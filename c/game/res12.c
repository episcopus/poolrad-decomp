#include "game.h"

/* 00BA:0000. Applies the readied weapon to Who's attack values; RecalcCombatValues calls it after it
     has copied the character's base values. With no readied weapon (SlotItems[0], +$CC) it does
     nothing. Otherwise the weapon's item kind picks a ItemTable row (DS:5582): its byte 9 becomes
     Who^.WeaponAttacks (+$115), byte $A Who^.WeaponDamage (+$117) and byte $B the base of the
     signed Who^.WeaponDamageBonus (+$119). The attack flags byte $E adds the dexterity roll
     adjustment (DexterityAttackAdjustment) to HitAdjust (+$110, reset to Thac0 +$2D first) when mask
     WeaponFlagDexToHit (2) is set, and the strength roll (StrengthAttackAdjustment) to HitAdjust and the
     strength damage (StrengthDamageAdjustment) to the damage bonus when mask WeaponFlagStrength (4) is set;
     mask WeaponFlagSlot11Plus (1) adds the plus of slot item 11 (+$F8) and mask WeaponFlagSlot12Plus
     ($80) the plus of slot item 12 (+$FC) to the weapon's own plus. Race BonusRace (2) gets one more
     point with the bonus kinds.
     Globals: ItemTable. */
void ApplyWeaponBonuses(PCharacter Who)
{
  POOL_TRACE("ApplyWeaponBonuses");
  PItem Weapon = 0;
  u8 ItemType = 0;
  s8 WeaponPlus = 0;
  Weapon = (*FPD(TCharacter (*), Who)).SlotItems[0];
  if (Weapon == 0) {
    return;
  }
  ItemType = (*FPD(TMenuLine (*), Weapon)).ItemType;
  (*FPD(TCharacter (*), Who)).HitAdjust = (*FPD(TCharacter (*), Who)).Thac0;
  if (((ItemTable[ItemType].Flags & WeaponFlagDexToHit)) != 0) {
    (*FPD(TCharacter (*), Who)).HitAdjust = (*FPD(TCharacter (*), Who)).HitAdjust + DexterityAttackAdjustment(Who);
  }
  (*FPD(TCharacter (*), Who)).WeaponDamageBonus[0] = ItemTable[ItemType].BonusNormal;
  if (((ItemTable[ItemType].Flags & WeaponFlagStrength)) != 0) {
    (*FPD(TCharacter (*), Who)).HitAdjust = (*FPD(TCharacter (*), Who)).HitAdjust + StrengthAttackAdjustment(Who);
    (*FPD(TCharacter (*), Who)).WeaponDamageBonus[0] = (*FPD(TCharacter (*), Who)).WeaponDamageBonus[0] + StrengthDamageAdjustment(Who);
  }
  WeaponPlus = (*FPD(TMenuLine (*), Weapon)).Plus;
  if (ItemTable[ItemType].Flags > 0x7F) {
    if ((*FPD(TCharacter (*), Who)).SlotItems[12] != 0) {
      WeaponPlus = WeaponPlus + (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[12])).Plus;
    }
  }
  if (((ItemTable[ItemType].Flags & WeaponFlagSlot11Plus)) > 0) {
    if ((*FPD(TCharacter (*), Who)).SlotItems[11] != 0) {
      WeaponPlus = WeaponPlus + (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[11])).Plus;
    }
  }
  (*FPD(TCharacter (*), Who)).WeaponDamageBonus[0] = (*FPD(TCharacter (*), Who)).WeaponDamageBonus[0] + WeaponPlus;
  if ((((*FPD(TCharacter (*), Who)).Race == BonusRace)) && (((((((*FPD(TMenuLine (*), Weapon)).ItemType > BonusKindRangeLow)) && (((*FPD(TMenuLine (*), Weapon)).ItemType < BonusKindRangeHigh))) || (((*FPD(TMenuLine (*), Weapon)).ItemType == BonusKindLow))) || (((*FPD(TMenuLine (*), Weapon)).ItemType == BonusKindLower))))) {
    WeaponPlus++;
  }
  (*FPD(TCharacter (*), Who)).HitAdjust = (*FPD(TCharacter (*), Who)).HitAdjust + WeaponPlus;
  (*FPD(TCharacter (*), Who)).WeaponAttacks[0] = ItemTable[ItemType].DiceCountNormal;
  (*FPD(TCharacter (*), Who)).WeaponDamage[0] = ItemTable[ItemType].DiceSizeNormal;
}

/* 00BA:01FB. Sets Who's movement (Movement, +$11C) from a readied armour; RecalcCombatValues calls it
     for every readied item. It does nothing unless the item's kind (ItemTable[item type].Slot) is 2, an
     armour. Then the armour's weight (+$37) picks the movement: at most $96 keeps the character's
     base movement (BaseMovement, +$72), $97..$18F gives 9 and anything else 6. A magic armour
     (Plus, +$32, not 0) adds 3 while the movement is at most 9.
     Globals: ItemTable. */
void SetArmourMovement(PCharacter Who, PItem Item)
{
  POOL_TRACE("SetArmourMovement");
  s32 t1;
  if (ItemTable[(*FPD(TMenuLine (*), Item)).ItemType].Slot == ArmourItemKind) {
    t1 = (*FPD(TMenuLine (*), Item)).Weight;
    if ((t1 >= 0 && t1 <= 150)) {
      (*FPD(TCharacter (*), Who)).Movement = (*FPD(TCharacter (*), Who)).BaseMovement;
    } else if ((t1 >= 151 && t1 <= 399)) {
      (*FPD(TCharacter (*), Who)).Movement = MediumArmourMove;
    } else {
      (*FPD(TCharacter (*), Who)).Movement = HeavyArmourMove;
    }
    if ((*FPD(TMenuLine (*), Item)).Plus != 0) {
      if ((*FPD(TCharacter (*), Who)).Movement <= MediumArmourMove) {
        (*FPD(TCharacter (*), Who)).Movement = (*FPD(TCharacter (*), Who)).Movement + MagicArmourMoveBonus;
      }
    }
  }
}

/* 00BA:0282. Adds one readied item's bonuses into the accumulator Bonus (TBonus) that
     RecalcCombatValues keeps; called for every readied item after SetArmourMovement. Value is the item
     kind's bonus class (ItemTable[item type].BonusClass); with bit 7 clear the item contributes nothing. The
     item kind (ItemTable[item type].Slot) and Value pick what happens: a kind-1 item assigns
     Value + Plus to Bonus.KindBonus; otherwise Value 0 adds Plus to Bonus.PlusSum (a kind-9 item
     keeps the larger Plus in Bonus.BestPlus instead) and always adds the item's PlusSave (+$33) to
     Who^.SaveBonus; a Value above 0 keeps Value + Plus as the larger Bonus.BestValue and, for a
     positive plus on a kind-2 (armour) item, sets Flag.
     Globals: ItemTable. */
void AddReadiedItemBonus(PCharacter Who, PItem Item, TBonus (*Bonus), u8 (*Flag))
{
  POOL_TRACE("AddReadiedItemBonus");
  u8 Value = 0;
  u8 Kind = 0;
  Value = ItemTable[(*FPD(TMenuLine (*), Item)).ItemType].BonusClass;
  if (Value <= 0x7F) {
    return;
  }
  Value = (Value & 0x7F);
  Kind = ItemTable[(*FPD(TMenuLine (*), Item)).ItemType].Slot;
  if (Kind == PlusItemKind) {
    (*Bonus).KindBonus = Value + (*FPD(TMenuLine (*), Item)).Plus;
    return;
  }
  if (Value == 0) {
    if (Kind == SpecialItemKind) {
      if ((*FPD(TMenuLine (*), Item)).Plus > (*Bonus).BestPlus) {
        (*Bonus).BestPlus = (*FPD(TMenuLine (*), Item)).Plus;
      }
    } else {
      (*Bonus).PlusSum = (*Bonus).PlusSum + (*FPD(TMenuLine (*), Item)).Plus;
    }
    (*FPD(TCharacter (*), Who)).SaveBonus = (*FPD(TCharacter (*), Who)).SaveBonus + (*FPD(TMenuLine (*), Item)).PlusSave;
  } else {
    if ((s16)(Value + (*FPD(TMenuLine (*), Item)).Plus) > (*Bonus).BestValue) {
      (*Bonus).BestValue = Value + (*FPD(TMenuLine (*), Item)).Plus;
      if ((((*FPD(TMenuLine (*), Item)).Plus > 0)) && ((Kind == ArmourItemKind))) {
        (*Flag) = 1;
      }
    }
  }
}

/* 00BA:03A0. Caps Who's movement by the weight the character carries above its strength
     allowance; RecalcCombatValues calls it once after the readied-item loop. Weight is
     CarriedWeight (+$102) minus StrengthWeightAllowance(Who) (the strength weight allowance), clamped at 0
     from below. The excess picks the cap: up to LightLoadLimit the movement is left alone, up to
     MediumLoadLimit it is MediumLoadMove (9), up to HeavyLoadLimit HeavyLoadMove (6), and above that
     OverloadMove (3); the movement only falls, never rises.
     Globals: none beyond Who. */
void CapMovementByLoad(PCharacter Who)
{
  POOL_TRACE("CapMovementByLoad");
  s16 Weight = 0;
  u8 NewMovement = 0;
  s32 t1;
  Weight = (*FPD(TCharacter (*), Who)).CarriedWeight - StrengthWeightAllowance(Who);
  if (Weight < 0) {
    Weight = 0;
  }
  t1 = Weight;
  if ((t1 >= 0 && t1 <= 512)) {
    NewMovement = (*FPD(TCharacter (*), Who)).Movement;
  } else if ((t1 >= 513 && t1 <= 768)) {
    NewMovement = MediumLoadMove;
  } else if ((t1 >= 769 && t1 <= 1024)) {
    NewMovement = HeavyLoadMove;
  } else {
    NewMovement = OverloadMove;
  }
  if (NewMovement < (*FPD(TCharacter (*), Who)).Movement) {
    (*FPD(TCharacter (*), Who)).Movement = NewMovement;
  }
}

/* 00BA:0442. Builds an item menu line's display text in Item^.Text and, when ShowText is set,
     draws it at (Col, Row) in LightGreen. Clears Text, then, when ShowReadied is set, prefixes ' Yes  '
     or ' No   ' from Readied. When any member of the party list PartyListHead has MagicMarkAffect (affect
     5, HasAffect), a Plus, PlusSave or Cursed item is marked '* '. A Count above 0 is written in
     front of the name. The three NameNum parts (ItemNameParts, 256 string[20] at DS:10A7) are appended
     from part 3 down to 1, skipping a part whose HiddenNames bit is set, and each shown part is
     followed by 's ' or ' '. The 's ' is used, once, when Count is at least 2 and this part is the
     only one shown, or part 1 is shown with part 3 also shown (Mask > ThirdNameBit) and the item
     type is not PluralOnThirdPartType ($56), or part 2 is shown while part 1 is not (not Odd(Mask):
     bit 0 of the mask is clear, 00BA:06A6), or part 3 is shown for PluralOnThirdPartType, or the
     item type is Slot11ItemType or Slot12ItemType and NameNum[3] is not SilverNameNum ($B1).
     Callers: the shop, loot and inventory lists (ShowText False, they draw Text themselves) and the
     character sheet (ShowText True).
     QUIRK 00BA:0442: the LongInt Value is never read (callers pass LongInt(the character) or 0).
     Globals: PartyListHead (read), ItemNameParts (read). Side effects: Item^.Text, and the screen when ShowText
     is set. */
