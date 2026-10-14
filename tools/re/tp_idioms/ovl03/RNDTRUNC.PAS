program RNDTRUNC;
{ Probe for ovl03:0234 (RandomCommand). Roll := Trunc(Random(Range)) compiles to the Random call,
  then xor dx,dx and two runtime calls (the Real conversions) before the byte store. The plain
  Roll := Random(Range) and Roll := Byte(Random(Range)) have no calls. Run:
  make tpc SRC=tools/re/tp_idioms/ovl03/RNDTRUNC.PAS DISASM=1 }
var
  Range: Byte;
  Roll: Byte;
begin
  Roll := Trunc(Random(Range));
end.
