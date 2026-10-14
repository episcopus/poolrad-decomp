(* Probe PRBTURN (ovl13, 2026-10-13): the turn-undead table index at ovl13:1226 is
     mov al,[bp-0xb]; cwde; mov cx,ax     ; Band (ShortInt)
     les di,[bp-0xa]
     mov al,es:[di+0x76]; cwde
     mov dx,0xa; mul dx
     mov di,ax
     add di,cx
     mov al,[di+0x447]
   Ours gives `add ax,cx; mov di,ax`. Which source gives `mov di,ax; add di,cx`?
   Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBTURN.PAS DISASM=1 *)
program PrbTurn;
{$A-,O+,F+,S-,R-,G-,I-}
type
  PRec = ^TRec;
  TRec = record
    Pad: array[0..$75] of Byte;
    Kind: Byte;                 { at +$76 }
    SKind: ShortInt;
  end;
var
  Arr: array[0..$6E] of ShortInt;
  BArr: array[0..$6E] of Byte;
  GP: PRec;
  GB: ShortInt;

function A2(P: PRec; Band: ShortInt): ShortInt;
begin
  A2 := Arr[ShortInt(P^.Kind) * 10 + Band];
end;

function A5(P: PRec; Band: ShortInt): ShortInt;
begin
  A5 := Arr[P^.SKind * 10 + Band];
end;

function A6(P: PRec; Band: ShortInt): ShortInt;
begin
  A6 := Arr[10 * P^.Kind + Band];
end;

function A7(P: PRec; Band: ShortInt): ShortInt;
begin
  A7 := ShortInt(BArr[P^.Kind * 10 + Band]);
end;

function A8(P: PRec; Band: Integer): ShortInt;
begin
  A8 := Arr[P^.Kind * 10 + Band];
end;

begin
  GP := nil; GB := A2(GP, 1) + A5(GP, 2) + A6(GP, 3) + A7(GP, 4) + A8(GP, 5);
end.
