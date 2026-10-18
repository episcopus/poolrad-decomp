#include "game.h"

/* ovl03:0001. The ECL command 0, the only command that takes no operands (the dispatcher at
     ovl03:2F2D calls it for CurrentOpcode 0). When PictureFrameDirty is set it redraws (clears and frames) the
     picture frame window and, when the game variable VarForceWallView is nonzero, the close-up box (columns 3 to 13)
     inside it; it then selects the character at ReselectCharacter when ReselectCharacterPending is set, clears the
     two-byte scratch
     PictureShownFlags,
     moves EclPC past the command, empties the return stack of ScriptGosub, and puts the text
     cursor at column 1, row 17 (GlyphCol, GlyphRow). */
void EndCommand(void)
{
  POOL_TRACE("EndCommand");
  if (PictureFrameDirty != 0) {
    DrawWindow(PictureFrameLeft, PictureFrameTop, PictureFrameRight, PictureFrameBottom, 0, 0xF, S("\000"));
    if ((*FPD(TGameVars (*), GameVars))[230] != 0) {
      DrawWindow(3, 3, 0xD, 0xD, 0, 0xF, S("\000"));
    }
  }
  if (ReselectCharacterPending != 0) {
    SelectedCharacter = ReselectCharacter;
    ReselectCharacterPending = 0;
  }
  rtl_FillChar((void *)&PictureShownFlags, 2, 0);
  CloseUpShown = 0;
  PictureFrameDirty = 0;
  ScriptRunEnded = 1;
  EclPC++;
  while (ReturnStack != 0) {
    ReturnPrev = (*FPD(TReturnEntry (*), ReturnStack)).Next;
    rtl_freemem(ReturnStack, 6);
    ReturnStack = ReturnPrev;
  }
  GlyphRow = EclTextTop;
  GlyphCol = EclTextLeft;
  GlyphRunInBox = 0;
}

/* ovl03:00F4. ECL command 1 (dispatcher ovl03:2F2D, CurrentOpcode 1): an unconditional jump. Its
     one operand is a script address, and EclPC moves to it (the same jump ScriptGosub makes after
     it pushes the return address). */
void GotoCommand(void)
{
  POOL_TRACE("GotoCommand");
  DecodeOperands(1);
  EclPC = MakeWord(OperandLow[1], OperandHigh[1]);
}

/* ovl03:0111. ECL command 2 (dispatcher ovl03:2F2D, CurrentOpcode 2): a subroutine call. Its one
     operand is the script address of the subroutine; ScriptGosub pushes the return address and
     jumps there. */
void GosubCommand(void)
{
  POOL_TRACE("GosubCommand");
  DecodeOperands(1);
  ScriptGosub(1);
}

/* ovl03:0126. ECL command 3 (dispatcher ovl03:2F2D, CurrentOpcode 3): compares its two operands
     and sets CompareFlags for the conditional commands. When either operand is a string (type bit 7
     set) both strings are taken from EclStrings[1] and [2], whatever the types, and compared with
     CompareStrings; otherwise the two word values are compared with CompareWords. */
void CompareCommand(void)
{
  POOL_TRACE("CompareCommand");
  u16 LeftWord = 0;
  u16 RightWord = 0;
  u8 Left[256] = {0};
  u8 Right[256] = {0};
  DecodeOperands(2);
  if (((OperandType[1] >= FirstStringOperandType)) || ((OperandType[2] >= FirstStringOperandType))) {
    rtl_str_assign(Left, 255, EclStrings[1]);
    rtl_str_assign(Right, 255, EclStrings[2]);
    CompareStrings(Left, Right);
  } else {
    LeftWord = OperandValue(1);
    RightWord = OperandValue(2);
    CompareWords(LeftWord, RightWord);
  }
}

/* ovl03:01A3. ECL commands 4 to 7 (dispatcher ovl03:2F2D, CurrentOpcode OpAdd, OpSub, OpDiv or
     OpMul): the values of the first two operands are combined and the answer is written with
     WriteVmWord to the script address the third operand names. Division and multiplication keep the
     low word of the answer. QUIRK ovl03:01FC: subtraction takes the second value minus the first,
     while division takes the first over the second. */
void ArithmeticCommand(void)
{
  POOL_TRACE("ArithmeticCommand");
  u16 Target = 0;
  u16 Values[2] = {0};
  s8 I = 0;
  u16 Answer = 0;
  u8 Unused = 0;
  DecodeOperands(3);
  {
    if (1 <= 2) {
      I = 1;
      for (;;) {
          Values[I - 1] = OperandValue(I);
        if (I == 2) break;
        I++;
      }
    }
  }
  Target = MakeWord(OperandLow[3], OperandHigh[3]);
  switch (CurrentOpcode) {
  case OpAdd:
  {
    Answer = Values[0] + Values[1];
    break;
  }
  case OpSub:
  {
    Answer = Values[1] - Values[0];
    break;
  }
  case OpDiv:
  {
    Answer = (Values[0] / Values[1]);
    break;
  }
  case OpMul:
  {
    Answer = Values[0] * Values[1];
    break;
  }
  }
  WriteVmWord(Target, Answer);
}

/* ovl03:0234. ECL command 8 (dispatcher ovl03:2F2D, CurrentOpcode 8): stores a random number. The
     first operand is the largest roll wanted: one is added to it, so the roll is 0 to that value
     (Random(n) gives 0 to n-1). The roll is written with WriteVmWord to the script address the
     second operand names. The Trunc keeps the Real conversion of the roll that the original makes
     (0AF8:119A, 119E); it changes nothing for a whole number. QUIRK ovl03:024D: a first operand of
     255 is not raised, so the roll can only be 0 to 254. */
void RandomCommand(void)
{
  POOL_TRACE("RandomCommand");
  u8 Range = 0;
  u8 Roll = 0;
  u16 Target = 0;
  DecodeOperands(2);
  Range = OperandValue(1);
  if (Range < 0xFF) {
    Range++;
  }
  Target = MakeWord(OperandLow[2], OperandHigh[2]);
  Roll = rtl_trunc((double)rtl_Random(Range));
  WriteVmWord(Target, Roll);
}

/* ovl03:0292. ECL command 9 (dispatcher ovl03:2F2D, CurrentOpcode 9): stores its first operand at
     the script address its second operand names. A string operand (type bit 7 set) is stored with
     WriteVmString from EclStrings[1]; a value is stored as a word with WriteVmWord. */
void StoreCommand(void)
{
  POOL_TRACE("StoreCommand");
  u16 Value = 0;
  u16 Target = 0;
  DecodeOperands(2);
  Target = MakeWord(OperandLow[2], OperandHigh[2]);
  if (OperandType[1] < FirstStringOperandType) {
    Value = OperandValue(1);
    WriteVmWord(Target, Value);
  } else {
    WriteVmString(Target, EclStrings[1]);
  }
}

/* ovl03:02E0. ECL command 10 (dispatcher ovl03:2F2D, CurrentOpcode 10): selects the party member at
     the 0-based position its operand names as SelectedCharacter. The walk starts at PartyListHead, the head
     of the party list (Next at +$104), and stops at the position or at the end of the list; a
     position past the end selects nothing. It sets ReselectCharacterPending first, so the next EndCommand (ovl03:0001)
     selects ReselectCharacter again. When the operand's bit 7 is set and the script has just cleared the
     character's name and status (ActiveFlagClearedByScript and NameClearedByScript, set by SetCharacterVar), the selected member
     leaves the party (RemoveSelectedCharacter, as ovl15:18E5 does) and is redrawn (DrawPartyRoster), and
     ReselectCharacterPending is
     cleared when that member is ReselectCharacter. */
void SelectCharacterCommand(void)
{
  POOL_TRACE("SelectCharacterCommand");
  PCharacter Member = 0;
  u8 Unused = 0;
  u8 Position = 0;
  u8 I = 0;
  u8 RemoveFlag = 0;
  ReselectCharacterPending = 1;
  DecodeOperands(1);
  I = 0;
  Position = OperandValue(1);
  Member = PartyListHead;
  RemoveFlag = (Position & RemoveMemberBit);
  Position = (Position & PositionMask);
  if (Position > 0) {
    while (((I < Position)) && ((Member != 0))) {
      Member = (*FPD(TCharacter (*), Member)).Next;
      I++;
    }
  }
  if (Member != 0) {
    SelectedCharacter = Member;
  }
  if ((((RemoveFlag != 0)) && ((ActiveFlagClearedByScript != 0))) && ((NameClearedByScript != 0))) {
    if (ReselectCharacter == SelectedCharacter) {
      ReselectCharacterPending = 0;
    }
    RemoveSelectedCharacter(0, 1);
    DrawPartyRoster(SelectedCharacter);
    ActiveFlagClearedByScript = 0;
    NameClearedByScript = 0;
  }
}

/* ovl03:03B4. ECL command 12 (dispatcher ovl03:2F2D, CurrentOpcode 12): shows an encounter picture
     at the distance the party can see ahead. Operand 1 is the sprite bank (EncounterSpriteBank) and
     operand 3 the picture bank (EncounterPicBank), both passed to ShowEncounterPicture; operand 2 is
     the largest distance the script allows, kept in word 704 of GameVars2. The distance is the steps
     ahead (OpenStepsAhead, which also stores them in word 705), cut down to that limit. The two shown
     flags are PictureShown (PictureShownFlags). */
void ShowEncounterCommand(void)
{
  POOL_TRACE("ShowEncounterCommand");
  u16 Unused = 0;
  DecodeOperands(3);
  EncounterSpriteBank = OperandValue(1);
  (*FPD(TGameVars (*), GameVars2))[704] = OperandValue(2);
  EncounterPicBank = OperandValue(3);
  (*FPD(TGameVars (*), GameVars2))[705] = OpenStepsAhead(PartyMapColumn, PartyMapRow, PartyFacing);
  if ((*FPD(TGameVars (*), GameVars2))[704] < (*FPD(TGameVars (*), GameVars2))[705]) {
    (*FPD(TGameVars (*), GameVars2))[705] = (*FPD(TGameVars (*), GameVars2))[704];
  }
  ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank, (u8)(*FPD(TGameVars (*), GameVars2))[705], &PictureShown);
}

/* ovl03:0450. ECL command 11 (dispatcher ovl03:2F2D, CurrentOpcode 11): adds a group of encounter
     members to the party list PartyListHead (icons from 8 up, so not the party's own members). Operand 1 is
     the kind LoadCharacter loads (LoadMonster, the save and load unit), operand 2 the number of members
     (at least 1), operand 3 the block of the combat picture 'CPIC' loaded into the icon slot EncounterIconSlot.
     The loaded character goes to the tail of the list first, then Count - 1 copies of it, each with
     its own copies of the item and affect lists (the copies are prepended, so the lists come out in
     reverse order). Every member gets CombatIcon := EncounterIconSlot, and the slot goes up by one afterwards.
     Nothing is added once EncounterMemberCount reaches MaxEncounterMembers. SelectedCharacter is saved
     and restored, and EncounterMembersAdded is set. */
void AddEncounterGroupCommand(void)
{
  POOL_TRACE("AddEncounterGroupCommand");
  u8 Kind = 0;
  u8 Count = 0;
  u8 PictureBlock = 0;
  u8 I = 0;
  PCharacter Last = 0;
  PCharacter NewMember = 0;
  PCharacter Who = 0;
  PCharacter Saved = 0;
  TCharacter Template = {0};
  u8 PictureSetName[13] = {0};
  PItem Items = 0;
  PItem OldItem = 0;
  PItem ItemsHead = 0;
  farptr Affects = 0;
  PAffect OldAffect = 0;
  farptr AffectsHead = 0;
  Saved = SelectedCharacter;
  I = 1;
  DecodeOperands(3);
  if (EncounterMemberCount >= MaxEncounterMembers) {
    return;
  }
  Last = 0;
  NewMember = 0;
  Kind = OperandValue(1);
  LoadCharacter(Kind, &Who, &Items, &Affects);
  Template = (*FPD(TCharacter (*), Who));
  ItemsHead = Items;
  AffectsHead = Affects;
  Count = OperandValue(2);
  if (Count <= 0) {
    Count = 1;
  }
  PictureBlock = OperandValue(3);
  Last = PartyListHead;
  rtl_str_assign(PictureSetName, 12, S("\004CPIC"));
  LoadPictureSlot(PictureSetName, PictureBlock, EncounterIconSlot);
  while ((*FPD(TCharacter (*), Last)).Next != 0) {
    Last = (*FPD(TCharacter (*), Last)).Next;
  }
  (*FPD(TCharacter (*), Last)).Next = Who;
  Last = (*FPD(TCharacter (*), Last)).Next;
  (*FPD(TCharacter (*), Last)).CombatIcon = EncounterIconSlot;
  (*FPD(TCharacter (*), Last)).Next = 0;
  EncounterMemberCount++;
  I++;
  while (((I <= Count)) && ((EncounterMemberCount < MaxEncounterMembers))) {
    NewMember = rtl_getmem(285);
    (*FPD(TCharacter (*), Last)).Next = NewMember;
    Last = (*FPD(TCharacter (*), Last)).Next;
    (*FPD(TCharacter (*), Last)) = Template;
    (*FPD(TCharacter (*), Last)).CombatIcon = EncounterIconSlot;
    (*FPD(TCharacter (*), Last)).Next = 0;
    (*FPD(TCharacter (*), Last)).Affects = 0;
    (*FPD(TCharacter (*), Last)).Items = 0;
    I++;
    EncounterMemberCount++;
    while (Items != 0) {
      if ((*FPD(TCharacter (*), Last)).Items == 0) {
        (*FPD(TCharacter (*), Last)).Items = rtl_getmem(63);
        (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Last)).Items)) = (*FPD(TMenuLine (*), Items));
        (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Last)).Items)).Next = 0;
      } else {
        OldItem = (*FPD(TCharacter (*), Last)).Items;
        (*FPD(TCharacter (*), Last)).Items = rtl_getmem(63);
        (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Last)).Items)) = (*FPD(TMenuLine (*), Items));
        (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Last)).Items)).Next = OldItem;
      }
      Items = (*FPD(TMenuLine (*), Items)).Next;
    }
    Items = ItemsHead;
    while (Affects != 0) {
      if ((*FPD(TCharacter (*), Last)).Affects == 0) {
        (*FPD(TCharacter (*), Last)).Affects = rtl_getmem(9);
        (*FPD(TAffect (*), (*FPD(TCharacter (*), Last)).Affects)) = (*FPD(TAffect (*), Affects));
        (*FPD(TAffect (*), (*FPD(TCharacter (*), Last)).Affects)).Next = 0;
      } else {
        OldAffect = (*FPD(TCharacter (*), Last)).Affects;
        (*FPD(TCharacter (*), Last)).Affects = rtl_getmem(9);
        (*FPD(TAffect (*), (*FPD(TCharacter (*), Last)).Affects)) = (*FPD(TAffect (*), Affects));
        (*FPD(TAffect (*), (*FPD(TCharacter (*), Last)).Affects)).Next = OldAffect;
      }
      Affects = (*FPD(TAffect (*), Affects)).Next;
    }
    Affects = AffectsHead;
  }
  EncounterIconSlot++;
  EncounterMembersAdded = 1;
  SelectedCharacter = Saved;
}

