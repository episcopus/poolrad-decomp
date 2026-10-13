"""Coordination guards use disposable Git repositories, never the live clone's shared state."""
import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/agent"))
import check
import claim
import common
import control
import handoff
import heartbeat
import safety
import unlock
import identity


def git_at(path, *args):
    return subprocess.check_output(["git", *args], cwd=path, text=True).strip()


def commit(path, message="fixture"):
    git_at(path, "add", ".")
    git_at(path, "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
           "commit", "-qm", message)
    return git_at(path, "rev-parse", "HEAD")


@pytest.fixture
def repo(tmp_path, monkeypatch):
    main = tmp_path / "clone"
    main.mkdir()
    git_at(main, "init", "-q", "-b", "main")
    (main / "re").mkdir()
    (main / "src").mkdir()
    (main / "work").mkdir()
    (main / "re/symbols.toml").write_text('[[routine]]\nid = "ovl00:0000"\nunit = "ovl00"\nname = "Foo"\nlevel = "none"\n')
    (main / "re/dseg.toml").write_text("")
    (main / "re/renames.toml").write_text("")
    (main / "src/POOLVARS.PAS").write_text("unit POOLVARS;\ninterface\nvar\n  First: Byte;\nimplementation\nend.\n")
    (main / "src/OVL00.PAS").write_text("unit OVL00;\ninterface\nimplementation\nend.\n")
    (main / "work/queue.toml").write_text('[[unit]]\nid = "ovl00"\n')
    commit(main)
    monkeypatch.setattr(common, "ROOT", main)
    monkeypatch.setattr(handoff, "CHANGELOG", main / "CHANGELOG.md")
    (main / "CHANGELOG.md").write_text("| Date | Section | Change | Evidence |\n|---|---|---|---|\n")
    monkeypatch.chdir(main)
    # The fixture simulates an explicitly admitted human run; the real clone is never admitted here.
    common.atomic_write(common.common_dir() / "poolrad-control.json", '{"state":"running","reason":"test fixture"}\n')
    identity.register("dec-1", "decompiler", "test-harness", "test/model", "test-session")
    return main


@pytest.mark.parametrize("name", ["../main", "/tmp/x", "-option", "agent\nstate = stopped", "", "A", "a" * 81])
def test_names_cannot_escape_coordination_directories(name):
    with pytest.raises(ValueError):
        common.identifier(name)


def test_duplicate_fields_are_not_silently_reinterpreted():
    with pytest.raises(ValueError, match="duplicate"):
        common.fields("agent = a\nagent = orch\n")


def test_control_requires_explicit_human_acknowledgement_and_main(repo):
    path = common.common_dir() / "poolrad-control.json"
    original = path.read_bytes()
    assert control.main(["--state", "stopped", "--reason", "test"]) == 2
    assert path.read_bytes() == original
    assert control.main(["--state", "draining", "--operator", "--reason", "human stop"]) == 0
    assert control.main(["--step", "--agent", "dec-1"]) == 0
    assert claim.main(["--agent", "dec-1", "--unit", "ovl00"]) == 2
    assert not common.lock_path("ovl00").exists()
    assert control.main(["--state", "paused", "--operator", "--reason", "human pause"]) == 0
    assert control.main(["--step", "--agent", "dec-1"]) == 3
    assert control.main(["--step", "--state", "running", "--agent", "dec-1"]) == 2


def test_corrupt_control_fails_closed(repo):
    (common.common_dir() / "poolrad-control.json").write_text('{"state": "unknown"}')
    assert claim.main(["--agent", "dec-1", "--unit", "ovl00"]) == 2
    assert not common.lock_path("ovl00").exists()


def test_missing_operator_admission_refuses_claims_and_raw_locks(repo):
    import lock
    (common.common_dir() / "poolrad-control.json").unlink()
    assert control.state()["state"] == "stopped"
    assert claim.main(["--agent", "dec-1", "--unit", "ovl00"]) == 2
    assert lock.main(["ovl00", "--agent", "dec-1"]) == 2
    assert not common.lock_path("ovl00").exists()


