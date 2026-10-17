#include "game.h"

/* ovl14:0000. Clears the icon set's bit pair in the event byte of the area-map cell
     (Col, Row): bits 6-7 for icon 6, 4-5 for 4, 2-3 for 2, 0-1 for 0. Called by DoWildernessMenu
     on the Exit path with the party cell and icon set. */
void ClearIconBits(s8 Col, s8 Row, s8 Icon)
{
  POOL_TRACE("ClearIconBits");
  switch (Icon) {
  case 6:
  {
    (*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] = ((*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] & 0x3F);
    break;
  }
  case 4:
  {
    (*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] = ((*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] & 0xCF);
    break;
  }
  case 2:
  {
    (*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] = ((*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] & 0xF3);
    break;
  }
  case 0:
  {
    (*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] = ((*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] & 0xFC);
    break;
  }
  }
}

/* ovl14:0109. Sets the icon set's bit in the map cell byte (Col, Row): bit 6 for icon 6,
     4 for 4, 2 for 2, 0 for 0, clearing the pair's other bit; out-of-map cells do
     nothing. The counterpart of ClearIconBits. Called by the Bash and Pick commands. */
void SetIconBits(s8 Col, s8 Row, s8 Icon)
{
  POOL_TRACE("SetIconBits");
  if (((((Col < 0)) || ((Col > 0xF))) || ((Row < 0))) || ((Row > 0xF))) {
  } else {
    switch (Icon) {
    case 6:
    {
      (*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] = (((*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] & 0x3F) | 0x40);
      break;
    }
    case 4:
    {
      (*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] = (((*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] & 0xCF) | 0x10);
      break;
    }
    case 2:
    {
      (*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] = (((*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] & 0xF3) | 0x4);
      break;
    }
    case 0:
    {
      (*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] = (((*FPD(TGeoCellBlock (*), GeoCells)).Cells[Row][Col] & 0xFC) | 0x1);
      break;
    }
    }
  }
}

/* ovl14:0236. Returns 1 when any character of the PartyListHead list has a class level above 0 in
     ClassLevels[Which] (+$96+Which), else 0. The Bash/Pick/Knock menu (DoWildernessMenu) offers Pick when flag 6 is
     found and Knock when flag 5 is found. */
u8 AnyMemberHasClassLevel(s8 Which)
{
  POOL_TRACE("AnyMemberHasClassLevel");
  u8 Result = 0;
  PCharacter Rec = 0;
  u8 Found = 0;
  Found = 0;
  Rec = PartyListHead;
  while (((Rec != 0)) && ((Found == 0))) {
    if ((*FPD(TCharacter (*), Rec)).ClassLevels[Which] > 0) {
      Found = 1;
    }
    Rec = (*FPD(TCharacter (*), Rec)).Next;
  }
  Result = Found;
  return Result;
}

/* ovl14:0294. The Bash command (the B key): walks the PartyListHead records and tries to force
     the first one whose lock answers the DoorKindAt cell test with 3 (or another value,
     below): each lock type wants its own 1d6/1d8 roll (RollDice), setting Done on success
     and clearing DoorMenuFlags[0] on some failures. On success it sets the icon bits like Pick
     and returns 1, else 0. */
