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


def test_a_routine_matches_inside_a_unit_of_stubs():
    # A unit being decompiled routine by routine: a matched routine sits beside stubs (playbook 30), and
    # such a unit is not compared as a whole. Picked from the sources, since units complete over time.
    for unit in match.units_with_source():
        if unit == "main":
            continue
        rs = match.routines_of((match.SRC / (unit.upper() + ".PAS")).read_text())
        if any(s for _n, s in rs) and any(not s for _n, s in rs):
            break
    else:
        pytest.skip("every unit with source is complete")
    results, whole = match.match_unit(unit)
    st = set(statuses(results).values())
    assert "stub" in st and ("matched" in st or "differs" in st)
    assert whole == ""


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
    r = mutated("ResumeIfSaved1 = 1;", "ResumeIfSaved1 = 2;")  # the resume set [0, 1] before ReadGameKey
    assert "literal pool" in r.detail


def test_a_wrong_callee_is_caught(mutated):
    r = mutated("  Halt;\n", "  RunError(0);\n")              # same shape: code in AX, far call
    assert r.name == "QuitGame" and "far call: ours goes to 0AF8:00E2, the original to 0AF8:00E9" in r.detail


def test_sources_parse_and_pad():
    text = (match.SRC / "RES06.PAS").read_text()
    parsed = dict(match.routines_of(text))
    assert not parsed["ClearTextCells"] and not parsed["ShowMessageLine"]
    # a stub marker on the implementation header (the last occurrence) is seen as a stub
    head, sep, tail = text.rpartition("procedure ClearTextCells(")
    stubbed = dict(match.routines_of(head + "{@stub} " + sep + tail))
    assert stubbed["ClearTextCells"] and not stubbed["ShowMessageLine"]
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


def test_the_whole_set_is_compiled_in_groups_under_the_reference_limit(monkeypatch):
    """2026-10-14: one MATCH program for every unit ran TPC out of memory at about 1,050 references."""
    def unit(n):
        return "unit X;\ninterface\nimplementation\n" + "".join("procedure P%d;\nbegin\nend;\n" % k for k in range(n)) + "end.\n"
    sources = {"A": unit(250), "B": unit(200), "C": unit(10), "D": unit(390)}
    monkeypatch.setattr(match, "MAX_REFS_PER_BUILD", 400)
    groups = match.build_groups(["a", "b", "c", "d"], sources)
    assert groups == [["a"], ["b", "c"], ["d"]]                  # order kept, none over the limit
    assert match.build_groups(["c"], sources) == [["c"]]


def test_a_group_that_runs_tpc_out_of_memory_is_split_and_retried(monkeypatch):
    """2026-10-14: a 357-reference group with ovl03's code in it still ran TPC out of memory."""
    def unit(n):
        return "unit X;\ninterface\nimplementation\n" + "".join("procedure P%d;\nbegin\nend;\n" % k for k in range(n)) + "end.\n"
    sources = {"A": unit(10), "B": unit(10), "C": unit(10), "D": unit(10)}
    tried = []

    def compile_variant(units, srcs, pads, out, program=None):
        tried.append(list(units))
        if len(units) > 1:
            raise match.MatchError("compile failed:\nMATCH.PAS(504): Error 1: Out of memory.")
        return "build-of-%s" % units[0]
    monkeypatch.setattr(match, "unit_sources", lambda: sources)
    monkeypatch.setattr(match, "Original", lambda: type("O", (), {"units": {"a": 1, "b": 1, "c": 1, "d": 1}})())
    monkeypatch.setattr(match, "compile_variant", compile_variant)
    monkeypatch.setattr(match, "compare_unit", lambda orig, u, a, b, only: (a, u))
    out = match.match_units(["a", "b", "c", "d"])
    assert {u: r[0] for u, r in out.items()} == {u: "build-of-%s" % u for u in "abcd"}
    assert tried[0] == ["a", "b", "c", "d"] and ["a", "b"] in tried
    monkeypatch.setattr(match, "compile_variant", lambda *a, **k: (_ for _ in ()).throw(match.MatchError("Error 26: Type mismatch")))
    with pytest.raises(match.MatchError, match="Type mismatch"):         # a real error is never split away
        match.match_units(["a", "b"])