/* ovl03:0817. ECL command 13 (dispatcher ovl03:2F2D, CurrentOpcode 13): brings the encounter picture
     one step nearer. While the steps the party sees ahead (VarStepsAhead, word 705 of GameVars2) are not
     used up, it takes one off and shows the picture again at the new distance (ShowEncounterPicture).
     It has no operands and always moves EclPC past the command. */
void ApproachEncounterCommand(void)
{
  POOL_TRACE("ApproachEncounterCommand");
  if ((*FPD(TGameVars (*), GameVars2))[705] > 0) {
    (*FPD(TGameVars (*), GameVars2))[705]--;
    ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank, (u8)(*FPD(TGameVars (*), GameVars2))[705], &PictureShown);
  }
  EclPC++;
}

/* ovl03:0856. ECL command 14 (dispatcher ovl03:2F2D, CurrentOpcode 14): shows the close-up picture of
     the encounter, or hides it. Operand 1 is the picture bank PicBank. When PicBank is HideCloseUp, the
     close-up goes: when PreviousAreaViewKind is above 1 or AreaViewKind is 1 and a close-up or the 3D sprite is up
     (CloseUpShown or Sprite3DLoaded), the area view is drawn again (ShowAreaView), those flags are cleared and CloseUpHidden
     is set; both PictureShown flags are cleared. Otherwise the picture window (3, 3 to 13, 13) is
     cleared first unless VarForceWallView is set, and the close-up is drawn as ShowEncounterPicture
     draws it: the PIC picture PicBank when word VarCloseUpHead of GameVars2 is NoHeadBank, else the HEAD
     and BODY pictures (ShowHeadBody). Purpose of PreviousAreaViewKind unknown: the loader sets it to 1 (ovl11:03EB). */
void ShowCloseUpCommand(void)
{
  POOL_TRACE("ShowCloseUpCommand");
  u8 PicBank = 0;
  DecodeOperands(1);
  PicBank = OperandValue(1);
  if ((((*FPD(TGameVars (*), GameVars))[230] == 0)) && ((PicBank != HideCloseUp))) {
    DrawWindow(3, 3, 0xD, 0xD, 0, 0xF, S("\000"));
  }
  if (PicBank != HideCloseUp) {
    PictureShown[1] = 1;
    CloseUpShown = 1;
    if ((*FPD(TGameVars (*), GameVars2))[737] == NoHeadBank) {
      LoadSpriteList(S("\003PIC"), PicBank, 0, rtl_far(&PictureAnimation));
      DrawSprite(3, 3, 1, PictureAnimation.Frames[0].Sprite);
    } else {
      ShowHeadBody((*FPD(TGameVars (*), GameVars2))[737], PicBank);
    }
  } else {
    if (((((PreviousAreaViewKind > 1)) || ((AreaViewKind == 1)))) && ((((CloseUpShown != 0)) || ((Sprite3DLoaded != 0))))) {
      ShowAreaView();
      CloseUpShown = 0;
      Sprite3DLoaded = 0;
      CloseUpHidden = 1;
    }
    PictureShown[0] = 0;
    PictureShown[1] = 0;
  }
}

/* ovl03:0951. ECL command 15 (dispatcher ovl03:2F2D, CurrentOpcode 15): asks the player for a number
     and stores it as a word at the script address that operand 2 names. Operand 1 is decoded but never
     read. The prompt is empty; ReadNumber (RES06, colour 10) repeats the input line until the text is a
     number from 0 to 65536. */
void ReadNumberCommand(void)
{
  POOL_TRACE("ReadNumberCommand");
  u8 Prompt[2] = {0};
  u16 Number = 0;
  u16 Target = 0;
  DecodeOperands(2);
  rtl_str_assign(Prompt, 1, S("\000"));
  Target = MakeWord(OperandLow[2], OperandHigh[2]);
  Number = ReadNumber(Prompt, 10);
  WriteVmWord(Target, Number);
}

/* ovl03:0994. ECL command 16 (dispatcher ovl03:2F2D, CurrentOpcode 16): asks the player for a line of
     text and stores it as a string at the script address that operand 2 names (WriteVmString). Operand
     1 is decoded but never read. The prompt is empty; ReadInputLine (RES06) reads the line in colour
     EclTextColor, at most EclInputMaxLength characters. An empty answer is stored as one space, so the
     script's string is never empty. */
void ReadStringCommand(void)
{
  POOL_TRACE("ReadStringCommand");
  u8 Prompt[2] = {0};
  u16 Target = 0;
  u8 Answer[256] = {0};
  u8 t1[256];
  DecodeOperands(2);
  rtl_str_assign(Prompt, 1, S("\000"));
  Target = MakeWord(OperandLow[2], OperandHigh[2]);
  rtl_str_assign(Answer, 255, ReadInputLine(t1, Prompt, EclTextColor, EclInputMaxLength));
  if (Answer[0] == 0) {
    rtl_str_assign(Answer, 255, S("\001 "));
  }
  WriteVmString(Target, Answer);
}

/* ovl03:0A09. ECL commands 17 and 18 (dispatcher ovl03:2F2D, CurrentOpcode $11 or $12): show the text
     of operand 1 in the ECL text window (EclTextLeft to EclTextRight, EclTextTop to EclTextBottom) with
     ShowPagedText. A number operand is turned into its text by WordToText and stored in EclStrings[1];
     a string operand is already there (DecodeOperands). Command 17 (OpContinueText) leaves the window and
     the cursor as they are; command 18 clears the window and puts the cursor at its top left corner first.
     EclWindowCleared is cleared, and DelayPerGlyph is set while the text is shown: DrawTextRun then waits after each
     glyph. */
void ShowTextCommand(void)
{
  POOL_TRACE("ShowTextCommand");
  u8 t1[256];
  DecodeOperands(1);
  EclWindowCleared = 0;
  DelayPerGlyph = 1;
  if (OperandType[1] < FirstStringOperandType) {
    rtl_str_assign(EclStrings[1], 255, WordToText(t1, OperandValue(1)));
  }
  if (CurrentOpcode == OpContinueText) {
    ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 0, EclStrings[1]);
  } else {
    GlyphRow = EclTextTop;
    GlyphCol = EclTextLeft;
    ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1, EclStrings[1]);
  }
  DelayPerGlyph = 0;
}

/* ovl03:0A9F. ECL command 19 (dispatcher ovl03:2F2D, CurrentOpcode $13): returns from a subroutine
     that ScriptGosub (ovl07:1951) called. EclPC moves past the command. When the return stack
     ReturnStack is not empty, EclPC takes the return address of its top entry (ReturnPC), the entry is
     freed and ReturnStack moves to the entry below it (Next, which ReturnPrev holds while the entry is
     freed). An empty stack leaves EclPC just past the command. */
void ReturnCommand(void)
{
  POOL_TRACE("ReturnCommand");
  EclPC++;
  if (ReturnStack != 0) {
    EclPC = (*FPD(TReturnEntry (*), ReturnStack)).ReturnPC;
    ReturnPrev = (*FPD(TReturnEntry (*), ReturnStack)).Next;
    rtl_freemem(ReturnStack, 6);
    ReturnStack = ReturnPrev;
  }
}

/* ovl03:0AED. ECL command 20 (dispatcher ovl03:2F2D, CurrentOpcode $14): compares two pairs of word
     operands. The six CompareFlags are cleared, the four operands are read as words (OperandValue),
     and operand 1 is compared with operand 2 and operand 3 with operand 4. When both pairs are equal
     CompareFlags[0] (=) is set, else CompareFlags[1] (<>). The conditional commands 22 to 27 (the
     handler at ovl03:0B52) test these flags. */
void CompareBothPairsCommand(void)
{
  POOL_TRACE("CompareBothPairsCommand");
  u16 Values[4] = {0};
  u8 I = 0;
  u8 Unused = 0;
  rtl_FillChar((void *)&CompareFlags, 6, 0);
  DecodeOperands(4);
  {
    if (1 <= 4) {
      I = 1;
      for (;;) {
          Values[I - 1] = OperandValue(I);
        if (I == 4) break;
        I++;
      }
    }
  }
  if (((Values[0] == Values[1])) && ((Values[2] == Values[3]))) {
    CompareFlags[0] = 1;
  } else {
    CompareFlags[1] = 1;
  }
}

/* ovl03:0B52. ECL commands 22 to 27 (dispatcher ovl03:2F2D, CurrentOpcode OpIfEqual to
     OpIfGreaterOrEqual): a conditional. EclPC moves past the opcode, then the next command runs only
     when its comparison flag in CompareFlags is set (=, <>, <, >, <=, >= in that order, set by
     CompareCommand, CompareBothPairsCommand and the comparison routines of OVL07). When the flag is clear,
     SkipCommand steps over the next command. Any other opcode only moves EclPC. */
void RunIfCompared(void)
{
  POOL_TRACE("RunIfCompared");
  EclPC++;
  switch (CurrentOpcode) {
  case OpIfEqual:
  {
    if (CompareFlags[0] == 0) {
      SkipCommand();
    }
    break;
  }
  case OpIfNotEqual:
  {
    if (CompareFlags[1] == 0) {
      SkipCommand();
    }
    break;
  }
  case OpIfLess:
  {
    if (CompareFlags[2] == 0) {
      SkipCommand();
    }
    break;
  }
  case OpIfGreater:
  {
    if (CompareFlags[3] == 0) {
      SkipCommand();
    }
    break;
  }
  case OpIfLessOrEqual:
  {
    if (CompareFlags[4] == 0) {
      SkipCommand();
    }
    break;
  }
  case OpIfGreaterOrEqual:
  {
    if (CompareFlags[5] == 0) {
      SkipCommand();
    }
    break;
  }
  }
}

/* ovl03:0BD1. ECL command 32 (dispatcher ovl03:2F2D, CurrentOpcode $20): starts ECL block Block of the
     area's script file. The operand is the block number: the WallViewMode of the area is saved in
     VarSavedWallView, then WallViewMode takes the block number. The file is GameDir + 'ECL' + the
     TileSet number + '.dax' (its path goes to SaveAndExit first), LoadEcl loads the block and InitScript
     resets the script machine. ScriptRunEnded and ScriptBlockStarted are set to 1 and AreaRedrawArmed is cleared. */
void StartEclBlock(void)
{
  POOL_TRACE("StartEclBlock");
  u8 Block = 0;
  u8 TileSetText[2] = {0};
  u8 t1[256];
  DecodeOperands(1);
  (*FPD(TGameVars (*), GameVars))[242] = WallViewMode;
  Block = OperandValue(1);
  WallViewMode = Block;
  rtl_str_int(TileSetText, 1, TileSet, 0);
  SaveAndExit(rtl_str_cat(t1, 4, (const u8 *const[]){GameDir, S("\003ECL"), TileSetText, S("\004.dax")}));
  LoadEcl(Block);
  InitScript();
  ScriptRunEnded = 1;
  ScriptBlockStarted = 1;
  AreaRedrawArmed = 0;
}

