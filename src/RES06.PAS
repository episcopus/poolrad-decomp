unit RES06;
{ Screen text output (whitepaper 5.15), partly decompiled: ShowMessageLine shows a message on the
  bottom line and waits for a key; the rest are stubs. }
{$A-,F+,S-,R-,G-,I-}
interface
type
  String40 = string[40];
procedure SetEgaFillRegisters;
procedure SetActivePage(Plane: Byte);
procedure SetPlaneSegment(Plane: Byte);
procedure res06_fn_00B7(A, B, C, D: ShortInt; E, F: Byte);
procedure res06_fn_017C;
procedure res06_fn_01DF(A, B, C, D, Glyph, F: Byte);
procedure res06_fn_05EB(A, Row, B, Width: Byte);
procedure res06_fn_0626(A, Row, Color: Byte; Text: string);
procedure res06_fn_06A7;
procedure res06_fn_0714;
procedure res06_fn_0768(A, B, C, D, E, F: Byte; Text: string);
function res06_fn_09E3(Prompt: string; A: Byte; MaxLen: Byte): string;
procedure res06_fn_0B66;
procedure ShowMessageLine(Color: Byte; Text: String40);
function GameClock: Longint;
procedure res06_fn_0CAB;
procedure res06_fn_0D68(Text: string; Color: Byte);
procedure DelayCounted;
procedure res06_fn_0DD3(Left, Top, Right, Bottom: Byte);
implementation
uses Crt, Dos, POOLVARS, RES04;

