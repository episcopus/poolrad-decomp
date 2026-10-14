(* Probe PRBUTYP (ovl13, 2026-10-13): how does ovl13:1351 write 4 bytes (0) through an untyped
   `var` parameter? It emits:
     les di,ptr [bp+6]; xor ax,ax; mov es:[di],ax; mov es:[di+2],ax
   which is `Selected := nil` for a PCharacter. But the parameter must be untyped to accept both
   TurnUndead's PCharacter and ovl09 TryTurnUndead's Byte Done. Try the untyped form and a cast.
   Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBUTYP.PAS DISASM=1 *)
program PrbUTyp;
{$A-,O+,F+,S-,R-,G-,I-}
type
  PRec = ^TRec;
  TRec = record B: Byte; end;

function A(Who: Pointer; var Sel): Boolean;
begin
  Sel := nil;
  A := False;
end;

var
  P: PRec;
  D: Byte;
begin
  P := nil;
  D := 0;
  if A(nil, P) then D := 1;
  if A(nil, D) then D := 2;
end.
