"""Exact time and routine costs (tools/oracle/timing.py, SPEC 8.4, whitepaper appendix C).

Mechanism tests use tiny hand-assembled programs (fast). The real-game tests boot the original in exact
mode (about 30 to 45 s per session) and compare against the committed goldens:

  * exact mode alone reproduces the golden in every digest (it is the same time model, counted exactly);
  * with System.Move replaced by Python for the whole session (about 50,000 calls) and its recorded cost
    charged, every time, screen, state (without the stack) and Random value of the golden is reproduced: the drift that
    the plain hybrid run showed (whitepaper appendix C, first known limit) is gone."""
import json
import struct
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from oracle import golden, timing  # noqa: E402
from oracle.machine import LOAD_SEG, Machine, OracleError  # noqa: E402
from oracle.run import run_session  # noqa: E402


# --------------------------------------------------------------------------- tiny programs
def timer_program(calls: int = 3, loop: int = 65535) -> tuple[bytes, dict]:
    """Install an INT 08h handler that counts ticks, call a routine R `calls` times (R spins `loop`
    iterations), exit with the tick count. Returns the code and the addresses of R and the handler."""
    head = bytes.fromhex("8CC8 8ED8".replace(" ", ""))                       # mov ax,cs ; mov ds,ax
    n_call_bytes = 3 * calls
    r_off = len(head) + 3 + 3 + 2 + n_call_bytes + 3 + 2 + 2                  # after: mov dx ; mov ax ; int ; calls ; mov al ; mov ah ; int
    r = b"\xB9" + struct.pack("<H", loop) + b"\xE2\xFE\xC3"                   # mov cx,N ; loop $ ; ret
    h_off = r_off + len(r)
    counter = h_off + 4 + 2 + 2 + 1
    handler = b"\xFE\x06" + struct.pack("<H", counter) + bytes.fromhex("B020 E620 CF".replace(" ", ""))
    code = head + b"\xBA" + struct.pack("<H", h_off) + bytes.fromhex("B80825 CD21".replace(" ", ""))
    for i in range(calls):
        here = len(code) + 3
        code += b"\xE8" + struct.pack("<h", r_off - here)
    code += b"\xA0" + struct.pack("<H", counter) + bytes.fromhex("B44C CD21".replace(" ", ""))
    assert len(code) == r_off, (len(code), r_off)
    code += r + handler + b"\x00"
    return code, {"r": r_off, "r_size": len(r), "handler": h_off, "counter": counter}


