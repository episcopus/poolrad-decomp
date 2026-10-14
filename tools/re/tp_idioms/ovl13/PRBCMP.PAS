(* Probe PRBCMP (ovl13, 2026-10-13): ovl13:13C4 emits `cmp byte [..+0x76],0; jle skip` for what
   looks like `X > 0` on a Byte field, but jle is a signed jump. Which source form gives jle?
   Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBCMP.PAS DISASM=1 *)
program PrbCmp;
{$A-,O+,F-,S-,R-,G-,I-}
type
  PRec = ^TRec;
  TRec = record
    Pad: array[0..$75] of Byte;
    Kind: Byte;
  end;
var
  GP: PRec;
  G: Byte;
  H: ShortInt;

function A1(P: PRec): Boolean;
begin
  A1 := P^.Kind > 0;
end;

function A2(P: PRec): Boolean;
begin
  A2 := ShortInt(P^.Kind) > 0;
end;

function A3(P: PRec): Boolean;
begin
  A3 := P^.Kind <= 0;
end;

function A4(P: PRec): Boolean;
begin
  if P^.Kind > 0 then
    A4 := False
  else
    A4 := True;
end;

begin
  GP := nil;
  G := 0;
  H := 0;
  if A1(GP) then G := 1;
  if A2(GP) then G := 2;
  if A3(GP) then G := 3;
  if A4(GP) then G := 4;
end.
