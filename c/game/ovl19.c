#include "game.h"

/* ovl19:004A. Draws the character sheet of SelectedCharacter in the window 1..38 x 1..22: the name line
     (DrawCharacterName) with an "(NPC)" tag after it for a computer-run member (B84 bit 7), the sex, race
     and age on row 3, the alignment on row 4, the class on row 5 (ClassNames, indexed by ClassCombo: 0..7
     are the single classes and 8..16 the multi-class names Cleric/Fighter .. Magic-User/Thief), the six
     ability lines (ShowAbilityScore) with their labels from row 7, the money (ShowCharacterMoney), the
     class levels and experience on row 15, the combat block (ShowCombatStats) on rows 17 and 18, the weapon
     and armor on rows 20 and 21 and the status on row 22, and the head and body portraits when they are
     on (ShowPortraits) and the tile set is 3. Called by ViewSelectedCharacter (the View command),
     TradeMoney (ovl19:219D) and ovl16 (CreateCharacter, ModifyCharacter). SheetCharacter keeps the
     character for the whole drawing. */
void ShowCharacterSheet(void)
{
  POOL_TRACE("ShowCharacterSheet");
  u8 SpareFirst = 0;
  u8 Row = 0;
  u8 Col = 0;
  u8 SpareSecond = 0;
  s8 Stat = 0;
  s8 ClassSlot = 0;
  u8 Text[256] = {0};
  u8 NeedSlash = 0;
  u8 ts1[256];
  u8 ts2[256];
  SheetCharacter = SelectedCharacter;
  ClearFullScreen();
  DrawWindowFrame(1, 1, ShowCharacterSheet_SheetRight, ShowCharacterSheet_SheetBottom, 0);
  DrawCharacterName(SheetCharacter, 1, 1, 0);
  if ((*FPD(TCharacter (*), SheetCharacter)).B84 > ComputerRunThreshold) {
    DrawTextAt((s16)((*FPD(TCharacter (*), SheetCharacter)).Name[0] + ShowCharacterSheet_NpcTagGap), 1, ShowCharacterSheet_ValueColor, S("\005(NPC)"));
  }
  Col = 1;
  rtl_str_assign(Text, 255, SexNames[(*FPD(TSheetFields (*), SheetCharacter)).Sex]);
  DrawTextAt(Col, ShowCharacterSheet_NameRow, ShowCharacterSheet_TextColor, Text);
  Col = (Col + Text[0]) + 1;
  rtl_str_assign(Text, 255, RaceNames[(*FPD(TCharacter (*), SheetCharacter)).Race]);
  DrawTextAt(Col, ShowCharacterSheet_NameRow, ShowCharacterSheet_TextColor, Text);
  Col = (Col + Text[0]) + 1;
  DrawTextAt(Col, ShowCharacterSheet_NameRow, ShowCharacterSheet_TextColor, rtl_str_cat(ts2, 2, (const u8 *const[]){S("\004Age "), WordToText(ts1, (*FPD(TCharacter (*), SheetCharacter)).Age)}));
  rtl_str_assign(Text, 255, AlignmentNames[(*FPD(TSheetFields (*), SheetCharacter)).Alignment]);
  DrawTextAt(1, ShowCharacterSheet_AlignmentRow, ShowCharacterSheet_TextColor, Text);
  rtl_str_assign(Text, 255, ClassNames[(*FPD(TCharacter (*), SheetCharacter)).ClassCombo]);
  DrawTextAt(1, ShowCharacterSheet_ClassRow, ShowCharacterSheet_TextColor, Text);
  {
    if (0 <= 5) {
      Stat = 0;
      for (;;) {
          switch (Stat) {
          case 0:
          {
            rtl_str_assign(Text, 255, S("\004STR "));
            break;
          }
          case 1:
          {
            rtl_str_assign(Text, 255, S("\004INT "));
            break;
          }
          case 2:
          {
            rtl_str_assign(Text, 255, S("\004WIS "));
            break;
          }
          case 3:
          {
            rtl_str_assign(Text, 255, S("\004DEX "));
            break;
          }
          case 4:
          {
            rtl_str_assign(Text, 255, S("\004CON "));
            break;
          }
          case 5:
          {
            rtl_str_assign(Text, 255, S("\004CHA "));
            break;
          }
          }
          DrawTextAt(1, (s16)(Stat + ShowCharacterSheet_FirstAbilityRow), ShowCharacterSheet_StatLabelColor, Text);
          ShowAbilityScore(Stat, 0);
        if (Stat == 5) break;
        Stat++;
      }
    }
  }
  ShowCharacterMoney();
  DrawTextAt(1, ShowCharacterSheet_LevelRow, ShowCharacterSheet_TextColor, S("\005Level"));
  NeedSlash = 0;
  rtl_str_assign(Text, 255, S("\000"));
  {
    if (0 <= 7) {
      ClassSlot = 0;
      for (;;) {
          if ((*FPD(TCharacter (*), SheetCharacter)).ClassLevels[ClassSlot] > 0) {
            if (NeedSlash) {
              rtl_str_assign(Text, 255, rtl_str_cat(ts1, 2, (const u8 *const[]){Text, S("\001/")}));
            }
            rtl_str_assign(Text, 255, rtl_str_cat(ts2, 2, (const u8 *const[]){Text, ByteToText(ts1, (*FPD(TCharacter (*), SheetCharacter)).ClassLevels[ClassSlot])}));
            NeedSlash = 1;
          }
        if (ClassSlot == 7) break;
        ClassSlot++;
      }
    }
  }
  DrawTextAt(7, ShowCharacterSheet_LevelRow, ShowCharacterSheet_TextColor, Text);
  DrawTextAt(17, ShowCharacterSheet_LevelRow, ShowCharacterSheet_TextColor, rtl_str_cat(ts2, 2, (const u8 *const[]){S("\004Exp "), LongIntToText(ts1, (*FPD(TCharacter (*), SheetCharacter)).Experience)}));
  ShowCombatStats();
  Row = ShowCharacterSheet_WeaponRow;
  if ((*FPD(TCharacter (*), SheetCharacter)).SlotItems[0] != 0) {
    DrawTextAt(1, Row, ShowCharacterSheet_TextColor, S("\006Weapon"));
    FormatItemLine((s32)SheetCharacter, (*FPD(TCharacter (*), SheetCharacter)).SlotItems[0], 8, Row, 0, 1);
  }
  Row++;
  if ((*FPD(TCharacter (*), SheetCharacter)).SlotItems[2] != 0) {
    /* QUIRK ovl19:0467: the Armor label is drawn in column 2, one column right of Weapon and Status */
    DrawTextAt(2, Row, ShowCharacterSheet_TextColor, S("\005Armor"));
    FormatItemLine((s32)SheetCharacter, (*FPD(TCharacter (*), SheetCharacter)).SlotItems[2], 8, Row, 0, 1);
  }
  Row++;
  DrawTextAt(1, Row, ShowCharacterSheet_TextColor, S("\006Status"));
  DrawTextAt(8, Row, ShowCharacterSheet_ValueColor, StatusNames[(*FPD(TSheetFields (*), SheetCharacter)).Status]);
  if (ShowPortraits != 0) {
    if (TileSet == ShowCharacterSheet_HeadBodyTileSet) {
      ShowHeadBodyWindow();
    }
  }
}

/* ovl19:050D. Clears the money window (columns 12 to 26, rows 7 to 14) and lists the kinds of money
     SelectedCharacter holds, from Jewelry (6) down to Copper (0): each kind with a nonzero Money entry gets
     a row, its name ending in column 19 and its amount in column 21. The Money entries are Words at +$88. */
void ShowCharacterMoney(void)
{
  POOL_TRACE("ShowCharacterMoney");
  u8 Row = 0;
  s8 Kind = 0;
  String40_RES06 Name = {0};
  u8 ts1[256];
  ClearWindow(ShowCharacterMoney_MoneyWindowLeft, ShowCharacterMoney_MoneyWindowTop, ShowCharacterMoney_MoneyWindowRight, ShowCharacterMoney_MoneyWindowBottom);
  Row = ShowCharacterMoney_MoneyWindowTop;
  {
    if (ShowCharacterMoney_LastMoneyKind >= 0) {
      Kind = ShowCharacterMoney_LastMoneyKind;
      for (;;) {
          if ((*FPD(TCharacter (*), SelectedCharacter)).Money[Kind] > 0) {
            rtl_str_assign(Name, 40, MoneyKindNames[Kind]);
            DrawTextAt((s16)(ShowCharacterMoney_MoneyNameRight - Name[0]), Row, ShowCharacterMoney_MoneyColor, Name);
            DrawTextAt(ShowCharacterMoney_MoneyAmountColumn, Row, ShowCharacterMoney_MoneyColor, WordToText(ts1, (*FPD(TCharacter (*), SelectedCharacter)).Money[Kind]));
            Row++;
          }
        if (Kind == 0) break;
        Kind--;
      }
    }
  }
}