u8 DoBash(void)
{
  POOL_TRACE("DoBash");
  u8 Result = 0;
  PCharacter Rec = 0;
  u8 Done = 0;
  Done = 0;
  Rec = PartyListHead;
  while (((Rec != 0)) && ((Done == 0))) {
    {
      TCharacter *w1 = &(*FPD(TCharacter (*), Rec));
        if (DoorKindAt(PartyMapColumn, PartyMapRow, PartyFacing) == 3) {
          switch (w1->Strength) {
          case 0x12:
          {
            switch (w1->StrengthPercent) {
            case 91:
            case 92:
            case 93:
            case 94:
            case 95:
            case 96:
            case 97:
            case 98:
            case 99:
            {
              if (RollDice(1, 6) == 1) {
                Done = 1;
              }
              break;
            }
            case 0x64:
            {
              if (RollDice(1, 6) <= 2) {
                Done = 1;
              }
              break;
            }
            default:
            {
              DoorMenuFlags[0] = 0;
            }
            }
            break;
          }
          case 0x13:
          case 0x14:
          {
            if (RollDice(1, 6) <= 3) {
              Done = 1;
            }
            break;
          }
          case 0x15:
          case 0x16:
          {
            if (RollDice(1, 6) <= 4) {
              Done = 1;
            }
            break;
          }
          case 0x17:
          {
            if (RollDice(1, 6) <= 5) {
              Done = 1;
            }
            break;
          }
          case 0x18:
          {
            if (RollDice(1, 8) <= 7) {
              Done = 1;
            }
            break;
          }
          case 0x19:
          {
            Done = 1;
            break;
          }
          default:
          {
            DoorMenuFlags[0] = 0;
          }
          }
        } else {
          switch (w1->Strength) {
          case 3:
          case 4:
          case 5:
          case 6:
          case 7:
          {
            if (RollDice(1, 6) == 1) {
              Done = 1;
            }
            break;
          }
          case 8:
          case 9:
          case 10:
          case 11:
          case 12:
          case 13:
          case 14:
          case 15:
          {
            if (RollDice(1, 6) <= 2) {
              Done = 1;
            }
            break;
          }
          case 16:
          case 17:
          {
            if (RollDice(1, 6) <= 3) {
              Done = 1;
            }
            break;
          }
          case 0x12:
          {
            switch (w1->StrengthPercent) {
            case 0:
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
            {
              if (RollDice(1, 6) <= 3) {
                Done = 1;
              }
              break;
            }
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
            case 91:
            case 92:
            case 93:
            case 94:
            case 95:
            case 96:
            case 97:
            case 98:
            case 99:
            {
              if (RollDice(1, 6) <= 4) {
                Done = 1;
              }
              break;
            }
            case 0x64:
            {
              if (RollDice(1, 6) <= 5) {
                Done = 1;
              }
              break;
            }
            }
            break;
          }
          }
        }
    }
    Rec = (*FPD(TCharacter (*), Rec)).Next;
  }
  if (Done != 0) {
    SetIconBits(PartyMapColumn, PartyMapRow, PartyFacing);
    SetIconBits((s16)(PartyMapColumn + DirStepX[PartyFacing]), (s16)(PartyMapRow + DirStepY[PartyFacing]), (((s16)(PartyFacing + 4)) % 8));
  }
  Result = Done;
  return Result;
}

/* ovl14:04DF. The Pick command (the P key): rolls 1d100 (RollDice) against each
     PartyListHead record's +$78 byte and requires its +$10C byte clear; on the first success it
     sets the icon bits at the party cell and ahead of it (the facing cell uses the icon
     set +4 mod 8), clears the DoorMenuFlags[1] menu flag, and returns 1, else 0. */
u8 DoPick(void)
{
  POOL_TRACE("DoPick");
  u8 Result = 0;
  PCharacter Rec = 0;
  u8 Done = 0;
  Done = 0;
  Rec = PartyListHead;
  while (((Rec != 0)) && ((Done == 0))) {
    {
      TCharacter *w1 = &(*FPD(TCharacter (*), Rec));
        if (RollDice(1, 0x64) <= w1->ThiefSkills[1]) {
          if (w1->Status == 0) {
            Done = 1;
          }
        }
    }
    Rec = (*FPD(TCharacter (*), Rec)).Next;
  }
  DoorMenuFlags[1] = 0;
  if (Done != 0) {
    SetIconBits(PartyMapColumn, PartyMapRow, PartyFacing);
    SetIconBits((s16)(PartyMapColumn + DirStepX[PartyFacing]), (s16)(PartyMapRow + DirStepY[PartyFacing]), (((s16)(PartyFacing + 4)) % 8));
  }
  Result = Done;
  return Result;
}

/* ovl14:05AB. Scans the 21 memorized spell slots (Spells, +$17) of Rec for the spell Code: returns the slot index, or $FF
     when no slot holds it. */
u8 FindSpellSlot(u8 Code, PCharacter Rec)
{
  POOL_TRACE("FindSpellSlot");
  u8 Result = 0;
  u8 Slot = 0;
  Slot = 0;
  while (((Slot <= 0x14)) && (((*FPD(TCharacter (*), Rec)).Spells[Slot] != Code))) {
    Slot++;
  }
  if (Slot <= 0x14) {
    Result = Slot;
  } else {
    Result = 0xFF;
  }
  return Result;
}

/* ovl14:05EE. Returns the first character of the PartyListHead list that has the spell Code memorized,
     or nil when none does. */
PCharacter FindMemberWithSpell(u8 Code)
{
  POOL_TRACE("FindMemberWithSpell");
  PCharacter Result = 0;
  PCharacter Rec = 0;
  Rec = PartyListHead;
  while (((Rec != 0)) && ((FindSpellSlot(Code, Rec) == 0xFF))) {
    Rec = (*FPD(TCharacter (*), Rec)).Next;
  }
  Result = Rec;
  return Result;
}

