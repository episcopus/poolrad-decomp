"""Record/replay of the outside world (tools/oracle/replay.py, Exhume's method).

Fast tests use tiny hand-assembled programs (helpers from test_oracle.py). The session tests boot the
real game and are marked slow: `make golden CHECK=1` and `make sessions` (both in `make check`) run the
recording and the replay with the C routines in the gate."""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tests/unit"))

from oracle import golden, replay  # noqa: E402
from oracle.keys import KeyScript  # noqa: E402
from oracle.machine import OracleError, LOAD_SEG  # noqa: E402
from test_oracle import machine_for  # noqa: E402


def clock_loop(pad: int) -> bytes:
    """Poll the time of day (INT 21h AH=2Ch) until the hundredths changed 3 times; SI counts the polls.
    `pad` NOPs per iteration stand for code that takes longer, as a routine replaced by C takes shorter."""
    head = bytes.fromhex("B42C CD21 88D3 30FF 31F6")                  # first read; BL=last, BH=0, SI=0
    body = bytes.fromhex("B42C CD21 46 38DA 7404 88D3 FEC7")          # read, count, note a change
    tail = b"\x90" * pad + bytes.fromhex("80FF03") + bytes([0x72, (256 - 18 - pad) & 0xFF])
    return head + body + tail + bytes.fromhex("89F0 B44C CD21")


def prepared(code, tmp_path, name):
    d = tmp_path / name
    d.mkdir()
    m = machine_for(code, d)
    m.keys = KeyScript([])
    m.random_log = []
    return m


def test_streams_are_run_length_coded():
    s = replay.Streams()
    for v, irq in ((1, 0), (1, 0), (1, 1), (2, 1), (2, 1)):
        s.add("k", v, irq)
    assert s.runs["k"] == [[1, 0, 2], [1, 1, 1], [2, 1, 2]] and s.total == 5
    c = replay.Cursor(s)
    assert [c.take("k")[0] for _ in range(5)] == [1, 1, 1, 2, 2]
    assert c.take("k") is None and c.take("other") is None


def test_replayed_reads_make_a_run_independent_of_instruction_count(tmp_path):
    rec_m = prepared(clock_loop(0), tmp_path, "rec")
    rec = replay.Recorder(rec_m)
    assert rec_m.run(5_000_000) == "exit"
    polls = rec_m.get("si")
    assert rec.streams.total == polls + 1

    slow = prepared(clock_loop(40), tmp_path, "slow")                  # without replay: time moves on
    assert slow.run(5_000_000) == "exit" and slow.get("si") != polls

    m = prepared(clock_loop(40), tmp_path, "replay")                    # with replay: the same answers
    p = replay.Player(m, rec)
    assert m.run(5_000_000) == "exit"
    assert m.get("si") == polls and p.reads == rec.streams.total


def test_a_saved_recording_replays_like_the_live_one(tmp_path):
    rec_m = prepared(clock_loop(0), tmp_path, "rec")
    live = replay.Recorder(rec_m)
    rec_m.run(5_000_000)
    rec = replay.Recording(live.streams, live.checkpoints, live.end, live.max_gap, {})
    rec.save(tmp_path / "r.json.gz")
    loaded = replay.Recording.load(tmp_path / "r.json.gz")
    assert loaded.digest() == rec.digest()
    assert (tmp_path / "r.json.gz").read_bytes() == (rec.save(tmp_path / "s.json.gz") or
                                                     (tmp_path / "s.json.gz").read_bytes())   # reproducible
    m = prepared(clock_loop(40), tmp_path, "replay")
    replay.Player(m, loaded)
    assert m.run(5_000_000) == "exit" and m.get("si") == rec_m.get("si")


def test_the_heap_is_part_of_the_canonical_state(tmp_path):
    from oracle.state import canonical_digest, dgroup_seg, HEAP_ORG, HEAP_PTR
    m = machine_for(bytes.fromhex("B8004C CD21"), tmp_path)
    ds = dgroup_seg()
    for o, (seg, off) in ((HEAP_ORG, (0x7000, 0)), (HEAP_PTR, (0x7000, 0x100))):
        m.ww(ds, o, off)
        m.ww(ds, o + 2, seg)
    before = canonical_digest(m, exclude_stack=True)
    m.wb(0x7000, 0x80, 0x55)                                            # inside the allocated heap
    inside = canonical_digest(m, exclude_stack=True)
    m.wb(0x7000, 0x180, 0x55)                                           # above HeapPtr: free memory
    assert before != inside == canonical_digest(m, exclude_stack=True)


def test_a_read_the_recording_does_not_have_is_a_divergence(tmp_path):
    rec_m = prepared(clock_loop(0), tmp_path, "rec")
    rec = replay.Recorder(rec_m)
    rec_m.run(5_000_000)
    m = prepared(bytes.fromhex("B400 CD1A B8004C CD21"), tmp_path, "other")   # asks INT 1Ah instead
    p = replay.Player(m, rec)
    assert m.run(1_000_000) == "diverged"
    assert "int1A.00" in p.first_difference and "read 1" in p.first_difference


def test_a_timer_interrupt_that_can_never_be_delivered_stops_the_run(tmp_path):
    m = machine_for(bytes.fromhex("FA EBFE"), tmp_path)                 # cli; jmp $
    with pytest.raises(OracleError, match="stalled"):
        m.run(50_000_000)


# --------------------------------------------------------------------------- the real game
@pytest.fixture(scope="module")
def create():
    return replay.Recording.load(golden.GOLDEN / "create-character" / golden.RECORDING)


@pytest.mark.slow
def test_replay_of_the_original_matches_its_recording(create):
    got, player = replay.replay(create)
    assert replay.difference(create, got, player) is None


@pytest.mark.slow
def test_a_wrong_random_result_is_caught(create):
    """The C Random answering one wrong value per call from call 33,500 (the character roll): caught at
    the first checkpoint after it, no later than the character sheet."""
    from oracle.hybrid import HybridLib, PARAMS
    rec = create
    hyb = HybridLib()
    n = [0]

    def bad_random(m):
        r = hyb.c_random(m)
        n[0] += 1
        if n[0] >= 33_500:
            m.set("ax", m.get("ax") ^ 1)
        return r

    def prepare(m):
        p = PARAMS["0AF8:11C0"]
        m.hook_routine(0x0AF8 + LOAD_SEG, 0x11C0, bad_random, ret_bytes=p["ret_bytes"], far=p["far"])

    got, player = replay.replay(rec, prepare)
    diff = replay.difference(rec, got, player)
    assert diff is not None and diff.startswith("read ")       # at a checkpoint, by its read number
    first_bad = min(n for n, cps in rec.checkpoints.items() if any(c["label"] == "sheet" for c in cps))
    assert int(diff.split()[1]) <= first_bad
