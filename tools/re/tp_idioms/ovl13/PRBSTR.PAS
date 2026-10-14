(* Probe PRBSTR (ovl13, 2026-10-13): how TP 6.0 with $O+ passes a string literal to a far
   procedure and in what order it pushes the arguments, and how a function's locals (a byte
   result, a mixed Pointer/Byte list) are laid out. ovl13:0E82 calls ShowCharacterMessage(
   Who, Text, Row, Wait) with the literal 'sweeps' and has locals Count(bp-2), ?(bp-3), I(bp-4),
   ?(bp-5), Enemy far ptr (bp-6..bp-9), Bound(bp-0xA), string temp at bp-0x10.
   Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBSTR.PAS DISASM=1 *)
program PrbStrCall;
{$A-,O+,F+,S-,R-,G-,I-}
type
  PRec = ^TRec;
  TRec = record
    F: array[0..$20] of Byte;
  end;
var
  G: Byte;
  GR: PRec;

procedure ShowMsg(Who: Pointer; Text: string; Row, Wait: Byte); far;
begin
  if (Row <> 0) or (Wait <> 0) then
    G := Byte(Text[1]) + PRec(Who)^.F[0];
end;

function F1(Who, Target: Pointer): Boolean;
var
  Count: Byte;
  Extra: Byte;
  I: Byte;
  Saved: Byte;
  Enemy: PRec;
  Bound: Byte;
begin
  F1 := False;
  Count := G;
  Extra := 0;
  Bound := Count;
  for I := 1 to Bound do
  begin
    Enemy := GR;
    if Enemy = PRec(Who) then
      Saved := I;
    if Enemy^.F[0] = 0 then
      Inc(Extra);
  end;
  if Extra > 0 then
  begin
    ShowMsg(Target, 'sweeps', 10, 1);
    F1 := True;
  end;
end;

begin
  G := Byte(F1(GR, GR));
end.