{ 0709:0000: retf 0: 0 bytes of parameters; 0 bytes of locals }
{ 0709:0000. Sets the EGA Graphics Controller registers for the picture fill: GC 0..5 to 0
  (set/reset, enable set/reset, colour compare, data rotate, read map select, mode), GC 7 to
  $0F (colour don't care) and GC 8 to $FF (bit mask), then the Sequencer Map Mask (SC 2) to $0F.
  Port I/O only; no parameters. }
procedure SetEgaFillRegisters;
begin
  Port[$3CE] := 0;  Port[$3CF] := 0;
  Port[$3CE] := 1;  Port[$3CF] := 0;
  Port[$3CE] := 2;  Port[$3CF] := 0;
  Port[$3CE] := 3;  Port[$3CF] := 0;
  Port[$3CE] := 4;  Port[$3CF] := 0;
  Port[$3CE] := 5;  Port[$3CF] := 0;
  Port[$3CE] := 7;  Port[$3CF] := $0F;
  Port[$3CE] := 8;  Port[$3CF] := $FF;
  Port[$3C4] := 2;  Port[$3C5] := $0F;
end;
{ 0709:0071: retf 2: 2 bytes of parameters; 0 bytes of locals }
{ 0709:0071. Sets the EGA/VGA plane the video BIOS page A points at: writes AH=5 (set active
  display page) and AL=A into Regs and calls Intr($10), then stores the selected plane's segment
  (Plane shl 9 + $A000) in ds4A16. Called by res08_init. }
procedure SetActivePage(Plane: Byte);
begin
  Regs.AH := 5;
  Regs.AL := Plane;
  Intr($10, Regs);
  ds4A16 := Plane shl 9 + $A000;
end;
{ 0709:00A0: retf 2: 2 bytes of parameters; 0 bytes of locals }
{ 0709:00A0. Stores the EGA/VGA plane segment of Plane (Plane shl 9 + $A000) in ds4A18. Called by
  res06_fn_00B7 and res08_init. }
procedure SetPlaneSegment(Plane: Byte);
begin
  ds4A18 := Plane shl 9 + $A000;
end;
{ 0709:00B7: retf 12: 12 bytes of parameters; 10 bytes of locals }
{@stub} procedure res06_fn_00B7(A, B, C, D: ShortInt; E, F: Byte); begin end;
{ 0709:017C: retf 0: 0 bytes of parameters; 18 bytes of locals }
{@stub} procedure res06_fn_017C; begin end;
{ 0709:01DF: retf 12: 12 bytes of parameters; 18 bytes of locals.
  Draws one rune glyph of the code wheel question as a font character (CheckCodeWheel passes the rune
  index + $40): A and B the screen position, Glyph the character, the rest still open. }
{@stub} procedure res06_fn_01DF(A, B, C, D, Glyph, F: Byte); begin end;
{ 0709:05EB: retf 8: 8 bytes of parameters; 0 bytes of locals }
{ 0709:05EB. Clears (or fills) Width cells of a row: when the column Width is in 0..$27 and the
  row B is in 0..$18 it calls res06_fn_01DF(Width, B, Row, A, $20, 1). BLOCKED (dec-5,
  2026-10-12): the body is settled as two set membership tests, `if not (Width in [0..$27]) then
  Exit; if not (B in [0..$18]) then Exit; ...` (the never-true lower-bound compares and the Exit
  block come from the set), but the routine does not match because a literal-pool byte 64 before the
  entry differs (ours FF, original F8): the pool belongs to the preceding res06_fn_01DF, still a
  stub, so decompile 01DF first. Called by ovl21_e6, ClearPromptLine, res06_fn_09E3, ShowMessageLine and
  res06_fn_0D68. }
{@stub} procedure res06_fn_05EB(A, Row, B, Width: Byte); begin end;
{ 0709:0626: retf 10: 10 bytes of parameters; 260 bytes of locals }
{@stub} procedure res06_fn_0626(A, Row, Color: Byte; Text: string); begin end;
{ 0709:06A7: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure res06_fn_06A7; begin end;
{ 0709:0714: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure res06_fn_0714; begin end;
{ 0709:0768: retf 16; six bytes and a string; ovl04 passes (1, $11, $26, $16, $A, 1, message). }
{@stub} procedure res06_fn_0768(A, B, C, D, E, F: Byte; Text: string); begin end;
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
{ 0709:0C3F. The game clock in hundredths of a second: reads the DOS time (GetTime) and returns
  Hour * 360000 + Minute * 6000 + Second * 100 + Sec100. Hour * 360000 is a LongInt multiply,
  Minute * 6000 and Second * 100 are Word multiplies (the high word of the product is dropped,
  QUIRK 0709:0C75, 0709:0C85). Called by WaitKeyOrTimeout, ShowTitleScreen, AnimateFinalPicture and
  ReadPromptChoice. }
function GameClock: Longint;
var
  Hour, Minute, Second, Sec100: Word;
begin
  GetTime(Hour, Minute, Second, Sec100);
  GameClock := Hour * 360000 + Minute * 6000 + Second * 100 + Sec100;
end;
{ 0709:0CAB: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure res06_fn_0CAB; begin end;
{ 0709:0D68: retf 6: 6 bytes of parameters; 42 bytes of locals.
  Shows the Text and waits: CheckCodeWheel passes the failure message of a wrong code word and the
  colour 14. }
{ 0709:0D68. BLOCKED (dec-5, 2026-10-12): shows Text on the bottom line in colour Color
  (res06_fn_05EB clears the row, res06_fn_0626 shows the text, DelayCounted waits, res06_fn_05EB
  clears again). Our frame is 256 bytes too big (a string temp our source creates), so it is left
  a stub. }
{@stub} procedure res06_fn_0D68(Text: string; Color: Byte); begin end;
{ 0709:0DBE: retf 0: 0 bytes of parameters; 0 bytes of locals }
{ 0709:0DBE. A delay of ds49E2 * 225 milliseconds (Crt.Delay). No parameters. Called while
  drawing many screens (ovl03, ovl10, ovl12, ovl13, ovl18, ovl19, ovl20). }
procedure DelayCounted;
begin
  Delay(ds49E2 * 225);
end;
{ 0709:0DD3: retf 8: 8 bytes of parameters; 12 bytes of locals }
{@stub} procedure res06_fn_0DD3(Left, Top, Right, Bottom: Byte); begin end;

begin
end.
