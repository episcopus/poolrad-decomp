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
  { One slot of the picture table at DS:5E5A. Two pointers, stride 8. FreePictureSlot frees
    either one when it is not nil. Pics[Mirror] is the same two pointers, indexed. }
  TPictureSlot = record
    case Integer of
      0: (FirstPic, SecondPic: Pointer);
      1: (Pics: array[0..1] of Pointer);
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
  { $400-byte map data block at DS:6A5C (also ^TBlock400): the first $300 bytes are not
    read here; the plane at +$300 holds one byte per 16x16-map cell (row * 16 + col)
    with a bit pair per icon set that ovl14 clears on exit. Full structure uncertain. }
  TGeoCellBlock = record
    Unknown: array[0..$2FF] of Byte;
    Cells: array[0..15, 0..15] of Byte;
  end;
  PGeoCellBlock = ^TGeoCellBlock;
  { Heap blocks the loader (StartGame) allocates with New; the size is the argument of each New
    (ovl11:0044..00A3) and the type only fixes SizeOf. They are word arrays at the offsets the map
    code indexes. }
  TBlock400 = array[0..511] of Word;      { a $400-byte block }
  TBlock588 = array[0..707] of Word;      { a $588-byte block (the sprite data, loaded by LoadPictureSlot) }
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
  { One line of a menu list or an item in memory: the 63-byte record of whitepaper 4.2.5 (field
    offsets [V] by tools/re/records.py round-trips). The Temple builds its Heal menu from these
    (ovl25_e6, ovl04:0A18) and the Shop shows its stock and the character's carried items with the
    same record, so ovl04, ovl06 and ovl25 all share one type; Text is a string[40] (the Shop's
    ovl06:0030 assigns with a System_StrLCopy limit of $28) and the byte at +$29 is the menu line's
    cleared flag, so the link is at +$2A. PItem/TItem are the same record. }
  PByte = ^Byte;
  PMenuLine = ^TMenuLine;
  TMenuLine = record
    Text: string[40];             { +$00: the line's text (a menu line or an item name) }
    Flag29: Byte;                 { +$29: cleared when a menu line is filled; meaning unknown }
    Next: PMenuLine;              { +$2A: the next line/item of the list; nil ends it }
    ItemType: Byte;               { +$2E }
    NameNum: array[1..3] of Byte; { +$2F..$31 }
    Plus: ShortInt;               { +$32 }
    PlusSave: Byte;               { +$33 }
    Readied: Boolean;             { +$34 }
    HiddenNames: Byte;            { +$35 }
    Cursed: Boolean;              { +$36: the item is cursed (Remove Curse looks for one, ovl04:0874) }
    Weight: Word;                 { +$37 }
    Count: Byte;                  { +$39 }
    Value: Word;                  { +$3A }
    Affects: array[1..3] of Byte; { +$3C..$3E }
  end;
  PItem = PMenuLine;
  TItem = TMenuLine;
  { A character in memory: the 285-byte record of whitepaper 4.2.5 (name, abilities and hp_max
    [V] by tools/re/records.py). Only the fields a decompiled unit uses are named; the Pad
    arrays keep the offsets. }
  PCharacter = ^TCharacter;
  { The combat state of a character (TCharacter.Combat, +$108), read and written by the combat
    unit ovl08; only the fields it uses are named. }
  PCombatant = ^TCombatant;
  TCombatant = record
    PendingSpell: Byte;           { +$0: nonzero: the turn finishes this spell through ovl22_e5 (ovl08:0336) }
    CanCast: Byte;                { +$1: zero hides Cast in the combat menu (ovl08:0747) }
    Pad2: Byte;
    { +$3: the turn order: CombatTurn acts only above 0, the highest roll goes first
      (PickNextCombatant), Delay sets 1, $14 (the Alt-Q quick fight) acts as $13. Signed. }
    Initiative: ShortInt;
    Pad4: array[4..5] of Byte;
    Moves: Byte;                  { +$6: movement left in half squares (the Move menu shows Moves div 2) }
    B7: Byte;                     { +$7: cleared at the start of each turn (ovl08:021E); meaning unknown }
    Pad8: Byte;
    B9: Byte;                     { +$9: saved and restored around a move that is taken back (ovl08:09FD, 0B41) }
    Target: PCharacter;           { +$A: the character attacked last (MeleeAttack sets it) }
    DyingRounds: Byte;            { +$E: the rounds a dying character (Status 5) has bled; above 9 it dies }
    BF: Byte;                     { +$F: cleared at the start of each turn (ovl08:0204); meaning unknown }
    Pad10: Byte;
    Turned: Byte;                 { +$11: nonzero hides Turn in the combat menu (ovl08:0795) }
    B12: Byte;                    { +$12: cleared at the start of each turn (ovl08:0211); meaning unknown }
    B13: Byte;                    { +$13: nonzero keeps a dying character from being bandaged (ovl08:1029) }
  end;
  { One $13-byte record of the list at DS:6DBB (FreeMem size, ovl08:0029); only Next is known. }
  PCombatNode = ^TCombatNode;
  TCombatNode = record
    Pad0: array[0..3] of Byte;
    Next: PCombatNode;            { +$4 }
    Pad8: array[8..$12] of Byte;
  end;
  { The $4E9-byte combat block at DS:6716 (FreeMem size, ovl08:0049); +2 and +3 are the column
    and row EndCombatRound centres the map view on (ovl08:0937). }
  PCombatMap = ^TCombatMap;
  TCombatMap = record
    Pad0: array[0..1] of Byte;
    ViewCol, ViewRow: ShortInt;   { +$2, +$3 }
    Pad4: array[4..$4E8] of Byte;
  end;
  TStepCost = record
    Cost: Byte;                   { +0 }
    Pad1: array[1..3] of Byte;
  end;
  TCharacter = record
    Name: string[15];             { +$00 }
    Strength, Intelligence, Wisdom, Dexterity: Byte;  { +$10..$13 }
    Constitution: Byte;           { +$14: Raise Dead lowers it by one (ovl04:060E) }
    Charisma, StrengthPercent: Byte;  { +$15, +$16 }
    { +$17..+$2B: the memorized spells, one spell number per slot, 0 = empty (CombatMenu offers
      Cast when one is set, ovl08:071E; ovl14 looks for Knock in them). }
    Spells: array[0..20] of Byte;
    Pad2C: array[$2C..$31] of Byte;
    HpMax: Byte;                  { +$32: maximum hit points }
    Pad33: array[$33..$7E] of Byte;
    Affects: Pointer;             { +$7F: the list of affects (res12_fn_2199, ovl24_e2 walk it) }
    Pad83: Byte;
    { +$84: below $80 the party's Space command takes the character out of quick combat
      (ovl08:0504); meaning otherwise unknown. }
    B84: Byte;
    Pad85: array[$85..$95] of Byte;
    { +$96..$9D: the level in each of the eight classes; Raise Dead treats index 2 apart (class 2
      is the fighter in the create-character run, whitepaper 5.8). Signed: only levels above 0 count. }
    ClassLevels: array[0..7] of ShortInt;
    Pad9E: array[$9E..$B0] of Byte;
    { +$B1: Raise Dead subtracts it from HpMax to get the hit points its constitution
      arithmetic works on (ovl04:0612); its meaning beyond that is not known. }
    HpB1: Byte;
    PadB2: array[$B2..$BA] of Byte;
    HeadBank: Byte;               { +$BB: the HEAD picture bank number, 0 when none (ShowHeadBodyWindow) }
    BodyBank: Byte;               { +$BC: the BODY picture bank number, 0 when none (ShowHeadBodyWindow) }
    PadBD: array[$BD..$C6] of Byte;
    ItemCountC7: Byte;            { +$C7: nonzero offers Use in the combat menu (ovl08:06E1); likely the item count }
    Items: PItem;                 { +$C8: the list of carried items }
    PadCC: array[$CC..$103] of Byte;
    Next: PCharacter;             { +$104: the next character of the party list (ds5D96), nil ends it }
    Combat: PCombatant;           { +$108: the character's combat state (ovl08) }
    { +$10C: the health status: 0 after Raise Dead and Stone to Flesh, 1 and 6 count as dead for
      Raise Dead, 7 as stoned for Stone to Flesh (ovl04:0539, 093D). }
    Status: Byte;
    Flag10D: Byte;                { +$10D: Raise Dead and Stone to Flesh set it to 1; meaning unknown }
    { +$10E: the side: SetQuickCombat compares it between attacker and target (ovl08:125D), and
      BandageDying only bandages characters with 0 (the party). }
    Side: Byte;
    { +$10F: nonzero while the computer fights for the character (quick combat): CombatTurn hands the
      turn to ovl09_e1 (ovl08:02B3); Quick sets it, the Space command clears it. }
    Quick: Byte;
    Pad110: array[$110..$11A] of Byte;
    Flag11B: Byte;                { +$11B: Raise Dead and Stone to Flesh set it to 1; meaning unknown }
    Pad11C: Byte;
  end;
  { The 28 bytes at DS:67F4 that the Temple clears on entry and ovl21_e12 turns into a LongInt
    sum (the money pooled in the shop); the element layout is not known yet. }
  TPartyMoney = array[0..$1B] of Byte;
  { A 3-byte record of the ovl30 sort table (whitepaper 5.18): the table DS:6718 is an array of
    these, element 0 holding the count in Val (SortTable reads and writes Key and Val). }
  { The line drawing state SetupLine fills and StepLine/e5 step (whitepaper 5.18): the endpoints, the
    three Bresenham steps and the current position. }
  TLineState = record
    X1, Y1: Integer;               { +$0, +$2: the start point }
    X2, Y2: Integer;               { +$4, +$6: the end point }
    D1: Integer;                   { +$8: the first Bresenham step }
    DX, DY: Integer;               { +$A, +$C: |X2-X1| and |Y2-Y1| }
    D2: Integer;                   { +$E: the second step }
    D3: Integer;                   { +$10: the third step }
    SX, SY: ShortInt;              { +$12, +$13: the x and y step direction }
    X, Y: Integer;                 { +$14, +$16: the current position, starts at X1, Y1 }
    First: Byte;                   { +$18: 0 while the line has not been stepped }
    Pattern: Byte;                 { +$19: a pattern byte StepLine sets from ds25C0 }
  end;
  PLineState = ^TLineState;
  TSortRec = record
    Head: Byte;                    { +0: never read by the sort }
    Key: Byte;                     { +1: the first sort key }
    Val: Byte;                     { +2: the second sort key }
  end;
  { One row of WalkLine's map (whitepaper 5.18): a 7-byte header and 43 tile cells; rows are 50
    bytes. Head[6] = 0 enables the tile gate. QUIRK: callers may pass X above 42, reading past
    Cells into the next row (no range checks). }
  TMapRow = record
    Head: array[0..6] of Byte;    { +$0..$6: the header; see above }
    Cells: array[0..42] of Byte;  { +$7..$31: the tile ids }
  end;
  TMapRows = array[0..24] of TMapRow;  { the map: row per Y; extent unverified }
  PMapRows = ^TMapRows;
  { One entry of the DS:2745 tile table WalkLine reads (whitepaper 5.18): 4 bytes per tile id;
    BoundY feeds the Bound line endpoints, BlockY gates the walk against Bound.Y. }
  TTileEntry = record
    BoundY: Byte;                 { +0: the walk base height of the tile }
    BlockY: Byte;                 { +1: blocks the walk while above Bound.Y }
    B2: Byte;                     { +2: never read by WalkLine; meaning unknown }
    B3: Byte;                     { +3: never read by WalkLine; meaning unknown }
  end;
  { One entry of the DS:5F27 map entity table ScanTargets scans: the position, an unknown byte and
    a kind byte; entry 0's Kind holds the count e6 loops over (like ds6718[0].Val). }
  TMapEntry = record
    X, Y: ShortInt;               { +$0, +$1: the position in map coordinates }
    Unk2: Byte;                   { +$2: never read by ScanTargets; meaning unknown }
    Kind: Byte;                   { +$3: nonzero means active, the value goes to ovl31_e1 }
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
  VarRiverGate = 418;             { river-crossing gate: CheckMapCell prints the stench message while it is 0
                                    (ovl14:0905); who sets it is not known yet }
var
  { The 13 code wheel records of the copy protection (whitepaper 5.12): the answer, the rune
    indices and the path pattern. CheckCodeWheel picks one at random. }
  ds0000: array[0..12] of TCodeWheelEntry;  { the code wheel records; see above }
  ds04DF: string[40];             { prompt string HandleWildernessKeys passes to ovl25_e2; filled elsewhere }
  { The wall view's id table: two equal groups of eight ids (0,15,12,11,13,10,9,14). ShowAreaView
    indexes it with the game variables VarWallIndexOutside and VarWallIndexInside. Its last six
    bytes are also entry 0 of SpecialBlocks, which DrawAreaView never reads. }
  ds0C26: array[0..15] of Byte;  { wall view id table, two equal groups of 8; see above }
  SpecialBlocks: array[0..9] of TSpecialBlock;  { entries 1..9 tested; only 3..9 replace the map block }
  ds2612: Word;                   { word passed to res03_fn_00DC by QuitGame and the Ctrl-S pause path; meaning unknown }
  ds260A: array[0..7] of Byte;    { 8-byte structure res07_fn_2632 copies from @ds260A (DrawWallDescriptors) }
  ds2622: Word;                   { word e1 passes to res03_fn_00DC when Done is 0; meaning unknown }
  ds2628: Word;                   { word the ovl14 movement code passes to res03_fn_00DC; meaning unknown }
  { Five words, one per 8x8 tile bank, subtracted from the symbol number to index within the
    bank (Put8x8Symbol, ovl34:020F); evidence in re/dseg.toml. }
  SymbolBase: array[0..4] of Word;  { per-bank base symbol numbers; see above }
  AreaMap: array[0..35, 0..43] of Byte;  { the area map: one block code per 3x3-tile block, one more
                                          than the code DrawCellPicture draws; byte 0x4E (the letter N)
                                          where no block is drawn (all of rows 34 and 35 in the
                                          shipped image). Read by DrawAreaView, ovl10 and ovl14. }
  { The base column of the map window page, indexed by AreaViewKind: entries 2..4 hold 0, 13 and
    26 (the pages of the 44-column map grid), entry 1 holds 78; evidence in re/dseg.toml. }
  MapBaseX: array[0..5] of Byte;  { map window page base column per AreaViewKind; see above }
  ds43DC: Word;                   { nonzero after overlay sizing means the overlay manager failed: res08_init
                                    shows 'Overlay error, program abort!' and halts (probably OvrResult) }
  NewHeapEnd: Pointer;            { DS:$4848: HeapEnd cut by $400 paragraphs; assigned to HeapEnd }
  CfgChar: Char;                   { the POOL.CFG choice just read (video E/C/T, sound T/P, retry key, F/N) }
  CfgText: Text;                  { POOL.CFG opened for reading (lines: video, sound, game dir, save dir, F/N);
                                    overlaps CfgProbeResult..SavedVideoMode in time-shared DGROUP; see res08_init }
  CfgProbeResult: Byte;                   { IOResult of probing pool.cfg (Reset); res08_init retries while nonzero }
  HeapWords: array[0..1] of Word absolute HeapEnd;
  { the offset (0) and segment (1) words of the heap end (res08_init cuts it by $400 paragraphs) }
  ds49D0: Boolean;                { when set, HeapErrorHandler offers ovl17_e9 (save and load unit) before quitting }
  ds49D1: Byte;                   { 1 when POOL.CFG line 5 is 'F', 0 otherwise (meaning of F/N unknown, 2.3) }
  GameVars: ^TGameVars;           { the game variables (see TGameVars) }
  CfgProbe: File;                 { pool.cfg opened untyped (128-byte records) to probe its existence }
  ds04B6: string[40];             { prompt string HandleWildernessKeys passes to ovl25_e2 in the movement loop }
  DebugMode: Boolean;             { STING debug mode: switched by Ctrl-D in ReadGameKey; ShowDebugTrace shows only when set }
  AreaViewKind: Byte;             { what to draw: 1 the 3D wall view, 2..4 the map window page; evidence in re/dseg.toml }
  ds6A60: Byte;                   { wall view descriptor 1 (of 4): SetWallDescriptors sets them }
  ds6A61: Byte;                   { wall view descriptor 2: ShowAreaView fills it from ds6F69 when ds84E5 is set }
  ds6A62: Byte;                   { wall view descriptor 3: ShowAreaView fills it from ds6F69 when ds84E5 is set }
  ds6A63: Byte;                   { wall view descriptor 4: ShowAreaView fills it from ds6F68 when ds84E5 is set }
  { ovl29_e5 draws the four wall view descriptors through DrawWallDescriptors only while ds6AAC is 0;
    ShowAreaView (when GameVars^[VarShowWallOverlays] is set) and ovl07_e8 clear it. }
  ds6AAC: Byte;                   { wall view overlay gate; see above }
  ds6AAD: ShortInt;               { the party's column in the 16x16 area map (GEO) }
    { ShortInt, not Byte: ovl14 widens it with cbw (ovl14:0696); ovl29_e4/e5 take it. }
  ds6AAE: ShortInt;               { the party's row in the 16x16 area map }
    { ShortInt, not Byte: ovl14 widens it with cbw (ovl14:069D); ovl29_e4/e5 take it; set to 1 by StartGame. }
  { The marker's icon set (DrawIcon's third parameter): the wilderness keys H, M, P and K set 0,
    2, 4 and 6 (HandleWildernessKeys, HandleWildernessKeys); ovl07_e10 maps a script value 0..3 to the same 0/2/4/6. }
  ds6AAF: Byte;                   { the marker's icon set; see above }
  ds6AB0: Byte;                   { ovl29_e2's result for the party cell and icon set (MoveParty); meaning unknown }
  ds6AB1: Byte;                   { the event byte of the party's map cell, from ovl29_e4; bit 7 = interior }
  MarkerFrame: Byte;              { the party marker's animation frame 0..5; evidence in re/dseg.toml }
  ds6F68: Byte;                   { special view code 2; set with ds84E5 := 1 by ovl07_e3 ($41) and ovl11_fn_0435 ($DB) }
  ds6F69: Byte;                   { special view code 1; set with ds84E5 := 1 by ovl07_e3 (9) and ovl11_fn_0435 ($E8) }
  ds84E5: Byte;                   { special view gate: ShowAreaView uses ds6F68/ds6F69 only while it is nonzero }
  ds84F0: Byte;                   { set to 0 in res08_init after closing pool.cfg; meaning unknown }
  Regs: Registers;                { registers for Intr calls (QuitGame) }
  { The second display page WriteCharsAt writes to when VideoAdapter is 1 (BH of INT 10h);
    res08_init sets it to 0 for EGA and passes it to SetPlaneSegment. }
  ds4A1A: Byte;                   { display page; see above }
  { The display page WriteCharsAt writes to first (BH of INT 10h, 0802:0048); res08_init sets it
    to 0 for EGA and passes it to SetActivePage. }
  ds4A1B: Byte;                   { display page; see above }
  SavedVideoMode: Byte;           { video mode QuitGame passes to INT 10h; no writer is in the decompiled units }
  ds4A1D: Byte;                   { copy of SavedVideoMode taken in res08_init; reader unknown }
  VideoAdapter: Byte;                   { video mode flag read by ClearWindow (03F1:0137): 0 fills the EGA planes,
                                    1 draws through res06_fn_00B7, 2 fills four planes; meaning unknown }
  DrawBuf: Pointer;                { far pointer DrawCellPicture passes to res07_fn_08D4; what it points at is unknown }
  SoundMode: Byte;                { sound setting; 2 while a Ctrl-S pause is in effect (ReadGameKey) }
  SoundModeBeforePause: Byte;     { SoundMode saved by a Ctrl-S pause; copied back only when it is 0 or 1 }
  SaveDir: string;                { POOL.CFG line 4: the save directory with trailing backslash (2.3) }
  { POOL.CFG line 3: the game directory with trailing backslash (res08_init, whitepaper 2.3). StartGame
    saves it in ds4661, empties it, builds a file path in it (ovl11:0564) for OpenGameFile and
    restores it (ovl11:0469, 05EA). }
  GameDir: string;                { the game directory; see above }
  { True ends HeapErrorHandler's retry loop: it is read after ovl17_e9 runs (ovl00:0075),
    and who sets it is not shown until ovl17 is decompiled. }
  ds557D: Boolean;                { heap error retry gate; see above }
  ds5E52: PT8x8Bank;              { SQRPACI bank 1 (ovl11:04D6); DrawCellPicture source (PicCode <= 127) }
  ds5E56: PT8x8Bank;              { SQRPACI bank 2 (ovl11:04F8); DrawCellPicture source (bit 7 set) }
  ds5E5A: array[Byte] of TPictureSlot;  { picture slots (ovl32); loader clears $D0 bytes (ovl11:02B9) }
  { Globals of the loader (StartGame, src/OVL11.PAS); the address in each comment is the write or
    read that shows it. }
  { Table of 30-byte entries indexed by TileSet: entries 1..8 hold 'Insert disk N in drive ' in the
    image (entry 0 is not a string). With the drive letter DS:547D and ':' appended it is the prompt
    OpenGameFile shows while a file is missing (OpenDaxFile 0802:061A, StartGame ovl11:0564). }
  InsertDiskPrompts: array[0..9] of string[29];  { the insert-disk prompts; see above }
  ds465C: Byte;                   { loop counter of the loader's three fill loops (ovl11:0130, 02CA, 035E) }
  ds4660: Byte;                   { result of OpenGameFile (the file open state) read at ovl11:05A6 }
  ds4661: string[40];             { the save game name; the loader copies GameDir here and back (ovl11:0469, 05EA) }
  ds468C: file;                   { the untyped file the loader reads the block from (ovl11:05A1..05E5) }
  { Second $800-byte word block the loader allocates (ovl11:0044); it zeroes word 830 (ovl11:03F5).
    ovl14 reads words 713, 714 and 725 of it, all within the 1024 words of TGameVars. }
  ds49D6: ^TGameVars;             { second game word block; see above }
  ds49DA: ^TBlock400;             { $400-byte block the loader allocates (ovl11:0054) }
  ds49DE: ^TBlock1E00;            { $1E00-byte block the loader allocates (ovl11:0064) }
  GameSpeed: Byte;                   { set to 1 by the loader; a count the ovl18 narratives read }
  ds4A16: Word;                   { EGA/VGA plane segment SetActivePage sets to AIndex shl 9 + $A000 }
  ds4A18: Word;                   { EGA/VGA plane segment SetPlaneSegment sets to AIndex shl 9 + $A000 }
  { The view mode: ShowEndingNarrative saves it, sets 7, restores it; VisitTemple sets 1 (ovl04:0D0F). }
  ds49F3: Byte;                   { the view mode; see above }
  ds0900: array[0..$A] of Byte;   { the first door block codes of AnimateAreaDoors (bit 7 = other bank) }
  ds090B: array[0..$11] of Byte;  { the second door block codes of AnimateAreaDoors (indexed 0..$11); same 7-bit flag }
  ds091D: array[0..$F] of Byte;   { the first 16-byte record AnimateAreaDoors passes to res07_fn_1E5C }
  ds092D: array[0..$F] of Byte;   { the second 16-byte record AnimateAreaDoors passes to res07_fn_1E5C }
  ds093D: array[0..$F] of Byte;   { the third 16-byte record AnimateAreaDoors passes to res07_fn_1E5C }
  ds094D: array[0..8] of Word;    { the per-step DrawAreaView columns of AnimateAreaDoors (indexed 0..8) }
  ds095F: array[0..8] of Word;    { the per-step DrawAreaView rows of AnimateAreaDoors (indexed 0..8) }
  ds470E: Pointer;                { the FINAL picture bank ShowEndingNarrative loads through res07_fn_0111 and draws }
  ds4712: Byte;                   { the DS:49F3 value ShowEndingNarrative saves at the start and restores at the end }
  ds4713: string[1];              { Str(TileSet): the picture number ShowEndingNarrative appends to FINAL }
  ds25C0: array[0..2, 0..2] of Byte;  { the 3x3 line pattern table StepLine reads at [SY+1, SX+1] }
  { ds2736 and ds273F: nine entries each (ds273F starts 9 bytes after ds2736). ovl14's
    ClampPartyPosition also adds them as the party's column and row step (cbw at ovl14:06D0, 06DB). }
  ds2736: array[0..8] of ShortInt;  { the x step per direction; see above }
  ds273F: array[0..8] of ShortInt;  { the y step per direction; see above }
  ds2745: array[0..255] of TTileEntry;  { the tile table WalkLine reads; see above }
  ds5F27: array[0..15] of TMapEntry;  { the map entity table e6 scans; extent unverified }
  ds6718: array[0..255] of TSortRec;  { the ovl30 sort table (element 0 holds the count, SortTable) }
  ds49ED: Word;                   { set to $9900 by the loader (ovl11:03C0) }
  ds49E5: Word;                   { copied to ds49ED by the ovl14 L key; meaning unknown }
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
  ds5377: Byte;                   { TileSet saved by SelectTileSet; the loader also sets it to 1 }
  ds5378: Word;                   { set to 1 by the loader (ovl11:03E0) }
  ds547A: Word;                   { set to 1 by the loader (ovl11:03DA) }
  ds547D: Byte;                   { a character the loader appends to the path through System_MemOp_0C3B (ovl11:0581) }
  ds557C: Byte;                   { cleared by the loader (ovl11:0438) }
  ds5582: array[0..$80F] of Byte; { $810-byte buffer the loader reads the file block into (ovl11:05CD) }
  { The selected character: the Temple acts on it (ovl04 reads it everywhere), ShowHeadBodyWindow
    shows its HEAD and BODY pictures (ovl28:04F9); the loader sets it nil (ovl11:03B8). }
  SelectedCharacter: PCharacter;  { see above }
  ds286F: array[0..13] of Byte;   { the HEAD picture number per bank (SelectedCharacter^.HeadBank, ShowHeadBodyWindow) }
  ds287D: array[0..13] of Byte;   { the BODY picture number per bank (SelectedCharacter^.BodyBank, ShowHeadBodyWindow) }
  ds5D96: LongInt;                { head of the TCodeRec list ovl14 walks (see below) }
    { Kept LongInt, not Pointer: the loader clears it with `ds5D96 := 0` (ovl11:03B0),
      which is Error 26 for a Pointer (proven by a make tpc probe); ovl14 reaches the
      records through Pointer(ds5D96). }
  ds5E1E: Word;                   { BlockRead result count of the loader (ovl11:05D6) }
  ds5E20: ^TBlock588;             { $588-byte block the loader allocates (ovl11:0074) }
  ds6810: PMenuLine;              { head of the shop's item list, a far pointer the loader clears (ovl11:031A) }
  ds6A58: ^TBlock924;             { $924-byte block the loader allocates (ovl11:0084) }
  ds6A5C: ^TBlock400;             { $400-byte block the loader allocates (ovl11:0094) }
  ds84DC: Byte;                   { the wall view / outdoor mode ovl29_e4 tests (0 and $A both skip) }
  GeoCells: PGeoCellBlock absolute ds6A5C; { cell-byte view of the $400 block for ovl14 }
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
  ds6B0A: string[8];              { the last picture file loaded (LoadSpriteList); cleared by the loader (ovl11:043D) }
  ds6B1C: Byte;                   { set to $FF by the loader (ovl11:0442) and by FreeSpriteList }
  ds0C6C: array[0..$F] of Byte;   { 16-byte table LoadSpriteList passes to res07_fn_1E5C (with ds0C7C) }
  ds0C7C: array[0..$F] of Byte;   { second 16-byte table LoadSpriteList passes to res07_fn_1E5C }
  ds70C7: ShortInt;               { loop counter of FreeSpriteList (the sprite list slots); ShortInt: the loop exits with jg }
  ds6B29: Word;                   { set to 1 by the loader (ovl11:0405) }
  ds6DDA: Byte;                   { cleared by the loader (ovl11:0410) }
  ds6DDE: array[0..2] of Byte;    { 3-byte buffer the loader fills with 1 (ovl11:0342) }
  ds6DE0: Byte;                   { knock menu flag: e1 offers Knock while nonzero; overlaps ds6DDE[2] }
  ds6DDF: Byte;                   { pick/knock menu flag (e1 offers Pick/Knock while nonzero) }
    { DoPick clears it. Overlaps ds6DDE[1]; exact sharing uncertain. }
  ds84D4: Byte;                   { cleared by the loader (ovl11:040B) }
  ds84DD: Byte;                   { cleared by the loader (ovl11:0415) }
  ds84DE: Byte;                   { cleared by the loader (ovl11:041A) }
  ds84DF: Byte;                   { cleared by the loader (ovl11:041F) }
  ds84E0: Byte;                   { cleared by the loader (ovl11:0424) }
  ds84E3: Byte;                   { cleared by the loader (ovl11:0433) }
  ds84E4: Byte;                   { window-clear once flag: HandleWildernessKeys clears the text window and sets it }
  ds84E9: Byte;                   { cleared by the loader (ovl11:0456) }

  { The 8x8 tile world of ovl34 (whitepaper 4.x): which 8X8D file to take the bank from, the five
    loaded banks, the staging buffer tiles are copied through, the buffer res07_fn_08D4 draws
    into, and a word res07_fn_1951 takes. Evidence in re/dseg.toml. }
  TileSet: Byte;                  { the 8X8D file number: Load8x8Bank loads 8x8d<TileSet> }
  TileBanks: array[0..4] of PT8x8Bank;  { the loaded 8x8 banks, indexed by bank; nil when the load failed }
  TileBuf: PT8x8Bank;             { the tile staging buffer: Put8x8Symbol Moves one tile to +$17 }

  { Globals of the Temple (ovl04). }
  { The Heal menu texts, string[40] entries 1..10 at DS:011A (Cure Blindness ... Stone to Flesh,
    Exit) copied into the menu lines (ovl04:0A33, I from 1 to 10 at ovl04:0A0C..0A54). Entry 0
    (DS:00F1) is never read: the index base is entry 0 so that TempleMenuText[I] names the same
    address; its bytes are the tail of the previous data. Entry 10 (DS:028B) holds length 4
    'Exit'. }
  TempleMenuText: array[0..10] of string[40];  { see above }
  { The six affects Cure Disease looks for and removes (entries 1..6 at DS:0114: $1F, $22, $2B,
    $2C, $32, $39 in the image; ovl04:031E, 03A6). Entry 0, the byte before, is never read. }
  DiseaseAffects: array[0..6] of Byte;  { see above }
  ds681F: Byte;                   { 1 while the Temple removes affects through ovl24_e2 (ovl04:0386, 05AB, 07CE), 0 after }
  ds67F4: TPartyMoney;            { the Temple clears it on entry (ovl04:0D32) and passes it to ovl21_e12 }
  ds6C95: PCharacter;             { the character Remove Curse hands to ovl22_e9 (ovl04:08FA) }
  ds6DC0: Byte;                   { cleared when the Temple opens (ovl04:0D37); meaning unknown }
  { Globals of the DOS file and BIOS text layer (res05); evidence in re/dseg.toml where named. }
  { 16 entries, the colours 0..15 mapped to 0..3 (0,0,0,1,2,2,2,3,3,1,1,1,2,2,3,3 in the image);
    WriteCharsAt maps the text colour through it when VideoAdapter is 0 (0802:0086). }
  ds25D5: array[0..15] of Byte;   { four-colour map of the text colours; see above }
  ds49CE: Word;                   { IOResult of the last FileExists file probe (0802:0334) }
  { The ten characters MakeDosFileName removes from a file name are entries 1..10 (DS:0D1A..0D23);
    entry 0 is the byte before them, never read (declared so the index base DS:0D19 names it). }
  BadNameChars: array[0..10] of Char;  { characters not allowed in a file name; see above }
  PackedBuf: Pointer;             { the packed bytes of the DAX block LoadDaxBlock is reading }
  { Colour maps for res07_fn_1E5C (16 entries, colour I becomes entry I): ds0CD2 is the identity,
    ds0CE2 turns colour 13 into 8 and ds0CF2 turns 13 into 0 (the image). LoadPictureSlot recolours the
    TileSet picture sets from ds0CD2 to ds0CE2 and ICON from ds0CD2 to ds0CF2. }
  ds0CD2: array[0..15] of Byte;   { identity colour map; see above }
  ds0CE2: array[0..15] of Byte;   { colour 13 to 8; see above }
  ds0CF2: array[0..15] of Byte;   { colour 13 to 0; see above }
  { Globals of the combat unit ovl08 (whitepaper 5.5). }
  ds6DBB: PCombatNode;            { a list of $13-byte records EndCombat frees (ovl08:0006); meaning unknown }
  ds6716: PCombatMap;             { the $4E9-byte combat block EndCombat frees (ovl08:0041) }
  ds6E36: Pointer;                { a picture EndCombat frees through res07_fn_2595 (ovl08:005A) }
  { A routine pointer: RunCombat sets @ovl13_e14 at the start (ovl08:0085) and EndCombat
    @ovl22_e4 at the end (ovl08:0069); who calls it is not known yet. }
  ds6B84: Pointer;                { see above }
  ds6814: Byte;                   { zero (or ds6815 zero) ends the combat (ovl08:009B, 095C); likely the count of one side }
  ds6815: Byte;                   { see ds6814; likely the count of the other side }
  ds6E30: Boolean;                { the Alt-M Magic On/Off toggle of the combat keys (ovl08:04A7) }
  ds6E31: Byte;                   { the key flag the ovl08 menus pass to ovl25_e2 }
  ds6DE3: Byte;                   { counted up once per combat round (ovl08:0891) }
  { The combatants by number: MoveCharacter attacks ds65B9[n] for the number ovl31_e16 returns
    (ovl08:0BF8). Extent unknown. }
  ds65B9: array[0..63] of PCharacter;  { the combatants by number; see above }
  { One 4-byte entry per kind of ground (the number ovl31_e16 returns); byte 0 is the movement cost
    of a step onto it: MoveCharacter refuses ("Blocked") a step whose cost is above the moves left
    (ovl08:0C5F); kind 0 is off the map (Flee:). Extent unknown. }
  ds2744: array[0..15] of TStepCost;  { the movement cost of each kind of ground; see above }
implementation
end.
