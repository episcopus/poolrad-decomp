#include "game.h"

/* ovl22:008A: retf 6: 6 bytes of parameters; 98 bytes of locals */
/* ovl22:008A. The spell menu picker ChooseSpellFromList (ovl19:299C) calls once BuildSpellList has filled
     SpellMenuList: it shows the list in the spell window through ChooseFromList, asking again until the player
     picks a word (Cast, Learn, Memorize or Scribe), presses Enter or leaves, and returns the spell number of the
     chosen line, or 0 when the player left (Exit or Escape). Mode (ChooseSpellFromList's DisplayMode) picks the
     button word: 1 'Cast', 2 'Memorize', 3 'Scribe', 4 'Learn' (any other Mode: no button and no title); the
     title is 'Choose Spell: ' for Modes 1 to 4. Mode 2 uses the short window (bottom row $0F, else $16) and
     Mode 4 offers no Exit. Choice is the list position the picker starts on and receives the position it ends
     on; a negative Choice (-1 from UseItem) first draws the spell window frame (rows 3 to the bottom) and
     restarts at 0. The page is redrawn on entry for a new window, and always for Learn and Cast. Mode 3 (Scribe)
     copies the item the chosen line came from, SpellMenuItems[index of the line], to CurrentItem. The list is
     freed (FreeMenuList) before returning. Globals: SpellMenuList (freed), SpellMenuSpells, SpellMenuItems,
     CurrentItem. Side effects: the screen, the heap.
     Choice stays the Word its callers declare and reaches ChooseFromList (var Choice: Integer) through the
     typecast Integer(Choice), a variable reference TP 6.0 accepts (probe VARCAST.PAS; WDTOIN.PAS shows the
     plain Word is refused).
     QUIRK ovl22:0194: the byte at [bp-5C] is allocated but never read or written.
     QUIRK ovl22:0230: with a left picker (Key #0) Selected is nil, the walk ends at the list's end and SpellIndex
     is the count of spell lines; Mode 3 then still copies SpellMenuItems[SpellIndex] to CurrentItem.
     QUIRK ovl22:01E8: the loop ends on the Key set [#0, Enter, 'C', 'E', 'L', 'M', 'S'] (the first letters of the
     buttons Cast, Exit, Learn, Memorize and Scribe), although ChooseFromList itself returns #0 for E and
     Escape. */
u8 PickSpellFromMenu(u8 Mode, u16 (*Choice))
{
  POOL_TRACE("PickSpellFromMenu");
  u8 Result = 0;
  PMenuLine Selected = 0;
  PMenuLine WalkPtr = 0;
  String40_RES06 Title = {0};
  String40_RES06 Prompt = {0};
  u8 UnusedByte = 0;
  u8 SpellIndex = 0;
  s8 Bottom = 0;
  u8 Key = 0;
  u8 WithExit = 0;
  u8 Redraw = 0;
  switch (Mode) {
  case PickSpellFromMenu_CastMode:
  {
    rtl_str_assign(Prompt, 40, S("\004Cast"));
    break;
  }
  case PickSpellFromMenu_MemorizeMode:
  {
    rtl_str_assign(Prompt, 40, S("\010Memorize"));
    break;
  }
  case PickSpellFromMenu_ScribeMode:
  {
    rtl_str_assign(Prompt, 40, S("\006Scribe"));
    break;
  }
  case PickSpellFromMenu_LearnMode:
  {
    rtl_str_assign(Prompt, 40, S("\005Learn"));
    break;
  }
  default:
  {
    rtl_str_assign(Prompt, 40, S("\000"));
  }
  }
  if ((Mode >= PickSpellFromMenu_CastMode && Mode <= PickSpellFromMenu_LearnMode)) {
    rtl_str_assign(Title, 40, S("\016Choose Spell: "));
  } else {
    rtl_str_assign(Title, 40, S("\000"));
  }
  if (Mode == PickSpellFromMenu_MemorizeMode) {
    Bottom = PickSpellFromMenu_ShortWindowBottom;
  } else {
    Bottom = PickSpellFromMenu_TallWindowBottom;
  }
  if (Mode == PickSpellFromMenu_LearnMode) {
    WithExit = 0;
  } else {
    WithExit = 1;
  }
  Redraw = 0;
  if ((*Choice) < 0) {
    DrawWindow(PickSpellFromMenu_WindowLeft, PickSpellFromMenu_WindowFrameTop, PickSpellFromMenu_WindowRight, Bottom, 0, 0, S("\000"));
    Redraw = 1;
    (*Choice) = 0;
  }
  if (((Mode == PickSpellFromMenu_LearnMode)) || ((Mode == PickSpellFromMenu_CastMode))) {
    Redraw = 1;
  }
  Selected = 0;
  do {
    Key = ChooseFromList(Title, Prompt, PickSpellFromMenu_HeadingColor, PickSpellFromMenu_LineColor, PickSpellFromMenu_HighlightColor, PickSpellFromMenu_WindowLeft, PickSpellFromMenu_ListTop, PickSpellFromMenu_WindowRight, Bottom, SpellMenuList, WithExit, &Redraw, &(*Choice), &Selected);
  } while (!(Key == PickSpellFromMenu_KeyNone || Key == PickSpellFromMenu_KeyEnter || Key == 'C' || Key == 'E' || Key == 'L' || Key == 'M' || Key == 'S'));
  WalkPtr = SpellMenuList;
  SpellIndex = 0;
  while (WalkPtr != Selected) {
    if ((*FPD(TMenuLine (*), WalkPtr)).Flag29 == 0) {
      SpellIndex++;
    }
    WalkPtr = (*FPD(TMenuLine (*), WalkPtr)).Next;
  }
  if (Key == PickSpellFromMenu_KeyNone || Key == 'E') {
    Result = 0;
  } else {
    Result = SpellMenuSpells[SpellIndex];
  }
  if (Mode == PickSpellFromMenu_ScribeMode) {
    CurrentItem = SpellMenuItems[SpellIndex];
  }
  FreeMenuList(&SpellMenuList);
  return Result;
}

/* ovl22:028D: retf 2: 2 bytes of parameters; 262 bytes of locals */
/* ovl22:028D. Appends one line for spell Spell to the spell menu list SpellMenuList (BuildSpellList calls this
     once per spell, in list order). The line's text is ' *' when the pending bit $80 of Spell is set,
     else '  ', followed by SpellNames[Spell and $7F]; when the spell's level differs from the level of
     the previous line a heading line (SpellLevelNames[level]: '1st Level' and so on) is inserted first.
     SpellMenuSpells[Count] keeps the spell number (pending bit cleared) of the line added. Called by BuildSpellList
     and AddItemSpells. */
void AddSpellMenuLine(u8 Spell)
{
  POOL_TRACE("AddSpellMenuLine");
  PMenuLine Line = 0;
  s8 Count = 0;
  s8 PrevLevel = 0;
  u8 t1[256];
  Line = SpellMenuList;
  if (SpellMenuList == 0) {
    Line = rtl_getmem(MenuLineBytes);
    SpellMenuList = Line;
    PrevLevel = 0;
    Count = 0;
  } else {
    Count = 1;
    while ((*FPD(TMenuLine (*), Line)).Next != 0) {
      if ((*FPD(TMenuLine (*), Line)).Flag29 == 0) {
        Count++;
      }
      Line = (*FPD(TMenuLine (*), Line)).Next;
    }
    PrevLevel = SpellTable[SpellMenuSpells[(s16)(Count - 1)]].Level;
    (*FPD(TMenuLine (*), Line)).Next = rtl_getmem(MenuLineBytes);
    Line = (*FPD(TMenuLine (*), Line)).Next;
  }
  (*FPD(TMenuLine (*), Line)).Next = 0;
  if (SpellTable[(Spell & SpellMask)].Level != PrevLevel) {
    rtl_str_assign((*FPD(TMenuLine (*), Line)).Text, 40, SpellLevelNames[SpellTable[(Spell & SpellMask)].Level]);
    (*FPD(TMenuLine (*), Line)).Flag29 = 1;
    (*FPD(TMenuLine (*), Line)).Next = rtl_getmem(MenuLineBytes);
    Line = (*FPD(TMenuLine (*), Line)).Next;
    (*FPD(TMenuLine (*), Line)).Next = 0;
  }
  if (Spell > SpellMask) {
    rtl_str_assign((*FPD(TMenuLine (*), Line)).Text, 40, S("\002 *"));
  } else {
    rtl_str_assign((*FPD(TMenuLine (*), Line)).Text, 40, S("\002  "));
  }
  rtl_str_assign((*FPD(TMenuLine (*), Line)).Text, 40, rtl_str_cat(t1, 2, (const u8 *const[]){(*FPD(TMenuLine (*), Line)).Text, SpellNames[(Spell & SpellMask)]}));
  (*FPD(TMenuLine (*), Line)).Flag29 = 0;
  SpellMenuSpells[Count] = (Spell & SpellMask);
}

/* ovl22:044E: retf 2: 2 bytes of parameters; 6 bytes of locals */
/* ovl22:044E. Adds the spell affects of the current item (CurrentItem, set by AddScrollSpells or by the
     caller) to the spell menu list: for each of its three spell affects it calls AddSpellMenuLine and
     records the item in SpellMenuItems[SpellMenuItemCount]. Pending selects which affects count: nonzero
     takes the pending ones (the pending bit $80 set, > $80), zero the plain ones (> 0). First it clears
     the item's HiddenNames so its spells can be listed: a character carrying the Read Magic affect
     (HasAffect(SelectedCharacter, ReadMagicAffect)) sees the item's hidden spell names, and a cleric
     (ClassLevels[0] > 0) sees a cleric's scroll (ItemTable[CurrentItem^.ItemType].Slot =
     ClericScrollClass); an item whose HiddenNames is not cleared is skipped. Called by BuildSpellList
     (Kind 2) and AddScrollSpells. */
void AddItemSpells(u8 Pending)
{
  POOL_TRACE("AddItemSpells");
  u8 I = 0;
  farptr Affect = 0;
  if (HasAffect(SelectedCharacter, AddItemSpells_ReadMagicAffect, &Affect) || (((((*FPD(TCharacter (*), SelectedCharacter)).ClassLevels[0] > 0)) && ((ItemTable[(*FPD(TMenuLine (*), CurrentItem)).ItemType].Slot == AddItemSpells_ClericScrollClass))))) {
    (*FPD(TMenuLine (*), CurrentItem)).HiddenNames = 0;
  }
  if ((*FPD(TMenuLine (*), CurrentItem)).HiddenNames == 0) {
    {
      if (1 <= 3) {
        I = 1;
        for (;;) {
            if (((((Pending != 0)) && (((*FPD(TMenuLine (*), CurrentItem)).Affects[I - 1] > AddItemSpells_PendingSpell)))) || ((((Pending == 0)) && (((*FPD(TMenuLine (*), CurrentItem)).Affects[I - 1] > 0))))) {
              AddSpellMenuLine((*FPD(TMenuLine (*), CurrentItem)).Affects[I - 1]);
              SpellMenuItems[SpellMenuItemCount] = CurrentItem;
              SpellMenuItemCount++;
            }
          if (I == 3) break;
          I++;
        }
      }
    }
  }
}

/* ovl22:051C: retf 2: 2 bytes of parameters; 2 bytes of locals */
/* ovl22:051C. Builds the spell menu list from the selected character's carried items: it clears
     SpellMenuItems and SpellMenuItemCount, then walks SelectedCharacter^.Items and, for every scroll
     (IsScroll), calls AddItemSpells with its Pending argument. Called by BuildSpellList for the "on Scrolls"
     (Pending 0) and "to be scribed" (Pending 1) lists. */
void AddScrollSpells(u8 Pending)
{
  POOL_TRACE("AddScrollSpells");
  u8 I = 0;
  {
    if (0 <= 0x30) {
      I = 0;
      for (;;) {
          SpellMenuItems[I] = 0;
        if (I == 0x30) break;
        I++;
      }
    }
  }
  SpellMenuItemCount = 0;
  CurrentItem = (*FPD(TCharacter (*), SelectedCharacter)).Items;
  while (CurrentItem != 0) {
    if (IsScroll(CurrentItem)) {
      AddItemSpells(Pending);
    }
    CurrentItem = (*FPD(TMenuLine (*), CurrentItem)).Next;
  }
}

/* ovl22:059C: retf 2: 2 bytes of parameters; 2 bytes of locals */
/* ovl22:059C. Builds the spell menu list SpellMenuList for the requested list kind and returns whether it
     is not empty. Kind (ChooseSpellFromList's SpellListKind): 0 the memorized spells (Spells[0..$14], plain),
     5 the pending memorized ones (bit $80), 1 the spell book (KnownSpells[1..$37]), 2 the selected
     character's first scroll item, 3 all scroll items plain, 6 all scroll items pending, 4 the spells the
     character has a slot for and does not know yet (SpellTable 1..$38). It clears SpellMenuSpells first.
     Called by ovl19:299C ChooseSpellFromList. */
u8 BuildSpellList(u8 Kind)
{
  POOL_TRACE("BuildSpellList");
  u8 Result = 0;
  u8 I = 0;
  Result = 0;
  SpellMenuList = 0;
  {
    if (0 <= 0x14) {
      I = 0;
      for (;;) {
          SpellMenuSpells[I] = 0;
        if (I == 0x14) break;
        I++;
      }
    }
  }
  switch (Kind) {
  case 0:
  {
    {
      if (0 <= 0x14) {
        I = 0;
        for (;;) {
            if ((((*FPD(TCharacter (*), SelectedCharacter)).Spells[I] > 0)) && (((*FPD(TCharacter (*), SelectedCharacter)).Spells[I] < BuildSpellList_PendingSpell))) {
              AddSpellMenuLine((*FPD(TCharacter (*), SelectedCharacter)).Spells[I]);
            }
          if (I == 0x14) break;
          I++;
        }
      }
    }
    break;
  }
  case 5:
  {
    {
      if (0 <= 0x14) {
        I = 0;
        for (;;) {
            if ((*FPD(TCharacter (*), SelectedCharacter)).Spells[I] > SpellMask) {
              AddSpellMenuLine((*FPD(TCharacter (*), SelectedCharacter)).Spells[I]);
            }
          if (I == 0x14) break;
          I++;
        }
      }
    }
    break;
  }
  case 1:
  {
    {
      if (1 <= 0x37) {
        I = 1;
        for (;;) {
            if ((*FPD(TCharacter (*), SelectedCharacter)).KnownSpells[I - 1] != 0) {
              AddSpellMenuLine(I);
            }
          if (I == 0x37) break;
          I++;
        }
      }
    }
    break;
  }
  case 2:
  {
    AddItemSpells(0);
    break;
  }
  case 3:
  {
    AddScrollSpells(0);
    break;
  }
  case 6:
  {
    AddScrollSpells(1);
    break;
  }
  case 4:
  {
    {
      if (1 <= 0x38) {
        I = 1;
        for (;;) {
            if ((((*FPD(TCharacter (*), SelectedCharacter)).SpellSlots[SpellTable[I].SpellClass][SpellTable[I].Level - 1] > 0)) && (((*FPD(TCharacter (*), SelectedCharacter)).KnownSpells[I - 1] == 0))) {
              AddSpellMenuLine(I);
            }
          if (I == 0x38) break;
          I++;
        }
      }
    }
    break;
  }
  }
  if (SpellMenuList != 0) {
    Result = 1;
  }
  return Result;
}