def make_exe(code: bytes, tmp: Path) -> Path:
    hdr_paras = 2
    img = code + bytes(0x100)
    size = hdr_paras * 16 + len(img)
    hdr = struct.pack("<2s13H", b"MZ", size % 512, (size + 511) // 512, 0, hdr_paras, 0, 0xFFFF,
                      (len(code) + 15) // 16, 0x100, 0, 0, 0, 28, 0)
    p = tmp / "T.EXE"
    p.write_bytes(hdr.ljust(hdr_paras * 16, b"\0") + img)
    return p


def run_program(tmp_path, *, exact: bool, replace_r=None, table=None, record=False, calls=3):
    code, a = timer_program(calls)
    game = tmp_path / "game"
    game.mkdir(exist_ok=True)
    m = Machine(make_exe(code, tmp_path), game, exact=exact)
    r = timing.Routine({"id": "R", "unit": "res99", "addr": "0000:%04X" % a["r"], "size": a["r_size"]})
    handler_times = []
    rec = timing.CostRecorder(m, [r]) if record else None
    if replace_r is not None:
        timing.replace(m, r, replace_r, far=False, table=table)
    if exact:
        m.add_breakpoint(LOAD_SEG, a["handler"], lambda mach: handler_times.append(mach.exact_now()))
    reason = m.run(5_000_000)
    return m, reason, handler_times, rec, a


def test_exact_mode_is_the_plain_time_model_counted_exactly(tmp_path):
    plain, r0, _, _, _ = run_program(tmp_path, exact=False)
    exact, r1, _, _, _ = run_program(tmp_path, exact=True)
    assert r0 == r1 == "exit"
    assert plain.exit_code == exact.exit_code >= 3, "R runs about 3.5 timer periods"
    assert (plain.insns, plain.extra) == (exact.insns, exact.extra)
    assert plain.state_digest() == exact.state_digest()


def test_recorder_counts_instructions_in_the_routines_own_code(tmp_path):
    _, _, _, rec, _ = run_program(tmp_path, exact=True, record=True)
    rows = rec.rows["R"]
    assert len(rows) == 3
    assert [x[1] for x in rows] == [65537] * 3          # mov cx ; 65535 x loop ; ret
    assert [x[2] for x in rows] == [0, 0, 0]
    assert rows[1][0] - rows[0][0] > 65537, "the timer handler's instructions are not part of R but do take time"


def test_ticks_inside_a_replaced_routine_arrive_at_their_original_times(tmp_path):
    ref, _, ref_ticks, rec, _ = run_program(tmp_path, exact=True, record=True)
    table = rec.table()
    hyb, reason, hyb_ticks, _, _ = run_program(tmp_path, exact=True, replace_r=lambda m: None, table=table)
    assert reason == "exit"
    assert len(ref_ticks) >= 3
    assert hyb_ticks == ref_ticks, "every tick, including those that fall inside R, is delivered at its original time"
    assert hyb.exit_code == ref.exit_code
    assert (hyb.insns, hyb.extra) == (ref.insns, ref.extra), "the run ends at the original's time"


def test_without_the_recording_the_replaced_routine_is_charged_a_constant(tmp_path):
    ref, _, _, _, _ = run_program(tmp_path, exact=True)
    cheap, _, _, _, _ = run_program(tmp_path, exact=True, replace_r=lambda m: None)
    assert cheap.insns + cheap.extra < ref.insns + ref.extra       # replaced, almost free
    assert cheap.exit_code < ref.exit_code                         # fewer ticks seen: the plain-hybrid drift


def test_a_declining_replacement_leaves_the_call_to_the_original(tmp_path):
    ref, _, ref_ticks, rec, _ = run_program(tmp_path, exact=True, record=True)
    hyb, _, ticks, _, _ = run_program(tmp_path, exact=True, replace_r=lambda m: False, table=rec.table())
    assert ticks == ref_ticks and hyb.exit_code == ref.exit_code and hyb.insns == ref.insns


def test_a_run_that_diverges_from_the_recording_is_reported(tmp_path):
    _, _, _, rec, _ = run_program(tmp_path, exact=True, record=True)
    table = rec.table()
    table.rows["R"][1][0] += 1                                     # the second call "was" one instruction later
    with pytest.raises(OracleError, match=r"R: call 1 entered at time \d+, the recording says"):
        run_program(tmp_path, exact=True, replace_r=lambda m: None, table=table)
    table = rec.table()
    del table.rows["R"][2]
    with pytest.raises(OracleError, match="not in the recorded timeline"):
        run_program(tmp_path, exact=True, replace_r=lambda m: None, table=table)


def test_exact_time_must_be_asked_for_at_construction(tmp_path):
    code, a = timer_program()
    m = Machine(make_exe(code, tmp_path), tmp_path, exact=False)
    with pytest.raises(OracleError, match="exact"):
        timing.replace(m, timing.Routine({"id": "R", "unit": "res99", "addr": "0000:0010", "size": 6}),
                       lambda mm: None, far=False)


# --------------------------------------------------------------------------- the real game
MOVE = "0AF8:1685"


def py_move(m) -> bool | None:
    """System.Move(src, dst, count) in Python; video destinations are left to the original code."""
    ss, sp = m.get("ss"), m.get("sp")
    count = m.rw(ss, sp + 4)
    dst_off, dst_seg = m.rw(ss, sp + 6), m.rw(ss, sp + 8)
    src_off, src_seg = m.rw(ss, sp + 10), m.rw(ss, sp + 12)
    if m.linear(dst_seg, dst_off) + count >= 0xA0000:
        return False
    m.write(dst_seg, dst_off, m.read(src_seg, src_off, count))
    return None


def _golden(name):
    return json.loads((golden.GOLDEN / name / "golden.json").read_text())


@pytest.fixture(scope="module", params=["boot-title", "create-character"])
def session(request):
    """Exact-mode original run with a cost recorder on System.Move, then the hybrid run."""
    name = request.param
    text = (golden.SESSIONS / (name + ".keys")).read_text()
    holder = {}

    def prepare(m):
        holder["rec"] = timing.CostRecorder(m, [MOVE])

    orig = run_session(text, max_insns=golden.MAX_INSNS, quiet=True, exact=True, prepare=prepare)
    table = holder["rec"].table()

    reps = {}

    def prepare_hybrid(m):
        reps["move"] = timing.replace(m, MOVE, py_move, ret_bytes=10, table=table)

    hybrid = run_session(text, max_insns=golden.MAX_INSNS, quiet=True, exact=True, prepare=prepare_hybrid)
    return name, orig, hybrid, table, reps["move"]


def test_exact_mode_reproduces_the_golden_in_every_digest(session):
    name, orig, _, _, _ = session
    got = golden.summarise(orig)
    g = _golden(name)
    want = {k: g[k] for k in got}
    reads = (golden.GOLDEN / name / "reads.txt").read_text().split()
    assert golden.first_difference(want, got, reads, orig["read_digests"]) is None


def test_hybrid_run_with_move_replaced_reproduces_the_golden(session):
    name, _, hybrid, table, rep = session
    assert len(table.rows[MOVE]) > 10_000, "Move is called tens of thousands of times"
    assert rep.calls == len(table.rows[MOVE]), "every call was timed from the recording"
    got = golden.hybrid_view(golden.summarise(hybrid))
    want = golden.hybrid_view(_golden(name))
    assert golden.first_difference(want, got) is None


def test_hybrid_differs_from_the_original_only_inside_the_stack_segment(session):
    """The full-state digests differ (the original pushed frames the replacement did not); no byte of
    globals, heap or video does. Compared on the final memory image."""
    from oracle.state import STACK_SIZE
    _, orig, hybrid, _, _ = session
    a, b = orig["_machine"], hybrid["_machine"]
    ss = a.get("ss")
    assert (b.get("ss"), b.get("sp")) == (ss, a.get("sp"))
    ma = bytearray(a.uc.mem_read(0x500, 0xA0000 - 0x500))
    mb = bytearray(b.uc.mem_read(0x500, 0xA0000 - 0x500))
    differing = [i + 0x500 for i in range(len(ma)) if ma[i] != mb[i]]
    assert all((ss << 4) <= d < (ss << 4) + STACK_SIZE for d in differing), "a byte outside the stack differs"
