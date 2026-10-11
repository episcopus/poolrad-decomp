"""The matcher (tools/match/match.py, SPEC 8.3): decompiled Pascal compiled by the pinned Turbo Pascal 6.0
against the original's instructions.

Needs the compiler (`make tp-pin`, docs/setup/SETUP-tp.md); skipped without it. Each compile takes well
under a second, so these run in the fast set."""
import shutil
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))

import match  # noqa: E402

pytestmark = pytest.mark.skipif(not (match.tp.TC / match.tp.pinned_version() / "BIN/TPC.EXE").exists(),
                                reason="Turbo Pascal 6.0 not installed (make tp-pin)")


def statuses(results):
    return {r.name: r.status for r in results}


def test_res04_matches_as_a_whole_unit():
    results, whole = match.match_unit("res04")
    assert set(statuses(results).values()) == {"matched"} and len(results) == 5
    assert whole.startswith("unit: complete")
    by = {r.name: r for r in results}
    assert by["res04_fn_0059"].pool == 38            # the set [0, 1] and 'STING' sit before the routine


def test_an_overlay_unit_matches_through_its_stubs():
    results, whole = match.match_unit("ovl00")
    assert statuses(results) == {"ovl00_e1": "matched", "ovl00_init": "matched"}
    assert whole.startswith("unit: complete")


def test_a_routine_matches_inside_a_unit_of_stubs():
    results, whole = match.match_unit("res06")
    assert statuses(results) == {"res06_fn_05EB": "stub", "res06_fn_0626": "stub", "res06_fn_0BF5": "matched"}
    assert whole == ""                               # a unit with stubs is not compared as a whole


@pytest.fixture
def mutated(tmp_path, monkeypatch):
    """Run the matcher over a copy of src/ with one textual change in RES04.PAS."""
    src = tmp_path / "src"
    shutil.copytree(match.SRC, src)
    monkeypatch.setattr(match, "SRC", src)
    monkeypatch.setattr(match, "BUILD", tmp_path / "build")

    def run(old, new):
        p = src / "RES04.PAS"
        text = p.read_text()
        assert old in text
        p.write_text(text.replace(old, new, 1))
        results, _whole = match.match_unit("res04")
        bad = [r for r in results if r.status != "matched"]
        assert len(bad) == 1, [(r.name, r.status) for r in results]
        return bad[0]
    return run


def test_a_wrong_constant_is_caught(mutated):
    r = mutated("if Key = #19 then", "if Key = #20 then")
    assert r.name == "res04_fn_0059" and "not an address" in r.detail


def test_a_wrong_global_is_caught(mutated):
    r = mutated("Regs.AL := ds4A1C;", "Regs.AL := ds5372;")
    assert r.name == "res04_fn_0000" and "global: ours is DS5372" in r.detail and "DS:4A1C" in r.detail


def test_a_wrong_set_constant_is_caught(mutated):
    r = mutated("in [0, 1]", "in [0, 2]")
    assert "literal pool" in r.detail


def test_a_wrong_callee_is_caught(mutated):
    r = mutated("  Halt;\n", "  RunError(0);\n")              # same shape: code in AX, far call
    assert r.name == "res04_fn_0000" and "far call: ours goes to 0AF8:00E2, the original to 0AF8:00E9" in r.detail


def test_sources_parse_and_pad():
    text = (match.SRC / "RES06.PAS").read_text()
    assert match.routines_of(text) == [("res06_fn_05EB", True), ("res06_fn_0626", True), ("res06_fn_0BF5", False)]
    padded = match.with_pads("RES06", text)
    assert "var MPadVRES06: array[0..63] of Byte; procedure MPadCRES06;" in padded
    assert padded.index("procedure MPadCRES06; begin end;") > padded.index("implementation")