/* ovl22:0729: retf 2: 2 bytes of parameters; 2 bytes of locals */
/* ovl22:0729. The size of the area pattern of spell Spell: CollectEnemiesInRange collects the targets it
     reaches. A 16-byte SpellTable row gives a base (row +2) and a per-level byte (row +3), so the
     result is base + per-level * caster level, the level from SpellCasterLevel (or * 6 while ItemAffectUse is
     set). A zero base with row +6 set becomes 1, and $FF (omni) becomes 1 too. Called by SpellAccepted
     (ovl09:02EB) and ovl13:1E16. */
u8 SpellAreaSize(u8 Spell)
{
  POOL_TRACE("SpellAreaSize");
  u8 Result = 0;
  u8 Area = 0;
  if (!ItemAffectUse) {
    Area = SpellTable[Spell].Pad2[0] + (SpellTable[Spell].Pad2[1] * SpellCasterLevel(Spell));
  } else {
    Area = (SpellTable[Spell].Pad2[1] * 6) + SpellTable[Spell].Pad2[0];
  }
  if (Area == 0) {
    if (SpellTable[Spell].Pad2[4] != 0) {
      Area = 1;
    }
  }
  if (Area == 0xFF) {
    Area = 1;
  }
  Result = Area;
  return Result;
}

/* ovl22:07D6. The duration (in ApplyAffect's time unit) of the affect a spell leaves. Spell is the
     spell number (the cast handlers pass CastingSpell). A few spells are rolled for instead of read from the
     table: spell 40 Cause Disease is 1d6*10, spells 57 and 61 are 5d4, spell 59 is 1d4*10+40, spell 63 is
     2d10*10 in combat (view mode 5) else (1d10+10)*10, and spell 67 is a flat $5A0. Every other value
     uses the SpellTable row's duration base (byte +4) plus its per-level byte (byte +5) times the caster
     level from SpellCasterLevel. Called by ApplySpellToTargets (as ApplyAffect's Duration) and
     CastEnlarge, CastHoldPerson, CastStrength, CastMonsterStrength. */
u16 SpellAffectDuration(u8 Spell)
{
  POOL_TRACE("SpellAffectDuration");
  u16 Result = 0;
  u16 Value = 0;
  switch (Spell) {
  case SpellAffectDuration_CauseDisease:
  {
    Value = RollDice(1, 6) * SpellAffectDuration_Scale;
    break;
  }
  case SpellAffectDuration_MonsterHaste:
  case SpellAffectDuration_MonsterParalyze:
  {
    Value = RollDice(5, 4);
    break;
  }
  case SpellAffectDuration_MonsterStrength:
  {
    Value = (RollDice(1, 4) * SpellAffectDuration_Scale) + 40;
    break;
  }
  case SpellAffectDuration_MonsterInvisibility:
  {
    if (ViewMode == ViewModeCombat) {
      Value = RollDice(2, 10) * SpellAffectDuration_Scale;
    } else {
      Value = ((s16)(RollDice(1, 10) + SpellAffectDuration_Scale)) * SpellAffectDuration_Scale;
    }
    break;
  }
  case SpellAffectDuration_MonsterReadMagic:
  {
    Value = 0x5A0;
    break;
  }
  default:
  {
    Value = SpellTable[Spell].Pad2[2] + (SpellTable[Spell].Pad2[3] * SpellCasterLevel(Spell));
  }
  }
  Result = Value;
  return Result;
}

/* ovl22:08C3. Applies the chosen spell Spell to every target in SpellTargets[1..SpellTargetCount] (the list the
     picker ChooseSpellTargets filled). It first sets the global DamageKind (Kind when the spell deals Damage,
     else 0) and returns at once with no targets. For each non-nil target: it rolls the spell's own
     saving throw (SpellTable row byte +8 nonzero, the save kind in +9) into Saved, and, when the
     current spell's row byte +2 is $FF, runs the affect hooks, and rolls to hit the target's
     ArmourClassValue (+$111); a miss cancels the damage and counts as saved. It deals Damage through
     DealDamage and, when the spell's AffectId (row byte +$A) is set, applies the affect through
     ApplyAffect with SpellAffectDuration(Spell), the caster level (CasterLevel, or SpellCasterLevel
     when 0), Flag, the row's save effect and Message. Called by the spell menus; the caster level is
     real or computed. */
void ApplySpellToTargets(u8 Spell, u8 CasterLevel, u8 Flag, u8 Damage, u8 Kind, const u8 *Message_in)
{
  POOL_TRACE("ApplySpellToTargets");
  const u8 *Message = Message_in;
  u8 Level = 0;
  u8 I = 0;
  PCharacter Target = 0;
  u8 Saved = 0;
  if (Damage == 0) {
    DamageKind = 0;
  } else {
    DamageKind = Kind;
  }
  if (SpellTargetCount == 0) {
    return;
  }
  if (CasterLevel == 0) {
    Level = SpellCasterLevel(Spell);
  } else {
    Level = CasterLevel;
  }
  {
    u8 limit = SpellTargetCount;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          if (SpellTargets[I] != 0) {
            Target = SpellTargets[I];
            if (SpellTable[Spell].Pad2[6] == 0) {
              Saved = 0;
            } else {
              Saved = SavingThrow(Target, SpellTable[Spell].Pad2[7], 0);
            }
            if (SpellTable[CastingSpell].Pad2[0] == 0xFF) {
              RecalcCombatValues(Target);
              RunAffectHooks(0xB, Target);
              if (!RollToHit(SelectedCharacter, Target, (*FPD(TCharacter (*), Target)).ArmourClassValue)) {
                Damage = 0;
                Saved = 1;
              }
            }
            if (Damage > 0) {
              DealDamage(Target, Damage, SpellTable[Spell].Pad2[6], Saved);
            }
            if (SpellTable[Spell].AffectId > 0) {
              ApplyAffect(Target, SpellTable[Spell].AffectId, SpellAffectDuration(Spell), Level, Flag, SpellTable[Spell].Pad2[6], Saved, Message);
            }
          }
        if (I == limit) break;
        I++;
      }
    }
  }
  DamageKind = 0;
}

/* ovl22:0A91. Picks the targets of a spell being cast and reports through Done whether the cast should
     go ahead. It defaults the picker's chosen character PickedSpellCharacter to the selected character, sets the
     target count SpellTargetCount to 1 and the first target FirstSpellTarget to the selected character, and Done to 1, then
     switches on the spell's target mode (SpellTable row byte +7): mode 1 keeps only the caster; mode 2
     asks 'Cast Spell on whom' (SelectPartyMember picks into PickedSpellCharacter) and keeps the pick, or clears Done and
     the list when none was picked; mode 4 adds every character of the party list PartyListHead, walking Next
     (+$104), to the list; any other mode clears Done. The second byte parameter is unused (QUIRK
     ovl22:0A91: the original frame reserves it). Called as the DS:6B84 combat callback (ovl08 EndCombat
     stores @ChooseSpellTargets). */
void ChooseSpellTargets(u8 Spell, u8 Unused, u8 (*Done))
{
  POOL_TRACE("ChooseSpellTargets");
  PCharacter Spare = 0;
  if (PickedSpellCharacter == 0) {
    PickedSpellCharacter = SelectedCharacter;
  }
  FirstSpellTarget = SelectedCharacter;
  SpellTargetCount = 1;
  (*Done) = 1;
  switch (SpellTable[Spell].Pad2[5]) {
  case 1:
  {
    break;
  }
  case 2:
  {
    RedrawView();
    SelectPartyMember(S("\022Cast Spell on whom"), 1, &PickedSpellCharacter);
    if (PickedSpellCharacter == 0) {
      FirstSpellTarget = 0;
      SpellTargetCount = 0;
      (*Done) = 0;
    } else {
      FirstSpellTarget = PickedSpellCharacter;
    }
    break;
  }
  case 4:
  {
    SpellTargets[SpellTargetCount] = PartyListHead;
    while ((*FPD(TCharacter (*), SpellTargets[SpellTargetCount])).Next != 0) {
      SpellTargets[(s16)(SpellTargetCount + 1)] = (*FPD(TCharacter (*), SpellTargets[SpellTargetCount])).Next;
      SpellTargetCount++;
    }
    break;
  }
  default:
  {
    (*Done) = 0;
  }
  }
}

/* ovl22:0C20 (e5). Casts a spell. Spell is the spell number, Quick (nonzero in quick combat)
     means the computer plays the cast so the player is not asked to give it up, and Announce
     (nonzero normally) is whether 'NAME casts SPELL' is shown; it is cleared when the spell is
     refused. Done is the target picker's out flag.
     Outside combat a spell with no target mode (SpellTable[Spell].Pad2[7] = 0) is combat-only: in
     the camp the player is asked to lose it, in the wilds to use the item that holds it. Then the
     target picker stored in DS:6B84 (SpellTargetPicker) fills Done; when it picked nothing the
     player may try again ('Abort Spell? ' in combat, or directly in quick combat) or the cast is
     given up. On a cast the caster is animated (DrawCombatIcon, faced towards the aim point SpellAimX/
     SpellAimY through InDirArc, a sound and a WalkCombatLine line) and the spell's handler
     SpellHandlers[Spell] runs with CastingSpell set. ClearCharacterMessage clears the prompt afterwards. Called
     by the combat and camp cast paths (ovl08:031A, ovl09:000F, ovl05:0ECD, ovl13:2432, ovl15:04A1,
     ovl19:1BD7). Globals: SelectedCharacter, ViewMode, ItemAffectUse, SpellAimX/SpellAimY, CastingSpell,
     SpellAppliedToArea and the
     SpellHandlers table. */
void CastChosenSpell(u8 Spell, u8 Quick, u8 Announce, u8 (*Done))
{
  POOL_TRACE("CastChosenSpell");
  u8 OK = 0;
  u8 Unused = 0;
  s8 CasterX = 0;
  s8 CasterY = 0;
  u8 Dir = 0;
  PCharacter Caster = 0;
  Caster = SelectedCharacter;
  OK = 1;
  if (((ViewMode != ViewModeCombat)) && ((SpellTable[Spell].Pad2[5] == 0))) {
    if (!ItemAffectUse) {
      DrawTextAt(1, 0x13, 0xA, SpellNames[Spell]);
      DrawTextAt(1, 0x14, 0xA, S("\031is a combat-only spell..."));
      if (AskYesNo(S("\011Lose it\077 "), 0xD, 0xF, 0xA) == 'Y') {
        ForgetSpell(Spell);
      }
    } else {
      DrawTextAt(1, 0x13, 0xA, S("\011That Item"));
      DrawTextAt(1, 0x14, 0xA, S("\030is a combat-only item..."));
      if (AskYesNo(S("\010Use it\077 "), 0xD, 0xF, 0xA) == 'Y') {
        (*Done) = 1;
      }
    }
    Announce = 0;
    OK = 0;
  }
  if (((Announce != 0)) && (!ItemAffectUse)) {
    ShowSpellMessage(Caster, S("\005casts"), Spell);
  }
  while (OK) {
    ((void (*)(u8, u8, u8 (*)))rtl_proc(SpellTargetPicker))(Spell, Quick, &(*Done));
    if ((*Done) != 0) {
      OK = 0;
      if (ViewMode == ViewModeCombat) {
        DrawCombatIcon(CastChosenSpell_AnimationKind);
        CasterX = CombatantX(Caster);
        CasterY = CombatantY(Caster);
        Dir = 0;
        while (!InDirArc(CasterX, CasterY, SpellAimX, SpellAimY, Dir)) {
          Dir++;
        }
        SetCombatantIcon(Caster, Dir, 1, 0);
        SetSoundDriverIdle(SoundIdleOff);
        switch (Spell) {
        case CastChosenSpell_Fireball:
        {
          PlaySound(SoundFireball);
          break;
        }
        case CastChosenSpell_LightningBolt:
        {
          PlaySound(SoundLightningBolt);
          break;
        }
        default:
        {
          PlaySound(SoundSpellDefault);
        }
        }
        WalkCombatLine(CasterX, CasterY, SpellAimX, SpellAimY, CastChosenSpell_AimStep, CastChosenSpell_AimWidth);
        SetSoundDriverIdle(SoundIdleDefault);
        if (IsCombatantInView(Caster, 0)) {
          SetCombatantIcon(Caster, (*FPD(TCombatant (*), (*FPD(TCharacter (*), Caster)).Combat)).IconSet, 1, 1);
          SetCombatantIcon(Caster, (*FPD(TCombatant (*), (*FPD(TCharacter (*), Caster)).Combat)).IconSet, 0, 0);
        }
      }
      ClearAttackerAffect(Caster);
      if (!ItemAffectUse) {
        ForgetSpell(Spell);
      }
      CastingSpell = Spell;
      SpellHandlers[CastingSpell];
      CastingSpell = 0;
      SpellAppliedToArea = 0;
    } else {
      if (ViewMode != ViewModeCombat) {
        OK = 0;
      } else if (((Quick != 0)) || ((AskYesNo(S("\015Abort Spell\077 "), 0xE, 0xA, 0xF) == 'Y'))) {
        ShowFlashMessage(S("\015Spell Aborted"));
        if (!ItemAffectUse) {
          ForgetSpell(Spell);
        }
        OK = 0;
      }
    }
  }
  ClearCharacterMessage();
  if (ViewMode == ViewModeCombat) {
    ClearWindow(0, 0x17, 0x27, 0x17);
  }
}

/* ovl22:0F4F. Applies the current spell CastingSpell to the chosen targets (SpellTargets[1..SpellTargetCount]) but keeps
     only those on Side: a target whose TCharacter.Side differs is dropped (set nil) and, for spell 1
     (Bless) in combat, a target the spell's area already reaches (CollectEnemiesInRange nonzero) is dropped
     too. Sets SpellAppliedToArea and calls ApplySpellToTargets with Message and no damage or affect of its own.
     Called by the cast handlers of spells 1 and 2 (Bless and Curse). */
void ApplySpellToSide(u8 Side, const u8 *Message_in)
{
  POOL_TRACE("ApplySpellToSide");
  const u8 *Message = Message_in;
  u8 I = 0;
  SpellAppliedToArea = 1;
  {
    u8 limit = SpellTargetCount;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          if ((((*FPD(TCharacter (*), SpellTargets[I])).Side != Side)) || (((((CastingSpell == 1)) && ((ViewMode == 5))) && ((CollectEnemiesInRange(SpellTargets[I], 1) > 0))))) {
            SpellTargets[I] = 0;
          }
        if (I == limit) break;
        I++;
      }
    }
  }
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, Message);
}

/* ovl22:100F (e11). Cast handler of spell 1, Bless: applies the current spell CastingSpell to the party
     side of the selected character (SelectedCharacter^.Side) with the message 'is Blessed'. One of the
     per-spell handlers in SpellHandlers (SpellHandlers[1], filled by InitSpellHandlers). */
