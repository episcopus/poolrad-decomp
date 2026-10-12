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
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import heartbeat  # noqa: E402

STATES = ("complete", "partial", "blocked", "review-passed", "review-failed", "escalate")
CHANGELOG = common.ROOT / "docs/design/CHANGELOG.md"


def handoff_dir() -> Path:
    d = common.common_dir() / "poolrad-handoffs"
    d.mkdir(exist_ok=True)
    return d


def fields(text: str) -> dict:
    return dict(re.findall(r"^(\w+) = (.*)$", text, re.M))


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
    CHANGELOG.write_text(text.replace(head, head + line, 1))
    return line.strip()


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--unit", default=os.environ.get("UNIT", ""))
    ap.add_argument("--agent", default=os.environ.get("AGENT", ""))
    ap.add_argument("--state", default=os.environ.get("STATE", ""))
    ap.add_argument("--note", default=os.environ.get("NOTE", ""))
    ap.add_argument("--changelog", default=os.environ.get("CHANGELOG", ""))
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--done", action="store_true", help="remove the hand-off UNIT (a key from --list)")
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
    if a.done:                                       # the orchestrator names the hand-off by its key
        path = handoff_dir() / ("%s.md" % key)
        if path.exists():
            f = fields(path.read_text())
            if f.get("changelog") and f.get("state") != "escalate":
                try:
                    print("handoff: changelog row added: %s" % add_changelog_row(f["changelog"]))
                except ValueError as e:
                    print("handoff: %s (add the row by hand)" % e, file=sys.stderr)
            path.unlink()
        print("handoff: cleared %s" % key)
        return 0
    if a.state not in STATES or not a.agent:
        print("handoff: need AGENT=<you> and STATE=%s" % "|".join(STATES), file=sys.stderr)
        return 2
    branch = common.git("rev-parse", "--abbrev-ref", "HEAD")
    if a.state == "escalate":
        if not a.note:
            print("handoff: an escalation needs NOTE=\"<the question or problem, with evidence>\"", file=sys.stderr)
            return 2
        key = "escalate-%s-%s" % (key, dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d%H%M%S"))
    else:
        if common.git("status", "--porcelain", "--", "src", "re", "docs", "work", "tools", "tests"):
            print("handoff: commit your work first (git status is not clean)", file=sys.stderr)
            return 1
        if a.changelog:
            parts = [p for p in a.changelog.split("|") if p.strip()]
            if len(parts) != 3:
                print("handoff: CHANGELOG must be '<section> | <change> | <evidence>'", file=sys.stderr)
                return 2
        key = ("review-" + key) if branch.startswith("review/") else key
    head = common.git("rev-parse", "--short", "HEAD")
    (handoff_dir() / ("%s.md" % key)).write_text(
        "unit = %s\nagent = %s\nbranch = %s\ncommit = %s\nstate = %s\ntime = %s\nnote = %s\nchangelog = %s\n" % (
            a.unit.lower(), a.agent, branch, head, a.state,
            dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"), a.note, a.changelog))
    heartbeat.beat(a.agent, "handed off %s (%s)" % (key, a.state))
    if a.state == "escalate":
        print("handoff: escalation %s is waiting for the orchestrator (it goes to the human)" % key)
    else:
        print("handoff: %s (%s, %s) is waiting for the orchestrator" % (branch, a.state, head))
    return 0


if __name__ == "__main__":
    sys.exit(main())
