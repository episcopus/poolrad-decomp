"""Session goldens (SPEC 8.5, playbook 40): the committed goldens are well formed, belong to the
current scripts and the pinned executable, and the original still reproduces them in the oracle.

The well-formedness tests are fast; `test_oracle_reproduces_committed_golden` boots the game
(about 15 s per session)."""
import json
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from oracle import golden  # noqa: E402

SESSIONS = sorted(p.stem for p in golden.SESSIONS.glob("*.keys"))


def _load(name):
    return json.loads((golden.GOLDEN / name / "golden.json").read_text())


def test_every_session_script_has_a_golden():
    assert SESSIONS, "no session scripts"
    for n in SESSIONS:
        assert (golden.GOLDEN / n / "golden.json").exists(), "run: make golden SESSION=%s" % n


@pytest.mark.parametrize("name", SESSIONS)
def test_golden_belongs_to_current_script_and_executable(name):
    g = _load(name)
    assert g["format"] == golden.FORMAT and g["session"] == name
    assert g["script_sha256"] == golden.sha256_file(golden.SESSIONS / (name + ".keys")), \
        "script changed after the golden was recorded"
    assert g["exe_sha256"] == golden.sha256_file(golden.EXE)
    assert g["recorded_runs"] == 2 and g["stop_reason"] in ("input-exhausted", "quit")


@pytest.mark.parametrize("name", SESSIONS)
def test_golden_files_are_complete(name):
    d = golden.GOLDEN / name
    g = _load(name)
    labels = [c["label"] for c in g["checkpoints"]]
    assert labels, "a golden without checkpoints proves nothing"
    for label in labels:
        assert (d / (label + ".png")).stat().st_size > 0, label
    reads = (d / "reads.txt").read_text().split()
    assert len(reads) == g["key_reads"]
    import hashlib
    assert hashlib.sha256("\n".join(reads).encode()).hexdigest() == g["reads_sha256"]
    nostack = (d / "reads_nostack.txt").read_text().split()
    assert len(nostack) == g["key_reads"]
    assert hashlib.sha256("\n".join(nostack).encode()).hexdigest() == g["reads_nostack_sha256"]
    # nothing but digests and our own screenshots (no game files)
    assert {p.name for p in d.iterdir()} == {"golden.json", "reads.txt", "reads_nostack.txt"} | {l + ".png" for l in labels}


def _hybrid_view():
    return {
        "stop_reason": "input-exhausted", "instructions": 1, "virtual_seconds": 1,
        "video_mode": 0x0D, "key_reads": 0, "reads_nostack_sha256": "a",
        "canonical_nostack_digest": "fin", "random_calls": 10, "random_digest": "seq",
        "files_opened": [],
        "checkpoints": [{"label": "title", "time": 5, "screen": "pix",
                         "canonical_nostack": "st", "random_calls": 5022}],
    }


def test_spinner_tolerance_is_one_call_and_nothing_else():
    a = _hybrid_view()
    assert golden.hybrid_difference(a, json.loads(json.dumps(a))) is None
    assert golden.hybrid_spinner_notes(a, a) == []
    one = json.loads(json.dumps(a))
    one["checkpoints"][0]["random_calls"] = 5021
    one["checkpoints"][0]["canonical_nostack"] = "step"
    assert golden.hybrid_difference(a, one) is None
    assert "title" in golden.hybrid_spinner_notes(a, one)[0]
    two = json.loads(json.dumps(a))
    two["checkpoints"][0]["random_calls"] = 5020
    assert "tolerance" in golden.hybrid_difference(a, two)
    state = json.loads(json.dumps(a))
    state["checkpoints"][0]["canonical_nostack"] = "other"
    assert "same Random count" in golden.hybrid_difference(a, state)
    screen = json.loads(json.dumps(a))
    screen["checkpoints"][0]["screen"] = "nope"
    assert "screen" in golden.hybrid_difference(a, screen)
    final = json.loads(json.dumps(a))
    final["random_digest"] = "other"
    assert "random_digest" in golden.hybrid_difference(a, final)


def test_stack_bytes_are_diagnostic():
    import tomllib
    d = tomllib.loads((ROOT / "re/state.toml").read_text())
    assert d["stack"] == "diagnostic"


def test_first_difference_names_the_checkpoint_and_the_key_read():
    a = {"stop_reason": "x", "reads_sha256": "A",
         "checkpoints": [{"label": "t", "time": 1, "screen": "s", "canonical": "c", "digest": "d", "random_calls": 3}]}
    assert golden.first_difference(a, dict(a), ["1"], ["1"]) is None
    b = json.loads(json.dumps(a))
    b["checkpoints"][0]["screen"] = "other"
    assert "checkpoint 0 (t)" in golden.first_difference(a, b, [], [])
    c = dict(a, reads_sha256="B")
    assert "key read 1" in golden.first_difference(a, c, ["x", "y", "z"], ["x", "q", "z"])


@pytest.mark.parametrize("name", SESSIONS)
def test_oracle_reproduces_committed_golden(name, capsys):
    assert golden.check(name, golden.GOLDEN) == 0, capsys.readouterr().err