/* ovl19:0608. Draws the combat block of SelectedCharacter on the sheet: on row 17, AC (DrawArmourClass) and
     THAC0 (60 minus HitAdjust, column 9 label, 15 value) and Encumbrance (CarriedWeight, column 22 label,
     34 value); on row 18, HP (DrawHitPoints), Damage (dice count, d, sides, then the bonus with its sign)
     and Movement (the Movement byte doubled by affect $2A and halved by affect $27, column 25 label,
     34 value). Labels are drawn in bright white (15), values in bright green (10). Called by ShowCharacterSheet
     (its call at ovl19:03F5) and by ovl16 (CreateCharacter, ModifyCharacter). */
void ShowCombatStats(void)
{
  POOL_TRACE("ShowCombatStats");
  PCharacter Character = 0;
  u8 Row = 0;
  u8 Col = 0;
  u8 Move_ = 0;
  String40_RES06 Damage = {0};
  farptr Affect = 0;
  u8 ts1[256];
  u8 ts2[256];
  u8 ts3[256];
  Character = SelectedCharacter;
  RecalcCombatValues(Character);
  Row = ShowCombatStats_CombatRow;
  DrawTextAt(ShowCombatStats_ArmorLabelColumn, Row, ShowCombatStats_LabelColor, S("\006AC    "));
  DrawArmourClass(Character, ShowCombatStats_ArmorValueColumn, Row);
  DrawTextAt(ShowCombatStats_ArmorLabelColumn, (s16)(Row + 1), ShowCombatStats_LabelColor, S("\006HP    "));
  DrawHitPoints(Character, ShowCombatStats_ArmorValueColumn, (s16)(Row + 1), 0);
  Col = 8;
  DrawTextAt((s16)(Col + 1), Row, ShowCombatStats_LabelColor, S("\010THAC0   "));
  DrawTextAt((s16)(Col + 7), Row, ShowCombatStats_ValueColor, ByteToText(ts1, (s16)(ShowCombatStats_ThacBase - (*FPD(TCharacter (*), Character)).HitAdjust)));
  rtl_str_assign(Damage, 40, rtl_str_cat(ts3, 3, (const u8 *const[]){ByteToText(ts1, (*FPD(TDamageDice (*), Character)).Count), S("\001d"), ByteToText(ts2, (*FPD(TDamageDice (*), Character)).Sides)}));
  if ((*FPD(TDamageDice (*), Character)).Bonus > 0) {
    rtl_str_assign(Damage, 40, rtl_str_cat(ts2, 3, (const u8 *const[]){Damage, S("\001+"), ByteToText(ts1, (*FPD(TDamageDice (*), Character)).Bonus)}));
  }
  if ((*FPD(TDamageDice (*), Character)).Bonus < 0) {
    rtl_str_assign(Damage, 40, rtl_str_cat(ts2, 3, (const u8 *const[]){Damage, S("\001-"), ByteToText(ts1, rtl_abs((*FPD(TDamageDice (*), Character)).Bonus))}));
  }
  DrawTextAt(Col, (s16)(Row + 1), ShowCombatStats_LabelColor, S("\016Damage        "));
  DrawTextAt((s16)(Col + 7), (s16)(Row + 1), ShowCombatStats_ValueColor, Damage);
  Col = 22;
  DrawTextAt(Col, Row, ShowCombatStats_LabelColor, S("\021Encumbrance      "));
  DrawTextAt((s16)(Col + 12), Row, ShowCombatStats_ValueColor, WordToText(ts1, (*FPD(TCharacter (*), Character)).CarriedWeight));
  Move_ = (*FPD(TCharacter (*), Character)).Movement;
  if (HasAffect(Character, ShowCombatStats_DoublingAffect, &Affect)) {
    Move_ = Move_ * 2;
  }
  if (HasAffect(Character, ShowCombatStats_HalvingAffect, &Affect)) {
    Move_ = (Move_ / 2);
  }
  DrawTextAt((s16)(Col + 3), (s16)(Row + 1), ShowCombatStats_LabelColor, S("\013Movement   "));
  DrawTextAt((s16)(Col + 12), (s16)(Row + 1), ShowCombatStats_ValueColor, ByteToText(ts1, Move_));
}

/* ovl19:0901. Draws ability score Index of SelectedCharacter (0 Strength .. 5 Charisma) on row 7 + Index,
     in columns 5 to 11 (a score below 10 is one column further right), in bright green, or bright magenta
     when Highlight is set. A Strength of 18 with a percentile also draws it in parentheses after the score
     on row 7, two digits, 00 for 100. Called by ShowCharacterSheet for each of the six lines with Highlight False. */
void ShowAbilityScore(s8 Index, u8 Highlight)
{
  POOL_TRACE("ShowAbilityScore");
  String40_RES06 Percentile = {0};
  u8 Col = 0;
  u8 Color = 0;
  u8 ts1[256];
  if (Highlight) {
    Color = ShowAbilityScore_HighlightColor;
  } else {
    Color = ShowAbilityScore_ScoreColor;
  }
  Col = ShowAbilityScore_FirstScoreColumn;
  ClearWindow(Col, (s16)(Index + ShowAbilityScore_ScoreRow), ShowAbilityScore_LastScoreColumn, (s16)(Index + ShowAbilityScore_ScoreRow));
  if ((*FPD(TAbilityBlock (*), SelectedCharacter)).Scores[Index] < ShowAbilityScore_FirstTwoDigitValue) {
    Col++;
  }
  DrawTextAt(Col, (s16)(Index + ShowAbilityScore_ScoreRow), Color, ByteToText(ts1, (*FPD(TAbilityBlock (*), SelectedCharacter)).Scores[Index]));
  if (Index == 0) {
    if ((*FPD(TCharacter (*), SelectedCharacter)).Strength == ExceptionalStrength) {
      if ((*FPD(TCharacter (*), SelectedCharacter)).StrengthPercent > 0) {
        rtl_str_assign(Percentile, 40, ByteToText(ts1, (*FPD(TCharacter (*), SelectedCharacter)).StrengthPercent));
        if ((*FPD(TCharacter (*), SelectedCharacter)).StrengthPercent < ShowAbilityScore_FirstTwoDigitValue) {
          rtl_str_assign(Percentile, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){S("\001\060"), Percentile}));
        }
        if ((*FPD(TCharacter (*), SelectedCharacter)).StrengthPercent == ShowAbilityScore_PercentileMax) {
          rtl_str_assign(Percentile, 40, S("\002\060\060"));
        }
        DrawTextAt(ShowAbilityScore_PercentileColumn, ShowAbilityScore_ScoreRow, Color, rtl_str_cat(ts1, 3, (const u8 *const[]){S("\001("), Percentile, S("\001)")}));
      }
    }
  }
}

/* ovl19:0AB3. The View command (whitepaper 5.4; the shop's V key, the Temple's and the camp's View): draws
     the sheet of SelectedCharacter and shows the prompt "View:" with the words Items (I), Spells (S), Trade
     (T), Drop (D) and Exit (E) until Exit or Escape (#0) is chosen or Done is set. Items runs RunItemMenu,
     Spells runs ChooseSpellFromList, Trade runs TradeMoney and Drop runs ChooseAndDropMoney and then
     ShowCharacterMoney. The sheet is drawn again after Items, Spells and Trade. In view mode 5 (combat)
     RestorePaletteColors0And8 runs on entry and SwapPaletteColors0And8 on exit. Done: the stop flag, 0 keeps the view
     going; RunItemMenu gets
     it too. ViewedCharacter keeps a copy of SelectedCharacter (ovl19:0AD1). */
