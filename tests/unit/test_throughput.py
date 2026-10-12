"""Shared learning, attribution, cache and expert budgets over disposable state, with no model calls."""
import copy
import json
import math
import subprocess
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/agent"))
import activity
import cache
import common
import control
import expert
import identity
import learning
import meter
import performance
import safety
from test_agent_safety import repo, git_at, commit  # isolated Git fixture, not the live clone


def test_identity_is_immutable_and_label_reuse_does_not_rewrite_history(repo):
    a = identity.register("worker", "tooling", "test", "provider/first", "session-1")
    b = identity.register("worker", "tooling", "test", "provider/second", "session-2")
    assert a["agent_id"] != b["agent_id"]
    assert identity.profile("worker")["model"] == "provider/second"
    assert identity.context("worker", agent_id=a["agent_id"])["model"] == "provider/first"
    identity.register(a["agent_id"], "tooling", "test", "provider/other", "session-3")
    assert identity.by_id(a["agent_id"])["model"] == "provider/first"  # separate id/name namespaces


def test_identity_requires_actual_metadata_and_refuses_active_label_replacement(repo):
    with pytest.raises(ValueError, match="register"):
        identity.ensure("new-worker", "decompiler")
    actor = identity.profile("dec-1")
    common.try_lock("ovl00", "agent = dec-1\nbranch = unit/ovl00\n")
    with pytest.raises(ValueError, match="locked"):
        identity.register("dec-1", "decompiler", "test", "provider/other", "new-session")
    assert identity.profile("dec-1")["agent_id"] == actor["agent_id"]


def test_control_events_capture_exact_harness_model_and_incarnation(repo):
    actor = identity.profile("dec-1")
    control.event("example", agent="dec-1")
    event = performance.events()[-1]
    assert event["agent_id"] == actor["agent_id"]
    assert event["model"] == "test/model" and event["harness"] == "test-harness"
    assert event["session"] == "test-session" and event["event_id"]


def test_shared_directory_lookup_is_cached_per_root_not_repeated_for_every_event(repo, monkeypatch):
    original = common.git
    calls = []
    def counted(*args, **kwargs):
        if args[:2] == ("rev-parse", "--git-common-dir"):
            calls.append(args)
        return original(*args, **kwargs)
    common._common_dir.cache_clear()
    monkeypatch.setattr(common, "git", counted)
    first = common.common_dir()
    for _ in range(10):
        assert common.common_dir() == first
    assert len(calls) == 1


def test_claim_freezes_identity_and_assigns_unique_task_id(repo):
    import claim
    assert claim.main(["--agent", "dec-1", "--unit", "ovl00"]) == 0
    record = common.fields(common.lock_path("ovl00").read_text())
    assert record["agent_id"] == identity.profile("dec-1")["agent_id"]
    assert len(record["task_id"]) == 32
    snapshot = json.loads((common.common_dir() / "poolrad-tasks" / (record["task_id"] + ".json")).read_text())
    assert snapshot["base"] == git_at(repo, "rev-parse", "main")


def test_unknown_usage_is_not_zero_and_duplicate_intervals_are_idempotent(repo):
    data = dict(session="test-session", source="test-harness export", interval_id="interval-1",
                cost_usd=0.3, tokens={"input": 100, "output": 20})
    identity.usage("dec-1", data)
    identity.usage("dec-1", data)
    report = performance.summarize(performance.events())
    assert report["agents"][0]["cost_usd"] == 0.3
    with pytest.raises(ValueError):
        identity.usage("dec-1", {**data, "cost_usd": None})
    with pytest.raises(ValueError):
        identity.usage("dec-1", {**data, "cost_usd": 0.8})
    with pytest.raises(ValueError):
        identity.usage("dec-1", {**data, "event": "check-passed"})
    unknown = performance.summarize([{"event": "claim", "agent": "old"}])["agents"][0]
    assert unknown["cost_usd"] is None and unknown["model"] is None


def test_meter_uses_documented_read_only_opencode_get_without_model_prompt(repo, monkeypatch):
    actor = dict(session="ses_example", model="openai/example", harness="opencode", variant="high")
    calls = []
    class Result:
        returncode = 0
        stdout = json.dumps({"data": {"id": "ses_example", "model": {"providerID": "openai", "id": "example", "variant": "high"},
            "cost": 1.2, "tokens": {"input": 100, "output": 10, "reasoning": 5, "cache": {"read": 20, "write": 0}}}})
    def run(command, **kwargs):
        calls.append(command)
        return Result()
    monkeypatch.setattr(meter.subprocess, "run", run)
    data = meter.opencode(actor)
    assert calls == [["opencode", "api", "get", "/api/session/ses_example"]]
    assert data["cost_usd"] == 1.2 and data["tokens"]["cache_read"] == 20