def test_claim_refuses_dirty_main_without_stashing_or_resetting(repo):
    source = repo / "src/OVL00.PAS"
    source.write_text(source.read_text() + "{ another agent's uncommitted work }\n")
    before = source.read_bytes()
    assert claim.main(["--agent", "dec-1", "--unit", "ovl00"]) == 1
    assert source.read_bytes() == before
    assert not common.lock_path("ovl00").exists()
    assert git_at(repo, "stash", "list") == ""


def test_claim_checks_existing_worktree_branch_without_overwriting_it(repo):
    wt = repo.parent / "poolrad-worktrees/ovl00"
    wt.parent.mkdir()
    git_at(repo, "worktree", "add", "-q", "-b", "unit/other", str(wt))
    assert claim.main(["--agent", "dec-1", "--unit", "ovl00"]) == 1
    assert git_at(wt, "branch", "--show-current") == "unit/other"
    assert not common.lock_path("ovl00").exists()


def test_pending_handoff_blocks_duplicate_claim(repo):
    directory = handoff.handoff_dir()
    (directory / "ovl00.md").write_text("agent = dec-1\n")
    assert claim.main(["--agent", "dec-2", "--unit", "ovl00"]) == 2
    assert not common.lock_path("ovl00").exists()


def claimed_worktree(repo, monkeypatch):
    assert claim.main(["--agent", "dec-1", "--unit", "ovl00"]) == 0
    wt = repo.parent / "poolrad-worktrees/ovl00"
    monkeypatch.setattr(common, "ROOT", wt)
    monkeypatch.chdir(wt)
    (wt / "src/OVL00.PAS").write_text("unit OVL00;\ninterface\nimplementation\n{ work }\nend.\n")
    commit(wt)
    monkeypatch.setattr(handoff, "unmatched", lambda unit: "")
    return wt


def test_handoff_requires_owner_and_correct_branch_and_pins_full_sha(repo, monkeypatch):
    wt = claimed_worktree(repo, monkeypatch)
    args = ["--unit", "ovl00", "--state", "partial", "--note", "done"]
    assert handoff.main([*args, "--agent", "dec-2"]) == 2
    assert handoff.main([*args, "--agent", "dec-1", "--state", "review-passed"]) == 2
    assert handoff.main([*args, "--agent", "dec-1"]) == 0
    record = common.fields((handoff.handoff_dir() / "ovl00.md").read_text())
    assert record["commit"] == git_at(wt, "rev-parse", "HEAD")
    assert len(record["commit"]) == 40
    assert handoff.main([*args, "--agent", "dec-1", "--note", "safe\nagent = orch"]) == 2


def test_handoff_update_does_not_overwrite_another_agents_record(repo, monkeypatch):
    claimed_worktree(repo, monkeypatch)
    path = handoff.handoff_dir() / "ovl00.md"
    text = "agent = dec-2\nbranch = unit/ovl00\ncommit = %s\n" % common.git("rev-parse", "HEAD")
    path.write_text(text)
    assert handoff.main(["--agent", "dec-1", "--unit", "ovl00", "--state", "partial"]) == 2
    assert path.read_text() == text


def test_handoff_refuses_uncommitted_makefile_not_just_source_changes(repo, monkeypatch):
    wt = claimed_worktree(repo, monkeypatch)
    (wt / "Makefile").write_text("# uncommitted tool change\n")
    assert handoff.main(["--agent", "dec-1", "--unit", "ovl00", "--state", "partial"]) == 1
    assert not (handoff.handoff_dir() / "ovl00.md").exists()