/* ovl14:0648. The Knock command (the K key): clears the KnockSpell slot of the first
     record holding it and returns True, or returns False when no record holds it. */
u8 DoKnock(void)
{
  POOL_TRACE("DoKnock");
  u8 Result = 0;
  PCharacter Rec = 0;
  Rec = FindMemberWithSpell(KnockSpell);
  if (Rec != 0) {
    (*FPD(TCharacter (*), Rec)).Spells[FindSpellSlot(KnockSpell, Rec)] = 0;
    Result = 1;
  } else {
    Result = 0;
  }
  return Result;
}

/* ovl14:068D. Steps the party one cell in the current icon set's direction when
     DoorKindAt allows it, clamping the result into the 16x16 area map: each clamped
     coordinate is written back and the edge flag GameVars2^[725] (+$5AA) is set. Called
     by the movement driver HandleWildernessKeys. The direction tables DirStepX/DirStepY are indexed
     by the icon set. */
void ClampPartyPosition(void)
{
  POOL_TRACE("ClampPartyPosition");
  s16 Col = 0;
  s16 Row = 0;
  s16 Icon = 0;
  Col = PartyMapColumn;
  Row = PartyMapRow;
  Icon = PartyFacing;
  (*FPD(TGameVars (*), GameVars2))[725] = 0;
  if (DoorKindAt(Col, Row, Icon) != 0) {
    Col += DirStepX[Icon];
    Row += DirStepY[Icon];
    if (Col > 0xF) {
      PartyMapColumn = 0xF;
      (*FPD(TGameVars (*), GameVars2))[725] = 1;
    }
    if (Col < 0) {
      PartyMapColumn = 0;
      (*FPD(TGameVars (*), GameVars2))[725] = 1;
    }
    if (Row > 0xF) {
      PartyMapRow = 0xF;
      (*FPD(TGameVars (*), GameVars2))[725] = 1;
    }
    if (Row < 0) {
      PartyMapRow = 0;
      (*FPD(TGameVars (*), GameVars2))[725] = 1;
    }
  }
}

/* ovl14:073B. Moves the party one cell in the current icon set's direction, wrapping
     the 16x16 area map ($F steps to 0, 0 steps to $F), then refreshes the cell bytes
     PartyCellWallId (through WallIdAt) and PartyCellEventByte (through EventByteAt), resets the DoorMenuFlags..DoorMenuFlags[2]
     menu flags to 1, and steps
     the sound through AdvanceGameClock (mode 2 when GameVars2^[714] has bit 0, else mode 1).
     Called by DoWildernessMenu. */
void MoveParty(void)
{
  POOL_TRACE("MoveParty");
  PlaySound(SoundStep);
  PartyMapColumn += DirStepX[PartyFacing];
  PartyMapRow += DirStepY[PartyFacing];
  if (PartyMapColumn < 0) {
    PartyMapColumn = 0xF;
  }
  if (PartyMapColumn > 0xF) {
    PartyMapColumn = 0;
  }
  if (PartyMapRow < 0) {
    PartyMapRow = 0xF;
  }
  if (PartyMapRow > 0xF) {
    PartyMapRow = 0;
  }
  PartyCellWallId = WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
  rtl_FillChar((void *)&DoorMenuFlags, 3, 1);
  PartyCellEventByte = EventByteAt(PartyMapColumn, PartyMapRow);
  if (((*FPD(TGameVars (*), GameVars2))[714] & 1) > 0) {
    AdvanceGameClock(1, 2);
  } else {
    AdvanceGameClock(1, 1);
  }
}

/* ovl14:0818. Checks the area-map block ahead of the party: steps the GameVars area-map
     position by the icon set's direction, clamps it (columns 0..$F, rows 0..$23), and
     reads that cell of AreaMap. N ($4E) and the impassable ranges pass through silently;
     the river codes ($66..$6C, $72) either print the stench message (when GameVars^[VarRiverGate]
     is 0) or move there; anything else moves there with a sound. Called by DoWildernessMenu. */
