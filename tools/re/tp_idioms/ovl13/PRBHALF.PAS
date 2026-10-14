(* Probe PRBHALF (ovl13, 2026-10-13): ovl13:0E52 is
     mov al,[bp+6]; mov [bp-2],al
     mov al,[ds6DE3]; shr al,1; jae +; inc byte [bp-2]
     mov al,[bp-2]; xor ah,ah; shr ax,1; mov [bp-1],al
   Semantically Value + (bit0 of ds6DE3), then div 2. Which source gives the
   `shr al,1; jae` bit test rather than `test al,1`? Candidates: Odd, and 1, etc.
   Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBHALF.PAS DISASM=1 *)
program PrbHalf;
{$A-,F+}
var
  G: Byte;

function F1(Value: Byte): Byte;
var C: Byte;
begin
  C := Value;
  if Odd(G) then Inc(C);
  F1 := C shr 1;
end;

function F2(Value: Byte): Byte;
begin
  F2 := (Value + (G and 1)) shr 1;
end;

function F3(Value: Byte): Byte;
var C: Byte;
begin
  C := Value;
  if (G and 1) <> 0 then Inc(C);
  F3 := C shr 1;
end;

function F4(Value: Byte): Byte;
begin
  F4 := (Value + Ord(Odd(G))) shr 1;
end;

begin
  G := F1(G) + F2(G) + F3(G) + F4(G);
end.