void CastBless(void)
{
  POOL_TRACE("CastBless");
  ApplySpellToSide((*FPD(TCharacter (*), SelectedCharacter)).Side, S("\012is Blessed"));
}

/* ovl22:1040 (e12). Cast handler of spell 2, Curse: applies the current spell CastingSpell to the side
     opposite the selected character (OpposingSide returns 1 for side 0, else 0) with the message
     'is Cursed'. One of the per-spell handlers in SpellHandlers (SpellHandlers[2]). */
void CastCurse(void)
{
  POOL_TRACE("CastCurse");
  ApplySpellToSide(OpposingSide(SelectedCharacter), S("\011is Cursed"));
}

/* ovl22:106B (e13). Cast handler of spell 3, Cure Light Wounds: when a target was chosen (SpellTargetCount
     nonzero) it rolls 1d8 (RollDice) and heals the first target FirstSpellTarget through HealCharacter (flag 0),
     then reports through ShowHealResult whether the target is fully or partially healed. One of the
     per-spell handlers in SpellHandlers (SpellHandlers[3], filled by InitSpellHandlers). */
void CastCureLightWounds(void)
{
  POOL_TRACE("CastCureLightWounds");
  if (SpellTargetCount == 0) {
    return;
  }
  if (HealCharacter(FirstSpellTarget, RollDice(1, 8), 0)) {
    ShowHealResult(FirstSpellTarget);
  }
}

/* ovl22:10A7 (e14). Cast handler of spell 4, Cause Light Wounds: applies the current spell CastingSpell
     to the chosen targets with 1d8 damage of kind 8 and no message (ApplySpellToTargets; the dice go
     through RollDiceCounted, which also records their count in LastDiceCount). One of the per-spell handlers
     in SpellHandlers (SpellHandlers[4], filled by InitSpellHandlers). */
void CastCauseLightWounds(void)
{
  POOL_TRACE("CastCauseLightWounds");
  ApplySpellToTargets(CastingSpell, 0, 0, RollDiceCounted(1, 8), 8, S("\000"));
}

/* ovl22:10E9 (e15). Cast handler of the detection spells, spells 5 and 11 (Detect Magic), 18 (Read
     Magic), 22 (Find Traps) and 29 (Detect Invisibility): applies the current spell CastingSpell to the
     chosen targets with the message 'is affected' and no damage of its own (ApplySpellToTargets; the
     spell's own AffectId does the work). One of the per-spell handlers in SpellHandlers
     (SpellHandlers[5], [11], [18], [22] and [29]; the table is filled by InitSpellHandlers). */
void CastDetectionSpell(void)
{
  POOL_TRACE("CastDetectionSpell");
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\013is affected"));
}

/* ovl22:1123 (e16). Cast handler of the protection spells, spells 6 and 16 (Protection From Evil) and
     7 and 17 (Protection From Good): applies the current spell CastingSpell to the chosen targets with the
     message 'is protected' and no damage of its own (ApplySpellToTargets; the spell's own AffectId does
     the work). One of the per-spell handlers in SpellHandlers (SpellHandlers[6], [7], [16] and [17];
     filled by InitSpellHandlers). */
void CastProtection(void)
{
  POOL_TRACE("CastProtection");
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\014is protected"));
}

/* ovl22:1162 (e17). Cast handler of spell 8, Resist Cold: applies the current spell CastingSpell to the
     chosen targets with the message 'is cold-resistant' and no damage of its own (ApplySpellToTargets;
     the spell's own AffectId does the work). One of the per-spell handlers in SpellHandlers
     (SpellHandlers[8], filled by InitSpellHandlers). */
void CastResistCold(void)
{
  POOL_TRACE("CastResistCold");
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\021is cold-resistant"));
}

/* ovl22:1190 (e18). Cast handler of spell 9, Burning Hands: deals SpellCasterLevel(CastingSpell) (the caster
     level) damage of kind DamageKindFire to the chosen targets with no message (ApplySpellToTargets;
     DealDamage classifies kind 9 as fire, ovl24:1389). One of the per-spell handlers in SpellHandlers
     (SpellHandlers[9], filled by InitSpellHandlers). */
void CastBurningHands(void)
{
  POOL_TRACE("CastBurningHands");
  ApplySpellToTargets(CastingSpell, 0, 0, SpellCasterLevel(CastingSpell), CastBurningHands_DamageKindFire, S("\000"));
}

/* ovl22:11DD (e19). Cast handler of spell 10, Charm Person: it first refuses a target that is not a
     person, i.e. one whose CreatureType is above 1 or whose combat footprint kind (CombatSize, bits 0..6)
     is above 1, showing 'is unaffected' (ShowCharacterMessage). Otherwise it applies the current spell CastingSpell
     to the targets with the charm affect's data (the caster level SpellCasterLevel(CastingSpell) plus the
     caster's Side in bit 7, so the charmed creature joins that side) and runs the affect through
     CallAffectHandler ($0B, the charm affect id). One of the per-spell handlers in SpellHandlers
     (SpellHandlers[10], filled by InitSpellHandlers). Reads FirstSpellTarget (the first chosen target), SelectedCharacter;
     changes the affect list of the target through CallAffectHandler. */
void CastCharmPerson(void)
{
  POOL_TRACE("CastCharmPerson");
  farptr Affect = 0;
  PCharacter Target = 0;
  Target = FirstSpellTarget;
  if ((((*FPD(TCharacter (*), Target)).CreatureType > CastCharmPerson_CharmableType)) || (((*FPD(TCharacter (*), Target)).CombatSize > CastCharmPerson_CharmableSize))) {
    ShowCharacterMessage(Target, S("\015is unaffected"), CastCharmPerson_MessageColor, TimedMessage);
  } else {
    ApplySpellToTargets(CastingSpell, (s16)(SpellCasterLevel(CastingSpell) + ((*FPD(TCharacter (*), SelectedCharacter)).Side * CastCharmPerson_SideScale)), RunsHandlerOnRemove, 0, 0, S("\012is charmed"));
    if (HasAffect(Target, CastCharmPerson_CharmAffect, &Affect)) {
      CallAffectHandler(CastCharmPerson_CharmAffect, FirstSpellTarget, Affect, ModeApply);
    }
  }
}

/* ovl22:12A5 (e20). Cast handler of spell 12, Enlarge: gives the first chosen target FirstSpellTarget the
     strength 18 (ExceptionalStrength) with the percentile for the caster level (SpellCasterLevel(CastingSpell):
     0 at level 1 up to 100 at level 6), through RaiseStrength, and shows 'is stronger' when the
     strength actually rose; it then adds the strength affect (id $0C, ovl24's AffectEnlarge) with
     the spell's duration, RaiseStrength's earlier-strength code and flag 1 (on removal it restores the
     old strength, ovl24:AddAffect). The level and percentile go through the shared working globals
     SpellWorkByteA/SpellWorkByteB. One of the per-spell handlers in SpellHandlers (SpellHandlers[12], filled by
     InitSpellHandlers). */
void CastEnlarge(void)
{
  POOL_TRACE("CastEnlarge");
  u8 Code = 0;
  SpellWorkByteA = ExceptionalStrength;
  switch (SpellCasterLevel(CastingSpell)) {
  case 1:
  {
    SpellWorkByteB = CastEnlarge_PercentLevel1;
    break;
  }
  case 2:
  {
    SpellWorkByteB = CastEnlarge_PercentLevel2;
    break;
  }
  case 3:
  {
    SpellWorkByteB = CastEnlarge_PercentLevel3;
    break;
  }
  case 4:
  {
    SpellWorkByteB = CastEnlarge_PercentLevel4;
    break;
  }
  case 5:
  {
    SpellWorkByteB = CastEnlarge_PercentLevel5;
    break;
  }
  case 6:
  {
    SpellWorkByteB = CastEnlarge_PercentLevel6;
    break;
  }
  }
  if (RaiseStrength(FirstSpellTarget, SpellWorkByteA, SpellWorkByteB, &Code)) {
    ShowCharacterMessage(FirstSpellTarget, S("\013is stronger"), CastEnlarge_MessageColor, TimedMessage);
  }
  AddAffect(FirstSpellTarget, CastEnlarge_StrengthAffect, SpellAffectDuration(CastingSpell), Code, 1);
}

/* ovl22:136E (e21). Cast handler of spell 13, Reduce (SpellHandlers[13]; InitSpellHandlers fills the table,
     whitepaper 5.22.2): when targets were chosen, a target that fails its saving throw (SavingThrow kind 4,
     a spell) loses the strength affect $0C that Enlarge adds (CureAffect) and is told 'has been reduced'.
     A target that saves, or that carries no strength affect, is left alone. Reads SpellTargetCount and FirstSpellTarget. */
void CastReduce(void)
{
  POOL_TRACE("CastReduce");
  if (SpellTargetCount > 0) {
    if (!SavingThrow(FirstSpellTarget, CastReduce_SaveKind, 0)) {
      if (CureAffect(FirstSpellTarget, CastReduce_StrengthAffect)) {
        ShowCharacterMessage(FirstSpellTarget, S("\020has been reduced"), CastReduce_MessageColor, TimedMessage);
      }
    }
  }
}

/* ovl22:13D8 (e22). Cast handler of spell 14, Friends (SpellHandlers[14]; InitSpellHandlers fills the table,
     whitepaper 5.22.2): raises the chosen target FirstSpellTarget's Charisma by 2d4, capped at 25 ($19), and calls
     ApplySpellToTargets with the pre-roll Charisma as the affect's Data and the restore flag set, so the
     affect's handler puts the old Charisma back when the affect ends; the message is 'is friendly'.
     Reads FirstSpellTarget and CastingSpell. */
void CastFriends(void)
{
  POOL_TRACE("CastFriends");
  u8 OldCharisma = 0;
  OldCharisma = (*FPD(TCharacter (*), FirstSpellTarget)).Charisma;
  (*FPD(TCharacter (*), FirstSpellTarget)).Charisma += RollDice(CastFriends_DiceCount, CastFriends_DiceSides);
  if ((*FPD(TCharacter (*), FirstSpellTarget)).Charisma > CastFriends_CharismaCap) {
    (*FPD(TCharacter (*), FirstSpellTarget)).Charisma = CastFriends_CharismaCap;
  }
  ApplySpellToTargets(CastingSpell, OldCharisma, CastFriends_RestoreOnRemoval, 0, 0, S("\013is friendly"));
}

/* ovl22:1439 (e23). Cast handler of spell 15, Magic Missile (SpellHandlers[15]; InitSpellHandlers fills the
     table, whitepaper 5.22.2): the caster level from SpellCasterLevel gives one missile per two levels, so
     it deals RollDiceCounted(Level div 2, 4) (a d4 per missile, its count kept in LastDiceCount) plus Level div 2
     (one point per missile) to the chosen targets, with no message. Reads CastingSpell. */
void CastMagicMissile(void)
{
  POOL_TRACE("CastMagicMissile");
  u8 Level = 0;
  Level = SpellCasterLevel(CastingSpell);
  ApplySpellToTargets(CastingSpell, 0, 0, (s16)(RollDiceCounted((Level / CastMagicMissile_LevelsPerMissile), CastMagicMissile_MissileSides) + (Level / CastMagicMissile_LevelsPerMissile)), CastMagicMissile_DamageKind, S("\000"));
}

/* ovl22:1499 (e24). Cast handler of spell 19, Shield (SpellHandlers[19]; InitSpellHandlers fills the table,
     whitepaper 5.22.2): applies the current spell CastingSpell (its own affect does the work) to the chosen
     targets with the message 'is shielded', no damage or flag of its own. Reads CastingSpell. */
void CastShield(void)
{
  POOL_TRACE("CastShield");
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\013is shielded"));
}

/* ovl22:14C7 (e25). Cast handler of spell 20, Shocking Grasp (SpellHandlers[20]; InitSpellHandlers fills the
     table, whitepaper 5.22.2): deals the caster level from SpellCasterLevel plus 1d8 (RollDiceCounted, count
     kept in LastDiceCount) of electrical damage to the chosen targets, with no message. Reads CastingSpell. */
void CastShockingGrasp(void)
{
  POOL_TRACE("CastShockingGrasp");
  /* QUIRK ovl22:14D7: TP 6.0 evaluates the right operand of `+` first when both are calls, so the
     original's SpellCasterLevel-before-RollDiceCounted order needs the sum written with the level on the
     right; the add is commutative and the bytes match only this way. */
  ApplySpellToTargets(CastingSpell, 0, 0, (s16)(RollDiceCounted(1, CastShockingGrasp_DiceSides) + SpellCasterLevel(CastingSpell)), CastShockingGrasp_DamageKindElectric, S("\000"));
}

/* ovl22:151B (e26). Cast handler of spell 21, Sleep (SpellHandlers[21]; InitSpellHandlers fills the table,
     whitepaper 5.22.2): sets SpellAppliedToArea and rolls the 4d4 pool SpellWorkByteA. For every chosen target SpellTargets[I] it
     charges a cost in SpellWorkByteB by the target's HighestLevel (+$73, a monster's hit dice) and level 5's Race
     (+$2E). A target is slept (the cost comes off the pool) only when it is not Animated (Status <> 1,
     an undead), does not already carry the sleep affect $35 (HasAffect) and the pool still covers its
     cost; otherwise it is dropped (SpellTargets[I] := nil). ApplySpellToTargets then applies the spell's own
     affect to the survivors with 'falls asleep'. Reads SpellTargetCount, CastingSpell; changes SpellAppliedToArea,
     SpellWorkByteA, SpellWorkByteB
     and the target list. */
void CastSleep(void)
{
  POOL_TRACE("CastSleep");
  u8 I = 0;
  farptr Affect = 0;
  SpellAppliedToArea = 1;
  SpellWorkByteA = RollDice(CastSleep_PoolDiceCount, CastSleep_PoolDiceSides);
  {
    u8 limit = SpellTargetCount;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          switch ((*FPD(TCharacter (*), SpellTargets[I])).HighestLevel) {
          case 0:
          case 1:
          {
            SpellWorkByteB = CastSleep_CostLevel0;
            break;
          }
          case 2:
          {
            SpellWorkByteB = CastSleep_CostLevel2;
            break;
          }
          case 3:
          {
            SpellWorkByteB = CastSleep_CostLevel3;
            break;
          }
          case 4:
          {
            SpellWorkByteB = CastSleep_CostLevel4;
            break;
          }
          case 5:
          {
            if ((*FPD(TCharacter (*), SpellTargets[I])).Race == 0) {
              SpellWorkByteB = CastSleep_CostLevel5Small;
            } else {
              SpellWorkByteB = CastSleep_CostLevel5Large;
            }
            break;
          }
          default:
          {
            SpellWorkByteB = CastSleep_CostLevel5Large;
          }
          }
          /* QUIRK ovl22:15FE: the guard is written positive on purpose; the equivalent negative
             `(Status = Animated) or HasAffect(...) or (pool < cost)` then-drop-else-Dec form compiles with
             the two branches laid out the other way round (probe PRB26.PAS) and does not match. */
          if (((((*FPD(TCharacter (*), SpellTargets[I])).Status != StatusAnimated)) && !HasAffect(SpellTargets[I], CastSleep_SleepAffect, &Affect)) && ((SpellWorkByteA >= SpellWorkByteB))) {
            SpellWorkByteA -= SpellWorkByteB;
          } else {
            SpellTargets[I] = 0;
          }
        if (I == limit) break;
        I++;
      }
    }
  }
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\014falls asleep"));
}

