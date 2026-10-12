unit RES09;
{ res09: resident unit, 880 bytes of code. Skeleton by tools/match/skeleton.py: every routine is a stub
  until decompiled (playbook 30). }
{$A-,F+,S-,R-,G-,I-}
interface
procedure res09_fn_0000;
procedure res09_fn_0137;
procedure res09_fn_02E8(LeftCol, TopRow, RightCol, BottomRow, FrameSet, TextColour: Byte; Text: string);
implementation

{ 03F1:0000: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure res09_fn_0000; begin end;
{ 03F1:0137: retf 8: 8 bytes of parameters; 12 bytes of locals }
{@stub} procedure res09_fn_0137; begin end;
{ 03F1:02E8: retf 16: 16 bytes of parameters; 42 bytes of locals }
{ Draws a window: clears rows TopRow..BottomRow, columns LeftCol..RightCol (res09_fn_0137), draws
  frame set FrameSet around them (res09_fn_0000) and centres Text on TopRow in colour TextColour
  (res06_fn_0626). Grid: a column is 16 pixels, a row 4 scanlines. The copy limit 40 in the callee
  says Text is really a string[40]; recorded as the generic string so the stub compiles alone.
  Signature from the pushes of the callers (bytes first, the string last) and the passes of the callee. }
{@stub} procedure res09_fn_02E8(LeftCol, TopRow, RightCol, BottomRow, FrameSet, TextColour: Byte; Text: string); begin end;

begin
end.
