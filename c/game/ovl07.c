#include "game.h"

/* ovl07:0000. DecodeOperands: reads the Count operands of the current command from the script at
     EclPC + 1 into OperandType, OperandLow and OperandHigh, and leaves EclPC on the next command.
     Each operand is a type byte and a low byte, plus a high byte for types 1, 2, 3 and $81; a
     packed string (type $80, the low byte its length) is unpacked into the next EclStrings entry
     (DecodeString), and a string address (type $81) copied into it (ReadVmString). */
void DecodeOperands(u8 Count)
{
  POOL_TRACE("DecodeOperands");
  u8 I = 0;
  u8 StrIndex = 0;
  u16 Value = 0;
  u16 Len = 0;
  StrIndex = 0;
  {
    u8 limit = Count;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          OperandType[I] = (*FPD(TEclCode (*), EclCode))[(u16)(EclPC + 1) - 39168];
          OperandLow[I] = (*FPD(TEclCode (*), EclCode))[(u16)(EclPC + 2) - 39168];
          EclPC = EclPC + 2;
          switch (OperandType[I]) {
          case 1:
          case 2:
          case 3:
          {
            EclPC++;
            OperandHigh[I] = (*FPD(TEclCode (*), EclCode))[EclPC - 39168];
            break;
          }
          case 0x80:
          {
            StrIndex++;
            Len = OperandLow[I];
            if (Len > 0) {
              DecodeString(Len, StrIndex);
            } else {
              rtl_str_assign(EclStrings[StrIndex], 255, S("\000"));
            }
            break;
          }
          case 0x81:
          {
            StrIndex++;
            EclPC++;
            OperandHigh[I] = (*FPD(TEclCode (*), EclCode))[EclPC - 39168];
            Value = MakeWord(OperandLow[I], OperandHigh[I]);
            ReadVmString(StrIndex, Value);
            break;
          }
          }
        if (I == limit) break;
        I++;
      }
    }
  }
  EclPC++;
}

/* ovl07:0136. OperandValue: the value of decoded operand N: the byte itself (type 0), the word at
     the address it names (types 1, 3 and $80, ReadVmWord) or the word itself (types 2 and $81).
     QUIRK ovl07:01AD: other types leave the result unassigned. */
u16 OperandValue(s8 N)
{
  POOL_TRACE("OperandValue");
  u16 Result = 0;
  u8 Unused[6] = {0};
  u8 Lo_ = 0;
  u8 Hi_ = 0;
  Lo_ = OperandLow[N];
  Hi_ = OperandHigh[N];
  switch (OperandType[N]) {
  case 0:
  {
    Result = Lo_;
    break;
  }
  case 1:
  case 3:
  case 0x80:
  {
    Result = ReadVmWord((s16)((Hi_ * 256) + Lo_));
    break;
  }
  case 2:
  case 0x81:
  {
    Result = MakeWord(Lo_, Hi_);
    break;
  }
  }
  return Result;
}

/* ovl07:01B6. InitScript: resets the script machine for a newly loaded script: clears its flags,
     sets the special view codes ($41 and 9), points EclPC at the start of the script ($9900) and
     reads the five entry addresses of its header into EclStepEntry..EclInitialEntry; clears game variable
     VarNoCasting and some words of GameVars2, forces the wall view, and (unless SkipAreaScriptLoad asks to keep
     them, which it then clears) clears game variables $4A00..$4A1F and words $6E79..$6E82 of
     GameVars2. */
void InitScript(void)
{
  POOL_TRACE("InitScript");
  u8 Unused = 0;
  u16 I = 0;
  CloseUpShown = 0;
  PictureFrameDirty = 0;
  ActiveFlagClearedByScript = 0;
  NameClearedByScript = 0;
  SpecialViewCode2 = 0x41;
  SpecialViewCode1 = 9;
  SpecialViewGate = 1;
  rtl_FillChar((void *)&PictureShownFlags, 2, 0);
  EncounterIconSlot = 8;
  EclPC = 0x9900;
  PickerDone = 0;
  ReturnStack = 0;
  ReturnPrev = 0;
  rtl_FillChar((void *)&CompareFlags, 6, 0);
  (*FPD(TGameVars (*), GameVars2))[737] = 0xFF;
  (*FPD(TGameVars (*), GameVars2))[722] = 0;
  (*FPD(TGameVars (*), GameVars2))[723] = 0;
  (*FPD(TGameVars (*), GameVars))[229] = 0;
  DecodeOperands(1);
  EclStepEntry = MakeWord(OperandLow[1], OperandHigh[1]);
  DecodeOperands(1);
  EclSearchEntry = MakeWord(OperandLow[1], OperandHigh[1]);
  DecodeOperands(1);
  EclPreCampEntry = MakeWord(OperandLow[1], OperandHigh[1]);
  DecodeOperands(1);
  EclCampInterruptedEntry = MakeWord(OperandLow[1], OperandHigh[1]);
  DecodeOperands(1);
  EclInitialEntry = MakeWord(OperandLow[1], OperandHigh[1]);
  (*FPD(TGameVars (*), GameVars))[230] = 1;
  if (SkipAreaScriptLoad == 0) {
    {
      if (1 <= 0x20) {
        I = 1;
        for (;;) {
            (*FPD(TVmWords4900 (*), VarsAt4900))[(u16)(I + 0x49FF) - 18688] = 0;
          if (I == 0x20) break;
          I++;
        }
      }
    }
    {
      if (0 <= 9) {
        I = 0;
        for (;;) {
            (*FPD(TVmWords6B00 (*), VarsAt6B00))[(u16)(I + 0x6E79) - 27392] = 0;
          if (I == 9) break;
          I++;
        }
      }
    }
  } else {
    SkipAreaScriptLoad = 0;
  }
}

/* ovl07:0341. LoadEcl: loads block BlockId of ECL<TileSet>.DAX into EclCode (whitepaper 4.2.2):
     clears the buffer, shows 'Loading...Please Wait' on the prompt line and loads the block until
     it holds at least the leading word (LoadDaxBlock), copies the bytes after that word, frees the
     block and clears the prompt line. */
void LoadEcl(u8 BlockId)
{
  POOL_TRACE("LoadEcl");
  u8 Unused[4] = {0};
  u8 Num[2] = {0};
  u16 Size = 0;
  farptr Block = 0;
  u8 ts1[5];
  rtl_FillChar((void *)&(*FPD(TEclCode (*), EclCode)), 0x1E00, 0);
  OpenNoPrompt = 0;
  do {
    ClearPromptLine();
    DrawTextAt(0, 0x18, 0xF, S("\025Loading...Please Wait"));
    rtl_str_int(Num, 1, TileSet, 0);
    LoadDaxBlock(rtl_str_cat(ts1, 2, (const u8 *const[]){S("\003ECL"), Num}), S("\004.dax"), BlockId, &Size, &Block);
  } while (!(Size >= 2));
  rtl_Move((void *)&(*FPD(TByteArray (*), Block))[2], (void *)&(*FPD(TEclCode (*), EclCode)), (u16)(Size - 2));
  rtl_freemem(Block, Size);
  ClearPromptLine();
}