/* ovl22:1658. Cast handler of spell 23, Hold Person (entry 27: InitSpellHandlers maps DS:6B84+23*4 to overlay
     stub 0096:00A7; SpellNames[23] is 'Hold Person' at DS:2C98): for every chosen target SpellTargets[I]
     it rolls a saving throw whose bonus shrinks as more targets were picked (one target -3, or -2 when
     the spell is Hold Person itself, two targets -1, three or four none), drawing a beam from the caster
     to every target but the first (SetSoundDriverIdle, PlaySound(SoundSpellDefault), the cast animation
     DrawCombatIcon($12) and the WalkCombatLine line), and applies the spell's own affect with the message
     'is held' through ApplyAffect. A target that is not a person (CreatureType above 1 or CombatSize
     above 1, as CastCharmPerson tests) is treated as having saved, and a nil target is skipped. Reads
     SpellTargetCount, SpellTargets, CastingSpell and SelectedCharacter. */
void CastHoldPerson(void)
{
  POOL_TRACE("CastHoldPerson");
  PCharacter Target = 0;
  u8 Saved = 0;
  u8 I = 0;
  s8 SaveBonus = 0;
  switch (SpellTargetCount) {
  case 1:
  {
    if (CastingSpell == CastHoldPerson_HoldPerson) {
      SaveBonus = CastHoldPerson_HoldPersonBonus;
    } else {
      SaveBonus = CastHoldPerson_OneTargetBonus;
    }
    break;
  }
  case 2:
  {
    SaveBonus = CastHoldPerson_TwoTargetsBonus;
    break;
  }
  case 3:
  case 4:
  {
    SaveBonus = CastHoldPerson_ThreeOrFourBonus;
    break;
  }
  }
  {
    u8 first = SpellTargetCount;
    if (first >= 1) {
      I = first;
      for (;;) {
          if (SpellTargets[I] != 0) {
            Target = SpellTargets[I];
            if (I < SpellTargetCount) {
              SetSoundDriverIdle(SoundIdleOff);
              PlaySound(SoundSpellDefault);
              DrawCombatIcon(CastHoldPerson_AnimationKind);
              WalkCombatLine(CombatantX(SelectedCharacter), CombatantY(SelectedCharacter), CombatantX(Target), CombatantY(Target), CastHoldPerson_AimStep, CastHoldPerson_AimWidth);
              SetSoundDriverIdle(SoundIdleDefault);
            }
            Saved = SavingThrow(Target, SpellTable[CastingSpell].Pad2[7], SaveBonus);
            if ((((*FPD(TCharacter (*), Target)).CreatureType > CastHoldPerson_FriendlyType)) || (((*FPD(TCharacter (*), Target)).CombatSize > CastHoldPerson_FriendlySize))) {
              Saved = 1;
            }
            ApplyAffect(Target, SpellTable[CastingSpell].AffectId, SpellAffectDuration(CastingSpell), SpellCasterLevel(CastingSpell), 0, SpellTable[CastingSpell].Pad2[6], Saved, S("\007is held"));
          }
        if (I == 1) break;
        I--;
      }
    }
  }
}

/* ovl22:17E9. Cast handler of spell 24, Resist Fire (entry 28: InitSpellHandlers maps DS:6B84+24*4 to overlay
     stub 0096:00AC; SpellNames[24] is 'Resist Fire' at DS:2CC1): applies the current spell CastingSpell to the
     chosen targets with the message 'is fire resistant' and no damage or flag of its own
     (ApplySpellToTargets; the spell's own affect does the work). One of the per-spell handlers in
     SpellHandlers (whitepaper 5.22.2). */
void CastResistFire(void)
{
  POOL_TRACE("CastResistFire");
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\021is fire resistant"));
}

/* ovl22:1822. Cast handler of spell 25, Silence, 15' Radius (entry 29: InitSpellHandlers maps DS:6B84+25*4 to
     overlay stub 0096:00B1; SpellNames[25] is "Silence, 15' Radius" at DS:2CEA): applies the current spell
     CastingSpell to the chosen targets with the message 'is silenced' and no damage or flag of its own
     (ApplySpellToTargets; the spell's own affect does the work). One of the per-spell handlers in
     SpellHandlers (whitepaper 5.22.2). */
void CastSilence(void)
{
  POOL_TRACE("CastSilence");
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\013is silenced"));
}

/* ovl22:185B. Cast handler of spell 26, Slow Poison (entry 30: InitSpellHandlers maps DS:6B84+26*4 to overlay
     stub 0096:00B6; SpellNames[26] is 'Slow Poison' at DS:2D13). It needs the first chosen target FirstSpellTarget
     to not be Animated (Status is not 1, an undead) and to carry the Poisoned affect $37 (HasAffect);
     anything else is dropped (FirstSpellTarget := nil) and the cast does nothing. A poisoned target at 0 hit
     points is brought back to 1 (HpCurrent), the spell's own affect is applied to the targets
     ('is affected'), the revival affect's removal handler is run (CallAffectHandler($4E), which heals
     an unconscious character, ovl24 AffectRevival) and the poison-slowing affect $0F is added for $A
     units. Reads FirstSpellTarget and CastingSpell. */
void CastSlowPoison(void)
{
  POOL_TRACE("CastSlowPoison");
  farptr Affect = 0;
  PCharacter Target = 0;
  Target = FirstSpellTarget;
  if ((*FPD(TCharacter (*), Target)).Status == StatusAnimated) {
    FirstSpellTarget = 0;
    return;
  }
  if (HasAffect(Target, CastSlowPoison_PoisonedAffect, &Affect)) {
    if ((*FPD(TCharacter (*), Target)).HpCurrent == 0) {
      (*FPD(TCharacter (*), Target)).HpCurrent = CastSlowPoison_ReviveHitPoints;
    }
    ApplySpellToTargets(CastingSpell, CastSlowPoison_FullCasterLevel, RunsHandlerOnRemove, 0, 0, S("\013is affected"));
    CallAffectHandler(CastSlowPoison_RevivalAffect, Target, 0, ModeRemove);
    AddAffect(Target, CastSlowPoison_SlowPoisonAffect, CastSlowPoison_SlowPoisonDuration, CastSlowPoison_SlowPoisonData, RunsHandlerOnRemove);
  }
}

/* ovl22:190F. Cast handler of spell 27, Snake Charm (entry 31: InitSpellHandlers maps DS:6B84+27*4 to overlay
     stub 0096:00BB; SpellNames[27] is 'Snake Charm' at DS:2D3C). The caster's own current hit points
     (SelectedCharacter^.HpCurrent) become the pool SpellWorkByteA; it then walks the party list PartyListHead and, for
     every giant snake (CreatureType $E) whose hit points fit the remaining pool, subtracts them, counts
     it in SpellTargetCount and adds it to the chosen targets SpellTargets. The spell's own affect is then applied to the
     charmed snakes with the message 'is charmed'. Reads SelectedCharacter, PartyListHead and CastingSpell; changes
     SpellWorkByteA, SpellTargetCount and the target list. */
void CastSnakeCharm(void)
{
  POOL_TRACE("CastSnakeCharm");
  PCharacter Current = 0;
  SpellWorkByteA = (*FPD(TCharacter (*), SelectedCharacter)).HpCurrent;
  SpellTargetCount = 0;
  Current = PartyListHead;
  while (Current != 0) {
    if ((((*FPD(TCharacter (*), Current)).CreatureType == CreatureSnake)) && ((SpellWorkByteA >= (*FPD(TCharacter (*), Current)).HpCurrent))) {
      SpellWorkByteA = SpellWorkByteA - (*FPD(TCharacter (*), Current)).HpCurrent;
      SpellTargetCount++;
      SpellTargets[SpellTargetCount] = Current;
    }
    Current = (*FPD(TCharacter (*), Current)).Next;
  }
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\012is charmed"));
}

/* ovl22:19C3 (e32). Cast handler of spell 28, Spiritual Hammer (SpellHandlers[28]: InitSpellHandlers maps
     DS:6B84+28*4 to overlay stub 0096:00C0; SpellNames[28] is 'Spiritual Hammer' at DS:2D65, the
     spell's own affect is $17). It applies the current spell CastingSpell to the chosen targets with no
     message of its own and the affect set to run its handler on removal (ApplySpellToTargets, Flag 1),
     then runs the handler of affect $17 on the first chosen target FirstSpellTarget (CallAffectHandler, mode 0),
     which is the spell's hammer. Reads CastingSpell and FirstSpellTarget. */
void CastSpiritualHammer(void)
{
  POOL_TRACE("CastSpiritualHammer");
  ApplySpellToTargets(CastingSpell, 0, RunsHandlerOnRemove, 0, 0, S("\000"));
  CallAffectHandler(CastSpiritualHammer_SpiritualHammerAffect, FirstSpellTarget, 0, ModeApply);
}

/* ovl22:1A16 (e33). Cast handler of spell 30, Invisibility (SpellHandlers[30]: InitSpellHandlers maps
     DS:6B84+30*4 to overlay stub 0096:00C5; SpellNames[30] is 'Invisibility' at DS:2DB7, its
     SpellTable affect byte is $19). It only applies the current spell CastingSpell to the chosen targets with
     the message 'is invisible'; the spell's own affect $19 does the hiding, so the handler has nothing
     else to do. Reads CastingSpell. */
void CastInvisibility(void)
{
  POOL_TRACE("CastInvisibility");
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\014is invisible"));
}

/* ovl22:1A4F (e34). Cast handler of spell 31, Knock (SpellHandlers[31]: InitSpellHandlers maps
     DS:6B84+31*4 to overlay stub 0096:00CA; SpellNames[31] is 'Knock' at DS:2DE0). It only applies
     the current spell CastingSpell to the chosen targets with the message 'Knock-Knock'; Knock's SpellTable
     affect byte is 0, so no affect is applied here. The door effect lives elsewhere: ovl14's wilderness
     door code looks for Knock among the memorized spells. Reads CastingSpell. */
void CastKnock(void)
{
  POOL_TRACE("CastKnock");
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\013Knock-Knock"));
}

/* ovl22:1A8A (e35). Cast handler of spell 32, Mirror Image (SpellHandlers[32]: InitSpellHandlers maps
     DS:6B84+32*4 to overlay stub 0096:00CF; SpellNames[32] is 'Mirror Image' at DS:2E09). It applies
     the current spell CastingSpell to the chosen targets with the message 'is duplicated' and the caster
     level set to 1d4 (RollDice(1, 4)); that roll is the number of images and becomes the affect's
     Data. Reads CastingSpell. */
void CastMirrorImage(void)
{
  POOL_TRACE("CastMirrorImage");
  ApplySpellToTargets(CastingSpell, RollDice(CastMirrorImage_ImagesCount, CastMirrorImage_ImagesSides), 0, 0, 0, S("\015is duplicated"));
}

/* ovl22:1ACC (e36). Cast handler of spell 33, Ray of Enfeeblement (SpellHandlers[33]: InitSpellHandlers maps
     DS:6B84+33*4 to overlay stub 0096:00D4; SpellNames[33] is 'Ray of Enfeeblement' at DS:2E32). It
     only applies the current spell CastingSpell to the chosen targets with the message 'is weakened'; the
     spell's own affect lowers the target's strength, so the handler has nothing else to do. Reads
     CastingSpell. */
void CastRayOfEnfeeblement(void)
{
  POOL_TRACE("CastRayOfEnfeeblement");
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\013is weakened"));
}

/* ovl22:1B11 (e37). Cast handler of spell 34, Stinking Cloud (SpellHandlers[34]: InitSpellHandlers maps
     DS:6B84+34*4 to overlay stub 0096:00D9; SpellNames[34] is 'Stinking Cloud' at DS:2E5B). It leaves
     a marker in the list CloudList (a list of $13-byte TCombatNode records) for the aim point SpellAimX/
     SpellAimY: the caster, the aim cell, and for each of the four aim directions (SpellNamesPrefix.AimDirs,
     DS:290E) the tile it found around the aim cell, whether the cell may hold the cloud, and the cloud's
     own affect $28 with the caster level. A cell whose tile is $1E (the cloud tile) borrows the tile of
     an earlier cloud marker that already reaches it; a cell whose tile is $1F (a body on the map)
     borrows the body's tile there (BodyTable). The cloud cell itself is painted into the combat map, the
     cast is announced ('Creates a noxious cloud'), the cursor is moved to the aim point and the cloud
     affect runs on every combatant in the four cells (ApplyCloudTile). Reads CastingSpell, SpellAimX/SpellAimY,
     CloudList, SelectedCharacter, BodyCount, BodyTable, CombatTiles, CombatMap and CombatantRecord; changes
     SpellAppliedToArea, CloudList, the combat map and the affects of the targets. */