void FormatItemLine(s32 Value, PItem Item, u8 Col, u8 Row, u8 ShowReadied, u8 ShowText)
{
  POOL_TRACE("FormatItemLine");
  u8 I = 0;
  u8 Mask = 0;
  farptr Affect = 0;
  u8 Found = 0;
  u8 Plural = 0;
  PCharacter Member = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  u8 t5[256];
  u8 t6[256];
  u8 t7[256];
  rtl_str_assign((*FPD(TMenuLine (*), Item)).Text, 40, S("\000"));
  if (ShowReadied) {
    if ((*FPD(TMenuLine (*), Item)).Readied) {
      rtl_str_assign((*FPD(TMenuLine (*), Item)).Text, 40, S("\006 Yes  "));
    } else {
      rtl_str_assign((*FPD(TMenuLine (*), Item)).Text, 40, S("\006 No   "));
    }
  }
  Found = 0;
  Member = PartyListHead;
  while (((Member != 0)) && !Found) {
    if (HasAffect(Member, MagicMarkAffect, &Affect)) {
      Found = 1;
    }
    Member = (*FPD(TCharacter (*), Member)).Next;
  }
  if (Found) {
    if (((((*FPD(TMenuLine (*), Item)).Plus > 0)) || (((*FPD(TMenuLine (*), Item)).PlusSave > 0))) || (*FPD(TMenuLine (*), Item)).Cursed) {
      rtl_str_assign((*FPD(TMenuLine (*), Item)).Text, 40, rtl_str_cat(t1, 3, (const u8 *const[]){(*FPD(TMenuLine (*), Item)).Text, S("\001*"), S("\001 ")}));
    }
  }
  if ((*FPD(TMenuLine (*), Item)).Count > 0) {
    rtl_str_assign((*FPD(TMenuLine (*), Item)).Text, 40, rtl_str_cat(t3, 3, (const u8 *const[]){(*FPD(TMenuLine (*), Item)).Text, ByteToText(t2, (*FPD(TMenuLine (*), Item)).Count), S("\001 ")}));
  }
  Mask = 0;
  {
    if (1 <= 3) {
      I = 1;
      for (;;) {
          if ((((*FPD(TMenuLine (*), Item)).NameNum[I - 1] != 0)) && ((((((s16)((u16)(*FPD(TMenuLine (*), Item)).HiddenNames >> ((s16)(3 - I)))) & 1)) == 0))) {
            Mask += (s16)(1 << ((s16)(I - 1)));
          }
        if (I == 3) break;
        I++;
      }
    }
  }
  Plural = 0;
  {
    if (3 >= 1) {
      I = 3;
      for (;;) {
          if (((((s16)((u16)Mask >> ((s16)(I - 1)))) & 1)) > 0) {
            rtl_str_assign((*FPD(TMenuLine (*), Item)).Text, 40, rtl_str_cat(t4, 2, (const u8 *const[]){(*FPD(TMenuLine (*), Item)).Text, ItemNameParts[(*FPD(TMenuLine (*), Item)).NameNum[I - 1]]}));
            if ((((*FPD(TMenuLine (*), Item)).Count < 2)) || Plural) {
              rtl_str_assign((*FPD(TMenuLine (*), Item)).Text, 40, rtl_str_cat(t5, 2, (const u8 *const[]){(*FPD(TMenuLine (*), Item)).Text, S("\001 ")}));
            } else if ((((((((s16)(1 << ((s16)(I - 1)))) == Mask)) || (((((I == 1)) && ((Mask > ThirdNameBit))) && (((*FPD(TMenuLine (*), Item)).ItemType != PluralOnThirdPartType))))) || ((((I == 2)) && !(Mask & 1)))) || ((((I == 3)) && (((*FPD(TMenuLine (*), Item)).ItemType == PluralOnThirdPartType))))) || (((((((*FPD(TMenuLine (*), Item)).ItemType == Slot11ItemType)) || (((*FPD(TMenuLine (*), Item)).ItemType == Slot12ItemType)))) && (((*FPD(TMenuLine (*), Item)).NameNum[2] != SilverNameNum))))) {
              rtl_str_assign((*FPD(TMenuLine (*), Item)).Text, 40, rtl_str_cat(t6, 2, (const u8 *const[]){(*FPD(TMenuLine (*), Item)).Text, S("\002s ")}));
              Plural = 1;
            } else {
              rtl_str_assign((*FPD(TMenuLine (*), Item)).Text, 40, rtl_str_cat(t7, 2, (const u8 *const[]){(*FPD(TMenuLine (*), Item)).Text, S("\001 ")}));
            }
          }
        if (I == 1) break;
        I--;
      }
    }
  }
  if (ShowText) {
    DrawTextAt(Col, Row, LightGreen, (*FPD(TMenuLine (*), Item)).Text);
  }
}

/* 00BA:0767. Draws the roster panel the view screens show (whitepaper 5.24): a "Name / AC  HP"
     header and one line per party member of the list PartyListHead. The member Who is drawn white from its
     Name, every other member through DrawCharacterName. Each line's armour value (DrawArmourClass) and
     current hit points (DrawHitPoints) are drawn in one of three columns picked by the value's range,
     and each line is cleared first. The left column is 1 in the plain full-window layout (ViewModePlain,
     the create-character and training screens, RunCharacterMenu ovl16:0161) and $11 in every other view: the shop and the
     Temple (ViewModeShop, beside the portrait window), the camp and area views (RedrawView) and the
     loot screen. Callers: the shop, the Temple, RedrawView (camp, area view and loot), SelectPartyMember
     and DrawWildernessScreen. Globals: ViewMode (read), PartyListHead (read). */
void DrawPartyRoster(PCharacter Who)
{
  POOL_TRACE("DrawPartyRoster");
  PCharacter Member = 0;
  u8 Left = 0;
  u8 Row = 0;
  u8 ValueShift = 0;
  s32 t1;
  if (ViewMode == ViewModePlain) {
    Left = 1;
  } else {
    Left = 0x11;
  }
  Row = 2;
  DrawTextAt(Left, Row, White, S("\004Name"));
  DrawTextAt(0x21, Row, White, S("\006AC  HP"));
  Row += 2;
  Member = PartyListHead;
  while (Member != 0) {
    ClearWindow(Left, Row, 0x26, Row);
    if (Member == Who) {
      DrawTextAt(Left, Row, White, (*FPD(TCharacter (*), Member)).Name);
    } else {
      DrawCharacterName(Member, Left, Row, 0);
    }
    switch ((*FPD(TCharacter (*), Member)).ArmourClassValue) {
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
      ValueShift = 1;
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
    {
      ValueShift = 2;
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
    {
      ValueShift = 1;
      break;
    }
    default:
    {
      ValueShift = 0;
    }
    }
    DrawArmourClass(Member, (s16)(ValueShift + 0x20), Row);
    t1 = (*FPD(TCharacter (*), Member)).HpCurrent;
    if ((t1 >= 0 && t1 <= 9)) {
      ValueShift = 2;
    } else if ((t1 >= 10 && t1 <= 99)) {
      ValueShift = 1;
    } else {
      ValueShift = 0;
    }
    DrawHitPoints(Member, (s16)(ValueShift + 0x24), Row, 0);
    Row++;
    Member = (*FPD(TCharacter (*), Member)).Next;
  }
  ClearWindow(Left, Row, 0x26, Row);
}

/* 00BA:08EF. Draws the character's armour value (the byte +$111 ovl24's RollBeatsResistance compares a
     d20+level against; DrawCharacterPanel shows it under the "AC" heading) as text at (Col, Row) in
     LightGreen: the distance from ArmourClassBase, Abs(Value - ArmourClassBase), written with a leading '-'
     when the value is above ArmourClassBase (a negative armour class). Called by DrawPartyRoster and
     DrawCharacterPanel. */
void DrawArmourClass(PCharacter Who, u8 Col, u8 Row)
{
  POOL_TRACE("DrawArmourClass");
  u8 ValueText[256] = {0};
  u8 Unused = 0;
  u8 t1[256];
  u8 t2[256];
  rtl_str_assign(ValueText, 255, ByteToText(t1, rtl_abs((s16)((*FPD(TCharacter (*), Who)).ArmourClassValue - ArmourClassBase))));
  if ((*FPD(TCharacter (*), Who)).ArmourClassValue > ArmourClassBase) {
    rtl_str_assign(ValueText, 255, rtl_str_cat(t2, 2, (const u8 *const[]){S("\001-"), ValueText}));
  }
  DrawTextAt(Col, Row, LightGreen, ValueText);
}

/* 00BA:0973. Draws Who's current hit points (HpCurrent, +$11B) as text at (Col, Row). The colour is
     Yellow while the hit points are below the maximum (HpMax, +$32), LightGreen at the maximum, and
     LightMagenta when Highlight is set (the caller's highlight). Called by DrawPartyRoster and
     DrawCharacterPanel. */
void DrawHitPoints(PCharacter Who, u8 Col, u8 Row, u8 Highlight)
{
  POOL_TRACE("DrawHitPoints");
  u8 ValueColor = 0;
  u8 Unused = 0;
  u8 t1[256];
  if ((*FPD(TCharacter (*), Who)).HpCurrent < (*FPD(TCharacter (*), Who)).HpMax) {
    ValueColor = Yellow_RES12;
  } else {
    ValueColor = LightGreen;
  }
  if (Highlight) {
    ValueColor = LightMagenta;
  }
  DrawTextAt(Col, Row, ValueColor, ByteToText(t1, (*FPD(TCharacter (*), Who)).HpCurrent));
}

/* 00BA:09E3. Draws the character panel the combat and inventory screens show (whitepaper 5.24): it
     clears the box ($17,1)-($26,$15), writes the name line through ShowCharacterMessage, the "Hitpoints" and
     "AC" headings with their values (DrawHitPoints, DrawArmourClass), the readied weapon's paged text
     (FormatItemLine then ShowPagedText) when a weapon is readied, and finally the status name
     (StatusNames[Status], +$10c) when the character takes no part in combat (Flag10D = 0), else
     "(Helpless)" when IsHelpless says so. The status row is not fixed: the routine stores
     GlyphRow := Row + 1 before the weapon test, ShowPagedText leaves GlyphRow past the lines the
     weapon text took, and the status is then drawn at GlyphRow + 2 (Row := GlyphRow + 1, then
     Row + 1), so the row follows the weapon text and the assignment is what makes the no-weapon path
     work.
     Globals: GlyphRow (written, then read after ShowPagedText leaves it past the weapon text).
     Side effects: video memory, the keyboard through ShowPagedText's paging. */
void DrawCharacterPanel(PCharacter Who)
{
  POOL_TRACE("DrawCharacterPanel");
  u8 Color = 0;
  u8 Row = 0;
  ClearWindow(0x17, 1, 0x26, 0x15);
  Row = 1;
  ShowCharacterMessage(Who, S("\001 "), Row, 0);
  Row++;
  DrawTextAt(0x17, (s16)(Row + 1), LightGreen, S("\011Hitpoints"));
  DrawHitPoints(Who, 0x21, (s16)(Row + 1), 0);
  Row += 2;
  DrawTextAt(0x17, (s16)(Row + 1), LightGreen, S("\002AC"));
  DrawArmourClass(Who, 0x1A, (s16)(Row + 1));
  GlyphRow = Row + 1;
  if ((*FPD(TCharacter (*), Who)).SlotItems[0] != 0) {
    Row += 2;
    Color = 0x17;
    FormatItemLine((s32)Who, (*FPD(TCharacter (*), Who)).SlotItems[0], 0, 0, 0, 0);
    /* QUIRK 00BA:0AE2: the bottom row is the three additions Row + 1 + 1 + 1 (three inc ax); the
       folded Row + 3 compiles to add ax, 3 and does not match the original */
    ShowPagedText(0x17, (s16)(Row + 1), 0x26, (s16)(((Row + 1) + 1) + 1), LightGreen, ClearTextBeforeMessage, (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[0])).Text);
  }
  Row = GlyphRow + 1;
  if ((*FPD(TCharacter (*), Who)).Flag10D == 0) {
    DrawTextAt(0x17, (s16)(Row + 1), White, StatusNames[(*FPD(TCharacter (*), Who)).Status]);
  } else if (IsHelpless(Who)) {
    DrawTextAt(0x17, (s16)(Row + 1), White, S("\012(Helpless)"));
  }
}

/* 00BA:0B73. Returns whether Who is helpless: True when any of the four affects in
     HelplessAffects (DS:286B, entries 1..4) is on Who's affect list (HasAffect). DrawCharacterPanel
     shows '(Helpless)' when it is True; ovl13 skips a helpless combatant. Called by eight
     overlay routines and DrawCharacterPanel.
     Globals: HelplessAffects (read). */
u8 IsHelpless(farptr Who)
{
  POOL_TRACE("IsHelpless");
  u8 Result = 0;
  u8 I = 0;
  farptr Affect = 0;
  Result = 0;
  {
    if (1 <= 4) {
      I = 1;
      for (;;) {
          if (HasAffect(Who, HelplessAffects[I], &Affect)) {
            Result = 1;
          }
        if (I == 4) break;
        I++;
      }
    }
  }
  return Result;
}

