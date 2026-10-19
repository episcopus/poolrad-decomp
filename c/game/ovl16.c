#include "game.h"

/* ovl16:0000. Frees a character and everything it owns: its combat state (Combat, size $16), its
     carried items (the list at Items, size $3F) and its affects (the list at Affects, size 9), then
     the character record itself (size $11D). The last statement, `Who := nil`, is a dead store: Who
     is a by-value parameter, so it only clears this routine's own copy and no caller's pointer
     changes (RemoveSelectedCharacter reassigns SelectedCharacter itself right after the call).
     QUIRK ovl16:00D4: the by-value `Who := nil` stores nil into the callee's own parameter copy and
     does not clear the caller's pointer. */
void FreeCharacter(PCharacter Who)
{
  POOL_TRACE("FreeCharacter");
  PItem CurItem = 0;
  PItem NextItem = 0;
  PAffect CurAffect = 0;
  PAffect NextAffect = 0;
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), Who));
      if (w1->Combat != 0) {
        rtl_freemem(w1->Combat, CombatRecordSize);
      }
      NextItem = w1->Items;
      while (NextItem != 0) {
        CurItem = NextItem;
        NextItem = (*FPD(TMenuLine (*), NextItem)).Next;
        rtl_freemem(CurItem, ItemListSize);
      }
      NextAffect = w1->Affects;
      while (NextAffect != 0) {
        CurAffect = NextAffect;
        NextAffect = (*FPD(TAffect (*), NextAffect)).Next;
        rtl_freemem(CurAffect, AffectRecordSize);
      }
  }
  rtl_freemem(Who, CharacterSize);
  Who = 0;
}

/* ovl16:0161. The main menu of the character-creation / training hall (called by ovl03:2E10). It
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
     (AskYesNo, then save and QuitGame), J the STING cheat (only when the game was started with the argument STING:
     ParamStr(1) = 'STING'). An extended key G or O selects another
     party member (UpdateSelectedCharacter); every other key (all except E and S) clears the heap
     retry gate HeapErrorStop, and E and S leave it alone: the E path's SaveGame retry loop reads HeapErrorStop to
     end the retry (POOLVARS). Mode (4) is the value stored in the view mode ViewMode on B. Local at
     [bp-5] is unused; the frame needs its 9 bytes. */
void RunCharacterMenu(void)
{
  POOL_TRACE("RunCharacterMenu");
  u8 I = 0;
  u8 Key = 0;
  u8 ExtKey = 0;
  u8 Done = 0;
  u8 Unused[9] = {0};
  s8 Row = 0;
  u8 Show = 0;
  u8 Mode = 0;
  u8 ts1[256];
  TileSet = 3;
  Mode = 4;
  Show = 1;
  StingCheat = 0;
  ViewMode = 0;
  while (1) {
    if (Show != 0) {
      DrawWindow(MenuLeft, MenuTop, MenuRight, MenuBottom, 0, 0, S("\000"));
      if (SelectedCharacter != 0) {
        DrawPartyRoster(SelectedCharacter);
        CharacterMenuSlots[1].Present = 1;
        CharacterMenuSlots[2].Present = 1;
        if ((((*FPD(TGameVars (*), GameVars2))[680] > 0)) || ((StingCheat != 0))) {
          CharacterMenuSlots[3].Present = 1;
        }
        CharacterMenuSlots[4].Present = 1;
        CharacterMenuSlots[6].Present = 1;
        CharacterMenuSlots[7].Present = 0;
        CharacterMenuSlots[8].Present = 1;
        CharacterMenuSlots[9].Present = 1;
      } else {
        CharacterMenuSlots[1].Present = 0;
        CharacterMenuSlots[2].Present = 0;
        CharacterMenuSlots[3].Present = 0;
        CharacterMenuSlots[4].Present = 0;
        CharacterMenuSlots[6].Present = 0;
        CharacterMenuSlots[7].Present = 1;
        CharacterMenuSlots[8].Present = 0;
        CharacterMenuSlots[9].Present = 0;
      }
      Row = 0;
      {
        if (0 <= 10) {
          I = 0;
          for (;;) {
              if (CharacterMenuSlots[I].Present != 0) {
                DrawTextAt(2, (s16)(Row + MenuFirstRow), HotKeyColor, rtl_str_char(ts1, CharacterMenuSlots[I].Name[1]));
                DrawTextAt(3, (s16)(Row + MenuFirstRow), NameColor, rtl_str_copy(ts1, CharacterMenuSlots[I].Name, 2, (s16)(CharacterMenuSlots[I].Name[0] - 1)));
                Row++;
              }
            if (I == 10) break;
            I++;
          }
        }
      }
      Show = 0;
    }
    Key = ReadPromptChoice(S("\022Choose a function "), CharacterMenuHotkeys, ChoiceTitleColor, 0, 0, 1, 0, &ExtKey);
    ClearPromptLine();
    if (ExtKey != 0) {
      if (Key == 'G' || Key == 'O') {
        UpdateSelectedCharacter(Key);
        DrawPartyRoster(SelectedCharacter);
      }
    } else {
      if (!((Key == 'E' || Key == 'S'))) {
        HeapErrorStop = 0;
      }
      switch ((u8)Key) {
      case 'C':
      {
        if (CharacterMenuSlots[0].Present != 0) {
          CreateCharacter();
        }
        break;
      }
      case 'D':
      {
        if (CharacterMenuSlots[1].Present != 0) {
          DropCharacter();
        }
        break;
      }
      case 'M':
      {
        if (CharacterMenuSlots[2].Present != 0) {
          ModifyCharacter();
        }
        break;
      }
      case 'T':
      {
        if (CharacterMenuSlots[3].Present != 0) {
          TrainCharacter();
        }
        break;
      }
      case 'V':
      {
        if (CharacterMenuSlots[4].Present != 0) {
          ViewSelectedCharacter(&Done);
        }
        break;
      }
      case 'A':
      {
        if (CharacterMenuSlots[5].Present != 0) {
          AddSavedCharacters();
        }
        break;
      }
      case 'R':
      {
        if (CharacterMenuSlots[6].Present != 0) {
          if (SelectedCharacter != 0) {
            SaveCharacter(SelectedCharacter, S("\000"));
            RemoveSelectedCharacter(0, 1);
          }
        }
        break;
      }
      case 'L':
      {
        if (CharacterMenuSlots[7].Present != 0) {
          LoadGame();
          if (ViewMode != 0) {
            SkipAreaScriptLoad = 1;
            return;
          }
        }
        break;
      }
      case 'S':
      {
        if (CharacterMenuSlots[8].Present != 0) {
          if (PartyListHead != 0) {
            SaveGame();
          }
        }
        break;
      }
      case 'B':
      {
        if (CharacterMenuSlots[9].Present != 0) {
          if (PartyListHead != 0) {
            ViewMode = Mode;
            ClearPromptLine();
            return;
          }
        }
        break;
      }
      case 'E':
      {
        if (CharacterMenuSlots[10].Present != 0) {
          Key = AskYesNo(S("\014Quit to DOS "), 0xE, 0xA, 0xF);
          if (Key == 'Y') {
            while ((!HeapErrorStop) && ((PartyListHead != 0))) {
              SaveGame();
            }
            QuitGame();
          }
        }
        break;
      }
      case 'J':
      {
        if (rtl_str_cmp(rtl_paramstr(ts1, 1), S("\005STING")) == 0) {
          StingCheat = 1;
          ShowFlashMessage(S("\027I Understand, master..."));
        }
        break;
      }
      }
      Show = 1;
    }
  }
}

/* ovl16:056C. The C (Create) function of the training hall, called by RunCharacterMenu (ovl16:0161). It
     builds a new party member and saves it. The record is allocated (GetMem and FillChar, 285 bytes)
     with its starting values: the six figure colour pairs from FigureColorSlots, armour class value 50 (AC 10), a to-hit base of
     40 that the class levels then replace (see Thac0),
     Flag10D set (it takes part in combat and earns experience), picture banks 1 and 1 and a random RandomTag.
     Four list menus follow in the window (1,2)..($26,$16), each a ChooseFromList with the title line
     'Pick Race', 'Pick Gender', 'Pick Class' or 'Pick Alignment' and the choices indented by two
     blanks; Enter picks, Escape (#0) leaves the whole routine:
     - Race: Dwarf, Elf, Gnome, Half-Elf, Halfling and Human (RaceNames 1..5 and 7; menu line 6 is
       stored as race 7, so Half-Orc cannot be picked). The race sets the first Figure byte (1 for
       Dwarf, Gnome and Halfling, 2 otherwise) and gives permanent racial affects through AddAffect
       (Duration 0, Data $FF, Flag 0): Dwarf $5A $61 $1A $2F, Gnome $61 $12 $2F $30, Halfling $5A $61,
       Elf $6B, Half-Elf $7C, Human none.
     - Gender: Male or Female (SexNames), stored as the zero-based choice in Sex.
     - Class: the row of the race in RaceClassChoices lists the classes it may pick; the chosen ClassCombo gets
       level 1 in each class it combines (ClassLevels, a multi-class mask such as 8 Cleric/Fighter sets
       several), then ComputeThiefSkills for a thief, THAC0 (the highest ClassThac0Table entry), the
       item-usage ClassBits (ClassItemBits) and ComputeSavingThrows.
     - Alignment: the row of the class in ClassAlignmentChoices lists the alignments it may pick (Alignment).
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
     QUIRK ovl16:0FF3: the maximum-age rule has no case for ClassCombo $A (Cleric/Ranger); no race offers
     it, so its age would stay 0. */
