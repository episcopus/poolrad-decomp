unit OVL03;
{ Encounter: the command loop of the ECL script interpreter (whitepaper 5.1), and the wilderness
  loop the main program runs after the character menu (RunWilderness, ovl03:32F8). DispatchCommand
  dispatches each command by its opcode (CurrentOpcode) to a handler in this unit; the handlers
  decode their operands through OVL07 and run them. }
{$A-,O+,F+,S-,R-,G-,I-,L-}
interface
uses POOLVARS, RES09, OVL07, OVL16, RES12;
procedure EndCommand;
procedure GotoCommand;
procedure GosubCommand;
procedure CompareCommand;
procedure ArithmeticCommand;
procedure RandomCommand;
procedure StoreCommand;
procedure SelectCharacterCommand;
procedure ShowEncounterCommand;
procedure AddEncounterGroupCommand;
procedure ApproachEncounterCommand;
procedure ShowCloseUpCommand;
procedure ReadNumberCommand;
procedure ReadStringCommand;
procedure ShowTextCommand;
procedure ReturnCommand;
procedure CompareBothPairsCommand;
procedure RunIfCompared;
procedure StartEclBlock;
procedure LoadAreaGraphics;
procedure BitwiseCommand;
procedure CopyIndexedWordCommand;
procedure StoreIndexedWordCommand;
procedure ChooseFromListCommand;
procedure AskMenuCommand;
procedure ClearEncounterCommand;
procedure ComputePartyValueCommand;
procedure ScanPartyCommand;
procedure CheckPartyHasRangerCommand;
procedure RollSurpriseCommand;
procedure RunAreaEventCommand;
procedure SelectCaseCommand;
procedure AddLootCommand;
procedure LoseMoneyAndItemsCommand;
procedure EncounterActionCommand;
procedure ChooseAttitudeCommand;
procedure ComparePartyItemCommand;
procedure PauseCommand;
procedure DamagePartyCommand;
procedure RedrawAreaViewCommand;
procedure PassTimeCommand;
procedure NewLineCommand;
procedure ClearPictureWindowCommand;
procedure ChoosePartyMemberCommand;
procedure AddComputerMemberCommand;
procedure FindMemorizedSpellCommand;
procedure EngineActionCommand;
procedure RunCamp;
procedure ShowSpecialScreenCommand;
procedure DrawGlyphRunCommand;
procedure DispatchCommand;
procedure RunScriptFrom(Address: Word);
procedure RunAreaStep;
procedure RunWilderness;
implementation
uses OVL04, OVL05, OVL06, OVL08, OVL14, OVL15, OVL17, OVL18, OVL20, OVL21, OVL24, OVL25, OVL26, OVL28, OVL29,
  OVL32, RES03, RES04, RES05, RES06, Crt;

const
  { The operand types from this one up are strings: $80 a packed string, $81 the address of a
    stored one (DecodeOperands in OVL07). }
  FirstStringOperandType = $80;
  { The opcodes of the arithmetic commands (ovl03:01A3). }
  OpAdd = 4;
  OpSub = 5;
  OpDiv = 6;
  OpMul = 7;
  { The opcodes of the conditional commands (ovl03:0B52): each runs the next command only when the
    CompareFlags entry of its comparison is set. }
  OpIfEqual = 22;
  OpIfNotEqual = 23;
  OpIfLess = 24;
  OpIfGreater = 25;
  OpIfLessOrEqual = 26;
  OpIfGreaterOrEqual = 27;
  { The opcodes of the bitwise commands (ovl03:0DEF). }
  OpAnd = 47;
  OpOr = 48;
  { The opcode of the case command that stores the chosen address in EclPC (ovl03:18F8); 38 runs it. }
  OpChooseAddress = 37;
  { The loot Kind of ECL command 39 (ovl03:19B0): below TreasureTableBase it is an item block, from it
    up a treasure table of Kind - TreasureTableBase rolls, and NoTreasure gives nothing. }
  TreasureTableBase = $80;
  NoTreasure = $FF;
  { The colour of the message 'Unable to find item file' (ovl03:19B0). }
  ItemErrorColor = 15;
  { The bit of ECL command 10's operand that removes the member from the party, and the mask of
    the party position (ovl03:02E0). }
  RemoveMemberBit = $80;
  PositionMask = $7F;
  { The two words of GameVars2 that ECL command 12 (ovl03:03B4) works with: the largest distance the
    script allows for the encounter picture, and the steps the party sees ahead (OpenStepsAhead,
    ovl07:0482, which also stores them there). }
  VarEncounterLimit = 704;
  { The words of GameVars2 ECL command 36 (ovl03:179B) reads: a shop and a temple visit the script asked
    for (cleared when served), and word 714, of which it keeps only the low bit (meaning unknown). }
  VarShopRequest = 876;
  VarTempleRequest = 738;
  { ECL command 11 (ovl03:0450) adds no encounter member once its count of members reaches this. }
  MaxEncounterMembers = 63;
  { The icon slot EncounterIconSlot starts at: InitScript (ovl07:01F0) and ECL command 28 (ovl03:125D) set it. }
  FirstEncounterIcon = 8;
  { ECL command 29 (ovl03:12C6) counts only what is above these: ResistValue above 60 and HitAdjust
    above 39. Purpose unknown. }
  ResistThreshold = 60;
  HitAdjustThreshold = 39;
  { The word of GameVars2 that ECL command 14 (ovl03:0856) reads: NoHeadBank when the close-up is the PIC
    picture, else the HEAD bank of the HEAD and BODY close-up (ShowEncounterPicture, ovl07:054E). }
  VarCloseUpHead = 737;
  NoHeadBank = $FF;
  { The picture bank ECL command 14 (ovl03:0856) takes to hide the close-up instead of showing it. }
  HideCloseUp = $FF;
  { The colour and the longest line of the text ECL command 16 asks for (ovl03:0994). }
  EclTextColor = 10;
  EclInputMaxLength = 40;
  { The ECL text window of ECL commands 17 and 18 (ovl03:0A09): columns 1 to 38, rows 17 to 22. The
    cursor starts at its top left corner, the one EndCommand (ovl03:0001) also puts it at. }
  EclTextLeft = 1;
  EclTextTop = $11;
  EclTextRight = $26;
  EclTextBottom = $16;
  { The WallViewMode values that show the map window pages 2 to 4 (AreaViewKind 2 to 4, ovl03:31B4). }
  WallModeMapPage2 = $19;
  WallModeMapPage3 = $1A;
  WallModeMapPage4 = $1B;
  { The GameVars words the area step (ovl03:31B4) reads: the area doors are animated when word VarAreaDoors is
    AreaDoorsOpen and word VarRiverGate is clear. Word 435 is one of the gates DrawAreaView reads
    (ovl27:0000); the meaning of the values is not traced. Word VarMapEdgeHit of GameVars2 is cleared at each step. }
  VarRiverGate = 418;
  AreaDoorsOpen = $FE;
  { The GameVars words the wilderness loop saves the party's cell in before DoWildernessMenu, so a
    cell that changed can play SoundStep. }
  VarSavedPartyColumn = 240;
  VarSavedPartyRow = 241;
  { UpCase of the key that makes camp (RunCamp) in the wilderness loop. }
  KeyCamp = 'E';
  { The colours of the ECL menus (ovl03:0F08, ovl03:10D1): the title of AskMenu and the heading of a
    list, the words of AskMenu and the lines of a list, the hotkeys and the highlight. }
  MenuTitleColor = 13;
  MenuTextColor = 10;
  MenuHotColor = 15;
  { The prompt line is text row $18; the menu command at ovl03:10D1 clears it, columns 0 to $27. }
  PromptLeftCol = 0;
  PromptLastCol = $27;
  { ECL command 17: the text goes on after the text already in the window; command 18 clears it first. }
  OpContinueText = $11;
  { The menu of ECL command 44 (ovl03:25CB): the words of the attitudes, each after a hotkey mark. }
  AttitudeMenu = '~HAUGHTY ~SLY ~NICE ~MEEK ~ABUSIVE';
  { ECL command 41 (ovl03:1EF8): the item AskMenu returns. Choice 3 is rewritten to ParlayChoice when the
    fourth word is PARLAY rather than ADVANCE. }
  CombatChoice = 0;
  WaitChoice = 1;
  FleeChoice = 2;
  AdvanceChoice = 3;
  ParlayChoice = 4;
  { The word EncounterActionCommand writes to operand 4. }
  MonstersFleeResult = 0;       { with the text 'The monsters flee.' }
  FightResult = 1;              { a fight, or a flee the movement check refuses }
  PartyFleesResult = 2;         { a flee the check allows, and the flee choice in kinds 1, 3 and 4 }
  ParlayResult = 3;             { a parlay path with no step left }
  { ECL command 46 (ovl03:2775). Operand 1: bit 7 (TrapSavingThrowBit) is the saving-throw mode, a targeted
    trap whose target saves; with it clear Flags is the number of hits, each on a random member that only
    ResistValue stops. In the saving-throw mode bit 6 (TrapWholePartyBit) hits the whole party and bit 5
    (TrapUnsavedBit) is a hit no saving throw stops; the low five bits are the saving throw bonus. Operand 5:
    bit 7 picks the selected character as the target (else a random member); its low three bits are the
    saving throw kind (the original passes them in that order: ovl03:2864, 28B2, 290E; a first reading had
    the two swapped). }
  TrapSavingThrowBit = $80;
  TrapWholePartyBit = $40;
  TrapUnsavedBit = $20;
  TrapBonusMask = $1F;
  TrapSelectedBit = $80;
  TrapKindMask = 7;
  { The party-wiped screen of ECL command 46: its window, the window colour, the text colour and the pause. }
  EndWindowLeft = 1;
  EndWindowTop = 1;
  EndWindowRight = $26;
  EndWindowBottom = $16;
  EndWindowColor = 15;
  EndTextColor = 10;
  EndPauseMs = 3000;
  ContinueColor = 15;
  { ECL command 59 (ovl03:2C03): the search steps through slots 1 to 82: the loop tests I <= SpellScanLast
    after the increment (ovl03:2C78), so Spells[82] is compared too [QUIRK: Spells has slots 0..20]; and the slot value
    it returns when the value is not found (the byte $FF, that is -1 in a ShortInt). }
  SpellScanLast = 81;
  NoSpellSlot = $FF;
  { ECL command 54 (ovl03:2B7E): the kind that makes the added member a member of the other side (Side 1),
    and the high bit of its B84 byte that marks a computer-run member. }
  OtherSideKind = $18;
  { The picture frame of ECL commands 0 and 61 (ovl03:0001, ovl03:2B14): columns 1 to 15 and rows 1 to
    15, a box the close-up picture is drawn inside (columns and rows 3 to 13). }
  PictureFrameLeft = 1;
  PictureFrameTop = 1;
  PictureFrameRight = $F;
  PictureFrameBottom = $F;
  { ECL command 60 (ovl03:2E7D): the glyph run is drawn in colour 15; a run that starts below the close-up
    box (its last row, CloseUpLastRow) starts at column 2, row 5 instead. }
  GlyphRunColor = 15;
  CloseUpLastRow = $D;
  GlyphRunCol = 2;
  GlyphRunRow = 5;
  { ECL command 45 (ovl03:2CCF) biases the operand word by CodeBias and tests the result against the
    actions below; the comments give the word the script writes. }
  CodeBias = $7FFF;
  ActionRedrawArea = $AC91;     { word $2C90: redraw the area view when it is out of date }
  ActionDuelWithCopy = 1;       { word $8000: a duel with the copy }
  ActionDuelNoCopy = 2;         { word $8001: a duel without the copy }
  ActionSound = $3A04;          { word $BA03: PlaySound by ScriptSoundCode }
  ActionStepParty = $401F;      { word $C01E: StepPartyForward }
  ActionWallProbe = $4019;      { word $C018: WallIdAt into PartyCellWallId when AreaViewKind is 1 }
  DuelWithCopy = 1;             { SetupDuel's WithCopy flag }
  DuelNoCopy = 0;
  { ECL command 56 (ovl03:2E10) picks its screen by operand 1: 8 is the ending narrative, 9 the camp. }
  ScreenEnding = 8;
  ScreenCamp = 9;
var
  { PictureShownFlags (POOLVARS) under the type ShowEncounterPicture takes: TPictureShown is declared in OVL07,
    and Turbo Pascal accepts a var argument only of the identical type. }
  PictureShown: TPictureShown absolute PictureShownFlags;

{ ovl03:0001. The ECL command 0, the only command that takes no operands (the dispatcher at
  ovl03:2F2D calls it for CurrentOpcode 0). When PictureFrameDirty is set it redraws (clears and frames) the
  picture frame window and, when the game variable VarForceWallView is nonzero, the close-up box (columns 3 to 13)
  inside it; it then selects the character at ReselectCharacter when ReselectCharacterPending is set, clears the
  two-byte scratch
  PictureShownFlags,
  moves EclPC past the command, empties the return stack of ScriptGosub, and puts the text
  cursor at column 1, row 17 (GlyphCol, GlyphRow). }
procedure EndCommand;
begin
  if PictureFrameDirty <> 0 then
  begin
    DrawWindow(PictureFrameLeft, PictureFrameTop, PictureFrameRight, PictureFrameBottom, 0, $F, '');
    if GameVars^[VarForceWallView] <> 0 then
      DrawWindow(3, 3, $D, $D, 0, $F, '');
  end;
  if ReselectCharacterPending <> 0 then
  begin
    SelectedCharacter := ReselectCharacter;
    ReselectCharacterPending := 0;
  end;
  FillChar(PictureShownFlags, 2, 0);
  CloseUpShown := 0;
  PictureFrameDirty := 0;
  ScriptRunEnded := 1;
  Inc(EclPC);
  while ReturnStack <> nil do
  begin
    ReturnPrev := ReturnStack^.Next;
    FreeMem(ReturnStack, 6);
    ReturnStack := ReturnPrev;
  end;
  GlyphRow := EclTextTop;
  GlyphCol := EclTextLeft;
  GlyphRunInBox := 0;
end;
{ ovl03:00F4. ECL command 1 (dispatcher ovl03:2F2D, CurrentOpcode 1): an unconditional jump. Its
  one operand is a script address, and EclPC moves to it (the same jump ScriptGosub makes after
  it pushes the return address). }
procedure GotoCommand;
begin
  DecodeOperands(1);
  EclPC := MakeWord(OperandLow[1], OperandHigh[1]);
end;
{ ovl03:0111. ECL command 2 (dispatcher ovl03:2F2D, CurrentOpcode 2): a subroutine call. Its one
  operand is the script address of the subroutine; ScriptGosub pushes the return address and
  jumps there. }
procedure GosubCommand;
begin
  DecodeOperands(1);
  ScriptGosub(1);
end;
{ ovl03:0126. ECL command 3 (dispatcher ovl03:2F2D, CurrentOpcode 3): compares its two operands
  and sets CompareFlags for the conditional commands. When either operand is a string (type bit 7
  set) both strings are taken from EclStrings[1] and [2], whatever the types, and compared with
  CompareStrings; otherwise the two word values are compared with CompareWords. }
procedure CompareCommand;
var
  LeftWord: Word;
  RightWord: Word;
  Left: string;
  Right: string;
begin
  DecodeOperands(2);
  if (OperandType[1] >= FirstStringOperandType) or (OperandType[2] >= FirstStringOperandType) then
  begin
    Left := EclStrings[1];
    Right := EclStrings[2];
    CompareStrings(Left, Right);
  end
  else
  begin
    LeftWord := OperandValue(1);
    RightWord := OperandValue(2);
    CompareWords(LeftWord, RightWord);
  end;
end;
{ ovl03:01A3. ECL commands 4 to 7 (dispatcher ovl03:2F2D, CurrentOpcode OpAdd, OpSub, OpDiv or
  OpMul): the values of the first two operands are combined and the answer is written with
  WriteVmWord to the script address the third operand names. Division and multiplication keep the
  low word of the answer. QUIRK ovl03:01FC: subtraction takes the second value minus the first,
  while division takes the first over the second. }
procedure ArithmeticCommand;
var
  Target: Word;
  Values: array[1..2] of Word;
  I: ShortInt;
  Answer: Word;
  Unused: Byte;                 { QUIRK ovl03:01A3: a byte of the frame nothing uses }
begin
  DecodeOperands(3);
  for I := 1 to 2 do
    Values[I] := OperandValue(I);
  Target := MakeWord(OperandLow[3], OperandHigh[3]);
  case CurrentOpcode of
    OpAdd: Answer := Values[1] + Values[2];
    OpSub: Answer := Values[2] - Values[1];
    OpDiv: Answer := Values[1] div Values[2];
    OpMul: Answer := Values[1] * Values[2];
  end;
  WriteVmWord(Target, Answer);
end;
{ ovl03:0234. ECL command 8 (dispatcher ovl03:2F2D, CurrentOpcode 8): stores a random number. The
  first operand is the largest roll wanted: one is added to it, so the roll is 0 to that value
  (Random(n) gives 0 to n-1). The roll is written with WriteVmWord to the script address the
  second operand names. The Trunc keeps the Real conversion of the roll that the original makes
  (0AF8:119A, 119E); it changes nothing for a whole number. QUIRK ovl03:024D: a first operand of
  255 is not raised, so the roll can only be 0 to 254. }
procedure RandomCommand;
var
  Range: Byte;
  Roll: Byte;
  Target: Word;
begin
  DecodeOperands(2);
  Range := OperandValue(1);
  if Range < $FF then
    Inc(Range);
  Target := MakeWord(OperandLow[2], OperandHigh[2]);
  Roll := Trunc(Random(Range));
  WriteVmWord(Target, Roll);
end;
{ ovl03:0292. ECL command 9 (dispatcher ovl03:2F2D, CurrentOpcode 9): stores its first operand at
  the script address its second operand names. A string operand (type bit 7 set) is stored with
  WriteVmString from EclStrings[1]; a value is stored as a word with WriteVmWord. }
procedure StoreCommand;
var
  Value: Word;
  Target: Word;
begin
  DecodeOperands(2);
  Target := MakeWord(OperandLow[2], OperandHigh[2]);
  if OperandType[1] < FirstStringOperandType then
  begin
    Value := OperandValue(1);
    WriteVmWord(Target, Value);
  end
  else
    WriteVmString(Target, EclStrings[1]);
end;
{ ovl03:02E0. ECL command 10 (dispatcher ovl03:2F2D, CurrentOpcode 10): selects the party member at
  the 0-based position its operand names as SelectedCharacter. The walk starts at PartyListHead, the head
  of the party list (Next at +$104), and stops at the position or at the end of the list; a
  position past the end selects nothing. It sets ReselectCharacterPending first, so the next EndCommand (ovl03:0001)
  selects ReselectCharacter again. When the operand's bit 7 is set and the script has just cleared the
  character's name and status (ActiveFlagClearedByScript and NameClearedByScript, set by SetCharacterVar), the selected member
  leaves the party (RemoveSelectedCharacter, as ovl15:18E5 does) and is redrawn (DrawPartyRoster), and
  ReselectCharacterPending is
  cleared when that member is ReselectCharacter. }
procedure SelectCharacterCommand;
var
  Member: PCharacter;
  Unused: Byte;                 { QUIRK ovl03:02E0: a byte of the frame nothing uses }
  Position: Byte;
  I: Byte;
  RemoveFlag: Byte;
begin
  ReselectCharacterPending := 1;
  DecodeOperands(1);
  I := 0;
  Position := OperandValue(1);
  Member := PCharacter(PartyListHead);
  RemoveFlag := Position and RemoveMemberBit;
  Position := Position and PositionMask;
  if Position > 0 then
    while (I < Position) and (Member <> nil) do
    begin
      Member := Member^.Next;
      Inc(I);
    end;
  if Member <> nil then
    SelectedCharacter := Member;
  if (RemoveFlag <> 0) and (ActiveFlagClearedByScript <> 0) and (NameClearedByScript <> 0) then
  begin
    if ReselectCharacter = SelectedCharacter then
      ReselectCharacterPending := 0;
    RemoveSelectedCharacter(False, True);
    DrawPartyRoster(SelectedCharacter);
    ActiveFlagClearedByScript := 0;
    NameClearedByScript := 0;
  end;
end;
{ ovl03:03B4. ECL command 12 (dispatcher ovl03:2F2D, CurrentOpcode 12): shows an encounter picture
  at the distance the party can see ahead. Operand 1 is the sprite bank (EncounterSpriteBank) and
  operand 3 the picture bank (EncounterPicBank), both passed to ShowEncounterPicture; operand 2 is
  the largest distance the script allows, kept in word 704 of GameVars2. The distance is the steps
  ahead (OpenStepsAhead, which also stores them in word 705), cut down to that limit. The two shown
  flags are PictureShown (PictureShownFlags). }
procedure ShowEncounterCommand;
var
  Unused: Word;                 { QUIRK ovl03:03B4: two bytes of the frame nothing uses }
begin
  DecodeOperands(3);
  EncounterSpriteBank := OperandValue(1);
  GameVars2^[VarEncounterLimit] := OperandValue(2);
  EncounterPicBank := OperandValue(3);
  GameVars2^[VarStepsAhead] := OpenStepsAhead(PartyMapColumn, PartyMapRow, PartyFacing);
  if GameVars2^[VarEncounterLimit] < GameVars2^[VarStepsAhead] then
    GameVars2^[VarStepsAhead] := GameVars2^[VarEncounterLimit];
  ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank, Byte(GameVars2^[VarStepsAhead]), PictureShown);
