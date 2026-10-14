{ Probe for ovl16:209F (playbook 30, batch 12). The race-limit lookup ds3DA3[Race, B9E] compiles
  to `mov di,ax; shl di,cl; add di,dx` (the index built in DI) only when the table is a two
  dimensional array; a flat array ds3DA3[Race*16 + B9E] shifts AX instead (`shl ax,cl`) and does
  not match the original. A constant second subscript (ds3DA3[Race, 6]) folds into the base
  displacement. }
{$A-,O+,F+,S-,R-,G-,I-}
program RecIdxProbe;
type
  PCharacter = ^TCharacter;
  TCharacter = record
    Pad: array[0..$FF] of Byte;
  end;
var
  Sel: PCharacter;
  Flat: array[0..$FF] of Byte;
  Rect: array[0..15, 0..15] of Byte;
  Race, B9E: ShortInt;
  V: Byte;

procedure V1; begin V := Flat[Race * 16 + B9E]; end;      { shl ax,cl (does not match) }
procedure V2; begin V := Rect[Race, B9E]; end;            { shl di,cl (matches) }
procedure V3; begin V := Rect[Race, 6]; end;              { constant column folds into the base }
procedure V4; begin V := Rect[Race, B9E + 2]; end;        { the +2 goes to the index (inc ax) }

begin
  V1; V2; V3; V4;
end.