void CreateCharacter(void)
{
  POOL_TRACE("CreateCharacter");
  PCharacter NewCharacter = 0;
  PCharacter SavedSelection = 0;
  PMenuLine MenuList = 0;
  PMenuLine PickedLine = 0;
  s16 Choice = 0;
  u8 I = 0;
  u8 RollAttempt = 0;
  u8 AbilityRoll = 0;
  u8 Key = 0;
  s8 RaceIndex = 0;
  s8 GenderIndex = 0;
  s8 ClassIndex = 0;
  u8 Spare1 = 0;
  s8 AbilityIndex = 0;
  u8 ChoiceCount = 0;
  s16 ConAdjustment = 0;
  u8 Spare2 = 0;
  u8 ClassTotal = 0;
  u8 GoldDiceTotal = 0;
  u8 WithExit = 0;
  u8 Redraw = 0;
  u8 ts1[256];
  NewCharacter = rtl_getmem(CharacterSize);
  rtl_FillChar((void *)&(*FPD(TCharacter (*), NewCharacter)), CharacterSize, 0);
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), NewCharacter));
      {
        if (1 <= CreateCharacter_StartFigureCount) {
          I = 1;
          for (;;) {
              w1->Figure[I] = FigureColorSlots[I] + (((s16)(FigureColorSlots[I] + 8)) * 16);
            if (I == CreateCharacter_StartFigureCount) break;
            I++;
          }
        }
      }
      w1->BaseArmourClassValue = CreateCharacter_StartResist;
      w1->Thac0 = CreateCharacter_StartThac0;
      w1->Status = 0;
      w1->Flag10D = 1;
      w1->HeadBank = 1;
      w1->BodyBank = 1;
      w1->CombatSize = 1;
      w1->RandomTag = rtl_Random(256);
  }
  NewMenuList(CreateCharacter_MenuRaceLines, &MenuList);
  (*FPD(TMenuLine (*), MenuList)).Flag29 = 1;
  rtl_str_assign((*FPD(TMenuLine (*), MenuList)).Text, 40, S("\011Pick Race"));
  {
    if (1 <= RaceHuman) {
      RaceIndex = 1;
      for (;;) {
          switch (RaceIndex) {
          case 1:
          case 2:
          case 3:
          case 4:
          case 5:
          {
            PickedLine = GetMenuLine(RaceIndex, MenuList);
            rtl_str_assign((*FPD(TMenuLine (*), PickedLine)).Text, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){S("\002  "), RaceNames[RaceIndex]}));
            break;
          }
          case RaceHuman:
          {
            PickedLine = GetMenuLine((s16)(RaceIndex - 1), MenuList);
            rtl_str_assign((*FPD(TMenuLine (*), PickedLine)).Text, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){S("\002  "), RaceNames[RaceIndex]}));
            break;
          }
          }
        if (RaceIndex == RaceHuman) break;
        RaceIndex++;
      }
    }
  }
  PickedLine = MenuList;
  Choice = 1;
  Redraw = 1;
  WithExit = 1;
  do {
    Key = ChooseFromList(S("\000"), S("\000"), CreateCharacter_MenuHeadingColor, CreateCharacter_MenuLineColor, CreateCharacter_MenuHighlightColor, CreateCharacter_MenuLeftCol, CreateCharacter_MenuTopRow, CreateCharacter_MenuRightCol, CreateCharacter_MenuBottomRow, MenuList, WithExit, &Redraw, &Choice, &PickedLine);
    if (Key == CreateCharacter_KeyEscape) {
      return;
    }
  } while (!(Key == CreateCharacter_KeyEnter));
  if (Choice == CreateCharacter_HumanMenuLine) {
    Choice++;
  }
  {
    TCharacter *w2 = &(*FPD(TCharacter (*), NewCharacter));
      w2->Race = Choice;
      switch (w2->Race) {
      case RaceHalfling:
      {
        w2->Figure[0] = IconSizeSmall;
        AddAffect(NewCharacter, CreateCharacter_AffectPoisonSaveConBonus, PermanentDuration, CreateCharacter_DataFF, NoRemoveHandler);
        AddAffect(NewCharacter, CreateCharacter_AffectSaveConBonusKind2Or4, PermanentDuration, CreateCharacter_DataFF, NoRemoveHandler);
        break;
      }
      case RaceDwarf:
      {
        w2->Figure[0] = IconSizeSmall;
        AddAffect(NewCharacter, CreateCharacter_AffectPoisonSaveConBonus, PermanentDuration, CreateCharacter_DataFF, NoRemoveHandler);
        AddAffect(NewCharacter, CreateCharacter_AffectSaveConBonusKind2Or4, PermanentDuration, CreateCharacter_DataFF, NoRemoveHandler);
        AddAffect(NewCharacter, CreateCharacter_AffectBonusVsOrcGoblin, PermanentDuration, CreateCharacter_DataFF, NoRemoveHandler);
        AddAffect(NewCharacter, CreateCharacter_AffectGiantsAttackPenalty, PermanentDuration, CreateCharacter_DataFF, NoRemoveHandler);
        break;
      }
      case RaceGnome:
      {
        w2->Figure[0] = IconSizeSmall;
        AddAffect(NewCharacter, CreateCharacter_AffectSaveConBonusKind2Or4, PermanentDuration, CreateCharacter_DataFF, NoRemoveHandler);
        AddAffect(NewCharacter, CreateCharacter_AffectBonusVsKoboldGoblin, PermanentDuration, CreateCharacter_DataFF, NoRemoveHandler);
        AddAffect(NewCharacter, CreateCharacter_AffectGiantsAttackPenalty, PermanentDuration, CreateCharacter_DataFF, NoRemoveHandler);
        AddAffect(NewCharacter, CreateCharacter_AffectGnollBugbearAttackPenalty, PermanentDuration, CreateCharacter_DataFF, NoRemoveHandler);
        break;
      }
      case RaceElf:
      {
        w2->Figure[0] = IconSizeLarge;
        AddAffect(NewCharacter, CreateCharacter_AffectElfCharmSleepResistance, PermanentDuration, CreateCharacter_DataFF, NoRemoveHandler);
        break;
      }
      case RaceHalfElf:
      {
        w2->Figure[0] = IconSizeLarge;
        AddAffect(NewCharacter, CreateCharacter_AffectHalfElfCharmSleepResistance, PermanentDuration, CreateCharacter_DataFF, NoRemoveHandler);
        break;
      }
      default:
      {
        w2->Figure[0] = IconSizeLarge;
      }
      }
  }
  FreeMenuList(&MenuList);
  NewMenuList(CreateCharacter_MenuGenderLines, &MenuList);
  (*FPD(TMenuLine (*), MenuList)).Flag29 = 1;
  rtl_str_assign((*FPD(TMenuLine (*), MenuList)).Text, 40, S("\013Pick Gender"));
  {
    if (0 <= 1) {
      GenderIndex = 0;
      for (;;) {
          PickedLine = GetMenuLine((s16)(GenderIndex + 1), MenuList);
          rtl_str_assign((*FPD(TMenuLine (*), PickedLine)).Text, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){S("\002  "), SexNames[GenderIndex]}));
        if (GenderIndex == 1) break;
        GenderIndex++;
      }
    }
  }
  PickedLine = MenuList;
  Choice = 1;
  WithExit = 1;
  Redraw = 1;
  do {
    Key = ChooseFromList(S("\000"), S("\000"), CreateCharacter_MenuHeadingColor, CreateCharacter_MenuLineColor, CreateCharacter_MenuHighlightColor, CreateCharacter_MenuLeftCol, CreateCharacter_MenuTopRow, CreateCharacter_MenuRightCol, CreateCharacter_MenuBottomRow, MenuList, WithExit, &Redraw, &Choice, &PickedLine);
    if (Key == CreateCharacter_KeyEscape) {
      return;
    }
  } while (!(Key == CreateCharacter_KeyEnter));
  (*FPD(TCharacter (*), NewCharacter)).Sex = Choice - 1;
  FreeMenuList(&MenuList);
  ChoiceCount = RaceClassChoices[(*FPD(TCharacter (*), NewCharacter)).Race][0];
  NewMenuList((s16)(ChoiceCount + 1), &MenuList);
  (*FPD(TMenuLine (*), MenuList)).Flag29 = 1;
  rtl_str_assign((*FPD(TMenuLine (*), MenuList)).Text, 40, S("\012Pick Class"));
  {
    u8 limit = ChoiceCount;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          PickedLine = GetMenuLine(I, MenuList);
          rtl_str_assign((*FPD(TMenuLine (*), PickedLine)).Text, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){S("\002  "), ClassNames[RaceClassChoices[(*FPD(TCharacter (*), NewCharacter)).Race][I]]}));
        if (I == limit) break;
        I++;
      }
    }
  }
  PickedLine = MenuList;
  Choice = 1;
  WithExit = 1;
  Redraw = 1;
  do {
    Key = ChooseFromList(S("\000"), S("\000"), CreateCharacter_MenuHeadingColor, CreateCharacter_MenuLineColor, CreateCharacter_MenuHighlightColor, CreateCharacter_MenuLeftCol, CreateCharacter_MenuTopRow, CreateCharacter_MenuRightCol, CreateCharacter_MenuBottomRow, MenuList, WithExit, &Redraw, &Choice, &PickedLine);
    if (Key == CreateCharacter_KeyEscape) {
      return;
    }
  } while (!(Key == CreateCharacter_KeyEnter));
  {
    TCharacter *w3 = &(*FPD(TCharacter (*), NewCharacter));
      w3->ClassCombo = RaceClassChoices[w3->Race][Choice];
      w3->HighestLevel = 1;
      switch (w3->ClassCombo) {
      case 0:
      case 1:
      case 2:
      case 3:
      case 4:
      case 5:
      case 6:
      case 7:
      {
        w3->ClassLevels[w3->ClassCombo] = 1;
        break;
      }
      case CreateCharacter_ClericFighter:
      {
        w3->ClassLevels[0] = 1;
        w3->ClassLevels[2] = 1;
        break;
      }
      case CreateCharacter_ClericFighterMage:
      {
        w3->ClassLevels[0] = 1;
        w3->ClassLevels[2] = 1;
        w3->ClassLevels[5] = 1;
        break;
      }
      case CreateCharacter_ClericRanger:
      {
        w3->ClassLevels[0] = 1;
        w3->ClassLevels[4] = 1;
        break;
      }
      case CreateCharacter_ClericMage:
      {
        w3->ClassLevels[0] = 1;
        w3->ClassLevels[5] = 1;
        break;
      }
      case CreateCharacter_ClericThief:
      {
        w3->ClassLevels[0] = 1;
        w3->ClassLevels[6] = 1;
        break;
      }
      case CreateCharacter_FighterMage:
      {
        w3->ClassLevels[2] = 1;
        w3->ClassLevels[5] = 1;
        break;
      }
      case CreateCharacter_FighterThief:
      {
        w3->ClassLevels[2] = 1;
        w3->ClassLevels[6] = 1;
        break;
      }
      case CreateCharacter_FighterMageThief:
      {
        w3->ClassLevels[2] = 1;
        w3->ClassLevels[5] = 1;
        w3->ClassLevels[6] = 1;
        break;
      }
      case CreateCharacter_MageThief:
      {
        w3->ClassLevels[5] = 1;
        w3->ClassLevels[6] = 1;
        break;
      }
      }
      if (w3->ClassLevels[6] > 0) {
        ComputeThiefSkills(NewCharacter);
      }
      w3->ClassBits = 0;
      w3->Thac0 = 0;
      {
        if (0 <= 7) {
          ClassIndex = 0;
          for (;;) {
              if (w3->ClassLevels[ClassIndex] > 0) {
                if (ClassThac0Table[ClassIndex][w3->ClassLevels[ClassIndex]] > w3->Thac0) {
                  w3->Thac0 = ClassThac0Table[ClassIndex][w3->ClassLevels[ClassIndex]];
                }
                w3->ClassBits += ClassItemBits[ClassIndex];
              }
            if (ClassIndex == 7) break;
            ClassIndex++;
          }
        }
      }
  }
  ComputeSavingThrows(NewCharacter);
  FreeMenuList(&MenuList);
  ChoiceCount = ClassAlignmentChoices[(*FPD(TCharacter (*), NewCharacter)).ClassCombo][0];
  NewMenuList((s16)(ChoiceCount + 1), &MenuList);
  (*FPD(TMenuLine (*), MenuList)).Flag29 = 1;
  rtl_str_assign((*FPD(TMenuLine (*), MenuList)).Text, 40, S("\016Pick Alignment"));
  {
    u8 limit = ChoiceCount;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          PickedLine = GetMenuLine(I, MenuList);
          rtl_str_assign((*FPD(TMenuLine (*), PickedLine)).Text, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){S("\002  "), AlignmentNames[ClassAlignmentChoices[(*FPD(TCharacter (*), NewCharacter)).ClassCombo][I]]}));
        if (I == limit) break;
        I++;
      }
    }
  }
  PickedLine = MenuList;
  Choice = 1;
  WithExit = 1;
  Redraw = 1;
  do {
    Key = ChooseFromList(S("\000"), S("\000"), CreateCharacter_MenuHeadingColor, CreateCharacter_MenuLineColor, CreateCharacter_MenuHighlightColor, CreateCharacter_MenuLeftCol, CreateCharacter_MenuTopRow, CreateCharacter_MenuRightCol, CreateCharacter_MenuBottomRow, MenuList, WithExit, &Redraw, &Choice, &PickedLine);
    if (Key == CreateCharacter_KeyEscape) {
      return;
    }
  } while (!(Key == CreateCharacter_KeyEnter));
  (*FPD(TCharacter (*), NewCharacter)).Alignment = ClassAlignmentChoices[(*FPD(TCharacter (*), NewCharacter)).ClassCombo][Choice];
  FreeMenuList(&MenuList);
  if ((*FPD(TCharacter (*), NewCharacter)).ClassCombo <= 7) {
    {
      TAgeEntry *w4 = &StartingAgeTable[(*FPD(TCharacter (*), NewCharacter)).Race][(*FPD(TCharacter (*), NewCharacter)).ClassCombo];
        (*FPD(TCharacter (*), NewCharacter)).Age = RollDice(w4->Count, w4->Sides) + w4->Base;
    }
  } else {
    {
      TCharacter *w5 = &(*FPD(TCharacter (*), NewCharacter));
        switch (w5->ClassCombo) {
        case CreateCharacter_ClericFighter:
        {
          w5->Age = StartingAgeTable[w5->Race][0].Base + (StartingAgeTable[w5->Race][0].Sides * StartingAgeTable[w5->Race][0].Count);
          break;
        }
        case CreateCharacter_ClericFighterMage:
        {
          w5->Age = StartingAgeTable[w5->Race][0].Base + (StartingAgeTable[w5->Race][0].Sides * StartingAgeTable[w5->Race][0].Count);
          break;
        }
        case CreateCharacter_ClericMage:
        {
          w5->Age = StartingAgeTable[w5->Race][0].Base + (StartingAgeTable[w5->Race][0].Sides * StartingAgeTable[w5->Race][0].Count);
          break;
        }
        case CreateCharacter_ClericThief:
        {
          w5->Age = StartingAgeTable[w5->Race][0].Base + (StartingAgeTable[w5->Race][0].Sides * StartingAgeTable[w5->Race][0].Count);
          break;
        }
        case CreateCharacter_FighterMage:
        {
          w5->Age = StartingAgeTable[w5->Race][5].Base + (StartingAgeTable[w5->Race][5].Sides * StartingAgeTable[w5->Race][5].Count);
          break;
        }
        case CreateCharacter_FighterThief:
        {
          w5->Age = StartingAgeTable[w5->Race][2].Base + (StartingAgeTable[w5->Race][2].Sides * StartingAgeTable[w5->Race][2].Count);
          break;
        }
        case CreateCharacter_FighterMageThief:
        {
          w5->Age = StartingAgeTable[w5->Race][5].Base + (StartingAgeTable[w5->Race][5].Sides * StartingAgeTable[w5->Race][5].Count);
          break;
        }
        case CreateCharacter_MageThief:
        {
          w5->Age = StartingAgeTable[w5->Race][5].Base + (StartingAgeTable[w5->Race][5].Sides * StartingAgeTable[w5->Race][5].Count);
          break;
        }
        }
    }
  }
  SavedSelection = SelectedCharacter;
  SelectedCharacter = NewCharacter;
  ShowCharacterSheet();
  do {
    (*FPD(TCharacter (*), NewCharacter)).StrengthPercent = 0;
    {
      if (0 <= CreateCharacter_CharismaIndex) {
        AbilityIndex = 0;
        for (;;) {
            (*FPD(TScoredCharacter (*), NewCharacter)).Scores[AbilityIndex] = 0;
            {
              if (1 <= CreateCharacter_AbilityRollCount) {
                RollAttempt = 1;
                for (;;) {
                    AbilityRoll = RollDice(CreateCharacter_AbilityDiceCount, CreateCharacter_AbilityDiceSides);
                    switch (RaceIndex) {
                    case RaceDwarf:
                    {
                      switch (AbilityIndex) {
                      case CreateCharacter_ConstitutionIndex:
                      {
                        AbilityRoll++;
                        break;
                      }
                      case CreateCharacter_CharismaIndex:
                      {
                        AbilityRoll--;
                        break;
                      }
                      }
                      break;
                    }
                    case RaceElf:
                    {
                      switch (AbilityIndex) {
                      case CreateCharacter_DexterityIndex:
                      {
                        AbilityRoll++;
                        break;
                      }
                      case CreateCharacter_ConstitutionIndex:
                      {
                        AbilityRoll--;
                        break;
                      }
                      }
                      break;
                    }
                    case RaceHalfling:
                    {
                      switch (AbilityIndex) {
                      case CreateCharacter_StrengthIndex:
                      {
                        AbilityRoll--;
                        break;
                      }
                      case CreateCharacter_DexterityIndex:
                      {
                        AbilityRoll++;
                        break;
                      }
                      }
                      break;
                    }
                    case RaceHalfOrc:
                    {
                      switch (AbilityIndex) {
                      case CreateCharacter_StrengthIndex:
                      {
                        AbilityRoll++;
                        break;
                      }
                      case CreateCharacter_ConstitutionIndex:
                      {
                        AbilityRoll++;
                        break;
                      }
                      case CreateCharacter_CharismaIndex:
                      {
                        AbilityRoll -= 2;
                        break;
                      }
                      }
                      break;
                    }
                    }
                    if ((*FPD(TScoredCharacter (*), NewCharacter)).Scores[AbilityIndex] < AbilityRoll) {
                      (*FPD(TScoredCharacter (*), NewCharacter)).Scores[AbilityIndex] = AbilityRoll;
                    }
                  if (RollAttempt == CreateCharacter_AbilityRollCount) break;
                  RollAttempt++;
                }
              }
            }
            {
              TScoredCharacter *w6 = &(*FPD(TScoredCharacter (*), NewCharacter));
                switch (AbilityIndex) {
                case CreateCharacter_StrengthIndex:
                {
                  if (((w6->Scores[AbilityIndex] > 0)) && ((RaceAgeBrackets[w6->Race][0] < w6->Age))) {
                    w6->Scores[AbilityIndex]++;
                  }
                  if (((w6->Scores[AbilityIndex] > 0)) && ((RaceAgeBrackets[w6->Race][1] < w6->Age))) {
                    w6->Scores[AbilityIndex]--;
                  }
                  if (((w6->Scores[AbilityIndex] > 0)) && ((RaceAgeBrackets[w6->Race][2] < w6->Age))) {
                    w6->Scores[AbilityIndex] -= 2;
                  }
                  if (((w6->Scores[AbilityIndex] > 0)) && ((RaceAgeBrackets[w6->Race][3] < w6->Age))) {
                    w6->Scores[AbilityIndex]--;
                  }
                  if (w6->Scores[AbilityIndex] < RaceAbilityLimits[w6->Race][w6->Sex]) {
                    w6->Scores[AbilityIndex] = RaceAbilityLimits[w6->Race][w6->Sex];
                  }
                  if (w6->Scores[AbilityIndex] > RaceStrengthMax[w6->Race][w6->Sex - (-2)]) {
                    w6->Scores[AbilityIndex] = RaceStrengthMax[w6->Race][w6->Sex - (-2)];
                  }
                  if (w6->Scores[AbilityIndex] < ClassAbilityMinimums[w6->ClassCombo][AbilityIndex]) {
                    w6->Scores[AbilityIndex] = ClassAbilityMinimums[w6->ClassCombo][AbilityIndex];
                  }
                  if (((w6->Scores[0] == ExceptionalStrength)) && ((w6->ClassLevels[2] > 0))) {
                    w6->StrengthPercent = rtl_Random(CreateCharacter_ExceptionalStrengthRoll) + 1;
                    if (RaceStrengthPercent[w6->Race][w6->Sex - (-4)] < w6->StrengthPercent) {
                      w6->StrengthPercent = RaceStrengthPercent[w6->Race][w6->Sex - (-4)];
                    }
                  }
                  break;
                }
                case CreateCharacter_IntelligenceIndex:
                {
                  if (RaceAgeBrackets[w6->Race][1] < w6->Age) {
                    w6->Scores[AbilityIndex]++;
                  }
                  if (RaceAgeBrackets[w6->Race][3] < w6->Age) {
                    w6->Scores[AbilityIndex]++;
                  }
                  if (w6->Scores[AbilityIndex] < RaceAbilityLimits[w6->Race][6]) {
                    w6->Scores[AbilityIndex] = RaceAbilityLimits[w6->Race][6];
                  }
                  if (w6->Scores[AbilityIndex] > RaceAbilityLimits[w6->Race][7]) {
                    w6->Scores[AbilityIndex] = RaceAbilityLimits[w6->Race][7];
                  }
                  if (w6->Scores[AbilityIndex] < ClassAbilityMinimums[w6->ClassCombo][AbilityIndex]) {
                    w6->Scores[AbilityIndex] = ClassAbilityMinimums[w6->ClassCombo][AbilityIndex];
                  }
                  break;
                }
                case CreateCharacter_WisdomIndex:
                {
                  if (RaceAgeBrackets[w6->Race][0] >= w6->Age) {
                    w6->Scores[AbilityIndex]--;
                  }
                  if (RaceAgeBrackets[w6->Race][1] < w6->Age) {
                    w6->Scores[AbilityIndex]++;
                  }
                  if (RaceAgeBrackets[w6->Race][2] < w6->Age) {
                    w6->Scores[AbilityIndex]++;
                  }
                  if (RaceAgeBrackets[w6->Race][3] < w6->Age) {
                    w6->Scores[AbilityIndex]++;
                  }
                  if (w6->Scores[AbilityIndex] < RaceAbilityLimits[w6->Race][8]) {
                    w6->Scores[AbilityIndex] = RaceAbilityLimits[w6->Race][8];
                  }
                  if (w6->Scores[AbilityIndex] > RaceAbilityLimits[w6->Race][9]) {
                    w6->Scores[AbilityIndex] = RaceAbilityLimits[w6->Race][9];
                  }
                  if (w6->Scores[AbilityIndex] < ClassAbilityMinimums[w6->ClassCombo][AbilityIndex]) {
                    w6->Scores[AbilityIndex] = ClassAbilityMinimums[w6->ClassCombo][AbilityIndex];
                  }
                  if (((w6->Scores[AbilityIndex] < CreateCharacter_MinClericWisdom)) && (((w6->ClassCombo >= CreateCharacter_ClericFighter && w6->ClassCombo <= CreateCharacter_ClericThief)))) {
                    w6->Scores[AbilityIndex] = CreateCharacter_MinClericWisdom;
                  }
                  break;
                }
                case CreateCharacter_DexterityIndex:
                {
                  if (RaceAgeBrackets[w6->Race][2] < w6->Age) {
                    w6->Scores[AbilityIndex] -= 2;
                  }
                  if (RaceAgeBrackets[w6->Race][3] < w6->Age) {
                    w6->Scores[AbilityIndex]--;
                  }
                  if (w6->Scores[AbilityIndex] < RaceAbilityLimits[w6->Race][10]) {
                    w6->Scores[AbilityIndex] = RaceAbilityLimits[w6->Race][10];
                  }
                  if (w6->Scores[AbilityIndex] > RaceAbilityLimits[w6->Race][11]) {
                    w6->Scores[AbilityIndex] = RaceAbilityLimits[w6->Race][11];
                  }
                  if (w6->Scores[AbilityIndex] < ClassAbilityMinimums[w6->ClassCombo][AbilityIndex]) {
                    w6->Scores[AbilityIndex] = ClassAbilityMinimums[w6->ClassCombo][AbilityIndex];
                  }
                  break;
                }
                case CreateCharacter_ConstitutionIndex:
                {
                  if (RaceAgeBrackets[w6->Race][1] < w6->Age) {
                    w6->Scores[AbilityIndex]--;
                  }
                  if (RaceAgeBrackets[w6->Race][2] < w6->Age) {
                    w6->Scores[AbilityIndex]--;
                  }
                  if (RaceAgeBrackets[w6->Race][3] < w6->Age) {
                    w6->Scores[AbilityIndex]--;
                  }
                  if (w6->Scores[AbilityIndex] < RaceAbilityLimits[w6->Race][12]) {
                    w6->Scores[AbilityIndex] = RaceAbilityLimits[w6->Race][12];
                  }
                  if (w6->Scores[AbilityIndex] > RaceAbilityLimits[w6->Race][13]) {
                    w6->Scores[AbilityIndex] = RaceAbilityLimits[w6->Race][13];
                  }
                  if (w6->Scores[AbilityIndex] < ClassAbilityMinimums[w6->ClassCombo][AbilityIndex]) {
                    w6->Scores[AbilityIndex] = ClassAbilityMinimums[w6->ClassCombo][AbilityIndex];
                  }
                  break;
                }
                case CreateCharacter_CharismaIndex:
                {
                  if (w6->Scores[AbilityIndex] < RaceAbilityLimits[w6->Race][14]) {
                    w6->Scores[AbilityIndex] = RaceAbilityLimits[w6->Race][14];
                  }
                  if (w6->Scores[AbilityIndex] > RaceAbilityLimits[w6->Race][15]) {
                    w6->Scores[AbilityIndex] = RaceAbilityLimits[w6->Race][15];
                  }
                  if (w6->Scores[AbilityIndex] < ClassAbilityMinimums[w6->ClassCombo][AbilityIndex]) {
                    w6->Scores[AbilityIndex] = ClassAbilityMinimums[w6->ClassCombo][AbilityIndex];
                  }
                  break;
                }
                }
            }
            ShowAbilityScore(AbilityIndex, 0);
          if (AbilityIndex == CreateCharacter_CharismaIndex) break;
          AbilityIndex++;
        }
      }
    }
    {
      TCharacter *w7 = &(*FPD(TCharacter (*), NewCharacter));
        w7->HpCurrent = w7->HpMax;
        w7->Attacks = CreateCharacter_StartAttacks;
        w7->BaseAttacks[0] = 1;
        w7->BaseDamage[0] = CreateCharacter_StartBaseDamage;
        w7->StrengthBonusFlag = 1;
        w7->BaseMovement = CreateCharacter_StartMovement;
        GoldDiceTotal = 0;
        ClassTotal = 0;
        {
          if (0 <= 7) {
            ClassIndex = 0;
            for (;;) {
                if (w7->ClassLevels[ClassIndex] > 0) {
                  switch (ClassIndex) {
                  case ClassCleric:
                  {
                    w7->SpellSlots[0][0] = 1;
                    break;
                  }
                  case ClassMagicUser:
                  {
                    w7->SpellSlots[1][0] = 1;
                    break;
                  }
                  }
                  GoldDiceTotal += RollDice(StartingGoldDice[ClassIndex][0], StartingGoldDice[ClassIndex][1]);
                  ClassTotal++;
                  switch (ClassIndex) {
                  case ClassCleric:
                  {
                    AddWisdomBonusSpells(NewCharacter);
                    {
                      if (1 <= LastSpell) {
                        I = 1;
                        for (;;) {
                            {
                              TSpellEntry *w8 = &SpellTable[I];
                                if (((w8->SpellClass == 0)) && ((w8->Level == 1))) {
                                  w7->KnownSpells[I - 1] = 1;
                                }
                            }
                          if (I == LastSpell) break;
                          I++;
                        }
                      }
                    }
                    break;
                  }
                  case ClassMagicUser:
                  {
                    w7->KnownSpells[10] = 1;
                    w7->KnownSpells[17] = 1;
                    w7->KnownSpells[18] = 1;
                    w7->KnownSpells[20] = 1;
                    break;
                  }
                  }
                }
              if (ClassIndex == 7) break;
              ClassIndex++;
            }
          }
        }
        w7->Money[3] = ((s16)(GoldDiceTotal * 10) / ClassTotal);
        w7->HpB1 = RollHitPoints(NewCharacter, 0xFF);
        w7->HpMax = w7->HpB1;
        ConAdjustment = ConstitutionHitPointAdjustment(NewCharacter);
        if (ConAdjustment < 0) {
          if (w7->HpMax > (s16)(rtl_abs(ConAdjustment) + ClassTotal)) {
            w7->HpMax = (((s16)(w7->HpMax + ConAdjustment)) / ClassTotal);
          } else {
            w7->HpMax = 1;
          }
        } else {
          w7->HpMax = (((s16)(w7->HpMax + ConAdjustment)) / ClassTotal);
        }
        w7->HpCurrent = w7->HpMax;
        w7->HpB1 = (w7->HpB1 / ClassTotal);
    }
    ShowCombatStats();
    ShowCharacterMoney();
    Key = AskYesNo(S("\025Keep this character\077 "), CreateCharacter_PromptTitleColor, CreateCharacter_PromptWordColor, CreateCharacter_PromptHotColor);
  } while (!(Key == KeyYes));
  ShowCharacterSheet();
  SelectedCharacter = SavedSelection;
  do {
    rtl_str_assign((*FPD(TCharacter (*), NewCharacter)).Name, 15, ReadInputLine(ts1, S("\020Character name: "), CreateCharacter_NamePromptColor, CreateCharacter_NameMaxLength));
  } while (!((*FPD(TCharacter (*), NewCharacter)).Name[0] != 0));
  SavedSelection = SelectedCharacter;
  SelectedCharacter = NewCharacter;
  ChooseHeadAndBody();
  EditCharacterIcon();
  SaveCharacter(NewCharacter, S("\000"));
  SelectedCharacter = SavedSelection;
  rtl_freemem(NewCharacter, CharacterSize);
}