void CheckMapCell(void)
{
  POOL_TRACE("CheckMapCell");
  s8 MapCol = 0;
  s8 GridCol = 0;
  s8 GridRow = 0;
  GridCol = (*FPD(TGameVars (*), GameVars))[195] + DirStepX[PartyFacing];
  GridRow = (*FPD(TGameVars (*), GameVars))[196] + DirStepY[PartyFacing];
  if (GridCol < 0) {
    GridCol = 0;
  }
  if (GridCol > 0xF) {
    GridCol = 0xF;
  }
  if (GridRow < 0) {
    GridRow = 0;
  }
  if (GridRow > 0x23) {
    GridRow = 0x23;
  }
  MapCol = GridCol + MapBaseX[AreaViewKind];
  switch (AreaMap[GridRow][MapCol]) {
  case 0x4E:
  case 126:
  case 127:
  case 128:
  case 130:
  case 131:
  case 132:
  case 168:
  case 169:
  case 170:
  case 171:
  case 172:
  case 174:
  case 175:
  case 176:
  case 177:
  case 178:
  case 179:
  case 0xBC:
  case 221:
  case 222:
  case 225:
  case 226:
  case 227:
  case 228:
  case 229:
  case 230:
  case 231:
  case 232:
  case 233:
  case 0xF5:
  {
    break;
  }
  case 102:
  case 103:
  case 104:
  case 105:
  case 106:
  case 107:
  case 108:
  case 0x72:
  {
    if ((*FPD(TGameVars (*), GameVars))[418] == 0) {
      FlashMessageLine(S("#The river's stench drives you back."), 0xE);
    } else {
      (*FPD(TGameVars (*), GameVars))[195] = GridCol;
      (*FPD(TGameVars (*), GameVars))[196] = GridRow;
      AdvanceGameClock(0xC, 3);
    }
    break;
  }
  default:
  {
    (*FPD(TGameVars (*), GameVars))[195] = GridCol;
    (*FPD(TGameVars (*), GameVars))[196] = GridRow;
    AdvanceGameClock(0xC, 3);
  }
  }
}

/* ovl14:0989. The wilderness key driver (called by RunWilderness (ovl03:32F8)): in the 3D view it
     reads menu and movement keys through ReadPromptChoice and dispatches them (A/C/V/E/S/L
     menu keys, H/M/P/K movement with the icon sets, anything else through UpdateSelectedCharacter),
     otherwise it loads the ICON pictures for map pages 2..4 and runs a smaller key loop;
     either loop repeats through DrawLocationLine until Redraw is set, then it tidies the
     window and returns the key. Also clears GameVars2^[713] on entry. */