/* ovl03:0C74. ECL commands 33 and 55 (dispatcher ovl03:2F2D, CurrentOpcode $21 or $37): load the
     graphics of the area for the three operands, the block numbers Blocks, where $FF means none.
     Command 33 loads the 3D map Blocks[1] (Load3DMap, VarGeoBlock keeps its number) when
     VarForceWallView is set, and the 'BACPAC' picture set (Load24x24Set) when Blocks[3] is given and
     VarForceWallView is clear. Command 55 loads the wall sets: slot 1 gets wall set 0 when Blocks[1] is
     $7F; when words 231 and 232 of GameVars are both set, slots 1 and 3 get Blocks[1] and Blocks[3],
     else each slot I gets Blocks[I] or, for $FF, the two words of WallSetSlotPairs[I] become $FFFF. The
     label ovl03:0D7B is the slot loop of this routine. AreaRedrawArmed is set first. When AreaStepRedrawOnce,
     Command55Ran and
     Command33Ran are all set, RedrawView runs, the selected character is redrawn (DrawPartyRoster) and
     AreaStepRedrawOnce is cleared. Words 231 and 232 of GameVars and word 713 of GameVars2 are not named yet. */
void LoadAreaGraphics(void)
{
  POOL_TRACE("LoadAreaGraphics");
  u8 Blocks[3] = {0};
  u8 I = 0;
  DecodeOperands(3);
  AreaRedrawArmed = 1;
  {
    if (1 <= 3) {
      I = 1;
      for (;;) {
          Blocks[I - 1] = OperandValue(I);
        if (I == 3) break;
        I++;
      }
    }
  }
  if (CurrentOpcode == 0x21) {
    Command33Ran = 1;
    if ((((Blocks[0] != 0xFF)) && ((Blocks[0] != 0x7F))) && (((*FPD(TGameVars (*), GameVars))[230] != 0))) {
      (*FPD(TGameVars (*), GameVars))[197] = Blocks[0];
      Load3DMap(Blocks[0]);
      (*FPD(TGameVars (*), GameVars2))[713] = 0;
    }
    if (((Blocks[2] != 0xFF)) && (((*FPD(TGameVars (*), GameVars))[230] == 0))) {
      Load24x24Set(S("\006BACPAC"), 0, 40);
    }
  } else {
    Command55Ran = 1;
    if (Blocks[0] == 0x7F) {
      LoadWallSet(0, 1);
    } else if ((((*FPD(TGameVars (*), GameVars))[231] != 0)) && (((*FPD(TGameVars (*), GameVars))[232] != 0))) {
      LoadWallSet(Blocks[0], 1);
      LoadWallSet(Blocks[2], 3);
    } else {
      {
        if (1 <= 3) {
          I = 1;
          for (;;) {
              if (Blocks[I - 1] != 0xFF) {
                LoadWallSet(Blocks[I - 1], I);
              } else {
                WallSetSlotPairs[I].A = 0xFFFF;
                WallSetSlotPairs[I].B = 0xFFFF;
              }
            if (I == 3) break;
            I++;
          }
        }
      }
    }
  }
  if ((((AreaStepRedrawOnce != 0)) && ((Command55Ran != 0))) && ((Command33Ran != 0))) {
    RedrawView();
    DrawPartyRoster(SelectedCharacter);
    AreaStepRedrawOnce = 0;
  }
}

/* ovl03:0DEF. ECL commands 47 and 48 (dispatcher ovl03:2F2D, CurrentOpcode OpAnd or OpOr): the
     bitwise and (47) or or (48) of the values of operands 1 and 2, kept as a byte. CompareWords compares
     that byte with 0, which sets the flags of CompareFlags for the conditional commands, and the byte is
     written with WriteVmWord to the script address operand 3 names. */
void BitwiseCommand(void)
{
  POOL_TRACE("BitwiseCommand");
  u16 Target = 0;
  u16 Second = 0;
  u16 First = 0;
  u8 Combined = 0;
  DecodeOperands(3);
  First = OperandValue(1);
  Second = OperandValue(2);
  Target = MakeWord(OperandLow[3], OperandHigh[3]);
  if (CurrentOpcode == OpAnd) {
    Combined = (First & Second);
  } else {
    Combined = (First | Second);
  }
  CompareWords(0, Combined);
  WriteVmWord(Target, Combined);
}

/* ovl03:0E5E. ECL command 42 (dispatcher ovl03:2F2D, CurrentOpcode $2A): copies a word out of a table.
     Operand 1 is the script address of the table, operand 2 the index (a byte) and operand 3 the script
     address the word goes to: the word at table + index is read with ReadVmWord and written with
     WriteVmWord. */
void CopyIndexedWordCommand(void)
{
  POOL_TRACE("CopyIndexedWordCommand");
  u16 Base = 0;
  u16 Dest = 0;
  u16 Source = 0;
  u16 Value = 0;
  u8 Index = 0;
  DecodeOperands(3);
  Base = MakeWord(OperandLow[1], OperandHigh[1]);
  Index = OperandValue(2);
  Dest = MakeWord(OperandLow[3], OperandHigh[3]);
  Source = Base + Index;
  Value = ReadVmWord(Source);
  WriteVmWord(Dest, Value);
}

/* ovl03:0EBC. ECL command 53 (dispatcher ovl03:2F2D, CurrentOpcode $35): stores operand 1 as a word
     in a table of words. Operand 2 is the script address of the table and operand 3 the index: the
     word goes to table + index with WriteVmWord. It is the store that CopyIndexedWordCommand (ovl03:0E5E,
     command 42) reads back. */
void StoreIndexedWordCommand(void)
{
  POOL_TRACE("StoreIndexedWordCommand");
  u16 Index = 0;
  u16 Base = 0;
  u16 Value = 0;
  u16 Addr = 0;
  DecodeOperands(3);
  Value = OperandValue(1);
  Base = MakeWord(OperandLow[2], OperandHigh[2]);
  Index = OperandValue(3);
  Addr = Base + Index;
  WriteVmWord(Addr, Value);
}

/* ovl03:0F08. ECL command 21 (dispatcher ovl03:2F2D, CurrentOpcode $15): a list menu. Operand 1 is
     the address that receives Choice, the index AskListMenu returns for the line the player picked.
     The prompt is the first string operand (EclStrings[1]); it is shown in the text window
     (EclTextLeft to EclTextRight, EclTextTop to EclTextBottom) and the list goes under it. Operand 3
     is the number of lines: they are the string operands EclStrings[1..Count], decoded again after
     Dec(EclPC) backs EclPC up one byte. The lines are built as a TMenuLine list (NewMenuList), each
     holding its text (at most 40 characters) and a cleared Flag29. QUIRK ovl03:0F08: AskListMenu
     leaves the chosen line in Menu (its var parameter), so FreeMenuList frees from that line on
     and the lines before it stay allocated [I]. The window is cleared afterwards. */
void ChooseFromListCommand(void)
{
  POOL_TRACE("ChooseFromListCommand");
  u8 Count = 0;
  u8 I = 0;
  u8 Prompt[256] = {0};
  PMenuLine Menu = 0;
  PMenuLine MenuHead = 0;
  u8 Empty[2] = {0};
  s16 Choice = 0;
  u8 Redraw = 0;
  u16 Target = 0;
  u8 Unused = 0;
  EclWindowCleared = 0;
  Redraw = 1;
  rtl_str_assign(Empty, 1, S("\000"));
  I = 1;
  DecodeOperands(3);
  Target = MakeWord(OperandLow[1], OperandHigh[1]);
  rtl_str_assign(Prompt, 255, EclStrings[1]);
  Count = OperandValue(3);
  EclPC--;
  DecodeOperands(Count);
  NewMenuList(Count, &Menu);
  MenuHead = Menu;
  GlyphCol = EclTextLeft;
  GlyphRow = EclTextTop;
  ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1, Prompt);
  while (Menu != 0) {
    rtl_str_assign((*FPD(TMenuLine (*), Menu)).Text, 40, EclStrings[I]);
    (*FPD(TMenuLine (*), Menu)).Flag29 = 0;
    Menu = (*FPD(TMenuLine (*), Menu)).Next;
    I++;
  }
  Menu = MenuHead;
  Choice = 0;
  /* the list starts one row below GlyphRow, where ShowPagedText left the cursor */
  AskListMenu(Empty, Empty, MenuTitleColor, MenuTextColor, MenuHotColor, EclTextLeft, (s16)(GlyphRow + 1), EclTextRight, EclTextBottom, Menu, 0, &Redraw, &Choice, &Menu);
  WriteVmWord(Target, Choice);
  FreeMenuList(&Menu);
  ClearRect(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom);
}

/* ovl03:10D1. ECL command 43 (dispatcher ovl03:2F2D, CurrentOpcode $2B): asks the player a menu. Operand
     1 is the address that receives the answer, operand 2 the number of options Count; the options are the
     string operands EclStrings[1..Count], decoded again after Dec(EclPC) as in ChooseFromListCommand. They
     become one text, each option after a '~' (the hotkey marker AskMenu reads, a space after all but the
     last). AskMenu (ovl07:1684) shows it on the prompt line and returns the 0-based position of the key
     pressed, $FF for a key that is no hotkey; WriteVmWord stores it. A single option
     'PRESS <RETURN> OR BUTTON TO CONTINUE' becomes 'PRESS <ENTER>/<RETURN> TO CONTINUE' and Return
     answers it (AcceptEnter). Animate is set when the close-up is up (CloseUpShown) and CloseUpHidden is set. The
     prompt line is cleared afterwards. */
void AskMenuCommand(void)
{
  POOL_TRACE("AskMenuCommand");
  u8 Count = 0;
  u8 Choice = 0;
  u8 I = 0;
  u8 Title[2] = {0};
  u8 Options[51] = {0};
  u16 Target = 0;
  u8 AcceptEnter = 0;
  u8 Animate = 0;
  u8 HotColor_ = 0;
  u8 WordColor_ = 0;
  u8 t1[256];
  u8 t2[256];
  rtl_str_assign(Title, 1, S("\000"));
  rtl_str_assign(Options, 50, S("\000"));
  DecodeOperands(2);
  Target = MakeWord(OperandLow[1], OperandHigh[1]);
  Count = OperandValue(2);
  EclPC--;
  DecodeOperands(Count);
  rtl_str_assign(Options, 50, S("\000"));
  if (Count == 1) {
    AcceptEnter = 1;
    HotColor_ = MenuHotColor;
    WordColor_ = MenuHotColor;
    if (rtl_str_cmp(EclStrings[1], S("$PRESS <RETURN> OR BUTTON TO CONTINUE")) == 0) {
      rtl_str_assign(EclStrings[1], 255, S("\"PRESS <ENTER>/<RETURN> TO CONTINUE"));
    }
  } else {
    AcceptEnter = 0;
    HotColor_ = MenuHotColor;
    WordColor_ = MenuTextColor;
  }
  Animate = (((CloseUpShown != 0)) && ((CloseUpHidden != 0)));
  {
    u8 limit = (s16)(Count - 1);
    if (1 <= limit) {
      I = 1;
      for (;;) {
          rtl_str_assign(Options, 50, rtl_str_cat(t1, 4, (const u8 *const[]){Options, S("\001~"), EclStrings[I], S("\001 ")}));
        if (I == limit) break;
        I++;
      }
    }
  }
  rtl_str_assign(Options, 50, rtl_str_cat(t2, 3, (const u8 *const[]){Options, S("\001~"), EclStrings[Count]}));
  Choice = AskMenu(Title, Options, MenuTitleColor, WordColor_, HotColor_, AcceptEnter, Animate);
  WriteVmWord(Target, Choice);
  ClearRect(PromptLeftCol_OVL03, BottomRow, PromptLastCol, BottomRow);
}

/* ovl03:125D. ECL command 28 (dispatcher ovl03:2F2D, CurrentOpcode $1C): clears the encounter. It has no
     operands and moves EclPC past the command. The members ECL command 11 added are dropped
     (EncounterMemberCount and EncounterMembersAdded go to 0), the icon slot EncounterIconSlot goes back to FirstEncounterIcon,
     PooledMoney is cleared, and the item list PooledItems is freed line by line (SizeOf(TMenuLine) bytes each). */
void ClearEncounterCommand(void)
{
  POOL_TRACE("ClearEncounterCommand");
  PMenuLine Next = 0;
  u16 Unused = 0;
  EclPC++;
  EncounterMemberCount = 0;
  EncounterMembersAdded = 0;
  EncounterIconSlot = FirstEncounterIcon;
  rtl_FillChar((void *)&PooledMoney, 28, 0);
  while (PooledItems != 0) {
    Next = (*FPD(TMenuLine (*), PooledItems)).Next;
    rtl_freemem(PooledItems, 63);
    PooledItems = Next;
  }
}

/* ovl03:12C6. ECL command 29 (dispatcher ovl03:2F2D, CurrentOpcode $1D): stores in operand 1 one byte
     computed over the whole party, the list PartyListHead followed through TCharacter.Next (+$104). For each
     member it reads the current hit points (HpCurrent, +$11B), ArmourClassValue (+$111), HitAdjust (+$110) and
     the class levels 0 and 5 (ClassLevels, +$96 and +$9B). ArmourClassValue is lowered by ResistThreshold and
     HitAdjust by HitAdjustThreshold (0 when they are not above it). The member's share is
     HitPoints + 5 * ArmourClassValue + 5 * HitAdjust + 8 * ClassLevel5 + 4 * ClassLevel0, divided by 10; the low
     byte of that quotient is added to the byte, which WriteVmWord stores at operand 1. Purpose unknown:
     what the script does with the value. */