/* ovl07:0411. LoadCharacter: allocates a character record (New), has LoadMonster fill it for Kind
     and returns it with its item list and its affect list. */
void LoadCharacter(u8 Kind, PCharacter (*Who), PItem (*Items), farptr (*Affects))
{
  POOL_TRACE("LoadCharacter");
  u8 Unused[4] = {0};
  (*Who) = 0;
  (*Who) = rtl_getmem(285);
  LoadMonster(Kind, (*Who));
  (*Items) = (*FPD(TCharacter (*), (*Who))).Items;
  (*Affects) = (*FPD(TCharacter (*), (*Who))).Affects;
}

/* ovl07:0482. OpenStepsAhead: how many cells the party can see ahead from (Col, Row) facing Dir
     (0, 2, 4, 6: north, east, south, west), counting the cells without a wall (WallIdAt 0) up to
     2. When the wall view is off (game variable VarForceWallView 0) the answer is 2, also stored
     in word $2C1 of GameVars2. */
u8 OpenStepsAhead(s8 Col, s8 Row, u8 Dir)
{
  POOL_TRACE("OpenStepsAhead");
  u8 Result = 0;
  u8 Done = 0;
  u8 Steps = 0;
  Steps = 0;
  Done = 0;
  Result = 0;
  if ((*FPD(TGameVars (*), GameVars))[230] == 0) {
    Result = 2;
    (*FPD(TGameVars (*), GameVars2))[705] = 2;
  } else {
    while (((Steps < 2)) && ((Done == 0))) {
      if (WallIdAt(Col, Row, Dir) == 0) {
        Steps++;
        Result = Steps;
        switch (Dir) {
        case DirNorth:
        {
          Row--;
          break;
        }
        case DirEast:
        {
          Col++;
          break;
        }
        case DirSouth:
        {
          Row++;
          break;
        }
        case DirWest:
        {
          Col--;
          break;
        }
        }
      } else {
        Done = 1;
      }
    }
  }
  return Result;
}

/* ovl07:0511. ShowHeadBody: loads the HEAD and BODY picture banks HeadBank and BodyBank
     (LoadHeadBodySprites), remembers them in ShownHeadBank and ShownBodyBank, and shows them at column 3, row 3
     with the body (ShowHeadBodySprites). Clears CloseUpHidden. Called by ovl03 and ShowEncounterPicture. */
void ShowHeadBody(u8 HeadBank, u8 BodyBank)
{
  POOL_TRACE("ShowHeadBody");
  CloseUpHidden = 0;
  ShownHeadBank = HeadBank;
  ShownBodyBank = BodyBank;
  LoadHeadBodySprites(HeadBank, BodyBank);
  ShowHeadBodySprites(3, 3, 1);
}

/* ovl07:054E. ShowEncounterPicture: in the 3D view (AreaViewKind 1) loads the SPRIT sprites of
     SpriteBank once (Shown[0]) and shows the one for Distance (0..2 cells away, Show3DSprite
     slot Distance + 1; slot 2 outside the 3D view); when the party is next to it (Distance 0) and
     monster pictures are wanted, shows the close-up once (Shown[1]): the PIC picture PicBank when
     word $2E1 of GameVars2 is $FF, else HEAD picture bank word $2E1 with BODY bank PicBank
     (ShowHeadBody); LastShownPictureWord remembers word $2E1 so the same close-up is not shown twice. Redraws the area
     view first when only the sprite was shown. */
void ShowEncounterPicture(u8 SpriteBank, u8 PicBank, u8 Distance, TPictureShown (*Shown))
{
  POOL_TRACE("ShowEncounterPicture");
  u8 Unused[8] = {0};
  u8 Slot = 0;
  if ((((*Shown)[1] == 0)) && (((*Shown)[0] != 0))) {
    ShowAreaView();
  }
  Slot = Distance + 1;
  if ((*Shown)[1] == 0) {
    if ((*Shown)[0] == 0) {
      if (WallMapMode != 0) {
        WallMapMode = 0;
        ShowAreaView();
      }
      LoadSpriteList(S("\005SPRIT"), SpriteBank, 1, rtl_far(&PictureAnimation));
      (*Shown)[0] = 1;
      Sprite3DLoaded = 1;
    }
    if (AreaViewKind == 1) {
      Show3DSprite(Slot, rtl_far(&PictureAnimation));
    } else {
      Show3DSprite(2, rtl_far(&PictureAnimation));
    }
  }
  if ((((*Shown)[1] != 0)) && ((LastShownPictureWord == (*FPD(TGameVars (*), GameVars2))[737]))) {
    return;
  }
  if (Distance != 0) {
    return;
  }
  if (AreaViewKind != 1) {
    return;
  }
  if (((SkipCloseUpIfNoPics != 0)) && ((ShowMonsterPics == 0))) {
    return;
  }
  LastShownPictureWord = (*FPD(TGameVars (*), GameVars2))[737];
  CloseUpShown = 1;
  if ((*FPD(TGameVars (*), GameVars2))[737] == 0xFF) {
    LoadSpriteList(S("\003PIC"), PicBank, 0, rtl_far(&PictureAnimation));
    (*Shown)[1] = 1;
    DrawSprite(3, 3, 1, PictureAnimation.Frames[0].Sprite);
  } else {
    ShowHeadBody((*FPD(TGameVars (*), GameVars2))[737], PicBank);
    (*Shown)[1] = 1;
    CloseUpHidden = 0;
  }
}

/* ovl07:06AF. MakeWord: the word whose low byte is Lo and high byte Hi (an operand's two bytes,
     OperandLow and OperandHigh). */
u16 MakeWord(u8 Lo_, u8 Hi_)
{
  POOL_TRACE("MakeWord");
  u16 Result = 0;
  Result = (Hi_ * 256) + Lo_;
  return Result;
}

/* ovl07:06D3. SixBitChar: the character of a 6-bit code of a packed script string: codes $20..$3F
     are themselves (space, digits, punctuation), codes 1..$1F become $41..$5F (the letters). */
u8 SixBitChar(u8 Code)
{
  POOL_TRACE("SixBitChar");
  u8 Result = 0;
  if (Code > 0x1F) {
    Result = (u8)Code;
  } else {
    Result = (u8)(s16)(Code + 0x40);
  }
  return Result;
}

/* ovl07:06FB. MemRegion: which block a script address names: RegionGameVars ($4900..$4CFF, the
     words of GameVars), RegionWords6B00 ($6B00..$6EFF, the words of GameVars2, overlaid by the selected
     character's fields), RegionWords9700 ($9700..$98FF, the words of GameVars3), RegionCode
     ($9900..$B6FF, the bytes of the loaded script) or RegionSpecial (anything else, the engine
     variables ReadVmWord and WriteVmWord handle one by one). */