void ViewSelectedCharacter(u8 (*Done))
{
  POOL_TRACE("ViewSelectedCharacter");
  u8 Key = 0;
  u8 Spare = 0;
  String40_RES06 Menu = {0};
  u8 HasMoney = 0;
  u8 HasSpells = 0;
  u8 ExtKey = 0;
  u8 Spell = 0;
  s8 Kind = 0;
  u16 Choice = 0;
  u8 ts1[48];
  if (ViewMode == ViewModeCombat) {
    RestorePaletteColors0And8();
  }
  Key = ' ';
  (*Done) = 0;
  ViewedCharacter = SelectedCharacter;
  ShowCharacterSheet();
  while (!((Key == 0x00 || Key == 'E')) && (((*Done) == 0))) {
    rtl_str_assign(Menu, 40, S("\000"));
    HasSpells = 0;
    HasMoney = 0;
    {
      if (0 <= 20) {
        Spell = 0;
        for (;;) {
            if ((*FPD(TCharacter (*), SheetCharacter)).Spells[Spell] > 0) {
              HasSpells = 1;
            }
          if (Spell == 20) break;
          Spell++;
        }
      }
    }
    {
      if (0 <= 6) {
        Kind = 0;
        for (;;) {
            if ((*FPD(TCharacter (*), SheetCharacter)).Money[Kind] > 0) {
              HasMoney = 1;
            }
          if (Kind == 6) break;
          Kind++;
        }
      }
    }
    if ((*FPD(TCharacter (*), SheetCharacter)).Items != 0) {
      rtl_str_assign(Menu, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){Menu, S("\006Items ")}));
    }
    if (HasSpells != 0) {
      rtl_str_assign(Menu, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){Menu, S("\007Spells ")}));
    }
    if (((((*FPD(TCharacter (*), SheetCharacter)).B84 < ComputerRun)) || (((*FPD(TCharacter (*), SheetCharacter)).Flag10D == 0))) || (((*FPD(TCharacter (*), SheetCharacter)).Status == 1))) {
      if (HasMoney && ((ViewMode != ViewModeCombat))) {
        rtl_str_assign(Menu, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){Menu, S("\006Trade ")}));
      }
    }
    if (HasMoney) {
      rtl_str_assign(Menu, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){Menu, S("\005Drop ")}));
    }
    rtl_str_assign(Menu, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){Menu, S("\004Exit")}));
    Key = ReadPromptChoice(S("\005View:"), Menu, 13, 10, 15, 0, 0, &ExtKey);
    Choice = 0xFFFF;
    switch ((u8)Key) {
    case 'I':
    {
      RunItemMenu(&(*Done));
      break;
    }
    case 'S':
    {
      Spell = ChooseSpellFromList(0, 0, &Choice, &HasSpells);
      break;
    }
    case 'T':
    {
      TradeMoney();
      break;
    }
    case 'D':
    {
      ChooseAndDropMoney();
      ShowCharacterMoney();
      break;
    }
    }
    if ((((*Done) == 0)) && ((Key == 'I' || Key == 'S' || Key == 'T'))) {
      ShowCharacterSheet();
    }
  }
  if (ViewMode == ViewModeCombat) {
    SwapPaletteColors0And8();
  }
  RedrawView();
}

/* ovl19:0D70. Asks whether Item may leave the character: ovl19:0EF8 calls it before its T, D and S
     actions (the call sites at ovl19:1339, 1365 and 1443). False when the item is readied: "Must be
     unreadied" is shown. True for an item that is not a scroll (IsScroll is false). For a scroll
     (IsScroll true) with a pending scribe (bit 7 set in one of Affects[1..3], whitepaper 5.22) it shows
     "<name> was going to scribe from that scroll" after the name and asks "is it Okay to lose it?";
     True only on Y. Otherwise True. Result: whether the item may go.
     Globals: SelectedCharacter (the name), GlyphCol and GlyphRow (the message follows the name on row 21).
     Side effect: rows 21 and 22 (columns 1 to 38) are cleared on every path. */
u8 CanGiveUpItem(PMenuLine Item)
{
  POOL_TRACE("CanGiveUpItem");
  u8 Result = 0;
  Result = 0;
  if ((*FPD(TMenuLine (*), Item)).Readied) {
    ShowFlashMessage(S("\021Must be unreadied"));
  } else if (!IsScroll(Item)) {
    Result = 1;
  } else if (((((*FPD(TMenuLine (*), Item)).Affects[0] > ScribeAffectThreshold)) || (((*FPD(TMenuLine (*), Item)).Affects[1] > ScribeAffectThreshold))) || (((*FPD(TMenuLine (*), Item)).Affects[2] > ScribeAffectThreshold))) {
    DrawCharacterName(SelectedCharacter, 1, 21, 0);
    GlyphCol = (*FPD(TCharacter (*), SelectedCharacter)).Name[0] + 2;
    GlyphRow = 21;
    ShowPagedText(1, 21, 38, 22, 14, 0, S("% was going to scribe from that scroll"));
    if (AskYesNo(S("\027is it Okay to lose it\077 "), 13, 10, 15) == 'Y') {
      Result = 1;
    }
  } else {
    Result = 1;
  }
  ClearWindow(1, 21, 38, 22);
  return Result;
}

/* ovl19:0EF8. The Items command of the View prompt (ViewSelectedCharacter's I key; whitepaper 5.4). It
     lists the items of SelectedCharacter with ChooseFromList under the words Ready (R), Use (U), Trade (T),
     Drop (D), Halve (H), Join (J), Sell (S) and Id (I), runs the chosen action and repeats until Escape or E
     is pressed, or Done is set. Ready runs ReadyItem. Use needs a readied item ("Must be Readied" otherwise)
     that IsScroll accepts, or one with Affects[2] above 0 and Affects[3] below $80; then it runs UseItem.
     Trade and Sell ask CanGiveUpItem, then run TradeItem or SellItem. Drop asks CanGiveUpItem,
     shows "Your <item> will be gone forever" and then "Drop It?", and on Y calls RemoveInventoryItem with
     SelectedCharacter and the item. Halve, Join and Id run HalveItem, JoinItem and IdentifyItem.
     Done: the stop flag shared with ViewSelectedCharacter; UseItem may set it. The item menu is drawn
     only when the character carries items; the Items window (rows 1 to 22) is drawn when DrawItemWindow
     is set or RedrawItemWindow is nonzero. The view mode ViewMode decides which words are offered: 1 (set by
     VisitTemple, ovl04:0D0F) offers Sell and Id; 2, 3 and 4 offer Use, and 5 (combat) offers Use only to
     a character whose Combat^.CanUseMagicItem is set. Trade is not offered in combat. */
void RunItemMenu(u8 (*Done))
{
  POOL_TRACE("RunItemMenu");
  u8 Key = 0;
  String40_RES06 Menu = {0};
  u8 Spare = 0;
  u8 DrawItemWindow = 0;
  u8 Redraw = 0;
  PMenuLine Cursor = 0;
  PMenuLine Selected = 0;
  s16 Choice = 0;
  u8 Spare2[4] = {0};
  PCharacter Character = 0;
  u8 OldCount = 0;
  u8 Spare3 = 0;
  u8 ts1[66];
  Character = SelectedCharacter;
  Key = ' ';
  Selected = (*FPD(TCharacter (*), Character)).Items;
  Choice = 0;
  Redraw = 1;
  DrawItemWindow = 1;
  while (!((Key == 0x00 || Key == 'E')) && (((*Done) == 0))) {
    if (!(((*FPD(TCharacter (*), Character)).ItemCountC7 > 0))) {
      return;
    }
    OldCount = (*FPD(TCharacter (*), Character)).ItemCountC7;
    if ((*FPD(TCharacter (*), Character)).Items != 0) {
      rtl_str_assign(Menu, 40, S("\005Ready"));
      if ((*FPD(TCharacter (*), Character)).Flag10D != 0) {
        if ((*FPD(TGameVars (*), GameVars))[229] == 0) {
          if (((((ViewMode == ViewModeCamp)) || ((ViewMode == ViewModeMap))) || ((ViewMode == ViewModeWall))) || ((((ViewMode == ViewModeCombat)) && (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Character)).Combat)).CanUseMagicItem != 0))))) {
            rtl_str_assign(Menu, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){Menu, S("\004 Use")}));
          }
        }
      }
      if (((((((*FPD(TCharacter (*), Character)).B84 < ComputerRun)) || (((*FPD(TCharacter (*), Character)).Flag10D == 0))) || (((*FPD(TCharacter (*), Character)).Status == 1)))) && ((ViewMode != ViewModeCombat))) {
        rtl_str_assign(Menu, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){Menu, S("\006 Trade")}));
      }
      rtl_str_assign(Menu, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){Menu, S("\005 Drop")}));
      if ((*FPD(TCharacter (*), Character)).ItemCountC7 < 16) {
        rtl_str_assign(Menu, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){Menu, S("\006 Halve")}));
      }
      rtl_str_assign(Menu, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){Menu, S("\005 Join")}));
      if (((((((*FPD(TCharacter (*), Character)).B84 < ComputerRun)) || (((*FPD(TCharacter (*), Character)).Flag10D == 0))) || (((*FPD(TCharacter (*), Character)).Status == 1)))) && ((ViewMode == ViewModeShop))) {
        rtl_str_assign(Menu, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){Menu, S("\005 Sell")}));
      }
      if (ViewMode == ViewModeShop) {
        rtl_str_assign(Menu, 40, rtl_str_cat(ts1, 2, (const u8 *const[]){Menu, S("\003 Id")}));
      }
      Cursor = (*FPD(TCharacter (*), Character)).Items;
      while (Cursor != 0) {
        FormatItemLine((s32)Character, Cursor, 0, 0, 1, 0);
        Cursor = (*FPD(TMenuLine (*), Cursor)).Next;
      }
      if (DrawItemWindow || ((RedrawItemWindow != 0))) {
        ClearFullScreen();
        DrawWindowFrame(1, 1, 38, 22, 0);
        DrawCharacterName(Character, 1, 1, 1);
        DrawTextAt((s16)((*FPD(TCharacter (*), Character)).Name[0] + 4), 1, 10, S("\005Items"));
        DrawWindow(1, 3, 38, 22, 0, 0, S("\000"));
        DrawTextAt(1, 3, 15, S("\012Ready Item"));
        Redraw = 1;
        DrawItemWindow = 0;
        RedrawItemWindow = 0;
      }
      Key = ChooseFromList(S("\000"), Menu, 13, 10, 15, 1, 5, 38, 22, (*FPD(TCharacter (*), Character)).Items, 1, &Redraw, &Choice, &Selected);
      if (Selected != 0) {
        switch ((u8)Key) {
        case 'R':
        {
          ReadyItem(Selected);
          break;
        }
        case 'U':
        {
          if (!(*FPD(TMenuLine (*), Selected)).Readied) {
            ShowFlashMessage(S("\017Must be Readied"));
            Key = ' ';
          } else if (IsScroll(Selected) || (((((*FPD(TMenuLine (*), Selected)).Affects[1] > 0)) && (((*FPD(TMenuLine (*), Selected)).Affects[2] < AffectFlag))))) {
            UseItem(Selected, &(*Done));
            if (ViewMode != ViewModeCombat) {
              (*Done) = 0;
            }
            if ((*Done) == 0) {
              DrawItemWindow = 1;
            }
          }
          break;
        }
        case 'T':
        {
          if (CanGiveUpItem(Selected)) {
            TradeItem(Selected);
          } else {
            Key = ' ';
          }
          DrawItemWindow = 1;
          break;
        }
        case 'D':
        {
          if (CanGiveUpItem(Selected)) {
            FormatItemLine((s32)Character, Selected, 0, 0, 0, 0);
            ShowPagedText(1, 21, 38, 22, 14, 1, rtl_str_cat(ts1, 3, (const u8 *const[]){S("\005Your "), (*FPD(TMenuLine (*), Selected)).Text, S("\024will be gone forever")}));
            if (AskYesNo(S("\011Drop It\077 "), 13, 10, 15) == 'Y') {
              RemoveInventoryItem(SelectedCharacter, Selected);
              Redraw = 1;
            }
            ClearWindow(1, 21, 38, 22);
          } else {
            Key = ' ';
          }
          break;
        }
        case 'H':
        {
          HalveItem(Selected);
          break;
        }
        case 'J':
        {
          JoinItem(Selected);
          break;
        }
        case 'S':
        {
          if (CanGiveUpItem(Selected)) {
            SellItem(Selected);
          } else {
            Key = ' ';
          }
          break;
        }
        case 'I':
        {
          IdentifyItem(Selected, &Redraw);
          break;
        }
        }
      }
      RecalcCombatValues(Character);
    }
    if ((*FPD(TCharacter (*), Character)).ItemCountC7 != OldCount) {
      Redraw = 1;
    }
  }
}