void CastStinkingCloud(void)
{
  POOL_TRACE("CastStinkingCloud");
  PCombatNode Cloud = 0;
  PCombatNode Node = 0;
  u8 Occupant[4] = {0};
  u8 J = 0;
  u8 Count = 0;
  u8 Tile = 0;
  u8 Level = 0;
  u8 I = 0;
  u8 Dir = 0;
  SpellAppliedToArea = 1;
  Level = SpellCasterLevel(CastingSpell);
  Count = 0;
  Node = CloudList;
  if (CloudList == 0) {
    CloudList = rtl_getmem(19);
    Node = CloudList;
  } else {
    while ((*FPD(TCombatNode (*), Node)).Next != 0) {
      if ((*FPD(TCombatNode (*), Node)).Owner == SelectedCharacter) {
        Count++;
      }
      Node = (*FPD(TCombatNode (*), Node)).Next;
    }
    (*FPD(TCombatNode (*), Node)).Next = rtl_getmem(19);
    Node = (*FPD(TCombatNode (*), Node)).Next;
  }
  rtl_FillChar((void *)&(*FPD(TCombatNode (*), Node)), 19, 0);
  AddAffect(SelectedCharacter, CastStinkingCloud_CloudAffect, Level, (s16)(Level + (Count * CastStinkingCloud_CloudCountScale)), 1);
  (*FPD(TCombatNode (*), Node)).Owner = SelectedCharacter;
  (*FPD(TCombatNode (*), Node)).Kind = Count;
  (*FPD(TCombatNode (*), Node)).X = SpellAimX;
  (*FPD(TCombatNode (*), Node)).Y = SpellAimY;
  {
    if (1 <= 4) {
      I = 1;
      for (;;) {
          Dir = SpellNamesPrefix.AimDirs[I - 1];
          GetMapCell((s16)(SpellAimX + DirStepX[Dir]), (s16)(SpellAimY + DirStepY[Dir]), &Occupant[I - 1], &Tile);
          if (((Tile > 0)) && ((CombatTiles[Tile].Cost < CastStinkingCloud_RefusedTileCost))) {
            (*FPD(TCombatNode (*), Node)).Arms[I - 1] = 1;
          } else {
            (*FPD(TCombatNode (*), Node)).Arms[I - 1] = 0;
          }
          if (Tile == CloudTile) {
            Cloud = CloudList;
            while (Cloud != 0) {
              if (Cloud != Node) {
                {
                  if (1 <= 4) {
                    J = 1;
                    for (;;) {
                        if ((*FPD(TCombatNode (*), Cloud)).Arms[J - 1] != 0) {
                          if (((((s16)((*FPD(TCombatNode (*), Cloud)).X + DirStepX[SpellNamesPrefix.AimDirs[J - 1]]) == (s16)(SpellAimX + DirStepX[Dir]))) && (((s16)((*FPD(TCombatNode (*), Cloud)).Y + DirStepY[SpellNamesPrefix.AimDirs[J - 1]]) == (s16)(SpellAimY + DirStepY[Dir])))) && (((*FPD(TCombatNode (*), Cloud)).Tiles[J - 1] != CloudTile))) {
                            Tile = (*FPD(TCombatNode (*), Cloud)).Tiles[J - 1];
                          }
                        }
                      if (J == 4) break;
                      J++;
                    }
                  }
                }
              }
              Cloud = (*FPD(TCombatNode (*), Cloud)).Next;
            }
          } else if (Tile == BodyTile) {
            {
              u8 limit = BodyCount;
              if (1 <= limit) {
                J = 1;
                for (;;) {
                    if (((BodyTable[J - 1].X == (s16)(SpellAimX + DirStepX[Dir]))) && ((BodyTable[J - 1].Y == (s16)(SpellAimY + DirStepY[Dir])))) {
                      Tile = BodyTable[J - 1].Tile;
                    }
                  if (J == limit) break;
                  J++;
                }
              }
            }
          }
          (*FPD(TCombatNode (*), Node)).Tiles[I - 1] = Tile;
          if ((*FPD(TCombatNode (*), Node)).Arms[I - 1] != 0) {
            (*FPD(TCombatMap (*), CombatMap)).Cells[(s16)(SpellAimY + DirStepY[Dir])][(s16)(SpellAimX + DirStepX[Dir])] = CloudTile;
          }
        if (I == 4) break;
        I++;
      }
    }
  }
  ShowCharacterMessage(SelectedCharacter, S("\027Creates a noxious cloud"), CastStinkingCloud_MessageColor, 0);
  MoveCombatCursor(SpellAimX, SpellAimY, CastStinkingCloud_AimCursorMargin, CastStinkingCloud_AimCursorDir);
  DelayByGameSpeed();
  ClearCharacterMessage();
  {
    if (1 <= 4) {
      I = 1;
      for (;;) {
          if (Occupant[I - 1] > 0) {
            ApplyCloudTile(CombatantRecord[Occupant[I - 1] - 1]);
          }
        if (I == 4) break;
        I++;
      }
    }
  }
}

/* ovl22:1F41. Cast handler that raises the chosen target FirstSpellTarget's Strength (the Strength spell):
     it rolls the class bonus die (1d4 for a magic-user level, 1d6 for a cleric or thief level, 1d8
     for a fighter level; the later class wins) and adds it to the target's Strength. A result above
     18 is clamped to 18; for a fighter level the overflow becomes the exceptional-strength percentile
     (10 per point above 18 plus the target's StrengthPercent, capped at 100). RaiseStrength applies the
     new Strength (showing 'is stronger' when it rose) and the strength affect $26 is added for the
     spell's duration. Reads FirstSpellTarget and CastingSpell. */
void CastStrength(void)
{
  POOL_TRACE("CastStrength");
  PCharacter Target = 0;
  u8 Percent = 0;
  u8 Bonus = 0;
  u8 Strength = 0;
  u8 Code = 0;
  Percent = 0;
  Target = FirstSpellTarget;
  if ((*FPD(TCharacter (*), Target)).ClassLevels[5] > 0) {
    Bonus = RollDice(1, CastStrength_MagicUserSides);
  }
  if ((((*FPD(TCharacter (*), Target)).ClassLevels[0] > 0)) || (((*FPD(TCharacter (*), Target)).ClassLevels[6] > 0))) {
    Bonus = RollDice(1, CastStrength_ClericSides);
  }
  if ((*FPD(TCharacter (*), Target)).ClassLevels[2] > 0) {
    Bonus = RollDice(1, CastStrength_FighterSides);
  }
  Strength = (*FPD(TCharacter (*), Target)).Strength + Bonus;
  /* QUIRK ovl22:1FFB: the cap is repeated in both branches (Strength 18 in each); the compiler keeps
     one store per branch instead of hoisting it, which is the original's layout. */
  if (Strength > ExceptionalStrength) {
    if ((*FPD(TCharacter (*), Target)).ClassLevels[2] > 0) {
      /* QUIRK ovl22:1FD4: TP 6.0 evaluates the right operand of `+` first, so the percentile sum is
         written target-first to keep the product on the left of the add in the original. */
      Percent = (*FPD(TCharacter (*), Target)).StrengthPercent + (((s16)(Strength - ExceptionalStrength)) * CastStrength_PercentStep);
      if (Percent > CastStrength_MaxPercent) {
        Percent = CastStrength_MaxPercent;
      }
      Strength = ExceptionalStrength;
    } else {
      Strength = ExceptionalStrength;
    }
  }
  if (RaiseStrength(Target, Strength, Percent, &Code)) {
    ShowCharacterMessage(Target, S("\013is stronger"), CastStrength_MessageColor, TimedMessage);
  }
  AddAffect(Target, CastStrength_StrengthAffect, SpellAffectDuration(CastingSpell), Code, RunsHandlerOnRemove);
}

/* ovl22:206F. Cast handler of spell 36, Animate Dead: for up to the caster level corpses still in the
     party list PartyListHead (Status 6, CreatureType 0) it places the body on the combat map at its own cell
     (PlaceCombatant) and turns it into an undead creature under the caster's side: CreatureType 4, Quick
     set, the memorized spells, the AI state and the combat target cleared, B84 $B2 when it was already a
     computer-run member (above $7F) else $B3, and Side copied from SelectedCharacter. The corpse is then
     revived (ReviveCombatant at HpMax) and, on success, carries the animate affect $20 (Data: the caster's
     Side in bits 4..7 plus the caster level) with the message 'is animated'. Reads CastingSpell, PartyListHead,
     SelectedCharacter and ViewMode; changes SpellAppliedToArea, SpellTargetCount and the corpse records. */
void CastAnimateDead(void)
{
  POOL_TRACE("CastAnimateDead");
  u8 I = 0;
  u8 SaveData = 0;
  u8 Level = 0;
  PCharacter Current = 0;
  SpellAppliedToArea = 1;
  Level = SpellCasterLevel(CastingSpell);
  SpellTargetCount = 0;
  Current = PartyListHead;
  while (((Current != 0)) && ((Level > 0))) {
    if ((*FPD(TCharacter (*), Current)).Status == CastAnimateDead_DeadStatus) {
      if ((*FPD(TCharacter (*), Current)).CreatureType == CreatureHuman) {
        if (PlaceCombatant(Current, CombatantX(Current), CombatantY(Current), CastAnimateDead_RestoreCell)) {
          /* The caster's Side goes into bits 4..7 of the affect data, the caster level into the low
             nibble (QUIRK ovl22:2105: the original sign-extends Side with cwde, so it is treated as a
             ShortInt here even though TCharacter.Side is a Byte). */
          SaveData = ((*FPD(TCharacter (*), Current)).Side * CastAnimateDead_SideScale) + SpellCasterLevel(CastingSpell);
          (*FPD(TCharacter (*), Current)).Side = (*FPD(TCharacter (*), SelectedCharacter)).Side;
          (*FPD(TCharacter (*), Current)).Quick = 1;
          (*FPD(TCharacter (*), Current)).Pad74[2] = CastAnimateDead_AnimatedMark;
          (*FPD(TCharacter (*), Current)).SweepAttacks = 0;
          (*FPD(TCharacter (*), Current)).BaseMovement = 6;
          {
            if (0 <= CastAnimateDead_MaxSpellSlot) {
              I = 0;
              for (;;) {
                  (*FPD(TCharacter (*), Current)).Spells[I] = 0;
                if (I == CastAnimateDead_MaxSpellSlot) break;
                I++;
              }
            }
          }
          if ((*FPD(TCharacter (*), Current)).B84 > CastAnimateDead_AiThreshold) {
            (*FPD(TCharacter (*), Current)).B84 = CastAnimateDead_HirelingMorale;
          } else {
            (*FPD(TCharacter (*), Current)).B84 = CastAnimateDead_CreatureMorale;
          }
          (*FPD(TCharacter (*), Current)).CreatureType = CreatureUndead;
          if (ViewMode == ViewModeCombat) {
            (*FPD(TCombatant (*), (*FPD(TCharacter (*), Current)).Combat)).Target = 0;
          }
          Level--;
          if (ReviveCombatant(Current, (*FPD(TCharacter (*), Current)).HpMax)) {
            ApplyAffect(Current, CastAnimateDead_AnimateAffect, 0, SaveData, RunsHandlerOnRemove, CastAnimateDead_NoSaveNegates, CastAnimateDead_NotSaved, S("\013is animated"));
            (*FPD(TCharacter (*), Current)).Status = 1;
          }
        }
      }
    }
    Current = (*FPD(TCharacter (*), Current)).Next;
  }
}

/* ovl22:2217. Cast handler of spell 37, Cure Blindness (SpellTable[37].AffectId is 0): removes the
     blindness affect $21 that spell 38 Cause Blindness leaves (SpellTable[38].AffectId) from the first
     chosen target FirstSpellTarget (CureAffect) and, only when the target actually carried it, tells 'can see'
     through ShowHitMessage. Reads FirstSpellTarget. */
void CastCureBlindness(void)
{
  POOL_TRACE("CastCureBlindness");
  if (CureAffect(FirstSpellTarget, CastCureBlindness_BlindnessAffect)) {
    ShowHitMessage(FirstSpellTarget, CastCureBlindness_ShowAbout, S("\007can see"));
  }
}

/* ovl22:225D. Cast handler of spell 38, Cause Blindness (SpellHandlers[38]: InitSpellHandlers maps
     DS:6B84+38*4 to overlay stub 0096:00ED; SpellNames[38] is 'Cause Blindness' at DS:2EFF). It only
     applies the current spell CastingSpell to the chosen targets with the message 'is blind'; the spell's own
     affect $21 does the blinding (the affect Cure Blindness removes, ovl22:2217), so the handler has
     nothing else to do. Reads CastingSpell. */
void CastCauseBlindness(void)
{
  POOL_TRACE("CastCauseBlindness");
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\010is blind"));
}

/* ovl22:228A. Cures the six disease affects of the Temple (DiseaseAffects[1..6] at DS:0114: $1F,
     $22, $2B, $2C, $32, $39) from the chosen target FirstSpellTarget and returns whether it cured any: it cures
     the $22 spell affect on its own, and curing $2B clears its companions $2C (Cause Disease) and $1F
     (Helpless) too, while curing $32 (Dreaded Mummy Disease) clears $39. RemovingAffects is set while the
     affects go so the removal does not trigger the Temple's own cure. Called by CastCureDisease (spell 39,
     Cure Disease) and CastMonsterHeal. */
u8 CureDiseaseAffects(void)
{
  POOL_TRACE("CureDiseaseAffects");
  u8 Result = 0;
  Result = 0;
  RemovingAffects = 1;
  if (CureAffect(FirstSpellTarget, CureDiseaseAffects_DiseaseAffectCured)) {
    Result = 1;
  }
  if (CureAffect(FirstSpellTarget, CureDiseaseAffects_DiseaseAffectCause)) {
    Result = 1;
    RemoveAffect(FirstSpellTarget, CureDiseaseAffects_DiseaseAffectCauseDisease, 0);
    RemoveAffect(FirstSpellTarget, CureDiseaseAffects_DiseaseAffectHelpless, 0);
  }
  if (CureAffect(FirstSpellTarget, CureDiseaseAffects_DiseaseAffectMummy)) {
    Result = 1;
    RemoveAffect(FirstSpellTarget, CureDiseaseAffects_DiseaseAffectMummyCleared, 0);
  }
  RemovingAffects = 0;
  return Result;
}

/* ovl22:232F. Cast handler of spell 39, Cure Disease (SpellHandlers[39]: InitSpellHandlers maps
     DS:6B84+39*4 to overlay stub 0096:00F2; SpellNames[39] is 'Cure Disease' at DS:2F28). It calls
     CureDiseaseAffects to cure the chosen target FirstSpellTarget and stores the result in a local it never
     reads, so the cure happens through that call alone (SpellHandlers is a table of procedures and
     takes no result). QUIRK ovl22:232F: the Boolean local Cured is written and never read. */
void CastCureDisease(void)
{
  POOL_TRACE("CastCureDisease");
  u8 Cured = 0;
  Cured = CureDiseaseAffects();
}

/* ovl22:234C. Cast handler of spell 40, Cause Disease (SpellHandlers[40]: InitSpellHandlers maps
     DS:6B84+40*4 to overlay stub 0096:00F7; SpellNames[40] is 'Cause Disease' at DS:2F51). It applies
     the current spell CastingSpell to the chosen targets with the message 'is diseased' and no damage of its
     own, but with Flag 1 so the spell's affect runs its handler when it is removed (the affect the
     Temple's Cure Disease and CureDiseaseAffects clear). Reads CastingSpell. */
void CastCauseDisease(void)
{
  POOL_TRACE("CastCauseDisease");
  ApplySpellToTargets(CastingSpell, 0, RunsHandlerOnRemove, 0, 0, S("\013is diseased"));
}

/* ovl22:2385 (e44). Cast handler of spells 41 and 46, Dispel Magic (InitSpellHandlers maps both
     DS:6B84+41*4 and DS:6B84+46*4 to overlay stub 0096:00FC; SpellNames[41] and SpellNames[46] are
     both 'Dispel Magic' at DS:2F7A and DS:3047). It tries to dispel the affects of the chosen target
     FirstSpellTarget: for every affect of the target's list whose Data byte is below $FF it takes the effect's
     level from the low nibble of Data, turns the caster level (SpellCasterLevel(CastingSpell)) and that level
     into a chance (50 percent, +5 for each level the caster is above the effect, -2 for each level
     below), and rolls 1d100: a roll up to that chance removes the affect (RemoveAffect) and, when
     anything was removed, the target is told 'is affected' (ShowHitMessage). SpellAppliedToArea marks the cast.
     QUIRK ovl22:2385: the outer loop runs SpellTargetCount times but the body always reads the same first target
     FirstSpellTarget (it is never indexed by the loop counter), so a cast with several targets rolls on the
     first one once per target and can show 'is affected' more than once. Reads CastingSpell, SpellTargetCount, FirstSpellTarget;
     changes SpellAppliedToArea, SpellWorkByteA, SpellWorkByteB and the target's affect list. */
