unit POOLVARS;
{ Game globals whose owning unit is not known yet. Names: dsXXXX is the DS offset
  (re/dseg.toml may give a better name later); others are named in re/dseg.toml. }
{$A-,F+,S-,R-,G-,I-}
interface
uses Dos;
type
  { One record of the code wheel table at DS:0000 (whitepaper 5.12; CheckCodeWheel reads it for the copy
    protection question). }
  TCodeWheelEntry = record
    Unknown: array[0..1] of Byte;  { +0: not read by CheckCodeWheel }
    CodeWord: string[6];          { +2: the answer the player must type }
    OuterRune: Byte;               { +9: the Espruar (outer ring) rune index }
    InnerRune: Byte;               { +$A: the Dethek (inner ring) rune index }
    ThirdRune: Byte;               { +$B: the third rune index }
    FourthRune: Byte;              { +$C: the fourth rune index, $FF when the record has none }
    Path: string[7];               { +$D: the path pattern drawn under the runes }
  end;
  { One fixed position of the area view (the table at DS:0C30). DrawAreaView tests entries
    1..9 for position; only entries 3..9 can replace the map block. Entry 0 is never read. }
  TSpecialBlock = record
    Col, Row: Word;              { position of the block on the area map (DS:3648) }
    Pic: Word;                   { the picture word; entries 3..9 draw Pic minus one }
  end;
  { The word variables of the game: the structure the far pointer at DS:49D2 leads to. ovl07 and
    ovl17 index it dynamically (the variables of the ECL scripts), words 195 and 196 keep the party
    position on the area map, and DrawAreaView reads words 380, 396, 415, 416, 435 and 466 as gates
    for fixed area blocks. The upper bound is still unknown; 465 words are in use. }
  TGameVars = array[0..511] of Word;
const
  { Words of GameVars^ whose meaning is proven (word n is at byte offset 2n of the block; the
    matched reads in ovl26 are at +$186, +$188, +$1CC, +$1F6, +$1FA and +$1FC). }
  VarMapX = 195;                  { the party's column in the area map grid (44 wide) }
  VarMapY = 196;                  { the party's row in the area map grid }
  VarForceWallView = 230;         { nonzero: ShowAreaView shows the wall view whatever AreaViewKind says }
  VarShowWallOverlays = 251;      { nonzero: ShowAreaView clears ds6AAC, so ovl29_e5 draws the overlay labels }
  VarWallIndexOutside = 253;      { the ds0C26 wall id index ShowAreaView uses for a cell that is not interior }
  VarWallIndexInside = 254;       { the ds0C26 wall id index for an interior cell (event byte bit 7) }
var
  { The 13 code wheel records of the copy protection (whitepaper 5.12): the answer, the rune
    indices and the path pattern. CheckCodeWheel picks one at random. }
  ds0000: array[0..12] of TCodeWheelEntry;  { the code wheel records; see above }
  { The wall view's id table: two equal groups of eight ids (0,15,12,11,13,10,9,14). ShowAreaView
    indexes it with the game variables VarWallIndexOutside and VarWallIndexInside. Its last six
    bytes are also entry 0 of SpecialBlocks, which DrawAreaView never reads. }
  ds0C26: array[0..15] of Byte;  { wall view id table, two equal groups of 8; see above }
  SpecialBlocks: array[0..9] of TSpecialBlock;  { entries 1..9 tested; only 3..9 replace the map block }
  ds2612: Word;                   { word passed to res03_fn_00DC by QuitGame and the Ctrl-S pause path; meaning unknown }
  AreaMap: array[0..35, 0..43] of Byte;  { the area map: one block code per 3x3-tile block, one more
                                          than the code ovl32_e2 draws; byte 0x4E (the letter N)
                                          where no block is drawn (all of rows 34 and 35 in the
                                          shipped image). Read by DrawAreaView, ovl10 and ovl14. }
  { The base column of the map window page, indexed by AreaViewKind: entries 2..4 hold 0, 13 and
    26 (the pages of the 44-column map grid), entry 1 holds 78; evidence in re/dseg.toml. }
  MapBaseX: array[0..5] of Byte;  { map window page base column per AreaViewKind; see above }
  ds49D0: Boolean;                { when set, HeapErrorHandler offers ovl17_e9 (save and load unit) before quitting }
  GameVars: ^TGameVars;           { the game variables (see TGameVars) }
  DebugMode: Boolean;             { STING debug mode: switched by Ctrl-D in ReadGameKey; ShowDebugTrace shows only when set }
  AreaViewKind: Byte;             { what to draw: 1 the 3D wall view, 2..4 the map window page; evidence in re/dseg.toml }
  ds6A60: Byte;                   { wall view descriptor 1 (of 4): ovl29_e1 stores them, ovl29_fn_0174 draws with them }
  ds6A61: Byte;                   { wall view descriptor 2: ShowAreaView fills it from ds6F69 when ds84E5 is set }
  ds6A62: Byte;                   { wall view descriptor 3: ShowAreaView fills it from ds6F69 when ds84E5 is set }
  ds6A63: Byte;                   { wall view descriptor 4: ShowAreaView fills it from ds6F68 when ds84E5 is set }
  { ovl29_e5 draws the four wall view descriptors through ovl29_fn_0174 only while ds6AAC is 0;
    ShowAreaView (when GameVars^[VarShowWallOverlays] is set) and ovl07_e8 clear it. }
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
  SavedVideoMode: Byte;           { video mode QuitGame passes to INT 10h; no writer is in the decompiled units }
  VideoAdapter: Byte;                   { video mode flag read by ClearWindow (03F1:0137): 0 fills the EGA planes,
                                    1 draws through res06_fn_00B7, 2 fills four planes; meaning unknown }
  SoundMode: Byte;                { sound setting; 2 while a Ctrl-S pause is in effect (ReadGameKey) }
  SoundModeBeforePause: Byte;     { SoundMode saved by a Ctrl-S pause; copied back only when it is 0 or 1 }
  { True ends HeapErrorHandler's retry loop: it is read after ovl17_e9 runs (ovl00:0075),
    and who sets it is not shown until ovl17 is decompiled. }
  ds557D: Boolean;                { heap error retry gate; see above }
implementation
end.
