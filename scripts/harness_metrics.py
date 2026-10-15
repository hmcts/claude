#!/usr/bin/env python3
"""Turn harness telemetry and git history into the starting-set metrics.

Reads two sources:

  1. The local JSONL event log written by `.claude/hooks/harness-telemetry.sh`
     and the git hooks in `.claude/hooks/git/` (default
     `~/.cpp-harness/events/*.jsonl`), or a directory of logs collected from
     several machines. As well as usage events, this log holds the
     **attribution index**: `commit_recorded` / `commit_rewritten` /
     `branch_pushed` records keyed by commit SHA.
  2. `git log` across the CPP workspace, for the SHAs to join against.

Attribution deliberately lives in the local index and NOT in commit messages —
most CPP repositories are public, and an AI-assistance marker in permanent
public history is not something that can be taken back. See
`docs/telemetry/attribution-index.md`.

The trade-off that buys: the index only knows about commits made on machines
whose logs you are reading. A freshly cloned repo shows 0% assisted, correctly
and unhelpfully. Collect logs before drawing conclusions from the percentage.

Reports the metrics from the measurement framework that are derivable from
those two sources, and states plainly which are not — rather than substituting
a weaker proxy and letting it be read as the real thing.

Stdlib only. Read-only: runs `git log` and nothing else.

Usage:
    python scripts/harness_metrics.py --repos ~/cpp --since 90
    python scripts/harness_metrics.py --format markdown > monthly-review.md
    python scripts/harness_metrics.py --format json | jq .
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Iterable

# Metrics that genuinely cannot be computed from a local event log plus git.
# Listed in the report so a reader can see the whole starting set and where the
# gaps are, instead of assuming the printed numbers are all there is.
NOT_LOCAL = [
    ("Change failure rate", "Azure DevOps Releases API + incident/rollback source of truth"),
    ("Defect escape rate", "Jira — bugs linked to a story, post-merge, split by PR tag"),
    ("PR review turnaround", "Azure DevOps Pull Requests API (creation → first vote → completion)"),
    ("Cycle time (median/p90)", "Azure DevOps — first commit to PR completion; git alone has no merge time"),
    ("CI first-pass rate", "Azure DevOps Builds API — result of the first run per PR"),
    ("SonarQube critical issues on new code", "SonarQube measures API, new_code period"),
    ("Quarterly DX survey", "Not instrumentable. Ask people."),
]

STAGE_ORDER = [
    "requirements", "architecture", "user-story", "test-specs",
    "code", "code-review", "build-test", "deploy-sandbox",
]


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------

def parse_ts(value: str) -> datetime | None:
    try:
        return datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    except (ValueError, TypeError):
        return None


def load_events(events_dir: Path) -> tuple[list[dict[str, Any]], int]:
    """Return (all events, count of unparseable lines).

    Deliberately unwindowed. Usage metrics are filtered to the window later,
    but the attribution index must be read whole: a rebase last month can
    rewrite a SHA that a commit inside the window still depends on, and
    truncating the log would silently break that chain.
    """
    events: list[dict[str, Any]] = []
    malformed = 0
    for path in sorted(events_dir.glob("**/*.jsonl")):
        with path.open(encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    malformed += 1
                    continue
                ts = parse_ts(row.get("ts", ""))
                if ts is None:
                    malformed += 1
                    continue
                row["_ts"] = ts
                events.append(row)
    events.sort(key=lambda r: r["_ts"])
    return events, malformed


@dataclass
class Commit:
    repo: str
    sha: str
    when: datetime
    assisted: str | None = None
    stages: list[str] = field(default_factory=list)


def git(repo: Path, *args: str) -> str:
    try:
        out = subprocess.run(
            ["git", "-C", str(repo), *args],
            capture_output=True, text=True, timeout=60, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.stdout if out.returncode == 0 else ""


def find_repos(root: Path, max_depth: int = 2) -> list[Path]:
    """Git repositories at or below root, without descending into them."""
    found: list[Path] = []

    def walk(d: Path, depth: int) -> None:
        if depth > max_depth:
            return
        if (d / ".git").exists():
            found.append(d)
            return  # never recurse into a repo
        try:
            children = sorted(p for p in d.iterdir() if p.is_dir() and not p.name.startswith("."))
        except (PermissionError, OSError):
            return
        for child in children:
            walk(child, depth + 1)

    walk(root, 0)
    return found


SEP = "\x1f"  # unit separator — safe inside commit metadata


def load_commits(repos: Iterable[Path], since_days: int) -> list[Commit]:
    fmt = SEP.join(["%H", "%cI"])
    commits: list[Commit] = []
    for repo in repos:
        raw = git(repo, "log", f"--since={since_days} days ago", "--no-merges", f"--format={fmt}")
        for line in raw.splitlines():
            parts = line.split(SEP)
            if len(parts) != 2:
                continue
            sha, when_s = (p.strip() for p in parts)
            try:
                when = datetime.fromisoformat(when_s).astimezone(timezone.utc)
            except ValueError:
                continue
            commits.append(Commit(repo.name, sha, when))
    return commits


# ---------------------------------------------------------------------------
# The attribution index
# ---------------------------------------------------------------------------

@dataclass
class Index:
    by_sha: dict[str, dict[str, Any]]      # every SHA known to be assisted
    superseded: set[str]                   # SHAs an amend/rebase has replaced
    recorded: int                          # live commits, after rewrites
    rewrites: int                          # old→new pairs seen
    pushes: list[dict[str, Any]]           # branch_pushed records


def build_index(events: list[dict[str, Any]]) -> Index:
    """Resolve commit_recorded + commit_rewritten into a SHA → attribution map.

    A commit that is amended or rebased gets a new SHA. `post-rewrite` gives us
    old→new pairs, so the attribution follows the commit forward. Both the
    original and the final SHA are kept: on a shared machine the pre-rebase
    commit may still be reachable, and matching it is not wrong.
    """
    recorded: dict[str, dict[str, Any]] = {}
    rewrites: dict[str, str] = {}
    pushes: list[dict[str, Any]] = []

    for e in events:
        kind = e.get("event")
        if kind == "commit_recorded" and e.get("sha"):
            recorded[e["sha"]] = {
                "harness": e.get("harness") or "unknown",
                "stages": [s for s in (e.get("stages") or []) if s],
                "session": e.get("session"),
                "install": e.get("install"),
                "repo": e.get("repo"),
                "ts": e["_ts"],
            }
        elif kind == "commit_rewritten" and e.get("old_sha") and e.get("new_sha"):
            rewrites[e["old_sha"]] = e["new_sha"]
        elif kind == "branch_pushed" and e.get("tip_sha"):
            pushes.append({
                "repo": e.get("repo"), "remote_ref": e.get("remote_ref"),
                "tip_sha": e["tip_sha"], "ts": e["_ts"],
            })

    by_sha: dict[str, dict[str, Any]] = {}
    for sha, rec in recorded.items():
        by_sha[sha] = rec
        cur, seen = sha, {sha}
        # Follow the rewrite chain forward. `seen` guards against a cycle,
        # which should be impossible but would otherwise hang the report.
        while cur in rewrites and rewrites[cur] not in seen:
            cur = rewrites[cur]
            seen.add(cur)
            by_sha[cur] = rec

    # A SHA that has been amended or rebased away is not a missing commit — it
    # is a superseded one. Counting it as missing would make the index look
    # broken after every routine rebase.
    superseded = {old for old in rewrites if old in by_sha}
    live = {s for s in by_sha if s not in superseded}

    return Index(by_sha=by_sha, superseded=superseded, recorded=len(live),
                 rewrites=len(rewrites), pushes=pushes)


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------

def iso_week(dt: datetime) -> str:
    y, w, _ = dt.isocalendar()
    return f"{y}-W{w:02d}"


def pct(numerator: int, denominator: int) -> float | None:
    return round(100.0 * numerator / denominator, 1) if denominator else None


def compute(events: list[dict], commits: list[Commit], index: Index,
            cutoff: datetime, args) -> dict[str, Any]:
    windowed = [e for e in events if e["_ts"] >= cutoff]
    starts = [e for e in windowed if e.get("event") == "session_start"]

    # --- 1/2. adoption ------------------------------------------------------
    by_week_installs: dict[str, set[str]] = defaultdict(set)
    by_week_sessions: dict[str, set[str]] = defaultdict(set)
    for e in starts:
        week = iso_week(e["_ts"])
        if e.get("install"):
            by_week_installs[week].add(e["install"])
        if e.get("session"):
            by_week_sessions[week].add(e["session"])

    weekly = []
    for week in sorted(by_week_sessions):
        installs = len(by_week_installs.get(week, ()))
        sessions = len(by_week_sessions[week])
        weekly.append({
            "week": week,
            "active_installations": installs or None,
            "sessions": sessions,
            "sessions_per_installation": round(sessions / installs, 1) if installs else None,
            "pct_of_eligible": pct(installs, args.eligible) if (installs and args.eligible) else None,
        })

    all_installs = {e["install"] for e in starts if e.get("install")}

    # --- 3. skills and agents ----------------------------------------------
    skills = Counter(e["skill"] for e in windowed
                     if e.get("event") == "skill_used" and e.get("skill"))
    agents = Counter(e["agent"].split(":")[-1] for e in windowed
                     if e.get("event") == "agent_used" and e.get("agent"))

    # --- 4. repo coverage ---------------------------------------------------
    repos_seen = {e["repo"] for e in windowed if e.get("repo")}

    # --- 5. abandonment -----------------------------------------------------
    # A session that entered the pipeline (reached a pre-code stage) but never
    # produced code. Sessions that only ever used an ad-hoc skill are excluded:
    # they never intended to run the pipeline, so counting them as abandoned
    # would overstate the rate badly.
    stages_by_session: dict[str, set[str]] = defaultdict(set)
    for e in windowed:
        if e.get("event") == "agent_used" and e.get("stage") and e.get("session"):
            stages_by_session[e["session"]].add(e["stage"])
    pre_code = {"requirements", "architecture", "user-story", "test-specs"}
    entered = {s for s, st in stages_by_session.items() if st & pre_code}
    reached_code = {s for s in entered if "code" in stages_by_session[s]}
    abandoned = len(entered) - len(reached_code)

    # --- 6. gate decisions --------------------------------------------------
    gates: dict[str, Counter] = defaultdict(Counter)
    gate_reasons: Counter = Counter()
    for e in windowed:
        if e.get("event") == "gate_decision" and e.get("stage"):
            gates[e["stage"]][e.get("decision", "?")] += 1
            if e.get("reason"):
                gate_reasons[e["reason"]] += 1

    gate_rows = []
    for stage in STAGE_ORDER:
        c = gates.get(stage)
        if not c:
            continue
        total = sum(c.values())
        gate_rows.append({
            "stage": stage,
            "total": total,
            "accept": c["accept"], "edit": c["edit"], "reject": c["reject"],
            "accept_rate": pct(c["accept"], total),
            "reject_rate": pct(c["reject"], total),
        })

    # --- 7. artefacts -------------------------------------------------------
    artefacts = Counter(e["artefact"] for e in windowed
                        if e.get("event") == "artefact_written" and e.get("artefact"))

    # --- 8/9. attribution, by SHA join --------------------------------------
    for c in commits:
        rec = index.by_sha.get(c.sha)
        if rec:
            c.assisted = rec["harness"]
            c.stages = rec["stages"]

    assisted = [c for c in commits if c.assisted]
    by_repo: dict[str, dict[str, int]] = defaultdict(lambda: {"assisted": 0, "total": 0})
    for c in commits:
        by_repo[c.repo]["total"] += 1
        if c.assisted:
            by_repo[c.repo]["assisted"] += 1
    repo_rows = sorted(
        ({"repo": r, **v, "pct": pct(v["assisted"], v["total"])} for r, v in by_repo.items()),
        key=lambda r: (-r["assisted"], r["repo"]),
    )
    stage_mix = Counter(s for c in assisted for s in c.stages)
    versions = Counter(c.assisted for c in assisted if c.assisted)

    # Index health. Recorded commits the git scan could not find are the honest
    # cost of not putting the marker in the commit itself: they were rewritten
    # away, never pushed, live in a repo outside --repos, or were made on a
    # machine whose log is not in this report.
    scanned = {c.sha for c in commits}
    live_in_window = [s for s, r in index.by_sha.items()
                      if r["ts"] >= cutoff and s not in index.superseded]
    missing = [s for s in live_in_window if s not in scanned]
    unmatched = sorted({index.by_sha[s]["repo"] or "?" for s in missing})

    return {
        "window_days": args.since,
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "adoption": {
            "weekly": weekly,
            "distinct_installations": len(all_installs) or None,
            "eligible_developers": args.eligible,
            "total_sessions": len(starts),
        },
        "skills": skills.most_common(),
        "agents": agents.most_common(),
        "coverage": {
            "repos_seen": len(repos_seen),
            "repos_total": args.total_repos,
            "pct": pct(len(repos_seen), args.total_repos),
            "names": sorted(repos_seen),
        },
        "pipeline": {
            "sessions_entered": len(entered),
            "reached_code": len(reached_code),
            "abandoned": abandoned,
            "abandonment_rate": pct(abandoned, len(entered)),
            "artefacts": artefacts.most_common(),
        },
        "gates": {"by_stage": gate_rows, "reasons": gate_reasons.most_common()},
        "commits": {
            "scanned_repos": len({c.repo for c in commits}),
            "total": len(commits),
            "assisted": len(assisted),
            "assisted_pct": pct(len(assisted), len(commits)),
            "by_repo": repo_rows,
            "stage_mix": stage_mix.most_common(),
            "harness_versions": versions.most_common(),
        },
        "index": {
            "commits_recorded": index.recorded,
            "rewrites_followed": index.rewrites,
            "pushes_recorded": len(index.pushes),
            "matched_in_git": len([c for c in commits if c.assisted]),
            "unmatched": len(missing),
            "unmatched_repos": unmatched,
            "pushed_refs": sorted({p["remote_ref"] for p in index.pushes
                                   if p.get("remote_ref") and p["ts"] >= cutoff}),
        },
        "not_derivable_locally": [{"metric": m, "source": s} for m, s in NOT_LOCAL],
    }


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

def bar(n: int, peak: int, width: int = 24) -> str:
    return "█" * max(1, round(width * n / peak)) if peak and n else ""


def table(headers: list[str], rows: list[list[Any]], md: bool,
          align_right: set[int] | None = None) -> list[str]:
    """Render a table as a real markdown table, or as aligned fixed-width text.

    Fixed-width columns collapse to a single paragraph when markdown is rendered,
    so the two formats need genuinely different output — not the same string.
    """
    right = align_right or set()
    cells = [[("" if c is None else str(c)) for c in row] for row in rows]
    if md:
        sep = ["---:" if i in right else "---" for i in range(len(headers))]
        return ["| " + " | ".join(headers) + " |",
                "|" + "|".join(sep) + "|",
                *["| " + " | ".join(r) + " |" for r in cells]]
    widths = [max(len(h), *(len(r[i]) for r in cells)) if cells else len(h)
              for i, h in enumerate(headers)]
    def line(vals: list[str]) -> str:
        return "  ".join(v.rjust(widths[i]) if i in right else v.ljust(widths[i])
                         for i, v in enumerate(vals)).rstrip()
    return [line(headers), line(["-" * w for w in widths]), *[line(r) for r in cells]]


def render(d: dict[str, Any], md: bool) -> str:
    h1 = (lambda s: f"# {s}\n") if md else (lambda s: f"\n{s}\n{'=' * len(s)}")
    h2 = (lambda s: f"\n## {s}\n") if md else (lambda s: f"\n{s}\n{'-' * len(s)}")
    out: list[str] = [h1(f"Harness metrics — last {d['window_days']} days")]
    out.append(f"\nGenerated {d['generated']}\n")

    a = d["adoption"]
    out.append(h2("1–2. Adoption"))
    if not a["weekly"]:
        out.append("No sessions recorded in the window.")
    else:
        out.append(f"{a['total_sessions']} sessions"
                   + (f", {a['distinct_installations']} distinct installations"
                      if a["distinct_installations"] else ""))
        if a["eligible_developers"]:
            out.append(f"Eligible developers: {a['eligible_developers']}")
        else:
            out.append("Eligible developers not supplied (--eligible) — "
                       "the adoption denominator is the number that matters most.")
        out.append("")
        out += table(
            ["week", "installs", "sessions", "per install", "% eligible"],
            [[w["week"], w["active_installations"] or "-", w["sessions"],
              w["sessions_per_installation"] or "-",
              "-" if w["pct_of_eligible"] is None else "{}%".format(w["pct_of_eligible"])]
             for w in a["weekly"]],
            md, align_right={1, 2, 3, 4})

    out.append(h2("3. Skill and agent usage"))
    if not d["skills"] and not d["agents"]:
        out.append("Nothing recorded.")
    for title, rows in (("Skills", d["skills"]), ("Agents", d["agents"])):
        if not rows:
            continue
        peak = rows[0][1]
        out.append(f"\n**{title}**\n" if md else f"\n{title}:")
        out += table([title.rstrip("s"), "uses", ""],
                     [[name, n, bar(n, peak)] for name, n in rows],
                     md, align_right={1})
    if d["skills"]:
        cold = [n for n, _ in d["skills"][-3:]] if len(d["skills"]) > 5 else []
        if cold:
            out.append(f"\nColdest: {', '.join(cold)} — candidates for deletion.")

    c = d["coverage"]
    out.append(h2("4. Repo coverage"))
    out.append(f"{c['repos_seen']} of {c['repos_total']} repositories touched"
               + (f" ({c['pct']}%)" if c["pct"] is not None else ""))

    p = d["pipeline"]
    out.append(h2("5. Pipeline completion"))
    if p["sessions_entered"]:
        out.append(f"{p['sessions_entered']} sessions entered the pipeline; "
                   f"{p['reached_code']} reached the code stage.")
        out.append(f"Abandonment rate: {p['abandonment_rate']}%")
    else:
        out.append("No sessions entered the pipeline.")
    if p["artefacts"]:
        out.append("Artefacts written: "
                   + ", ".join(f"{k} ({n})" for k, n in p["artefacts"]))

    g = d["gates"]
    out.append(h2("9. Gate decisions"))
    if not g["by_stage"]:
        out.append("No gate decisions recorded. Without /gate there is no direct\n"
                   "quality signal for any pipeline agent — this is the gap worth closing first.")
    else:
        out += table(["stage", "n", "accept", "edit", "reject", "reject %"],
                     [[r["stage"], r["total"], r["accept"], r["edit"], r["reject"],
                       f"{r['reject_rate']}%"] for r in g["by_stage"]],
                     md, align_right={1, 2, 3, 4, 5})
        if g["reasons"]:
            out.append("\nReasons: " + ", ".join(f"{k} ({n})" for k, n in g["reasons"]))
        low = [r for r in g["by_stage"] if r["total"] >= 5 and r["reject_rate"] == 0.0]
        if low:
            out.append("\nZero rejections at: " + ", ".join(r["stage"] for r in low)
                       + ".\nRead this twice — it can mean the agent is good, or that\n"
                         "reviewers have stopped reading. The second is worse and looks identical here.")

    k = d["commits"]
    ix = d["index"]
    out.append(h2("Attribution (local commit index)"))
    if not k["total"]:
        out.append("No commits found. Check --repos, or whether the window is too narrow.")
    else:
        out.append(f"{k['assisted']} of {k['total']} commits assisted "
                   f"({k['assisted_pct']}%) across {k['scanned_repos']} repositories")
        if ix["commits_recorded"] == 0:
            out.append("\nThe attribution index is empty. Either the harness has not been used\n"
                       "in these repos, or the git hooks are not installed — those two are\n"
                       "indistinguishable from here. Verify with:\n"
                       "  git config --get core.hooksPath")
        elif k["assisted"] == 0:
            out.append("\nCommits were recorded, but none of them appear in the scanned history.\n"
                       "Widen --repos, or check that the branches were not rebased on a machine\n"
                       "whose log is missing from this report.")
        else:
            out.append("")
            out += table(["repo", "assisted", "total", "%"],
                         [[r["repo"], r["assisted"], r["total"], f"{r['pct']}%"]
                          for r in k["by_repo"][:12] if r["assisted"]],
                         md, align_right={1, 2, 3})
            if k["stage_mix"]:
                out.append("\n**Stage mix across assisted commits**\n" if md
                           else "\nStage mix across assisted commits:")
                peak = max(n for _, n in k["stage_mix"])
                ordered = sorted(k["stage_mix"],
                                 key=lambda x: STAGE_ORDER.index(x[0])
                                 if x[0] in STAGE_ORDER else 99)
                out += table(["stage", "commits", ""],
                             [[name, n, bar(n, peak)] for name, n in ordered],
                             md, align_right={1})
            if len(k["harness_versions"]) > 1:
                out.append("\nHarness versions in play: "
                           + ", ".join(f"{v} ({n})" for v, n in k["harness_versions"]))

    out.append(h2("Index health"))
    out.append("Attribution is held locally, keyed by SHA, so that nothing about AI\n"
               "assistance is written into public git history. The cost is that this\n"
               "percentage is only as complete as the logs you are reading.\n")
    out += table(["measure", "n"],
                 [["commits recorded (after rewrites)", ix["commits_recorded"]],
                  ["rewrites followed (amend/rebase)", ix["rewrites_followed"]],
                  ["matched in scanned history", ix["matched_in_git"]],
                  ["recorded but not found", ix["unmatched"]],
                  ["branch pushes recorded", ix["pushes_recorded"]]],
                 md, align_right={1})
    if ix["unmatched"]:
        out.append(f"\n{ix['unmatched']} recorded commit(s) were not found in the scanned\n"
                   "history. Expected causes, in rough order of likelihood: squashed at merge,\n"
                   "rebased on another machine, never pushed, or in a repo outside --repos.\n"
                   + (f"Affected repos: {', '.join(ix['unmatched_repos'][:8])}\n"
                      if ix["unmatched_repos"] else "")
                   + "A persistently high number here means the percentage above is an\n"
                     "undercount, not that the harness is unused.")
    if ix["pushed_refs"]:
        out.append(f"\n{len(ix['pushed_refs'])} branch(es) carried assisted commits to a remote.\n"
                   "These are the join keys for PR-level metrics in Azure DevOps — match on\n"
                   "the PR's source branch, which keeps the assisted/unassisted split inside\n"
                   "ADO where it is not publicly visible.")

    out.append(h2("Not derivable from local data"))
    out.append("These need the systems of record. They are the metrics that make the\n"
               "numbers above credible, so do not report the above without them.\n")
    out += table(["metric", "source"],
                 [[r["metric"], r["source"]] for r in d["not_derivable_locally"]], md)

    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(
        description="Report harness metrics from telemetry events and the local "
                    "commit attribution index.")
    ap.add_argument("--events", type=Path,
                    default=Path.home() / ".cpp-harness" / "events",
                    help="Directory of *.jsonl event logs (default: ~/.cpp-harness/events)")
    ap.add_argument("--repos", type=Path, default=None,
                    help="Workspace root to scan for git repos (default: parent of this repo)")
    ap.add_argument("--since", type=int, default=90, help="Window in days (default: 90)")
    ap.add_argument("--eligible", type=int, default=None,
                    help="Eligible developer count — the adoption denominator")
    ap.add_argument("--total-repos", type=int, default=145,
                    help="Repository count for coverage (default: 145)")
    ap.add_argument("--format", choices=["text", "markdown", "json"], default="text")
    ap.add_argument("--no-git", action="store_true", help="Skip the git scan")
    args = ap.parse_args()

    cutoff = datetime.now(timezone.utc) - timedelta(days=args.since)

    events: list[dict] = []
    malformed = 0
    if args.events.is_dir():
        events, malformed = load_events(args.events)
    elif args.format != "json":
        print(f"note: no event log at {args.events} — adoption, skill, gate and "
              f"attribution metrics will be empty.", file=sys.stderr)

    index = build_index(events)

    commits: list[Commit] = []
    if not args.no_git:
        root = args.repos or Path(__file__).resolve().parent.parent.parent
        repos = find_repos(root)
        if not repos and args.format != "json":
            print(f"note: no git repositories found under {root}", file=sys.stderr)
        commits = load_commits(repos, args.since)

    if malformed and args.format != "json":
        print(f"note: skipped {malformed} unparseable event line(s)", file=sys.stderr)

    data = compute(events, commits, index, cutoff, args)
    if args.format == "json":
        json.dump(data, sys.stdout, indent=2)
        sys.stdout.write("\n")
    else:
        sys.stdout.write(render(data, md=args.format == "markdown"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