/* ovl16:1F37. Drops the selected character from the party, the D function of the training-hall menu
     (RunCharacterMenu, ovl16:0161, whose 'Drop' item dispatches it). It asks AskYesNo "Drop <name>
     forever? " and, only when that is answered Y, a second AskYesNo "Are you sure? ". A no at either
     prompt shows the flash message "<name> breathes a sigh of relief." and does nothing else.
     Otherwise it shows "<name> bids you farewell." when the character still counts for combat and
     experience (Flag10D set; whitepaper 5.8) or "You dump <name> out back." when it does not, then
     removes it from the party through RemoveSelectedCharacter(False, True). No parameters; reads the global
     SelectedCharacter (nothing happens while it is nil); side effects: a flash message and the drop. */
void DropCharacter(void)
{
  POOL_TRACE("DropCharacter");
  u8 Unused = 0;
  u8 ts1[43];
  if (SelectedCharacter == 0) {
    return;
  }
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), SelectedCharacter));
      if (((AskYesNo(rtl_str_cat(ts1, 3, (const u8 *const[]){S("\005Drop "), w1->Name, S("\012 forever\077 ")}), 0xE, 0xA, 0xF) == 'Y')) && ((AskYesNo(S("\016Are you sure\077 "), 0xE, 0xA, 0xF) == 'Y'))) {
        if (w1->Flag10D == 0) {
          ShowFlashMessage(rtl_str_cat(ts1, 3, (const u8 *const[]){S("\011You dump "), w1->Name, S("\012 out back.")}));
        } else {
          ShowFlashMessage(rtl_str_cat(ts1, 2, (const u8 *const[]){w1->Name, S("\023 bids you farewell.")}));
        }
        RemoveSelectedCharacter(0, 1);
      } else {
        ShowFlashMessage(rtl_str_cat(ts1, 2, (const u8 *const[]){w1->Name, S("\033 breathes a sigh of relief.")}));
      }
  }
}