void ComputePartyValueCommand(void)
{
  POOL_TRACE("ComputePartyValueCommand");
  u8 HitPoints = 0;
  u8 HitAdjust = 0;
  u8 ClassLevel5 = 0;
  u8 ClassLevel0 = 0;
  u8 ArmourClassValue = 0;
  u8 Checksum = 0;
  u16 Target = 0;
  PCharacter Member = 0;
  DecodeOperands(1);
  Checksum = 0;
  Member = PartyListHead;
  while (Member != 0) {
    HitPoints = (*FPD(TCharacter (*), Member)).HpCurrent;
    ArmourClassValue = (*FPD(TCharacter (*), Member)).ArmourClassValue;
    HitAdjust = (*FPD(TCharacter (*), Member)).HitAdjust;
    ClassLevel5 = (*FPD(TCharacter (*), Member)).ClassLevels[5];
    ClassLevel0 = (*FPD(TCharacter (*), Member)).ClassLevels[0];
    if (ArmourClassValue > ResistThreshold) {
      ArmourClassValue = ArmourClassValue - ResistThreshold;
    } else {
      ArmourClassValue = 0;
    }
    if (HitAdjust > HitAdjustThreshold) {
      HitAdjust = HitAdjust - HitAdjustThreshold;
    } else {
      HitAdjust = 0;
    }
    Checksum += (((s16)((((HitPoints + (5 * ArmourClassValue)) + (5 * HitAdjust)) + (8 * ClassLevel5)) + (4 * ClassLevel0))) / 10);
    Member = (*FPD(TCharacter (*), Member)).Next;
  }
  Target = MakeWord(OperandLow[1], OperandHigh[1]);
  WriteVmWord(Target, Checksum);
}

typedef struct Frame_ScanPartyCommand {
  u16 StatAddress;
  u16 Sum;
  u8 AffectId;
  PCharacter Member;
  s8 Found;
  farptr Affect;
  u8 Stats[3];
  u16 MinAddr;
  u16 MaxAddr;
  u16 AverageAddr;
  u16 FoundAddr;
  u8 I;
} Frame_ScanPartyCommand;

/* ovl03:13D7. Writes the four results of the scan to the script addresses of operands 3 to 6. It
       reaches the parent's locals through the static link (push bp; push cs; call). */
static void ScanPartyCommand_WriteScanResults(struct Frame_ScanPartyCommand *up)
{
  WriteVmWord(up->MinAddr, up->Stats[0]);
  WriteVmWord(up->MaxAddr, up->Stats[1]);
  WriteVmWord(up->AverageAddr, up->Stats[2]);
  WriteVmWord(up->FoundAddr, up->Found);
}

/* ovl03:1435. ECL command 30 (dispatcher ovl03:2F2D, CurrentOpcode $1E): scans the party (PartyListHead
     followed through TCharacter.Next) and writes the answer to the script
     addresses of operands 3 to 6. Operand 1 chooses what is scanned. 0 is an affect search: operand 2
     is the affect id, HasAffect looks for it in each member's affect list, and operand 6 gets 1 when
     a member has it (the other three values are then 0). The script address $6BA7 is the thief skill 3
     of each member (TCharacter.ThiefSkills[3]) and $6C1B their movement (TCharacter.Movement): operand 3
     gets the lowest value of the party, operand 4 the highest, operand 5 the average (rounded down) and
     operand 6 gets 0. Any other operand 1 writes nothing. A type 1 operand 1 is the script address
     itself, not the word it names (OperandValue would read that word). QUIRK ovl03:1435: an empty party
     divides by zero in the two stat scans. The write-back is the nested routine WriteScanResults (the
     script addresses and the four values are its parent's locals). */
void ScanPartyCommand(void)
{
  POOL_TRACE("ScanPartyCommand");
  Frame_ScanPartyCommand fr;
  memset(&fr, 0, sizeof fr);
  DecodeOperands(6);
  fr.Member = PartyListHead;
  fr.Found = 0;
  if (OperandType[1] == 1) {
    fr.StatAddress = MakeWord(OperandLow[1], OperandHigh[1]);
  } else {
    fr.StatAddress = OperandValue(1);
  }
  fr.AffectId = OperandValue(2);
  fr.MinAddr = MakeWord(OperandLow[3], OperandHigh[3]);
  fr.MaxAddr = MakeWord(OperandLow[4], OperandHigh[4]);
  fr.AverageAddr = MakeWord(OperandLow[5], OperandHigh[5]);
  fr.FoundAddr = MakeWord(OperandLow[6], OperandHigh[6]);
  fr.Sum = 0;
  fr.I = 0;
  fr.Stats[0] = ScanPartyCommand_StatMinStart;
  fr.Stats[1] = 0;
  switch (fr.StatAddress) {
  case 0:
  {
    while (((fr.Member != 0)) && ((fr.Found == 0))) {
      fr.Found = HasAffect(fr.Member, fr.AffectId, &fr.Affect);
      fr.Member = (*FPD(TCharacter (*), fr.Member)).Next;
    }
    {
      if (1 <= 3) {
        fr.I = 1;
        for (;;) {
            fr.Stats[fr.I - 1] = 0;
          if (fr.I == 3) break;
          fr.I++;
        }
      }
    }
    ScanPartyCommand_WriteScanResults(&fr);
    break;
  }
  case ScanPartyCommand_StatThiefSkill3:
  {
    while (fr.Member != 0) {
      fr.I++;
      if ((*FPD(TCharacter (*), fr.Member)).ThiefSkills[2] < fr.Stats[0]) {
        fr.Stats[0] = (*FPD(TCharacter (*), fr.Member)).ThiefSkills[2];
      }
      if ((*FPD(TCharacter (*), fr.Member)).ThiefSkills[2] > fr.Stats[1]) {
        fr.Stats[1] = (*FPD(TCharacter (*), fr.Member)).ThiefSkills[2];
      }
      fr.Sum += (*FPD(TCharacter (*), fr.Member)).ThiefSkills[2];
      fr.Member = (*FPD(TCharacter (*), fr.Member)).Next;
    }
    fr.Stats[2] = (fr.Sum / fr.I);
    ScanPartyCommand_WriteScanResults(&fr);
    break;
  }
  case ScanPartyCommand_StatMovement:
  {
    while (fr.Member != 0) {
      fr.I++;
      if ((*FPD(TCharacter (*), fr.Member)).Movement < fr.Stats[0]) {
        fr.Stats[0] = (*FPD(TCharacter (*), fr.Member)).Movement;
      }
      if ((*FPD(TCharacter (*), fr.Member)).Movement > fr.Stats[1]) {
        fr.Stats[1] = (*FPD(TCharacter (*), fr.Member)).Movement;
      }
      fr.Sum += (*FPD(TCharacter (*), fr.Member)).Movement;
      fr.Member = (*FPD(TCharacter (*), fr.Member)).Next;
    }
    fr.Stats[2] = (fr.Sum / fr.I);
    ScanPartyCommand_WriteScanResults(&fr);
    break;
  }
  }
}

/* ovl03:1629. ECL command 34 (dispatcher ovl03:2F2D, CurrentOpcode $22): reports whether a party member
     has the class mask 4 or 10. It walks the party list PartyListHead (through TCharacter.Next) and tests the
     ClassCombo (+$2F) of each member: a member with 4 or 10 sets the flag. Operand 1 receives the flag (1
     or 0) and operand 2 the second value, which the original always writes as 0 (QUIRK ovl03:1629: the
     Mark byte is set with the flag and never read). Mask 10 is one of the multi-class values AwardExperience
     halves (ovl05:0355); mask 4 is not named yet. */
void CheckPartyHasRangerCommand(void)
{
  POOL_TRACE("CheckPartyHasRangerCommand");
  PCharacter Member = 0;
  u8 Found = 0;
  u8 Second = 0;
  u8 Mark = 0;
  u16 Target = 0;
  u16 SecondTarget = 0;
  u8 Unused = 0;
  DecodeOperands(2);
  Member = PartyListHead;
  Found = 0;
  Second = 0;
  Mark = 0;
  while (Member != 0) {
    if ((((*FPD(TCharacter (*), Member)).ClassCombo == 4)) || (((*FPD(TCharacter (*), Member)).ClassCombo == 10))) {
      Found = 1;
      Mark = 1;
    }
    Member = (*FPD(TCharacter (*), Member)).Next;
  }
  Target = MakeWord(OperandLow[1], OperandHigh[1]);
  SecondTarget = MakeWord(OperandLow[2], OperandHigh[2]);
  WriteVmWord(Target, Found);
  WriteVmWord(SecondTarget, Second);
}

/* ovl03:16C9. ECL command 35 (dispatcher ovl03:2F2D, CurrentOpcode $23): rolls two six-sided dice and
     writes an outcome, 0 to 2, to the script address $6DCB (word 715 of GameVars2, which RunCombat clears
     every round, VarSurpriseSides in ovl08). Operands 1 to 4 are four values. Width is operand 4 + 2 -
     operand 1 and Height is operand 2 + 2 - operand 3 (signed bytes). The first roll must not exceed
     Width and the second must be above Height for outcome 1; a second roll at most Height gives outcome
     2 whatever the first roll did; otherwise the outcome is 0. Purpose unknown: what the script does with
     the outcome. QUIRK ovl03:175F: the value 3 is set when the first roll fits and the second is at most
     Height, but the test that follows overwrites it with 2 (ovl03:1769), so 3 is never written. */
void RollSurpriseCommand(void)
{
  POOL_TRACE("RollSurpriseCommand");
  u8 RollA = 0;
  u8 RollB = 0;
  u8 I = 0;
  u8 Kind = 0;
  u8 Values[4] = {0};
  s8 Width = 0;
  s8 Height = 0;
  DecodeOperands(4);
  Kind = 0;
  {
    if (1 <= 4) {
      I = 1;
      for (;;) {
          Values[I - 1] = OperandValue(I);
        if (I == 4) break;
        I++;
      }
    }
  }
  Width = (Values[3] + 2) - Values[0];
  Height = (Values[1] + 2) - Values[2];
  RollA = RollDice(1, 6);
  RollB = RollDice(1, 6);
  if (RollA <= Width) {
    if (RollB <= Height) {
      Kind = 3;
    } else {
      Kind = 1;
    }
  }
  if (RollB <= Height) {
    Kind = 2;
  }
  WriteVmWord(RollSurpriseCommand_SurpriseWordAddr, Kind);
}

/* ovl03:179B. ECL command 36 (dispatcher ovl03:2F2D, CurrentOpcode $24): the area logic. ShopMain
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
     screen (RedrawView). */
void RunAreaEventCommand(void)
{
  POOL_TRACE("RunAreaEventCommand");
  u16 Steps = 0;
  EclPC++;
  if (((EncounterMembersAdded == 0)) && ((DuelMode == 0))) {
    if ((*FPD(TGameVars (*), GameVars2))[876] == 1) {
      (*FPD(TGameVars (*), GameVars2))[876] = 0;
      ShopMain();
    } else if ((*FPD(TGameVars (*), GameVars2))[738] == 1) {
      (*FPD(TGameVars (*), GameVars2))[738] = 0;
      VisitTemple();
    } else {
      EndBattle();
    }
  } else {
    Steps = OpenStepsAhead(PartyMapColumn, PartyMapRow, PartyFacing);
    if (Steps < (*FPD(TGameVars (*), GameVars2))[705]) {
      (*FPD(TGameVars (*), GameVars2))[705] = Steps;
    }
    RunCombat();
    EndBattle();
    if ((*FPD(TGameVars (*), GameVars))[230] == 0) {
      Load24x24Set(S("\006BACPAC"), 0, 40);
      LoadPictureSlot(S("\004ICON"), 0, 9);
      LoadPictureSlot(S("\004ICON"), 1, 10);
      LoadPictureSlot(S("\004ICON"), 2, 11);
    }
    if (DuelMode != 0) {
      DuelMode = 0;
    }
  }
  if (AreaViewKind == 1) {
    ViewMode = ViewModeWall;
  } else {
    ViewMode = ViewModeMap;
  }
  (*FPD(TGameVars (*), GameVars2))[714] = ((*FPD(TGameVars (*), GameVars2))[714] & 1);
  rtl_FillChar((void *)&PictureShownFlags, 2, 0);
  CloseUpShown = 0;
  RedrawView();
}

/* ovl03:18F8. ECL commands 37 and 38 (dispatcher ovl03:2F2D, CurrentOpcode OpChooseAddress or 38):
     choose one of the script addresses that follow the command. Operand 1 is the choice and operand 2
     the number of addresses; a second DecodeOperands reads them, so operand I+1 is the address for choice
     I. Nothing is chosen when the choice is not below the count. Command 37 stores the chosen address in
     EclPC (its readers are not traced yet), command 38 runs it as a subroutine (ScriptGosub). EclPC goes
     down by one on every call, before the choice is made. */
void SelectCaseCommand(void)
{
  POOL_TRACE("SelectCaseCommand");
  u8 Choice = 0;
  u8 Count = 0;
  u8 Unused = 0;
  u8 I = 0;
  u8 Taken = 0;
  u8 Unused2 = 0;
  Taken = 0;
  DecodeOperands(2);
  Choice = OperandValue(1);
  Count = OperandValue(2);
  EclPC--;
  DecodeOperands(Count);
  I = 0;
  while (((I < Count)) && (!Taken)) {
    if (Choice == I) {
      if (CurrentOpcode == OpChooseAddress) {
        EclPC = MakeWord(OperandLow[(s16)(I + 1)], OperandHigh[(s16)(I + 1)]);
      } else {
        ScriptGosub((s16)(I + 1));
      }
      Taken = 1;
    } else {
      I++;
    }
  }
}

