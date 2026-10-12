"""Agent coordination tools (SPEC 9.4): shared locks, review-pass."""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/agent"))
sys.path.insert(0, str(ROOT / "tools/match"))

import common  # noqa: E402
import review  # noqa: E402


def test_a_lock_is_shared_and_atomic():
    unit = "zz_test_lock"
    common.lock_path(unit).unlink(missing_ok=True)
    try:
        assert common.try_lock(unit, "agent = a\n")
        assert not common.try_lock(unit, "agent = b\n")          # the second claim fails
        assert common.lock_path(unit).read_text() == "agent = a\n"
        assert common.lock_dir().parent == common.common_dir()   # in the clone's git directory
    finally:
        common.lock_path(unit).unlink(missing_ok=True)


def write_review(tmp_path, body):
    d = tmp_path / "reviews"
    d.mkdir(exist_ok=True)
    (d / "res04.md").write_text(body)
    return d


def test_review_pass_refuses_a_self_review_and_open_must_fix(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(review, "REVIEWS", write_review(tmp_path, "decompiler: alice\nreviewer: alice\n"))
    assert review.main(["res04", "--check"]) == 1
    assert "is the decompiler" in capsys.readouterr().out
    monkeypatch.setattr(review, "REVIEWS", write_review(
        tmp_path, "decompiler: alice\nreviewer: bob\n- [ ] must-fix res04_fn_0059: wrong name\n"))
    assert review.main(["res04", "--check"]) == 1
    assert "open finding" in capsys.readouterr().out


@pytest.mark.skipif(not (ROOT / "build/toolchain").exists(), reason="needs Turbo Pascal 6.0 (make tp-pin)")
def test_review_pass_accepts_a_clean_review_of_a_complete_unit(tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(review, "REVIEWS", write_review(
        tmp_path, "decompiler: alice\nreviewer: bob\n- [x] must-fix res04_fn_0059: fixed in abc\n- [ ] note x\n"))
    assert review.main(["res04", "--check"]) == 0
    assert "would record 'passed" in capsys.readouterr().out


def test_a_failed_review_goes_back_to_a_decompiler_not_to_a_reviewer(tmp_path, monkeypatch):
    # Built from a copy of the live registry with every recorded review removed, so it does not depend on
    # which units have been reviewed on main (a merged review used to move the queue and break this test).
    import re
    import next as nxt
    reviews = tmp_path / "work/reviews"
    reviews.mkdir(parents=True)
    (tmp_path / "re").mkdir()
    symbols = (ROOT / "re/symbols.toml").read_text()
    (tmp_path / "re/symbols.toml").write_text(re.sub(r"(?m)^review = .*\n", "", symbols))
    (tmp_path / "work/queue.toml").write_text((ROOT / "work/queue.toml").read_text())
    monkeypatch.setattr(common, "ROOT", tmp_path)
    (tmp_path / "locks").mkdir()
    monkeypatch.setattr(common, "lock_dir", lambda: tmp_path / "locks")
    first = nxt.next_review()[0]                                 # complete, not reviewed
    (reviews / ("%s.md" % first)).write_text("decompiler: a\nreviewer: b\n- [ ] must-fix x: wrong\n")
    assert nxt.next_review()[0] != first                         # waits for the fix
    assert nxt.next_unit()[0] == first and "review failed" in nxt.next_unit()[1]
    (reviews / ("%s.md" % first)).write_text("decompiler: a\nreviewer: b\n- [x] must-fix x: wrong (fixed)\n")
    assert nxt.next_review()[0] == first                         # fixed: back in the review queue


def test_an_escalation_needs_no_commit_and_a_changelog_row_lands_on_done(tmp_path, monkeypatch, capsys):
    import handoff
    import heartbeat
    monkeypatch.setattr(handoff, "handoff_dir", lambda: tmp_path)
    monkeypatch.setattr(heartbeat, "heartbeat_dir", lambda: tmp_path / "beats")
    (tmp_path / "beats").mkdir()
    log = tmp_path / "CHANGELOG.md"
    log.write_text("| Date | Section | Change | Evidence |\n|---|---|---|---|\n| old | x | y | z |\n")
    monkeypatch.setattr(handoff, "CHANGELOG", log)
    assert handoff.main(["--unit", "general", "--agent", "rev-1", "--state", "escalate"]) == 2   # needs a note
    assert handoff.main(["--unit", "general", "--agent", "rev-1", "--state", "escalate",
                         "--note", "matcher accepts X"]) == 0
    esc = [p for p in tmp_path.glob("escalate-general-*.md")]
    assert len(esc) == 1
    handoff.main(["--list"])
    assert "ESCALATION for the human" in capsys.readouterr().out
    (tmp_path / "ovl33.md").write_text("unit = ovl33\nstate = complete\nchangelog = 5.8 | trace | make match\n")
    assert handoff.main(["--unit", "ovl33", "--done"]) == 0
    rows = log.read_text().splitlines()
    assert rows[2].endswith("| 5.8 | trace | make match |") and rows[3] == "| old | x | y | z |"


def test_a_heartbeat_is_shared_and_a_silent_agent_shows_as_quiet(tmp_path, monkeypatch, capsys):
    import datetime as dt
    import heartbeat
    monkeypatch.setattr(heartbeat, "heartbeat_dir", lambda: tmp_path)
    assert heartbeat.main(["--agent", "dec-9", "--note", ""]) == 2               # a note is required
    assert heartbeat.main(["--agent", "dec-9", "--note", "matching ovl34_fn_0000"]) == 0
    assert heartbeat.main(["--agent", "rev-9", "--note", "queue empty", "--done"]) == 0
    later = dt.datetime.now(dt.timezone.utc) + dt.timedelta(minutes=heartbeat.QUIET_MINUTES + 5)
    rows = heartbeat.listing(later)
    assert rows[0].startswith("QUIET") and "dec-9" in rows[0] and "matching ovl34_fn_0000" in rows[0]
    assert rows[1].startswith("stopped") and "rev-9" in rows[1]                # stopped is never quiet
    assert heartbeat.listing()[0].startswith("ok")                            # fresh: not quiet
    assert heartbeat.heartbeat_dir is not None and common.common_dir().exists()


def test_the_watch_screen_shows_agents_handoffs_and_locks(tmp_path, monkeypatch):
    import handoff
    import heartbeat
    import watch
    for name in ("beats", "handoffs", "locks"):
        (tmp_path / name).mkdir()
    monkeypatch.setattr(heartbeat, "heartbeat_dir", lambda: tmp_path / "beats")
    monkeypatch.setattr(handoff, "handoff_dir", lambda: tmp_path / "handoffs")
    monkeypatch.setattr(common, "lock_dir", lambda: tmp_path / "locks")
    heartbeat.beat("dec-9", "matching ovl34_fn_0000")
    (tmp_path / "handoffs/escalate-general-1.md").write_text("agent = rev-9\nstate = escalate\nnote = a question\n")
    (tmp_path / "locks/ovl34.lock").write_text("agent = dec-9\n")
    text = watch.screen(5)
    assert "dec-9" in text and "matching ovl34_fn_0000" in text
    assert "ESCALATE" in text and "a question" in text and "ovl34" in text and "next unit" in text


def test_a_claim_shows_the_orchestrators_notes_on_its_unit(tmp_path):
    import claim
    (tmp_path / "work").mkdir()
    (tmp_path / "work/blockers.md").write_text(
        "# Blockers\n\n<!-- mentions ovl34 in a comment -->\n\n"
        "- ovl34 back on the decompiler: revert 1bb73fd,\n  then make res09 agree.\n\n"
        "- res06 stub parameters: Left, Top.\n- ovl340 is another unit.\n")
    notes = claim.blocker_notes(tmp_path, "ovl34")
    assert notes == ["- ovl34 back on the decompiler: revert 1bb73fd, then make res09 agree."]
    assert claim.blocker_notes(tmp_path, "res08") == []


def test_a_handoff_with_nothing_to_merge_is_refused(tmp_path, monkeypatch):
    import handoff
    import heartbeat
    monkeypatch.setattr(handoff, "handoff_dir", lambda: tmp_path)
    monkeypatch.setattr(heartbeat, "heartbeat_dir", lambda: tmp_path)
    state = {"branch": "unit/ovl33", "ahead": "0"}

    def fake_git(*args, **kw):
        return {"rev-parse": state["branch"] if "--abbrev-ref" in args else "abc1234",
                "status": "", "rev-list": state["ahead"]}.get(args[0], "")
    monkeypatch.setattr(common, "git", fake_git)
    monkeypatch.setattr(handoff, "unmatched", lambda unit: "")
    run = ["--unit", "ovl33", "--agent", "dec-9", "--state", "complete", "--note", "already complete"]
    assert handoff.main(run) == 1 and not (tmp_path / "ovl33.md").exists()      # nothing beyond main
    state["branch"] = "main"
    state["ahead"] = "3"
    assert handoff.main(run) == 1                                                # run from the main checkout
    state["branch"] = "unit/ovl33"
    assert handoff.main(run) == 0 and (tmp_path / "ovl33.md").exists()


def test_make_targets_keep_the_lock_owners_heartbeat_alive(tmp_path, monkeypatch):
    import datetime as dt
    import heartbeat
    (tmp_path / "beats").mkdir()
    (tmp_path / "locks").mkdir()
    monkeypatch.setattr(heartbeat, "heartbeat_dir", lambda: tmp_path / "beats")
    monkeypatch.setattr(common, "lock_dir", lambda: tmp_path / "locks")
    (tmp_path / "locks/ovl23.lock").write_text("unit = ovl23\nagent = dec-9\nbranch = unit/ovl23\n")
    branch = {"now": "unit/ovl23"}
    monkeypatch.setattr(common, "git", lambda *a, **k: branch["now"])
    heartbeat.beat("dec-9", "decompiling IncrementBonuses")
    beat = tmp_path / "beats/dec-9.txt"
    old = heartbeat.fields(beat.read_text())["time"]
    beat.write_text(beat.read_text().replace(old, "2000-01-01T00:00:00+00:00"))   # long silent
    assert heartbeat.auto("make match ovl23") == "dec-9"
    f = heartbeat.fields(beat.read_text())
    assert f["note"] == "decompiling IncrementBonuses" and f["activity"] == "make match ovl23"
    assert dt.datetime.fromisoformat(f["time"]).year > 2000 and heartbeat.listing()[0].startswith("ok")
    branch["now"] = "main"                                           # the orchestrator's make check
    assert heartbeat.auto("make check") is None
    monkeypatch.setattr(common, "git", lambda *a, **k: (_ for _ in ()).throw(RuntimeError("no git")))
    assert heartbeat.auto("make check") is None                     # never raises


def test_a_unit_handoff_that_does_not_match_is_refused(tmp_path, monkeypatch, capsys):
    import handoff
    import heartbeat
    monkeypatch.setattr(handoff, "handoff_dir", lambda: tmp_path)
    monkeypatch.setattr(heartbeat, "heartbeat_dir", lambda: tmp_path)
    monkeypatch.setattr(common, "git", lambda *a, **k: {"rev-parse": "unit/ovl23" if "--abbrev-ref" in a
                                                        else "abc1234", "rev-list": "2"}.get(a[0], ""))
    monkeypatch.setattr(handoff, "unmatched", lambda unit: "DIFF    RecalcCharacter ovl23:0010 x")
    run = ["--unit", "ovl23", "--agent", "dec-9", "--state", "partial", "--note", "3 drafts"]
    assert handoff.main(run) == 1 and not (tmp_path / "ovl23.md").exists()
    assert "RecalcCharacter" in capsys.readouterr().err
    monkeypatch.setattr(handoff, "unmatched", lambda unit: "")
    assert handoff.main(run) == 0                                    # drafts turned back into stubs
    esc = ["--unit", "ovl23", "--agent", "dec-9", "--state", "escalate", "--note", "a question"]
    monkeypatch.setattr(handoff, "unmatched", lambda unit: "DIFF x")
    assert handoff.main(esc) == 0                                    # escalations are not checked


@pytest.mark.skipif(not (ROOT / "build/toolchain").exists(), reason="needs Turbo Pascal 6.0 (make tp-pin)")
def test_unmatched_is_empty_for_a_matching_unit():
    import handoff
    assert handoff.unmatched("ovl00") == ""
