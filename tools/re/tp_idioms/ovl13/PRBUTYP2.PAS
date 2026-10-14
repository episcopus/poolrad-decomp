(* Probe PRBUTYP2 (ovl13, 2026-10-13): the callee must write 4 zero bytes through an untyped
   `var` parameter (ovl13:1351). Direct assignment is Error 43. Test typecast forms.
   Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBUTYP2.PAS DISASM=1 *)
program PrbUTyp2;
{$A-,O+,F+,S-,R-,G-,I-}
type
  PRec = ^TRec;
  TRec = record B: Byte; end;

function A1(Who: Pointer; var Sel): Boolean;
var P: PRec;
begin
  P := nil;
  PRec(Sel) := P;
  A1 := False;
end;

function A2(Who: Pointer; var Sel): Boolean;
var P: PRec;
begin
  P := nil;
  PRec(Pointer(Sel)) := P;
  A2 := False;
end;

function A4(Who: Pointer; var Sel): Boolean;
var P: PRec;
begin
  P := nil;
  Move(P, Sel, 4);
  A4 := False;
end;

var
  P: PRec;
  D: Byte;
begin
  P := nil;
  D := 0;
  if A1(nil, P) then D := 1;
  if A2(nil, P) then D := 2;

  if A4(nil, P) then D := 4;
end.