/* ovl19:14D0. The Ready action of the item menu (RunItemMenu's R key, ovl19:0EF8) and of the AI's item step
     (ovl09:13CA): readies Item for SelectedCharacter, or unreadies it when it is readied. Readying runs three
     groups of checks and the last one that fails sets Reason: the hands (HandsInUse plus the item's
     ItemTable[ItemType].Hands above MaxHands gives "Your hands are full!", not shown in combat when the computer
     fights for the character, Quick), the body slot ItemTable[ItemType].Slot (an item already in it gives "already
     using <name>"; the kinds $49 and $1C also check slots 11 and 12), and the classes ItemTable[ItemType].ClassMask
     allows (none of them in the character's ClassBits gives "Wrong Class"). When every check passes, the item is
     marked Readied and its affect is applied: CallAffectHandler with the item's Affects[3] byte when that byte
     is above $7F. Unreadying a readied item refuses a cursed one ("It's Cursed") and otherwise clears Readied
     and removes the affect. The routine never stores the item in SlotItems.
     Parameter: Item, the item. Globals: SelectedCharacter, ViewMode (the view mode, 5 for combat), ItemTable
     (indexed by item type, not by race). Side effects: messages (ShowFlashMessage); the "already using" case
     first redraws the slot item (FormatItemLine). QUIRK ovl19:15BB: slot 9 is tested at SlotItems[10]
     (+$F4) but the message names SlotItems[9] (+$F0). */
void ReadyItem(PMenuLine Item)
{
  POOL_TRACE("ReadyItem");
  u8 AffectOn = 0;
  u8 Reason = 0;
  u8 Slot = 0;
  PCharacter Character = 0;
  u8 ts1[55];
  AffectOn = ((*FPD(TMenuLine (*), Item)).Affects[2] > AffectThreshold);
  Character = SelectedCharacter;
  if ((*FPD(TMenuLine (*), Item)).Readied) {
    if ((*FPD(TMenuLine (*), Item)).Cursed) {
      ShowFlashMessage(S("\013It's Cursed"));
    } else {
      (*FPD(TMenuLine (*), Item)).Readied = 0;
      if (AffectOn) {
        CallAffectHandler((*FPD(TMenuLine (*), Item)).Affects[2], Character, Item, 1);
      }
    }
  } else {
    Reason = ReadyItem_ReadyOk;
    if ((s16)((*FPD(TCharacter (*), Character)).HandsInUse + ItemTable[(*FPD(TMenuLine (*), Item)).ItemType].Hands) > ReadyItem_MaxHands) {
      Reason = ReadyItem_ReadyHandsFull;
    }
    Slot = ItemTable[(*FPD(TMenuLine (*), Item)).ItemType].Slot;
    switch (Slot) {
    case 0:
    case 1:
    case 2:
    case 3:
    case 4:
    case 5:
    case 6:
    case 7:
    case 8:
    {
      if ((*FPD(TCharacter (*), Character)).SlotItems[Slot] != 0) {
        Reason = ReadyItem_ReadySlotUsed;
      }
      break;
    }
    case ReadyItem_QuirkSlot:
    {
      if ((*FPD(TCharacter (*), Character)).SlotItems[10] != 0) {
        Reason = ReadyItem_ReadySlotUsed;
      }
      break;
    }
    }
    if ((*FPD(TMenuLine (*), Item)).ItemType == 0x49) {
      if ((*FPD(TCharacter (*), Character)).SlotItems[11] != 0) {
        Reason = ReadyItem_ReadySlotUsed;
        Slot = 11;
      }
    }
    if ((*FPD(TMenuLine (*), Item)).ItemType == 0x1C) {
      if ((*FPD(TCharacter (*), Character)).SlotItems[12] != 0) {
        Reason = ReadyItem_ReadySlotUsed;
        Slot = 12;
      }
    }
    if (((ItemTable[(*FPD(TMenuLine (*), Item)).ItemType].ClassMask & (*FPD(TCharacter (*), Character)).ClassBits)) == 0) {
      Reason = ReadyItem_ReadyWrongClass;
    }
    switch (Reason) {
    case ReadyItem_ReadyOk:
    {
      (*FPD(TMenuLine (*), Item)).Readied = 1;
      if (AffectOn) {
        CallAffectHandler((*FPD(TMenuLine (*), Item)).Affects[2], Character, Item, 0);
      }
      break;
    }
    case ReadyItem_ReadyWrongClass:
    {
      ShowFlashMessage(S("\013Wrong Class"));
      break;
    }
    case ReadyItem_ReadySlotUsed:
    {
      FormatItemLine((s32)Character, (*FPD(TCharacter (*), Character)).SlotItems[Slot], 0, 0, 0, 0);
      ShowFlashMessage(rtl_str_cat(ts1, 2, (const u8 *const[]){S("\016already using "), (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Character)).SlotItems[Slot])).Text}));
      break;
    }
    case ReadyItem_ReadyHandsFull:
    {
      if (((ViewMode != ViewModeCombat)) || (((*FPD(TCharacter (*), Character)).Quick == 0))) {
        ShowFlashMessage(S("\024Your hands are full!"));
      }
      break;
    }
    }
  }
}

/* ovl19:1734. The Trade action of the item menu (RunItemMenu's T key, after CanGiveUpItem; ovl19:0EF8).
     Redraws the screen, then asks "Trade with Whom?" (SelectPartyMember), which picks the recipient into Recipient,
     starting from the viewed character (ViewedCharacter). Nothing is traded when no member is picked. Otherwise ViewedCharacter
     is set to the recipient. When WouldOverloadInventory refuses the recipient, "Overloaded" is shown and the
     item stays. Otherwise the item goes to AddItemCopy with the recipient and to RemoveInventoryItem with
     SelectedCharacter (the Drop action makes the same RemoveInventoryItem call), and the recipient's carried weight
     is recalculated (RecalcCombatValues). Parameter: Item, the item traded. Globals: ViewedCharacter (the viewed character),
     SelectedCharacter (the giver). Side effects: the screen (RedrawView) and the messages. */
