(* Probe PRBUTYP3 (ovl13, 2026-10-13): the nil store through an untyped var parameter. Target bytes
   (ovl13:135B): les di,ptr [bp+6]; xor ax,ax; mov es:[di],ax; mov es:[di+2],ax.
   Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBUTYP3.PAS DISASM=1 *)
program PrbUTyp3;
{$A-,O+,F+,S-,R-,G-,I-}
type
  PRec = ^TRec;
  TRec = record B: Byte; end;

function A1(Who: Pointer; var Sel): Boolean;
begin
  PRec(Sel) := nil;
  A1 := False;
end;

function A2(Who: Pointer; var Sel): Boolean;
var P: PRec;
begin
  P := nil;
  PRec(Sel) := P;
  A2 := False;
end;

var
  P: PRec;
  D: Byte;
begin
  P := nil;
  D := 0;
  if A1(nil, P) then D := 1;
  if A2(nil, P) then D := 2;
end.