def test_meter_refuses_stale_missing_or_regressing_cost(repo):
    actor = identity.profile("dec-1")
    sample = dict(session=actor["session"], model=actor["model"], source="trusted bridge",
                  cost_usd=1.0, observed_at=time.time(), tokens={"input": 100, "output": 10})
    assert meter.validate(sample, actor) == sample
    for cost in (None, -1, float("nan"), True):
        with pytest.raises(ValueError):
            meter.validate({**sample, "cost_usd": cost}, actor)
    with pytest.raises(ValueError):
        meter.validate({**sample, "observed_at": time.time() - 300}, actor)
    with pytest.raises(ValueError):
        meter.delta(sample, {**sample, "cost_usd": 0.9})


def test_performance_counts_checks_without_double_counting_instrumented_match():
    rows = [dict(event="activity", agent="a", agent_id="id", tool="match", seconds=2, check_id="check", returncode=0),
            dict(event="check-passed", agent="a", agent_id="id", check_id="check", seconds={"match": 2, "tests": 3, "golden": 4})]
    result = performance.summarize(rows)["agents"][0]
    assert result["tool_seconds"] == 9 and result["tools"]["check.golden"] == 4


def test_activity_extracts_real_code_bytes_and_named_differences():
    output = "MATCH   Foo ovl00:0000 25 bytes code, 3 pool, 2 address fields\nDIFF    Bar ovl00:0042 wrong global\n"
    result = activity.results(output)
    assert result["matched"] == 1 and result["code_bytes"] == 25 and result["pool_bytes"] == 3
    assert result["failed"][0]["routine"] == "ovl00:0042"


def test_learning_includes_known_fixes_not_just_generic_reading_instructions():
    text = "\n".join(learning.brief("ovl28", "frame string with", ROOT))
    assert "WITH placement" in text and "LoadDaxBlock" in text
    assert "docs/reference/prior-art.md" in text and "read-only" in text
    assert "Read `docs/design/WHITEPAPER.md:" in text
    assert "8 words" not in text                         # a retrieval brief, not generic style boilerplate


def test_lesson_requires_durable_evidence_not_ignored_build_logs(repo):
    directory = repo / "re/learnings"
    directory.mkdir()
    (repo / "build").mkdir()
    (repo / "build/log.md").write_text("ephemeral")
    (directory / "ovl00.toml").write_text('[[lesson]]\nid="a"\nconfidence="V"\nunits=["ovl00"]\ntags=["frame"]\ntitle="x"\nlesson="x"\nevidence=["build/log.md"]\n')
    with pytest.raises(ValueError, match="durable"):
        learning.lessons(repo)


def test_stale_worker_reads_new_lessons_and_whitepaper_from_accepted_main(repo):
    original = git_at(repo, "rev-parse", "HEAD")
    (repo / "re/learnings").mkdir()
    (repo / "re/learnings/ovl00.toml").write_text('[[lesson]]\nid="new-fix"\nconfidence="V"\nunits=["ovl00"]\ntags=["frame"]\ntitle="new accepted fix"\nlesson="Use the accepted clue, not a stale branch."\nevidence=["src/OVL00.PAS"]\n')
    (repo / "docs/design").mkdir(parents=True)
    (repo / "docs/design/WHITEPAPER.md").write_text("### 5.99 ovl00 new learning\nNew accepted evidence for ovl00.\n")
    commit(repo)
    git_at(repo, "switch", "-qc", "task/stale", original)
    assert not (repo / "re/learnings/ovl00.toml").exists()
    text = "\n".join(learning.brief("ovl00", "frame", repo))
    assert "new accepted fix" in text and "New accepted evidence" in text
    assert "git show main:" in text


def test_packet_disassembly_does_not_stop_at_an_early_return():
    import packet
    # jmp 5; retf (early); nop; nop; retf (real epilogue)
    code = bytes.fromhex("eb03 cb 90 90 cb")
    class Namer:
        def glob(self, off): return "global"
    listing, frame = packet.listing(Namer(), "ovl00", code, {"addr": "ovl00:0000", "size": 6})
    assert any(line.startswith("0005") for line in listing)


def test_golden_cache_ignores_pascal_edits_but_invalidates_original_inputs(repo):
    for path in ("tools/oracle/a.py", "poolrad/game.bin", "tests/sessions/x.keys", "re/units.toml", "re/state.toml"):
        p = repo / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("# original input\n")
    initial = cache.golden_key(repo)
    (repo / "src/OVL00.PAS").write_text("changed Pascal still requires fresh matcher proof")
    assert cache.golden_key(repo) == initial
    for path in ("tools/oracle/a.py", "poolrad/game.bin", "tests/sessions/x.keys", "re/state.toml", "re/units.toml"):
        p = repo / path
        old = p.read_text()
        p.write_text(old + "changed")
        assert cache.golden_key(repo) != initial
        p.write_text(old)
    (repo / "re/symbols.toml").write_text("invalid TOML!")
    with pytest.raises(ValueError):
        cache.golden_key(repo)


