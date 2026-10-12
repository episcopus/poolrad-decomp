"""The initialization part of a unit with no interface routines (tools/match/match.py init_region).

Variant B puts a padding procedure first in every unit (with_pads). In a unit with no routines of its
own, that procedure is the first line-numbered code of the segment, so init_region must skip it exactly
as regions() does, or variant B's "init" is the 5-byte padding procedure (the res08 failure: `DIFF
res08_init 042B:00A4 ... 912 vs 5 bytes`, escalation escalate-general-20261012041843).

The probe is compiled with the pinned TP 6.0; skipped without it."""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))

import match  # noqa: E402

pytestmark = pytest.mark.skipif(not (match.tp.TC / match.tp.pinned_version() / "BIN/TPC.EXE").exists(),
                                reason="Turbo Pascal 6.0 not installed (make tp-pin)")

# No interface routines; an initialization part with globals, a loop and a string literal (a pool).
PROBE = """{$A-,F+,S-,R-,G-,I-}
unit INITPRB;

interface

var
  G: array[1..8] of Word;
  S: string;

implementation

var
  K: Byte;

begin
  for K := 1 to 8 do
    G[K] := K * 3;
  S := 'INIT';
end.
"""


@pytest.fixture(scope="module")
def builds(tmp_path_factory):
    out = tmp_path_factory.mktemp("init")
    src = {"INITPRB": PROBE.replace("\n", "\r\n")}
    return (match.compile_variant(["INITPRB"], src, False, out / "A"),
            match.compile_variant(["INITPRB"], src, True, out / "B"))


def test_variants_a_and_b_agree_on_the_init_of_a_unit_without_routines(builds):
    a, b = builds
    pad = match.pad_proc("INITPRB")
    ia = match.init_region(a, "INITPRB", 0)
    ib = match.init_region(b, "INITPRB", 0, pad=pad)
    assert ia is not None and ib is not None
    pad_region = match.regions(b, "INITPRB", [], pad=pad)[0]
    assert ib.entry >= pad_region.end                        # past the padding procedure
    assert ib.end - ib.entry == ia.end - ia.entry > 5         # the same code, not the 5-byte pad
    assert ib.pool == ia.pool                                 # the same literal pool before it


def test_without_the_pad_rule_variant_b_takes_the_padding_procedure(builds):
    """The failure the rule prevents, reproduced on the probe."""
    _a, b = builds
    wrong = match.init_region(b, "INITPRB", 0)
    assert wrong.entry == b.pubs[match.pad_proc("INITPRB").upper()][1]
    assert wrong.end - wrong.entry == 5