u8 MemRegion(u16 Addr)
{
  POOL_TRACE("MemRegion");
  u8 Result = 0;
  Result = RegionSpecial;
  if (((Addr >= 0x4900)) && ((Addr <= 0x4CFF))) {
    Result = RegionGameVars;
  }
  if (((Addr >= 0x6B00)) && ((Addr <= 0x6EFF))) {
    Result = RegionWords6B00;
  }
  if (((Addr >= 0x9700)) && ((Addr <= 0x98FF))) {
    Result = RegionWords9700;
  }
  if (((Addr >= 0x9900)) && ((Addr <= 0xB6FF))) {
    Result = RegionCode;
  }
  return Result;
}

/* ovl07:0756. PartyIndexOf: the 0-based position of Who in the party list (PartyListHead); the length
     of the list when Who is not in it. */
u8 PartyIndexOf(PCharacter Who)
{
  POOL_TRACE("PartyIndexOf");
  u8 Result = 0;
  u8 Index = 0;
  PCharacter Member = 0;
  u8 Found = 0;
  Member = PartyListHead;
  Found = 0;
  Index = 0;
  while (((Member != 0)) && !Found) {
    if (Member == Who) {
      Found = 1;
    } else {
      Index++;
      Member = (*FPD(TCharacter (*), Member)).Next;
    }
  }
  Result = Index;
  return Result;
}

/* ovl07:07BC. GetCharacterVar: the value of script address Addr ($6B00..$6EFF) when it names a
     field of the selected character (SelectedCharacter) or another engine value; Found is False
     (and the result undefined) for the addresses it does not handle, which ReadVmWord then reads
     from GameVars2. The offsets are those of the script's character record, not of TCharacter.
     QUIRK ovl07:095A: address $6C0D sets Found but leaves the result unassigned. */
u16 GetCharacterVar(u16 Addr, u8 (*Found))
{
  POOL_TRACE("GetCharacterVar");
  u16 Result = 0;
  u8 Index = 0;
  (*Found) = 1;
  Addr = Addr - 0x6B00;
  switch (Addr) {
  case 0x18:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).Constitution;
    break;
  }
  case 0x9B:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).SavingThrows[1];
    break;
  }
  case 0xA0:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).HighestLevel;
    break;
  }
  case 165:
  case 166:
  case 167:
  case 168:
  case 169:
  case 170:
  case 171:
  case 172:
  {
    Index = Addr - 0xA4;
    Result = (*FPD(TCharacter (*), SelectedCharacter)).ThiefSkills[Index - 1];
    break;
  }
  case 0xB8:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).B84;
    break;
  }
  case 0xBB:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).Money[0];
    break;
  }
  case 0xBD:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).Money[1];
    break;
  }
  case 0xBF:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).Money[2];
    break;
  }
  case 0xC1:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).Money[3];
    break;
  }
  case 0xC3:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).Money[4];
    break;
  }
  case 0xD8:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).Alignment;
    break;
  }
  case 0xF7:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).XpValue;
    break;
  }
  case 0xF9:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).XpPerHp;
    break;
  }
  case 0x100:
  {
    if ((*FPD(TCharacter (*), SelectedCharacter)).Flag10D != 0) {
      Result = 1;
    } else {
      Result = 0x80;
    }
    break;
  }
  case 0x10C:
  {
    if ((((*FPD(TCharacter (*), SelectedCharacter)).Side == 0)) && (((*FPD(TCharacter (*), SelectedCharacter)).Quick != 0))) {
      Result = 0x80;
    } else if ((*FPD(TCharacter (*), SelectedCharacter)).Side == 1) {
      Result = 0x81;
    } else {
      Result = 0;
    }
    break;
  }
  case 0x10D:
  {
    break;
  }
  case 0x11B:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).Movement;
    break;
  }
  case 0x2B1:
  {
    Result = PartyIndexOf(SelectedCharacter);
    break;
  }
  case 0x2B4:
  {
    Result = PartyIndexOf(SelectedCharacter);
    break;
  }
  case 0x2CF:
  {
    switch ((*FPD(TCharacter (*), SelectedCharacter)).Charisma) {
    case 3:
    {
      Result = 0;
      break;
    }
    case 4:
    {
      Result = 5;
      break;
    }
    case 5:
    {
      Result = 10;
      break;
    }
    case 6:
    {
      Result = 15;
      break;
    }
    case 7:
    {
      Result = 20;
      break;
    }
    case 8:
    case 9:
    case 10:
    case 11:
    case 12:
    {
      Result = 25;
      break;
    }
    case 13:
    {
      Result = 30;
      break;
    }
    case 14:
    {
      Result = 35;
      break;
    }
    case 15:
    {
      Result = 40;
      break;
    }
    case 16:
    {
      Result = 50;
      break;
    }
    case 17:
    {
      Result = 55;
      break;
    }
    case 18:
    case 19:
    case 20:
    case 21:
    case 22:
    case 23:
    case 24:
    case 25:
    {
      Result = 60;
      break;
    }
    }
    break;
  }
  case 0x312:
  {
    Result = TileSet;
    break;
  }
  case 0x33E:
  {
    Result = (*FPD(TGameVars (*), GameVars2))[830];
    break;
  }
  default:
  {
    (*Found) = 0;
  }
  }
  return Result;
}

/* ovl07:0A74. SetCharacterVar: applies a script write of Value to address Addr ($6B00..$6EFF) to
     the selected character's fields and engine state (WriteVmWord has already stored it in GameVars2).
     QUIRK ovl07:0AA3: addresses $6B20..$6B70 write the byte at Spells[Addr - $6B1F], past the 21
     spell slots into the bytes that follow. */
