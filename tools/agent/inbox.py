#!/usr/bin/env python3
"""inbox.py: everything waiting for a human, newest last, each with the command that resolves it.

  make inbox [JSON=1]
  .venv/bin/python tools/agent/inbox.py [--json]

One place instead of a stream (docs/process/SYSTEM-REVIEW-2026-10-12.md 6.6). Every item is four lines:
what, evidence (a path or a coordination key), recommendation, the exact command to run. Sections:

  Escalations        pending hand-off records escalate-*.md; cleared by `make handoff-done ... DECISION=`
  Rejected           hand-off records an integrator marked `integrate = rejected` (with integrate_reason,
                     integrate_log, integrate_time); the worker's agent reclaims the unit and reads the log
  To merge           the other pending hand-offs (complete, partial, blocked, review-*); `make integrate`
  Locks              a lock whose holder's last heartbeat says stopped or is older than a day, or whose
                     claim is older than a day with no commits beyond main; operator recovery
  Frontier           routines whose worker attempts reached the limit; release after a matcher fix
  Main               no passing `make check` receipt for the current main tree
  Queues             the next unit and the next review

Everything is read from the clone's common git directory (tools/agent/common.py) and the registry; the
inbox changes nothing and always exits 0. `--json` prints the same items as a JSON list.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402

STALE_HOURS = 24
ORCHESTRATOR = "orch"


def now() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def when(value: str | None, fallback: float = 0.0) -> dt.datetime:
    try:
        d = dt.datetime.fromisoformat(value or "")
        return d if d.tzinfo else d.replace(tzinfo=dt.timezone.utc)
    except ValueError:
        return dt.datetime.fromtimestamp(fallback, dt.timezone.utc)


def item(section: str, what: str, evidence: str, recommendation: str, command: str, time: dt.datetime) -> dict:
    return {"section": section, "what": what, "evidence": evidence, "recommendation": recommendation,
            "command": command, "time": time.isoformat(timespec="seconds")}


def handoff_records() -> list[tuple[Path, dict]]:
    d = common.common_dir() / "poolrad-handoffs"
    if not d.exists():
        return []
    out = []
    for p in sorted(d.glob("*.md")):
        try:
            out.append((p, common.fields(p.read_text())))
        except ValueError:
            out.append((p, {"note": "unreadable record"}))
    return out


def handoffs() -> list[dict]:
    out = []
    for p, f in handoff_records():
        t = when(f.get("time"), p.stat().st_mtime)
        key = p.stem
        if key.startswith("escalate-"):
            out.append(item("Escalations",
                            "escalation from %s about %s: %s" % (f.get("agent", "?"), f.get("unit", "?"),
                                                                 f.get("note", "")[:400]),
                            str(p), "decide it (the note says what the agent recommends) and record the decision",
                            'make handoff-done AGENT=%s UNIT=%s DECISION="<decision>"' % (ORCHESTRATOR, key), t))
        elif f.get("integrate") == "rejected":
            out.append(item("Rejected",
                            "integration of %s (%s, %s) was rejected: %s" % (
                                f.get("branch", key), f.get("state", "?"), f.get("agent", "?"),
                                f.get("integrate_reason", "no reason recorded")),
                            f.get("integrate_log", str(p)),
                            "read the log, then let the owner take the unit back and fix the branch (the worker's "
                            "sessions see the rejection reason in their prompt)",
                            "make worker AGENT=%s ROLE=decompiler UNIT=%s   (by hand: make claim AGENT=%s UNIT=%s; log %s)" % (
                                f.get("agent", "<agent>"), f.get("unit", key), f.get("agent", "<agent>"),
                                f.get("unit", key), f.get("integrate_log", "the log")),
                            when(f.get("integrate_time"), p.stat().st_mtime)))
        else:
            out.append(item("To merge",
                            "%s (%s) from %s at %s: %s" % (f.get("branch", key), f.get("state", "?"),
                                                           f.get("agent", "?"), f.get("commit", "?")[:12],
                                                           f.get("note", "")[:200]),
                            str(p), "integrate it", "make integrate", t))
    return out


def commits_beyond_main(branch: str) -> int | None:
    try:
        if not common.git("branch", "--list", branch):
            return None
        return int(common.git("rev-list", "--count", "main..%s" % branch) or 0)
    except RuntimeError:
        return None


def locks() -> list[dict]:
    out = []
    beats = common.common_dir() / "poolrad-heartbeats"
    for p in sorted(common.lock_dir().glob("*.lock")):
        f = common.fields(p.read_text())
        key, agent = p.stem, f.get("agent", "?")
        started = when(f.get("started"), p.stat().st_mtime)
        reasons = []
        beat = beats / ("%s.txt" % agent)
        if beat.exists():
            h = common.fields(beat.read_text())
            age = now() - when(h.get("time"), beat.stat().st_mtime)
            if h.get("state") == "stopped":
                reasons.append("its holder %s said it stopped (%s)" % (agent, h.get("note", "")[:120]))
            elif age > dt.timedelta(hours=STALE_HOURS):
                reasons.append("its holder %s last beat %d h ago" % (agent, age.total_seconds() // 3600))
        if now() - started > dt.timedelta(hours=STALE_HOURS):
            n = commits_beyond_main(f.get("branch", ""))
            if not n:
                reasons.append("claimed %d h ago with %s beyond main" % (
                    (now() - started).total_seconds() // 3600, "no commits" if n == 0 else "no branch"))
        if reasons:
            out.append(item("Locks", "lock %s held by %s looks abandoned: %s" % (key, agent, "; ".join(reasons)),
                            str(p), "confirm the holder is gone (make agents), then release it",
                            'make unlock UNIT=%s OPERATOR=1 FORCE=1 REASON="holder %s confirmed gone"' % (key, agent),
                            started))
    return out


def frontier() -> list[dict]:
    import worker
    out = []
    d = common.common_dir() / "poolrad-frontier"
    if not d.exists():
        return out
    for p in sorted(d.glob("*.json")):
        try:
            data = json.loads(p.read_text())
        except ValueError:
            continue
        unit = p.stem
        failed = {rid: e for rid, e in data.items() if e.get("escalation_exhausted")}
        if failed:
            last = max(when(e.get("last"), p.stat().st_mtime) for e in failed.values())
            out.append(item("Escalation failed",
                            "%s: the escalation tier could not match %d routine(s) either: %s" % (
                                unit, len(failed), ", ".join(sorted(failed))),
                            str(p), "read the routines' notes in re/symbols.toml (the escalation wrote what it "
                            "established) and decide: a matcher or map fix, a probe, or more escalation attempts",
                            ".venv/bin/python tools/agent/worker.py --release %s <routine>   (clears its attempts)" % unit,
                            last))
        hit = {rid: e for rid, e in data.items()
               if int(e.get("attempts", 0)) >= worker.DEFAULT_MAX_ATTEMPTS and not e.get("escalation_exhausted")}
        if not hit:
            continue
        last = max(when(e.get("last"), p.stat().st_mtime) for e in hit.values())
        out.append(item("Frontier",
                        "%s: %d routine(s) at the attempt limit: %s" % (
                            unit, len(hit), ", ".join("%s (%d)" % (rid, int(e.get("attempts", 0)))
                                                       for rid, e in sorted(hit.items()))),
                        str(p), "the escalation tier (a tier-2 worker) takes them; without one, fix what stopped them and release them",
                        ".venv/bin/python tools/agent/worker.py --release %s   then   make worker AGENT=<name> ROLE=decompiler UNIT=%s" % (unit, unit),
                        last))
    return out


def main_check() -> list[dict]:
    import check
    try:
        current = check.fingerprint()
        ok = (check.receipts() / (current + ".json")).exists()
    except (RuntimeError, OSError, ValueError) as e:
        return [item("Main", "could not fingerprint main: %s" % e, str(common.ROOT), "run the check", "make check", now())]
    if ok:
        return []
    return [item("Main", "no passing make check receipt for the current main tree", str(check.receipts()),
                 "run the check before integrating anything", "make check", now())]


def queues() -> list[dict]:
    import next as nxt
    out = []
    try:
        u = nxt.next_unit()
        out.append(item("Queues", "next unit: %s (%s; %d of %d routines at L2)" % u if u else
                        "next unit: none (queue empty, or every unit locked, complete or waiting)",
                        str(common.ROOT / "work/queue.toml"), "start a worker on it" if u else "nothing to start",
                        "make worker AGENT=<name> ROLE=decompiler" if u else "", now()))
        r = nxt.next_review()
        out.append(item("Queues", "next review: %s (%s; %d routines)" % r[:3] if r else "next review: none waiting",
                        str(common.ROOT / "work/queue.toml"), "start a reviewer on it" if r else "nothing to start",
                        "make worker AGENT=<name> ROLE=reviewer" if r else "", now()))
    except (OSError, ValueError, KeyError) as e:
        out.append(item("Queues", "queues unreadable: %s" % e, str(common.ROOT), "check the registry", "make status", now()))
    return out


SECTIONS = ("Escalations", "Rejected", "To merge", "Locks", "Frontier", "Main", "Queues")


def items() -> list[dict]:
    out = handoffs() + locks() + frontier() + main_check() + queues()
    order = {s: k for k, s in enumerate(SECTIONS)}
    return sorted(out, key=lambda i: (order.get(i["section"], 99), i["time"]))      # newest last per section


def render(rows: list[dict]) -> str:
    lines = []
    section = None
    for i in rows:
        if i["section"] != section:
            section = i["section"]
            lines += ["", "== %s ==" % section]
        lines += ["what:      " + i["what"], "evidence:  " + i["evidence"],
                  "recommend: " + i["recommendation"], "command:   " + (i["command"] or "(none)"), ""]
    waiting = sum(i["section"] not in ("Queues",) for i in rows)
    lines.append("inbox: %d item(s) waiting for a human (%s)" % (waiting, common.common_dir()))
    return "\n".join(lines).lstrip("\n")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    try:
        rows = items()
    except Exception as e:                            # noqa: BLE001  the inbox must always answer
        rows = [item("Main", "inbox could not read the coordination state: %s" % e, str(common.common_dir()),
                     "check the clone", "make doctor", now())]
    print(json.dumps(rows, indent=1) if a.json else render(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