void CastDispelMagic(void)
{
  POOL_TRACE("CastDispelMagic");
  u8 I = 0;
  u8 Level = 0;
  PCharacter Target = 0;
  u8 Dispelled = 0;
  PAffect Affect = 0;
  PAffect Next = 0;
  SpellAppliedToArea = 1;
  Level = SpellCasterLevel(CastingSpell);
  {
    u8 limit = SpellTargetCount;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          Dispelled = 0;
          Target = FirstSpellTarget;
          Affect = (*FPD(TCharacter (*), Target)).Affects;
          while (Affect != 0) {
            Next = (*FPD(TAffect (*), Affect)).Next;
            if ((*FPD(TAffect (*), Affect)).Data < CastDispelMagic_MaxAffectData) {
              SpellWorkByteB = ((*FPD(TAffect (*), Affect)).Data & CastDispelMagic_LevelMask);
              if (Level > SpellWorkByteB) {
                SpellWorkByteA = (((s16)(Level - SpellWorkByteB)) * CastDispelMagic_LevelStep) + CastDispelMagic_BaseChance;
              } else if (Level < SpellWorkByteB) {
                SpellWorkByteA = CastDispelMagic_BaseChance - (((s16)(SpellWorkByteB - Level)) * CastDispelMagic_LevelPenalty);
              } else {
                SpellWorkByteA = CastDispelMagic_BaseChance;
              }
              if (RollDice(1, CastDispelMagic_DiceSides) <= SpellWorkByteA) {
                RemoveAffect(Target, (*FPD(TAffect (*), Affect)).Id, Affect);
                Dispelled = 1;
              }
            }
            Affect = Next;
          }
          if (Dispelled) {
            ShowHitMessage(Target, CastDispelMagic_ShowAbout, S("\013is affected"));
          }
        if (I == limit) break;
        I++;
      }
    }
  }
}

/* ovl22:24D6 (e45). Cast handler of spell 42, Prayer (InitSpellHandlers maps DS:6B84+42*4 to overlay stub
     0096:0101; SpellNames[42] is 'Prayer'). It applies the current spell CastingSpell to the chosen targets
     with no flag, damage or kind of its own and the message 'is praying'; the caster level it passes as
     the affect's Data is the caster level (SpellCasterLevel(CastingSpell)) plus the caster's Side scaled by 16, so
     the affect's handler can tell whose side the prayer favours (the same Side-in-the-data trick as
     Charm Person and Animate Dead). Reads CastingSpell and SelectedCharacter; changes the targets' affects. */
void CastPrayer(void)
{
  POOL_TRACE("CastPrayer");
  /* QUIRK ovl22:24F1: the original sign-extends Side with cwde, so it is read as a ShortInt even
     though TCharacter.Side is a Byte. */
  ApplySpellToTargets(CastingSpell, (s16)(SpellCasterLevel(CastingSpell) + ((*FPD(TCharacter (*), SelectedCharacter)).Side * CastPrayer_SideScale)), 0, 0, 0, S("\012is praying"));
}

/* ovl22:2540 (e9). Cast handler of spell 43, Remove Curse, and the routine the Temple's Remove
     Curse service calls (InitSpellHandlers maps DS:6B84+43*4 to overlay stub 0096:007E; SpellNames[43] is
     'Remove Curse' at DS:2FCC; the Temple's RemoveCurse ovl04:083A stores the character in FirstSpellTarget and
     calls this). It first tries to cure the curse affect $24 from the character FirstSpellTarget and, when it was
     there, says 'is un-cursed' (ShowHitMessage). Otherwise it walks the character's carried items
     (FirstSpellTarget^.Items, the list at +$C8) and clears the Cursed flag (+$36) of the first cursed item it
     finds, saying ''s item is un-cursed'. Reads FirstSpellTarget; changes the character's affects and its items. */
void CastRemoveCurse(void)
{
  POOL_TRACE("CastRemoveCurse");
  PItem Item = 0;
  u8 UnCursed = 0;
  if (CureAffect(FirstSpellTarget, AffectBestowCurse)) {
    ShowHitMessage(FirstSpellTarget, CastRemoveCurse_ShowAbout, S("\014is un-cursed"));
  } else {
    UnCursed = 0;
    Item = (*FPD(TCharacter (*), FirstSpellTarget)).Items;
    while (((Item != 0)) && !UnCursed) {
      if ((*FPD(TMenuLine (*), Item)).Cursed) {
        UnCursed = 1;
        (*FPD(TMenuLine (*), Item)).Cursed = 0;
      }
      Item = (*FPD(TMenuLine (*), Item)).Next;
    }
    if (UnCursed) {
      ShowHitMessage(FirstSpellTarget, CastRemoveCurse_ShowAbout, S("\024's item is un-cursed"));
    }
  }
}

/* ovl22:2604. Cast handler of spell 44, Bestow Curse (InitSpellHandlers maps DS:6B84+44*4 to overlay
     stub 0096:0106; SpellNames[44] is 'Bestow Curse' at DS:2FF5 and SpellTable[44].AffectId is the curse
     affect $24). It only applies the current spell CastingSpell to the chosen targets with the message
     'has been cursed!'; the spell's own affect does the cursing, so the handler has nothing else to do.
     Reads CastingSpell. */
void CastBestowCurse(void)
{
  POOL_TRACE("CastBestowCurse");
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\020has been cursed!"));
}

/* ovl22:263D. Cast handler of spell 45, Blink (InitSpellHandlers maps DS:6B84+45*4 to overlay stub 0096:010B;
     SpellNames[45] is 'Blink' at DS:301E and SpellTable[45].AffectId is the blink affect $25). It only
     applies the current spell CastingSpell to the chosen targets with the message 'is blinking'; the spell's
     own affect does the blinking, so the handler has nothing else to do. Reads CastingSpell. */
void CastBlink(void)
{
  POOL_TRACE("CastBlink");
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\013is blinking"));
}

/* ovl22:266B. Cast handler of spells 47 and 64, Fireball (InitSpellHandlers maps both DS:6B84+47*4 and
     DS:6B84+64*4 to overlay stub 0096:0110; SpellNames[47] is 'Fireball', and spell 64 has an empty
     name, a monster's fireball). It sets SpellAppliedToArea and takes the caster level from SpellCasterLevel (the
     spell's d6-per-level damage) except for the monster's spell 64, whose level is the roll 1d3*2+1.
     When the 3D wall view is off (GameVars^[VarForceWallView] = 0) it collects into SpellTargets[1..SpellTargetCount]
     the combatants ScanTargets finds within two steps of the aim point SpellAimX/SpellAimY; it then moves
     the combat cursor onto the aim point and applies the spell to the targets with RollDiceCounted
     (the d6 per level), fire damage and no message. Called through SpellHandlers[47] and [64]. */
void CastFireball(void)
{
  POOL_TRACE("CastFireball");
  u8 Level = 0;
  u8 I = 0;
  SpellAppliedToArea = 1;
  if (CastingSpell == CastFireball_MonsterFireball) {
    Level = (RollDice(CastFireball_LevelDiceCount, CastFireball_LevelDiceSides) * CastFireball_LevelScale) + 1;
  } else {
    Level = SpellCasterLevel(CastingSpell);
  }
  if ((*FPD(TGameVars (*), GameVars))[230] == 0) {
    ScanTargets(SpellAimX, SpellAimY, CastFireball_ScanSteps, OmniDir, CastFireball_FootprintBase, CombatMap);
    {
      u8 limit = SortEntries[0].Val_;
      if (1 <= limit) {
        I = 1;
        for (;;) {
            SpellTargets[I] = CombatantRecord[SortEntries[I].Head - 1];
          if (I == limit) break;
          I++;
        }
      }
    }
    SpellTargetCount = SortEntries[0].Val_;
  }
  MoveCombatCursor(SpellAimX, SpellAimY, CastFireball_AimCursorMargin, CastFireball_AimCursorDir);
  ApplySpellToTargets(CastingSpell, 0, 0, RollDiceCounted(Level, CastFireball_DamageDiceSides), CastFireball_DamageKindFire, S("\000"));
}

/* ovl22:2764. Applies the current spell CastingSpell to up to the caster level (SpellCasterLevel) of the
     chosen targets SpellTargets[1..SpellTargetCount] that stand on Side, after removing from them the counter-affect
     Affect: a target on Side with budget left spends one point of the level and, if it already carries
     Affect, has it cured and is dropped, so the surviving targets are the ones the spell then affects.
     It sets SpellAppliedToArea, applies the spell through ApplySpellToTargets with Message, and finally runs the
     affect hooks $12 on each surviving target. Called by CastHaste (ovl22:2892) and the Slow handler
     (ovl22:2C09). Haste passes the slow affect $2A, Slow the haste affect $27 (the two
     spells' SpellTable affect ids), so each removes the opposite spell from the side before it casts. */
void ApplySpellToSideUpToLevel(u8 Affect, u8 Side, const u8 *Message_in)
{
  POOL_TRACE("ApplySpellToSideUpToLevel");
  const u8 *Message = Message_in;
  u8 Level = 0;
  u8 I = 0;
  SpellAppliedToArea = 1;
  Level = SpellCasterLevel(CastingSpell);
  {
    u8 limit = SpellTargetCount;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          if ((((*FPD(TCharacter (*), SpellTargets[I])).Side == Side)) && ((Level > 0))) {
            Level--;
            if (CureAffect(SpellTargets[I], Affect)) {
              SpellTargets[I] = 0;
            }
          } else {
            SpellTargets[I] = 0;
          }
        if (I == limit) break;
        I++;
      }
    }
  }
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, Message);
  {
    u8 limit = SpellTargetCount;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          if (SpellTargets[I] != 0) {
            RunAffectHooks(ApplySpellToSideUpToLevel_AffectHooks, SpellTargets[I]);
          }
        if (I == limit) break;
        I++;
      }
    }
  }
}

/* ovl22:2892. Cast handler of spell 48, Haste (InitSpellHandlers maps DS:6B84+48*4 to overlay stub
     0096:0115; SpellNames[48] is 'Haste' and SpellTable[48].AffectId is the haste affect $27). It hands
     the caster's own side and the slow affect $2A (SpellTable[55].AffectId) to ApplySpellToSideUpToLevel,
     which cures Slow from up to caster-level members of the side and then applies Haste to the rest with
     'is Hasted'. One of the per-spell handlers in SpellHandlers (SpellHandlers[48]). */
void CastHaste(void)
{
  POOL_TRACE("CastHaste");
  ApplySpellToSideUpToLevel(CastHaste_SlowAffect, (*FPD(TCharacter (*), SelectedCharacter)).Side, S("\011is Hasted"));
}

/* ovl22:28BC. One cell of a line spell's beam: it reads the cell (CellX, CellY) through GetMapCell
     and reports in Blocked whether the tile refuses the beam (Tile > 0 with a CombatTiles cost of $FF,
     the impassable cost). When a combatant stands in the cell (Occupant > 0) it deals Damage to it with
     the spell's saving throw (SavingThrow with SaveKind and no bonus; the damage is halved on a save,
     DealDamage's SaveEffect 2) as electrical damage (DamageKind $0C) and plays the zap animation
     DrawCombatIcon($13). Called by the line-area helpers (CastLineBeam and its callers, the Lightning
     Bolt handler CastLightningBolt among them). */
void DamageTargetInCell(u8 CellX, u8 CellY, u8 Damage, u8 SaveKind_, u8 (*Blocked))
{
  POOL_TRACE("DamageTargetInCell");
  PCharacter Target = 0;
  u8 Occupant = 0;
  u8 Tile = 0;
  u8 Unused = 0;
  (*Blocked) = 0;
  GetMapCell(CellX, CellY, &Occupant, &Tile);
  if (((Tile > 0)) && ((CombatTiles[Tile].Cost == DamageTargetInCell_RefusedTileCost))) {
    (*Blocked) = 1;
  }
  if (Occupant > 0) {
    Target = CombatantRecord[Occupant - 1];
    DamageKind = DamageTargetInCell_DamageKindElectric;
    DealDamage(Target, Damage, HalfOnSave, SavingThrow(Target, SaveKind_, DamageTargetInCell_NoBonus));
    DrawCombatIcon(DamageTargetInCell_ZapAnimation);
    DamageKind = 0;
  }
}

/* ovl22:295B. The line-beam helper of the line spells: it draws the beam of the Lightning Bolt handler
     CastLightningBolt and of the monster beams (CastMonsterBeam, the dragon breath MonsterBreath) and damages every combatant it
     passes. It starts at the aim cell SpellAimX/SpellAimY (playing the zap animation DrawCombatIcon($13)) and
     walks a line away from the caster for Range * 2 steps (a TLineState filled by SetupLine and advanced
     by StepLine); it draws each step through WalkCombatLine and deals Damage (electrical, SavingThrow kind
     SaveKind) through DamageTargetInCell. The walk stops at the end of the line, when the line leaves the
     map (Tile 0), at a tile whose CombatTiles cost is above MaxPassableCost, or when the occupant of the
     cell changes (a fresh combatant, so the beam does not pass through bodies). When Blocked (the tile
     refused the beam) and Bounce is set, it moves the aim cell to the bounce point and walks a second
     line back to the caster, turning the beam around once (DirSign flips and Bounce clears). Sets SpellAppliedToArea.
     Parameters: Range the spell's reach (the line walks Range * 2 cells); Damage the damage dealt per
     cell; SaveKind the SavingThrow kind; Bounce nonzero lets the beam reflect off a wall once. Globals:
     SpellAimX/SpellAimY (the aim cell, moved to the bounce point), SpellAppliedToArea, SelectedCharacter and CombatTiles.
     Called by CastLightningBolt (Lightning Bolt), CastMonsterBeam and MonsterBreath (the dragon breath). */