end;
{ ovl03:0450. ECL command 11 (dispatcher ovl03:2F2D, CurrentOpcode 11): adds a group of encounter
  members to the party list PartyListHead (icons from 8 up, so not the party's own members). Operand 1 is
  the kind LoadCharacter loads (LoadMonster, the save and load unit), operand 2 the number of members
  (at least 1), operand 3 the block of the combat picture 'CPIC' loaded into the icon slot EncounterIconSlot.
  The loaded character goes to the tail of the list first, then Count - 1 copies of it, each with
  its own copies of the item and affect lists (the copies are prepended, so the lists come out in
  reverse order). Every member gets CombatIcon := EncounterIconSlot, and the slot goes up by one afterwards.
  Nothing is added once EncounterMemberCount reaches MaxEncounterMembers. SelectedCharacter is saved
  and restored, and EncounterMembersAdded is set. }
procedure AddEncounterGroupCommand;
var
  Kind: Byte;
  Count: Byte;
  PictureBlock: Byte;
  I: Byte;
  Last: PCharacter;
  NewMember: PCharacter;
  Who: PCharacter;
  Saved: PCharacter;
  Template: TCharacter;
  PictureSetName: string[12];
  Items: PItem;
  OldItem: PItem;
  ItemsHead: PItem;
  Affects: Pointer;
  OldAffect: PAffect;
  AffectsHead: Pointer;
begin
  Saved := SelectedCharacter;
  I := 1;
  DecodeOperands(3);
  if EncounterMemberCount >= MaxEncounterMembers then
    Exit;
  Last := nil;
  NewMember := nil;
  Kind := OperandValue(1);
  LoadCharacter(Kind, Who, Items, Affects);
  Template := Who^;
  ItemsHead := Items;
  AffectsHead := Affects;
  Count := OperandValue(2);
  if Count <= 0 then
    Count := 1;
  PictureBlock := OperandValue(3);
  Last := PCharacter(PartyListHead);
  PictureSetName := 'CPIC';
  LoadPictureSlot(PictureSetName, PictureBlock, EncounterIconSlot);
  while Last^.Next <> nil do
    Last := Last^.Next;
  Last^.Next := Who;
  Last := Last^.Next;
  Last^.CombatIcon := EncounterIconSlot;
  Last^.Next := nil;
  Inc(EncounterMemberCount);
  Inc(I);
  while (I <= Count) and (EncounterMemberCount < MaxEncounterMembers) do
  begin
    New(NewMember);
    Last^.Next := NewMember;
    Last := Last^.Next;
    Last^ := Template;
    Last^.CombatIcon := EncounterIconSlot;
    Last^.Next := nil;
    Last^.Affects := nil;
    Last^.Items := nil;
    Inc(I);
    Inc(EncounterMemberCount);
    while Items <> nil do
    begin
      if Last^.Items = nil then
      begin
        New(Last^.Items);
        Last^.Items^ := Items^;
        Last^.Items^.Next := nil;
      end
      else
      begin
        OldItem := Last^.Items;
        New(Last^.Items);
        Last^.Items^ := Items^;
        Last^.Items^.Next := OldItem;
      end;
      Items := Items^.Next;
    end;
    Items := ItemsHead;
    while Affects <> nil do
    begin
      if PAffect(Last^.Affects) = nil then
      begin
        New(PAffect(Last^.Affects));
        PAffect(Last^.Affects)^ := PAffect(Affects)^;
        PAffect(Last^.Affects)^.Next := nil;
      end
      else
      begin
        OldAffect := PAffect(Last^.Affects);
        New(PAffect(Last^.Affects));
        PAffect(Last^.Affects)^ := PAffect(Affects)^;
        PAffect(Last^.Affects)^.Next := OldAffect;
      end;
      Affects := PAffect(Affects)^.Next;
    end;
    Affects := AffectsHead;
  end;
  Inc(EncounterIconSlot);
  EncounterMembersAdded := 1;
  SelectedCharacter := Saved;
end;
{ ovl03:0817. ECL command 13 (dispatcher ovl03:2F2D, CurrentOpcode 13): brings the encounter picture
  one step nearer. While the steps the party sees ahead (VarStepsAhead, word 705 of GameVars2) are not
  used up, it takes one off and shows the picture again at the new distance (ShowEncounterPicture).
  It has no operands and always moves EclPC past the command. }
procedure ApproachEncounterCommand;
begin
  if GameVars2^[VarStepsAhead] > 0 then
  begin
    Dec(GameVars2^[VarStepsAhead]);
    ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank, Byte(GameVars2^[VarStepsAhead]), PictureShown);
  end;
  Inc(EclPC);
end;
{ ovl03:0856. ECL command 14 (dispatcher ovl03:2F2D, CurrentOpcode 14): shows the close-up picture of
  the encounter, or hides it. Operand 1 is the picture bank PicBank. When PicBank is HideCloseUp, the
  close-up goes: when PreviousAreaViewKind is above 1 or AreaViewKind is 1 and a close-up or the 3D sprite is up
  (CloseUpShown or Sprite3DLoaded), the area view is drawn again (ShowAreaView), those flags are cleared and CloseUpHidden
  is set; both PictureShown flags are cleared. Otherwise the picture window (3, 3 to 13, 13) is
  cleared first unless VarForceWallView is set, and the close-up is drawn as ShowEncounterPicture
  draws it: the PIC picture PicBank when word VarCloseUpHead of GameVars2 is NoHeadBank, else the HEAD
  and BODY pictures (ShowHeadBody). Purpose of PreviousAreaViewKind unknown: the loader sets it to 1 (ovl11:03EB). }
procedure ShowCloseUpCommand;
var
  PicBank: Byte;
begin
  DecodeOperands(1);
  PicBank := OperandValue(1);
  if (GameVars^[VarForceWallView] = 0) and (PicBank <> HideCloseUp) then
    DrawWindow(3, 3, $D, $D, 0, $F, '');
  if PicBank <> HideCloseUp then
  begin
    PictureShown[1] := 1;
    CloseUpShown := 1;
    if GameVars2^[VarCloseUpHead] = NoHeadBank then
    begin
      LoadSpriteList('PIC', PicBank, 0, @PictureAnimation);
      DrawSprite(3, 3, 1, PictureAnimation.Frames[1].Sprite);
    end
    else
      ShowHeadBody(GameVars2^[VarCloseUpHead], PicBank);
  end
  else
  begin
    if ((PreviousAreaViewKind > 1) or (AreaViewKind = 1)) and ((CloseUpShown <> 0) or (Sprite3DLoaded <> 0)) then
    begin
      ShowAreaView;
      CloseUpShown := 0;
      Sprite3DLoaded := 0;
      CloseUpHidden := 1;
    end;
    PictureShown[0] := 0;
    PictureShown[1] := 0;
  end;
