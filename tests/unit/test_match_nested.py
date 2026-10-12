"""Nested routines in the matcher (tools/match/match.py nested_routines): a nested routine gets L2 from its
parent's match only when the parent calls it as TP 6.0 calls a nested routine (`push bp; push cs; call`,
static link first) and it lies wholly inside the parent's exactly compared pre-entry region (operator
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

    procedure C;
    begin {C}
      L := A(L);
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
    for name in ("A", "Unused", "C", "B"):
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
    assert set(found) == {entries["A"], entries["B"], entries["C"]}
    for t, (end, _caller) in found.items():
        assert top.entry - top.pool <= t < end <= top.entry
        assert seg[t:t + 3] == bytes([0x55, 0x89, 0xE5])
    assert found[entries["C"]][1] == entries["B"]


def test_uncalled_and_literal_shapes_get_nothing(probe):
    seg, entries, top = probe
    found = match.nested_routines(seg, top.entry - top.pool, top.entry, top.end)
    assert entries["Unused"] is None                          # never called: not even emitted
    assert len(found) == 3
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
    assert entries["A"] in found


def test_a_static_link_call_outside_the_pre_entry_region_proves_nothing(probe):
    seg, entries, top = probe
    patched = bytearray(seg)
    k = call_sites(seg, top, entries["B"])[0]
    other = 0                                                  # Other, the unit's first (top-level) routine
    patched[k + 3:k + 5] = ((other - (k + 5)) & 0xFFFF).to_bytes(2, "little")
    found = match.nested_routines(bytes(patched), top.entry - top.pool, top.entry, top.end)
    assert other not in found and entries["B"] not in found


def test_write_levels_records_l2_and_how_it_was_proven(tmp_path, monkeypatch):
    orig = match.Original()
    (tmp_path / "re").mkdir()
    (tmp_path / "re/symbols.toml").write_text((ROOT / "re/symbols.toml").read_text())
    monkeypatch.setattr(match, "ROOT", tmp_path)
    rid = orig.routines[0]["id"]
    why = "nested in Parent (x:0000), proven by the parent's match"
    r = match.Result("n", rid, "nested", why, orig.routines[0]["size"])
    match.write_levels([r], orig)
    match.write_levels([r], orig)                              # a second run adds nothing
    text = (tmp_path / "re/symbols.toml").read_text()
    block = text.split('id = "%s"' % rid, 1)[1].split("[[routine]]", 1)[0]
    assert 'level = "L2"' in block and block.count(why) == 1