void TradeItem(PMenuLine Item)
{
  POOL_TRACE("TradeItem");
  PCharacter Recipient = 0;
  Recipient = ViewedCharacter;
  RedrawView();
  SelectPartyMember(S("\020Trade with Whom\077"), 1, &Recipient);
  if (Recipient != 0) {
    ViewedCharacter = Recipient;
    if (WouldOverloadInventory(Recipient, Item)) {
      ShowFlashMessage(S("\012Overloaded"));
    } else {
      AddItemCopy(Recipient, Item);
      RemoveInventoryItem(SelectedCharacter, Item);
      RecalcCombatValues(Recipient);
    }
  }
}

/* ovl19:17ED. The Halve action of the item menu (RunItemMenu's H key, ovl19:0EF8): splits the stack Item
     in two. Half is its Count div 2; when Half is zero "Can't halve that" is shown. Otherwise a new record
     (New, 63 bytes) is a copy of Item with Count Half and not Readied, linked in after Item: it takes Item's
     old Next, and Item keeps the rest of the count (Count minus Half) and points at the new record. Parameter:
     Item, the stack halved. Side effects: a new item record is allocated (it is never freed here); the
     message (ShowFlashMessage). */
void HalveItem(PMenuLine Item)
{
  POOL_TRACE("HalveItem");
  PMenuLine NewItem = 0;
  u8 Half = 0;
  u8 Rest = 0;
  Half = ((*FPD(TMenuLine (*), Item)).Count / 2);
  if (Half > 0) {
    Rest = (*FPD(TMenuLine (*), Item)).Count - Half;
    NewItem = rtl_getmem(63);
    rtl_Move((void *)&(*FPD(TMenuLine (*), Item)), (void *)&(*FPD(TMenuLine (*), NewItem)), 63);
    (*FPD(TMenuLine (*), NewItem)).Count = Half;
    (*FPD(TMenuLine (*), NewItem)).Readied = 0;
    (*FPD(TMenuLine (*), NewItem)).Next = (*FPD(TMenuLine (*), Item)).Next;
    (*FPD(TMenuLine (*), Item)).Count = Rest;
    (*FPD(TMenuLine (*), Item)).Next = NewItem;
  } else {
    ShowFlashMessage(S("\020Can't halve that"));
  }
}

/* ovl19:189D. The Join action of the item menu (RunItemMenu's J key, ovl19:0EF8): gathers into Item the counts
     of the other items of SelectedCharacter that match it. A match has a nonzero Count, the same NameNum[1..3],
     ItemType, Plus, PlusSave, Cursed and Weight, and Affects[1] below 2 (QUIRK ovl19:19A1 below). Each match is
     taken off the character (RemoveInventoryItem) and its count added to the total, while the total stays at most
     255. When the total would pass 255, Target is filled to 255, the match gives up what is needed to make
     255 (its count drops) and the match becomes the item that gathers the rest. Parameter: Item, the stack
     that gathers. Globals: SelectedCharacter (its Items list). Side effects: matches leave the list.
     QUIRK ovl19:19A1: the Affects[1], Affects[2] and Affects[3] tests compare the match with itself (both
     sides read Cursor), so they never reject a match; only the Affects[1] below 2 test (ovl19:19B4) does. */
void JoinItem(PMenuLine Item)
{
  POOL_TRACE("JoinItem");
  PMenuLine Cursor = 0;
  PMenuLine Next = 0;
  PMenuLine Target = 0;
  u8 Total = 0;
  Target = Item;
  Total = (*FPD(TMenuLine (*), Target)).Count;
  Cursor = (*FPD(TCharacter (*), SelectedCharacter)).Items;
  while (Cursor != 0) {
    Next = (*FPD(TMenuLine (*), Cursor)).Next;
    if (((((((((((((((Cursor != Target)) && (((*FPD(TMenuLine (*), Cursor)).Count > 0))) && (((*FPD(TMenuLine (*), Cursor)).NameNum[0] == (*FPD(TMenuLine (*), Target)).NameNum[0]))) && (((*FPD(TMenuLine (*), Cursor)).NameNum[1] == (*FPD(TMenuLine (*), Target)).NameNum[1]))) && (((*FPD(TMenuLine (*), Cursor)).NameNum[2] == (*FPD(TMenuLine (*), Target)).NameNum[2]))) && (((*FPD(TMenuLine (*), Cursor)).ItemType == (*FPD(TMenuLine (*), Target)).ItemType))) && (((*FPD(TMenuLine (*), Cursor)).Plus == (*FPD(TMenuLine (*), Target)).Plus))) && (((*FPD(TMenuLine (*), Cursor)).PlusSave == (*FPD(TMenuLine (*), Target)).PlusSave))) && (((*FPD(TMenuLine (*), Cursor)).Cursed == (*FPD(TMenuLine (*), Target)).Cursed))) && (((*FPD(TMenuLine (*), Cursor)).Weight == (*FPD(TMenuLine (*), Target)).Weight))) && (((*FPD(TMenuLine (*), Cursor)).Affects[0] == (*FPD(TMenuLine (*), Cursor)).Affects[0]))) && (((*FPD(TMenuLine (*), Cursor)).Affects[0] < 2))) && (((*FPD(TMenuLine (*), Cursor)).Affects[1] == (*FPD(TMenuLine (*), Cursor)).Affects[1]))) && (((*FPD(TMenuLine (*), Cursor)).Affects[2] == (*FPD(TMenuLine (*), Cursor)).Affects[2]))) {
      if ((s16)(Total + (*FPD(TMenuLine (*), Cursor)).Count) <= 255) {
        Total += (*FPD(TMenuLine (*), Cursor)).Count;
        RemoveInventoryItem(SelectedCharacter, Cursor);
      } else {
        (*FPD(TMenuLine (*), Target)).Count = 255;
        (*FPD(TMenuLine (*), Cursor)).Count = (*FPD(TMenuLine (*), Cursor)).Count - ((s16)(255 - Total));
        Total = (*FPD(TMenuLine (*), Cursor)).Count;
        Target = Cursor;
      }
    }
    Cursor = Next;
  }
  (*FPD(TMenuLine (*), Target)).Count = Total;
}

/* ovl19:1A8A. The Use action: Item, one of SelectedCharacter's items, is used and Done (the stop flag of the View
     prompt and the item menu) is set to what the use ends with. Called by RunItemMenu (the U key, ovl19:0EF8) and by
     UseMagicItem (ovl09:03E4). A scroll (IsScroll true) gives its spell by ChooseSpellFromList ("on Scroll", with
     Choice -1 it opens the Spells window) and is remembered in CurrentItem. Any other item with Affects[2] above 0 and
     Affects[3] below AffectFlag gives the spell Affects[2] and sets ItemAffectUse. No spell (0, or none chosen) sets
     Done to 0. Otherwise, in combat (view mode 5) for a character the computer does not fight for (Quick 0),
     DrawCombatScreen runs first. An affect item's use shows "uses an item" and the item's line (ShowCharacterMessage,
     FormatItemLine, a delay). CastChosenSpell casts the spell and sets Done; in combat a spell whose SpellTable row has byte
     +$B set takes Done from EndCombatTurn instead. With Done set, a scroll is used up through ConsumeScrollSpell; an item that
     is not a scroll and has Affects[1] above 0 loses one of its Count when the count is above 1, else one charge
     (Affects[1]), and leaves the character (RemoveInventoryItem) with its last charge. Parameters: Item, Done. Globals:
     SelectedCharacter, ViewMode (the view mode, 5 for combat), SpellTable, CurrentItem, ItemAffectUse. Side effects:
     messages, the screen (the item line is on row 22, or 23 in combat). */
