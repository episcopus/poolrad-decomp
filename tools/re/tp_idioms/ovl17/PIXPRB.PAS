{ Probe: how to index the Pixels pointer field of TMemPic (ovl32's record) in TP 6.0.
  Question: does `Rec^.Pixels[I]` compile, or is `PByteArray(Rec^.Pixels)^[I]` needed? }
{$F+,S-,R-,I-}
program PixProbe;

type
  PMemPic = ^TMemPic;
  TMemPic = record
    Head: array[0..$10] of Byte;
    ByteSize: Word;
    Pixels: ^Byte;
    Tail: array[0..20000] of Byte;
  end;
  PByteArray = ^TByteArray;
  TByteArray = array[0..65519] of Byte;

var
  D: Pointer;
  P: PMemPic;
  I: Word;

procedure B;
begin
  PByteArray(PMemPic(D)^.Pixels)^[I] := 0;
end;

procedure E;
begin
  P^.Pixels^ := 0;
end;

begin
  B;
  E;
end.
