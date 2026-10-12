"""A global declared `absolute` on another global (tools/match/match.py absolute_aliases, original_global).

TP 6.0 gives `Alias: T absolute Base` Base's address, and the map lists both names at that address in
an order that changes with the layout. data_var() takes the first name the map lists there, so before
the rule `match --all` failed or passed depending on the units linked: res08's `HeapWords: array[0..1]
of Word absolute HeapEnd` (src/POOLVARS.PAS) came first once unit/ovl28 was merged and the matcher
stopped with `global HEAPWORDS has no original offset`. An alias now resolves, through its declaration
only, to its base's original offset, whichever name the map lists first.

The probe is compiled with the pinned TP 6.0; skipped without it."""
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))

import match  # noqa: E402

needs_tp = pytest.mark.skipif(not (match.tp.TC / match.tp.pinned_version() / "BIN/TPC.EXE").exists(),
                              reason="Turbo Pascal 6.0 not installed (make tp-pin)")

PROBE = """{$A-,F+,S-,R-,G-,I-}
unit ALIASPRB;

interface

var
  Base: Pointer;
  Alias: array[0..1] of Word absolute Base;
  Screen: array[0..1] of Byte absolute $B800:$0000;
  Sink: Word;
  { Ghost: Word absolute Sink; in a comment: not a declaration }

procedure ReadAlias;

implementation

procedure ReadAlias;
begin
  Sink := Alias[1];
end;

end.
"""

BASE_OFFSET = 0x1234                    # the original's offset of Base in this test


def orig(offsets: dict[str, int]):
    return SimpleNamespace(global_offset=lambda name: offsets.get(name.upper()))


def test_aliases_come_only_from_absolute_on_a_variable():
    assert match.absolute_aliases(PROBE) == {"ALIAS": "BASE"}     # not Screen ($B800:$0000), not Ghost


def test_several_names_and_a_var_keyword():
    text = "unit U;\ninterface\nvar A, B: Word absolute C;\nimplementation\nend.\n"
    assert match.absolute_aliases(text) == {"A": "C", "B": "C"}


@pytest.fixture(scope="module")
def build(tmp_path_factory):
    out = tmp_path_factory.mktemp("alias")
    return match.compile_variant(["ALIASPRB"], {"ALIASPRB": PROBE.replace("\n", "\r\n")}, False, out / "A")


def read_disp(build) -> int:
    """The DS displacement of `Sink := Alias[1]`: mov ax,[Base+2]."""
    seg = build.seg_start("ALIASPRB")
    entry = build.pubs["READALIAS"][1]
    for i in match.md.disasm(build.img[seg + entry: seg + entry + 32], entry):
        if i.mnemonic == "mov" and i.op_str.startswith("ax, word ptr ["):
            return int(i.op_str.split("[")[1].rstrip("]"), 16)
    raise AssertionError("no load of Alias[1] in ReadAlias")


def ordered(build, first: str):
    """The build with the map's publics reordered so that `first` is listed first at its address."""
    pubs = {first: build.pubs[first]}
    pubs.update((n, v) for n, v in build.pubs.items() if n != first)
    return match.Build(build.img, build.relocs, build.segs, pubs, build.lines, build.rtl, build.sources, build.entry)


@needs_tp
def test_the_map_lists_alias_and_base_at_one_address(build):
    assert build.pubs["ALIAS"] == build.pubs["BASE"]
    assert build.data_var(read_disp(build))[1] == 2


@needs_tp
@pytest.mark.parametrize("first", ["ALIAS", "BASE"])
def test_the_alias_resolves_to_its_base_in_either_map_order(build, first):
    b = ordered(build, first)
    disp = read_disp(b)
    assert b.data_var(disp) == (first, 2)
    cmp = SimpleNamespace(orig=orig({"BASE": BASE_OFFSET}))
    assert match.Comparer.expect_global(cmp, b, disp) == (BASE_OFFSET + 2, "%s+2" % first)


@needs_tp
def test_without_the_alias_rule_the_alias_first_order_fails(build):
    """The failure the rule removes, reproduced on the probe."""
    b = ordered(build, "ALIAS")
    name, _delta = b.data_var(read_disp(b))
    with pytest.raises(match.MatchError, match="global ALIAS has no original offset"):
        match.original_global(orig({"BASE": BASE_OFFSET}), {}, name)


def test_an_alias_whose_base_has_no_offset_still_fails_clearly():
    with pytest.raises(match.MatchError, match="ALIAS is declared absolute BASE, which has no original offset"):
        match.original_global(orig({}), {"ALIAS": "BASE"}, "ALIAS")


def test_an_alias_with_a_different_offset_of_its_own_fails():
    with pytest.raises(match.MatchError, match="gives it DS:0010, not DS:1234"):
        match.original_global(orig({"BASE": BASE_OFFSET, "ALIAS": 0x10}), {"ALIAS": "BASE"}, "ALIAS")


def test_a_cycle_of_aliases_fails():
    with pytest.raises(match.MatchError, match="cycle"):
        match.original_global(orig({}), {"A": "B", "B": "A"}, "A")


def test_a_global_that_is_no_alias_is_unchanged():
    o = orig({"BASE": BASE_OFFSET})
    assert match.original_global(o, {"ALIAS": "BASE"}, "BASE") == BASE_OFFSET
    with pytest.raises(match.MatchError, match="global SINK has no original offset: name it dsXXXX"):
        match.original_global(o, {"ALIAS": "BASE"}, "SINK")
