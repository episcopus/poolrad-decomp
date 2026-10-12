#!/usr/bin/env python3
"""Bounded advice queue for ONE human-started expert. Never launches, replaces or stops agents.

Conservative defaults: 1 active case, 5 cases/run, 900 seconds/case, $10 allocation/case and $50/run.
Dollar admission uses real harness counters and reserved allocations. Counters arrive after model
turns, so a provider/harness billing cap is REQUIRED; repository reservations are not a hard invoice
ceiling. Missing usage, expiry or overage freezes dispatch. No recursive consultation, verdict-writing,
source editing or human-reserved decisions. Advice returns to the original worker for normal proof.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
import tomllib
import uuid
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import common
import control
import identity
import learning
import meter
import performance
import activity

DEFAULTS = dict(max_cases=5, case_usd=10.0, run_usd=50.0, deadline_seconds=900)


def directory() -> Path:
    p = common.common_dir() / "poolrad-expert"
    p.mkdir(exist_ok=True)
    return p


def policy() -> dict:
    p = directory() / "policy.json"
    if not p.exists():
        raise ValueError("expert budget is not configured by the human; no automatic spending")
    return json.loads(p.read_text())


def write_case(case: dict) -> None:
    common.atomic_write(directory() / (case["case_id"] + ".json"), json.dumps(case, sort_keys=True) + "\n")


def cases() -> list[dict]:
    return [json.loads(p.read_text()) for p in sorted(directory().glob("case-*.json"))]


def get_case(case_id: str) -> dict:
    if not re.fullmatch(r"case-[0-9a-f]{32}", case_id):
        raise ValueError("invalid expert case id")
    return json.loads((directory() / (common.identifier(case_id, "case id") + ".json")).read_text())


def freeze(reason: str, case_id: str | None = None, kind: str = "usage") -> None:
    p = policy()
    p["frozen"] = reason
    p["frozen_case"] = case_id
    p["frozen_kind"] = kind
    common.atomic_write(directory() / "policy.json", json.dumps(p, sort_keys=True) + "\n")
    control.event("expert-frozen", reason=reason)


def configure(agent: str, billing_cap: str, reason: str) -> dict:
    common.require_main("expert-budget")
    control.admit()
    if not billing_cap.strip() or not reason.strip():
        raise ValueError("human must supply the external provider/harness BILLING_CAP_REF and approval reason")
    actor = identity.ensure(agent, "expert")
    sample = meter.snapshot(actor)
    for case in cases():
        if case["state"] in ("claimed", "expired", "usage-unknown"):
            raise ValueError("reconcile the outstanding expert case before admitting another budget")
    run = control.state().get("run_id")
    if not run:
        raise ValueError("start an explicitly identified run before configuring the expert")
    existing = directory() / "policy.json"
    if existing.exists() and policy().get("run_id") == run:
        raise ValueError("this run already has a budget; do not reset counters to obtain more consultations")
    p = {**DEFAULTS, "run_id": run, "expert_id": actor["agent_id"], "expert": agent,
         "baseline": sample, "billing_cap_ref": billing_cap, "approval": reason, "frozen": None}
    common.atomic_write(existing, json.dumps(p, sort_keys=True) + "\n")
    meter.observe(agent, sample)
    control.event("expert-budget", agent=agent, **{k: v for k, v in p.items() if k != "baseline"})
    return p


def budget(p: dict, sample: dict, extra: float = 0) -> None:
    if p.get("frozen") and p.get("frozen_kind") == "usage" and not p.get("frozen_case"):
        # A pre-dispatch meter outage can recover automatically, but an unsettled paid case cannot.
        meter.delta(p["baseline"], sample)
        if not any(c["state"] in ("claimed", "expired", "usage-unknown") for c in cases()):
            p.update(frozen=None, frozen_kind=None)
            common.atomic_write(directory() / "policy.json", json.dumps(p, sort_keys=True) + "\n")
            control.event("expert-meter-restored")
    if p.get("frozen"):
        raise ValueError("expert dispatch frozen: " + p["frozen"])
    if p.get("run_id") != control.state().get("run_id"):
        raise ValueError("expert authorization belongs to another run")
    spent = meter.delta(p["baseline"], sample)["cost_usd"]
    reserved = 0.0
    for case in cases():
        if case["run_id"] != p["run_id"] or case["state"] not in ("claimed", "expired", "usage-unknown"):
            continue
        used = meter.delta(case["meter_start"], sample)["cost_usd"] if case.get("meter_start") else 0.0
        reserved += max(0, case["allocation_usd"] - used)
    if spent + reserved + extra > p["run_usd"]:
        raise ValueError("expert run allocation exhausted; no replacement or extra consultation")


def problem(unit: str, fn: str) -> dict:
    if unit not in {u["id"] for u in common.queue()}:
        raise ValueError("expert cases must name a queued game unit")
    rows = common.routines()
    matches = [r for r in rows if r["unit"] == unit and fn.lower() in (r["id"].lower(), r["name"].lower())]
    if len(matches) != 1:
        raise ValueError("expert case needs one known routine id/name in that unit")
    return matches[0]


def eligible(unit: str, row: dict, category: str) -> list[dict]:
    history = performance.events()
    if category == "codegen":
        trials = [e for e in history if e.get("event") == "activity" and e.get("tool") == "match" and
                  e.get("unit") == unit and e.get("returncode") and e.get("revision") and
                  (any(f["routine"] == row["id"] for f in e.get("failed", [])) or
                   row["name"] in e.get("args", []) or row["id"] in e.get("args", []))]
        unique = {}
        for event in trials:
            unique.pop(event["revision"], None)
            unique[event["revision"]] = event
        if len(unique) < 3:
            raise ValueError("consult only after 3 recorded distinct failed revisions; read learning/idioms first")
        return list(unique.values())[-5:]
    trials = []
    for event in history:
        if event.get("event") == "handoff" and event.get("key") == "review-" + unit:
            if event.get("state") == "review-passed":
                trials = []
            elif event.get("state") == "review-failed":
                trials.append(event)
    if len({e["commit"] for e in trials}) < 2:
        raise ValueError("review consultation needs 2 recorded failed review rounds")
    return trials[-3:]


def candidates() -> list[dict]:
    """Cheap deterministic triage, not another reasoning agent polling a dashboard."""
    latest = {}
    for event in performance.events():
        if event.get("event") == "activity" and event.get("tool") == "match" and event.get("returncode"):
            for failed in event.get("failed", []):
                if event.get("unit"):
                    latest[(event["unit"], failed["routine"])] = failed
    out = []
    for (unit, routine), failed in sorted(latest.items()):
        try:
            row = problem(unit, routine)
            eligible(unit, row, "codegen")
            out.append(dict(unit=unit, routine=routine, category="codegen",
                            question="Diagnose these recorded code-generation failures without changing matcher rules: " + failed["detail"][:900]))
        except ValueError:
            continue
    for entry in common.queue():
        unit = entry["id"]
        findings = common.open_must_fix(unit)
        if not findings:
            continue
        rows = [r for r in common.routines() if r["unit"] == unit and not r["name"].endswith("_init")]
        targeted = [r for r in rows if any(r["name"] in f or r["id"] in f for f in findings)]
        if not targeted:
            continue                           # do not guess the affected routine for a unit-wide finding
        try:
            eligible(unit, targeted[0], "review")
            out.append(dict(unit=unit, routine=targeted[0]["id"], category="review",
                            question="Diagnose recurring review findings; advice is not a review pass: " + " ".join(findings)[:1200]))
        except ValueError:
            continue
    return out


def scan(agent: str) -> list[dict]:
    identity.ensure(agent, "orchestrator")
    control.admit()
    queued = []
    for candidate in candidates():
        try:
            case = request(agent, candidate["unit"], candidate["routine"], candidate["category"], candidate["question"])
            queued.append(dict(case_id=case["case_id"], unit=case["unit"], routine=case["routine"]))
        except ValueError as e:
            queued.append(dict(**candidate, held=str(e)))
            if (directory() / "policy.json").exists() and policy().get("frozen"):
                break
    return queued


def request(agent: str, unit: str, fn: str, category: str, question: str) -> dict:
    identity.ensure(agent, "orchestrator")
    control.admit()
    p = policy()
    expert = identity.profile(p["expert"])
    if not expert or expert["agent_id"] != p["expert_id"]:
        raise ValueError("the approved expert incarnation changed; no replacement launch is authorized")
    row = problem(unit, fn)
    if not question.strip() or len(question) > 2000:
        raise ValueError("provide a bounded, specific question (up to 2000 characters)")
    # Known human-held rule questions go to the human, not to a paid advisor as an approval proxy.
    notes = row.get("notes", "").lower()
    if "waiting for the human" in notes or "human decision" in notes or "escalate-res06-20261012110841" in notes:
        raise ValueError("routine is held on a human decision; expert advice cannot authorize it")
    history = eligible(unit, row, category)
    main_dir = common.main_checkout()
    worker = main_dir.parent / "poolrad-worktrees" / unit
    root = worker if category == "codegen" and worker.is_dir() else main_dir
    revision = activity.source_revision(root)
    frozen_trial = None
    if category == "codegen" and revision != history[-1]["revision"]:
        path = common.common_dir() / "poolrad-trials" / (unit + "-" + history[-1]["revision"] + ".json")
        if not path.exists():
            raise ValueError("worker inputs changed since the last failure and no frozen trial exists; record a current trial")
        frozen_trial = json.loads(path.read_text())
        if frozen_trial.get("unit") != unit or frozen_trial.get("revision") != history[-1]["revision"]:
            raise ValueError("frozen trial identity does not match failure history")
        revision = frozen_trial["revision"]
    source = frozen_trial["source"] if frozen_trial else (root / "src" / (unit.upper() + ".PAS")).read_text()
    local_rows = tomllib.loads((root / "re/symbols.toml").read_text()).get("routine", [])
    local_name = next((r["name"] for r in local_rows if r["id"] == row["id"]), row["name"])
    if frozen_trial:
        local_name = frozen_trial.get("names", {}).get(row["id"], local_name)
    match = re.search(r"^(?:\{@stub\}\s*)?(?:procedure|function)\s+%s\b.*?(?=^(?:procedure|function)\s|\Z)" %
                      re.escape(local_name), source, re.M | re.S)
    source_excerpt = match[0] if match else source
    key = hashlib.sha256((row["id"] + category + revision).encode()).hexdigest()
    current = [c for c in cases() if c["run_id"] == p["run_id"]]
    if any(c["problem_key"] == key for c in current):
        raise ValueError("this problem revision already has a consultation; no recursive retries")
    if len(current) >= p["max_cases"]:
        raise ValueError("expert case count exhausted for this run")
    try:
        sample = meter.snapshot(expert)
    except (ValueError, OSError):
        freeze("usage unavailable before consultation")
        raise
    budget(p, sample)                      # queued requests are free; reserve money atomically at take
    text = "\n".join(learning.brief(unit, question, common.main_checkout()))
    case = dict(case_id="case-" + uuid.uuid4().hex, state="queued", run_id=p["run_id"],
        requester=agent, unit=unit, routine=row["id"], name=row["name"], category=category, question=question,
        problem_key=key, revision=revision, base=common.git("rev-parse", "main"), history=history,
        learning=text[:18000], source_excerpt=source_excerpt[:16000], source_name=local_name,
        source_origin=("frozen recorded FAILED trial; current source changed" if frozen_trial else
                       "frozen worker worktree snapshot (may be uncommitted)") + "; advice is not proof",
        source_changed_since_trial=bool(frozen_trial),
        source_truncated=len(source_excerpt) > 16000,
        allocation_usd=p["case_usd"], expert_id=p["expert_id"], created=time.time())
    write_case(case)
    control.event("expert-requested", agent=agent, case_id=case["case_id"], unit=unit, routine=row["id"],
                  allocation_usd=p["case_usd"])
    return case


def take(agent: str) -> dict | None:
    actor = identity.ensure(agent, "expert")
    control.admit()
    p = policy()
    if actor["agent_id"] != p["expert_id"]:
        raise ValueError("only the one approved expert can take cases")
    active = [c for c in cases() if c["state"] in ("claimed", "expired", "usage-unknown")]
    if active:
        if active[0]["state"] == "claimed" and time.time() > active[0]["deadline"]:
            active[0]["state"] = "expired"
            write_case(active[0])
            freeze("case deadline expired; settle measured usage before resuming", active[0]["case_id"], "deadline")
        raise ValueError("one case is already active or unsettled; never claim another")
    try:
        sample = meter.snapshot(actor)
    except (ValueError, OSError):
        freeze("usage unavailable before taking a case")
        raise
    budget(p, sample)
    queued = sorted((c for c in cases() if c["state"] == "queued" and c["run_id"] == p["run_id"]), key=lambda c: c["created"])
    if not queued:
        return None
    try:
        budget(p, sample, p["case_usd"])
    except ValueError:
        if not p.get("frozen"):
            freeze("insufficient run allocation for another case", kind="overage")
        raise
    case = queued[0]
    case.update(state="claimed", started=time.time(), deadline=time.time() + p["deadline_seconds"], meter_start=sample)
    write_case(case)
    meter.observe(agent, sample)
    control.event("expert-taken", agent=agent, case_id=case["case_id"], unit=case["unit"], routine=case["routine"])
    return case


def step(agent: str, case_id: str) -> bool:
    case = get_case(case_id)
    actor = identity.ensure(agent, "expert")
    if case["expert_id"] != actor["agent_id"] or case["state"] != "claimed":
        return False
    if control.state()["state"] in ("paused", "stopped") or time.time() > case["deadline"]:
        case["state"] = "expired"
        write_case(case)
        freeze("case paused/stopped or deadline expired; finish with measured usage, no more reasoning", case_id, "deadline")
        return False
    p = policy()
    try:
        sample = meter.snapshot(actor)
        if meter.delta(case["meter_start"], sample)["cost_usd"] >= case["allocation_usd"]:
            freeze("case allocation reached; stop reasoning and settle the case", case_id, "overage")
            return False
        budget(p, sample)
        meter.observe(agent, sample)
    except (ValueError, OSError):
        freeze("usage unavailable or budget exhausted during the case", case_id)
        return False
    return True


def finish(agent: str, case_id: str, response: dict) -> dict:
    case = get_case(case_id)
    actor = identity.ensure(agent, "expert")
    if case["expert_id"] != actor["agent_id"] or case["state"] not in ("claimed", "expired", "usage-unknown"):
        raise ValueError("case is not owned and unsettled for this expert")
    if not isinstance(response, dict) or len(json.dumps(response)) > 16000 or \
            not isinstance(response.get("diagnosis"), str) or not response["diagnosis"].strip() or \
            not isinstance(response.get("evidence"), list) or not response["evidence"] or \
            any(not isinstance(e, str) or not e.strip() or len(e) > 500 for e in response["evidence"]):
        raise ValueError("bounded response needs a diagnosis and evidence; no verdict or source edits")
    if set(response) - {"diagnosis", "evidence", "suggested_probes", "learning_ids", "requires_human"}:
        raise ValueError("expert response cannot contain approvals, verdicts or executable instructions")
    if not isinstance(response.get("requires_human", False), bool):
        raise ValueError("requires_human must be Boolean, never an approval")
    probes = response.get("suggested_probes", [])
    if not isinstance(probes, list) or len(probes) > 5 or any(not isinstance(p, str) or len(p) > 2000 for p in probes):
        raise ValueError("suggest at most five small probes; the decompiler proves them")
    try:
        sample = meter.snapshot(actor)
        usage = meter.delta(case["meter_start"], sample)
    except (ValueError, OSError):
        case.update(state="usage-unknown", response=response)
        write_case(case)
        freeze("usage unknown at finish; no further consultation until a trusted meter is restored", case_id)
        raise
    case.update(state="completed", response=response, finished=time.time(), cost_usd=usage["cost_usd"],
                meter_end=sample, expired=time.time() > case["deadline"])
    write_case(case)
    meter.observe(agent, sample)
    p = policy()
    if usage["cost_usd"] > case["allocation_usd"] or meter.delta(p["baseline"], sample)["cost_usd"] >= p["run_usd"]:
        freeze("measured allocation exceeded or run spend reached; provider cap must enforce in-flight billing", case_id, "overage")
    elif p.get("frozen_case") == case_id and p.get("frozen_kind") != "overage":
        p.update(frozen=None, frozen_case=None, frozen_kind=None)
        common.atomic_write(directory() / "policy.json", json.dumps(p, sort_keys=True) + "\n")
    control.event("expert-completed", agent=agent, case_id=case_id, cost_usd=usage["cost_usd"], expired=case["expired"])
    return case


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("command", choices=("budget", "request", "take", "step", "finish", "list", "result", "scan", "candidates"))
    ap.add_argument("--agent", default="")
    ap.add_argument("--unit", default="")
    ap.add_argument("--fn", default="")
    ap.add_argument("--category", choices=("codegen", "review"), default="codegen")
    ap.add_argument("--question", default="")
    ap.add_argument("--case", default="")
    ap.add_argument("--response")
    ap.add_argument("--operator", action="store_true")
    ap.add_argument("--billing-cap-ref", default="")
    ap.add_argument("--reason", default="")
    ap.add_argument("--wait", type=int, default=0, help="deterministic wait, at most 300 seconds; no model polling")
    a = ap.parse_args(argv)
    try:
        if a.command == "list":
            print(json.dumps([{k: c.get(k) for k in ("case_id", "state", "run_id", "unit", "routine",
                             "category", "allocation_usd", "cost_usd", "deadline")} for c in cases()], sort_keys=True, indent=2))
            return 0
        if a.command == "result":
            case = get_case(a.case)
            print(json.dumps({k: case.get(k) for k in ("case_id", "state", "unit", "routine", "revision",
                             "base", "response", "expired", "cost_usd")}, sort_keys=True, indent=2))
            return 0
        if a.command == "candidates":
            print(json.dumps(candidates(), sort_keys=True, indent=2))
            return 0
        if a.command == "take" and not 0 <= a.wait <= 300:
            raise ValueError("WAIT must be 0..300 seconds")
        until = time.monotonic() + a.wait
        while True:
            with control.coordination_lock():
                if a.command == "budget":
                    if not a.operator:
                        raise ValueError("only the human configures an expert budget with OPERATOR=1")
                    result = configure(a.agent, a.billing_cap_ref, a.reason)
                elif a.command == "request":
                    result = request(a.agent, a.unit, a.fn, a.category, a.question)
                elif a.command == "scan":
                    result = scan(a.agent)
                elif a.command == "take":
                    result = take(a.agent)
                elif a.command == "step":
                    if not step(a.agent, a.case):
                        print("expert: stop reasoning, preserve advice and settle usage")
                        return 3
                    result = {"allowed": True}
                else:
                    result = finish(a.agent, a.case, json.loads(Path(a.response).read_text()))
            if result is not None or a.command != "take" or time.monotonic() >= until:
                print(json.dumps(result, sort_keys=True))
                return 0 if result is not None else 1
            time.sleep(min(5, max(0, until - time.monotonic())))
    except (ValueError, RuntimeError, OSError, KeyError) as e:
        print("expert: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
