{$A-,F+,S-,R-,G-,I-}
program PRB17;
{ Probe for res12:1892 (playbook 30).
  Questions:
  1. How does TP 6.0 compile `X div 4` for a Word local: one `mov cl,2; shr ax,cl` or two `shr ax,1`?
  2. Same for `X shr 2`.
  3. What local declaration order puts a Word at [bp-8], a Word at [bp-6] and a
     far Pointer at [bp-4]?
  4. How is `PPicture(P)^.Pixels^[N]` compiled (pointer field load plus index add)? }
type
  TByteArray = array[0..0] of Byte;
  PByteArray = ^TByteArray;
  TPicture = record
    Header: array[0..$10] of Byte;
    ByteSize: Word;
    Pixels: PByteArray;
    Data: array[0..0] of Byte;
  end;
  PPicture = ^TPicture;
var
  Glob: Word;
  DstPic: Pointer;
  Row: Byte;

procedure Rows(DivSel, ShrSel: Byte);
var
  RowBytes, PixelBytes: Word;
  Pic: Pointer;
begin
  RowBytes := Glob;
  PixelBytes := RowBytes div 4;
  if DivSel = 1 then
    PixelBytes := PixelBytes shr 2;
  if ShrSel = 1 then
    PixelBytes := PixelBytes shr 2;
  Move(PPicture(Pic)^.Pixels^[0], PPicture(DstPic)^.Pixels^[Row * RowBytes], RowBytes);
end;

begin
  Rows(1, 1);
end.
