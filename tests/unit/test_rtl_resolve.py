"""tools/re/tp_toolchain.py runtime_names/runtime_entries: far calls into a fresh runtime unit
resolve to the entry of the same POOL runtime routine, never to a neighbour or a routine's middle
(escalate-ovl34-20261012033554: our Move resolved as POOL's Assign, 0AF8:13E2 instead of 0AF8:1685)."""
import re
import sys
import tomllib
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/re"))
import tp_toolchain as tp  # noqa: E402

# Str links POOL's 0AF8:13B1 (which ends just before Assign) and not Assign; Move follows it in our
# build, as in ovl34's Put8x8Symbol: the layout that made the plain alignment resolve Move as Assign.
MOVE_SRC = """program MOVETEST;
{$A-,F+,S-,R-,G-,I-}
var A, B: array[0..15] of Byte; S: string; I: Integer;
begin
  Str(I:3, S);
  Move(A[1], B[2], 7);
end.
"""


def test_entry_glue_does_not_shift_a_routine():
    """POOL: X, Assign, Move; ours: X, Move (Assign dropped by the smart linker). Both routines begin
    with `mov bx,sp`, which a byte alignment glues onto X; the entry must still resolve to Move."""
    tail = bytes.fromhex("8bec837e0600") * 8 + bytes.fromhex("5dca0800")
    assign = bytes.fromhex("8bdc") + bytes(range(0x10, 0x3e))
    move = bytes.fromhex("8bdc") + bytes.fromhex("8cda36c5770a36c47f06368b4f04fc3bf773070" "3f103f94e4f")
    U = tail + assign + move + bytes.fromhex("cb")
    R = tail + move + bytes.fromhex("cb")
    entries = [0, len(tail), len(tail) + len(assign)]
    _, m = tp.align_unit(U, R)
    assert m.get(len(tail)) == len(tail)            # the alignment alone puts Assign's entry on Move's
    assert tp.runtime_entries(U, R, entries) == {0: 0, len(tail): len(tail) + len(assign)}


def test_masked_body_finds_randomize_when_the_vote_loses_its_address_words():
    """Randomize's two RandSeed words sit in an unequal-length difference once the linker drops
    the bytes after it, so the alignment vote sees 6 of 13 bytes. The body still occurs once."""
    body = bytes.fromhex("b42ccd21890e284489162a44cb")
    fresh = bytes.fromhex("b42ccd21890e4e0089165000cb")
    extra = bytes(range(20))
    U = body + extra
    R = b"XXXX" + fresh
    assert tp.runtime_entries(U, R, [0, len(body)]) == {4: 0}


def test_a_body_that_occurs_twice_is_not_a_runtime_entry():
    body = bytes.fromhex("b42ccd21890e284489162a44cb")
    fresh = bytes.fromhex("b42ccd21890e4e0089165000cb")
    U = body + bytes(range(20))
    R = fresh + fresh
    assert tp.runtime_entries(U, R, [0, len(body)]) == {}


def compile_program(tmp_path: Path, name: str, text: str):
    ver = tp.pinned_version()
    bin_dir = tp.TC / ver / "BIN"
    if not (bin_dir / "TPC.EXE").exists():
        pytest.skip("pinned compiler not installed; run make tp-pin")
    try:
        kind, emu = tp.find_emulator(None)
    except SystemExit:
        pytest.skip("no DOS emulator; run make emu2")
    import shutil
    for f in ("TPC.EXE", "TURBO.TPL"):
        shutil.copy(bin_dir / f, tmp_path / f)
    (tmp_path / (name + ".PAS")).write_text(text.replace("\n", "\r\n"))
    log = tp.run_tpc(kind, emu, tmp_path, ["/B", "/GD", name + ".PAS"])
    exe, mapf = tp.ci(tmp_path, name + ".EXE"), tp.ci(tmp_path, name + ".MAP")
    assert exe and mapf and tp.compiled_ok(log), log
    img, _ = tp.read_mz(exe)
    segs, _ = tp.read_map(mapf)
    return img, segs


def far_calls(img: bytes, segs: dict, seg: str) -> list[tuple[int, int]]:
    start, length, _ = segs[seg]
    code = img[start:start + length]
    return [(code[i + 4] << 8 | code[i + 3], code[i + 2] << 8 | code[i + 1])
            for i in range(len(code) - 4) if code[i] == 0x9A]


def test_move_resolves_to_pool_move(tmp_path):
    img, segs = compile_program(tmp_path, "MOVETEST", MOVE_SRC)
    rtl = tp.runtime_names(img, segs)
    sys_para = segs["SYSTEM"][0] >> 4
    prog = min((v[0], k) for k, v in segs.items() if v[2] == "CODE")[1]
    calls = [c for c in far_calls(img, segs, prog) if c[0] == sys_para]
    assert any(rtl.get(c) == "System_Move (POOL 0AF8:1685)" for c in calls), \
        [(hex(s), hex(o), rtl.get((s, o))) for s, o in calls]
    assert "System_Assign (POOL 0AF8:13E2)" not in rtl.values()   # Assign is not linked in


def runtime_routine_ids() -> set[str]:
    units = tomllib.loads((ROOT / "re/units.toml").read_text())["resident"]
    starts = {"%04X" % int(u["code_start"].split(":")[0], 16)
              for u in units if u.get("name", "").upper() in tp.UNITS}
    sym = tomllib.loads((ROOT / "re/symbols.toml").read_text())["routine"]
    return {r["id"] for r in sym if r["id"][:4] in starts and r["id"][4] == ":"}


@pytest.mark.parametrize("probe", [False, True])
def test_every_runtime_name_is_a_pool_entry_one_to_one(tmp_path, probe):
    """Over the full runtime (the probe build) and a small program: every resolved name is a POOL
    runtime routine entry, each one is resolved once, and our code at the resolved offset is that
    routine: at least half of its first bytes (up to 16, within the routine) are the same (link-time
    address fields differ; a neighbour that only shares a `push bp; mov bp,sp` prologue does not)."""
    if probe:
        d = tp.TC / "probe" / "tp60-1991"
        exe, mapf = tp.ci(d, "SINK.EXE"), tp.ci(d, "SINK.MAP")
        if not (exe and mapf):
            pytest.skip("no tp60-1991 probe build; run make tp-install tp-probe")
        img, _ = tp.read_mz(exe)
        segs, _ = tp.read_map(mapf)
    else:
        img, segs = compile_program(tmp_path, "MOVETEST", MOVE_SRC)
    rtl = tp.runtime_names(img, segs)
    assert rtl
    pool, _ = tp.read_mz(tp.EXE)
    ids = runtime_routine_ids()
    entries = sorted(ids)
    got = []
    for (para, off), name in rtl.items():
        rid = re.search(r"POOL ([0-9A-F]{4}:[0-9A-F]{4})", name).group(1)
        assert rid in ids, name
        got.append(rid)
        e = int(rid[5:], 16)
        later = [int(x[5:], 16) for x in entries if x[:4] == rid[:4] and int(x[5:], 16) > e]
        k = min(16, later[0] - e if later else 16)
        pa, oa = int(rid[:4], 16) * 16 + e, para * 16 + off
        same = sum(img[oa + i] == pool[pa + i] for i in range(k))
        assert 2 * same >= k, (name, hex(off), img[oa:oa + k].hex(), pool[pa:pa + k].hex())
    assert len(got) == len(set(got)), "a POOL routine resolved twice"