/* ovl03:19B0. ECL command 39 (dispatcher ovl03:2F2D, CurrentOpcode $27): adds loot to the loot list PooledItems
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
     gives 'E'. */
void AddLootCommand(void)
{
  POOL_TRACE("AddLootCommand");
  s8 Index = 0;
  u8 Kind = 0;
  u8 Treasure = 0;
  u8 Unused[23] = {0};
  TMenuLine Item = {0};
  PMenuLine Entry = 0;
  PMenuLine Node = 0;
  u8 Pick = 0;
  u8 Chance = 0;
  u8 Roll2 = 0;
  u8 Code = 0;
  u16 Offset = 0;
  u16 Size = 0;
  u8 TileSetText[2] = {0};
  farptr Block = 0;
  u8 t1[6];
  DecodeOperands(8);
  {
    if (0 <= 6) {
      Index = 0;
      for (;;) {
          PooledMoney[Index] = OperandValue((s16)(Index + 1));
        if (Index == 6) break;
        Index++;
      }
    }
  }
  Kind = OperandValue(8);
  if (Kind < TreasureTableBase) {
    rtl_str_int(TileSetText, 1, TileSet, 0);
    LoadDaxBlock(rtl_str_cat(t1, 2, (const u8 *const[]){S("\004ITEM"), TileSetText}), S("\004.dax"), Kind, &Size, &Block);
    if (Size == 0) {
      ShowMessageLine(ItemErrorColor, S("\030Unable to find item file"));
      QuitGame();
    }
    Offset = 0;
    do {
      rtl_Move((void *)&(*FPD(TByteArray (*), Block))[Offset], (void *)&Item, 63);
      Item.Next = 0;
      Offset += 63;
      if (PooledItems == 0) {
        PooledItems = rtl_getmem(63);
        (*FPD(TMenuLine (*), PooledItems)) = Item;
      } else {
        Entry = PooledItems;
        PooledItems = rtl_getmem(63);
        (*FPD(TMenuLine (*), PooledItems)) = Item;
        (*FPD(TMenuLine (*), PooledItems)).Next = Entry;
      }
    } while (!(Offset >= Size));
    rtl_freemem(Block, Size);
  } else if (Kind != NoTreasure) {
    Index = Kind - TreasureTableBase;
    {
      u8 limit = Index;
      if (1 <= limit) {
        Treasure = 1;
        for (;;) {
            Chance = RollDice(1, 100);
            switch (Chance) {
            case 1:
            case 2:
            case 3:
            case 4:
            case 5:
            case 6:
            case 7:
            case 8:
            case 9:
            case 10:
            case 11:
            case 12:
            case 13:
            case 14:
            case 15:
            case 16:
            case 17:
            case 18:
            case 19:
            case 20:
            case 21:
            case 22:
            case 23:
            case 24:
            case 25:
            case 26:
            case 27:
            case 28:
            case 29:
            case 30:
            case 31:
            case 32:
            case 33:
            case 34:
            case 35:
            case 36:
            case 37:
            case 38:
            case 39:
            case 40:
            case 41:
            case 42:
            case 43:
            case 44:
            case 45:
            case 46:
            case 47:
            case 48:
            case 49:
            case 50:
            case 51:
            case 52:
            case 53:
            case 54:
            case 55:
            case 56:
            case 57:
            case 58:
            case 59:
            case 60:
            {
              Roll2 = RollDice(1, 100);
              switch (Roll2) {
              case 1:
              case 2:
              case 3:
              case 4:
              case 5:
              case 6:
              case 7:
              case 8:
              case 9:
              case 10:
              case 11:
              case 12:
              case 13:
              case 14:
              case 15:
              case 16:
              case 17:
              case 18:
              case 19:
              case 20:
              case 21:
              case 22:
              case 23:
              case 24:
              case 25:
              case 26:
              case 27:
              case 28:
              case 29:
              case 30:
              case 31:
              case 32:
              case 33:
              case 34:
              case 35:
              case 36:
              case 37:
              case 38:
              case 39:
              case 40:
              case 41:
              case 42:
              case 43:
              case 44:
              case 45:
              case 46:
              case 47:
              case 50:
              case 51:
              case 52:
              case 53:
              case 54:
              case 55:
              case 56:
              case 57:
              case 58:
              case 59:
              {
                if (Roll2 == 45) {
                  Code = ';';
                } else {
                  Code = (u8)Roll2;
                }
                break;
              }
              case 60:
              case 61:
              case 62:
              case 63:
              case 64:
              case 65:
              case 66:
              case 67:
              case 68:
              case 69:
              case 70:
              case 71:
              case 72:
              case 73:
              case 74:
              case 75:
              case 76:
              case 77:
              case 78:
              case 79:
              case 80:
              case 81:
              case 82:
              case 83:
              case 84:
              case 85:
              case 86:
              case 87:
              case 88:
              case 89:
              case 90:
              {
                Roll2 = RollDice(1, 10);
                switch (Roll2) {
                case 1:
                case 2:
                case 3:
                case 4:
                {
                  Code = '$';
                  break;
                }
                case 5:
                case 6:
                case 7:
                {
                  Code = '#';
                  break;
                }
                case 8:
                {
                  Code = '"';
                  break;
                }
                case 9:
                {
                  Code = '%';
                  break;
                }
                case 10:
                {
                  Code = '&';
                  break;
                }
                }
                break;
              }
              case 91:
              case 92:
              case 93:
              case 94:
              {
                Code = 'I';
                break;
              }
              case 95:
              case 96:
              case 97:
              {
                Code = ']';
                break;
              }
              case 98:
              case 99:
              case 100:
              {
                Code = 'M';
                break;
              }
              }
              break;
            }
            case 61:
            case 62:
            case 63:
            case 64:
            case 65:
            case 66:
            case 67:
            case 68:
            case 69:
            case 70:
            case 71:
            case 72:
            case 73:
            case 74:
            case 75:
            case 76:
            case 77:
            case 78:
            case 79:
            case 80:
            case 81:
            case 82:
            case 83:
            case 84:
            case 85:
            {
              Code = '=';
              break;
            }
            case 86:
            case 87:
            case 88:
            case 89:
            case 90:
            case 91:
            case 92:
            {
              Code = '>';
              break;
            }
            case 93:
            case 94:
            case 95:
            case 96:
            case 97:
            case 98:
            {
              Pick = RollDice(1, 16);
              switch (Pick) {
              case 1:
              case 2:
              case 3:
              case 4:
              case 5:
              case 6:
              case 7:
              {
                Code = 'G';
                break;
              }
              case 8:
              case 9:
              {
                Code = 'F';
                break;
              }
              case 10:
              {
                Code = 'T';
                break;
              }
              case 11:
              case 12:
              {
                Code = 'N';
                break;
              }
              case 13:
              case 14:
              {
                Code = 'O';
                break;
              }
              case 15:
              {
                Code = '\\';
                break;
              }
              case 16:
              {
                Code = 'C';
                break;
              }
              }
              break;
            }
            case 99:
            case 100:
            {
              Code = 'E';
              break;
            }
            }
            BuildTreasureItem(Code, &Item);
            if (PooledItems == 0) {
              PooledItems = rtl_getmem(63);
              (*FPD(TMenuLine (*), PooledItems)) = Item;
              (*FPD(TMenuLine (*), PooledItems)).Next = 0;
            } else {
              Entry = PooledItems;
              PooledItems = rtl_getmem(63);
              (*FPD(TMenuLine (*), PooledItems)) = Item;
              (*FPD(TMenuLine (*), PooledItems)).Next = Entry;
            }
          if (Treasure == limit) break;
          Treasure++;
        }
      }
    }
    Node = PooledItems;
    while (Node != 0) {
      FormatItemLine((s32)SelectedCharacter, Node, 0, 0, 0, 0);
      Node = (*FPD(TMenuLine (*), Node)).Next;
    }
  }
}

/* ovl03:1DB1. ECL command 40 (dispatcher ovl03:2F2D, CurrentOpcode $28): takes a share of the money and
     the items. Operand 1 is Mode: 0 takes it from the selected character only, any other value from every
     member of the party (the list PartyListHead, followed through TCharacter.Next, +$104). Operand 2 is the
     percentage Percent: each member's money is scaled by (100 - Percent) / 100 (ScaleMoney), and each item
     is lost on a d100 roll at most Percent (LoseItems). Operand 2 is read a second time for the chance, the
     same value unless the operand is a variable that changed. Operand 3 is decoded and not read. */
void LoseMoneyAndItemsCommand(void)
{
  POOL_TRACE("LoseMoneyAndItemsCommand");
  u8 Mode = 0;
  u8 Percent = 0;
  u8 Chance = 0;
  PCharacter Member = 0;
  PItem Items = 0;
  double Factor = 0;
  u8 Unused = 0;
  DecodeOperands(3);
  Mode = OperandValue(1);
  Percent = OperandValue(2);
  Factor = ((double)((s16)(100 - Percent)) / (double)100);
  Chance = OperandValue(2);
  if (Mode == 0) {
    ScaleMoney(Factor, SelectedCharacter);
    LoseItems(Chance, SelectedCharacter);
  } else {
    Member = PartyListHead;
    while (Member != 0) {
      Items = (*FPD(TCharacter (*), Member)).Items;
      ScaleMoney(Factor, Member);
      LoseItems(Chance, Member);
      Member = (*FPD(TCharacter (*), Member)).Next;
    }
  }
}

/* ovl03:1EF8. ECL command 41 (dispatcher ovl03:2F2D, opcode 41): the encounter action menu.
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
     QUIRK ovl03:210A: steps ahead other than 0, 1 or 2 leave the prompt (Lines[0]) unset. */
