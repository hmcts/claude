#!/usr/bin/env python3
"""Validate the HMCTS claude config repo.

Covers the checks Claude Code's built-in `/plugin validate` does NOT do:
cross-repo consistency with the marketplace, pointer-stub integrity,
CLAUDE.md / README.md cross-references, and dangling skill references from
agents and skills.

Exits 1 if any check fails; all violations are reported in one run.

Usage:
    python scripts/validate_claude_config.py [--marketplace-path PATH]

The marketplace path defaults to `_marketplace/` (the layout used by CI).
Falls back to skipping the cross-repo check if the marketplace is absent.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

try:
    import yaml
except ImportError:
    print("error: PyYAML is required (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)

REPO = Path(__file__).resolve().parent.parent
SKILLS_DIR = REPO / ".claude" / "skills"
AGENTS_DIR = REPO / ".claude" / "agents"
CONTEXT_DIR = REPO / ".claude" / "context"
COMMANDS_DIR = REPO / ".claude" / "commands" / "opsx"
SETTINGS_JSON = REPO / ".claude" / "settings.json"
CLAUDE_MD = REPO / "CLAUDE.md"
README_MD = REPO / "README.md"
MARKETPLACE_SUFFIX = "@agentic-plugins-marketplace"

errors: list[str] = []
warnings: list[str] = []


def fail(msg: str) -> None:
    errors.append(msg)


def warn(msg: str) -> None:
    warnings.append(msg)


def parse_frontmatter(md_path: Path) -> tuple[dict[str, Any] | None, str]:
    """Return (frontmatter_dict_or_none, body_text)."""
    text = md_path.read_text()
    if not text.startswith("---\n"):
        return None, text
    end = text.find("\n---", 4)
    if end == -1:
        return None, text
    try:
        fm = yaml.safe_load(text[4:end]) or {}
    except yaml.YAMLError:
        return None, text[end + 4 :]
    return fm, text[end + 4 :]


def pointer_stub_plugin(md_path: Path) -> str | None:
    """Return the plugin name referenced by a pointer stub, or None."""
    text = md_path.read_text()
    match = re.search(
        r"/plugin install ([a-z0-9-]+)@agentic-plugins-marketplace", text
    )
    return match.group(1) if match else None


# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------


def check_settings_json() -> dict[str, Any]:
    """Return parsed settings; fail and return empty dict on error."""
    if not SETTINGS_JSON.exists():
        fail(".claude/settings.json is missing")
        return {}
    try:
        return json.loads(SETTINGS_JSON.read_text())
    except json.JSONDecodeError as e:
        fail(f".claude/settings.json is not valid JSON: {e}")
        return {}


def check_enabled_plugins_against_marketplace(
    settings: dict[str, Any], marketplace_path: Path | None
) -> None:
    """Check that every enabled marketplace plugin exists in the fetched marketplace."""
    enabled = settings.get("enabledPlugins", {})
    marketplace_keys = [k for k in enabled if k.endswith(MARKETPLACE_SUFFIX)]
    if not marketplace_keys:
        return

    if marketplace_path is None:
        warn(
            "marketplace repo not fetched — skipping cross-repo enabledPlugins check. "
            "Pass --marketplace-path to enable."
        )
        return

    mp_json = marketplace_path / ".claude-plugin" / "marketplace.json"
    if not mp_json.exists():
        fail(f"marketplace repo at {marketplace_path} has no .claude-plugin/marketplace.json")
        return

    try:
        mp = json.loads(mp_json.read_text())
    except json.JSONDecodeError as e:
        fail(f"marketplace.json in {marketplace_path} is not valid JSON: {e}")
        return

    known = {entry["name"] for entry in mp.get("plugins", [])}
    for key in marketplace_keys:
        plugin_name = key[: -len(MARKETPLACE_SUFFIX)]
        if plugin_name not in known:
            fail(
                f".claude/settings.json enables '{key}' but no plugin of that name "
                f"is published in the marketplace"
            )


def check_pointer_stub_integrity(settings: dict[str, Any]) -> None:
    """Every pointer stub references a plugin that's enabled in settings.json."""
    enabled = settings.get("enabledPlugins", {})
    enabled_names = {
        k[: -len(MARKETPLACE_SUFFIX)]
        for k in enabled
        if k.endswith(MARKETPLACE_SUFFIX)
    }

    # Candidate pointer stubs: top-level .md files AND SKILL.md files that
    # contain a `/plugin install <name>@agentic-plugins-marketplace` line.
    candidates: list[Path] = []
    if SKILLS_DIR.exists():
        candidates.extend(SKILLS_DIR.glob("*.md"))
        candidates.extend(SKILLS_DIR.glob("*/SKILL.md"))

    for stub in candidates:
        plugin = pointer_stub_plugin(stub)
        if plugin is None:
            continue  # not a pointer stub
        if plugin not in enabled_names:
            rel = stub.relative_to(REPO)
            fail(
                f"{rel}: pointer stub references '{plugin}@agentic-plugins-marketplace' "
                f"but it's not enabled in .claude/settings.json"
            )