def test_handoff_cleanup_requires_merge_and_check_receipt_and_archives(repo, monkeypatch):
    wt = claimed_worktree(repo, monkeypatch)
    assert handoff.main(["--agent", "dec-1", "--unit", "ovl00", "--state", "partial"]) == 0
    assert handoff.main(["--agent", "orch", "--unit", "ovl00", "--done"]) == 2  # worker cannot clean up
    monkeypatch.setattr(common, "ROOT", repo)
    monkeypatch.chdir(repo)
    args = ["--agent", "orch", "--unit", "ovl00", "--done"]
    assert handoff.main(args) == 2                                              # not yet merged
    git_at(repo, "merge", "--ff-only", "unit/ovl00")
    assert handoff.main(args) == 2                                              # not yet checked
    fingerprint = check.fingerprint()
    (check.receipts() / (fingerprint + ".json")).write_text(json.dumps({
        "fingerprint": fingerprint, "stages": [s[0] for s in check.STAGES]}))
    assert handoff.main(args) == 0
    assert not (handoff.handoff_dir() / "ovl00.md").exists()
    assert list((common.common_dir() / "poolrad-handoff-archive").glob("ovl00-*.md"))
    assert wt.exists()                                                           # no cleanup deletes work


def test_a_registered_orchestrator_may_clear_an_escalation(repo):
    identity.register("haiku-orch", "orchestrator", "test-harness", "test/model", "test-session-orch")
    assert handoff.main(["--agent", "dec-1", "--unit", "general", "--state", "escalate", "--note", "question"]) == 0
    key = next(handoff.handoff_dir().glob("escalate-*.md")).stem
    assert handoff.main(["--agent", "dec-1", "--unit", key, "--done", "--decision", "no"]) == 2
    assert handoff.main(["--agent", "haiku-orch", "--unit", key, "--done",
                         "--decision", "human: this label is the orchestrator"]) == 0
    assert not (handoff.handoff_dir() / ("%s.md" % key)).exists()


def test_escalation_cleanup_requires_human_decision(repo):
    assert handoff.main(["--agent", "dec-1", "--unit", "general", "--state", "escalate", "--note", "question"]) == 0
    key = next(handoff.handoff_dir().glob("escalate-*.md")).stem
    args = ["--agent", "orch", "--unit", key, "--done"]
    assert handoff.main(args) == 2
    assert handoff.main([*args, "--decision", "human approved at 12:00 UTC"]) == 0


def test_bad_changelog_does_not_clear_handoff(repo, monkeypatch):
    commit_id = common.git("rev-parse", "HEAD")
    path = handoff.handoff_dir() / "ovl00.md"
    text = "state = complete\ncommit = %s\nchangelog = malformed\n" % commit_id
    path.write_text(text)
    monkeypatch.setattr(check, "require_receipt", lambda: None)
    assert handoff.main(["--agent", "orch", "--unit", "ovl00", "--done"]) == 2
    assert path.read_text() == text


def test_changelog_retry_does_not_duplicate_a_completed_row(repo):
    row = "tools | safety guards | tests"
    handoff.add_changelog_row(row)
    handoff.add_changelog_row(row)
    assert handoff.CHANGELOG.read_text().count("| tools | safety guards | tests |") == 1


def test_unlock_refuses_workers_and_unmerged_work_and_requires_reason(repo, monkeypatch):
    wt = claimed_worktree(repo, monkeypatch)
    assert unlock.main(["ovl00", "--agent", "dec-1"]) == 2
    monkeypatch.setattr(common, "ROOT", repo)
    monkeypatch.chdir(repo)
    assert unlock.main(["ovl00", "--agent", "orch"]) == 2
    assert unlock.main(["ovl00", "--operator", "--force"]) == 2
    before = (wt / "src/OVL00.PAS").read_bytes()
    assert unlock.main(["ovl00", "--operator", "--force", "--reason", "human confirmed stopped"]) == 0
    assert (wt / "src/OVL00.PAS").read_bytes() == before
    assert git_at(wt, "branch", "--show-current") == "unit/ovl00"


def test_unlock_refuses_dirty_worktree_after_merge(repo, monkeypatch):
    wt = claimed_worktree(repo, monkeypatch)
    monkeypatch.setattr(common, "ROOT", repo)
    monkeypatch.chdir(repo)
    git_at(repo, "merge", "--ff-only", "unit/ovl00")
    (wt / "draft.txt").write_text("keep this untracked draft")
    assert unlock.main(["ovl00", "--agent", "orch"]) == 2
    assert common.lock_path("ovl00").exists()