void EncounterActionCommand(void)
{
  POOL_TRACE("EncounterActionCommand");
  u8 Choice = 0;
  u8 ChoiceKinds[5] = {0};
  u8 Lines[4][256] = {0};
  u8 FleeMovement = 0;
  u8 MonsterMovement = 0;
  u8 I = 0;
  u8 Fastest = 0;
  u8 Slowest = 0;
  u8 MenuAgain = 0;
  u8 ClearWindow = 0;
  u8 Animate = 0;
  u8 Options[41] = {0};
  u8 Title[2] = {0};
  u8 ChoiceKind = 0;
  u8 Line = 0;
  u16 ResultAddr = 0;
  SkipCloseUpIfNoPics = 1;
  EclWindowCleared = 0;
  DelayPerGlyph = 1;
  MovementRange(&Fastest, &Slowest);
  rtl_str_assign(Title, 1, S("\000"));
  DecodeOperands(14);
  EncounterSpriteBank = OperandValue(1);
  (*FPD(TGameVars (*), GameVars2))[704] = OperandValue(2);
  EncounterPicBank = OperandValue(3);
  ResultAddr = MakeWord(OperandLow[4], OperandHigh[4]);
  {
    if (0 <= 4) {
      I = 0;
      for (;;) {
          ChoiceKinds[I] = OperandValue((s16)(I + 5));
        if (I == 4) break;
        I++;
      }
    }
  }
  {
    if (1 <= 3) {
      I = 1;
      for (;;) {
          rtl_str_assign(Lines[I], 255, EclStrings[I]);
        if (I == 3) break;
        I++;
      }
    }
  }
  FleeMovement = OperandValue(13);
  MonsterMovement = OperandValue(14);
  (*FPD(TGameVars (*), GameVars2))[705] = OpenStepsAhead(PartyMapColumn, PartyMapRow, PartyFacing);
  if ((*FPD(TGameVars (*), GameVars2))[704] < (*FPD(TGameVars (*), GameVars2))[705]) {
    (*FPD(TGameVars (*), GameVars2))[705] = (*FPD(TGameVars (*), GameVars2))[704];
  }
  ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank, (u8)(*FPD(TGameVars (*), GameVars2))[705], &PictureShown);
  do {
    Animate = (((CloseUpShown != 0)) && ((CloseUpHidden != 0)));
    ClearWindow = 1;
    MenuAgain = 0;
    GlyphCol = EclTextLeft;
    GlyphRow = EclTextTop;
    switch ((*FPD(TGameVars (*), GameVars2))[705]) {
    case 0:
    {
      Line = 1;
      do {
        rtl_str_assign(Lines[0], 255, Lines[Line]);
        Line++;
      } while (!(((Lines[0][0] != 0)) || ((Line > 3))));
      break;
    }
    case 1:
    {
      Line = 2;
      do {
        rtl_str_assign(Lines[0], 255, Lines[Line]);
        Line++;
        if (Line > 3) {
          Line = 1;
        }
      } while (!(((Lines[0][0] != 0)) || ((Line == 2))));
      break;
    }
    case 2:
    {
      Line = 3;
      do {
        rtl_str_assign(Lines[0], 255, Lines[Line]);
        Line++;
        if (Line > 3) {
          Line = 1;
        }
      } while (!(((Lines[0][0] != 0)) || ((Line == 3))));
      break;
    }
    }
    if (Lines[0][0] == 0) {
      ClearWindow = 0;
    }
    ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, ClearWindow, Lines[0]);
    /* PARLAY is tested first so its literal is emitted before ADVANCE (pool at ovl03:1E9B). */
    if ((((*FPD(TGameVars (*), GameVars2))[705] == 0)) || (((*FPD(TGameVars (*), GameVars))[230] == 0))) {
      rtl_str_assign(Options, 40, S("\033~COMBAT ~WAIT ~FLEE ~PARLAY"));
    } else {
      rtl_str_assign(Options, 40, S("\034~COMBAT ~WAIT ~FLEE ~ADVANCE"));
    }
    Choice = AskMenu(Title, Options, MenuTitleColor, MenuTextColor, MenuHotColor, 0, Animate);
    if ((((*FPD(TGameVars (*), GameVars2))[705] == 0)) || (((*FPD(TGameVars (*), GameVars))[230] == 0))) {
      if (Choice == AdvanceChoice) {
        Choice = ParlayChoice;
      }
    }
    ChoiceKind = ChoiceKinds[Choice];
    switch (ChoiceKind) {
    case 0:
    {
      if (Choice != FleeChoice) {
        WriteVmWord(ResultAddr, FightResult);
      } else if (Slowest >= FleeMovement) {
        WriteVmWord(ResultAddr, PartyFleesResult);
      } else {
        WriteVmWord(ResultAddr, FightResult);
      }
      break;
    }
    case 1:
    {
      switch (Choice) {
      case CombatChoice:
      {
        WriteVmWord(ResultAddr, FightResult);
        break;
      }
      case WaitChoice:
      {
        MenuAgain = 1;
        ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1, S("\020Both sides wait."));
        break;
      }
      case FleeChoice:
      {
        WriteVmWord(ResultAddr, PartyFleesResult);
        break;
      }
      case AdvanceChoice:
      {
        if ((*FPD(TGameVars (*), GameVars2))[705] != 0) {
          (*FPD(TGameVars (*), GameVars2))[705]--;
          ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank, (u8)(*FPD(TGameVars (*), GameVars2))[705], &PictureShown);
        } else {
          ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1, S("\020Both sides wait."));
        }
        MenuAgain = 1;
        break;
      }
      case ParlayChoice:
      {
        if ((*FPD(TGameVars (*), GameVars2))[705] <= 0) {
          WriteVmWord(ResultAddr, ParlayResult);
        } else {
          (*FPD(TGameVars (*), GameVars2))[705]--;
          ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank, (u8)(*FPD(TGameVars (*), GameVars2))[705], &PictureShown);
          MenuAgain = 1;
        }
        break;
      }
      }
      break;
    }
    case 2:
    {
      switch (Choice) {
      case CombatChoice:
      {
        if (MonsterMovement > Fastest) {
          WriteVmWord(ResultAddr, MonstersFleeResult);
          GlyphCol = EclTextLeft;
          GlyphRow = EclTextTop;
          ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1, S("\022The monsters flee."));
        } else {
          WriteVmWord(ResultAddr, FightResult);
        }
        break;
      }
      case 1:
      case 2:
      case 3:
      case 4:
      {
        WriteVmWord(ResultAddr, MonstersFleeResult);
        GlyphCol = EclTextLeft;
        GlyphRow = EclTextTop;
        ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1, S("\022The monsters flee."));
        break;
      }
      }
      break;
    }
    case 3:
    {
      switch (Choice) {
      case CombatChoice:
      {
        WriteVmWord(ResultAddr, FightResult);
        break;
      }
      case WaitChoice:
      case AdvanceChoice:
      {
        if ((*FPD(TGameVars (*), GameVars2))[705] != 0) {
          (*FPD(TGameVars (*), GameVars2))[705]--;
          ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank, (u8)(*FPD(TGameVars (*), GameVars2))[705], &PictureShown);
        } else {
          ShowPagedText(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom, EclTextColor, 1, S("\020Both sides wait."));
        }
        MenuAgain = 1;
        break;
      }
      case FleeChoice:
      {
        WriteVmWord(ResultAddr, PartyFleesResult);
        break;
      }
      case ParlayChoice:
      {
        if ((*FPD(TGameVars (*), GameVars2))[705] <= 0) {
          WriteVmWord(ResultAddr, ParlayResult);
        } else {
          (*FPD(TGameVars (*), GameVars2))[705]--;
          ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank, (u8)(*FPD(TGameVars (*), GameVars2))[705], &PictureShown);
          MenuAgain = 1;
        }
        break;
      }
      }
      break;
    }
    case 4:
    {
      switch (Choice) {
      case CombatChoice:
      {
        WriteVmWord(ResultAddr, FightResult);
        break;
      }
      case WaitChoice:
      case AdvanceChoice:
      case ParlayChoice:
      {
        if ((*FPD(TGameVars (*), GameVars2))[705] <= 0) {
          WriteVmWord(ResultAddr, ParlayResult);
        } else {
          (*FPD(TGameVars (*), GameVars2))[705]--;
          ShowEncounterPicture(EncounterSpriteBank, EncounterPicBank, (u8)(*FPD(TGameVars (*), GameVars2))[705], &PictureShown);
          MenuAgain = 1;
        }
        break;
      }
      case FleeChoice:
      {
        WriteVmWord(ResultAddr, PartyFleesResult);
        break;
      }
      }
      break;
    }
    }
  } while (!(MenuAgain == 0));
  ClearRect(PromptLeftCol_OVL03, BottomRow, PromptLastCol, BottomRow);
  DelayPerGlyph = 0;
  SkipCloseUpIfNoPics = 0;
}

/* ovl03:25CB. ECL command 44 (dispatcher ovl03:2F2D, CurrentOpcode 2Ch): asks the player for an attitude.
     The menu offers AttitudeMenu's words (HAUGHTY, SLY, NICE, MEEK and ABUSIVE) under a blank title. Operands
     1 to 5 are the value of each attitude in that order, and the value of the one the player picks is written
     with WriteVmWord to the script address operand 6 names. Purpose unknown: what the script does with the
     value (not traced yet). */
void ChooseAttitudeCommand(void)
{
  POOL_TRACE("ChooseAttitudeCommand");
  u8 Choice = 0;
  u8 Value = 0;
  u8 I = 0;
  u8 Values[5] = {0};
  u16 Target = 0;
  u8 BlankTitle = 0;
  u8 t1[2];
  DecodeOperands(6);
  BlankTitle = ' ';
  {
    if (0 <= 4) {
      I = 0;
      for (;;) {
          Values[I] = OperandValue((s16)(I + 1));
        if (I == 4) break;
        I++;
      }
    }
  }
  Choice = AskMenu(rtl_str_char(t1, BlankTitle), AttitudeMenu, MenuTitleColor, MenuTextColor, MenuHotColor, 0, 0);
  Target = MakeWord(OperandLow[6], OperandHigh[6]);
  Value = Values[Choice];
  WriteVmWord(Target, Value);
}

/* ovl03:266A. ECL command 50 (dispatcher ovl03:2F2D, CurrentOpcode 32h): tests whether a party member carries
     an item of the type operand 1 names. It walks the party list PartyListHead (through TCharacter.Next) and each
     member's carried items (TCharacter.Items, +$C8; TMenuLine.Next at +$2A), comparing the ItemType (+$2E) of
     each with the operand, and stops at the first match. CompareFlags[0] (equal) is set and [1] (not equal)
     cleared when one is found, else [1] is set; the conditional commands 22 to 27 (ovl03:0B52) test them.
     Purpose unknown: which item types the script tests. */
void ComparePartyItemCommand(void)
{
  POOL_TRACE("ComparePartyItemCommand");
  u8 ItemType = 0;
  u8 Unused = 0;
  PCharacter Member = 0;
  PItem Item = 0;
  u8 Found = 0;
  DecodeOperands(1);
  Found = 0;
  ItemType = OperandValue(1);
  rtl_FillChar((void *)&CompareFlags, 6, 0);
  CompareFlags[1] = 1;
  Member = PartyListHead;
  while (((Member != 0)) && (!Found)) {
    Item = (*FPD(TCharacter (*), Member)).Items;
    while (((Item != 0)) && (!Found)) {
      if (ItemType == (*FPD(TMenuLine (*), Item)).ItemType) {
        CompareFlags[0] = 1;
        CompareFlags[1] = 0;
        Found = 1;
      }
      Item = (*FPD(TMenuLine (*), Item)).Next;
    }
    Member = (*FPD(TCharacter (*), Member)).Next;
  }
}

/* ovl03:271F. ECL command 58 (dispatcher ovl03:2F2D, CurrentOpcode 3Ah): pauses the script for the game
     speed (DelayByGameSpeed, RES06: GameSpeed * 225 milliseconds). It has no operands; Inc(EclPC) steps the
     program counter past the opcode so RunScriptFrom (ovl03:3171) reads the next command (see EclPC). */
void PauseCommand(void)
{
  POOL_TRACE("PauseCommand");
  EclPC++;
  DelayByGameSpeed();
}

/* ovl03:2775. ECL command 46 (dispatcher ovl03:2F2D, CurrentOpcode 2Eh): damages the party, a trap or an
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
     is shown. Purpose unknown: which events use it. */
void DamagePartyCommand(void)
{
  POOL_TRACE("DamagePartyCommand");
  u8 Flags = 0;
  u8 DamageDice = 0;
  u8 DamageSides = 0;
  u8 I = 0;
  u8 SaveBonus = 0;
  u8 Resistance = 0;
  u8 DamageBonus = 0;
  u8 MemberNumber = 0;
  u8 SaveKind_ = 0;
  u8 Step = 0;
  u16 Damage = 0;
  PCharacter Who = 0;
  PCharacter Member = 0;
  PCharacter SavedCharacter = 0;
  u8 Unused = 0;
  u8 WholePartyHit = 0;
  SavedCharacter = SelectedCharacter;
  Unused = 0;
  WholePartyHit = 0;
  Who = PartyListHead;
  DecodeOperands(5);
  Flags = OperandValue(1);
  DamageDice = OperandValue(2);
  DamageSides = OperandValue(3);
  DamageBonus = OperandValue(4);
  Resistance = OperandValue(5);
  Damage = RollDice(DamageDice, DamageSides) + DamageBonus;
  if (((Flags & TrapWholePartyBit)) != 0) {
    WholePartyHit = 1;
  } else {
    MemberNumber = RollDice(1, (u8)(*FPD(TGameVars (*), GameVars2))[830]);
  }
  if (((Flags & TrapSavingThrowBit)) != 0) {
    SaveBonus = (Flags & TrapBonusMask);
    SaveKind_ = (Resistance & TrapKindMask);
    if (WholePartyHit) {
      while (Who != 0) {
        if (((Flags & TrapUnsavedBit)) != 0) {
          DamageWithMessage(Damage, Who);
        } else if (!SavingThrow(Who, SaveKind_, SaveBonus)) {
          DamageWithMessage(Damage, Who);
        }
        Who = (*FPD(TCharacter (*), Who)).Next;
      }
    } else if (((Resistance & TrapSelectedBit)) != 0) {
      if (((SaveKind_ == 0)) || (!SavingThrow(SelectedCharacter, (s16)(SaveKind_ - 1), SaveBonus))) {
        DamageWithMessage(Damage, SelectedCharacter);
      }
    } else {
      {
        u8 limit = MemberNumber;
        if (2 <= limit) {
          I = 2;
          for (;;) {
              Who = (*FPD(TCharacter (*), Who)).Next;
            if (I == limit) break;
            I++;
          }
        }
      }
      if (!SavingThrow(Who, SaveKind_, SaveBonus)) {
        DamageWithMessage(Damage, Who);
      }
    }
  } else {
    /* QUIRK ovl03:2775: bit 7 clear, so Flags is the number of hits, counted per bit: bit 6 (and bit 5)
       adds to it here, and when bit 6 is set MemberNumber was not rolled above. */
    {
      u8 limit = Flags;
      if (1 <= limit) {
        I = 1;
        for (;;) {
            Who = PartyListHead;
            MemberNumber = RollDice(1, (u8)(*FPD(TGameVars (*), GameVars2))[830]);
            Step = 1;
            while (Step < MemberNumber) {
              Who = (*FPD(TCharacter (*), Who)).Next;
              Step++;
            }
            if (RollBeatsResistance(Who, Resistance)) {
              DamageWithMessage(Damage, Who);
            }
            Damage = RollDice(DamageDice, DamageSides) + DamageBonus;
          if (I == limit) break;
          I++;
        }
      }
    }
  }
  Member = PartyListHead;
  PartyDestroyed = 1;
  while (Member != 0) {
    if ((*FPD(TCharacter (*), Member)).Flag10D != 0) {
      PartyDestroyed = 0;
    }
    Member = (*FPD(TCharacter (*), Member)).Next;
  }
  if (PartyDestroyed != 0) {
    DrawWindow(EndWindowLeft, EndWindowTop, EndWindowRight, EndWindowBottom, 0, EndWindowColor, S("\010The END!"));
    GlyphCol = 2;
    GlyphRow = 2;
    ShowPagedText(EndWindowLeft, EndWindowTop, EndWindowRight, EndWindowBottom, EndTextColor, 1, S("\033The entire party is killed!"));
    rtl_Delay(EndPauseMs);
  }
  SelectedCharacter = SavedCharacter;
  ShowMessageLine(ContinueColor, S("\"press <enter>/<return> to continue"));
}