u8 HandleWildernessKeys(void)
{
  POOL_TRACE("HandleWildernessKeys");
  u8 Result = 0;
  u8 Redraw = 0;
  u8 Key = 0;
  u8 KeyFlag = 0;
  u8 SpareBuf[41] = {0};
  u8 ViewFlag = 0;
  s32 SpareLong = 0;
  (*FPD(TGameVars (*), GameVars2))[713] = 0;
  switch (AreaViewKind) {
  case 1:
  {
    Redraw = 0;
    do {
      Key = ReadPromptChoice(S("\000"), WildernessPromptWithArea, 0xD, 0xA, 0xF, 1, 0, &KeyFlag);
      if (KeyFlag == 0) {
        switch ((u8)Key) {
        case 'A':
        {
          if ((*FPD(TGameVars (*), GameVars))[251] == 0) {
            WallMapMode = (WallMapMode == 0);
            DrawWallView(PartyMapColumn, PartyMapRow, PartyFacing);
          } else {
            FlashMessageLine(S("\010Not Here"), 0xE);
          }
          break;
        }
        case 'C':
        {
          if ((*FPD(TCharacter (*), SelectedCharacter)).Status == 0) {
            CastSpells();
          }
          break;
        }
        case 'V':
        {
          ViewSelectedCharacter(&ViewFlag);
          break;
        }
        case 'E':
        {
          Redraw = 1;
          break;
        }
        case 'S':
        {
          (*FPD(TGameVars (*), GameVars2))[714] = ((*FPD(TGameVars (*), GameVars2))[714] ^ 1);
          break;
        }
        case 'L':
        {
          (*FPD(TGameVars (*), GameVars2))[714] = ((*FPD(TGameVars (*), GameVars2))[714] | 2);
          AdvanceGameClock(1, 2);
          EclPC = EclSearchEntry;
          Redraw = 1;
          break;
        }
        }
      } else {
        switch ((u8)Key) {
        case 'H':
        {
          ClampPartyPosition();
          Redraw = 1;
          break;
        }
        case 'P':
        {
          PartyFacing = (((s16)(PartyFacing + 4)) % 8);
          PartyCellWallId = WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
          DrawWallView(PartyMapColumn, PartyMapRow, PartyFacing);
          break;
        }
        case 'K':
        {
          PartyFacing = (((s16)(PartyFacing + 6)) % 8);
          PlaySound(SoundStep);
          PartyCellWallId = WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
          DrawWallView(PartyMapColumn, PartyMapRow, PartyFacing);
          break;
        }
        case 'M':
        {
          PartyFacing = (((s16)(PartyFacing + 2)) % 8);
          PlaySound(SoundStep);
          PartyCellWallId = WallIdAt(PartyMapColumn, PartyMapRow, PartyFacing);
          DrawWallView(PartyMapColumn, PartyMapRow, PartyFacing);
          break;
        }
        default:
        {
          UpdateSelectedCharacter(Key);
          DrawPartyRoster(SelectedCharacter);
        }
        }
      }
      DrawLocationLine();
    } while (!(Redraw != 0));
    break;
  }
  case 2:
  case 3:
  case 4:
  {
    if (PreviousAreaViewKind < 2) {
      LoadPictureSlot(S("\004ICON"), 0, 9);
      LoadPictureSlot(S("\004ICON"), 1, 0xA);
      LoadPictureSlot(S("\004ICON"), 2, 0xB);
      DrawWildernessScreen();
    }
    Redraw = 0;
    do {
      Key = ReadPromptChoice(S("\000"), WildernessPromptNoArea, 0xD, 0xA, 0xF, 1, 0, &KeyFlag);
      if (KeyFlag == 0) {
        switch ((u8)Key) {
        case 'C':
        {
          CastSpells();
          break;
        }
        case 'V':
        {
          ViewSelectedCharacter(&ViewFlag);
          break;
        }
        case 'E':
        {
          Redraw = 1;
          break;
        }
        case 'S':
        {
          (*FPD(TGameVars (*), GameVars2))[714] = ((*FPD(TGameVars (*), GameVars2))[714] ^ 1);
          break;
        }
        case 'L':
        {
          (*FPD(TGameVars (*), GameVars2))[714] = ((*FPD(TGameVars (*), GameVars2))[714] | 2);
          AdvanceGameClock(1, 2);
          EclPC = EclSearchEntry;
          Redraw = 1;
          break;
        }
        }
      } else {
        Redraw = 1;
        switch ((u8)Key) {
        case 'H':
        {
          PartyFacing = 0;
          break;
        }
        case 'M':
        {
          PartyFacing = 2;
          break;
        }
        case 'P':
        {
          PartyFacing = 4;
          break;
        }
        case 'K':
        {
          PartyFacing = 6;
          break;
        }
        default:
        {
          UpdateSelectedCharacter(Key);
          DrawPartyRoster(SelectedCharacter);
          Redraw = 0;
        }
        }
      }
      DrawLocationLine();
    } while (!(Redraw != 0));
    break;
  }
  }
  PreviousAreaViewKind = AreaViewKind;
  if (EclWindowCleared == 0) {
    ClearWindow(1, 0x11, 0x26, 0x16);
    EclWindowCleared = 1;
  }
  Result = Key;
  return Result;
}

/* ovl14:0D6D. The wilderness command menu (called by RunWilderness (ovl03:32F8)): in the 3D view it
     builds the Bash/Pick/Knock/Exit menu from the DoorMenuFlags/DoorMenuFlags[1]/DoorMenuFlags[2] flags and the
     record flag checks, prompts through ReadPromptChoice and dispatches the key: in the DoorKindAt = 2
     arm 'B' calls DoBash, 'P' calls DoPick (ovl14:0ED6) and 'K' calls DoKnock, with Knock
     offered when FindMemberWithSpell($1F) finds a record (ovl14:0E14), while in the = 3 arm 'B'
     calls DoBash and 'K' calls DoKnock, with Knock offered when AnyMemberHasClassLevel(5) is set
     (ovl14:0F53), but 'P' only clears the Pick flag (mov DoorMenuFlags[1],0 at ovl14:1015, no DoPick
     call); on the map pages it steps the area map (CheckMapCell on pages 2..4);
     on success it moves the party (MoveParty), then always tidies the sprite banks. */