typedef struct Frame_ModifyCharacter {
  u8 SavedScores[6];
  u8 SavedStrengthPercent;
  u8 SavedHpMax;
  u8 Spare;
  s8 Stat;
  u8 Key;
  u8 ExtKey;
  u8 StatIndex;
  u8 Spare2[7];
} Frame_ModifyCharacter;

/* ovl16:2033 (nested). Redraws the value under the cursor: ability StatIndex through
       ShowAbilityScore (ovl19:0901), or the hit-point line through DrawHitPoints (00BA:0973) when
       StatIndex is HitPointIndex. Highlight is passed to both (false clears the highlight). It reads
       the parent's StatIndex and the global SelectedCharacter. */
static void ModifyCharacter_ShowStat(struct Frame_ModifyCharacter *up, u8 Highlight)
{
  if (up->StatIndex < ModifyCharacter_AbilityCount) {
    ShowAbilityScore(up->StatIndex, Highlight);
  } else {
    DrawHitPoints(SelectedCharacter, ModifyCharacter_HitPointColumn, ModifyCharacter_HitPointRow, Highlight);
  }
}

/* ovl16:209F. The Modify (M) function of the training hall, dispatched by RunCharacterMenu
     (ovl16:0161). It refuses a character that already has experience ('<name> can''t be modified.',
     FlashMessageLine), else draws the character sheet and lets the player raise or lower the six
     ability scores and the hit points. The arrow keys move the cursor (Down/Up through Strength
     ..Charisma and the hit-point line) and adjust the value under it (Right raises, Left lowers); a
     value is held between the per-race limits (RaceAbilityLimits) and the per-class minimum (ClassAbilityMinimums), a Wisdom
     change recomputes the cleric bonus spells (AddWisdomBonusSpells), and a hit-point change is
     bounded by MinHitPoints (floor) and MaxHitPoints (ceiling). 'K' (Keep) accepts the changes and leaves, 'E'
     (Exit, or Escape) restores the saved abilities. The nested ShowStat (ovl16:2033) redraws the
     value under the cursor. A `with SelectedCharacter^` block edits the modified character; its
     Experience, Scores (+$10), StrengthPercent, HpMax, HpCurrent, Race, ClassCombo, Sex, ClassLevels,
     SpellSlots and HirelingShare are used. */
void ModifyCharacter(void)
{
  POOL_TRACE("ModifyCharacter");
  Frame_ModifyCharacter fr;
  memset(&fr, 0, sizeof fr);
  u8 ts1[35];
  if ((*FPD(TCharacter (*), SelectedCharacter)).Experience > 0) {
    FlashMessageLine(rtl_str_cat(ts1, 2, (const u8 *const[]){(*FPD(TCharacter (*), SelectedCharacter)).Name, S("\023 can't be modified.")}), ModifyCharacter_MessageColor);
    return;
  }
  ShowCharacterSheet();
  rtl_Move((void *)&(*FPD(TScoredCharacter (*), SelectedCharacter)).Scores, (void *)&fr.SavedScores, ModifyCharacter_AbilityCount);
  fr.SavedStrengthPercent = (*FPD(TCharacter (*), SelectedCharacter)).StrengthPercent;
  fr.SavedHpMax = (*FPD(TCharacter (*), SelectedCharacter)).HpMax;
  fr.StatIndex = ModifyCharacter_HitPointIndex;
  ModifyCharacter_ShowStat(&fr, 0);
  fr.StatIndex = 0;
  ModifyCharacter_ShowStat(&fr, 1);
  {
    TScoredCharacter *w1 = &(*FPD(TScoredCharacter (*), SelectedCharacter));
      do {
        fr.Key = ReadPromptChoice(S("\022Modify character: "), S("\011Keep Exit"), ModifyCharacter_PromptTitleColor, ModifyCharacter_PromptWordColor, ModifyCharacter_PromptHotColor, AcceptExtendedKeys, 0, &fr.ExtKey);
        ModifyCharacter_ShowStat(&fr, 0);
        if (fr.ExtKey != 0) {
          switch ((u8)fr.Key) {
          case 'P':
          case 0x0D:
          {
            fr.StatIndex++;
            if (fr.StatIndex > ModifyCharacter_HitPointIndex) {
              fr.StatIndex = 0;
            }
            break;
          }
          case 'H':
          {
            fr.StatIndex--;
            if (fr.StatIndex == 0xFF) {
              fr.StatIndex = ModifyCharacter_HitPointIndex;
            }
            break;
          }
          case 'K':
          {
            if (fr.StatIndex < ModifyCharacter_AbilityCount) {
              fr.Stat = fr.StatIndex;
              w1->Scores[fr.Stat]--;
              switch (fr.Stat) {
              case 0:
              {
                if (w1->StrengthPercent > 0) {
                  w1->StrengthPercent--;
                  w1->Scores[fr.Stat]++;
                } else if (((w1->Scores[fr.Stat] < RaceAbilityLimits[w1->Race][w1->Sex])) || ((w1->Scores[fr.Stat] < ClassAbilityMinimums[w1->ClassCombo][0]))) {
                  w1->Scores[fr.Stat] = RaceAbilityLimits[w1->Race][w1->Sex];
                }
                break;
              }
              case 1:
              {
                if (((w1->Scores[fr.Stat] < RaceAbilityLimits[w1->Race][6])) || ((w1->Scores[fr.Stat] < ClassAbilityMinimums[w1->ClassCombo][1]))) {
                  w1->Scores[fr.Stat] = RaceAbilityLimits[w1->Race][6];
                }
                break;
              }
              case 2:
              {
                if (((w1->Scores[fr.Stat] < RaceAbilityLimits[w1->Race][8])) || ((w1->Scores[fr.Stat] < ClassAbilityMinimums[w1->ClassCombo][2]))) {
                  w1->Scores[fr.Stat] = RaceAbilityLimits[w1->Race][8];
                }
                if (w1->SpellSlots[0][0] > 0) {
                  w1->SpellSlots[0][0] = 1;
                }
                AddWisdomBonusSpells(SelectedCharacter);
                break;
              }
              case 3:
              {
                if (((w1->Scores[fr.Stat] < RaceAbilityLimits[w1->Race][10])) || ((w1->Scores[fr.Stat] < ClassAbilityMinimums[w1->ClassCombo][3]))) {
                  w1->Scores[fr.Stat] = RaceAbilityLimits[w1->Race][10];
                }
                break;
              }
              case 4:
              {
                if (((w1->Scores[fr.Stat] < RaceAbilityLimits[w1->Race][12])) || ((w1->Scores[fr.Stat] < ClassAbilityMinimums[w1->ClassCombo][4]))) {
                  w1->Scores[fr.Stat] = RaceAbilityLimits[w1->Race][12];
                }
                if (MaxHitPoints(SelectedCharacter) < w1->HpMax) {
                  w1->HpMax = MaxHitPoints(SelectedCharacter);
                }
                w1->HpCurrent = w1->HpMax;
                fr.StatIndex = ModifyCharacter_HitPointIndex;
                ModifyCharacter_ShowStat(&fr, 0);
                fr.StatIndex = 4;
                break;
              }
              case 5:
              {
                if (((w1->Scores[fr.Stat] < RaceAbilityLimits[w1->Race][14])) || ((w1->Scores[fr.Stat] < ClassAbilityMinimums[w1->ClassCombo][5]))) {
                  w1->Scores[fr.Stat] = RaceAbilityLimits[w1->Race][14];
                }
                break;
              }
              }
            } else {
              w1->HpMax--;
              if (MinHitPoints(SelectedCharacter) > w1->HpMax) {
                w1->HpMax = MinHitPoints(SelectedCharacter);
              }
              w1->HpCurrent = w1->HpMax;
            }
            break;
          }
          case 'M':
          {
            if (fr.StatIndex < ModifyCharacter_AbilityCount) {
              fr.Stat = fr.StatIndex;
              w1->Scores[fr.Stat]++;
              switch (fr.Stat) {
              case 0:
              {
                if (w1->Scores[fr.Stat] > RaceStrengthMax[w1->Race][w1->Sex - (-2)]) {
                  if ((((w1->Scores[fr.Stat] > ExceptionalStrength)) && ((w1->ClassLevels[2] > 0))) && ((RaceStrengthPercent[w1->Race][w1->Sex - (-4)] > w1->StrengthPercent))) {
                    w1->StrengthPercent++;
                  }
                  w1->Scores[fr.Stat] = RaceStrengthMax[w1->Race][w1->Sex - (-2)];
                }
                break;
              }
              case 1:
              {
                if (w1->Scores[fr.Stat] > RaceAbilityLimits[w1->Race][7]) {
                  w1->Scores[fr.Stat] = RaceAbilityLimits[w1->Race][7];
                }
                break;
              }
              case 2:
              {
                if (w1->Scores[fr.Stat] > RaceAbilityLimits[w1->Race][9]) {
                  w1->Scores[fr.Stat] = RaceAbilityLimits[w1->Race][9];
                }
                if (w1->SpellSlots[0][0] > 0) {
                  w1->SpellSlots[0][0] = 1;
                }
                AddWisdomBonusSpells(SelectedCharacter);
                break;
              }
              case 3:
              {
                if (w1->Scores[fr.Stat] > RaceAbilityLimits[w1->Race][11]) {
                  w1->Scores[fr.Stat] = RaceAbilityLimits[w1->Race][11];
                }
                break;
              }
              case 4:
              {
                if (w1->Scores[fr.Stat] > RaceAbilityLimits[w1->Race][13]) {
                  w1->Scores[fr.Stat] = RaceAbilityLimits[w1->Race][13];
                }
                if (MinHitPoints(SelectedCharacter) > w1->HpMax) {
                  w1->HpMax = MinHitPoints(SelectedCharacter);
                }
                w1->HpCurrent = w1->HpMax;
                fr.StatIndex = ModifyCharacter_HitPointIndex;
                ModifyCharacter_ShowStat(&fr, 0);
                fr.StatIndex = 4;
                break;
              }
              case 5:
              {
                if (w1->Scores[fr.Stat] > RaceAbilityLimits[w1->Race][15]) {
                  w1->Scores[fr.Stat] = RaceAbilityLimits[w1->Race][15];
                }
                break;
              }
              }
            } else {
              w1->HpMax++;
              if (MaxHitPoints(SelectedCharacter) < w1->HpMax) {
                w1->HpMax = MaxHitPoints(SelectedCharacter);
              }
              w1->HpCurrent = w1->HpMax;
            }
            break;
          }
          }
        } else {
          switch ((u8)fr.Key) {
          case 'E':
          case 0x00:
          {
            {
              if (0 <= 5) {
                fr.Stat = 0;
                for (;;) {
                    (*FPD(TScoredCharacter (*), SelectedCharacter)).Scores[fr.Stat] = fr.SavedScores[fr.Stat];
                  if (fr.Stat == 5) break;
                  fr.Stat++;
                }
              }
            }
            (*FPD(TCharacter (*), SelectedCharacter)).StrengthPercent = fr.SavedStrengthPercent;
            (*FPD(TCharacter (*), SelectedCharacter)).HpMax = fr.SavedHpMax;
            (*FPD(TCharacter (*), SelectedCharacter)).HpCurrent = w1->HpMax;
            RecalcCombatValues(SelectedCharacter);
            return;
            break;
          }
          }
        }
        RecalcCombatValues(SelectedCharacter);
        ShowCombatStats();
        ModifyCharacter_ShowStat(&fr, 1);
      } while (!(((fr.ExtKey == 0)) && ((fr.Key == ModifyCharacter_KeyKeep))));
      (*FPD(TCharacter (*), SelectedCharacter)).HirelingShare = 1;
  }
}

