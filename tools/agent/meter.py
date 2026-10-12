#!/usr/bin/env python3
"""Read harness counters without prompting models or opening the credentials database.

OpenCode V2: authenticated CLI GET /api/session/{sessionID}, documented at opencode.ai/v2/docs/api.
Other harnesses can publish the same cumulative-counter schema through a trusted bridge. Missing,
stale or regressing counters fail closed for expert admission. This measures cost; it is NOT a provider
billing cap. The human must configure a separate harness/provider spend cap for a paid expert worker.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common
import identity
import control


def validate(data: dict, profile: dict) -> dict:
    if data.get("session") != profile["session"] or data.get("model") != profile["model"] or not data.get("source"):
        raise ValueError("meter session/model must match the registered expert, with a harness source")
    if data.get("variant", "") != profile.get("variant", ""):
        raise ValueError("meter variant does not match registration")
    cost = data.get("cost_usd")
    if isinstance(cost, bool) or not isinstance(cost, (int, float)) or not math.isfinite(cost) or cost < 0:
        raise ValueError("meter needs finite cumulative cost_usd; unknown is not zero")
    observed = data.get("observed_at")
    if not isinstance(observed, (int, float)) or not math.isfinite(observed) or not 0 <= time.time() - observed <= 120:
        raise ValueError("meter sample is stale or has no observation timestamp")
    tokens = data.get("tokens")
    if not isinstance(tokens, dict) or not {"input", "output"} <= tokens.keys() or any(
        isinstance(v, bool) or not isinstance(v, int) or v < 0 for v in tokens.values()):
        raise ValueError("meter needs measured cumulative input/output token counts")
    if set(tokens) - {"input", "output", "reasoning", "cache_read", "cache_write"}:
        raise ValueError("unsupported meter token fields")
    return data


def opencode(profile: dict) -> dict:
    session = profile["session"]
    if not re.fullmatch(r"ses_[A-Za-z0-9_-]+", session):
        raise ValueError("invalid OpenCode session id")
    try:
        result = subprocess.run(["opencode", "api", "get", "/api/session/" + session],
                                cwd=common.ROOT, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise ValueError("OpenCode usage API unavailable") from e
    if result.returncode:
        raise ValueError("OpenCode usage API failed; no cost estimate substituted")
    data = json.loads(result.stdout)["data"]
    model = data.get("model", {})
    if data.get("id") != session or model.get("variant", "") != profile.get("variant", ""):
        raise ValueError("OpenCode session/variant does not match registration")
    token = data["tokens"]
    return validate(dict(session=session, model=model["providerID"] + "/" + model["id"], variant=model.get("variant", ""),
        cost_usd=data["cost"], observed_at=time.time(), source="opencode-v2:session/" + session,
        tokens=dict(input=token["input"], output=token["output"], reasoning=token["reasoning"],
                    cache_read=token["cache"]["read"], cache_write=token["cache"]["write"])), profile)


def snapshot(profile: dict) -> dict:
    if profile["harness"] == "opencode":
        return opencode(profile)
    path = common.common_dir() / "poolrad-meter-bridge" / (profile["agent_id"] + ".json")
    if not path.exists():
        raise ValueError("no trusted meter bridge for %s; expert consultations remain blocked" % profile["harness"])
    return validate(json.loads(path.read_text()), profile)


def delta(before: dict, after: dict) -> dict:
    if before["session"] != after["session"] or before["model"] != after["model"] or before["source"] != after["source"]:
        raise ValueError("meter identity changed during the measured interval")
    cost = after["cost_usd"] - before["cost_usd"]
    tokens = {name: value - before["tokens"].get(name, 0) for name, value in after["tokens"].items()}
    if cost < 0 or any(v < 0 for v in tokens.values()):
        raise ValueError("harness counters regressed; do not treat them as a free interval")
    interval = hashlib.sha256(json.dumps([before, after], sort_keys=True).encode()).hexdigest()
    return dict(session=after["session"], source=after["source"], interval_id=interval, cost_usd=cost, tokens=tokens)


def collect(agent: str) -> dict:
    profile = identity.profile(agent)
    if not profile:
        raise ValueError("register metadata before metering")
    current = snapshot(profile)
    with control.coordination_lock():
        observe(agent, current)
    return current


def observe(agent: str, current: dict) -> None:
    """Caller holds coordination_lock; all samplers share one nonoverlapping usage checkpoint."""
    profile = identity.profile(agent)
    directory = common.common_dir() / "poolrad-meter-checkpoints"
    directory.mkdir(exist_ok=True)
    path = directory / (profile["agent_id"] + ".json")
    if path.exists():
        identity.usage(agent, delta(json.loads(path.read_text()), current))
    else:
        control.event("meter-baseline", agent=agent, cumulative_cost_usd=current["cost_usd"],
                      source=current["source"], coverage="future intervals only; earlier spend unattributed")
    common.atomic_write(path, json.dumps(current, sort_keys=True) + "\n")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--agent", required=True)
    a = ap.parse_args(argv)
    try:
        print(json.dumps(collect(a.agent), sort_keys=True))
        return 0
    except (ValueError, RuntimeError, OSError, KeyError) as e:
        print("meter: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