void DoWildernessMenu(void)
{
  POOL_TRACE("DoWildernessMenu");
  u8 Done = 0;
  u8 MenuFlag = 0;
  u8 Menu[41] = {0};
  u8 Key2 = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  u8 t5[256];
  u8 t6[256];
  Done = 0;
  switch (AreaViewKind) {
  case 1:
  {
    if ((*FPD(TGameVars (*), GameVars2))[713] < 0xFF) {
      switch (DoorKindAt(PartyMapColumn, PartyMapRow, PartyFacing)) {
      case 1:
      {
        Done = 1;
        break;
      }
      case 2:
      {
        Menu[0] = 0x00;
        if (DoorMenuFlags[0] != 0) {
          rtl_str_assign(Menu, 40, S("\004Bash"));
        }
        if (((DoorMenuFlags[1] != 0)) && ((AnyMemberHasClassLevel(6) != 0))) {
          rtl_str_assign(Menu, 40, rtl_str_cat(t1, 2, (const u8 *const[]){Menu, S("\005 Pick")}));
        }
        if (((DoorMenuFlags[2] != 0)) && ((FindMemberWithSpell(KnockSpell) != 0))) {
          rtl_str_assign(Menu, 40, rtl_str_cat(t2, 2, (const u8 *const[]){Menu, S("\006 Knock")}));
        }
        rtl_str_assign(Menu, 40, rtl_str_cat(t3, 2, (const u8 *const[]){Menu, S("\005 Exit")}));
        if (rtl_str_cmp(Menu, S("\005 Exit")) == 0) {
          ClearIconBits(PartyMapColumn, PartyMapRow, PartyFacing);
        } else {
          Key2 = ReadPromptChoice(S("\010Locked. "), Menu, 0xD, 0xA, 0xF, 0, 0, &MenuFlag);
          switch ((u8)Key2) {
          case 'B':
          {
            Done = DoBash();
            break;
          }
          case 'P':
          {
            Done = DoPick();
            break;
          }
          case 'K':
          {
            Done = DoKnock();
            break;
          }
          }
        }
        break;
      }
      case 3:
      {
        Menu[0] = 0x00;
        if (DoorMenuFlags[0] != 0) {
          rtl_str_assign(Menu, 40, S("\004Bash"));
        }
        if (((DoorMenuFlags[1] != 0)) && ((AnyMemberHasClassLevel(6) != 0))) {
          rtl_str_assign(Menu, 40, rtl_str_cat(t4, 2, (const u8 *const[]){Menu, S("\005 Pick")}));
        }
        if (((DoorMenuFlags[2] != 0)) && ((AnyMemberHasClassLevel(5) != 0))) {
          rtl_str_assign(Menu, 40, rtl_str_cat(t5, 2, (const u8 *const[]){Menu, S("\006 Knock")}));
        }
        rtl_str_assign(Menu, 40, rtl_str_cat(t6, 2, (const u8 *const[]){Menu, S("\005 Exit")}));
        if (rtl_str_cmp(Menu, S("\005 Exit")) == 0) {
          ClearIconBits(PartyMapColumn, PartyMapRow, PartyFacing);
        } else {
          Key2 = ReadPromptChoice(S("\010Locked. "), Menu, 0xD, 0xA, 0xF, 0, 0, &MenuFlag);
          switch ((u8)Key2) {
          case 'B':
          {
            Done = DoBash();
            break;
          }
          case 'P':
          {
            DoorMenuFlags[1] = 0;
            break;
          }
          case 'K':
          {
            Done = DoKnock();
            break;
          }
          }
        }
        break;
      }
      }
      if (Done != 0) {
        MoveParty();
      } else {
        PlaySound(SoundNoAction);
      }
      DrawLocationLine();
    } else {
      (*FPD(TGameVars (*), GameVars2))[713] = 0;
    }
    break;
  }
  case 2:
  case 3:
  case 4:
  {
    if ((*FPD(TGameVars (*), GameVars2))[713] < 0xFF) {
      CheckMapCell();
      DrawLocationLine();
    } else {
      (*FPD(TGameVars (*), GameVars2))[713] = 0;
    }
    break;
  }
  }
  FreeSpriteList(rtl_far(&PictureAnimation));
  ReleasePicture((void *)&HeadSpriteBank);
  ReleasePicture((void *)&BodySpriteBank);
  HeadBankIndex = 0xFF;
  BodyBankIndex = 0xFF;
}

/* Initialisation part of unit OVL14. */
void init_OVL14(void)
{
  POOL_TRACE("init");
  /* ovl14:10A7. The unit's initialisation part is empty: the compiler emits only `55 89 E5 5D CB`
     (push bp; mov bp, sp; pop bp; retf, the frame with no body), so the wilderness unit runs no code
     at start-up. */
}
