"""Readability tools (docs/process/READABILITY.md): the checkable rules and the renaming tool."""
import shutil
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))

import match  # noqa: E402
import readability  # noqa: E402
import rename  # noqa: E402

UNIT = """unit RES09;
{ Something real: this unit draws the frame around the screen and its panels. }
{$A-,F+,S-,R-,G-,I-}
interface
procedure res09_fn_0000(A: Byte);
procedure DrawFrame(Width: Byte);
implementation
uses POOLVARS;

procedure res09_fn_0000(A: Byte);
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
"""


@pytest.fixture
def tree(tmp_path, monkeypatch):
    src = tmp_path / "src"
    src.mkdir()
    (src / "RES09.PAS").write_text(UNIT)
    (src / "POOLVARS.PAS").write_text("unit POOLVARS;\ninterface\nvar\n  ds1234: Byte;\nimplementation\nend.\n")
    monkeypatch.setattr(match, "SRC", src)
    for name in ("symbols.toml", "dseg.toml"):
        shutil.copy(ROOT / "re" / name, tmp_path / name)
    doc = tmp_path / "WHITEPAPER.md"
    doc.write_text("The routine `res09_fn_0000` stores `ds1234`, see 'res09_fn_0000' in strings.\n")
    monkeypatch.setattr(rename, "SYMBOLS", tmp_path / "symbols.toml")
    monkeypatch.setattr(rename, "DSEG", tmp_path / "dseg.toml")
    monkeypatch.setattr(rename, "LOG", tmp_path / "renames.toml")
    monkeypatch.setattr(rename, "DOCS", (doc,))
    return tmp_path


def test_the_checkable_rules_find_what_was_skipped(tree):
    found = readability.check("res09")
    assert any(f.startswith("R2 res09_fn_0000") for f in found)        # provisional name
    assert any(f.startswith("R3 res09_fn_0000") for f in found)        # no comment
    assert any(f.startswith("R4 res09_fn_0000: `A`") for f in found)   # a one-letter parameter
    assert any(f.startswith("R5 res09_fn_0000") for f in found)        # an unexplained global
    assert not any("DrawFrame" in f for f in found)                    # the readable routine passes
    assert not any(f.startswith("R1") for f in found)


def test_rename_changes_the_registry_the_source_and_the_whitepaper(tree):
    assert rename.main(["res09_fn_0000", "res09_fn_0000x", "--why", ""]) == 2          # evidence required
    assert rename.main(["res09_fn_0000", "DrawFrame", "--why", "x"]) == 2              # name taken
    assert rename.main(["res09_fn_0000", "SetBorderColour", "--why", "stores the border colour (03F1:0005)"]) == 0
    assert rename.main(["ds1234", "BorderColour", "--why", "written by SetBorderColour"]) == 0
    src = (match.SRC / "RES09.PAS").read_text()
    assert "SetBorderColour" in src and "res09_fn_0000" not in src and "BorderColour := A" in src
    assert 'name = "SetBorderColour"' in (tree / "symbols.toml").read_text()
    assert 'name = "BorderColour"' in (tree / "dseg.toml").read_text()
    doc = (tree / "WHITEPAPER.md").read_text()
    assert "`SetBorderColour` stores `BorderColour`" in doc and "'res09_fn_0000'" in doc   # strings untouched
    (match.SRC / "RES09.PAS").write_text(src.replace("SetBorderColour", "res09_fn_0000", 1))   # a stale merge
    assert rename.main(["--apply"]) == 0
    assert "res09_fn_0000" not in (match.SRC / "RES09.PAS").read_text()


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