void UseItem(PMenuLine Item, u8 (*Done))
{
  POOL_TRACE("UseItem");
  u8 Spell = 0;
  u16 Choice = 0;
  u8 Listed = 0;
  Choice = 0xFFFF;
  ItemAffectUse = 0;
  Spell = 0;
  if (IsScroll(Item)) {
    CurrentItem = Item;
    Spell = ChooseSpellFromList(UseItem_SpellListOnScroll, UseItem_UseListMode, &Choice, &Listed);
  } else if ((((*FPD(TMenuLine (*), Item)).Affects[1] > 0)) && (((*FPD(TMenuLine (*), Item)).Affects[2] < AffectFlag))) {
    ItemAffectUse = 1;
    Spell = (*FPD(TMenuLine (*), Item)).Affects[1];
  }
  if (Spell == 0) {
    (*Done) = 0;
  } else {
    if (((ViewMode == ViewModeCombat)) && (((*FPD(TCharacter (*), SelectedCharacter)).Quick == 0))) {
      DrawCombatScreen();
    }
    if (ItemAffectUse) {
      if (Spell > LastSpell) {
        Spell -= UseItem_SpellShift;
      }
      ShowCharacterMessage(SelectedCharacter, S("\014uses an item"), 10, 0);
      if (ViewMode == ViewModeCombat) {
        DrawTextAt(0, UseItem_ItemPromptRow, UseItem_TitleColor, S("\005Item:"));
        FormatItemLine((s32)SelectedCharacter, Item, 5, UseItem_ItemPromptRow, 0, 1);
      } else {
        FormatItemLine((s32)SelectedCharacter, Item, 1, 22, 0, 1);
      }
      DelayByGameSpeed();
      ClearCharacterMessage();
    }
    ItemAffectUse = 1;
    CastChosenSpell(Spell, (*FPD(TCharacter (*), SelectedCharacter)).Quick, 0, &(*Done));
    ItemAffectUse = 0;
    if (((ViewMode == ViewModeCombat)) && ((SpellTable[Spell].PadB[0] != 0))) {
      (*Done) = EndCombatTurn(SelectedCharacter);
    }
  }
  if ((*Done) != 0) {
    if (IsScroll(Item)) {
      ConsumeScrollSpell(SelectedCharacter, Item, Spell);
    } else if ((*FPD(TMenuLine (*), Item)).Affects[0] > 0) {
      if ((*FPD(TMenuLine (*), Item)).Count > 1) {
        (*FPD(TMenuLine (*), Item)).Count--;
      } else {
        (*FPD(TMenuLine (*), Item)).Affects[0]--;
        if ((*FPD(TMenuLine (*), Item)).Affects[0] == 0) {
          RemoveInventoryItem(SelectedCharacter, Item);
        }
      }
    }
  }
}

/* ovl19:1CEE. The Sell action of the item menu (RunItemMenu's S key, ovl19:0EF8, after CanGiveUpItem): the offer for
     Item is half its Value in gold (Value div 2), and a stack of more than one item is offered its Count times that
     offer divided by StackDivisor (QUIRK ovl19:1D1A). The offer is shown on row 21 as "I'll give you <offer> gold
     pieces for your <name>" and the character is asked "Is It a Deal? ". On Y, "Sold!" is shown, the item leaves
     SelectedCharacter (RemoveInventoryItem) and the offer is paid as platinum (GoldPerPlatinum gold each, Offer div 5) and
     gold (Offer mod 5). Every coin weighs one, so WouldOverload (ovl21:0054) may refuse them: then "Overloaded.
     Money will be put in pool." is shown, Room (what he can still carry) limits the platinum that goes to him, and
     the rest goes to PooledMoney[PlatinumKind]. Parameter: Item. Globals: SelectedCharacter (the seller),
     SheetCharacter (the item line FormatItemLine draws at ovl19:1D55), PooledMoney. Side effects: messages, the
     window rows 21 and 22 (cleared at the end). QUIRK ovl19:1D1A: the test for kind $49 is followed by a test of the
     same kind for $1C, so the $1C branch (ovl19:1D46, the stack offer without the division) is never taken. */
void SellItem(PMenuLine Item)
{
  POOL_TRACE("SellItem");
  u16 Offer = 0;
  u16 Platinum = 0;
  u16 Gold = 0;
  u16 Room = 0;
  u8 ts1[256];
  u8 ts2[256];
  Offer = 0;
  if ((*FPD(TMenuLine (*), Item)).Value > 0) {
    Offer = ((*FPD(TMenuLine (*), Item)).Value / 2);
  }
  if ((*FPD(TMenuLine (*), Item)).Count > 1) {
    if (!(((((*FPD(TMenuLine (*), Item)).ItemType == SellItem_ItemKindSlot11)) && (((*FPD(TMenuLine (*), Item)).ItemType == SellItem_ItemKindSlot12))))) {
      Offer = (((u16)(Offer * (*FPD(TMenuLine (*), Item)).Count)) / SellItem_StackDivisor);
    } else {
      Offer = Offer * (*FPD(TMenuLine (*), Item)).Count;
    }
  }
  FormatItemLine((s32)SheetCharacter, Item, 0, 0, 0, 0);
  ShowPagedText(SellItem_MessageLeft, SellItem_MessageTop, SellItem_MessageRight, SellItem_MessageBottom, SellItem_MessageColor, 1, rtl_str_cat(ts2, 4, (const u8 *const[]){S("\016I'll give you "), WordToText(ts1, Offer), S("\026 gold pieces for your "), (*FPD(TMenuLine (*), Item)).Text}));
  if (AskYesNo(S("\016Is It a Deal\077 "), 13, 10, 15) == 'Y') {
    ShowFlashMessage(S("\005Sold!"));
    RemoveInventoryItem(SelectedCharacter, Item);
    Platinum = (Offer / SellItem_GoldPerPlatinum);
    Gold = (Offer % SellItem_GoldPerPlatinum);
    if (WouldOverload(SelectedCharacter, (u16)(Gold + Platinum), &Room)) {
      ShowFlashMessage(S("'Overloaded.  Money will be put in pool."));
      if (Room > Platinum) {
        (*FPD(TCharacter (*), SelectedCharacter)).Money[4] += Platinum;
      } else {
        (*FPD(TCharacter (*), SelectedCharacter)).Money[4] += Room;
        PooledMoney[4] += (u16)(Platinum - Room);
      }
      (*FPD(TCharacter (*), SelectedCharacter)).Money[3] += Gold;
    } else {
      (*FPD(TCharacter (*), SelectedCharacter)).Money[4] += Platinum;
      (*FPD(TCharacter (*), SelectedCharacter)).Money[3] += Gold;
    }
  }
  ClearWindow(SellItem_MessageLeft, SellItem_MessageTop, SellItem_MessageRight, SellItem_MessageBottom);
}

/* ovl19:1F52. The Id action of the item menu (RunItemMenu's I key, ovl19:0EF8; whitepaper 5.4): identifies Item
     for 200 gold pieces. It shows "For 200 gold pieces I'll identify your <item>" and asks "Is It a Deal? ". On Y
     the price comes from SelectedCharacter's money (CharacterMoneyValueInGold, SetCharacterGold) or else from the
     pooled money (PooledMoney, SetPooledGold); when neither covers it, "Not Enough Money" is shown. A paid item
     whose HiddenNames is set is identified: HiddenNames is cleared, its line is drawn again (FormatItemLine), "It
     looks like some sort of <item>" is shown and Redraw is set. Otherwise "I can't tell anything new about your
     <item>" is shown. Parameters: Item, the item; Redraw, the var flag of the item list (1: draw it again).
     Side effects: rows 21 and 22 (columns 1 to 38) are cleared at the end; DelayByGameSpeed after a payment. */
void IdentifyItem(PMenuLine Item, u8 (*Redraw))
{
  POOL_TRACE("IdentifyItem");
  s32 CharacterGold = 0;
  s32 PooledGold = 0;
  u8 Paid = 0;
  u8 ts1[80];
  Paid = 0;
  FormatItemLine((s32)SheetCharacter, Item, 0, 0, 0, 0);
  ShowPagedText(IdentifyItem_MessageLeft, IdentifyItem_MessageTop, IdentifyItem_MessageRight, IdentifyItem_MessageBottom, IdentifyItem_MessageColor, ClearTextBeforeMessage, rtl_str_cat(ts1, 2, (const u8 *const[]){S("'For 200 gold pieces I'll identify your "), (*FPD(TMenuLine (*), Item)).Text}));
  if (AskYesNo(S("\016Is It a Deal\077 "), IdentifyItem_PromptTitleColor, IdentifyItem_PromptWordColor, IdentifyItem_PromptHotColor) == 'Y') {
    CharacterGold = CharacterMoneyValueInGold(SelectedCharacter);
    if (CharacterGold >= IdentifyItem_IdentifyPrice) {
      Paid = 1;
      CharacterGold -= IdentifyItem_IdentifyPrice;
      SetCharacterGold(CharacterGold);
    } else {
      PooledGold = MoneyValueInGold(&PooledMoney);
      if (PooledGold >= IdentifyItem_IdentifyPrice) {
        Paid = 1;
        PooledGold -= IdentifyItem_IdentifyPrice;
        SetPooledGold(PooledGold);
      } else {
        ShowFlashMessage(S("\020Not Enough Money"));
      }
    }
  }
  if (Paid) {
    if ((*FPD(TMenuLine (*), Item)).HiddenNames == 0) {
      ShowPagedText(IdentifyItem_MessageLeft, IdentifyItem_MessageTop, IdentifyItem_MessageRight, IdentifyItem_MessageBottom, IdentifyItem_MessageColor, ClearTextBeforeMessage, rtl_str_cat(ts1, 2, (const u8 *const[]){S("%I can't tell anything new about your "), (*FPD(TMenuLine (*), Item)).Text}));
    } else {
      (*FPD(TMenuLine (*), Item)).HiddenNames = 0;
      FormatItemLine((s32)SheetCharacter, Item, 0, 0, 0, 0);
      ShowPagedText(IdentifyItem_MessageLeft, IdentifyItem_MessageTop, IdentifyItem_MessageRight, IdentifyItem_MessageBottom, IdentifyItem_MessageColor, ClearTextBeforeMessage, rtl_str_cat(ts1, 2, (const u8 *const[]){S("\033It looks like some sort of "), (*FPD(TMenuLine (*), Item)).Text}));
      (*Redraw) = 1;
    }
  }
  if (Paid) {
    DelayByGameSpeed();
  }
  ClearWindow(IdentifyItem_MessageLeft, IdentifyItem_MessageTop, IdentifyItem_MessageRight, IdentifyItem_MessageBottom);
}

