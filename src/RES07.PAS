unit RES07;
{ res07: resident unit, 10832 bytes of code. Skeleton by tools/match/skeleton.py: every routine is a stub
  until decompiled (playbook 30). }
{$A-,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure res07_fn_0000;
procedure res07_fn_007B;
procedure res07_fn_00CF(A: Byte);
procedure res07_fn_00FF;
procedure res07_fn_0111(Text: string; A, B, C: Byte; var Target);
procedure res07_fn_02A5(Data: Pointer; Offset: Word; A, B: Byte; Sprite: Pointer);
procedure res07_fn_066F;
procedure res07_fn_0710;
procedure res07_fn_08D4(Col, Row: Integer; PicIndex, Flags: Byte; Source, Dest: Pointer);
procedure res07_fn_0A33;
procedure res07_fn_0C0C;
procedure res07_fn_0D6C;
procedure res07_fn_0D71(Col, Row: Integer; PicIndex, Flags: Byte; Source, Dest: Pointer);
procedure res07_fn_0E01;
procedure res07_fn_0E28;
procedure res07_fn_0E33;
procedure res07_fn_0E48;
procedure res07_fn_0EC0;
procedure res07_fn_0EE2;
procedure res07_fn_0F56;
procedure res07_fn_102D;
procedure res07_fn_1042;
procedure res07_fn_10DC;
procedure res07_fn_140E;
procedure res07_fn_1484;
procedure res07_fn_1509;
procedure res07_fn_1514;
procedure res07_fn_1596;
procedure res07_fn_15C7(Source, Dest: Pointer);
procedure res07_fn_1708;
procedure res07_fn_1951(X, Y: Integer; Buf: Pointer);
procedure res07_fn_1A19;
procedure res07_fn_1B52;
procedure res07_fn_1E5C(P1, P2: Pointer; A: Word; B: Byte; P3: Pointer);
procedure res07_fn_248E(Height, Width: Word; ItemCount, AllocFlags: Byte; var Pic);
procedure res07_fn_2595(var Pic);
procedure res07_fn_2632;
procedure res07_fn_2A0D(A, B: Byte);
implementation

{ 0464:0000: retf 6: 6 bytes of parameters; 6 bytes of locals }
{@stub} procedure res07_fn_0000; begin end;
{ 0464:007B: retf 6: 6 bytes of parameters; 10 bytes of locals }
{@stub} procedure res07_fn_007B; begin end;
{ 0464:00CF: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} procedure res07_fn_00CF(A: Byte); begin end;
{ 0464:00FF: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure res07_fn_00FF; begin end;
{ 0464:0111: retf 14. Text is a string value. Target is untyped var so ovl32, ovl34,
  ovl28 and ovl11 can each pass their pointer variable: the routine frees it when it is not
  nil, then loads the picture there. }
{@stub} procedure res07_fn_0111(Text: string; A, B, C: Byte; var Target); begin end;
{ 0464:02A5: frame not read }
{@stub} procedure res07_fn_02A5(Data: Pointer; Offset: Word; A, B: Byte; Sprite: Pointer); begin end;
{ 0464:066F: frame not read }
{@stub} procedure res07_fn_066F; begin end;
{ 0464:0710: retf 14: 14 bytes of parameters; 0 bytes of locals }
{@stub} procedure res07_fn_0710; begin end;
{ 0464:08D4: retf 16: two Integers, two Bytes, two Pointers. DrawCellPicture passes the cell,
  the picture index, flags 0, a picture pointer and DrawBuf. }
{@stub} procedure res07_fn_08D4(Col, Row: Integer; PicIndex, Flags: Byte; Source, Dest: Pointer); begin end;
{ 0464:0A33: frame not read }
{@stub} procedure res07_fn_0A33; begin end;
{ 0464:0C0C: frame not read }
{@stub} procedure res07_fn_0C0C; begin end;
{ 0464:0D6C: retf 16: 16 bytes of parameters; 0 bytes of locals }
{@stub} procedure res07_fn_0D6C; begin end;
{ 0464:0D71: retf 16: same frame as res07_fn_08D4. Bit 0 of Flags is tested. }
{@stub} procedure res07_fn_0D71(Col, Row: Integer; PicIndex, Flags: Byte; Source, Dest: Pointer); begin end;
{ 0464:0E01: frame not read }
{@stub} procedure res07_fn_0E01; begin end;
{ 0464:0E28: frame not read }
{@stub} procedure res07_fn_0E28; begin end;
{ 0464:0E33: frame not read }
{@stub} procedure res07_fn_0E33; begin end;
{ 0464:0E48: frame not read }
{@stub} procedure res07_fn_0E48; begin end;
{ 0464:0EC0: frame not read }
{@stub} procedure res07_fn_0EC0; begin end;
{ 0464:0EE2: frame not read }
{@stub} procedure res07_fn_0EE2; begin end;
{ 0464:0F56: frame not read }
{@stub} procedure res07_fn_0F56; begin end;
{ 0464:102D: frame not read }
{@stub} procedure res07_fn_102D; begin end;
{ 0464:1042: frame not read }
{@stub} procedure res07_fn_1042; begin end;
{ 0464:10DC: frame not read }
{@stub} procedure res07_fn_10DC; begin end;
{ 0464:140E: frame not read }
{@stub} procedure res07_fn_140E; begin end;
{ 0464:1484: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} procedure res07_fn_1484; begin end;
{ 0464:1509: frame not read }
{@stub} procedure res07_fn_1509; begin end;
{ 0464:1514: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure res07_fn_1514; begin end;
{ 0464:1596: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} procedure res07_fn_1596; begin end;
{ 0464:15C7: retf 8: two Pointers. Returns at once when either is nil. }
{@stub} procedure res07_fn_15C7(Source, Dest: Pointer); begin end;
{ 0464:1708: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure res07_fn_1708; begin end;
{ 0464:1951: frame not read }
{@stub} procedure res07_fn_1951(X, Y: Integer; Buf: Pointer); begin end;
{ 0464:1A19: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure res07_fn_1A19; begin end;
{ 0464:1B52: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure res07_fn_1B52; begin end;
{ 0464:1E5C: retf 16: 16 bytes of parameters; 68 bytes of locals }
{@stub} procedure res07_fn_1E5C(P1, P2: Pointer; A: Word; B: Byte; P3: Pointer); begin end;
{ 0464:248E: retf 12. GetMems a picture (height * width, plus a pixel buffer when bit 0
  of AllocFlags is set) and stores the pointer. Pic is untyped so ovl11 can pass its
  PT8x8Bank banks. }
{@stub} procedure res07_fn_248E(Height, Width: Word; ItemCount, AllocFlags: Byte; var Pic); begin end;
{ 0464:2595: retf 4: one var Pointer. Frees the picture (FreeMem) and nils the pointer.
  Pic is untyped so ovl28 can pass its typed sprite banks. }
{@stub} procedure res07_fn_2595(var Pic); begin end;
{ 0464:2632: retf 18: 18 bytes of parameters; 36 bytes of locals }
{@stub} procedure res07_fn_2632; begin end;
{ 0464:2A0D: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure res07_fn_2A0D(A, B: Byte); begin end;

begin
end.
