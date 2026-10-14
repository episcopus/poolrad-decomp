program PRB2C3D;
{$A-,F+,S-,R-,G-,I-}
{ Probe: how TP 6.0 ($A-) lays out a 4-byte Pointer local together with byte locals.
  ovl13:2C3D has sub sp,6 and only touches a 4-byte local at [bp-5] and [bp-3].
  Which declaration gives that? }
type
  PCharacter = ^Byte;
procedure I1;
var A: Pointer;
begin A := nil; end;
procedure I2;
var A: Pointer; X: Byte;
begin A := nil; X := 0; end;
procedure I3;
var X: Byte; A: Pointer;
begin X := 0; A := nil; end;
procedure I4;
var X: Byte; A: Pointer; Y: Byte;
begin X := 0; A := nil; Y := 0; end;
procedure I5;
var A: Pointer; X, Y: Byte;
begin A := nil; X := 0; Y := 0; end;
procedure I6;
var X, Y: Byte; A: Pointer;
begin X := 0; Y := 0; A := nil; end;
procedure I7;
var A: Pointer; X: Word;
begin A := nil; X := 0; end;
procedure I8;
var X: Word; A: Pointer;
begin X := 0; A := nil; end;
procedure I9;
var A: PCharacter; X: Byte;
begin A := nil; X := 0; end;
begin
  I1; I2; I3; I4; I5; I6; I7; I8; I9;
end.