void CastLineBeam(u8 Range, u8 Damage, u8 SaveKind_, u8 Bounce)
{
  POOL_TRACE("CastLineBeam");
  TLineState (*Line) = (TLineState (*))rtl_stack_alloc(26);
  TLineState (*Line2) = (TLineState (*))rtl_stack_alloc(26);
  s8 CasterX = 0;
  s8 CasterY = 0;
  u8 StartX = 0;
  u8 StartY = 0;
  s8 DirSign = 0;
  u8 Blocked = 0;
  u8 StepDone = 0;
  u8 Bouncing = 0;
  u8 PrevOccupant = 0;
  u8 Occupant = 0;
  u8 Tile = 0;
  u8 Length_ = 0;
  u16 stack_mark = rtl_stack_mark();
  DrawCombatIcon(CastLineBeam_ZapAnimation);
  GetMapCell(SpellAimX, SpellAimY, &PrevOccupant, &Tile);
  DirSign = 1;
  CasterX = CombatantX(SelectedCharacter);
  CasterY = CombatantY(SelectedCharacter);
  Bouncing = Bounce;
  if (((CasterX == SpellAimX)) && ((CasterY == SpellAimY))) {
    goto L_exit;
  }
  Length_ = Range * 2;
  SpellAppliedToArea = 1;
  while (Length_ > 0) {
    rtl_FillChar((void *)&(*Line), 26, 0);
    (*Line).X1 = SpellAimX;
    (*Line).Y1 = SpellAimY;
    (*Line).X2 = SpellAimX + ((((s16)(SpellAimX - CasterX)) * DirSign) * Length_);
    (*Line).Y2 = SpellAimY + ((((s16)(SpellAimY - CasterY)) * DirSign) * Length_);
    SetupLine(rtl_far(&(*Line)));
    do {
      StartX = (*Line).X;
      StartY = (*Line).Y;
      /* The beam steps the line while it still has room (`if (X1 <> X2) or (Y1 <> Y2)`), and the
         stops are the `until` disjunction: the loop ends when StepLine stops, a fresh occupant
         blocks the beam, the line leaves the map, the tile refuses it, or the reach is spent. */
      if ((((*Line).X1 != (*Line).X2)) || (((*Line).Y1 != (*Line).Y2))) {
        do {
          StepDone = StepLine(rtl_far(&(*Line)));
          GetMapCell((*Line).X, (*Line).Y, &Occupant, &Tile);
        } while (!(((((!StepDone) || ((((Occupant > 0)) && ((Occupant != PrevOccupant))))) || ((Tile == 0))) || ((CombatTiles[Tile].Cost > CastLineBeam_MaxPassableCost))) || (((*Line).First >= Length_))));
      }
      PrevOccupant = Occupant;
      if (Tile == 0) {
        Length_ = 0;
      }
      WalkCombatLine(StartX, StartY, (*Line).X, (*Line).Y, CastLineBeam_LineStep, CastLineBeam_LineWidth);
      DamageTargetInCell((*Line).X, (*Line).Y, Damage, SaveKind_, &Blocked);
      if (Blocked) {
        SpellAimX = (*Line).X;
        SpellAimY = (*Line).Y;
        rtl_FillChar((void *)&(*Line2), 26, 0);
        (*Line2).X1 = SpellAimX;
        (*Line2).Y1 = SpellAimY;
        (*Line2).X2 = CasterX;
        (*Line2).Y2 = CasterY;
        SetupLine(rtl_far(&(*Line2)));
        while (StepLine(rtl_far(&(*Line2)))) {
        }
        if (((Bouncing != 0)) && (((*Line2).First <= CastLineBeam_BounceFirstLimit))) {
          (*Line).First += CastLineBeam_BounceExtraSteps;
        }
        /* QUIRK ovl22:2B71: written `0 - DirSign`, not `-DirSign`: TP 6.0 compiles unary minus to
           `neg ax` but the subtraction to `mov dx,ax; xor ax,ax; sub ax,dx`, which is the original's
           bytes (probe NEG.PAS). */
        DirSign = 0 - DirSign;
        Bouncing = 0;
        PrevOccupant = 0;
      }
      if ((*Line).First < Length_) {
        Length_ -= (*Line).First;
      } else {
        Length_ = 0;
      }
    } while (!((Blocked) || ((Length_ == 0))));
  }
  SpellAppliedToArea = 0;
L_exit:
  rtl_stack_release(stack_mark);
}

/* ovl22:2BB7 (e50). Cast handler of spell 51, Lightning Bolt: it rolls one d6 per caster level
     (SpellCasterLevel(CastingSpell), RollDice) as the damage, deals it to the combatant on the aim cell
     SpellAimX/SpellAimY (DamageTargetInCell, electrical, save kind 4) and then runs the beam CastLineBeam
     with reach 8, the same damage and save kind and the bounce flag 1, so the bolt reflects off a wall
     once. Reads CastingSpell. Called through SpellHandlers[51] (InitSpellHandlers). */
void CastLightningBolt(void)
{
  POOL_TRACE("CastLightningBolt");
  u8 Damage = 0;
  u8 Blocked = 0;
  Damage = RollDice(SpellCasterLevel(CastingSpell), CastLightningBolt_LevelDiceSides);
  DamageTargetInCell(SpellAimX, SpellAimY, Damage, SaveKindSpell, &Blocked);
  CastLineBeam(CastLightningBolt_BeamReach, Damage, SaveKindSpell, CastLightningBolt_BounceOnce);
}

/* ovl22:2C09 (e51). Cast handler of spell 55, Slow: hands the opposite side of the selected character
     (OpposingSide) and the haste affect $27 (SpellTable[48].AffectId) to ApplySpellToSideUpToLevel,
     which cures Haste from up to caster-level members of that side and then applies Slow to the rest
     with 'is Slowed'. One of the per-spell handlers in SpellHandlers (SpellHandlers[55], filled by
     InitSpellHandlers; the Haste handler CastHaste does the mirror image with the slow affect $2A). Reads
     SelectedCharacter. */
void CastSlow(void)
{
  POOL_TRACE("CastSlow");
  ApplySpellToSideUpToLevel(CastSlow_HasteAffect, OpposingSide(SelectedCharacter), S("\011is Slowed"));
}

/* ovl22:2C43 (e52). Cast handler of spell 56, Restoration: it gives the selected character FirstSpellTarget back
     one drained level. The character's drained levels are Pad74[$74] and the hit points lost with them
     Pad74[$75] (a character shows +$32 max, +$11B current and +$75 lost hit points, ovl33:0004), so one
     restored level gives back Pad74[$75] div Pad74[$74] hit points, added to HpMax (+$32), the current
     hit points (+$11B) and HpB1 (+$B1), then the drained-level count is decremented. It then picks the
     class to advance (ClassLevels, +$96): over the eight classes it takes the class whose current level
     is not above the best so far and whose entry one level up in the experience table ExperienceTable
     has the smallest positive value, and keeps the class whose IsMaxClassLevel call is false; that class gains one
     level, the character's Experience (+$AC) is raised to at least that entry, RecalcClassStats
     recomputes the derived values and the character is told 'is restored' (ShowCharacterMessage). A character
     with no drained level (Pad74[$74] = 0) is left alone. Reads FirstSpellTarget; changes the character's drained
     levels, hit points, class level and Experience. */
void CastRestoration(void)
{
  POOL_TRACE("CastRestoration");
  PCharacter Target = 0;
  u8 PerLevel = 0;
  s8 MaxLevel = 0;
  s8 Level = 0;
  s32 BestXp = 0;
  s8 BestClass = 0;
  s8 Class = 0;
  Target = FirstSpellTarget;
  if ((*FPD(TCharacter (*), Target)).Pad74[0] <= 0) {
    return;
  }
  PerLevel = ((*FPD(TCharacter (*), Target)).Pad74[1] / (*FPD(TCharacter (*), Target)).Pad74[0]);
  (*FPD(TCharacter (*), Target)).HpMax += PerLevel;
  (*FPD(TCharacter (*), Target)).HpCurrent += PerLevel;
  (*FPD(TCharacter (*), Target)).HpB1 += PerLevel;
  (*FPD(TCharacter (*), Target)).Pad74[1] -= PerLevel;
  (*FPD(TCharacter (*), Target)).Pad74[0]--;
  MaxLevel = CastRestoration_MaxRestoredLevel;
  BestXp = CastRestoration_MaxExperience;
  /* QUIRK ovl22:2CAE: BestClass is never initialized, only set by an accepted class; a character with
     no class that can advance would advance whatever class the stale local names. */
  {
    if (0 <= CastRestoration_LastClass) {
      Class = 0;
      for (;;) {
          Level = (*FPD(TCharacter (*), Target)).ClassLevels[Class];
          if ((((((Level > 0)) && ((Level <= MaxLevel))) && ((ExperienceTable[Class][(s8)(Level + 1)] > 0))) && ((ExperienceTable[Class][(s8)(Level + 1)] < BestXp))) && !IsMaxClassLevel(Target, Class)) {
            MaxLevel = Level;
            BestClass = Class;
            BestXp = ExperienceTable[Class][(s8)(Level + 1)];
          }
        if (Class == CastRestoration_LastClass) break;
        Class++;
      }
    }
  }
  (*FPD(TCharacter (*), Target)).ClassLevels[BestClass]++;
  if ((*FPD(TCharacter (*), Target)).Experience < BestXp) {
    (*FPD(TCharacter (*), Target)).Experience = BestXp;
  }
  RecalcClassStats(Target);
  ShowCharacterMessage(Target, S("\013is restored"), CastRestoration_MessageColor, TimedMessage);
}

/* ovl22:2E02. Cast handler of spell 57, a monster-only spell: SpellNames[57] is empty, and the
     InitSpellHandlers table points element 57 of SpellHandlers at this stub. It first cancels the slow affect
     $2A from the first chosen target FirstSpellTarget (CureAffect, which shows 'is Cured'); when the target was
     not slowed it applies the current spell CastingSpell to the chosen targets with 'is Speedy', so the
     affected target carries the spell's own (haste) affect. It is CastHaste's single-target sibling. */
void CastMonsterHaste(void)
{
  POOL_TRACE("CastMonsterHaste");
  if (!CureAffect(FirstSpellTarget, CastMonsterHaste_SlowAffect)) {
    ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\011is Speedy"));
  }
}

/* ovl22:2E4D. Cast handler of spell 58, a monster-only spell: SpellNames[58] is empty, and the
     InitSpellHandlers table points element 58 of SpellHandlers at this stub. It cures the first chosen target
     FirstSpellTarget: when the target carries the Poisoned affect $37 (CureAffect) it also removes the affect $16
     that the poison leaves behind, with RemovingAffects set so the removals do not run ovl04's own cure handlers.
     A target that is not poisoned is cured of disease instead (CureDiseaseAffects) and, when neither
     cure applies, heals 1d4 + 8 hit points through HealCharacter and reports 'is Healed'. */
void CastMonsterHeal(void)
{
  POOL_TRACE("CastMonsterHeal");
  u8 Spare = 0;
  if (CureAffect(FirstSpellTarget, CastMonsterHeal_PoisonedAffect)) {
    RemovingAffects = 1;
    RemoveAffect(FirstSpellTarget, CastMonsterHeal_PoisonAidAffect, 0);
    RemovingAffects = 0;
  } else if (!CureDiseaseAffects()) {
    if (HealCharacter(FirstSpellTarget, (s16)(RollDice(CastMonsterHeal_HealDiceCount, CastMonsterHeal_HealDiceSides) + CastMonsterHeal_HealBase), CastMonsterHeal_NoFlag)) {
      ShowHitMessage(FirstSpellTarget, CastMonsterHeal_ShowAbout, S("\011is Healed"));
    }
  }
}

/* ovl22:2EE5. Cast handler of spell 59, a monster-only spell: SpellNames[59] is empty, and the
     InitSpellHandlers table points element 59 of SpellHandlers at this stub. It gives the first chosen target
     FirstSpellTarget a fixed Strength of 21 with no exceptional percentile (RaiseStrength; a monster's strength),
     shows 'is stronger' when the strength actually rose (ShowCharacterMessage) and adds the strength affect $26
     (the affect CastStrength and this routine leave, SpellTable[35] and [59]; Enlarge's is $0C, ovl24
     RaiseStrength) for the current spell's own duration (SpellAffectDuration). */
void CastMonsterStrength(void)
{
  POOL_TRACE("CastMonsterStrength");
  u8 Code = 0;
  if (RaiseStrength(FirstSpellTarget, CastMonsterStrength_MonsterStrength, CastMonsterStrength_NoPercent, &Code)) {
    ShowCharacterMessage(FirstSpellTarget, S("\013is stronger"), CastMonsterStrength_MessageColor, TimedMessage);
  }
  AddAffect(FirstSpellTarget, CastMonsterStrength_StrengthAffect, SpellAffectDuration(CastingSpell), Code, RunsHandlerOnRemove);
}

/* ovl22:2F4D. Cast handler of spell 60, a monster-only spell: SpellNames[60] is empty, and the
     InitSpellHandlers table points element 60 of SpellHandlers at this stub. It strikes the combatant on the aim
     cell SpellAimX/SpellAimY for 1d6 + 20 points (DamageTargetInCell: the spell's saving throw kind 4, half
     damage on a save, and the zap animation) and then runs a short beam CastLineBeam(3, 20, 4, 0): six
     cells of 20 points away from the caster, no bounce. */
void CastMonsterBeam(void)
{
  POOL_TRACE("CastMonsterBeam");
  u8 Blocked = 0;
  DamageTargetInCell(SpellAimX, SpellAimY, (s16)(RollDice(CastMonsterBeam_StrikeDiceCount, CastMonsterBeam_StrikeDiceSides) + CastMonsterBeam_StrikeBase), SaveKindSpell, &Blocked);
  CastLineBeam(CastMonsterBeam_BeamReach, CastMonsterBeam_BeamDamage, SaveKindSpell, CastMonsterBeam_NoBounce);
}

/* ovl22:2F99 (e57). Cast handler of spell 61, a monster-only spell: SpellNames[61] is empty and the
     InitSpellHandlers handler table points element 61 of SpellHandlers at this stub. It only applies the current
     spell CastingSpell to the chosen targets with the message 'is paralyzed'; the spell's own affect does the
     paralyzing (as CastCauseBlindness does the blinding). Reads CastingSpell. */
void CastMonsterParalyze(void)
{
  POOL_TRACE("CastMonsterParalyze");
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\014is paralyzed"));
}

/* ovl22:2FD0 (e58). Cast handler of spell 62, a monster-only spell: SpellNames[62] is empty and the
     InitSpellHandlers handler table points element 62 of SpellHandlers at this stub. It heals the first chosen
     target FirstSpellTarget through HealCharacter for 2d4 + 2 hit points (RollDice, no flag) and reports
     'is Healed' when the heal went through (ShowHitMessage, its Flag 1). The map read the routine's
     own prologue as a separate 3-byte routine ovl22_fn_2FD3 at the sub sp word; make match WRITE=1
     removed that entry (nothing calls it, and the entry stubs point at 2FD0, overlay entry 58).
     Reads FirstSpellTarget. */
void CastMonsterHealWounds(void)
{
  POOL_TRACE("CastMonsterHealWounds");
  if (HealCharacter(FirstSpellTarget, (s16)(RollDice(2, 4) + 2), 0)) {
    ShowHitMessage(FirstSpellTarget, 1, S("\011is Healed"));
  }
}

/* ovl22:302A (e59). Cast handler of spell 63, a monster-only spell: SpellNames[63] is empty and the
     InitSpellHandlers handler table points element 63 of SpellHandlers at this stub. It only applies the current
     spell CastingSpell to the chosen targets with the message 'is invisible'; the spell's own affect does the
     work (as CastDetectionSpell and CastCauseBlindness leave it to the affect). Reads CastingSpell. */
void CastMonsterInvisibility(void)
{
  POOL_TRACE("CastMonsterInvisibility");
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, S("\014is invisible"));
}

/* ovl22:3058 (e60). Cast handler of spell 65, a monster-only spell: SpellNames[65] is empty and the
     InitSpellHandlers handler table points element 65 of SpellHandlers at this stub. It applies the current
     spell CastingSpell to the chosen targets for 2d4 + 2 points (RollDiceCounted, its count kept in LastDiceCount)
     of magic damage with no message. The roll is the damage CastMagicMissile deals for a caster of
     level 3 or 4 (two missiles of 1d4 + 1, ovl22:1439), fixed here since a monster has no caster level.
     Reads CastingSpell; changes LastDiceCount. */
void CastMonsterMagicDamage(void)
{
  POOL_TRACE("CastMonsterMagicDamage");
  ApplySpellToTargets(CastingSpell, 0, 0, (s16)(RollDiceCounted(CastMonsterMagicDamage_DiceCount, CastMonsterMagicDamage_DiceSides) + CastMonsterMagicDamage_DamageBonus), CastMonsterMagicDamage_DamageKind, S("\000"));
}