def test_golden_cache_expires_and_corruption_or_failed_fresh_recheck_cannot_pass(repo):
    cache.save("key")
    assert cache.hit("key")
    assert not cache.hit("key", time.time() + cache.MAX_AGE + 1)
    (cache.directory() / "key.json").write_text("broken")
    assert not cache.hit("key")
    cache.save("key")
    cache.invalidate("key")
    assert not cache.hit("key")


def test_operator_false_is_not_interpreted_as_approval(repo):
    (repo / "Makefile").write_text((ROOT / "Makefile").read_text())
    output = git_at(repo, "status", "--short")  # keep the fixture explicitly local
    result = subprocess.run(["make", "-s", "-n", "agent-control", "STATE=running", "OPERATOR=0", "REASON=test"],
                            cwd=repo, capture_output=True, text=True)
    assert result.returncode == 0 and "--operator" not in result.stdout


@pytest.fixture
def expert_run(repo, monkeypatch):
    common.atomic_write(common.common_dir() / "poolrad-control.json", '{"state":"running","run_id":"test-run","reason":"test"}')
    actor = identity.register("expert-1", "expert", "test-harness", "test/model", "expert-session")
    identity.register("orch", "orchestrator", "test-harness", "test/controller", "orch-session")
    sample = dict(session=actor["session"], model=actor["model"], cost_usd=0.0, source="trusted test meter",
                  observed_at=time.time(), tokens={"input": 0, "output": 0})
    monkeypatch.setattr(meter, "snapshot", lambda profile: copy.deepcopy(sample))
    with control.coordination_lock():
        expert.configure("expert-1", "test provider cap: 50 USD", "human fixture approval")
    current = activity.source_revision(repo)
    for revision in ("old-a", "old-b", current):
        control.event("activity", agent="dec-1", tool="match", unit="ovl00", args=["ovl00", "--routine", "Foo"],
                      revision=revision, returncode=1, failed=[dict(routine="ovl00:0000", name="Foo", detail="frame differs")])
    return repo, sample


def queue_one():
    with control.coordination_lock():
        return expert.request("orch", "ovl00", "Foo", "codegen", "Why does the frame differ?")


def test_expert_is_a_queue_not_a_launcher_and_only_one_active_case(expert_run):
    repo, sample = expert_run
    case = queue_one()
    assert case["state"] == "queued" and case["allocation_usd"] == 10
    with control.coordination_lock():
        taken = expert.take("expert-1")
    assert taken["case_id"] == case["case_id"]
    assert 890 <= taken["deadline"] - time.time() <= 900
    with pytest.raises(ValueError, match="already active"):
        expert.take("expert-1")
    assert "source_excerpt" in taken and "advice is not proof" in taken["source_origin"]


def test_expert_refuses_duplicate_revision_and_recursive_consultation(expert_run):
    queue_one()
    with pytest.raises(ValueError, match="already has"):
        queue_one()
    with pytest.raises(ValueError, match="not orchestrator"):
        expert.request("expert-1", "ovl00", "Foo", "codegen", "delegate to another expert")


def test_expert_requests_require_recorded_failure_history(expert_run):
    (common.common_dir() / "poolrad-events.jsonl").write_text("")
    with pytest.raises(ValueError, match="3 recorded"):
        queue_one()


def test_expert_refuses_changed_inputs_and_known_human_decisions(expert_run):
    repo, _sample = expert_run
    (repo / "src/OVL00.PAS").write_text("new revision, not yet tested")
    with pytest.raises(ValueError, match="inputs changed"):
        queue_one()
    symbols = repo / "re/symbols.toml"
    symbols.write_text(symbols.read_text() + 'notes = "waiting for the human"\n')
    with pytest.raises(ValueError, match="human decision"):
        queue_one()


def test_expert_can_use_preserved_failed_draft_after_worker_stubs_it_for_handoff(expert_run):
    repo, _sample = expert_run
    revision = activity.source_revision(repo)
    directory = common.common_dir() / "poolrad-trials"
    directory.mkdir()
    common.atomic_write(directory / ("ovl00-" + revision + ".json"), json.dumps(dict(
        unit="ovl00", revision=revision, source="procedure Foo; begin { failed draft } end;", names={"ovl00:0000": "Foo"})))
    (repo / "src/OVL00.PAS").write_text("{ stubbed for safe hand-off }")
    case = queue_one()
    assert "failed draft" in case["source_excerpt"] and case["source_changed_since_trial"]
    assert "FAILED trial" in case["source_origin"]


