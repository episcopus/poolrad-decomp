"""Nested routines in the matcher (tools/match/match.py nested_routines): a nested routine gets L2 from its
parent's match only when the parent calls it as TP 6.0 calls a nested routine (`push bp; push cs; call`,
static link first) and it lies wholly inside the parent's pre-entry region (operator
decision on escalation escalate-general-20261012012957).

The probe is compiled with the pinned TP 6.0; skipped without it."""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))

import match  # noqa: E402

pytestmark = pytest.mark.skipif(not (match.tp.TC / match.tp.pinned_version() / "BIN/TPC.EXE").exists(),
                                reason="Turbo Pascal 6.0 not installed (make tp-pin)")

# Top has nested A, B (B has nested C, which calls its uncle A: a sibling-style static link), a nested
# routine nobody calls (the smart linker drops it: no code), and a string literal shaped like a routine
# (push bp; mov bp,sp; pop bp; retf).
PROBE = """{$A-,O+,F+,S-,R-,G-,I-}
unit NESTPRB;

interface
procedure Other;
procedure Top;

implementation

var
  G, H: Byte;
  S: string;

procedure Other;
begin
  G := 7;
end;

procedure Top;
var
  L: Byte;

  function A(X: Byte): Byte;
  begin {A}
    if X = 8 then A := 0 else A := L;
  end;

  procedure Unused;
  begin {Unused}
    G := 1;
  end;

  procedure B;

    procedure D;
    begin {D}
      H := 2;
    end;

    procedure C;
    begin {C}
      L := A(L);
      D;
    end;

  begin {B}
    C;
    G := A(3);
  end;

begin
  S := 'U'#$89#$E5#$5D#$CB;
  L := H;
  G := A(H);
  B;
  Other;
end;

end.
"""


@pytest.fixture(scope="module")
def probe(tmp_path_factory):
    """(segment bytes, entries of the nested routines by name, Top's region)."""
    out = tmp_path_factory.mktemp("nested")
    b = match.compile_variant(["NESTPRB"], {"NESTPRB": PROBE.replace("\n", "\r\n")}, False, out / "A")
    start, length, _cls = b.segs["NESTPRB"]
    seg = b.img[start:start + length]
    src_lines = PROBE.split("\n")
    entries = {}
    for name in ("A", "Unused", "C", "B", "D"):
        line = next(k + 1 for k, t in enumerate(src_lines) if t.strip() == "begin {%s}" % name)
        code = [o for o, ln in b.lines["NESTPRB"] if ln == line]
        entries[name] = min(code) if code else None
    top = {r.name: r for r in match.regions(b, "NESTPRB", ["Other", "Top"])}["Top"]
    return seg, entries, top


def test_nested_routines_are_proven_by_their_calls(probe):
    seg, entries, top = probe
    found = match.nested_routines(seg, top.entry - top.pool, top.entry, top.end)
    # A and B are called by Top with `push bp; push cs; call`, C by B the same way (a nested routine
    # already proven); every one ends with its return inside Top's pre-entry region.
    # D is called only by its sibling C, with C's own static link passed on (`push word ptr [bp+6]`).
    assert set(found) == {entries["A"], entries["B"], entries["C"], entries["D"]}
    for t, (end, _caller) in found.items():
        assert top.entry - top.pool <= t < end <= top.entry
        assert seg[t:t + 3] == bytes([0x55, 0x89, 0xE5])
    assert found[entries["C"]][1] == entries["B"]
    assert found[entries["D"]][1] == entries["C"]
    k = seg.find(bytes([0xFF, 0x76, 0x06, 0x0E, 0xE8]), entries["C"], found[entries["C"]][0])
    assert k > 0, "C calls D as a sibling: push word ptr [bp+6]; push cs; call"


def test_uncalled_and_literal_shapes_get_nothing(probe):
    seg, entries, top = probe
    found = match.nested_routines(seg, top.entry - top.pool, top.entry, top.end)
    assert entries["Unused"] is None                          # never called: not even emitted
    assert len(found) == 4
    shaped = seg.find(bytes([0x05, 0x55, 0x89, 0xE5, 0x5D, 0xCB]), top.entry - top.pool, top.entry)
    assert shaped > 0 and shaped + 1 not in found              # the string literal of the pool


def call_sites(seg, top, target):
    """Offsets of `push bp; push cs; call target` in Top's body."""
    out = []
    for k in range(top.entry, top.end - 4):
        if seg[k:k + 3] == bytes([0x55, 0x0E, 0xE8]):
            if (k + 5 + int.from_bytes(seg[k + 3:k + 5], "little", signed=True)) & 0xFFFF == target:
                out.append(k)
    return out


def test_a_call_without_the_static_link_proves_nothing(probe):
    seg, entries, top = probe
    patched = bytearray(seg)
    for k in call_sites(seg, top, entries["B"]):
        patched[k] = 0x90                                      # nop instead of push bp
    found = match.nested_routines(bytes(patched), top.entry - top.pool, top.entry, top.end)
    assert entries["B"] not in found and entries["C"] not in found   # C was proven only through B
    assert entries["D"] not in found                                 # and D only through C
    assert entries["A"] in found


