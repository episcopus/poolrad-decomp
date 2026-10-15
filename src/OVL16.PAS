unit OVL16;
{ CharCreate (overlay 16, whitepaper 5.8): the training hall, where a party member is created,
  modified, trained, dropped, added from the saved list or removed. RunCharacterMenu is its menu;
  CreateCharacter asks for a race, gender, class and alignment ('Pick Race', 'Pick Gender', 'Pick
  Class', 'Pick Alignment' in the literal pool at ovl16:04F1..0525), rolls the six ability scores
  and saves a TCharacter; ModifyCharacter, TrainCharacter, DropCharacter, AddSavedCharacters and
  RemoveSelectedCharacter are the other functions. FreeCharacter frees a character and everything
  it owns. EditCharacterIcon is the character-icon editor of the camp's Alter menu and of the end of
  character creation (its nested DrawIconCell and CopyPictureSlot draw and recolour the icon). }
{$A-,O+,F+,S-,R-,G-,I-,L-}
interface
uses POOLVARS, RES04, RES06, RES07, RES09, RES12, OVL17, OVL19, OVL23, OVL24, OVL25, OVL28, OVL31, OVL32;
procedure FreeCharacter(Who: PCharacter);
procedure RunCharacterMenu;
procedure CreateCharacter;
procedure DropCharacter;
procedure ModifyCharacter;
procedure TrainCharacter;
procedure AddSavedCharacters;
procedure RemoveSelectedCharacter(Uncounted, FreePicture: Boolean);
procedure ChooseHeadAndBody;
procedure EditCharacterIcon;
function ConstitutionHitPointAdjustment(Who: PCharacter): ShortInt;
function MinHitPoints(Who: PCharacter): Byte;
function MaxHitPoints(Who: PCharacter): Byte;
function RollHitPoints(Who: PCharacter; ClassBits: Byte): Byte;
procedure PayGold(Amount: LongInt; Who: PCharacter);
implementation

const
  CombatRecordSize = $16;   { FreeMem size of TCharacter.Combat (TCombatant) }
  ItemListSize = $3F;       { FreeMem size of one item of TCharacter.Items (TMenuLine) }
  AffectSize = 9;           { FreeMem size of one affect of TCharacter.Affects (TAffect) }
  CharacterSize = $11D;     { FreeMem size of a whole TCharacter }
  MenuLeft = 1;             { the function menu window, drawn by DrawWindow in RunCharacterMenu }
  MenuTop = 1;
  MenuRight = $26;
  MenuBottom = $16;
  MenuFirstRow = $C;        { text row of the first function name in the menu }
  HotKeyColour = $F;        { white: the function name's first (hotkey) letter }
  NameColour = $A;          { green: the rest of the function name }
  ChoiceTitleColour = $D;   { the ReadPromptChoice title colour of the menu }
  { GameVars2^ word 680: the set of classes this training hall trains, a mask over the ClassTrainingBits class
    bits (only its low byte is tested). RunCharacterMenu offers Train (slot 3) while it is nonzero,
    or while the STING cheat StingCheat is set; TrainCharacter needs it to share a bit with the
    character's classes and with a trainable class, else 'We don't train that class here'. Who
    writes it is not found yet [I]. }
  TrainableClassesWord = 680;
  GoldInCopper = 200;       { one gold piece is 200 copper (CoinCopperValues[GoldCoin]) }
  { the column of each ability's minimum and maximum in a 16-byte row of the per-race limits
    RaceAbilityLimits (ModifyCharacter, CreateCharacter): the Strength columns +0/+2/+4 are RaceStrengthMax and
    RaceStrengthPercent, and Intelligence .. Charisma take the columns +6/+7 .. +14/+15. }
  IntMinOffset = 6;
  IntMaxOffset = 7;
  WisMinOffset = 8;
  WisMaxOffset = 9;
  DexMinOffset = 10;
  DexMaxOffset = 11;
  ConMinOffset = 12;
  ConMaxOffset = 13;
  ChaMinOffset = 14;
  ChaMaxOffset = 15;
  ExceptionalStrength = 18; { a Strength above this uses the exceptional percentile; 18 itself rolls one }

type
  { The five coin kinds, in the order of CoinCopperValues (copper 0 .. platinum 4). The money routine
    42ED walks it with Succ and Pred, which is the enumerated type the original used (its
    `mov al,x; inc al` / `dec al` is the Succ/Pred codegen, tools/re/tp_idioms/ovl16/PAYPRB2.PAS). }
  TCoinKind = (CopperCoin, SilverCoin, ElectrumCoin, GoldCoin, PlatinumCoin);

  { An in-memory picture as ovl32 loads it: the tile byte size at +$11, the pointer to the packed
    pixel buffer at +$13 and the copied tile bytes (the tail) at +$17. The same layout as ovl32's
    private TMemPic, declared here because ovl16 needs it too (like ovl17's copy). }
  PMemPic = ^TMemPic;
  TMemPic = record
    Head: array[0..$10] of Byte;    { +0..+$10: the picture header (height, width, item count) }
    ByteSize: Word;                 { +$11: bytes per tile }
    Pixels: ^Byte;                  { +$13: the packed pixel bytes }
    Tail: array[0..20000] of Byte;  { +$17: the tile bytes, indexed by a byte times ByteSize }
  end;

  { TCharacter seen from its ability scores on, with the six scores (Strength .. Charisma) as an
    array so a loop can index them by ability (ModifyCharacter's cursor, CreateCharacter's rolls). The
    offsets match TCharacter's
    (whitepaper 4.2.5): +$10 the scores, +$16 StrengthPercent, +$2E Race, +$2F ClassMask,
    +$32 HpMax, +$85 HirelingShare, +$96 ClassLevels, +$9E B9E, +$B2 SpellSlots, +$11B Flag11B
    (the current hit points). }
  PScoredCharacter = ^TScoredCharacter;
  TScoredCharacter = record
    Pad0: array[0..$F] of Byte;             { +$00..+$0F: Name and the rest of TCharacter }
    Scores: array[0..5] of Byte;            { +$10: Strength, Intelligence, Wisdom, Dexterity,
                                              Constitution, Charisma }
    StrengthPercent: Byte;                  { +$16 }
    Pad17: array[$17..$2D] of Byte;
    Race: ShortInt;                         { +$2E }
    ClassMask: ShortInt;                    { +$2F }
    Age: Word;                              { +$30 }
    HpMax: Byte;                            { +$32 }
    Pad33: array[$33..$84] of Byte;
    HirelingShare: Byte;                    { +$85 }
    Pad86: array[$86..$95] of Byte;
    ClassLevels: array[0..7] of ShortInt;   { +$96..+$9D }
    B9E: ShortInt;                          { +$9E }
    Pad9F: Byte;                            { +$9F }
    PadA0: array[$A0..$B1] of Byte;
    SpellSlots: array[0..1, 1..3] of Byte;  { +$B2..+$B7 }
    PadB8: array[$B8..$11A] of Byte;
    Flag11B: Byte;                          { +$11B: the current hit points }
  end;

{ ovl16:0000. Frees a character and everything it owns: its combat state (Combat, size $16), its
  carried items (the list at Items, size $3F) and its affects (the list at Affects, size 9), then
  the character record itself (size $11D). The last statement, `Who := nil`, is a dead store: Who
  is a by-value parameter, so it only clears this routine's own copy and no caller's pointer
  changes (RemoveSelectedCharacter reassigns SelectedCharacter itself right after the call).
  QUIRK ovl16:00D4: the by-value `Who := nil` stores nil into the callee's own parameter copy and
  does not clear the caller's pointer. }
procedure FreeCharacter(Who: PCharacter);
var
  CurItem: PItem;
  NextItem: PItem;
  CurAffect: PAffect;
  NextAffect: PAffect;
begin
  with Who^ do
  begin
    if Combat <> nil then
      FreeMem(Combat, CombatRecordSize);
    NextItem := Items;
    while NextItem <> nil do
    begin
      CurItem := NextItem;
      NextItem := NextItem^.Next;
      FreeMem(CurItem, ItemListSize);
    end;
    NextAffect := PAffect(Affects);
    while NextAffect <> nil do
    begin
      CurAffect := NextAffect;
      NextAffect := NextAffect^.Next;
      FreeMem(CurAffect, AffectSize);
    end;
  end;
  FreeMem(Who, CharacterSize);
  Who := nil;   { QUIRK ovl16:00D4: a dead store, Who is a by-value parameter (no caller changes) }
end;
{ ovl16:0161. The main menu of the character-creation / training hall (called by ovl03:2E10). It
  draws the window (DrawWindow) and, when a character is selected, its roster (DrawPartyRoster) and
  the eleven function names of the menu at DS:0619 (the first letter in white, the rest in green,
  DrawTextAt). The eleven slots, in the order of the hotkey line CharacterMenuHotkeys 'C D M T V A R L S B E J',
  hold the texts at DS:0619: SlotCreate 0 'Create New Character', SlotDrop 1 'Drop Character',
  SlotModify 2 'Modify Character', SlotTrain 3 'Train Character', SlotView 4 'View Character',
  SlotAdd 5 'Add Character to Party', SlotRemove 6 'Remove Character from Party', SlotLoad 7
  'Load Saved Game', SlotSave 8 'Save Current Game', SlotBegin 9 'BEGIN Adventuring' and SlotExit
  10 'Exit to DOS'. It then asks ReadPromptChoice for a function key and dispatches it: C create
  (CreateCharacter), D drop (DropCharacter), M modify (ModifyCharacter), T train (TrainCharacter),
  V view (ViewSelectedCharacter), A add (AddSavedCharacters), R remove (SaveCharacter then
  RemoveSelectedCharacter), L load (LoadGame), S save (SaveGame), B BEGIN Adventuring (it needs a
  non-empty party, PartyListHead, and stores the view mode Mode 4 in ViewMode before it leaves), E exit
  (AskYesNo, then save and QuitGame), J the STING cheat. An extended key G or O selects another
  party member (UpdateSelectedCharacter); every other key (all except E and S) clears the heap
  retry gate HeapErrorStop, and E and S leave it alone: the E path's SaveGame retry loop reads HeapErrorStop to
  end the retry (POOLVARS). Mode (4) is the value stored in the view mode ViewMode on B. Local at
  [bp-5] is unused; the frame needs its 9 bytes. }
procedure RunCharacterMenu;
const
  { The eleven slots of the menu at CharacterMenuSlots, in the order of the hotkey line CharacterMenuHotkeys
    'C D M T V A R L S B E J' (the slot text is listed in the routine comment above). }
  SlotCreate = 0;
  SlotDrop = 1;
  SlotModify = 2;
  SlotTrain = 3;
  SlotView = 4;
  SlotAdd = 5;
  SlotRemove = 6;
  SlotLoad = 7;
  SlotSave = 8;
  SlotBegin = 9;
  SlotExit = 10;
var
  I: Byte;
  Key: Char;
  ExtKey: Byte;
  Done: Byte;
  Unused: string[8];
  Row: ShortInt;
  Show: Byte;
  Mode: Byte;
begin
  TileSet := 3;
  Mode := 4;
  Show := 1;
  StingCheat := 0;
  ViewMode := 0;
  while True do
  begin
    if Show <> 0 then
    begin
      DrawWindow(MenuLeft, MenuTop, MenuRight, MenuBottom, 0, 0, '');
      if SelectedCharacter <> nil then
      begin
        DrawPartyRoster(SelectedCharacter);
        CharacterMenuSlots[SlotDrop].Present := 1;
        CharacterMenuSlots[SlotModify].Present := 1;
        if (GameVars2^[TrainableClassesWord] > 0) or (StingCheat <> 0) then
          CharacterMenuSlots[SlotTrain].Present := 1;
        CharacterMenuSlots[SlotView].Present := 1;
        CharacterMenuSlots[SlotRemove].Present := 1;
        CharacterMenuSlots[SlotLoad].Present := 0;
        CharacterMenuSlots[SlotSave].Present := 1;
        CharacterMenuSlots[SlotBegin].Present := 1;
      end
      else
      begin
        CharacterMenuSlots[SlotDrop].Present := 0;
        CharacterMenuSlots[SlotModify].Present := 0;
        CharacterMenuSlots[SlotTrain].Present := 0;
        CharacterMenuSlots[SlotView].Present := 0;
        CharacterMenuSlots[SlotRemove].Present := 0;
        CharacterMenuSlots[SlotLoad].Present := 1;
        CharacterMenuSlots[SlotSave].Present := 0;
        CharacterMenuSlots[SlotBegin].Present := 0;
      end;
      Row := 0;
      for I := 0 to 10 do
        if CharacterMenuSlots[I].Present <> 0 then
        begin
          DrawTextAt(2, Row + MenuFirstRow, HotKeyColour, CharacterMenuSlots[I].Name[1]);
          DrawTextAt(3, Row + MenuFirstRow, NameColour, Copy(CharacterMenuSlots[I].Name, 2,
            Length(CharacterMenuSlots[I].Name) - 1));
          Inc(Row);
        end;
      Show := 0;
    end;
    Key := ReadPromptChoice('Choose a function ', CharacterMenuHotkeys, ChoiceTitleColour, 0, 0, 1, 0, ExtKey);
    ClearPromptLine;
    if ExtKey <> 0 then
    begin
      if Key in ['G', 'O'] then
      begin
        UpdateSelectedCharacter(Key);
        DrawPartyRoster(SelectedCharacter);
      end;
    end
    else
    begin
      if not (Key in ['E', 'S']) then
        HeapErrorStop := False;
      case Key of
        'C':
          if CharacterMenuSlots[SlotCreate].Present <> 0 then
            CreateCharacter;
        'D':
          if CharacterMenuSlots[SlotDrop].Present <> 0 then
            DropCharacter;
        'M':
          if CharacterMenuSlots[SlotModify].Present <> 0 then
            ModifyCharacter;
        'T':
          if CharacterMenuSlots[SlotTrain].Present <> 0 then
            TrainCharacter;
        'V':
          if CharacterMenuSlots[SlotView].Present <> 0 then
            ViewSelectedCharacter(Done);
        'A':
          if CharacterMenuSlots[SlotAdd].Present <> 0 then
            AddSavedCharacters;
        'R':
          if CharacterMenuSlots[SlotRemove].Present <> 0 then
            if SelectedCharacter <> nil then
            begin
              SaveCharacter(SelectedCharacter, '');
              RemoveSelectedCharacter(False, True);
            end;
        'L':
          if CharacterMenuSlots[SlotLoad].Present <> 0 then
          begin
            LoadGame;
            if ViewMode <> 0 then
            begin
              SkipAreaScriptLoad := 1;
              Exit;
            end;
          end;
        'S':
          if CharacterMenuSlots[SlotSave].Present <> 0 then
            if PartyListHead <> 0 then
              SaveGame;
        'B':
          if CharacterMenuSlots[SlotBegin].Present <> 0 then
            if PartyListHead <> 0 then
            begin
              ViewMode := Mode;
              ClearPromptLine;
              Exit;
            end;
        'E':
          if CharacterMenuSlots[SlotExit].Present <> 0 then
          begin
            Key := AskYesNo('Quit to DOS ', $E, $A, $F);
            if Key = 'Y' then
            begin
              while (not HeapErrorStop) and (PartyListHead <> 0) do
                SaveGame;
              QuitGame;
            end;
          end;
        'J':
          if ParamStr(1) = 'STING' then
          begin
            StingCheat := 1;
            ShowFlashMessage('I Understand, master...');
          end;
      end;
      Show := 1;
    end;
  end;
end;
{ ovl16:056C. The C (Create) function of the training hall, called by RunCharacterMenu (ovl16:0161). It
  builds a new party member and saves it. The record is allocated (GetMem and FillChar, 285 bytes)
  with its starting values: the six figure colour pairs from FigureColourSlots, magic resistance 50, THAC0 40,
  Flag10D set (it takes part in combat and earns experience), picture banks 1 and 1 and a random BAB.
  Four list menus follow in the window (1,2)..($26,$16), each a ChooseFromList with the title line
  'Pick Race', 'Pick Gender', 'Pick Class' or 'Pick Alignment' and the choices indented by two
  blanks; Enter picks, Escape (#0) leaves the whole routine:
  - Race: Dwarf, Elf, Gnome, Half-Elf, Halfling and Human (RaceNames 1..5 and 7; menu line 6 is
    stored as race 7, so Half-Orc cannot be picked). The race sets the first Figure byte (1 for
    Dwarf, Gnome and Halfling, 2 otherwise) and gives permanent racial affects through AddAffect
    (Duration 0, Data $FF, Flag 0): Dwarf $5A $61 $1A $2F, Gnome $61 $12 $2F $30, Halfling $5A $61,
    Elf $6B, Half-Elf $7C, Human none.
  - Gender: Male or Female (SexNames), stored as the zero-based choice in B9E.
  - Class: the row of the race in RaceClassChoices lists the classes it may pick; the chosen ClassMask gets
    level 1 in each class it combines (ClassLevels, a multi-class mask such as 8 Cleric/Fighter sets
    several), then ComputeThiefSkills for a thief, THAC0 (the highest ClassThac0Table entry), the
    item-usage ClassBits (ClassItemBits) and ComputeSavingThrows.
  - Alignment: the row of the class in ClassAlignmentChoices lists the alignments it may pick (ByteA0).
  The age comes next: the roll of the race and class entry in StartingAgeTable (a single class) or, for a
  multi-class, the maximum of one class's entry (Base + Sides * Count, not a roll). The class whose
  entry is used is not simply the first of the combined classes in the order cleric, fighter,
  magic-user: it is the Cleric entry for masks 8, 9, $B and $C, the Fighter entry for $E, and the
  Magic-User entry for $D (Fighter/Magic-User), $F and $10 (a first-in-order rule would wrongly
  give Fighter for $D and Cleric for $F).
  Then, until the player answers Y to 'Keep this character? ', it makes the character the
  SelectedCharacter, shows the sheet and rolls each ability score: the best of six RollDice(3, 6),
  raised or lowered by the race's age brackets (RaceAgeBrackets), clamped to the race's limits for the gender
  (RaceAbilityLimits) and raised to the class minimum (ClassAbilityMinimums); an 18 Strength of a fighter gets a random
  percentile up to the race's limit (StrengthPercent), a cleric multi-class gets at least 13 Wisdom.
  The class loop then sets the first spell slots (cleric, magic-user), makes the character know the
  first-level cleric spells (SpellTable) or four magic-user spells, rolls the starting gold (StartingGoldDice
  dice, ten times their total shared by the classes) and the hit points (RollHitPoints, the
  constitution adjustment and the class count; HpB1 keeps the roll per class) and shows the combat
  numbers and the money. The name is asked ('Character name: ', repeated until it is not empty), the
  head and body pictures are chosen (ChooseHeadAndBody), the icon editor runs (EditCharacterIcon) and
  SaveCharacter writes the character to its file; SelectedCharacter is restored and the record freed
  (the character joins the party later, through the A function that loads it from the file).
  No parameters; reads and temporarily replaces the global SelectedCharacter. Side effects: the menus,
  the character sheet and the saved character file.
  QUIRK ovl16:0783: Escape in a menu leaves with Exit, which neither frees the new character or the
  menu list nor restores SelectedCharacter (it is not yet replaced there); the memory is leaked.
  QUIRK ovl16:1236: the racial roll adjustments (race 1 +1 Con -1 Cha, 2 +1 Dex -1 Con, 5 -1 Str
  +1 Dex, 6 +1 Str +1 Con -2 Cha) test RaceIndex, the loop variable of the race menu, which is 7
  after that loop, not the chosen race, so they never apply.
  QUIRK ovl16:0FF3: the maximum-age rule has no case for ClassMask $A (Cleric/Ranger); no race offers
  it, so its age would stay 0. }
procedure CreateCharacter;
const
  StartFigureCount = 6;         { Figure[1..6]: the six colour pairs of the character icon }
  StartResist = 50;             { ResistBase }
  StartThac0 = 40;              { Thac0 before the class levels lower it }
  HumanRace = 7;                { RaceNames[7] }
  MenuRaceLines = 7;            { NewMenuList's count: the title line and the six races }
  MenuGenderLines = 3;          { the title line and two genders }
  RaceDwarf = 1;                { RaceNames: Dwarf, Elf, Gnome, Half-Elf, Halfling, Half-Orc, Human }
  RaceElf = 2;
  RaceGnome = 3;
  RaceHalfElf = 4;
  RaceHalfling = 5;
  RaceHalfOrc = 6;              { not on the menu; its adjustments are in the dead racial roll code }
  FirstRaceLine = 1;
  LastMenuRace = 5;             { menu lines 1..5 are the races 1..5 }
  HumanMenuLine = 6;            { menu line 6 is Human, stored as race 7 }
  { The window and colours of the four ChooseFromList menus (the title and prompt words are empty). }
  MenuLeftCol = 1;
  MenuTopRow = 2;
  MenuRightCol = $26;
  MenuBottomRow = $16;
  MenuHeadingColour = $D;
  MenuLineColour = $A;
  MenuHighlightColour = $F;
  { AskYesNo's and ReadInputLine's colours. }
  PromptTitleColour = $D;
  PromptWordColour = $A;
  PromptHotColour = $F;
  NamePromptColour = $D;
  KeyEnter = #13;
  KeyEscape = #0;
  { The permanent affects the race gives (AddAffect Duration 0, Data $FF, Flag 0). The saving-throw
    hooks (RunAffectHooks kind $C, ovl24:02FA) run $5A and $61, the hooks of kind $A (the attacker of
    a roll) $12 and $1A, kind $10 (the target of a roll) $2F and $30, kind 9 (a new affect)
    $6B and $7C; what each does is not read yet [?]. }
  AffectSaveHookA = $5A;
  AffectSaveHookB = $61;
  AffectAttackHookA = $1A;
  AffectAttackHookB = $12;
  AffectTargetHookA = $2F;
  AffectTargetHookB = $30;
  AffectNewAffectElf = $6B;
  AffectNewAffectHalfElf = $7C;
  PermanentDuration = 0;
  DataFF = $FF;
  NoRemoveHandler = 0;
  FighterFigure = 1;            { Figure[0] for the Dwarf, Gnome and Halfling }
  OtherFigure = 2;              { Figure[0] for the others }
  { The class numbers (ClassLevels index, ClassNames order) and the multi-class ClassMask values. }
  ClericClass = 0;
  FighterClass = 2;
  RangerClass = 4;
  MageClass = 5;
  ThiefClass = 6;
  ClassTypeCount = 8;
  ClericFighter = 8;
  ClericFighterMage = 9;
  ClericRanger = $A;
  ClericMage = $B;
  ClericThief = $C;
  FighterMage = $D;
  FighterThief = $E;
  FighterMageThief = $F;
  MageThief = $10;
  { The age brackets of RaceAgeBrackets (columns of a race's row). }
  YoungAdultAge = 0;
  MiddleAge = 1;
  OldAge = 2;
  VenerableAge = 3;
  AbilityRollCount = 6;         { rolls per ability; the best is kept }
  AbilityDiceCount = 3;
  AbilityDiceSides = 6;
  StrengthIndex = 0;            { the six abilities in TCharacter order, +$10..+$15 }
  IntelligenceIndex = 1;
  WisdomIndex = 2;
  DexterityIndex = 3;
  ConstitutionIndex = 4;
  CharismaIndex = 5;
  MinClericWisdom = 13;         { a Cleric multi-class needs this Wisdom }
  ExceptionalStrengthRoll = 100; { Random(100) + 1: the percentile of an 18 Strength fighter }
  StartAttacks = 2;             { Attacks }
  StartBaseDamage = 2;          { BaseDamage[1] }
  StartMovement = $C;           { BaseMovement }
  SpellDetectMagic = $B;        { the magic-user spells a magic-user starts with (SpellNames) }
  SpellReadMagic = $12;
  SpellShield = $13;
  SpellSleep = $15;
  SpellCount = $38;             { the spells of SpellTable }
  KeepAnswer = 'Y';
  NameMaxLength = $F;           { TCharacter.Name is string[15] }
var
  NewCharacter: PCharacter;     { [bp-4]: the working copy of the character being created }
  SavedSelection: PCharacter;   { [bp-8]: SelectedCharacter before the creation replaced it }
  MenuList: PMenuLine;          { [bp-0xC]: the list menu being shown (title line first) }
  PickedLine: PMenuLine;        { [bp-0x10]: ChooseFromList's selected line, and the line being filled }
  Choice: Integer;              { [bp-0x12]: ChooseFromList's choice, 1 is the first line after the title }
  I: Byte;                      { [bp-0x13]: the menu line / figure / spell loop }
  RollAttempt: Byte;            { [bp-0x14]: the six rolls of one ability }
  AbilityRoll: Byte;            { [bp-0x15]: the current RollDice(3, 6) }
  Key: Char;                    { [bp-0x16]: the key ChooseFromList or AskYesNo returned }
  RaceIndex: ShortInt;          { [bp-0x17]: the race menu's loop variable; 7 afterwards (see the QUIRK) }
  GenderIndex: ShortInt;        { [bp-0x18]: the gender menu's loop variable }
  ClassIndex: ShortInt;         { [bp-0x19]: the class loop: 0..7 }
  Spare1: Byte;                 { [bp-0x1A]: the original frame reserves this byte, never used }
  AbilityIndex: ShortInt;       { [bp-0x1B]: the ability being rolled: 0..5 }
  ChoiceCount: Byte;            { [bp-0x1C]: the number of choices of the class or alignment menu }
  ConAdjustment: Integer;       { [bp-0x1E]: ConstitutionHitPointAdjustment of the new character }
  Spare2: Byte;                 { [bp-0x1F]: the original frame reserves this byte, never used }
  ClassTotal: Byte;             { [bp-0x20]: the number of classes the character has a level in }
  GoldDiceTotal: Byte;          { [bp-0x21]: the starting-gold dice rolled over the classes }
  WithExit: Byte;               { [bp-0x22]: ChooseFromList's WithExit, 1 }
  Redraw: Byte;                 { [bp-0x23]: ChooseFromList's var Redraw, 1 }
begin
  GetMem(NewCharacter, CharacterSize);
  FillChar(NewCharacter^, CharacterSize, 0);
  with NewCharacter^ do
  begin
    for I := 1 to StartFigureCount do
      Figure[I] := FigureColourSlots[I] + (FigureColourSlots[I] + 8) * 16;
    ResistBase := StartResist;
    Thac0 := StartThac0;
    Status := 0;
    Flag10D := 1;
    HeadBank := 1;
    BodyBank := 1;
    CombatSize := 1;
    BAB := Random(256);
  end;
  NewMenuList(MenuRaceLines, MenuList);
  MenuList^.Flag29 := 1;
  MenuList^.Text := 'Pick Race';
  for RaceIndex := 1 to HumanRace do
    case RaceIndex of
      FirstRaceLine..LastMenuRace:
        begin
          PickedLine := GetMenuLine(RaceIndex, MenuList);
          PickedLine^.Text := '  ' + RaceNames[RaceIndex];
        end;
      HumanRace:
        begin
          PickedLine := GetMenuLine(RaceIndex - 1, MenuList);
          PickedLine^.Text := '  ' + RaceNames[RaceIndex];
        end;
    end;
  PickedLine := MenuList;
  Choice := 1;
  Redraw := 1;
  WithExit := 1;
  repeat
    Key := ChooseFromList('', '', MenuHeadingColour, MenuLineColour, MenuHighlightColour, MenuLeftCol,
      MenuTopRow, MenuRightCol, MenuBottomRow, MenuList, WithExit, Redraw, Choice, PickedLine);
    if Key = KeyEscape then Exit;
  until Key = KeyEnter;
  if Choice = HumanMenuLine then
    Inc(Choice);
  with NewCharacter^ do
  begin
    Race := Choice;
    case Race of
      RaceHalfling:
        begin
          Figure[0] := FighterFigure;
          AddAffect(NewCharacter, AffectSaveHookA, PermanentDuration, DataFF, NoRemoveHandler);
          AddAffect(NewCharacter, AffectSaveHookB, PermanentDuration, DataFF, NoRemoveHandler);
        end;
      RaceDwarf:
        begin
          Figure[0] := FighterFigure;
          AddAffect(NewCharacter, AffectSaveHookA, PermanentDuration, DataFF, NoRemoveHandler);
          AddAffect(NewCharacter, AffectSaveHookB, PermanentDuration, DataFF, NoRemoveHandler);
          AddAffect(NewCharacter, AffectAttackHookA, PermanentDuration, DataFF, NoRemoveHandler);
          AddAffect(NewCharacter, AffectTargetHookA, PermanentDuration, DataFF, NoRemoveHandler);
        end;
      RaceGnome:
        begin
          Figure[0] := FighterFigure;
          AddAffect(NewCharacter, AffectSaveHookB, PermanentDuration, DataFF, NoRemoveHandler);
          AddAffect(NewCharacter, AffectAttackHookB, PermanentDuration, DataFF, NoRemoveHandler);
          AddAffect(NewCharacter, AffectTargetHookA, PermanentDuration, DataFF, NoRemoveHandler);
          AddAffect(NewCharacter, AffectTargetHookB, PermanentDuration, DataFF, NoRemoveHandler);
        end;
      RaceElf:
        begin
          Figure[0] := OtherFigure;
          AddAffect(NewCharacter, AffectNewAffectElf, PermanentDuration, DataFF, NoRemoveHandler);
        end;
      RaceHalfElf:
        begin
          Figure[0] := OtherFigure;
          AddAffect(NewCharacter, AffectNewAffectHalfElf, PermanentDuration, DataFF, NoRemoveHandler);
        end;
    else
      Figure[0] := OtherFigure;
    end;
  end;
  FreeMenuList(MenuList);
  NewMenuList(MenuGenderLines, MenuList);
  MenuList^.Flag29 := 1;
  MenuList^.Text := 'Pick Gender';
  for GenderIndex := 0 to 1 do
  begin
    PickedLine := GetMenuLine(GenderIndex + 1, MenuList);
    PickedLine^.Text := '  ' + SexNames[GenderIndex];
  end;
  PickedLine := MenuList;
  Choice := 1;
  WithExit := 1;
  Redraw := 1;
  repeat
    Key := ChooseFromList('', '', MenuHeadingColour, MenuLineColour, MenuHighlightColour, MenuLeftCol,
      MenuTopRow, MenuRightCol, MenuBottomRow, MenuList, WithExit, Redraw, Choice, PickedLine);
    if Key = KeyEscape then Exit;
  until Key = KeyEnter;
  NewCharacter^.B9E := Choice - 1;
  FreeMenuList(MenuList);
  ChoiceCount := RaceClassChoices[NewCharacter^.Race, 0];
  NewMenuList(ChoiceCount + 1, MenuList);
  MenuList^.Flag29 := 1;
  MenuList^.Text := 'Pick Class';
  for I := 1 to ChoiceCount do
  begin
    PickedLine := GetMenuLine(I, MenuList);
    PickedLine^.Text := '  ' + ClassNames[RaceClassChoices[NewCharacter^.Race, I]];
  end;
  PickedLine := MenuList;
  Choice := 1;
  WithExit := 1;
  Redraw := 1;
  repeat
    Key := ChooseFromList('', '', MenuHeadingColour, MenuLineColour, MenuHighlightColour, MenuLeftCol,
      MenuTopRow, MenuRightCol, MenuBottomRow, MenuList, WithExit, Redraw, Choice, PickedLine);
    if Key = KeyEscape then Exit;
  until Key = KeyEnter;
  with NewCharacter^ do
  begin
    ClassMask := RaceClassChoices[Race, Choice];
    HighestLevel := 1;
    case ClassMask of
      0..7: ClassLevels[ClassMask] := 1;
      ClericFighter:
        begin
          ClassLevels[ClericClass] := 1;
          ClassLevels[FighterClass] := 1;
        end;
      ClericFighterMage:
        begin
          ClassLevels[ClericClass] := 1;
          ClassLevels[FighterClass] := 1;
          ClassLevels[MageClass] := 1;
        end;
      ClericRanger:
        begin
          ClassLevels[ClericClass] := 1;
          ClassLevels[RangerClass] := 1;
        end;
      ClericMage:
        begin
          ClassLevels[ClericClass] := 1;
          ClassLevels[MageClass] := 1;
        end;
      ClericThief:
        begin
          ClassLevels[ClericClass] := 1;
          ClassLevels[ThiefClass] := 1;
        end;
      FighterMage:
        begin
          ClassLevels[FighterClass] := 1;
          ClassLevels[MageClass] := 1;
        end;
      FighterThief:
        begin
          ClassLevels[FighterClass] := 1;
          ClassLevels[ThiefClass] := 1;
        end;
      FighterMageThief:
        begin
          ClassLevels[FighterClass] := 1;
          ClassLevels[MageClass] := 1;
          ClassLevels[ThiefClass] := 1;
        end;
      MageThief:
        begin
          ClassLevels[MageClass] := 1;
          ClassLevels[ThiefClass] := 1;
        end;
    end;
    if ClassLevels[ThiefClass] > 0 then
      ComputeThiefSkills(NewCharacter);
    ClassBits := 0;
    Thac0 := 0;
    for ClassIndex := 0 to ClassTypeCount - 1 do
      if ClassLevels[ClassIndex] > 0 then
      begin
        if ClassThac0Table[ClassIndex, ClassLevels[ClassIndex]] > Thac0 then
          Thac0 := ClassThac0Table[ClassIndex, ClassLevels[ClassIndex]];
        Inc(ClassBits, ClassItemBits[ClassIndex]);
      end;
  end;
  ComputeSavingThrows(NewCharacter);
  FreeMenuList(MenuList);
  ChoiceCount := ClassAlignmentChoices[NewCharacter^.ClassMask, 0];
  NewMenuList(ChoiceCount + 1, MenuList);
  MenuList^.Flag29 := 1;
  MenuList^.Text := 'Pick Alignment';
  for I := 1 to ChoiceCount do
  begin
    PickedLine := GetMenuLine(I, MenuList);
    PickedLine^.Text := '  ' + AlignmentNames[ClassAlignmentChoices[NewCharacter^.ClassMask, I]];
  end;
  PickedLine := MenuList;
  Choice := 1;
  WithExit := 1;
  Redraw := 1;
  repeat
    Key := ChooseFromList('', '', MenuHeadingColour, MenuLineColour, MenuHighlightColour, MenuLeftCol,
      MenuTopRow, MenuRightCol, MenuBottomRow, MenuList, WithExit, Redraw, Choice, PickedLine);
    if Key = KeyEscape then Exit;
  until Key = KeyEnter;
  NewCharacter^.ByteA0 := ClassAlignmentChoices[NewCharacter^.ClassMask, Choice];
  FreeMenuList(MenuList);
  if NewCharacter^.ClassMask <= 7 then
    with StartingAgeTable[NewCharacter^.Race, NewCharacter^.ClassMask] do
      NewCharacter^.Age := RollDice(Count, Sides) + Base
  else
    with NewCharacter^ do
      case ClassMask of
        ClericFighter:
          Age := StartingAgeTable[Race, ClericClass].Base
            + StartingAgeTable[Race, ClericClass].Sides * StartingAgeTable[Race, ClericClass].Count;
        ClericFighterMage:
          Age := StartingAgeTable[Race, ClericClass].Base
            + StartingAgeTable[Race, ClericClass].Sides * StartingAgeTable[Race, ClericClass].Count;
        ClericMage:
          Age := StartingAgeTable[Race, ClericClass].Base
            + StartingAgeTable[Race, ClericClass].Sides * StartingAgeTable[Race, ClericClass].Count;
        ClericThief:
          Age := StartingAgeTable[Race, ClericClass].Base
            + StartingAgeTable[Race, ClericClass].Sides * StartingAgeTable[Race, ClericClass].Count;
        FighterMage:
          Age := StartingAgeTable[Race, MageClass].Base
            + StartingAgeTable[Race, MageClass].Sides * StartingAgeTable[Race, MageClass].Count;
        FighterThief:
          Age := StartingAgeTable[Race, FighterClass].Base
            + StartingAgeTable[Race, FighterClass].Sides * StartingAgeTable[Race, FighterClass].Count;
        FighterMageThief:
          Age := StartingAgeTable[Race, MageClass].Base
            + StartingAgeTable[Race, MageClass].Sides * StartingAgeTable[Race, MageClass].Count;
        MageThief:
          Age := StartingAgeTable[Race, MageClass].Base
            + StartingAgeTable[Race, MageClass].Sides * StartingAgeTable[Race, MageClass].Count;
      end;
  SavedSelection := SelectedCharacter;
  SelectedCharacter := NewCharacter;
  ShowCharacterSheet;
  repeat
    NewCharacter^.StrengthPercent := 0;
    for AbilityIndex := 0 to CharismaIndex do
    begin
      PScoredCharacter(NewCharacter)^.Scores[AbilityIndex] := 0;
      for RollAttempt := 1 to AbilityRollCount do
      begin
        AbilityRoll := RollDice(AbilityDiceCount, AbilityDiceSides);
        case RaceIndex of
          RaceDwarf:
            case AbilityIndex of
              ConstitutionIndex: Inc(AbilityRoll);
              CharismaIndex: Dec(AbilityRoll);
            end;
          RaceElf:
            case AbilityIndex of
              DexterityIndex: Inc(AbilityRoll);
              ConstitutionIndex: Dec(AbilityRoll);
            end;
          RaceHalfling:
            case AbilityIndex of
              StrengthIndex: Dec(AbilityRoll);
              DexterityIndex: Inc(AbilityRoll);
            end;
          RaceHalfOrc:
            case AbilityIndex of
              StrengthIndex: Inc(AbilityRoll);
              ConstitutionIndex: Inc(AbilityRoll);
              CharismaIndex: Dec(AbilityRoll, 2);
            end;
        end;
        if PScoredCharacter(NewCharacter)^.Scores[AbilityIndex] < AbilityRoll then
          PScoredCharacter(NewCharacter)^.Scores[AbilityIndex] := AbilityRoll;
      end;
      with PScoredCharacter(NewCharacter)^ do
        case AbilityIndex of
          StrengthIndex:
            begin
              if (Scores[AbilityIndex] > 0) and (RaceAgeBrackets[Race, YoungAdultAge] < Age) then
                Inc(Scores[AbilityIndex]);
              if (Scores[AbilityIndex] > 0) and (RaceAgeBrackets[Race, MiddleAge] < Age) then
                Dec(Scores[AbilityIndex]);
              if (Scores[AbilityIndex] > 0) and (RaceAgeBrackets[Race, OldAge] < Age) then
                Dec(Scores[AbilityIndex], 2);
              if (Scores[AbilityIndex] > 0) and (RaceAgeBrackets[Race, VenerableAge] < Age) then
                Dec(Scores[AbilityIndex]);
              if Scores[AbilityIndex] < RaceAbilityLimits[Race, B9E] then
                Scores[AbilityIndex] := RaceAbilityLimits[Race, B9E];
              if Scores[AbilityIndex] > RaceStrengthMax[Race, B9E] then
                Scores[AbilityIndex] := RaceStrengthMax[Race, B9E];
              if Scores[AbilityIndex] < ClassAbilityMinimums[ClassMask, AbilityIndex] then
                Scores[AbilityIndex] := ClassAbilityMinimums[ClassMask, AbilityIndex];
              if (Scores[StrengthIndex] = ExceptionalStrength) and (ClassLevels[FighterClass] > 0) then
              begin
                StrengthPercent := Random(ExceptionalStrengthRoll) + 1;
                if RaceStrengthPercent[Race, B9E] < StrengthPercent then
                  StrengthPercent := RaceStrengthPercent[Race, B9E];
              end;
            end;
          IntelligenceIndex:
            begin
              if RaceAgeBrackets[Race, MiddleAge] < Age then
                Inc(Scores[AbilityIndex]);
              if RaceAgeBrackets[Race, VenerableAge] < Age then
                Inc(Scores[AbilityIndex]);
              if Scores[AbilityIndex] < RaceAbilityLimits[Race, IntMinOffset] then
                Scores[AbilityIndex] := RaceAbilityLimits[Race, IntMinOffset];
              if Scores[AbilityIndex] > RaceAbilityLimits[Race, IntMaxOffset] then
                Scores[AbilityIndex] := RaceAbilityLimits[Race, IntMaxOffset];
              if Scores[AbilityIndex] < ClassAbilityMinimums[ClassMask, AbilityIndex] then
                Scores[AbilityIndex] := ClassAbilityMinimums[ClassMask, AbilityIndex];
            end;
          WisdomIndex:
            begin
              if RaceAgeBrackets[Race, YoungAdultAge] >= Age then
                Dec(Scores[AbilityIndex]);
              if RaceAgeBrackets[Race, MiddleAge] < Age then
                Inc(Scores[AbilityIndex]);
              if RaceAgeBrackets[Race, OldAge] < Age then
                Inc(Scores[AbilityIndex]);
              if RaceAgeBrackets[Race, VenerableAge] < Age then
                Inc(Scores[AbilityIndex]);
              if Scores[AbilityIndex] < RaceAbilityLimits[Race, WisMinOffset] then
                Scores[AbilityIndex] := RaceAbilityLimits[Race, WisMinOffset];
              if Scores[AbilityIndex] > RaceAbilityLimits[Race, WisMaxOffset] then
                Scores[AbilityIndex] := RaceAbilityLimits[Race, WisMaxOffset];
              if Scores[AbilityIndex] < ClassAbilityMinimums[ClassMask, AbilityIndex] then
                Scores[AbilityIndex] := ClassAbilityMinimums[ClassMask, AbilityIndex];
              if (Scores[AbilityIndex] < MinClericWisdom) and (ClassMask in [ClericFighter..ClericThief]) then
                Scores[AbilityIndex] := MinClericWisdom;
            end;
          DexterityIndex:
            begin
              if RaceAgeBrackets[Race, OldAge] < Age then
                Dec(Scores[AbilityIndex], 2);
              if RaceAgeBrackets[Race, VenerableAge] < Age then
                Dec(Scores[AbilityIndex]);
              if Scores[AbilityIndex] < RaceAbilityLimits[Race, DexMinOffset] then
                Scores[AbilityIndex] := RaceAbilityLimits[Race, DexMinOffset];
              if Scores[AbilityIndex] > RaceAbilityLimits[Race, DexMaxOffset] then
                Scores[AbilityIndex] := RaceAbilityLimits[Race, DexMaxOffset];
              if Scores[AbilityIndex] < ClassAbilityMinimums[ClassMask, AbilityIndex] then
                Scores[AbilityIndex] := ClassAbilityMinimums[ClassMask, AbilityIndex];
            end;
          ConstitutionIndex:
            begin
              if RaceAgeBrackets[Race, MiddleAge] < Age then
                Dec(Scores[AbilityIndex]);
              if RaceAgeBrackets[Race, OldAge] < Age then
                Dec(Scores[AbilityIndex]);
              if RaceAgeBrackets[Race, VenerableAge] < Age then
                Dec(Scores[AbilityIndex]);
              if Scores[AbilityIndex] < RaceAbilityLimits[Race, ConMinOffset] then
                Scores[AbilityIndex] := RaceAbilityLimits[Race, ConMinOffset];
              if Scores[AbilityIndex] > RaceAbilityLimits[Race, ConMaxOffset] then
                Scores[AbilityIndex] := RaceAbilityLimits[Race, ConMaxOffset];
              if Scores[AbilityIndex] < ClassAbilityMinimums[ClassMask, AbilityIndex] then
                Scores[AbilityIndex] := ClassAbilityMinimums[ClassMask, AbilityIndex];
            end;
          CharismaIndex:
            begin
              if Scores[AbilityIndex] < RaceAbilityLimits[Race, ChaMinOffset] then
                Scores[AbilityIndex] := RaceAbilityLimits[Race, ChaMinOffset];
              if Scores[AbilityIndex] > RaceAbilityLimits[Race, ChaMaxOffset] then
                Scores[AbilityIndex] := RaceAbilityLimits[Race, ChaMaxOffset];
              if Scores[AbilityIndex] < ClassAbilityMinimums[ClassMask, AbilityIndex] then
                Scores[AbilityIndex] := ClassAbilityMinimums[ClassMask, AbilityIndex];
            end;
        end;
      ShowAbilityScore(AbilityIndex, False);
    end;
    with NewCharacter^ do
    begin
      Flag11B := HpMax;
      Attacks := StartAttacks;
      BaseAttacks[1] := 1;
      BaseDamage[1] := StartBaseDamage;
      StrengthBonusFlag := 1;
      BaseMovement := StartMovement;
      GoldDiceTotal := 0;
      ClassTotal := 0;
      for ClassIndex := 0 to ClassTypeCount - 1 do
        if ClassLevels[ClassIndex] > 0 then
        begin
          case ClassIndex of
            ClericClass: SpellSlots[0, 1] := 1;
            MageClass: SpellSlots[1, 1] := 1;
          end;
          Inc(GoldDiceTotal, RollDice(StartingGoldDice[ClassIndex, 0], StartingGoldDice[ClassIndex, 1]));
          Inc(ClassTotal);
          case ClassIndex of
            ClericClass:
              begin
                AddWisdomBonusSpells(NewCharacter);
                for I := 1 to SpellCount do
                  with SpellTable[I] do
                    if (SpellClass = 0) and (Level = 1) then
                      KnownSpells[I] := 1;
              end;
            MageClass:
              begin
                KnownSpells[SpellDetectMagic] := 1;
                KnownSpells[SpellReadMagic] := 1;
                KnownSpells[SpellShield] := 1;
                KnownSpells[SpellSleep] := 1;
              end;
          end;
        end;
      Money[Ord(GoldCoin)] := GoldDiceTotal * 10 div ClassTotal;
      HpB1 := RollHitPoints(NewCharacter, $FF);
      HpMax := HpB1;
      ConAdjustment := ConstitutionHitPointAdjustment(NewCharacter);
      if ConAdjustment < 0 then
      begin
        if HpMax > Abs(ConAdjustment) + ClassTotal then
          HpMax := (HpMax + ConAdjustment) div ClassTotal
        else
          HpMax := 1;
      end
      else
        HpMax := (HpMax + ConAdjustment) div ClassTotal;
      Flag11B := HpMax;
      HpB1 := HpB1 div ClassTotal;
    end;
    ShowCombatStats;
    ShowCharacterMoney;
    Key := AskYesNo('Keep this character? ', PromptTitleColour, PromptWordColour, PromptHotColour);
  until Key = KeepAnswer;
  ShowCharacterSheet;
  SelectedCharacter := SavedSelection;
  repeat
    NewCharacter^.Name := ReadInputLine('Character name: ', NamePromptColour, NameMaxLength);
  until Length(NewCharacter^.Name) <> 0;
  SavedSelection := SelectedCharacter;
  SelectedCharacter := NewCharacter;
  ChooseHeadAndBody;
  EditCharacterIcon;
  SaveCharacter(NewCharacter, '');
  SelectedCharacter := SavedSelection;
  FreeMem(NewCharacter, CharacterSize);
end;
{ ovl16:1F37. Drops the selected character from the party, the D function of the training-hall menu
  (RunCharacterMenu, ovl16:0161, whose 'Drop' item dispatches it). It asks AskYesNo "Drop <name>
  forever? " and, only when that is answered Y, a second AskYesNo "Are you sure? ". A no at either
  prompt shows the flash message "<name> breathes a sigh of relief." and does nothing else.
  Otherwise it shows "<name> bids you farewell." when the character still counts for combat and
  experience (Flag10D set; whitepaper 5.8) or "You dump <name> out back." when it does not, then
  removes it from the party through RemoveSelectedCharacter(False, True). No parameters; reads the global
  SelectedCharacter (nothing happens while it is nil); side effects: a flash message and the drop. }
procedure DropCharacter;
var
  Unused: Byte;      { [bp-1]: never read; the original frame carries this spare byte }
begin
  if SelectedCharacter = nil then Exit;
  with SelectedCharacter^ do
  begin
    if (AskYesNo('Drop ' + Name + ' forever? ', $E, $A, $F) = 'Y')
       and (AskYesNo('Are you sure? ', $E, $A, $F) = 'Y') then
    begin
      if Flag10D = 0 then
        ShowFlashMessage('You dump ' + Name + ' out back.')
      else
        ShowFlashMessage(Name + ' bids you farewell.');
      RemoveSelectedCharacter(False, True);
    end
    else
      ShowFlashMessage(Name + ' breathes a sigh of relief.');
  end;
end;
{ ovl16:209F. The Modify (M) function of the training hall, dispatched by RunCharacterMenu
  (ovl16:0161). It refuses a character that already has experience ('<name> can''t be modified.',
  FlashMessageLine), else draws the character sheet and lets the player raise or lower the six
  ability scores and the hit points. The arrow keys move the cursor (Down/Up through Strength
  ..Charisma and the hit-point line) and adjust the value under it (Right raises, Left lowers); a
  value is held between the per-race limits (RaceAbilityLimits) and the per-class minimum (ClassAbilityMinimums), a Wisdom
  change recomputes the cleric bonus spells (AddWisdomBonusSpells), and a hit-point change is
  bounded by fn_3FB3 (floor) and fn_408C (ceiling). 'K' (Keep) accepts the changes and leaves, 'E'
  (Exit, or Escape) restores the saved abilities. The nested ShowStat (ovl16:2033) redraws the
  value under the cursor. A `with SelectedCharacter^` block edits the modified character; its
  Experience, Scores (+$10), StrengthPercent, HpMax, Flag11B, Race, ClassMask, B9E, ClassLevels,
  SpellSlots and HirelingShare are used. }
procedure ModifyCharacter;
const
  AbilityCount = 6;             { Strength..Charisma; the cursor's HitPointIndex is the extra step }
  HitPointIndex = 6;            { the hit-point line below Charisma }
  { The BIOS scan codes ReadPromptChoice returns with ExtKey set for the four arrows. }
  ScanUp = #$48;
  ScanDown = #$50;
  ScanLeft = #$4B;
  ScanRight = #$4D;
  KeyEnter = #13;
  KeyKeep = 'K';                { the 'Keep' word of the prompt: accept the changes }
  KeyExit = 'E';                { the 'Exit' word of the prompt: restore the saved abilities }
  KeyNone = #0;                 { what Escape returns }
  { The prompt line (ReadPromptChoice of ovl25): its title, word and hotkey colours; ExtKeys = 1
    accepts the arrow keys. }
  PromptTitleColour = $D;
  PromptWordColour = $A;
  PromptHotColour = $F;
  AcceptExtendedKeys = 1;
  MessageColour = $E;           { the flash message on an experienced character }
  { the hit-point line the cursor's last step shows (DrawHitPoints of res12) }
  HitPointColumn = 4;
  HitPointRow = $12;
  FighterClass = 2;             { only a fighter raises the Strength percentile }
var
  SavedScores: array[0..5] of Byte;   { [bp-6..bp-1]: the scores as they were on entry }
  SavedStrengthPercent: Byte;         { [bp-7]: the exceptional Strength on entry }
  SavedHpMax: Byte;                   { [bp-8]: the maximum hit points on entry }
  Spare: Byte;                        { [bp-9]: the original frame reserves this byte, never read }
  Stat: ShortInt;                     { [bp-0xa]: the ability under the cursor / the restore loop }
  Key: Char;                          { [bp-0xb]: the key ReadPromptChoice returned }
  ExtKey: Byte;                       { [bp-0xc]: nonzero when Key is an extended key }
  StatIndex: Byte;                    { [bp-0xd]: the cursor: 0..5 an ability, 6 the hit-point line }
  Spare2: array[0..6] of Byte;        { [bp-0xe..bp-0x14]: the original frame reserves these, never read }

  { ovl16:2033 (nested). Redraws the value under the cursor: ability StatIndex through
    ShowAbilityScore (ovl19:0901), or the hit-point line through DrawHitPoints (00BA:0973) when
    StatIndex is HitPointIndex. Highlight is passed to both (false clears the highlight). It reads
    the parent's StatIndex and the global SelectedCharacter. }
  procedure ShowStat(Highlight: Boolean);
  begin
    if StatIndex < AbilityCount then
      ShowAbilityScore(StatIndex, Highlight)
    else
      DrawHitPoints(SelectedCharacter, HitPointColumn, HitPointRow, Byte(Highlight));
  end;

begin
  if SelectedCharacter^.Experience > 0 then
  begin
    FlashMessageLine(SelectedCharacter^.Name + ' can''t be modified.', MessageColour);
    Exit;
  end;
  ShowCharacterSheet;
  Move(PScoredCharacter(SelectedCharacter)^.Scores, SavedScores, AbilityCount);
  SavedStrengthPercent := SelectedCharacter^.StrengthPercent;
  SavedHpMax := SelectedCharacter^.HpMax;
  StatIndex := HitPointIndex;
  ShowStat(False);
  StatIndex := 0;
  ShowStat(True);
  with PScoredCharacter(SelectedCharacter)^ do
  begin
    repeat
    Key := ReadPromptChoice('Modify character: ', 'Keep Exit',
      PromptTitleColour, PromptWordColour, PromptHotColour, AcceptExtendedKeys, 0, ExtKey);
    ShowStat(False);
    if ExtKey <> 0 then
    begin
      case Key of
        ScanDown, KeyEnter:
        begin
          Inc(StatIndex);
          if StatIndex > HitPointIndex then
            StatIndex := 0;
        end;
        ScanUp:
        begin
          Dec(StatIndex);
          if StatIndex = $FF then
            StatIndex := HitPointIndex;
        end;
        ScanLeft:
        begin
          if StatIndex < AbilityCount then
          begin
            Stat := StatIndex;
            Dec(Scores[Stat]);
            case Stat of
              0:
                if StrengthPercent > 0 then
                begin
                  Dec(StrengthPercent);
                  Inc(Scores[Stat]);
                end
                else if (Scores[Stat] < RaceAbilityLimits[Race, B9E])
                     or (Scores[Stat] < ClassAbilityMinimums[ClassMask, 0]) then
                  Scores[Stat] := RaceAbilityLimits[Race, B9E];
              1:
                if (Scores[Stat] < RaceAbilityLimits[Race, IntMinOffset])
                   or (Scores[Stat] < ClassAbilityMinimums[ClassMask, 1]) then
                  Scores[Stat] := RaceAbilityLimits[Race, IntMinOffset];
              2:
                begin
                  if (Scores[Stat] < RaceAbilityLimits[Race, WisMinOffset])
                     or (Scores[Stat] < ClassAbilityMinimums[ClassMask, 2]) then
                    Scores[Stat] := RaceAbilityLimits[Race, WisMinOffset];
                  if SpellSlots[0, 1] > 0 then
                    SpellSlots[0, 1] := 1;
                  AddWisdomBonusSpells(SelectedCharacter);
                end;
              3:
                if (Scores[Stat] < RaceAbilityLimits[Race, DexMinOffset])
                   or (Scores[Stat] < ClassAbilityMinimums[ClassMask, 3]) then
                  Scores[Stat] := RaceAbilityLimits[Race, DexMinOffset];
              4:
                begin
                  if (Scores[Stat] < RaceAbilityLimits[Race, ConMinOffset])
                     or (Scores[Stat] < ClassAbilityMinimums[ClassMask, 4]) then
                    Scores[Stat] := RaceAbilityLimits[Race, ConMinOffset];
                  if MaxHitPoints(SelectedCharacter) < HpMax then
                    HpMax := MaxHitPoints(SelectedCharacter);
                  Flag11B := HpMax;
                  StatIndex := HitPointIndex;
                  ShowStat(False);
                  StatIndex := 4;
                end;
              5:
                if (Scores[Stat] < RaceAbilityLimits[Race, ChaMinOffset])
                   or (Scores[Stat] < ClassAbilityMinimums[ClassMask, 5]) then
                  Scores[Stat] := RaceAbilityLimits[Race, ChaMinOffset];
            end;
          end
        else
        begin
          Dec(HpMax);
          if MinHitPoints(SelectedCharacter) > HpMax then
            HpMax := MinHitPoints(SelectedCharacter);
          Flag11B := HpMax;
        end;
      end;
        ScanRight:
        begin
          if StatIndex < AbilityCount then
          begin
            Stat := StatIndex;
            Inc(Scores[Stat]);
            case Stat of
              0:
                if Scores[Stat] > RaceStrengthMax[Race, B9E] then
                begin
                  if (Scores[Stat] > ExceptionalStrength)
                     and (ClassLevels[FighterClass] > 0)
                     and (RaceStrengthPercent[Race, B9E] > StrengthPercent) then
                    Inc(StrengthPercent);
                  Scores[Stat] := RaceStrengthMax[Race, B9E];
                end;
              1:
                if Scores[Stat] > RaceAbilityLimits[Race, IntMaxOffset] then
                  Scores[Stat] := RaceAbilityLimits[Race, IntMaxOffset];
              2:
                begin
                  if Scores[Stat] > RaceAbilityLimits[Race, WisMaxOffset] then
                    Scores[Stat] := RaceAbilityLimits[Race, WisMaxOffset];
                  if SpellSlots[0, 1] > 0 then
                    SpellSlots[0, 1] := 1;
                  AddWisdomBonusSpells(SelectedCharacter);
                end;
              3:
                if Scores[Stat] > RaceAbilityLimits[Race, DexMaxOffset] then
                  Scores[Stat] := RaceAbilityLimits[Race, DexMaxOffset];
              4:
                begin
                  if Scores[Stat] > RaceAbilityLimits[Race, ConMaxOffset] then
                    Scores[Stat] := RaceAbilityLimits[Race, ConMaxOffset];
                  if MinHitPoints(SelectedCharacter) > HpMax then
                    HpMax := MinHitPoints(SelectedCharacter);
                  Flag11B := HpMax;
                  StatIndex := HitPointIndex;
                  ShowStat(False);
                  StatIndex := 4;
                end;
              5:
                if Scores[Stat] > RaceAbilityLimits[Race, ChaMaxOffset] then
                  Scores[Stat] := RaceAbilityLimits[Race, ChaMaxOffset];
            end;
          end
          else
          begin
            Inc(HpMax);
            if MaxHitPoints(SelectedCharacter) < HpMax then
              HpMax := MaxHitPoints(SelectedCharacter);
            Flag11B := HpMax;
          end;
      end;
      end;
    end
    else
      case Key of
        KeyExit, KeyNone:
        begin
          for Stat := 0 to AbilityCount - 1 do
            PScoredCharacter(SelectedCharacter)^.Scores[Stat] := SavedScores[Stat];
          SelectedCharacter^.StrengthPercent := SavedStrengthPercent;
          SelectedCharacter^.HpMax := SavedHpMax;
          SelectedCharacter^.Flag11B := HpMax;
          RecalcCombatValues(SelectedCharacter);
          Exit;
        end;
      end;
    RecalcCombatValues(SelectedCharacter);
    ShowCombatStats;
    ShowStat(True);
    until (ExtKey = 0) and (Key = KeyKeep);
    SelectedCharacter^.HirelingShare := 1;
  end;
end;
{ ovl16:29AE. The Train (T) function of the training hall, dispatched by RunCharacterMenu
  (ovl16:0161) when SlotTrain (CharacterMenuSlots[3]) is present. It refuses an unconscious character (Status
  at +$10C not 0, 'we only train conscious people') and one with less than 1000 gold
  (CharacterMoneyValueInGold, 'Training costs 1000 gp.'), unless the STING cheat StingCheat is
  set (the J key, ovl16:0306). For each class with a level it adds that class's bit (ClassTrainingBits)
  and, unless the race has reached the level cap IsMaxClassLevel (res12:2F57) inlines for
  that class, marks the class trainable when Experience has reached ExperienceTable[class, level+1]
  and that threshold is above 0 (0 means the class has no further level). Experience already
  at ExperienceTable[class, level+2] is cut to one below it, so one visit raises one level. Unless
  StingCheat is set, the hall's word GameVars2^[TrainableClassesWord] (680) must share a bit with the
  character's classes and with a trainable class; only its low byte is tested. The window
  then lists the levels the character will become, AskYesNo confirms, PayGold takes the
  1000 gold, each trainable class rises by one and RecalcClassStats rebuilds the derived
  stats. Raising a class (once per class that rises) also gives back one level DrainLevels
  (ovl12:2122) took: while Pad74[$74] (the drained level count) is above 0 it subtracts
  Pad74[$75] div Pad74[$74] hit points from Pad74[$75] (the hit points lost with them,
  CastRestoration in ovl22) and decrements Pad74[$74] [I] (ovl12 and ovl22 are the evidence
  for the two fields). A magic-user who rose (class 5) picks one spell
  (ChooseSpellFromList, list kind 4, 'to choose from') and marks it known. The hit points
  gained are RollHitPoints of the trained classes, shared across every class with a level,
  with a floor of 1, added to HpB1 (+$B1) and, after the constitution adjustment, to HpMax;
  Flag11B (the current hit points) keeps the same gap below HpMax. No parameters. Globals:
  SelectedCharacter, StingCheat, ClassTrainingBits, ExperienceTable, GameVars2, ClassNames. Side effects: the function
  window, the flash line, the character's experience, levels, spells, hit points and money.
  QUIRK ovl16:2CDA: the first refusal's Exit is followed by a jump the compiler keeps, the
  skip of the else branch, which nothing reaches.
  QUIRK ovl16:2F95: the `KnownSpells[ChosenSpell] := 1` after the magic-user rise also runs if
  the repeat ended because Listed = 0 with ChosenSpell = 0; KnownSpells is declared index 1..$38
  (+$33..+$6A), so index 0 is the byte at +$32, HpMax, and HpMax becomes 1 before the hit-point
  gain is added (range checks are off in this build). Whether Listed = 0 can be reached is for
  ChooseSpellFromList (ovl19) to say. }
procedure TrainCharacter;
const
  MessageColour = $E;           { yellow: the flash messages of the refusals }
  TrainCost = 1000;             { the gold pieces the training costs }
  PromptTitleColour = $D;       { the AskYesNo title colour }
  PromptWordColour = $A;
  PromptHotColour = $F;
  BecomeTextCol = 6;            { the column of the becoming lines }
  BecomeTextColour = $A;        { green }
  NameRow = 4;                  { DrawCharacterName's row; the first class line is the next }
  FirstBecomeRow = 5;
  NameCol = 4;                  { DrawCharacterName's column; its mode argument is 0 }
  ClericClass = 0;              { ClassLevels index; a half-elf cleric caps at 5 }
  FighterClass = 2;             { the class the racial level caps apply to }
  MageClass = 5;                { a rise here asks for a new spell }
  { TCharacter.Pad74 index of the drained-level state the class rise restores (the routine comment). }
  DrainedLevels = $74;          { the count of levels DrainLevels (ovl12:2122) drained }
  LostHitPoints = $75;          { the hit points lost with them (CastRestoration, ovl22) }
  SpellListToChoose = 4;        { ChooseSpellFromList's 'to choose from' list (ovl19:299C) }
  SpellDisplayMode = 4;         { the display mode the call pushes; ovl22 reads it }
  NoSpellChoice = $FFFF;        { negative, so ChooseSpellFromList opens the spell window }
  Strength17 = 17;              { the strength that raises a race's fighter cap by one }
  Strength18 = 18;              { a gnome fighter's cap looks at strength below 18 }
  RaceDwarf = 1;                { RaceNames: Dwarf, Elf, Gnome, Half-Elf, Halfling (DS:0F03) }
  RaceElf = 2;
  RaceGnome = 3;
  RaceHalfElf = 4;
  RaceHalfling = 5;
var
  AtLimit: Byte;                { [bp-1]: the class is at its racial level limit }
  NewExperience: LongInt;       { [bp-5]: the experience the training leaves the character at }
  ClassXp: LongInt;             { [bp-9]: a class's ExperienceTable threshold }
  TrainableBits: Byte;          { [bp-0xa]: the class bits with enough experience to train }
  ClassBitMask: Byte;           { [bp-0xb]: the class bits of every class with a level above 0 }
  AllowedBits: Byte;            { [bp-0xc]: the class bits the training may raise }
  TrainedCount: Byte;           { [bp-0xd]: the classes with a level (the hit points are shared) }
  HpRoll: Integer;              { [bp-0xf]: RollHitPoints' roll, signed so the divide is idiv }
  HpGain: Integer;              { [bp-0x11]: the hit points the rise adds }
  SavedHp: Byte;                { [bp-0x12]: the hit points of the class levels before the rise }
  I: ShortInt;                  { [bp-0x13]: the class loop }
  ConBonus: Integer;            { [bp-0x15]: ConstitutionHitPointAdjustment, sign-extended }
  Row: Byte;                    { [bp-0x16]: the text row of the becoming list }
  SavedMageLevel: ShortInt;     { [bp-0x17]: ClassLevels[5] before the rise }
  Level: ShortInt;              { [bp-0x18]: ClassLevels[I]; Succ of it indexes ExperienceTable }
  ChosenSpell: Byte;            { [bp-0x19]: the spell ChooseSpellFromList returned }
  Choice: Word;                 { [bp-0x1b]: ChooseSpellFromList's choice }
  Listed: Byte;                 { [bp-0x1c]: ChooseSpellFromList's listed flag }
  Spare: Byte;                  { [bp-0x1d]: the original frame reserves this byte, never read }
begin
  if (SelectedCharacter^.Status <> 0) and (StingCheat = 0) then
  begin
    FlashMessageLine('we only train conscious people', MessageColour);
    Exit;
  end;
  if (CharacterMoneyValueInGold(SelectedCharacter) < TrainCost) and (StingCheat = 0) then
  begin
    FlashMessageLine('Training costs 1000 gp.', MessageColour);
    Exit;
  end;
  TrainableBits := 0;
  ClassBitMask := 0;
  with SelectedCharacter^ do
  begin
    NewExperience := 0;
    for I := 0 to 7 do
      if ClassLevels[I] > 0 then
      begin
        Inc(ClassBitMask, ClassTrainingBits[I]);
        AtLimit := 0;
        Level := ClassLevels[I];
        case Race of
          RaceDwarf:
            if I = FighterClass then
              if ((Level = 8) and (Strength = Strength17)) or
                 ((Level = 7) and (Strength < Strength17)) then
                AtLimit := 1;
          RaceElf:
            if I = FighterClass then
              if (Level = 7) or ((Level = 6) and (Strength = Strength17))
                 or ((Level = 5) and (Strength < Strength17)) then
                AtLimit := 1;
          RaceGnome:
            if I = FighterClass then
              if (Level = 6) or ((Level = 5) and (Strength < Strength18)) then
                AtLimit := 1;
          RaceHalfElf:
            if (I = ClericClass) and (Level = 5) then
              AtLimit := 1
            else if I = FighterClass then
              if (Level = 8) or ((Level = 7) and (Strength = Strength17))
                 or ((Level = 6) and (Strength < Strength17)) then
                AtLimit := 1;
          RaceHalfling:
            if I = FighterClass then
              if (Level = 6) or ((Level = 5) and (Strength = Strength17))
                 or ((Level = 4) and (Strength < Strength17)) then
                AtLimit := 1;
        end;
        if AtLimit = 0 then
          if (ExperienceTable[I, Succ(Level)] <= Experience) or (StingCheat <> 0) then
            if ExperienceTable[I, Succ(Level)] > 0 then
            begin
              Inc(TrainableBits, ClassTrainingBits[I]);
              ClassXp := ExperienceTable[I, Succ(Succ(Level))];
              if (ClassXp > 0) and (Experience >= ClassXp) and (ClassXp > NewExperience) then
                NewExperience := ClassXp - 1;
            end;
      end;
    if NewExperience > 0 then
      Experience := NewExperience;
    if StingCheat = 0 then
    begin
      if Byte(GameVars2^[TrainableClassesWord] and ClassBitMask) = 0 then
      begin
        FlashMessageLine('We don''t train that class here', MessageColour);
        Exit;
      end
      else if Byte(GameVars2^[TrainableClassesWord] and TrainableBits) = 0 then
      begin
        FlashMessageLine('Not Enough Experience', MessageColour);
        Exit;
      end;
    end;
    if StingCheat = 0 then
      AllowedBits := Byte(GameVars2^[TrainableClassesWord] and TrainableBits)
    else
      AllowedBits := TrainableBits;
    ClearWindow(MenuLeft, MenuTop, MenuRight, MenuBottom);
    Row := NameRow;
    DrawCharacterName(SelectedCharacter, NameCol, Row, 0);
    DrawTextAt(Length(Name) + 4, Row, BecomeTextColour, ' will become:');
    for I := 0 to 7 do
      if (ClassLevels[I] > 0) and ((ClassTrainingBits[I] and AllowedBits) > 0) then
      begin
        Inc(Row);
        if Row = FirstBecomeRow then
          DrawTextAt(BecomeTextCol, Row, BecomeTextColour,
            '    a level ' + ByteToText(ClassLevels[I] + 1) + ' ' + ClassNames[I])
        else
          DrawTextAt(BecomeTextCol, Row, BecomeTextColour,
            'and a level ' + ByteToText(ClassLevels[I] + 1) + ' ' + ClassNames[I]);
      end;
    if AskYesNo('Do you wish to train? ', PromptTitleColour, PromptWordColour,
      PromptHotColour) <> 'Y' then
      Exit;
    ShowFlashMessage('Congratulations...');
    if StingCheat = 0 then
      PayGold(TrainCost, SelectedCharacter);
    TrainedCount := 0;
    SavedMageLevel := ClassLevels[MageClass];
    for I := 0 to 7 do
      if ClassLevels[I] > 0 then
      begin
        Inc(TrainedCount);
        if (ClassTrainingBits[I] and AllowedBits) > 0 then
        begin
          Inc(ClassLevels[I]);
          { the rise also restores one level DrainLevels (ovl12:2122) took: give back that
            level's share of the lost hit points and drop the count of drained levels [I] }
          if Pad74[DrainedLevels] > 0 then
          begin
            Dec(Pad74[LostHitPoints], Pad74[LostHitPoints] div Pad74[DrainedLevels]);
            Dec(Pad74[DrainedLevels]);
          end;
        end;
      end;
    RecalcClassStats(SelectedCharacter);
    if ClassLevels[MageClass] > SavedMageLevel then
    begin
      Choice := NoSpellChoice;
      repeat
        ChosenSpell := ChooseSpellFromList(SpellListToChoose, SpellDisplayMode, Choice, Listed);
      until (ChosenSpell > 0) or (Listed = 0);
      { QUIRK ovl16:2F95: also runs if Listed = 0 chose no spell, then ChosenSpell 0 writes HpMax
        (+$32) because KnownSpells is declared [1..$38], so index 0 is the byte below it }
      KnownSpells[ChosenSpell] := 1;
    end;
    HpRoll := RollHitPoints(SelectedCharacter, AllowedBits);
    HpGain := HpRoll div TrainedCount;
    if HpGain = 0 then
      HpGain := 1;
    Inc(HpB1, HpGain);
    ConBonus := ConstitutionHitPointAdjustment(SelectedCharacter);
    HpGain := (HpRoll + ConBonus) div TrainedCount;
    if HpGain < 1 then
      HpGain := 1;
    SavedHp := HpMax - Flag11B;
    Inc(HpMax, HpGain);
    Flag11B := HpMax - SavedHp;
  end;
end;
{ ovl16:306D. The Add (A) function of the training hall, dispatched by RunCharacterMenu (ovl16:0161):
  it clears the function window, lists the saved characters on disk (ReadSavedCharacterList) and runs
  the menu "Add a character: " with "Add Exit" (ChooseFromList). Enter or A loads the highlighted
  character's record (GetMem, LoadCharacterFile) and, when its menu line does not already start with
  '*', prefixes '* ' and tries to put it in the party. A character already in the party (same Name and
  BAB, +$AB) is refused; a player-run member (B84 below $80) is refused once six are in the party, and
  a computer-run member (B84 $80 and up, a hireling) once the party size GameVars2^[VarPartySize] is
  eight. A refused record is freed (FreeMem); the party records themselves are freed elsewhere. The
  menu repeats until E, Escape or a full party. The edited list is written back
  (RewriteSavedCharacterList, ovl17) and freed (FreeMenuList, ovl25). No parameters; side effects: the
  function window, the menu, the heap and the saved-character list file.
  QUIRK ovl16:30E8: the ChooseFromList WithExit argument is read from [bp-0x14], a local the routine
  never assigns (whatever the previous frame left there). }
procedure AddSavedCharacters;
const
  VarPartySize = 830;           { the party member count, a word of the GameVars2 game variable block }
  ComputerRun = $80;            { high bit of B84: the computer runs the member (hireling) }
  MaxPlayerMembers = 6;         { the menu stops once six player-run members are in the party }
  MaxPartySize = 8;             { the menu stops once the party holds eight members }
  KeyEnter = #13;               { ChooseFromList returns Enter, or the chosen word's letter }
  KeyAdd = 'A';                 { the 'Add' word of the prompt }
  KeyExit = 'E';                { the 'Exit' word of the prompt; Escape returns #0 }
var
  List: PMenuLine;              { [bp-4]: the saved-character list ReadSavedCharacterList built }
  Selected: PMenuLine;          { [bp-8]: the highlighted line of that list }
  NewChar: PCharacter;          { [bp-0xc]: the record GetMem allocated for the chosen character }
  Who: PCharacter;              { [bp-0x10]: the party list walk }
  Choice: Integer;              { [bp-0x12]: ChooseFromList's var Choice }
  Key: Char;                    { [bp-0x13]: the key ChooseFromList returned }
  WithExit: Byte;               { [bp-0x14]: ChooseFromList's WithExit (QUIRK: never assigned) }
  Redraw: Byte;                 { [bp-0x15]: ChooseFromList's var Redraw }
  Count: Byte;                  { [bp-0x16]: the player-run members found in the party list }
begin
  ClearWindow(1, 1, $26, $16);
  ReadSavedCharacterList(List);
  if List = nil then Exit;
  Choice := 0;
  Selected := List;
  Redraw := 1;
  repeat
    Key := ChooseFromList('Add a character: ', 'Add Exit', $D, $A, $F, 1, 2, $26, $16,
      List, WithExit, Redraw, Choice, Selected);
    if (Key = KeyEnter) or (Key = KeyAdd) then
      if Selected^.Text[1] <> '*' then
      begin
        GetMem(NewChar, CharacterSize);
        LoadCharacterFile(Selected^.Text, NewChar, 0, 1);
        Selected^.Text := '* ' + Selected^.Text;
        Count := 0;
        if PCharacter(PartyListHead) = nil then
        begin
          GameVars2^[VarPartySize] := 0;
          AddPartyMember(NewChar);
          BuildCharacterIcon(True);
        end
        else
        begin
          Who := PCharacter(PartyListHead);
          while (Who <> nil)
                and ((Who^.Name <> NewChar^.Name) or (Who^.BAB <> NewChar^.BAB)) do
          begin
            if Who^.B84 < ComputerRun then
              Inc(Count);
            Who := Who^.Next;
          end;
          if (Who = nil)
             and (((NewChar^.B84 < ComputerRun) and (Count < MaxPlayerMembers))
                  or ((NewChar^.B84 > ComputerRun - 1)
                      and (GameVars2^[VarPartySize] < MaxPartySize))) then
          begin
            AddPartyMember(NewChar);
            BuildCharacterIcon(True);
            if NewChar^.B84 < ComputerRun then
              Inc(Count);
          end
          else
            FreeMem(NewChar, CharacterSize);
        end;
      end;
  until (Key = KeyExit) or (Key = #0) or (Count > MaxPlayerMembers - 1)
    or (GameVars2^[VarPartySize] > MaxPartySize - 1);
  RewriteSavedCharacterList(List);
  FreeMenuList(List);
end;
{ ovl16:3291. Removes a character from the party list (the head is PartyListHead, linked by TCharacter.Next
  at +$104) and frees its record. It walks the list from the head to the member before
  SelectedCharacter (or finds SelectedCharacter itself at the head). When Uncounted is false (the
  member counted in the party size), it lowers the party size GameVars2^[VarPartySize]; an extra combatant
  passes Uncounted true and leaves the count alone. FreePicture frees the member's combat icon picture
  slot (CombatIcon, +$BF) first. The head is replaced by its Next; a middle member is unlinked from its
  predecessor, and SelectedCharacter becomes the member that took its place (its successor at the head,
  its predecessor otherwise). Called on drop, load, battle removal and party reorder. }
procedure RemoveSelectedCharacter(Uncounted, FreePicture: Boolean);
const
  VarPartySize = 830;   { the party member count, a word of the GameVars2 game variable block }
var
  Cur: PCharacter;      { [bp-4]: the list node examined; the predecessor when the member is found }
begin
  if PCharacter(PartyListHead) = nil then Exit;
  Cur := PCharacter(PartyListHead);
  if Cur <> SelectedCharacter then
  begin
    while (Cur^.Next <> SelectedCharacter) and (Cur^.Next <> nil) do
      Cur := Cur^.Next;
    if Cur^.Next <> nil then
    begin
      if FreePicture then
        FreePictureSlot(SelectedCharacter^.CombatIcon);
      Cur^.Next := SelectedCharacter^.Next;
      FreeCharacter(SelectedCharacter);
      SelectedCharacter := Cur;
      if not Uncounted then
        Dec(GameVars2^[VarPartySize]);
    end;
  end
  else
  begin
    if FreePicture then
      FreePictureSlot(SelectedCharacter^.CombatIcon);
    PCharacter(PartyListHead) := SelectedCharacter^.Next;
    Cur := SelectedCharacter^.Next;
    FreeCharacter(SelectedCharacter);
    SelectedCharacter := Cur;
    if not Uncounted then
      Dec(GameVars2^[VarPartySize]);
  end;
end;
{ ovl16:33E7. The head/body step of character creation (the "Head Body Keep" prompt of the create
  flow, whitepaper 5.8): it shows the selected character's HEAD and BODY pictures (ShowHeadBodyWindow)
  and asks ReadPromptChoice for a key. H or B steps the HeadBank (+$BB) or the BodyBank (+$BC) through
  the picture numbers DS:286F and DS:287D, wrapping above $E and $C back to 1; K keeps the two banks as
  they are now. Any other key (Escape included) leaves the banks alone and shows the prompt again: only
  K leaves the loop. The banks that were current on entry are restored at the end unless the last K
  kept the current ones. No parameters; works on SelectedCharacter. Side effects: the head/body window,
  the prompt line and the two pictures. }
procedure ChooseHeadAndBody;
const
  MaxHeadBank = $E;   { the highest HeadBank the picture table DS:286F (14 entries) offers }
  MaxBodyBank = $C;   { the highest BodyBank the picture table DS:287D offers }
  { The prompt line colours (ReadPromptChoice of ovl25). }
  PromptTitleColour = 0;    { the title is empty, so its colour does not matter }
  PromptWordColour = $F;    { white: the letters of the words 'Head Body Keep' }
  PromptHotColour = $A;     { green: the words' capitals 'H', 'B', 'K' and the highlight }
  PromptExtKeys = 0;        { the extended keys are not accepted }
  PromptAnimate = 0;        { the caller does not ask for the picture animation }
var
  Key: Char;               { [bp-1]: the key ReadPromptChoice returned }
  ExtKey: Byte;            { [bp-2]: nonzero when Key is an extended key }
  SavedHeadBank: Byte;     { [bp-3]: the HeadBank that was current on entry }
  SavedBodyBank: Byte;     { [bp-4]: the BodyBank that was current on entry }
begin
  with SelectedCharacter^ do
  begin
    SavedHeadBank := HeadBank;
    SavedBodyBank := BodyBank;
    repeat
      ShowHeadBodyWindow;
      Key := ReadPromptChoice('', 'Head Body Keep', PromptTitleColour, PromptWordColour,
        PromptHotColour, PromptExtKeys, PromptAnimate, ExtKey);
      if ExtKey = 0 then
        case Key of
          'H':
            if HeadBank < MaxHeadBank then Inc(HeadBank) else HeadBank := 1;
          'B':
            if BodyBank < MaxBodyBank then Inc(BodyBank) else BodyBank := 1;
          'K':
            begin
              SavedHeadBank := HeadBank;
              SavedBodyBank := BodyBank;
            end;
        end;
    until Key = 'K';
    HeadBank := SavedHeadBank;
    BodyBank := SavedBodyBank;
  end;
  ClearPromptLine;
end;
{ ovl16:382D. The character-icon editor: the Icon function of the camp's Alter menu (AlterMenu,
  ovl15:1C59) and the last step of CreateCharacter (after ChooseHeadAndBody). No parameters; it edits
  SelectedCharacter in place: the CHEAD and CBODY picture blocks (CHeadBlock, CBodyBlock), the icon
  size (Figure[0]: 1 small, 2 large) and the six colour pairs (Figure[1..6], low nibble colour 1,
  high nibble colour 2) that BuildCharacterIcon (ovl17:0482) and CopyPictureSlot turn into the
  character's combat icon (the picture slot CombatIcon of the table PictureSlots).
  It draws the editor window, then the icon as it was on entry (icon cell row 2, caption 'old') and
  the working icon (cell row 4, caption 'new'), each with the caption 'ready   action' below it (the
  two halves DrawIconCell draws, the identical and the mirrored picture). The working icon lives in
  scratch slot WorkSlot ($C): CopyPictureSlot recolours the combat icon into it after every key.
  A prompt line (ReadPromptChoice, no title, the word list IconEditorPrompts[State]) offers the choices of the
  current State: StateMain picks Parts, color-1, color-2 or Size (Exit or Escape leaves);
  StateParts picks the Head or the Weapon picture; StateColourPart picks the part whose colour
  changes (Weapon, Body, Hair or Face, Shield, Arm, Leg); StateSize picks Small or Large; StateStep
  then steps the chosen block with Next and Prev, or the chosen colour nibble through the 16 colours.
  Keep saves the value in the Saved... locals and returns to Mode, the state it came from; Exit or
  Escape restores the saved value. Leaving StateMain restores the saved (last kept) values and
  copies the working icon back into the combat icon slot. The editor then asks AskYesNo 'Is this
  icon ok? ' and starts again on anything but Y; on a map-window area view (AreaViewKind above 1) it
  first reloads the ICON pictures 0 and 1 into slots 11 and 12 (the slots it used as scratch).
  Globals: reads and changes SelectedCharacter^ (CHeadBlock, CBodyBlock, CombatIcon, Figure) and the
  prompt lines IconEditorPrompts (the word 'xxxx' of line 3 becomes 'Hair' or 'Face'); reads AreaViewKind.
  SwapPaletteColours0And8 and RestorePaletteColours0And8 bracket the editor (palette register calls when VideoAdapter
  is 1, purpose
  unknown).
  QUIRK ovl16:39F9: ReadPromptChoice is called with ExtKeys 0, so ExtKey is always 0 and the `if
  ExtKey = 0` guard never skips the key dispatch. QUIRK ovl16:3987: the size prompt names the size
  the player can switch to: 'Small' is shown while Figure[0] is 2 (large), 'Large' otherwise. }
procedure EditCharacterIcon;
type
  TFigureColours = array[1..6] of Byte;
  TFigureBytes = record             { the character's Figure array: the size, then the six colour pairs }
    Size: Byte;
    Colours: TFigureColours;
  end;
const
  WindowLeft = 1;                 { the editor window, drawn by DrawWindow with no title }
  WindowTop = 1;
  WindowRight = $26;
  WindowBottom = $16;
  { The editor's states: the line of IconEditorPrompts the prompt shows. }
  StateMain = 1;                  { 'Parts color-1 color-2 Size Exit' }
  StateParts = 2;                 { 'Head Weapon Exit' }
  StateColourPart = 3;            { 'Weapon Body Hair Shield Arm Leg Exit' ('Face' instead of 'Hair' for color-2) }
  StateSize = 4;                  { 'Small Keep Exit' or 'Large Keep Exit' }
  StateStep = 5;                  { 'Next Prev Keep Exit' }
  ColourPromptLine = 3;           { the line of IconEditorPrompts holding the word 'xxxx' ... }
  ColourWordColumn = 13;          { ... which starts at this column ... }
  ColourWordLength = 4;           { ... and is this long ('Hair' or 'Face') }
  { The pictures. }
  WorkSlot = $C;                  { scratch picture slot of PictureSlots the editor draws the working icon from }
  ReloadedSlot = $B;              { slot 11: BuildCharacterIcon's scratch slot, reloaded with ICON picture 0 }
  OldCellRow = 2;                 { the icon cell of the icon as it was on entry }
  NewCellRow = 4;                 { the icon cell of the working icon }
  EditorCellCol = 1;
  CaptionOldCol = 8;              { 'old' and 'new', beside the cells (text columns and rows) }
  CaptionOldRow = 6;
  CaptionNewRow = $C;
  HalvesCol = 3;                  { 'ready   action', under each cell }
  HalvesOldRow = $A;
  HalvesNewRow = $10;
  CaptionColour = $F;
  { The icon's fields. }
  IconSizeSmall = 1;              { Figure[0]: the CHEAD/CBODY suffix 'S' }
  IconSizeLarge = 2;              { Figure[0]: the suffix 'T' }
  MaxHeadBlock = 13;              { CHeadBlock runs 0..13 }
  MaxBodyBlock = $1F;             { CBodyBlock runs 0..31 }
  { The Figure[1..6] colour pairs, named by the prompt word that picks them. }
  PartBody = 1;
  PartArm = 2;
  PartLeg = 3;
  PartHairFace = 4;
  PartShield = 5;
  PartWeapon = 6;
  { The prompt line (ReadPromptChoice of ovl25): title, word and hotkey colours; ExtKeys 0 and
    Animate 0. }
  PromptTitleColour = $D;
  PromptWordColour = $A;
  PromptHotColour = $F;
  { The hotkeys of the prompt words. }
  KeyEscape = #0;                 { what ReadPromptChoice returns on Escape }
  KeySpace = ' ';                 { the key the editor stores to mean 'nothing pressed' }
  KeyParts = 'P';
  KeyColour1 = '1';
  KeyColour2 = '2';
  KeySize = 'S';
  KeyHead = 'H';
  KeyWeapon = 'W';
  KeyBody = 'B';
  KeyHair = 'H';
  KeyFace = 'F';
  KeyShield = 'S';
  KeyArm = 'A';
  KeyLeg = 'L';
  KeyLarge = 'L';
  KeySmall = 'S';
  KeyNext = 'N';
  KeyPrev = 'P';
  KeyKeep = 'K';
  KeyExit = 'E';
  KeyYes = 'Y';
var
  UnusedTop: Byte;                    { [bp-1]: the original frame reserves this byte, never read }
  Key: Char;                          { [bp-2]: the key ReadPromptChoice returned }
  ExtKey: Byte;                       { [bp-3]: nonzero when Key is an extended key (the editor ignores those) }
  SavedCHeadBlock: Byte;              { [bp-4]: CHeadBlock as last kept }
  SavedCBodyBlock: Byte;              { [bp-5]: CBodyBlock as last kept }
  SavedSize: Byte;                    { [bp-6]: Figure[0] as last kept }
  SavedCombatIcon: Byte;              { [bp-7]: CombatIcon while BuildCharacterIcon builds into WorkSlot }
  State: Byte;                        { [bp-8]: the prompt line shown (StateMain..StateStep) }
  SizeName: string[5];                { [bp-0xe..bp-9]: 'Small' or 'Large' in StateSize, else empty }
  UnusedMid: Byte;                    { [bp-0xf]: the original frame reserves this byte, never read }
  SavedFigure: TFigureColours;        { [bp-0x15..bp-0x10]: Figure[1..6] as last kept }
  ColourPart: Byte;                   { [bp-0x16]: the Figure index (PartBody..PartWeapon) whose colours change }
  EditFace: Boolean;                  { [bp-0x17]: the high nibble (color-2, Face) is edited, not the low (color-1, Hair) }
  LowNibble: Byte;                    { [bp-0x18]: colour 1 of Figure[ColourPart] }
  HighNibble: Byte;                   { [bp-0x19]: colour 2 of Figure[ColourPart] }
  Mode: Byte;                         { [bp-0x1a]: the state StateStep returns to (StateParts or StateColourPart) }
  PartKey: Char;                      { [bp-0x1b]: the picture chosen in StateParts (KeyHead or KeyWeapon) }

  { ovl16:34DF (nested). Draws one cell of the editor: it fills the cell (FillPictureRect, 12 cells
    wide and 24 pixel rows tall, from the palette at @FillRectPalette into DrawBuf) and draws the two mirrored
    halves of the icon (DrawIcon) at columns CellCol and CellCol + 3, row CellRow. On the text-only
    adapter (VideoAdapter 0) the fill uses colour 3 (the icon's ground) and only the head pictures
    (index $C, WorkSlot) are drawn; on the other adapters the fill uses colour 0 and the body pictures
    (index $19) are drawn first. FlushPictureChanges shows the result. It reads nothing of the
    editor's own variables. }
  procedure DrawIconCell(CellCol, CellRow: Byte);
  const
    IconColsPerCell = 3;    { an icon cell is 3 text columns wide }
    CellWidthCells = $C;    { FillPictureRect width, in 8-pixel cells }
    CellHeightRows = $18;   { FillPictureRect height, in pixel rows }
    SecondHalfCol = 3;      { the mirrored-half icon is 3 columns right }
    GroundColour = 3;       { the icon's ground colour on VideoAdapter 0 }
    BodyPicIndex = $19;     { the BODY picture block of the icon }
    HeadPicIndex = $C;      { the HEAD picture block of the icon }
    IconSet = 0;            { the icon set DrawIcon reads the pictures from }
  begin
    if VideoAdapter = 0 then
      FillPictureRect(CellCol * IconColsPerCell, CellRow * CellHeightRows, CellWidthCells,
        CellHeightRows, GroundColour, @FillRectPalette, DrawBuf)
    else
    begin
      FillPictureRect(CellCol * IconColsPerCell, CellRow * CellHeightRows, CellWidthCells,
        CellHeightRows, 0, @FillRectPalette, DrawBuf);
      DrawIcon(CellCol, CellRow, IconSet, 0, BodyPicIndex);
      DrawIcon(CellCol + SecondHalfCol, CellRow, IconSet, 1, BodyPicIndex);
    end;
    DrawIcon(CellCol, CellRow, IconSet, 0, HeadPicIndex);
    DrawIcon(CellCol + SecondHalfCol, CellRow, IconSet, 1, HeadPicIndex);
    FlushPictureChanges;
  end;

  { ovl16:35BE (nested). Copies one picture slot of the character-icon table DS:5E5A into another:
    both halves (the identical half at FirstPic and the mirrored half at SecondPic) get their tile
    bytes (the tail at +$17) and their packed pixel bytes (the buffer Pixels points at, +$13) copied
    from Source into Dest. ByteSize (the word at +$11) gives the tile size; on the EGA adapter
    (VideoAdapter 1) the pixel buffer holds a quarter of that. When Recolor is set the copied
    destination icon is recoloured with the selected character's six colour pairs (Figure[1..6]
    through FigureColourSlots), exactly the recolouring BuildCharacterIcon (ovl17:0482) applies. The editor
    calls it with the character's CombatIcon as Source and WorkSlot as Dest (and the other way round
    at the end, without recolouring). It reads nothing of the editor's own variables. }
  procedure CopyPictureSlot(Source, Dest, Recolor: Byte);
  var
    I: Byte;                          { [bp-1]: loop index over the colour map }
    Spare: Byte;                      { [bp-2]: the original frame reserves this byte, never read }
    MapFrom: array[0..15] of Byte;    { [bp-0x12..bp-3]: the icon's source colours (the identity map) }
    MapTo: array[0..15] of Byte;      { [bp-0x22..bp-0x13]: the destination colour of each source colour }
    PixelBytes: Word;                 { [bp-0x24]: the pixel-buffer size copied }
  begin
    PixelBytes := PMemPic(PictureSlots[Dest].FirstPic)^.ByteSize;
    if VideoAdapter = 1 then
      PixelBytes := PixelBytes shr 1 shr 1;
    Move(PMemPic(PictureSlots[Source].FirstPic)^.Tail, PMemPic(PictureSlots[Dest].FirstPic)^.Tail,
      PMemPic(PictureSlots[Dest].FirstPic)^.ByteSize);
    Move(PMemPic(PictureSlots[Source].SecondPic)^.Tail, PMemPic(PictureSlots[Dest].SecondPic)^.Tail,
      PMemPic(PictureSlots[Dest].SecondPic)^.ByteSize);
    Move(PMemPic(PictureSlots[Source].FirstPic)^.Pixels^, PMemPic(PictureSlots[Dest].FirstPic)^.Pixels^, PixelBytes);
    Move(PMemPic(PictureSlots[Source].SecondPic)^.Pixels^, PMemPic(PictureSlots[Dest].SecondPic)^.Pixels^, PixelBytes);
    if Recolor <> 0 then
      with SelectedCharacter^ do
      begin
        for I := 0 to 15 do
        begin
          MapFrom[I] := I;
          MapTo[I] := I;
        end;
        for I := 1 to 6 do
        begin
          MapTo[FigureColourSlots[I]] := Figure[I] and $0F;
          MapTo[FigureColourSlots[I] + 8] := (Figure[I] and $F0) shr 4;
        end;
        RemapPictureColours(@MapFrom, @MapTo, 0, 0, PictureSlots[Dest].FirstPic);
        RemapPictureColours(@MapFrom, @MapTo, 0, 0, PictureSlots[Dest].SecondPic);
      end;
  end;

begin
  DrawWindow(WindowLeft, WindowTop, WindowRight, WindowBottom, 0, 0, '');
  SwapPaletteColours0And8;
  repeat
    BuildCharacterIcon(False);
    with SelectedCharacter^ do
    begin
      State := StateMain;
      SavedFigure := TFigureBytes(Figure).Colours;
      SavedCombatIcon := CombatIcon;
      CombatIcon := WorkSlot;
      BuildCharacterIcon(False);
      CombatIcon := SavedCombatIcon;
      SavedCHeadBlock := CHeadBlock;
      SavedCBodyBlock := CBodyBlock;
      SavedSize := Figure[0];
      CopyPictureSlot(CombatIcon, WorkSlot, 1);
      DrawIconCell(EditorCellCol, OldCellRow);
      DrawTextAt(CaptionOldCol, CaptionOldRow, CaptionColour, 'old');
      DrawTextAt(HalvesCol, HalvesOldRow, CaptionColour, 'ready   action');
      DrawTextAt(CaptionOldCol, CaptionNewRow, CaptionColour, 'new');
      DrawTextAt(HalvesCol, HalvesNewRow, CaptionColour, 'ready   action');
      repeat
        DrawIconCell(EditorCellCol, NewCellRow);
        SizeName := '';
        if State = StateSize then
          if Figure[0] = IconSizeLarge then
            SizeName := 'Small'
          else
            SizeName := 'Large';
        Key := ReadPromptChoice('', SizeName + IconEditorPrompts[State], PromptTitleColour,
          PromptWordColour, PromptHotColour, 0, 0, ExtKey);
        if ExtKey = 0 then
          case State of
            StateMain:
              begin
                Mode := StateMain;
                case Key of
                  KeyParts: State := StateParts;
                  KeyColour1:
                    begin
                      State := StateColourPart;
                      EditFace := False;
                      Delete(IconEditorPrompts[ColourPromptLine], ColourWordColumn, ColourWordLength);
                      Insert('Hair', IconEditorPrompts[ColourPromptLine], ColourWordColumn);
                    end;
                  KeyColour2:
                    begin
                      State := StateColourPart;
                      EditFace := True;
                      Delete(IconEditorPrompts[ColourPromptLine], ColourWordColumn, ColourWordLength);
                      Insert('Face', IconEditorPrompts[ColourPromptLine], ColourWordColumn);
                    end;
                  KeySize: State := StateSize;
                end;
              end;
            StateParts:
              begin
                Mode := StateParts;
                if Key in [KeyEscape, KeyExit] then
                  State := StateMain
                else
                begin
                  PartKey := Key;
                  State := StateStep;
                end;
              end;
            StateColourPart:
              begin
                Mode := StateColourPart;
                case Key of
                  KeyWeapon: ColourPart := PartWeapon;
                  KeyBody: ColourPart := PartBody;
                  KeyHair: ColourPart := PartHairFace;
                  KeyFace: ColourPart := PartHairFace;
                  KeyShield: ColourPart := PartShield;
                  KeyArm: ColourPart := PartArm;
                  KeyLeg: ColourPart := PartLeg;
                else
                  ColourPart := PartBody;
                end;
                if Key in [KeyEscape, KeyExit] then
                  State := StateMain
                else
                  State := StateStep;
              end;
            StateSize:
              begin
                case Key of
                  KeyLarge:
                    begin
                      Figure[0] := IconSizeLarge;
                      BuildCharacterIcon(False);
                    end;
                  KeySmall:
                    begin
                      Figure[0] := IconSizeSmall;
                      BuildCharacterIcon(False);
                    end;
                  KeyKeep:
                    begin
                      SavedSize := Figure[0];
                      State := StateMain;
                      Key := KeySpace;
                    end;
                  KeyExit, KeyEscape:
                    begin
                      Figure[0] := SavedSize;
                      State := StateMain;
                      Key := KeySpace;
                    end;
                end;
                BuildCharacterIcon(False);
              end;
            StateStep:
              case Mode of
                StateParts:
                  case PartKey of
                    KeyHead:
                      begin
                        case Key of
                          KeyPrev:
                            if CHeadBlock > 0 then
                              Dec(CHeadBlock)
                            else
                              CHeadBlock := MaxHeadBlock;
                          KeyNext:
                            if CHeadBlock < MaxHeadBlock then
                              Inc(CHeadBlock)
                            else
                              CHeadBlock := 0;
                          KeyKeep:
                            with SelectedCharacter^ do
                            begin
                              SavedCHeadBlock := CHeadBlock;
                              State := Mode;
                              Key := KeySpace;
                            end;
                          KeyExit, KeyEscape:
                            begin
                              CHeadBlock := SavedCHeadBlock;
                              State := Mode;
                              Key := KeySpace;
                            end;
                        end;
                        BuildCharacterIcon(False);
                      end;
                    KeyWeapon:
                      begin
                        case Key of
                          KeyPrev:
                            if CBodyBlock > 0 then
                              Dec(CBodyBlock)
                            else
                              CBodyBlock := MaxBodyBlock;
                          KeyNext:
                            if CBodyBlock < MaxBodyBlock then
                              Inc(CBodyBlock)
                            else
                              CBodyBlock := 0;
                          KeyKeep:
                            with SelectedCharacter^ do
                            begin
                              SavedCBodyBlock := CBodyBlock;
                              State := Mode;
                              Key := KeySpace;
                            end;
                          KeyExit, KeyEscape:
                            begin
                              CBodyBlock := SavedCBodyBlock;
                              State := Mode;
                              Key := KeySpace;
                            end;
                        end;
                        BuildCharacterIcon(False);
                      end;
                  end;
                StateColourPart:
                  begin
                    LowNibble := Figure[ColourPart] and $F;
                    HighNibble := (Figure[ColourPart] and $F0) shr 4;
                    case Key of
                      KeyNext:
                        begin
                          if EditFace then
                            HighNibble := (HighNibble + 1) mod 16
                          else
                            LowNibble := (LowNibble + 1) mod 16;
                          Figure[ColourPart] := (HighNibble shl 4) + LowNibble;
                        end;
                      KeyPrev:
                        begin
                          if EditFace then
                            HighNibble := (HighNibble - 1) and $F
                          else
                            LowNibble := (LowNibble - 1) and $F;
                          Figure[ColourPart] := (HighNibble shl 4) + LowNibble;
                        end;
                      KeyKeep:
                        begin
                          SavedFigure := TFigureBytes(Figure).Colours;
                          State := Mode;
                          Key := KeySpace;
                        end;
                      KeyExit, KeyEscape:
                        begin
                          TFigureBytes(Figure).Colours := SavedFigure;
                          State := Mode;
                          Key := KeySpace;
                        end;
                    end;
                  end;
              end;
          end;
        CopyPictureSlot(CombatIcon, WorkSlot, 1);
      until (Mode = StateMain) and (Key in [KeyEscape, KeyExit]);
      CHeadBlock := SavedCHeadBlock;
      CBodyBlock := SavedCBodyBlock;
      Figure[0] := SavedSize;
      TFigureBytes(Figure).Colours := SavedFigure;
      CopyPictureSlot(CombatIcon, WorkSlot, 1);
      CopyPictureSlot(WorkSlot, CombatIcon, 0);
    end;
    ClearPromptLine;
    FreePictureSlot(WorkSlot);
    if AreaViewKind > 1 then
    begin
      LoadPictureSlot('ICON', 0, ReloadedSlot);
      LoadPictureSlot('ICON', 1, WorkSlot);
    end;
    Key := AskYesNo('Is this icon ok? ', PromptTitleColour, PromptWordColour, PromptHotColour);
  until Key = KeyYes;
  RestorePaletteColours0And8;
end;
{ ovl16:3F31. The constitution hit-point adjustment shared by the hit-point floor MinHitPoints and
  the ceiling MaxHitPoints of ModifyCharacter (ovl16:209F). It sums ConstitutionHitPointTable[Constitution] over the
  eight classes the character has a level in (ClassLevels[I], +$96, signed, above 0), then adds the
  fighter bonus: one more for a fighter (ClassMask = 2) above constitution 16 and a second above 17
  (the AD&D 1e fighter constitution bonus). The `with Who^` evaluates the parameter once into a
  hidden local; the result is the signed total (it can be negative for a low constitution). }
function ConstitutionHitPointAdjustment(Who: PCharacter): ShortInt;
var
  Sum: ShortInt;
  I: ShortInt;
  Spare: Byte;   { [bp-4]: the original frame carries this byte, never read or written }
begin
  Sum := 0;
  with Who^ do
    for I := 0 to 7 do
      if ClassLevels[I] > 0 then
      begin
        Inc(Sum, ConstitutionHitPointTable[Constitution]);
        if Constitution > 16 then
          if ClassMask = 2 then
            Inc(Sum);
        if Constitution > 17 then
          if ClassMask = 2 then
            Inc(Sum);
      end;
  ConstitutionHitPointAdjustment := Sum;
end;
{ ovl16:3FB3. The minimum hit points a character's HpMax may be trained down to; the floor
  counterpart of the ceiling MaxHitPoints, both called by ModifyCharacter (ovl16:209F). Over the
  eight classes the character has a level in (ClassLevels[I], +$96, signed, above 0) it counts the
  hit dice (Count) and totals their levels into Total, adding one level for class 4 and class 7
  (whose maximum die is one higher, see ovl16:408C). It then divides Total plus the constitution
  adjustment (ConstitutionHitPointAdjustment, which may be negative) by Count; a negative adjustment
  Total cannot absorb (Total at most its magnitude plus Count) clamps the result to 1, so the floor
  is never below 1. The `with Who^` evaluates the parameter once. No side effects. }
function MinHitPoints(Who: PCharacter): Byte;
var
  Count: Byte;         { [bp-2]: the classes the character has a level in }
  Adjustment: ShortInt;{ [bp-3]: the constitution hit-point adjustment (ConstitutionHitPointAdjustment) }
  Total: Byte;         { [bp-4]: the summed hit-dice levels, then the divided result }
  I: ShortInt;         { [bp-5]: class index 0..7 }
begin
  with Who^ do
  begin
    Count := 0;
    Total := 0;
    for I := 0 to 7 do
      if ClassLevels[I] > 0 then
      begin
        Inc(Total, ClassLevels[I]);
        Inc(Count);
        case I of
          4: Inc(Total);
          7: Inc(Total);
        end;
      end;
  end;
  Adjustment := ConstitutionHitPointAdjustment(Who);
  if Adjustment < 0 then
  begin
    if Total > Abs(Adjustment) + Count then
      Total := (Total + Adjustment) div Count
    else
      Total := 1;
  end
  else
    Total := (Total + Adjustment) div Count;
  MinHitPoints := Total;
end;
{ ovl16:408C. The maximum hit points of Who, the ceiling counterpart of MinHitPoints
   (ovl16:3FB3) and both called by ModifyCharacter (ovl16:209F). Over the eight classes the
   character has a level in (ClassLevels[I], +$96, signed, above 0) it totals the levels times the
   maximum hit die of each class (8 cleric and druid, 10 fighter and paladin, 8 ranger, 4
   magic-user, 6 thief, 4 monk; one extra die-worth for class 4 ranger and class 7 monk) and counts
   the classes; it then divides the total plus the constitution adjustment by the class count and
   never returns below 1. QUIRK ovl16:41B8: the constitution adjustment is taken from the global
   SelectedCharacter (DS:5D92), not from Who, although every caller passes SelectedCharacter. The
   `with Who^` evaluates the parameter once into a hidden local. No side effects. }
function MaxHitPoints(Who: PCharacter): Byte;
var
  Count: Byte;          { [bp-2]: the classes the character has a level in }
  Total: Byte;          { [bp-3]: the summed maximum hit points, then the divided result }
  Adjustment: ShortInt; { [bp-4]: the constitution hit-point adjustment (ConstitutionHitPointAdjustment) }
  I: ShortInt;          { [bp-5]: class index 0..7 }
begin
  with Who^ do
  begin
    Count := 0;
    Total := 0;
    for I := 0 to 7 do
      if ClassLevels[I] > 0 then
      begin
        Inc(Count);
        case I of
          0: Inc(Total, ClassLevels[I] * 8);
          1: Inc(Total, ClassLevels[I] * 8);
          2: Inc(Total, ClassLevels[I] * 10);
          3: Inc(Total, ClassLevels[I] * 10);
          4: Inc(Total, (ClassLevels[I] + 1) * 8);
          5: Inc(Total, ClassLevels[I] * 4);
          6: Inc(Total, ClassLevels[I] * 6);
          7: Inc(Total, (ClassLevels[I] + 1) * 4);
        end;
      end;
  end;
  Adjustment := ConstitutionHitPointAdjustment(SelectedCharacter);
  if Adjustment < 0 then
  begin
    if Total > Abs(Adjustment) + Count then
      Total := (Total + Adjustment) div Count
    else
      Total := 1;
  end
  else
    Total := (Total + Adjustment) div Count;
  MaxHitPoints := Total;
end;
{ ovl16:4235. Rolls the hit points a level gains for the classes in ClassBits: over the eight classes
   it adds, for each class the character has a level in (ClassLevels, +$96, signed, above 0) whose
   bit is in ClassBits (ClassTrainingBits, one bit per class), a roll of ClassHitDiceCount[I] dice of
   ClassHitDieSides[I] sides (RollDice, ovl24:0DE3), where a class at level 1 rolls at least two
   thirds of its hit die (the first-level minimum). The caller divides the sum by the number of
   classes with a level. Called by the training hall (ovl16:29AE, whitepaper 5.8) and the
   create-character run (ovl16:1D1E). No side effects but the random rolls. }
function RollHitPoints(Who: PCharacter; ClassBits: Byte): Byte;
var
  ClassRoll: Byte;   { [bp-2]: the roll for one class }
  Sum: Byte;         { [bp-3]: the summed rolls, the result }
  I: ShortInt;       { [bp-4]: class index 0..7 }
begin
  Sum := 0;
  for I := 0 to 7 do
    if (Who^.ClassLevels[I] > 0) and ((ClassTrainingBits[I] and ClassBits) > 0) then
    begin
      ClassRoll := RollDice(ClassHitDiceCount[I], ClassHitDieSides[I]);
      if Who^.ClassLevels[I] = 1 then
        if ClassRoll < (ClassHitDieSides[I] * 2) div 3 then
          ClassRoll := (ClassHitDieSides[I] * 2) div 3;
      Inc(Sum, ClassRoll);
    end;
  RollHitPoints := Sum;
end;
{ ovl16:42ED. Takes Amount gold pieces from Who's money (the training-hall cost, ovl16:29AE): the
   amount is converted to copper (times GoldInCopper), then coin by coin from copper up it hands
   over Amount div CoinCopperValues[Kind] + 1 coins (one more than the remainder needs, so the
   hand-over always overshoots) capped at the coins Who holds, and gives the overshoot back as
   change kind by kind from platinum down (Amount div CoinCopperValues[Kind] coins). QUIRK
   ovl16:432A: the kind is not bounded, so a character who cannot cover the amount walks on into
   Money[5..6] (gems and jewelry) and reads CoinCopperValues past its five entries, and when a kind
   has no coins left the hand-over of zero coins starts the loop again. The `with Who^` evaluates
   the parameter once. }
procedure PayGold(Amount: LongInt; Who: PCharacter);
var
  Coins: Word;       { [bp-2]: the coins of one kind handed over or given back }
  Kind: TCoinKind;   { [bp-3]: the coin kind, copper 0 .. platinum 4 }
begin
  Amount := Amount * GoldInCopper;
  Kind := CopperCoin;
  with Who^ do
  begin
    while Amount > 0 do
    begin
      Coins := Amount div CoinCopperValues[Ord(Kind)] + 1;
      if Coins > Money[Ord(Kind)] then
        Coins := Money[Ord(Kind)];
      Dec(Amount, Coins * CoinCopperValues[Ord(Kind)]);
      Dec(Money[Ord(Kind)], Coins);
      Kind := Succ(Kind);
    end;
    if Amount < 0 then
    begin
      Amount := Abs(Amount);
      Kind := PlatinumCoin;
      while Amount > 0 do
      begin
        Coins := Amount div CoinCopperValues[Ord(Kind)];
        Dec(Amount, Coins * CoinCopperValues[Ord(Kind)]);
        Inc(Money[Ord(Kind)], Coins);
        Kind := Pred(Kind);
      end;
    end;
  end;
end;

begin
end.
