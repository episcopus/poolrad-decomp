"""Readability tools (docs/process/READABILITY.md): the checkable rules and the renaming tool."""
import shutil
import sys
import tomllib
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))

import match  # noqa: E402
import readability  # noqa: E402
import rename  # noqa: E402


def _provisional_routine(tree):
    """First routine that still has its provisional map name. The fixture used to hard-code
    res09_fn_0000, which vanished when res09 was decompiled and renamed (dec-2, res09), so
    the name is picked from the registry copy instead; the tests stay valid until the last
    provisional routine is renamed."""
    sym = tomllib.loads((tree / "symbols.toml").read_text()).get("routine", [])
    for r in sym:
        if "_fn_" in r.get("name", ""):
            return r["name"], r["addr"]
    raise AssertionError("no provisional routine left for the rename fixture")


def _unit(routine):
    return """unit RES09;
{ Something real: this unit draws the frame around the screen and its panels. }
{$A-,F+,S-,R-,G-,I-}
interface
procedure %s(A: Byte);
procedure DrawFrame(Width: Byte);
implementation
uses POOLVARS;

procedure %s(A: Byte);
begin
  ds1234 := A;
end;

{ 03F1:0040. Draws the frame of the given width around the play area, then the panels. }
procedure DrawFrame(Width: Byte);
var
  Row: Byte;
begin
  Row := Width;
end;

begin
end.
""" % (routine, routine)


def _doc(routine):
    return ("The routine `%s` stores `ds1234`, see '%s' in strings.\n" % (routine, routine))


@pytest.fixture
def tree(tmp_path, monkeypatch):
    src = tmp_path / "src"
    src.mkdir()
    for name in ("symbols.toml", "dseg.toml"):
        shutil.copy(ROOT / "re" / name, tmp_path / name)
    routine, _ = _provisional_routine(tmp_path)
    (src / "RES09.PAS").write_text(_unit(routine))
    (src / "POOLVARS.PAS").write_text("unit POOLVARS;\ninterface\nvar\n  ds1234: Byte;\nimplementation\nend.\n")
    monkeypatch.setattr(match, "SRC", src)
    doc = tmp_path / "WHITEPAPER.md"
    doc.write_text(_doc(routine))
    monkeypatch.setattr(rename, "SYMBOLS", tmp_path / "symbols.toml")
    monkeypatch.setattr(rename, "DSEG", tmp_path / "dseg.toml")
    monkeypatch.setattr(rename, "LOG", tmp_path / "renames.toml")
    monkeypatch.setattr(rename, "DOCS", (doc,))
    return tmp_path


def test_the_checkable_rules_find_what_was_skipped(tree):
    routine, _ = _provisional_routine(tree)
    found = readability.check("res09")
    assert any(f.startswith("R2 " + routine) for f in found)        # provisional name
    assert any(f.startswith("R3 " + routine) for f in found)        # no comment
    assert any(f.startswith("R4 " + routine + ": `A`") for f in found)  # a one-letter parameter
    assert any(f.startswith("R5 " + routine) for f in found)        # an unexplained global
    assert not any("DrawFrame" in f for f in found)                    # the readable routine passes
    assert not any(f.startswith("R1") for f in found)


def test_rename_changes_the_registry_the_source_and_the_whitepaper(tree):
    routine, addr = _provisional_routine(tree)
    assert rename.main([routine, routine + "x", "--why", ""]) == 2          # evidence required
    assert rename.main([routine, "DrawFrame", "--why", "x"]) == 2              # name taken
    assert rename.main([routine, "SetBorderColour", "--why", "stores the border colour (%s)" % addr]) == 0
    assert rename.main(["ds1234", "BorderColour", "--why", "written by SetBorderColour"]) == 0
    src = (match.SRC / "RES09.PAS").read_text()
    assert "SetBorderColour" in src and routine not in src and "BorderColour := A" in src
    assert 'name = "SetBorderColour"' in (tree / "symbols.toml").read_text()
    assert 'name = "BorderColour"' in (tree / "dseg.toml").read_text()
    doc = (tree / "WHITEPAPER.md").read_text()
    assert "`SetBorderColour` stores `BorderColour`" in doc and "'%s'" % routine in doc   # strings untouched
    (match.SRC / "RES09.PAS").write_text(src.replace("SetBorderColour", routine, 1))   # a stale merge
    assert rename.main(["--apply"]) == 0
    assert routine not in (match.SRC / "RES09.PAS").read_text()


def test_rename_reaches_code_after_apostrophes_in_comments_and_prose():
    # dec-1, ovl27: an apostrophe in a comment paired with the next one further down, and every use in
    # between kept the old name.
    pas = ("{ the player's turn }\nprocedure Old(A: Byte);\nbegin\n  Old(1); Write('Old''s', 'x');\n"
           "end;\n(* it's done *)\nbegin Old(2) end.\n")
    text, n = rename.replace_word(pas, "Old", "New")
    assert n == 3 and "Old(" not in text and "'Old''s'" in text
    doc = "The game's main loop calls `Old`;\nthe players' turn calls Old too, see 'Old' in strings.\n"
    text, n = rename.replace_word(doc, "Old", "New", pascal=False)
    assert n == 2 and "`New`" in text and "calls New too" in text and "'Old'" in text
    assert rename.left_behind(text, "Old") == [2]


def test_rename_evidence_with_backslashes_and_quotes_stays_valid_toml(tree):
    import tomllib
    why = 'prompt "Insert disk" at C:\\GAME\\ costs $5'
    routine, _ = _provisional_routine(tree)
    assert rename.main([routine, "SetBorderColour", "--why", why]) == 0
    assert rename.main(["ds1234", "BorderColour", "--why", why]) == 0
    for name in ("symbols.toml", "dseg.toml", "renames.toml"):
        tomllib.loads((tree / name).read_text())                        # still parses
    log = tomllib.loads((tree / "renames.toml").read_text())["rename"]
    assert log[-1]["why"] == "prompt 'Insert disk' at C:\\GAME\\ costs $5"
