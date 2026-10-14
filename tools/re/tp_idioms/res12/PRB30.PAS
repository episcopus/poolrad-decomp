{$A-,O+,F+,S-,R-,G-,I-}
program PRB30;
{ Probe: frame layout of a Byte function that saves array[1..72] of TSortRec to a local and
  uses one Byte index. Which offset does the compiler give the local array and the index? }
type
  TSortRec = record
    Head: Byte;
    Key: Byte;
    Val: Byte;
  end;
var
  ds6718: array[0..255] of TSortRec;
var
  G: Byte;
function Test(Who, Target: Pointer): Byte;
var
  Saved: array[1..72] of TSortRec;
  I: Byte;
begin
  Move(ds6718[1], Saved, SizeOf(Saved));
  I := 1;
  Test := Saved[I].Key shr 1;
  Move(Saved, ds6718[1], SizeOf(Saved));
end;
begin
  G := Test(nil, nil);
end.