void SetCharacterVar(u16 Addr, u16 Value)
{
  POOL_TRACE("SetCharacterVar");
  u8 Index = 0;
  s32 t1;
  Addr = Addr - 0x6B00;
  t1 = Addr;
  if (t1 == 0) {
    if (Value == 0) {
      NameClearedByScript = 1;
    }
  } else if ((t1 >= 32 && t1 <= 112)) {
    Index = Addr - 0x1F;
    (*FPD(TCharacter (*), SelectedCharacter)).Spells[Index] = Value;
  } else if (t1 == 184) {
    if (Value > 0xB2) {
      Value -= 0x32;
    }
    (*FPD(TCharacter (*), SelectedCharacter)).B84 = Value;
  } else if (t1 == 187) {
    (*FPD(TCharacter (*), SelectedCharacter)).Money[0] = Value;
  } else if (t1 == 189) {
    (*FPD(TCharacter (*), SelectedCharacter)).Money[1] = Value;
  } else if (t1 == 191) {
    (*FPD(TCharacter (*), SelectedCharacter)).Money[2] = Value;
  } else if (t1 == 193) {
    (*FPD(TCharacter (*), SelectedCharacter)).Money[3] = Value;
  } else if (t1 == 195) {
    (*FPD(TCharacter (*), SelectedCharacter)).Money[4] = Value;
  } else if (t1 == 247) {
    (*FPD(TCharacter (*), SelectedCharacter)).XpValue = Value;
  } else if (t1 == 249) {
    (*FPD(TCharacter (*), SelectedCharacter)).XpPerHp = Value;
  } else if (t1 == 256) {
    if (Value >= 0x80) {
      (*FPD(TCharacter (*), SelectedCharacter)).Flag10D = 0;
      if (Value == 0x87) {
        (*FPD(TCharacter (*), SelectedCharacter)).Status = 7;
      }
    }
    if (Value == 0) {
      ActiveFlagClearedByScript = 1;
    }
  } else if (t1 == 268) {
    switch (Value) {
    case 0:
    {
      (*FPD(TCharacter (*), SelectedCharacter)).Side = 0;
      (*FPD(TCharacter (*), SelectedCharacter)).Quick = 0;
      break;
    }
    case 0x80:
    {
      (*FPD(TCharacter (*), SelectedCharacter)).Side = 0;
      (*FPD(TCharacter (*), SelectedCharacter)).Quick = 1;
      break;
    }
    case 0x81:
    {
      (*FPD(TCharacter (*), SelectedCharacter)).Side = 1;
      (*FPD(TCharacter (*), SelectedCharacter)).Quick = 1;
      break;
    }
    }
  } else if (t1 == 786) {
    SelectTileSet(Value);
  } else if (t1 == 802) {
    if (Value > 0x80) {
      Value = (Value & 0x7F);
      LoadWallSet(Value, 1);
    }
  } else if (t1 == 804) {
    if (Value > 0x80) {
      Value = (Value & 0x7F);
      LoadWallSet(Value, 2);
    }
  } else if (t1 == 806) {
    if (Value > 0x80) {
      Value = (Value & 0x7F);
      LoadWallSet(Value, 3);
    }
  }
}

/* ovl07:0C77. WriteVmWord: the script's store of Value at address Addr: a word of GameVars,
     GameVars2 (then also SetCharacterVar) or GameVars3, a byte of the loaded script, or one of the engine
     variables at the special addresses (the party's position and marker, the special view codes). */
void WriteVmWord(u16 Addr, u16 Value)
{
  POOL_TRACE("WriteVmWord");
  u8 Region = 0;
  u8 Done = 0;
  Region = MemRegion(Addr);
  switch (Region) {
  case RegionGameVars:
  {
    (*FPD(TVmWords4900 (*), VarsAt4900))[Addr - 18688] = Value;
    if (((Addr == 0x49FD)) || ((Addr == 0x49FE))) {
      HeadBodyWritten = 1;
    }
    break;
  }
  case RegionWords6B00:
  {
    (*FPD(TVmWords6B00 (*), VarsAt6B00))[Addr - 27392] = Value;
    SetCharacterVar(Addr, Value);
    break;
  }
  case RegionWords9700:
  {
    (*FPD(TVmWords9700 (*), VarsAt9700))[Addr - 38656] = Value;
    break;
  }
  case RegionCode:
  {
    (*FPD(TEclCode (*), EclCode))[Addr - 39168] = Value;
    break;
  }
  case RegionSpecial:
  {
    if (Addr < 0xBF68) {
      switch (Addr) {
      case 0xFB:
      {
        break;
      }
      case 0xFC:
      {
        break;
      }
      case 0xB1:
      {
        break;
      }
      case 0x3DE:
      {
        ScriptSoundCode = Value;
        break;
      }
      case 0xB8:
      {
        ScriptWordB8 = Value;
        break;
      }
      case 0xB9:
      {
        ScriptWordB9 = Value;
        break;
      }
      }
    } else {
      Addr = Addr - 0xBF68;
      switch (Addr) {
      case 0xE3:
      {
        PartyMovedByScript = 1;
        PartyMapColumn = Value;
        break;
      }
      case 0xE4:
      {
        PartyMapRow = Value;
        PartyMovedByScript = 1;
        break;
      }
      case 0xE5:
      {
        do {
          Done = 1;
          switch (Value) {
          case 0:
          {
            PartyFacing = 0;
            break;
          }
          case 1:
          {
            PartyFacing = 2;
            break;
          }
          case 2:
          {
            PartyFacing = 4;
            break;
          }
          case 3:
          {
            PartyFacing = 6;
            break;
          }
          default:
          {
            Done = 0;
            Value -= 4;
          }
          }
        } while (!(Done == 1));
        PartyMovedByScript = 1;
        break;
      }
      case 0xF1:
      {
        SpecialViewCode2 = Value;
        SpecialViewGate = 1;
        break;
      }
      case 0xF7:
      {
        SpecialViewCode1 = Value;
        SpecialViewGate = 1;
        break;
      }
      case 0x10BA:
      {
        break;
      }
      }
    }
    break;
  }
  }
}

/* ovl07:0E0C. ReadVmWord: the script's load of the word at address Addr: a word of GameVars,
     GameVars2 (unless GetCharacterVar answers it from the selected character) or GameVars3, a byte of the
     loaded script, or an engine variable at the special addresses. QUIRK ovl07:0EE7, 0F45: the
     addresses it does not know leave the result unassigned. */
u16 ReadVmWord(u16 Addr)
{
  POOL_TRACE("ReadVmWord");
  u16 Result = 0;
  u8 Region = 0;
  u8 Found = 0;
  u16 Unused = 0;
  Region = MemRegion(Addr);
  Found = 0;
  switch (Region) {
  case RegionGameVars:
  {
    Result = (*FPD(TVmWords4900 (*), VarsAt4900))[Addr - 18688];
    break;
  }
  case RegionWords6B00:
  {
    Result = GetCharacterVar(Addr, &Found);
    if (!Found) {
      Result = (*FPD(TVmWords6B00 (*), VarsAt6B00))[Addr - 27392];
    }
    break;
  }
  case RegionWords9700:
  {
    Result = (*FPD(TVmWords9700 (*), VarsAt9700))[Addr - 38656];
    break;
  }
  case RegionCode:
  {
    Result = (*FPD(TEclCode (*), EclCode))[Addr - 39168];
    break;
  }
  case RegionSpecial:
  {
    if (Addr < 0xC04B) {
      switch (Addr) {
      case 0xB1:
      {
        Result = ScriptWordB1;
        break;
      }
      case 0xFB:
      {
        Result = ScriptWordFB;
        break;
      }
      case 0xFC:
      {
        Result = ScriptWordFC;
        break;
      }
      case 0x33D:
      {
        Result = PartyFacing;
        break;
      }
      case 0x35F:
      {
        break;
      }
      }
    } else {
      Addr = Addr - 0xC04B;
      switch (Addr) {
      case 0:
      {
        Result = PartyMapColumn;
        break;
      }
      case 1:
      {
        Result = PartyMapRow;
        break;
      }
      case 2:
      {
        Result = (s16)((u16)PartyFacing >> 1);
        break;
      }
      case 3:
      {
        Result = PartyCellWallId;
        break;
      }
      case 4:
      {
        Result = PartyCellEventByte;
        break;
      }
      case 0xE:
      {
        break;
      }
      }
    }
    break;
  }
  }
  return Result;
}