end;
{ ovl03:0951. ECL command 15 (dispatcher ovl03:2F2D, CurrentOpcode 15): asks the player for a number
  and stores it as a word at the script address that operand 2 names. Operand 1 is decoded but never
  read. The prompt is empty; ReadNumber (RES06, colour 10) repeats the input line until the text is a
  number from 0 to 65536. }
procedure ReadNumberCommand;
var
  Prompt: string[1];
  Number: Word;
  Target: Word;
begin
  DecodeOperands(2);
  Prompt := '';
  Target := MakeWord(OperandLow[2], OperandHigh[2]);
  Number := ReadNumber(Prompt, 10);
  WriteVmWord(Target, Number);
end;
{ ovl03:0994. ECL command 16 (dispatcher ovl03:2F2D, CurrentOpcode 16): asks the player for a line of
  text and stores it as a string at the script address that operand 2 names (WriteVmString). Operand
  1 is decoded but never read. The prompt is empty; ReadInputLine (RES06) reads the line in colour
  EclTextColor, at most EclInputMaxLength characters. An empty answer is stored as one space, so the
  script's string is never empty. }
procedure ReadStringCommand;
var
  Prompt: string[1];
  Target: Word;
  Answer: string;
begin
  DecodeOperands(2);
  Prompt := '';
  Target := MakeWord(OperandLow[2], OperandHigh[2]);
  Answer := ReadInputLine(Prompt, EclTextColor, EclInputMaxLength);
  if Length(Answer) = 0 then
    Answer := ' ';
  WriteVmString(Target, Answer);
end;
{ ovl03:0A09. ECL commands 17 and 18 (dispatcher ovl03:2F2D, CurrentOpcode $11 or $12): show the text
  of operand 1 in the ECL text window (EclTextLeft to EclTextRight, EclTextTop to EclTextBottom) with
  ShowPagedText. A number operand is turned into its text by WordToText and stored in EclStrings[1];
  a string operand is already there (DecodeOperands). Command 17 (OpContinueText) leaves the window and
  the cursor as they are; command 18 clears the window and puts the cursor at its top left corner first.
  EclWindowCleared is cleared, and DelayPerGlyph is set while the text is shown: DrawTextRun then waits after each
  glyph. }
procedure ShowTextCommand;
begin
  DecodeOperands(1);
  EclWindowCleared := 0;
  DelayPerGlyph := 1;
  if OperandType[1] < FirstStringOperandType then
    EclStrings[1] := WordToText(OperandValue(1));
  if CurrentOpcode = OpContinueText then
    ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 0, EclStrings[1])
  else
  begin
    GlyphRow := EclTextTop;
    GlyphCol := EclTextLeft;
    ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1, EclStrings[1]);
  end;
  DelayPerGlyph := 0;
end;
{ ovl03:0A9F. ECL command 19 (dispatcher ovl03:2F2D, CurrentOpcode $13): returns from a subroutine
  that ScriptGosub (ovl07:1951) called. EclPC moves past the command. When the return stack
  ReturnStack is not empty, EclPC takes the return address of its top entry (ReturnPC), the entry is
  freed and ReturnStack moves to the entry below it (Next, which ReturnPrev holds while the entry is
  freed). An empty stack leaves EclPC just past the command. }
procedure ReturnCommand;
begin
  Inc(EclPC);
  if ReturnStack <> nil then
  begin
    EclPC := ReturnStack^.ReturnPC;
    ReturnPrev := ReturnStack^.Next;
    FreeMem(ReturnStack, SizeOf(TReturnEntry));
    ReturnStack := ReturnPrev;
  end;
end;
{ ovl03:0AED. ECL command 20 (dispatcher ovl03:2F2D, CurrentOpcode $14): compares two pairs of word
  operands. The six CompareFlags are cleared, the four operands are read as words (OperandValue),
  and operand 1 is compared with operand 2 and operand 3 with operand 4. When both pairs are equal
  CompareFlags[0] (=) is set, else CompareFlags[1] (<>). The conditional commands 22 to 27 (the
  handler at ovl03:0B52) test these flags. }
procedure CompareBothPairsCommand;
var
  Values: array[1..4] of Word;
  I: Byte;
  Unused: Byte;                 { QUIRK ovl03:0AED: a byte of the frame nothing uses }
begin
  FillChar(CompareFlags, SizeOf(CompareFlags), 0);
  DecodeOperands(4);
  for I := 1 to 4 do
    Values[I] := OperandValue(I);
  if (Values[1] = Values[2]) and (Values[3] = Values[4]) then
    CompareFlags[0] := 1
  else
    CompareFlags[1] := 1;
end;
{ ovl03:0B52. ECL commands 22 to 27 (dispatcher ovl03:2F2D, CurrentOpcode OpIfEqual to
  OpIfGreaterOrEqual): a conditional. EclPC moves past the opcode, then the next command runs only
  when its comparison flag in CompareFlags is set (=, <>, <, >, <=, >= in that order, set by
  CompareCommand, CompareBothPairsCommand and the comparison routines of OVL07). When the flag is clear,
  SkipCommand steps over the next command. Any other opcode only moves EclPC. }
procedure RunIfCompared;
begin
  Inc(EclPC);
  case CurrentOpcode of
    OpIfEqual: if CompareFlags[0] = 0 then SkipCommand;
    OpIfNotEqual: if CompareFlags[1] = 0 then SkipCommand;
    OpIfLess: if CompareFlags[2] = 0 then SkipCommand;
    OpIfGreater: if CompareFlags[3] = 0 then SkipCommand;
    OpIfLessOrEqual: if CompareFlags[4] = 0 then SkipCommand;
    OpIfGreaterOrEqual: if CompareFlags[5] = 0 then SkipCommand;
  end;
end;
{ ovl03:0BD1. ECL command 32 (dispatcher ovl03:2F2D, CurrentOpcode $20): starts ECL block Block of the
  area's script file. The operand is the block number: the WallViewMode of the area is saved in
  VarSavedWallView, then WallViewMode takes the block number. The file is GameDir + 'ECL' + the
  TileSet number + '.dax' (its path goes to SaveAndExit first), LoadEcl loads the block and InitScript
  resets the script machine. ScriptRunEnded and ScriptBlockStarted are set to 1 and AreaRedrawArmed is cleared. }
procedure StartEclBlock;
var
  Block: Byte;
  TileSetText: string[1];
begin
  DecodeOperands(1);
  GameVars^[VarSavedWallView] := WallViewMode;
  Block := OperandValue(1);
  WallViewMode := Block;
  Str(TileSet, TileSetText);
  SaveAndExit(GameDir + 'ECL' + TileSetText + '.dax');
  LoadEcl(Block);
  InitScript;
  ScriptRunEnded := 1;
  ScriptBlockStarted := 1;
  AreaRedrawArmed := 0;
end;
{ ovl03:0C74. ECL commands 33 and 55 (dispatcher ovl03:2F2D, CurrentOpcode $21 or $37): load the
  graphics of the area for the three operands, the block numbers Blocks, where $FF means none.
  Command 33 loads the 3D map Blocks[1] (Load3DMap, VarGeoBlock keeps its number) when
  VarForceWallView is set, and the 'BACPAC' picture set (Load24x24Set) when Blocks[3] is given and
  VarForceWallView is clear. Command 55 loads the wall sets: slot 1 gets wall set 0 when Blocks[1] is
  $7F; when words 231 and 232 of GameVars are both set, slots 1 and 3 get Blocks[1] and Blocks[3],
  else each slot I gets Blocks[I] or, for $FF, the two words of WallSetSlotPairs[I] become $FFFF. The
  label ovl03:0D7B is the slot loop of this routine. AreaRedrawArmed is set first. When AreaStepRedrawOnce,
  Command55Ran and
  Command33Ran are all set, RedrawView runs, the selected character is redrawn (DrawPartyRoster) and
  AreaStepRedrawOnce is cleared. Words 231 and 232 of GameVars and word 713 of GameVars2 are not named yet. }
procedure LoadAreaGraphics;
var
  Blocks: array[1..3] of Byte;
  I: Byte;
begin
  DecodeOperands(3);
  AreaRedrawArmed := 1;
  for I := 1 to 3 do
    Blocks[I] := OperandValue(I);
  if CurrentOpcode = $21 then
  begin
    Command33Ran := 1;
    if (Blocks[1] <> $FF) and (Blocks[1] <> $7F) and (GameVars^[VarForceWallView] <> 0) then
    begin
      GameVars^[VarGeoBlock] := Blocks[1];
      Load3DMap(Blocks[1]);
      GameVars2^[713] := 0;
    end;
    if (Blocks[3] <> $FF) and (GameVars^[VarForceWallView] = 0) then
      Load24x24Set('BACPAC', 0, 40);
  end
  else
  begin
    Command55Ran := 1;
    if Blocks[1] = $7F then
      LoadWallSet(0, 1)
    else if (GameVars^[231] <> 0) and (GameVars^[232] <> 0) then
    begin
      LoadWallSet(Blocks[1], 1);
      LoadWallSet(Blocks[3], 3);
    end
    else
      for I := 1 to 3 do
        if Blocks[I] <> $FF then
          LoadWallSet(Blocks[I], I)
        else
        begin
          WallSetSlotPairs[I].A := $FFFF;
          WallSetSlotPairs[I].B := $FFFF;
        end;
  end;
  if (AreaStepRedrawOnce <> 0) and (Command55Ran <> 0) and (Command33Ran <> 0) then
  begin
    RedrawView;
    DrawPartyRoster(SelectedCharacter);
    AreaStepRedrawOnce := 0;
  end;
end;
{ ovl03:0DEF. ECL commands 47 and 48 (dispatcher ovl03:2F2D, CurrentOpcode OpAnd or OpOr): the
  bitwise and (47) or or (48) of the values of operands 1 and 2, kept as a byte. CompareWords compares
  that byte with 0, which sets the flags of CompareFlags for the conditional commands, and the byte is
  written with WriteVmWord to the script address operand 3 names. }
procedure BitwiseCommand;
var
  Target: Word;
  Second: Word;
  First: Word;
  Combined: Byte;
begin
  DecodeOperands(3);
  First := OperandValue(1);
  Second := OperandValue(2);
  Target := MakeWord(OperandLow[3], OperandHigh[3]);
  if CurrentOpcode = OpAnd then
    Combined := First and Second
  else
    Combined := First or Second;
  CompareWords(0, Combined);
  WriteVmWord(Target, Combined);
end;
{ ovl03:0E5E. ECL command 42 (dispatcher ovl03:2F2D, CurrentOpcode $2A): copies a word out of a table.
  Operand 1 is the script address of the table, operand 2 the index (a byte) and operand 3 the script
  address the word goes to: the word at table + index is read with ReadVmWord and written with
  WriteVmWord. }
procedure CopyIndexedWordCommand;
var
  Base: Word;
  Dest: Word;
  Source: Word;
  Value: Word;
  Index: Byte;
begin
  DecodeOperands(3);
  Base := MakeWord(OperandLow[1], OperandHigh[1]);
  Index := OperandValue(2);
  Dest := MakeWord(OperandLow[3], OperandHigh[3]);
  Source := Base + Index;
  Value := ReadVmWord(Source);
  WriteVmWord(Dest, Value);
end;
{ ovl03:0EBC. ECL command 53 (dispatcher ovl03:2F2D, CurrentOpcode $35): stores operand 1 as a word
  in a table of words. Operand 2 is the script address of the table and operand 3 the index: the
  word goes to table + index with WriteVmWord. It is the store that CopyIndexedWordCommand (ovl03:0E5E,
  command 42) reads back. }
procedure StoreIndexedWordCommand;
var
  Index: Word;
  Base: Word;
  Value: Word;
  Addr: Word;
begin
  DecodeOperands(3);
  Value := OperandValue(1);
  Base := MakeWord(OperandLow[2], OperandHigh[2]);
  Index := OperandValue(3);
  Addr := Base + Index;
  WriteVmWord(Addr, Value);
end;
{ ovl03:0F08. ECL command 21 (dispatcher ovl03:2F2D, CurrentOpcode $15): a list menu. Operand 1 is
  the address that receives Choice, the index AskListMenu returns for the line the player picked.
  The prompt is the first string operand (EclStrings[1]); it is shown in the text window
  (EclTextLeft to EclTextRight, EclTextTop to EclTextBottom) and the list goes under it. Operand 3
  is the number of lines: they are the string operands EclStrings[1..Count], decoded again after
  Dec(EclPC) backs EclPC up one byte. The lines are built as a TMenuLine list (NewMenuList), each
  holding its text (at most 40 characters) and a cleared Flag29. QUIRK ovl03:0F08: AskListMenu
  leaves the chosen line in Menu (its var parameter), so FreeMenuList frees from that line on
  and the lines before it stay allocated [I]. The window is cleared afterwards. }
procedure ChooseFromListCommand;
var
  Count: Byte;
  I: Byte;
  Prompt: string;
  Menu: PMenuLine;
  MenuHead: PMenuLine;
  Empty: string[1];
  Choice: Integer;
  Redraw: Byte;
  Target: Word;
  Unused: Byte;                 { QUIRK ovl03:0F08: a byte of the frame nothing uses }
