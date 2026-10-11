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
