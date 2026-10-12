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