/* ovl07:0F53. WriteVmString: stores Text at script address Addr, one character per word of
     GameVars, GameVars2 or GameVars3 or per byte of the script, followed by a 0; address $6B00 is the
     selected character's name instead (up to 15 characters). Nothing for the special addresses. */
void WriteVmString(u16 Addr, const u8 *Text_in)
{
  POOL_TRACE("WriteVmString");
  const u8 *Text = Text_in;
  u8 Region = 0;
  u8 Len = 0;
  u8 I = 0;
  Region = MemRegion(Addr);
  Len = Text[0];
  switch (Region) {
  case RegionGameVars:
  {
    {
      u8 limit = (s16)(Len - 1);
      if (0 <= limit) {
        I = 0;
        for (;;) {
            (*FPD(TVmWords4900 (*), VarsAt4900))[(u16)(I + Addr) - 18688] = Text[(s16)(I + 1)];
          if (I == limit) break;
          I++;
        }
      }
    }
    (*FPD(TVmWords4900 (*), VarsAt4900))[(u16)(Len + Addr) - 18688] = 0;
    break;
  }
  case RegionWords6B00:
  {
    if (Addr == 0x6B00) {
      rtl_str_assign((*FPD(TCharacter (*), SelectedCharacter)).Name, 15, Text);
    } else {
      {
        u8 limit = (s16)(Len - 1);
        if (0 <= limit) {
          I = 0;
          for (;;) {
              (*FPD(TVmWords6B00 (*), VarsAt6B00))[(u16)(I + Addr) - 27392] = Text[(s16)(I + 1)];
            if (I == limit) break;
            I++;
          }
        }
      }
      (*FPD(TVmWords6B00 (*), VarsAt6B00))[(u16)(Len + Addr) - 27392] = 0;
    }
    break;
  }
  case RegionWords9700:
  {
    {
      u8 limit = (s16)(Len - 1);
      if (0 <= limit) {
        I = 0;
        for (;;) {
            (*FPD(TVmWords9700 (*), VarsAt9700))[(u16)(I + Addr) - 38656] = Text[(s16)(I + 1)];
          if (I == limit) break;
          I++;
        }
      }
    }
    (*FPD(TVmWords9700 (*), VarsAt9700))[(u16)(Len + Addr) - 38656] = 0;
    break;
  }
  case RegionCode:
  {
    {
      u8 limit = (s16)(Len - 1);
      if (0 <= limit) {
        I = 0;
        for (;;) {
            (*FPD(TEclCode (*), EclCode))[(u16)(I + Addr) - 39168] = Text[(s16)(I + 1)];
          if (I == limit) break;
          I++;
        }
      }
    }
    (*FPD(TEclCode (*), EclCode))[(u16)(Len + Addr) - 39168] = 0;
    break;
  }
  }
}

/* ovl07:1153. DecodeString: unpacks a packed string operand of Len bytes from the script at
     EclPC + 1 into EclStrings[Index], advancing EclPC: every three bytes hold four 6-bit codes,
     SixBitChar turns each nonzero code into a character, code 0 is skipped. */
void DecodeString(u8 Len, u8 Index)
{
  POOL_TRACE("DecodeString");
  u8 Count = 0;
  u8 Unused = 0;
  u8 Cur = 0;
  u8 Prev = 0;
  u8 Code = 0;
  u8 Phase = 0;
  u8 Ch = 0;
  u8 ts1[2];
  u8 ts2[256];
  rtl_str_assign(EclStrings[Index], 255, S("\000"));
  Count = 0;
  Phase = 1;
  while (Count < Len) {
    if (Phase < 4) {
      EclPC++;
      Prev = Cur;
      Cur = (*FPD(TEclCode (*), EclCode))[EclPC - 39168];
      Count++;
    }
    switch (Phase) {
    case 1:
    {
      Code = (s16)((u16)Cur >> 2);
      break;
    }
    case 2:
    {
      Code = (Prev << 6) + (s16)((u16)Cur >> 2);
      Code = (s16)((u16)Code >> 2);
      break;
    }
    case 3:
    {
      Code = (Prev << 4) + (s16)((u16)Cur >> 4);
      Code = (s16)((u16)Code >> 2);
      break;
    }
    case 4:
    {
      Code = (Cur & 0x3F);
      break;
    }
    }
    if (Phase < 4) {
      Phase++;
    } else {
      Phase = 1;
    }
    if (Code != 0) {
      Ch = SixBitChar(Code);
      rtl_str_assign(EclStrings[Index], 255, rtl_str_cat(ts2, 2, (const u8 *const[]){EclStrings[Index], rtl_str_char(ts1, Ch)}));
    }
  }
  if (Phase == 4) {
    Code = (Cur & 0x3F);
    if (Code != 0) {
      Ch = SixBitChar(Code);
      rtl_str_assign(EclStrings[Index], 255, rtl_str_cat(ts2, 2, (const u8 *const[]){EclStrings[Index], rtl_str_char(ts1, Ch)}));
    }
  }
}

/* ovl07:12FB. ReadVmString: copies the string stored at script address Addr (one character per
     word of GameVars, GameVars2 or GameVars3 or per byte of the script, up to a 0) into
     EclStrings[Index]; address $6B00 is the selected character's name. */
