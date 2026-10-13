#!/usr/bin/env python3
"""Immutable agent incarnations: harness/model/session attribution, not authentication or launching.

  make agent-register AGENT=dec-1 ROLE=decompiler HARNESS=opencode MODEL=provider/model SESSION=<id>
  make agent-usage AGENT=dec-1 USAGE=<harness-export.json>
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import os
import sys
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common

ROLES = ("orchestrator", "decompiler", "reviewer", "expert", "tooling", "mapper", "documentarian", "verifier")


def directory() -> Path:
    p = common.common_dir() / "poolrad-identities"
    p.mkdir(exist_ok=True)
    return p


def namespace(name: str) -> Path:
    p = directory() / name
    p.mkdir(exist_ok=True)
    return p


def is_orchestrator(agent: str) -> bool:
    """The orchestrator may be named orch, or any agent registered with role orchestrator.

    handoff-done and unlock accept that registration. A decompiler name never passes.
    """
    if agent == "orch":
        return True
    try:
        record = profile(agent)
    except ValueError:
        return False
    return bool(record and record.get("role") == "orchestrator")


def profile(agent: str) -> dict | None:
    agent = common.identifier(agent, "agent")
    for p in (namespace("by-name") / (agent + ".json"), directory() / (agent + ".json")):
        if p.exists():
            record = json.loads(p.read_text())
            if isinstance(record, dict) and record.get("agent") == agent:
                return record
    return None


def by_id(agent_id: str) -> dict | None:
    agent_id = common.identifier(agent_id, "agent id")
    for p in (namespace("by-id") / (agent_id + ".json"), directory() / (agent_id + ".json")):
        if p.exists():
            record = json.loads(p.read_text())
            if isinstance(record, dict) and record.get("agent_id") == agent_id:
                return record
    return None


def register(agent: str, role: str, harness: str, model: str, session: str, variant: str = "") -> dict:
    common.identifier(agent, "agent")
    common.identifier(harness, "harness")
    if role not in ROLES or not model.strip() or not session.strip():
        raise ValueError("registration needs ROLE, HARNESS, exact MODEL and harness SESSION; do not guess metadata")
    for label, value in (("model", model), ("session", session), ("variant", variant)):
        common.single_line(value, label)
    metadata = dict(agent=agent, role=role, harness=harness, model=model, session=session, variant=variant)
    old = profile(agent)
    if old and all(old.get(k) == v for k, v in metadata.items()):
        return old
    if old:
        held = [common.fields(p.read_text()) for p in common.lock_dir().glob("*.lock")]
        if any(p.get("agent") == agent for p in held):
            raise ValueError("agent label is still locked by another incarnation; use a new name or recover it first")
        for path in (common.common_dir() / "poolrad-expert").glob("case-*.json"):
            case = json.loads(path.read_text())
            if case.get("expert_id") == old["agent_id"] and case.get("state") in ("claimed", "expired", "usage-unknown"):
                raise ValueError("expert label still owns an unsettled case; never replace it to evade its budget")
        beat = common.common_dir() / "poolrad-heartbeats" / (agent + ".txt")
        if beat.exists() and common.fields(beat.read_text()).get("state") != "stopped":
            raise ValueError("agent label is still active; use a unique name")
    record = {**metadata, "agent_id": uuid.uuid4().hex,
              "created": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}
    common.atomic_write(namespace("by-id") / (record["agent_id"] + ".json"), json.dumps(record, sort_keys=True) + "\n")
    common.atomic_write(namespace("by-name") / (agent + ".json"), json.dumps(record, sort_keys=True) + "\n")
    import control
    control.event("agent-registered", **record)
    return record


def ensure(agent: str, role: str, harness: str = "", model: str = "", session: str = "", variant: str = "") -> dict:
    old = profile(agent)
    if harness or model or session or variant:
        return register(agent, role, harness, model, session, variant)
    if not old:
        raise ValueError("register agent metadata at creation, or pass HARNESS, MODEL and SESSION to make claim")
    if old["role"] != role:
        raise ValueError("agent is registered as %s, not %s; use a separate role/session" % (old["role"], role))
    return old


def context(agent: str = "", branch: str = "", agent_id: str | None = None) -> dict:
    """Prefer the lock's frozen identity/task id over a mutable agent label."""
    if not branch:
        try:
            branch = common.git("branch", "--show-current")
        except RuntimeError:
            branch = ""
    held = [common.fields(p.read_text()) for p in common.lock_dir().glob("*.lock")]
    lock = next((p for p in held if p.get("branch") == branch and (not agent or p.get("agent") == agent)), {})
    agent = agent or lock.get("agent") or os.environ.get("POOLRAD_AGENT", "")
    frozen = agent_id or lock.get("agent_id")
    if frozen:
        record = by_id(frozen)
    else:
        record = profile(agent) if agent else None
    return {"agent": agent or None, "agent_id": record.get("agent_id") if record else None,
            "role": record.get("role") if record else None, "harness": record.get("harness") if record else None,
            "model": record.get("model") if record else None, "variant": record.get("variant") if record else None,
            "session": record.get("session") if record else None, "task_id": lock.get("task_id"),
            "branch": branch or None}


