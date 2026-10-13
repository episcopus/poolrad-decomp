{ Probe FORBOUND (ovl09, 2026-10-13): how TP 6.0 compiles a for loop's bound.
  Compile with: make tpc SRC=tools/re/tp_idioms/ovl09/FORBOUND.PAS DISASM=1
  Result (TP 6.0 June 1991, default switches):
  - VarBound: `Count := G; for I := 1 to Count do` copies the bound into a hidden
    temporary (mov al,[bp-3]; mov [bp-5],al) and the frame grows by that slot.
  - ExprBound: `for I := 1 to T[0] do` evaluates the indexed expression straight into the
    hidden temporary (one slot, no second copy; the frame pads to even).
  Use the frame the original shows to tell which source form the original had: a bound
  variable means an extra copy, an expression bound means the evaluation is the only store.
  Found while matching ovl09:02EB/0255 (see re/learnings/ovl09.toml#for-loop-bound-temporary). }
program ForBound;
var
  G: Byte;
  T: array[0..3] of Byte;

function VarBound: Byte;
var
  I, Count: Byte;
begin
  VarBound := 0;
  Count := G;
  for I := 1 to Count do
    VarBound := VarBound + 1;
end;

function ExprBound: Byte;
var
  I: Byte;
begin
  ExprBound := 0;
  for I := 1 to T[0] do
    ExprBound := ExprBound + 1;
end;

begin
  G := 3;
  T[0] := 2;
  if VarBound = ExprBound then
    G := 0;
end.
