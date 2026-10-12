unit RES06;
{ Screen text output (whitepaper 5.15), partly decompiled: ShowMessageLine shows a message on the
  bottom line and waits for a key; the rest are stubs. }
{$A-,F+,S-,R-,G-,I-}
interface
type
  String40 = string[40];
procedure res06_fn_0000;
procedure res06_fn_0071(A: Byte);
procedure res06_fn_00A0(A: Byte);
procedure res06_fn_00B7(A, B, C, D: ShortInt; E, F: Byte);
procedure res06_fn_017C;
procedure res06_fn_01DF(A, B, C, D, Glyph, F: Byte);
procedure res06_fn_05EB(A, Row, B, Width: Byte);
procedure res06_fn_0626(A, Row, Color: Byte; Text: string);
procedure res06_fn_06A7;
procedure res06_fn_0714;
procedure res06_fn_0768;
function res06_fn_09E3(Prompt: string; A: Byte; MaxLen: Byte): string;
procedure res06_fn_0B66;
procedure ShowMessageLine(Color: Byte; Text: String40);
procedure res06_fn_0C3F;
procedure res06_fn_0CAB;
procedure res06_fn_0D68(Text: string; Color: Byte);
procedure res06_fn_0DBE;
procedure res06_fn_0DD3(A, B, Width, D: Byte);
implementation
uses RES04;

{ 0709:0000: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure res06_fn_0000; begin end;
{ 0709:0071: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure res06_fn_0071(A: Byte); begin end;
{ 0709:00A0: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure res06_fn_00A0(A: Byte); begin end;
{ 0709:00B7: retf 12: 12 bytes of parameters; 10 bytes of locals }
{@stub} procedure res06_fn_00B7(A, B, C, D: ShortInt; E, F: Byte); begin end;
{ 0709:017C: retf 0: 0 bytes of parameters; 18 bytes of locals }
{@stub} procedure res06_fn_017C; begin end;
{ 0709:01DF: retf 12: 12 bytes of parameters; 18 bytes of locals.
  Draws one rune glyph of the code wheel question as a font character (CheckCodeWheel passes the rune
  index + $40): A and B the screen position, Glyph the character, the rest still open. }
{@stub} procedure res06_fn_01DF(A, B, C, D, Glyph, F: Byte); begin end;
{ 0709:05EB: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure res06_fn_05EB(A, Row, B, Width: Byte); begin end;
{ 0709:0626: retf 10: 10 bytes of parameters; 260 bytes of locals }
{@stub} procedure res06_fn_0626(A, Row, Color: Byte; Text: string); begin end;
{ 0709:06A7: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure res06_fn_06A7; begin end;
{ 0709:0714: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure res06_fn_0714; begin end;
{ 0709:0768: retf 16: 16 bytes of parameters; 294 bytes of locals }
{@stub} procedure res06_fn_0768; begin end;
{ 0709:09E3: retf 8: 8 bytes of parameters; 812 bytes of locals.
  The line reader: shows the Prompt and returns what the player types as its string result
  (the caller keeps the result pointer: retf 8 pops Prompt, A and B only). CheckCodeWheel asks for the
  code word with it. }
{@stub} function res06_fn_09E3(Prompt: string; A: Byte; MaxLen: Byte): string; begin end;
{ 0709:0B66: retf 6: 6 bytes of parameters; 346 bytes of locals }
{@stub} procedure res06_fn_0B66; begin end;
{ 0709:0BF5: show a one-line message on row 24 and wait for a key (whitepaper 5.15). }
procedure ShowMessageLine(Color: Byte; Text: String40);
var
  Key: Char;
begin
  res06_fn_05EB(0, 24, 0, 40);
  res06_fn_0626(0, 24, Color, Text);
  Key := ReadGameKey;
end;
{ 0709:0C3F: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure res06_fn_0C3F; begin end;
{ 0709:0CAB: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure res06_fn_0CAB; begin end;
{ 0709:0D68: retf 6: 6 bytes of parameters; 42 bytes of locals.
  Shows the Text and waits: CheckCodeWheel passes the failure message of a wrong code word and the
  colour 14. }
{@stub} procedure res06_fn_0D68(Text: string; Color: Byte); begin end;
{ 0709:0DBE: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure res06_fn_0DBE; begin end;
{ 0709:0DD3: retf 8: 8 bytes of parameters; 12 bytes of locals }
{@stub} procedure res06_fn_0DD3(A, B, Width, D: Byte); begin end;

begin
end.