/* 00BA:0BB8. Recomputes every combat value of Who from the items it carries and has readied; called
     whenever a character's equipment or status changes (ovl03, ovl06, ovl08..ovl10, ovl12, ovl13,
     ovl16, ovl19, ovl21, ovl24).
     It clears the 13 per-kind slots (SlotItems, +$CC); walks the carried item list (Items, +$C8) to
     count the items (ItemCountC7, +$C7), add every item's Weight (+$37) times its Count (+$39) to
     CarriedWeight (+$102) and to the readied weight ReadiedItemWeight (DS:4846), and file each readied
     item into its slot (kind 0..8 into SlotItems[kind], kind 9 into the first free of slots 9 and 10,
     item type $49 into slot 11 and $1C into slot 12), raising HandsInUse (+$100) by the kind's
     ItemTable[item type].Hands. It adds the seven carried money words (Money, +$88, coins count one
     each) to the weight, copies the base attack triple (+$A3..+$A8) into the readied weapon triple
     (+$115..+$11A) and the base armour class value (BaseArmourClassValue, +$A9) into ArmourClassValue (+$111), then clears the
     five accumulator bytes (TBonus), SaveBonus (+$101) and the armour-plus flag, sets Movement (+$11C)
     to BaseMovement (+$72) and HitAdjust (+$110) to Thac0 (+$2D), and stores the dexterity adjustment
     (DexterityAdjustment) in DexAdjust. With no readied weapon it adds the unarmed strength bonuses
     (StrengthAttackAdjustment, StrengthDamageAdjustment) to HitAdjust and the damage bonus, then runs
     ApplyWeaponBonuses. For every readied item it runs SetArmourMovement and AddReadiedItemBonus; a
     positive plus on a kind-2 (armour) item sets ArmourPlusFlag, and after the loop that flag clears
     Bonus.BestPlus (a magic armour drops the largest kind-9 plus; why is not proven [?]). A readied item
     whose NameNum[1] is HoldingNameNum instead counts ExcludedWeight (5000) less, floored at
     ReadiedItemWeight. CapMovementByLoad then caps Movement by the load, and only after that does
     BestValue reach its final value: it is first raised to the base ArmourClassValue (so the armour base
     counts once), ArmourClassValue becomes the sum of all five accumulator bytes (DexAdjust, KindBonus,
     PlusSum, BestPlus and BestValue), and RearArmourClassValue (+$112) becomes BestValue + PlusSum + BestPlus - 2
     (DexAdjust and KindBonus do not go into it). Finally SweepAttacks (+$6B) is set: the fighter level
     (ClassLevels[ClassFighter]) when it is above 0 and Race (+$2E) is above 0 (a player race: RaceNames[0] is 'Monster'), else 1.
     Globals: reads ItemTable, writes ReadiedItemWeight, and reads and writes Who's Race, ClassLevels,
     Money and the fields SlotItems, ItemCountC7, HandsInUse, CarriedWeight,
     WeaponAttacks/WeaponDamage/WeaponDamageBonus, SaveBonus, ArmourClassValue, Movement, HitAdjust, RearArmourClassValue
     and SweepAttacks. */
void RecalcCombatValues(PCharacter Who)
{
  POOL_TRACE("RecalcCombatValues");
  u8 TripleIndex = 0;
  s8 BonusIndex = 0;
  PItem Item = 0;
  u8 ArmourPlusFlag = 0;
  u8 IgnoresWeight = 0;
  TBonus Bonus = {0};
  s8 SlotIndex = 0;
  u8 Unused = 0;
  s8 MoneyKind = 0;
  u16 Weight = 0;
  s8 ItemKind = 0;
  {
    if (0 <= 12) {
      SlotIndex = 0;
      for (;;) {
          (*FPD(TCharacter (*), Who)).SlotItems[SlotIndex] = 0;
        if (SlotIndex == 12) break;
        SlotIndex++;
      }
    }
  }
  IgnoresWeight = 0;
  (*FPD(TCharacter (*), Who)).ItemCountC7 = 0;
  Item = (*FPD(TCharacter (*), Who)).Items;
  (*FPD(TCharacter (*), Who)).HandsInUse = 0;
  (*FPD(TCharacter (*), Who)).CarriedWeight = 0;
  ReadiedItemWeight = 0;
  while (Item != 0) {
    (*FPD(TCharacter (*), Who)).ItemCountC7++;
    Weight = (*FPD(TMenuLine (*), Item)).Weight;
    if ((*FPD(TMenuLine (*), Item)).Count > 0) {
      Weight = (*FPD(TMenuLine (*), Item)).Count * Weight;
    }
    (*FPD(TCharacter (*), Who)).CarriedWeight += Weight;
    if ((*FPD(TMenuLine (*), Item)).Readied) {
      ReadiedItemWeight += Weight;
      ItemKind = ItemTable[(*FPD(TMenuLine (*), Item)).ItemType].Slot;
      /* QUIRK 00BA:0C8C: ItemKind indexes SlotItems signed (cwde) but the case reads it
         unsigned (jb/ja), so the selector is written as the Byte view of the ShortInt */
      switch (ItemKind) {
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
        (*FPD(TCharacter (*), Who)).SlotItems[ItemKind] = Item;
        break;
      }
      case SpecialItemKind:
      {
        if ((*FPD(TCharacter (*), Who)).SlotItems[9] != 0) {
          if ((*FPD(TCharacter (*), Who)).SlotItems[10] == 0) {
            (*FPD(TCharacter (*), Who)).SlotItems[10] = Item;
          }
        } else {
          (*FPD(TCharacter (*), Who)).SlotItems[9] = Item;
        }
        break;
      }
      }
      if ((*FPD(TMenuLine (*), Item)).ItemType == Slot11ItemType) {
        (*FPD(TCharacter (*), Who)).SlotItems[11] = Item;
      }
      if ((*FPD(TMenuLine (*), Item)).ItemType == Slot12ItemType) {
        (*FPD(TCharacter (*), Who)).SlotItems[12] = Item;
      }
      if ((*FPD(TMenuLine (*), Item)).NameNum[0] == HoldingNameNum) {
        IgnoresWeight = 1;
      }
      (*FPD(TCharacter (*), Who)).HandsInUse = (*FPD(TCharacter (*), Who)).HandsInUse + ItemTable[(*FPD(TMenuLine (*), Item)).ItemType].Hands;
    }
    Item = (*FPD(TMenuLine (*), Item)).Next;
  }
  {
    if (0 <= 6) {
      MoneyKind = 0;
      for (;;) {
          (*FPD(TCharacter (*), Who)).CarriedWeight = (*FPD(TCharacter (*), Who)).CarriedWeight + (*FPD(TCharacter (*), Who)).Money[MoneyKind];
        if (MoneyKind == 6) break;
        MoneyKind++;
      }
    }
  }
  {
    if (1 <= 2) {
      TripleIndex = 1;
      for (;;) {
          (*FPD(TCharacter (*), Who)).WeaponAttacks[TripleIndex - 1] = (*FPD(TCharacter (*), Who)).BaseAttacks[TripleIndex - 1];
          (*FPD(TCharacter (*), Who)).WeaponDamage[TripleIndex - 1] = (*FPD(TCharacter (*), Who)).BaseDamage[TripleIndex - 1];
          (*FPD(TCharacter (*), Who)).WeaponDamageBonus[TripleIndex - 1] = (*FPD(TCharacter (*), Who)).BaseDamageBonus[TripleIndex - 1];
        if (TripleIndex == 2) break;
        TripleIndex++;
      }
    }
  }
  {
    if (0 <= 4) {
      BonusIndex = 0;
      for (;;) {
          Bonus.Values[BonusIndex] = 0;
        if (BonusIndex == 4) break;
        BonusIndex++;
      }
    }
  }
  ArmourPlusFlag = 0;
  (*FPD(TCharacter (*), Who)).SaveBonus = 0;
  (*FPD(TCharacter (*), Who)).ArmourClassValue = (*FPD(TCharacter (*), Who)).BaseArmourClassValue;
  (*FPD(TCharacter (*), Who)).Movement = (*FPD(TCharacter (*), Who)).BaseMovement;
  (*FPD(TCharacter (*), Who)).HitAdjust = (*FPD(TCharacter (*), Who)).Thac0;
  Bonus.DexAdjust = DexterityAdjustment(Who);
  if ((*FPD(TCharacter (*), Who)).SlotItems[0] == 0) {
    (*FPD(TCharacter (*), Who)).HitAdjust = (*FPD(TCharacter (*), Who)).HitAdjust + StrengthAttackAdjustment(Who);
    (*FPD(TCharacter (*), Who)).WeaponDamageBonus[0] = (*FPD(TCharacter (*), Who)).WeaponDamageBonus[0] + StrengthDamageAdjustment(Who);
  }
  ApplyWeaponBonuses(Who);
  Item = (*FPD(TCharacter (*), Who)).Items;
  while (Item != 0) {
    if ((*FPD(TMenuLine (*), Item)).Readied) {
      SetArmourMovement(Who, Item);
      AddReadiedItemBonus(Who, Item, &Bonus, &ArmourPlusFlag);
    }
    Item = (*FPD(TMenuLine (*), Item)).Next;
  }
  if (ArmourPlusFlag) {
    Bonus.BestPlus = 0;
  }
  if (IgnoresWeight) {
    if ((*FPD(TCharacter (*), Who)).CarriedWeight < ExcludedWeight) {
      (*FPD(TCharacter (*), Who)).CarriedWeight = 0;
    } else {
      (*FPD(TCharacter (*), Who)).CarriedWeight -= ExcludedWeight;
    }
    if ((*FPD(TCharacter (*), Who)).CarriedWeight < ReadiedItemWeight) {
      (*FPD(TCharacter (*), Who)).CarriedWeight = ReadiedItemWeight;
    }
  }
  CapMovementByLoad(Who);
  if (Bonus.BestValue < (*FPD(TCharacter (*), Who)).ArmourClassValue) {
    Bonus.BestValue = (*FPD(TCharacter (*), Who)).ArmourClassValue;
  }
  (*FPD(TCharacter (*), Who)).ArmourClassValue = 0;
  {
    if (0 <= 4) {
      BonusIndex = 0;
      for (;;) {
          (*FPD(TCharacter (*), Who)).ArmourClassValue = (*FPD(TCharacter (*), Who)).ArmourClassValue + Bonus.Values[BonusIndex];
        if (BonusIndex == 4) break;
        BonusIndex++;
      }
    }
  }
  (*FPD(TCharacter (*), Who)).RearArmourClassValue = ((Bonus.BestValue + Bonus.PlusSum) + Bonus.BestPlus) - 2;
  if ((((*FPD(TCharacter (*), Who)).ClassLevels[2] > 0)) && (((*FPD(TCharacter (*), Who)).Race > RaceMonster))) {
    (*FPD(TCharacter (*), Who)).SweepAttacks = (*FPD(TCharacter (*), Who)).ClassLevels[2];
  } else {
    (*FPD(TCharacter (*), Who)).SweepAttacks = 1;
  }
}

/* 00BA:1037. Formats the byte N as its decimal text: it writes N into a 255-character local through
     Str and copies that into the string result. DrawArmourClass and DrawHitPoints show the AC and
     hit-point values with it, and TwoDigitText (ovl20:0565) keeps the first two characters. */
u8 *ByteToText(u8 *Result_out, u8 Value)
{
  POOL_TRACE("ByteToText");
  u8 *Result = Result_out;
  u8 Text[256] = {0};
  rtl_str_int(Text, 255, Value, 0);
  rtl_str_assign(Result, 255, Text);
  return Result;
}

/* 00BA:1073. Formats the word Value as its decimal text, the same way ByteToText does for a byte:
     Str into a 255-character local, copied into the string result. The shops and the Temple put
     prices and amounts into messages with it.
     Globals: none. */
u8 *WordToText(u8 *Result_out, u16 Value)
{
  POOL_TRACE("WordToText");
  u8 *Result = Result_out;
  u8 Text[256] = {0};
  rtl_str_int(Text, 255, Value, 0);
  rtl_str_assign(Result, 255, Text);
  return Result;
}

/* 00BA:10AD. Formats the LongInt Value as its decimal text, the same way ByteToText and WordToText
     do: Str into a 255-character local, copied into the string result. ovl19's character sheet
     (ShowCharacterSheet) writes the character's experience points (Experience, +$AC) with it.
     Globals: none. */
u8 *LongIntToText(u8 *Result_out, s32 Value)
{
  POOL_TRACE("LongIntToText");
  u8 *Result = Result_out;
  u8 Text[256] = {0};
  rtl_str_int(Text, 255, Value, 0);
  rtl_str_assign(Result, 255, Text);
  return Result;
}

/* 00BA:10E6. Returns the AD&D dexterity adjustment of Who's dexterity (Dexterity, +$13):
     dexterity 1..3 gives -4, 4..6 the dexterity minus 7, 7..14 gives 0, 15..18 the dexterity
     minus 14, 19..20 gives 4, 21..23 gives 5 and 24..25 gives 6. RecalcCombatValues stores it in
     the accumulator's first byte, which it sums into the character's combat value. */
u8 DexterityAdjustment(PCharacter Who)
{
  POOL_TRACE("DexterityAdjustment");
  u8 Result = 0;
  u8 Dex = 0;
  Dex = (*FPD(TCharacter (*), Who)).Dexterity;
  switch (Dex) {
  case 1:
  case 2:
  case 3:
  {
    Result = DexBand1Adjust;
    break;
  }
  case 4:
  case 5:
  case 6:
  {
    Result = Dex - DexBand2Offset;
    break;
  }
  case 15:
  case 16:
  case 17:
  case 18:
  {
    Result = Dex - DexBand3Offset;
    break;
  }
  case 19:
  case 20:
  {
    Result = DexBand4Adjust;
    break;
  }
  case 21:
  case 22:
  case 23:
  {
    Result = DexBand5Adjust;
    break;
  }
  case 24:
  case 25:
  {
    Result = DexBand6Adjust;
    break;
  }
  default:
  {
    Result = 0;
  }
  }
  return Result;
}