/* ovl03:2AA2. ECL command 49 (dispatcher ovl03:2F2D, CurrentOpcode 31h): redraws the area view when the 3D
     encounter sprite is loaded (Sprite3DLoaded, set by ShowEncounterPicture), as the hiding path of ShowCloseUpCommand
     does, then clears the sprite flag and the close-up flag CloseUpShown. It has no operands; Inc(EclPC) steps the
     program counter past the opcode so RunScriptFrom (ovl03:3171) reads the next command (see EclPC).
     Purpose unknown: why the script redraws the area. */
void RedrawAreaViewCommand(void)
{
  POOL_TRACE("RedrawAreaViewCommand");
  EclPC++;
  if (Sprite3DLoaded != 0) {
    ShowAreaView();
    Sprite3DLoaded = 0;
    CloseUpShown = 0;
  }
}

/* ovl03:2AC1. ECL command 52 (dispatcher ovl03:2F2D, CurrentOpcode 34h): passes time. Operand 1 is the
     amount, and AdvanceGameClock advances the game clock by that many units of digit 1 (the digit the camp's
     rest, RunRestPeriod in ovl20, advances in steps of 5). QUIRK ovl03:2AC1: Amount is passed to
     OperandValue as the operand number before the routine has set it, so the operand read is whatever
     byte the frame held on entry; the compiled code does exactly this. */
void PassTimeCommand(void)
{
  POOL_TRACE("PassTimeCommand");
  u8 Amount = 0;
  u8 Unused = 0;
  DecodeOperands(1);
  Amount = OperandValue(Amount);
  AdvanceGameClock(Amount, 1);
}

/* ovl03:2AEB. ECL command 51 (dispatcher ovl03:2F2D, CurrentOpcode 33h): starts a new line of text. The
     text cursor (GlyphCol, GlyphRow, the glyph position ShowPagedText keeps) goes to column 1 of the next
     row. GlyphRunPending is cleared when it is set; the cursor moves the same way on both branches, which the
     original compiles as two branches. Inc(EclPC) steps the program counter past the opcode so RunScriptFrom
     (ovl03:3171) reads the next command (see EclPC). */
void NewLineCommand(void)
{
  POOL_TRACE("NewLineCommand");
  EclPC++;
  if (GlyphRunPending != 0) {
    GlyphCol = EclTextLeft;
    GlyphRow++;
    GlyphRunPending = 0;
  } else {
    GlyphCol = EclTextLeft;
    GlyphRow++;
  }
}

/* ovl03:2B14. ECL command 61 (dispatcher ovl03:2F2D, CurrentOpcode 3Dh): clears the picture window, the
     box at columns 1 to 15 and rows 1 to 15 that frames the encounter picture (ShowCloseUpCommand draws
     the close-up inside the box at 3 to 13, and EndCommand draws this box as a frame). Then GlyphRunInBox is set
     (its meaning is not traced; EndCommand clears it). Inc(EclPC) steps the program counter past the opcode
     so RunScriptFrom (ovl03:3171) reads the next command (see EclPC). */
void ClearPictureWindowCommand(void)
{
  POOL_TRACE("ClearPictureWindowCommand");
  EclPC++;
  ClearRect(PictureFrameLeft, PictureFrameTop, PictureFrameRight, PictureFrameBottom);
  GlyphRunInBox = 1;
}

/* ovl03:2B33. ECL command 57 (dispatcher ovl03:2F2D, CurrentOpcode 39h): asks the player to choose a party
     member. The ECL text window (EclTextLeft to EclTextBottom) is cleared, the string operand 1 is copied
     into a local as the prompt, and SelectPartyMember runs with that prompt, mode 0 and SelectedCharacter as
     the var parameter that receives the chosen member. SelectPartyMember is the selection the learning notes
     call SelectPartyMember (res12, matched earlier); its own code is not traced here. Its Who is untyped
     in RES12.PAS, since PCharacter is not visible there (the caller passes the address of SelectedCharacter). */
void ChoosePartyMemberCommand(void)
{
  POOL_TRACE("ChoosePartyMemberCommand");
  u8 Prompt[256] = {0};
  DecodeOperands(1);
  ClearRect(EclTextLeft, EclTextTop, EclTextRight, EclTextBottom);
  rtl_str_assign(Prompt, 255, EclStrings[1]);
  SelectPartyMember(Prompt, 0, &SelectedCharacter);
}

/* ovl03:2B7E. ECL command 54 (dispatcher ovl03:2F2D, CurrentOpcode 36h): adds a computer-run member. Operand
     1 is the kind AddMonsterToParty adds (it rolls the character and calls AddPartyMember, which makes it the
     SelectedCharacter). Operand 2 halved, with the high bit ComputerRun set, is its B84 byte: the low
     seven bits are its morale and the high bit marks it as run by the computer (TCharacter.B84). Its Side is
     1 for OtherSideKind and 0 otherwise. The character is then redrawn (RecalcCombatValues and DrawPartyRoster).
     QUIRK ovl03:2B7E: four bytes of the frame nothing uses. */
void AddComputerMemberCommand(void)
{
  POOL_TRACE("AddComputerMemberCommand");
  s32 Unused = 0;
  u8 Kind = 0;
  u8 Morale = 0;
  DecodeOperands(2);
  Kind = OperandValue(1);
  AddMonsterToParty(Kind);
  Morale = OperandValue(2);
  Morale = (s16)((u16)Morale >> 1);
  Morale = (Morale | ComputerRun);
  (*FPD(TCharacter (*), SelectedCharacter)).B84 = Morale;
  if (Kind != OtherSideKind) {
    (*FPD(TCharacter (*), SelectedCharacter)).Side = 0;
  } else {
    (*FPD(TCharacter (*), SelectedCharacter)).Side = 1;
  }
  RecalcCombatValues(SelectedCharacter);
  DrawPartyRoster(SelectedCharacter);
}

/* ovl03:2C03. ECL command 59 (dispatcher ovl03:2F2D, CurrentOpcode 3Bh): looks for the value of operand 1
     among the memorized spells of the first party member (PartyListHead, TCharacter.Spells). The bytes from Spells[1]
     up are compared with the value one by one, up to slot SpellScanLast + 1 (82). Operand 2 receives the slot found,
     or NoSpellSlot when none in those bytes has it; operand 3 receives Count, the members walked (1 for a party
     with a member, 0 for an empty one). Purpose unknown: what the script does with the two results.
     QUIRK ovl03:2C03: the walk stops after the first member, because the search sets Found both when it finds
     the value and when it runs out of slots. QUIRK ovl03:2C03: Found is tested before the routine sets it, so
     the search runs only when that stack byte is zero. QUIRK ovl03:2C03: the two target addresses are kept as
     bytes (the high byte of each operand address is lost). QUIRK ovl03:2C03: the scan runs past the 21 entries
     of Spells, through the record bytes after them. */
void FindMemorizedSpellCommand(void)
{
  POOL_TRACE("FindMemorizedSpellCommand");
  u8 Value = 0;
  u8 I = 0;
  u8 Count = 0;
  PCharacter Member = 0;
  u8 Found = 0;
  u8 SlotAddr = 0;
  u8 CountAddr = 0;
  DecodeOperands(3);
  Value = OperandValue(1);
  SlotAddr = MakeWord(OperandLow[2], OperandHigh[2]);
  CountAddr = MakeWord(OperandLow[3], OperandHigh[3]);
  I = 1;
  Count = 0;
  Member = PartyListHead;
  while (((Member != 0)) && (!Found)) {
    do {
      if ((*FPD(TCharacter (*), Member)).Spells[I] == Value) {
        Found = 1;
      } else if (I <= SpellScanLast) {
        I++;
      } else {
        I = NoSpellSlot;
        Found = 1;
      }
    } while (!(Found));
    Member = (*FPD(TCharacter (*), Member)).Next;
    Count++;
  }
  WriteVmWord(SlotAddr, I);
  WriteVmWord(CountAddr, Count);
}

/* ovl03:2CCF. ECL command 45 (dispatcher ovl03:2F2D, CurrentOpcode 2Dh): runs the engine action that the
     word of its operand picks (the two bytes of the operand, not its value). The word less CodeBias is
     tested against the Action codes in turn; any other word does nothing. The actions:
     - ActionRedrawArea: PartyCellEventByte takes the event byte of the party's cell (EventByteAt). When AreaRedrawArmed is set
       (ECL commands 33 and 55 set it, 32 clears it) and one of CloseUpShown, Sprite3DLoaded, SpecialViewGate,
       PartyMovedByScript or HeadBodyWritten is
       set, the area view is drawn again (ShowAreaView), DrawLocationLine runs and those five flags are cleared.
     - ActionDuelWithCopy and ActionDuelNoCopy: SetupDuel starts a duel with or without the copy.
     - ActionSound: PlaySound of SoundStep when ScriptSoundCode is 8, of SoundFireball when ScriptSoundCode is 10.
     - ActionStepParty: StepPartyForward moves the party one cell.
     - ActionWallProbe: when AreaViewKind is 1, PartyCellWallId takes the wall id of the party's cell (WallIdAt). */
void EngineActionCommand(void)
{
  POOL_TRACE("EngineActionCommand");
  u16 Code = 0;
  u16 Action = 0;
  DecodeOperands(1);
  Code = MakeWord(OperandLow[1], OperandHigh[1]);
  Action = Code - CodeBias;
  switch (Action) {
  case ActionRedrawArea:
  {
    PartyCellEventByte = EventByteAt(PartyMapColumn, PartyMapRow);
    if (((AreaRedrawArmed != 0)) && (((((((CloseUpShown != 0)) || ((Sprite3DLoaded != 0))) || ((SpecialViewGate != 0))) || ((PartyMovedByScript != 0))) || ((HeadBodyWritten != 0))))) {
      ShowAreaView();
      DrawLocationLine();
      HeadBodyWritten = 0;
      SpecialViewGate = 0;
      PartyMovedByScript = 0;
      CloseUpShown = 0;
      Sprite3DLoaded = 0;
    }
    break;
  }
  case ActionDuelWithCopy:
  {
    SetupDuel(DuelWithCopy);
    break;
  }
  case ActionDuelNoCopy:
  {
    SetupDuel(DuelNoCopy);
    break;
  }
  case ActionSound:
  {
    switch (ScriptSoundCode) {
    case 8:
    {
      PlaySound(SoundStep);
      break;
    }
    case 10:
    {
      PlaySound(SoundFireball);
      break;
    }
    }
    break;
  }
  case ActionStepParty:
  {
    StepPartyForward();
    break;
  }
  case ActionWallProbe:
  {
    if (AreaViewKind == 1) {
      PartyCellWallId = WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
    }
    break;
  }
  }
}

/* ovl03:2DD3. Runs the camp (MakeCamp, OVL15) between two script entries: the script machine runs the
     third entry address, EclPreCampEntry, before the camp (through ovl03:3171, not decompiled yet). When the camp
     leaves EndCamp set, the area view is redrawn (RedrawView) and the fourth entry address, EclCampInterruptedEntry, runs.
     Callers: ECL command 56 with operand 9 (ovl03:2E10) and RunWilderness (ovl03:33E7, the E key of the wilderness
     loop). Then the area view is drawn again
     (ShowAreaView) and HeapErrorStop, the gate of the heap error retry, is cleared. */
void RunCamp(void)
{
  POOL_TRACE("RunCamp");
  u8 EndCamp = 0;
  u8 Unused = 0;
  EndCamp = 0;
  RunScriptFrom(EclPreCampEntry);
  MakeCamp(&EndCamp);
  if (EndCamp != 0) {
    RedrawView();
    RunScriptFrom(EclCampInterruptedEntry);
  }
  ShowAreaView();
  HeapErrorStop = 0;
}

/* ovl03:2E10. ECL command 56 (dispatcher ovl03:2F2D, CurrentOpcode 38h, cmp al,38h at ovl03:3135): shows
     the screen that operand 1 picks. 0 runs RunCharacterMenu (not traced yet) and redraws the view (RedrawView);
     ScreenEnding shows the ending narrative (ShowEndingNarrative, OVL18); ScreenCamp runs the camp (RunCamp),
     keeps the script counter EclPC across it, and then EndCommand (ovl03:0001) runs. A pending selection
     (ReselectCharacterPending, set by ECL command 10) first selects the character at ReselectCharacter, as EndCommand does. */
void ShowSpecialScreenCommand(void)
{
  POOL_TRACE("ShowSpecialScreenCommand");
  u8 Choice = 0;
  u16 SavedCounter = 0;
  u8 Unused = 0;
  if (ReselectCharacterPending != 0) {
    SelectedCharacter = ReselectCharacter;
    ReselectCharacterPending = 0;
  }
  DecodeOperands(1);
  Choice = OperandValue(1);
  switch (Choice) {
  case 0:
  {
    RunCharacterMenu();
    RedrawView();
    break;
  }
  case ScreenEnding:
  {
    ShowEndingNarrative();
    break;
  }
  case ScreenCamp:
  {
    SavedCounter = EclPC;
    RunCamp();
    EclPC = SavedCounter;
    EndCommand();
    break;
  }
  }
}

