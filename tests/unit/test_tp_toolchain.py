"""tools/re/tp_toolchain.py: the comparison must accept the pinned compiler and reject
single-byte code changes. Needs `make tp-probe` (skipped when the probe build is absent)."""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/re"))
import tp_toolchain as tc  # noqa: E402

PROBE = tc.TC / "probe" / "tp60-1991"
STARTS = {"DOS": 0x0A32, "CRT": 0x0A40, "OVERLAY": 0x0AA2, "SYSTEM": 0x0AF8}


def ref_side():
    exe, mapf = tc.ci(PROBE, "SINK.EXE"), tc.ci(PROBE, "SINK.MAP")
    if not (exe and mapf):
        pytest.skip("no tp60-1991 probe build; run make tp-install tp-probe")
    img, rel = tc.read_mz(exe)
    segs, _ = tc.read_map(mapf)
    return tc.Side(img, rel, {u: (segs[u][0], segs[u][1]) for u in tc.UNITS})


def test_pinned_runtime_units_match():
    ours, rel = tc.read_mz(tc.EXE)
    _, res = tc.classify_all(ours, rel, ref_side(), STARTS)
    for u in tc.UNITS:
        assert res[u]["match"], (u, res[u]["classes"])


@pytest.mark.parametrize("off", [0x004B, 0x0B10, 0x1690])  # cld in init, StrCopy body, Move body
def test_single_byte_change_is_caught(off):
    ours, rel = tc.read_mz(tc.EXE)
    mutated = bytearray(ours)
    mutated[0x0AF8 * 16 + off] ^= 0x01
    _, res = tc.classify_all(bytes(mutated), rel, ref_side(), STARTS)
    assert not res["SYSTEM"]["match"]


def test_tpc_annotates_runtime_calls_with_pool_names(capsys):
    """`make tpc DISASM=1` maps far calls into the fresh runtime onto POOL's routines."""
    if not (tc.TC / tc.pinned_version() / "BIN" / "TPC.EXE").exists():
        pytest.skip("pinned compiler not installed; run make tp-install")
    try:
        tc.find_emulator(None)
    except SystemExit:
        pytest.skip("no DOS emulator; run make emu2")
    args = type("A", (), {"version": None, "src": str(ROOT / "tools/re/tp_idioms/STRIDIOM.PAS"),
                          "emu": None, "opts": [], "disasm": True})()
    assert tc.cmd_tpc(args) == 0
    out = capsys.readouterr().out
    assert "System_StrConcat (POOL 0AF8:0B98)" in out
    assert "System_StrLCopy (POOL 0AF8:0B25)" in out


@pytest.mark.parametrize("log,ok", [
    ("Turbo Pascal  Version 6.0\nSINK.PAS(12)\n66 lines, 4384 bytes code, 2668 bytes data.\n", True),  # emu2
    ("Turbo Pascal  Version 6.0\n167 lines, 0.2 seconds, 17552 bytes code, 2764 bytes data.\n", True),  # DOSBox-X
    ("SINK.PAS(3): Error 3: Unknown identifier.\n", False),
    ("12 lines, 0.1 seconds, 100 bytes code, 10 bytes data.\nError 2: File not found.\n", False),
])
def test_compiled_ok_accepts_both_emulator_summaries(log, ok):
    assert tc.compiled_ok(log) is ok