/* 00BA:1168. Maps Who's dexterity (Dexterity, +$13) to its AD&D reaction/attack adjustment:
     dexterity 0..2 gives -4, 3..5 the dexterity minus 6, 6..15 gives 0, 16..18 the dexterity
     minus 15, 19..20 gives 3, 21..23 gives 4 and 24..25 gives 5. ApplyWeaponBonuses adds it to
     the attack value (HitAdjust) for a weapon kind whose attack flags carry mask WeaponFlagDexToHit
     (2). ovl13 also calls it. Globals: none. */
s8 DexterityAttackAdjustment(PCharacter Who)
{
  POOL_TRACE("DexterityAttackAdjustment");
  s8 Result = 0;
  u8 Dex = 0;
  Dex = (*FPD(TCharacter (*), Who)).Dexterity;
  switch (Dex) {
  case 0:
  case 1:
  case 2:
  {
    Result = (-4);
    break;
  }
  case 3:
  case 4:
  case 5:
  {
    Result = Dex - 6;
    break;
  }
  case 16:
  case 17:
  case 18:
  {
    Result = Dex - 0xF;
    break;
  }
  case 19:
  case 20:
  {
    Result = 3;
    break;
  }
  case 21:
  case 22:
  case 23:
  {
    Result = 4;
    break;
  }
  case 24:
  case 25:
  {
    Result = 5;
    break;
  }
  default:
  {
    Result = 0;
  }
  }
  return Result;
}

/* 00BA:11EA. Maps a character's strength (Strength, +$10) to a 0..30 row of the strength table:
     strength 0..17 is itself, strength 18 is 18 plus the exceptional strength (StrengthPercent,
     +$16: 0 gives 18, 1..50 gives 19, 51..75 gives 20, 76..90 gives 21, 91..99 gives 22 and 100
     gives 23), and strength 19..25 gives 24..30. StrengthAttackAdjustment, StrengthDamageAdjustment and StrengthWeightAllowance
     use it to look up the reaction, damage and weight allowances of a strength.
     QUIRK 00BA:1258: a strength above 25, or a strength-18 percentage above 100, leaves the result
     unassigned (the original returns whatever the frame held).
     Globals: none. */
u8 StrengthRowIndex(PCharacter Who)
{
  POOL_TRACE("StrengthRowIndex");
  u8 Result = 0;
  switch ((*FPD(TCharacter (*), Who)).Strength) {
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
  {
    Result = (*FPD(TCharacter (*), Who)).Strength;
    break;
  }
  case 0x12:
  {
    switch ((*FPD(TCharacter (*), Who)).StrengthPercent) {
    case 0:
    {
      Result = 0x12;
      break;
    }
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
      Result = 0x13;
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
    {
      Result = 0x14;
      break;
    }
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
      Result = 0x15;
      break;
    }
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
      Result = 0x16;
      break;
    }
    case 0x64:
    {
      Result = 0x17;
      break;
    }
    }
    break;
  }
  case 19:
  case 20:
  case 21:
  case 22:
  case 23:
  case 24:
  case 25:
  {
    Result = (*FPD(TCharacter (*), Who)).Strength + 5;
    break;
  }
  }
  return Result;
}

/* 00BA:1282. Returns the strength reaction/attack adjustment of Who: StrengthRowIndex (00BA:11EA)
     maps the strength to a 0..30 table row and the row picks the bonus (1..3 gives -3, 4..5 -2,
     6..7 -1, 17..19 +1, 20..22 +2, 23..25 +3, 26..27 +4 and 28..30 the row minus 23; every other row
     gives 0). ApplyWeaponBonuses and RecalcCombatValues add it to HitAdjust. The whole adjustment is 0
     unless Who^.StrengthBonusFlag (+$AA) is nonzero. Globals: none. */
s8 StrengthAttackAdjustment(PCharacter Who)
{
  POOL_TRACE("StrengthAttackAdjustment");
  s8 Result = 0;
  u8 Row = 0;
  Result = 0;
  Row = StrengthRowIndex(Who);
  if ((*FPD(TCharacter (*), Who)).StrengthBonusFlag != 0) {
    switch (Row) {
    case 1:
    case 2:
    case 3:
    {
      Result = (-3);
      break;
    }
    case 4:
    case 5:
    {
      Result = (-2);
      break;
    }
    case 6:
    case 7:
    {
      Result = (-1);
      break;
    }
    case 17:
    case 18:
    case 19:
    {
      Result = 1;
      break;
    }
    case 20:
    case 21:
    case 22:
    {
      Result = 2;
      break;
    }
    case 23:
    case 24:
    case 25:
    {
      Result = 3;
      break;
    }
    case 26:
    case 27:
    {
      Result = 4;
      break;
    }
    case 28:
    case 29:
    case 30:
    {
      Result = Row - 0x17;
      break;
    }
    }
  }
  return Result;
}

/* 00BA:1325. Returns the strength damage adjustment of Who: StrengthRowIndex (00BA:11EA) maps the
     strength to a 0..30 table row and the row picks the damage bonus (1..2 gives -2, 3..5 -1, 16 +1,
     17..19 the row minus 16, 20..29 the row minus 17 and 30 +14; every other row gives 0).
     ApplyWeaponBonuses and RecalcCombatValues add it to WeaponDamageBonus. The whole adjustment is 0
     unless Who^.StrengthBonusFlag (+$AA) is nonzero. Globals: none. */
s8 StrengthDamageAdjustment(PCharacter Who)
{
  POOL_TRACE("StrengthDamageAdjustment");
  s8 Result = 0;
  u8 Row = 0;
  Result = 0;
  Row = StrengthRowIndex(Who);
  if ((*FPD(TCharacter (*), Who)).StrengthBonusFlag != 0) {
    switch (Row) {
    case 1:
    case 2:
    {
      Result = (-2);
      break;
    }
    case 3:
    case 4:
    case 5:
    {
      Result = (-1);
      break;
    }
    case 0x10:
    {
      Result = 1;
      break;
    }
    case 17:
    case 18:
    case 19:
    {
      Result = Row - 0x10;
      break;
    }
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
    {
      Result = Row - 0x11;
      break;
    }
    case 0x1E:
    {
      Result = 14;
      break;
    }
    }
  }
  return Result;
}

/* 00BA:13AB. Returns the weight a character of Who's strength can carry, in coins: StrengthRowIndex
     (00BA:11EA) maps the strength to a 0..30 table row and the row picks the allowance (rows 1..3
     give -350, 4..5 -250, 6..7 -150, 12..13 100, 14..15 200, 16 350, 17..21 (row-17)*250+500,
     22..26 (row-22)*1000+2000, 27 7500, 28..30 (row-28)*3000+9000, every other row 0).
     CapMovementByLoad subtracts it from the carried weight; ovl21's CarryLimit adds 1500 to it.
     Globals: none. */
s16 StrengthWeightAllowance(PCharacter Who)
{
  POOL_TRACE("StrengthWeightAllowance");
  s16 Result = 0;
  u8 Row = 0;
  u8 Unused = 0;
  Row = StrengthRowIndex(Who);
  switch (Row) {
  case 1:
  case 2:
  case 3:
  {
    Result = (-350);
    break;
  }
  case 4:
  case 5:
  {
    Result = (-250);
    break;
  }
  case 6:
  case 7:
  {
    Result = (-150);
    break;
  }
  case 12:
  case 13:
  {
    Result = 100;
    break;
  }
  case 14:
  case 15:
  {
    Result = 200;
    break;
  }
  case 0x10:
  {
    Result = 350;
    break;
  }
  case 17:
  case 18:
  case 19:
  case 20:
  case 21:
  {
    Result = (((s16)(Row - 0x11)) * 0xFA) + 0x1F4;
    break;
  }
  case 22:
  case 23:
  case 24:
  case 25:
  case 26:
  {
    Result = (((s16)(Row - 0x16)) * 0x3E8) + 0x7D0;
    break;
  }
  case 0x1B:
  {
    Result = 0x1D4C;
    break;
  }
  case 28:
  case 29:
  case 30:
  {
    Result = (((s16)(Row - 0x1C)) * 0xBB8) + 0x2328;
    break;
  }
  default:
  {
    Result = 0;
  }
  }
  return Result;
}

/* 00BA:148B. Clears the spell Spell from the selected character's memorized spells (SelectedCharacter,
     DS:5D92; Spells at +$17, 21 slots 0..$14): it scans the slots and empties the first one that holds
     Spell. DealDamage calls it ("loses a pending spell"), ovl13 and ovl22 also call it. */
void ForgetSpell(u8 Spell)
{
  POOL_TRACE("ForgetSpell");
  u8 I = 0;
  I = 0;
  while (I <= 0x14) {
    if ((*FPD(TCharacter (*), SelectedCharacter)).Spells[I] == Spell) {
      (*FPD(TCharacter (*), SelectedCharacter)).Spells[I] = 0;
      I = 0x15;
    }
    I++;
  }
}

/* 00BA:1509. Removes Item from the carried-item list Who^.Items (+$C8) and frees the record:
     when Item is the head it re-points the head at Item^.Next, otherwise it walks the list for the
     record whose Next is Item; a nil Item or an Item not on the list only reports through
     ShowMessageLine. The item is unlinked (Item^.Next := nil) and freed (ItemListSize). Called by
     ovl07 LoseItems for every lost item, and by ovl13, ovl19 and ovl22 when an item is consumed.
     Globals: none. */
void RemoveInventoryItem(PCharacter Who, PItem Item)
{
  POOL_TRACE("RemoveInventoryItem");
  PItem Prev = 0;
  if (Item == 0) {
    ShowMessageLine(Yellow_RES12, S("\023Nil Item pointer..."));
  } else {
    Prev = (*FPD(TCharacter (*), Who)).Items;
    if (Prev == Item) {
      (*FPD(TCharacter (*), Who)).Items = (*FPD(TMenuLine (*), Item)).Next;
    } else {
      while (((Prev != 0)) && (((*FPD(TMenuLine (*), Prev)).Next != Item))) {
        Prev = (*FPD(TMenuLine (*), Prev)).Next;
      }
    }
    if (Prev == 0) {
      ShowMessageLine(Yellow_RES12, S("&Tried to Lose item & couldn't find it!"));
    } else {
      (*FPD(TMenuLine (*), Prev)).Next = (*FPD(TMenuLine (*), Item)).Next;
      (*FPD(TMenuLine (*), Item)).Next = 0;
      rtl_freemem(Item, ItemListSize);
    }
  }
}

/* 00BA:15F7. Allocates an item record (ItemListSize), deep-copies Item into it (Move) with its Next
     cleared, and appends it to the end of the carried-item list Who^.Items (+$C8); an empty list keeps
     the copy as the head. Used when a character is given a copy of an item, not the item itself.
     Globals: none. */
void AddItemCopy(PCharacter Who, PItem Item)
{
  POOL_TRACE("AddItemCopy");
  PItem Prev = 0;
  PItem NewItem = 0;
  NewItem = rtl_getmem(ItemListSize);
  rtl_Move((void *)&(*FPD(TMenuLine (*), Item)), (void *)&(*FPD(TMenuLine (*), NewItem)), ItemListSize);
  (*FPD(TMenuLine (*), NewItem)).Next = 0;
  Prev = (*FPD(TCharacter (*), Who)).Items;
  if (Prev == 0) {
    (*FPD(TCharacter (*), Who)).Items = NewItem;
  } else {
    while ((*FPD(TMenuLine (*), Prev)).Next != 0) {
      Prev = (*FPD(TMenuLine (*), Prev)).Next;
    }
    (*FPD(TMenuLine (*), Prev)).Next = NewItem;
  }
}

/* 00BA:1693. Flashes Text on the bottom message line (row 24, columns 0..39) in LightGreen: clears the
     row, writes the text, waits DelayByGameSpeed, and clears the row again. No key is waited for.
     Called with 'Not enough money.', 'OverLoaded' and similar combat and shop notices.
     Globals: none. */
void ShowFlashMessage(const u8 *Text_in)
{
  POOL_TRACE("ShowFlashMessage");
  const u8 *Text = Text_in;
  ClearWindow(0, BottomRow, ScreenLastCol, BottomRow);
  DrawTextAt(0, BottomRow, LightGreen, Text);
  DelayByGameSpeed();
  ClearWindow(0, BottomRow, ScreenLastCol, BottomRow);
}

/* 00BA:16EC. Shows a message about Who in a small window, its top Row in the combat view (view
     mode ViewModeCombat) and a fixed window otherwise; draws Who's name (DrawCharacterName) and the paged text Text
     (ShowPagedText) and, when Wait is set, delays DelayByGameSpeed and clears the window again
     (ClearCharacterMessage). Used for the per-character combat and camp messages ('is bandaged',
     'flees in panic', 'is cured'). Globals: ViewMode (view mode), RestWindowActive (picks the window top).
     Side effects: video memory, the keyboard through ShowPagedText's paging. */