/* ovl16:29AE. The Train (T) function of the training hall, dispatched by RunCharacterMenu
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
     HpCurrent (the current hit points) keeps the same gap below HpMax. No parameters. Globals:
     SelectedCharacter, StingCheat, ClassTrainingBits, ExperienceTable, GameVars2, ClassNames. Side effects: the function
     window, the flash line, the character's experience, levels, spells, hit points and money.
     QUIRK ovl16:2CDA: the first refusal's Exit is followed by a jump the compiler keeps, the
     skip of the else branch, which nothing reaches.
     QUIRK ovl16:2F95: the `KnownSpells[ChosenSpell] := 1` after the magic-user rise also runs if
     the repeat ended because Listed = 0 with ChosenSpell = 0; KnownSpells is declared index 1..$38
     (+$33..+$6A), so index 0 is the byte at +$32, HpMax, and HpMax becomes 1 before the hit-point
     gain is added (range checks are off in this build). Whether Listed = 0 can be reached is for
     ChooseSpellFromList (ovl19) to say.
     QUIRK ovl16:2C9D: Experience := NewExperience (the cut to one below the level after next) runs before the refusals
     ('We do not train that class here', 'Not Enough Experience') and before the 'Do you wish to train?' confirmation, so
     opening Train with enough experience for two levels lowers the experience even when the player declines or is
     refused; kept. */
void TrainCharacter(void)
{
  POOL_TRACE("TrainCharacter");
  u8 AtLimit = 0;
  s32 NewExperience = 0;
  s32 ClassXp = 0;
  u8 TrainableBits = 0;
  u8 ClassBitMask = 0;
  u8 AllowedBits = 0;
  u8 TrainedCount = 0;
  s16 HpRoll = 0;
  s16 HpGain = 0;
  u8 SavedHp = 0;
  s8 I = 0;
  s16 ConBonus = 0;
  u8 Row = 0;
  s8 SavedMageLevel = 0;
  s8 Level = 0;
  u8 ChosenSpell = 0;
  u16 Choice = 0;
  u8 Listed = 0;
  u8 Spare = 0;
  u8 ts1[256];
  u8 ts2[256];
  if ((((*FPD(TCharacter (*), SelectedCharacter)).Status != 0)) && ((StingCheat == 0))) {
    FlashMessageLine(S("\036we only train conscious people"), TrainCharacter_MessageColor);
    return;
  }
  if (((CharacterMoneyValueInGold(SelectedCharacter) < TrainCharacter_TrainCost)) && ((StingCheat == 0))) {
    FlashMessageLine(S("\027Training costs 1000 gp."), TrainCharacter_MessageColor);
    return;
  }
  TrainableBits = 0;
  ClassBitMask = 0;
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), SelectedCharacter));
      NewExperience = 0;
      {
        if (0 <= 7) {
          I = 0;
          for (;;) {
              if (w1->ClassLevels[I] > 0) {
                ClassBitMask += ClassTrainingBits[I];
                AtLimit = 0;
                Level = w1->ClassLevels[I];
                switch (w1->Race) {
                case RaceDwarf:
                {
                  if (I == ClassFighter) {
                    if (((((Level == 8)) && ((w1->Strength == Strength17)))) || ((((Level == 7)) && ((w1->Strength < Strength17))))) {
                      AtLimit = 1;
                    }
                  }
                  break;
                }
                case RaceElf:
                {
                  if (I == ClassFighter) {
                    if ((((Level == 7)) || ((((Level == 6)) && ((w1->Strength == Strength17))))) || ((((Level == 5)) && ((w1->Strength < Strength17))))) {
                      AtLimit = 1;
                    }
                  }
                  break;
                }
                case RaceGnome:
                {
                  if (I == ClassFighter) {
                    if (((Level == 6)) || ((((Level == 5)) && ((w1->Strength < ExceptionalStrength))))) {
                      AtLimit = 1;
                    }
                  }
                  break;
                }
                case RaceHalfElf:
                {
                  if (((I == ClassCleric)) && ((Level == 5))) {
                    AtLimit = 1;
                  } else if (I == ClassFighter) {
                    if ((((Level == 8)) || ((((Level == 7)) && ((w1->Strength == Strength17))))) || ((((Level == 6)) && ((w1->Strength < Strength17))))) {
                      AtLimit = 1;
                    }
                  }
                  break;
                }
                case RaceHalfling:
                {
                  if (I == ClassFighter) {
                    if ((((Level == 6)) || ((((Level == 5)) && ((w1->Strength == Strength17))))) || ((((Level == 4)) && ((w1->Strength < Strength17))))) {
                      AtLimit = 1;
                    }
                  }
                  break;
                }
                }
                if (AtLimit == 0) {
                  if (((ExperienceTable[I][(s8)(Level + 1)] <= w1->Experience)) || ((StingCheat != 0))) {
                    if (ExperienceTable[I][(s8)(Level + 1)] > 0) {
                      TrainableBits += ClassTrainingBits[I];
                      ClassXp = ExperienceTable[I][(s8)((s8)(Level + 1) + 1)];
                      if ((((ClassXp > 0)) && ((w1->Experience >= ClassXp))) && ((ClassXp > NewExperience))) {
                        NewExperience = ClassXp - 1;
                      }
                    }
                  }
                }
              }
            if (I == 7) break;
            I++;
          }
        }
      }
      if (NewExperience > 0) {
        w1->Experience = NewExperience;
      }
      if (StingCheat == 0) {
        if ((u8)((*FPD(TGameVars (*), GameVars2))[680] & ClassBitMask) == 0) {
          FlashMessageLine(S("\036We don't train that class here"), TrainCharacter_MessageColor);
          return;
        } else if ((u8)((*FPD(TGameVars (*), GameVars2))[680] & TrainableBits) == 0) {
          FlashMessageLine(S("\025Not Enough Experience"), TrainCharacter_MessageColor);
          return;
        }
      }
      if (StingCheat == 0) {
        AllowedBits = (u8)((*FPD(TGameVars (*), GameVars2))[680] & TrainableBits);
      } else {
        AllowedBits = TrainableBits;
      }
      ClearWindow(MenuLeft, MenuTop, MenuRight, MenuBottom);
      Row = TrainCharacter_NameRow;
      DrawCharacterName(SelectedCharacter, TrainCharacter_NameCol, Row, 0);
      DrawTextAt((s16)(w1->Name[0] + 4), Row, TrainCharacter_BecomeTextColor, S("\015 will become:"));
      {
        if (0 <= 7) {
          I = 0;
          for (;;) {
              if (((w1->ClassLevels[I] > 0)) && ((((ClassTrainingBits[I] & AllowedBits)) > 0))) {
                Row++;
                if (Row == TrainCharacter_FirstBecomeRow) {
                  DrawTextAt(TrainCharacter_BecomeTextCol, Row, TrainCharacter_BecomeTextColor, rtl_str_cat(ts2, 4, (const u8 *const[]){S("\014    a level "), ByteToText(ts1, (s16)(w1->ClassLevels[I] + 1)), S("\001 "), ClassNames[I]}));
                } else {
                  DrawTextAt(TrainCharacter_BecomeTextCol, Row, TrainCharacter_BecomeTextColor, rtl_str_cat(ts2, 4, (const u8 *const[]){S("\014and a level "), ByteToText(ts1, (s16)(w1->ClassLevels[I] + 1)), S("\001 "), ClassNames[I]}));
                }
              }
            if (I == 7) break;
            I++;
          }
        }
      }
      if (AskYesNo(S("\026Do you wish to train\077 "), TrainCharacter_PromptTitleColor, TrainCharacter_PromptWordColor, TrainCharacter_PromptHotColor) != 'Y') {
        return;
      }
      ShowFlashMessage(S("\022Congratulations..."));
      if (StingCheat == 0) {
        PayGold(TrainCharacter_TrainCost, SelectedCharacter);
      }
      TrainedCount = 0;
      SavedMageLevel = w1->ClassLevels[5];
      {
        if (0 <= 7) {
          I = 0;
          for (;;) {
              if (w1->ClassLevels[I] > 0) {
                TrainedCount++;
                if (((ClassTrainingBits[I] & AllowedBits)) > 0) {
                  w1->ClassLevels[I]++;
                  /* the rise also restores one level DrainLevels (ovl12:2122) took: give back that
                     level's share of the lost hit points and drop the count of drained levels [I] */
                  if (w1->Pad74[0] > 0) {
                    w1->Pad74[1] -= (w1->Pad74[1] / w1->Pad74[0]);
                    w1->Pad74[0]--;
                  }
                }
              }
            if (I == 7) break;
            I++;
          }
        }
      }
      RecalcClassStats(SelectedCharacter);
      if (w1->ClassLevels[5] > SavedMageLevel) {
        Choice = TrainCharacter_NoSpellChoice;
        do {
          ChosenSpell = ChooseSpellFromList(TrainCharacter_SpellListToChoose, TrainCharacter_SpellDisplayMode, &Choice, &Listed);
        } while (!(((ChosenSpell > 0)) || ((Listed == 0))));
        /* QUIRK ovl16:2F95: also runs if Listed = 0 chose no spell, then ChosenSpell 0 writes HpMax
           (+$32) because KnownSpells is declared [1..$38], so index 0 is the byte below it */
        w1->KnownSpells[ChosenSpell - 1] = 1;
      }
      HpRoll = RollHitPoints(SelectedCharacter, AllowedBits);
      HpGain = (HpRoll / TrainedCount);
      if (HpGain == 0) {
        HpGain = 1;
      }
      w1->HpB1 += HpGain;
      ConBonus = ConstitutionHitPointAdjustment(SelectedCharacter);
      HpGain = (((s16)(HpRoll + ConBonus)) / TrainedCount);
      if (HpGain < 1) {
        HpGain = 1;
      }
      SavedHp = w1->HpMax - w1->HpCurrent;
      w1->HpMax += HpGain;
      w1->HpCurrent = w1->HpMax - SavedHp;
  }
}

/* ovl16:306D. The Add (A) function of the training hall, dispatched by RunCharacterMenu (ovl16:0161):
     it clears the function window, lists the saved characters on disk (ReadSavedCharacterList) and runs
     the menu "Add a character: " with "Add Exit" (ChooseFromList). Enter or A loads the highlighted
     character's record (GetMem, LoadCharacterFile) and, when its menu line does not already start with
     '*', prefixes '* ' and tries to put it in the party. A character already in the party (same Name and
     RandomTag, +$AB) is refused; a player-run member (B84 below $80) is refused once six are in the party, and
     a computer-run member (B84 $80 and up, a hireling) once the party size GameVars2^[VarPartySize] is
     eight. A refused record is freed (FreeMem); the party records themselves are freed elsewhere. The
     menu repeats until E, Escape or a full party. The edited list is written back
     (RewriteSavedCharacterList, ovl17) and freed (FreeMenuList, ovl25). No parameters; side effects: the
     function window, the menu, the heap and the saved-character list file.
     QUIRK ovl16:30E8: the ChooseFromList WithExit argument is read from [bp-0x14], a local the routine
     never assigns (whatever the previous frame left there).
     QUIRK ovl16:3263: the loop end test `Count > MaxPlayerMembers - 1` reads Count, which is assigned only inside the
     branch of Enter or A on a line that does not yet start with '*'; Next, Prev or a line that already starts with '*'
     reach the test with Count never set (first pass) or stale; kept. */