def test_expert_missing_usage_freezes_dispatch_instead_of_treating_it_as_free(expert_run, monkeypatch):
    def unavailable(profile): raise ValueError("no meter")
    monkeypatch.setattr(meter, "snapshot", unavailable)
    with pytest.raises(ValueError): queue_one()
    assert expert.policy()["frozen"]
    assert not expert.cases()


def test_expert_deadline_retains_allocation_until_usage_is_settled(expert_run):
    _repo, sample = expert_run
    case = queue_one()
    with control.coordination_lock(): taken = expert.take("expert-1")
    taken["deadline"] = time.time() - 1
    expert.write_case(taken)
    assert not expert.step("expert-1", case["case_id"])
    assert expert.get_case(case["case_id"])["state"] == "expired"
    sample.update(cost_usd=2.0, tokens={"input": 100, "output": 10})
    with control.coordination_lock():
        result = expert.finish("expert-1", case["case_id"], {"diagnosis": "use a small probe", "evidence": ["src/OVL00.PAS"]})
    assert result["expired"] and result["cost_usd"] == 2.0
    assert expert.policy()["frozen"] is None


def test_expert_overage_and_unknown_finish_block_further_spending(expert_run, monkeypatch):
    _repo, sample = expert_run
    case = queue_one()
    with control.coordination_lock(): expert.take("expert-1")
    sample.update(cost_usd=10.1, tokens={"input": 100, "output": 10})
    with control.coordination_lock():
        expert.finish("expert-1", case["case_id"], {"diagnosis": "bounded advice", "evidence": ["src/OVL00.PAS"]})
    assert expert.policy()["frozen_kind"] == "overage"
    assert not expert.step("expert-1", case["case_id"])


def test_unknown_cost_at_finish_keeps_case_unsettled_and_prevents_replacement(expert_run, monkeypatch):
    case = queue_one()
    with control.coordination_lock(): expert.take("expert-1")
    def missing(profile): raise ValueError("missing actual cost")
    monkeypatch.setattr(meter, "snapshot", missing)
    with pytest.raises(ValueError):
        expert.finish("expert-1", case["case_id"], {"diagnosis": "partial advice", "evidence": ["src/OVL00.PAS"]})
    assert expert.get_case(case["case_id"])["state"] == "usage-unknown"
    with pytest.raises(ValueError, match="unsettled"):
        identity.register("expert-1", "expert", "test-harness", "other/model", "replacement-session")
    with pytest.raises(ValueError, match="already active"):
        expert.take("expert-1")


def test_deterministic_expert_scan_queues_existing_worker_advice_without_new_sessions(expert_run):
    assert expert.candidates()[0]["routine"] == "ovl00:0000"
    with control.coordination_lock(): result = expert.scan("orch")
    assert result[0]["case_id"] and len(expert.cases()) == 1
    with control.coordination_lock(): result = expert.scan("orch")
    assert "already has" in result[0]["held"] and len(expert.cases()) == 1


def test_expert_cannot_reset_budget_within_a_run(expert_run):
    with pytest.raises(ValueError, match="already has a budget"):
        expert.configure("expert-1", "cap", "try to reset")


def test_expert_response_cannot_write_verdicts_or_approvals(expert_run):
    case = queue_one()
    with control.coordination_lock(): expert.take("expert-1")
    with pytest.raises(ValueError, match="cannot contain approvals"):
        expert.finish("expert-1", case["case_id"], {"diagnosis": "x", "evidence": ["src/OVL00.PAS"], "level": "L2"})


def test_expert_queue_keeps_conservative_case_and_money_limits(expert_run):
    for i in range(5):
        case = {"case_id": "case-" + ("%032x" % i), "state": "queued", "run_id": "test-run",
                "problem_key": "different-%d" % i, "allocation_usd": 10, "created": time.time()}
        expert.write_case(case)
    with pytest.raises(ValueError, match="case count exhausted"):
        queue_one()
    policy = expert.policy()
    sample = {**policy["baseline"], "cost_usd": 45.0}
    with pytest.raises(ValueError, match="allocation exhausted"):
        expert.budget(policy, sample, 10)


def test_explicit_scoped_spec_approval_does_not_allow_other_reserved_files(repo):
    git_at(repo, "switch", "-qc", "task/authorized")
    (repo / "docs/spec").mkdir(parents=True)
    (repo / "docs/spec/SPEC.md").write_text("expert role documentation")
    (repo / "re/state.toml").write_text("still reserved")
    commit(repo)
    directory = common.common_dir() / "poolrad-task-approvals"
    directory.mkdir()
    common.atomic_write(directory / "authorized.json", json.dumps(dict(branch="task/authorized", paths=["docs/spec/SPEC.md"],
        base=git_at(repo, "rev-parse", "main"), reason="human approved expert role only")))
    findings = safety.branch_findings()
    assert not any("SPEC.md" in f for f in findings) and any("state.toml" in f for f in findings)