begin
  EclWindowCleared := 0;
  Redraw := 1;
  Empty := '';
  I := 1;
  DecodeOperands(3);
  Target := MakeWord(OperandLow[1], OperandHigh[1]);
  Prompt := EclStrings[1];
  Count := OperandValue(3);
  Dec(EclPC);
  DecodeOperands(Count);
  NewMenuList(Count, Menu);
  MenuHead := Menu;
  GlyphCol := EclTextLeft;
  GlyphRow := EclTextTop;
  ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1, Prompt);
  while Menu <> nil do
  begin
    Menu^.Text := EclStrings[I];
    Menu^.Flag29 := 0;
    Menu := Menu^.Next;
    Inc(I);
  end;
  Menu := MenuHead;
  Choice := 0;
  { the list starts one row below GlyphRow, where ShowPagedText left the cursor }
  AskListMenu(Empty, Empty, MenuTitleColor, MenuTextColor, MenuHotColor, EclTextLeft, GlyphRow + 1,
    EclTextRight, EclTextBottom, Menu, 0, Redraw, Choice, Menu);
  WriteVmWord(Target, Choice);
  FreeMenuList(Menu);
  ClearRect(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom);
end;
{ ovl03:10D1. ECL command 43 (dispatcher ovl03:2F2D, CurrentOpcode $2B): asks the player a menu. Operand
  1 is the address that receives the answer, operand 2 the number of options Count; the options are the
  string operands EclStrings[1..Count], decoded again after Dec(EclPC) as in ChooseFromListCommand. They
  become one text, each option after a '~' (the hotkey marker AskMenu reads, a space after all but the
  last). AskMenu (ovl07:1684) shows it on the prompt line and returns the 0-based position of the key
  pressed, $FF for a key that is no hotkey; WriteVmWord stores it. A single option
  'PRESS <RETURN> OR BUTTON TO CONTINUE' becomes 'PRESS <ENTER>/<RETURN> TO CONTINUE' and Return
  answers it (AcceptEnter). Animate is set when the close-up is up (CloseUpShown) and CloseUpHidden is set. The
  prompt line is cleared afterwards. }
procedure AskMenuCommand;
var
  Count: Byte;
  Choice: Byte;
  I: Byte;
  Title: string[1];
  Options: string[50];
  Target: Word;
  AcceptEnter: Byte;
  Animate: Byte;
  HotColor: Byte;
  WordColor: Byte;
begin
  Title := '';
  Options := '';
  DecodeOperands(2);
  Target := MakeWord(OperandLow[1], OperandHigh[1]);
  Count := OperandValue(2);
  Dec(EclPC);
  DecodeOperands(Count);
  Options := '';
  if Count = 1 then
  begin
    AcceptEnter := 1;
    HotColor := MenuHotColor;
    WordColor := MenuHotColor;
    if EclStrings[1] = 'PRESS <RETURN> OR BUTTON TO CONTINUE' then
      EclStrings[1] := 'PRESS <ENTER>/<RETURN> TO CONTINUE';
  end
  else
  begin
    AcceptEnter := 0;
    HotColor := MenuHotColor;
    WordColor := MenuTextColor;
  end;
  Animate := Ord((CloseUpShown <> 0) and (CloseUpHidden <> 0));
  for I := 1 to Count - 1 do
    Options := Options + '~' + EclStrings[I] + ' ';
  Options := Options + '~' + EclStrings[Count];
  Choice := AskMenu(Title, Options, MenuTitleColor, WordColor, HotColor, AcceptEnter, Animate);
  WriteVmWord(Target, Choice);
  ClearRect(PromptLeftCol, BottomRow, PromptLastCol, BottomRow);
end;
{ ovl03:125D. ECL command 28 (dispatcher ovl03:2F2D, CurrentOpcode $1C): clears the encounter. It has no
  operands and moves EclPC past the command. The members ECL command 11 added are dropped
  (EncounterMemberCount and EncounterMembersAdded go to 0), the icon slot EncounterIconSlot goes back to FirstEncounterIcon,
  PooledMoney is cleared, and the item list PooledItems is freed line by line (SizeOf(TMenuLine) bytes each). }
procedure ClearEncounterCommand;
var
  Next: PMenuLine;
  Unused: Word;                 { QUIRK ovl03:125D: two bytes of the frame nothing uses }
begin
  Inc(EclPC);
  EncounterMemberCount := 0;
  EncounterMembersAdded := 0;
  EncounterIconSlot := FirstEncounterIcon;
  FillChar(PooledMoney, SizeOf(TPartyMoney), 0);
  while PooledItems <> nil do
  begin
    Next := PooledItems^.Next;
    FreeMem(PooledItems, SizeOf(TMenuLine));
    PooledItems := Next;
  end;
end;
{ ovl03:12C6. ECL command 29 (dispatcher ovl03:2F2D, CurrentOpcode $1D): stores in operand 1 one byte
  computed over the whole party, the list PartyListHead followed through TCharacter.Next (+$104). For each
  member it reads the current hit points (Flag11B, +$11B), ResistValue (+$111), HitAdjust (+$110) and
  the class levels 0 and 5 (ClassLevels, +$96 and +$9B). ResistValue is lowered by ResistThreshold and
  HitAdjust by HitAdjustThreshold (0 when they are not above it). The member's share is
  HitPoints + 5 * ResistValue + 5 * HitAdjust + 8 * ClassLevel5 + 4 * ClassLevel0, divided by 10; the low
  byte of that quotient is added to the byte, which WriteVmWord stores at operand 1. Purpose unknown:
  what the script does with the value. }
procedure ComputePartyValueCommand;
var
  HitPoints: Byte;
  HitAdjust: Byte;
  ClassLevel5: Byte;
  ClassLevel0: Byte;
  ResistValue: Byte;
  Checksum: Byte;
  Target: Word;
  Member: PCharacter;
begin
  DecodeOperands(1);
  Checksum := 0;
  Member := PCharacter(PartyListHead);
  while Member <> nil do
  begin
    HitPoints := Member^.Flag11B;
    ResistValue := Member^.ResistValue;
    HitAdjust := Member^.HitAdjust;
    ClassLevel5 := Member^.ClassLevels[5];
    ClassLevel0 := Member^.ClassLevels[0];
    if ResistValue > ResistThreshold then
      ResistValue := ResistValue - ResistThreshold
    else
      ResistValue := 0;
    if HitAdjust > HitAdjustThreshold then
      HitAdjust := HitAdjust - HitAdjustThreshold
    else
      HitAdjust := 0;
    Inc(Checksum, (HitPoints + 5 * ResistValue + 5 * HitAdjust + 8 * ClassLevel5 + 4 * ClassLevel0) div 10);
    Member := Member^.Next;
  end;
  Target := MakeWord(OperandLow[1], OperandHigh[1]);
  WriteVmWord(Target, Checksum);
