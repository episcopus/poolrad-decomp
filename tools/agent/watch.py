#!/usr/bin/env python3
"""watch.py: the operator's live view of the agents (docs/process/KICKOFF.md, "What you watch").

  make watch-agents [INTERVAL=5]          redraw every INTERVAL seconds until Ctrl+C

One screen: progress, every agent's last heartbeat (QUIET in red after heartbeat.QUIET_MINUTES), the
hand-offs waiting for the orchestrator (escalations first), the locks, and what the queues offer next.
It only reads the shared files next to the locks (tools/agent/common.py) and the registry of the
checkout it runs in, so it is safe to leave running while agents work.
"""
from __future__ import annotations

import argparse
import datetime as dt
import shutil
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import control  # noqa: E402
import handoff  # noqa: E402
import heartbeat  # noqa: E402
import next as nxt  # noqa: E402

COLOR = sys.stdout.isatty()


def c(code: str, text: str) -> str:
    return "\033[%sm%s\033[0m" % (code, text) if COLOR else text


BOLD, DIM, RED, GREEN, YELLOW, CYAN = "1", "2", "1;31", "32", "33", "36"


def ago(minutes: int) -> str:
    return "%dm" % minutes if minutes < 60 else "%dh%02dm" % divmod(minutes, 60)


def cut(text: str, width: int) -> str:
    return text if len(text) <= width else text[:max(width - 1, 0)] + "…"


def section(title: str, width: int) -> str:
    return c(BOLD + ";" + CYAN, "── %s " % title) + c(DIM, "─" * max(width - len(title) - 4, 0))


def progress() -> str:
    rs = common.routines()
    units = [u["id"] for u in common.queue()]
    mine = [r for r in rs if r["unit"] in units]
    done = [u for u in units if common.unit_complete(u, rs)]
    passed = [u for u in done if nxt.reviewed(u, rs)]
    l2 = sum(r.get("level") in ("L2", "L3") for r in mine)
    return "units %s complete, %s reviewed   routines %s at L2" % (
        c(BOLD, "%d/%d" % (len(done), len(units))), c(BOLD, str(len(passed))), c(BOLD, "%d/%d" % (l2, len(mine))))


def agents(now: dt.datetime, width: int) -> list[str]:
    rows = []
    for p in heartbeat.heartbeat_dir().glob("*.txt"):
        f = heartbeat.fields(p.read_text())
        age = int((now - dt.datetime.fromisoformat(f["time"])).total_seconds() // 60)
        stopped = f.get("state") == "stopped"
        note = f.get("note", "") + (" | last: %s" % f["activity"] if f.get("activity") else "")
        rows.append((stopped, f["agent"], age, f.get("branch", "?"), note))
    rows.sort(key=lambda r: (r[0], r[1]))                     # working agents first, then by name
    out = []
    for stopped, agent, age, branch, note in rows:
        if stopped:
            flag, paint = "stopped", DIM
        elif age > heartbeat.QUIET_MINUTES:
            flag, paint = "QUIET", RED
        else:
            flag, paint = "ok", GREEN
        head = "%-8s %-9s %6s  %-22s " % (flag, agent, ago(age), cut(branch, 22))
        line = c(paint, "%-8s" % flag) + head[8:] + cut(note, width - len(head))
        out.append(c(DIM, line) if stopped else line)
    return out or [c(DIM, "no heartbeat yet")]


def handoffs(width: int) -> list[str]:
    files = sorted(handoff.handoff_dir().glob("*.md"),
                   key=lambda p: (not p.stem.startswith("escalate-"), p.stat().st_mtime))
    out = []
    for p in files:
        f = handoff.fields(p.read_text())
        esc = p.stem.startswith("escalate-")
        tag = c(RED, "ESCALATE") if esc else c(YELLOW, "%-8s" % f.get("state", "?")[:8])
        head = "%-8s %-28s %-9s " % ("", cut(p.stem, 28), cut(f.get("agent", "?"), 9))
        out.append(tag + head[8:] + cut(f.get("note", ""), width - len(head)))
    return out or [c(DIM, "nothing waiting")]


def locks() -> list[str]:
    out = []
    for p in sorted(common.lock_dir().glob("*.lock")):
        f = heartbeat.fields(p.read_text())
        out.append("%-16s %-9s" % (p.stem, f.get("agent", "?")))
    if not out:
        return [c(DIM, "none")]
    return ["   ".join(out[i:i + 3]) for i in range(0, len(out), 3)]


def queues() -> str:
    u, r = nxt.next_unit(), nxt.next_review()
    return "next unit %s   next review %s" % (c(BOLD, u[0]) if u else c(DIM, "none"),
                                              c(BOLD, r[0]) if r else c(DIM, "none"))


def screen(interval: int) -> str:
    width = shutil.get_terminal_size((120, 40)).columns
    now = dt.datetime.now(dt.timezone.utc)
    title = "POOL OF RADIANCE  agents"
    stamp = "%s  every %ds  Ctrl+C to stop" % (now.astimezone().strftime("%H:%M:%S"), interval)
    state = control.state()
    label = "Control: %s, %s" % (state["state"], state.get("reason", ""))
    lines = [c(BOLD, title) + " " * max(width - len(title) - len(stamp), 1) + c(DIM, stamp),
             progress(), cut(label, width), ""]
    for name, body in (("Agents", agents(now, width)), ("Hand-offs", handoffs(width)), ("Locks", locks()),
                       ("Queues", [queues()])):
        lines += [section(name, width), *body, ""]
    return "\n".join(lines)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--interval", type=int, default=5)
    ap.add_argument("--once", action="store_true", help="draw one screen and exit")
    a = ap.parse_args(argv)
    if a.once:
        print(screen(a.interval))
        return 0
    sys.stdout.write("\033[?25l")                              # hide the cursor while drawing
    try:
        while True:
            try:
                text = screen(a.interval)
            except Exception as e:                            # a file mid-write: show it, try again
                text = "watch: %s" % e
            sys.stdout.write("\033[H\033[2J" + text)
            sys.stdout.flush()
            time.sleep(a.interval)
    except KeyboardInterrupt:
        return 0
    finally:
        sys.stdout.write("\033[?25h\n")


if __name__ == "__main__":
    sys.exit(main())
