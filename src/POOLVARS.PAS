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
  { One bank of 8x8 tiles as res07_fn_0111 loads it: a picture record (whitepaper 4.x; its
    header carries the height at +0 and the item count at +8), Stride bytes per tile at +$11,
    the tile data at +$17. Only Stride and Data are read by this unit. }
  T8x8Bank = record
    Head: array[0..$10] of Byte;  { +0..+$10: record header (height at +0, item count at +8) }
    Stride: Word;                 { +$11: bytes per tile }
    Gap: array[0..3] of Byte;     { +$13..+$16: unused by this unit }
    Data: array[0..8191] of Byte; { +$17: the tiles, indexed Symbol * Stride with $R- }
  end;
  PT8x8Bank = ^T8x8Bank;          { a loaded 8x8 tile bank }
  { The word variables of the game: the structure the far pointer at DS:49D2 leads to. ovl07 and
    ovl17 index it dynamically (the variables of the ECL scripts), words 195 and 196 keep the party
    position on the area map, and DrawAreaView reads words 380, 396, 415, 416, 435 and 466 as gates
    for fixed area blocks. The loader (StartGame) allocates the block at DS:49D2 with $800 bytes
    (New with the size $800 at ovl11:0034 and the FillChar of $800 at ovl11:0271), so the array has
    1024 words; the words above 465 are simply not read. }
  TGameVars = array[0..1023] of Word;
  { Heap blocks the loader (StartGame) allocates with New; the size is the argument of each New
    (ovl11:0044..00A3) and the type only fixes SizeOf. They are word arrays at the offsets the map
    code indexes. }
  TBlock400 = array[0..511] of Word;      { a $400-byte block }
  TBlock588 = array[0..707] of Word;      { a $588-byte block (the sprite data, loaded by ovl32_e4) }
  TBlock924 = array[0..1169] of Word;     { a $924-byte block }
  TBlock1E00 = array[0..3839] of Word;    { a $1E00-byte block }
  { One 4-byte element of the table at DS:6AAE the loader fills (ovl11:0369..0390). }
  TPresenceSlot = record
    A, B: Word;
  end;
  { One 5-byte entry of the loader's slot table at DS:6AFB: Kind $FF and a nil Addr mean the slot is
    empty (ovl11:02CA..0302). }
  TLoadSlot = record
    Kind: Byte;
    Addr: Pointer;
  end;
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
  { Five words, one per 8x8 tile bank, subtracted from the symbol number to index within the
    bank (Put8x8Symbol, ovl34:020F); evidence in re/dseg.toml. }
  SymbolBase: array[0..4] of Word;  { per-bank base symbol numbers; see above }
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
  ds6AAE: Byte;                   { the party's row in the 16x16 area map; ovl29_e4/e5 take it; set to 1 by StartGame }
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
  { Globals of the loader (StartGame, src/OVL11.PAS); the address in each comment is the write or
    read that shows it. }
  { Table of 30-byte entries the loader copies into the file path (ovl11:0564, indexed by TileSet);
    its contents are the save directory names (save/load). }
  ds2614: array[0..9] of string[29];  { save directory name table; see above }
  ds465C: Byte;                   { loop counter of the loader's three fill loops (ovl11:0130, 02CA, 035E) }
  ds4660: Byte;                   { result of res05_fn_025D (the file open state) read at ovl11:05A6 }
  ds4661: string[40];             { the save game name; the loader copies ds547C here and back (ovl11:0469, 05EA) }
  ds468C: file;                   { the untyped file the loader reads the block from (ovl11:05A1..05E5) }
  { Second $800-byte word block the loader allocates (ovl11:0044); it zeroes word 830 (ovl11:03F5). }
  ds49D6: ^TGameVars;             { second game word block; see above }
  ds49DA: ^TBlock400;             { $400-byte block the loader allocates (ovl11:0054) }
  ds49DE: ^TBlock1E00;            { $1E00-byte block the loader allocates (ovl11:0064) }
  ds49E2: Byte;                   { set to 1 by the loader (ovl11:03C6) }
  ds49ED: Word;                   { set to $9900 by the loader (ovl11:03C0) }
  ds49F4: Byte;                   { cleared by the loader (ovl11:03CB) }
  ds49F5: Byte;                   { set to 1 by the loader (ovl11:0392) }
  ds49F6: Byte;                   { set to 1 by the loader (ovl11:0397) }
  ds49F8: Byte;                   { cleared by the loader (ovl11:03A6) }
  ds49F9: Byte;                   { set to 1 by the loader (ovl11:03EB) }
  ds49FB: Word;                   { cleared by the loader (ovl11:03AD) }
  ds49FF: Byte;                   { cleared by the loader (ovl11:0429) }
  ds4A00: Byte;                   { set to 1 by the loader (ovl11:03A1) }
  ds4A24: Pointer;                { screen buffer the loader allocates through res07_fn_248E (ovl11:00D4) }
  ds4A28: array[0..$A7] of Byte;  { $A8-byte buffer the loader clears (ovl11:00EC) }
  ds4AD0: array[0..$14F] of Byte; { $150-byte buffer the loader clears (ovl11:00FD) }
  ds4C20: array[0..$14F] of Byte; { $150-byte buffer the loader fills with $FF (ovl11:010E) }
  ds4D70: array[0..$14F] of Byte; { $150-byte buffer the loader clears (ovl11:011F) }
  { Per-cell screen address table the loader fills (ovl11:0130..0163): $B800 (even cell) or $BA00
    (odd cell) plus 5*(I div 2). }
  ds4EC0: array[0..$C7] of Word;  { cell text scanline address; see above }
  ds5050: array[0..$C7] of Word;  { per-cell row offset table the loader fills (ovl11:0186): I*40 }
  { Per-cell plane address table the loader fills (ovl11:019F..0241): 10*(I div 4) plus $B800,
    $BA00, $BC00 or $BE00. }
  ds51E0: array[0..$C7] of Word;  { cell graphics plane address; see above }
  ds5370: Byte;                   { set to 1 by the loader (ovl11:042E) }
  ds5374: Word;                   { last sound value rung by res03_fn_01A5, cleared by the loader (ovl11:045D) }
  ds5377: Byte;                   { set to 1 by the loader (ovl11:03D5) }
  ds5378: Word;                   { set to 1 by the loader (ovl11:03E0) }
  ds547A: Word;                   { set to 1 by the loader (ovl11:03DA) }
  { The file path the loader builds (ovl11:0564) and passes to res05_fn_025D; the loader saves it
    in ds4661 and restores it (ovl11:0469, 05EA). }
  ds547C: string;                 { the file path; see above }
  ds547D: Byte;                   { a character the loader appends to the path through System_MemOp_0C3B (ovl11:0581) }
  ds557C: Byte;                   { cleared by the loader (ovl11:0438) }
  ds5582: array[0..$80F] of Byte; { $810-byte buffer the loader reads the file block into (ovl11:05CD) }
  ds5D92: LongInt;                { a 4-byte value the loader clears (ovl11:03B8): one `xor ax,ax` and two stores }
  ds5D96: LongInt;                { a 4-byte value the loader clears (ovl11:03B0): one `xor ax,ax` and two stores }
  ds5E1E: Word;                   { BlockRead result count of the loader (ovl11:05D6) }
  ds5E20: ^TBlock588;             { $588-byte block the loader allocates (ovl11:0074) }
  ds5E52: PT8x8Bank;              { the SQRPACI sprite bank 1 the loader loads (ovl11:04D6) }
  ds5E56: PT8x8Bank;              { the SQRPACI sprite bank 2 the loader loads (ovl11:04F8) }
  ds5E5A: array[0..$CF] of Byte;  { $D0-byte buffer the loader clears (ovl11:02B9); the picture set table of ovl32_e4 }
  ds6810: LongInt;                { a 4-byte value the loader clears (ovl11:031A): one `xor ax,ax` and two stores }
  ds6A58: ^TBlock924;             { $924-byte block the loader allocates (ovl11:0084) }
  ds6A5C: ^TBlock400;             { $400-byte block the loader allocates (ovl11:0094) }
  ds6AAEWords: array[0..3] of TPresenceSlot;  { the 4-byte element table at DS:6AAE; the loader sets
                                    elements 2 and 3 to $FFFF (ovl11:035E..0390) }
  ds6AB2: Word;                   { cleared by the loader (ovl11:0353) }
  ds6AB4: Word;                   { set to 1 by the loader (ovl11:0358) }
  ds6ABE: array[0..$41] of Byte;  { $42-byte buffer the loader clears (ovl11:0309) }
  { The loader sets entries 1 and 2 to Kind $FF and Addr nil (ovl11:02CA..0302). }
  ds6AFB: array[0..2] of TLoadSlot;  { 5-byte slot table; see TLoadSlot }
  ds6B00: Byte;                   { the bank index of the HEAD sprite in DS:6B01; $FF when none (LoadHeadBodySprites) }
  ds6B01: Pointer;                { the loaded HEAD sprite bank (ShowHeadBodySprites, LoadHeadBodySprites) }
  ds6B05: Byte;                   { the bank index of the BODY sprite in DS:6B06; $FF when none (LoadHeadBodySprites) }
  ds6B06: Pointer;                { the loaded BODY sprite bank (ShowHeadBodySprites, LoadHeadBodySprites) }
  ds6B0A: Byte;                   { cleared by the loader (ovl11:043D) }
  ds6B1C: Byte;                   { set to $FF by the loader (ovl11:0442) and by FreeSpriteList }
  ds70C7: ShortInt;               { loop counter of FreeSpriteList (the sprite list slots); ShortInt: the loop exits with jg }
  ds6B29: Word;                   { set to 1 by the loader (ovl11:0405) }
  ds6DDA: Byte;                   { cleared by the loader (ovl11:0410) }
  ds6DDE: array[0..2] of Byte;    { 3-byte buffer the loader fills with 1 (ovl11:0342) }
  ds84D4: Byte;                   { cleared by the loader (ovl11:040B) }
  ds84DD: Byte;                   { cleared by the loader (ovl11:0415) }
  ds84DE: Byte;                   { cleared by the loader (ovl11:041A) }
  ds84DF: Byte;                   { cleared by the loader (ovl11:041F) }
  ds84E0: Byte;                   { cleared by the loader (ovl11:0424) }
  ds84E3: Byte;                   { cleared by the loader (ovl11:0433) }
  ds84E9: Byte;                   { cleared by the loader (ovl11:0456) }

  { The 8x8 tile world of ovl34 (whitepaper 4.x): which 8X8D file to take the bank from, the five
    loaded banks, the staging buffer tiles are copied through, the buffer res07_fn_08D4 draws
    into, and a word res07_fn_1951 takes. Evidence in re/dseg.toml. }
  DrawBuf: Pointer;               { the buffer res07_fn_08D4 draws into }
  TileSet: Byte;                  { the 8X8D file number: Load8x8Bank loads 8x8d<TileSet> }
  TileBanks: array[0..4] of PT8x8Bank;  { the loaded 8x8 banks, indexed by bank; nil when the load failed }
  TileBuf: PT8x8Bank;             { the tile staging buffer: Put8x8Symbol Moves one tile to +$17 }
implementation
end.
