unit RES05;
{ res05 opens game files (res05_fn_025D) and keeps the 8X8D file number. SelectTileSet saves
  TileSet and stores a new one; RestoreTileSet puts the saved number back. }
{$A-,F+,S-,R-,G-,I+}
interface
type
  { A 40-character name: res05_fn_025D copies its two name arguments (the file name and its
    extension) with System_StrLCopy limit $28 (0802:028D, 0802:02A4). }
  String40 = string[40];
procedure res05_fn_0000;
procedure res05_fn_0020;
procedure res05_fn_0040;
procedure res05_fn_0105;
procedure res05_fn_0175;
procedure res05_fn_0193;
procedure res05_fn_0212;
function res05_fn_025D(A: String40; B: String40; C: Byte; var F: file): Byte;
procedure res05_fn_02EB;
procedure res05_fn_0356;
procedure res05_fn_0425;
procedure res05_fn_050F;
procedure res05_fn_05CD;
procedure res05_fn_06E7;
procedure res05_fn_0716;
procedure SelectTileSet(NewSet: Byte);
procedure RestoreTileSet;
implementation
uses POOLVARS;

{ 0802:0000: retf 6: 6 bytes of parameters; 0 bytes of locals }
{@stub} procedure res05_fn_0000; begin end;
{ 0802:0020: retf 6: 6 bytes of parameters; 0 bytes of locals }
{@stub} procedure res05_fn_0020; begin end;
{ 0802:0040: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure res05_fn_0040; begin end;
{ 0802:0105: retf 10: 10 bytes of parameters; 260 bytes of locals }
{@stub} procedure res05_fn_0105; begin end;
{ 0802:0175: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure res05_fn_0175; begin end;
{ 0802:0193: retf 6: 6 bytes of parameters; 42 bytes of locals }
{@stub} procedure res05_fn_0193; begin end;
{ 0802:0212: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure res05_fn_0212; begin end;
{ 0802:025D: retf 14: 14 bytes of parameters; 84 bytes of locals }
{@stub} function res05_fn_025D(A: String40; B: String40; C: Byte; var F: file): Byte; begin end;
{ 0802:02EB: retf 4: 4 bytes of parameters; 170 bytes of locals }
{@stub} procedure res05_fn_02EB; begin end;
{ 0802:0356: retf 8: 8 bytes of parameters; 772 bytes of locals }
{@stub} procedure res05_fn_0356; begin end;
{ 0802:0425: retf 4: 4 bytes of parameters; 770 bytes of locals }
{@stub} procedure res05_fn_0425; begin end;
{ 0802:050F: retf 16: 16 bytes of parameters; 6 bytes of locals }
{@stub} procedure res05_fn_050F; begin end;
{ 0802:05CD: retf 20: 20 bytes of parameters; 1110 bytes of locals }
{@stub} procedure res05_fn_05CD; begin end;
{ 0802:06E7: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure res05_fn_06E7; begin end;
{ 0802:0716: retf 18: 18 bytes of parameters; 574 bytes of locals }
{@stub} procedure res05_fn_0716; begin end;
{ 0802:094A. Saves TileSet in ds5377, then makes NewSet the current 8X8D file number.
  RestoreTileSet copies ds5377 back. ovl07 and ovl17 call this. }
procedure SelectTileSet(NewSet: Byte);
begin
  ds5377 := TileSet;
  TileSet := NewSet;
end;

{ 0802:095D. Puts back the TileSet that SelectTileSet saved in ds5377. ovl17 calls this. }
procedure RestoreTileSet;
begin
  TileSet := ds5377;
end;

begin
end.