void ShowCharacterMessage(PCharacter Who, const u8 *Text_in, u8 Row, u8 Wait)
{
  POOL_TRACE("ShowCharacterMessage");
  const u8 *Text = Text_in;
  u8 Top = 0;
  if (ViewMode == ViewModeCombat) {
    ClearWindow(CombatMessageLeft, Row, CombatMessageRight, CombatMessageBottom);
    DrawCharacterName(Who, CombatMessageLeft, Row, 0);
    ShowPagedText(CombatMessageLeft, (s16)(Row + 1), CombatMessageRight, CombatMessageBottom, LightGreen, ClearTextBeforeMessage, Text);
  } else {
    if (RestWindowActive != 0) {
      Top = MessageTop;
    } else {
      Top = MessageFrameTop;
      DrawWindowFrame(MessageLeft, Top, MessageRight, MessageBottom, 0);
    }
    ClearWindow(MessageLeft, Top, MessageRight, MessageBottom);
    DrawCharacterName(Who, MessageLeft, (s16)(Top + 1), 0);
    ShowPagedText(MessageLeft, (s16)((Top + 1) + 1), MessageRight, MessageBottom, LightGreen, ClearTextBeforeMessage, Text);
  }
  if (Wait) {
    DelayByGameSpeed();
    ClearCharacterMessage();
  }
}

/* 00BA:17E3. Clears the message window ShowCharacterMessage wrote in: in the combat view (ViewModeCombat)
     the box (CombatMessageLeft,CombatMessageRow)-(CombatMessageRight,CombatMessageBottom), otherwise the
     box (MessageLeft,MessageTop)-(MessageRight,MessageBottom). Called after the wait flag of
     ShowCharacterMessage and by the camp, temple and resting screens to wipe a message. Globals: ViewMode. */
void ClearCharacterMessage(void)
{
  POOL_TRACE("ClearCharacterMessage");
  if (ViewMode == ViewModeCombat) {
    ClearWindow(CombatMessageLeft, CombatMessageRow, CombatMessageRight, CombatMessageBottom);
  } else {
    ClearWindow(MessageLeft, MessageTop, MessageRight, MessageBottom);
  }
}

/* 00BA:1816. Draws Who's name (Name, +0) as text at (Col, Row) in the colour of Who's state:
     LightRed when Who takes no part in combat (Flag10D, +$10d = 0), Yellow for a monster
     (SideMonsters = 1) and LightCyan otherwise (the party, SideParty = 0). When AddPossessive is set it
     appends "'s" after the name
     (at Col + Length(Name)). Called by the roster, the character panel and ovl13, ovl16, ovl19,
     ovl21 and ovl22. Globals: none. */
void DrawCharacterName(PCharacter Who, u8 Col, u8 Row, u8 AddPossessive)
{
  POOL_TRACE("DrawCharacterName");
  u8 Color = 0;
  if ((*FPD(TCharacter (*), Who)).Flag10D == 0) {
    Color = LightRed;
  } else if ((*FPD(TCharacter (*), Who)).Side == SideMonsters) {
    Color = Yellow_RES12;
  } else {
    Color = LightCyan;
  }
  DrawTextAt(Col, Row, Color, (*FPD(TCharacter (*), Who)).Name);
  if (AddPossessive) {
    DrawTextAt((s16)(Col + (*FPD(TCharacter (*), Who)).Name[0]), Row, Color, S("\002's"));
  }
}

/* 00BA:1892. Copies one item of a 24x3 picture into the combat picture CombatAnimationPicture. PicIndex selects a
     slot of the picture table PictureSlots and Half picks one of the slot's two pointers
     (PictureSlots[PicIndex].Pics[Half]); ItemIndex is the destination item (0..3), copied at byte offset ItemIndex times the
     picture's bytes-per-item (ByteSize, +$11). When Mirror is set the source picture is first
     mirrored into a temporary 24x3 picture (AllocatePicture then MirrorPicture) and that copy is
     blitted, otherwise the table picture is blitted directly. In both cases the bitmap (Data, +$17)
     is copied with ItemBytes bytes and the pixel buffer (Pixels, +$13) with PixelBytes, a quarter of
     ItemBytes on the EGA (VideoAdapterEga, 1: the EGA layout holds one plane byte per four data bytes,
     whitepaper 5.23). ReleasePicture frees the temporary.
     Called in a loop by DrawCombatIcon and by ovl13.
     Globals: CombatAnimationPicture (read), PictureSlots (read), VideoAdapter (read). */
void CopyPictureItem(u8 PicIndex, u8 Half, u8 ItemIndex, u8 Mirror)
{
  POOL_TRACE("CopyPictureItem");
  farptr Pic = 0;
  u16 PixelBytes = 0;
  u16 ItemBytes = 0;
  ItemBytes = (*FPD(TPicture (*), CombatAnimationPicture)).ByteSize;
  PixelBytes = ItemBytes;
  if (VideoAdapter == VideoAdapterEga) {
    PixelBytes = (PixelBytes / 4);
  }
  if (Mirror) {
    AllocatePicture(0x18, 3, 1, 1, (void *)&Pic);
    MirrorPicture(PictureSlots[PicIndex].Pics[Half], Pic);
    rtl_Move((void *)&(*FPD(TPicture (*), Pic)).Data[0], (void *)&(*FPD(TPicture (*), CombatAnimationPicture)).Data[(u16)(ItemIndex * ItemBytes)], ItemBytes);
    rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), (*FPD(TPicture (*), Pic)).Pixels))[0], (void *)&(*FPD(TByteArray_RES07 (*), (*FPD(TPicture (*), CombatAnimationPicture)).Pixels))[(u16)(ItemIndex * PixelBytes)], PixelBytes);
    ReleasePicture((void *)&Pic);
  } else {
    rtl_Move((void *)&(*FPD(TPicture (*), PictureSlots[PicIndex].Pics[Half])).Data[0], (void *)&(*FPD(TPicture (*), CombatAnimationPicture)).Data[(u16)(ItemIndex * ItemBytes)], ItemBytes);
    rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), (*FPD(TPicture (*), PictureSlots[PicIndex].Pics[Half])).Pixels))[0], (void *)&(*FPD(TByteArray_RES07 (*), (*FPD(TPicture (*), CombatAnimationPicture)).Pixels))[(u16)(ItemIndex * PixelBytes)], PixelBytes);
  }
}

/* 00BA:19DE. Draws the four items of a 2-wide combat icon into the combat picture CombatAnimationPicture: it calls
     CopyPictureItem four times with Half 0, 0, 1, 1 and Row 0, 1, 2, 3, mirroring the second and
     third item (Mirror False, True, True, False). PicIndex is the source slot in the picture table PictureSlots.
     Called by ovl12, ovl13 and ovl22 (a combatant's icon into the battle picture). Globals: none. */
void DrawCombatIcon(u8 PicIndex)
{
  POOL_TRACE("DrawCombatIcon");
  CopyPictureItem(PicIndex, 0, 0, 0);
  CopyPictureItem(PicIndex, 0, 1, 1);
  CopyPictureItem(PicIndex, 1, 2, 1);
  CopyPictureItem(PicIndex, 1, 3, 0);
}

/* 00BA:1A29. Walks the line from cell (FromX, FromY) to cell (ToX, ToY) and animates the combat cursor
     along it (whitepaper 5.18, combat movement). It builds the Bresenham path between the two cells
     (multiplied by CellPitch, 3, the 24x24 icon pitch) through SetupLine/StepLine, collecting each step's
     direction Pattern into Path. It then walks that path: it computes the screen cell (PX, PY), draws
     the combat picture CombatAnimationPicture onto the staging buffer DrawBuf through DrawPictureItemClipped (frame Frame of
     Count), flushes and delays, steps PX/PY by DirStepX/DirStepY[Path[I]], and keeps the cursor on
     the cell (CursorX, CursorY) through MoveCombatCursor. StepDelay is both the number of
     milliseconds waited after each drawn step (ovl13: MissileMode 10, IconMode $32, SwingMode $14) and, when above 0,
     the switch that forces drawing every step; Count is the number of animation frames.
     Count, StepDelay and the position come from ovl12, ovl13 and ovl22 (the aiming and movement code).
     Globals: CombatMap (read), CombatAnimationPicture (read), DrawBuf (read), IconBackgroundBuffer (read), DirStepX, DirStepY.
     Calls ovl30's line routines and ovl31's cursor/view routines. Side effects: video memory, timing. */
void WalkCombatLine(s8 FromX, s8 FromY, s8 ToX, s8 ToY, u8 Count, u8 StepDelay)
{
  POOL_TRACE("WalkCombatLine");
  u16 stack_mark = rtl_stack_mark();
  u8 Path[148] = {0};
  TLineState (*Line) = (TLineState (*))rtl_stack_alloc(26);
  u8 PadA = 0;
  u8 PadB = 0;
  u8 PathLen = 0;
  u8 PathCount = 0;
  u8 Frame = 0;
  u8 PadC = 0;
  u8 WalkFinished = 0;
  u8 Done = 0;
  s8 CursorX = 0;
  s8 CursorY = 0;
  s8 StartX = 0;
  s8 StartY = 0;
  s8 AccX = 0;
  s8 AccY = 0;
  s8 DeltaX = 0;
  s8 DeltaY = 0;
  s8 DXStep = 0;
  s8 DYStep = 0;
  s8 PX = 0;
  s8 PY = 0;
  StartX = FromX;
  StartY = FromY;
  rtl_FillChar((void *)&Path, 148, DirNone);
  rtl_FillChar((void *)&(*Line), 26, 0);
  PathLen = 0;
  Frame = 0;
  (*Line).X1 = FromX * CellPitch;
  (*Line).Y1 = FromY * CellPitch;
  (*Line).X2 = ToX * CellPitch;
  (*Line).Y2 = ToY * CellPitch;
  SetupLine(rtl_far(&(*Line)));
  do {
    Done = !StepLine(rtl_far(&(*Line)));
    Path[PathLen] = (*Line).Pattern;
    PathLen++;
  } while (!(Done));
  PathCount = PathLen;
  if (PathCount < 2) {
    goto L_exit;
  }
  DeltaX = ToX - FromX;
  DeltaY = ToY - FromY;
  if (!((IsInView((s16)(FromX - (*FPD(TCombatMap (*), CombatMap)).ViewX), (s16)(FromY - (*FPD(TCombatMap (*), CombatMap)).ViewY)) && IsInView((s16)(ToX - (*FPD(TCombatMap (*), CombatMap)).ViewX), (s16)(ToY - (*FPD(TCombatMap (*), CombatMap)).ViewY))))) {
    if (((rtl_abs(DeltaX) <= ViewLimit)) && ((rtl_abs(DeltaY) <= ViewLimit))) {
      WalkFinished = 1;
      CursorX = FromX + (DeltaX / 2);
      CursorY = FromY + (DeltaY / 2);
    } else {
      WalkFinished = 0;
      CursorX = (*FPD(TCombatMap (*), CombatMap)).ViewX + ViewCentreCell;
      CursorY = (*FPD(TCombatMap (*), CombatMap)).ViewY + ViewCentreCell;
    }
  } else {
    WalkFinished = 1;
    CursorX = (*FPD(TCombatMap (*), CombatMap)).ViewX + ViewCentreCell;
    CursorY = (*FPD(TCombatMap (*), CombatMap)).ViewY + ViewCentreCell;
  }
  MoveCombatCursor(CursorX, CursorY, CursorMargin, CursorNoStep);
  PathLen = 0;
  AccX = 0;
  AccY = 0;
  do {
    PX = (((s16)(FromX - (*FPD(TCombatMap (*), CombatMap)).ViewX)) * CellPitch) + AccX;
    PY = (((s16)(FromY - (*FPD(TCombatMap (*), CombatMap)).ViewY)) * CellPitch) + AccY;
    StartX = FromX;
    StartY = FromY;
    Done = 0;
    do {
      if ((((StepDelay > 0)) || (((PX % CellPitch) == 0))) || (((PY % CellPitch) == 0))) {
        DrawPictureItemClipped(PX, PY, Frame, (PictureMasked | PictureSaveBackground), CombatAnimationPicture, DrawBuf);
        FlushPictureChanges();
        rtl_Delay(StepDelay);
        DrawPictureItemClipped(PX, PY, 0, PictureRestore, IconBackgroundBuffer, DrawBuf);
        Frame++;
        if (Frame >= Count) {
          Frame = 0;
        }
      }
      PathLen++;
      DXStep = DirStepX[Path[PathLen]];
      DYStep = DirStepY[Path[PathLen]];
      PX += DXStep;
      PY += DYStep;
      if (((((PX < 0)) || ((PX > ViewPixelLimit))) || ((PY < 0))) || ((PY > ViewPixelLimit))) {
        Done = 1;
      }
      if ((!Done) && ((PathLen < PathCount))) {
        AccX += DXStep;
        AccY += DYStep;
        if (rtl_abs(AccX) == CellPitch) {
          FromX += SignOf(AccX);
          CursorX += SignOf(AccX);
          AccX = 0;
        }
        if (rtl_abs(AccY) == CellPitch) {
          FromY += SignOf(AccY);
          CursorY += SignOf(AccY);
          AccY = 0;
        }
      }
    } while (!(((PathLen >= PathCount)) || Done));
    if (PathLen < PathCount) {
      DeltaX = SignOf((s16)(StartX - FromX));
      DeltaY = SignOf((s16)(StartY - FromY));
      if (DeltaX != 0) {
        if (FromX >= (s16)((*FPD(TCombatMap (*), CombatMap)).ViewX + ViewLimit)) {
          CursorX = FromX + CursorCentreMargin;
        } else if (FromX <= (*FPD(TCombatMap (*), CombatMap)).ViewX) {
          CursorX = FromX - CursorCentreMargin;
        }
      }
      if (DeltaY != 0) {
        if (FromY >= (s16)((*FPD(TCombatMap (*), CombatMap)).ViewY + ViewLimit)) {
          CursorY = FromY + CursorCentreMargin;
        } else if (FromY <= (*FPD(TCombatMap (*), CombatMap)).ViewY) {
          CursorY = FromY - CursorCentreMargin;
        }
      }
      MoveCombatCursor(CursorX, CursorY, CursorMargin, CursorNoStep);
    } else {
      WalkFinished = 1;
      if (!IsInView((s16)(ToX - (*FPD(TCombatMap (*), CombatMap)).ViewX), (s16)(ToY - (*FPD(TCombatMap (*), CombatMap)).ViewY))) {
        MoveCombatCursor(ToX, ToY, CursorCentreMargin, CursorNoStep);
      }
      PX = ((s16)(ToX - (*FPD(TCombatMap (*), CombatMap)).ViewX)) * CellPitch;
      PY = ((s16)(ToY - (*FPD(TCombatMap (*), CombatMap)).ViewY)) * CellPitch;
      DrawPictureItemClipped(PX, PY, Frame, (PictureMasked | PictureSaveBackground), CombatAnimationPicture, DrawBuf);
      if (StepDelay > 0) {
        FlushPictureChanges();
        rtl_Delay(StepDelay);
        DrawPictureItemClipped(PX, PY, 0, PictureRestore, IconBackgroundBuffer, DrawBuf);
      }
    }
  } while (!(WalkFinished));
  FlushPictureChanges();
L_exit:
  rtl_stack_release(stack_mark);
}

