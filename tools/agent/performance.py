#!/usr/bin/env python3
"""Report attributable task/tool outcomes. Missing identity, billing and old events stay unknown."""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common


def events() -> list[dict]:
    p = common.common_dir() / "poolrad-events.jsonl"
    if not p.exists():
        return []
    result = []
    for line in p.read_text().splitlines():
        try:
            result.append(json.loads(line))
        except json.JSONDecodeError:
            # Only an incomplete final append may be ignored; earlier corruption is surfaced.
            raise ValueError("coordination event log has an invalid JSON record")
    return result


def summarize(rows: list[dict], run_id: str | None = None) -> dict:
    agents = {}
    seen_usage, seen_completed = set(), set()
    instrumented_checks = {r.get("check_id") for r in rows if r.get("event") == "activity" and r.get("check_id")}
    for row in rows:
        if run_id and row.get("run_id") != run_id:
            continue
        label = row.get("agent")
        if not label:
            continue
        key = row.get("agent_id") or "legacy:" + label
        item = agents.setdefault(key, dict(agent_id=row.get("agent_id"), agent=label,
            harness=row.get("harness"), model=row.get("model"), session=row.get("session"), role=row.get("role"),
            claims=0, accepted_tasks=0, recorded_promotions=0, accepted_code_bytes=0,
            activities=0, failures=0, tool_seconds=0.0, accepted_wall_seconds=0.0, tools={}, cost_usd=None, tokens={}))
        kind = row.get("event")
        if kind == "claim":
            item["claims"] += 1
        elif kind == "task-accepted" and row.get("task_id") not in seen_completed:
            seen_completed.add(row.get("task_id"))
            item["accepted_tasks"] += 1
            item["recorded_promotions"] += row.get("recorded_promotions", 0)
            item["accepted_code_bytes"] += row.get("accepted_code_bytes", 0)
            item["accepted_wall_seconds"] += row.get("wall_seconds", 0)
        elif kind == "activity":
            item["activities"] += 1
            item["failures"] += int(row.get("returncode", 0) != 0)
            seconds = row.get("seconds", 0)
            item["tool_seconds"] += seconds
            tool = row.get("tool", "unknown")
            item["tools"][tool] = item["tools"].get(tool, 0.0) + seconds
        elif kind in ("check-passed", "check-failed"):
            for stage, seconds in row.get("seconds", {}).items():
                if stage == "match" and row.get("check_id") in instrumented_checks:
                    continue
                item["tool_seconds"] += seconds
                item["tools"]["check." + stage] = item["tools"].get("check." + stage, 0.0) + seconds
        elif kind == "usage" and row.get("usage_id") not in seen_usage:
            seen_usage.add(row.get("usage_id"))
            item["cost_usd"] = (item["cost_usd"] or 0) + row["cost_usd"]
            for name, value in row.get("tokens", {}).items():
                item["tokens"][name] = item["tokens"].get(name, 0) + value
    return {"agents": list(agents.values()), "notes": [
        "Promotions are registry deltas accepted on main, not a controlled model benchmark.",
        "Tool time excludes model reasoning and queue waits. Dollar coverage includes imported intervals only.",
        "Missing model/harness/cost is unknown, never zero or inferred from an agent name."]}


def accepted(handoff: dict, check_record: dict | None = None) -> None:
    """Attribute accepted registry deltas to the submitter, not to the orchestrator clearing them."""
    task_id = handoff.get("task_id")
    if not task_id:
        return                                        # legacy hand-off cannot be retroactively attributed
    path = common.common_dir() / "poolrad-tasks" / (common.identifier(task_id) + ".json")
    task = json.loads(path.read_text())
    import safety
    old = safety.entries(safety.blob(task["base"], "re/symbols.toml"), "routine", "id")
    new = safety.entries(safety.blob("HEAD", "re/symbols.toml"), "routine", "id")
    ids = {rid for rid, row in new.items() if row.get("unit") == task["unit"] and
           row.get("level") in ("L2", "L3") and old.get(rid, {}).get("level") not in ("L2", "L3")}
    proven = {}
    check_id = (check_record or {}).get("check_id")
    if check_id:
        for row in events():
            if row.get("event") == "activity" and row.get("check_id") == check_id and not row.get("returncode"):
                proven.update({r["routine"]: r for r in row.get("routines", [])})
    import control
    control.event("task-accepted", agent=task["agent"], agent_id=task["agent_id"], task_id=task_id,
                  unit=task["unit"], commit=handoff["commit"], recorded_promotions=len(ids),
                  wall_seconds=max(0, (dt.datetime.now(dt.timezone.utc) - dt.datetime.fromisoformat(task["created"])).total_seconds()),
                  accepted_code_bytes=sum(proven[rid]["code_bytes"] for rid in ids if rid in proven))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args(argv)
    try:
        report = summarize(events(), a.run)
        if a.json:
            print(json.dumps(report, sort_keys=True, indent=2))
        else:
            print("Agent / harness / model | claims | accepted tasks | L2 promotions | code bytes | tool seconds | imported USD")
            for row in report["agents"]:
                print("%s / %s / %s | %d | %d | %d | %d | %.1f | %s" % (
                    row["agent"], row["harness"] or "unknown", row["model"] or "unknown", row["claims"],
                    row["accepted_tasks"], row["recorded_promotions"], row["accepted_code_bytes"], row["tool_seconds"],
                    "unknown" if row["cost_usd"] is None else "%.2f" % row["cost_usd"]))
            print("\n".join(report["notes"]))
        return 0
    except (ValueError, RuntimeError, OSError) as e:
        print("performance: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
