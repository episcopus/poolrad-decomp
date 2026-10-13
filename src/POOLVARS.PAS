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
  { One bank of 8x8 tiles as LoadPicture loads it: a picture record (whitepaper 4.x; its
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
  { $400-byte map data block at DS:6A5C (also ^TBlock400): the four 256-byte planes of a GEO
    block (whitepaper 4.2.1), each indexed [Row, Col] of the 16x16 area map. WallsNE and WallsSW
    hold two wall ids per cell (WallIdAt: direction 0 north = high nibble of WallsNE, 2 east = low
    nibble, 4 south = high nibble of WallsSW, 6 west = low nibble); Events the event byte
    (EventByteAt; bit 7 = interior); Cells the door plane, a bit pair per direction (DoorKindAt: 0 =
    bits 0-1, 2 = bits 2-3, 4 = bits 4-5, 6 = bits 6-7), which ovl14 also changes. }
  TGeoCellBlock = record
    WallsNE: array[0..15, 0..15] of Byte;   { +$000 }
    WallsSW: array[0..15, 0..15] of Byte;   { +$100 }
    Events: array[0..15, 0..15] of Byte;    { +$200 }
    Cells: array[0..15, 0..15] of Byte;     { +$300 }
  end;
  PGeoCellBlock = ^TGeoCellBlock;
  { Heap blocks the loader (StartGame) allocates with New; the size is the argument of each New
    (ovl11:0044..00A3) and the type only fixes SizeOf. They are word arrays at the offsets the map
    code indexes. }
  TBlock400 = array[0..511] of Word;      { a $400-byte block }
  TBlock588 = array[0..707] of Word;      { a $588-byte block (the sprite data, loaded by LoadPictureSlot) }
  TBlock924 = array[0..1169] of Word;     { a $924-byte block }
  { The wall tiles at DS:6A58 ($924 bytes, allocated by StartGame): fifteen walls (wall ids 1..15)
    of 156 bytes each, one 8x8 tile number per byte; LoadWallSet fills them from WALLDEF wallsets
    of five walls (whitepaper 4.2.4), DrawWallPiece reads them. }
  TWallTiles = array[1..15, 0..$9B] of Byte;
  { The same $924 bytes seen as LoadWallSet fills them: three wallset slots (1..3) of five walls
    (1..5) of 156 tile numbers; wallset slot S, wall W is wall id (S - 1) * 5 + W of TWallTiles. }
  TWallSets = array[1..3, 1..5, 0..$9B] of Byte;
  { The loaded ECL script (whitepaper 4.2.2, 5.1): $1E00 bytes the loader allocates and LoadEcl
    fills; the script addresses it as VM addresses $9900..$B6FF (ReadVmWord region 3). }
  TEclCode = array[$9900..$B6FF] of Byte;
  { The three word blocks as the ECL script addresses them (MemRegion, ovl07:06FB): the game
    variables at VM addresses $4900..$4CFF, the second block (ds49D6) at $6B00..$6EFF, the third
    (ds49DA) at $9700..$98FF. The index base gives the displacement the code shows ($6E00, $2A00,
    -$2E00); TGameVars and TBlock400 stay the 0-based views of the same blocks. }
  TVmWords4900 = array[$4900..$4CFF] of Word;
  { One entry of the script's return stack (ScriptGosub, ovl07:1951): the address to return to
    and the entry below it. }
  PReturnEntry = ^TReturnEntry;
  TReturnEntry = record
    ReturnPC: Word;               { +0 }
    Next: PReturnEntry;           { +2 }
  end;
  TVmWords6B00 = array[$6B00..$6EFF] of Word;
  TVmWords9700 = array[$9700..$98FF] of Word;
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
    (NewMenuList, ovl04:0A18) and the Shop shows its stock and the character's carried items with the
    same record, so ovl04, ovl06 and ovl25 all share one type; Text is a string[40] (the Shop's
    ovl06:0030 assigns with a System_StrLCopy limit of $28) and the byte at +$29 is the menu line's
    cleared flag, so the link is at +$2A. PItem/TItem are the same record. }
  PByte = ^Byte;
  PMenuLine = ^TMenuLine;
  TMenuLine = record
    Text: string[40];             { +$00: the line's text (a menu line or an item name) }
    Flag29: Byte;                 { +$29: nonzero marks a heading line of a list menu: drawn in the
                                    heading colour and skipped by the highlight (ChooseFromList) }
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
  { One frame of the animated picture the prompt line (ReadPromptChoice) cycles while it waits for
    a key: the 4 bytes LoadSpriteList copies from the picture data are the frame's delay
    (ReadPromptChoice multiplies it by 10 and compares it with the GameClock hundredths since the
    last frame, ovl25:04D1), then the sprite (drawn by DrawSprite at column 3, row 3, ovl25:04CC). }
  TAnimFrame = record
    Delay: Longint;               { +0: tenths of a second the frame stays up }
    Sprite: Pointer;              { +4: the frame's picture }
  end;
  { The $42-byte sprite list at DS:6ABE seen as an animation (ReadPromptChoice): the number of frames, the
    frame shown, then the frames (OVL28 declares the same bytes as TSpriteList). }
  TAnimation = record
    Count: Byte;                  { +0: frames loaded }
    Current: Byte;                { +1: the frame shown, 1..Count; 0 when there is no animation }
    Frames: array[1..8] of TAnimFrame;  { +2 }
  end;
  TItem = TMenuLine;
  { A character in memory: the 285-byte record of whitepaper 4.2.5 (name, abilities and hp_max
    [V] by tools/re/records.py). Only the fields a decompiled unit uses are named; the Pad
    arrays keep the offsets. }
  PCharacter = ^TCharacter;
  { One 9-byte affect of a character's affect list (TCharacter.Affects; New and FreeMem size 9 in
    ovl24): AddAffect fills it, RemoveAffect unlinks it and, when Flag is set, first calls its
    handler (AffectHandlers) with mode 1. }
  PAffect = ^TAffect;
  TAffect = record
    Id: Byte;                     { +0: the affect number }
    Duration: Word;               { +1: 0 for a permanent affect (ApplyAffect replaces a shorter one) }
    Data: Byte;                   { +3: the affect's value (a strength affect keeps the earlier strength here) }
    Flag: Byte;                   { +4: nonzero: the handler runs when the affect is removed }
    Next: PAffect;                { +5: the next affect; nil ends the list }
  end;
  { The handler of an affect number (the table AffectHandlers): Mode 0 applies it, 1 removes it. }
  TAffectHandler = procedure(Who: PCharacter; Affect: PAffect; Mode: Byte);
  { The combat state of a character (TCharacter.Combat, +$108), read and written by the combat
    units ovl08 and ovl31; only the fields they use are named. }
  PCombatant = ^TCombatant;
  TCombatant = record
    { +$0: nonzero: the turn finishes this spell through ovl22_e5 (ovl08:0336); cleared when the
      combatant leaves the map (RemoveCombatant). }
    PendingSpell: Byte;
    CanCast: Byte;                { +$1: zero hides Cast in the combat menu (ovl08:0747) }
    Pad2: Byte;
    { +$3: the turn order: CombatTurn acts only above 0, the highest roll goes first
      (PickNextCombatant), Delay sets 1, $14 (the Alt-Q quick fight) acts as $13. Signed. Cleared
      by RemoveCombatant. }
    Initiative: ShortInt;
    Pad4: array[4..5] of Byte;
    { +$6: movement left in half squares (the Move menu shows Moves div 2); cleared by
      RemoveCombatant. }
    Moves: Byte;
    { +$7: cleared at the start of each turn (ovl08:021E) and by RemoveCombatant; meaning unknown }
    B7: Byte;
    Pad8: Byte;
    { +$9: the icon set (facing) DrawIcon draws the combatant with (SetCombatantIcon, ovl31);
      saved and restored around a move that is taken back (ovl08:09FD, 0B41). }
    IconSet: Byte;
    Target: PCharacter;           { +$A: the character attacked last (MeleeAttack sets it) }
    DyingRounds: Byte;            { +$E: the rounds a dying character (Status 5) has bled; above 9 it dies }
    BF: Byte;                     { +$F: cleared at the start of each turn (ovl08:0204); meaning unknown }
    Pad10: Byte;
    Turned: Byte;                 { +$11: nonzero hides Turn in the combat menu (ovl08:0795) }
    B12: Byte;                    { +$12: cleared at the start of each turn (ovl08:0211); meaning unknown }
    { +$13: nonzero: no body is left on the map when the combatant dies (RemoveCombatant, ovl31),
      and a dying character with it set is not bandaged (ovl08:1029). }
    NoBody: Byte;
  end;
  { One $13-byte record of the list at DS:6DBB (FreeMem size, ovl08:0029); only Next is known. }
  PCombatNode = ^TCombatNode;
  TCombatNode = record
    Pad0: array[0..3] of Byte;
    Next: PCombatNode;            { +$4 }
    Pad8: array[8..$12] of Byte;
  end;
  { One 16-byte row of the spell table DS:320A (SpellTable): RecalcClassStats reads the class
    and the level (ovl23:0110, 0119); the other bytes are not known yet. }
  TSpellEntry = record
    { +0: 0 for a cleric spell, 1 for a magic-user spell (the row of TCharacter.SpellSlots);
      signed: ovl15:02C0 compares it with a signed class. }
    SpellClass: ShortInt;
    Level: ShortInt;              { +1: the spell level 1..3, an index of TCharacter.SpellSlots; signed (ovl23:011D cwde) }
    Pad2: array[2..9] of Byte;
    { +$A: the affect the spell leaves on a character: the camp's Display names an affect by the first
      spell with this affect (ovl15:10D9). }
    AffectId: Byte;
    PadB: array[$B..15] of Byte;
  end;
  { The seven digits of the camp's rest clock RestTime (ovl20:02F2). }
  TRestClock = array[0..6] of Word;
  TCharacter = record
    Name: string[15];             { +$00 }
    Strength, Intelligence, Wisdom, Dexterity: Byte;  { +$10..$13 }
    Constitution: Byte;           { +$14: Raise Dead lowers it by one (ovl04:060E) }
    Charisma, StrengthPercent: Byte;  { +$15, +$16 }
    { +$17..+$2B: the memorized spells, one spell number per slot, 0 = empty (CombatMenu offers
      Cast when one is set, ovl08:071E; ovl14 looks for Knock in them). }
    Spells: array[0..20] of Byte;
    { +$2C: the hours of rest the character's study needs, 0, 4 or 6 (StudyRestMinutes sets it,
      CancelMemorizing clears it, ovl15:0123, 0191). }
    RestHours: Byte;
    { +$2D: the to-hit value: RecalcClassStats sets it to the best (highest) entry of
      ClassThac0Table over the character's classes (ovl23:0006..0062); whitepaper 4.2.5 calls it THAC0. }
    Thac0: Byte;
    { +$2E: the race (whitepaper 4.2.5); signed: ComputeThiefSkills sign-extends it (ovl23:034F)
      to index the race row of ThiefRaceTable. }
    Race: ShortInt;
    { +$2F: the class (whitepaper 4.2.5): 0 cleric, 2 fighter, 5 magic-user, 6 thief, 8..16 the
      multi-class combinations (AwardExperience splits the experience by 2 or 3, ovl05:0454);
      signed (the case at ovl05:045A compares with jl). }
    ClassMask: ShortInt;
    { +$30: the age in years; the saved record holds it at 0x30 (whitepaper 4.2.5); CarryClock adds one
      to every character when the rest clock's top digit reaches its radix (ovl20:037B). }
    Age: Word;
    HpMax: Byte;                  { +$32: maximum hit points }
    { +$33..+$6A: one byte per spell 1..$38 (the rows of the spell table SpellTable): RecalcClassStats sets it to 1
      for every cleric spell (table class 0) of a level the character has a cleric spell slot
      for (ovl23:0135); likely the spells the character can learn [I]. }
    KnownSpells: array[1..$38] of Byte;
    Pad6B: Byte;                  { +$6B }
    { +$6C: bits 0..6 are the combat footprint kind (PlaceCombatant copies them into CombatantTable[].Kind); bit 7
      is not part of it. }
    CombatSize: Byte;
    { +$6D..+$71: five values ComputeSavingThrows sets to 20 and lowers to the best entry of
      SaveTable over the character's classes (ovl23:026D..030D): the five saving throws [I]. }
    SavingThrows: array[0..4] of Byte;
    Pad72: Byte;
    { +$73: raised to the highest class level by RecalcClassStats (ovl23:0066), never lowered
      there; signed. }
    HighestLevel: ShortInt;
    Pad74: array[$74..$76] of Byte;
    { +$77..+$7E: the eight values ComputeThiefSkills builds from the thief level, the race and
      (for the first five) the dexterity: the thief skills [I] (ovl23:0329). }
    ThiefSkills: array[1..8] of Byte;
    Affects: Pointer;             { +$7F: the list of affects (res12_fn_2199, RemoveAffect walk it) }
    Pad83: Byte;
    { +$84: below $80 the party's Space command takes the character out of quick combat
      (ovl08:0504); meaning otherwise unknown. }
    B84: Byte;
    { +$85: the low three bits are the shares of the treasure a computer-run member (B84 $80 and up)
      takes for himself after a battle (TakeHirelingShares, ovl05:1329). }
    HirelingShare: Byte;
    Pad86: array[$86..$87] of Byte;
    { +$88..+$95: the character's money, seven words in the order of the pooled money TPartyMoney
      (a defeated monster's are added to it, ovl05:0093). }
    Money: array[0..6] of Word;
    { +$96..$9D: the level in each of the eight classes; Raise Dead treats index 2 apart (class 2
      is the fighter in the create-character run, whitepaper 5.8). Signed: only levels above 0 count. }
    ClassLevels: array[0..7] of ShortInt;
    Pad9E: array[$9E..$9F] of Byte;
    ByteA0: ShortInt;             { +$A0: the script reads it signed (GetCharacterVar, ovl07:08C5); meaning unknown }
    { +$A1: RecalcClassStats sets 3 when the fighter level (ClassLevels[2]) is above 6, else 2
      (ovl23:0083): likely attacks per two rounds [I]. }
    Attacks: Byte;
    PadA2: array[$A2..$AB] of Byte;
    Experience: LongInt;          { +$AC: experience points; AwardExperience adds a battle's share (ovl05:04A3) }
    PadB0: Byte;
    { +$B1: Raise Dead subtracts it from HpMax to get the hit points its constitution
      arithmetic works on (ovl04:0612); its meaning beyond that is not known. }
    HpB1: Byte;
    { +$B2..+$B7: the spell slots by spell class (0 cleric, 1 magic-user, the SpellClass of
      SpellTable) and spell level 1..3: RecalcClassStats copies the cleric row from ClericSlotTable
      for the cleric level (ovl23:00B0) and AddWisdomBonusSpells adds the wisdom bonus; the magic-user
      row comes from MageSlotTable (ovl23:014C). The spell menus index both rows with the class and
      level of a SpellTable entry (ovl15:02ED: [$B1 + class*3 + level]). }
    SpellSlots: array[0..1, 1..3] of Byte;
    { +$B8, +$BA: a monster's experience value: ComputeBattleExperience adds XpValue plus HpB1 times
      XpPerHp for every defeated monster (ovl05:00C4) [I]. }
    XpValue: Word;
    XpPerHp: Byte;
    HeadBank: Byte;               { +$BB: the HEAD picture bank number, 0 when none (ShowHeadBodyWindow) }
    BodyBank: Byte;               { +$BC: the BODY picture bank number, 0 when none (ShowHeadBodyWindow) }
    PadBD: array[$BD..$BE] of Byte;
    CombatIcon: Byte;             { +$BF: the icon picture DrawIcon draws for it on the combat map (ovl31) }
    PadC0: array[$C0..$C6] of Byte;
    ItemCountC7: Byte;            { +$C7: nonzero offers Use in the combat menu (ovl08:06E1); likely the item count }
    Items: PItem;                 { +$C8: the list of carried items }
    PadCC: array[$CC..$100] of Byte;
    SaveBonus: ShortInt;          { +$101: added to the d20 of every saving throw (SavingThrow, ovl24:0D96) }
    { +$102: the weight the character carries; every coin counts one (ovl21:0020, 003A), and it may
      not exceed CarryLimit, 1500 plus the strength allowance res12_fn_13AB (ovl21:0000, 0054). }
    CarriedWeight: Word;
    Next: PCharacter;             { +$104: the next character of the party list (ds5D96), nil ends it }
    Combat: PCombatant;           { +$108: the character's combat state (ovl08, ovl31) }
    { +$10C: the health status: 0 after Raise Dead and Stone to Flesh, 1 and 6 count as dead for
      Raise Dead, 7 as stoned for Stone to Flesh (ovl04:0539, 093D). }
    Status: Byte;
    Flag10D: Byte;                { +$10D: Raise Dead and Stone to Flesh set it to 1; MoveCombatCursor
                                    redraws only combatants with it set; meaning unknown }
    { +$10E: the side: SetQuickCombat compares it between attacker and target (ovl08:125D), and
      BandageDying only bandages characters with 0 (the party). }
    Side: Byte;
    { +$10F: nonzero while the computer fights for the character (quick combat): CombatTurn hands the
      turn to ovl09_e1 (ovl08:02B3); Quick sets it, the Space command clears it. }
    Quick: Byte;
    { +$110: added to the d20 an attack roll (RollToHit) must bring to the needed value (ovl24:0D41) [I]. }
    HitAdjust: Byte;
    { +$111: the d20 roll (20 counts 100) plus the level RollBeatsResistance is given must exceed it
      (ovl24:0C90); likely the magic resistance [I]. }
    ResistValue: Byte;
    Pad112: array[$112..$11A] of Byte;
    { +$11B: Raise Dead and Stone to Flesh set it to 1; HealCharacter adds to it up to HpMax,
      ReviveCombatant sets it and DropCombatant clears it: the current hit points [I] (ovl24:17B9). }
    Flag11B: Byte;
    { +$11C: the party's slowest and fastest values of it set the script's range (MovementRange,
      ovl07:1FB1), doubled by affect $27 and halved by affect $2A: likely the movement rate [I]. }
    Movement: Byte;
  end;
  { The 28 bytes at DS:67F4 that the Temple clears on entry and MoneyValueInGold turns into a LongInt
    sum (the money pooled in the shop or left after a battle): seven LongInt amounts, one per kind
    of money (ovl05 adds TCharacter.Money[0..6] into them, ovl05:0093, and values them at 1/200,
    1/20, 1/2, 1, 5, 250 and 2200 units each for the battle's experience, ovl05:0233). }
  TPartyMoney = array[0..6] of LongInt;
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
  { The combat map CombatMap points at (ovl31): a 7-byte header, then 25 rows of 50 tile ids. ovl30's
    WalkLine reads the same block as TMapRows (Head[6] is its tile gate). }
  TCombatMap = record
    Head0: array[0..1] of Byte;   { +$0..$1: not read by ovl31 }
    ViewX, ViewY: ShortInt;       { +$2, +$3: the map cell shown at the top left of the 7x7 view }
    ShowCursor: Byte;             { +$4: nonzero: the cursor icon is drawn on the cursor cells }
    CursorKind: Byte;             { +$5: the footprint kind of the cursor (ShowCursorOn; 1 otherwise) }
    Head6: Byte;                  { +$6: WalkLine's tile gate }
    Cells: array[0..24, 0..49] of Byte;  { +$7: the tile id of each cell, [row, column] }
  end;
  PCombatMap = ^TCombatMap;
  { One entry of DS:2744, the combat tile table (4 bytes per tile id; ovl30 reads the same table
    from DS:2745 as TTileEntry). }
  TCombatTile = record
    Cost: Byte;                   { +0: $FF: no combatant may stand there (PlaceCombatant); the largest
                                    cost under a footprint wins (ProbeStep) }
    Bound, Block: Byte;           { +1, +2: TTileEntry.BoundY and BlockY }
    Picture: Byte;                { +3: the cell picture DrawCellPicture draws for the tile }
  end;
  { One cell of a combat footprint (DS:2844): its offset from the combatant's cell, or DX = -1 for
    no cell. }
  TFootCell = record
    DX, DY: ShortInt;
  end;
  { A body left on the combat map (DS:66DD, RemoveCombatant): who died, where, and the tile it covered. }
  TBody = record
    Who: PCharacter;              { +0 }
    X, Y: ShortInt;               { +4, +5 }
    Tile: Byte;                   { +6: the tile id under the body }
  end;
  { A column span of one row of a placement shape (ovl10's DS:0306 table). }
  TColSpan = record
    Lo, Hi: ShortInt;
  end;
  { One entry of the DS:5F27 map entity table ScanTargets scans: the position, an unknown byte and
    a kind byte; entry 0's Kind holds the count e6 loops over (like ds6718[0].Val). }
  TMapEntry = record
    X, Y: ShortInt;               { +$0, +$1: the position in map coordinates }
    Unk2: Byte;                   { +$2: never read by ScanTargets; meaning unknown }
    Kind: Byte;                   { +$3: the footprint kind (FootprintCell; 1..4), 0 when not on the map }
  end;
  { One sixteen-byte combat AI row of RaceRow (ScoreTarget copies one into a local). }
  TRaceRow = array[0..15] of Byte;
const
  { Words of GameVars^ whose meaning is proven (word n is at byte offset 2n of the block; the
    matched reads in ovl26 are at +$186, +$188, +$1CC, +$1F6, +$1FA and +$1FC). }
  VarMapX = 195;                  { the party's column in the area map grid (44 wide) }
  VarMapY = 196;                  { the party's row in the area map grid }
  VarGeoBlock = 197;              { the GEO block id of the loaded 3D area map (Load3DMap, ovl29:11FB) }
  VarForceWallView = 230;         { nonzero: ShowAreaView shows the wall view whatever AreaViewKind says }
  { Nonzero: the overhead wall map is off (ShowAreaView clears WallMapMode, the A key cannot set
    it, ovl14:0380); the name predates that evidence. }
  VarShowWallOverlays = 251;
  VarWallIndexOutside = 253;      { the ds0C26 wall id index ShowAreaView uses for a cell that is not interior }
  VarWallIndexInside = 254;       { the ds0C26 wall id index for an interior cell (event byte bit 7) }
  VarRiverGate = 418;             { river-crossing gate: CheckMapCell prints the stench message while it is 0
                                    (ovl14:0905); who sets it is not known yet }
var
  { The 13 code wheel records of the copy protection (whitepaper 5.12): the answer, the rune
    indices and the path pattern. CheckCodeWheel picks one at random. }
  ds0000: array[0..12] of TCodeWheelEntry;  { the code wheel records; see above }
  ds04DF: string[40];             { prompt string HandleWildernessKeys passes to ReadPromptChoice; filled elsewhere }
  { The wall view's id table: two equal groups of eight ids (0,15,12,11,13,10,9,14). ShowAreaView
    indexes it with the game variables VarWallIndexOutside and VarWallIndexInside. Its last six
    bytes are also entry 0 of SpecialBlocks, which DrawAreaView never reads. }
  ds0C26: array[0..15] of Byte;  { wall view id table, two equal groups of 8; see above }
  SpecialBlocks: array[0..9] of TSpecialBlock;  { entries 1..9 tested; only 3..9 replace the map block }
  ds2612: Word;                   { word passed to PlaySound by QuitGame and the Ctrl-S pause path; meaning unknown }
  ds260A: array[0..7] of Byte;    { 8-byte structure FillPictureRect copies from @ds260A (DrawWallDescriptors) }
  ds2622: Word;                   { word e1 passes to PlaySound when Done is 0; meaning unknown }
  ds2628: Word;                   { word the ovl14 movement code passes to PlaySound; meaning unknown }
  { Five words, one per 8x8 tile bank, subtracted from the symbol number to index within the
    bank (Put8x8Symbol, ovl34:020F); evidence in re/dseg.toml. }
  SymbolBase: array[0..4] of Word;  { per-bank base symbol numbers; see above }
  ds272C: Word;                   { LoadWallSet adds the bank's symbol offset to the wall tile numbers at or above it }
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
  ds04B6: string[40];             { prompt string HandleWildernessKeys passes to ReadPromptChoice in the movement loop }
  DebugMode: Boolean;             { STING debug mode: switched by Ctrl-D in ReadGameKey; ShowDebugTrace shows only when set }
  AreaViewKind: Byte;             { what to draw: 1 the 3D wall view, 2..4 the map window page; evidence in re/dseg.toml }
  ds6A60: Byte;                   { wall view descriptor 1 (of 4): SetWallDescriptors sets them }
  ds6A61: Byte;                   { wall view descriptor 2: ShowAreaView fills it from ds6F69 when ds84E5 is set }
  ds6A62: Byte;                   { wall view descriptor 3: ShowAreaView fills it from ds6F69 when ds84E5 is set }
  ds6A63: Byte;                   { wall view descriptor 4: ShowAreaView fills it from ds6F68 when ds84E5 is set }
  { Nonzero: the view shows the overhead wall map (DrawWallMap) instead of the 3D walls and their
    frame (DrawWallView, ovl29:0603). The A key of the movement loop toggles it while
    GameVars^[VarShowWallOverlays] is 0 (ovl14:0380); ShowAreaView (when that variable is set),
    ShowEncounterPicture and StartGame clear it. }
  WallMapMode: Byte;              { overhead wall map shown instead of the 3D view; see above }
  ds6AAD: ShortInt;               { the party's column in the 16x16 area map (GEO) }
    { ShortInt, not Byte: ovl14 widens it with cbw (ovl14:0696); EventByteAt/DrawWallView take it. }
  ds6AAE: ShortInt;               { the party's row in the 16x16 area map }
    { ShortInt, not Byte: ovl14 widens it with cbw (ovl14:069D); EventByteAt/DrawWallView take it; set to 1 by StartGame. }
  { The marker's icon set (DrawIcon's third parameter): the wilderness keys H, M, P and K set 0,
    2, 4 and 6 (HandleWildernessKeys, HandleWildernessKeys); WriteVmWord maps a script value 0..3 to the same 0/2/4/6. }
  ds6AAF: Byte;                   { the marker's icon set; see above }
  ds6AB0: Byte;                   { WallIdAt's result for the party cell and icon set (MoveParty); meaning unknown }
  ds6AB1: Byte;                   { the event byte of the party's map cell, from EventByteAt; bit 7 = interior }
  MarkerFrame: Byte;              { the party marker's animation frame 0..5; evidence in re/dseg.toml }
  { special view code 2: StartGame sets $DB (ovl11:0435, inside StartGame); InitScript sets $41 and ds84E5 }
  ds6F68: Byte;
  { special view code 1: StartGame sets $E8; InitScript sets 9 and ds84E5 }
  ds6F69: Byte;
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
                                    1 draws through FillPlaneRect, 2 fills four planes; meaning unknown }
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
  EclCode: ^TEclCode;              { $1E00-byte block the loader allocates (ovl11:0064) }
  GameSpeed: Byte;                   { set to 1 by the loader; a count the ovl18 narratives read }
  ds4A16: Word;                   { EGA/VGA plane segment SetActivePage sets to AIndex shl 9 + $A000 }
  ds4A18: Word;                   { EGA/VGA plane segment SetPlaneSegment sets to AIndex shl 9 + $A000 }
  { The view mode: ShowEndingNarrative saves it, sets 7, restores it; VisitTemple sets 1 (ovl04:0D0F);
    5 during combat (ovl31 changes the combat map only then). }
  ds49F3: Byte;                   { the view mode; see above }
  ds0900: array[0..$A] of Byte;   { the first door block codes of AnimateAreaDoors (bit 7 = other bank) }
  ds090B: array[0..$11] of Byte;  { the second door block codes of AnimateAreaDoors (indexed 0..$11); same 7-bit flag }
  ds091D: array[0..$F] of Byte;   { the first 16-byte record AnimateAreaDoors passes to res07_fn_1E5C }
  ds092D: array[0..$F] of Byte;   { the second 16-byte record AnimateAreaDoors passes to res07_fn_1E5C }
  ds093D: array[0..$F] of Byte;   { the third 16-byte record AnimateAreaDoors passes to res07_fn_1E5C }
  ds094D: array[0..8] of Word;    { the per-step DrawAreaView columns of AnimateAreaDoors (indexed 0..8) }
  ds095F: array[0..8] of Word;    { the per-step DrawAreaView rows of AnimateAreaDoors (indexed 0..8) }
  ds470E: Pointer;                { the FINAL picture bank ShowEndingNarrative loads through LoadPicture and draws }
  ds4712: Byte;                   { the DS:49F3 value ShowEndingNarrative saves at the start and restores at the end }
  ds4713: string[1];              { Str(TileSet): the picture number ShowEndingNarrative appends to FINAL }
  ds25C0: array[0..2, 0..2] of Byte;  { the 3x3 line pattern table StepLine reads at [SY+1, SX+1] }
  { ds2736 and ds273F: nine entries each (ds273F starts 9 bytes after ds2736). ovl14's
    ClampPartyPosition also adds them as the party's column and row step (cbw at ovl14:06D0, 06DB). }
  ds2736: array[0..8] of ShortInt;  { the x step per direction; see above }
  ds273F: array[0..8] of ShortInt;  { the y step per direction; see above }
  ds2745: array[0..255] of TTileEntry;  { the tile table WalkLine reads; see above }
  CombatantTable: array[0..72] of TMapEntry;  { the combatants on the combat map; entry 0's Kind is the count
                                    (72 entries fit before CombatantViewCol) }
  CombatantViewCol: array[1..72] of ShortInt;  { each combatant's column on the 7x7 view (X - ViewX, ovl31) }
  CombatantViewRow: array[1..72] of ShortInt;  { each combatant's row on the view (Y - ViewY, ovl31) }
  CellOccupant: array[0..24, 0..49] of Byte;  { the combatant standing on each map cell, 0 for none (RebuildOccupancy) }
  { The character record of each combatant (ovl31); MoveCharacter attacks CombatantRecord[n] for
    the number ProbeStep returns (ovl08:0BF8). }
  CombatantRecord: array[1..72] of PCharacter;  { see above }
  BodyTable: array[1..8] of TBody;   { the bodies left on the combat map (RemoveCombatant) }
  BodyCount: Byte;                   { the number of bodies in BodyTable }
  { The combat map (ovl31): the $4E9-byte block EndCombat frees (ovl08:0041); EndCombatRound
    centres the view on ViewX/ViewY (ovl08:0937). }
  CombatMap: PCombatMap;             { see above }
  { The combat tile table; overlaps ds2745 (one byte on). Cost is also the movement cost:
    MoveCharacter refuses ("Blocked") a step whose cost is above the moves left (ovl08:0C5F). }
  CombatTiles: array[0..255] of TCombatTile;  { see above }
  Footprints: array[0..4, 0..3] of TFootCell;  { the cells of footprint kinds 1..4 (kind 0 unused) }
  DyingPicture: Pointer;                { the picture RemoveCombatant draws over a dying combatant's cells }
  ds261E: Word;                   { the sound RemoveCombatant plays (PlaySound) when a combatant dies }
  ds6718: array[0..255] of TSortRec;  { the ovl30 sort table (element 0 holds the count, SortTable) }
  EclPC: Word;                   { set to $9900 by the loader (ovl11:03C0) }
  ds49E5: Word;                   { the second script entry address (see ds49E3); the ovl14 L key copies it to EclPC }
  ds49F4: Byte;                   { cleared by the loader (ovl11:03CB) }
  ShowPortraits: Byte;            { nonzero: the portraits are shown; the camp's Pics submenu toggles it
                                    (ovl15:1D31, 1DFC); the loader sets it to 1 (ovl11:0392) }
  ShowMonsterPics: Byte;          { nonzero: the monster pictures are shown; the camp's Pics submenu toggles it
                                    (ovl15:1D02, 1DE9); the loader sets it to 1 (ovl11:0397) }
  ds49F8: Byte;                   { cleared by the loader (ovl11:03A6) }
  ds49F9: Byte;                   { set to 1 by the loader (ovl11:03EB) }
  ds49FB: Word;                   { cleared by the loader (ovl11:03AD) }
  PartyDestroyed: Byte;           { 1 when no player-run member is left (SettleBattleOutcome); loader clears it }
  ds4A00: Byte;                   { set to 1 by the loader (ovl11:03A1) and by EndBattle (ovl05:1631) }
  ds4A24: Pointer;                { screen buffer the loader allocates through AllocatePicture (ovl11:00D4) }
  ds4A28: array[0..$A7] of Byte;  { $A8-byte buffer the loader clears (ovl11:00EC) }
  { The changed-region trackers the blitters (res07 08D4/0D71) fill and res07
    ShowChanges (1B52) flushes: per changed screen row, ds4AD0 and ds4C20 hold
    the first and last changed byte offset and ds4D70 the last; indexed by word
    (row*2), so 168 word entries. The loader clears/fills the same $150 bytes
    through FillChar (ovl11:00FD, 010E, 011F). }
  ds4AD0: array[0..$A7] of Word;  { first changed offset of the row }
  ds4C20: array[0..$A7] of Word;  { last changed offset of the row (starts $FFFF) }
  ds4D70: array[0..$A7] of Word;  { last changed offset of the row (starts 0) }
  { Per-cell screen address table the loader fills (ovl11:0130..0163): $B800 (even cell) or $BA00
    (odd cell) plus 5*(I div 2). }
  ds4EC0: array[0..$C7] of Word;  { cell text scanline address; see above }
  ds5050: array[0..$C7] of Word;  { per-cell row offset table the loader fills (ovl11:0186): I*40 }
  { Per-cell plane address table the loader fills (ovl11:019F..0241): 10*(I div 4) plus $B800,
    $BA00, $BC00 or $BE00. }
  ds51E0: array[0..$C7] of Word;  { cell graphics plane address; see above }
  ds5370: Byte;                   { set to 1 by the loader (ovl11:042E) }
  SoundDriverIdle: Word;          { nonzero: sound timer driver stopped between sounds (RES03); ovl11:045D clears it }
  ds5377: Byte;                   { TileSet saved by SelectTileSet; the loader also sets it to 1 }
  ds5378: Word;                   { set to 1 by the loader (ovl11:03E0) }
  ds547A: Word;                   { set to 1 by the loader (ovl11:03DA) }
  ds547D: Byte;                   { a character the loader appends to the path through System_MemOp_0C3B (ovl11:0581) }
  ds557C: Byte;                   { cleared by the loader (ovl11:0438) }
  ds5582: array[0..$80F] of Byte;   { $810-byte buffer the loader reads the file block into (ovl11:05CD) }
  { 129 sixteen-byte combat AI rows indexed by race (ScoreTarget copies the row of Who^.Race
    into a local and scores it): the same block the loader uses as its file buffer (load time
    only, ovl11:05CD). The row count ($810 div 16) is from the size; the per-race meaning of
    the bytes is open. }
  RaceRow: array[0..128] of TRaceRow absolute ds5582;
  { The selected character: the Temple acts on it (ovl04 reads it everywhere), ShowHeadBodyWindow
    shows its HEAD and BODY pictures (ovl28:04F9); the loader sets it nil (ovl11:03B8). }
  SelectedCharacter: PCharacter;  { see above }
  ds286F: array[0..13] of Byte;   { the HEAD picture number per bank (SelectedCharacter^.HeadBank, ShowHeadBodyWindow) }
  ds287D: array[0..13] of Byte;   { the BODY picture number per bank (SelectedCharacter^.BodyBank, ShowHeadBodyWindow) }
  KeypadScanLetters: array[0..8] of Char; { 'OPQK MGHI': the scan code letter of keypad digits 1..9 (ReadPromptChoice) }
  ds5D96: LongInt;                { head of the TCodeRec list ovl14 walks (see below) }
    { Kept LongInt, not Pointer: the loader clears it with `ds5D96 := 0` (ovl11:03B0),
      which is Error 26 for a Pointer (proven by a make tpc probe); ovl14 reaches the
      records through Pointer(ds5D96). }
  ds5E1E: Word;                   { BlockRead result count of the loader (ovl11:05D6) }
  GameFont: ^TBlock588;             { $588-byte block the loader allocates (ovl11:0074) }
  GlyphCol: Byte;                   { 0768's current glyph column: reset to Left on clear/newline, Inc per glyph }
  GlyphRow: Byte;                   { 0768's current glyph row: reset to Top on clear, Inc per newline }
  ds6810: PMenuLine;              { head of the shop's item list, a far pointer the loader clears (ovl11:031A) }
  WallTiles: ^TWallTiles;            { the wall tiles, $924 bytes the loader allocates (ovl11:0084) }
  ds6A5C: ^TBlock400;             { $400-byte block the loader allocates (ovl11:0094) }
  ds84DC: Byte;                   { the wall view / outdoor mode EventByteAt tests (0 and $A both skip) }
  GeoCells: PGeoCellBlock absolute ds6A5C; { cell-byte view of the $400 block for ovl14 }
  WallSets: ^TWallSets absolute WallTiles; { the wall tiles by wallset slot and wall (LoadWallSet) }
  ds6AAEWords: array[0..3] of TPresenceSlot;  { the 4-byte element table at DS:6AAE; the loader sets
                                    elements 2 and 3 to $FFFF (ovl11:035E..0390) }
  ds6AB2: Word;                   { cleared by the loader (ovl11:0353) }
  ds6AB4: Word;                   { set to 1 by the loader (ovl11:0358) }
  ds6AB6: array[0..7] of Byte;    { DS:6AB6..6ABD, 8 bytes no decompiled routine reads; declared so that the
                                    frame indexing of ReadPromptChoice (PictureAnimation.Frames[I], a base 8 bytes
                                    below the record, ovl25:04C8) resolves to the original offsets }
  { The $42-byte sprite list the loader clears (ovl11:0309) and ShowEncounterPicture loads; ReadPromptChoice
    animates it while it waits for a key. }
  PictureAnimation: TAnimation;
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
  { The ten pieces a wall of the 3D view is drawn from (DrawWallPiece, DrawWallView): each piece is a
    rectangle of 8x8 tiles, Width x Height, whose tiles follow each other in a wall's 156-byte tile
    list from FirstTile on (the image's values 0,2,6,..,$9A add up to $9C exactly), drawn with its
    top left tile at view column Col, row Row. Indexed by the piece number 0..9. }
  WallPieceFirstTile: array[0..9] of Byte;     { first tile of each wall piece in the 156-byte tile list; see above }
  WallPieceWidth: array[0..9] of Byte;     { width in tiles of each wall piece; see above }
  WallPieceHeight: array[0..9] of Byte;     { height in tiles of each wall piece; see above }
  WallPieceCol: array[0..9] of Integer;  { view column of each wall piece's top left tile; see above }
  WallPieceRow: array[0..9] of Integer;  { view row of each wall piece's top left tile; see above }
  ds70C7: ShortInt;               { loop counter of FreeSpriteList (the sprite list slots); ShortInt: the loop exits with jg }
  ListMenuTop: Integer;            { the list menu's first shown line (ChooseFromList); 1 after the loader (ovl11:0405) }
  PromptWordChoice: Byte;         { the highlighted word of the prompt line, 1-based (ReadPromptChoice) }
  LastPromptExtKey: Byte;         { the last prompt's Flag (an extended key), copied by ReadPromptChoice }
  PromptTimeout: Longint;         { prompt timeout in GameClock hundredths; 0 waits forever (ReadPromptChoice) }
  PromptTimeoutKey: Char;         { the key the prompt returns when the timeout runs out (ReadPromptChoice) }
  ds6DDA: Byte;                   { cleared by the loader (ovl11:0410) }
  ds6DDE: array[0..2] of Byte;    { 3-byte buffer the loader fills with 1 (ovl11:0342) }
  ds6DE0: Byte;                   { knock menu flag: e1 offers Knock while nonzero; overlaps ds6DDE[2] }
  ds6DDF: Byte;                   { pick/knock menu flag (e1 offers Pick/Knock while nonzero) }
    { DoPick clears it. Overlaps ds6DDE[1]; exact sharing uncertain. }
  DuelMode: Byte;                 { nonzero during a duel (EndBattle's duel texts); the loader clears it (ovl11:040B) }
  ds84DD: Byte;                   { cleared by the loader (ovl11:0415) }
  ds84DE: Byte;                   { cleared by the loader (ovl11:041A) }
  ds84DF: Byte;                   { cleared by the loader (ovl11:041F) }
  ds84E0: Byte;                   { cleared by the loader (ovl11:0424) }
  ds84E3: Byte;                   { cleared by the loader (ovl11:0433) }
  ds84E4: Byte;                   { window-clear once flag: HandleWildernessKeys clears the text window and sets it }
  ds84E9: Byte;                   { cleared by the loader (ovl11:0456) }

  { The 8x8 tile world of ovl34 (whitepaper 4.x): which 8X8D file to take the bank from, the five
    loaded banks, the staging buffer tiles are copied through, the buffer res07_fn_08D4 draws
    into, and a word ShowPicture takes. Evidence in re/dseg.toml. }
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
  ds681F: Byte;                   { 1 while the Temple removes affects (RemoveAffect; ovl04:0386, 05AB, 07CE), 0 after }
  PooledMoney: TPartyMoney;       { the Temple clears it on entry (ovl04:0D32) and passes it to MoneyValueInGold }
  ds6C95: PCharacter;             { the character Remove Curse hands to ovl22_e9 (ovl04:08FA) }
  { 1 while money lies in the pool: PoolMoney sets it, ShareMoney sets it when some is left; the
    Temple and the shop clear it with the pool (ovl04:0D37). }
  MoneyInPool: Byte;
  { Globals of the DOS file and BIOS text layer (res05); evidence in re/dseg.toml where named. }
  { 16 entries, the colours 0..15 mapped to 0..3 (0,0,0,1,2,2,2,3,3,1,1,1,2,2,3,3 in the image);
    WriteCharsAt maps the text colour through it when VideoAdapter is 0 (0802:0086). }
  ds25D5: array[0..15] of Byte;   { four-colour map of the text colours; see above }
  { EGA plane masks for DrawGlyph mode 1 (0709:03C0): selected through Port[$3C5] by
    3 - Bit; adjacent to GlyphColorPatterns. }
  EgaPlaneMasks: array[0..3] of Byte;
  { Per-colour words DrawGlyph mode 0 ORs into the pixel accumulator (0709:02A3):
    indexed by the mapped colour 0..3; adjacent to ds25D5. }
  GlyphColorPatterns: array[0..3] of Word;
  { Per-column words DrawGlyph mode 0 ANDs with the colour word (0709:02B0):
    indexed by the bit column 0..7. }
  GlyphPixelMasks: array[0..7] of Word;
  { Plane bit masks 1, 2, 4, 8 that res07's direct picture blit writes to the Sequencer Map Mask
    (port 3C5h) for plane 0..3 when it copies one byte per plane (0464:1A6E). }
  EgaPlaneBitMasks: array[0..3] of Byte;
  ds49CE: Word;                   { IOResult of the last FileExists file probe (0802:0334) }
  { Characters 0768's word scanner tests (0709:0822..08F0): the leading run is skipped,
    the word run stops at them or space, the trailing run is skipped. Storage descriptor
    $0404 in the three 0D12 calls: 4 bytes at bit offset 32 (set of #32..#63, proven by a
    make tpc probe). Storage overlaps BadNameChars entry 0 at $D19 by one byte. No writer
    exists anywhere in the image; the initial bytes are 70 00 8C 20 (members $, %, &, 2,
    3, 7, =). Runtime meaning of those members: open. }
  BreakChars: set of #32..#63;
  { The ten characters MakeDosFileName removes from a file name are entries 1..10 (DS:0D1A..0D23);
    entry 0 is the byte before them, never read (declared so the index base DS:0D19 names it). }
  BadNameChars: array[0..10] of Char;  { characters not allowed in a file name; see above }
  { The value of the five coins in copper pieces: copper 1, silver 10, electrum 100, gold 200,
    platinum 1000 (the image); MoneyValueInGold values money with it and divides by the gold entry. }
  { Rows of eight words describing the fixed treasure items BuildTreasureItem builds (DS:0970): a row starts at
    the index BuildTreasureItem picks (1, 9, $11, ... $91, and $90 once) and holds the three name numbers,
    the weight, the value and three affect numbers (ovl21:182F..18C2; the image). }
  TreasureItemRows: array[0..$98] of Word;
  CoinCopperValues: array[0..4] of LongInt;
  { The names of the seven kinds of money, string[10] at DS:0FFA: Copper, Silver, Electrum, Gold,
    Platinum, Gems, Jewelry (the image); the Take menu lists the pool with them (ovl21:0DDF). }
  MoneyKindNames: array[0..6] of string[10];
  PackedBuf: Pointer;             { the packed bytes of the DAX block LoadDaxBlock is reading }
  { Colour maps for res07_fn_1E5C (16 entries, colour I becomes entry I): ds0CD2 is the identity,
    ds0CE2 turns colour 13 into 8 and ds0CF2 turns 13 into 0 (the image). LoadPictureSlot recolours the
    TileSet picture sets from ds0CD2 to ds0CE2 and ICON from ds0CD2 to ds0CF2. }
  ds0CD2: array[0..15] of Byte;   { identity colour map; see above }
  ds0CE2: array[0..15] of Byte;   { colour 13 to 8; see above }
  ds0CF2: array[0..15] of Byte;   { colour 13 to 0; see above }
  { Fill bytes of FillPictureRect (the image: 00 55 AA FF then 00 11 .. BB at ds0D06..). ds0D02[C] is
    the byte of four 2-bit pixels of colour C (C 0..3); ds0D06[C] the byte of two 4-bit pixels of
    colour C (C * $11). The two tables overlap: ds0D02[C + 4] is ds0D06[C]. }
  ds0D02: array[0..15] of Byte;   { four 2-bit pixels of colour C; see above }
  ds0D06: array[0..15] of Byte;   { two 4-bit pixels of colour C (C * $11); see above }
  { Globals of the combat unit ovl08 (whitepaper 5.5). }
  ds6DBB: PCombatNode;            { a list of $13-byte records EndCombat frees (ovl08:0006); meaning unknown }
  ds6E36: Pointer;                { a picture EndCombat frees through ReleasePicture (ovl08:005A) }
  { A routine pointer: RunCombat sets @ovl13_e14 at the start (ovl08:0085) and EndCombat
    @ovl22_e4 at the end (ovl08:0069); who calls it is not known yet. }
  ds6B84: Pointer;                { routine RunCombat stores at ovl08:0085 and EndCombat at ovl08:0069 }
  ds6814: Byte;                   { zero (or ds6815 zero) ends the combat (ovl08:009B, 095C); likely the count of one side }
  ds6815: Byte;                   { see ds6814; likely the count of the other side }
  { ds6814 and ds6815 indexed by side (ovl10:1AC7); the combat AI indexes them by the
    res12_fn_23B7 side of the actor (UseMagicItem, CastMemorizedSpell, ovl09:049F, 05C6). }
  ds6814Sides: array[0..1] of Byte absolute ds6814;
  ds6825: Byte;                   { AI morale scratch (CheckMorale computes it from B84, compares percentages) }
  ds6E2F: Byte;                   { byte CheckMorale copies into ds6825; meaning unknown }
  ds6E30: Boolean;                { the Alt-M Magic On/Off toggle of the combat keys (ovl08:04A7) }
  ds6E31: Byte;                   { the key flag the ovl08 menus pass to ReadPromptChoice }
  ds6DE3: Byte;                   { counted up once per combat round (ovl08:0891) }
  { Class tables of ovl23 (whitepaper 5.6). Their extents are not known (only the rows the
    characters reach are read). A table whose columns count from 1 is addressed from the byte
    before it ([row, column] is base - 1 + row * width + column), so that byte is declared just
    before the table: it is never read, and declaring it makes the index base name it in our
    layout as in the original (as BadNameChars does). }
  { The spell table: one 16-byte row per spell 1..$38 at DS:320A. Entry 0 (DS:31FA) is never
    read: it is declared so that the index base, which RecalcClassStats adds (ovl23:0103), names it. }
  SpellTable: array[0..$38] of TSpellEntry;  { see above }
  ClassThac0Table: array[0..7, 0..10] of Byte;  { the to-hit value per class 0..7 and level (RecalcClassStats) }
  ds40BC: Byte;                   { the byte before ClericSlotTable; see above }
  ClericSlotTable: array[0..12, 1..3] of Byte;  { cleric spell slots of levels 1..3 per cleric level }
  ds41D4: Byte;                   { the byte before MageSlotTable; see above }
  MageSlotTable: array[0..12, 1..3] of Byte;  { magic-user spell slots of levels 1..3 per magic-user level }
  SavingThrowTable: array[0..7, 0..8, 0..4] of Byte;  { the five saving throws per class 0..7 and level }
  ds3CF3: Byte;                   { the byte before ThiefSkillTable; see above }
  ThiefSkillTable: array[0..8, 1..8] of Byte;  { the eight thief skills per thief level }
  ds3D3B: Byte;                   { the byte before ThiefRaceTable; see above }
  ThiefRaceTable: array[0..7, 1..8] of ShortInt;  { the race adjustment of the eight thief skills }
  ds3D4E: Byte;                   { the byte before ThiefDexTable; see above }
  ThiefDexTable: array[0..18, 1..5] of ShortInt;  { the dexterity adjustment of the first five thief skills }
  { Globals of the camp's rest clock, ovl20 (whitepaper 5.22). }
  { The radix of each digit of RestTime (ovl20:02F2): a digit that reaches its radix gives one unit to the next
    digit. Seven words in the image at DS:363A, 10, 10, 6, 24, 30, 12, 256: minutes, tens of minutes, hours,
    days, months, years [I]. }
  ClockRadix: array[0..6] of Word;
  { Globals of the battle's aftermath ovl05 (whitepaper 5.20). }
  MonstersLooted: Byte;           { 1 when a defeated monster gave up its money and items (ovl05:0088) }
  PartyFled: Byte;                { 1 when the party fled the battle (a member with Status 3, ovl05:050D) }
  NoExperienceCount: Byte;        { members that get no share of the battle's experience (ovl05:05EA) }
  BattleExperience: LongInt;      { the experience each character receives for the battle (ovl05:060B) }
  BattleWon: Byte;                { 1 when the party (or the duelist) won the battle (ovl05:05CA, 07AC) }
  ds5D9A: PMenuLine;              { loot list entry where the battle's item experience count stops (ovl05:02E5) }
  { Globals of the affect and roll unit ovl24. }
  SaveRoll: Byte;                 { the saving throw roll: d20 plus SaveBonus and the bonus (ovl24:0D73) }
  HookAffectId: Byte;             { the affect ApplyAffect offers to the hooks; 0 afterwards: unaffected (ovl24:1672) }
  DamageAmount: Byte;             { the damage DealDamage offers to the hooks and then deals (ovl24:134E) }
  DamageKind: Byte;               { the kind of damage: 1 fire, 2 cold, 4 electricity, $10 acid, bit 3 magic (ovl24:13E4) }
  ds681C: Byte;                   { the dice count of the last RollDiceCounted roll (ovl24:0E37) }
  AttackRoll: ShortInt;           { the d20 attack or resistance roll (20 counts 100) the hooks may change (ovl24:0C63) }
  SaveKind: Byte;                 { the saving throw kind SavingThrow offers to the hooks (ovl24:0DAD) }
  { The handler of every affect number, called through CallAffectHandler (ovl24:001E); extent unknown. Entry 0
    is not a handler: SaveKind lies in it. }
  AffectHandlers: array[0..$8B] of TAffectHandler;  { see above }
  { The sixteen affects RemoveDeathAffects removes are entries 1..16 at DS:0C14 ($07 $0B $1E $1F $20
    $33 $34 $35 $36 $3A $3B $5F $62 $89 $4A $4B in the image); entry 0 is the byte before. }
  DeathAffects: array[0..16] of Byte;  { affects removed when a combatant dies; see above }
  { The two affects ovl24_e14 removes are entries 1..2 at DS:0C24 ($4A $4B); entry 0 is the byte before. }
  ds0C23: array[0..2] of Byte;    { entries 1..2 ($4A $4B) are the affects ovl24_e14 removes }
  { Globals of the camp unit ovl15 (whitepaper 5.22). }
  CampMenuText: string[40];             { 'Save View Magic Rest Alter Exit': the Camp menu MakeCamp shows (ovl15:1F06) }
  CampMagicMenuText: string[40];             { 'Cast Memorize Scribe Display Rest Exit': the camp Magic menu (ovl15:1429) }
  AlterMenuText: string[40];             { 'Order Drop Speed Icon Pics Exit': the camp Alter menu (ovl15:1C86) }
  PartyOrderMenuTexts: array[0..1] of string[40];  { 'Select Exit' and 'Place Exit': the Party Order menu before and after a
                                    character is picked (ovl15:17B0) }
  { The time a rest lasts, one word per digit of the game clock (ovl20 indexes it, ovl20:04A7): the
    camp's Rest command sets [1] minutes, [2] tens of minutes and [3] hours from the longest study
    time of the party (ovl15:07CA) before ovl20_e2 runs the rest, and clears all seven words after. }
  RestTime: TRestClock;
  ds6DB5: Pointer;                { set to nil when the camp opens and closes and before casting (ovl15:04B0, 1FB6) }
  ds6DD8: Word;                   { cleared when the camp opens (ovl15:1E80); meaning unknown }
  { The spell names, string[40] per spell 1..$38 at DS:2912 ('Bless' .. 'Restoration' in the image,
    the rows of SpellTable); entry 0 is the index base (ovl15:10EE), never read. }
  SpellNames: array[0..$38] of string[40];
  { Globals of the combat map builder ovl10 (whitepaper 5.5.2). }
  CombatBlock: Byte;              { the area map block code the battle is fought on (ovl10:1215) }
  { The combat direction (an index of ds2736/ds273F) of a facing 0..3; PrepareCombatants also
    uses it as the starting icon set (ovl10:1363, 15EA). }
  FacingCombatDir: array[0..3] of Byte;
  { Per side (PlacingSide): 4 groups of 6 rows of 11 placement cells, 1 while free (ovl10:1480). }
  PlacementCells: array[0..1, 0..3, 0..5, 0..10] of Byte;
  SideOriginCol: array[0..1] of ShortInt;   { per side: the grid origin column in area map steps (ovl10:1597) }
  SideOriginRow: array[0..1] of ShortInt;   { per side: the grid origin row in area map steps (ovl10:15A4) }
  FirstRingCells: array[0..1] of ShortInt;  { per side: the cells of its first placement ring (ovl10:17DB) }
  SideFacing: array[0..1] of ShortInt;      { per side: the facing 0..3 (ovl10:1A3D) }
  { Combat AI step patterns (ovl09): row Combat+$15 (RollDice(1, 2) in ovl09:08CD), column the
    attempt 0..4; the byte is added to the base direction mod 8 before ProbeStep (ovl09:068B..06C2).
    Rows of 5 from DS:02AE up to FacingWallDirs (DS:02D2) give 7 rows; row 0 is all zero [I]. }
  StepTurnOffsets: array[0..6, 0..4] of Byte;
  { Per side facing: the area map directions (entries 1..3) FindStartCell tests for walls (ovl10:1879). }
  FacingWallDirs: array[0..3, 0..3] of Byte;
  { Per side facing: twice the facing of each placement group 0..3 (ovl10:15C5). }
  GroupFacing: array[0..3, 0..3] of Byte;
  RingStartCol: array[Boolean, 0..3] of ShortInt;  { a ring's first column, per group > 0 and facing (ovl10:1640) }
  RingStartRow: array[Boolean, 0..3] of ShortInt;  { a ring's first row, per group > 0 and facing (ovl10:1672) }
  { The column span (Lo..Hi) of each of the 6 rows of a placement shape: shapes 0..3 per facing,
    4 for group 1 (ovl10:1B38). }
  PlacementShapes: array[0..4, 0..5] of TColSpan;
  PlacingSide: ShortInt;          { the side being placed on the combat map (ovl10:1C41) }
  { Globals of the ECL script machine's memory and operands (ovl07, whitepaper 5.1). }
  { The three word blocks as the script addresses them (see TVmWords4900): the same pointers as
    GameVars, ds49D6 and ds49DA. }
  VarsAt4900: ^TVmWords4900 absolute GameVars;
  VarsAt6B00: ^TVmWords6B00 absolute ds49D6;
  VarsAt9700: ^TVmWords9700 absolute ds49DA;
  ds49FD: Byte;                   { the HEAD bank ShowHeadBody last loaded (ovl07:051C) }
  ds49FE: Byte;                   { the BODY bank ShowHeadBody last loaded (ovl07:0522) }
  ds6F6A: Word;                   { returned for script address $FB (ReadVmWord, ovl07:0EC3); meaning unknown }
  ds6F6C: Word;                   { returned for script address $FC (ReadVmWord, ovl07:0ED0); meaning unknown }
  ds6F6E: Word;                   { returned for script address $B1 (ReadVmWord, ovl07:0EB6); meaning unknown }
  ds84CC: Word;                   { set by a script write to address $3DE (WriteVmWord, ovl07:0D3B); meaning unknown }
  ds84CE: Word;                   { set by a script write to address $B8 (WriteVmWord, ovl07:0D48); meaning unknown }
  ds84D0: Word;                   { set by a script write to address $B9 (WriteVmWord, ovl07:0D55); meaning unknown }
  ds84D2: Byte;                   { set to 1 when the script writes 0 to the character word $6C00 (ovl07:0B99) }
  ds84D3: Byte;                   { set to 1 when the script writes 0 to the character word $6B00 (ovl07:0A91) }
  ds84E1: Byte;                   { cleared by ShowHeadBody (ovl07:0514); meaning unknown }
  ds84E6: Byte;                   { set to 1 when the script moves the party or changes its marker (ovl07:0D6C..0DD6) }
  ds84E8: Byte;                   { set to 1 when the script writes game variable $49FD or $49FE (ovl07:0CAF) }
  { The decoded operands of the current script command (DecodeOperands, ovl07:0000): entries
    1..64 of each table; entry 0 is the byte before, never read (in the image it is the last entry
    of the table before). OperandType 0 is an immediate byte, 1 and 3 an address to read, 2 an
    immediate word, $80 a packed string, $81 the address of a string. }
  OperandType: array[0..64] of Byte;
  OperandHigh: array[0..64] of Byte;   { the high byte of a word operand }
  OperandLow: array[0..64] of Byte;    { the low byte, or the length of a packed string }
  { The string operands of the current command, entries 1.. in operand order (DecodeOperands);
    entry 0 is the index base, never read (in the image it overlaps the operand tables). The upper
    bound is not known: the largest operand count seen is 14 (ovl03). }
  EclStrings: array[0..14] of string;
  { The five entry addresses of the loaded script, read from its header by InitScript
    (ovl07:0260..02B8); coab calls them vm_run_1, SearchLocation, PreCampCheck, CampInterrupted
    and ecl_initial_entryPoint [H]. The wilderness L key starts the script at the second
    (ovl14). }
  ds49E3: Word;                   { the first script entry address; see above }
  ds49E7: Word;                   { the third script entry address; see above }
  ds49E9: Word;                   { the fourth script entry address; see above }
  ds49EB: Word;                   { the fifth script entry address; see above }
  ReturnStack: PReturnEntry;           { the top of the script's return stack (ScriptGosub); InitScript empties it }
  ReturnPrev: PReturnEntry;           { the previous top while ScriptGosub pushes; InitScript clears it }
  { The results of the script's last comparison (CompareStrings, CompareWords): 1 in [0] when
    equal, [1] unequal, [2] less, [3] greater, [4] less or equal, [5] greater or equal, else 0. }
  CompareFlags: array[0..5] of Byte;
  SkippedOpcode: Byte;                   { the opcode SkipCommand reads at EclPC (ovl07:1EB7) }
  ds84EA: Byte;                   { the head/picture word ds49D6^[$2E1] ShowEncounterPicture last showed (ovl07:0633) }
  ds6F83: Byte;                   { set to 8 by InitScript (ovl07:01F0); meaning unknown }
  ds70C6: Byte;                   { cleared by InitScript (ovl07:01FB); meaning unknown }
  ds84C8: array[0..1] of Byte;    { two bytes InitScript clears (ovl07:01DF); meaning unknown }
  ds84E2: Byte;                   { cleared by InitScript (ovl07:01C1); meaning unknown }
implementation
end.
