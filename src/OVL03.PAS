unit OVL03;
{ Encounter: the command loop of the ECL script interpreter (whitepaper 5.1). ovl03_fn_2F2D
  dispatches each command by its opcode (SkippedOpcode) to a handler in this unit; the handlers
  decode their operands through OVL07 and run them. The other routines are still stubs. }
{$A-,O+,F+,S-,R-,G-,I-}
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
procedure ComparePairsCommand;
procedure RunIfCompared;
procedure StartEclBlock;
procedure LoadAreaGraphics;
procedure BitwiseCommand;
procedure CopyIndexedWordCommand;
procedure StoreIndexedWordCommand;
procedure ChooseFromListCommand;
procedure AskMenuCommand;
procedure ClearEncounterCommand;
procedure ovl03_fn_12C6;
procedure ovl03_fn_1307;
procedure ovl03_fn_13D7;
procedure ovl03_fn_1435;
procedure ovl03_fn_1629;
procedure ovl03_fn_16C9;
procedure ovl03_fn_1758;
procedure ovl03_fn_179B;
procedure ovl03_fn_18F8;
procedure ovl03_fn_19B0;
procedure ovl03_fn_1B42;
procedure ovl03_fn_1C13;
procedure ovl03_fn_1DB1;
procedure ovl03_fn_1EF8;
procedure ovl03_fn_238D;
procedure ovl03_fn_25CB;
procedure ovl03_fn_266A;
procedure ovl03_fn_271F;
procedure ovl03_fn_2775;
procedure ovl03_fn_2AA2;
procedure ovl03_fn_2AC1;
procedure ovl03_fn_2AEB;
procedure ovl03_fn_2B14;
procedure ovl03_fn_2B33;
procedure ovl03_fn_2B7E;
procedure ovl03_fn_2C03;
procedure ovl03_fn_2CCF;
procedure ovl03_fn_2D39;
procedure ovl03_fn_2DBA;
procedure ovl03_fn_2DCB;
procedure ovl03_fn_2DD3;
procedure ovl03_fn_2E10;
procedure ovl03_fn_2E7D;
procedure ovl03_fn_2F2D;
procedure ovl03_fn_3171;
procedure ovl03_fn_31B4;
procedure ovl03_e1;
procedure ovl03_fn_3379;
procedure ovl03_fn_34AB;
implementation
uses OVL17, OVL25, OVL26, OVL28, OVL29, OVL32, RES06;

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
  { The bit of ECL command 10's operand that removes the member from the party, and the mask of
    the party position (ovl03:02E0). }
  RemoveMemberBit = $80;
  PositionMask = $7F;
  { The two words of ds49D6 that ECL command 12 (ovl03:03B4) works with: the largest distance the
    script allows for the encounter picture, and the steps the party sees ahead (OpenStepsAhead,
    ovl07:0482, which also stores them there). }
  VarEncounterLimit = 704;
  VarStepsAhead = 705;
  { ECL command 11 (ovl03:0450) adds no encounter member once its count of members reaches this. }
  MaxEncounterMembers = 63;
  { The icon slot ds6F83 starts at: InitScript (ovl07:01F0) and ECL command 28 (ovl03:125D) set it. }
  FirstEncounterIcon = 8;
  { The word of ds49D6 that ECL command 14 (ovl03:0856) reads: NoHeadBank when the close-up is the PIC
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
  { The colours of the ECL menus (ovl03:0F08, ovl03:10D1): the title of AskMenu and the heading of a
    list, the words of AskMenu and the lines of a list, the hotkeys and the highlight. }
  MenuTitleColor = 13;
  MenuTextColor = 10;
  MenuHotColor = 15;
  { The prompt line is text row $18; the menu command at ovl03:10D1 clears it, columns 0 to $27. }
  PromptRow = $18;
  PromptLeftCol = 0;
  PromptLastCol = $27;
  { ECL command 17: the text goes on after the text already in the window; command 18 clears it first. }
  OpContinueText = $11;
var
  { ds84C8 (POOLVARS) under the type ShowEncounterPicture takes: TPictureShown is declared in OVL07,
    and Turbo Pascal accepts a var argument only of the identical type. }
  PictureShown: TPictureShown absolute ds84C8;

{ ovl03:0001. The ECL command 0, the only command that takes no operands (the dispatcher at
  ovl03:2F2D calls it for SkippedOpcode 0). It clears the text windows when ds84E2 is set (the
  second one only when the game variable VarForceWallView is set, since the code reads that same
  word), selects the character at ds4436 when ds4430 is set, clears the two-byte scratch ds84C8,
  moves EclPC past the command, empties the return stack of ScriptGosub, and puts the text
  cursor at column 1, row 17 (GlyphCol, GlyphRow). }
procedure EndCommand;
begin
  if ds84E2 <> 0 then
  begin
    DrawWindow(1, 1, $F, $F, 0, $F, '');
    if GameVars^[VarForceWallView] <> 0 then
      DrawWindow(3, 3, $D, $D, 0, $F, '');
  end;
  if ds4430 <> 0 then
  begin
    SelectedCharacter := ds4436;
    ds4430 := 0;
  end;
  FillChar(ds84C8, 2, 0);
  ds84E0 := 0;
  ds84E2 := 0;
  ds442E := 1;
  Inc(EclPC);
  while ReturnStack <> nil do
  begin
    ReturnPrev := ReturnStack^.Next;
    FreeMem(ReturnStack, 6);
    ReturnStack := ReturnPrev;
  end;
  GlyphRow := $11;
  GlyphCol := 1;
  ds84DE := 0;
end;
{ ovl03:00F4. ECL command 1 (dispatcher ovl03:2F2D, SkippedOpcode 1): an unconditional jump. Its
  one operand is a script address, and EclPC moves to it (the same jump ScriptGosub makes after
  it pushes the return address). }
procedure GotoCommand;
begin
  DecodeOperands(1);
  EclPC := MakeWord(OperandLow[1], OperandHigh[1]);
end;
{ ovl03:0111. ECL command 2 (dispatcher ovl03:2F2D, SkippedOpcode 2): a subroutine call. Its one
  operand is the script address of the subroutine; ScriptGosub pushes the return address and
  jumps there. }
procedure GosubCommand;
begin
  DecodeOperands(1);
  ScriptGosub(1);
end;
{ ovl03:0126. ECL command 3 (dispatcher ovl03:2F2D, SkippedOpcode 3): compares its two operands
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
{ ovl03:01A3. ECL commands 4 to 7 (dispatcher ovl03:2F2D, SkippedOpcode OpAdd, OpSub, OpDiv or
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
  case SkippedOpcode of
    OpAdd: Answer := Values[1] + Values[2];
    OpSub: Answer := Values[2] - Values[1];
    OpDiv: Answer := Values[1] div Values[2];
    OpMul: Answer := Values[1] * Values[2];
  end;
  WriteVmWord(Target, Answer);
end;
{ ovl03:0234. ECL command 8 (dispatcher ovl03:2F2D, SkippedOpcode 8): stores a random number. The
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
{ ovl03:0292. ECL command 9 (dispatcher ovl03:2F2D, SkippedOpcode 9): stores its first operand at
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
{ ovl03:02E0. ECL command 10 (dispatcher ovl03:2F2D, SkippedOpcode 10): selects the party member at
  the 0-based position its operand names as SelectedCharacter. The walk starts at ds5D96, the head
  of the party list (Next at +$104), and stops at the position or at the end of the list; a
  position past the end selects nothing. It sets ds4430 first, so the next EndCommand (ovl03:0001)
  selects ds4436 again. When the operand's bit 7 is set and the script has just cleared the
  character's name and status (ds84D2 and ds84D3, set by SetCharacterVar), the selected member
  leaves the party (ovl16_e2, as ovl15:18E5 does) and is redrawn (res12_fn_0767), and ds4430 is
  cleared when that member is ds4436. }
procedure SelectCharacterCommand;
var
  Member: PCharacter;
  Unused: Byte;                 { QUIRK ovl03:02E0: a byte of the frame nothing uses }
  Position: Byte;
  I: Byte;
  RemoveFlag: Byte;
begin
  ds4430 := 1;
  DecodeOperands(1);
  I := 0;
  Position := OperandValue(1);
  Member := PCharacter(ds5D96);
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
  if (RemoveFlag <> 0) and (ds84D2 <> 0) and (ds84D3 <> 0) then
  begin
    if ds4436 = SelectedCharacter then
      ds4430 := 0;
    ovl16_e2(False, True);
    res12_fn_0767(SelectedCharacter);
    ds84D2 := 0;
    ds84D3 := 0;
  end;
end;
{ ovl03:03B4. ECL command 12 (dispatcher ovl03:2F2D, SkippedOpcode 12): shows an encounter picture
  at the distance the party can see ahead. Operand 1 is the sprite bank (EncounterSpriteBank) and
  operand 3 the picture bank (EncounterPicBank), both passed to ShowEncounterPicture; operand 2 is
  the largest distance the script allows, kept in word 704 of ds49D6. The distance is the steps
  ahead (OpenStepsAhead, which also stores them in word 705), cut down to that limit. The two shown
  flags are PictureShown (ds84C8). }
procedure ShowEncounterCommand;
var
  Unused: Word;                 { QUIRK ovl03:03B4: two bytes of the frame nothing uses }
begin
  DecodeOperands(3);
  EncounterSpriteBank := OperandValue(1);
  ds49D6^[VarEncounterLimit] := OperandValue(2);
  EncounterPicBank := OperandValue(3);
  ds49D6^[VarStepsAhead] := OpenStepsAhead(PartyMapColumn, PartyMapRow, PartyFacing);
  if ds49D6^[VarEncounterLimit] < ds49D6^[VarStepsAhead] then
    ds49D6^[VarStepsAhead] := ds49D6^[VarEncounterLimit];
  ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank, Byte(ds49D6^[VarStepsAhead]), PictureShown);
end;
{ ovl03:0450. ECL command 11 (dispatcher ovl03:2F2D, SkippedOpcode 11): adds a group of encounter
  members to the party list ds5D96 (icons from 8 up, so not the party's own members). Operand 1 is
  the kind LoadCharacter loads (ovl17_e6, the save and load unit), operand 2 the number of members
  (at least 1), operand 3 the block of the combat picture 'CPIC' loaded into the icon slot ds6F83.
  The loaded character goes to the tail of the list first, then Count - 1 copies of it, each with
  its own copies of the item and affect lists (the copies are prepended, so the lists come out in
  reverse order). Every member gets CombatIcon := ds6F83, and the slot goes up by one afterwards.
  Nothing is added once EncounterMemberCount reaches MaxEncounterMembers. SelectedCharacter is saved
  and restored, and ds84E7 is set. }
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
  Last := PCharacter(ds5D96);
  PictureSetName := 'CPIC';
  LoadPictureSlot(PictureSetName, PictureBlock, ds6F83);
  while Last^.Next <> nil do
    Last := Last^.Next;
  Last^.Next := Who;
  Last := Last^.Next;
  Last^.CombatIcon := ds6F83;
  Last^.Next := nil;
  Inc(EncounterMemberCount);
  Inc(I);
  while (I <= Count) and (EncounterMemberCount < MaxEncounterMembers) do
  begin
    New(NewMember);
    Last^.Next := NewMember;
    Last := Last^.Next;
    Last^ := Template;
    Last^.CombatIcon := ds6F83;
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
  Inc(ds6F83);
  ds84E7 := 1;
  SelectedCharacter := Saved;
end;
{ ovl03:0817. ECL command 13 (dispatcher ovl03:2F2D, SkippedOpcode 13): brings the encounter picture
  one step nearer. While the steps the party sees ahead (VarStepsAhead, word 705 of ds49D6) are not
  used up, it takes one off and shows the picture again at the new distance (ShowEncounterPicture).
  It has no operands and always moves EclPC past the command. }
procedure ApproachEncounterCommand;
begin
  if ds49D6^[VarStepsAhead] > 0 then
  begin
    Dec(ds49D6^[VarStepsAhead]);
    ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank, Byte(ds49D6^[VarStepsAhead]), PictureShown);
  end;
  Inc(EclPC);
end;
{ ovl03:0856. ECL command 14 (dispatcher ovl03:2F2D, SkippedOpcode 14): shows the close-up picture of
  the encounter, or hides it. Operand 1 is the picture bank PicBank. When PicBank is HideCloseUp, the
  close-up goes: when ds49F9 is above 1 or AreaViewKind is 1 and a close-up or the 3D sprite is up
  (ds84E0 or ds84E3), the area view is drawn again (ShowAreaView), those flags are cleared and ds84E1
  is set; both PictureShown flags are cleared. Otherwise the picture window (3, 3 to 13, 13) is
  cleared first unless VarForceWallView is set, and the close-up is drawn as ShowEncounterPicture
  draws it: the PIC picture PicBank when word VarCloseUpHead of ds49D6 is NoHeadBank, else the HEAD
  and BODY pictures (ShowHeadBody). Purpose of ds49F9 unknown: the loader sets it to 1 (ovl11:03EB). }
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
    ds84E0 := 1;
    if ds49D6^[VarCloseUpHead] = NoHeadBank then
    begin
      LoadSpriteList('PIC', PicBank, 0, @PictureAnimation);
      DrawSprite(3, 3, 1, PictureAnimation.Frames[1].Sprite);
    end
    else
      ShowHeadBody(ds49D6^[VarCloseUpHead], PicBank);
  end
  else
  begin
    if ((ds49F9 > 1) or (AreaViewKind = 1)) and ((ds84E0 <> 0) or (ds84E3 <> 0)) then
    begin
      ShowAreaView;
      ds84E0 := 0;
      ds84E3 := 0;
      ds84E1 := 1;
    end;
    PictureShown[0] := 0;
    PictureShown[1] := 0;
  end;
end;
{ ovl03:0951. ECL command 15 (dispatcher ovl03:2F2D, SkippedOpcode 15): asks the player for a number
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
{ ovl03:0994. ECL command 16 (dispatcher ovl03:2F2D, SkippedOpcode 16): asks the player for a line of
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
{ ovl03:0A09. ECL commands 17 and 18 (dispatcher ovl03:2F2D, SkippedOpcode $11 or $12): show the text
  of operand 1 in the ECL text window (EclTextLeft to EclTextRight, EclTextTop to EclTextBottom) with
  ShowPagedText. A number operand is turned into its text by res12_fn_1073 and stored in EclStrings[1];
  a string operand is already there (DecodeOperands). Command 17 (OpContinueText) leaves the window and
  the cursor as they are; command 18 clears the window and puts the cursor at its top left corner first.
  ds84E4 is cleared, and ds4A00 is set while the text is shown: DrawTextRun then waits after each
  glyph. }
procedure ShowTextCommand;
begin
  DecodeOperands(1);
  ds84E4 := 0;
  ds4A00 := 1;
  if OperandType[1] < FirstStringOperandType then
    EclStrings[1] := res12_fn_1073(OperandValue(1));
  if SkippedOpcode = OpContinueText then
    ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 0, EclStrings[1])
  else
  begin
    GlyphRow := EclTextTop;
    GlyphCol := EclTextLeft;
    ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1, EclStrings[1]);
  end;
  ds4A00 := 0;
end;
{ ovl03:0A9F. ECL command 19 (dispatcher ovl03:2F2D, SkippedOpcode $13): returns from a subroutine
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
{ ovl03:0AED. ECL command 20 (dispatcher ovl03:2F2D, SkippedOpcode $14): compares two pairs of word
  operands. The six CompareFlags are cleared, the four operands are read as words (OperandValue),
  and operand 1 is compared with operand 2 and operand 3 with operand 4. When both pairs are equal
  CompareFlags[0] (=) is set, else CompareFlags[1] (<>). The conditional commands 22 to 27 (the
  handler at ovl03:0B52) test these flags. Purpose unknown: what the script compares this way (the
  pairs are not yet traced to game variables). }
procedure ComparePairsCommand;
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
{ ovl03:0B52. ECL commands 22 to 27 (dispatcher ovl03:2F2D, SkippedOpcode OpIfEqual to
  OpIfGreaterOrEqual): a conditional. EclPC moves past the opcode, then the next command runs only
  when its comparison flag in CompareFlags is set (=, <>, <, >, <=, >= in that order, set by
  CompareCommand, ComparePairsCommand and the comparison routines of OVL07). When the flag is clear,
  SkipCommand steps over the next command. Any other opcode only moves EclPC. }
procedure RunIfCompared;
begin
  Inc(EclPC);
  case SkippedOpcode of
    OpIfEqual: if CompareFlags[0] = 0 then SkipCommand;
    OpIfNotEqual: if CompareFlags[1] = 0 then SkipCommand;
    OpIfLess: if CompareFlags[2] = 0 then SkipCommand;
    OpIfGreater: if CompareFlags[3] = 0 then SkipCommand;
    OpIfLessOrEqual: if CompareFlags[4] = 0 then SkipCommand;
    OpIfGreaterOrEqual: if CompareFlags[5] = 0 then SkipCommand;
  end;
end;
{ ovl03:0BD1. ECL command 32 (dispatcher ovl03:2F2D, SkippedOpcode $20): starts ECL block Block of the
  area's script file. The operand is the block number: the WallViewMode of the area is saved in
  VarSavedWallView, then WallViewMode takes the block number. The file is GameDir + 'ECL' + the
  TileSet number + '.dax' (its path goes to ovl17_e11 first), LoadEcl loads the block and InitScript
  resets the script machine. ds442E and ds442F are set to 1 and ds4431 is cleared. }
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
  ovl17_e11(GameDir + 'ECL' + TileSetText + '.dax');
  LoadEcl(Block);
  InitScript;
  ds442E := 1;
  ds442F := 1;
  ds4431 := 0;
end;
{ ovl03:0C74. ECL commands 33 and 55 (dispatcher ovl03:2F2D, SkippedOpcode $21 or $37): load the
  graphics of the area for the three operands, the block numbers Blocks, where $FF means none.
  Command 33 loads the 3D map Blocks[1] (Load3DMap, VarGeoBlock keeps its number) when
  VarForceWallView is set, and the 'BACPAC' picture set (Load24x24Set) when Blocks[3] is given and
  VarForceWallView is clear. Command 55 loads the wall sets: slot 1 gets wall set 0 when Blocks[1] is
  $7F; when words 231 and 232 of GameVars are both set, slots 1 and 3 get Blocks[1] and Blocks[3],
  else each slot I gets Blocks[I] or, for $FF, the two words of ds6AAEWords[I] become $FFFF. The
  label ovl03:0D7B is the slot loop of this routine. ds4431 is set first. When ds4432, ds4433 and
  ds4434 are all set, res12_fn_27D9 runs, the selected character is redrawn (res12_fn_0767) and
  ds4432 is cleared. Words 231 and 232 of GameVars and word 713 of ds49D6 are not named yet. }
procedure LoadAreaGraphics;
var
  Blocks: array[1..3] of Byte;
  I: Byte;
begin
  DecodeOperands(3);
  ds4431 := 1;
  for I := 1 to 3 do
    Blocks[I] := OperandValue(I);
  if SkippedOpcode = $21 then
  begin
    ds4434 := 1;
    if (Blocks[1] <> $FF) and (Blocks[1] <> $7F) and (GameVars^[VarForceWallView] <> 0) then
    begin
      GameVars^[VarGeoBlock] := Blocks[1];
      Load3DMap(Blocks[1]);
      ds49D6^[713] := 0;
    end;
    if (Blocks[3] <> $FF) and (GameVars^[VarForceWallView] = 0) then
      Load24x24Set('BACPAC', 0, 40);
  end
  else
  begin
    ds4433 := 1;
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
          ds6AAEWords[I].A := $FFFF;
          ds6AAEWords[I].B := $FFFF;
        end;
  end;
  if (ds4432 <> 0) and (ds4433 <> 0) and (ds4434 <> 0) then
  begin
    res12_fn_27D9;
    res12_fn_0767(SelectedCharacter);
    ds4432 := 0;
  end;
end;
{ ovl03:0DEF. ECL commands 47 and 48 (dispatcher ovl03:2F2D, SkippedOpcode OpAnd or OpOr): the
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
  if SkippedOpcode = OpAnd then
    Combined := First and Second
  else
    Combined := First or Second;
  CompareWords(0, Combined);
  WriteVmWord(Target, Combined);
end;
{ ovl03:0E5E. ECL command 42 (dispatcher ovl03:2F2D, SkippedOpcode $2A): copies a word out of a table.
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
{ ovl03:0EBC. ECL command 53 (dispatcher ovl03:2F2D, SkippedOpcode $35): stores operand 1 as a word
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
{ ovl03:0F08. ECL command 21 (dispatcher ovl03:2F2D, SkippedOpcode $15): a list menu. Operand 1 is
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
  ds84E4 := 0;
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
{ ovl03:10D1. ECL command 43 (dispatcher ovl03:2F2D, SkippedOpcode $2B): asks the player a menu. Operand
  1 is the address that receives the answer, operand 2 the number of options Count; the options are the
  string operands EclStrings[1..Count], decoded again after Dec(EclPC) as in ChooseFromListCommand. They
  become one text, each option after a '~' (the hotkey marker AskMenu reads, a space after all but the
  last). AskMenu (ovl07:1684) shows it on the prompt line and returns the 0-based position of the key
  pressed, $FF for a key that is no hotkey; WriteVmWord stores it. A single option
  'PRESS <RETURN> OR BUTTON TO CONTINUE' becomes 'PRESS <ENTER>/<RETURN> TO CONTINUE' and Return
  answers it (AcceptEnter). Animate is set when the close-up is up (ds84E0) and ds84E1 is set. The
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
  Animate := Ord((ds84E0 <> 0) and (ds84E1 <> 0));
  for I := 1 to Count - 1 do
    Options := Options + '~' + EclStrings[I] + ' ';
  Options := Options + '~' + EclStrings[Count];
  Choice := AskMenu(Title, Options, MenuTitleColor, WordColor, HotColor, AcceptEnter, Animate);
  WriteVmWord(Target, Choice);
  ClearRect(PromptLeftCol, PromptRow, PromptLastCol, PromptRow);
end;
{ ovl03:125D. ECL command 28 (dispatcher ovl03:2F2D, SkippedOpcode $1C): clears the encounter. It has no
  operands and moves EclPC past the command. The members ECL command 11 added are dropped
  (EncounterMemberCount and ds84E7 go to 0), the icon slot ds6F83 goes back to FirstEncounterIcon,
  PooledMoney is cleared, and the item list ds6810 is freed line by line (SizeOf(TMenuLine) bytes each). }
procedure ClearEncounterCommand;
var
  Next: PMenuLine;
  Unused: Word;                 { QUIRK ovl03:125D: two bytes of the frame nothing uses }
begin
  Inc(EclPC);
  EncounterMemberCount := 0;
  ds84E7 := 0;
  ds6F83 := FirstEncounterIcon;
  FillChar(PooledMoney, SizeOf(TPartyMoney), 0);
  while ds6810 <> nil do
  begin
    Next := ds6810^.Next;
    FreeMem(ds6810, SizeOf(TMenuLine));
    ds6810 := Next;
  end;
end;
{ ovl03:12C6: frame not read }
{@stub} procedure ovl03_fn_12C6; begin end;
{ ovl03:1307: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_1307; begin end;
{ ovl03:13D7: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_13D7; begin end;
{ ovl03:1435: retf 0: 0 bytes of parameters; 26 bytes of locals }
{@stub} procedure ovl03_fn_1435; begin end;
{ ovl03:1629: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl03_fn_1629; begin end;
{ ovl03:16C9: frame not read }
{@stub} procedure ovl03_fn_16C9; begin end;
{ ovl03:1758: frame not read }
{@stub} procedure ovl03_fn_1758; begin end;
{ ovl03:179B: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl03_fn_179B; begin end;
{ ovl03:18F8: retf 0: 0 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl03_fn_18F8; begin end;
{ ovl03:19B0: frame not read }
{@stub} procedure ovl03_fn_19B0; begin end;
{ ovl03:1B42: frame not read }
{@stub} procedure ovl03_fn_1B42; begin end;
{ ovl03:1C13: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_1C13; begin end;
{ ovl03:1DB1: retf 0: 0 bytes of parameters; 18 bytes of locals }
{@stub} procedure ovl03_fn_1DB1; begin end;
{ ovl03:1EF8: frame not read }
{@stub} procedure ovl03_fn_1EF8; begin end;
{ ovl03:238D: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_238D; begin end;
{ ovl03:25CB: retf 0: 0 bytes of parameters; 302 bytes of locals }
{@stub} procedure ovl03_fn_25CB; begin end;
{ ovl03:266A: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl03_fn_266A; begin end;
{ ovl03:271F: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_271F; begin end;
{ ovl03:2775: retf 0: 0 bytes of parameters; 62 bytes of locals }
{@stub} procedure ovl03_fn_2775; begin end;
{ ovl03:2AA2: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_2AA2; begin end;
{ ovl03:2AC1: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl03_fn_2AC1; begin end;
{ ovl03:2AEB: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_2AEB; begin end;
{ ovl03:2B14: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_2B14; begin end;
{ ovl03:2B33: retf 0: 0 bytes of parameters; 256 bytes of locals }
{@stub} procedure ovl03_fn_2B33; begin end;
{ ovl03:2B7E: retf 0: 0 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl03_fn_2B7E; begin end;
{ ovl03:2C03: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl03_fn_2C03; begin end;
{ ovl03:2CCF: frame not read }
{@stub} procedure ovl03_fn_2CCF; begin end;
{ ovl03:2D39: frame not read }
{@stub} procedure ovl03_fn_2D39; begin end;
{ ovl03:2DBA: frame not read }
{@stub} procedure ovl03_fn_2DBA; begin end;
{ ovl03:2DCB: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_2DCB; begin end;
{ ovl03:2DD3: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl03_fn_2DD3; begin end;
{ ovl03:2E10: retf 0: 0 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl03_fn_2E10; begin end;
{ ovl03:2E7D: retf 0: 0 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl03_fn_2E7D; begin end;
{ ovl03:2F2D: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_2F2D; begin end;
{ ovl03:3171: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_3171; begin end;
{ ovl03:31B4: retf 0: 0 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl03_fn_31B4; begin end;
{ ovl03:32F8: frame not read }
{@stub} procedure ovl03_e1; begin end;
{ ovl03:3379: frame not read }
{@stub} procedure ovl03_fn_3379; begin end;
{ ovl03:34AB: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_34AB; begin end;

begin
end.