/* ovl03:2E7D. ECL command 60 (dispatcher ovl03:2F2D, CurrentOpcode 3Ch): draws one line of glyphs at the text
     cursor. Operand 1 is the script address of a run of words: each word's low byte plus 1 is the glyph drawn
     (DrawGlyph, one copy, colour GlyphRunColor) at GlyphCol and GlyphRow, and the cursor moves right after each
     glyph. The run ends at the first word whose low byte is 0 or $FF. When GlyphRunInBox is set (ECL command 61) and the
     cursor is below CloseUpLastRow, the cursor first goes to GlyphRunCol, GlyphRunRow and PictureFrameDirty is set.
     GlyphRunPending
     is set, and the cursor goes down one row at the end. Purpose unknown: what the script writes this way. */
void DrawGlyphRunCommand(void)
{
  POOL_TRACE("DrawGlyphRunCommand");
  u16 Start = 0;
  u16 Address = 0;
  u8 Index = 0;
  u8 Value = 0;
  u8 Done = 0;
  u8 Unused = 0;
  rtl_FillChar((void *)&PictureShownFlags, 2, 0);
  CloseUpShown = 0;
  DecodeOperands(1);
  Start = MakeWord(OperandLow[1], OperandHigh[1]);
  Index = 0;
  Done = 0;
  if (((GlyphRunInBox != 0)) && ((GlyphRow > CloseUpLastRow))) {
    GlyphRow = GlyphRunRow;
    GlyphCol = GlyphRunCol;
    PictureFrameDirty = 1;
  }
  GlyphRunPending = 1;
  do {
    Address = Start + Index;
    Value = ReadVmWord(Address) + 1;
    if (Value > 1) {
      DrawGlyph(GlyphCol, GlyphRow, GlyphRunColor, 1, Value, 0);
      GlyphCol++;
      Index++;
    } else {
      Done = 1;
    }
  } while (!(Done));
  GlyphRow++;
}

/* ovl03:2F2D. The ECL command dispatcher (called by ovl03:3171 for each command the script runs): it runs
     the handler of CurrentOpcode, one case arm per opcode. Each handler decodes its own operands and moves
     EclPC past the command. An opcode without an arm (31, and 62 and above) does nothing. */
void DispatchCommand(void)
{
  POOL_TRACE("DispatchCommand");
  switch (CurrentOpcode) {
  case 0:
  {
    EndCommand();
    break;
  }
  case 1:
  {
    GotoCommand();
    break;
  }
  case 2:
  {
    GosubCommand();
    break;
  }
  case 3:
  {
    CompareCommand();
    break;
  }
  case OpAdd:
  case OpSub:
  case OpDiv:
  case OpMul:
  {
    ArithmeticCommand();
    break;
  }
  case 8:
  {
    RandomCommand();
    break;
  }
  case 9:
  {
    StoreCommand();
    break;
  }
  case 10:
  {
    SelectCharacterCommand();
    break;
  }
  case 11:
  {
    AddEncounterGroupCommand();
    break;
  }
  case 12:
  {
    ShowEncounterCommand();
    break;
  }
  case 13:
  {
    ApproachEncounterCommand();
    break;
  }
  case 14:
  {
    ShowCloseUpCommand();
    break;
  }
  case 15:
  {
    ReadNumberCommand();
    break;
  }
  case 16:
  {
    ReadStringCommand();
    break;
  }
  case 17:
  case 18:
  {
    ShowTextCommand();
    break;
  }
  case 19:
  {
    ReturnCommand();
    break;
  }
  case 20:
  {
    CompareBothPairsCommand();
    break;
  }
  case 21:
  {
    ChooseFromListCommand();
    break;
  }
  case OpIfEqual:
  case OpIfNotEqual:
  case OpIfLess:
  case OpIfGreater:
  case OpIfLessOrEqual:
  case OpIfGreaterOrEqual:
  {
    RunIfCompared();
    break;
  }
  case 28:
  {
    ClearEncounterCommand();
    break;
  }
  case 29:
  {
    ComputePartyValueCommand();
    break;
  }
  case 30:
  {
    ScanPartyCommand();
    break;
  }
  case 32:
  {
    StartEclBlock();
    break;
  }
  case 33:
  case 55:
  {
    LoadAreaGraphics();
    break;
  }
  case 34:
  {
    CheckPartyHasRangerCommand();
    break;
  }
  case 35:
  {
    RollSurpriseCommand();
    break;
  }
  case 36:
  {
    RunAreaEventCommand();
    break;
  }
  case OpChooseAddress:
  case 38:
  {
    SelectCaseCommand();
    break;
  }
  case 39:
  {
    AddLootCommand();
    break;
  }
  case 40:
  {
    LoseMoneyAndItemsCommand();
    break;
  }
  case 41:
  {
    EncounterActionCommand();
    break;
  }
  case 42:
  {
    CopyIndexedWordCommand();
    break;
  }
  case 43:
  {
    AskMenuCommand();
    break;
  }
  case 44:
  {
    ChooseAttitudeCommand();
    break;
  }
  case 45:
  {
    EngineActionCommand();
    break;
  }
  case 46:
  {
    DamagePartyCommand();
    break;
  }
  case OpAnd:
  case OpOr:
  {
    BitwiseCommand();
    break;
  }
  case 49:
  {
    RedrawAreaViewCommand();
    break;
  }
  case 50:
  {
    ComparePartyItemCommand();
    break;
  }
  case 51:
  {
    NewLineCommand();
    break;
  }
  case 52:
  {
    PassTimeCommand();
    break;
  }
  case 53:
  {
    StoreIndexedWordCommand();
    break;
  }
  case 54:
  {
    AddComputerMemberCommand();
    break;
  }
  case 56:
  {
    ShowSpecialScreenCommand();
    break;
  }
  case 57:
  {
    ChoosePartyMemberCommand();
    break;
  }
  case 58:
  {
    PauseCommand();
    break;
  }
  case 59:
  {
    FindMemorizedSpellCommand();
    break;
  }
  case 60:
  {
    DrawGlyphRunCommand();
    break;
  }
  case 61:
  {
    ClearPictureWindowCommand();
    break;
  }
  }
}

/* ovl03:3171. Runs the ECL script from the script address Address (an entry point: EclPreCampEntry for the camp,
     RunCamp ovl03:2DD3, or one InitScript sets). EclPC takes Address. While the run is not over (ScriptRunEnded clear:
     EndCommand and StartEclBlock set it) and the party is not destroyed (PartyDestroyed clear), the opcode of
     the current command goes to PreviousOpcode, the opcode at EclPC is read into CurrentOpcode and DispatchCommand runs
     it. Both flags are cleared on the way out. */
void RunScriptFrom(u16 Address)
{
  POOL_TRACE("RunScriptFrom");
  EclPC = Address;
  ScriptRunEnded = 0;
  while (((ScriptRunEnded == 0)) && ((PartyDestroyed == 0))) {
    PreviousOpcode = CurrentOpcode;
    CurrentOpcode = (*FPD(TEclCode (*), EclCode))[EclPC - 39168];
    DispatchCommand();
  }
  ScriptRunEnded = 0;
}

/* ovl03:31B4. One step of the area (the party has moved, or the script asked for the area to be drawn again):
     the event byte of the party's cell goes to PartyCellEventByte (EventByteAt), word VarMapEdgeHit of GameVars2 is cleared, and
     the view kind AreaViewKind is set to 1 (the 3D wall view) with its old value kept in PreviousAreaViewKind. The script entry
     EclInitialEntry runs. When VarForceWallView is clear, AreaViewKind takes 2, 3 or 4 from WallViewMode (the map window
     pages; page 3 also animates the area doors, AnimateAreaDoors ovl18:06B3). The picture window is cleared
     when the old kind was a map page, and the area is drawn (ShowAreaView). Then the script entries EclStepEntry and
     EclSearchEntry run, and the step repeats while a script block was started (ScriptBlockStarted, StartEclBlock).
     SelectedCharacter
     is saved and restored around the entries. Called from the area loop RunWilderness (ovl03:32F8). Purpose unknown
     in parts: what the entries and word VarMapEdgeHit do. */
void RunAreaStep(void)
{
  POOL_TRACE("RunAreaStep");
  PCharacter Saved = 0;
  do {
    PartyCellEventByte = EventByteAt(PartyMapColumn, PartyMapRow);
    (*FPD(TGameVars (*), GameVars2))[725] = 0;
    Saved = SelectedCharacter;
    PreviousAreaViewKind = AreaViewKind;
    AreaViewKind = 1;
    RunScriptFrom(EclInitialEntry);
    ViewMode = ViewModeWall;
    if ((*FPD(TGameVars (*), GameVars))[230] == 0) {
      switch (WallViewMode) {
      case WallModeMapPage2:
      {
        AreaViewKind = 2;
        ViewMode = ViewModeMap;
        break;
      }
      case WallModeMapPage3:
      {
        AreaViewKind = 3;
        ViewMode = ViewModeMap;
        if ((((*FPD(TGameVars (*), GameVars))[435] == AreaDoorsOpen)) && (((*FPD(TGameVars (*), GameVars))[418] == 0))) {
          AnimateAreaDoors(1);
        }
        break;
      }
      case WallModeMapPage4:
      {
        AreaViewKind = 4;
        ViewMode = ViewModeMap;
        break;
      }
      }
    }
    if (((PreviousAreaViewKind > 1)) && ((AreaViewKind == 1))) {
      DrawWindow(3, 3, 0xD, 0xD, 0, 0xA, S("\000"));
    }
    if ((((((((PreviousAreaViewKind > 1)) || ((AreaViewKind == 1)))) && ((AreaRedrawArmed != 0)))) || ((((PreviousAreaViewKind == 1)) && ((AreaViewKind == 1)))))) {
      ShowAreaView();
    }
    ScriptBlockStarted = 0;
    RunScriptFrom(EclStepEntry);
    if (ScriptBlockStarted == 0) {
      RunScriptFrom(EclSearchEntry);
      SelectedCharacter = Saved;
      DrawPartyRoster(SelectedCharacter);
    }
  } while (!(ScriptBlockStarted == 0));
}

/* ovl03:32F8. The wilderness loop, entry 1 of this overlay: the main program calls it after the
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
     bytes of this routine (a call operand and a cmp), not routines. */
void RunWilderness(void)
{
  POOL_TRACE("RunWilderness");
  u8 Key = 0;
  u8 Unused = 0;
  Command55Ran = 0;
  Command33Ran = 0;
  ReselectCharacterPending = 0;
  AreaRedrawArmed = 0;
  AreaStepRedrawOnce = 1;
  ViewMode = ViewModeWall;
  ScriptBlockStarted = 0;
  WallViewMode = (*FPD(TGameVars (*), GameVars))[242];
  switch (WallViewMode) {
  case WallModeMapPage2:
  case WallModeMapPage3:
  case WallModeMapPage4:
  {
    if ((*FPD(TGameVars (*), GameVars))[230] == 0) {
      ViewMode = ViewModeMap;
    }
    break;
  }
  }
  if (SkipAreaScriptLoad == 0) {
    LoadEcl(WallViewMode);
  }
  InitScript();
  RunScriptFrom(EclInitialEntry);
  if (ViewMode != ViewModeMap) {
    if (AreaStepRedrawOnce == 1) {
      RedrawView();
      AreaStepRedrawOnce = 0;
    }
    ShowAreaView();
  }
  (*FPD(TGameVars (*), GameVars))[242] = WallViewMode;
  do {
    Key = HandleWildernessKeys();
    ReselectCharacter = SelectedCharacter;
    (*FPD(TGameVars (*), GameVars))[242] = WallViewMode;
    while ((((((*FPD(TGameVars (*), GameVars2))[714] > 1)) || ((rtl_upcase(Key) == KeyCamp)))) && ((PartyDestroyed == 0))) {
      if (rtl_upcase(Key) == KeyCamp) {
        RunCamp();
      } else {
        SavedSearchMode = ((*FPD(TGameVars (*), GameVars2))[714] & 1);
        (*FPD(TGameVars (*), GameVars2))[714] = 1;
        ShowAreaView();
        RunScriptFrom(EclSearchEntry);
        if (ScriptBlockStarted != 0) {
          RunAreaStep();
        }
        (*FPD(TGameVars (*), GameVars2))[714] = SavedSearchMode;
      }
      if (PartyDestroyed == 0) {
        Key = HandleWildernessKeys();
        ReselectCharacter = SelectedCharacter;
      }
    }
    if (PartyDestroyed == 0) {
      RunScriptFrom(EclStepEntry);
    }
    if (ScriptBlockStarted != 0) {
      RunAreaStep();
    } else if (PartyDestroyed == 0) {
      (*FPD(TGameVars (*), GameVars))[240] = PartyMapColumn;
      (*FPD(TGameVars (*), GameVars))[241] = PartyMapRow;
      DoWildernessMenu();
      ShowAreaView();
      /* ShortInt <> Word: the right operand is evaluated first, the original's load order (ovl03:3497). */
      if (((PartyMapColumn != (*FPD(TGameVars (*), GameVars))[240])) || ((PartyMapRow != (*FPD(TGameVars (*), GameVars))[241]))) {
        PlaySound(SoundStep);
      }
      CloseUpShown = 0;
      CloseUpHidden = 1;
      RunScriptFrom(EclSearchEntry);
      if (ScriptBlockStarted != 0) {
        RunAreaStep();
      }
    }
  } while (!(PartyDestroyed != 0));
  PartyDestroyed = 0;
}

/* Initialisation part of unit OVL03. */
void init_OVL03(void)
{
  POOL_TRACE("init");
  /* ovl03:3508. The initialisation part is empty: push bp, mov bp, sp, pop bp, retf. */
}