end;
{ ovl03:1435. ECL command 30 (dispatcher ovl03:2F2D, CurrentOpcode $1E): scans the party (PartyListHead
  followed through TCharacter.Next) and writes the answer to the script
  addresses of operands 3 to 6. Operand 1 chooses what is scanned. 0 is an affect search: operand 2
  is the affect id, HasAffect looks for it in each member's affect list, and operand 6 gets 1 when
  a member has it (the other three values are then 0). The script address $6BA7 is the thief skill 3
  of each member (TCharacter.ThiefSkills[3]) and $6C1B their movement (TCharacter.Movement): operand 3
  gets the lowest value of the party, operand 4 the highest, operand 5 the average (rounded down) and
  operand 6 gets 0. Any other operand 1 writes nothing. A type 1 operand 1 is the script address
  itself, not the word it names (OperandValue would read that word). QUIRK ovl03:1435: an empty party
  divides by zero in the two stat scans. The write-back is the nested routine WriteScanResults (the
  script addresses and the four values are its parent's locals). }
procedure ScanPartyCommand;
const
  { The script addresses of the two stats: GetCharacterVar (ovl07:07BC) reads $6BA7 as ThiefSkills[3]
    ($A7 - $A4 = 3) and $6C1B as Movement ($11B). }
  StatThiefSkill3 = $6BA7;
  StatMovement = $6C1B;
  { The lowest value starts at the largest byte. }
  StatMinStart = $FF;
var
  StatAddress: Word;            { operand 1: 0 for the affect search, else the address of a stat }
  Sum: Word;                    { the sum of the stat over the party }
  AffectId: Byte;               { operand 2: the affect the search looks for }
  Member: PCharacter;           { the party member being visited }
  Found: ShortInt;              { 1 when a member has the affect }
  Affect: Pointer;              { the affect HasAffect leaves in the search }
  Stats: array[1..3] of Byte;   { the lowest, highest and average values (written to operands 3 to 5) }
  MinAddr: Word;                { operand 3: script address of the lowest value }
  MaxAddr: Word;                { operand 4: script address of the highest value }
  AverageAddr: Word;            { operand 5: script address of the average }
  FoundAddr: Word;              { operand 6: script address of the affect flag }
  I: Byte;                      { the party members counted, then the loop counter }

  { ovl03:13D7. Writes the four results of the scan to the script addresses of operands 3 to 6. It
    reaches the parent's locals through the static link (push bp; push cs; call). }
  procedure WriteScanResults;
  begin
    WriteVmWord(MinAddr, Stats[1]);
    WriteVmWord(MaxAddr, Stats[2]);
    WriteVmWord(AverageAddr, Stats[3]);
    WriteVmWord(FoundAddr, Found);
  end;
begin
  DecodeOperands(6);
  Member := PCharacter(PartyListHead);
  Found := 0;
  if OperandType[1] = 1 then
    StatAddress := MakeWord(OperandLow[1], OperandHigh[1])
  else
    StatAddress := OperandValue(1);
  AffectId := OperandValue(2);
  MinAddr := MakeWord(OperandLow[3], OperandHigh[3]);
  MaxAddr := MakeWord(OperandLow[4], OperandHigh[4]);
  AverageAddr := MakeWord(OperandLow[5], OperandHigh[5]);
  FoundAddr := MakeWord(OperandLow[6], OperandHigh[6]);
  Sum := 0;
  I := 0;
  Stats[1] := StatMinStart;
  Stats[2] := 0;
  case StatAddress of
    0:
      begin
        while (Member <> nil) and (Found = 0) do
        begin
          Found := Ord(HasAffect(Member, AffectId, Affect));
          Member := Member^.Next;
        end;
        for I := 1 to 3 do
          Stats[I] := 0;
        WriteScanResults;
      end;
    StatThiefSkill3:
      begin
        while Member <> nil do
        begin
          Inc(I);
          if Member^.ThiefSkills[3] < Stats[1] then
            Stats[1] := Member^.ThiefSkills[3];
          if Member^.ThiefSkills[3] > Stats[2] then
            Stats[2] := Member^.ThiefSkills[3];
          Inc(Sum, Member^.ThiefSkills[3]);
          Member := Member^.Next;
        end;
        Stats[3] := Sum div I;
        WriteScanResults;
      end;
    StatMovement:
      begin
        while Member <> nil do
        begin
          Inc(I);
          if Member^.Movement < Stats[1] then
            Stats[1] := Member^.Movement;
          if Member^.Movement > Stats[2] then
            Stats[2] := Member^.Movement;
          Inc(Sum, Member^.Movement);
          Member := Member^.Next;
        end;
        Stats[3] := Sum div I;
        WriteScanResults;
      end;
  end;
end;
{ ovl03:1629. ECL command 34 (dispatcher ovl03:2F2D, CurrentOpcode $22): reports whether a party member
  has the class mask 4 or 10. It walks the party list PartyListHead (through TCharacter.Next) and tests the
  ClassMask (+$2F) of each member: a member with 4 or 10 sets the flag. Operand 1 receives the flag (1
  or 0) and operand 2 the second value, which the original always writes as 0 (QUIRK ovl03:1629: the
  Mark byte is set with the flag and never read). Mask 10 is one of the multi-class values AwardExperience
  halves (ovl05:0355); mask 4 is not named yet. }
procedure CheckPartyHasRangerCommand;
var
  Member: PCharacter;           { the party member being tested }
  Found: Byte;                  { 1 when a member has a class mask of 4 or 10 }
  Second: Byte;                 { the value operand 2 receives: always 0 }
  Mark: Byte;                   { QUIRK ovl03:1629: set with Found, never read }
  Target: Word;                 { operand 1: script address of Found }
  SecondTarget: Word;           { operand 2: script address of Second }
  Unused: Byte;                 { QUIRK ovl03:1629: a byte of the frame nothing uses }
begin
  DecodeOperands(2);
  Member := PCharacter(PartyListHead);
  Found := 0;
  Second := 0;
  Mark := 0;
  while Member <> nil do
  begin
    if (Member^.ClassMask = 4) or (Member^.ClassMask = 10) then
    begin
      Found := 1;
      Mark := 1;
    end;
    Member := Member^.Next;
  end;
  Target := MakeWord(OperandLow[1], OperandHigh[1]);
  SecondTarget := MakeWord(OperandLow[2], OperandHigh[2]);
  WriteVmWord(Target, Found);
  WriteVmWord(SecondTarget, Second);
end;
{ ovl03:16C9. ECL command 35 (dispatcher ovl03:2F2D, CurrentOpcode $23): rolls two six-sided dice and
  writes an outcome, 0 to 2, to the script address $6DCB (word 715 of GameVars2, which RunCombat clears
  every round, VarSurpriseSides in ovl08). Operands 1 to 4 are four values. Width is operand 4 + 2 -
  operand 1 and Height is operand 2 + 2 - operand 3 (signed bytes). The first roll must not exceed
  Width and the second must be above Height for outcome 1; a second roll at most Height gives outcome
  2 whatever the first roll did; otherwise the outcome is 0. Purpose unknown: what the script does with
  the outcome. QUIRK ovl03:175F: the value 3 is set when the first roll fits and the second is at most
  Height, but the test that follows overwrites it with 2 (ovl03:1769), so 3 is never written. }
procedure RollSurpriseCommand;
const
  SurpriseWordAddr = $6DCB;
var
  RollA: Byte;                  { the first d6 }
  RollB: Byte;                  { the second d6 }
  I: Byte;
  Kind: Byte;                   { the outcome written to SurpriseWordAddr }
  Values: array[1..4] of Byte;  { operands 1 to 4 }
  Width: ShortInt;              { operand 4 + 2 - operand 1 }
  Height: ShortInt;             { operand 2 + 2 - operand 3 }
begin
  DecodeOperands(4);
  Kind := 0;
  for I := 1 to 4 do
    Values[I] := OperandValue(I);
  Width := Values[4] + 2 - Values[1];
  Height := Values[2] + 2 - Values[3];
  RollA := RollDice(1, 6);
  RollB := RollDice(1, 6);
  if RollA <= Width then
  begin
    if RollB <= Height then
      Kind := 3
    else
      Kind := 1;
  end;
  if RollB <= Height then
    Kind := 2;
  WriteVmWord(SurpriseWordAddr, Kind);
end;
{ ovl03:179B. ECL command 36 (dispatcher ovl03:2F2D, CurrentOpcode $24): the area logic. ShopMain
  (ovl06:053E) and RunCombat (ovl08:007A) name ovl03 as their caller. It has no operands; Inc(EclPC)
  steps the program counter past the opcode so RunScriptFrom (ovl03:3171) reads the next command (see
  EclPC). An encounter is pending when EncounterMembersAdded (set by ECL command 11) or DuelMode is set.
  Without one, a shop or temple the script asked for comes first: when word VarShopRequest of GameVars2
  is 1 it is cleared and ShopMain runs, else when VarTempleRequest is 1 it is cleared and VisitTemple
  runs; with neither request EndBattle runs. With an encounter, VarStepsAhead becomes the lower of its
  value and the steps ahead (OpenStepsAhead), RunCombat and EndBattle run, and when VarForceWallView is
  clear the BACPAC set (Load24x24Set) and the ICON pictures 0 to 2 are loaded into picture slots 9 to
  11. DuelMode is then cleared. Both paths end by setting the view mode ViewMode to 4 when AreaViewKind is 1,
  else 3, keeping only the low bit of VarTravelMode, clearing PictureShown and CloseUpShown, and redrawing the
  screen (RedrawView). }
procedure RunAreaEventCommand;
var
  Steps: Word;                  { the steps ahead the party sees, from OpenStepsAhead }
begin
  Inc(EclPC);
  if (EncounterMembersAdded = 0) and (DuelMode = 0) then
  begin
    if GameVars2^[VarShopRequest] = 1 then
    begin
      GameVars2^[VarShopRequest] := 0;
      ShopMain;
    end
    else if GameVars2^[VarTempleRequest] = 1 then
    begin
      GameVars2^[VarTempleRequest] := 0;
      VisitTemple;
    end
    else
      EndBattle;
  end
  else
  begin
    Steps := OpenStepsAhead(PartyMapColumn, PartyMapRow, PartyFacing);
    if Steps < GameVars2^[VarStepsAhead] then
      GameVars2^[VarStepsAhead] := Steps;
    RunCombat;
    EndBattle;
    if GameVars^[VarForceWallView] = 0 then
    begin
      Load24x24Set('BACPAC', 0, 40);
      LoadPictureSlot('ICON', 0, 9);
      LoadPictureSlot('ICON', 1, 10);
      LoadPictureSlot('ICON', 2, 11);
    end;
    if DuelMode <> 0 then
      DuelMode := 0;
  end;
  if AreaViewKind = 1 then
    ViewMode := ViewModeWall
  else
    ViewMode := ViewModeMap;
  GameVars2^[VarTravelMode] := GameVars2^[VarTravelMode] and 1;
  FillChar(PictureShownFlags, 2, 0);
  CloseUpShown := 0;
  RedrawView;
end;
{ ovl03:18F8. ECL commands 37 and 38 (dispatcher ovl03:2F2D, CurrentOpcode OpChooseAddress or 38):
  choose one of the script addresses that follow the command. Operand 1 is the choice and operand 2
  the number of addresses; a second DecodeOperands reads them, so operand I+1 is the address for choice
  I. Nothing is chosen when the choice is not below the count. Command 37 stores the chosen address in
  EclPC (its readers are not traced yet), command 38 runs it as a subroutine (ScriptGosub). EclPC goes
  down by one on every call, before the choice is made. }
procedure SelectCaseCommand;
var
  Choice: Byte;
  Count: Byte;
  Unused: Byte;                 { QUIRK ovl03:18F8: a byte of the frame nothing uses }
  I: Byte;
  Taken: Boolean;
  Unused2: Byte;                { QUIRK ovl03:18F8: a byte of the frame nothing uses }
begin
  Taken := False;
  DecodeOperands(2);
  Choice := OperandValue(1);
  Count := OperandValue(2);
  Dec(EclPC);
  DecodeOperands(Count);
  I := 0;
  while (I < Count) and (not Taken) do
  begin
    if Choice = I then
    begin
      if CurrentOpcode = OpChooseAddress then
        EclPC := MakeWord(OperandLow[I + 1], OperandHigh[I + 1])
      else
        ScriptGosub(I + 1);
      Taken := True;
    end
    else
      Inc(I);
  end;
end;
{ ovl03:19B0. ECL command 39 (dispatcher ovl03:2F2D, CurrentOpcode $27): adds loot to the loot list PooledItems
  (the list ComputeBattleExperience, ovl05:0000, fills). Operands 1 to 7 set PooledMoney (each read as a
  word); operand 8 is the Kind of the loot:
  - a Kind below TreasureTableBase is an item block: every 63-byte record of ITEM<TileSet>.dax block Kind
    (LoadDaxBlock) is linked in front of PooledItems, then the block is freed. An empty block (size 0) shows
    ItemErrorColor's message and ends the game (QuitGame).
  - NoTreasure adds nothing.
  - any other Kind is a treasure table with Kind - TreasureTableBase rolls. Each roll adds one item in
    front of PooledItems (BuildTreasureItem, with the roll's Code). After the rolls FormatItemLine runs for every
    item of the list with SelectedCharacter (its meaning is not traced yet).
  The Code of a roll: Chance (d100) of 1 to 60 picks Roll2, a second d100. 1 to 47 and 50 to 59 are the
  kind itself (45 gives ';'); 60 to 90 a d10 gives '$', '#', '"', '%' or '&' for 1 to 4, 5 to 7, 8, 9 or
  10; 91 to 94 gives 'I', 95 to 97 ']' and 98 to 100 'M'. Roll2 of 48 or 49 keeps the Code of the
  previous roll (QUIRK ovl03:1BB7). Chance 61 to 85 gives '=', 86 to 92 '>', 93 to 98 a d16 gives 'G',
  'F', 'T', 'N', 'O', '\' or 'C' for 1 to 7, 8 or 9, 10, 11 or 12, 13 or 14, 15 and 16, and 99 or 100
  gives 'E'. }
procedure AddLootCommand;
var
  Index: ShortInt;              { the money loop counter, then the number of rolls }
  Kind: Byte;
  Treasure: Byte;               { the roll being made }
  Unused: array[0..22] of Byte; { QUIRK ovl03:19B0: 23 bytes of the frame nothing uses }
  Item: TMenuLine;
  Entry: PMenuLine;
  Node: PMenuLine;
  Pick: Byte;
  Chance: Byte;
  Roll2: Byte;                  { the second d100 of a roll, then the d10 of the 60..90 group }
  Code: Char;                   { the kind of the item the roll builds }
  Offset: Word;
  Size: Word;
  TileSetText: string[1];
  Block: Pointer;
begin
  DecodeOperands(8);
  for Index := 0 to 6 do
    PooledMoney[Index] := OperandValue(Byte(Index) + 1);
  Kind := OperandValue(8);
  if Kind < TreasureTableBase then
  begin
    Str(TileSet, TileSetText);
    LoadDaxBlock('ITEM' + TileSetText, '.dax', Kind, Size, Block);
    if Size = 0 then
    begin
      ShowMessageLine(ItemErrorColor, 'Unable to find item file');
      QuitGame;
    end;
    Offset := 0;
    repeat
      Move(PByteArray(Block)^[Offset], Item, SizeOf(Item));
      Item.Next := nil;
      Inc(Offset, SizeOf(Item));
      if PooledItems = nil then
      begin
        New(PooledItems);
        PooledItems^ := Item;
      end
      else
      begin
        Entry := PooledItems;
        New(PooledItems);
        PooledItems^ := Item;
        PooledItems^.Next := Entry;
      end;
    until Offset >= Size;
    FreeMem(Block, Size);
  end
  else if Kind <> NoTreasure then
  begin
    Index := Kind - TreasureTableBase;
    for Treasure := 1 to Index do
    begin
      Chance := RollDice(1, 100);
      case Chance of
        1..60:
          begin
            Roll2 := RollDice(1, 100);
            case Roll2 of
              1..47, 50..59:
                if Roll2 = 45 then
                  Code := ';'
                else
                  Code := Chr(Roll2);
              60..90:
                begin
                  Roll2 := RollDice(1, 10);
                  case Roll2 of
                    1..4: Code := '$';
                    5..7: Code := '#';
                    8: Code := '"';
                    9: Code := '%';
                    10: Code := '&';
                  end;
                end;
              91..94: Code := 'I';
              95..97: Code := ']';
              98..100: Code := 'M';
            end;
          end;
        61..85: Code := '=';
        86..92: Code := '>';
        { 91 and 92 are taken by 86..92 above; the label is 91..98 as the original compares it }
        91..98:
          begin
            Pick := RollDice(1, 16);
            case Pick of
              1..7: Code := 'G';
              8..9: Code := 'F';
              10: Code := 'T';
              11, 12: Code := 'N';
              13, 14: Code := 'O';
              15: Code := '\';
              16: Code := 'C';
            end;
          end;
        99, 100: Code := 'E';
      end;
      BuildTreasureItem(Ord(Code), Item);
      if PooledItems = nil then
      begin
        New(PooledItems);
        PooledItems^ := Item;
        PooledItems^.Next := nil;
      end
      else
      begin
        Entry := PooledItems;
        New(PooledItems);
        PooledItems^ := Item;
        PooledItems^.Next := Entry;
      end;
    end;
    Node := PooledItems;
    while Node <> nil do
    begin
      FormatItemLine(LongInt(SelectedCharacter), Node, 0, 0, 0, 0);
      Node := Node^.Next;
    end;
  end;
end;
{ ovl03:1DB1. ECL command 40 (dispatcher ovl03:2F2D, CurrentOpcode $28): takes a share of the money and
  the items. Operand 1 is Mode: 0 takes it from the selected character only, any other value from every
  member of the party (the list PartyListHead, followed through TCharacter.Next, +$104). Operand 2 is the
  percentage Percent: each member's money is scaled by (100 - Percent) / 100 (ScaleMoney), and each item
  is lost on a d100 roll at most Percent (LoseItems). Operand 2 is read a second time for the chance, the
  same value unless the operand is a variable that changed. Operand 3 is decoded and not read. }
procedure LoseMoneyAndItemsCommand;
var
  Mode: Byte;
  Percent: Byte;
  Chance: Byte;
  Member: PCharacter;
  Items: PItem;                 { QUIRK ovl03:1DB1: the member's item list is read into Items and never used }
  Factor: Real;
  Unused: Byte;                 { QUIRK ovl03:1DB1: a byte of the frame nothing uses }
begin
  DecodeOperands(3);
  Mode := OperandValue(1);
  Percent := OperandValue(2);
  Factor := (100 - Percent) / 100;
  Chance := OperandValue(2);
  if Mode = 0 then
  begin
    ScaleMoney(Factor, SelectedCharacter);
    LoseItems(Chance, SelectedCharacter);
  end
  else
  begin
    Member := PCharacter(PartyListHead);
    while Member <> nil do
    begin
      Items := Member^.Items;
      ScaleMoney(Factor, Member);
      LoseItems(Chance, Member);
      Member := Member^.Next;
    end;
  end;
end;
{ ovl03:1EF8. ECL command 41 (dispatcher ovl03:2F2D, opcode 41): the encounter action menu.
  It shows the encounter the way command 12 does (operand 1 the sprite bank, operand 2 the distance
  limit kept in word VarEncounterLimit of GameVars2, operand 3 the picture bank, the steps ahead cut
  down to that limit), then asks COMBAT, WAIT, FLEE and either ADVANCE or PARLAY. ADVANCE is the
  fourth word only when steps remain and GameVars word VarForceWallView is set; otherwise that word
  is PARLAY and a pick of it is choice 4, not 3. Operand 4 is the script address the outcome is
  written to (MakeWord of its two bytes; OperandValue never reads it). Operands 5 to 9 are the kind
  of choices 0 to 4, and the kind selects which outcome table runs. The first three string operands
  are unpacked into EclStrings[1..3] and copied to the prompt candidates; the prompt shown is the
  first non-empty candidate, searched from the one after the steps ahead and wrapping over 1 to 3.
  Operand 13 is the movement a flee needs, compared with the party's slowest (MovementRange);
  operand 14 is the monsters' movement, compared with the party's fastest.
  The word written is 0 with 'The monsters flee.', 1 for a fight or a flee the movement check
  refuses, 2 for a flee the check allows (and for the flee choice in kinds 1, 3 and 4), and 3 when
  a parlay path has no step left. A step closer, or 'Both sides wait.', sets MenuAgain and the menu
  is asked again. SkipCloseUpIfNoPics is set for the whole command, so ShowEncounterPicture skips the close-up
  unless monster pictures are on; EclWindowCleared is cleared and DelayPerGlyph is set, so DrawTextRun waits after
  each glyph. The prompt line is cleared on the way out.
  QUIRK ovl03:210A: steps ahead other than 0, 1 or 2 leave the prompt (Lines[0]) unset. }
procedure EncounterActionCommand;
var
  Choice: Byte;                 { the menu item AskMenu returns: 0 combat, 1 wait, 2 flee, 3 advance, 4 parlay }
  ChoiceKinds: array[0..4] of Byte;  { operands 5 to 9: the kind of each choice }
  Lines: array[0..3] of string; { Lines[1..3] the candidate prompts, Lines[0] the one shown }
  FleeMovement: Byte;           { operand 13: slowest party movement that still flees }
  MonsterMovement: Byte;        { operand 14: the monsters' movement }
  I: Byte;
  Fastest: Byte;                { the party's fastest movement (MovementRange) }
  Slowest: Byte;                { the party's slowest movement (MovementRange) }
  MenuAgain: Byte;              { 1 repeats the menu after a step or a wait text }
  ClearWindow: Byte;            { 1 clears the text window; 0 when the prompt is empty }
  Animate: Byte;                { 1 animates the menu while the close-up is up }
  Options: string[40];          { '~COMBAT ~WAIT ~FLEE' and '~ADVANCE' or '~PARLAY' }
  Title: string[1];             { the menu title: empty }
  ChoiceKind: Byte;             { the kind of the item picked }
  Line: Byte;                   { the candidate prompt being tried }
  ResultAddr: Word;             { operand 4: script address of the outcome }
begin
  SkipCloseUpIfNoPics := 1;
  EclWindowCleared := 0;
  DelayPerGlyph := 1;
  MovementRange(Fastest, Slowest);
  Title := '';
  DecodeOperands(14);
  EncounterSpriteBank := OperandValue(1);
  GameVars2^[VarEncounterLimit] := OperandValue(2);
  EncounterPicBank := OperandValue(3);
  ResultAddr := MakeWord(OperandLow[4], OperandHigh[4]);
  for I := 0 to 4 do
    ChoiceKinds[I] := OperandValue(I + 5);
  for I := 1 to 3 do
    Lines[I] := EclStrings[I];
  FleeMovement := OperandValue(13);
  MonsterMovement := OperandValue(14);
  GameVars2^[VarStepsAhead] := OpenStepsAhead(PartyMapColumn, PartyMapRow, PartyFacing);
  if GameVars2^[VarEncounterLimit] < GameVars2^[VarStepsAhead] then
    GameVars2^[VarStepsAhead] := GameVars2^[VarEncounterLimit];
  ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank, Byte(GameVars2^[VarStepsAhead]), PictureShown);
  repeat
    Animate := Ord((CloseUpShown <> 0) and (CloseUpHidden <> 0));
    ClearWindow := 1;
    MenuAgain := 0;
    GlyphCol := EclTextLeft;
    GlyphRow := EclTextTop;
    case GameVars2^[VarStepsAhead] of
      0:
        begin
          Line := 1;
          repeat
            Lines[0] := Lines[Line];
            Inc(Line);
          until (Length(Lines[0]) <> 0) or (Line > 3);
        end;
      1:
        begin
          Line := 2;
          repeat
            Lines[0] := Lines[Line];
            Inc(Line);
            if Line > 3 then
              Line := 1;
          until (Length(Lines[0]) <> 0) or (Line = 2);
        end;
      2:
        begin
          Line := 3;
          repeat
            Lines[0] := Lines[Line];
            Inc(Line);
            if Line > 3 then
              Line := 1;
          until (Length(Lines[0]) <> 0) or (Line = 3);
        end;
    end;
    if Length(Lines[0]) = 0 then
      ClearWindow := 0;
    ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, ClearWindow, Lines[0]);
    { PARLAY is tested first so its literal is emitted before ADVANCE (pool at ovl03:1E9B). }
    if (GameVars2^[VarStepsAhead] = 0) or (GameVars^[VarForceWallView] = 0) then
      Options := '~COMBAT ~WAIT ~FLEE ~PARLAY'
    else
      Options := '~COMBAT ~WAIT ~FLEE ~ADVANCE';
    Choice := AskMenu(Title, Options, MenuTitleColor, MenuTextColor, MenuHotColor, 0, Animate);
    if (GameVars2^[VarStepsAhead] = 0) or (GameVars^[VarForceWallView] = 0) then
      if Choice = AdvanceChoice then
        Choice := ParlayChoice;
    ChoiceKind := ChoiceKinds[Choice];
    case ChoiceKind of
      0:
        if Choice <> FleeChoice then
          WriteVmWord(ResultAddr, FightResult)
        else if Slowest >= FleeMovement then
          WriteVmWord(ResultAddr, PartyFleesResult)
        else
          WriteVmWord(ResultAddr, FightResult);
      1:
        case Choice of
          CombatChoice: WriteVmWord(ResultAddr, FightResult);
          WaitChoice:
            begin
              MenuAgain := 1;
              ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1,
                'Both sides wait.');
            end;
          FleeChoice: WriteVmWord(ResultAddr, PartyFleesResult);
          AdvanceChoice:
            begin
              if GameVars2^[VarStepsAhead] <> 0 then
              begin
                Dec(GameVars2^[VarStepsAhead]);
                ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank,
                  Byte(GameVars2^[VarStepsAhead]), PictureShown);
              end
              else
                ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1,
                  'Both sides wait.');
              MenuAgain := 1;
            end;
          ParlayChoice:
            if GameVars2^[VarStepsAhead] <= 0 then
              WriteVmWord(ResultAddr, ParlayResult)
            else
            begin
              Dec(GameVars2^[VarStepsAhead]);
              ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank,
                Byte(GameVars2^[VarStepsAhead]), PictureShown);
              MenuAgain := 1;
            end;
        end;
      2:
        case Choice of
          CombatChoice:
            if MonsterMovement > Fastest then
            begin
              WriteVmWord(ResultAddr, MonstersFleeResult);
              GlyphCol := EclTextLeft;
              GlyphRow := EclTextTop;
              ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1,
                'The monsters flee.');
            end
            else
              WriteVmWord(ResultAddr, FightResult);
          WaitChoice..ParlayChoice:
            begin
              WriteVmWord(ResultAddr, MonstersFleeResult);
              GlyphCol := EclTextLeft;
              GlyphRow := EclTextTop;
              ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1,
                'The monsters flee.');
            end;
        end;
      3:
        case Choice of
          CombatChoice: WriteVmWord(ResultAddr, FightResult);
          WaitChoice, AdvanceChoice:
            begin
              if GameVars2^[VarStepsAhead] <> 0 then
              begin
                Dec(GameVars2^[VarStepsAhead]);
                ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank,
                  Byte(GameVars2^[VarStepsAhead]), PictureShown);
              end
              else
                ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1,
                  'Both sides wait.');
              MenuAgain := 1;
            end;
          FleeChoice: WriteVmWord(ResultAddr, PartyFleesResult);
          ParlayChoice:
            if GameVars2^[VarStepsAhead] <= 0 then
              WriteVmWord(ResultAddr, ParlayResult)
            else
            begin
              Dec(GameVars2^[VarStepsAhead]);
              ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank,
                Byte(GameVars2^[VarStepsAhead]), PictureShown);
              MenuAgain := 1;
            end;
        end;
      4:
        case Choice of
          CombatChoice: WriteVmWord(ResultAddr, FightResult);
          WaitChoice, AdvanceChoice, ParlayChoice:
            if GameVars2^[VarStepsAhead] <= 0 then
              WriteVmWord(ResultAddr, ParlayResult)
            else
            begin
              Dec(GameVars2^[VarStepsAhead]);
              ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank,
                Byte(GameVars2^[VarStepsAhead]), PictureShown);
              MenuAgain := 1;
            end;
          FleeChoice: WriteVmWord(ResultAddr, PartyFleesResult);
        end;
    end;
  until MenuAgain = 0;
  ClearRect(PromptLeftCol, BottomRow, PromptLastCol, BottomRow);
  DelayPerGlyph := 0;
  SkipCloseUpIfNoPics := 0;
