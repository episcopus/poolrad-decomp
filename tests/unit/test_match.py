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


@pytest.fixture(scope="module")
def built():
    """One build for the units these tests read (the whole program is compiled either way)."""
    return match.match_units(["res04", "ovl00", "res06"])


def test_res04_matches_as_a_whole_unit(built):
    results, whole = built["res04"]
    assert set(statuses(results).values()) == {"matched"} and len(results) == 5
    assert whole.startswith("unit: complete")
    by = {r.name: r for r in results}
    assert by["ReadGameKey"].pool == 38            # the set [0, 1] and 'STING' sit before the routine


def test_an_overlay_unit_matches_through_its_stubs(built):
    results, whole = built["ovl00"]
    assert statuses(results) == {"HeapErrorHandler": "matched", "ovl00_init": "matched"}
    assert whole.startswith("unit: complete")


def test_a_routine_matches_inside_a_unit_of_stubs(built):
    results, whole = built["res06"]
    st = statuses(results)
    assert st.pop("ShowMessageLine") == "matched" and set(st.values()) == {"stub"} and len(st) >= 2
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
    r = mutated("KeyCtrlS = #19;", "KeyCtrlS = #20;")          # a named constant is still a constant
    assert r.name == "ReadGameKey" and "not an address" in r.detail


def test_a_wrong_global_is_caught(mutated):
    r = mutated("Regs.AL := SavedVideoMode;", "Regs.AL := SoundMode;")
    assert r.name == "QuitGame" and "global: ours is SOUNDMODE (DS:5372 expected)" in r.detail and "DS:4A1C" in r.detail


def test_a_wrong_set_constant_is_caught(mutated):
    r = mutated("in [0, 1]", "in [0, 2]")
    assert "literal pool" in r.detail


def test_a_wrong_callee_is_caught(mutated):
    r = mutated("  Halt;\n", "  RunError(0);\n")              # same shape: code in AX, far call
    assert r.name == "QuitGame" and "far call: ours goes to 0AF8:00E2, the original to 0AF8:00E9" in r.detail


def test_sources_parse_and_pad():
    text = (match.SRC / "RES06.PAS").read_text()
    parsed = dict(match.routines_of(text))
    assert parsed["res06_fn_05EB"] and parsed["res06_fn_0626"] and not parsed["ShowMessageLine"]
    padded = match.with_pads("RES06", text)
    assert "var MPadVRES06: array[0..63] of Byte; procedure MPadCRES06;" in padded
    assert padded.index("procedure MPadCRES06; begin end;") > padded.index("implementation")


def test_the_main_program_matches_with_every_initialisation_call():
    results, whole = match.match_unit("main")
    assert [r.status for r in results] == ["matched"] and whole.startswith("unit: complete")
    assert results[0].symbols == 58                  # 48 initialisation calls and 10 calls of the main block


def test_skeleton_declares_every_routine_and_marks_a_real_initialisation():
    import skeleton
    orig = match.Original()
    text = skeleton.skeleton(orig, "res08")          # res08's initialisation sets up the overlay manager
    assert match.STUB_INIT in text and match.init_begin_line(text) is not None
    names = [n for n, stub in match.routines_of(text)]
    assert all(stub for _n, stub in match.routines_of(text))
    assert names == [r["name"] for r in sorted((r for r in orig.routines if r["unit"] == "res08"
                                                and not r["name"].endswith("_init")),
                                               key=lambda r: int(r["addr"].split(":")[1], 16))]
    empty = skeleton.skeleton(orig, "res10")         # an empty initialisation is already decompiled
    assert match.STUB_INIT not in empty and empty.endswith("begin\nend.\n")
