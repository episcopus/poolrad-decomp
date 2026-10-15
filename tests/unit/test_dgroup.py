"""The DGROUP layout, stub order and external object tools of Phase 5 (playbook 50).

Fast tests on small inputs; nothing here compiles. The real layout is proven by `make rebuild`."""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/re"))
sys.path.insert(0, str(ROOT / "tools/match"))

import dgroup  # noqa: E402
import extobj  # noqa: E402
import stub_order  # noqa: E402


def types_of(src: str) -> "dgroup.Types":
    return dgroup.Types(src)


def test_literal_of_scalars_strings_arrays_and_records():
    t = types_of("type\n  TPair = record\n    Lo, Hi: ShortInt;\n  end;\nconst\n  K = 3;\n")
    parse = lambda s: dgroup.parse_type(t, s)
    assert dgroup.literal(parse("array[0..3] of Byte"), bytes([1, 2, 3, 4])) == "(1, 2, 3, 4)"
    assert dgroup.literal(parse("array[0..K] of ShortInt"), bytes([1, 255, 3, 4])) == "(1, -1, 3, 4)"
    assert dgroup.literal(parse("string[6]"), bytes([3]) + b"Ace" + bytes(3)) == "'Ace'"
    assert dgroup.literal(parse("array[0..1] of TPair"), bytes([1, 2, 255, 0])) == "((Lo: 1; Hi: 2), (Lo: -1; Hi: 0))"
    assert dgroup.literal(parse("set of #32..#63"), bytes([1, 0, 0, 0x80])) == "[' ', '?']"
    assert dgroup.literal(parse("string[3]"), bytes([3]) + b"it'") == "'it'''"


def test_literal_refuses_what_cannot_be_written():
    t = types_of("")
    parse = lambda s: dgroup.parse_type(t, s)
    with pytest.raises(dgroup.DGroupError):
        dgroup.literal(parse("string[3]"), bytes([1]) + b"a" + b"\x07\x00")      # stale bytes after the end
    with pytest.raises(dgroup.DGroupError):
        dgroup.literal(parse("Boolean"), bytes([2]))
    assert dgroup.size_of(parse("array[1..8] of string[15]")) == 128


LAYOUT = '''unit P;
interface
uses Dos;
type
  TW = record A: Byte; end;
%s
const
  { DS:0002..0003: storage of Alias, Big }
  Raw0002: array[0..1] of Byte = (
      $01, $02);
  { names }
  Names: array[0..1] of string[3] = ('a', 'b');
var
  { DS:442E..442F: storage of Counter }
  ds442E: array[0..1] of Byte;
  Alias: Word absolute Raw0002;
  Big: array[0..9] of Byte absolute Raw0002;
  Counter: Word absolute ds442E;
implementation
end.
''' % dgroup.LAYOUT_BEGIN


def test_compact_form_drops_cells_and_values_and_keeps_the_declarations():
    out = dgroup.compact_poolvars(LAYOUT)
    assert "Raw0002" not in out and "ds442E" not in out                 # storage cells are gone
    assert "Names: array[0..1] of string[3];" in out                    # a typed constant is a variable
    assert "Alias: Word;" in out and "Big: array[0..9] of Byte;" in out    # views are variables
    assert "Counter: Word;" in out
    assert "= (" not in out and "$01" not in out
    assert dgroup.LAYOUT_BEGIN not in out
    assert dgroup.compact_poolvars(out) == out                          # nothing to do twice


def test_compact_leaves_a_source_without_a_layout_alone():
    plain = "unit P;\ninterface\nvar\n  X: Byte;\nimplementation\nend.\n"
    assert dgroup.compact_poolvars(plain) == plain


def test_poolvars_in_the_repository_has_a_layout_that_compacts_to_declarations_only():
    text = (ROOT / "src/POOLVARS.PAS").read_text()
    if dgroup.LAYOUT_BEGIN not in text:
        pytest.skip("POOLVARS has no layout yet (make dgroup WRITE=1)")
    compact = dgroup.compact_poolvars(text)
    assert dgroup.LAYOUT_BEGIN not in compact and "$" not in "".join(
        l for l in compact.splitlines() if l.startswith("  Raw"))
    assert len(compact) < len(text)
    assert max(len(l) for l in text.splitlines()) <= 127                # Turbo Pascal's line limit
    assert dgroup.compact_poolvars(compact) == compact


def test_omf_records_have_valid_checksums_and_the_structure_the_linker_reads():
    obj = extobj.omf("T", 6, [("Foo", 0), ("Bar", 3)], bytes(range(6)), [2])
    pos, kinds = 0, []
    while pos < len(obj):
        rtype, length = obj[pos], obj[pos + 1] | obj[pos + 2] << 8
        rec = obj[pos:pos + 3 + length]
        assert sum(rec) % 256 == 0                                      # OMF checksum
        kinds.append(rtype)
        pos += 3 + length
    assert kinds[0] == 0x80 and kinds[-1] == 0x8A                       # THEADR first, MODEND last
    assert 0x98 in kinds and 0x90 in kinds and 0xA0 in kinds and 0x9C in kinds
    assert bytes(range(6)) in obj


def test_stub_order_moves_the_exported_routines_and_keeps_the_others():
    text = '''unit OVLXX;
interface
uses POOLVARS;
procedure A;
{ the second one }
procedure B(X: Byte;
  Y: Byte);
function C: Word;
procedure D;
implementation
end.
'''
    head, chunks, tail = stub_order.split_interface(text)
    assert [stub_order.header_name(c) for c in chunks] == ["A", "B", "C", "D"]
    assert chunks[1][0] == "{ the second one }" and len(chunks[1]) == 3     # comment and a two-line header go together
    assert tail.startswith("implementation")