end;
{ ovl03:25CB. ECL command 44 (dispatcher ovl03:2F2D, CurrentOpcode 2Ch): asks the player for an attitude.
  The menu offers AttitudeMenu's words (HAUGHTY, SLY, NICE, MEEK and ABUSIVE) under a blank title. Operands
  1 to 5 are the value of each attitude in that order, and the value of the one the player picks is written
  with WriteVmWord to the script address operand 6 names. Purpose unknown: what the script does with the
  value (not traced yet). }
procedure ChooseAttitudeCommand;
var
  Choice: Byte;                 { the 0-based attitude AskMenu returns }
  Value: Byte;                  { the value of the chosen attitude }
  I: Byte;
  Values: array[0..4] of Byte;  { operands 1 to 5 }
  Target: Word;                 { operand 6: script address of Value }
  BlankTitle: Char;
begin
  DecodeOperands(6);
  BlankTitle := ' ';
  for I := 0 to 4 do
    Values[I] := OperandValue(I + 1);
  Choice := AskMenu(BlankTitle, AttitudeMenu, MenuTitleColor, MenuTextColor, MenuHotColor, 0, 0);
  Target := MakeWord(OperandLow[6], OperandHigh[6]);
  Value := Values[Choice];
  WriteVmWord(Target, Value);
end;
{ ovl03:266A. ECL command 50 (dispatcher ovl03:2F2D, CurrentOpcode 32h): tests whether a party member carries
  an item of the type operand 1 names. It walks the party list PartyListHead (through TCharacter.Next) and each
  member's carried items (TCharacter.Items, +$C8; TMenuLine.Next at +$2A), comparing the ItemType (+$2E) of
  each with the operand, and stops at the first match. CompareFlags[0] (equal) is set and [1] (not equal)
  cleared when one is found, else [1] is set; the conditional commands 22 to 27 (ovl03:0B52) test them.
  Purpose unknown: which item types the script tests. }
procedure ComparePartyItemCommand;
var
  ItemType: Byte;
  Unused: Byte;                 { QUIRK ovl03:266A: a byte of the frame nothing uses }
  Member: PCharacter;
  Item: PItem;
  Found: Boolean;
begin
  DecodeOperands(1);
  Found := False;
  ItemType := OperandValue(1);
  FillChar(CompareFlags, SizeOf(CompareFlags), 0);
  CompareFlags[1] := 1;
  Member := PCharacter(PartyListHead);
  while (Member <> nil) and (not Found) do
  begin
    Item := Member^.Items;
    while (Item <> nil) and (not Found) do
    begin
      if ItemType = Item^.ItemType then
      begin
        CompareFlags[0] := 1;
        CompareFlags[1] := 0;
        Found := True;
      end;
      Item := Item^.Next;
    end;
    Member := Member^.Next;
  end;
end;
{ ovl03:271F. ECL command 58 (dispatcher ovl03:2F2D, CurrentOpcode 3Ah): pauses the script for the game
  speed (DelayByGameSpeed, RES06: GameSpeed * 225 milliseconds). It has no operands; Inc(EclPC) steps the
  program counter past the opcode so RunScriptFrom (ovl03:3171) reads the next command (see EclPC). }
procedure PauseCommand;
begin
  Inc(EclPC);
  DelayByGameSpeed;
end;
{ ovl03:2775. ECL command 46 (dispatcher ovl03:2F2D, CurrentOpcode 2Eh): damages the party, a trap or an
  ambush. Operands 2 to 4 are the damage (RollDice(DamageDice, DamageSides) + DamageBonus, rolled again for each
  hit of the random mode). Operand 1 (Flags) bit 7 (TrapSavingThrowBit) is the saving-throw mode: the target
  takes the damage unless SavingThrow (bonus: the low five bits of Flags, kind: the low three bits of operand
  5) succeeds for it, or unconditionally when bit 5 (TrapUnsavedBit) is set. In that mode the target is the
  whole party when bit 6 (TrapWholePartyBit) is set (each member saves), else the selected character when
  operand 5 bit 7 (TrapSelectedBit) is set (the kind minus one: 0 means no save, 1..5 the five SavingThrows [I];
  QUIRK: kinds 6 and 7
  index past them), else one
  random member (RollDice over the party size VarPartySize). With bit 7 clear, Flags is the number of hits,
  each on a random member of the party list PartyListHead, that takes the damage when RollBeatsResistance (operand 5)
  succeeds for it. QUIRK ovl03:2775: with bit 7 clear bit 6 is not a mode here and counts into that number:
  MemberNumber is not rolled and the loop `for I := 1 to Flags` runs once per bit, so Flags $40 or more means
  64 or more hits. DamageWithMessage (ovl07:20CC) does the damage. Then PartyDestroyed is 1 unless a member has
  Flag10D (combat participation) set; when it is 1 the window 'The END!' shows 'The entire party is killed!'
  and the game waits 3 seconds. The selected character is restored and 'press <enter>/<return> to continue'
  is shown. Purpose unknown: which events use it. }
procedure DamagePartyCommand;
var
  Flags: Byte;
  DamageDice: Byte;
  DamageSides: Byte;
  I: Byte;
  SaveBonus: Byte;
  Resistance: Byte;
  DamageBonus: Byte;
  MemberNumber: Byte;
  SaveKind: Byte;
  Step: Byte;
  Damage: Word;
  Who: PCharacter;
  Member: PCharacter;
  SavedCharacter: PCharacter;
  Unused: Boolean;              { QUIRK ovl03:2775: set to False, never read }
  WholePartyHit: Boolean;