/* 00BA:1FEB. Shows a per-character combat message and flashes the character's combat icon over
     its view cell. Outside the combat view (ViewModeCombat) it only shows the message Text with a wait
     and returns. In the combat view: silences the sound driver, draws the combat icon slot AffectHitIcon
     ($16) when AffectMessage is set and DamageHitIcon ($17) otherwise, puts the combat cursor on the character
     when it is off screen, plays the sound SoundAffectMessage when AffectMessage is set and SoundDamageMessage otherwise, and
     shows Text without waiting. It then flashes the character's icon: for FlashCount + 1 passes it draws the four
     picture items (0..3) of the combat picture CombatAnimationPicture at the character's pixel position (CellPitch, 3,
     pixels per view cell, CombatantViewCol/CombatantViewRow), flushes and waits FlashDelay ($46) ms, and
     restores the cell from IconBackgroundBuffer. Finally it resumes the sound driver and flushes; with AffectMessage clear
     (FlashCount 0) it waits DelayByGameSpeed instead. DealDamage calls it with AffectMessage 0 for the damage
     message, ApplyAffect with 1 for an affect or spell effect message ('is Healed', 'is Paralyzed', 'is turned'),
     and the training code uses it too.
     Globals: ViewMode (view mode), GameSpeed (FlashCount), SoundDamageMessage/SoundAffectMessage (sounds),
     CombatAnimationPicture,
     IconBackgroundBuffer,
     DrawBuf, CombatantViewCol, CombatantViewRow. Side effects: video memory, sound, timing. */
void ShowHitMessage(farptr Who, u8 AffectMessage, const u8 *Text_in)
{
  POOL_TRACE("ShowHitMessage");
  const u8 *Text = Text_in;
  s8 Col = 0;
  s8 Row = 0;
  u8 Icon = 0;
  u8 Frame = 0;
  u8 Pass = 0;
  u8 FlashCount = 0;
  if (ViewMode == ViewModeCombat) {
    SetSoundDriverIdle(SoundIdleOff);
    if (AffectMessage != 0) {
      Icon = AffectHitIcon;
    } else {
      Icon = DamageHitIcon;
    }
    DrawCombatIcon(Icon);
    if (!IsCombatantInView(Who, 1)) {
      MoveCombatCursor(CombatantX(Who), CombatantY(Who), CursorCentreMargin, CursorNoStep);
    }
    if (AffectMessage != 0) {
      PlaySound(SoundAffectMessage);
    } else {
      PlaySound(SoundDamageMessage);
    }
    ShowCharacterMessage(Who, Text, CombatMessageRow, 0);
    if (AffectMessage != 0) {
      FlashCount = GameSpeed;
    } else {
      FlashCount = 0;
    }
    Col = CombatantViewCol[CombatantIndex(Who) - 1] * CellPitch;
    Row = CombatantViewRow[CombatantIndex(Who) - 1] * CellPitch;
    {
      u8 limit = FlashCount;
      if (0 <= limit) {
        Pass = 0;
        for (;;) {
            {
              if (0 <= 3) {
                Frame = 0;
                for (;;) {
                    DrawPictureItemClipped(Col, Row, Frame, (PictureMasked | PictureSaveBackground), CombatAnimationPicture, DrawBuf);
                    FlushPictureChanges();
                    rtl_Delay(FlashDelay);
                    DrawPictureItemClipped(Col, Row, 0, PictureRestore, IconBackgroundBuffer, DrawBuf);
                  if (Frame == 3) break;
                  Frame++;
                }
              }
            }
          if (Pass == limit) break;
          Pass++;
        }
      }
    }
    SetSoundDriverIdle(SoundIdleDefault);
    FlushPictureChanges();
    if (FlashCount == 0) {
      DelayByGameSpeed();
    }
  } else {
    ShowCharacterMessage(Who, Text, CombatMessageRow, 1);
  }
}

/* 00BA:2199. Returns whether Who has the affect AffectId on its affect list (TCharacter.Affects, +$7F).
     It leaves in the caller's Affect the matching affect record when found, or the nil end of the list
     otherwise (the callers only test the result). The list is walked until Found or the end. Called by
     CureBlindness, CureDisease, NeutralizePoison, RemoveCurse and the movement, step and campaign code.
     Globals: none. */
u8 HasAffect(farptr Who, u8 AffectId, farptr (*Affect))
{
  POOL_TRACE("HasAffect");
  u8 Result = 0;
  u8 Found = 0;
  Found = 0;
  (*Affect) = (*FPD(TCharacter (*), Who)).Affects;
  while ((((*Affect) != 0)) && !Found) {
    if ((*FPD(TAffect (*), (*Affect))).Id == AffectId) {
      Found = 1;
    } else {
      (*Affect) = (*FPD(TAffect (*), (*Affect))).Next;
    }
  }
  Result = Found;
  return Result;
}

/* 00BA:2228. Applies Damage hit points to Who and updates its status. It computes Overkill =
     Damage - HpCurrent when the damage exceeds Who's current hit points (HpCurrent, +$11B) and
     Remaining = HpCurrent - Damage otherwise (the other stays 0, so Remaining = 0 whenever the
     damage is at or above HpCurrent; that is the code's "reaches 0 or below"). The status tests run
     in this order: dead (StatusDead) when the overkill is above 9, or when Remaining = 0 and Who was
     already StatusAnimated (an animated character is Dead for every blow that reaches 0 or below,
     never Dying); otherwise dying (StatusDying) when there is any overkill, recording the overkill in
     Combat^.DyingRounds (+$E) in the combat view; otherwise unconscious (StatusUnconscious) when
     Remaining = 0, that is an exact hit to 0. When the resulting status is not the standing set
     StatusOkay + StatusAnimated Who leaves combat: Flag10D and the hit points are cleared and, in the
     combat view, its side's count (SideCounts, by Side) and its initiative (Combat^.Initiative, +$3)
     drop; a standing character just takes Remaining as its hit points. DealDamage, DamageWithMessage
     and ovl13 call it. Globals: ViewMode (view mode), SideCounts. */
void ApplyDamage(farptr Who, u8 Damage)
{
  POOL_TRACE("ApplyDamage");
  u8 Overkill = 0;
  u8 Remaining = 0;
  s32 t1;
  Overkill = 0;
  Remaining = 0;
  if ((*FPD(TCharacter (*), Who)).HpCurrent >= Damage) {
    Remaining = (*FPD(TCharacter (*), Who)).HpCurrent - Damage;
  } else {
    Overkill = Damage - (*FPD(TCharacter (*), Who)).HpCurrent;
  }
  if (((Overkill > 9)) || ((((Remaining == 0)) && (((*FPD(TCharacter (*), Who)).Status == StatusAnimated))))) {
    (*FPD(TCharacter (*), Who)).Status = StatusDead;
  } else if (Overkill > 0) {
    (*FPD(TCharacter (*), Who)).Status = StatusDying;
    if (ViewMode == ViewModeCombat) {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).DyingRounds = Overkill;
    }
  } else if (Remaining == 0) {
    (*FPD(TCharacter (*), Who)).Status = StatusUnconscious;
  }
  if (!(((t1 = (*FPD(TCharacter (*), Who)).Status), (t1 == StatusOkay || t1 == StatusAnimated)))) {
    (*FPD(TCharacter (*), Who)).Flag10D = 0;
    (*FPD(TCharacter (*), Who)).HpCurrent = 0;
    if (ViewMode == ViewModeCombat) {
      SideCounts[(*FPD(TCharacter (*), Who)).Side]--;
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative = 0;
    }
  } else {
    (*FPD(TCharacter (*), Who)).HpCurrent = Remaining;
  }
}

/* 00BA:234A. Shows how far a heal brought Who: "is fully healed" when its current hit points (the
     byte +$11B) equal its maximum (HpMax, +$32) and "is partially healed" otherwise, through
     ShowCharacterMessage with a wait. Outside the combat view it then redraws the party roster
     (DrawPartyRoster) for the selected character. ovl12 and ovl22 (the healing and training code)
     call it. Globals: ViewMode (view mode), SelectedCharacter. */
void ShowHealResult(farptr Who)
{
  POOL_TRACE("ShowHealResult");
  String40_RES06 Message = {0};
  if ((*FPD(TCharacter (*), Who)).HpCurrent == (*FPD(TCharacter (*), Who)).HpMax) {
    rtl_str_assign(Message, 40, S("\017is fully healed"));
  } else {
    rtl_str_assign(Message, 40, S("\023is partially healed"));
  }
  ShowCharacterMessage(Who, Message, CombatMessageRow, 1);
  if (ViewMode != ViewModeCombat) {
    DrawPartyRoster(SelectedCharacter);
  }
}

/* 00BA:23B7. Returns the side opposite Who's (Side, +$10E): 1 when Who is on the party side (0) and
     0 otherwise. The combat AI indexes the per-side counts SideCounts with it to count Who's
     enemies (UseMagicItem, CastMemorizedSpell, DifferentSideInArea) and ovl12/ovl13/ovl22 use it
     too. Globals: none. */
u8 OpposingSide(farptr Who)
{
  POOL_TRACE("OpposingSide");
  u8 Result = 0;
  if ((*FPD(TCharacter (*), Who)).Side == SideParty) {
    Result = SideMonsters;
  } else {
    Result = SideParty;
  }
  return Result;
}

/* 00BA:23DB. Recounts the living combatants of each side: it clears both per-side counts
     (SideCounts) and walks the character list (PartyListHead) adding one for every member that takes part
     in combat (Flag10D, +$10D, set) to its own side's count. RunCombat and EndCombatRound call it at
     the start of a battle and each round; PlaceAllCombatants and ReviveCombatant also call it.
     Globals: PartyListHead (read), SideCounts (write). */
void RecountCombatSides(void)
{
  POOL_TRACE("RecountCombatSides");
  PCharacter Member = 0;
  SideCounts[0] = 0;
  SideCounts[1] = 0;
  Member = PartyListHead;
  while (Member != 0) {
    if ((*FPD(TCharacter (*), Member)).Flag10D != 0) {
      SideCounts[(*FPD(TCharacter (*), Member)).Side]++;
    }
    Member = (*FPD(TCharacter (*), Member)).Next;
  }
}

