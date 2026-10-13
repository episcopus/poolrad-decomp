#!/usr/bin/env python3
"""handoff.py: talk to the orchestrator (playbooks 30, 70, 90).

  make handoff AGENT=<you> UNIT=<id> STATE=<state> NOTE="..." [CHANGELOG="<section> | <change> | <evidence>"]
  make handoffs                                   (orchestrator: what is waiting, escalations first)
  make handoff-done UNIT=<key>                    (orchestrator, after acting on it; key as `make handoffs` shows)

STATE is one of:
  complete, partial, blocked        a decompiler's unit branch is ready to merge
  review-passed, review-failed      a reviewer's review branch is ready to merge
  escalate                          not a branch: a question or problem for the orchestrator to bring to
                                    the human (a suspected matcher problem, a spec question, a wrong claim
                                    elsewhere, a conflict nobody can settle from evidence); UNIT may be
                                    `general`; nothing needs to be committed first

A hand-off is a small file in the clone's git directory next to the locks (tools/agent/common.py), so
every worktree sees it and nothing is committed. CHANGELOG is the row this branch adds to
docs/design/CHANGELOG.md: decompilers do not edit that file (every branch would conflict on its first
row); `make handoff-done` adds the row, dated, when the orchestrator has merged the branch.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import control  # noqa: E402
import heartbeat  # noqa: E402
import identity  # noqa: E402

STATES = ("complete", "partial", "blocked", "review-passed", "review-failed", "escalate")
CHANGELOG = common.ROOT / "docs/design/CHANGELOG.md"


def unmatched(unit: str) -> str:
    """Run the matcher on a unit branch's unit; the problem lines when anything other than a stub differs
    (`make check` matches every routine that is not a {@stub}, so such a merge would fail on main)."""
    r = subprocess.run([sys.executable, str(common.ROOT / "tools/match/match.py"), unit],
                       cwd=common.ROOT, capture_output=True, text=True)
    if r.returncode == 0:
        return ""
    lines = [l for l in (r.stdout + r.stderr).splitlines() if not l.startswith("MATCH")]
    return "\n".join(lines[-12:]) or "match exited %d" % r.returncode


def handoff_dir() -> Path:
    d = common.common_dir() / "poolrad-handoffs"
    d.mkdir(exist_ok=True)
    return d


def fields(text: str) -> dict:
    return common.fields(text)


def add_changelog_row(row: str) -> str:
    """Insert `| <today> | <row> |` as the newest row of the changelog table; return the line."""
    parts = [p.strip() for p in row.split("|") if p.strip()]
    if len(parts) != 3:
        raise ValueError("CHANGELOG must be '<section> | <change> | <evidence>', got %r" % row)
    line = "| %s | %s |\n" % (dt.date.today().isoformat(), " | ".join(parts))
    text = CHANGELOG.read_text()
    head = "|---|---|---|---|\n"
    if head not in text:
        raise ValueError("%s: no table header" % CHANGELOG)
    if line not in text:
        common.atomic_write(CHANGELOG, text.replace(head, head + line, 1))
    return line.strip()


def main(argv=None) -> int:
    try:
        with control.coordination_lock():
            return run(argv)
    except (ValueError, RuntimeError, OSError) as e:
        print("handoff: %s" % e, file=sys.stderr)
        return 2


def archive(key: str, text: str) -> None:
    directory = common.common_dir() / "poolrad-handoff-archive"
    directory.mkdir(exist_ok=True)
    digest = hashlib.sha256(text.encode()).hexdigest()
    common.atomic_write(directory / ("%s-%s.md" % (key, digest)), text)


def finish(key: str, agent: str, decision: str, changelog: bool = True) -> int:
    """Clear a hand-off after its branch is in main. `changelog=False` when the row is already in the
    merge commit (make integrate writes it there; writing it again here, with a date that may have
    changed since, would dirty main)."""
    common.require_main("handoff-done")
    if not identity.is_orchestrator(agent):
        raise ValueError("handoff-done needs AGENT=orch, or an agent registered as orchestrator, in the main checkout")
    path = handoff_dir() / ("%s.md" % key)
    if not path.exists():
        print("handoff: no pending record for %s" % key)
        return 0
    text = path.read_text()
    f = fields(text)
    check_record = None
    if f.get("state") == "escalate":
        if not decision.strip():
            raise ValueError("clearing an escalation needs DECISION=<human instruction or reference>; agents cannot approve it")
        common.single_line(decision, "decision")
    else:
        commit = f.get("commit", "")
        if not re.fullmatch(r"[0-9a-f]{7,40}", commit):
            raise ValueError("hand-off has no valid pinned commit")
        common.git("merge-base", "--is-ancestor", commit, "HEAD")
        import check
        check_record = check.require_receipt()
    # Preserve the record before removing it. A malformed changelog must leave the hand-off pending.
    if changelog and f.get("changelog") and f.get("state") != "escalate":
        print("handoff: changelog row added: %s" % add_changelog_row(f["changelog"]))
    archive(key, text)
    if f.get("state") != "escalate":
        import performance
        performance.accepted(f, check_record)
    control.event("handoff-done", agent=agent, key=key, commit=f.get("commit"), decision=decision)
    grant = common.common_dir() / "poolrad-task-approvals" / (key + ".json")
    if grant.exists():
        directory = common.common_dir() / "poolrad-task-approval-archive"
        directory.mkdir(exist_ok=True)
        text = grant.read_text()
        common.atomic_write(directory / (key + "-" + hashlib.sha256(text.encode()).hexdigest() + ".json"), text)
        grant.unlink()
    path.unlink()
    print("handoff: archived and cleared %s" % key)
    return 0


def run(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--unit", default=os.environ.get("UNIT", ""))
    ap.add_argument("--agent", default=os.environ.get("AGENT", ""))
    ap.add_argument("--state", default=os.environ.get("STATE", ""))
    ap.add_argument("--note", default=os.environ.get("NOTE", ""))
    ap.add_argument("--changelog", default=os.environ.get("CHANGELOG", ""))
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--done", action="store_true", help="remove the hand-off UNIT (a key from --list)")
    ap.add_argument("--decision", default="", help="human instruction/reference before clearing an escalation")
    a = ap.parse_args(argv)
    if a.list:
        files = sorted(handoff_dir().glob("*.md"), key=lambda p: (not p.stem.startswith("escalate-"), p.stat().st_mtime))
        for p in files:
            tag = "ESCALATION for the human" if p.stem.startswith("escalate-") else "branch to merge"
            print("key = %s   (%s)\n%s\n" % (p.stem, tag, p.read_text().strip()))
        n_esc = sum(p.stem.startswith("escalate-") for p in files)
        print("handoffs: %d waiting, %d of them escalations (%s)" % (len(files), n_esc, handoff_dir()))
        return 0
    key = a.unit.lower()
    if not key:
        print("handoff: need UNIT=<id>", file=sys.stderr)
        return 2
    common.identifier(key, "unit or hand-off key")
    if a.done:                                       # the orchestrator names the hand-off by its key
        return finish(key, a.agent, a.decision)
    if a.state not in STATES or not a.agent:
        print("handoff: need AGENT=<you> and STATE=%s" % "|".join(STATES), file=sys.stderr)
        return 2
    common.identifier(a.agent, "agent")
    common.single_line(a.note, "note")
    common.single_line(a.changelog, "changelog")
    branch = common.git("rev-parse", "--abbrev-ref", "HEAD")
    if a.state == "escalate":
        if not a.note:
            print("handoff: an escalation needs NOTE=\"<the question or problem, with evidence>\"", file=sys.stderr)
            return 2
        key = "escalate-%s-%s" % (key, dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S%f"))
    else:
        if common.git("status", "--porcelain", "--", "src", "re", "docs", "work", "tools", "tests", "Makefile",
                      "AGENTS.md", "CLAUDE.md", "pyproject.toml", "uv.lock", ".claude", ".cursor", ".opencode"):
            print("handoff: commit your work first (git status is not clean)", file=sys.stderr)
            return 1
        if branch == "main" or not int(common.git("rev-list", "--count", "main..HEAD") or 0):
            print("handoff: %s has no commits beyond main, so there is nothing to merge; run it from your "
                  "worktree after committing (an escalation needs no commits)" % branch, file=sys.stderr)
            return 1
        prefix = "review" if a.state.startswith("review-") else ("task" if branch.startswith("task/") else "unit")
        expected = "%s/%s" % (prefix, a.unit)
        if branch != expected:
            raise ValueError("STATE and UNIT require branch %s, not %s" % (expected, branch))
        owner_key = "review-" + key if prefix == "review" else key
        common.require_owner(owner_key, a.agent, branch)
        import safety
        problems = safety.branch_findings(branch)
        if problems:
            raise ValueError("branch contains forbidden changes:\n" + "\n".join(problems))
        if branch.startswith("unit/"):
            problems = unmatched(branch.split("/", 1)[1])
            if problems:
                print("handoff: make match on %s still shows differences; a hand-off (also partial or blocked) "
                      "must match everywhere it is not a {@stub}: turn each unfinished routine back into a "
                      "{@stub} (keep the draft in its re/symbols.toml notes or an earlier commit), commit, and "
                      "hand off again:\n%s" % (branch, problems), file=sys.stderr)
                return 1
        if a.changelog:
            parts = [p for p in a.changelog.split("|") if p.strip()]
            if len(parts) != 3:
                print("handoff: CHANGELOG must be '<section> | <change> | <evidence>'", file=sys.stderr)
                return 2
        key = ("review-" + key) if branch.startswith("review/") else key
    head = common.git("rev-parse", "HEAD")
    path = handoff_dir() / ("%s.md" % key)
    if path.exists():
        old_text = path.read_text()
        old = fields(old_text)
        if old.get("agent") != a.agent or old.get("branch") != branch:
            raise ValueError("%s already has a pending hand-off from another agent; do not overwrite it" % key)
        common.git("merge-base", "--is-ancestor", old["commit"], head)
        archive(key, old_text)
    common.atomic_write(path,
        "unit = %s\nagent = %s\nbranch = %s\ncommit = %s\nstate = %s\ntime = %s\nnote = %s\nchangelog = %s\n" % (
            a.unit.lower(), a.agent, branch, head, a.state,
             dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), a.note, a.changelog) +
        identity.attribution_fields(a.agent, branch))
    control.event("handoff", agent=a.agent, key=key, branch=branch, commit=head, state=a.state)
    heartbeat.beat(a.agent, "handed off %s (%s)" % (key, a.state))
    if a.state == "escalate":
        print("handoff: escalation %s is waiting for the orchestrator (it goes to the human)" % key)
    else:
        print("handoff: %s (%s, %s) is waiting for the orchestrator" % (branch, a.state, head))
    return 0


if __name__ == "__main__":
    sys.exit(main())