void ReadVmString(u8 Index, u16 Addr)
{
  POOL_TRACE("ReadVmString");
  u8 Region = 0;
  u8 I = 0;
  u8 ts1[2];
  u8 ts2[256];
  Region = MemRegion(Addr);
  rtl_str_assign(EclStrings[Index], 255, S("\000"));
  I = 0;
  switch (Region) {
  case RegionGameVars:
  {
    while ((*FPD(TVmWords4900 (*), VarsAt4900))[(u16)(I + Addr) - 18688] != 0) {
      rtl_str_assign(EclStrings[Index], 255, rtl_str_cat(ts2, 2, (const u8 *const[]){EclStrings[Index], rtl_str_char(ts1, (u8)(*FPD(TVmWords4900 (*), VarsAt4900))[(u16)(I + Addr) - 18688])}));
      I++;
    }
    break;
  }
  case RegionWords6B00:
  {
    if (Addr == 0x6B00) {
      rtl_str_assign(EclStrings[Index], 255, (*FPD(TCharacter (*), SelectedCharacter)).Name);
    } else {
      while ((*FPD(TVmWords6B00 (*), VarsAt6B00))[(u16)(I + Addr) - 27392] != 0) {
        rtl_str_assign(EclStrings[Index], 255, rtl_str_cat(ts2, 2, (const u8 *const[]){EclStrings[Index], rtl_str_char(ts1, (u8)(*FPD(TVmWords6B00 (*), VarsAt6B00))[(u16)(I + Addr) - 27392])}));
        I++;
      }
    }
    break;
  }
  case RegionWords9700:
  {
    while ((*FPD(TVmWords9700 (*), VarsAt9700))[(u16)(I + Addr) - 38656] != 0) {
      rtl_str_assign(EclStrings[Index], 255, rtl_str_cat(ts2, 2, (const u8 *const[]){EclStrings[Index], rtl_str_char(ts1, (u8)(*FPD(TVmWords9700 (*), VarsAt9700))[(u16)(I + Addr) - 38656])}));
      I++;
    }
    break;
  }
  case RegionCode:
  {
    while ((*FPD(TEclCode (*), EclCode))[(u16)(I + Addr) - 39168] != 0) {
      rtl_str_assign(EclStrings[Index], 255, rtl_str_cat(ts2, 2, (const u8 *const[]){EclStrings[Index], rtl_str_char(ts1, (u8)(*FPD(TEclCode (*), EclCode))[(u16)(I + Addr) - 39168])}));
      I++;
    }
    break;
  }
  }
}

/* ovl07:156D. ParseHotkeys: prepares a menu text for the prompt: turns its letters and digits to
     lower case (+$20), and for every '~' removes it, upper-cases the character after it and appends
     that character to Keys, the menu's hotkeys in order. QUIRK ovl07:15BF: digits are moved by $20
     as well ('0'..'9' become 'P'..'Y'). */
void ParseHotkeys(u8 (*Text)[256], String40_RES06 (*Keys))
{
  POOL_TRACE("ParseHotkeys");
  u8 I = 0;
  s32 t1;
  u8 ts1[2];
  u8 ts2[42];
  rtl_str_assign((*Keys), 40, S("\000"));
  {
    u8 limit = (*Text)[0];
    if (1 <= limit) {
      I = 1;
      for (;;) {
          if ((t1 = (*Text)[I]), ((t1 >= '0' && t1 <= '9') || (t1 >= 'A' && t1 <= 'Z'))) {
            (*Text)[I] = (u8)(s16)((*Text)[I] + 0x20);
          }
          if ((*Text)[I] == HotkeyMark) {
            rtl_str_delete((*Text), I, 1);
            (*Text)[I] = rtl_upcase((*Text)[I]);
            rtl_str_assign((*Keys), 40, rtl_str_cat(ts2, 2, (const u8 *const[]){(*Keys), rtl_str_char(ts1, (*Text)[I])}));
          }
        if (I == limit) break;
        I++;
      }
    }
  }
}

/* ovl07:1684. AskMenu: shows Title and the menu Text on the prompt line (ReadPromptChoice, in the
     three colours, Animate passed on) and waits for one of its '~' hotkeys (ParseHotkeys); Return
     also answers when AcceptEnter is set. Returns the 0-based position of the hotkey in the menu
     (so '~Yes ~No' gives 0 or 1), 0 for Return, $FF for a letter or digit that is not a hotkey.
     An extended key goes to UpdateSelectedCharacter and the selected character is redrawn (DrawPartyRoster)
     before asking again. Callers: ovl03, the Temple, the treasure menu and the shop. */
u8 AskMenu(const u8 *Title_in, const u8 *Text_in, u8 TitleColor_, u8 WordColor_, u8 HotColor_, u8 AcceptEnter, u8 Animate)
{
  POOL_TRACE("AskMenu");
  const u8 *Title = Title_in;
  u8 Text[256];
  rtl_str_assign(Text, 255, Text_in);
  u8 Result = 0;
  String40_RES06 Keys = {0};
  u8 I = 0;
  u8 Key = 0;
  u8 ExtKey = 0;
  ParseHotkeys(&Text, &Keys);
  do {
    Key = ReadPromptChoice(Title, Text, TitleColor_, WordColor_, HotColor_, 1, Animate, &ExtKey);
    if (ExtKey != 0) {
      UpdateSelectedCharacter(Key);
      DrawPartyRoster(SelectedCharacter);
      Key = 0x00;
    }
  } while (!((((Key >= '0' && Key <= '9') || (Key >= 'A' && Key <= 'Z'))) || ((((Key == KeyReturn)) && ((AcceptEnter != 0))))));
  switch ((u8)Key) {
  case 0x0D:
  {
    Result = 0;
    break;
  }
  default:
  {
    I = 1;
    while (((I <= Keys[0])) && ((Keys[I] != Key))) {
      I++;
    }
    if (I <= Keys[0]) {
      Result = I - 1;
    } else {
      Result = 0xFF;
    }
  }
  }
  return Result;
}

/* ovl07:1788. AskListMenu: ParseHotkeys on the menu Text, then the scrolling list menu
     ChooseFromList with Title, the prepared Text and every other parameter passed on; the key it
     returns is dropped (only the var results Redraw, Choice and Selected matter). Called by ovl03. */
void AskListMenu(const u8 *Title_in, const u8 *Text_in, u8 HeadingColor, u8 LineColor, u8 HighlightColor, s8 Left, s8 Top, s8 Right, s8 Bottom, PMenuLine List, u8 WithExit, u8 (*Redraw), s16 (*Choice), PMenuLine (*Selected))
{
  POOL_TRACE("AskListMenu");
  const u8 *Title = Title_in;
  u8 Text[256];
  rtl_str_assign(Text, 255, Text_in);
  u8 Key = 0;
  String40_RES06 Keys = {0};
  ParseHotkeys(&Text, &Keys);
  Key = ChooseFromList(Title, Text, HeadingColor, LineColor, HighlightColor, Left, Top, Right, Bottom, List, WithExit, &(*Redraw), &(*Choice), &(*Selected));
}

/* ovl07:1815. CompareStrings: sets the six comparison flags CompareFlags for Left against Right. */
void CompareStrings(const u8 *Left_in, const u8 *Right_in)
{
  POOL_TRACE("CompareStrings");
  const u8 *Left = Left_in;
  const u8 *Right = Right_in;
  rtl_FillChar((void *)&CompareFlags, 6, 0);
  if (rtl_str_cmp(Left, Right) == 0) {
    CompareFlags[0] = 1;
  }
  if (rtl_str_cmp(Left, Right) != 0) {
    CompareFlags[1] = 1;
  }
  if (rtl_str_cmp(Left, Right) < 0) {
    CompareFlags[2] = 1;
  }
  if (rtl_str_cmp(Left, Right) > 0) {
    CompareFlags[3] = 1;
  }
  if (rtl_str_cmp(Left, Right) <= 0) {
    CompareFlags[4] = 1;
  }
  if (rtl_str_cmp(Left, Right) >= 0) {
    CompareFlags[5] = 1;
  }
}