def attribution_fields(agent: str, branch: str) -> str:
    record = context(agent, branch)
    return "".join("%s = %s\n" % (k, record[k]) for k in
                   ("agent_id", "harness", "model", "variant", "session", "task_id") if record.get(k))


def task_snapshot(key: str, unit: str, actor: dict, branch: str) -> dict:
    task = {"task_id": uuid.uuid4().hex, "key": key, "unit": unit, "branch": branch,
            "agent": actor["agent"], "agent_id": actor["agent_id"], "base": common.git("rev-parse", "main"),
            "created": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}
    p = common.common_dir() / "poolrad-tasks"
    p.mkdir(exist_ok=True)
    common.atomic_write(p / (task["task_id"] + ".json"), json.dumps(task, sort_keys=True) + "\n")
    return task


def usage(agent: str, data: dict) -> None:
    """Import a measured harness usage interval once. Missing dollars/tokens are not zero."""
    p = profile(agent)
    if not p:
        raise ValueError("register the agent before importing usage")
    allowed = {"session", "source", "interval_id", "cost_usd", "tokens", "task_id", "case_id"}
    if set(data) - allowed:
        raise ValueError("usage contains unsupported attribution fields")
    if data.get("session") != p["session"] or not data.get("source") or not data.get("interval_id"):
        raise ValueError("usage needs the matching session, source and unique interval_id")
    dollars = data.get("cost_usd")
    if isinstance(dollars, bool) or not isinstance(dollars, (int, float)) or not math.isfinite(dollars) or dollars < 0:
        raise ValueError("usage needs a finite measured cost_usd; unknown cost is not free")
    tokens = data.get("tokens", {})
    if not tokens or set(tokens) - {"input", "output", "reasoning", "cache_read", "cache_write"} or \
            any(isinstance(v, bool) or not isinstance(v, int) or v < 0 for v in tokens.values()):
        raise ValueError("usage needs nonnegative measured token counts")
    digest = hashlib.sha256((p["agent_id"] + str(data["source"]) + str(data["interval_id"])).encode()).hexdigest()
    archive = common.common_dir() / "poolrad-usage"
    archive.mkdir(exist_ok=True)
    destination = archive / (digest + ".json")
    if destination.exists():
        if json.loads(destination.read_text()) != data:
            raise ValueError("usage interval was already recorded with different values")
        return
    common.atomic_write(destination, json.dumps(data, sort_keys=True) + "\n")
    import control
    control.event("usage", agent=agent, agent_id=p["agent_id"], usage_id=digest, **data)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--agent", required=True)
    ap.add_argument("--role", choices=ROLES, default="")
    ap.add_argument("--harness", default="")
    ap.add_argument("--model", default="")
    ap.add_argument("--session", default="")
    ap.add_argument("--variant", default="")
    ap.add_argument("--usage")
    a = ap.parse_args(argv)
    try:
        import control
        registered = None
        with control.coordination_lock():
            if a.usage:
                usage(a.agent, json.loads(Path(a.usage).read_text()))
                print("usage: recorded measured interval for %s" % a.agent)
            else:
                registered = register(a.agent, a.role, a.harness, a.model, a.session, a.variant)
        if registered:
            # A read-only baseline at creation prevents attributing earlier session spend to a new task.
            # Failure is labelled unknown for regular agents; expert dispatch separately requires a meter.
            import meter
            try:
                meter.collect(a.agent)
                status = "baseline/interval captured from harness"
            except (ValueError, RuntimeError, OSError, KeyError):
                status = "unknown: no usable harness meter"
            print(json.dumps({**registered, "meter_status": status}, sort_keys=True))
        return 0
    except (ValueError, RuntimeError, OSError) as e:
        print("identity: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