/* ovl19:2156. The Trade command of the View prompt for money (ViewSelectedCharacter's T key; whitepaper 5.4):
     gives money of SelectedCharacter to another member. "Trade to?" asks for the recipient (SelectPartyMember), which
     is kept in ViewedCharacter. The coin kinds SelectedCharacter holds are listed under "Select type of coin", each with
     its amount, its name right-aligned in eight columns. The chosen kind is asked for ("How much <kind> will you
     trade? ", ReadAmount, at most the character's money of that kind) and TransferMoney moves it to the recipient.
     The list is built again while money is left, and the recipient is asked again when the list is left with
     money still held. Parameters: none. Globals: ViewedCharacter (the recipient), SelectedCharacter (the giver).
     Side effects: the screen (RedrawView, ShowCharacterSheet, ShowCharacterMoney) and the menu lines (GetMem,
     FreeMenuList). Its list is the one TakeMoney (ovl21:0CEB) builds for the pool.
     QUIRK ovl19:21EE: Kinds is incremented for every listed kind and never read.
     QUIRK ovl19:2468: Finished is not set when the list is cancelled before any transfer, so the test reads the
     byte the frame held before the call. */
void TradeMoney(void)
{
  POOL_TRACE("TradeMoney");
  PCharacter Recipient = 0;
  s8 Kind = 0;
  s8 CoinKind = 0;
  u8 I = 0;
  u8 Pad = 0;
  PMenuLine List = 0;
  PMenuLine Chosen = 0;
  PMenuLine Head = 0;
  u16 Kinds = 0;
  s16 Choice = 0;
  u8 Num[16] = {0};
  u8 Spaces[5] = {0};
  u8 Text[256] = {0};
  u8 Key = 0;
  u16 Amount = 0;
  u8 Finished = 0;
  u8 Done = 0;
  u8 Redraw = 0;
  u8 ts1[256];
  do {
    Recipient = ViewedCharacter;
    RedrawView();
    SelectPartyMember(S("\011Trade to\077"), 1, &Recipient);
    if (Recipient == 0) {
      Finished = 1;
    } else {
      ShowCharacterSheet();
      do {
        ShowCharacterMoney();
        ViewedCharacter = Recipient;
        List = 0;
        Chosen = 0;
        Head = 0;
        Kinds = 0;
        {
          if (0 <= TradeMoney_LastMoneyKind) {
            Kind = 0;
            for (;;) {
                if ((*FPD(TCharacter (*), SelectedCharacter)).Money[Kind] != 0) {
                  Kinds++;
                  if (List == 0) {
                    List = rtl_getmem(MenuLineBytes);
                    (*FPD(TMenuLine (*), List)).Next = 0;
                  } else {
                    Chosen = List;
                    List = rtl_getmem(MenuLineBytes);
                    (*FPD(TMenuLine (*), List)).Next = Chosen;
                  }
                  rtl_str_int(Num, 15, (*FPD(TCharacter (*), SelectedCharacter)).Money[Kind], 0);
                  Pad = TradeMoney_NameColumnWidth - MoneyKindNames[Kind][0];
                  rtl_str_assign(Spaces, 4, S("\000"));
                  Spaces[0] = (u8)Pad;
                  {
                    u8 limit = Pad;
                    if (1 <= limit) {
                      I = 1;
                      for (;;) {
                          Spaces[I] = ' ';
                        if (I == limit) break;
                        I++;
                      }
                    }
                  }
                  rtl_str_assign((*FPD(TMenuLine (*), List)).Text, 40, rtl_str_cat(ts1, 4, (const u8 *const[]){Spaces, MoneyKindNames[Kind], S("\001 "), Num}));
                  (*FPD(TMenuLine (*), List)).Flag29 = 0;
                }
              if (Kind == TradeMoney_LastMoneyKind) break;
              Kind++;
            }
          }
        }
        Head = List;
        Choice = 0;
        Redraw = 1;
        Key = ChooseFromList(S("\023Select type of coin"), S("\000"), TradeMoney_ListHeadingColor, TradeMoney_ListLineColor, TradeMoney_ListHighlightColor, TradeMoney_ListLeft, TradeMoney_ListTop, TradeMoney_ListRight, TradeMoney_ListBottom, List, 1, &Redraw, &Choice, &Chosen);
        if (Chosen == 0) {
          Done = 1;
        } else {
          rtl_str_assign(Text, 255, S("\000"));
          CoinKind = MoneyKindOfLine((*FPD(TMenuLine (*), Chosen)).Text, &Text);
          rtl_str_assign(Text, 255, rtl_str_cat(ts1, 3, (const u8 *const[]){S("\011How much "), Text, S("\020will you trade\077 ")}));
          Amount = ReadAmount((*FPD(TCharacter (*), SelectedCharacter)).Money[CoinKind], Text, TradeMoney_AmountColor);
          TransferMoney(&SelectedCharacter, &Recipient, Amount, CoinKind);
          Done = 1;
          Finished = 1;
          {
            if (0 <= TradeMoney_LastMoneyKind) {
              Kind = 0;
              for (;;) {
                  if ((*FPD(TCharacter (*), SelectedCharacter)).Money[Kind] > 0) {
                    Finished = 0;
                    Done = 0;
                  }
                if (Kind == TradeMoney_LastMoneyKind) break;
                Kind++;
              }
            }
          }
        }
        if (Head != 0) {
          FreeMenuList(&Head);
        }
      } while (!(Done));
    }
  } while (!(Finished));
}

/* ovl19:24A7. The Drop command for money of the View prompt (ViewSelectedCharacter's D key, whitepaper 5.4; the
     Drop entry shows only while the character holds money): draws the money window (ShowCharacterMoney), then lists
     the coin kinds SelectedCharacter holds under "Select type of coin", each with its amount, and asks for one
     (ChooseFromList). "How much <kind> will you drop? " asks for the amount (ReadAmount, at most the money of that kind)
     and DropMoney takes it away (ovl21:0A01). The list is built again while money is left; the menu ends when the
     list is left or no money is left. Parameters: none. Globals: SelectedCharacter (the giver). Side effects: the
     screen (the list, the prompt) and the list lines (GetMem, FreeMenuList).
     QUIRK ovl19:24EF: Kinds is incremented for every listed kind and never read. */
