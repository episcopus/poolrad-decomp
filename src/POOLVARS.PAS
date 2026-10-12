unit POOLVARS;
{ Game globals whose owning unit is not known yet. Names: dsXXXX is the DS offset
  (re/dseg.toml may give a better name later); others are named in re/dseg.toml. }
{$A-,F+,S-,R-,G-,I-}
interface
uses Dos;
type
  { The record ds49D2 points at: the game's running state. Its owning unit is not known yet
    (res07, res12 and the overlays all read it), so only fields a unit has proven are declared;
    the filler keeps every field at its original offset. }
  TGameState = record
    Unknown1: array[0..$185] of Byte;  { $0000..$0185: not decompiled yet }
    MapX: Word;                        { $0186: the party's column in the area map grid (44 wide) }
    MapY: Word;                        { $0188: the party's row }
    Unknown2: array[0..$41] of Byte;   { $018A..$01CB: not decompiled yet }
    ForceWallView: Word;               { $01CC: nonzero: ovl26_e1 shows the wall view whatever AreaViewKind says }
    Unknown3: array[0..$27] of Byte;   { $01CE..$01F5: not decompiled yet }
    ShowWallOverlays: Word;            { $01F6: nonzero: ovl26_e1 clears ds6AAC, so ovl29_e5 draws the overlay labels }
    Unknown4: array[0..1] of Byte;     { $01F8..$01F9: not decompiled yet }
    WallIndexOutside: Word;            { $01FA: the ds0C26 wall id index ovl26_e1 uses for a cell that is not interior }
    WallIndexInside: Word;            { $01FC: the ds0C26 wall id index for an interior cell (event byte bit 7) }
  end;
var
  { The wall view's id table: two equal groups of eight ids (0,15,12,11,13,10,9,14). ShowAreaView
    indexes it with the TGameState words at $1FA (outside cell) and $1FC (interior cell). }
  ds0C26: array[0..15] of Byte;  { wall view id table, two equal groups of 8; see above }
  ds2612: Word;                   { passed to res03_fn_00DC when the sound stops (QuitGame, Ctrl-S); meaning unknown }
  { The base column of the map window page, indexed by AreaViewKind: entries 2..4 hold 0, 13 and
    26 (the pages of the 44-column map grid), entry 1 holds 78; evidence in re/dseg.toml. }
  MapBaseX: array[0..5] of Byte;  { map window page base column per AreaViewKind; see above }
  DebugMode: Boolean;             { STING debug mode: switched by Ctrl-D in ReadGameKey; ShowDebugTrace shows only when set }
  ds49D0: Boolean;                { when set, HeapErrorHandler offers ovl17_e9 (save and load unit) before quitting }
  { The game state record the view units read (owner not known yet): the party's map position is
    MapX/MapY at +$186/+$188; ovl26_e1 and ovl27_e1 also read words at $1CC, $1F6, $1FA, $1FC. }
  ds49D2: ^TGameState;            { the game state record; see above }
  AreaViewKind: Byte;             { what to draw: 1 the 3D wall view, 2..4 the map window page; evidence in re/dseg.toml }
  ds6A60: Byte;                   { wall view descriptor 1 (of 4): ovl29_e1 stores them, ovl29_fn_0174 draws with them }
  ds6A61: Byte;                   { wall view descriptor 2: ovl26_e1 fills it from ds6F69 when ds84E5 is set }
  ds6A62: Byte;                   { wall view descriptor 3: ovl26_e1 fills it from ds6F69 when ds84E5 is set }
  ds6A63: Byte;                   { wall view descriptor 4: ovl26_e1 fills it from ds6F68 when ds84E5 is set }
  { ovl29_e5 draws the four wall view descriptors through ovl29_fn_0174 only while ds6AAC is 0;
    ovl26_e1 (when the TGameState word at $1F6 is set) and ovl07_e8 clear it. }
  ds6AAC: Byte;                   { wall view overlay gate; see above }
  ds6AAD: Byte;                   { the party's column in the 16x16 area map (GEO); ovl29_e4/e5 take it }
  ds6AAE: Byte;                   { the party's row in the 16x16 area map; ovl29_e4/e5 take it; set to 1 by ovl11_e1 }
  { The marker's icon set (ovl32_e5's third parameter): the wilderness keys H, M, P and K set 0,
    2, 4 and 6 (ovl14_fn_0B48); ovl07_e10 maps a script value 0..3 to the same 0/2/4/6. }
  ds6AAF: Byte;                   { the marker's icon set; see above }
  ds6AB1: Byte;                   { the event byte of the party's map cell, from ovl29_e4; bit 7 = interior }
  MarkerFrame: Byte;              { the party marker's animation frame 0..5; evidence in re/dseg.toml }
  ds6F68: Byte;                   { special view code 2; set with ds84E5 := 1 by ovl07_e3 ($41) and ovl11_fn_0435 ($DB) }
  ds6F69: Byte;                   { special view code 1; set with ds84E5 := 1 by ovl07_e3 (9) and ovl11_fn_0435 ($E8) }
  ds84E5: Byte;                   { special view gate: ShowAreaView uses ds6F68/ds6F69 only while it is nonzero }
  Regs: Registers;                { registers for Intr calls (QuitGame) }
  SavedVideoMode: Byte;           { the video mode QuitGame restores }
  SoundMode: Byte;                { sound setting; 2 while paused by Ctrl-S (ReadGameKey) }
  SoundModeBeforePause: Byte;     { SoundMode before a Ctrl-S pause; restored when 0 or 1 }
  ds557D: Boolean;                { set by ovl17_e9; True ends HeapErrorHandler's retry loop }
implementation
end.