/* 00BA:2433. Collects Who's enemies that an area scan can reach into the target list CombatantScanList and
     returns how many there are. It scans the map for every combatant whose footprint line from Who is
     at most Range steps away (ScanTargets, direction omni, footprint kind of Who), then keeps only the
     records whose combatant is on the side opposite Who's (Side of CombatantRecord[SortEntries[I].Head]
     equals OpposingSide(Who)): each kept record is compacted into SortEntries (Move) and the table count
     (SortEntries[0].Val) is lowered to the kept count. Finally the combatant index of every kept record
     (SortEntries[I].Head) is written into CombatantScanList[1..Count], the combatant order the AI and the area spells
     work through (ovl09:02EB, 0B3C). The result is that count; 0 when no enemy is in range. */
u8 CollectEnemiesInRange(farptr Who, u8 Range)
{
  POOL_TRACE("CollectEnemiesInRange");
  u8 Result = 0;
  u8 Count = 0;
  u8 Found = 0;
  u8 Index = 0;
  ScanTargets(CombatantX(Who), CombatantY(Who), Range, OmniDir, CombatantKind(Who), CombatMap);
  Count = SortEntries[0].Val_;
  Found = 0;
  if (Count > 0) {
    {
      u8 limit = Count;
      if (1 <= limit) {
        Index = 1;
        for (;;) {
            if ((*FPD(TCharacter (*), CombatantRecord[SortEntries[Index].Head - 1])).Side == OpposingSide(Who)) {
              Found++;
              rtl_Move((void *)&SortEntries[Index], (void *)&SortEntries[Found], 3);
            }
          if (Index == limit) break;
          Index++;
        }
      }
    }
    Count = Found;
    SortEntries[0].Val_ = Found;
  }
  Result = Count;
  {
    u8 limit = Count;
    if (1 <= limit) {
      Index = 1;
      for (;;) {
          CombatantScanList[Index] = SortEntries[Index].Head;
        if (Index == limit) break;
        Index++;
      }
    }
  }
  return Result;
}

/* 00BA:255B. Returns half the distance, in map steps, of Target from Who. It preserves the current
     scan result (SortEntries, the 72 records ScanTargets can fill), opens the WalkLine tile gate
     (CombatMap^.Head6, +6) so the line is not blocked by the tile the combatants stand on, scans from
     Who (ScanTargets over $FF steps, direction omni, footprint kind of Who), closes the gate again,
     and looks Target up among the found combatants (CombatantRecord[SortEntries[I].Head] = Target; the
     first index I with a match, or the scan count when it is not found). The result is that record's
     shortest walk length (Key, the fewest WalkLine steps) divided by two, the distance in map cells;
     ovl09:0B3C and others test it = 1 as melee range. The saved records are put back before the
     return. Globals: SortEntries (read/write), CombatMap (write), CombatantRecord (read).
     QUIRK 00BA:2617: when Target is not found the result comes from the record at the scan count
     (or from record 1 when nothing was found), not from a defined value. */
u8 DistanceToTarget(farptr Who, farptr Target)
{
  POOL_TRACE("DistanceToTarget");
  u8 Result = 0;
  TSortRec Saved[255] = {0};
  u8 Index = 0;
  rtl_Move((void *)&SortEntries[1], (void *)&Saved, SavedScanBytes);
  (*FPD(TCombatMap (*), CombatMap)).Head6 = 1;
  ScanTargets(CombatantX(Who), CombatantY(Who), UnlimitedSteps, OmniDir, CombatantKind(Who), CombatMap);
  (*FPD(TCombatMap (*), CombatMap)).Head6 = 0;
  Index = 1;
  while (((CombatantRecord[SortEntries[Index].Head - 1] != Target)) && ((Index < SortEntries[0].Val_))) {
    Index++;
  }
  Result = (s16)((u16)SortEntries[Index].Key >> 1);
  rtl_Move((void *)&Saved, (void *)&SortEntries[1], SavedScanBytes);
  return Result;
}

/* 00BA:2637. Ends Who's combat turn: it clears the pending spell (PendingSpell, +$0; CastChosenSpell
     casts it when the turn ends), the turn order (Initiative, +$3), the guard byte (B7, +$7; the Guard
     command of the Done menu sets it to 1) and the movement left (Moves, +$6), then returns 1 (the
     turn is over). The Done menu's Quit command, every "the turn ends" path of the AI and the self-end
     checks call it (ovl08:031A, 09DF, 0E45; ovl09:000F, 07F2, 0B3C, 10D7; ovl12; ovl13).
     Globals: none. */
u8 EndCombatTurn(farptr Who)
{
  POOL_TRACE("EndCombatTurn");
  u8 Result = 0;
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative = 0;
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).PendingSpell = 0;
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).B7 = 0;
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves = 0;
  Result = 1;
  return Result;
}

/* 00BA:2686. Guards: ends Who's combat turn (EndCombatTurn) so the initiative, movement and pending
     spell are gone, then sets the guard byte (Combat^.B7, +$7) to 1 and flashes 'Guarding' on the
     bottom line (ShowFlashMessage). The Done menu's Guard command (ovl08:0E45) and EndOrGuardTurn
     (the AI's fallback when the character has nothing to do) call it; the return value is the 1
     EndCombatTurn gives, so the turn is over. Globals: none. */
u8 GuardTurn(farptr Who)
{
  POOL_TRACE("GuardTurn");
  u8 Result = 0;
  Result = EndCombatTurn(Who);
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).B7 = 1;
  ShowFlashMessage(S("\010Guarding"));
  return Result;
}

/* 00BA:26C2. Returns the level the selected character casts a spell at: the spell's class
     (SpellTable[Spell].SpellClass, byte 0 of the 16-byte row; SpellClassCleric 0, SpellClassMagicUser 1) picks the
     character's level in that class (ClassLevels: ClassCleric 0, ClassMagicUser 5; whitepaper 5.6), and a spell
     class SpellClassFixed (2) gives SpecialSpellLevel (12). When ItemAffectUse is set every class except
     SpellClassFixed gives ItemSpellLevel (6) instead. SpellAreaSize multiplies the
     spell row's +3 byte by the result, so this is the power the spell is cast with. Called by the ovl22 casting
     routines.
     QUIRK 00BA:26FB: a spell class other than SpellClassCleric, SpellClassMagicUser or SpellClassFixed
     leaves the result unassigned (the frame byte is returned).
     Globals: SpellTable, SelectedCharacter (read), ItemAffectUse (read). */
u8 SpellCasterLevel(u8 Spell)
{
  POOL_TRACE("SpellCasterLevel");
  u8 Result = 0;
  switch (SpellTable[Spell].SpellClass) {
  case SpellClassCleric:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).ClassLevels[0];
    break;
  }
  case SpellClassMagicUser:
  {
    Result = (*FPD(TCharacter (*), SelectedCharacter)).ClassLevels[5];
    break;
  }
  case SpellClassFixed:
  {
    Result = SpecialSpellLevel;
    break;
  }
  }
  if (ItemAffectUse && ((SpellTable[Spell].SpellClass != SpellClassFixed))) {
    Result = ItemSpellLevel;
  }
  return Result;
}

/* 00BA:272A. Draws the window frames of a view screen (one DrawWindow each): the full screen
     (1,1)-(38,22), the bottom text window (1,17)-(38,22) and the upper-left window (1,1)-(15,15);
     when WithInner is set it also draws the inner window (3,3)-(13,13) that frames the character
     portrait or the 3D view. RedrawView calls it before drawing the portrait, the sprites or the
     area view. Side effect: the screen (DrawWindow clears and frames each window). */
void DrawViewWindows(u8 WithInner)
{
  POOL_TRACE("DrawViewWindows");
  DrawWindow(1, 1, 0x26, 0x16, 0, 0xF, S("\000"));
  DrawWindow(1, 0x11, 0x26, 0x16, 0, 0xF, S("\000"));
  DrawWindow(1, 1, 0xF, 0xF, 0, 0xF, S("\000"));
  if (WithInner) {
    DrawWindow(3, 3, 0xD, 0xD, 0, 0xF, S("\000"));
  }
}

/* 00BA:27D9. Redraws the whole screen for the current view mode (ViewMode), the resident unit's view
     dispatcher. Mode 0 is the plain full window; mode 1 the character portrait screen
     (DrawViewWindows then the HEAD and BODY sprites at (3,3)); mode 2 the camp (the portrait
     windows, the PIC sprite list and the roster); modes 3 and 4 the area view (DrawViewWindows,
     ShowAreaView and the roster, the inner window drawn only for mode 4); mode 6 the loot screen
     (the portrait windows, the PIC block 1 sprites and the roster). Modes 2, 3 and 4 draw the
     character roster and the location line, mode 6 the roster only; modes 0 and 1 draw neither
     (mode 1 shows the portrait). Called by the shop, the Temple, the loot, camp and combat menus to
     redraw their screen.
     Globals: ViewMode (read), ShownHeadBank, ShownBodyBank, PictureAnimation, SelectedCharacter (read). */
void RedrawView(void)
{
  POOL_TRACE("RedrawView");
  switch (ViewMode) {
  case ViewModePlain:
  {
    DrawWindow(1, 1, 0x26, 0x16, 0, 0xF, S("\000"));
    break;
  }
  case ViewModeShop:
  {
    DrawViewWindows(1);
    LoadHeadBodySprites(ShownHeadBank, ShownBodyBank);
    ShowHeadBodySprites(3, 3, 1);
    break;
  }
  case ViewModeCamp:
  {
    DrawViewWindows(1);
    LoadSpriteList(S("\003PIC"), 0x1D, 0, rtl_far(&PictureAnimation));
    DrawPartyRoster(SelectedCharacter);
    DrawLocationLine();
    break;
  }
  case ViewModeWall:
  {
    DrawViewWindows(1);
    ShowAreaView();
    DrawPartyRoster(SelectedCharacter);
    DrawLocationLine();
    break;
  }
  case ViewModeMap:
  {
    DrawViewWindows(0);
    ShowAreaView();
    DrawPartyRoster(SelectedCharacter);
    DrawLocationLine();
    break;
  }
  case ViewModeLoot:
  {
    DrawViewWindows(1);
    LoadSpriteList(S("\003PIC"), 1, 0, rtl_far(&PictureAnimation));
    DrawPartyRoster(SelectedCharacter);
    break;
  }
  }
}

/* 00BA:290B. Builds the party location line and draws it on row 15 of the side window (ClearWindow
     (17,15)-(38,15), then DrawTextAt (17,15) in LightGreen): the party position (PartyMapColumn and
     PartyMapRow, or the game map position GameVars^[VarMapX/Y] for the area view, the column shifted
     by the map page width for AreaViewKind 3 and 4), the facing (FacingNames) and the game clock time
     as hours:minutes (the game clock digits, each number padded to two digits with a leading zero).
     Outside the 3D view (GameVars^[VarShowWallOverlays] = 0) the position "column,row " is
     prepended; in the camp (ViewModeCamp) " camping" is appended and in the wilderness search mode
     (bit 0 of the travel mode word GameVars2^[714]) " search". Called by the camp and wilderness screens.
     Globals: PartyMapColumn, PartyMapRow, GameVars, AreaViewKind, VarsAt4900, FacingNames,
     PartyFacing, ViewMode, GameVars2 (all read). Side effect: the screen. */
void DrawLocationLine(void)
{
  POOL_TRACE("DrawLocationLine");
  s8 Col = 0;
  s8 Row = 0;
  u8 Hours[3] = {0};
  u8 Minutes[3] = {0};
  u8 Line[41] = {0};
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  u8 t5[256];
  u8 t6[256];
  u8 t7[256];
  u8 t8[256];
  u8 t9[256];
  u8 t10[256];
  u8 t11[256];
  rtl_str_assign(Line, 40, S("\000"));
  Col = PartyMapColumn;
  Row = PartyMapRow;
  if (AreaViewKind > 1) {
    Col = (*FPD(TGameVars (*), GameVars))[195];
    Row = (*FPD(TGameVars (*), GameVars))[196];
    if (AreaViewKind == 3) {
      Col += MapPageWidth;
    }
    if (AreaViewKind == 4) {
      Col += 26;
    }
  }
  rtl_str_assign(Hours, 2, WordToText(t1, (*FPD(TVmWords4900 (*), VarsAt4900))[201]));
  if (Hours[0] < 2) {
    rtl_str_assign(Hours, 2, rtl_str_cat(t2, 2, (const u8 *const[]){S("\0010"), Hours}));
  }
  rtl_str_assign(Minutes, 2, WordToText(t3, (u16)((10 * (*FPD(TVmWords4900 (*), VarsAt4900))[200]) + (*FPD(TVmWords4900 (*), VarsAt4900))[199])));
  if (Minutes[0] < 2) {
    rtl_str_assign(Minutes, 2, rtl_str_cat(t4, 2, (const u8 *const[]){S("\0010"), Minutes}));
  }
  if ((*FPD(TGameVars (*), GameVars))[251] == 0) {
    rtl_str_assign(Line, 40, rtl_str_cat(t7, 4, (const u8 *const[]){ByteToText(t5, Col), S("\001,"), ByteToText(t6, Row), S("\001 ")}));
  }
  rtl_str_assign(Line, 40, rtl_str_cat(t8, 3, (const u8 *const[]){Line, FacingNames[PartyFacing], S("\001 ")}));
  rtl_str_assign(Line, 40, rtl_str_cat(t9, 4, (const u8 *const[]){Line, Hours, S("\001:"), Minutes}));
  if (ViewMode == ViewModeCamp) {
    rtl_str_assign(Line, 40, rtl_str_cat(t10, 2, (const u8 *const[]){Line, S("\010 camping")}));
  } else if ((((*FPD(TGameVars (*), GameVars2))[714] & 1)) > 0) {
    rtl_str_assign(Line, 40, rtl_str_cat(t11, 2, (const u8 *const[]){Line, S("\007 search")}));
  }
  ClearWindow(0x11, 0xF, 0x26, 0xF);
  DrawTextAt(0x11, 0xF, LightGreen, Line);
}