void AddSavedCharacters(void)
{
  POOL_TRACE("AddSavedCharacters");
  PMenuLine List = 0;
  PMenuLine Selected = 0;
  PCharacter NewChar = 0;
  PCharacter Who = 0;
  s16 Choice = 0;
  u8 Key = 0;
  u8 WithExit = 0;
  u8 Redraw = 0;
  u8 Count = 0;
  u8 ts1[43];
  ClearWindow(1, 1, 0x26, 0x16);
  ReadSavedCharacterList(&List);
  if (List == 0) {
    return;
  }
  Choice = 0;
  Selected = List;
  Redraw = 1;
  do {
    Key = ChooseFromList(S("\021Add a character: "), S("\010Add Exit"), 0xD, 0xA, 0xF, 1, 2, 0x26, 0x16, List, WithExit, &Redraw, &Choice, &Selected);
    if (((Key == AddSavedCharacters_KeyEnter)) || ((Key == AddSavedCharacters_KeyAdd))) {
      if ((*FPD(TMenuLine (*), Selected)).Text[1] != '*') {
        NewChar = rtl_getmem(CharacterSize);
        LoadCharacterFile((*FPD(TMenuLine (*), Selected)).Text, NewChar, 0, 1);
        rtl_str_assign((*FPD(TMenuLine (*), Selected)).Text, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){S("\002* "), (*FPD(TMenuLine (*), Selected)).Text}));
        Count = 0;
        if (PartyListHead == 0) {
          (*FPD(TGameVars (*), GameVars2))[830] = 0;
          AddPartyMember(NewChar);
          BuildCharacterIcon(1);
        } else {
          Who = PartyListHead;
          while (((Who != 0)) && ((((rtl_str_cmp((*FPD(TCharacter (*), Who)).Name, (*FPD(TCharacter (*), NewChar)).Name) != 0)) || (((*FPD(TCharacter (*), Who)).RandomTag != (*FPD(TCharacter (*), NewChar)).RandomTag))))) {
            if ((*FPD(TCharacter (*), Who)).B84 < ComputerRun) {
              Count++;
            }
            Who = (*FPD(TCharacter (*), Who)).Next;
          }
          if (((Who == 0)) && (((((((*FPD(TCharacter (*), NewChar)).B84 < ComputerRun)) && ((Count < AddSavedCharacters_MaxPlayerMembers)))) || (((((*FPD(TCharacter (*), NewChar)).B84 > 127)) && (((*FPD(TGameVars (*), GameVars2))[830] < AddSavedCharacters_MaxPartySize))))))) {
            AddPartyMember(NewChar);
            BuildCharacterIcon(1);
            if ((*FPD(TCharacter (*), NewChar)).B84 < ComputerRun) {
              Count++;
            }
          } else {
            rtl_freemem(NewChar, CharacterSize);
          }
        }
      }
    }
  } while (!(((((Key == KeyExit)) || ((Key == 0x00))) || ((Count > 5))) || (((*FPD(TGameVars (*), GameVars2))[830] > 7))));
  RewriteSavedCharacterList(List);
  FreeMenuList(&List);
}

/* ovl16:3291. Removes a character from the party list (the head is PartyListHead, linked by TCharacter.Next
     at +$104) and frees its record. It walks the list from the head to the member before
     SelectedCharacter (or finds SelectedCharacter itself at the head). When Uncounted is false (the
     member counted in the party size), it lowers the party size GameVars2^[VarPartySize]; an extra combatant
     passes Uncounted true and leaves the count alone. FreePicture frees the member's combat icon picture
     slot (CombatIcon, +$BF) first. The head is replaced by its Next; a middle member is unlinked from its
     predecessor, and SelectedCharacter becomes the member that took its place (its successor at the head,
     its predecessor otherwise). Called on drop, load, battle removal and party reorder. */
void RemoveSelectedCharacter(u8 Uncounted, u8 FreePicture)
{
  POOL_TRACE("RemoveSelectedCharacter");
  PCharacter Cur = 0;
  if (PartyListHead == 0) {
    return;
  }
  Cur = PartyListHead;
  if (Cur != SelectedCharacter) {
    while ((((*FPD(TCharacter (*), Cur)).Next != SelectedCharacter)) && (((*FPD(TCharacter (*), Cur)).Next != 0))) {
      Cur = (*FPD(TCharacter (*), Cur)).Next;
    }
    if ((*FPD(TCharacter (*), Cur)).Next != 0) {
      if (FreePicture) {
        FreePictureSlot((*FPD(TCharacter (*), SelectedCharacter)).CombatIcon);
      }
      (*FPD(TCharacter (*), Cur)).Next = (*FPD(TCharacter (*), SelectedCharacter)).Next;
      FreeCharacter(SelectedCharacter);
      SelectedCharacter = Cur;
      if (!Uncounted) {
        (*FPD(TGameVars (*), GameVars2))[830]--;
      }
    }
  } else {
    if (FreePicture) {
      FreePictureSlot((*FPD(TCharacter (*), SelectedCharacter)).CombatIcon);
    }
    PartyListHead = (*FPD(TCharacter (*), SelectedCharacter)).Next;
    Cur = (*FPD(TCharacter (*), SelectedCharacter)).Next;
    FreeCharacter(SelectedCharacter);
    SelectedCharacter = Cur;
    if (!Uncounted) {
      (*FPD(TGameVars (*), GameVars2))[830]--;
    }
  }
}

/* ovl16:33E7. The head/body step of character creation (the "Head Body Keep" prompt of the create
     flow, whitepaper 5.8): it shows the selected character's HEAD and BODY pictures (ShowHeadBodyWindow)
     and asks ReadPromptChoice for a key. H or B steps the HeadBank (+$BB) or the BodyBank (+$BC) through
     the picture numbers DS:286F and DS:287D, wrapping above $E and $C back to 1; K keeps the two banks as
     they are now. Any other key (Escape included) leaves the banks alone and shows the prompt again: only
     K leaves the loop. The banks that were current on entry are restored at the end unless the last K
     kept the current ones. No parameters; works on SelectedCharacter. Side effects: the head/body window,
     the prompt line and the two pictures. */
void ChooseHeadAndBody(void)
{
  POOL_TRACE("ChooseHeadAndBody");
  u8 Key = 0;
  u8 ExtKey = 0;
  u8 SavedHeadBank = 0;
  u8 SavedBodyBank = 0;
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), SelectedCharacter));
      SavedHeadBank = w1->HeadBank;
      SavedBodyBank = w1->BodyBank;
      do {
        ShowHeadBodyWindow();
        Key = ReadPromptChoice(S("\000"), S("\016Head Body Keep"), ChooseHeadAndBody_PromptTitleColor, ChooseHeadAndBody_PromptWordColor, ChooseHeadAndBody_PromptHotColor, ChooseHeadAndBody_PromptExtKeys, ChooseHeadAndBody_PromptAnimate, &ExtKey);
        if (ExtKey == 0) {
          switch ((u8)Key) {
          case 'H':
          {
            if (w1->HeadBank < ChooseHeadAndBody_MaxHeadBank) {
              w1->HeadBank++;
            } else {
              w1->HeadBank = 1;
            }
            break;
          }
          case 'B':
          {
            if (w1->BodyBank < ChooseHeadAndBody_MaxBodyBank) {
              w1->BodyBank++;
            } else {
              w1->BodyBank = 1;
            }
            break;
          }
          case 'K':
          {
            SavedHeadBank = w1->HeadBank;
            SavedBodyBank = w1->BodyBank;
            break;
          }
          }
        }
      } while (!(Key == 'K'));
      w1->HeadBank = SavedHeadBank;
      w1->BodyBank = SavedBodyBank;
  }
  ClearPromptLine();
}

typedef struct Frame_EditCharacterIcon {
  u8 UnusedTop;
  u8 Key;
  u8 ExtKey;
  u8 SavedCHeadBlock;
  u8 SavedCBodyBlock;
  u8 SavedSize;
  u8 SavedCombatIcon;
  u8 State;
  u8 SizeName[6];
  u8 UnusedMid;
  EditCharacterIcon_TFigureColors SavedFigure;
  u8 ColorPart;
  u8 EditFace;
  u8 LowNibble_;
  u8 HighNibble;
  u8 Mode;
  u8 PartKey;
} Frame_EditCharacterIcon;

/* ovl16:34DF (nested). Draws one cell of the editor: it fills the cell (FillPictureRect, 12 cells
       wide and 24 pixel rows tall, from the palette at @FillRectPalette into DrawBuf) and draws the two mirrored
       halves of the icon (DrawIcon) at columns CellCol and CellCol + 3, row CellRow. On the text-only
       adapter (VideoAdapter 0) the fill uses colour 3 (the icon's ground) and only the head pictures
       (index $C, WorkSlot) are drawn; on the other adapters the fill uses colour 0 and the body pictures
       (index $19) are drawn first. FlushPictureChanges shows the result. It reads nothing of the
       editor's own variables. */
static void EditCharacterIcon_DrawIconCell(struct Frame_EditCharacterIcon *up, u8 CellCol, u8 CellRow)
{
  if (VideoAdapter == AdapterCga) {
    FillPictureRect((s16)(CellCol * DrawIconCell_IconColsPerCell), (s16)(CellRow * DrawIconCell_CellHeightRows), DrawIconCell_CellWidthCells, DrawIconCell_CellHeightRows, DrawIconCell_GroundColor, rtl_far(&FillRectPalette), DrawBuf);
  } else {
    FillPictureRect((s16)(CellCol * DrawIconCell_IconColsPerCell), (s16)(CellRow * DrawIconCell_CellHeightRows), DrawIconCell_CellWidthCells, DrawIconCell_CellHeightRows, 0, rtl_far(&FillRectPalette), DrawBuf);
    DrawIcon(CellCol, CellRow, DrawIconCell_IconSet, 0, DrawIconCell_BodyPicIndex);
    DrawIcon((s16)(CellCol + DrawIconCell_SecondHalfCol), CellRow, DrawIconCell_IconSet, 1, DrawIconCell_BodyPicIndex);
  }
  DrawIcon(CellCol, CellRow, DrawIconCell_IconSet, 0, DrawIconCell_HeadPicIndex);
  DrawIcon((s16)(CellCol + DrawIconCell_SecondHalfCol), CellRow, DrawIconCell_IconSet, 1, DrawIconCell_HeadPicIndex);
  FlushPictureChanges();
}

/* ovl16:35BE (nested). Copies one picture slot of the character-icon table DS:5E5A into another:
       both halves (the identical half at FirstPic and the mirrored half at SecondPic) get their tile
       bytes (the tail at +$17) and their packed pixel bytes (the buffer Pixels points at, +$13) copied
       from Source into Dest. ByteSize (the word at +$11) gives the tile size; on the EGA adapter
       (VideoAdapter 1) the pixel buffer holds a quarter of that. When Recolor is set the copied
       destination icon is recoloured with the selected character's six colour pairs (Figure[1..6]
       through FigureColorSlots), exactly the recolouring BuildCharacterIcon (ovl17:0482) applies. The editor
       calls it with the character's CombatIcon as Source and WorkSlot as Dest (and the other way round
       at the end, without recolouring). It reads nothing of the editor's own variables. */
