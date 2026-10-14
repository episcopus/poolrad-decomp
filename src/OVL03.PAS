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
procedure ovl03_fn_0856;
procedure ovl03_fn_08E5;
procedure ovl03_fn_0951;
procedure ovl03_fn_0994;
procedure ovl03_fn_0A09;
procedure ovl03_fn_0A9F;
procedure ovl03_fn_0AED;
procedure ovl03_fn_0B39;
procedure ovl03_fn_0B43;
procedure ovl03_fn_0B48;
procedure ovl03_fn_0B52;
procedure ovl03_fn_0BD1;
procedure ovl03_fn_0C74;
procedure ovl03_fn_0D7B;
procedure ovl03_fn_0DEF;
procedure ovl03_fn_0E5E;
procedure ovl03_fn_0EBC;
procedure ovl03_fn_0F08;
procedure ovl03_fn_0FE2;
procedure ovl03_fn_10D1;
procedure ovl03_fn_125D;
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
uses OVL32;

const
  { The operand types from this one up are strings: $80 a packed string, $81 the address of a
    stored one (DecodeOperands in OVL07). }
  FirstStringOperandType = $80;
  { The opcodes of the arithmetic commands (ovl03:01A3). }
  OpAdd = 4;
  OpSub = 5;
  OpDiv = 6;
  OpMul = 7;
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
{ ovl03:0856: frame not read }
{@stub} procedure ovl03_fn_0856; begin end;
{ ovl03:08E5: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_08E5; begin end;
{ ovl03:0951: retf 0: 0 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl03_fn_0951; begin end;
{ ovl03:0994: retf 0: 0 bytes of parameters; 516 bytes of locals }
{@stub} procedure ovl03_fn_0994; begin end;
{ ovl03:0A09: retf 0: 0 bytes of parameters; 256 bytes of locals }
{@stub} procedure ovl03_fn_0A09; begin end;
{ ovl03:0A9F: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_0A9F; begin end;
{ ovl03:0AED: frame not read }
{@stub} procedure ovl03_fn_0AED; begin end;
{ ovl03:0B39: frame not read }
{@stub} procedure ovl03_fn_0B39; begin end;
{ ovl03:0B43: frame not read }
{@stub} procedure ovl03_fn_0B43; begin end;
{ ovl03:0B48: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_0B48; begin end;
{ ovl03:0B52: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_0B52; begin end;
{ ovl03:0BD1: retf 0: 0 bytes of parameters; 260 bytes of locals }
{@stub} procedure ovl03_fn_0BD1; begin end;
{ ovl03:0C74: frame not read }
{@stub} procedure ovl03_fn_0C74; begin end;
{ ovl03:0D7B: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_0D7B; begin end;
{ ovl03:0DEF: retf 0: 0 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl03_fn_0DEF; begin end;
{ ovl03:0E5E: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl03_fn_0E5E; begin end;
{ ovl03:0EBC: retf 0: 0 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl03_fn_0EBC; begin end;
{ ovl03:0F08: frame not read }
{@stub} procedure ovl03_fn_0F08; begin end;
{ ovl03:0FE2: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_0FE2; begin end;
{ ovl03:10D1: retf 0: 0 bytes of parameters; 320 bytes of locals }
{@stub} procedure ovl03_fn_10D1; begin end;
{ ovl03:125D: retf 0: 0 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl03_fn_125D; begin end;
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