/* 00BA:2B5E. Draws the wilderness map screen: it sets the view mode to ViewModeMap (3), draws the
     adventure screen's three windows (DrawAdventureScreen), the area view (ShowAreaView), the party
     marker (DrawPartyMarker), the location line and the character roster. Called by ovl14's
     HandleWildernessKeys when the party moves in the wilderness.
     Globals: ViewMode (write). Side effect: the screen. */
void DrawWildernessScreen(void)
{
  POOL_TRACE("DrawWildernessScreen");
  ViewMode = ViewModeMap;
  DrawAdventureScreen();
  ShowAreaView();
  DrawPartyMarker();
  DrawLocationLine();
  DrawPartyRoster(SelectedCharacter);
}

/* 00BA:2B88. Draws the combat screen: SwapPaletteColors0And8 prepares the EGA palette, the left window
     (1,1)-(21,21) and the right window (23,1)-(38,21) are drawn with DrawWindow, the bottom two rows
     (0,23)-(39,24) are cleared, and the cursor is placed on the combat map's view origin plus three
     cells (MoveCombatCursor: margin CursorMargin, direction CursorNoStep). Called by StartBattle,
     PlayerTurn and the combat overlays. Globals: CombatMap (read). Side effect: the screen. */
void DrawCombatScreen(void)
{
  POOL_TRACE("DrawCombatScreen");
  SwapPaletteColors0And8();
  DrawWindow(1, 1, 0x15, 0x15, 0, 0, S("\000"));
  DrawWindow(0x17, 1, 0x26, 0x15, 0, 0, S("\000"));
  ClearWindow(0, 0x17, ScreenLastCol, 0x18);
  MoveCombatCursor((s16)((*FPD(TCombatMap (*), CombatMap)).ViewX + ViewCentreCell), (s16)((*FPD(TCombatMap (*), CombatMap)).ViewY + ViewCentreCell), CursorMargin, CursorNoStep);
}

/* 00BA:2C48. The party-member picker: it loops showing the character roster (DrawPartyRoster) and
     a ReadPromptChoice prompt titled Title with the word "Select" (and " Exit" when WithExit is set),
     updating the caller's Selected pointer. When ReadPromptChoice sets its extended-key flag ExtKey,
     the scan code 'O' (End) steps to the next member and 'G' (Home) to the previous (both wrap around
     the party list PartyListHead); with ExtKey clear a typed G or O does nothing. A typed 'E', or a key code
     #0 with ExtKey clear, clears the selection. QUIRK 00BA:2C48: the #0 test runs only when ExtKey is
     clear, so #0 is not an extended-key prefix but the key code 0 returned with the flag clear. The
     loop ends on Enter, Escape, 'E' or 'S'; Enter, Escape and 'S' (the hotkey of the prompt's "Select"
     word) keep the current selection, 'E' clears it. Animate for ReadPromptChoice is 1 in the camp
     (ViewModeCamp) and loot (ViewModeLoot) screens. Called by ovl03, ovl19 and ovl22.
     Globals: ViewMode (read), PartyListHead (read). Side effects: the screen, the keyboard. */
void SelectPartyMember(const u8 *Title_in, u8 WithExit, PCharacter (*Selected))
{
  POOL_TRACE("SelectPartyMember");
  const u8 *Title = Title_in;
  u8 Key = 0;
  u8 ExtKey = 0;
  u8 Animate = 0;
  PCharacter PartyMember = 0;
  u8 Extra[41] = {0};
  u8 t1[256];
  u8 t2[256];
  Key = ' ';
  rtl_str_assign(Extra, 40, S("\000"));
  if (WithExit) {
    rtl_str_assign(Extra, 40, S("\005 Exit"));
  }
  while (!((Key == KeyEnter_RES12 || Key == KeyEscape_RES12 || Key == KeyExit || Key == KeySelect))) {
    DrawPartyRoster((*Selected));
    if (((ViewMode == ViewModeCamp)) || ((ViewMode == ViewModeLoot))) {
      Animate = 1;
    } else {
      Animate = 0;
    }
    Key = ReadPromptChoice(rtl_str_cat(t1, 2, (const u8 *const[]){Title, S("\001 ")}), rtl_str_cat(t2, 2, (const u8 *const[]){S("\006Select"), Extra}), PromptTitleColor, PromptWordColor, PromptHotColor, AcceptExtendedKeys, Animate, &ExtKey);
    PartyMember = (*Selected);
    if (ExtKey != 0) {
      switch ((u8)Key) {
      case 'O':
      {
        PartyMember = (*FPD(TCharacter (*), PartyMember)).Next;
        if (PartyMember == 0) {
          PartyMember = PartyListHead;
        }
        break;
      }
      case 'G':
      {
        PartyMember = PartyListHead;
        if ((*Selected) != PartyListHead) {
          while ((*FPD(TCharacter (*), PartyMember)).Next != (*Selected)) {
            PartyMember = (*FPD(TCharacter (*), PartyMember)).Next;
          }
        } else {
          while ((*FPD(TCharacter (*), PartyMember)).Next != 0) {
            PartyMember = (*FPD(TCharacter (*), PartyMember)).Next;
          }
        }
        break;
      }
      }
    } else if (((Key == KeyExit)) || ((Key == 0x00))) {
      PartyMember = 0;
    }
    (*Selected) = PartyMember;
  }
}

/* 00BA:2E03. Returns whether Who's readied weapon (SlotItems[0], +$CC) is a missile weapon: False
     with no readied weapon, otherwise True when the weapon kind's ItemTable attack range (byte $C) is
     above 1 (a melee weapon has range 1). ovl08's MeleeAttack refuses a missile-only weapon
     (IsRangedWeapon and not RangedWeaponCanMelee); the combat AI and ovl13 test it too.
     Globals: ItemTable (read). */
u8 IsRangedWeapon(farptr Who)
{
  POOL_TRACE("IsRangedWeapon");
  u8 Result = 0;
  if ((((*FPD(TCharacter (*), Who)).SlotItems[0] != 0)) && ((ItemTable[(*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[0])).ItemType].Range > 1))) {
    Result = 1;
  } else {
    Result = 0;
  }
  return Result;
}

/* 00BA:2E46. Returns whether Who's readied missile weapon (IsRangedWeapon) can also strike in
     melee: True when IsRangedWeapon holds and the weapon kind's ItemTable attack flags carry both the
     melee bit ($10) and the strength bit ($04). ovl08's MeleeAttack allows the attack only when
     IsRangedWeapon implies this too (else "Not with that weapon"); ovl09 and ovl13 test it.
     Globals: ItemTable (read). */
u8 RangedWeaponCanMelee(farptr Who)
{
  POOL_TRACE("RangedWeaponCanMelee");
  u8 Result = 0;
  if (IsRangedWeapon(Who) && ((((ItemTable[(*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[0])).ItemType].Flags & ((WeaponFlagMelee | WeaponFlagStrength)))) == ((WeaponFlagMelee | WeaponFlagStrength))))) {
    Result = 1;
  } else {
    Result = 0;
  }
  return Result;
}

/* 00BA:2E8B. Picks the item Who's attack aims with and returns whether it found one, clearing Aim
     first. With a readied weapon (SlotItems[0], +$CC): its kind's ItemTable attack flags (byte $E)
     decide the aim. The melee bit ($10) aims the weapon itself; the launcher bit ($08) aims the item
     in slot 11 (+$F8) when the slot-11 bit ($01) is set, or the item in slot 12 (+$FC) when the
     slot-12 bit ($80) is set. The result is 1 when an item was aimed, or when the flags are exactly
     $A (that case returns 1 with Aim still nil; why is not proven); 0 otherwise. ovl09's AiTurn
     passes the aimed item to PerformAttack for the attack. Globals: ItemTable (read). */
u8 ChooseAttackItem(farptr Who, farptr (*Aim))
{
  POOL_TRACE("ChooseAttackItem");
  u8 Result = 0;
  PItem Item = 0;
  u8 Flags = 0;
  Result = 0;
  Item = (*FPD(TCharacter (*), Who)).SlotItems[0];
  (*Aim) = 0;
  Flags = 0;
  if (Item != 0) {
    Flags = ItemTable[(*FPD(TMenuLine (*), Item)).ItemType].Flags;
    if (((Flags & WeaponFlagMelee)) != 0) {
      (*Aim) = Item;
    }
    if (((Flags & WeaponFlagAmmo)) != 0) {
      if (((Flags & WeaponFlagSlot11Plus)) != 0) {
        (*Aim) = (*FPD(TCharacter (*), Who)).SlotItems[11];
      }
      if (((Flags & WeaponFlagSlot12Plus)) != 0) {
        (*Aim) = (*FPD(TCharacter (*), Who)).SlotItems[12];
      }
    }
  }
  if ((((*Aim) != 0)) || ((Flags == 0xA))) {
    Result = 1;
  }
  return Result;
}

/* 00BA:2F57. Returns whether Who's level in one class has reached the maximum its race allows:
     CastRestoration (ovl22:2C43, spell 56 Restoration) picks the class that regains a drained level
     and skips a class this reaches, so it never raises ClassLevels[ClassIndex] (+$96) past the cap.
     The training hall's TrainCharacter (ovl16:29AE) does not call this: it inlines the same race and
     strength limits. False when the level is 0; otherwise Who's race (+$2E) and
     strength (+$10) pick the limit (the AD&D demihuman level limits [H]): a dwarf (RaceDwarf 1) in the
     fighter class (ClassFighter 2) stops at level 8 with Strength17 (17), at 7 with less; an elf
     (RaceElf 2) stops at 7, at 6 with Strength17, at 5 with less; a gnome (RaceGnome 3) stops at 6, at
     5 with strength below ExceptionalStrength (18); a half-elf (RaceHalfElf 4) stops at 5 in the cleric class
     (ClassCleric 0) and at 8 in the fighter class, at 7 with Strength17, at 6 with less; a halfling
     (RaceHalfling 5) stops at 6, at 5 with Strength17, at 4 with less.
     ClassIndex is the class index 0..7. Globals: none. */
u8 IsMaxClassLevel(PCharacter Who, s8 ClassIndex)
{
  POOL_TRACE("IsMaxClassLevel");
  u8 Result = 0;
  s8 Level = 0;
  Result = 0;
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), Who));
      Level = w1->ClassLevels[ClassIndex];
      if (Level > 0) {
        switch (w1->Race) {
        case RaceDwarf:
        {
          if (((ClassIndex == ClassFighter)) && (((((Level == 8)) && ((w1->Strength == Strength17))) || (((Level == 7)) && ((w1->Strength < Strength17)))))) {
            Result = 1;
          }
          break;
        }
        case RaceElf:
        {
          if (((ClassIndex == ClassFighter)) && (((((Level == 7)) || (((Level == 6)) && ((w1->Strength == Strength17)))) || (((Level == 5)) && ((w1->Strength < Strength17)))))) {
            Result = 1;
          }
          break;
        }
        case RaceGnome:
        {
          if (((ClassIndex == ClassFighter)) && ((((Level == 6)) || (((Level == 5)) && ((w1->Strength < ExceptionalStrength)))))) {
            Result = 1;
          }
          break;
        }
        case RaceHalfElf:
        {
          if (((ClassIndex == ClassCleric)) && ((Level == 5))) {
            Result = 1;
          } else if (((ClassIndex == ClassFighter)) && (((((Level == 8)) || (((Level == 7)) && ((w1->Strength == Strength17)))) || (((Level == 6)) && ((w1->Strength < Strength17)))))) {
            Result = 1;
          }
          break;
        }
        case RaceHalfling:
        {
          if (((ClassIndex == ClassFighter)) && (((((Level == 6)) || (((Level == 5)) && ((w1->Strength == Strength17)))) || (((Level == 4)) && ((w1->Strength < Strength17)))))) {
            Result = 1;
          }
          break;
        }
        }
      }
  }
  return Result;
}

/* Initialisation part of unit RES12. */
void init_RES12(void)
{
  POOL_TRACE("init");
}