static void EditCharacterIcon_CopyPictureSlot(struct Frame_EditCharacterIcon *up, u8 Source, u8 Dest, u8 Recolor)
{
  u16 stack_mark = rtl_stack_mark();
  u8 I = 0;
  u8 Spare = 0;
  u8 (*MapFrom)[16] = (u8 (*)[16])rtl_stack_alloc(16);
  u8 (*MapTo)[16] = (u8 (*)[16])rtl_stack_alloc(16);
  u16 PixelBytes = 0;
  PixelBytes = (*FPD(TMemPic_OVL16 (*), PictureSlots[Dest].FirstPic)).ByteSize;
  if (VideoAdapter == AdapterEga) {
    PixelBytes = (u16)((u16)(u16)((u16)PixelBytes >> 1) >> 1);
  }
  rtl_Move((void *)&(*FPD(TMemPic_OVL16 (*), PictureSlots[Source].FirstPic)).Tail, (void *)&(*FPD(TMemPic_OVL16 (*), PictureSlots[Dest].FirstPic)).Tail, (*FPD(TMemPic_OVL16 (*), PictureSlots[Dest].FirstPic)).ByteSize);
  rtl_Move((void *)&(*FPD(TMemPic_OVL16 (*), PictureSlots[Source].SecondPic)).Tail, (void *)&(*FPD(TMemPic_OVL16 (*), PictureSlots[Dest].SecondPic)).Tail, (*FPD(TMemPic_OVL16 (*), PictureSlots[Dest].SecondPic)).ByteSize);
  rtl_Move((void *)&(*FPD(u8 (*), (*FPD(TMemPic_OVL16 (*), PictureSlots[Source].FirstPic)).Pixels)), (void *)&(*FPD(u8 (*), (*FPD(TMemPic_OVL16 (*), PictureSlots[Dest].FirstPic)).Pixels)), PixelBytes);
  rtl_Move((void *)&(*FPD(u8 (*), (*FPD(TMemPic_OVL16 (*), PictureSlots[Source].SecondPic)).Pixels)), (void *)&(*FPD(u8 (*), (*FPD(TMemPic_OVL16 (*), PictureSlots[Dest].SecondPic)).Pixels)), PixelBytes);
  if (Recolor != 0) {
    {
      TCharacter *w1 = &(*FPD(TCharacter (*), SelectedCharacter));
        {
          if (0 <= 15) {
            I = 0;
            for (;;) {
                (*MapFrom)[I] = I;
                (*MapTo)[I] = I;
              if (I == 15) break;
              I++;
            }
          }
        }
        {
          if (1 <= 6) {
            I = 1;
            for (;;) {
                (*MapTo)[FigureColorSlots[I]] = (w1->Figure[I] & 0xF);
                (*MapTo)[(s16)(FigureColorSlots[I] + 8)] = (s16)((u16)((w1->Figure[I] & 0xF0)) >> 4);
              if (I == 6) break;
              I++;
            }
          }
        }
        RemapPictureColors(rtl_far(&(*MapFrom)), rtl_far(&(*MapTo)), 0, 0, PictureSlots[Dest].FirstPic);
        RemapPictureColors(rtl_far(&(*MapFrom)), rtl_far(&(*MapTo)), 0, 0, PictureSlots[Dest].SecondPic);
    }
  }
L_exit:
  rtl_stack_release(stack_mark);
}

/* ovl16:382D. The character-icon editor: the Icon function of the camp's Alter menu (AlterMenu,
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
     StateParts picks the Head or the Weapon picture; StateColorPart picks the part whose colour
     changes (Weapon, Body, Hair or Face, Shield, Arm, Leg); StateSize picks Small or Large; StateStep
     then steps the chosen block with Next and Prev, or the chosen colour nibble through the 16 colours.
     Keep saves the value in the Saved... locals and returns to Mode, the state it came from; Exit or
     Escape restores the saved value. Leaving StateMain restores the saved (last kept) values and
     copies the working icon back into the combat icon slot. The editor then asks AskYesNo 'Is this
     icon ok? ' and starts again on anything but Y; on a map-window area view (AreaViewKind above 1) it
     first reloads the ICON pictures 0 and 1 into slots 11 and 12 (the slots it used as scratch).
     Globals: reads and changes SelectedCharacter^ (CHeadBlock, CBodyBlock, CombatIcon, Figure) and the
     prompt lines IconEditorPrompts (the word 'xxxx' of line 3 becomes 'Hair' or 'Face'); reads AreaViewKind.
     SwapPaletteColors0And8 and RestorePaletteColors0And8 bracket the editor (palette register calls when VideoAdapter
     is 1, purpose
     unknown).
     QUIRK ovl16:39F9: ReadPromptChoice is called with ExtKeys 0, so ExtKey is always 0 and the `if
     ExtKey = 0` guard never skips the key dispatch. QUIRK ovl16:3987: the size prompt names the size
     the player can switch to: 'Small' is shown while Figure[0] is 2 (large), 'Large' otherwise. */
void EditCharacterIcon(void)
{
  POOL_TRACE("EditCharacterIcon");
  Frame_EditCharacterIcon fr;
  memset(&fr, 0, sizeof fr);
  u8 ts1[46];
  DrawWindow(EditCharacterIcon_WindowLeft, EditCharacterIcon_WindowTop, EditCharacterIcon_WindowRight, EditCharacterIcon_WindowBottom, 0, 0, S("\000"));
  SwapPaletteColors0And8();
  do {
    BuildCharacterIcon(0);
    {
      TCharacter *w1 = &(*FPD(TCharacter (*), SelectedCharacter));
        fr.State = EditCharacterIcon_StateMain;
        memcpy(fr.SavedFigure, (*(EditCharacterIcon_TFigureBytes (*))&w1->Figure).Colors, 6);
        fr.SavedCombatIcon = w1->CombatIcon;
        w1->CombatIcon = EditCharacterIcon_WorkSlot;
        BuildCharacterIcon(0);
        w1->CombatIcon = fr.SavedCombatIcon;
        fr.SavedCHeadBlock = w1->CHeadBlock;
        fr.SavedCBodyBlock = w1->CBodyBlock;
        fr.SavedSize = w1->Figure[0];
        EditCharacterIcon_CopyPictureSlot(&fr, w1->CombatIcon, EditCharacterIcon_WorkSlot, 1);
        EditCharacterIcon_DrawIconCell(&fr, EditCharacterIcon_EditorCellCol, EditCharacterIcon_OldCellRow);
        DrawTextAt(EditCharacterIcon_CaptionOldCol, EditCharacterIcon_CaptionOldRow, EditCharacterIcon_CaptionColor, S("\003old"));
        DrawTextAt(EditCharacterIcon_HalvesCol, EditCharacterIcon_HalvesOldRow, EditCharacterIcon_CaptionColor, S("\016ready   action"));
        DrawTextAt(EditCharacterIcon_CaptionOldCol, EditCharacterIcon_CaptionNewRow, EditCharacterIcon_CaptionColor, S("\003new"));
        DrawTextAt(EditCharacterIcon_HalvesCol, EditCharacterIcon_HalvesNewRow, EditCharacterIcon_CaptionColor, S("\016ready   action"));
        do {
          EditCharacterIcon_DrawIconCell(&fr, EditCharacterIcon_EditorCellCol, EditCharacterIcon_NewCellRow);
          rtl_str_assign(fr.SizeName, 5, S("\000"));
          if (fr.State == EditCharacterIcon_StateSize) {
            if (w1->Figure[0] == IconSizeLarge) {
              rtl_str_assign(fr.SizeName, 5, S("\005Small"));
            } else {
              rtl_str_assign(fr.SizeName, 5, S("\005Large"));
            }
          }
          fr.Key = ReadPromptChoice(S("\000"), rtl_str_cat(ts1, 2, (const u8 *const[]){fr.SizeName, IconEditorPrompts[fr.State - 1]}), EditCharacterIcon_PromptTitleColor, EditCharacterIcon_PromptWordColor, EditCharacterIcon_PromptHotColor, 0, 0, &fr.ExtKey);
          if (fr.ExtKey == 0) {
            switch (fr.State) {
            case EditCharacterIcon_StateMain:
            {
              fr.Mode = EditCharacterIcon_StateMain;
              switch ((u8)fr.Key) {
              case 'P':
              {
                fr.State = EditCharacterIcon_StateParts;
                break;
              }
              case '1':
              {
                fr.State = EditCharacterIcon_StateColorPart;
                fr.EditFace = 0;
                rtl_str_delete(IconEditorPrompts[2], EditCharacterIcon_ColorWordColumn, EditCharacterIcon_ColorWordLength);
                rtl_str_insert(S("\004Hair"), IconEditorPrompts[2], 40, EditCharacterIcon_ColorWordColumn);
                break;
              }
              case '2':
              {
                fr.State = EditCharacterIcon_StateColorPart;
                fr.EditFace = 1;
                rtl_str_delete(IconEditorPrompts[2], EditCharacterIcon_ColorWordColumn, EditCharacterIcon_ColorWordLength);
                rtl_str_insert(S("\004Face"), IconEditorPrompts[2], 40, EditCharacterIcon_ColorWordColumn);
                break;
              }
              case 'S':
              {
                fr.State = EditCharacterIcon_StateSize;
                break;
              }
              }
              break;
            }
            case EditCharacterIcon_StateParts:
            {
              fr.Mode = EditCharacterIcon_StateParts;
              if (fr.Key == EditCharacterIcon_KeyEscape || fr.Key == KeyExit) {
                fr.State = EditCharacterIcon_StateMain;
              } else {
                fr.PartKey = fr.Key;
                fr.State = EditCharacterIcon_StateStep;
              }
              break;
            }
            case EditCharacterIcon_StateColorPart:
            {
              fr.Mode = EditCharacterIcon_StateColorPart;
              switch ((u8)fr.Key) {
              case 'W':
              {
                fr.ColorPart = EditCharacterIcon_PartWeapon;
                break;
              }
              case 'B':
              {
                fr.ColorPart = EditCharacterIcon_PartBody;
                break;
              }
              case 'H':
              {
                fr.ColorPart = EditCharacterIcon_PartHairFace;
                break;
              }
              case 'F':
              {
                fr.ColorPart = EditCharacterIcon_PartHairFace;
                break;
              }
              case 'S':
              {
                fr.ColorPart = EditCharacterIcon_PartShield;
                break;
              }
              case 'A':
              {
                fr.ColorPart = EditCharacterIcon_PartArm;
                break;
              }
              case 'L':
              {
                fr.ColorPart = EditCharacterIcon_PartLeg;
                break;
              }
              default:
              {
                fr.ColorPart = EditCharacterIcon_PartBody;
              }
              }
              if (fr.Key == EditCharacterIcon_KeyEscape || fr.Key == KeyExit) {
                fr.State = EditCharacterIcon_StateMain;
              } else {
                fr.State = EditCharacterIcon_StateStep;
              }
              break;
            }
            case EditCharacterIcon_StateSize:
            {
              switch ((u8)fr.Key) {
              case 'L':
              {
                w1->Figure[0] = IconSizeLarge;
                BuildCharacterIcon(0);
                break;
              }
              case 'S':
              {
                w1->Figure[0] = IconSizeSmall;
                BuildCharacterIcon(0);
                break;
              }
              case 'K':
              {
                fr.SavedSize = w1->Figure[0];
                fr.State = EditCharacterIcon_StateMain;
                fr.Key = EditCharacterIcon_KeySpace;
                break;
              }
              case 'E':
              case 0x00:
              {
                w1->Figure[0] = fr.SavedSize;
                fr.State = EditCharacterIcon_StateMain;
                fr.Key = EditCharacterIcon_KeySpace;
                break;
              }
              }
              BuildCharacterIcon(0);
              break;
            }
            case EditCharacterIcon_StateStep:
            {
              switch (fr.Mode) {
              case EditCharacterIcon_StateParts:
              {
                switch ((u8)fr.PartKey) {
                case 'H':
                {
                  switch ((u8)fr.Key) {
                  case 'P':
                  {
                    if (w1->CHeadBlock > 0) {
                      w1->CHeadBlock--;
                    } else {
                      w1->CHeadBlock = EditCharacterIcon_MaxHeadBlock;
                    }
                    break;
                  }
                  case 'N':
                  {
                    if (w1->CHeadBlock < EditCharacterIcon_MaxHeadBlock) {
                      w1->CHeadBlock++;
                    } else {
                      w1->CHeadBlock = 0;
                    }
                    break;
                  }
                  case 'K':
                  {
                    {
                      TCharacter *w2 = &(*FPD(TCharacter (*), SelectedCharacter));
                        fr.SavedCHeadBlock = w2->CHeadBlock;
                        fr.State = fr.Mode;
                        fr.Key = EditCharacterIcon_KeySpace;
                    }
                    break;
                  }
                  case 'E':
                  case 0x00:
                  {
                    w1->CHeadBlock = fr.SavedCHeadBlock;
                    fr.State = fr.Mode;
                    fr.Key = EditCharacterIcon_KeySpace;
                    break;
                  }
                  }
                  BuildCharacterIcon(0);
                  break;
                }
                case 'W':
                {
                  switch ((u8)fr.Key) {
                  case 'P':
                  {
                    if (w1->CBodyBlock > 0) {
                      w1->CBodyBlock--;
                    } else {
                      w1->CBodyBlock = EditCharacterIcon_MaxBodyBlock;
                    }
                    break;
                  }
                  case 'N':
                  {
                    if (w1->CBodyBlock < EditCharacterIcon_MaxBodyBlock) {
                      w1->CBodyBlock++;
                    } else {
                      w1->CBodyBlock = 0;
                    }
                    break;
                  }
                  case 'K':
                  {
                    {
                      TCharacter *w3 = &(*FPD(TCharacter (*), SelectedCharacter));
                        fr.SavedCBodyBlock = w3->CBodyBlock;
                        fr.State = fr.Mode;
                        fr.Key = EditCharacterIcon_KeySpace;
                    }
                    break;
                  }
                  case 'E':
                  case 0x00:
                  {
                    w1->CBodyBlock = fr.SavedCBodyBlock;
                    fr.State = fr.Mode;
                    fr.Key = EditCharacterIcon_KeySpace;
                    break;
                  }
                  }
                  BuildCharacterIcon(0);
                  break;
                }
                }
                break;
              }
              case EditCharacterIcon_StateColorPart:
              {
                fr.LowNibble_ = (w1->Figure[fr.ColorPart] & 0xF);
                fr.HighNibble = (s16)((u16)((w1->Figure[fr.ColorPart] & 0xF0)) >> 4);
                switch ((u8)fr.Key) {
                case 'N':
                {
                  if (fr.EditFace) {
                    fr.HighNibble = (((s16)(fr.HighNibble + 1)) % 16);
                  } else {
                    fr.LowNibble_ = (((s16)(fr.LowNibble_ + 1)) % 16);
                  }
                  w1->Figure[fr.ColorPart] = ((s16)(fr.HighNibble << 4)) + fr.LowNibble_;
                  break;
                }
                case 'P':
                {
                  if (fr.EditFace) {
                    fr.HighNibble = (((s16)(fr.HighNibble - 1)) & 0xF);
                  } else {
                    fr.LowNibble_ = (((s16)(fr.LowNibble_ - 1)) & 0xF);
                  }
                  w1->Figure[fr.ColorPart] = ((s16)(fr.HighNibble << 4)) + fr.LowNibble_;
                  break;
                }
                case 'K':
                {
                  memcpy(fr.SavedFigure, (*(EditCharacterIcon_TFigureBytes (*))&w1->Figure).Colors, 6);
                  fr.State = fr.Mode;
                  fr.Key = EditCharacterIcon_KeySpace;
                  break;
                }
                case 'E':
                case 0x00:
                {
                  memcpy((*(EditCharacterIcon_TFigureBytes (*))&w1->Figure).Colors, fr.SavedFigure, 6);
                  fr.State = fr.Mode;
                  fr.Key = EditCharacterIcon_KeySpace;
                  break;
                }
                }
                break;
              }
              }
              break;
            }
            }
          }
          EditCharacterIcon_CopyPictureSlot(&fr, w1->CombatIcon, EditCharacterIcon_WorkSlot, 1);
        } while (!(((fr.Mode == EditCharacterIcon_StateMain)) && ((fr.Key == EditCharacterIcon_KeyEscape || fr.Key == KeyExit))));
        w1->CHeadBlock = fr.SavedCHeadBlock;
        w1->CBodyBlock = fr.SavedCBodyBlock;
        w1->Figure[0] = fr.SavedSize;
        memcpy((*(EditCharacterIcon_TFigureBytes (*))&w1->Figure).Colors, fr.SavedFigure, 6);
        EditCharacterIcon_CopyPictureSlot(&fr, w1->CombatIcon, EditCharacterIcon_WorkSlot, 1);
        EditCharacterIcon_CopyPictureSlot(&fr, EditCharacterIcon_WorkSlot, w1->CombatIcon, 0);
    }
    ClearPromptLine();
    FreePictureSlot(EditCharacterIcon_WorkSlot);
    if (AreaViewKind > 1) {
      LoadPictureSlot(S("\004ICON"), 0, EditCharacterIcon_ReloadedSlot);
      LoadPictureSlot(S("\004ICON"), 1, EditCharacterIcon_WorkSlot);
    }
    fr.Key = AskYesNo(S("\021Is this icon ok\077 "), EditCharacterIcon_PromptTitleColor, EditCharacterIcon_PromptWordColor, EditCharacterIcon_PromptHotColor);
  } while (!(fr.Key == KeyYes));
  RestorePaletteColors0And8();
}