def test_unlock_releases_clean_merged_work_without_deleting_it(repo, monkeypatch):
    wt = claimed_worktree(repo, monkeypatch)
    monkeypatch.setattr(common, "ROOT", repo)
    monkeypatch.chdir(repo)
    git_at(repo, "merge", "--ff-only", "unit/ovl00")
    assert unlock.main(["ovl00", "--agent", "orch"]) == 0
    assert not common.lock_path("ovl00").exists() and wt.exists()


def test_missing_branch_does_not_make_a_lock_releasable(repo):
    common.try_lock("ovl00", "agent = dec-1\nbranch = unit/missing\n")
    assert unlock.main(["ovl00", "--agent", "orch"]) == 2
    assert common.lock_path("ovl00").exists()


def test_table_preservation_catches_missing_records_fields_and_evidence():
    old = {"a": {"id": "a", "level": "none", "evidence": ["base"]}}
    left = {"a": {"id": "a", "level": "L2", "evidence": ["base", "match"]}}
    right = {**old, "b": {"id": "b", "level": "L2"}}
    merged = {"a": {"id": "a", "evidence": ["base"]}}
    findings = safety.table_findings("symbols", old, left, right, merged)
    assert any("entry b" in f for f in findings)
    assert any("a.level" in f for f in findings)
    assert any("a.evidence" in f for f in findings)


def test_merge_preservation_distinguishes_explicit_branch_deletion():
    base = {"phantom": {}, "keep": {}}
    left = {**base, "left_added": {}}
    right = {"keep": {}, "right_added": {}}
    assert safety.retained_keys(base, left, right) == {"keep", "left_added", "right_added"}


def test_duplicate_registry_ids_fail_closed():
    with pytest.raises(ValueError):
        safety.entries('[[routine]]\nid="a"\n[[routine]]\nid="a"\n', "routine", "id")


def test_real_merge_guard_catches_lost_globals_before_commit(repo, monkeypatch):
    base = common.git("rev-parse", "HEAD")
    git_at(repo, "switch", "-qc", "unit/left")
    path = repo / "src/POOLVARS.PAS"
    path.write_text(path.read_text().replace("  First: Byte;", "  First: Byte;\n  LeftAdded: Byte;"))
    left = commit(repo)
    git_at(repo, "switch", "-qc", "unit/right", base)
    path.write_text(path.read_text().replace("  First: Byte;", "  First: Byte;\n  RightAdded: Byte;"))
    right = commit(repo)
    git_at(repo, "switch", "-q", "unit/left")
    result = subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                             "merge", "--no-commit", right], cwd=repo, capture_output=True)
    assert result.returncode == 1                                                 # expected conflict
    path.write_text(safety.blob(base, "src/POOLVARS.PAS"))                         # lossy resolution
    git_at(repo, "add", "src/POOLVARS.PAS")
    findings = safety.merge_findings(staged=True)
    assert any("leftadded" in f for f in findings) and any("rightadded" in f for f in findings)
    path.write_text(path.read_text().replace("  First: Byte;", "  First: Byte;\n  LeftAdded: Byte;\n  RightAdded: Byte;"))
    git_at(repo, "add", "src/POOLVARS.PAS")
    assert safety.merge_findings(staged=True) == []


def test_fingerprint_invalidates_changed_source_and_added_local_files(repo):
    first = check.fingerprint()
    source = repo / "src/OVL00.PAS"
    original = source.read_text()
    source.write_text(original + "{ changed }\n")
    assert check.fingerprint() != first
    source.write_text(original)
    assert check.fingerprint() == first
    (repo / "src/LOCAL.PAS").write_text("unit LOCAL;")
    assert check.fingerprint() != first