begin
  SavedCharacter := SelectedCharacter;
  Unused := False;
  WholePartyHit := False;
  Who := PCharacter(PartyListHead);
  DecodeOperands(5);
  Flags := OperandValue(1);
  DamageDice := OperandValue(2);
  DamageSides := OperandValue(3);
  DamageBonus := OperandValue(4);
  Resistance := OperandValue(5);
  Damage := RollDice(DamageDice, DamageSides) + DamageBonus;
  if (Flags and TrapWholePartyBit) <> 0 then
    WholePartyHit := True
  else
    MemberNumber := RollDice(1, Byte(GameVars2^[VarPartySize]));
  if (Flags and TrapSavingThrowBit) <> 0 then
  begin
    SaveBonus := Flags and TrapBonusMask;
    SaveKind := Resistance and TrapKindMask;
    if WholePartyHit then
    begin
      while Who <> nil do
      begin
        if (Flags and TrapUnsavedBit) <> 0 then
          DamageWithMessage(Damage, Who)
        else if not SavingThrow(Who, SaveKind, SaveBonus) then
          DamageWithMessage(Damage, Who);
        Who := Who^.Next;
      end;
    end
    else if (Resistance and TrapSelectedBit) <> 0 then
    begin
      if (SaveKind = 0) or (not SavingThrow(SelectedCharacter, SaveKind - 1, SaveBonus)) then
        DamageWithMessage(Damage, SelectedCharacter);
    end
    else
    begin
      for I := 2 to MemberNumber do
        Who := Who^.Next;
      if not SavingThrow(Who, SaveKind, SaveBonus) then
        DamageWithMessage(Damage, Who);
    end;
  end
  else
  begin
    { QUIRK ovl03:2775: bit 7 clear, so Flags is the number of hits, counted per bit: bit 6 (and bit 5)
      adds to it here, and when bit 6 is set MemberNumber was not rolled above. }
    for I := 1 to Flags do
    begin
      Who := PCharacter(PartyListHead);
      MemberNumber := RollDice(1, Byte(GameVars2^[VarPartySize]));
      Step := 1;
      while Step < MemberNumber do
      begin
        Who := Who^.Next;
        Inc(Step);
      end;
      if RollBeatsResistance(Who, Resistance) then
        DamageWithMessage(Damage, Who);
      Damage := RollDice(DamageDice, DamageSides) + DamageBonus;
    end;
  end;
  Member := PCharacter(PartyListHead);
  PartyDestroyed := 1;
  while Member <> nil do
  begin
    if Member^.Flag10D <> 0 then
      PartyDestroyed := 0;
    Member := Member^.Next;
  end;
  if PartyDestroyed <> 0 then
  begin
    DrawWindow(EndWindowLeft, EndWindowTop, EndWindowRight, EndWindowBottom, 0, EndWindowColor, 'The END!');
    GlyphCol := 2;
    GlyphRow := 2;
    ShowPagedText(EndWindowLeft, EndWindowTop, EndWindowRight, EndWindowBottom, EndTextColor, 1,
      'The entire party is killed!');
    Delay(EndPauseMs);
  end;
  SelectedCharacter := SavedCharacter;
  ShowMessageLine(ContinueColor, 'press <enter>/<return> to continue');
end;
{ ovl03:2AA2. ECL command 49 (dispatcher ovl03:2F2D, CurrentOpcode 31h): redraws the area view when the 3D
  encounter sprite is loaded (Sprite3DLoaded, set by ShowEncounterPicture), as the hiding path of ShowCloseUpCommand
  does, then clears the sprite flag and the close-up flag CloseUpShown. It has no operands; Inc(EclPC) steps the
  program counter past the opcode so RunScriptFrom (ovl03:3171) reads the next command (see EclPC).
  Purpose unknown: why the script redraws the area. }
procedure RedrawAreaViewCommand;
begin
  Inc(EclPC);
  if Sprite3DLoaded <> 0 then
  begin
    ShowAreaView;
    Sprite3DLoaded := 0;
    CloseUpShown := 0;
  end;
end;
{ ovl03:2AC1. ECL command 52 (dispatcher ovl03:2F2D, CurrentOpcode 34h): passes time. Operand 1 is the
  amount, and AdvanceGameClock advances the game clock by that many units of digit 1 (the digit the camp's
  rest, RunRestPeriod in ovl20, advances in steps of 5). QUIRK ovl03:2AC1: Amount is passed to
  OperandValue as the operand number before the routine has set it, so the operand read is whatever
  byte the frame held on entry; the compiled code does exactly this. }
procedure PassTimeCommand;
var
  Amount: Byte;
  Unused: Byte;                 { QUIRK ovl03:2AC1: a byte of the frame nothing uses }
begin
  DecodeOperands(1);
  Amount := OperandValue(Amount);
  AdvanceGameClock(Amount, 1);
end;
{ ovl03:2AEB. ECL command 51 (dispatcher ovl03:2F2D, CurrentOpcode 33h): starts a new line of text. The
  text cursor (GlyphCol, GlyphRow, the glyph position ShowPagedText keeps) goes to column 1 of the next
  row. GlyphRunPending is cleared when it is set; the cursor moves the same way on both branches, which the
  original compiles as two branches. Inc(EclPC) steps the program counter past the opcode so RunScriptFrom
  (ovl03:3171) reads the next command (see EclPC). }
procedure NewLineCommand;
begin
  Inc(EclPC);
  if GlyphRunPending <> 0 then
  begin
    GlyphCol := EclTextLeft;
    Inc(GlyphRow);
    GlyphRunPending := 0;
  end
  else
  begin
    GlyphCol := EclTextLeft;
    Inc(GlyphRow);
  end;
end;
{ ovl03:2B14. ECL command 61 (dispatcher ovl03:2F2D, CurrentOpcode 3Dh): clears the picture window, the
  box at columns 1 to 15 and rows 1 to 15 that frames the encounter picture (ShowCloseUpCommand draws
  the close-up inside the box at 3 to 13, and EndCommand draws this box as a frame). Then GlyphRunInBox is set
  (its meaning is not traced; EndCommand clears it). Inc(EclPC) steps the program counter past the opcode
  so RunScriptFrom (ovl03:3171) reads the next command (see EclPC). }
procedure ClearPictureWindowCommand;
begin
  Inc(EclPC);
  ClearRect(PictureFrameLeft, PictureFrameTop, PictureFrameRight, PictureFrameBottom);
  GlyphRunInBox := 1;
end;
{ ovl03:2B33. ECL command 57 (dispatcher ovl03:2F2D, CurrentOpcode 39h): asks the player to choose a party
  member. The ECL text window (EclTextLeft to EclTextBottom) is cleared, the string operand 1 is copied
  into a local as the prompt, and SelectPartyMember runs with that prompt, mode 0 and SelectedCharacter as
  the var parameter that receives the chosen member. SelectPartyMember is the selection the learning notes
  call SelectPartyMember (res12, matched earlier); its own code is not traced here. Its Who is untyped
  in RES12.PAS, since PCharacter is not visible there (the caller passes the address of SelectedCharacter). }
procedure ChoosePartyMemberCommand;
var
  Prompt: string;
begin
  DecodeOperands(1);
  ClearRect(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom);
  Prompt := EclStrings[1];
  SelectPartyMember(Prompt, 0, SelectedCharacter);
end;
{ ovl03:2B7E. ECL command 54 (dispatcher ovl03:2F2D, CurrentOpcode 36h): adds a computer-run member. Operand
  1 is the kind AddMonsterToParty adds (it rolls the character and calls AddPartyMember, which makes it the
  SelectedCharacter). Operand 2 halved, with the high bit ComputerRun set, is its B84 byte: the low
  seven bits are its morale and the high bit marks it as run by the computer (TCharacter.B84). Its Side is
  1 for OtherSideKind and 0 otherwise. The character is then redrawn (RecalcCombatValues and DrawPartyRoster).
  QUIRK ovl03:2B7E: four bytes of the frame nothing uses. }
procedure AddComputerMemberCommand;
var
  Unused: LongInt;              { QUIRK ovl03:2B7E: four bytes of the frame nothing uses }
  Kind: Byte;
  Morale: Byte;
begin
  DecodeOperands(2);
  Kind := OperandValue(1);
  AddMonsterToParty(Kind);
  Morale := OperandValue(2);
  Morale := Morale shr 1;
  Morale := Morale or ComputerRun;
  SelectedCharacter^.B84 := Morale;
  if Kind <> OtherSideKind then
    SelectedCharacter^.Side := 0
  else
    SelectedCharacter^.Side := 1;
  RecalcCombatValues(SelectedCharacter);
  DrawPartyRoster(SelectedCharacter);
end;
{ ovl03:2C03. ECL command 59 (dispatcher ovl03:2F2D, CurrentOpcode 3Bh): looks for the value of operand 1
  among the memorized spells of the first party member (PartyListHead, TCharacter.Spells). The bytes from Spells[1]
  up are compared with the value one by one, up to slot SpellScanLast + 1 (82). Operand 2 receives the slot found,
  or NoSpellSlot when none in those bytes has it; operand 3 receives Count, the members walked (1 for a party
  with a member, 0 for an empty one). Purpose unknown: what the script does with the two results.
  QUIRK ovl03:2C03: the walk stops after the first member, because the search sets Found both when it finds
  the value and when it runs out of slots. QUIRK ovl03:2C03: Found is tested before the routine sets it, so
  the search runs only when that stack byte is zero. QUIRK ovl03:2C03: the two target addresses are kept as
  bytes (the high byte of each operand address is lost). QUIRK ovl03:2C03: the scan runs past the 21 entries
  of Spells, through the record bytes after them. }
procedure FindMemorizedSpellCommand;
var
  Value: Byte;                  { operand 1: the value searched for }
  I: Byte;                      { the slot searched, from 1 }
  Count: Byte;                  { the members walked }
  Member: PCharacter;           { the party member being searched }
  Found: Boolean;               { QUIRK ovl03:2C03: read before it is set }
  SlotAddr: Byte;               { operand 2: script address of I (its high byte is lost, QUIRK ovl03:2C03) }
  CountAddr: Byte;              { operand 3: script address of Count (QUIRK ovl03:2C03) }
begin
  DecodeOperands(3);
  Value := OperandValue(1);
  SlotAddr := MakeWord(OperandLow[2], OperandHigh[2]);
  CountAddr := MakeWord(OperandLow[3], OperandHigh[3]);
  I := 1;
  Count := 0;
  Member := PCharacter(PartyListHead);
  while (Member <> nil) and (not Found) do
  begin
    repeat
      if Member^.Spells[I] = Value then
        Found := True
      else if I <= SpellScanLast then
        Inc(I)
      else
      begin
        I := NoSpellSlot;
        Found := True;
      end;
    until Found;
    Member := Member^.Next;
    Inc(Count);
  end;
  WriteVmWord(SlotAddr, I);
  WriteVmWord(CountAddr, Count);