/* ovl16:3F31. The constitution hit-point adjustment shared by the hit-point floor MinHitPoints and
     the ceiling MaxHitPoints of ModifyCharacter (ovl16:209F). It sums ConstitutionHitPointTable[Constitution] over the
     eight classes the character has a level in (ClassLevels[I], +$96, signed, above 0), then adds the
     fighter bonus: one more for a fighter (ClassCombo = 2) above constitution 16 and a second above 17
     (the AD&D 1e fighter constitution bonus). The `with Who^` evaluates the parameter once into a
     hidden local; the result is the signed total (it can be negative for a low constitution). */
s8 ConstitutionHitPointAdjustment(PCharacter Who)
{
  POOL_TRACE("ConstitutionHitPointAdjustment");
  s8 Result = 0;
  s8 Sum = 0;
  s8 I = 0;
  u8 Spare = 0;
  Sum = 0;
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), Who));
      {
        if (0 <= 7) {
          I = 0;
          for (;;) {
              if (w1->ClassLevels[I] > 0) {
                Sum += ConstitutionHitPointTable[w1->Constitution];
                if (w1->Constitution > 16) {
                  if (w1->ClassCombo == 2) {
                    Sum++;
                  }
                }
                if (w1->Constitution > 17) {
                  if (w1->ClassCombo == 2) {
                    Sum++;
                  }
                }
              }
            if (I == 7) break;
            I++;
          }
        }
      }
  }
  Result = Sum;
  return Result;
}

/* ovl16:3FB3. The minimum hit points a character's HpMax may be trained down to; the floor
     counterpart of the ceiling MaxHitPoints, both called by ModifyCharacter (ovl16:209F). Over the
     eight classes the character has a level in (ClassLevels[I], +$96, signed, above 0) it counts the
     hit dice (Count) and totals their levels into Total, adding one level for class 4 and class 7
     (whose maximum die is one higher, see ovl16:408C). It then divides Total plus the constitution
     adjustment (ConstitutionHitPointAdjustment, which may be negative) by Count; a negative adjustment
     Total cannot absorb (Total at most its magnitude plus Count) clamps the result to 1, so the floor
     is never below 1. The `with Who^` evaluates the parameter once. No side effects. */
u8 MinHitPoints(PCharacter Who)
{
  POOL_TRACE("MinHitPoints");
  u8 Result = 0;
  u8 Count = 0;
  s8 Adjustment = 0;
  u8 Total = 0;
  s8 I = 0;
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), Who));
      Count = 0;
      Total = 0;
      {
        if (0 <= 7) {
          I = 0;
          for (;;) {
              if (w1->ClassLevels[I] > 0) {
                Total += w1->ClassLevels[I];
                Count++;
                switch (I) {
                case 4:
                {
                  Total++;
                  break;
                }
                case 7:
                {
                  Total++;
                  break;
                }
                }
              }
            if (I == 7) break;
            I++;
          }
        }
      }
  }
  Adjustment = ConstitutionHitPointAdjustment(Who);
  if (Adjustment < 0) {
    if (Total > (s16)(rtl_abs(Adjustment) + Count)) {
      Total = (((s16)(Total + Adjustment)) / Count);
    } else {
      Total = 1;
    }
  } else {
    Total = (((s16)(Total + Adjustment)) / Count);
  }
  Result = Total;
  return Result;
}

/* ovl16:408C. The maximum hit points of Who, the ceiling counterpart of MinHitPoints
      (ovl16:3FB3) and both called by ModifyCharacter (ovl16:209F). Over the eight classes the
      character has a level in (ClassLevels[I], +$96, signed, above 0) it totals the levels times the
      maximum hit die of each class (8 cleric and druid, 10 fighter and paladin, 8 ranger, 4
      magic-user, 6 thief, 4 monk; one extra die-worth for class 4 ranger and class 7 monk) and counts
      the classes; it then divides the total plus the constitution adjustment by the class count and
      never returns below 1. QUIRK ovl16:41B8: the constitution adjustment is taken from the global
      SelectedCharacter (DS:5D92), not from Who, although every caller passes SelectedCharacter. The
      `with Who^` evaluates the parameter once into a hidden local. No side effects. */
u8 MaxHitPoints(PCharacter Who)
{
  POOL_TRACE("MaxHitPoints");
  u8 Result = 0;
  u8 Count = 0;
  u8 Total = 0;
  s8 Adjustment = 0;
  s8 I = 0;
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), Who));
      Count = 0;
      Total = 0;
      {
        if (0 <= 7) {
          I = 0;
          for (;;) {
              if (w1->ClassLevels[I] > 0) {
                Count++;
                switch (I) {
                case 0:
                {
                  Total += (s16)(w1->ClassLevels[I] * 8);
                  break;
                }
                case 1:
                {
                  Total += (s16)(w1->ClassLevels[I] * 8);
                  break;
                }
                case 2:
                {
                  Total += (s16)(w1->ClassLevels[I] * 10);
                  break;
                }
                case 3:
                {
                  Total += (s16)(w1->ClassLevels[I] * 10);
                  break;
                }
                case 4:
                {
                  Total += (s16)(((s16)(w1->ClassLevels[I] + 1)) * 8);
                  break;
                }
                case 5:
                {
                  Total += (s16)(w1->ClassLevels[I] * 4);
                  break;
                }
                case 6:
                {
                  Total += (s16)(w1->ClassLevels[I] * 6);
                  break;
                }
                case 7:
                {
                  Total += (s16)(((s16)(w1->ClassLevels[I] + 1)) * 4);
                  break;
                }
                }
              }
            if (I == 7) break;
            I++;
          }
        }
      }
  }
  Adjustment = ConstitutionHitPointAdjustment(SelectedCharacter);
  if (Adjustment < 0) {
    if (Total > (s16)(rtl_abs(Adjustment) + Count)) {
      Total = (((s16)(Total + Adjustment)) / Count);
    } else {
      Total = 1;
    }
  } else {
    Total = (((s16)(Total + Adjustment)) / Count);
  }
  Result = Total;
  return Result;
}

/* ovl16:4235. Rolls the hit points a level gains for the classes in ClassBits: over the eight classes
      it adds, for each class the character has a level in (ClassLevels, +$96, signed, above 0) whose
      bit is in ClassBits (ClassTrainingBits, the training guild bits of the classes), a roll of ClassHitDiceCount[I] dice of
      ClassHitDieSides[I] sides (RollDice, ovl24:0DE3), where a class at level 1 rolls at least two
      thirds of its hit die (the first-level minimum). The caller divides the sum by the number of
      classes with a level. Called by the training hall (ovl16:29AE, whitepaper 5.8) and the
      create-character run (ovl16:1D1E). No side effects but the random rolls. */
u8 RollHitPoints(PCharacter Who, u8 ClassBits)
{
  POOL_TRACE("RollHitPoints");
  u8 Result = 0;
  u8 ClassRoll = 0;
  u8 Sum = 0;
  s8 I = 0;
  Sum = 0;
  {
    if (0 <= 7) {
      I = 0;
      for (;;) {
          if ((((*FPD(TCharacter (*), Who)).ClassLevels[I] > 0)) && ((((ClassTrainingBits[I] & ClassBits)) > 0))) {
            ClassRoll = RollDice(ClassHitDiceCount[I], ClassHitDieSides[I]);
            if ((*FPD(TCharacter (*), Who)).ClassLevels[I] == 1) {
              if (ClassRoll < (((s16)(ClassHitDieSides[I] * 2)) / 3)) {
                ClassRoll = (((s16)(ClassHitDieSides[I] * 2)) / 3);
              }
            }
            Sum += ClassRoll;
          }
        if (I == 7) break;
        I++;
      }
    }
  }
  Result = Sum;
  return Result;
}

/* ovl16:42ED. Takes Amount gold pieces from Who's money (the training-hall cost, ovl16:29AE): the
      amount is converted to copper (times GoldInCopper), then coin by coin from copper up it hands
      over Amount div CoinCopperValues[Kind] + 1 coins (one more than the remainder needs, so the
      hand-over always overshoots) capped at the coins Who holds, and gives the overshoot back as
      change kind by kind from platinum down (Amount div CoinCopperValues[Kind] coins). QUIRK
      ovl16:432A: the kind is not bounded, so a character who cannot cover the amount walks on into
      Money[5..6] (gems and jewelry) and reads CoinCopperValues past its five entries, and when a kind
      has no coins left the hand-over of zero coins starts the loop again. The `with Who^` evaluates
      the parameter once. */
void PayGold(s32 Amount, PCharacter Who)
{
  POOL_TRACE("PayGold");
  u16 Coins = 0;
  TCoinKind Kind = 0;
  Amount = Amount * GoldInCopper;
  Kind = CopperCoin_OVL16;
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), Who));
      while (Amount > 0) {
        Coins = (Amount / CoinCopperValues[Kind]) + 1;
        if (Coins > w1->Money[Kind]) {
          Coins = w1->Money[Kind];
        }
        Amount -= Coins * CoinCopperValues[Kind];
        w1->Money[Kind] -= Coins;
        Kind = (TCoinKind)(Kind + 1);
      }
      if (Amount < 0) {
        Amount = rtl_abs(Amount);
        Kind = PlatinumCoin_OVL16;
        while (Amount > 0) {
          Coins = (Amount / CoinCopperValues[Kind]);
          Amount -= Coins * CoinCopperValues[Kind];
          w1->Money[Kind] += Coins;
          Kind = (TCoinKind)(Kind - 1);
        }
      }
  }
}

/* Initialisation part of unit OVL16. */
void init_OVL16(void)
{
  POOL_TRACE("init");
}
