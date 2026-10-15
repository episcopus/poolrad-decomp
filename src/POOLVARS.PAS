unit POOLVARS;
{ Game globals whose owning unit is not known yet. Names: dsXXXX is the DS offset
  (re/dseg.toml may give a better name later); others are named in re/dseg.toml. }
{$A-,F+,S-,R-,G-,I-}
interface
uses Dos, Overlay, Crt;
type
  { One record of the code wheel table at DS:0002 (whitepaper 5.12; CheckCodeWheel reads it for the copy
    protection question). The table begins two bytes in because Turbo Pascal keeps DS:0000 for itself, so
    the first record's two leading bytes (the original's Unknown field, never read) are those two bytes
    and the record ends with them. }
  TCodeWheelEntry = record
    CodeWord: string[6];          { +0 (the original's +2): the answer the player must type }
    OuterRune: Byte;               { +7: the Espruar (outer ring) rune index }
    InnerRune: Byte;               { +8: the Dethek (inner ring) rune index }
    ThirdRune: Byte;               { +9: the third rune index }
    FourthRune: Byte;              { +$A: the fourth rune index, $FF when the record has none }
    Path: string[7];               { +$B: the path pattern drawn under the runes }
    Unknown: array[0..1] of Byte;  { +$13: not read by CheckCodeWheel }
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
    variables at VM addresses $4900..$4CFF, the second block (GameVars2) at $6B00..$6EFF, the third
    (GameVars3) at $9700..$98FF. The index base gives the displacement the code shows ($6E00, $2A00,
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
    PlusSave: ShortInt;           { +$33: signed (AddReadiedItemBonus sign-extends it) }
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
  { One slot of the training-hall function menu at DS:0619 (11 records, stride 42): the line the
    create-character overlay (ovl16) draws and whether the function is offered. RunCharacterMenu reads
    Name[I] with I = 0..10 and gates the hotkey 'C'..'J' on Present. }
  TFunctionSlot = record
    Name: string[40];
    Present: Byte;               { +$29: nonzero: the function is drawn and its hotkey works }
  end;
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
  { The combat target picker stored in DS:6B84: the spell number, an unused byte and Done in/out
    (ChooseSpellTargets, ovl22:0A91; ovl08 stores it and CastChosenSpell calls it). }
  TSpellTargetPicker = procedure(Spell: Byte; Unused: Byte; var Done: Byte);
  { A cast handler: SpellHandlers holds one parameterless far routine per spell number; it reads the
    current spell from CastingSpell and applies it (InitSpellHandlers fills entries 1.. from overlay stub 0096:0057
    on; CastChosenSpell calls SpellHandlers[Spell] after the picker, whitepaper 5.22). }
  TSpellHandler = procedure;
  { The combat state of a character (TCharacter.Combat, +$108), read and written by the combat
    units ovl08, ovl09 and ovl31; only the fields they use are named. ovl10 allocates $16 bytes for it
    (CombatRecordSize), which is this record's size with the fields to +$15. }
  PCombatant = ^TCombatant;
  TCombatant = record
    { +$0: nonzero: the turn finishes this spell through CastChosenSpell (ovl08:0336); cleared when the
      combatant leaves the map (RemoveCombatant). }
    PendingSpell: Byte;
    CanCast: Byte;                { +$1: zero hides Cast in the combat menu (ovl08:0747) }
    { +$2: zero makes UseMagicItem give up at once (ovl09:03E4); no other decompiled unit reads it [I]. }
    CanUseMagicItem: Byte;
    { +$3: the turn order: CombatTurn acts only above 0, the highest roll goes first
      (PickNextCombatant), Delay sets 1, $14 (the Alt-Q quick fight) acts as $13. Signed. Cleared
      by RemoveCombatant. }
    Initiative: ShortInt;
    Pad4: array[4..5] of Byte;
    { +$6: movement left in half squares (the Move menu shows Moves div 2); cleared by
      RemoveCombatant. }
    Moves: Byte;
    { +$7: the guard flag: GuardTurn (00BA:2686) sets it to 1 and EndCombatTurn (00BA:2637)
      clears it; also cleared at the start of each turn (ovl08:021E) and by RemoveCombatant }
    B7: Byte;
    { +$8: the has-attacked-this-round flag: StartCombatantRound clears it and
      ResolveCombatantAttacks sets it to 1 (ovl13:143A); RefreshAttacks (ovl13:0E0B) lets the new
      attack count through while it is 0. }
    Pad8: Byte;
    { +$9: the icon set (facing) DrawIcon draws the combatant with (SetCombatantIcon, ovl31);
      saved and restored around a move that is taken back (ovl08:09FD, 0B41). }
    IconSet: Byte;
    Target: PCharacter;           { +$A: the character attacked last (MeleeAttack sets it) }
    DyingRounds: Byte;            { +$E: the rounds a dying character (Status 5) has bled; above 9 it dies }
    BF: Byte;                     { +$F: cleared at the start of each turn (ovl08:0204); meaning unknown }
    { +$10: nonzero forces flight: CheckMorale (ovl09:10D7) then shows 'is forced to flee' and sets Panic;
      QuickTurn shows 'flees in panic' only while it is zero (ovl09:000F). }
    ForcedFlight: Byte;
    Turned: Byte;                 { +$11: nonzero hides Turn in the combat menu (ovl08:0795) }
    B12: Byte;                    { +$12: cleared at the start of each turn (ovl08:0211); meaning unknown }
    { +$13: nonzero: no body is left on the map when the combatant dies (RemoveCombatant, ovl31),
      and a dying character with it set is not bandaged (ovl08:1029). }
    NoBody: Byte;
    { +$14: nonzero while the combatant is panicking: CheckMorale clears it and sets it on a failed
      morale roll; AiTurn moves a panicking combatant with MoveStep (ovl09:0B3C, ovl09:07F2). }
    Panic: Byte;
    { +$15: the step pattern, 1..6, the row of StepTurnOffsets that CanAffordStep and MoveStep read;
      QuickTurn and MoveStep reroll it (ovl09:000F, 07F2). }
    StepPattern: Byte;
  end;
  { One $13-byte record of the list at DS:6DBB (New/GetMem size 19, FreeMem size 19 at ovl08:0029): a
    cloud on the combat map: CastStinkingCloud (ovl22:1B11) allocates one, fills it and later walks the
    list, and ClearCloud (ovl12:0CC3) frees it. Its centre is (X, Y); arm i is one step from it in
    direction CloudArmDirections[i], and Tiles[i] is the tile that arm covered before the cloud came. }
  PCombatNode = ^TCombatNode;
  TCombatNode = record
    Owner: PCharacter;            { +$0: the character the cloud belongs to (the caster) }
    Next: PCombatNode;            { +$4: the next cloud marker in the list }
    Tiles: array[1..4] of Byte;   { +$8..$B: the tile each arm covered (found around the aim point) }
    Arms: array[1..4] of Byte;    { +$C..$F: nonzero while the arm is still in place (a walkable combat tile) }
    { +$10, +$11: the centre cell, the aim column and row (SpellAimX and SpellAimY at the cast; signed, cwde at
      ovl22:1D3A, 1D74). }
    X, Y: ShortInt;
    { +$12: the high nibble of the Data of the affect that made it (the caster's cloud count at the cast). }
    Kind: Byte;
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
  { The 41 bytes at DS:28E9, the storage of SpellNames[0] (never read as a name): the four bytes at
    +$25 hold the aim directions the Stinking Cloud handler scans around a spell's aim point (the image has
    8, 2, 3, 4 at DS:290E..2911), the rest is not known yet. }
  TSpellNamesPrefix = record
    Unknown: array[0..$24] of Byte;   { +0..+$24 }
    AimDirs: array[1..4] of Byte;     { +$25..+$28: the cloud aim directions at DS:290E }
  end;
  { One entry of the starting-age table StartingAgeTable: a new character of that race and class starts Base years
    old plus Count dice of Sides sides (ovl16:056C). }
  TAgeEntry = record
    Base: Word;                   { +0: the base age in years }
    Count: Byte;                  { +2: the number of dice }
    Sides: Byte;                  { +3: the sides of each die }
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
    { +$6B: the sweep-attack limit RecalcCombatValues (00BA:0BB8) sets: the fighter level
      (ClassLevels[2]) when it is above 0 and the race is above 0, else 1; StartCombatantRound
      (ovl13:0000) copies it into the combatant's attack-slot limit (Combat^.Pad4[5]) which
      SweepEnemies reads, and CollapseAndChangeSide (ovl12:0B1B) sets it from the fighter level too. }
    SweepAttacks: Byte;
    { +$6C: bits 0..6 are the combat footprint kind (PlaceCombatant copies them into CombatantTable[].Kind); bit 7
      is not part of it. }
    CombatSize: Byte;
    { +$6D..+$71: five values ComputeSavingThrows sets to 20 and lowers to the best entry of
      SaveTable over the character's classes (ovl23:026D..030D): the five saving throws [I]. }
    SavingThrows: array[0..4] of Byte;
    { +$72: the character's base movement; RecalcCombatValues copies it into Movement (+$11C) and
      SetArmourMovement restores it for light armour. }
    BaseMovement: Byte;
    { +$73: raised to the highest class level by RecalcClassStats (ovl23:0066), never lowered
      there; signed. }
    HighestLevel: ShortInt;
    Pad74: array[$74..$76] of Byte;
    { +$77..+$7E: the eight values ComputeThiefSkills builds from the thief level, the race and
      (for the first five) the dexterity: the thief skills [I] (ovl23:0329). }
    ThiefSkills: array[1..8] of Byte;
    Affects: Pointer;             { +$7F: the list of affects (HasAffect, RemoveAffect walk it) }
    Pad83: Byte;
    { +$84: for computer-run members, low seven bits are morale and high bit $80 marks the AI
      (PrepareCombatants, ovl10:0675; CheckMorale, ovl09:10D7). Below $80, the party's Space
      command takes the character out of quick combat (ovl08:0504) [I]. }
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
    { +$9E: Sign-extended row index LoadMonster's caller (ovl17:1262) and the create menus (ovl16)
      use to pick the character's picture banks: ovl17:1262 reads FigureSuffixChars[2 + B9E*8 + roll] and
      FigureSuffixChars[18/28/38/48 + B9E*5 + roll], and ovl16:13CB reads RaceAbilityLimits[B9E + (Race shl 4)].
      ovl16:0A29 sets it to (the create menu's selection - 1); it is probably the sex, 0 male
      (whitepaper 4.2.5), but that is not settled. }
    B9E: ShortInt;
    { +$9F: the creature kind some spells test a target by: Charm Person and the shared helper
      ovl22_fn_1758 require 1 or less (ovl22:11F3, 1760), Snake Charm $E (ovl22:193E) and ovl12
      tests 4 and $A; MON*CHA has the humanoids at 0 or 1, the undead at 4 and a giant snake at $E,
      and a saved party member at 0. }
    CreatureType: Byte;
    { +$A0: the script reads it signed (GetCharacterVar, ovl07:08C5). Purpose unknown: ScoreItem (ovl09:128D)
      refuses an item whose Affects[3] is $84 when the low nibble of its Affects[2] differs from this byte. }
    ByteA0: ShortInt;
    { +$A1: RecalcClassStats sets 3 when the fighter level (ClassLevels[2]) is above 6, else 2
      (ovl23:0083): likely attacks per two rounds [I]. }
    Attacks: Byte;
    { +$A2..+$AB: the character's base attack triple, each a pair of entries 1..2: the AI item
      chooser (ovl09:13CA) reads only entry 1 (it multiplies +$A3 by +$A5 into its item score and,
      when the signed +$A7 is above 0, adds twice it). RecalcCombatValues copies both entries of the
      three pairs into the readied weapon block at +$115. +$A9 is the base value RecalcCombatValues
      copies into ResistValue (+$111); ovl16:05E4 sets it to 50. The rest is unknown. }
    PadA2: Byte;
    BaseAttacks: array[1..2] of Byte;      { +$A3, +$A4: attacks per round (base) }
    BaseDamage: array[1..2] of Byte;       { +$A5, +$A6: damage (base) }
    BaseDamageBonus: array[1..2] of ShortInt;  { +$A7, +$A8: signed damage bonus (base) }
    ResistBase: Byte;             { +$A9: base magic resistance RecalcCombatValues copies into ResistValue }
    { +$AA: the strength reaction and damage adjustments (StrengthAttackAdjustment, StrengthDamageAdjustment) apply only
      when this byte is nonzero; its meaning beyond that is not proven (it may mark a creature whose
      attacks use the strength tables). }
    StrengthBonusFlag: Byte;
    { +$AB: LoadMonster's caller gives a new monster the value Random(256) here (ovl17:1262);
      the rest of the byte's use is not known. }
    BAB: Byte;
    Experience: LongInt;          { +$AC: experience points; AwardExperience adds a battle's share (ovl05:04A3) }
    { +$B0: the character's class bits [I]: UseBestItem skips an item whose ClassMask (TItemRow) shares
      no bit with it (ovl09:13CA). Purpose unknown beyond that. }
    ClassBits: Byte;
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
    CHeadBlock: Byte;             { +$BD: the CHEAD picture block BuildCharacterIcon loads for the combat icon }
    CBodyBlock: Byte;             { +$BE: the CBODY picture block BuildCharacterIcon loads for the combat icon }
    CombatIcon: Byte;             { +$BF: the icon picture DrawIcon draws for it on the combat map (ovl31) }
    { +$C0..+$C6: the character's figure descriptor as BuildCharacterIcon reads it. Figure[0] indexes FigureSuffixChars
      for the CHEAD/CBODY name suffix; Figure[1..6] are six colour pairs (low nibble the source
      colour's destination in the icon colour map, high nibble the source colour's + 8 slot). }
    Figure: array[0..6] of Byte;
    ItemCountC7: Byte;            { +$C7: nonzero offers Use in the combat menu (ovl08:06E1); likely the item count }
    Items: PItem;                 { +$C8: the list of carried items }
    { +$CC..+$FF: the per-kind items the character remembers (13 pointer slots): ovl09:13CA
      compares the item it picked with slots 0 and 1 and checks their Cursed flag, ovl09:0B3C and
      ovl13 read ItemTable[ItemType] of slot 0, and ovl19 indexes the slots by ItemTable[ItemType].Slot
      and reads the slots of item types $49 and $1C at +$F8 and +$FC (11 and 12). The writer is
      not in the overlays: ReadyItem (ovl19:14D0) does not store it. }
    SlotItems: array[0..12] of PItem;  { +$CC }
    { +$100: the hands the character's items take [I]. ScoreItem refuses an item whose Hands plus this is
      above 3 (ovl09:128D). UseBestItem first takes the Hands of the slot-0 and slot-1 items off it, then
      gives the slot-1 hands back after a use, and tests it against 2 (ovl09:13CA). Whether it counts hands
      in use or hands free is not proven: the subtraction runs before the pick is made. }
    HandsInUse: Byte;
    SaveBonus: ShortInt;          { +$101: added to the d20 of every saving throw (SavingThrow, ovl24:0D96) }
    { +$102: the weight the character carries; every coin counts one (ovl21:0020, 003A), and it may
      not exceed CarryLimit, 1500 plus the strength allowance StrengthWeightAllowance (ovl21:0000, 0054). }
    CarriedWeight: Word;
    Next: PCharacter;             { +$104: the next character of the party list (PartyListHead), nil ends it }
    Combat: PCombatant;           { +$108: the character's combat state (ovl08, ovl31) }
    { +$10C: the health status: 0 after Raise Dead and Stone to Flesh, 1 and 6 count as dead for
      Raise Dead, 7 as stoned for Stone to Flesh (ovl04:0539, 093D). }
    Status: Byte;
    Flag10D: Byte;                { +$10D: combat participation and experience eligibility: AwardExperience
                                    grants XP only when set (ovl05:0355); Raise Dead and Stone to Flesh set it;
                                    MoveCombatCursor redraws only combatants with it set }
    { +$10E: the side: SetQuickCombat compares it between attacker and target (ovl08:125D), and
      BandageDying only bandages characters with 0 (the party). }
    Side: Byte;
    { +$10F: nonzero while the computer fights for the character (quick combat): CombatTurn hands the
      turn to QuickTurn (ovl08:02B3); Quick sets it, the Space command clears it. }
    Quick: Byte;
    { +$110: added to the d20 an attack roll (RollToHit) must bring to the needed value (ovl24:0D41) [I]. }
    HitAdjust: Byte;
    { +$111: the d20 roll (20 counts 100) plus the level RollBeatsResistance is given must exceed it
      (ovl24:0C90); likely the magic resistance [I]. }
    ResistValue: Byte;
    { +$112: RecalcCombatValues computes it (the sum of its frame bytes [bp-$B]..[bp-9] minus two);
      not read by a decompiled routine yet, meaning unknown. }
    ds112: Byte;
    { +$113, +$114: two bytes indexed 1..2 by PartingShots, which picks the higher one that is nonzero
      as its attack slot and sets it to 1 (ovl13:0B80..0BBA); StartCombatantRound writes entry 2
      from the attack byte (ovl13:006E). What the pair counts is not settled. The lower bound is 1
      so the compiler emits the same `add di, ax` addressing as the original. }
    AttackSlots: array[1..2] of Byte;
    { +$115, +$117, +$119: the readied weapon's attack triple, each a pair of entries 1..2. RecalcCombatValues
      copies the base triple (+$A3, +$A5, +$A7) in and ApplyWeaponBonuses then overwrites entry 1 from
      the ItemTable row of the weapon's item kind (bytes 9, $A and $B). The AI's item score multiplies
      +$A5 by +$A3 and adds twice +$A7, so the three read as the attacks per round, the damage and a
      signed damage bonus [I]. Entry 2 rides along, never read by a decompiled routine. }
    WeaponAttacks: array[1..2] of Byte;       { +$115, +$116 }
    WeaponDamage: array[1..2] of Byte;        { +$117, +$118 }
    WeaponDamageBonus: array[1..2] of ShortInt;  { +$119, +$11A: signed; the strength and item plus bonus goes here }
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
    Pattern: Byte;                 { +$19: a pattern byte StepLine sets from LinePatternTable }
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
    a kind byte; entry 0's Kind holds the count e6 loops over (like SortEntries[0].Val). }
  TMapEntry = record
    X, Y: ShortInt;               { +$0, +$1: the position in map coordinates }
    Unk2: Byte;                   { +$2: never read by ScanTargets; meaning unknown }
    Kind: Byte;                   { +$3: the footprint kind (FootprintCell; 1..4), 0 when not on the map }
  end;
  { One 16-byte row of ItemTable: the ITEMS file record of whitepaper 4.3. The field names are those of
    coab's ItemData as tools/re/items.py decodes them [H]; the layout is verified by the round trip [V].
    ovl09 reads +0, +1, +5, +9..+$E; +6..+8 and +$F are not read by any decompiled routine. }
  TItemRow = record
    Slot: Byte;                   { +0: the item's slot kind (UseBestItem, ovl09:13CA, tests it for 0 and 1) }
    Hands: Byte;                  { +1: the hands the item takes }
    DiceCountLarge: Byte;         { +2 }
    DiceSizeLarge: Byte;          { +3 }
    BonusLarge: ShortInt;         { +4 }
    Attacks: Byte;                { +5: the number of attacks (ScoreItem, ovl09:128D, counts those beyond the first) }
    { +6: bit 7 set means the item has a bonus class (the byte and $7F; AddReadiedItemBonus, 00BA:0282) }
    BonusClass: Byte;
    Pad7: array[7..8] of Byte;
    DiceCountNormal: Byte;        { +9: dice rolled against normal-size foes }
    DiceSizeNormal: Byte;         { +$A: the die size against normal-size foes }
    BonusNormal: ShortInt;        { +$B: the damage bonus against normal-size foes (signed) }
    Range: Byte;                  { +$C: the attack range }
    ClassMask: Byte;              { +$D: the class bits that may use the item (ANDed with ClassBits) }
    Flags: Byte;                  { +$E: the flag bits of the AI's item step (ovl09 constants FlagAttack etc.) }
    Pad15: Byte;
  end;
const
  { Words of GameVars^ whose meaning is proven (word n is at byte offset 2n of the block; the
    matched reads in ovl26 are at +$186, +$188, +$1CC, +$1F6, +$1FA and +$1FC). }
  VarMapX = 195;                  { the party's column in the area map grid (44 wide) }
  VarMapY = 196;                  { the party's row in the area map grid }
  VarGeoBlock = 197;              { the GEO block id of the loaded 3D area map (Load3DMap, ovl29:11FB) }
  VarForceWallView = 230;         { nonzero: ShowAreaView shows the wall view whatever AreaViewKind says }
  VarSavedWallView = 242;         { WallViewMode before ECL command 32 (ovl03:0BD1) set it; the wilderness
                                    loop (ovl03:32F8) reads it back on entry and writes it after each key }
  { Nonzero: the overhead wall map is off (ShowAreaView clears WallMapMode, the A key cannot set
    it, ovl14:0380); the name predates that evidence. }
  VarShowWallOverlays = 251;
  VarWallIndexOutside = 253;      { the WallViewIdTable wall id index ShowAreaView uses for a cell that is not interior }
  VarWallIndexInside = 254;       { the WallViewIdTable wall id index for an interior cell (event byte bit 7) }
  VarRiverGate = 418;             { river-crossing gate: CheckMapCell prints the stench message while it is 0
                                    (ovl14:0905); who sets it is not known yet }
  { Word 710 of GameVars2^ (the second game word block, $6B00..$6EFF, not GameVars^): the morale source of
    computer-run members (ovl10 sets B84 from it; StartBattle caps it at 100) [I]; CheckMorale reads it
    (ovl09:10D7). }
  Var2Morale = 710;
{ ---- DGROUP layout, generated by tools/re/dgroup.py (playbook 50): do not reorder ---- }
const
  { The initialised data of DGROUP, DS:0002..43DB, in the original's order (the Overlay unit's own
    constants follow it). Every object keeps its name; where another object overlaps it the bytes
    sit in a dsXXXX cell and the objects are `absolute` views of it (tools/re/dgroup.py, playbook 50). }
  { DS:0002..00F0: storage of CodeWheelRecords }
  Raw0002: array[0..238] of Byte =
    (
      $06, $42, $45, $57, $41, $52, $45, $1D, $1E, $6C, $70, $09, $2D, $20, $2D, $20,
      $2D, $20, $2D, $20, $2D, $06, $5A, $4F, $4D, $42, $49, $45, $5B, $5C, $4D, $FF,
      $09, $2D, $2E, $2E, $2D, $2E, $2E, $2D, $2E, $2E, $06, $4E, $4F, $54, $4E, $4F,
      $57, $2C, $2D, $6A, $FF, $09, $2E, $2E, $2E, $2E, $2E, $2E, $2E, $2E, $2E, $06,
      $43, $4F, $50, $50, $45, $52, $09, $0A, $43, $FF, $09, $2D, $20, $2D, $20, $2D,
      $20, $2D, $20, $2D, $06, $44, $52, $41, $47, $4F, $4E, $01, $02, $68, $FF, $09,
      $2D, $2E, $2E, $2D, $2E, $2E, $2D, $2E, $2E, $06, $45, $46, $52, $45, $45, $54,
      $11, $12, $6D, $FF, $09, $2E, $2E, $2E, $2E, $2E, $2E, $2E, $2E, $2E, $06, $46,
      $52, $49, $45, $4E, $44, $17, $18, $3F, $FF, $09, $2D, $20, $2D, $20, $2D, $20,
      $2D, $20, $2D, $06, $4A, $55, $4E, $47, $4C, $45, $19, $1A, $4E, $FF, $09, $2D,
      $2E, $2E, $2D, $2E, $2E, $2D, $2E, $2E, $06, $4B, $4E, $49, $47, $48, $54, $22,
      $23, $6C, $FF, $09, $2E, $2E, $2E, $2E, $2E, $2E, $2E, $2E, $2E, $06, $53, $41,
      $56, $49, $4F, $52, $2E, $2F, $42, $FF, $09, $2D, $20, $2D, $20, $2D, $20, $2D,
      $20, $2D, $06, $54, $45, $4D, $50, $4C, $45, $36, $37, $4B, $FF, $09, $2D, $2E,
      $2E, $2D, $2E, $2E, $2D, $2E, $2E, $06, $56, $55, $4C, $43, $41, $4E, $34);
  { DS:00F1..0112: storage of TempleMenuText }
  ds00F1: array[0..33] of Byte =
    (
      $35, $6E, $FF, $09, $2E, $2E, $2E, $2E, $2E, $2E, $2E, $2E, $2E, $06, $57, $59,
      $56, $45, $52, $4E, $2C, $2D, $47, $FF, $09, $2D, $20, $2D, $20, $2D, $20, $2D,
      $20, $2D);
  { DS:0113..02AD: storage of DiseaseAffects }
  ds0113: array[0..410] of Byte =
    (
      $00, $1F, $22, $2B, $2C, $32, $39, $0E, $43, $75, $72, $65, $20, $42, $6C, $69,
      $6E, $64, $6E, $65, $73, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $0C, $43, $75, $72, $65, $20, $44, $69, $73, $65, $61, $73, $65, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $11, $43, $75, $72, $65, $20, $4C,
      $69, $67, $68, $74, $20, $57, $6F, $75, $6E, $64, $73, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $13, $43, $75, $72, $65, $20, $53, $65, $72, $69, $6F, $75, $73, $20,
      $57, $6F, $75, $6E, $64, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $14, $43, $75, $72, $65,
      $20, $43, $72, $69, $74, $69, $63, $61, $6C, $20, $57, $6F, $75, $6E, $64, $73,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $11, $4E, $65, $75, $74, $72, $61, $6C, $69, $7A, $65, $20,
      $50, $6F, $69, $73, $6F, $6E, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0A, $52, $61,
      $69, $73, $65, $20, $44, $65, $61, $64, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $0C, $52, $65, $6D, $6F, $76, $65, $20, $43, $75,
      $72, $73, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0E,
      $53, $74, $6F, $6E, $65, $20, $74, $6F, $20, $46, $6C, $65, $73, $68, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $04, $45, $78, $69, $74, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00);
  { DS:02AE..02D1: storage of StepTurnOffsets }
  ds02AE: array[0..35] of Byte =
    (
      $00, $00, $00, $00, $00, $00, $08, $07, $06, $01, $02, $08, $01, $02, $07, $06,
      $07, $01, $08, $06, $02, $01, $07, $08, $02, $06, $08, $07, $06, $05, $04, $08,
      $01, $02, $03, $04);
  { Per side facing: the area map directions (entries 1..3) FindStartCell tests for walls (ovl10:1879). }
  FacingWallDirs: array[0..3, 0..3] of Byte = ((8, 4, 6, 2), (8, 6, 4, 0), (8, 0, 6, 2), (8, 2, 0, 4));
  { Per side facing: twice the facing of each placement group 0..3 (ovl10:15C5). }
  GroupFacing: array[0..3, 0..3] of Byte = ((0, 0, 2, 6), (2, 2, 0, 4), (4, 4, 2, 6), (6, 6, 4, 0));
  { The combat direction (an index of DirStepX/DirStepY) of a facing 0..3; PrepareCombatants also
    uses it as the starting icon set (ovl10:1363, 15EA). }
  FacingCombatDir: array[0..3] of Byte = (7, 2, 3, 6);
  { a ring's first column, per group > 0 and facing (ovl10:1640) }
  RingStartCol: array[Boolean, 0..3] of ShortInt = ((5, 4, 5, 6), (3, 8, 7, 2));
  { a ring's first row, per group > 0 and facing (ovl10:1672) }
  RingStartRow: array[Boolean, 0..3] of ShortInt = ((3, 2, 2, 3), (0, 2, 5, 3));
  { DS:0306..0331: storage of PlacementShapes }
  ds0306: array[0..43] of Byte =
    (
      $01, $00, $01, $00, $01, $00, $02, $09, $03, $0A, $04, $0A, $00, $02, $00, $03,
      $01, $04, $02, $05, $03, $06, $04, $07, $00, $06, $00, $07, $01, $08, $01, $00,
      $01, $00, $01, $00, $03, $06, $04, $07, $05, $08, $06, $09);
  { DS:0332..0381: storage of FourListedNames }
  Raw0332: array[0..79] of Byte =
    (
      $07, $0A, $08, $0A, $00, $06, $00, $07, $01, $08, $02, $09, $03, $0A, $04, $0A,
      $06, $4B, $4F, $42, $4F, $4C, $44, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $0D, $4B, $4F, $42, $4F, $4C, $44, $20, $4C, $45, $41, $44, $45, $52, $00, $00,
      $06, $47, $4F, $42, $4C, $49, $4E, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $0D, $47, $4F, $42, $4C, $49, $4E, $20, $4C, $45, $41, $44, $45, $52, $00, $00);
  { Eight 16-byte names at DS:0382 (rows 1 to 8), directly after FourListedNames: the names the affect handler at ovl12:0947
    compares with the attacked character's name. Their text is not read yet [?]. }
  EightListedNamesA: array[1..8] of string[15] = (
      'ORC',
      'ORC LEADER',
      'GOBLIN',
      'GOBLIN LEADER',
      'HOBGOBLIN',
      'HOBGOBLIN CHIEF',
      'GAGOOL',
      'MACE');
  { DS:0402..0446: storage of EightListedNamesB }
  Raw0402: array[0..68] of Byte =
    (
      $04, $4F, $47, $52, $45, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $0B, $4F, $47, $52, $45, $20, $4C, $45, $41, $44, $45, $52, $00, $00, $00, $00,
      $05, $54, $52, $4F, $4C, $4C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $0A, $46, $49, $52, $45, $20, $47, $49, $41, $4E, $54, $00, $00, $00, $00, $00,
      $0A, $48, $49, $4C, $4C);
  { DS:0447..04B5: storage of TurnUndeadTable }
  Raw0447: array[0..110] of Byte =
    (
      $20, $47, $49, $41, $4E, $54, $00, $00, $00, $00, $00, $0A, $07, $04, $01, $01,
      $00, $00, $FF, $FF, $FF, $0D, $0A, $07, $01, $01, $00, $00, $00, $FF, $FF, $10,
      $0D, $0A, $04, $01, $01, $00, $00, $00, $FF, $13, $10, $0D, $07, $04, $01, $01,
      $00, $00, $FF, $14, $13, $10, $0A, $07, $04, $01, $01, $00, $00, $63, $14, $13,
      $0D, $0A, $07, $04, $01, $01, $00, $63, $63, $14, $10, $0D, $0A, $07, $04, $01,
      $00, $63, $63, $63, $14, $10, $0D, $0A, $07, $04, $01, $63, $63, $63, $63, $14,
      $10, $0D, $0A, $07, $01, $63, $63, $63, $63, $63, $14, $10, $0D, $0A, $04);
  { prompt string HandleWildernessKeys passes to ReadPromptChoice in the movement loop }
  WildernessPromptWithArea: string[40] = 'Area Cast View Encamp Search Look';
  { prompt string HandleWildernessKeys passes to ReadPromptChoice; filled elsewhere }
  WildernessPromptNoArea: string[40] = 'Cast View Encamp Search Look';
  { Globals of the camp unit ovl15 (whitepaper 5.22). }
  { 'Save View Magic Rest Alter Exit': the Camp menu MakeCamp shows (ovl15:1F06) }
  CampMenuText: string[40] = 'Save View Magic Rest Alter Exit';
  { 'Cast Memorize Scribe Display Rest Exit': the camp Magic menu (ovl15:1429) }
  CampMagicMenuText: string[40] = 'Cast Memorize Scribe Display Rest Exit';
  { DS:055A..0583: storage of AlterMenuText }
  ds055A: array[0..41] of Byte =
    (
      $1F, $4F, $72, $64, $65, $72, $20, $44, $72, $6F, $70, $20, $53, $70, $65, $65,
      $64, $20, $49, $63, $6F, $6E, $20, $50, $69, $63, $73, $20, $45, $78, $69, $74,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00);
  PartyOrderMenuTexts: array[0..1] of string[40] = ('Select Exit', 'Place Exit');
  { The item-usage bit of each class 0..7 (the image: 2, $10, 8, $40, $80, 1, 4, $20 for cleric, druid,
    fighter, paladin, ranger, magic-user, thief, monk): ovl16:056C adds the bit of every class a new
    character has a level in into TCharacter.ClassBits (+$B0), the mask UseBestItem tests an item's
    ClassMask against. }
  ClassItemBits: array[0..7] of Byte = (2, 16, 8, 64, 128, 1, 4, 32);
  { DS:05DE..05EF: storage of ClassTrainingBits }
  Raw05DE: array[0..17] of Byte =
    (
      $02, $02, $08, $0A, $0A, $01, $04, $06, $10, $10, $10, $20, $20, $20, $40, $40,
      $40, $00);
  { DS:05F0..0618: storage of CharacterMenuHotkeys }
  Raw05F0: array[0..40] of Byte =
    (
      $17, $43, $20, $44, $20, $4D, $20, $54, $20, $56, $20, $41, $20, $52, $20, $4C,
      $20, $53, $20, $42, $20, $45, $20, $4A, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00);
  { the training-hall function menu (see TFunctionSlot) }
  CharacterMenuSlots: array[0..10] of TFunctionSlot = (
      (Name: 'Create New Character'; Present: 1),
      (Name: 'Drop Character'; Present: 0),
      (Name: 'Modify Character'; Present: 0),
      (Name: 'Train Character'; Present: 0),
      (Name: 'View Character'; Present: 0),
      (Name: 'Add Character to Party'; Present: 1),
      (Name: 'Remove Character from Party'; Present: 0),
      (Name: 'Load Saved Game'; Present: 1),
      (Name: 'Save Current Game'; Present: 0),
      (Name: 'BEGIN Adventuring'; Present: 0),
      (Name: 'Exit to DOS'; Present: 1));
  ds07E7: Byte = 0;  { the byte between the function menu and the icon editor prompts (never read) }
  { DS:07E8..08B5: storage of IconEditorPrompts }
  ds07E8: array[0..205] of Byte =
    (
      $1F, $50, $61, $72, $74, $73, $20, $63, $6F, $6C, $6F, $72, $2D, $31, $20, $63,
      $6F, $6C, $6F, $72, $2D, $32, $20, $53, $69, $7A, $65, $20, $45, $78, $69, $74,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $10, $48, $65, $61, $64, $20, $57,
      $65, $61, $70, $6F, $6E, $20, $45, $78, $69, $74, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $24, $57, $65, $61, $70, $6F, $6E, $20, $42, $6F, $64, $79, $20, $78,
      $78, $78, $78, $20, $53, $68, $69, $65, $6C, $64, $20, $41, $72, $6D, $20, $4C,
      $65, $67, $20, $45, $78, $69, $74, $00, $00, $00, $00, $0A, $20, $4B, $65, $65,
      $70, $20, $45, $78, $69, $74, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $13, $4E, $65, $78, $74, $20, $50, $72, $65, $76, $20, $4B,
      $65, $65, $70, $20, $45, $78, $69, $74, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00);
  { The hit dice of the eight classes 0..7, rolled by ovl16:4235: ClassHitDiceCount[Class] dice of
    ClassHitDieSides[Class] sides. The image holds 1,1,1,1,2,1,1,2 (cleric, druid, fighter, paladin,
    ranger, magic-user, thief, monk; two dice for the ranger and the monk) and 8,8,10,10,8,4,6,4
    sides. Entry 7 of the sides table is the byte at DS:08C5, entry 0 of the CHEAD suffix table
    below (the image). }
  ClassHitDiceCount: array[0..7] of Byte = (1, 1, 1, 1, 2, 1, 1, 2);  { the number of hit dice of the eight classes }
  { DS:08BE..08C4: storage of ClassHitDieSides }
  ds08BE: array[0..6] of Byte =
    (
      $08, $08, $0A, $0A, $08, $04, $06);
  { The CHEAD/CBODY character-picture name suffix table: the byte FigureSuffixChars[FigureIndex] is the
    character BuildCharacterIcon appends to 'CHEAD'/'CBODY' (index 1 gives 'S', 2 gives 'T'). Its extent is
    unverified: the region runs to the door table at DS:0900. }
  FigureSuffixChars: array[0..$3A] of Char = (
      #4, 'S', 'T', #1, #2, #3, #4, #5, #8, #11, #12, #6, #7, #9, #10, #13, #14, #6, #7, #2, #4, #2, #4, #2, #2,
      #4, #8, #2, #4, #1, #3, #4, #5, #6, #7, #9, #11, #7, #9, #2, #2, #2, #2, #2, #8, #10, #12, #8, #10, #6, #6,
      #6, #6, #6, #8, #10, #8, #10, #8);
  { the first door block codes of AnimateAreaDoors (bit 7 = other bank) }
  DoorBlockCodesFirst: array[0..$A] of Byte = (101, 102, 103, 104, 105, 106, 107, 113, 224, 225, 226);
  { the second door block codes of AnimateAreaDoors (indexed 0..$11); same 7-bit flag }
  DoorBlockCodesSecond: array[0..$11] of Byte = (
      86, 87, 88, 89, 108, 109, 110, 111, 112, 114, 115, 116, 117, 118, 119, 223, 243, 245);
  { the first 16-byte record AnimateAreaDoors passes to RemapPictureColours }
  DoorRemapFrom: array[0..$F] of Byte = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);
  { the second 16-byte record AnimateAreaDoors passes to RemapPictureColours }
  DoorRemapToFirst: array[0..$F] of Byte = (1, 1, 2, 3, 4, 5, 6, 2, 8, 9, 10, 11, 12, 13, 14, 15);
  { the third 16-byte record AnimateAreaDoors passes to RemapPictureColours }
  DoorRemapToSecond: array[0..$F] of Byte = (0, 1, 2, 3, 4, 5, 6, 2, 8, 9, 10, 11, 12, 13, 14, 15);
  { the per-step DrawAreaView columns of AnimateAreaDoors (indexed 0..8) }
  DoorViewColumns: array[0..8] of Word = (17, 17, 17, 19, 19, 19, 23, 23, 23);
  { DS:095F..096F: storage of DoorViewRows }
  Raw095F: array[0..16] of Byte =
    (
      $0F, $00, $0F, $00, $0F, $00, $14, $00, $14, $00, $14, $00, $19, $00, $19, $00,
      $19);
  { DS:0970..0A78: storage of TreasureItemRows }
  ds0970: array[0..264] of Byte =
    (
      $00, $00, $BB, $00, $A7, $00, $40, $00, $01, $00, $20, $03, $03, $00, $03, $00,
      $00, $00, $EF, $00, $A7, $00, $40, $00, $01, $00, $4C, $04, $01, $00, $52, $00,
      $00, $00, $B9, $00, $A7, $00, $40, $00, $01, $00, $90, $01, $01, $00, $55, $00,
      $00, $00, $AD, $00, $A7, $00, $40, $00, $01, $00, $C2, $01, $01, $00, $50, $00,
      $00, $00, $F0, $00, $A7, $00, $41, $00, $01, $00, $34, $08, $38, $00, $38, $00,
      $00, $00, $EE, $00, $A7, $00, $42, $00, $01, $00, $88, $13, $00, $00, $1B, $00,
      $80, $00, $9D, $00, $A7, $00, $45, $00, $01, $00, $70, $17, $14, $00, $33, $00,
      $00, $00, $CE, $00, $A7, $00, $45, $00, $01, $00, $F8, $2A, $1E, $00, $58, $00,
      $00, $00, $E1, $00, $A7, $00, $45, $00, $01, $00, $88, $13, $14, $00, $54, $00,
      $00, $00, $E2, $00, $A7, $00, $64, $00, $0A, $00, $98, $3A, $00, $00, $26, $00,
      $83, $00, $00, $00, $6F, $00, $B6, $00, $01, $00, $10, $27, $05, $00, $51, $00,
      $00, $00, $E4, $00, $A7, $00, $77, $00, $01, $00, $80, $3E, $14, $00, $57, $00,
      $00, $00, $AA, $00, $A7, $00, $58, $00, $19, $00, $5C, $44, $00, $00, $59, $00,
      $85, $00, $9D, $00, $A7, $00, $15, $00, $14, $00, $B8, $0B, $01, $00, $53, $00,
      $00, $00, $F2, $00, $A7, $00, $45, $00, $01, $00, $88, $13, $14, $00, $2F, $00,
      $00, $00, $CD, $00, $A7, $00, $42, $00, $01, $00, $88, $13, $00, $00, $3D, $00,
      $81, $00, $E3, $00, $A7, $00, $42, $00, $01);
  { DS:0A79..0C12: storage of SpellLevelNames }
  ds0A79: array[0..409] of Byte =
    (
      $00, $4C, $1D, $00, $00, $38, $00, $8B, $00, $BA, $00, $A7, $00, $49, $00, $96,
      $00, $A8, $61, $00, $00, $00, $00, $00, $00, $E5, $00, $A7, $00, $58, $00, $19,
      $00, $70, $17, $00, $00, $48, $00, $86, $00, $09, $31, $73, $74, $20, $4C, $65,
      $76, $65, $6C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $09, $32, $6E, $64, $20, $4C, $65, $76, $65, $6C, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $09, $33, $72, $64, $20,
      $4C, $65, $76, $65, $6C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $09, $34, $74, $68, $20, $4C, $65, $76, $65, $6C, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $09, $35, $74,
      $68, $20, $4C, $65, $76, $65, $6C, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $09, $36, $74, $68, $20, $4C, $65, $76, $65, $6C,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $09,
      $37, $74, $68, $20, $4C, $65, $76, $65, $6C, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $09, $38, $74, $68, $20, $4C, $65, $76,
      $65, $6C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $09, $39, $74, $68, $20, $4C, $65, $76, $65, $6C, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00);
  { DS:0C13..0C22: storage of DeathAffects }
  ds0C13: array[0..15] of Byte =
    (
      $00, $07, $0B, $1E, $1F, $20, $33, $34, $35, $36, $3A, $3B, $5F, $62, $89, $4A);
  { The two affects RemoveExtraDeathAffects removes are entries 1..2 at DS:0C24 ($4A $4B); entry 0 is the byte before. }
  ExtraDeathAffects: array[0..2] of Byte = (75, 74, 75);  { entries 1..2 ($4A $4B) are the affects
    RemoveExtraDeathAffects removes }
  { DS:0C26..0C2F: storage of WallViewIdTable }
  Raw0C26: array[0..9] of Byte =
    (
      $00, $0F, $0C, $0B, $0D, $0A, $09, $0E, $00, $0F);
  { entries 1..9 tested; only 3..9 replace the map block }
  SpecialBlocks: array[0..9] of TSpecialBlock = (
      (Col: 2828; Row: 2573; Pic: 3593),
      (Col: 10; Row: 9; Pic: 240),
      (Col: 3; Row: 32; Pic: 2),
      (Col: 12; Row: 31; Pic: 2),
      (Col: 25; Row: 11; Pic: 1),
      (Col: 32; Row: 15; Pic: 165),
      (Col: 33; Row: 23; Pic: 157),
      (Col: 37; Row: 8; Pic: 147),
      (Col: 19; Row: 16; Pic: 247),
      (Col: 25; Row: 27; Pic: 256));
  { 16-byte table LoadSpriteList passes to RemapPictureColours (with SpriteRemapTo) }
  SpriteRemapFrom: array[0..$F] of Byte = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);
  { second 16-byte table LoadSpriteList passes to RemapPictureColours }
  SpriteRemapTo: array[0..$F] of Byte = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 0, 14, 15);
  { The ten pieces a wall of the 3D view is drawn from (DrawWallPiece, DrawWallView): each piece is a
    rectangle of 8x8 tiles, Width x Height, whose tiles follow each other in a wall's 156-byte tile
    list from FirstTile on (the image's values 0,2,6,..,$9A add up to $9C exactly), drawn with its
    top left tile at view column Col, row Row. Indexed by the piece number 0..9. }
  { first tile of each wall piece in the 156-byte tile list; see above }
  WallPieceFirstTile: array[0..9] of Byte = (0, 2, 6, 10, 22, 38, 54, 110, 132, 154);
  WallPieceWidth: array[0..9] of Byte = (1, 1, 1, 3, 2, 2, 7, 2, 2, 1);  { width in tiles of each wall piece; see above }
  { height in tiles of each wall piece; see above }
  WallPieceHeight: array[0..9] of Byte = (2, 4, 4, 4, 8, 8, 8, 11, 11, 2);
  { view column of each wall piece's top left tile; see above }
  WallPieceCol: array[0..9] of Integer = (5, 4, 6, 4, 2, 7, 2, 0, 9, 5);
  { view row of each wall piece's top left tile; see above }
  WallPieceRow: array[0..9] of Integer = (4, 3, 3, 3, 1, 1, 1, 0, 0, 4);
  { Colour maps for RemapPictureColours (16 entries, colour I becomes entry I): PictureRemapFrom is the identity,
    PictureRemap13To8 turns colour 13 into 8 and PictureRemap13To0 turns 13 into 0 (the image). LoadPictureSlot recolours the
    TileSet picture sets from PictureRemapFrom to PictureRemap13To8 and ICON from PictureRemapFrom to PictureRemap13To0. }
  PictureRemapFrom: array[0..15] of Byte = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15);  { identity colour
    map; see above }
  PictureRemap13To8: array[0..15] of Byte = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 8, 14, 15);  { colour 13 to 8;
    see above }
  PictureRemap13To0: array[0..15] of Byte = (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 0, 14, 15);  { colour 13 to 0;
    see above }
  { DS:0D02..0D05: storage of PixelsByColour2Bit }
  Raw0D02: array[0..3] of Byte =
    (
      $00, $55, $AA, $FF);
  { two 4-bit pixels of colour C (C * $11); see above }
  PixelsByColour4Bit: array[0..15] of Byte = (0, 17, 34, 51, 68, 85, 102, 119, 136, 153, 170, 187, 204, 221, 238, 255);
  { DS:0D16..0D18: storage of BreakChars }
  ds0D16: array[0..2] of Byte =
    (
      $02, $70, $00);
  { The ten characters MakeDosFileName removes from a file name are entries 1..10 (DS:0D1A..0D23);
    entry 0 is the byte before them, never read (declared so the index base DS:0D19 names it). }
  { characters not allowed in a file name; see above }
  BadNameChars: array[0..10] of Char = (#140, ' ', '.', '*', ',', '?', '/', '\', ':', ';', '|');
  CoinCopperValues: array[0..4] of LongInt = (1, 10, 100, 200, 1000);
  { 17 string[26] at DS:0D38, 27 bytes apart (the image): Cleric .. Monk (0..7), then Cleric/Fighter,
    Cleric/Fighter/Magic-User, Cleric/Ranger, Cleric/Magic-User, Cleric/Thief, Fighter/Magic-User,
    Fighter/Thief, Fighter/Magic-User/Thief and Magic-User/Thief (8..16), indexed by TCharacter.ClassMask. }
  ClassNames: array[0..16] of string[26] = (
      'Cleric',
      'Druid',
      'Fighter',
      'Paladin',
      'Ranger',
      'Magic-User',
      'Thief',
      'Monk',
      'Cleric/Fighter',
      'Cleric/Fighter/Magic-User',
      'Cleric/Ranger',
      'Cleric/Magic-User',
      'Cleric/Thief',
      'Fighter/Magic-User',
      'Fighter/Thief',
      'Fighter/Magic-User/Thief',
      'Magic-User/Thief');
  RaceNames: array[0..7] of string[9] = (
      'Monster',
      'Dwarf',
      'Elf',
      'Gnome',
      'Half-Elf',
      'Halfling',
      'Half-Orc',
      'Human');
  { Nine string[16] at DS:0F53, 17 bytes apart (the image): Lawful Good .. Chaotic Neutral (0..7) and
    Chaotic Evil (8), indexed by the signed byte at +$A0. }
  AlignmentNames: array[0..8] of string[16] = (
      'Lawful Good',
      'Lawful Neutral',
      'Lawful Evil',
      'Neutral Good',
      'True Neutral',
      'Neutral Evil',
      'Chaotic Good',
      'Chaotic Neutral',
      'Chaotic Evil');
  { The sheet's name tables (ShowCharacterSheet), the images' strings: the sex (+$9E, ShortInt), the race (+$2E),
    the class (+$2F: 0..7 the single classes, 8..16 the multi-class names) and the alignment (+$A0),
    and the status (+$10C). }
  SexNames: array[0..1] of string[6] = ('Male', 'Female');
  { The names of the seven kinds of money, string[10] at DS:0FFA: Copper, Silver, Electrum, Gold,
    Platinum, Gems, Jewelry (the image); the Take menu lists the pool with them (ovl21:0DDF). }
  MoneyKindNames: array[0..6] of string[10] = ('Copper', 'Silver', 'Electrum', 'Gold', 'Platinum', 'Gems', 'Jewelry');
  { DS:1047..10A6: storage of StatusNames }
  ds1047: array[0..95] of Byte =
    (
      $04, $4F, $6B, $61, $79, $00, $00, $00, $00, $00, $00, $00, $00, $08, $41, $6E,
      $69, $6D, $61, $74, $65, $64, $00, $00, $00, $00, $08, $74, $65, $6D, $70, $67,
      $6F, $6E, $65, $00, $00, $00, $00, $07, $52, $75, $6E, $6E, $69, $6E, $67, $00,
      $00, $00, $00, $00, $0B, $55, $6E, $63, $6F, $6E, $73, $63, $69, $6F, $75, $73,
      $00, $05, $44, $79, $69, $6E, $67, $00, $00, $00, $00, $00, $00, $00, $04, $44,
      $65, $61, $64, $00, $00, $00, $00, $00, $00, $00, $00, $06, $53, $74, $6F, $6E);
  { DS:10A7..25A7: storage of ItemNameParts }
  Raw10A7: array[0..5376] of Byte =
    (
      $65, $64, $00, $00, $00, $00, $00, $00, $04, $47, $6F, $6E, $65, $00, $00, $00,
      $00, $00, $00, $00, $00, $0A, $42, $61, $74, $74, $6C, $65, $20, $41, $78, $65,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $08, $48, $61, $6E, $64, $20,
      $41, $78, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $08,
      $42, $61, $72, $64, $69, $63, $68, $65, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $0D, $42, $65, $63, $20, $44, $65, $20, $43, $6F, $72, $62,
      $69, $6E, $00, $00, $00, $00, $00, $00, $00, $0D, $42, $69, $6C, $6C, $2D, $47,
      $75, $69, $73, $61, $72, $6D, $65, $00, $00, $00, $00, $00, $00, $00, $08, $42,
      $6F, $20, $53, $74, $69, $63, $6B, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $04, $43, $6C, $75, $62, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $06, $44, $61, $67, $67, $65, $72, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $04, $44, $61,
      $72, $74, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $08, $46, $61, $75, $63, $68, $61, $72, $64, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $0D, $46, $61, $75, $63, $68, $61, $72, $64,
      $2D, $46, $6F, $72, $6B, $00, $00, $00, $00, $00, $00, $00, $05, $46, $6C, $61,
      $69, $6C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $0D, $4D, $69, $6C, $69, $74, $61, $72, $79, $20, $46, $6F, $72, $6B, $00,
      $00, $00, $00, $00, $00, $00, $06, $47, $6C, $61, $69, $76, $65, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0F, $47, $6C, $61, $69,
      $76, $65, $2D, $47, $75, $69, $73, $61, $72, $6D, $65, $00, $00, $00, $00, $00,
      $08, $47, $75, $69, $73, $61, $72, $6D, $65, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $0F, $47, $75, $69, $73, $61, $72, $6D, $65, $2D, $56,
      $6F, $75, $6C, $67, $65, $00, $00, $00, $00, $00, $07, $48, $61, $6C, $62, $65,
      $72, $64, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0D,
      $4C, $75, $63, $65, $72, $6E, $20, $48, $61, $6D, $6D, $65, $72, $00, $00, $00,
      $00, $00, $00, $00, $06, $48, $61, $6D, $6D, $65, $72, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $4A, $61, $76, $65, $6C, $69,
      $6E, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $08, $4A,
      $6F, $20, $53, $74, $69, $63, $6B, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $04, $4D, $61, $63, $65, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $0C, $4D, $6F, $72, $6E, $69, $6E, $67,
      $20, $53, $74, $61, $72, $00, $00, $00, $00, $00, $00, $00, $00, $08, $50, $61,
      $72, $74, $69, $73, $61, $6E, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $0D, $4D, $69, $6C, $69, $74, $61, $72, $79, $20, $50, $69, $63, $6B,
      $00, $00, $00, $00, $00, $00, $00, $08, $41, $77, $6C, $20, $50, $69, $6B, $65,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $51, $75, $61,
      $72, $72, $65, $6C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $07, $52, $61, $6E, $73, $65, $75, $72, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $08, $53, $63, $69, $6D, $69, $74, $61, $72, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $05, $53, $70, $65, $61,
      $72, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $06, $53, $70, $65, $74, $75, $6D, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $0D, $51, $75, $61, $72, $74, $65, $72, $20, $53, $74,
      $61, $66, $66, $00, $00, $00, $00, $00, $00, $00, $0D, $42, $61, $73, $74, $61,
      $72, $64, $20, $53, $77, $6F, $72, $64, $00, $00, $00, $00, $00, $00, $00, $0B,
      $42, $72, $6F, $61, $64, $20, $53, $77, $6F, $72, $64, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $0A, $4C, $6F, $6E, $67, $20, $53, $77, $6F, $72, $64, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $0B, $53, $68, $6F, $72, $74, $20,
      $53, $77, $6F, $72, $64, $00, $00, $00, $00, $00, $00, $00, $00, $00, $10, $54,
      $77, $6F, $2D, $48, $61, $6E, $64, $65, $64, $20, $53, $77, $6F, $72, $64, $00,
      $00, $00, $00, $07, $54, $72, $69, $64, $65, $6E, $74, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $06, $56, $6F, $75, $6C, $67, $65, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $12, $43, $6F,
      $6D, $70, $6F, $73, $69, $74, $65, $20, $4C, $6F, $6E, $67, $20, $42, $6F, $77,
      $00, $00, $13, $43, $6F, $6D, $70, $6F, $73, $69, $74, $65, $20, $53, $68, $6F,
      $72, $74, $20, $42, $6F, $77, $00, $08, $4C, $6F, $6E, $67, $20, $42, $6F, $77,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $09, $53, $68, $6F,
      $72, $74, $20, $42, $6F, $77, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $0E, $48, $65, $61, $76, $79, $20, $43, $72, $6F, $73, $73, $62, $6F, $77,
      $00, $00, $00, $00, $00, $00, $0E, $4C, $69, $67, $68, $74, $20, $43, $72, $6F,
      $73, $73, $62, $6F, $77, $00, $00, $00, $00, $00, $00, $05, $53, $6C, $69, $6E,
      $67, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $04, $4D, $61, $69, $6C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $05, $41, $72, $6D, $6F, $72, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $4C, $65, $61, $74, $68,
      $65, $72, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06,
      $50, $61, $64, $64, $65, $64, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $07, $53, $74, $75, $64, $64, $65, $64, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $04, $52, $69, $6E, $67, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $05, $53,
      $63, $61, $6C, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $05, $43, $68, $61, $69, $6E, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $06, $53, $70, $6C, $69, $6E, $74, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $42, $61,
      $6E, $64, $65, $64, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $05, $50, $6C, $61, $74, $65, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $06, $53, $68, $69, $65, $6C, $64, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $05, $57, $6F, $6F,
      $64, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $05, $41, $72, $72, $6F, $77, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $06, $50, $6F, $74, $69, $6F, $6E, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $06, $53, $63, $72, $6F, $6C, $6C, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $04, $52, $69, $6E, $67, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03,
      $52, $6F, $64, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $05, $53, $74, $61, $76, $65, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $04, $57, $61, $6E, $64, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $4A,
      $75, $67, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $06, $41, $6D, $75, $6C, $65, $74, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $09, $41, $70, $70, $61, $72, $61, $74,
      $75, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $42, $61,
      $67, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $06, $42, $65, $61, $6B, $65, $72, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $04, $42, $6F, $61, $74, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $04, $42, $6F, $6F,
      $6B, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $05, $42, $6F, $6F, $74, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $04, $42, $6F, $77, $6C, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $42, $72, $61, $63,
      $65, $72, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $07, $42, $72, $61, $7A, $69, $65, $72, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $06, $42, $72, $6F, $6F, $63, $68, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $05, $42, $72, $6F, $6F, $6D,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $05,
      $50, $75, $72, $73, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $06, $43, $61, $6E, $64, $6C, $65, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $43, $61, $72, $70, $65, $74,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $43,
      $65, $6E, $73, $65, $72, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $05, $43, $68, $69, $6D, $65, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $05, $43, $6C, $6F, $61, $6B, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $43, $72,
      $79, $73, $74, $61, $6C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $04, $43, $75, $62, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $05, $43, $75, $62, $69, $63, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $08, $46, $6F, $72,
      $74, $72, $65, $73, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $08, $44, $65, $63, $61, $6E, $74, $65, $72, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $04, $44, $65, $63, $6B, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $05, $44, $72, $75, $6D,
      $73, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $04, $44, $75, $73, $74, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $04, $45, $79, $65, $73, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $08, $46, $69, $67, $75, $72,
      $69, $6E, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $05,
      $46, $6C, $61, $73, $6B, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $09, $47, $61, $75, $6E, $74, $6C, $65, $74, $73, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $47, $65, $6D, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $47,
      $69, $72, $64, $6C, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $04, $48, $65, $6C, $6D, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $04, $48, $6F, $72, $6E, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0A, $48, $6F,
      $72, $73, $65, $73, $68, $6F, $65, $73, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $07, $49, $6E, $63, $65, $6E, $73, $65, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $05, $53, $74, $6F, $6E, $65, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0A, $49, $6E, $73,
      $74, $72, $75, $6D, $65, $6E, $74, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $07, $4A, $61, $76, $65, $6C, $69, $6E, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $05, $4A, $65, $77, $65, $6C, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $08, $4F, $69, $6E, $74,
      $6D, $65, $6E, $74, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $06, $4C, $69, $62, $72, $61, $6D, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $04, $4C, $79, $72, $65, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $4D, $61, $6E, $75, $61,
      $6C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07,
      $4D, $61, $74, $74, $6F, $63, $6B, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $04, $4D, $61, $75, $6C, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $09, $4D, $65, $64, $61, $6C, $6C,
      $69, $6F, $6E, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $4D,
      $69, $72, $72, $6F, $72, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $08, $4E, $65, $63, $6B, $6C, $61, $63, $65, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $03, $4E, $65, $74, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $50, $69,
      $67, $6D, $65, $6E, $74, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $05, $50, $65, $61, $72, $6C, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $07, $50, $65, $72, $69, $61, $70, $74, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0A, $50, $68, $79,
      $6C, $61, $63, $74, $65, $72, $79, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $05, $50, $69, $70, $65, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $04, $48, $6F, $6C, $65, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $05, $54, $6F, $6B, $65,
      $6E, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $04, $52, $6F, $62, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $04, $52, $6F, $70, $65, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $52, $75, $67, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03,
      $53, $61, $77, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $06, $53, $63, $61, $72, $61, $62, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $05, $53, $70, $61, $64, $65, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $53,
      $70, $68, $65, $72, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $08, $54, $61, $6C, $69, $73, $6D, $61,
      $6E, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $04, $54, $6F,
      $6D, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $07, $54, $72, $69, $64, $65, $6E, $74, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $08, $47, $72, $69, $6D, $6F, $69, $72, $65,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $04, $57, $65, $6C,
      $6C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $05, $57, $69, $6E, $67, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $04, $56, $69, $61, $6C, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $4C, $61, $6E, $74,
      $65, $72, $6E, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $03, $4F, $69, $6C, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0B, $31, $30, $20, $66, $74,
      $2E, $20, $50, $6F, $6C, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0B,
      $35, $30, $20, $66, $74, $2E, $20, $52, $6F, $70, $65, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $04, $49, $72, $6F, $6E, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $11, $54, $68, $66, $20, $50, $72,
      $69, $63, $6B, $6C, $79, $20, $54, $6F, $6F, $6C, $73, $00, $00, $00, $0C, $49,
      $72, $6F, $6E, $20, $52, $61, $74, $69, $6F, $6E, $73, $00, $00, $00, $00, $00,
      $00, $00, $00, $10, $53, $74, $61, $6E, $64, $61, $72, $64, $20, $52, $61, $74,
      $69, $6F, $6E, $73, $00, $00, $00, $00, $0B, $48, $6F, $6C, $79, $20, $53, $79,
      $6D, $62, $6F, $6C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0F, $48, $6F,
      $6C, $79, $20, $57, $61, $74, $65, $72, $20, $76, $69, $61, $6C, $00, $00, $00,
      $00, $00, $11, $55, $6E, $68, $6F, $6C, $79, $20, $57, $61, $74, $65, $72, $20,
      $76, $69, $61, $6C, $00, $00, $00, $07, $42, $61, $72, $64, $69, $6E, $67, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $44, $72, $61,
      $67, $6F, $6E, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $09, $4C, $69, $67, $68, $74, $6E, $69, $6E, $67, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $06, $53, $61, $64, $64, $6C, $65, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0A, $53, $6D, $61, $6C,
      $6C, $20, $52, $61, $66, $74, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $04, $43, $61, $72, $74, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $05, $57, $61, $67, $6F, $6E, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $02, $2B, $31, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $02,
      $2B, $32, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $02, $2B, $33, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $02, $2B, $34, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $02, $2B,
      $35, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $02, $6F, $66, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $05, $43, $6C,
      $6F, $61, $6B, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $0C, $44, $69, $73, $70, $6C, $61, $63, $65, $6D, $65, $6E, $74, $00,
      $00, $00, $00, $00, $00, $00, $00, $07, $54, $6F, $72, $63, $68, $65, $73, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $03, $4F, $69, $6C,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $05, $53, $70, $65, $65, $64, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $08, $54, $61, $70, $65, $73, $74, $72, $79, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0D, $42, $6F, $64, $69,
      $6C, $79, $20, $48, $65, $61, $6C, $74, $68, $00, $00, $00, $00, $00, $00, $00,
      $06, $43, $6F, $70, $70, $65, $72, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $06, $53, $69, $6C, $76, $65, $72, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $08, $45, $6C, $65, $63, $74,
      $72, $75, $6D, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $04,
      $47, $6F, $6C, $64, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $08, $50, $6C, $61, $74, $69, $6E, $75, $6D, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $08, $4F, $69, $6E, $74, $6D, $65,
      $6E, $74, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0A, $4B,
      $65, $6F, $67, $68, $74, $75, $6D, $27, $73, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $05, $53, $68, $65, $65, $74, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $08, $53, $74, $72, $65, $6E, $67, $74,
      $68, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $48, $65,
      $61, $6C, $69, $6E, $67, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $07, $48, $6F, $6C, $64, $69, $6E, $67, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $05, $45, $78, $74, $72, $61, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0C, $47, $61, $73,
      $65, $6F, $75, $73, $20, $46, $6F, $72, $6D, $00, $00, $00, $00, $00, $00, $00,
      $00, $0C, $53, $6C, $69, $70, $70, $65, $72, $69, $6E, $65, $73, $73, $00, $00,
      $00, $00, $00, $00, $00, $00, $08, $4A, $65, $77, $65, $6C, $6C, $65, $64, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $46, $6C, $79, $69,
      $6E, $67, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $10, $54, $72, $65, $61, $73, $75, $72, $65, $20, $46, $69, $6E, $64, $69, $6E,
      $67, $00, $00, $00, $00, $04, $46, $65, $61, $72, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0D, $44, $69, $73, $61, $70,
      $70, $65, $61, $72, $61, $6E, $63, $65, $00, $00, $00, $00, $00, $00, $00, $09,
      $53, $74, $61, $74, $75, $65, $74, $74, $65, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $06, $46, $75, $6E, $67, $75, $73, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $05, $43, $68, $61, $69, $6E, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $50,
      $65, $6E, $64, $61, $6E, $74, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $06, $42, $72, $6F, $61, $63, $68, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $0A, $4F, $66, $20, $53, $65, $65, $6B,
      $69, $6E, $67, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $02, $2D, $31,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $02, $2D, $32, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $02, $2D, $33, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0E, $4C, $69, $67,
      $68, $74, $6E, $69, $6E, $67, $20, $42, $6F, $6C, $74, $00, $00, $00, $00, $00,
      $00, $0F, $46, $69, $72, $65, $20, $52, $65, $73, $69, $73, $74, $61, $6E, $63,
      $65, $00, $00, $00, $00, $00, $0E, $4D, $61, $67, $69, $63, $20, $4D, $69, $73,
      $73, $69, $6C, $65, $73, $00, $00, $00, $00, $00, $00, $04, $53, $61, $76, $65,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $0F, $43, $6C, $65, $72, $69, $63, $61, $6C, $20, $53, $63, $72, $6F, $6C, $6C,
      $00, $00, $00, $00, $00, $11, $4D, $61, $67, $69, $63, $20, $55, $73, $65, $72,
      $20, $53, $63, $72, $6F, $6C, $6C, $00, $00, $00, $0C, $57, $69, $74, $68, $20,
      $31, $20, $53, $70, $65, $6C, $6C, $00, $00, $00, $00, $00, $00, $00, $00, $0D,
      $57, $69, $74, $68, $20, $32, $20, $53, $70, $65, $6C, $6C, $73, $00, $00, $00,
      $00, $00, $00, $00, $0D, $57, $69, $74, $68, $20, $33, $20, $53, $70, $65, $6C,
      $6C, $73, $00, $00, $00, $00, $00, $00, $00, $11, $50, $72, $6F, $74, $65, $63,
      $74, $69, $6F, $6E, $20, $53, $63, $72, $6F, $6C, $6C, $00, $00, $00, $07, $4A,
      $65, $77, $65, $6C, $72, $79, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $04, $46, $69, $6E, $65, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $04, $48, $75, $67, $65, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $04, $42, $6F,
      $6E, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $05, $42, $72, $61, $73, $73, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $03, $4B, $65, $79, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $04, $41, $43, $20,
      $32, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $04, $41, $43, $20, $36, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $04, $41, $43, $20, $34, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $04, $41, $43, $20, $33,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $0D, $4F, $66, $20, $50, $72, $6F, $74, $65, $63, $74, $69, $6F, $6E, $00, $00,
      $00, $00, $00, $00, $00, $0C, $50, $61, $72, $61, $6C, $79, $7A, $61, $74, $69,
      $6F, $6E, $00, $00, $00, $00, $00, $00, $00, $00, $0A, $4F, $67, $72, $65, $20,
      $50, $6F, $77, $65, $72, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0C,
      $49, $6E, $76, $69, $73, $69, $62, $69, $6C, $69, $74, $79, $00, $00, $00, $00,
      $00, $00, $00, $00, $08, $4D, $69, $73, $73, $69, $6C, $65, $73, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $09, $45, $6C, $76, $65, $6E, $6B,
      $69, $6E, $64, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $52,
      $6F, $74, $74, $69, $6E, $67, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $07, $43, $6F, $76, $65, $72, $65, $64, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $07, $45, $66, $72, $65, $65, $74, $69,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $42, $6F,
      $74, $74, $6C, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $11, $4D, $69, $73, $73, $69, $6C, $65, $20, $41, $74, $74, $72, $61,
      $63, $74, $6F, $72, $00, $00, $00, $0D, $4F, $66, $20, $4D, $61, $67, $6C, $75,
      $62, $69, $79, $65, $74, $00, $00, $00, $00, $00, $00, $00, $14, $53, $65, $63,
      $72, $20, $44, $6F, $6F, $72, $20, $26, $20, $54, $72, $61, $70, $20, $44, $65,
      $74, $11, $47, $64, $20, $44, $72, $61, $67, $6F, $6E, $20, $43, $6F, $6E, $74,
      $72, $6F, $6C, $00, $00, $00, $0F, $46, $65, $61, $74, $68, $65, $72, $20, $46,
      $61, $6C, $6C, $69, $6E, $67, $00, $00, $00, $00, $00, $0E, $47, $69, $61, $6E,
      $74, $20, $53, $74, $72, $65, $6E, $67, $74, $68, $00, $00, $00, $00, $00, $00,
      $12, $52, $65, $73, $74, $6F, $72, $69, $6E, $67, $20, $4C, $65, $76, $65, $6C,
      $28, $73, $29, $00, $00, $0C, $46, $6C, $61, $6D, $65, $20, $54, $6F, $6E, $67,
      $75, $65, $00, $00, $00, $00, $00, $00, $00, $00, $09, $46, $69, $72, $65, $62,
      $61, $6C, $6C, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $09,
      $53, $70, $69, $72, $69, $74, $75, $61, $6C, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $07, $42, $6F, $75, $6C, $64, $65, $72, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $44, $69, $61, $6D, $6F, $6E,
      $64, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $45,
      $6D, $65, $72, $61, $6C, $64, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $04, $4F, $70, $61, $6C, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $07, $53, $61, $70, $68, $69, $72, $65,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $4F, $66,
      $20, $54, $79, $72, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $09, $4F, $66, $20, $54, $65, $6D, $70, $75, $73, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $07, $4F, $66, $20, $53, $75, $6E, $65, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $57, $6F, $6F,
      $64, $65, $6E, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $0C, $2B, $33, $20, $76, $73, $20, $55, $6E, $64, $65, $61, $64, $00, $00,
      $00, $00, $00, $00, $00, $00, $04, $50, $61, $73, $73, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $06, $43, $75, $72, $73,
      $65, $64, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00);
  { The eight compass names the location line of res12 (00BA:290B) indexes with PartyFacing, each a
    three-byte string[2] at DS:25A8: N, NE, E, SE, S, SW, W, NW (the bytes are in the image). }
  FacingNames: array[0..7] of string[2] = ('N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW');
  { the 3x3 line pattern table StepLine reads at [SY+1, SX+1] }
  LinePatternTable: array[0..2, 0..2] of Byte = ((7, 0, 1), (6, 8, 2), (5, 4, 3));
  { EGA plane masks for DrawGlyph mode 1 (0709:03C0): selected through Port[$3C5] by
    3 - Bit; adjacent to GlyphColorPatterns. }
  EgaPlaneMasks: array[0..3] of Byte = (8, 4, 2, 1);
  { Per-colour words DrawGlyph mode 0 ORs into the pixel accumulator (0709:02A3):
    indexed by the mapped colour 0..3; adjacent to TextColourMap4. }
  GlyphColorPatterns: array[0..3] of Word = (0, 21845, 43690, 65535);
  { Globals of the DOS file and BIOS text layer (res05); evidence in re/dseg.toml where named. }
  { 16 entries, the colours 0..15 mapped to 0..3 (0,0,0,1,2,2,2,3,3,1,1,1,2,2,3,3 in the image);
    WriteCharsAt maps the text colour through it when VideoAdapter is 0 (0802:0086). }
  { four-colour map of the text colours; see above }
  TextColourMap4: array[0..15] of Byte = (0, 0, 0, 1, 2, 2, 2, 3, 3, 1, 1, 1, 2, 2, 3, 3);
  { DS:25E5..25F5: storage of GlyphPixelMasks }
  ds25E5: array[0..16] of Byte =
    (
      $00, $C0, $00, $30, $00, $0C, $00, $03, $C0, $00, $30, $00, $0C, $00, $03, $00,
      $00);
  { Plane bit masks 1, 2, 4, 8 that res07's direct picture blit writes to the Sequencer Map Mask
    (port 3C5h) for plane 0..3 when it copies one byte per plane (0464:1A6E). }
  EgaPlaneBitMasks: array[0..3] of Byte = (1, 2, 4, 8);
  { DS:25FA..2609: storage of PixelBitsByColour }
  Raw25FA: array[0..15] of Byte =
    (
      $00, $00, $00, $00, $40, $10, $04, $01, $80, $20, $08, $02, $C0, $30, $0C, $03);
  { 8-byte structure FillPictureRect copies from @FillRectPalette (DrawWallDescriptors) }
  FillRectPalette: array[0..7] of Byte = (0, 17, 34, 18, 0, 33, 48, 51);
  SoundStopAll: Word = 255;  { word passed to PlaySound by QuitGame and the Ctrl-S pause path; meaning unknown }
  { DS:2614..2617: storage of InsertDiskPrompts }
  ds2614: array[0..3] of Byte =
    (
      $00, $00, $01, $00);
  SoundSpellDefault: Word = 2;  { PlaySound argument of CastChosenSpell for a spell without its own sound }
  SoundMissMessage: Word = 3;  { the sound ShowHitMessage plays when Flag is clear; meaning unknown }
  SoundHitMessage: Word = 4;  { the sound ShowHitMessage plays when Flag is set (a hit); meaning unknown }
  SoundCombatantDies: Word = 5;  { the sound RemoveCombatant plays (PlaySound) when a combatant dies }
  SoundAttackLeaves: Word = 6;  { the sound PlaySound plays as an attack animation leaves the attacker (ovl13:26B0) }
  SoundNoAction: Word = 7;  { word e1 passes to PlaySound when Done is 0; meaning unknown }
  SoundLightningBolt: Word = 8;  { sound passed to PlaySound by CastChosenSpell when spell $33 is cast; meaning unknown }
  SoundAttackMissed: Word = 9;  { word ResolveCombatantAttacks passes to PlaySound when nothing landed (ovl13:1774) }
  SoundStep: Word = 10;  { word the ovl14 movement code passes to PlaySound; meaning unknown }
  { sound passed to PlaySound by CastChosenSpell when spell $2F is cast, and by ovl03:2CCF when ScriptSoundCode is 10;
    meaning unknown }
  SoundFireball: Word = 11;
  { DS:262C..2721: storage of SoundAttackArrives }
  Raw262C: array[0..245] of Byte =
    (
      $0C, $00, $0D, $00, $0E, $00, $17, $49, $6E, $73, $65, $72, $74, $20, $64, $69,
      $73, $6B, $20, $31, $20, $69, $6E, $20, $64, $72, $69, $76, $65, $20, $00, $00,
      $00, $00, $00, $00, $17, $49, $6E, $73, $65, $72, $74, $20, $64, $69, $73, $6B,
      $20, $32, $20, $69, $6E, $20, $64, $72, $69, $76, $65, $20, $00, $00, $00, $00,
      $00, $00, $17, $49, $6E, $73, $65, $72, $74, $20, $64, $69, $73, $6B, $20, $33,
      $20, $69, $6E, $20, $64, $72, $69, $76, $65, $20, $00, $00, $00, $00, $00, $00,
      $17, $49, $6E, $73, $65, $72, $74, $20, $64, $69, $73, $6B, $20, $34, $20, $69,
      $6E, $20, $64, $72, $69, $76, $65, $20, $00, $00, $00, $00, $00, $00, $17, $49,
      $6E, $73, $65, $72, $74, $20, $64, $69, $73, $6B, $20, $35, $20, $69, $6E, $20,
      $64, $72, $69, $76, $65, $20, $00, $00, $00, $00, $00, $00, $17, $49, $6E, $73,
      $65, $72, $74, $20, $64, $69, $73, $6B, $20, $36, $20, $69, $6E, $20, $64, $72,
      $69, $76, $65, $20, $00, $00, $00, $00, $00, $00, $17, $49, $6E, $73, $65, $72,
      $74, $20, $64, $69, $73, $6B, $20, $37, $20, $69, $6E, $20, $64, $72, $69, $76,
      $65, $20, $00, $00, $00, $00, $00, $00, $17, $49, $6E, $73, $65, $72, $74, $20,
      $64, $69, $73, $6B, $20, $38, $20, $69, $6E, $20, $64, $72, $69, $76, $65, $20,
      $00, $00, $00, $00, $00, $00);
  { Five words, one per 8x8 tile bank, subtracted from the symbol number to index within the
    bank (Put8x8Symbol, ovl34:020F); evidence in re/dseg.toml. }
  SymbolBase: array[0..4] of Word = (1, 46, 116, 186, 256);  { per-bank base symbol numbers; see above }
  { DS:272C..2735: storage of WallSymbolFloor }
  Raw272C: array[0..9] of Byte =
    (
      $2D, $00, $73, $00, $B9, $00, $FF, $00, $1E, $01);
  { DirStepX and DirStepY: nine entries each (DirStepY starts 9 bytes after DirStepX). ovl14's
    ClampPartyPosition also adds them as the party's column and row step (cbw at ovl14:06D0, 06DB). }
  DirStepX: array[0..8] of ShortInt = (0, 1, 1, 1, 0, -1, -1, -1, 0);  { the x step per direction; see above }
  { DS:273F..2743: storage of DirStepY }
  ds273F: array[0..4] of Byte =
    (
      $FF, $FF, $00, $01, $01);
  { DS:2744..2744: storage of CombatTiles }
  ds2744: array[0..0] of Byte =
    (
      $01);
  { DS:2745..2843: storage of WalkTileTable }
  Raw2745: array[0..254] of Byte =
    (
      $00, $FF, $00, $FF, $00, $02, $00, $FF, $00, $02, $01, $FF, $00, $02, $02, $FF,
      $00, $02, $03, $01, $00, $00, $04, $FF, $00, $02, $05, $FF, $00, $02, $06, $FF,
      $00, $02, $07, $01, $00, $00, $08, $FF, $00, $02, $09, $01, $00, $00, $0A, $FF,
      $00, $02, $0B, $01, $00, $00, $0C, $FF, $00, $02, $0D, $01, $00, $00, $0E, $FF,
      $00, $02, $0F, $01, $00, $00, $10, $FF, $00, $02, $11, $FF, $00, $02, $12, $FF,
      $00, $02, $13, $FF, $00, $02, $14, $FF, $00, $02, $15, $01, $00, $00, $16, $01,
      $00, $00, $17, $FF, $00, $02, $18, $01, $00, $00, $22, $01, $00, $00, $23, $01,
      $00, $00, $24, $01, $00, $00, $25, $01, $00, $00, $26, $01, $00, $00, $27, $FF,
      $00, $02, $00, $FF, $00, $02, $01, $FF, $00, $02, $02, $FF, $00, $02, $03, $01,
      $00, $00, $04, $01, $00, $00, $05, $01, $00, $00, $06, $01, $00, $00, $07, $FF,
      $00, $00, $08, $FF, $00, $00, $09, $01, $00, $00, $0A, $01, $00, $00, $0B, $01,
      $00, $00, $0C, $01, $00, $00, $0D, $01, $00, $00, $0E, $01, $00, $00, $0F, $01,
      $00, $00, $10, $01, $00, $00, $11, $FF, $00, $00, $12, $FF, $00, $00, $13, $01,
      $00, $00, $14, $01, $00, $00, $15, $01, $00, $00, $16, $FF, $00, $00, $17, $FF,
      $00, $00, $18, $01, $00, $00, $19, $01, $00, $00, $1A, $01, $00, $00, $1B, $FF,
      $00, $00, $1C, $FF, $00, $02, $1D, $FF, $00, $02, $1E, $FF, $00, $02, $1F);
  { DS:2844..286A: storage of Footprints }
  ds2844: array[0..38] of Byte =
    (
      $01, $00, $00, $20, $FF, $00, $02, $21, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF,
      $00, $00, $00, $01, $FF, $FF, $FF, $FF, $00, $00, $01, $00, $FF, $FF, $FF, $FF,
      $00, $00, $01, $00, $00, $01, $01);
  { DS:286B..286E: storage of HelplessAffects }
  ds286B: array[0..3] of Byte =
    (
      $01, $33, $34, $35);
  { the affects that leave a character helpless (IsHelpless tests
                                    entries 1..4 through HasAffect; ovl13:1FC3 compares the same
                                    entries with the 16-byte combat table at DS:3204). Entry 0 (DS:286B)
                                    is never read. }
  { the HEAD picture number per bank (SelectedCharacter^.HeadBank, ShowHeadBodyWindow) }
  HeadPictureNumbers: array[0..13] of Byte = (31, 0, 8, 9, 13, 16, 18, 22, 34, 45, 51, 53, 57, 67);
  { DS:287D..288B: storage of BodyPictureNumbers }
  Raw287D: array[0..14] of Byte =
    (
      $44, $01, $02, $03, $04, $07, $08, $12, $18, $1A, $21, $23, $25, $00, $01);
  { DS:288C..28E8: storage of KeypadScanLetters }
  ds288C: array[0..92] of Byte =
    (
      $4F, $50, $51, $4B, $20, $4D, $47, $48, $49, $48, $48, $48, $48, $48, $48, $48,
      $48, $48, $48, $48, $4B, $48, $48, $48, $48, $48, $48, $48, $48, $48, $4D, $4B,
      $4B, $48, $48, $48, $48, $48, $48, $48, $4D, $4D, $4B, $4B, $4B, $48, $48, $48,
      $48, $48, $4D, $4D, $4D, $4B, $4B, $4B, $4B, $48, $48, $48, $4D, $4D, $4D, $4D,
      $4B, $4B, $4B, $4B, $4B, $48, $4D, $4D, $4D, $4D, $4D, $4B, $4B, $4B, $4B, $50,
      $50, $50, $4D, $4D, $4D, $4D, $4B, $4B, $4B, $50, $50, $50, $50);
  { DS:28E9..290C: storage of SpellNames, SpellNamesPrefix }
  ds28E9: array[0..35] of Byte =
    (
      $50, $4D, $4D, $4D, $4B, $4B, $50, $50, $50, $50, $50, $50, $50, $4D, $4D, $4B,
      $50, $50, $50, $50, $50, $50, $50, $50, $50, $4D, $50, $50, $50, $50, $50, $50,
      $50, $50, $50, $50);
  { DS:290D..31F9: storage of CloudArmDirections }
  Raw290D: array[0..2284] of Byte =
    (
      $50, $08, $02, $03, $04, $05, $42, $6C, $65, $73, $73, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $05, $43,
      $75, $72, $73, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $11, $43, $75, $72, $65, $20, $4C, $69, $67,
      $68, $74, $20, $57, $6F, $75, $6E, $64, $73, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $12, $43, $61, $75, $73, $65, $20, $4C, $69, $67, $68, $74, $20, $57, $6F, $75,
      $6E, $64, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $0C, $44, $65, $74, $65, $63, $74,
      $20, $4D, $61, $67, $69, $63, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $14, $50, $72, $6F, $74, $65, $63, $74, $69, $6F, $6E, $20, $46, $72,
      $6F, $6D, $20, $45, $76, $69, $6C, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $14, $50, $72, $6F, $74,
      $65, $63, $74, $69, $6F, $6E, $20, $66, $72, $6F, $6D, $20, $47, $6F, $6F, $64,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $0B, $52, $65, $73, $69, $73, $74, $20, $43, $6F, $6C, $64,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0D, $42, $75,
      $72, $6E, $69, $6E, $67, $20, $48, $61, $6E, $64, $73, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $0C, $43, $68, $61, $72, $6D, $20, $50, $65, $72,
      $73, $6F, $6E, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0C,
      $44, $65, $74, $65, $63, $74, $20, $4D, $61, $67, $69, $63, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $07, $45, $6E, $6C, $61, $72, $67, $65,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $06, $52, $65, $64, $75, $63, $65, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $07, $46, $72, $69, $65, $6E,
      $64, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $0D, $4D, $61, $67, $69, $63, $20, $4D, $69, $73, $73, $69, $6C,
      $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $14, $50, $72, $6F,
      $74, $65, $63, $74, $69, $6F, $6E, $20, $46, $72, $6F, $6D, $20, $45, $76, $69,
      $6C, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $14, $50, $72, $6F, $74, $65, $63, $74, $69, $6F, $6E,
      $20, $46, $72, $6F, $6D, $20, $47, $6F, $6F, $64, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0A, $52,
      $65, $61, $64, $20, $4D, $61, $67, $69, $63, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $06, $53, $68, $69, $65, $6C, $64, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $0E, $53, $68, $6F, $63, $6B, $69, $6E, $67, $20, $47, $72, $61, $73, $70, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $05, $53, $6C, $65, $65, $70, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $0A, $46, $69, $6E, $64, $20, $54, $72, $61, $70, $73, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0B, $48, $6F, $6C, $64,
      $20, $50, $65, $72, $73, $6F, $6E, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $0B, $52, $65, $73, $69, $73, $74, $20, $46, $69, $72, $65,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $13, $53, $69,
      $6C, $65, $6E, $63, $65, $2C, $20, $31, $35, $27, $20, $52, $61, $64, $69, $75,
      $73, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $0B, $53, $6C, $6F, $77, $20, $50, $6F, $69, $73,
      $6F, $6E, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0B,
      $53, $6E, $61, $6B, $65, $20, $43, $68, $61, $72, $6D, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $10, $53, $70, $69, $72, $69, $74, $75,
      $61, $6C, $20, $48, $61, $6D, $6D, $65, $72, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $13, $44, $65, $74, $65, $63, $74, $20, $49, $6E, $76, $69, $73, $69, $62,
      $69, $6C, $69, $74, $79, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0C, $49, $6E, $76, $69, $73,
      $69, $62, $69, $6C, $69, $74, $79, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $05, $4B, $6E, $6F, $63, $6B, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0C, $4D, $69, $72,
      $72, $6F, $72, $20, $49, $6D, $61, $67, $65, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $13, $52, $61, $79, $20, $6F, $66, $20, $45, $6E, $66,
      $65, $65, $62, $6C, $65, $6D, $65, $6E, $74, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0E, $53,
      $74, $69, $6E, $6B, $69, $6E, $67, $20, $43, $6C, $6F, $75, $64, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $08, $53, $74, $72, $65, $6E, $67, $74, $68,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $0C, $41, $6E, $69, $6D, $61, $74, $65, $20, $44, $65, $61, $64, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $0E, $43, $75, $72, $65, $20, $42,
      $6C, $69, $6E, $64, $6E, $65, $73, $73, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $0F, $43, $61, $75, $73, $65, $20, $42, $6C, $69, $6E, $64, $6E, $65,
      $73, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0C, $43, $75, $72, $65,
      $20, $44, $69, $73, $65, $61, $73, $65, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $0D, $43, $61, $75, $73, $65, $20, $44, $69, $73, $65, $61,
      $73, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0C, $44, $69,
      $73, $70, $65, $6C, $20, $4D, $61, $67, $69, $63, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $06, $50, $72, $61, $79, $65, $72, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0C,
      $52, $65, $6D, $6F, $76, $65, $20, $43, $75, $72, $73, $65, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $0C, $42, $65, $73, $74, $6F, $77, $20,
      $43, $75, $72, $73, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $05, $42, $6C, $69, $6E, $6B, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $0C, $44, $69, $73, $70, $65,
      $6C, $20, $4D, $61, $67, $69, $63, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $08, $46, $69, $72, $65, $62, $61, $6C, $6C, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $05, $48, $61, $73,
      $74, $65, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $0B, $48, $6F, $6C, $64, $20, $50, $65, $72, $73, $6F,
      $6E, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $18, $49,
      $6E, $76, $69, $73, $69, $62, $69, $6C, $69, $74, $79, $2C, $20, $31, $30, $27,
      $20, $52, $61, $64, $69, $75, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $0E, $4C, $69, $67, $68, $74, $6E, $69, $6E,
      $67, $20, $42, $6F, $6C, $74, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $20, $50, $72, $6F, $74, $65, $63, $74, $69, $6F, $6E, $20, $46, $72, $6F, $6D,
      $20, $45, $76, $69, $6C, $2C, $20, $31, $30, $27, $20, $52, $61, $64, $69, $75,
      $73, $00, $00, $00, $00, $00, $00, $00, $00, $20, $50, $72, $6F, $74, $65, $63,
      $74, $69, $6F, $6E, $20, $46, $72, $6F, $6D, $20, $47, $6F, $6F, $64, $2C, $20,
      $31, $30, $27, $20, $52, $61, $64, $69, $75, $73, $00, $00, $00, $00, $00, $00,
      $00, $00, $1F, $50, $72, $6F, $74, $65, $63, $74, $69, $6F, $6E, $20, $46, $72,
      $6F, $6D, $20, $4E, $6F, $72, $6D, $61, $6C, $20, $4D, $69, $73, $73, $69, $6C,
      $65, $73, $00, $00, $00, $00, $00, $00, $00, $00, $00, $04, $53, $6C, $6F, $77,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $0B, $52, $65, $73, $74, $6F, $72, $61, $74, $69, $6F, $6E,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00);
  { DS:31FA..3639: storage of SpellTable }
  ds31FA: array[0..1087] of Byte =
    (
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $01, $06, $00, $06, $00, $0A, $04, $00, $04, $01, $02, $0A, $02, $00, $00,
      $00, $01, $06, $00, $06, $00, $0A, $00, $00, $04, $02, $01, $0A, $03, $01, $00,
      $00, $01, $00, $00, $00, $00, $04, $02, $00, $04, $00, $02, $05, $01, $00, $00,
      $00, $01, $FF, $00, $00, $00, $04, $00, $00, $04, $00, $01, $05, $02, $01, $00,
      $00, $01, $03, $00, $0A, $00, $00, $01, $00, $04, $05, $02, $01, $00, $00, $00,
      $00, $01, $00, $00, $00, $03, $04, $02, $00, $04, $08, $02, $04, $01, $00, $00,
      $00, $01, $00, $00, $00, $03, $04, $02, $00, $04, $09, $02, $04, $02, $00, $00,
      $00, $01, $00, $00, $00, $0A, $04, $02, $00, $04, $0A, $02, $0A, $00, $00, $00,
      $01, $01, $00, $00, $00, $00, $04, $00, $00, $04, $00, $01, $01, $04, $01, $00,
      $01, $01, $0C, $00, $00, $00, $04, $00, $01, $04, $0B, $01, $01, $06, $01, $00,
      $01, $01, $00, $00, $00, $02, $00, $01, $00, $04, $05, $02, $01, $00, $00, $00,
      $01, $01, $00, $02, $00, $0A, $04, $02, $00, $04, $0C, $02, $01, $00, $00, $00,
      $01, $01, $00, $02, $00, $0A, $04, $02, $01, $04, $0D, $02, $01, $00, $01, $00,
      $01, $01, $00, $00, $00, $01, $00, $01, $00, $04, $0E, $00, $01, $00, $00, $00,
      $01, $01, $06, $04, $00, $00, $04, $00, $00, $04, $00, $01, $01, $06, $01, $00,
      $01, $01, $00, $00, $00, $02, $04, $02, $00, $04, $08, $02, $01, $01, $00, $00,
      $01, $01, $00, $00, $00, $02, $04, $02, $00, $04, $09, $02, $01, $02, $00, $00,
      $01, $01, $00, $00, $00, $02, $00, $01, $00, $04, $10, $00, $0A, $00, $00, $00,
      $01, $01, $00, $00, $00, $05, $00, $01, $00, $04, $11, $02, $01, $03, $00, $00,
      $01, $01, $FF, $00, $00, $00, $04, $00, $00, $04, $00, $01, $01, $04, $01, $00,
      $01, $01, $03, $04, $00, $05, $09, $00, $00, $04, $35, $01, $01, $07, $01, $01,
      $00, $02, $00, $00, $1E, $00, $00, $01, $00, $04, $13, $00, $05, $00, $00, $00,
      $00, $02, $06, $00, $04, $01, $06, $00, $01, $04, $34, $01, $05, $07, $01, $00,
      $00, $02, $00, $00, $00, $0A, $04, $02, $00, $04, $14, $02, $05, $02, $00, $00,
      $00, $02, $0C, $00, $00, $02, $1F, $00, $03, $04, $15, $01, $05, $04, $01, $01,
      $00, $02, $00, $00, $00, $3C, $04, $02, $00, $04, $16, $02, $01, $00, $00, $00,
      $00, $02, $03, $00, $00, $00, $F0, $00, $00, $04, $33, $01, $05, $00, $01, $00,
      $00, $02, $03, $00, $00, $01, $00, $01, $00, $04, $17, $02, $05, $01, $00, $00,
      $01, $02, $00, $04, $00, $05, $00, $01, $00, $04, $18, $02, $02, $01, $00, $00,
      $01, $02, $00, $00, $00, $00, $04, $02, $00, $04, $19, $02, $02, $02, $00, $00,
      $01, $02, $00, $00, $00, $00, $00, $00, $00, $04, $00, $00, $01, $00, $00, $00,
      $01, $02, $00, $00, $00, $02, $00, $01, $00, $04, $1C, $02, $02, $03, $00, $00,
      $01, $02, $01, $01, $00, $01, $04, $00, $01, $04, $1D, $01, $02, $02, $01, $00,
      $01, $02, $03, $00, $00, $01, $09, $00, $03, $00, $1E, $01, $02, $07, $01, $01,
      $01, $02, $00, $00, $00, $3C, $00, $02, $00, $04, $26, $00, $0A, $00, $00, $00,
      $00, $03, $01, $00, $00, $00, $F0, $04, $00, $04, $20, $02, $0A, $02, $00, $00,
      $00, $03, $00, $00, $00, $00, $04, $02, $00, $04, $00, $02, $0A, $00, $00, $00,
      $00, $03, $FF, $00, $00, $00, $04, $00, $01, $04, $21, $01, $0A, $03, $01, $00,
      $00, $03, $00, $00, $00, $00, $00, $02, $00, $04, $00, $00, $64, $00, $00, $00,
      $00, $03, $FF, $00, $00, $00, $04, $00, $01, $04, $22, $01, $64, $04, $01, $00,
      $00, $03, $06, $00, $00, $00, $09, $02, $00, $04, $00, $02, $04, $05, $01, $01,
      $00, $03, $00, $00, $00, $01, $00, $01, $00, $04, $31, $02, $06, $06, $00, $00,
      $00, $03, $00, $00, $00, $00, $04, $02, $00, $04, $00, $02, $06, $00, $00, $00,
      $00, $03, $FF, $00, $00, $0A, $04, $00, $01, $04, $24, $01, $06, $04, $01, $00,
      $01, $03, $00, $00, $00, $01, $00, $01, $00, $04, $25, $01, $01, $02, $00, $00,
      $01, $03, $0C, $00, $00, $01, $09, $02, $00, $04, $00, $02, $03, $02, $01, $01,
      $01, $03, $0A, $01, $00, $00, $0B, $00, $02, $04, $00, $01, $03, $07, $01, $03,
      $01, $03, $06, $00, $03, $01, $0A, $04, $00, $04, $27, $02, $03, $03, $00, $00,
      $01, $03, $0C, $00, $00, $02, $07, $00, $01, $04, $34, $01, $03, $06, $01, $00,
      $01, $03, $00, $00, $00, $00, $09, $04, $00, $04, $19, $02, $03, $01, $00, $00,
      $01, $03, $04, $01, $00, $00, $08, $00, $02, $04, $00, $01, $03, $07, $01, $00,
      $01, $03, $00, $00, $00, $02, $04, $02, $00, $04, $2D, $02, $03, $01, $00, $00,
      $01, $03, $00, $00, $00, $02, $04, $02, $00, $04, $2E, $02, $03, $02, $00, $00,
      $01, $03, $00, $00, $00, $0A, $04, $02, $00, $04, $29, $02, $03, $03, $00, $00,
      $01, $03, $09, $01, $03, $01, $0A, $00, $00, $04, $2A, $01, $03, $05, $01, $00,
      $00, $07, $00, $00, $00, $00, $04, $02, $00, $04, $00, $02, $06, $00, $00, $00,
      $02, $06, $00, $00, $00, $00, $00, $01, $00, $04, $27, $02, $00, $03, $00, $00,
      $02, $06, $00, $00, $00, $00, $04, $02, $00, $04, $00, $02, $00, $01, $00, $00,
      $02, $06, $00, $00, $00, $00, $00, $01, $00, $04, $26, $02, $00, $01, $00, $00,
      $02, $06, $04, $04, $00, $00, $04, $00, $02, $04, $00, $01, $00, $07, $01, $00,
      $02, $06, $06, $00, $00, $00, $04, $00, $01, $00, $34, $01, $00, $07, $01, $00,
      $02, $06, $00, $00, $00, $00, $00, $01, $00, $04, $27, $02, $00, $01, $00, $00,
      $02, $06, $00, $00, $00, $00, $07, $04, $00, $04, $47, $02, $00, $02, $00, $00,
      $02, $06, $07, $00, $00, $00, $0B, $00, $02, $04, $00, $01, $00, $07, $01, $03,
      $02, $06, $0C, $00, $00, $00, $04, $00, $00, $04, $00, $01, $00, $06, $01, $00,
      $02, $06, $00, $00, $00, $00, $00, $01, $00, $04, $00, $02, $00, $00, $00, $00,
      $02, $06, $00, $00, $00, $00, $00, $01, $00, $04, $04, $00, $00, $00, $00, $00);
  { Globals of the camp's rest clock, ovl20 (whitepaper 5.22). }
  { The radix of each digit of RestTime (ovl20:02F2): a digit that reaches its radix gives one unit to the next
    digit. Seven words in the image at DS:363A, 10, 10, 6, 24, 30, 12, 256: minutes, tens of minutes, hours,
    days, months, years [I]. }
  ClockRadix: array[0..6] of Word = (10, 10, 6, 24, 30, 12, 256);
  { DS:3648..3C75: storage of AreaMap }
  ds3648: array[0..1581] of Byte =
    (
      $01, $02, $01, $02, $01, $02, $01, $02, $01, $02, $01, $02, $01, $02, $01, $02,
      $01, $02, $01, $02, $01, $02, $01, $02, $01, $02, $01, $28, $9D, $9E, $9B, $9C,
      $35, $65, $31, $9B, $33, $62, $5E, $9D, $35, $36, $9E, $37, $02, $01, $02, $01,
      $02, $01, $05, $06, $08, $06, $08, $09, $02, $01, $02, $01, $02, $01, $02, $05,
      $06, $08, $09, $01, $02, $01, $25, $2D, $2E, $9C, $2D, $30, $62, $63, $64, $32,
      $9C, $35, $36, $44, $4A, $9D, $38, $63, $01, $02, $01, $01, $02, $05, $12, $07,
      $0D, $21, $04, $12, $08, $09, $05, $06, $08, $06, $03, $12, $07, $04, $12, $10,
      $01, $02, $26, $1A, $62, $2F, $62, $62, $36, $5F, $5F, $9B, $37, $5E, $9D, $43,
      $4B, $9B, $9C, $33, $02, $05, $06, $03, $0D, $0F, $0E, $0F, $0C, $0B, $0A, $23,
      $07, $04, $0D, $0E, $0F, $23, $12, $0D, $21, $04, $12, $07, $10, $01, $02, $27,
      $33, $65, $64, $5E, $9B, $9C, $9D, $44, $65, $34, $37, $34, $9C, $9D, $9E, $2D,
      $03, $07, $0D, $0F, $0C, $0B, $22, $0C, $0B, $22, $0B, $1F, $12, $07, $0E, $22,
      $0C, $0B, $0A, $0C, $0B, $21, $04, $12, $07, $10, $01, $02, $28, $38, $65, $34,
      $9D, $9E, $9B, $43, $62, $63, $62, $63, $4C, $9B, $9C, $48, $0E, $0F, $22, $0B,
      $22, $0C, $0B, $22, $24, $24, $1F, $07, $04, $0D, $22, $24, $22, $0C, $0B, $24,
      $22, $24, $21, $04, $12, $11, $02, $29, $9C, $37, $62, $63, $32, $9D, $37, $63,
      $64, $65, $64, $65, $62, $32, $9D, $43, $0C, $0B, $24, $22, $24, $22, $0C, $0B,
      $22, $1F, $07, $04, $12, $0E, $0C, $0B, $24, $22, $24, $22, $0C, $0B, $1F, $07,
      $04, $11, $01, $02, $28, $33, $64, $5E, $9B, $9C, $48, $65, $3A, $62, $3A, $62,
      $63, $4D, $9E, $35, $0B, $24, $22, $24, $0C, $0B, $22, $24, $22, $21, $12, $0E,
      $0F, $22, $24, $22, $0B, $24, $22, $24, $22, $1F, $04, $12, $16, $13, $02, $29,
      $9B, $33, $62, $5E, $9D, $9E, $43, $42, $7B, $3D, $93, $3B, $65, $4B, $44, $63,
      $22, $22, $0C, $0B, $22, $24, $24, $22, $0C, $0B, $C9, $CA, $22, $0C, $0B, $24,
      $22, $0C, $0B, $22, $1F, $12, $07, $11, $01, $02, $01, $02, $27, $9C, $35, $65,
      $32, $44, $42, $93, $92, $FF, $A7, $3C, $64, $4D, $43, $65, $24, $0B, $22, $0C,
      $0B, $22, $0C, $0B, $22, $24, $CB, $CC, $24, $22, $0C, $0B, $24, $20, $1B, $1C,
      $16, $04, $12, $13, $02, $01, $02, $01, $29, $37, $62, $63, $32, $49, $41, $88,
      $93, $A7, $3E, $65, $62, $63, $64, $36, $0B, $22, $24, $24, $22, $24, $22, $22,
      $24, $22, $CD, $CE, $CF, $24, $1F, $1D, $1C, $04, $12, $13, $01, $17, $15, $02,
      $01, $02, $01, $02, $01, $2A, $64, $5E, $9B, $37, $62, $41, $3F, $3E, $62, $63,
      $64, $65, $36, $9C, $24, $0C, $0B, $22, $24, $22, $0C, $0B, $22, $24, $D0, $D1,
      $D2, $1C, $12, $07, $04, $12, $D8, $94, $02, $01, $02, $01, $02, $FB, $02, $01,
      $02, $01, $2A, $36, $2C, $62, $46, $47, $62, $63, $64, $65, $62, $36, $9E, $9B,
      $22, $24, $22, $24, $22, $0B, $22, $24, $22, $1F, $04, $12, $D3, $D4, $EF, $D5,
      $D6, $D7, $79, $7A, $95, $02, $01, $02, $01, $8A, $95, $02, $01, $02, $01, $2B,
      $01, $45, $9B, $9C, $48, $62, $63, $64, $34, $9B, $9C, $9D, $1B, $1B, $1C, $1D,
      $1E, $0C, $0B, $22, $1F, $04, $12, $07, $04, $12, $07, $DA, $D9, $79, $7C, $79,
      $7A, $95, $02, $01, $8A, $91, $7B, $95, $02, $01, $02, $01, $02, $39, $9D, $9E,
      $43, $36, $33, $62, $36, $9D, $9E, $2D, $04, $12, $07, $04, $12, $1D, $1E, $1F,
      $04, $12, $07, $04, $14, $18, $15, $EE, $DB, $DC, $79, $7A, $79, $91, $95, $86,
      $7A, $90, $91, $7B, $95, $02, $01, $02, $40, $9B, $2D, $30, $36, $9E, $44, $64,
      $4C, $9C, $44, $62, $14, $15, $2B, $17, $18, $18, $19, $14, $15, $17, $18, $15,
      $01, $02, $8A, $91, $79, $DD, $E7, $E6, $E5, $7D, $88, $89, $79, $7A, $7B, $91,
      $92, $96, $02, $29, $FC, $2F, $62, $4A, $9B, $9C, $5D, $65, $63, $32, $61, $63,
      $01, $02, $01, $02, $01, $02, $01, $02, $01, $02, $01, $02, $8A, $89, $93, $7B,
      $91, $DE, $E9, $E8, $E4, $01, $7D, $88, $7A, $90, $91, $7B, $92, $93, $95, $02,
      $27, $BA, $64, $4B, $9D, $9E, $9B, $48, $4A, $9B, $43, $64, $02, $01, $02, $01,
      $02, $01, $02, $01, $02, $01, $86, $89, $7B, $91, $92, $93, $79, $DF, $E1, $E2,
      $E3, $6F, $01, $7D, $88, $92, $93, $92, $93, $79, $7B, $95, $02, $B9, $B8, $2E,
      $2D, $4C, $9C, $5D, $4B, $44, $62, $63, $01, $02, $01, $02, $01, $02, $01, $02,
      $01, $02, $86, $88, $91, $7B, $92, $93, $79, $E0, $6D, $72, $66, $70, $02, $01,
      $7D, $91, $92, $93, $91, $7C, $91, $8E, $01, $02, $BB, $B7, $48, $63, $4D, $9D,
      $9E, $61, $64, $65, $02, $01, $02, $01, $02, $01, $52, $5C, $02, $01, $02, $7D,
      $88, $92, $93, $79, $7B, $8F, $76, $68, $67, $71, $01, $02, $8A, $91, $7B, $91,
      $7B, $91, $79, $8D, $02, $01, $29, $B6, $5D, $65, $60, $9B, $9C, $61, $62, $36,
      $01, $02, $01, $02, $01, $02, $53, $4F, $5B, $02, $01, $02, $7D, $88, $91, $7C,
      $8E, $02, $77, $69, $6D, $70, $02, $01, $88, $90, $91, $7B, $93, $7B, $91, $93,
      $95, $02, $99, $C8, $B5, $48, $60, $9D, $9E, $43, $36, $9B, $02, $01, $02, $01,
      $02, $01, $54, $4F, $50, $01, $02, $01, $02, $7D, $7B, $79, $8D, $01, $F6, $6A,
      $6B, $73, $01, $02, $7D, $7A, $7B, $91, $92, $93, $79, $7A, $8C, $01, $9F, $C7,
      $9C, $43, $31, $9B, $44, $4A, $9D, $9E, $01, $02, $01, $02, $01, $02, $55, $4F,
      $5B, $02, $01, $02, $01, $86, $88, $A7, $8C, $02, $8A, $59, $6A, $6B, $74, $01,
      $02, $A6, $91, $7B, $92, $93, $79, $97, $9A, $9A, $9B, $C6, $44, $62, $F2, $4D,
      $61, $60, $9C, $44, $02, $01, $02, $01, $02, $01, $02, $54, $5C, $01, $02, $01,
      $02, $01, $7D, $8C, $02, $8A, $91, $58, $6D, $66, $6D, $74, $01, $7D, $93, $92,
      $93, $79, $7B, $97, $9C, $FA, $9E, $C5, $5D, $F1, $01, $2A, $5D, $31, $9B, $43,
      $01, $02, $01, $02, $01, $02, $01, $53, $4F, $5B, $01, $02, $01, $02, $01, $02,
      $8A, $91, $7B, $91, $59, $6A, $6B, $6D, $75, $01, $A6, $93, $91, $7C, $91, $97,
      $9C, $C2, $C3, $C4, $A4, $01, $02, $01, $F3, $62, $4C, $35, $02, $01, $02, $01,
      $02, $01, $52, $4F, $4F, $50, $02, $01, $02, $01, $02, $86, $7A, $90, $91, $7B,
      $58, $6D, $6A, $6C, $6B, $75, $7D, $88, $7B, $79, $7B, $93, $98, $C5, $A4, $01,
      $01, $02, $8A, $89, $B4, $64, $65, $B2, $01, $02, $01, $02, $01, $02, $55, $4F,
      $51, $02, $01, $02, $01, $02, $01, $02, $7D, $7A, $7B, $91, $92, $59, $6D, $6D,
      $66, $6D, $75, $7D, $88, $A7, $8C, $A6, $92, $C0, $02, $8A, $89, $89, $92, $93,
      $87, $B2, $B3, $4E, $02, $01, $02, $01, $02, $01, $02, $54, $4F, $5B, $02, $01,
      $02, $01, $02, $01, $86, $90, $91, $7B, $92, $93, $5A, $59, $F4, $FD, $6E, $01,
      $7D, $8C, $02, $7D, $93, $BF, $A3, $A1, $A2, $92, $A0, $83, $84, $4E, $4E, $4E,
      $01, $02, $01, $02, $01, $02, $01, $53, $4F, $50, $01, $02, $01, $02, $01, $02,
      $01, $7D, $88, $92, $93, $79, $7B, $7A, $57, $F5, $AE, $AD, $01, $02, $01, $02,
      $A6, $BE, $BD, $EB, $ED, $83, $84, $4E, $4E, $4E, $4E, $4E, $02, $01, $02, $01,
      $02, $01, $02, $54, $51, $01, $02, $01, $02, $01, $02, $01, $02, $01, $7D, $88,
      $92, $7C, $91, $93, $85, $4E, $4E, $4E, $AC, $AA, $A9, $A9, $A8, $BC, $EA, $EC,
      $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $01, $02, $01, $02, $01, $02, $01, $55,
      $56, $02, $01, $02, $01, $02, $AA, $AB, $AD, $AA, $AF, $7E, $7F, $80, $81, $83,
      $84, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E,
      $4E, $4E, $4E, $4E, $02, $01, $02, $01, $02, $01, $02, $01, $02, $01, $02, $01,
      $F9, $B0, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $82, $4E, $4E, $4E, $4E, $4E,
      $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E,
      $01, $02, $01, $FE, $01, $02, $AD, $02, $01, $02, $01, $02, $B0, $4E, $4E, $4E,
      $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E,
      $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $B1, $AD, $B1, $AD,
      $AA, $AF, $4E, $AC, $B1, $AD, $AA, $AF, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E,
      $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E,
      $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E,
      $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E,
      $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E,
      $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E,
      $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E,
      $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E, $4E);
  { the area map: one block code per 3x3-tile block, one more
                                          than the code DrawCellPicture draws; byte 0x4E (the letter N)
                                          where no block is drawn (all of rows 34 and 35 in the
                                          shipped image). Read by DrawAreaView, ovl10 and ovl14. }
  { The base column of the map window page, indexed by AreaViewKind: entries 2..4 hold 0, 13 and
    26 (the pages of the 44-column map grid), entry 1 holds 78; evidence in re/dseg.toml. }
  MapBaseX: array[0..5] of Byte = (78, 78, 0, 13, 26, 0);  { map window page base column per AreaViewKind; see above }
  { DS:3C7C..3CF2: storage of ClassThac0Table }
  ds3C7C: array[0..118] of Byte =
    (
      $28, $28, $28, $28, $2A, $2A, $2A, $2C, $2C, $2C, $2E, $28, $28, $28, $28, $2A,
      $2A, $2A, $2C, $2C, $2C, $2E, $28, $28, $29, $2A, $2B, $2C, $2D, $2E, $2F, $30,
      $31, $28, $28, $29, $2A, $2B, $2C, $2D, $2E, $2F, $30, $31, $28, $28, $29, $2A,
      $2B, $2C, $2D, $2E, $2F, $30, $31, $28, $28, $28, $28, $28, $28, $29, $29, $29,
      $29, $29, $28, $28, $28, $28, $28, $29, $29, $29, $29, $2C, $2C, $28, $28, $28,
      $28, $2A, $2A, $2A, $2C, $2C, $2C, $2E, $02, $20, $08, $40, $80, $01, $04, $10,
      $00, $02, $02, $08, $10, $20, $01, $04, $10, $10, $10, $10, $20, $20, $20, $40,
      $40, $40, $0A, $0F, $0A, $0A, $0B);
  ds3CF3: Byte = 12;  { the byte before ThiefSkillTable; see above }
  { DS:3CF4..3CF4: storage of ThiefSkillTable }
  ds3CF4: array[0..0] of Byte =
    (
      $0B);
  { DS:3CF5..3D3A: storage of FigureColourSlots }
  Raw3CF5: array[0..69] of Byte =
    (
      $0A, $01, $02, $03, $04, $06, $07, $1E, $19, $14, $0F, $0A, $0A, $55, $00, $23,
      $1D, $19, $15, $0F, $0A, $56, $00, $28, $21, $1E, $1B, $14, $0F, $57, $00, $2D,
      $25, $23, $21, $19, $0F, $58, $14, $32, $2A, $28, $28, $1F, $14, $5A, $19, $37,
      $2F, $2D, $2F, $25, $14, $5C, $1E, $3C, $34, $32, $37, $2B, $19, $5E, $23, $41,
      $39, $37, $3E, $31, $19, $60);
  ds3D3B: Byte = 40;  { the byte before ThiefRaceTable; see above }
  { DS:3D3C..3D4D: storage of ThiefRaceTable }
  ds3D3C: array[0..17] of Byte =
    (
      $46, $3E, $3C, $46, $38, $1E, $62, $2D, $00, $0A, $0F, $00, $00, $00, $F6, $FB,
      $05, $FB);
  ds3D4E: Byte = 0;  { the byte before ThiefDexTable; see above }
  { DS:3D4F..3DA2: storage of ThiefDexTable }
  ds3D4F: array[0..83] of Byte =
    (
      $05, $0A, $05, $00, $00, $00, $05, $0A, $05, $05, $0A, $F1, $00, $0A, $00, $00,
      $00, $05, $00, $00, $00, $05, $05, $05, $0A, $0F, $05, $F1, $FB, $FB, $05, $05,
      $00, $00, $05, $05, $F6, $00, $00, $00, $00, $00, $00, $00, $00, $F1, $F6, $F6,
      $EC, $F6, $ED, $FB, $F6, $F1, $FB, $FB, $00, $FB, $F6, $00, $00, $00, $00, $FB,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $FB, $00, $00);
  { DS:3DA3..3E16: storage of RaceAbilityLimits, RaceStrengthMax, RaceStrengthPercent }
  Raw3DA3: array[0..115] of Byte =
    (
      $00, $05, $0A, $00, $05, $05, $0A, $0F, $05, $0A, $0A, $0F, $14, $0A, $0C, $0C,
      $08, $08, $12, $11, $63, $00, $03, $12, $03, $12, $03, $11, $0C, $13, $03, $10,
      $03, $03, $12, $10, $4B, $00, $08, $12, $03, $12, $07, $13, $06, $12, $08, $12,
      $06, $06, $12, $0F, $32, $00, $07, $12, $03, $12, $03, $12, $08, $12, $03, $12,
      $03, $03, $12, $11, $5A, $00, $04, $12, $03, $12, $06, $12, $06, $12, $03, $12,
      $06, $06, $11, $0E, $00, $00, $06, $12, $03, $11, $08, $12, $0A, $13, $03, $12,
      $06, $06, $12, $12, $63, $4B, $03, $11, $03, $0E, $03, $11, $0D, $13, $03, $0C,
      $03, $03, $12, $12);
  { DS:3E17..3E5A: storage of RaceClassChoices }
  Raw3E17: array[0..67] of Byte =
    (
      $64, $32, $03, $12, $03, $12, $03, $12, $03, $12, $03, $12, $03, $02, $06, $0E,
      $00, $00, $00, $00, $00, $00, $00, $00, $07, $02, $05, $06, $0D, $0E, $0F, $10,
      $00, $00, $00, $00, $03, $02, $06, $0E, $00, $00, $00, $00, $00, $00, $00, $00,
      $0B, $00, $02, $05, $06, $08, $09, $0B, $0D, $0E, $0F, $10, $03, $02, $06, $0E,
      $00, $00, $00, $00);
  { DS:3E5B..3F30: storage of StartingAgeTable }
  Raw3E5B: array[0..213] of Byte =
    (
      $00, $00, $00, $00, $06, $00, $02, $06, $08, $0C, $0E, $00, $00, $00, $00, $00,
      $04, $00, $02, $05, $06, $00, $00, $00, $00, $00, $00, $00, $FA, $00, $02, $14,
      $00, $00, $00, $00, $28, $00, $05, $04, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $4B, $00, $03, $06, $8A, $02, $0A, $0A, $00, $00, $00, $00,
      $82, $00, $05, $06, $00, $00, $00, $00, $00, $00, $00, $00, $96, $00, $05, $06,
      $64, $00, $05, $06, $2C, $01, $03, $0C, $00, $00, $00, $00, $3C, $00, $05, $04,
      $00, $00, $00, $00, $00, $00, $00, $00, $64, $00, $02, $0C, $50, $00, $05, $04,
      $28, $00, $02, $04, $00, $00, $00, $00, $16, $00, $03, $04, $00, $00, $00, $00,
      $00, $00, $00, $00, $1E, $00, $02, $08, $16, $00, $03, $08, $00, $00, $00, $00,
      $00, $00, $00, $00, $14, $00, $03, $04, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $28, $00, $02, $04, $14, $00, $01, $04, $00, $00, $00, $00,
      $0D, $00, $01, $04, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $14, $00, $02, $04, $12, $00, $01, $04, $12, $00, $01, $04, $0F, $00, $01, $04,
      $11, $00, $01, $04, $14, $00);
  { The age brackets of each race 1..7 (ovl16:056C): five words per row, the ages above which a character
    counts as a young adult, middle aged, old and venerable (the image's Dwarf row is 50, 150, 250, 350,
    450); the ability scores of a new character are adjusted for every bracket its age is above. Row 0
    is the index base: the image holds the end of StartingAgeTable there. }
  RaceAgeBrackets: array[0..7, 0..4] of Word = (
      (1025, 24, 1026, 18, 1025),
      (50, 150, 250, 350, 450),
      (175, 550, 875, 1200, 1600),
      (90, 300, 450, 600, 750),
      (40, 100, 175, 250, 325),
      (33, 68, 101, 144, 199),
      (15, 30, 45, 60, 80),
      (20, 40, 60, 90, 120));
  { The per-class ability minimums ModifyCharacter clamps to: six columns per class (Strength ..
    Charisma), indexed by [ClassMask, Stat]. }
  ClassAbilityMinimums: array[0..$10, 0..5] of Byte = (
      (6, 6, 9, 0, 0, 0),
      (0, 0, 12, 0, 0, 15),
      (9, 0, 6, 6, 7, 0),
      (13, 9, 12, 0, 9, 17),
      (0, 13, 14, 0, 14, 0),
      (0, 9, 6, 6, 0, 0),
      (6, 6, 0, 9, 0, 0),
      (15, 0, 15, 15, 11, 0),
      (9, 0, 9, 0, 0, 0),
      (9, 9, 9, 0, 0, 0),
      (0, 13, 14, 0, 14, 0),
      (0, 9, 9, 0, 0, 0),
      (0, 0, 9, 9, 0, 0),
      (9, 9, 0, 0, 0, 0),
      (9, 0, 0, 9, 0, 0),
      (9, 9, 0, 9, 0, 0),
      (0, 9, 0, 9, 0, 0));
  { DS:3FE7..408D: storage of ClassAlignmentChoices }
  Raw3FE7: array[0..166] of Byte =
    (
      $09, $00, $01, $02, $03, $04, $05, $06, $07, $08, $05, $01, $03, $04, $05, $07,
      $00, $00, $00, $00, $09, $00, $01, $02, $03, $04, $05, $06, $07, $08, $01, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $09, $00, $01, $02, $03, $04, $05, $06,
      $07, $08, $09, $00, $01, $02, $03, $04, $05, $06, $07, $08, $07, $01, $02, $03,
      $04, $05, $07, $08, $00, $00, $09, $00, $01, $02, $03, $04, $05, $06, $07, $08,
      $09, $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $00, $01, $02, $03, $04,
      $05, $06, $07, $08, $09, $00, $01, $02, $03, $04, $05, $06, $07, $08, $09, $00,
      $01, $02, $03, $04, $05, $06, $07, $08, $09, $00, $01, $02, $03, $04, $05, $06,
      $07, $08, $09, $00, $01, $02, $03, $04, $05, $06, $07, $08, $07, $01, $02, $03,
      $04, $05, $07, $08, $00, $00, $07, $01, $02, $03, $04, $05, $07, $08, $00, $00,
      $07, $01, $02, $03, $04, $05, $07);
  { DS:408E..409A: storage of ConstitutionHitPointTable }
  ds408E: array[0..12] of Byte =
    (
      $08, $00, $00, $FE, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00);
  { DS:409B..40BB: storage of ExperienceTable }
  Raw409B: array[0..32] of Byte =
    (
      $00, $00, $01, $02, $02, $02, $02, $02, $DD, $05, $00, $00, $B9, $0B, $00, $00,
      $71, $17, $00, $00, $C9, $32, $00, $00, $6D, $6B, $00, $00, $FF, $FF, $FF, $FF,
      $FF);
  ds40BC: Byte = 255;  { the byte before ClericSlotTable; see above }
  { DS:40BD..41D3: storage of ClericSlotTable }
  ds40BD: array[0..278] of Byte =
    (
      $FF, $FF, $FF, $FF, $FF, $FF, $02, $00, $00, $02, $01, $00, $03, $02, $00, $03,
      $03, $01, $03, $03, $02, $00, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF,
      $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF,
      $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $D1, $07, $00, $00, $A1, $0F, $00, $00, $41, $1F,
      $00, $00, $51, $46, $00, $00, $B9, $88, $00, $00, $71, $11, $01, $00, $49, $E8,
      $01, $00, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $FF, $FF,
      $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF,
      $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF,
      $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF,
      $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $C5, $09,
      $00, $00, $89, $13, $00, $00, $11, $27, $00, $00, $E5, $57, $00, $00, $41, $9C,
      $00, $00, $FF, $FF, $FF, $FF, $FF);
  ds41D4: Byte = 255;  { the byte before MageSlotTable; see above }
  { DS:41D5..4262: storage of MageSlotTable }
  ds41D5: array[0..141] of Byte =
    (
      $FF, $FF, $FF, $FF, $FF, $FF, $02, $00, $00, $02, $01, $00, $03, $02, $00, $04,
      $02, $01, $04, $02, $02, $00, $00, $00, $00, $00, $00, $00, $00, $00, $E3, $04,
      $00, $00, $C5, $09, $00, $00, $89, $13, $00, $00, $11, $27, $00, $00, $21, $4E,
      $00, $00, $05, $A6, $00, $00, $71, $11, $01, $00, $B1, $AD, $01, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF,
      $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF,
      $FF, $FF, $FF, $FF, $FF, $FF, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00,
      $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00);
  { DS:4263..426D: storage of StartingGoldDice }
  Raw4263: array[0..10] of Byte =
    (
      $03, $06, $03, $06, $05, $04, $05, $04, $05, $04, $02);
  { DS:426E..43DB: storage of SavingThrowTable }
  ds426E: array[0..365] of Byte =
    (
      $04, $02, $06, $05, $04, $0A, $0D, $0E, $10, $0F, $0A, $0D, $0E, $10, $0F, $0A,
      $0D, $0E, $10, $0F, $09, $0C, $0D, $0F, $0E, $09, $0C, $0D, $0F, $0E, $09, $0C,
      $0D, $0F, $0E, $07, $0A, $0B, $0D, $0C, $07, $0A, $0B, $0D, $0C, $07, $0A, $0B,
      $0D, $0C, $0A, $0D, $0E, $10, $0F, $0A, $0D, $0E, $10, $0F, $0A, $0D, $0E, $10,
      $0F, $09, $0C, $0D, $0F, $0E, $09, $0C, $0D, $0F, $0E, $09, $0C, $0D, $0F, $0E,
      $07, $0A, $0B, $0D, $0C, $07, $0A, $0B, $0D, $0C, $07, $0A, $0B, $0D, $0C, $0E,
      $0F, $10, $11, $11, $0E, $0F, $10, $11, $11, $0D, $0E, $0F, $10, $10, $0D, $0E,
      $0F, $10, $10, $0B, $0C, $0D, $0D, $0E, $0B, $0C, $0D, $0D, $0E, $0A, $0B, $0C,
      $0C, $0D, $0A, $0B, $0C, $0C, $0D, $08, $09, $0A, $09, $0B, $0E, $0F, $10, $11,
      $11, $0E, $0F, $10, $11, $11, $0D, $0E, $0F, $10, $10, $0D, $0E, $0F, $10, $10,
      $0B, $0C, $0D, $0D, $0E, $0B, $0C, $0D, $0D, $0E, $0A, $0B, $0C, $0C, $0D, $0A,
      $0B, $0C, $0C, $0D, $08, $09, $0A, $09, $0B, $0E, $0F, $10, $11, $11, $0E, $0F,
      $10, $11, $11, $0D, $0E, $0F, $10, $10, $0D, $0E, $0F, $10, $10, $0B, $0C, $0D,
      $0D, $0E, $0B, $0C, $0D, $0D, $0E, $0A, $0B, $0C, $0C, $0D, $0A, $0B, $0C, $0C,
      $0D, $08, $09, $0A, $09, $0B, $0E, $0D, $0B, $0F, $0C, $0E, $0D, $0B, $0F, $0C,
      $0E, $0D, $0B, $0F, $0C, $0E, $0D, $0B, $0F, $0C, $0E, $0D, $0B, $0F, $0C, $0D,
      $0B, $09, $0D, $0A, $0D, $0B, $09, $0D, $0A, $0D, $0B, $09, $0D, $0A, $0D, $0B,
      $09, $0D, $0A, $0D, $0C, $0E, $10, $0F, $0D, $0C, $0E, $10, $0F, $0D, $0C, $0E,
      $10, $0F, $0D, $0C, $0E, $10, $0F, $0C, $0B, $0C, $0F, $0D, $0C, $0B, $0C, $0F,
      $0D, $0C, $0B, $0C, $0F, $0D, $0C, $0B, $0C, $0F, $0D, $0B, $0A, $0A, $0E, $0B,
      $0D, $0C, $0E, $10, $0F, $0D, $0C, $0E, $10, $0F, $0D, $0C, $0E, $10, $0F, $0D,
      $0C, $0E, $10, $0F, $0C, $0B, $0C, $0F, $0D, $0C, $0B, $0C, $0F, $0D, $0C, $0B,
      $0C, $0F, $0D, $0C, $0B, $0C, $0F, $0D, $0B, $0A, $0A, $0E, $0B, $00);
var
  { The variables of DGROUP, DS:442E..84EF, in the original's order, then the views. }
  { set to 1 by EndCommand (ovl03:0001) and StartEclBlock (ovl03:0BD1): the script run ends; the script run
    loop (ovl03:3171) clears it on entry and on exit }
  ScriptRunEnded: Byte;
  { RunAreaStep (ovl03:31B4) runs its step again while this is set; ECL command 32 (ovl03:0BD1) sets it }
  ScriptBlockStarted: Byte;  { set to 1 by ECL command 32 (ovl03:0BD1) }
  ReselectCharacterPending: Byte;  { when nonzero, the ECL command 0 (ovl03:0001) selects the character at ReselectCharacter }
  AreaRedrawArmed: Byte;  { cleared by ECL command 32 (ovl03:0BD1), set by 33 and 55 (ovl03:0C74) }
  RosterRedrawFlagA: Byte;  { with RosterRedrawFlagB and RosterRedrawFlagC set, ovl03:0C74 redraws the character; set
    elsewhere }
  RosterRedrawFlagB: Byte;  { set by ECL command 55 (ovl03:0C74); meaning unknown }
  RosterRedrawFlagC: Byte;  { set by ECL command 33 (ovl03:0C74); meaning unknown }
  { The members ECL command 11 (ovl03:0450) has added to the party list; it adds none at
    MaxEncounterMembers (63). }
  EncounterMemberCount: Byte;
  ReselectCharacter: PCharacter;  { and clears this flag; what sets the flag is not known }
  { Globals of the battle's aftermath ovl05 (whitepaper 5.20). }
  MonstersLooted: Byte;  { 1 when a defeated monster gave up its money and items (ovl05:0088) }
  PartyFled: Byte;  { 1 when the party fled the battle (a member with Status 3, ovl05:050D) }
  { Scratch of the combat AI (ovl09). }
  AiLastDirection: Byte;
  { the direction the AI chose last; 8 before its first step
                                    (ovl09:0B3C clears it, the 07F2 step reads and sets it) }
  AiStepTurns: Byte;  { counts the turns the AI spent looking for a step (ovl09:07F2) }
  { DS:443E..443F: storage of AiScratch }
  Raw443E: array[0..1] of Byte;
  { Per side (PlacingSide): 4 groups of 6 rows of 11 placement cells, 1 while free (ovl10:1480). }
  PlacementCells: array[0..1, 0..3, 0..5, 0..10] of Byte;
  SideOriginCol: array[0..1] of ShortInt;  { per side: the grid origin column in area map steps (ovl10:1597) }
  SideOriginRow: array[0..1] of ShortInt;  { per side: the grid origin row in area map steps (ovl10:15A4) }
  FirstRingCells: array[0..1] of ShortInt;  { per side: the cells of its first placement ring (ovl10:17DB) }
  SideFacing: array[0..1] of ShortInt;  { per side: the facing 0..3 (ovl10:1A3D) }
  { DS:4658..4659: storage of PlacingSide }
  ds4658: array[0..1] of Byte;
  { DS:465A..465B: storage of CombatBlock }
  ds465A: array[0..1] of Byte;
  { DS:465C..465F: storage of LoaderLoopIndex }
  Raw465C: array[0..3] of Byte;
  LoaderOpenResult: Byte;  { result of OpenGameFile (the file open state) read at ovl11:05A6 }
  { DS:4661..468B: storage of GameDirBackup }
  Raw4661: array[0..42] of Byte;
  LoaderFile: file;  { the untyped file the loader reads the block from (ovl11:05A1..05E5) }
  { DS:470C..470D: storage of StingCheat }
  Raw470C: array[0..1] of Byte;
  FinalPictureBank: Pointer;  { the FINAL picture bank ShowEndingNarrative loads through LoadPicture and draws }
  SavedViewMode: Byte;  { the DS:49F3 value ShowEndingNarrative saves at the start and restores at the end }
  { DS:4713..4715: storage of FinalPictureNumber }
  Raw4713: array[0..2] of Byte;
  { The character whose sheet ShowCharacterSheet draws: a copy of SelectedCharacter taken at its start (ovl19:0051).
    The Sell action (ovl19:1CEE) passes it to FormatItemLine for the item's line (ovl19:1D59); no other routine reads it yet. }
  SheetCharacter: PCharacter;
  { DS:471A..471C: storage of ViewedCharacter }
  ds471A: array[0..2] of Byte;
  { DS:471D..471D: storage of TimedAffectFlags }
  ds471D: array[0..0] of Byte;
  TimedAffectFlagsFrom0: array[0..$47] of Byte;  { the same 72 bytes from index 1; prefer TimedAffectFlags }
  { the heading of each spell level in the spell menu: entries
                                    1..3 are '1st Level', '2nd Level', '3rd Level'; entry 0 is empty }
  SpellMenuList: PMenuLine;  { head of the spell menu list BuildSpellList builds, PickSpellFromMenu frees }
  SpellMenuSpells: array[0..$14] of Byte;  { the spell number (bit 7 = pending) of each menu line, in list order }
  SpellMenuItems: array[0..$30] of PMenuLine;  { for each scribed/learned line, the item (scroll) it came from }
  SpellMenuItemCount: Byte;  { the number of entries SpellMenuItems holds (AddItemSpells, fn_051C) }
  { SpellWorkByteA and SpellWorkByteB: two byte working globals the ovl22 cast handlers share (the original keeps them
    at DS:4844 and DS:4845, between SpellMenuItemCount and NewHeapEnd). Enlarge (CastEnlarge) puts its
    strength (18) and its percentile in them for RaiseStrength; Sleep (CastSleep) its hit-point pool;
    Snake Charm (CastSnakeCharm) a hit-point pool that reaches 0 through it; ovl24_fn_23B6 a value and a
    duration. }
  SpellWorkByteA: Byte;  { a spell handler's first working byte (see the note above) }
  SpellWorkByteB: Byte;  { the second working byte paired with SpellWorkByteA (see the note above) }
  { the offset (0) and segment (1) words of the heap end (res08_init cuts it by $400 paragraphs) }
  { The total weight of the readied items RecalcCombatValues recomputes: it is reset to 0, raised by each
    readied item's Weight times Count, and becomes the floor of the character's CarriedWeight when
    the weight-excluding item (NameNum[1] $BA) is readied (00BA:0F43). }
  ReadiedItemWeight: Word;
  { nonzero after overlay sizing means the overlay manager failed: res08_init
                                    shows 'Overlay error, program abort!' and halts (probably OvrResult) }
  NewHeapEnd: Pointer;  { DS:$4848: HeapEnd cut by $400 paragraphs; assigned to HeapEnd }
  CfgChar: Char;  { the POOL.CFG choice just read (video E/C/T, sound T/P, retry key, F/N) }
  CfgText: Text;
  CfgProbe: File;  { pool.cfg opened untyped (128-byte records) to probe its existence }
  { POOL.CFG opened for reading (lines: video, sound, game dir, save dir, F/N);
                                    overlaps CfgProbeResult..SavedVideoMode in time-shared DGROUP; see res08_init }
  CfgProbeResult: Byte;  { IOResult of probing pool.cfg (Reset); res08_init retries while nonzero }
  FileProbeResult: Word;  { IOResult of the last FileExists file probe (0802:0334) }
  OfferSaveOnHeapError: Boolean;  { when set, HeapErrorHandler offers SaveGame (save and load unit) before quitting }
  CfgFlagF: Byte;  { 1 when POOL.CFG line 5 is 'F', 0 otherwise (meaning of F/N unknown, 2.3) }
  GameVars: ^TGameVars;  { the game variables (see TGameVars) }
  { Second $800-byte word block the loader allocates (ovl11:0044); it zeroes word 830 (ovl11:03F5).
    ovl14 reads words 713, 714 and 725 of it, all within the 1024 words of TGameVars. }
  GameVars2: ^TGameVars;  { second game word block; see above }
  GameVars3: ^TBlock400;  { $400-byte block the loader allocates (ovl11:0054) }
  EclCode: ^TEclCode;  { $1E00-byte block the loader allocates (ovl11:0064) }
  GameSpeed: Byte;  { set to 1 by the loader; a count the ovl18 narratives read }
  { The five entry addresses of the loaded script, read from its header by InitScript
    (ovl07:0260..02B8); coab calls them vm_run_1, SearchLocation, PreCampCheck, CampInterrupted
    and ecl_initial_entryPoint [H]. The wilderness L key starts the script at the second
    (ovl14). }
  EclStepEntry: Word;  { the first script entry address; see above }
  EclSearchEntry: Word;  { the second script entry address (see EclStepEntry); the ovl14 L key copies it to EclPC }
  EclPreCampEntry: Word;  { the third script entry address; see above }
  EclCampInterruptedEntry: Word;  { the fourth script entry address; see above }
  EclInitialEntry: Word;  { the fifth script entry address; see above }
  { DS:49ED..49F2: storage of EclPC }
  ds49ED: array[0..5] of Byte;
  { The view mode: ShowEndingNarrative saves it, sets 7, restores it; VisitTemple sets 1 (ovl04:0D0F);
    5 during combat (ovl31 changes the combat map only then). }
  ViewMode: Byte;  { the view mode; see above }
  SuppressContinuePrompt: Byte;  { cleared by the loader (ovl11:03CB) }
  ShowPortraits: Byte;
  { nonzero: the portraits are shown; the camp's Pics submenu toggles it
                                    (ovl15:1D31, 1DFC); the loader sets it to 1 (ovl11:0392) }
  ShowMonsterPics: Byte;
  DebugMode: Boolean;  { STING debug mode: switched by Ctrl-D in ReadGameKey; ShowDebugTrace shows only when set }
  { nonzero: the monster pictures are shown; the camp's Pics submenu toggles it
                                    (ovl15:1D02, 1DE9); the loader sets it to 1 (ovl11:0397) }
  SkipAreaScriptLoad: Byte;  { cleared by the loader (ovl11:03A6) }
  { the view kind before the last area step: RunAreaStep (ovl03:31B4) copies AreaViewKind here before it sets 1 }
  PreviousAreaViewKind: Byte;  { set to 1 by the loader (ovl11:03EB) }
  AreaViewKind: Byte;
  RestInterruptCounter: Word;
  ShownHeadBank: Byte;  { the HEAD bank ShowHeadBody last loaded (ovl07:051C) }
  ShownBodyBank: Byte;  { the BODY bank ShowHeadBody last loaded (ovl07:0522) }
  { rest steps since the last interruption check: ovl20:0C9A counts them and
                                    resets it at the GameVars2 word VarRestInterruptSteps; the loader clears it
                                    (ovl11:03AD) }
  PartyDestroyed: Byte;  { 1 when no player-run member is left (SettleBattleOutcome); loader clears it }
  { DS:4A00..4A01: storage of WaitAfterTextRun }
  Raw4A00: array[0..1] of Byte;
  Regs: Registers;  { registers for Intr calls (QuitGame) }
  ActivePageSegment: Word;  { EGA display page segment SetActivePage selects (Page shl 9 + $A000) }
  FillPageSegment: Word;  { EGA display page segment SetPageSegment stores for FillPlaneRect }
  { The second display page WriteCharsAt writes to when VideoAdapter is 1 (BH of INT 10h);
    res08_init sets it to 0 for EGA and passes it to SetPageSegment. }
  FillTextPage: Byte;  { display page; see above }
  { The display page WriteCharsAt writes to first (BH of INT 10h, 0802:0048); res08_init sets it
    to 0 for EGA and passes it to SetActivePage. }
  TextPage: Byte;  { display page; see above }
  SavedVideoMode: Byte;  { video mode QuitGame passes to INT 10h; no writer is in the decompiled units }
  PreviousVideoMode: Byte;  { copy of SavedVideoMode taken in res08_init; reader unknown }
  { DS:4A1E..4A1F: storage of VideoAdapter }
  ds4A1E: array[0..1] of Byte;
  { the video mode read by ClearWindow (03F1:0137) and res06: 0 fills
                                    the text-scanline banks, 1 draws through FillPlaneRect on the EGA
                                    display pages, 2 fills the four graphics banks; POOL.CFG 'E'
                                    selects 1 (whitepaper 2.3) }
  DrawBuf: Pointer;  { far pointer DrawCellPicture passes to DrawPictureItem; what it points at is unknown }
  ScreenSaveBuffer: Pointer;  { screen buffer the loader allocates through AllocatePicture (ovl11:00D4) }
  RowDirtyFlags: array[0..$A7] of Byte;  { $A8-byte buffer the loader clears (ovl11:00EC) }
  { The changed-region trackers the blitters (res07 08D4/0D71/2632) fill and res07
    FlushPictureChanges (1B52) flushes: per changed screen row, RowFirstChangedOfs holds the
    first (lowest) changed byte offset in the staging buffer DrawBuf (a minimum, so
    it starts at $FFFF) and RowLastChangedOfs the last (highest, it starts at 0); RowFirstChangedCol holds
    the screen-side byte column of that first changed byte (LeftCol * 2 on adapter
    0, LeftCol * 1 on adapter 1, LeftCol * 4 on adapter 2). FlushPictureChanges
    moves DrawBuf^.Data[RowFirstChangedOfs[Row] .. RowLastChangedOfs[Row]] to the screen at that column.
    Indexed by word (row*2), so 168 word entries. The loader clears/fills the same
    $150 bytes through FillChar (ovl11:00FD, 010E, 011F). }
  RowFirstChangedCol: array[0..$A7] of Word;  { screen-side byte column of the row's first changed byte }
  RowFirstChangedOfs: array[0..$A7] of Word;  { first (lowest) changed byte offset in DrawBuf (a minimum, starts $FFFF) }
  RowLastChangedOfs: array[0..$A7] of Word;  { last (highest) changed byte offset in DrawBuf (starts 0) }
  { Per-cell screen address table the loader fills (ovl11:0130..0163): $B800 (even cell) or $BA00
    (odd cell) plus 5*(I div 2). }
  CellTextSegments: array[0..$C7] of Word;  { cell text scanline address; see above }
  CellRowOffsets: array[0..$C7] of Word;  { per-cell row offset table the loader fills (ovl11:0186): I*40 }
  { Per-cell plane address table the loader fills (ovl11:019F..0241): 10*(I div 4) plus $B800,
    $BA00, $BC00 or $BE00. }
  CellPlaneSegments: array[0..$C7] of Word;  { cell graphics plane address; see above }
  { DS:5370..5371: storage of ClipChecksEnabled }
  Raw5370: array[0..1] of Byte;
  SoundMode: Byte;  { sound setting; 2 while a Ctrl-S pause is in effect (ReadGameKey) }
  SoundModeBeforePause: Byte;  { SoundMode saved by a Ctrl-S pause; copied back only when it is 0 or 1 }
  SoundDriverIdle: Word;  { nonzero: sound timer driver stopped between sounds (RES03); ovl11:045D clears it }
  { The 8x8 tile world of ovl34 (whitepaper 4.x): which 8X8D file to take the bank from, the five
    loaded banks, the staging buffer tiles are copied through, the buffer DrawPictureItem draws
    into, and a word ShowPicture takes. Evidence in re/dseg.toml. }
  TileSet: Byte;  { the 8X8D file number: Load8x8Bank loads 8x8d<TileSet> }
  SavedTileSet: Byte;  { TileSet saved by SelectTileSet; the loader also sets it to 1 }
  UnreadWord5378: Word;  { set to 1 by the loader (ovl11:03E0) }
  SaveDir: string;  { POOL.CFG line 4: the save directory with trailing backslash (2.3) }
  UnreadWord547A: Word;  { set to 1 by the loader (ovl11:03DA) }
  { DS:547C..547C: storage of GameDir }
  ds547C: array[0..0] of Byte;
  { DS:547D..557B: storage of DiskDriveLetter }
  Raw547D: array[0..254] of Byte;
  { set to 1 while LoadMonster reads the MON*.DAX affect and item lists and to 0 after
    (ovl17:107B, 1252); cleared by the loader (ovl11:0438) }
  OpenNoPrompt: Byte;
  { True ends HeapErrorHandler's retry loop: it is read after SaveGame runs (ovl00:0075),
    and who sets it is not shown until ovl17 is decompiled. }
  HeapErrorStop: Boolean;  { heap error retry gate; see above }
  PackedBuf: Pointer;  { the packed bytes of the DAX block LoadDaxBlock is reading }
  { The ITEMS type table (whitepaper 4.3): 129 sixteen-byte rows, one per item type, indexed by an item's
    ItemType (ScoreItem, UseBestItem, AiTurn and UseMagicItem read them). The loader (ovl11:05CD) reads the
    file's record 2 into this block, which is its buffer at load time. The row count ($810 div 16) is from
    the file size. }
  ItemTable: array[0..128] of TItemRow;
  { The selected character: the Temple acts on it (ovl04 reads it everywhere), ShowHeadBodyWindow
    shows its HEAD and BODY pictures (ovl28:04F9); the loader sets it nil (ovl11:03B8). }
  SelectedCharacter: PCharacter;  { see above }
  PartyListHead: LongInt;  { head of the TCodeRec list ovl14 walks (see below) }
  { DS:5D9A..5E1D: storage of LootListBoundary }
  Raw5D9A: array[0..131] of Byte;
  { Kept LongInt, not Pointer: the loader clears it with `PartyListHead := 0` (ovl11:03B0),
      which is Error 26 for a Pointer (proven by a make tpc probe); ovl14 reaches the
      records through Pointer(PartyListHead). }
  LoaderReadCount: Word;  { BlockRead result count of the loader (ovl11:05D6) }
  GameFont: ^TBlock588;  { $588-byte block the loader allocates (ovl11:0074) }
  GlyphCol: Byte;  { 0768's current glyph column: reset to Left on clear/newline, Inc per glyph }
  { DS:5E25..5E39: storage of GlyphRow }
  ds5E25: array[0..20] of Byte;
  TileBanks: array[0..4] of PT8x8Bank;  { the loaded 8x8 banks, indexed by bank; nil when the load failed }
  TileBuf: PT8x8Bank;  { the tile staging buffer: Put8x8Symbol Moves one tile to +$17 }
  SqrPaciBank1: PT8x8Bank;  { SQRPACI bank 1 (ovl11:04D6); DrawCellPicture source (PicCode <= 127) }
  SqrPaciBank2: PT8x8Bank;  { SQRPACI bank 2 (ovl11:04F8); DrawCellPicture source (bit 7 set) }
  { DS:5E5A..5F19: storage of PictureSlots }
  Raw5E5A: array[0..191] of Byte;
  { DS:5F1A..5F26: storage of DyingPicture }
  ds5F1A: array[0..12] of Byte;
  CombatantTable: array[0..72] of TMapEntry;
  { the combatants on the combat map; entry 0's Kind is the count
                                    (72 entries fit before CombatantViewCol) }
  CombatantViewCol: array[1..72] of ShortInt;  { each combatant's column on the 7x7 view (X - ViewX, ovl31) }
  CombatantViewRow: array[1..72] of ShortInt;  { each combatant's row on the view (Y - ViewY, ovl31) }
  CellOccupant: array[0..24, 0..49] of Byte;  { the combatant standing on each map cell, 0 for none (RebuildOccupancy) }
  { The character record of each combatant (ovl31); MoveCharacter attacks CombatantRecord[n] for
    the number ProbeStep returns (ovl08:0BF8). }
  CombatantRecord: array[1..72] of PCharacter;  { see above }
  BodyTable: array[1..8] of TBody;  { the bodies left on the combat map (RemoveCombatant) }
  BodyCount: Byte;  { the number of bodies in BodyTable }
  { DS:6716..6717: storage of CombatMap }
  ds6716: array[0..1] of Byte;
  { DS:6718..67F3: storage of SortEntries }
  Raw6718: array[0..219] of Byte;
  PooledMoney: TPartyMoney;  { the Temple clears it on entry (ovl04:0D32) and passes it to MoneyValueInGold }
  PooledItems: PMenuLine;  { head of the shop's item list, a far pointer the loader clears (ovl11:031A) }
  PartySideCount: Byte;  { zero (or EnemySideCount zero) ends the combat (ovl08:009B, 095C); likely the count of one side }
  EnemySideCount: Byte;  { see PartySideCount; likely the count of the other side }
  { Globals of the affect and roll unit ovl24. }
  SaveRoll: Byte;  { the saving throw roll: d20 plus SaveBonus and the bonus (ovl24:0D73) }
  HookAffectId: Byte;  { the affect ApplyAffect offers to the hooks; 0 afterwards: unaffected (ovl24:1672) }
  DamageAmount: Byte;  { the damage DealDamage offers to the hooks and then deals (ovl24:134E) }
  DamageKind: Byte;  { the kind of damage: 1 fire, 2 cold, 4 electricity, $10 acid, bit 3 magic (ovl24:13E4) }
  { The round's Movement in half squares ComputeMovement computes for a combatant (it stores it
    before the movement affect hooks and reads it back); StartCombatantRound also seeds it from Who^.PadA2.
    ovl12:0C4B shifts it left by 1 every time it runs and ovl12:10C1 shifts it right by 1 [?]. }
  HookedMoveOrAttacks: Byte;
  { The spell currently being cast: ApplySpellToTargets reads its SpellTable row byte +2 to decide whether
    the spell needs a roll to hit. DS:681B. ovl12:064E also clears DamageAmount when this byte is $0F;
    ovl12:2556 cancels the damage hook then too; ovl12:09C0 (ImageAbsorbsHit) needs it above 0. }
  CastingSpell: Byte;
  LastDiceCount: Byte;  { the dice count of the last RollDiceCounted roll (ovl24:0E37) }
  { Set while ComputeMovement runs the movement affect hooks and cleared around them; what reads
    it is not known yet (ovl12:1452 (StopMovement) clears HookedMoveOrAttacks while it is not 0). }
  HookRunning: Boolean;
  { Cleared before and tested after RunAffectHooks kinds 1 (on the target) and 0 (on the attacker)
    around an attack's target check (ovl13:1085); a hook that sets it rejects the attack. ovl12:0918 and
    ovl12:0C26 also set it to 1 (turn pending). }
  HookVetoFlag: Byte;
  RemovingAffects: Byte;  { 1 while the Temple removes affects (RemoveAffect; ovl04:0386, 05AB, 07CE), 0 after }
  { A flag the spell code shares: ApplySpellToSide sets it to 1 and CastChosenSpell and SelectSpellTargets clear it;
    SelectSpellTargets sets it to 1 once it has filled the target list SpellTargets from a spell's area scan
    (ovl13:2205), never cleared by ovl13; ovl12:09C0 (ImageAbsorbsHit) lets an image take a hit only while
    this byte is 0. It is touched by ovl04, ovl05, ovl06, ovl18, ovl19 and ovl21. The meaning is not
    settled. DS:6820. }
  SpellAppliedToArea: Byte;
  { Set to 1 by InitSpellHandlers (ovl22:3435) at start-up, next byte after SpellAppliedToArea, and by ovl12:2F57 when
    it adds a strength affect; nonzero: the Items window is drawn even if its flag is clear (ovl19:1194). DS:6821. }
  RedrawItemWindow: Byte;
  { DS:6822..6822: storage of AttackSlotRolls, AttackRoll }
  ds6822: array[0..0] of Byte;
  { DS:6823..6824: storage of AvoidedAttackCounter }
  Raw6823: array[0..1] of Byte;
  MoraleScratch: Byte;  { AI morale scratch (CheckMorale computes it from B84, compares percentages) }
  { DS:6826..6827: storage of AttackTarget, HandlerCombatant }
  Raw6826: array[0..1] of Byte;
  { DS:6828..6829: storage of AffectHandlers }
  ds6828: array[0..1] of Byte;
  { DS:682A..6987: storage of SaveKind }
  ds682A: array[0..349] of Byte;
  { DS:6988..6A57: storage of MonsterBreathVector }
  Raw6988: array[0..207] of Byte;
  WallTiles: ^TWallTiles;  { the wall tiles, $924 bytes the loader allocates (ovl11:0084) }
  GeoBlock: ^TBlock400;  { $400-byte block the loader allocates (ovl11:0094) }
  { what to draw: 1 the 3D wall view, 2..4 the map window page (evidence in re/dseg.toml);
                                    1 also makes ECL command 36 (ovl03:179B) set the view mode to 4 instead of 3 }
  WallDescriptor1: Byte;  { wall view descriptor 1 (of 4): SetWallDescriptors sets them }
  WallDescriptor2: Byte;  { wall view descriptor 2: ShowAreaView fills it from SpecialViewCode1 when SpecialViewGate is set }
  WallDescriptor3: Byte;  { wall view descriptor 3: ShowAreaView fills it from SpecialViewCode1 when SpecialViewGate is set }
  { DS:6A63..6AAB: storage of WallDescriptor4 }
  Raw6A63: array[0..72] of Byte;
  { Nonzero: the view shows the overhead wall map (DrawWallMap) instead of the 3D walls and their
    frame (DrawWallView, ovl29:0603). The A key of the movement loop toggles it while
    GameVars^[VarShowWallOverlays] is 0 (ovl14:0380); ShowAreaView (when that variable is set),
    ShowEncounterPicture and StartGame clear it. }
  WallMapMode: Byte;  { overhead wall map shown instead of the 3D view; see above }
  PartyMapColumn: ShortInt;  { the party's column in the 16x16 area map (GEO) }
  { ShortInt, not Byte: ovl14 widens it with cbw (ovl14:0696); EventByteAt/DrawWallView take it. }
  PartyMapRow: ShortInt;  { the party's row in the 16x16 area map }
  { ShortInt, not Byte: ovl14 widens it with cbw (ovl14:069D); EventByteAt/DrawWallView take it; set to 1 by StartGame. }
  { PartyFacing is the party's eight-way direction code: the wilderness keys H, M, P and K set
    0, 2, 4 and 6 (HandleWildernessKeys); WriteVmWord maps script values 0..3 to those values. The
    combat builder indexes direction steps with it and halves it for the four facing icons
    (ovl10:0673, 0876..0879). The same values select DrawIcon's marker icon set. }
  PartyFacing: Byte;  { see above }
  PartyCellWallId: Byte;  { WallIdAt's result for the party cell and icon set (MoveParty); meaning unknown }
  PartyCellEventByte: Byte;  { the event byte of the party's map cell, from EventByteAt; bit 7 = interior }
  { the 4-byte element table shares its base with PartyMapRow at
                                    DS:6AAE; the loader sets entries 2 and 3 to $FFFF (ovl11:035E..0390) }
  UnreadWord6AB2: Word;  { cleared by the loader (ovl11:0353) }
  UnreadWord6AB4: Word;  { set to 1 by the loader (ovl11:0358) }
  ds6AB6: array[0..7] of Byte;
  { DS:6ABE..6AFA: storage of PictureAnimation }
  ds6ABE: array[0..60] of Byte;
  { DS:6AFB..6AFF: storage of LoadSlots }
  Raw6AFB: array[0..4] of Byte;
  HeadBankIndex: Byte;  { the bank index of the HEAD sprite in DS:6B01; $FF when none (LoadHeadBodySprites) }
  HeadSpriteBank: Pointer;  { the loaded HEAD sprite bank (ShowHeadBodySprites, LoadHeadBodySprites) }
  BodyBankIndex: Byte;  { the bank index of the BODY sprite in DS:6B06; $FF when none (LoadHeadBodySprites) }
  BodySpriteBank: Pointer;  { the loaded BODY sprite bank (ShowHeadBodySprites, LoadHeadBodySprites) }
  { DS:6B0A..6B1B: storage of LastSpriteFile }
  Raw6B0A: array[0..17] of Byte;
  { DS:6B1C..6B28: storage of LastSpriteBank }
  Raw6B1C: array[0..12] of Byte;
  ListMenuTop: Integer;  { the list menu's first shown line (ChooseFromList); 1 after the loader (ovl11:0405) }
  PromptWordChoice: Byte;  { the highlighted word of the prompt line, 1-based (ReadPromptChoice) }
  { DS:6B2C..6B2D: storage of LastPromptExtKey }
  ds6B2C: array[0..1] of Byte;
  PromptTimeout: Longint;  { prompt timeout in GameClock hundredths; 0 waits forever (ReadPromptChoice) }
  { DS:6B32..6B7F: storage of PromptTimeoutKey }
  ds6B32: array[0..77] of Byte;
  { The current item the ovl22 spell lists work on (PickSpellFromMenu, fn_044E, fn_051C); UseItem (ovl19:1AB3) also
    stores the scroll it takes its spell from here, when IsScroll accepts the item (main named it CurrentItem
    for that store; the ovl22 routines use it as their working item). }
  CurrentItem: PItem;
  { DS:6B84..6C90: storage of SpellHandlers, SpellTargetPicker, SpellPickerPointer }
  Raw6B84: array[0..268] of Byte;
  { DS:6C91..6C93: storage of SpellTargets }
  Raw6C91: array[0..2] of Byte;
  { The number of chosen targets: the target pickers set it to 1 for a single target and higher for an area
    spell (SelectSpellTargets, ChooseSpellTargets); ApplySpellToTargets loops 1..SpellTargetCount. DS:6C94. }
  SpellTargetCount: Byte;
  { DS:6C95..6DB4: storage of FirstSpellTarget }
  Raw6C95: array[0..287] of Byte;
  PickedSpellCharacter: PCharacter;  { set to nil when the camp opens and closes and before casting (ovl15:04B0, 1FB6) }
  { Globals of the combat unit ovl08 (whitepaper 5.5). }
  { The combat cell a spell being cast is aimed at (X here, Y in SpellAimY): FindSpellTarget writes the chosen
    target's cell together with the target (ovl13:207C/2086), SelectSpellTargets fills it from CombatantX of the
    selected character, and CastChosenSpell uses it as a line endpoint of the cast animation and as part of
    the point to face (InDirArc). ShortInt: the Stinking Cloud handler adds a signed DirStepX to it (cwde at
    ovl22:1C53). DS:6DB9. }
  SpellAimX: ShortInt;
  { The Y of the cell a spell being cast is aimed at, the companion of DS:6DB9; see its comment. DS:6DBA. }
  SpellAimY: ShortInt;
  { Globals of the combat unit ovl08 (whitepaper 5.5). }
  { The list of clouds (TCombatNode, the Stinking Cloud markers): EndCombat frees them (ovl08:0006); ovl12:0CC3. }
  CloudList: PCombatNode;
  { True while the Use action (UseItem, ovl19:1BC2..1BE2) casts a spell through CastChosenSpell, and set
    (ovl19:1AE7) for an item whose Affects[2] gives the spell (not a scroll); what CastChosenSpell does
    with it is not known yet. 0 in the spell setup paths (ovl22:3413 clears it); when set,
    SpellCasterLevel (00BA:26C2) returns a fixed level 6, and SpellAreaSize (ovl22:0729) multiplies its
    per-level byte by 6 instead of the caster level (ovl22:072F, ovl19:1B1E). }
  ItemAffectUse: Boolean;
  { DS:6DC0..6DC1: storage of MoneyInPool }
  ds6DC0: array[0..1] of Byte;
  { DS:6DC2..6DCE: storage of RestTime }
  ds6DC2: array[0..12] of Byte;
  { DS:6DCF..6DD7: storage of RestStudyCountdowns }
  ds6DCF: array[0..8] of Byte;
  RestHealCounter: Word;
  { DS:6DDA..6DDB: storage of RestWindowActive }
  ds6DDA: array[0..1] of Byte;
  { DS:6DDC..6DDD: storage of MarkerFrame }
  ds6DDC: array[0..1] of Byte;
  { DS:6DDE..6DDE: storage of DoorMenuFlags }
  Raw6DDE: array[0..0] of Byte;
  PickMenuFlag: Byte;  { pick/knock menu flag (e1 offers Pick/Knock while nonzero) }
  { DS:6DE0..6DE1: storage of KnockMenuFlag }
  Raw6DE0: array[0..1] of Byte;
  AllyAttackConfirmed: Byte;  { set to 1 when the player confirms attacking an ally (ovl13:2998) }
  CombatRound: Byte;  { counted up once per combat round (ovl08:0891) }
  { DS:6DE4..6E2B: storage of CombatantScanList }
  Raw6DE4: array[0..71] of Byte;
  { One counter per attack slot (1 and 2) of the attacks ovl13:1406 has made while resolving a
    combatant's turn; entry 0 at DS:6E2C is the array base, never read. }
  AttackSlotCounts: array[0..2] of Byte;
  SecondMoraleByte: Byte;  { byte CheckMorale copies into MoraleScratch; meaning unknown }
  MagicToggleOn: Boolean;  { the Alt-M Magic On/Off toggle of the combat keys (ovl08:04A7) }
  { DS:6E31..6E35: storage of PromptKeyFlag }
  Raw6E31: array[0..4] of Byte;
  { DS:6E36..6F67: storage of CombatPicture }
  Raw6E36: array[0..305] of Byte;
  { special view code 2: StartGame sets $DB (ovl11:0435, inside StartGame); InitScript sets $41 and SpecialViewGate }
  SpecialViewCode2: Byte;
  { special view code 1: StartGame sets $E8; InitScript sets 9 and SpecialViewGate }
  SpecialViewCode1: Byte;
  ScriptWordFB: Word;  { returned for script address $FB (ReadVmWord, ovl07:0EC3); meaning unknown }
  ScriptWordFC: Word;  { returned for script address $FC (ReadVmWord, ovl07:0ED0); meaning unknown }
  ScriptWordB1: Word;  { returned for script address $B1 (ReadVmWord, ovl07:0EB6); meaning unknown }
  ReturnStack: PReturnEntry;  { the top of the script's return stack (ScriptGosub); InitScript empties it }
  ReturnPrev: PReturnEntry;  { the previous top while ScriptGosub pushes; InitScript clears it }
  { The results of the script's last comparison (CompareStrings, CompareWords): 1 in [0] when
    equal, [1] unequal, [2] less, [3] greater, [4] less or equal, [5] greater or equal, else 0. }
  CompareFlags: array[0..5] of Byte;
  { the opcode that was current before the last one the script run loop (ovl03:3171) read; no other reader yet }
  PreviousOpcode: Byte;
  { DS:6F7F..6F80: storage of SkippedOpcode }
  ds6F7F: array[0..1] of Byte;
  { The encounter picture's banks: operand 1 and operand 3 of ECL command 12 (ovl03:03B4), passed to
    ShowEncounterPicture as SpriteBank (SPRIT) and PicBank (PIC, or HEAD and BODY). }
  EncounterSpriteBank: Byte;  { the SPRIT bank the encounter sprites are loaded from (ovl07:054E) }
  EncounterPicBank: Byte;  { the PIC bank, or the HEAD and BODY bank, of the close-up (ovl07:054E) }
  { DS:6F83..6FC7: storage of EncounterIconSlot }
  Raw6F83: array[0..68] of Byte;
  { DS:6FC8..7004: storage of EclStrings }
  ds6FC8: array[0..60] of Byte;
  { DS:7005..7044: storage of OperandType }
  ds7005: array[0..63] of Byte;
  { DS:7045..7084: storage of OperandHigh }
  ds7045: array[0..63] of Byte;
  OperandLow: array[0..64] of Byte;  { the low byte, or the length of a packed string }
  PickerDone: Byte;  { cleared by InitScript (ovl07:01FB); meaning unknown }
  { DS:70C7..84C7: storage of SharedLoopIndex }
  Raw70C7: array[0..5120] of Byte;
  { DS:84C8..84CB: storage of PictureShownFlags }
  Raw84C8: array[0..3] of Byte;
  ScriptSoundCode: Word;  { set by a script write to address $3DE (WriteVmWord, ovl07:0D3B); meaning unknown }
  ScriptWordB8: Word;  { set by a script write to address $B8 (WriteVmWord, ovl07:0D48); meaning unknown }
  ScriptWordB9: Word;  { set by a script write to address $B9 (WriteVmWord, ovl07:0D55); meaning unknown }
  CharWord6C00Zeroed: Byte;  { set to 1 when the script writes 0 to the character word $6C00 (ovl07:0B99) }
  CharWord6B00Zeroed: Byte;  { set to 1 when the script writes 0 to the character word $6B00 (ovl07:0A91) }
  { DoPick clears it. Overlaps DoorMenuFlags[1]; exact sharing uncertain. }
  DuelMode: Byte;  { nonzero during a duel (EndBattle's duel texts); the loader clears it (ovl11:040B) }
  NoExperienceCount: Byte;  { members that get no share of the battle's experience (ovl05:05EA) }
  BattleExperience: LongInt;  { the experience each character receives for the battle (ovl05:060B) }
  { DS:84DA..84DB: storage of BattleWon }
  ds84DA: array[0..1] of Byte;
  WallViewMode: Byte;  { the wall view / outdoor mode EventByteAt tests (0 and $A both skip) }
  { The low bit of GameVars2 word 714, saved by the wilderness loop (ovl03:32F8) while that word is
    forced to 1. The loader clears it (ovl11:0415). }
  SavedWord714Low: Byte;
  { cleared by the loader (ovl11:041A) and by EndCommand (ovl03:0001); set by ECL command 61
    (ovl03:2B14); while it is set, DrawGlyphRunCommand (ovl03:2E7D) starts a glyph run below row 13 at
    column 2, row 5; the rest is unknown }
  GlyphRunInBox: Byte;
  { cleared by the loader (ovl11:041F) and, when set, by ECL command 51 (NewLineCommand, ovl03:2AEB); set by
    DrawGlyphRunCommand (ovl03:2E7D) before it draws a run; meaning unknown }
  GlyphRunPending: Byte;
  { CloseUpShown: set while a close-up picture is up (ShowEncounterPicture, ShowCloseUpCommand ovl03:0856). }
  CloseUpShown: Byte;  { close-up picture up; cleared by the loader (ovl11:0424) }
  { CloseUpHidden is set to 1 when ShowCloseUpCommand (ovl03:0856) hides the close-up. }
  CloseUpHidden: Byte;  { cleared by ShowHeadBody (ovl07:0514); meaning unknown }
  { set by DrawGlyphRunCommand (ovl03:2E7D) when it moves a glyph run to the picture window; EndCommand
    (ovl03:0001) redraws the picture frame while it is set }
  PictureFrameDirty: Byte;  { cleared by InitScript (ovl07:01C1) }
  { Sprite3DLoaded: set when ShowEncounterPicture loads the 3D sprite; ShowCloseUpCommand (ovl03:0856) clears it. }
  Sprite3DLoaded: Byte;  { 3D encounter sprite loaded; cleared by the loader (ovl11:0433) }
  WindowClearOnce: Byte;  { window-clear once flag: HandleWildernessKeys clears the text window and sets it }
  SpecialViewGate: Byte;  { special view gate: ShowAreaView uses SpecialViewCode2/SpecialViewCode1 only while it is nonzero }
  PartyMovedByScript: Byte;  { set to 1 when the script moves the party or changes its marker (ovl07:0D6C..0DD6) }
  { set to 1 by ECL command 11 (ovl03:0450) after it has added members to the party list; meaning unknown }
  EncounterMembersAdded: Byte;
  HeadBodyWritten: Byte;  { set to 1 when the script writes game variable $49FD or $49FE (ovl07:0CAF) }
  { SkipCloseUpIfNoPics: EncounterActionCommand (ovl03:1EF8) sets it so ShowEncounterPicture skips the
    close-up unless monster pictures are on. The loader clears it (ovl11:0456). }
  SkipCloseUpIfNoPics: Byte;  { skip the close-up unless monster pictures are on }
  { DS:84EA..84EF: storage of LastShownPictureWord }
  Raw84EA: array[0..5] of Byte;
  { The 13 code wheel records of the copy protection (whitepaper 5.12): the answer, the rune
    indices and the path pattern. CheckCodeWheel picks one at random. }
  CodeWheelRecords: array[0..12] of TCodeWheelEntry absolute Raw0002;  { the code wheel records; see above }
  { Globals of the Temple (ovl04). }
  { The Heal menu texts, string[40] entries 1..10 at DS:011A (Cure Blindness ... Stone to Flesh,
    Exit) copied into the menu lines (ovl04:0A33, I from 1 to 10 at ovl04:0A0C..0A54). Entry 0
    (DS:00F1) is never read: the index base is entry 0 so that TempleMenuText[I] names the same
    address; its bytes are the tail of the previous data. Entry 10 (DS:028B) holds length 4
    'Exit'. }
  TempleMenuText: array[0..10] of string[40] absolute ds00F1;  { see above }
  { The six affects Cure Disease looks for and removes (entries 1..6 at DS:0114: $1F, $22, $2B,
    $2C, $32, $39 in the image; ovl04:031E, 03A6). Entry 0, the byte before, is never read. }
  DiseaseAffects: array[0..6] of Byte absolute ds0113;  { see above }
  { Combat AI step patterns (ovl09): row Combat+$15 (RollDice(1, 2) in ovl09:08CD), column the
    attempt 0..4; the byte is added to the base direction mod 8 before ProbeStep (ovl09:068B..06C2).
    Rows of 5 from DS:02AE up to FacingWallDirs (DS:02D2) give 7 rows; row 0 is all zero [I]. }
  StepTurnOffsets: array[0..6, 0..4] of Byte absolute ds02AE;
  { The column span (Lo..Hi) of each of the 6 rows of a placement shape: shapes 0..3 per facing,
    4 for group 1 (ovl10:1B38). }
  PlacementShapes: array[0..4, 0..5] of TColSpan absolute ds0306;
  { Five 16-byte names at DS:0332 (rows 0 to 4; row 0 is the index base and is never read). The rows 1 to 4
    are the names the affect handler at ovl12:0679 compares with the attacked character's name; their text
    is not read yet [?]. }
  FourListedNames: array[0..4] of string[15] absolute Raw0332;
  { Eight 16-byte names at DS:0402 (rows 1 to 8), directly after EightListedNamesA: the names the affect handler at ovl12:11F9
    compares with the attacked character's name. Their text is not read yet [?]. }
  EightListedNamesB: array[1..8] of string[15] absolute Raw0402;
  { The Turn Undead table (ovl13:122F): a row per undead type (TCharacter +$76) and a column per
    cleric level band (0..9, the code passes 1..10 with bounds checks off); a positive entry turns
    the undead, a nonpositive one destroys it, and the d20 turning check must reach the entry's
    absolute value. The image holds the rows from DS:0447; the menu string after it begins at
    DS:04B6. }
  TurnUndeadTable: array[0..10, 0..9] of Byte absolute Raw0447;
  AlterMenuText: string[40] absolute ds055A;  { 'Order Drop Speed Icon Pics Exit': the camp Alter menu (ovl15:1C86) }
  { One bit per class 0..7 (the value is added to a class-bit mask): ovl16:29AE builds the character's
    class bits from the classes with a level above 0 (DS:05DE[ClassLevels]) and the bits it may train. }
  ClassTrainingBits: array[0..7] of Byte absolute Raw05DE;
  { The 'C D M T V A R L S B E J' hotkey line: the prompt RunCharacterMenu (ovl16:0161) passes to
    ReadPromptChoice under the title 'Choose a function '. }
  CharacterMenuHotkeys: string[23] absolute Raw05F0;
  { The five prompt lines of the character-icon editor EditCharacterIcon (ovl16:382D), 1-based, indexed by
    its State: the image holds 'Parts color-1 color-2 Size Exit', 'Head Weapon Exit',
    'Weapon Body xxxx Shield Arm Leg Exit', ' Keep Exit' and 'Next Prev Keep Exit' (DS:07E8, stride 41).
    The editor rewrites the 'xxxx' of line 3 (column 13) to 'Hair' or 'Face'. }
  IconEditorPrompts: array[1..5] of string[40] absolute ds07E8;
  ClassHitDieSides: array[0..7] of Byte absolute ds08BE;  { the sides of each class's hit die }
  DoorViewRows: array[0..8] of Word absolute Raw095F;  { the per-step DrawAreaView rows of AnimateAreaDoors (indexed 0..8) }
  { The value of the five coins in copper pieces: copper 1, silver 10, electrum 100, gold 200,
    platinum 1000 (the image); MoneyValueInGold values money with it and divides by the gold entry. }
  { Rows of eight words describing the fixed treasure items BuildTreasureItem builds (DS:0970): a row starts at
    the index BuildTreasureItem picks (1, 9, $11, ... $91, and $90 once) and holds the three name numbers,
    the weight, the value and three affect numbers (ovl21:182F..18C2; the image). }
  TreasureItemRows: array[0..$98] of Word absolute ds0970;
  { The spell lists of the CastSpell overlay (ovl22, whitepaper 5.22): BuildSpellList builds one and
    PickSpellFromMenu runs the picker over it. }
  SpellLevelNames: array[0..3] of string[40] absolute ds0A79;
  { The sixteen affects RemoveDeathAffects removes are entries 1..16 at DS:0C14 ($07 $0B $1E $1F $20
    $33 $34 $35 $36 $3A $3B $5F $62 $89 $4A $4B in the image); entry 0 is the byte before. }
  DeathAffects: array[0..16] of Byte absolute ds0C13;  { affects removed when a combatant dies; see above }
  { The wall view's id table: two equal groups of eight ids (0,15,12,11,13,10,9,14). ShowAreaView
    indexes it with the game variables VarWallIndexOutside and VarWallIndexInside. Its last six
    bytes are also entry 0 of SpecialBlocks, which DrawAreaView never reads. }
  WallViewIdTable: array[0..15] of Byte absolute Raw0C26;  { wall view id table, two equal groups of 8; see above }
  { Fill bytes of FillPictureRect (the image: 00 55 AA FF then 00 11 .. BB at PixelsByColour4Bit..). PixelsByColour2Bit[C] is
    the byte of four 2-bit pixels of colour C (C 0..3); PixelsByColour4Bit[C] the byte of two 4-bit pixels of
    colour C (C * $11). The two tables overlap: PixelsByColour2Bit[C + 4] is PixelsByColour4Bit[C]. }
  PixelsByColour2Bit: array[0..15] of Byte absolute Raw0D02;  { four 2-bit pixels of colour C; see above }
  { Characters 0768's word scanner tests (0709:0822..08F0): the leading run is skipped,
    the word run stops at them or space, the trailing run is skipped. Storage descriptor
    $0404 in the three 0D12 calls: 4 bytes at bit offset 32 (set of #32..#63, proven by a
    make tpc probe). Storage overlaps BadNameChars entry 0 at $D19 by one byte. No writer
    exists anywhere in the image; the initial bytes are 70 00 8C 20 (members $, %, &, 2,
    3, 7, =). Runtime meaning of those members: open. }
  BreakChars: set of #32..#63 absolute ds0D16;
  { The names of the nine character status values that DrawCharacterPanel shows as the status line:
    string[12] at DS:1047, 13 bytes apart (the image: 0 Okay, 1 Animated, 2 tempgone, 3 Running,
    4 Unconscious, 5 Dying, 6 Dead, 7 Stoned, 8 Gone), indexed by TCharacter.Status. }
  StatusNames: array[0..8] of string[12] absolute ds1047;
  { The item name parts FormatItemLine appends to a menu line: 256 strings of at most 20
    characters (21 bytes each) at DS:10A7 (the image: entry 1 'Battle Axe' through entry 255
    'Cursed'; entry 0 overlaps the tail of the preceding status string and is never used).
    Indexed by TMenuLine.NameNum. }
  ItemNameParts: array[0..255] of string[20] absolute Raw10A7;
  { Per-column words DrawGlyph mode 0 ANDs with the colour word (0709:02B0):
    indexed by the bit column 0..7. }
  GlyphPixelMasks: array[0..7] of Word absolute ds25E5;
  { Per palette colour C (0..15) and pixel position K (0..3): the byte UnpackPicturePixels ORs
    into a picture byte for VideoAdapter 0. For C 0..3 it is C's 2-bit value in pixel K's bit pair
    (C = 1, K = 0 gives $40); the entries for C 4..15 do not follow that pattern (image bytes
    from DS:25FA: 00 00 00 00 40 10 04 01 80 20 08 02 C0 30 0C 03 00 11 22 12 ...). }
  PixelBitsByColour: array[0..15, 0..3] of Byte absolute Raw25FA;
  { Globals of the loader (StartGame, src/OVL11.PAS); the address in each comment is the write or
    read that shows it. }
  { Table of 30-byte entries indexed by TileSet: entries 1..8 hold 'Insert disk N in drive ' in the
    image (entry 0 is not a string). With the drive letter DS:547D and ':' appended it is the prompt
    OpenGameFile shows while a file is missing (OpenDaxFile 0802:061A, StartGame ovl11:0564). }
  InsertDiskPrompts: array[0..9] of string[29] absolute ds2614;  { the insert-disk prompts; see above }
  SoundAttackArrives: Word absolute Raw262C;  { the sound PlaySound plays as an attack animation reaches the target
    (ovl13:26B0) }
  WallSymbolFloor: Word absolute Raw272C;  { LoadWallSet adds the
    bank's symbol offset to the wall tile numbers at or above it }
  DirStepY: array[0..8] of ShortInt absolute ds273F;  { the y step per direction; see above }
  { The combat tile table; overlaps WalkTileTable (one byte on). Cost is also the movement cost:
    MoveCharacter refuses ("Blocked") a step whose cost is above the moves left (ovl08:0C5F). }
  CombatTiles: array[0..255] of TCombatTile absolute ds2744;  { see above }
  WalkTileTable: array[0..255] of TTileEntry absolute Raw2745;  { the tile table WalkLine reads; see above }
  Footprints: array[0..4, 0..3] of TFootCell absolute ds2844;  { the cells of footprint kinds 1..4 (kind 0 unused) }
  HelplessAffects: array[0..4] of Byte absolute ds286B;
  { the BODY picture number per bank (SelectedCharacter^.BodyBank, ShowHeadBodyWindow) }
  BodyPictureNumbers: array[0..13] of Byte absolute Raw287D;
  { 'OPQK MGHI': the scan code letter of keypad digits 1..9 (ReadPromptChoice) }
  KeypadScanLetters: array[0..8] of Char absolute ds288C;
  { The spell names, string[40] per spell 1..$38 at DS:2912 ('Bless' .. 'Restoration' in the image,
    the rows of SpellTable); entry 0 is the index base (ovl15:10EE), never read. }
  SpellNames: array[0..$38] of string[40] absolute ds28E9;
  { The DS:28E9 bytes before SpellNames[1] (DS:2912) seen as a record: the Stinking Cloud handler
    (ovl22:1B11) reads AimDirs (DS:290E) from it. }
  SpellNamesPrefix: TSpellNamesPrefix absolute SpellNames;
  { rest steps since the last whole-party heal: ovl20:0871 counts to
                                    RestHealCheckInterval (288 steps, 24 hours) then heals and resets it;
                                    MakeCamp clears it when the camp opens (ovl15:1E80) }
  { The direction of each cloud arm 1..4 (ovl12:0CC3): DirStepX[CloudArmDirections[Arm]] and
    DirStepY[CloudArmDirections[Arm]] give the
    arm's step from the centre. The values are not read yet [?]. }
  CloudArmDirections: array[0..4] of Byte absolute Raw290D;
  { Class tables of ovl23 (whitepaper 5.6). Their extents are not known (only the rows the
    characters reach are read). A table whose columns count from 1 is addressed from the byte
    before it ([row, column] is base - 1 + row * width + column), so that byte is declared just
    before the table: it is never read, and declaring it makes the index base name it in our
    layout as in the original (as BadNameChars does). }
  { The spell table: one 16-byte row per spell 1..$38 at DS:320A. Entry 0 (DS:31FA) is never
    read: it is declared so that the index base, which RecalcClassStats adds (ovl23:0103), names it. }
  SpellTable: array[0..$38] of TSpellEntry absolute ds31FA;  { see above }
  AreaMap: array[0..35, 0..43] of Byte absolute ds3648;
  { the to-hit value per class 0..7 and level (RecalcClassStats) }
  ClassThac0Table: array[0..7, 0..10] of Byte absolute ds3C7C;
  ThiefSkillTable: array[0..8, 1..8] of Byte absolute ds3CF4;  { the eight thief skills per thief level }
  { The colour-slot table BuildCharacterIcon reads to build the character icon's colour map: FigureColourSlots[I] for
    I 1..6 holds 1, 2, 3, 4, 6, 7 (the destination colour of the I-th of the six colour pairs, and
    plus 8 for the high nibble). It sits inside the ThiefSkillTable region (DS:3CF4). }
  FigureColourSlots: array[0..$F] of Byte absolute Raw3CF5;
  ThiefRaceTable: array[0..7, 1..8] of ShortInt absolute ds3D3C;  { the race adjustment of the eight thief skills }
  { the dexterity adjustment of the first five thief skills }
  ThiefDexTable: array[0..18, 1..5] of ShortInt absolute ds3D4F;
  { The per-race ability limits ModifyCharacter (ovl16:209F) and ovl16:056C clamp to: a 16-byte row
    per race, a minimum and maximum column per ability (RaceAbilityLimits, indexed by [Race, B9E] or
    [Race, column]). Columns +0/+2/+4 hold the Strength minimum, maximum and exceptional percentile
    maximum (RaceStrengthMax and RaceStrengthPercent are the same rows viewed two and four columns
    on), columns +6/+7 .. +14/+15 the minimum and maximum of Intelligence, Wisdom, Dexterity,
    Constitution and Charisma. }
  RaceAbilityLimits: array[0..$F, 0..$F] of Byte absolute Raw3DA3;
  RaceStrengthMax: array[0..$F, -2..$D] of Byte absolute RaceAbilityLimits;
  RaceStrengthPercent: array[0..$F, -4..$B] of Byte absolute RaceAbilityLimits;
  { The classes each race may pick when a character is created (ovl16:056C): a 12-byte row per race 1..7
    (Dwarf .. Human, RaceNames order), the count of choices first and then the ClassMask numbers (0..7
    the single classes, 8..16 the multi-classes) in menu order. The image's Dwarf row is 3, 2, 6, 14
    (fighter, thief, fighter/thief) and its Human row 4, 0, 2, 5, 6. Row 0 is the index base; the image
    holds the tail of the Human row of RaceAbilityLimits there. }
  RaceClassChoices: array[0..7, 0..11] of ShortInt absolute Raw3E17;
  { The starting ages (ovl16:056C): a 28-byte row per race 1..7 of seven TAgeEntry, one per single class 0..6
    (the image's Dwarf cleric is 250 + 2d20, its fighter 40 + 5d4). Row 0 is the index base: it lies over
    the Half-Orc and Human rows of RaceClassChoices in the image. }
  StartingAgeTable: array[0..7, 0..6] of TAgeEntry absolute Raw3E5B;
  { The alignments each class mask may pick (ovl16:056C): a 10-byte row per ClassMask 0..16, the count first and
    then the AlignmentNames numbers (the image's cleric row is 9 and 0..8, its druid row 5 and 1, 3, 4, 5,
    7). }
  ClassAlignmentChoices: array[0..16, 0..9] of ShortInt absolute Raw3FE7;
  { The constitution hit-point adjustment table (the AD&D 1e table): ConstitutionHitPointTable[Constitution] is the
    hit-point adjustment a class with a level gets, signed (Constitution 3 gives -2, 4..6 -1,
    7..14 0, 15 +1, 16..18 +2). ovl16:3F31 sums it over the classes the character has a level in
    and adds the fighter bonus (Constitution above 16). Indexed by TCharacter.Constitution (+$14). }
  ConstitutionHitPointTable: array[0..$12] of ShortInt absolute ds408E;
  { The experience points a class needs for each level: one 14-entry LongInt row per class 0..7, entry
    [Class, Level] one more than the AD&D threshold (fighter [2, 2] is 2001, magic-user [5, 2] 2501,
    thief [6, 2] 1251) and -1 above the class's top level. The Restoration handler (ovl22:2C43) reads
    [Class, Level + 1] to pick the class whose next level is cheapest to restore. TrainCharacter (ovl16:29AE) reads
    [Class, Level + 1], the next level's threshold (it trains when Experience has reached it; 0 means the class has no
    further level), and [Class, Level + 2], the level after (Experience already there is cut to one below, so one
    visit raises one level; 0 when there is none). The highest-class-level routine of ovl12 (ovl12:2122) reads it too. }
  ExperienceTable: array[0..7, 0..13] of LongInt absolute Raw409B;
  ClericSlotTable: array[0..12, 1..3] of Byte absolute ds40BD;  { cleric spell slots of levels 1..3 per cleric level }
  MageSlotTable: array[0..12, 1..3] of Byte absolute ds41D5;  { magic-user spell slots of levels 1..3 per magic-user level }
  { The dice of a new character's starting gold per class 0..7 (ovl16:056C): the count, then the sides (the image: cleric and
    druid 3d6, fighter, paladin, ranger and monk 5d4, magic-user 2d4, thief 2d6). The gold is ten times
    the total rolled over the character's classes, shared by their number. }
  StartingGoldDice: array[0..7, 0..1] of Byte absolute Raw4263;
  SavingThrowTable: array[0..7, 0..8, 0..4] of Byte absolute ds426E;  { the five saving throws per class 0..7 and level }
  AiScratch: Byte absolute Raw443E;  { cleared with AiLastDirection at the start of the AI turn (ovl09:0B3C); meaning unknown }
  PlacingSide: ShortInt absolute ds4658;  { the side being placed on the combat map (ovl10:1C41) }
  { Globals of the combat map builder ovl10 (whitepaper 5.5.2). }
  CombatBlock: Byte absolute ds465A;  { the area map block code the battle is fought on (ovl10:1215) }
  LoaderLoopIndex: Byte absolute Raw465C;  { loop counter of the loader's three fill loops (ovl11:0130, 02CA, 035E) }
  GameDirBackup: string[40] absolute Raw4661;  { the save game name; the loader copies GameDir here and back
    (ovl11:0469, 05EA) }
  { Set to 1 by the RunCharacterMenu STING cheat (the J key, ovl16:0161). While set, the menu
    offers Train (CharacterMenuSlots slot 3), and TrainCharacter (ovl16:29AE) skips the consciousness, gold,
    class and experience checks and does not charge the 1000 gold. }
  StingCheat: Byte absolute Raw470C;
  FinalPictureNumber: string[1] absolute Raw4713;  { Str(TileSet): the picture number ShowEndingNarrative appends to FINAL }
  { The character the View command was started for: a copy of SelectedCharacter that ViewSelectedCharacter
    stores (ovl19:0AD1). The two Trade commands start their "Trade to?" from it and store the recipient in it
    (TradeItem, ovl19:1734; TradeMoney, ovl19:2156). }
  ViewedCharacter: PCharacter absolute ds471A;
  { Per-member timed-affect flags, indexed from 1 (member 1 is DS:471E). ovl20:0000 clears a member's
    flag, spends elapsed time on that member's affects, and sets the flag again while a timed affect
    remains. Index 0 (this byte) is never read. TimedAffectFlagsFrom0 is the same 72 bytes from index 1 and is only the
    name ovl20's rest code uses; a port should read and write TimedAffectFlags. }
  TimedAffectFlags: array[0..$48] of Byte absolute ds471D;
  { Globals of the ECL script machine's memory and operands (ovl07, whitepaper 5.1). }
  { The three word blocks as the script addresses them (see TVmWords4900): the same pointers as
    GameVars, GameVars2 and GameVars3. }
  VarsAt4900: ^TVmWords4900 absolute GameVars;
  VarsAt6B00: ^TVmWords6B00 absolute GameVars2;
  VarsAt9700: ^TVmWords9700 absolute GameVars3;
  { up: ECL 36, 49, 51, 58 and 61 (ovl03:179B, 2AA2, 2AEB, 271F, 2B14); down: 37, 38 (ovl03:18F8); meaning unknown }
  EclPC: Word absolute ds49ED;  { set to $9900 by the loader (ovl11:03C0) }
  WaitAfterTextRun: Byte absolute Raw4A00;  { set to 1 by the loader (ovl11:03A1) and by EndBattle (ovl05:1631) }
  VideoAdapter: Byte absolute ds4A1E;
  ClipChecksEnabled: Byte absolute Raw5370;  { set to 1 by the loader (ovl11:042E) }
  { POOL.CFG line 3: the game directory with trailing backslash (res08_init, whitepaper 2.3). StartGame
    saves it in GameDirBackup, empties it, builds a file path in it (ovl11:0564) for OpenGameFile and
    restores it (ovl11:0469, 05EA). }
  GameDir: string absolute ds547C;  { the game directory; see above }
  DiskDriveLetter: Byte absolute Raw547D;  { a character the loader appends to the path through System_MemOp_0C3B
    (ovl11:0581) }
  LootListBoundary: PMenuLine absolute Raw5D9A;  { loot list entry where the
    battle's item experience count stops (ovl05:02E5) }
  GlyphRow: Byte absolute ds5E25;  { 0768's current glyph row: reset to Top on clear, Inc per newline }
  PictureSlots: array[Byte] of TPictureSlot absolute Raw5E5A;  { picture slots (ovl32); loader clears $D0 bytes (ovl11:02B9) }
  DyingPicture: Pointer absolute ds5F1A;  { the picture RemoveCombatant draws over a dying combatant's cells }
  { The combat map (ovl31): the $4E9-byte block EndCombat frees (ovl08:0041); EndCombatRound
    centres the view on ViewX/ViewY (ovl08:0937). }
  CombatMap: PCombatMap absolute ds6716;  { see above }
  SortEntries: array[0..255] of TSortRec absolute Raw6718;  { the ovl30 sort table (element 0 holds the count, SortTable) }
  { PartySideCount and EnemySideCount indexed by side (ovl10:1AC7); the combat AI indexes them by the
    OpposingSide side of the actor (UseMagicItem, CastMemorizedSpell, ovl09:049F, 05C6). }
  SideCounts: array[0..1] of Byte absolute PartySideCount;
  { Byte DS:6822 as the three bytes ResolveCombatantAttacks addresses by attack slot: element 0 is the scalar
    AttackRoll that RollToHit and RollBeatsResistance write, elements 1 and 2 (DS:6823/6824) are the
    per-slot rolls the attack loop counts. }
  AttackSlotRolls: array[0..2] of ShortInt absolute ds6822;
  AttackRoll: ShortInt absolute AttackSlotRolls;  { the scalar attack or resistance roll (ovl24:0C63) }
  AvoidedAttackCounter: Byte absolute Raw6823;  { decremented every time an attack is avoided (ovl12:0FAC); meaning
    unknown [?] }
  { The character Who attacked last (Who^.Combat^.Target), copied by BoostAttackAgainstTarget (ovl12:013B).
    A far pointer: its segment word is DS:6828, the start of AffectHandlers, which overlaps it. }
  AttackTarget: PCharacter absolute Raw6826;
  { A combatant pointer the affect handlers share as scratch: ovl13:3A86 (the affect $4A handler)
    stores the combatant the affect records (CombatantRecord[Affect^.Data]) here and attacks it, and
    ovl12's handler at ovl12 code 0x138 stores Who^.Combat^.Target here before reading it. It
    overlaps the offset word of AffectHandlers[0], which is never called (SaveKind lies in it). }
  HandlerCombatant: PCharacter absolute Raw6826;
  { The handler of every affect number, called through CallAffectHandler (ovl24:001E); extent unknown. Entry 0
    is not a handler: SaveKind lies in it. }
  AffectHandlers: array[0..$8B] of TAffectHandler absolute ds6828;  { see above }
  SaveKind: Byte absolute ds682A;  { the saving throw kind SavingThrow offers to the hooks (ovl24:0DAD) }
  { Set to @MonsterBreath by InitSpellHandlers (ovl22:37A1). No routine in the image reads DS:6988 (no overlay,
    the resident units or the main program has the address), so its purpose is not known. DS:6988. }
  MonsterBreathVector: Pointer absolute Raw6988;
  WallSets: ^TWallSets absolute WallTiles;  { the wall tiles by wallset slot and wall (LoadWallSet) }
  GeoCells: PGeoCellBlock absolute GeoBlock;  { cell-byte view of the $400 block for ovl14 }
  WallDescriptor4: Byte absolute Raw6A63;  { wall view descriptor 4: ShowAreaView fills it from SpecialViewCode2 when
    SpecialViewGate is set }
  WallSetSlotPairs: array[0..3] of TPresenceSlot absolute PartyMapRow;
  { DS:6AB6..6ABD, 8 bytes no decompiled routine reads; declared so that the
                                    frame indexing of ReadPromptChoice (PictureAnimation.Frames[I], a base 8 bytes
                                    below the record, ovl25:04C8) resolves to the original offsets }
  { The $42-byte sprite list the loader clears (ovl11:0309) and ShowEncounterPicture loads; ReadPromptChoice
    animates it while it waits for a key. }
  PictureAnimation: TAnimation absolute ds6ABE;
  { The loader sets entries 1 and 2 to Kind $FF and Addr nil (ovl11:02CA..0302). }
  LoadSlots: array[0..2] of TLoadSlot absolute Raw6AFB;  { 5-byte slot table; see TLoadSlot }
  LastSpriteFile: string[8] absolute Raw6B0A;  { the last picture file loaded (LoadSpriteList); cleared by the loader
    (ovl11:043D) }
  LastSpriteBank: Byte absolute Raw6B1C;  { set to $FF by the loader (ovl11:0442) and by FreeSpriteList }
  LastPromptExtKey: Byte absolute ds6B2C;  { the last prompt's Flag (an extended key), copied by ReadPromptChoice }
  PromptTimeoutKey: Char absolute ds6B32;  { the key the prompt returns when the timeout runs out (ReadPromptChoice) }
  { The DS:6B84 block InitSpellHandlers fills: element 0 (DS:6B84) is the target picker and elements
    1..$43 are the per-spell cast handlers, one per spell number 1..$43 (68 elements, DS:6B84..6C93,
    ending just before SpellTargetCount), so CastChosenSpell's [Spell*4 + DS:6B84] reaches SpellHandlers[Spell].
    It is the real array here (not an absolute over a 4-byte pointer) so that a constant index such as
    SpellHandlers[1] resolves to DS:6B88 under `make match`; the DS:6B84 views below alias it. }
  SpellHandlers: array[0..$43] of TSpellHandler absolute Raw6B84;
  { DS:6B84 as the combat target picker: RunCombat sets @SelectSpellTargets at the start (ovl08:0085) and
    EndCombat @ChooseSpellTargets at the end (ovl08:0069); CastChosenSpell calls it as (spell, B, Done). }
  SpellTargetPicker: TSpellTargetPicker absolute SpellHandlers;
  { DS:6B84 as a far pointer, the two stores above written through the pointer type: RunCombat sets
    @SelectSpellTargets at the start (ovl08:0085) and EndCombat @ChooseSpellTargets at the end (ovl08:0069). }
  SpellPickerPointer: Pointer absolute SpellHandlers;
  { Globals of the spell target picker (CastSpell, whitepaper 5.22). The spell targets SelectSpellTargets
    (ovl13) and ChooseSpellTargets (ovl22) collect while a spell is aimed: entry I holds the PCharacter of a
    target at DS:6C91 + (I-1)*4, entry 1 is the global FirstSpellTarget above; entry 0 is never read (its fourth byte
    is the count SpellTargetCount, which overlaps the array). ApplySpellToTargets applies the spell to each of them. }
  SpellTargets: array[0..73] of PCharacter absolute Raw6C91;  { 1-based spell target list; see above }
  { The first spell target, also the character Remove Curse hands to CastRemoveCurse (ovl04:08FA). }
  FirstSpellTarget: PCharacter absolute Raw6C95;
  { 1 while money lies in the pool: PoolMoney sets it, ShareMoney sets it when some is left; the
    Temple and the shop clear it with the pool (ovl04:0D37). }
  MoneyInPool: Byte absolute ds6DC0;
  { 'Select Exit' and 'Place Exit': the Party Order menu before and after a
                                    character is picked (ovl15:17B0) }
  { The time a rest lasts, one word per digit of the game clock (ovl20 indexes it, ovl20:04A7): the
    camp's Rest command sets [1] minutes, [2] tens of minutes and [3] hours from the longest study
    time of the party (ovl15:07CA) before RunRestPeriod runs the rest, and clears all seven words after. }
  RestTime: TRestClock absolute ds6DC2;
  { Per-member rest-study delay, decremented each rest step (ovl20:0B33..0B91). When it reaches zero,
    the next pending spell's level resets it to three times that level (ovl20:0B80..0B91). }
  RestStudyCountdowns: array[0..6] of Byte absolute ds6DCF;
  RestWindowActive: Byte absolute ds6DDA;
  MarkerFrame: Byte absolute ds6DDC;  { the party marker's animation frame 0..5; evidence in re/dseg.toml }
  { nonzero while the rest screen is up: ovl20:0C9A sets it to 1 on entry and 0
                                    on exit, and RES12:0886 picks the top row of its message window from it;
                                    loader clears it (ovl11:0410) }
  DoorMenuFlags: array[0..2] of Byte absolute Raw6DDE;  { 3-byte buffer the loader fills with 1 (ovl11:0342) }
  KnockMenuFlag: Byte absolute Raw6DE0;  { knock menu flag: e1 offers Knock while nonzero; overlaps DoorMenuFlags[2] }
  { The combatant order the AI works through: one DS:5F27 combatant index per entry, read from
    entry 1 (ovl09:02EB loops 1..CollectEnemiesInRange(Who, SpellAreaSize(Spell)) over it; ovl13:0F90 moves
    the character at entry 1 to another entry). Entry 0 is never read. Extent not proven; the
    next named byte after it is SecondMoraleByte. }
  CombatantScanList: array[0..73] of Byte absolute Raw6DE4;
  PromptKeyFlag: Byte absolute Raw6E31;  { the key flag the ovl08 menus pass to ReadPromptChoice }
  CombatPicture: Pointer absolute Raw6E36;  { a picture EndCombat frees through ReleasePicture (ovl08:005A) }
  SkippedOpcode: Byte absolute ds6F7F;  { the opcode SkipCommand reads at EclPC (ovl07:1EB7) }
  { The icon slot of the encounter group being set up: InitScript sets 8 (ovl07:01F0). ECL command 11
    (ovl03:0450) and SetupDuel (ovl07:1A6F) load the group's CPIC picture into it and give it to their
    members as CombatIcon; ECL command 11 moves it on by one per group. }
  EncounterIconSlot: Byte absolute Raw6F83;
  { The string operands of the current command, entries 1.. in operand order (DecodeOperands);
    entry 0 is the index base, never read (in the image it overlaps the operand tables). The upper
    bound is not known: the largest operand count seen is 14 (ovl03). }
  EclStrings: array[0..14] of string absolute ds6FC8;
  { The decoded operands of the current script command (DecodeOperands, ovl07:0000): entries
    1..64 of each table; entry 0 is the byte before, never read (in the image it is the last entry
    of the table before). OperandType 0 is an immediate byte, 1 and 3 an address to read, 2 an
    immediate word, $80 a packed string, $81 the address of a string. }
  OperandType: array[0..64] of Byte absolute ds7005;
  OperandHigh: array[0..64] of Byte absolute ds7045;  { the high byte of a word operand }
  { loop counter of FreeSpriteList (the sprite list slots); ShortInt: the loop exits with jg }
  SharedLoopIndex: ShortInt absolute Raw70C7;
  PictureShownFlags: array[0..1] of Byte absolute Raw84C8;  { two bytes InitScript clears (ovl07:01DF); meaning unknown }
  BattleWon: Byte absolute ds84DA;  { 1 when the party (or the duelist) won the battle (ovl05:05CA, 07AC) }
  LastShownPictureWord: Byte absolute Raw84EA;  { the head/picture word GameVars2^[$2E1] ShowEncounterPicture last
    showed (ovl07:0633) }
  HeapWords: array[0..1] of Word absolute HeapEnd;
implementation
end.