def test_a_static_link_call_outside_the_pre_entry_region_proves_nothing(probe):
    seg, entries, top = probe
    patched = bytearray(seg)
    k = call_sites(seg, top, entries["B"])[0]
    other = 0                                                  # Other, the unit's first (top-level) routine
    patched[k + 3:k + 5] = ((other - (k + 5)) & 0xFFFF).to_bytes(2, "little")
    found = match.nested_routines(bytes(patched), top.entry - top.pool, top.entry, top.end)
    assert other not in found and entries["B"] not in found


def _nested_pool():
    """A 5-byte nested `mov bx,[disp]; ret`, one literal, and a parent that calls the nested routine."""
    nested = bytes.fromhex("8b1e0002c3")          # mov bx, [0200]; ret
    parent_at = 6
    e8_at = parent_at + 2
    seg = bytearray(nested + bytes([0x41]))
    seg += bytes([0x55, 0x0E, 0xE8]) + ((0 - (e8_at + 3)) & 0xFFFF).to_bytes(2, "little") + bytes([0xC3])
    return bytes(seg), parent_at


class _Orig:
    def routine_id(self, unit, off):
        return "RES06:01DF"

    def far_target(self, seg, off):
        return None


def test_a_nested_pool_accepts_the_right_global_and_rejects_the_wrong_one():
    seg, parent = _nested_pool()
    ours = bytearray(seg)
    ours[2:4] = (0x0100).to_bytes(2, "little")     # our GlyphCol
    literal = bytearray(ours)
    literal[5] = 0x42                              # the byte outside the nested range
    cmp = match.Comparer.__new__(match.Comparer)
    cmp.obytes = seg
    cmp.unit = "res06"
    cmp.seg = "RES06"
    cmp.a = None
    cmp.orig = _Orig()
    ra = match.Region("ShowPagedText", parent, parent, parent + 6)

    def run(answers, pool):
        cmp.expect_global = lambda build, value: answers.get(value)
        return cmp.pre_entry(pool, pool, seg, ra, parent)

    ok, why, _n = run({0x0100: (0x0200, "GlyphCol")}, bytes(ours))
    assert ok, why
    ok, why, _n = run({0x0100: (0x9999, "GlyphCol")}, bytes(ours))
    assert not ok and "GlyphCol" in why
    ok, why, _n = run({0x0100: (0x0200, "GlyphCol")}, bytes(literal))
    assert not ok and "literal pool byte" in why


def test_a_nested_near_call_is_resolved_at_our_address():
    """Our parent sits at a different offset than the original, so the call displacement differs."""
    nested = bytes([0xE8]) + ((0x0100 - 3) & 0xFFFF).to_bytes(2, "little") + bytes([0xC3])
    parent_at = 5
    seg = bytearray(nested + bytes([0x41]))
    seg += bytes([0x55, 0x0E, 0xE8]) + ((0 - (parent_at + 5)) & 0xFFFF).to_bytes(2, "little") + bytes([0xC3])
    ours_entry = 0x0200
    nested_at = ours_entry - parent_at          # the nested routine sits at the start of the pool
    our_target = 0x0350                         # not the same displacement as the original's 0100
    ours = bytearray(seg)
    ours[1:3] = ((our_target - (nested_at + 3)) & 0xFFFF).to_bytes(2, "little")
    seen = []

    cmp = match.Comparer.__new__(match.Comparer)
    cmp.obytes = bytes(seg)
    cmp.unit = "res06"
    cmp.seg = "RES06"
    cmp.a = None
    cmp.orig = _Orig()
    cmp.orig.routine_id = lambda unit, off: "RES06:%04X" % off
    cmp.expect_routine = lambda build, seg, off: seen.append(off) or "RES06:0100"
    ra = match.Region("ShowPagedText", ours_entry, parent_at, ours_entry + 6)
    ok, why, _n = cmp.pre_entry(bytes(ours), bytes(ours), bytes(seg), ra, parent_at)
    assert ok, why
    assert seen == [our_target]
    cmp.expect_routine = lambda build, seg, off: "RES06:FFFF"
    ok, why, _n = cmp.pre_entry(bytes(ours), bytes(ours), bytes(seg), ra, parent_at)
    assert not ok and "near call" in why


def test_write_levels_records_l2_and_how_it_was_proven(tmp_path, monkeypatch):
    orig = match.Original()
    (tmp_path / "re").mkdir()
    (tmp_path / "re/symbols.toml").write_text((ROOT / "re/symbols.toml").read_text())
    monkeypatch.setattr(match, "ROOT", tmp_path)
    rid = orig.routines[0]["id"]
    why = "nested in Parent (x:0000), proven by the parent's match"
    r = match.Result("n", rid, "nested", why, orig.routines[0]["size"])
    unit = orig.routines[0]["unit"]
    match.write_levels([r], orig, unit)
    match.write_levels([r], orig, unit)                        # a second run adds nothing
    text = (tmp_path / "re/symbols.toml").read_text()
    block = text.split('id = "%s"' % rid, 1)[1].split("[[routine]]", 1)[0]
    assert 'level = "L2"' in block and block.count(why) == 1