def check_skill_frontmatter() -> None:
    """Every .claude/skills/*/SKILL.md must have YAML frontmatter with name + description."""
    if not SKILLS_DIR.exists():
        return
    for skill_md in SKILLS_DIR.glob("*/SKILL.md"):
        fm, _ = parse_frontmatter(skill_md)
        rel = skill_md.relative_to(REPO)
        if fm is None:
            fail(f"{rel}: missing or unparseable YAML frontmatter")
            continue
        if not fm.get("name"):
            fail(f"{rel}: frontmatter missing `name` field")
        if not fm.get("description"):
            fail(f"{rel}: frontmatter missing `description` field")


def check_command_frontmatter() -> None:
    """Every .claude/commands/opsx/*.md must have YAML frontmatter with name + description."""
    if not COMMANDS_DIR.exists():
        return
    for cmd_md in COMMANDS_DIR.glob("*.md"):
        fm, _ = parse_frontmatter(cmd_md)
        rel = cmd_md.relative_to(REPO)
        if fm is None:
            fail(f"{rel}: missing or unparseable YAML frontmatter")
            continue
        if not fm.get("name"):
            fail(f"{rel}: frontmatter missing `name` field")
        if not fm.get("description"):
            fail(f"{rel}: frontmatter missing `description` field")


# Match `agents/<name>.md` and `context/<name>.md` references inside CLAUDE.md
# tables/prose. Requires the preceding char to be non-alphabetic so we don't
# pick up parts of longer paths.
_AGENT_REF = re.compile(r"(?<![A-Za-z0-9/_-])agents/([a-z0-9_-]+)\.md\b")
_CONTEXT_REF = re.compile(r"(?<![A-Za-z0-9/_-])context/([a-z0-9_-]+)\.md\b")


def check_claude_md_references() -> None:
    """Every agent/context file referenced in CLAUDE.md must exist on disk."""
    if not CLAUDE_MD.exists():
        fail("CLAUDE.md is missing")
        return
    text = CLAUDE_MD.read_text()
    for m in _AGENT_REF.finditer(text):
        agent = m.group(1)
        if not (AGENTS_DIR / f"{agent}.md").exists():
            fail(f"CLAUDE.md references agents/{agent}.md but it does not exist")
    for m in _CONTEXT_REF.finditer(text):
        ctx = m.group(1)
        if not (CONTEXT_DIR / f"{ctx}.md").exists():
            fail(f"CLAUDE.md references context/{ctx}.md but it does not exist")


def check_readme_references() -> None:
    """Every agent/skill/context file referenced in README.md tables must exist."""
    if not README_MD.exists():
        return
    text = README_MD.read_text()
    for m in _AGENT_REF.finditer(text):
        agent = m.group(1)
        if not (AGENTS_DIR / f"{agent}.md").exists():
            fail(f"README.md references agents/{agent}.md but it does not exist")
    for m in _CONTEXT_REF.finditer(text):
        ctx = m.group(1)
        if not (CONTEXT_DIR / f"{ctx}.md").exists():
            fail(f"README.md references context/{ctx}.md but it does not exist")


# `skill: skills/<path>` references inside agents or skills. The path is
# relative to `.claude/` and may point at a file (`.md`) or a directory (`/`).
_SKILL_PATH_REF = re.compile(
    r"skill:\s*`?(skills/[A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*(?:\.md)?/?)`?",
    re.MULTILINE,
)