/* ovl07:18EB. CompareWords: sets the six comparison flags CompareFlags for Left against Right
     (unsigned). */
void CompareWords(u16 Left, u16 Right)
{
  POOL_TRACE("CompareWords");
  rtl_FillChar((void *)&CompareFlags, 6, 0);
  if (Left == Right) {
    CompareFlags[0] = 1;
  }
  if (Left != Right) {
    CompareFlags[1] = 1;
  }
  if (Left < Right) {
    CompareFlags[2] = 1;
  }
  if (Left > Right) {
    CompareFlags[3] = 1;
  }
  if (Left <= Right) {
    CompareFlags[4] = 1;
  }
  if (Left >= Right) {
    CompareFlags[5] = 1;
  }
}

/* ovl07:1951. ScriptGosub: pushes EclPC on the script's return stack (ReturnStack, a new 6-byte entry)
     and jumps to the address of decoded operand N. */
void ScriptGosub(u8 N)
{
  POOL_TRACE("ScriptGosub");
  if (ReturnStack == 0) {
    ReturnStack = rtl_getmem(6);
    (*FPD(TReturnEntry (*), ReturnStack)).Next = 0;
  } else {
    ReturnPrev = ReturnStack;
    ReturnStack = rtl_getmem(6);
    (*FPD(TReturnEntry (*), ReturnStack)).Next = ReturnPrev;
  }
  (*FPD(TReturnEntry (*), ReturnStack)).ReturnPC = EclPC;
  EclPC = MakeWord(OperandLow[N], OperandHigh[N]);
}

/* ovl07:19DB. StepPartyForward: moves the party one cell in the direction it faces (PartyFacing: 0, 2,
     4, 6) on the 16 x 16 area map, wrapping at the edges, then reads the new cell's event byte
     (EventByteAt into PartyCellEventByte) and the wall it faces (WallIdAt into PartyCellWallId). */
void StepPartyForward(void)
{
  POOL_TRACE("StepPartyForward");
  switch (PartyFacing) {
  case DirNorth:
  {
    if (PartyMapRow > 0) {
      PartyMapRow--;
    } else {
      PartyMapRow = LastMapCell;
    }
    break;
  }
  case DirEast:
  {
    if (PartyMapColumn < LastMapCell) {
      PartyMapColumn++;
    } else {
      PartyMapColumn = 0;
    }
    break;
  }
  case DirSouth:
  {
    if (PartyMapRow < LastMapCell) {
      PartyMapRow++;
    } else {
      PartyMapRow = 0;
    }
    break;
  }
  case DirWest:
  {
    if (PartyMapColumn > 0) {
      PartyMapColumn--;
    } else {
      PartyMapColumn = LastMapCell;
    }
    break;
  }
  }
  PartyCellEventByte = EventByteAt(PartyMapColumn, PartyMapRow);
  PartyCellWallId = WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
}

/* ovl07:1A6F. SetupDuel: starts a duel (DuelMode 1, word $2E6 of GameVars2 := WithCopy): every party
     member other than the selected character (by name) gets Flag10D 0; when WithCopy is nonzero,
     loads the CPIC combat icon into slot EncounterIconSlot and appends to the party a copy of the selected
     character named 'ROLF', computer-run on the other side (Side 1, Quick 1, B84 $B2), with that
     icon, no affects and a copy of every item. */
void SetupDuel(s8 WithCopy)
{
  POOL_TRACE("SetupDuel");
  PCharacter Member = 0;
  PCharacter Copy_ = 0;
  PCharacter Original = 0;
  PItem Item = 0;
  PItem Rest = 0;
  farptr Unused = 0;
  DuelMode = 1;
  (*FPD(TGameVars (*), GameVars2))[742] = WithCopy;
  Original = SelectedCharacter;
  Member = PartyListHead;
  while (Member != 0) {
    if (rtl_str_cmp((*FPD(TCharacter (*), Member)).Name, (*FPD(TCharacter (*), Original)).Name) != 0) {
      (*FPD(TCharacter (*), Member)).Flag10D = 0;
    }
    Member = (*FPD(TCharacter (*), Member)).Next;
  }
  if (WithCopy != 0) {
    LoadPictureSlot(S("\004CPIC"), 0xB, EncounterIconSlot);
    Member = PartyListHead;
    while ((*FPD(TCharacter (*), Member)).Next != 0) {
      Member = (*FPD(TCharacter (*), Member)).Next;
    }
    Copy_ = rtl_getmem(285);
    (*FPD(TCharacter (*), Copy_)) = (*FPD(TCharacter (*), Original));
    (*FPD(TCharacter (*), Copy_)).Flag10D = 1;
    (*FPD(TCharacter (*), Copy_)).Next = 0;
    rtl_str_assign((*FPD(TCharacter (*), Copy_)).Name, 15, S("\004ROLF"));
    (*FPD(TCharacter (*), Copy_)).Quick = 1;
    (*FPD(TCharacter (*), Copy_)).Side = 1;
    (*FPD(TCharacter (*), Copy_)).B84 = 0xB2;
    (*FPD(TCharacter (*), Copy_)).CombatIcon = EncounterIconSlot;
    (*FPD(TCharacter (*), Copy_)).Affects = 0;
    (*FPD(TCharacter (*), Copy_)).Items = 0;
    (*FPD(TCharacter (*), Member)).Next = Copy_;
    Member = (*FPD(TCharacter (*), Member)).Next;
    Item = (*FPD(TCharacter (*), Original)).Items;
    while (Item != 0) {
      if ((*FPD(TCharacter (*), Member)).Items == 0) {
        (*FPD(TCharacter (*), Member)).Items = rtl_getmem(63);
        (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Member)).Items)) = (*FPD(TMenuLine (*), Item));
        (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Member)).Items)).Next = 0;
      } else {
        Rest = (*FPD(TCharacter (*), Member)).Items;
        (*FPD(TCharacter (*), Member)).Items = rtl_getmem(63);
        (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Member)).Items)) = (*FPD(TMenuLine (*), Item));
        (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Member)).Items)).Next = Rest;
      }
      Item = (*FPD(TMenuLine (*), Item)).Next;
    }
  }
}

/* ovl07:1CC3. ScaleMoney: multiplies each of Who's seven money amounts by Factor (Real),
     truncated. */
void ScaleMoney(double Factor, PCharacter Who)
{
  POOL_TRACE("ScaleMoney");
  (*FPD(TCharacter (*), Who)).Money[0] = rtl_trunc(((double)(*FPD(TCharacter (*), Who)).Money[0] * Factor));
  (*FPD(TCharacter (*), Who)).Money[1] = rtl_trunc(((double)(*FPD(TCharacter (*), Who)).Money[1] * Factor));
  (*FPD(TCharacter (*), Who)).Money[2] = rtl_trunc(((double)(*FPD(TCharacter (*), Who)).Money[2] * Factor));
  (*FPD(TCharacter (*), Who)).Money[3] = rtl_trunc(((double)(*FPD(TCharacter (*), Who)).Money[3] * Factor));
  (*FPD(TCharacter (*), Who)).Money[4] = rtl_trunc(((double)(*FPD(TCharacter (*), Who)).Money[4] * Factor));
  (*FPD(TCharacter (*), Who)).Money[5] = rtl_trunc(((double)(*FPD(TCharacter (*), Who)).Money[5] * Factor));
  (*FPD(TCharacter (*), Who)).Money[6] = rtl_trunc(((double)(*FPD(TCharacter (*), Who)).Money[6] * Factor));
}

