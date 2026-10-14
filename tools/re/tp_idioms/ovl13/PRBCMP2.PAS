(* Probe PRBCMP2 (ovl13, 2026-10-13): ovl13:1351 compares the +$76 field with `jle` (`> 0`) and
   `jge` (`< MinRow`), both signed. Test ShortInt casts and a ShortInt local.
   Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBCMP2.PAS DISASM=1 *)
program PrbCmp2;
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

function A1(P: PRec): Boolean;
var
  Min: ShortInt;
begin
  Min := 13;
  A1 := False;
  if ShortInt(P^.Kind) > 0 then
    if ShortInt(P^.Kind) < Min then
      A1 := True;
end;

function A2(P: PRec): Boolean;
var
  Min: Byte;
begin
  Min := 13;
  A2 := False;
  if ShortInt(P^.Kind) > 0 then
    if ShortInt(P^.Kind) < Min then
      A2 := True;
end;

function A3(P: PRec): Boolean;
var
  Min: ShortInt;
begin
  Min := 13;
  A3 := False;
  if P^.Kind > 0 then
    if P^.Kind < Min then
      A3 := True;
end;

begin
  GP := nil;
  G := 0;
  if A1(GP) then G := 1;
  if A2(GP) then G := 2;
  if A3(GP) then G := 3;
end.