def check_skill_path_references() -> None:
    """Every `skill: skills/...` reference in agents/skills must resolve on disk."""
    search_dirs = [AGENTS_DIR, SKILLS_DIR]
    for base in search_dirs:
        if not base.exists():
            continue
        for md in base.rglob("*.md"):
            text = md.read_text()
            for m in _SKILL_PATH_REF.finditer(text):
                rel_path = m.group(1).rstrip("/")
                target = REPO / ".claude" / rel_path
                if target.exists() or (REPO / ".claude" / f"{rel_path}").is_dir():
                    continue
                # Try with SKILL.md appended (for directory refs)
                if (target / "SKILL.md").exists():
                    continue
                rel_md = md.relative_to(REPO)
                fail(f"{rel_md}: references skill path '{rel_path}' which does not resolve")


# Dangling skill-name references in SKILL.md / agent bodies (prefix-gated).
_TASK_REFERENCE = re.compile(r"\bTask:\s*[`\"]?([a-z][a-z0-9-]*-[a-z0-9-]+)\b")
_BACKTICK_SKILL = re.compile(
    r"`([a-z][a-z0-9-]*-[a-z0-9-]+)`\s+skill\b", re.IGNORECASE
)


def check_dangling_skill_names() -> None:
    """SKILL.md bodies referencing other skills (kebab-case names) must refer to real ones."""
    # Collect known skill names from pointer stubs + local SKILL.md frontmatter.
    known: set[str] = set()
    if SKILLS_DIR.exists():
        for md in SKILLS_DIR.glob("*.md"):
            stem = md.stem
            if "-" in stem:
                known.add(stem)
        for skill_md in SKILLS_DIR.glob("*/SKILL.md"):
            fm, _ = parse_frontmatter(skill_md)
            if fm and "name" in fm:
                known.add(fm["name"])
            # Directory name is also a valid skill identifier
            known.add(skill_md.parent.name)

    prefixes = {n.split("-", 1)[0] for n in known if "-" in n}

    search_roots = [SKILLS_DIR, AGENTS_DIR]
    for root in search_roots:
        if not root.exists():
            continue
        for md in root.rglob("*.md"):
            _, body = parse_frontmatter(md)
            for pattern in (_TASK_REFERENCE, _BACKTICK_SKILL):
                for m in pattern.finditer(body):
                    name = m.group(1)
                    if name in known:
                        continue
                    prefix = name.split("-", 1)[0]
                    if prefix in prefixes:
                        rel = md.relative_to(REPO)
                        fail(
                            f"{rel}: references unknown skill '{name}' "
                            f"(matched pattern: {pattern.pattern!r})"
                        )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--marketplace-path",
        default=str(REPO / "_marketplace"),
        help="Path to a checked-out copy of the agentic-plugins-marketplace repo. "
        "If absent, the cross-repo enabledPlugins check is skipped with a warning.",
    )
    args = parser.parse_args()

    marketplace_path: Path | None = Path(args.marketplace_path)
    if not marketplace_path.exists():
        marketplace_path = None

    settings = check_settings_json()

    checks = [
        (
            "enabledPlugins vs. marketplace",
            lambda: check_enabled_plugins_against_marketplace(settings, marketplace_path),
        ),
        ("pointer stub integrity", lambda: check_pointer_stub_integrity(settings)),
        ("skill frontmatter", check_skill_frontmatter),
        ("opsx command frontmatter", check_command_frontmatter),
        ("CLAUDE.md file references", check_claude_md_references),
        ("README.md file references", check_readme_references),
        ("`skill: skills/...` path references", check_skill_path_references),
        ("dangling skill names", check_dangling_skill_names),
    ]

    for name, fn in checks:
        try:
            fn()
        except Exception as e:
            fail(f"check '{name}' crashed: {e}")

    if warnings:
        for w in warnings:
            print(f"warning: {w}", file=sys.stderr)

    if errors:
        print("", file=sys.stderr)
        print(f"{len(errors)} validation error(s):", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    print(f"all {len(checks)} checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
