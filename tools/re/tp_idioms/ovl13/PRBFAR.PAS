(* Probe PRBFAR (ovl13, 2026-10-13): with the far-call switch and no word alignment, where does a
  `with Who^.Combat^` hidden temp land for a far procedure with a named byte local? ovl13:0000
  (far, A-) has sub sp,6 and its hidden temp offset word at the odd offset [bp-5], with [bp-1] and
  [bp-6] never read.
  Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBFAR.PAS DISASM=1 *)
program PrbFar;
{$A-,F+}
type
  PComb = ^TComb;
  TComb = record FA: Byte; FB: Byte; FC: Byte; FInit: ShortInt; FP4: array[4..5] of Byte; end;
  PChar = ^TChar;
  TChar = record Pad0: array[0..$107] of Byte; Combat: PComb; end;
var
  G: PChar;

procedure WithOneName(Who: PChar);
var
  U: Byte;
begin
  with Who^.Combat^ do
  begin
    FA := 0;
    FB := 1;
  end;
  U := 0;
end;

procedure WithTwoNames(Who: PChar);
var
  U, V: Byte;
begin
  with Who^.Combat^ do
  begin
    FA := 0;
    FB := 1;
  end;
  U := 0;
  V := 0;
end;

begin
  WithOneName(G);
  WithTwoNames(G);
end.