def test_failed_or_concurrently_modified_checks_never_write_receipt(repo, monkeypatch):
    class Result:
        returncode = 1
    monkeypatch.setattr(check, "run_stage", lambda *a, **kw: Result())
    # common.git also uses subprocess.run: isolate its reads before replacing the runner.
    monkeypatch.setattr(common, "git", lambda *a, **kw: "HEAD")
    monkeypatch.setattr(common, "common_dir", lambda: repo / ".git")
    values = iter(["before", "after"])
    monkeypatch.setattr(check, "fingerprint", lambda: next(values))
    assert check.main() == 1
    Result.returncode = 0
    values = iter(["before", "after"])
    assert check.main() == 2


def test_failed_recheck_invalidates_previous_passing_receipt(repo, monkeypatch):
    current = check.fingerprint()
    path = check.receipts() / (current + ".json")
    path.write_text(json.dumps({"fingerprint": current, "stages": [s[0] for s in check.STAGES]}))
    monkeypatch.setattr(common, "common_dir", lambda: repo / ".git")
    monkeypatch.setattr(check, "fingerprint", lambda: current)
    class Result:
        returncode = 1
    monkeypatch.setattr(check, "run_stage", lambda *a, **kw: Result())
    assert check.main() == 1 and not path.exists()


def test_receipt_is_unusable_after_an_input_changes(repo):
    initial = check.fingerprint()
    path = check.receipts() / (initial + ".json")
    path.write_text(json.dumps({"fingerprint": initial, "stages": [s[0] for s in check.STAGES]}))
    check.require_receipt()
    (repo / "src/OVL00.PAS").write_text("changed after checking")
    with pytest.raises(ValueError, match="no passing"):
        check.require_receipt()


def test_pending_handoff_is_skipped_by_both_queues(repo):
    import next as nxt
    directory = handoff.handoff_dir()
    (directory / "ovl00.md").write_text("state = partial\n")
    assert nxt.next_unit() is None
    (repo / "re/symbols.toml").write_text('[[routine]]\nid="ovl00:0000"\nunit="ovl00"\nlevel="L2"\n')
    (directory / "review-ovl00.md").write_text("state = review-passed\n")
    assert nxt.next_review() is None


def test_global_aliases_can_share_an_offset():
    rows = '[[global]]\nname="Base"\noffset=2\n[[global]]\nname="Alias"\noffset=2\n'
    assert len(safety.entries(rows, "global", "name")) == 2


def test_git_errors_in_merge_inputs_never_count_as_empty_files(repo):
    with pytest.raises(RuntimeError):
        safety.blob("missing-revision", "re/symbols.toml")
    assert safety.blob("HEAD", "re/not-present.toml") == ""


def test_branch_ownership_refuses_decompiler_tool_changes(repo):
    git_at(repo, "switch", "-qc", "unit/ovl00")
    (repo / "tools").mkdir()
    (repo / "tools/fix.py").write_text("# must be a tooling task\n")
    commit(repo)
    assert any("tooling" in f for f in safety.branch_findings())


def test_heartbeat_updates_are_atomic_and_do_not_inject_fields(repo):
    path = heartbeat.beat("dec-1", "first\nstate = stopped")
    record = common.fields(path.read_text())
    assert record["state"] == "working"
    assert "state = stopped" in record["note"]
    heartbeat.beat("dec-1", "human stopped", done=True)
    assert not list(path.parent.glob(".dec-1.txt.*"))


def test_make_keeps_dollars_quotes_and_shell_metacharacters_literal(repo):
    (repo / "Makefile").write_text((ROOT / "Makefile").read_text())
    note = 'sound {$L SOUND.OBJ}, "quoted", apostrophe\'s; $(touch forbidden) `touch forbidden`'
    result = subprocess.run(["make", "-s", "-n", "handoff", "AGENT=dec-1", "UNIT=ovl00",
                             "STATE=escalate", "NOTE=" + note], cwd=repo, capture_output=True, text=True)
    assert result.returncode == 0 and "{$L SOUND.OBJ}" in result.stdout
    import shlex
    args = shlex.split(result.stdout.strip())
    assert args[args.index("--note") + 1] == note
    assert not (repo / "forbidden").exists()
