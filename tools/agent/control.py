#!/usr/bin/env python3
"""Shared operator control. Stops claims, not processes; no agent lifecycle tools are called.

  make agent-control STATE=draining OPERATOR=1 REASON="finish current tasks"
  make agent-step AGENT=dec-1            check before each routine and after a wait

These are accidental-misuse guards, not authentication. A sandbox or harness permissions must protect
the control file and operator commands from workers with unrestricted shell access.
"""
from __future__ import annotations

import argparse
import datetime as dt
import fcntl
import json
import os
import sys
from contextlib import contextmanager
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common

STATES = ("running", "paused", "draining", "stopped")


@contextmanager
def coordination_lock():
    """Serialize operator state changes and claim admission across worktrees."""
    with (common.common_dir() / "poolrad-coordination.lock").open("a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)


def state() -> dict:
    path = common.common_dir() / "poolrad-control.json"
    if not path.exists():
        return {"state": "running", "reason": "legacy run: no operator control set"}
    record = json.loads(path.read_text())
    if not isinstance(record, dict) or record.get("state") not in STATES:
        raise ValueError("invalid operator control state; refusing new work")
    return record


def admit() -> None:
    record = state()
    if record["state"] != "running":
        raise ValueError("operator control is %s: %s; do not claim more work" % (
            record["state"], record.get("reason", "")))


def event(kind: str, **data) -> None:
    """Append-only coordination history; the dashboard's latest heartbeat is not an audit log."""
    record = {"time": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
              "event": kind, **data}
    with (common.common_dir() / "poolrad-events.jsonl").open("a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.write(json.dumps(record, sort_keys=True) + "\n")
        f.flush()
        os.fsync(f.fileno())


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--state", choices=STATES)
    ap.add_argument("--operator", action="store_true", help="human acknowledgement, not authentication")
    ap.add_argument("--reason", default="")
    ap.add_argument("--step", action="store_true")
    ap.add_argument("--agent", default=os.environ.get("AGENT", ""))
    a = ap.parse_args(argv)
    try:
        if a.step and a.state:
            raise ValueError("--step cannot change operator state")
        if a.state:
            if not a.operator or not a.reason.strip():
                raise ValueError("changing control needs OPERATOR=1 and REASON=<human instruction>")
            common.require_main("agent-control")
            common.single_line(a.reason, "reason")
            with coordination_lock():
                old = state()["state"]
                record = {"state": a.state, "reason": a.reason,
                          "time": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}
                common.atomic_write(common.common_dir() / "poolrad-control.json", json.dumps(record) + "\n")
                event("control", previous=old, **record)
        record = state()
        print("control: %s (%s)" % (record["state"], record.get("reason", "")))
        if a.step:
            common.identifier(a.agent, "agent")
            if record["state"] in ("paused", "stopped"):
                print("agent-step: stop starting routines; preserve work and hand off before stopping")
                return 3
            if record["state"] == "draining":
                print("agent-step: finish and hand off only your current task, then stop")
        return 0
    except (ValueError, RuntimeError, OSError) as e:
        print("control: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
