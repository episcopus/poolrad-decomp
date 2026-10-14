#!/usr/bin/env python3
"""watch.py: the operator's live view of the agents (docs/process/KICKOFF.md, "What you watch").

  make watch-agents [INTERVAL=5]          redraw every INTERVAL seconds until Ctrl+C

One screen: progress (units, routines, and code bytes at L2: on main, and with what the unit locks'
worktrees have matched but not handed off or not integrated yet), agents still in the run, the hand-offs waiting for the orchestrator
(escalations first), the locks, and what the queues offer next. Active agents (a heartbeat within
heartbeat.QUIET_MINUTES) come first, then any agent quiet for less than heartbeat.LAPSED_MINUTES,
each group by name. A stopped session, and a heartbeat silent for LAPSED_MINUTES or more, is left
off this screen; `make agents` still lists every heartbeat file.
It only reads the shared files next to the locks (tools/agent/common.py) and the registry of the
checkout it runs in, so it is safe to leave running while agents work.
"""
from __future__ import annotations

import argparse
import datetime as dt
import shutil
import tomllib
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


def matched(r: dict) -> bool:
    return r.get("level") in ("L2", "L3")


def unit_bytes(rs: list[dict], unit: str) -> tuple[int, int]:
    """(bytes at L2/L3, all bytes) of a unit's Pascal routines, by re/symbols.toml sizes (as make status)."""
    mine = [r for r in rs if r["unit"] == unit and not r.get("external")]
    return (sum(int(r.get("size") or 0) for r in mine if matched(r)), sum(int(r.get("size") or 0) for r in mine))


def in_flight(rs: list[dict], units: set[str]) -> dict[str, tuple[int, int]]:
    """Per locked unit: (bytes at L2, all bytes) in the holder's worktree registry. The worker records L2
    there after every batch, but main sees it only after the hand-off is integrated."""
    out = {}
    wts = common.main_checkout().parent / "poolrad-worktrees"
    for p in common.lock_dir().glob("*.lock"):
        unit = p.stem
        if unit not in units:
            continue                                         # reviews and tasks change no levels
        reg = wts / unit / "re/symbols.toml"
        try:
            out[unit] = unit_bytes(tomllib.loads(reg.read_text()).get("routine", []), unit)
        except (OSError, tomllib.TOMLDecodeError):
            continue                                         # mid-write or gone: next redraw
    return out


def pct(part: int, whole: int) -> str:
    return "%.1f%%" % (100.0 * part / whole) if whole else "?"


def progress() -> str:
    rs = common.routines()
    units = [u["id"] for u in common.queue()]
    mine = [r for r in rs if r["unit"] in units]
    done = [u for u in units if common.unit_complete(u, rs)]
    passed = [u for u in done if nxt.reviewed(u, rs)]
    l2 = sum(matched(r) for r in mine)
    game = [r for r in mine if not r.get("external")]
    total = sum(int(r.get("size") or 0) for r in game)
    on_main = sum(int(r.get("size") or 0) for r in game if matched(r))
    extra = sum(max(0, wt - unit_bytes(rs, u)[0]) for u, (wt, _) in in_flight(rs, set(units)).items())
    line = "units %s complete, %s reviewed   routines %s at L2   bytes %s at L2 (%s)" % (
        c(BOLD, "%d/%d" % (len(done), len(units))), c(BOLD, str(len(passed))), c(BOLD, "%d/%d" % (l2, len(mine))),
        c(BOLD, "{:,}/{:,}".format(on_main, total)), c(BOLD, pct(on_main, total)))
    if extra:
        line += "   +{:,} in worktrees: {}".format(extra, c(BOLD + ";" + GREEN, pct(on_main + extra, total)))
    return line


def agents(now: dt.datetime, width: int) -> list[str]:
    """Active agents first, then by name. Stopped sessions and lapsed heartbeats are omitted."""
    rows = []
    for p in heartbeat.heartbeat_dir().glob("*.txt"):
        f = heartbeat.fields(p.read_text())
        age = int((now - dt.datetime.fromisoformat(f["time"])).total_seconds() // 60)
        if f.get("state") == "stopped" or age >= heartbeat.LAPSED_MINUTES:
            continue
        note = f.get("note", "") + (" | last: %s" % f["activity"] if f.get("activity") else "")
        active = age <= heartbeat.QUIET_MINUTES
        rows.append((not active, f["agent"], age, f.get("branch", "?"), note))
    rows.sort(key=lambda r: (r[0], r[1]))                     # active first, then by name
    out = []
    for quiet, agent, age, branch, note in rows:
        flag, paint = ("QUIET", RED) if quiet else ("ok", GREEN)
        head = "%-8s %-9s %6s  %-22s " % (flag, agent, ago(age), cut(branch, 22))
        out.append(c(paint, "%-8s" % flag) + head[8:] + cut(note, width - len(head)))
    return out or [c(DIM, "no active agents")]


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
    flight = in_flight(common.routines(), {u["id"] for u in common.queue()})
    for p in sorted(common.lock_dir().glob("*.lock")):
        f = heartbeat.fields(p.read_text())
        share = "%6s" % pct(*flight[p.stem]) if p.stem in flight else " " * 6
        out.append("%-16s %-14s %s" % (p.stem, cut(f.get("agent", "?"), 14), share))
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
