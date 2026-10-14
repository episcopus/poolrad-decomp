program PTYPE;
{ Probe (ovl12_e1 work): TP 6.0 rejects a procedural-type assignment whose routine has other parameter types
  (Error 143, Invalid procedure or function reference). H[0] := X with a PC, PC, Byte routine into a PC, PA, Byte type. }
type
  PC = ^TC;
  TC = record A: Byte; end;
  PA = ^TA;
  TA = record B: Byte; end;
  TH = procedure(Who: PC; Aff: PA; Mode: Byte);
var
  H: array[0..3] of TH;
procedure X(Who: PC; Other: PC; Mode: Byte);
begin
end;
begin
  H[0] := X;
end.