end;
{ ovl03:2CCF. ECL command 45 (dispatcher ovl03:2F2D, CurrentOpcode 2Dh): runs the engine action that the
  word of its operand picks (the two bytes of the operand, not its value). The word less CodeBias is
  tested against the Action codes in turn; any other word does nothing. The actions:
  - ActionRedrawArea: PartyCellEventByte takes the event byte of the party's cell (EventByteAt). When AreaRedrawArmed is set
    (ECL commands 33 and 55 set it, 32 clears it) and one of CloseUpShown, Sprite3DLoaded, SpecialViewGate,
    PartyMovedByScript or HeadBodyWritten is
    set, the area view is drawn again (ShowAreaView), DrawLocationLine runs and those five flags are cleared.
  - ActionDuelWithCopy and ActionDuelNoCopy: SetupDuel starts a duel with or without the copy.
  - ActionSound: PlaySound of SoundStep when ScriptSoundCode is 8, of SoundFireball when ScriptSoundCode is 10.
  - ActionStepParty: StepPartyForward moves the party one cell.
  - ActionWallProbe: when AreaViewKind is 1, PartyCellWallId takes the wall id of the party's cell (WallIdAt). }
procedure EngineActionCommand;
var
  Code: Word;                   { the operand's word }
  Action: Word;                 { Code less CodeBias: the action tested }
begin
  DecodeOperands(1);
  Code := MakeWord(OperandLow[1], OperandHigh[1]);
  Action := Code - CodeBias;
  case Action of
    ActionRedrawArea:
      begin
        PartyCellEventByte := EventByteAt(PartyMapColumn, PartyMapRow);
        if (AreaRedrawArmed <> 0) and ((CloseUpShown <> 0) or (Sprite3DLoaded <> 0) or (SpecialViewGate <> 0) or
          (PartyMovedByScript <> 0) or (HeadBodyWritten <> 0)) then
        begin
          ShowAreaView;
          DrawLocationLine;
          HeadBodyWritten := 0;
          SpecialViewGate := 0;
          PartyMovedByScript := 0;
          CloseUpShown := 0;
          Sprite3DLoaded := 0;
        end;
      end;
    ActionDuelWithCopy: SetupDuel(DuelWithCopy);
    ActionDuelNoCopy: SetupDuel(DuelNoCopy);
    ActionSound:
      case ScriptSoundCode of
        8: PlaySound(SoundStep);
        10: PlaySound(SoundFireball);
      end;
    ActionStepParty: StepPartyForward;
    ActionWallProbe:
      if AreaViewKind = 1 then
        PartyCellWallId := WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
  end;
end;
{ ovl03:2DD3. Runs the camp (MakeCamp, OVL15) between two script entries: the script machine runs the
  third entry address, EclPreCampEntry, before the camp (through ovl03:3171, not decompiled yet). When the camp
  leaves EndCamp set, the area view is redrawn (RedrawView) and the fourth entry address, EclCampInterruptedEntry, runs.
  Callers: ECL command 56 with operand 9 (ovl03:2E10) and RunWilderness (ovl03:33E7, the E key of the wilderness
  loop). Then the area view is drawn again
  (ShowAreaView) and HeapErrorStop, the gate of the heap error retry, is cleared. }
procedure RunCamp;
var
  EndCamp: Byte;                { the camp sets it when it is closed }
  Unused: Byte;                 { QUIRK ovl03:2DD3: a byte of the frame nothing uses }
begin
  EndCamp := 0;
  RunScriptFrom(EclPreCampEntry);
  MakeCamp(EndCamp);
  if EndCamp <> 0 then
  begin
    RedrawView;
    RunScriptFrom(EclCampInterruptedEntry);
  end;
  ShowAreaView;
  HeapErrorStop := False;
end;
{ ovl03:2E10. ECL command 56 (dispatcher ovl03:2F2D, CurrentOpcode 38h, cmp al,38h at ovl03:3135): shows
  the screen that operand 1 picks. 0 runs RunCharacterMenu (not traced yet) and redraws the view (RedrawView);
  ScreenEnding shows the ending narrative (ShowEndingNarrative, OVL18); ScreenCamp runs the camp (RunCamp),
  keeps the script counter EclPC across it, and then EndCommand (ovl03:0001) runs. A pending selection
  (ReselectCharacterPending, set by ECL command 10) first selects the character at ReselectCharacter, as EndCommand does. }
procedure ShowSpecialScreenCommand;
var
  Choice: Byte;                 { the screen the operand picks }
  SavedCounter: Word;           { EclPC, saved around RunCamp }
  Unused: Byte;                 { QUIRK ovl03:2E10: a byte of the frame nothing uses }
begin
  if ReselectCharacterPending <> 0 then
  begin
    SelectedCharacter := ReselectCharacter;
    ReselectCharacterPending := 0;
  end;
  DecodeOperands(1);
  Choice := OperandValue(1);
  case Choice of
    0:
      begin
        RunCharacterMenu;
        RedrawView;
      end;
    ScreenEnding: ShowEndingNarrative;
    ScreenCamp:
      begin
        SavedCounter := EclPC;
        RunCamp;
        EclPC := SavedCounter;
        EndCommand;
      end;
  end;
end;
{ ovl03:2E7D. ECL command 60 (dispatcher ovl03:2F2D, CurrentOpcode 3Ch): draws one line of glyphs at the text
  cursor. Operand 1 is the script address of a run of words: each word's low byte plus 1 is the glyph drawn
  (DrawGlyph, one copy, colour GlyphRunColor) at GlyphCol and GlyphRow, and the cursor moves right after each
  glyph. The run ends at the first word whose low byte is 0 or $FF. When GlyphRunInBox is set (ECL command 61) and the
  cursor is below CloseUpLastRow, the cursor first goes to GlyphRunCol, GlyphRunRow and PictureFrameDirty is set.
  GlyphRunPending
  is set, and the cursor goes down one row at the end. Purpose unknown: what the script writes this way. }
procedure DrawGlyphRunCommand;
var
  Start: Word;                  { operand 1: the script address of the run }
  Address: Word;                { the word read: Start plus Index }
  Index: Byte;                  { the glyphs drawn so far }
  Value: Byte;                  { the glyph of the word read: its low byte plus 1 }
  Done: Boolean;                { set when the run ends }
  Unused: Byte;                 { QUIRK ovl03:2E7D: a byte of the frame nothing uses }
begin
  FillChar(PictureShownFlags, 2, 0);
  CloseUpShown := 0;
  DecodeOperands(1);
  Start := MakeWord(OperandLow[1], OperandHigh[1]);
  Index := 0;
  Done := False;
  if (GlyphRunInBox <> 0) and (GlyphRow > CloseUpLastRow) then
  begin
    GlyphRow := GlyphRunRow;
    GlyphCol := GlyphRunCol;
    PictureFrameDirty := 1;
  end;
  GlyphRunPending := 1;
  repeat
    Address := Start + Index;
    Value := ReadVmWord(Address) + 1;
    if Value > 1 then
    begin
      DrawGlyph(GlyphCol, GlyphRow, GlyphRunColor, 1, Value, 0);
      Inc(GlyphCol);
      Inc(Index);
    end
    else
      Done := True;
  until Done;
  Inc(GlyphRow);
end;
{ ovl03:2F2D. The ECL command dispatcher (called by ovl03:3171 for each command the script runs): it runs
  the handler of CurrentOpcode, one case arm per opcode. Each handler decodes its own operands and moves
  EclPC past the command. An opcode without an arm (31, and 62 and above) does nothing. }
procedure DispatchCommand;
begin
  case CurrentOpcode of
    0: EndCommand;
    1: GotoCommand;
    2: GosubCommand;
    3: CompareCommand;
    OpAdd, OpSub, OpDiv, OpMul: ArithmeticCommand;
    8: RandomCommand;
    9: StoreCommand;
    10: SelectCharacterCommand;
    11: AddEncounterGroupCommand;
    12: ShowEncounterCommand;
    13: ApproachEncounterCommand;
    14: ShowCloseUpCommand;
    15: ReadNumberCommand;
    16: ReadStringCommand;
    17, 18: ShowTextCommand;
    19: ReturnCommand;
    20: CompareBothPairsCommand;
    21: ChooseFromListCommand;
    OpIfEqual, OpIfNotEqual, OpIfLess, OpIfGreater, OpIfLessOrEqual, OpIfGreaterOrEqual: RunIfCompared;
    28: ClearEncounterCommand;
    29: ComputePartyValueCommand;
    30: ScanPartyCommand;
    32: StartEclBlock;
    33, 55: LoadAreaGraphics;
    34: CheckPartyHasRangerCommand;
    35: RollSurpriseCommand;
    36: RunAreaEventCommand;
    OpChooseAddress, 38: SelectCaseCommand;
    39: AddLootCommand;
    40: LoseMoneyAndItemsCommand;
    41: EncounterActionCommand;
    42: CopyIndexedWordCommand;
    43: AskMenuCommand;
    44: ChooseAttitudeCommand;
    45: EngineActionCommand;
    46: DamagePartyCommand;
    OpAnd, OpOr: BitwiseCommand;
    49: RedrawAreaViewCommand;
    50: ComparePartyItemCommand;
    51: NewLineCommand;
    52: PassTimeCommand;
    53: StoreIndexedWordCommand;
    54: AddComputerMemberCommand;
    56: ShowSpecialScreenCommand;
    57: ChoosePartyMemberCommand;
    58: PauseCommand;
    59: FindMemorizedSpellCommand;
    60: DrawGlyphRunCommand;
    61: ClearPictureWindowCommand;
  end;
end;
{ ovl03:3171. Runs the ECL script from the script address Address (an entry point: EclPreCampEntry for the camp,
  RunCamp ovl03:2DD3, or one InitScript sets). EclPC takes Address. While the run is not over (ScriptRunEnded clear:
  EndCommand and StartEclBlock set it) and the party is not destroyed (PartyDestroyed clear), the opcode of
  the current command goes to PreviousOpcode, the opcode at EclPC is read into CurrentOpcode and DispatchCommand runs
  it. Both flags are cleared on the way out. }
procedure RunScriptFrom(Address: Word);
begin
  EclPC := Address;
  ScriptRunEnded := 0;
  while (ScriptRunEnded = 0) and (PartyDestroyed = 0) do
  begin
    PreviousOpcode := CurrentOpcode;
    CurrentOpcode := EclCode^[EclPC];
    DispatchCommand;
  end;
  ScriptRunEnded := 0;
end;
{ ovl03:31B4. One step of the area (the party has moved, or the script asked for the area to be drawn again):
  the event byte of the party's cell goes to PartyCellEventByte (EventByteAt), word VarMapEdgeHit of GameVars2 is cleared, and
  the view kind AreaViewKind is set to 1 (the 3D wall view) with its old value kept in PreviousAreaViewKind. The script entry
  EclInitialEntry runs. When VarForceWallView is clear, AreaViewKind takes 2, 3 or 4 from WallViewMode (the map window
  pages; page 3 also animates the area doors, AnimateAreaDoors ovl18:06B3). The picture window is cleared
  when the old kind was a map page, and the area is drawn (ShowAreaView). Then the script entries EclStepEntry and
  EclSearchEntry run, and the step repeats while a script block was started (ScriptBlockStarted, StartEclBlock).
  SelectedCharacter
  is saved and restored around the entries. Called from the area loop RunWilderness (ovl03:32F8). Purpose unknown
  in parts: what the entries and word VarMapEdgeHit do. }
procedure RunAreaStep;
var
  Saved: PCharacter;            { SelectedCharacter, restored after the second entry }
begin
  repeat
    PartyCellEventByte := EventByteAt(PartyMapColumn, PartyMapRow);
    GameVars2^[VarMapEdgeHit] := 0;
    Saved := SelectedCharacter;
    PreviousAreaViewKind := AreaViewKind;
    AreaViewKind := 1;
    RunScriptFrom(EclInitialEntry);
    ViewMode := ViewModeWall;
    if GameVars^[VarForceWallView] = 0 then
      case WallViewMode of
        WallModeMapPage2:
          begin
            AreaViewKind := 2;
            ViewMode := ViewModeMap;
          end;
        WallModeMapPage3:
          begin
            AreaViewKind := 3;
            ViewMode := ViewModeMap;
            if (GameVars^[VarAreaDoors] = AreaDoorsOpen) and (GameVars^[VarRiverGate] = 0) then
              AnimateAreaDoors(1);
          end;
        WallModeMapPage4:
          begin
            AreaViewKind := 4;
            ViewMode := ViewModeMap;
          end;
      end;
    if (PreviousAreaViewKind > 1) and (AreaViewKind = 1) then
      DrawWindow(3, 3, $D, $D, 0, $A, '');
    if ((((PreviousAreaViewKind > 1) or (AreaViewKind = 1)) and (AreaRedrawArmed <> 0)) or ((PreviousAreaViewKind = 1)
      and (AreaViewKind = 1))) then
      ShowAreaView;
    ScriptBlockStarted := 0;
    RunScriptFrom(EclStepEntry);
    if ScriptBlockStarted = 0 then
    begin
      RunScriptFrom(EclSearchEntry);
      SelectedCharacter := Saved;
      DrawPartyRoster(SelectedCharacter);
    end;
  until ScriptBlockStarted = 0;
end;
{ ovl03:32F8. The wilderness loop, entry 1 of this overlay: the main program calls it after the
  character menu and quits when it returns. It clears the area flags, takes WallViewMode from
  VarSavedWallView, and sets the view mode ViewMode to ViewModeMap for map pages 2 to 4 when
  VarForceWallView is clear, else ViewModeWall. Unless SkipAreaScriptLoad is set it loads the area script
  (LoadEcl) and always resets the script machine (InitScript) and runs entry EclInitialEntry. A view mode
  other than the map page redraws once (RedrawView, while AreaStepRedrawOnce is still 1) and draws the area
  (ShowAreaView). Then it loops on HandleWildernessKeys. While word VarTravelMode of GameVars2 is above 1
  or the key is KeyCamp, and the party is not destroyed: KeyCamp makes camp (RunCamp); any other such
  key saves the low bit of that word in SavedSearchMode, forces the word to 1, draws the area, runs entry
  EclSearchEntry and a step (RunAreaStep) if a script block started (ScriptBlockStarted), then restores the bit. Otherwise
  entry EclStepEntry runs, and a started block steps the area; if none started and the party lives, the
  wilderness menu (DoWildernessMenu) runs and SoundStep plays when the party's cell changed. A destroyed
  party clears PartyDestroyed and leaves the loop. The map entries ovl03:3379 and ovl03:34AB are
  bytes of this routine (a call operand and a cmp), not routines. }
procedure RunWilderness;
var
  Key: Char;                    { the key HandleWildernessKeys returned }
  Unused: Byte;                 { QUIRK ovl03:32F8: a byte of the frame nothing uses }
begin
  Command55Ran := 0;
  Command33Ran := 0;
  ReselectCharacterPending := 0;
  AreaRedrawArmed := 0;
  AreaStepRedrawOnce := 1;
  ViewMode := ViewModeWall;
  ScriptBlockStarted := 0;
  WallViewMode := GameVars^[VarSavedWallView];
  case WallViewMode of
    WallModeMapPage2, WallModeMapPage3, WallModeMapPage4:
      if GameVars^[VarForceWallView] = 0 then
        ViewMode := ViewModeMap;
  end;
  if SkipAreaScriptLoad = 0 then
    LoadEcl(WallViewMode);
  InitScript;
  RunScriptFrom(EclInitialEntry);
  if ViewMode <> ViewModeMap then
  begin
    if AreaStepRedrawOnce = 1 then
    begin
      RedrawView;
      AreaStepRedrawOnce := 0;
    end;
    ShowAreaView;
  end;
  GameVars^[VarSavedWallView] := WallViewMode;
  repeat
    Key := HandleWildernessKeys;
    ReselectCharacter := SelectedCharacter;
    GameVars^[VarSavedWallView] := WallViewMode;
    while ((GameVars2^[VarTravelMode] > 1) or (UpCase(Key) = KeyCamp)) and (PartyDestroyed = 0) do
    begin
      if UpCase(Key) = KeyCamp then
        RunCamp
      else
      begin
        SavedSearchMode := GameVars2^[VarTravelMode] and 1;
        GameVars2^[VarTravelMode] := 1;
        ShowAreaView;
        RunScriptFrom(EclSearchEntry);
        if ScriptBlockStarted <> 0 then
          RunAreaStep;
        GameVars2^[VarTravelMode] := SavedSearchMode;
      end;
      if PartyDestroyed = 0 then
      begin
        Key := HandleWildernessKeys;
        ReselectCharacter := SelectedCharacter;
      end;
    end;
    if PartyDestroyed = 0 then
      RunScriptFrom(EclStepEntry);
    if ScriptBlockStarted <> 0 then
      RunAreaStep
    else if PartyDestroyed = 0 then
    begin
      GameVars^[VarSavedPartyColumn] := PartyMapColumn;
      GameVars^[VarSavedPartyRow] := PartyMapRow;
      DoWildernessMenu;
      ShowAreaView;
      { ShortInt <> Word: the right operand is evaluated first, the original's load order (ovl03:3497). }
      if (PartyMapColumn <> GameVars^[VarSavedPartyColumn]) or
         (PartyMapRow <> GameVars^[VarSavedPartyRow]) then
        PlaySound(SoundStep);
      CloseUpShown := 0;
      CloseUpHidden := 1;
      RunScriptFrom(EclSearchEntry);
      if ScriptBlockStarted <> 0 then
        RunAreaStep;
    end;
  until PartyDestroyed <> 0;
  PartyDestroyed := 0;
end;

{ ovl03:3508. The initialisation part is empty: push bp, mov bp, sp, pop bp, retf. }
begin
end.
