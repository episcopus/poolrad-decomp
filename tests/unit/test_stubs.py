"""`make stubs` copies registry signatures and names into `{@stub}` headers and touches nothing else."""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))
import stubs

UNIT = """unit OVL12;
{ skeleton }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure ovl12_fn_0000;
procedure ovl12_e2;
function ovl12_fn_0058(A: Byte): Word;
procedure Done;
implementation

{ ovl12:0000: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_0000; begin end;
{ ovl12:001F: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e2; begin end;
{ ovl12:0058: retf 2 }
{@stub} function ovl12_fn_0058(A: Byte): Word; begin end; { trailing remark }
{ ovl12:0090: decompiled; the registry signature differs on purpose and must not be applied }
procedure Done;
begin
  ovl12_fn_0000;
end;

end.
"""


def routine(off, name, signature="", c_name=None):
    return {"id": "ovl12:%04X" % off, "unit": "ovl12", "addr": "ovl12:%04X" % off, "name": name,
            "signature": signature, "c_name": c_name or name}


REGISTRY = [
    routine(0x0000, "ovl12_fn_0000", "procedure ovl12_fn_0000(Color: Byte)"),
    routine(0x001F, "DrawThing", "procedure DrawThing(X, Y: Word)", c_name="ovl12_e2"),
    routine(0x0058, "ovl12_fn_0058", "function ovl12_fn_0058(A: Byte): Word"),
    routine(0x0090, "Done", "procedure Done(Changed: Boolean)"),
]


def test_stub_headers_follow_the_registry_signature_and_name_and_nothing_else_moves():
    changes, notes = stubs.plan(UNIT, "ovl12", REGISTRY)
    text = stubs.apply(UNIT, changes)
    assert "{@stub} procedure ovl12_fn_0000(Color: Byte); begin end;\n" in text
    assert "\nprocedure ovl12_fn_0000(Color: Byte);\n" in text
    assert "{@stub} procedure DrawThing(X, Y: Word); begin end;\n" in text
    assert "\nprocedure DrawThing(X, Y: Word);\n" in text and "ovl12_e2" not in text
    # Equal header: untouched, trailing remark kept; the decompiled routine keeps its own header.
    assert "{@stub} function ovl12_fn_0058(A: Byte): Word; begin end; { trailing remark }\n" in text
    assert "\nprocedure Done;\nbegin\n  ovl12_fn_0000;\nend;\n" in text and "Changed" not in text
    assert text.count("{@stub}") == 3 and len(changes) == 4
    # The frame comments above the stubs stay where they were.
    assert "{ ovl12:0000: retf 2: 2 bytes of parameters; 0 bytes of locals }\n{@stub} procedure ovl12_fn_0000(Color: Byte)" in text
    assert notes == ["ovl12: ovl12_fn_0000 is still used 1 more time(s) in the file after the rename; "
                     "`make rename APPLY=1` renames the uses"] or notes == []


def test_a_matching_source_is_a_no_op_even_when_wrapped_differently():
    text = UNIT.replace("{@stub} function ovl12_fn_0058(A: Byte): Word; begin end;",
                        "{@stub} function ovl12_fn_0058(A: Byte):\n  Word; begin end;")
    registry = [routine(0x0000, "ovl12_fn_0000"), routine(0x001F, "ovl12_e2"),
                routine(0x0058, "ovl12_fn_0058", "function ovl12_fn_0058(A: Byte): Word")]
    changes, notes = stubs.plan(text, "ovl12", registry)
    assert changes == [] and notes == []
    assert stubs.apply(text, changes) == text


def test_long_signatures_wrap_within_the_compiler_line_limit():
    sig = ("function ChooseFromList(Title, Prompt: String40; HeadingColor, LineColor, HighlightColor: Byte; "
           "Left, Top, Right, Bottom: ShortInt; List: PMenuLine; WithExit: Byte; var Redraw: Byte; "
           "var Choice: Integer; var Selected: PMenuLine): Char")
    lines = stubs.wrap("{@stub} ", sig, "; begin end;")
    assert all(len(l) <= stubs.LINE_LIMIT for l in lines) and len(lines) > 1
    assert lines[0].startswith("{@stub} function ChooseFromList(") and lines[-1].endswith("; begin end;")
    assert all(l.startswith("  ") for l in lines[1:])
    assert stubs.normalise(" ".join(l.strip() for l in lines).replace("{@stub} ", "").replace("; begin end;", "")) == sig


def test_unknown_stubs_are_reported_not_rewritten():
    changes, notes = stubs.plan(UNIT, "ovl12", [routine(0x0000, "ovl12_fn_0000")])
    assert changes == []
    assert any("no re/symbols.toml record for stub ovl12_e2" in n for n in notes)
    assert any("ovl12_fn_0058" in n for n in notes)


def test_cli_gates_and_writes(tmp_path, monkeypatch, capsys):
    src = tmp_path / "src"
    src.mkdir()
    (src / "OVL12.PAS").write_text(UNIT)
    monkeypatch.setattr(stubs, "SRC", src)
    monkeypatch.setattr(stubs, "registry", lambda path=None: REGISTRY)
    assert stubs.main(["ovl12"]) == 1
    out = capsys.readouterr().out
    assert "- {@stub} procedure ovl12_fn_0000; begin end;" in out
    assert "+ {@stub} procedure ovl12_fn_0000(Color: Byte); begin end;" in out
    assert (src / "OVL12.PAS").read_text() == UNIT
    assert stubs.main(["ovl12", "--write"]) == 0
    assert "procedure DrawThing(X, Y: Word)" in (src / "OVL12.PAS").read_text()
    assert stubs.main([]) == 0
    assert "every stub header matches" in capsys.readouterr().out