/* ovl07:1DF0. LoseItems: for each item Who carries, rolls d100 and hands the item to
     RemoveInventoryItem when the roll is at most Chance. Chance is lowered for good before each roll by
     90 for an item heavier than 255 and by 50 for one heavier than 24 (not below 0), so the lighter
     items after a heavy one keep the lower chance. */
void LoseItems(u8 Chance, PCharacter Who)
{
  POOL_TRACE("LoseItems");
  u8 Roll = 0;
  PItem Item = 0;
  PItem NextItem = 0;
  Item = (*FPD(TCharacter (*), Who)).Items;
  while (Item != 0) {
    if ((*FPD(TMenuLine (*), Item)).Weight > 0xFF) {
      if (Chance > 0x5A) {
        Chance = Chance - 0x5A;
      } else {
        Chance = 0;
      }
    } else if ((*FPD(TMenuLine (*), Item)).Weight > 0x18) {
      if (Chance > 0x32) {
        Chance = Chance - 0x32;
      } else {
        Chance = 0;
      }
    }
    Roll = RollDice(1, 100);
    NextItem = (*FPD(TMenuLine (*), Item)).Next;
    if (Roll <= Chance) {
      RemoveInventoryItem(Who, Item);
    }
    Item = NextItem;
  }
}

/* ovl07:1EA6. SkipCommand: steps EclPC over the script command at EclPC without running it: reads
     its opcode (into CurrentOpcode) and decodes the number of operands that opcode takes (DecodeOperands);
     an opcode without operands is one byte. */
void SkipCommand(void)
{
  POOL_TRACE("SkipCommand");
  CurrentOpcode = (*FPD(TEclCode (*), EclCode))[EclPC - 39168];
  switch (CurrentOpcode) {
  case 1:
  case 2:
  case 0xA:
  case 0xE:
  case 0x11:
  case 0x12:
  case 0x1D:
  case 0x20:
  case 0x2D:
  case 0x32:
  case 0x34:
  case 0x36:
  case 0x38:
  case 0x39:
  case 0x3C:
  {
    DecodeOperands(1);
    break;
  }
  case 3:
  case 8:
  case 9:
  case 0xC:
  case 0xF:
  case 0x10:
  case 0x1F:
  case 0x22:
  {
    DecodeOperands(2);
    break;
  }
  case 4:
  case 5:
  case 6:
  case 7:
  case 0xB:
  case 0x21:
  case 0x28:
  case 0x2A:
  case 0x2F:
  case 0x30:
  case 0x35:
  case 0x37:
  case 0x3B:
  {
    DecodeOperands(3);
    break;
  }
  case 0x14:
  case 0x23:
  {
    DecodeOperands(4);
    break;
  }
  case 0x2E:
  {
    DecodeOperands(5);
    break;
  }
  case 0x1E:
  case 0x2C:
  {
    DecodeOperands(6);
    break;
  }
  case 0x27:
  {
    DecodeOperands(8);
    break;
  }
  case 0x29:
  {
    DecodeOperands(14);
    break;
  }
  default:
  {
    EclPC++;
  }
  }
}

/* ovl07:1FB1. MovementRange: the highest and lowest Movement of the party members (PartyListHead),
     each doubled by affect $27 or else halved by affect $2A (HasAffect). */
void MovementRange(u8 (*Fastest), u8 (*Slowest))
{
  POOL_TRACE("MovementRange");
  PCharacter Member = 0;
  farptr Affect = 0;
  u8 Value = 0;
  Member = PartyListHead;
  (*Fastest) = (*FPD(TCharacter (*), Member)).Movement;
  (*Slowest) = (*FPD(TCharacter (*), Member)).Movement;
  while (Member != 0) {
    Value = (*FPD(TCharacter (*), Member)).Movement;
    if (HasAffect(Member, 0x27, &Affect)) {
      Value = Value << 1;
    } else if (HasAffect(Member, 0x2A, &Affect)) {
      Value = (s16)((u16)Value >> 1);
    }
    if (Value > (*Fastest)) {
      (*Fastest) = Value;
    }
    if (Value < (*Slowest)) {
      (*Slowest) = Value;
    }
    Member = (*FPD(TCharacter (*), Member)).Next;
  }
}

/* ovl07:20CC. DamageWithMessage: unless Who is already dead (Status 6), shows '<name> dies.' when
     Damage is more than its hit points (HpCurrent) plus 10, else '<name> is hit FOR <n> points of
     Damage.' in the text window (rows $11..$16, starting a new page with a 'press <enter>' prompt
     when the window is full), applies the damage (ApplyDamage), clears the window and redraws
     the selected character. */
void DamageWithMessage(u16 Damage, PCharacter Who)
{
  POOL_TRACE("DamageWithMessage");
  u8 Unused = 0;
  u8 Text[256] = {0};
  u8 Num[4] = {0};
  u8 ClearFirst = 0;
  u8 ts1[51];
  if ((*FPD(TCharacter (*), Who)).Status == StatusDead) {
    return;
  }
  ClearFirst = 0;
  rtl_str_int(Num, 3, Damage, 0);
  if ((s16)((*FPD(TCharacter (*), Who)).HpCurrent + 10) < Damage) {
    rtl_str_assign(Text, 255, rtl_str_cat(ts1, 3, (const u8 *const[]){S("\002  "), (*FPD(TCharacter (*), Who)).Name, S("\007 dies. ")}));
  } else {
    rtl_str_assign(Text, 255, rtl_str_cat(ts1, 5, (const u8 *const[]){S("\002  "), (*FPD(TCharacter (*), Who)).Name, S("\014 is hit FOR "), Num, S("\022 points of Damage.")}));
  }
  if (GlyphRow > 0x16) {
    GlyphRow = 0x11;
    ClearFirst = 1;
    ShowMessageLine(0xF, S("\"press <enter>/<return> to continue"));
  } else {
    ClearFirst = 0;
  }
  GlyphCol = 0x26;
  ShowPagedText(1, 0x11, 0x26, 0x16, 0xF, ClearFirst, Text);
  ApplyDamage(Who, Damage);
  ClearRect(0x11, 1, 0x26, 0xF);
  DrawPartyRoster(SelectedCharacter);
}

/* Initialisation part of unit OVL07. */
void init_OVL07(void)
{
  POOL_TRACE("init");
}