/* ovl22:3092 (e61). Cast handler of spell 66, a monster-only spell: SpellNames[66] is empty and the
     InitSpellHandlers handler table points element 66 of SpellHandlers at this stub. The handler is empty: the
     picker has already chosen the targets (CastChosenSpell calls SpellTargetPicker, the DS:6B84
     callback, before the handler) and the spell then does nothing, since ApplySpellToTargets is never
     called here, unlike its neighbours CastMonsterParalyze (spell 61) and CastMonsterMagicDamage
     (spell 65). */
void CastMonsterNoEffect(void)
{
  POOL_TRACE("CastMonsterNoEffect");
}

/* ovl22:30A2 (e62). Cast handler of the monster-only spell 67 (SpellHandlers element 67, whose
     SpellNames entry is empty, whitepaper 5.22.2): applies the current spell CastingSpell to the chosen
     targets with caster level $FF (a fixed affect data, as CastSlowPoison's FullCasterLevel), Flag 1
     so the affect's handler runs when it is removed, no damage or kind of its own, and the message
     'is Reading'. */
void CastMonsterReadMagic(void)
{
  POOL_TRACE("CastMonsterReadMagic");
  ApplySpellToTargets(CastingSpell, 0xFF, 1, 0, 0, S("\012is Reading"));
}

/* ovl22:30D9. MonsterBreath: the breath attack of a monster (the dragon breath the line spells'
     comments name). When CombatRound is set (a combat round counter) it first rolls 1d100 and gives up on a
     roll of 50 or less, so the monster does not breathe every round. It takes the breather's combat cell
     (CombatantX/Y of Who), shows 'Breathes!', asks the target picker SpellTargetPicker for the aim
     (spell $33, the Lightning Bolt, quick) with its Done at PickerDone, and nudges the aim cell
     SpellAimX/SpellAimY one cell towards the breather (SignOf) and off the cell beside him. It clears the
     breather's attacker affect, plays the zap animation (DrawCombatIcon($13)), draws the breath line
     (WalkCombatLine) from the breather to the aim cell, damages the aim cell for his maximum hit points
     (DamageTargetInCell: electrical, save kind 3) and runs the line beam CastLineBeam($A, HpMax, 3, 0).
     Finally it spends the breath affect Affect: while its Data byte is above $FD it is only decremented,
     otherwise the affect $58 is removed; EndCombatTurn(Who) then runs and its byte result is left in the
     unread Blocked local (QUIRK ovl22:30D9). Globals: CombatRound, SpellAimX/SpellAimY, PickerDone. Parameters: Who the
     breathing monster, Affect its breath affect, Unused is never read (QUIRK ovl22:30D9). */
void MonsterBreath(PCharacter Who, PAffect Affect, u8 Unused)
{
  POOL_TRACE("MonsterBreath");
  u8 Blocked = 0;
  s8 CasterX = 0;
  s8 CasterY = 0;
  if (((CombatRound != 0)) && ((RollDice(1, MonsterBreath_ChanceSides) <= MonsterBreath_BreatheChance))) {
    return;
  }
  CasterX = CombatantX(Who);
  CasterY = CombatantY(Who);
  ShowCharacterMessage(Who, S("\011Breathes!"), MonsterBreath_MessageColor, TimedMessage);
  ((void (*)(u8, u8, u8 (*)))rtl_proc(SpellTargetPicker))(MonsterBreath_PickerSpell, MonsterBreath_PickerQuick, &PickerDone);
  SpellAimX = CasterX + SignOf((s16)(SpellAimX - CasterX));
  SpellAimY = CasterY + SignOf((s16)(SpellAimY - CasterY));
  if (SpellAimX == (s16)(CasterX + 1)) {
    SpellAimX++;
  }
  if (SpellAimY == (s16)(CasterY + 1)) {
    SpellAimY++;
  }
  ClearAttackerAffect(Who);
  DrawCombatIcon(MonsterBreath_ZapAnimation);
  WalkCombatLine(CasterX, CasterY, SpellAimX, SpellAimY, MonsterBreath_BeamStep, MonsterBreath_BeamWidth);
  DamageTargetInCell(SpellAimX, SpellAimY, (*FPD(TCharacter (*), Who)).HpMax, SaveKindBreath, &Blocked);
  CastLineBeam(MonsterBreath_BeamReach, (*FPD(TCharacter (*), Who)).HpMax, SaveKindBreath, MonsterBreath_NoBounce);
  if ((*FPD(TAffect (*), Affect)).Data > MonsterBreath_BreathDataLimit) {
    (*FPD(TAffect (*), Affect)).Data--;
  } else {
    RemoveAffect(Who, MonsterBreath_BreathAffect, Affect);
  }
  Blocked = (u8)EndCombatTurn(Who);
}

/* ovl22:323D. IsScroll: whether Item is a spell scroll. It rejects a nil item first, then tests the
     item's class byte ItemTable[Item^.ItemType].Slot (the first byte of the 16-byte row for the item type
     in the ItemTable table at DS:5582): the three values $B, $C and $D are the spell scrolls whose
     Affects[1..3] hold spell numbers (AddItemSpells and the scribing helpers read them). Callers use it
     to find the carried scrolls: AddScrollSpells, ScribeScrolls, StudyRestMinutes, CancelScribing,
     ProcessPendingScribedSpell, UseMagicItem and the inventory. */
u8 IsScroll(PItem Item)
{
  POOL_TRACE("IsScroll");
  u8 Result = 0;
  if ((((Item != 0)) && ((ItemTable[(*FPD(TMenuLine (*), Item)).ItemType].Slot > IsScroll_NotAScrollBelow))) && ((ItemTable[(*FPD(TMenuLine (*), Item)).ItemType].Slot < IsScroll_NotAScrollAbove))) {
    Result = 1;
  } else {
    Result = 0;
  }
  return Result;
}

/* ovl22:328A. ConsumeScrollSpell: removes one scribed spell from a scroll. The spell number (the low
     seven bits of Spell) is looked for among the scroll's three spell bytes Item^.Affects[1..3]; the
     last slot whose low seven bits match is cleared, the scroll's second name number (NameNum[2],
     +$30) is decremented and, when it drops below $D2 (no spells left), the scroll is removed from
     Who's items (RemoveInventoryItem unlinks it and frees it; nothing is redrawn).
     ProcessPendingScribedSpell calls it after marking the scribed spell known, and ovl19's item code
     calls it too. Nothing happens when the spell is not on the scroll (Slot stays 0). */
void ConsumeScrollSpell(PCharacter Who, PItem Item, u8 Spell)
{
  POOL_TRACE("ConsumeScrollSpell");
  u8 SpellNumber = 0;
  u8 I = 0;
  u8 Slot = 0;
  SpellNumber = (Spell & SpellMask);
  Slot = 0;
  {
    if (1 <= 3) {
      I = 1;
      for (;;) {
          if ((((*FPD(TMenuLine (*), Item)).Affects[I - 1] & SpellMask)) == SpellNumber) {
            Slot = I;
          }
        if (I == 3) break;
        I++;
      }
    }
  }
  if (Slot == 0) {
    return;
  }
  (*FPD(TMenuLine (*), Item)).Affects[Slot - 1] = 0;
  (*FPD(TMenuLine (*), Item)).NameNum[1]--;
  if ((*FPD(TMenuLine (*), Item)).NameNum[1] < ConsumeScrollSpell_UsedUpScrollBelow) {
    RemoveInventoryItem(Who, Item);
  }
}

/* ovl22:331A. Announces a spell event for a named character. In combat (ViewMode = 5) it shows the timed
     message 'Casts a Spell' and, on the combat message row, 'Spell:' with the spell's name at column 0.
     Outside combat it clears the message window, draws Who's name at column 1 of row $13 (DrawCharacterName),
     draws Message right after the name (two columns past the name's length: 'casts', 'has memorized' or
     'has scribed'), draws the spell's name at column 1 of the next row, waits a game-speed delay and
     clears the prompt (ClearCharacterMessage). Called by ovl20's ProcessMemorizedSpell and
     ProcessPendingScribedSpell and by CastChosenSpell (which passes 'casts'). The map's ovl22_fn_3379
     entry at 3379 was invented inside this routine; make match WRITE=1 removed it. */
void ShowSpellMessage(PCharacter Who, const u8 *Message_in, u8 Spell)
{
  POOL_TRACE("ShowSpellMessage");
  const u8 *Message = Message_in;
  u8 t1[256];
  if (ViewMode == ViewModeCombat) {
    ShowCharacterMessage(Who, S("\015Casts a Spell"), ShowSpellMessage_MessageColor, TimedMessage);
    ClearWindow(0, 0x17, 0x27, 0x17);
    DrawTextAt(0, 0x17, ShowSpellMessage_MessageColor, rtl_str_cat(t1, 2, (const u8 *const[]){S("\006Spell:"), SpellNames[Spell]}));
  } else {
    ClearWindow(ShowSpellMessage_TextColumn, 0x12, 0x26, 0x16);
    DrawCharacterName(Who, ShowSpellMessage_TextColumn, ShowSpellMessage_MessageRow, 0);
    DrawTextAt((s16)((*FPD(TCharacter (*), Who)).Name[0] + ShowSpellMessage_GapAfterName), ShowSpellMessage_MessageRow, ShowSpellMessage_MessageColor, Message);
    DrawTextAt(ShowSpellMessage_TextColumn, ShowSpellMessage_SpellNameRow, ShowSpellMessage_MessageColor, SpellNames[Spell]);
    DelayByGameSpeed();
    ClearCharacterMessage();
  }
}

/* ovl22:3413 (e10). Initialises the spell-casting tables and globals once at start-up (ovl11:002D
     StartGame calls it). It fills the DS:6B84 block SpellHandlers: element 0 is the target picker
     (@ChooseSpellTargets) and elements 1..$43 the cast handler of every spell number 1..$43, each an
     overlay stub of this unit (several spells share one handler: elements 5, 11, 18, 22 and 29 are
     CastDetectionSpell; 6, 7, 16, 17 and 52..54 are CastProtection; 46 is CastDispelMagic with 41).
     Then it stores @MonsterBreath in DS:6988 (MonsterBreathVector), clears the affect-removal flag RemovingAffects, the
     item-cast flag ItemAffectUse (set while the Use action casts a spell from an item, ovl19; the
     spell is then not forgotten and SpellCasterLevel returns 6) and the picker's chosen character
     PickedSpellCharacter, and sets RedrawItemWindow to 1. */
void InitSpellHandlers(void)
{
  POOL_TRACE("InitSpellHandlers");
  SpellTargetPicker = PROC_ChooseSpellTargets;
  RemovingAffects = 0;
  ItemAffectUse = 0;
  PickedSpellCharacter = 0;
  RedrawItemWindow = 1;
  SpellHandlers[1] = PROC_CastBless;
  SpellHandlers[2] = PROC_CastCurse;
  SpellHandlers[3] = PROC_CastCureLightWounds;
  SpellHandlers[4] = PROC_CastCauseLightWounds;
  SpellHandlers[5] = PROC_CastDetectionSpell;
  SpellHandlers[6] = PROC_CastProtection;
  SpellHandlers[7] = PROC_CastProtection;
  SpellHandlers[8] = PROC_CastResistCold;
  SpellHandlers[9] = PROC_CastBurningHands;
  SpellHandlers[10] = PROC_CastCharmPerson;
  SpellHandlers[11] = PROC_CastDetectionSpell;
  SpellHandlers[12] = PROC_CastEnlarge;
  SpellHandlers[13] = PROC_CastReduce;
  SpellHandlers[14] = PROC_CastFriends;
  SpellHandlers[15] = PROC_CastMagicMissile;
  SpellHandlers[16] = PROC_CastProtection;
  SpellHandlers[17] = PROC_CastProtection;
  SpellHandlers[18] = PROC_CastDetectionSpell;
  SpellHandlers[19] = PROC_CastShield;
  SpellHandlers[20] = PROC_CastShockingGrasp;
  SpellHandlers[21] = PROC_CastSleep;
  SpellHandlers[22] = PROC_CastDetectionSpell;
  SpellHandlers[23] = PROC_CastHoldPerson;
  SpellHandlers[24] = PROC_CastResistFire;
  SpellHandlers[25] = PROC_CastSilence;
  SpellHandlers[26] = PROC_CastSlowPoison;
  SpellHandlers[27] = PROC_CastSnakeCharm;
  SpellHandlers[28] = PROC_CastSpiritualHammer;
  SpellHandlers[29] = PROC_CastDetectionSpell;
  SpellHandlers[30] = PROC_CastInvisibility;
  SpellHandlers[31] = PROC_CastKnock;
  SpellHandlers[32] = PROC_CastMirrorImage;
  SpellHandlers[33] = PROC_CastRayOfEnfeeblement;
  SpellHandlers[34] = PROC_CastStinkingCloud;
  SpellHandlers[35] = PROC_CastStrength;
  SpellHandlers[36] = PROC_CastAnimateDead;
  SpellHandlers[37] = PROC_CastCureBlindness;
  SpellHandlers[38] = PROC_CastCauseBlindness;
  SpellHandlers[39] = PROC_CastCureDisease;
  SpellHandlers[40] = PROC_CastCauseDisease;
  SpellHandlers[41] = PROC_CastDispelMagic;
  SpellHandlers[42] = PROC_CastPrayer;
  SpellHandlers[43] = PROC_CastRemoveCurse;
  SpellHandlers[44] = PROC_CastBestowCurse;
  SpellHandlers[45] = PROC_CastBlink;
  SpellHandlers[46] = PROC_CastDispelMagic;
  SpellHandlers[47] = PROC_CastFireball;
  SpellHandlers[48] = PROC_CastHaste;
  SpellHandlers[49] = PROC_CastHoldPerson;
  SpellHandlers[50] = PROC_CastInvisibility;
  SpellHandlers[51] = PROC_CastLightningBolt;
  SpellHandlers[52] = PROC_CastProtection;
  SpellHandlers[53] = PROC_CastProtection;
  SpellHandlers[54] = PROC_CastProtection;
  SpellHandlers[55] = PROC_CastSlow;
  SpellHandlers[56] = PROC_CastRestoration;
  SpellHandlers[57] = PROC_CastMonsterHaste;
  SpellHandlers[58] = PROC_CastMonsterHeal;
  SpellHandlers[59] = PROC_CastMonsterStrength;
  SpellHandlers[60] = PROC_CastMonsterBeam;
  SpellHandlers[61] = PROC_CastMonsterParalyze;
  SpellHandlers[62] = PROC_CastMonsterHealWounds;
  SpellHandlers[63] = PROC_CastMonsterInvisibility;
  SpellHandlers[64] = PROC_CastFireball;
  SpellHandlers[65] = PROC_CastMonsterMagicDamage;
  SpellHandlers[66] = PROC_CastMonsterNoEffect;
  SpellHandlers[67] = PROC_CastMonsterReadMagic;
  MonsterBreathVector = PROC_MonsterBreath;
}

/* Initialisation part of unit OVL22. */
void init_OVL22(void)
{
  POOL_TRACE("init");
}
