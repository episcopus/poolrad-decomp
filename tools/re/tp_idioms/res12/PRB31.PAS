{$A-,O+,F+,S-,R-,G-,I-}
program PRB31;
{ Probe: which local declaration gives a Byte function with sub sp,0x300, the save buffer based
  at [bp-0x2fe] and one Byte index at [bp-0x2ff]? 765 = 255*3 TSortRecs declared first is tried
  against a 216-byte array after a 551-byte preceding local. }
type
  TSortRec = record
    Head: Byte;
    Key: Byte;
    Val: Byte;
  end;
var
  ds6718: array[0..255] of TSortRec;
  G: Byte;
function Test(Who, Target: Pointer): Byte;
var
  Saved: array[1..255] of TSortRec;
  I: Byte;
begin
  Move(ds6718[1], Saved, 216);
  I := 1;
  Test := Saved[I].Key shr 1;
  Move(Saved, ds6718[1], 216);
end;
begin
  G := Test(nil, nil);
end.
