unit OVL29;
{ The wall view and GEO loader (whitepaper 5.2): SetWallDescriptors stores the four wall view
  descriptors (ds6A60..ds6A63) that ShowAreaView passes; CellInRange tests a 16x16 block map cell;
  ovl29_e4 reads the event byte of a map cell; ovl29_e5 draws the wall view and its overlay labels;
  LoadWallSet and Load3DMap load the WALLDEF and GEO data. Design doc whitepaper 5.2. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure ovl29_fn_0000;
procedure ovl29_fn_0143;
procedure SetWallDescriptors(Wall1, Wall2, Wall3, Wall4: Byte);
procedure DrawWallDescriptors;
procedure ovl29_fn_0211;
function CellInRange(Col, Row: ShortInt): Boolean;
function ovl29_e3(A, B: ShortInt; C: Byte): Byte;
function ovl29_e2(A, B, C: Byte): Byte;
function ovl29_e4(X, Y: ShortInt): Byte;
procedure StepDisplay;
procedure ovl29_e5(A, B, C: Byte);
procedure LoadWallSet;
procedure Load3DMap;
implementation
uses POOLVARS, RES07;
type
  { The GEO block ds6A5C: the event plane ovl29_e4 reads is the third 256 bytes at +$200. }
  PGeoBlock = ^TGeoBlock;
  TGeoBlock = record
    Unknown: array[0..$1FF] of Byte;  { +$0..+$1FF }
    Events: array[0..$FF] of Byte;    { +$200..+$2FF }
  end;

{ ovl29:0000: frame not read }
{@stub} procedure ovl29_fn_0000; begin end;
{ ovl29:0143: retf 6: 6 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl29_fn_0143; begin end;
{ ovl29:0155: retf 8: 8 bytes of parameters; 0 bytes of locals }
{ ovl29:0155. Stores the four wall view descriptors: A..D into ds6A60..ds6A63 (descriptor 1..4;
  whitepaper 5.2). Called by ovl26 ShowAreaView with the wall view ids. }
procedure SetWallDescriptors(Wall1, Wall2, Wall3, Wall4: Byte);
begin
  ds6A60 := Wall1;
  ds6A61 := Wall2;
  ds6A62 := Wall3;
  ds6A63 := Wall4;
end;
{ ovl29:0174. Draws the four wall view descriptors ds6A60..ds6A63 through res07_fn_2632 (A=2,
  B and D the descriptor's screen position/size, C=$B, E the descriptor, F=@ds260A's 8-byte
  structure, G=DrawBuf). Called by ovl29_e5. }
procedure DrawWallDescriptors;
begin
  res07_fn_2632(2, $10, $B, $2B, ds6A60, @ds260A, DrawBuf);
  res07_fn_2632(2, $3B, $B, 1, ds6A61, @ds260A, DrawBuf);
  res07_fn_2632(2, $3C, $B, 2, ds6A62, @ds260A, DrawBuf);
  res07_fn_2632(2, $3E, $B, $2A, ds6A63, @ds260A, DrawBuf);
end;
{ ovl29:0211: retf 8: 8 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl29_fn_0211; begin end;
{ ovl29:031F: retf 4: 4 bytes of parameters; 2 bytes of locals }
{ ovl29:031F. True when both X and Y are in 0..$F (a map cell inside the 16x16 block). Signed
  ShortInt parameters; the four compares are in the order X <= $F, X >= 0, Y <= $F, Y >= 0. Called
  by ovl29_e3, ovl29_e2, ovl29_e4 and ovl29_e5. }
function CellInRange(Col, Row: ShortInt): Boolean;
begin
  if (Col > $F) or (Col < 0) or (Row > $F) or (Row < 0) then
    CellInRange := False
  else
    CellInRange := True;
end;
{ ovl29:0350: retf 6: 6 bytes of parameters; 2 bytes of locals }
{@stub} function ovl29_e3(A, B: ShortInt; C: Byte): Byte; begin end;
{ ovl29:047B: retf 6: 6 bytes of parameters; 2 bytes of locals }
{@stub} function ovl29_e2(A, B, C: Byte): Byte; begin end;
{ ovl29:057A: retf 4: 4 bytes of parameters; 2 bytes of locals.
  Returns the event byte of the area map cell (X, Y), wrapping both into 0..15 first; the event
  plane is the third 256 bytes of the GEO block (whitepaper 4.2.1: bit 7 = interior). ShowAreaView
  asks for the party cell (ds6AAD, ds6AAE) and tests bit 7. }
{ ovl29:057A. BLOCKED (dec-5, 2026-10-12): the event byte of the cell (X, Y): outside 0..$F
  with ds84DC 0 or $A it returns 0, else it wraps X and Y into 0..$F and reads the event plane
  (the third 256 bytes of the GEO block ds6A5C, +$200 + Y*16 + X). Drafted; the block order needs
  the inverted condition and the record field folds $200, but the compiler then orders les di
  before add ax,dx while ours combines the index first, so it is left a stub. }
{@stub} function ovl29_e4(X, Y: ShortInt): Byte; begin end;
{ ovl29:05F3: retf 0: 0 bytes of parameters; 0 bytes of locals }
{ ovl29:05F3. Steps the picture display (res07_fn_1B52, the same call ovl34 uses after a
  direct blit). No parameters. Called by ovl29_fn_0143 and ovl29_e5. }
procedure StepDisplay;
begin
  res07_fn_1B52;
end;
{ ovl29:05FD: retf 6: 6 bytes of parameters; 24 bytes of locals.
  Draws the rest of the wall view: with ds6AAC at 0 it draws the four descriptors through
  DrawWallDescriptors, otherwise it calls ovl29_fn_0000; A and B are the party cell (ds6AAD, ds6AAE)
  and C the icon set of the marker (ds6AAF). }
{@stub} procedure ovl29_e5(A, B, C: Byte); begin end;
{ ovl29:0E08: retf 4: 4 bytes of parameters; 280 bytes of locals }
{@stub} procedure LoadWallSet; begin end;
{ ovl29:10C7: retf 2: 2 bytes of parameters; 272 bytes of locals }
{@stub} procedure Load3DMap; begin end;

begin
end.