void ChooseAndDropMoney(void)
{
  POOL_TRACE("ChooseAndDropMoney");
  s8 Kind = 0;
  s8 CoinKind = 0;
  u8 Pad = 0;
  u8 I = 0;
  u16 Kinds = 0;
  s16 Choice = 0;
  PMenuLine List = 0;
  PMenuLine Chosen = 0;
  PMenuLine Head = 0;
  u8 Done = 0;
  u8 Redraw = 0;
  u8 Num[16] = {0};
  u8 Spaces[5] = {0};
  u8 Text[256] = {0};
  u8 Key = 0;
  u16 Amount = 0;
  u8 ts1[256];
  do {
    ShowCharacterMoney();
    List = 0;
    Chosen = 0;
    Head = 0;
    Kinds = 0;
    {
      if (0 <= ChooseAndDropMoney_LastMoneyKind) {
        Kind = 0;
        for (;;) {
            if ((*FPD(TCharacter (*), SelectedCharacter)).Money[Kind] != 0) {
              Kinds++;
              if (List == 0) {
                List = rtl_getmem(MenuLineBytes);
                (*FPD(TMenuLine (*), List)).Next = 0;
              } else {
                Chosen = List;
                List = rtl_getmem(MenuLineBytes);
                (*FPD(TMenuLine (*), List)).Next = Chosen;
              }
              rtl_str_int(Num, 15, (*FPD(TCharacter (*), SelectedCharacter)).Money[Kind], 0);
              Pad = ChooseAndDropMoney_NameColumnWidth - MoneyKindNames[Kind][0];
              rtl_str_assign(Spaces, 4, S("\000"));
              Spaces[0] = (u8)Pad;
              {
                u8 limit = Pad;
                if (1 <= limit) {
                  I = 1;
                  for (;;) {
                      Spaces[I] = ' ';
                    if (I == limit) break;
                    I++;
                  }
                }
              }
              rtl_str_assign((*FPD(TMenuLine (*), List)).Text, 40, rtl_str_cat(ts1, 4, (const u8 *const[]){Spaces, MoneyKindNames[Kind], S("\001 "), Num}));
              (*FPD(TMenuLine (*), List)).Flag29 = 0;
            }
          if (Kind == ChooseAndDropMoney_LastMoneyKind) break;
          Kind++;
        }
      }
    }
    Head = List;
    Choice = 0;
    Redraw = 1;
    Key = ChooseFromList(S("\023Select type of coin"), S("\000"), ChooseAndDropMoney_ListHeadingColor, ChooseAndDropMoney_ListLineColor, ChooseAndDropMoney_ListHighlightColor, ChooseAndDropMoney_ListLeft, ChooseAndDropMoney_ListTop, ChooseAndDropMoney_ListRight, ChooseAndDropMoney_ListBottom, List, 1, &Redraw, &Choice, &Chosen);
    if (Chosen == 0) {
      Done = 1;
    } else {
      rtl_str_assign(Text, 255, S("\000"));
      CoinKind = MoneyKindOfLine((*FPD(TMenuLine (*), Chosen)).Text, &Text);
      rtl_str_assign(Text, 255, rtl_str_cat(ts1, 3, (const u8 *const[]){S("\011How much "), Text, S("\017will you drop\077 ")}));
      Amount = ReadAmount((*FPD(TCharacter (*), SelectedCharacter)).Money[CoinKind], Text, ChooseAndDropMoney_AmountColor);
      DropMoney(SelectedCharacter, Amount, CoinKind);
      Done = 1;
      {
        if (0 <= ChooseAndDropMoney_LastMoneyKind) {
          Kind = 0;
          for (;;) {
              if ((*FPD(TCharacter (*), SelectedCharacter)).Money[Kind] > 0) {
                Done = 0;
              }
            if (Kind == ChooseAndDropMoney_LastMoneyKind) break;
            Kind++;
          }
        }
      }
    }
    if (Head != 0) {
      FreeMenuList(&Head);
    }
  } while (!(Done));
}

/* ovl19:275B: rejects an item when the character already has more than 15 items or when its added
     weight exceeds the character's strength-based capacity plus 1500. The item weight is multiplied
     by its count only when the count is nonzero. The call to RecalcCombatValues occurs before the checks. */
u8 WouldOverloadInventory(PCharacter Character, PMenuLine Item)
{
  POOL_TRACE("WouldOverloadInventory");
  u8 Result = 0;
  u8 Overloaded = 0;
  u16 AddedWeight = 0;
  RecalcCombatValues(Character);
  Overloaded = 0;
  if ((*FPD(TCharacter (*), Character)).ItemCountC7 > WouldOverloadInventory_MaximumItemCount) {
    Overloaded = 1;
  }
  AddedWeight = (*FPD(TMenuLine (*), Item)).Weight;
  if ((*FPD(TMenuLine (*), Item)).Count > 0) {
    AddedWeight = AddedWeight * (*FPD(TMenuLine (*), Item)).Count;
  }
  if ((u16)((*FPD(TCharacter (*), Character)).CarriedWeight + AddedWeight) > (s16)(StrengthWeightAllowance(Character) + WouldOverloadInventory_BaseCarryAllowance)) {
    Overloaded = 1;
  }
  Result = Overloaded;
  return Result;
}

/* ovl19:27DF. Updates SelectedCharacter from the party list: G selects the previous member, wrapping
     from the first member to the last; O selects the next member, wrapping to the head; other keys
     select the head. */
void UpdateSelectedCharacter(u8 Key)
{
  POOL_TRACE("UpdateSelectedCharacter");
  PCharacter Character = 0;
  Character = PartyListHead;
  if (Character != 0) {
    switch ((u8)Key) {
    case 'G':
    {
      if (Character == SelectedCharacter) {
        while ((*FPD(TCharacter (*), Character)).Next != 0) {
          Character = (*FPD(TCharacter (*), Character)).Next;
        }
      } else {
        while (((Character != 0)) && (((*FPD(TCharacter (*), Character)).Next != SelectedCharacter))) {
          Character = (*FPD(TCharacter (*), Character)).Next;
        }
      }
      break;
    }
    case 'O':
    {
      if ((*FPD(TCharacter (*), SelectedCharacter)).Next != 0) {
        Character = (*FPD(TCharacter (*), SelectedCharacter)).Next;
      }
      break;
    }
    default:
    {
      Character = PartyListHead;
    }
    }
  }
  SelectedCharacter = Character;
}

/* ovl19:28BE: converts Who's five coin words (+$88..+$90) to gold using CoinCopperValues, adds half a
     gold piece in copper before division, and returns the rounded total as a LongInt. The Temple keeps
     only its low word (ovl04:0177). QUIRK ovl19:28BE: the frame reserves [bp-$A], which is never accessed. */
s32 CharacterMoneyValueInGold(PCharacter Who)
{
  POOL_TRACE("CharacterMoneyValueInGold");
  s32 Result = 0;
  s32 TotalCopper = 0;
  s8 CoinIndex = 0;
  u8 UnusedFrameByte = 0;
  TotalCopper = 0;
  {
    if (0 <= CharacterMoneyValueInGold_LastCoinIndex) {
      CoinIndex = 0;
      for (;;) {
          TotalCopper += CoinCopperValues[CoinIndex] * (*FPD(TCharacter (*), Who)).Money[CoinIndex];
        if (CoinIndex == CharacterMoneyValueInGold_LastCoinIndex) break;
        CoinIndex++;
      }
    }
  }
  Result = ((TotalCopper + CharacterMoneyValueInGold_HalfGoldCopperValue) / CoinCopperValues[3]);
  return Result;
}

/* ovl19:299C. Sets Listed from the requested spell list. If Choice is negative it opens and titles the
     spell window; it then delegates selection to ovl22. */
u8 ChooseSpellFromList(u8 SpellListKind, u8 DisplayMode, u16 (*Choice), u8 (*Listed))
{
  POOL_TRACE("ChooseSpellFromList");
  u8 Result = 0;
  String40_RES06 ModeDescription = {0};
  u8 ts1[48];
  switch (SpellListKind) {
  case ChooseSpellFromList_SpellListInMemory:
  {
    rtl_str_assign(ModeDescription, 40, S("\011in Memory"));
    break;
  }
  case ChooseSpellFromList_SpellListInSpellBook:
  {
    rtl_str_assign(ModeDescription, 40, S("\015in Spell Book"));
    break;
  }
  case ChooseSpellFromList_SpellListOnScroll:
  {
    rtl_str_assign(ModeDescription, 40, S("\011on Scroll"));
    break;
  }
  case ChooseSpellFromList_SpellListOnScrolls:
  {
    rtl_str_assign(ModeDescription, 40, S("\012on Scrolls"));
    break;
  }
  case ChooseSpellFromList_SpellListToChooseFrom:
  {
    rtl_str_assign(ModeDescription, 40, S("\016to choose from"));
    break;
  }
  case ChooseSpellFromList_SpellListToMemorize:
  {
    rtl_str_assign(ModeDescription, 40, S("\017to be memorized"));
    break;
  }
  case ChooseSpellFromList_SpellListToScribe:
  {
    rtl_str_assign(ModeDescription, 40, S("\015to be scribed"));
    break;
  }
  default:
  {
    ModeDescription[0] = 0x00;
  }
  }
  (*Listed) = BuildSpellList(SpellListKind);
  if ((*Listed) != 0) {
    if ((*Choice) < 0) {
      DrawWindow(1, 1, 0x26, 1, 0, 0, S("\000"));
      DrawCharacterName(SelectedCharacter, 1, 1, 1);
      DrawTextAt((s16)((*FPD(TCharacter (*), SelectedCharacter)).Name[0] + 4), ChooseSpellFromList_TitleRow, ChooseSpellFromList_TitleColor, rtl_str_cat(ts1, 2, (const u8 *const[]){S("\007Spells "), ModeDescription}));
    }
    Result = PickSpellFromMenu(DisplayMode, &(*Choice));
  } else {
    Result = 0;
  }
  return Result;
}

/* Initialisation part of unit OVL19. */
void init_OVL19(void)
{
  POOL_TRACE("init");
}
