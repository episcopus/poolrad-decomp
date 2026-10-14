(* Probe PRB2AA0 (ovl13, 2026-10-14): idioms needed by ovl13:2AA0 (the aiming prompt). The original
  builds two strings: DrawTextAt(0,$17,$A,'Range = ' + ByteToText(Distance) + '  ') and a prompt
  'Next Prev Manual ' + Aim + 'Center Exit' assigned back to Aim (StrLCopy max $28), then
  ReadPromptChoice('Aim:', Aim, $D, $A, $F, 0, 0, ExtKey). Which source shapes and temp sizes do
  they give? ($F+ and $O+ as the unit.)
  Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRB2AA0.PAS DISASM=1 *)
program Prb2AA0;
{$A-,O+,F+,S-,R-,G+,I-}
type
  String40 = string[40];
var
  G: Byte;
  GAim: String40;

procedure DrawTextAt(Col, Row, Color: Byte; Text: string); far;
begin
  if Col + Row + Color > 0 then G := Byte(Text[0]);
end;

function ByteToText(Value: Byte): string; far;
begin
  ByteToText := 'x';
end;

function ReadPromptChoice(Title, Prompt: String40; TitleColor, WordColor, HotColor, ExtKeys,
  Animate: Byte; var ExtKey: Byte): Char; far;
begin
  ReadPromptChoice := 'N';
end;

function F1(P1, P2: Pointer; B1: Byte; ShowRange: Byte): Char;
var
  Aim: String40;
  ExtKey: Byte;
  Distance: Byte;
  Title: String40;
begin
  Aim := '';
  Distance := G;
  if ShowRange <> 0 then
    DrawTextAt(0, $17, $A, 'Range = ' + ByteToText(Distance) + '  ');
  Title := 'Aim:';
  Aim := 'Next Prev Manual ' + Aim + 'Center Exit';
  ExtKey := 0;
  F1 := ReadPromptChoice('Aim:', Aim, $D, $A, $F, 0, 0, ExtKey);
end;

begin
  G := Byte(F1(@G, @G, G, G));
end.
