unit OVL29;
{ GeoLoad: overlay unit, 4619 bytes of code. Skeleton by tools/match/skeleton.py: every routine is a stub
  until decompiled (playbook 30). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure ovl29_fn_0000;
procedure ovl29_fn_0143;
procedure ovl29_e1(A, B, C, D: Byte);
procedure ovl29_fn_0174;
procedure ovl29_fn_0211;
procedure ovl29_fn_031F;
function ovl29_e3(A, B: ShortInt; C: Byte): Byte;
function ovl29_e2(A, B, C: Byte): Byte;
function ovl29_e4(X, Y: ShortInt): Byte;
procedure ovl29_fn_05F3;
procedure ovl29_e5(A, B, C: Byte);
procedure LoadWallSet;
procedure Load3DMap;
implementation

{ ovl29:0000: frame not read }
{@stub} procedure ovl29_fn_0000; begin end;
{ ovl29:0143: retf 6: 6 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl29_fn_0143; begin end;
{ ovl29:0155: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl29_e1(A, B, C, D: Byte); begin end;
{ ovl29:0174: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl29_fn_0174; begin end;
{ ovl29:0211: retf 8: 8 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl29_fn_0211; begin end;
{ ovl29:031F: retf 4: 4 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl29_fn_031F; begin end;
{ ovl29:0350: retf 6: 6 bytes of parameters; 2 bytes of locals }
{@stub} function ovl29_e3(A, B: ShortInt; C: Byte): Byte; begin end;
{ ovl29:047B: retf 6: 6 bytes of parameters; 2 bytes of locals }
{@stub} function ovl29_e2(A, B, C: Byte): Byte; begin end;
{ ovl29:057A: retf 4: 4 bytes of parameters; 2 bytes of locals.
  Returns the event byte of the area map cell (X, Y), wrapping both into 0..15 first; the event
  plane is the third 256 bytes of the GEO block (whitepaper 4.2.1: bit 7 = interior). ShowAreaView
  asks for the party cell (ds6AAD, ds6AAE) and tests bit 7. }
{@stub} function ovl29_e4(X, Y: ShortInt): Byte; begin end;
{ ovl29:05F3: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl29_fn_05F3; begin end;
{ ovl29:05FD: retf 6: 6 bytes of parameters; 24 bytes of locals.
  Draws the rest of the wall view: with ds6AAC at 0 it draws the four descriptors through
  ovl29_fn_0174, otherwise it calls ovl29_fn_0000; A and B are the party cell (ds6AAD, ds6AAE)
  and C the icon set of the marker (ds6AAF). }
{@stub} procedure ovl29_e5(A, B, C: Byte); begin end;
{ ovl29:0E08: retf 4: 4 bytes of parameters; 280 bytes of locals }
{@stub} procedure LoadWallSet; begin end;
{ ovl29:10C7: retf 2: 2 bytes of parameters; 272 bytes of locals }
{@stub} procedure Load3DMap; begin end;

begin
end.
