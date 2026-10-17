#include "game.h"

/* ovl15:0000. Returns the minutes of rest Who's study needs and stores its hours in RestHours: 15
     minutes per spell level of every spell being memorized (a Spells slot with bit 7) and of every
     scroll spell being scribed (bit 7 of a spell byte of an item IsScroll accepts, a scroll), plus
     4 hours when there is any (6 when one of them is above level 2). RestParty rests the party for
     the largest value. */
u16 StudyRestMinutes(PCharacter Who)
{
  POOL_TRACE("StudyRestMinutes");
  u16 Result = 0;
  u8 MaxMemLevel = 0;
  u8 MaxScribeLevel = 0;
  u8 MemSum = 0;
  u8 ScribeSum = 0;
  PItem Item = 0;
  u8 I = 0;
  u8 Level = 0;
  u8 Hours = 0;
  MaxMemLevel = 0;
  MaxScribeLevel = 0;
  MemSum = 0;
  ScribeSum = 0;
  {
    if (0 <= LastSpellSlot) {
      I = 0;
      for (;;) {
          if ((*FPD(TCharacter (*), Who)).Spells[I] > SpellMask) {
            Level = SpellTable[((*FPD(TCharacter (*), Who)).Spells[I] & SpellMask)].Level;
            if (Level > MaxMemLevel) {
              MaxMemLevel = Level;
            }
            MemSum += Level;
          }
        if (I == LastSpellSlot) break;
        I++;
      }
    }
  }
  Item = (*FPD(TCharacter (*), Who)).Items;
  while (Item != 0) {
    if (IsScroll(Item)) {
      {
        if (1 <= ScrollSpells) {
          I = 1;
          for (;;) {
              if ((*FPD(TMenuLine (*), Item)).Affects[I - 1] > SpellMask) {
                Level = SpellTable[((*FPD(TMenuLine (*), Item)).Affects[I - 1] & SpellMask)].Level;
                if (Level > MaxScribeLevel) {
                  MaxScribeLevel = Level;
                }
                ScribeSum += Level;
              }
            if (I == ScrollSpells) break;
            I++;
          }
        }
      }
    }
    Item = (*FPD(TMenuLine (*), Item)).Next;
  }
  Hours = 0;
  if (((MemSum > 0)) || ((ScribeSum > 0))) {
    Hours = BaseRestHours;
  }
  if (((MaxMemLevel > LongRestLevel)) || ((MaxScribeLevel > LongRestLevel))) {
    Hours = LongRestHours;
  }
  (*FPD(TCharacter (*), Who)).RestHours = Hours;
  Result = ((Hours * 60) + (MemSum * MinutesPerLevel)) + (ScribeSum * MinutesPerLevel);
  return Result;
}

/* ovl15:0159. Cancels Who's memorizing: every Spells slot still being memorized (bit 7) is emptied
     and RestHours is cleared. The answer No to 'Memorize These Spells?' and CancelPartyStudy. */
void CancelMemorizing(PCharacter Who)
{
  POOL_TRACE("CancelMemorizing");
  u8 I = 0;
  {
    if (0 <= LastSpellSlot) {
      I = 0;
      for (;;) {
          if ((*FPD(TCharacter (*), Who)).Spells[I] > SpellMask) {
            (*FPD(TCharacter (*), Who)).Spells[I] = 0;
          }
        if (I == LastSpellSlot) break;
        I++;
      }
    }
  }
  (*FPD(TCharacter (*), Who)).RestHours = 0;
}

/* ovl15:019C. Cancels Who's scribing: bit 7 is cleared from the three spell bytes of every scroll
     Who carries (an item IsScroll accepts). The answer No to 'Scribe These Spells?' and
     CancelPartyStudy. */
void CancelScribing(PCharacter Who)
{
  POOL_TRACE("CancelScribing");
  u8 I = 0;
  PItem Item = 0;
  Item = (*FPD(TCharacter (*), Who)).Items;
  while (Item != 0) {
    if (IsScroll(Item)) {
      {
        if (1 <= ScrollSpells) {
          I = 1;
          for (;;) {
              (*FPD(TMenuLine (*), Item)).Affects[I - 1] = ((*FPD(TMenuLine (*), Item)).Affects[I - 1] & SpellMask);
            if (I == ScrollSpells) break;
            I++;
          }
        }
      }
    }
    Item = (*FPD(TMenuLine (*), Item)).Next;
  }
}

/* ovl15:0214. Cancels the memorizing and scribing of every member of the party list (PartyListHead);
     MakeCamp runs it when the camp opens and when it closes, so only a study finished by RestParty
     survives the camp. */
void CancelPartyStudy(void)
{
  POOL_TRACE("CancelPartyStudy");
  PCharacter Who = 0;
  Who = PartyListHead;
  while (Who != 0) {
    CancelMemorizing(Who);
    CancelScribing(Who);
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
}

/* ovl15:025C. Returns the spell slots SelectedCharacter has left for spells of SpellClass (0 cleric,
     1 magic-user) and SpellLevel (1..3): SpellSlots[SpellClass, SpellLevel] minus the spells of that
     class and level in its Spells slots, memorized or still being memorized. */
u8 SpellSlotsLeft(s8 SpellLevel, s8 SpellClass)
{
  POOL_TRACE("SpellSlotsLeft");
  u8 Result = 0;
  u8 Count = 0;
  u8 I = 0;
  Count = 0;
  {
    if (0 <= LastSpellSlot) {
      I = 0;
      for (;;) {
          if (((((*FPD(TCharacter (*), SelectedCharacter)).Spells[I] > 0)) && ((SpellTable[((*FPD(TCharacter (*), SelectedCharacter)).Spells[I] & SpellMask)].Level == SpellLevel))) && ((SpellTable[((*FPD(TCharacter (*), SelectedCharacter)).Spells[I] & SpellMask)].SpellClass == SpellClass))) {
            Count++;
          }
        if (I == LastSpellSlot) break;
        I++;
      }
    }
  }
  Result = (*FPD(TCharacter (*), SelectedCharacter)).SpellSlots[SpellClass][SpellLevel - 1] - Count;
  return Result;
}

/* ovl15:036C. Whether SelectedCharacter may Action (ActionCast, ActionMemorize, ActionScribe): not
     when the game variable VarNoCasting forbids casting here (casting only: 'cannot cast spells in
     this area'), nor when the character's Status is 1 or Flag10D is 0 ('is in no condition to cast
     any spells', 'memorize spells' or 'scribe any scrolls'). The refusal is shown on the message line
     (ShowCharacterMessage). */
u8 MayUseMagic(u8 Action)
{
  POOL_TRACE("MayUseMagic");
  u8 Result = 0;
  String40_RES06 Reason = {0};
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  rtl_str_assign(Reason, 40, S("\000"));
  if (((Action == ActionCast)) && (((*FPD(TGameVars (*), GameVars))[229] > 0))) {
    rtl_str_assign(Reason, 40, S("\037cannot cast spells in this area"));
  } else if ((((*FPD(TCharacter (*), SelectedCharacter)).Status == 1)) || (((*FPD(TCharacter (*), SelectedCharacter)).Flag10D == 0))) {
    rtl_str_assign(Reason, 40, S("\026is in no condition to "));
    switch (Action) {
    case ActionCast:
    {
      rtl_str_assign(Reason, 40, rtl_str_cat(t1, 2, (const u8 *const[]){Reason, S("\017cast any spells")}));
      break;
    }
    case ActionMemorize:
    {
      rtl_str_assign(Reason, 40, rtl_str_cat(t2, 2, (const u8 *const[]){Reason, S("\017memorize spells")}));
      break;
    }
    case ActionScribe:
    {
      rtl_str_assign(Reason, 40, rtl_str_cat(t3, 2, (const u8 *const[]){Reason, S("\022scribe any scrolls")}));
      break;
    }
    }
  }
  if (Reason[0] == 0) {
    Result = 1;
  } else {
    Result = 0;
    ShowCharacterMessage(SelectedCharacter, Reason, MessageColor, 1);
  }
  return Result;
}

/* ovl15:04A1. The Cast command: when MayUseMagic allows it, repeatedly lists SelectedCharacter's memorized
     spells (ChooseSpellFromList) and casts the chosen one in a cleared text window (CastChosenSpell), until the list
     is left; 'has no spells memorized' when there is none. Clears PickedSpellCharacter first and redraws the screen
     (RedrawView) when something was shown. The camp's Magic menu and ovl14's wilderness keys. */
void CastSpells(void)
{
  POOL_TRACE("CastSpells");
  u16 Choice = 0;
  u8 Listed = 0;
  u8 Redraw = 0;
  u8 Done = 0;
  u8 Spell = 0;
  Redraw = 0;
  Choice = NoChoice;
  PickedSpellCharacter = 0;
  if (MayUseMagic(ActionCast)) {
    do {
      Spell = ChooseSpellFromList(ListMemorized, 1, &Choice, &Listed);
      if (Spell != 0) {
        Redraw = 1;
        DrawWindowFrame(1, 0x11, 0x26, 0x16, 0);
        ClearWindow(1, 0x11, 0x26, 0x16);
        CastChosenSpell(Spell, 0, 1, &Done);
        Choice = NoChoice;
      } else if (Listed != 0) {
        Redraw = 1;
      } else {
        ShowCharacterMessage(SelectedCharacter, S("\027has no spells memorized"), MessageColor, 1);
      }
    } while (!(Spell == 0));
  }
  if (Redraw != 0) {
    RedrawView();
  }
}

/* ovl15:05A4. Shows the spell slots SelectedCharacter has left for memorizing: 'can memorize:' and,
     per class that has slots, a row '    Cleric Spells:' or 'Magic-User Spells:' with the slots left
     at levels 1..3 (blank where the class has no slot of that level), from text row $14. Returns
     False, showing nothing, when the character has no spell slot at all. */
u8 ShowSpellSlotsLeft(void)
{
  POOL_TRACE("ShowSpellSlotsLeft");
  u8 Result = 0;
  String40_RES06 Line = {0};
  u8 Counts[3][2][3] = {0};
  u8 HasClass[2] = {0};
  s8 SpellClass = 0;
  s8 SpellLevel = 0;
  u8 Col = 0;
  u8 Row = 0;
  u8 Any = 0;
  u8 t1[256];
  Any = 0;
  {
    if (ClassCleric <= SpellBookMage) {
      SpellClass = ClassCleric;
      for (;;) {
          HasClass[SpellClass] = 0;
          {
            if (1 <= SpellLevels) {
              SpellLevel = 1;
              for (;;) {
                  rtl_str_assign(Counts[SpellLevel - 1][SpellClass], 2, ByteToText(t1, SpellSlotsLeft(SpellLevel, SpellClass)));
                  if ((*FPD(TCharacter (*), SelectedCharacter)).SpellSlots[SpellClass][SpellLevel - 1] == 0) {
                    rtl_str_assign(Counts[SpellLevel - 1][SpellClass], 2, S("\001 "));
                  } else {
                    HasClass[SpellClass] = 1;
                    Any = 1;
                  }
                if (SpellLevel == SpellLevels) break;
                SpellLevel++;
              }
            }
          }
        if (SpellClass == SpellBookMage) break;
        SpellClass++;
      }
    }
  }
  if (Any) {
    ShowCharacterMessage(SelectedCharacter, S("\015can memorize:"), MessageColor, 0);
    Row = 3;
    {
      if (ClassCleric <= SpellBookMage) {
        SpellClass = ClassCleric;
        for (;;) {
            if (HasClass[SpellClass]) {
              switch (SpellClass) {
              case ClassCleric:
              {
                rtl_str_assign(Line, 40, S("\022    Cleric Spells:"));
                break;
              }
              case SpellBookMage:
              {
                rtl_str_assign(Line, 40, S("\022Magic-User Spells:"));
                break;
              }
              }
              DrawTextAt(1, (s16)(Row + 0x11), TextColor, Line);
              Col = 0x13;
              {
                if (1 <= SpellLevels) {
                  SpellLevel = 1;
                  for (;;) {
                      DrawTextAt((s16)(Col + 1), (s16)(Row + 0x11), TextColor, Counts[SpellLevel - 1][SpellClass]);
                      Col += 3;
                    if (SpellLevel == SpellLevels) break;
                    SpellLevel++;
                  }
                }
              }
              Row++;
            }
          if (SpellClass == SpellBookMage) break;
          SpellClass++;
        }
      }
    }
  }
  Result = Any;
  return Result;
}

/* ovl15:077A. The Rest command: sets RestTime to the longest StudyRestMinutes of the party (hours,
     tens of minutes, minutes; the call also stores each member's RestHours), runs the rest
     (RunRestPeriod, whose result goes to EndCamp, ending the camp when nonzero), then clears RestTime and
     calls DrawLocationLine. */
void RestParty(u8 (*EndCamp))
{
  POOL_TRACE("RestParty");
  PCharacter Who = 0;
  u16 MaxMinutes = 0;
  u16 Minutes = 0;
  u16 Unused = 0;
  MaxMinutes = 0;
  Who = PartyListHead;
  while (Who != 0) {
    Minutes = StudyRestMinutes(Who);
    if (MaxMinutes < Minutes) {
      MaxMinutes = Minutes;
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  RestTime[3] = (MaxMinutes / 60);
  RestTime[2] = (((u16)(MaxMinutes - (RestTime[3] * 60))) / 10);
  RestTime[1] = (MaxMinutes % 10);
  (*EndCamp) = RunRestPeriod();
  rtl_FillChar((void *)&RestTime, 14, 0);
  DrawLocationLine();
}

/* ovl15:0824. Sorts SelectedCharacter's 21 Spells slots by spell number (bit 7 ignored, empty
     slots first) with an exchange sort; MemorizeSpells calls it after adding a spell. */
void SortMemorizedSpells(void)
{
  POOL_TRACE("SortMemorizedSpells");
  u8 I = 0;
  u8 J = 0;
  u8 Spell = 0;
  {
    if (0 <= 19) {
      I = 0;
      for (;;) {
          {
            u8 first = I;
            if (first <= LastSpellSlot) {
              J = first;
              for (;;) {
                  if ((((*FPD(TCharacter (*), SelectedCharacter)).Spells[I] & SpellMask)) > (((*FPD(TCharacter (*), SelectedCharacter)).Spells[J] & SpellMask))) {
                    Spell = (*FPD(TCharacter (*), SelectedCharacter)).Spells[I];
                    (*FPD(TCharacter (*), SelectedCharacter)).Spells[I] = (*FPD(TCharacter (*), SelectedCharacter)).Spells[J];
                    (*FPD(TCharacter (*), SelectedCharacter)).Spells[J] = Spell;
                  }
                if (J == LastSpellSlot) break;
                J++;
              }
            }
          }
        if (I == 19) break;
        I++;
      }
    }
  }
}

/* ovl15:090A. The Memorize command. When spells are still being memorized from before, asks
     'Memorize These Spells? ' (No cancels them, Yes leaves). Then, while slots are left
     (ShowSpellSlotsLeft, else 'cannot memorize any spells'), the chosen spell (ChooseSpellFromList) goes into
     the first empty Spells slot with bit 7 set (being memorized) if its class and level has a slot
     left, and the slots are sorted. After a choice was made it asks 'Memorize these spells? ' over
     the list of spells being memorized; No cancels them. */
void MemorizeSpells(void)
{
  POOL_TRACE("MemorizeSpells");
  u8 Done = 0;
  u8 Listed = 0;
  u8 Redraw = 0;
  u8 Spell = 0;
  u8 Slot = 0;
  u16 Choice = 0;
  if (!MayUseMagic(ActionMemorize)) {
    return;
  }
  Done = 0;
  Choice = NoChoice;
  Spell = ChooseSpellFromList(ListMemorizing, 0, &Choice, &Listed);
  Redraw = 1;
  if (Listed != 0) {
    if (AskYesNo(S("\027Memorize These Spells\077 "), AskColor, WordColor, HotColor) == KeyNo) {
      CancelMemorizing(SelectedCharacter);
    } else {
      Done = 1;
    }
  } else {
    Redraw = 0;
  }
  Choice = NoChoice;
  while (!Done) {
    Done = !ShowSpellSlotsLeft();
    if (Done) {
      ShowCharacterMessage(SelectedCharacter, S("\032cannot memorize any spells"), MessageColor, 1);
    } else {
      Spell = ChooseSpellFromList(ListLearnable, 2, &Choice, &Listed);
      Redraw = 1;
      if (Spell == 0) {
        Done = 1;
      } else if (SpellSlotsLeft(SpellTable[Spell].Level, SpellTable[Spell].SpellClass) > 0) {
        Slot = 0;
        while ((*FPD(TCharacter (*), SelectedCharacter)).Spells[Slot] != 0) {
          Slot++;
        }
        (*FPD(TCharacter (*), SelectedCharacter)).Spells[Slot] = Spell + Pending;
        SortMemorizedSpells();
      }
    }
  }
  if (Choice != NoChoice) {
    Choice = NoChoice;
    Spell = ChooseSpellFromList(ListMemorizing, 0, &Choice, &Listed);
    if (Listed != 0) {
      if (AskYesNo(S("\027Memorize these spells\077 "), AskColor, WordColor, HotColor) == KeyNo) {
        CancelMemorizing(SelectedCharacter);
      }
    }
  }
  if (Redraw != 0) {
    RedrawView();
  }
}

/* ovl15:0B5B. The Scribe command (a magic-user copying scroll spells into the spell book). When
     scroll spells are still being scribed, asks 'Scribe These Spells? ' (No cancels them, Yes
     leaves). Then, for each scroll spell chosen (ChooseSpellFromList; 'has no copyable scrolls' when there is
     none): 'You already know that spell' when it is in KnownSpells, 'You are already scibing that
     spell' (sic) when a scroll spell byte already has it with bit 7, 'You can not scribe that
     spell.' when the character has no slot of its class and level, else bit 7 is set on the first
     scroll spell byte holding it. After a choice it asks 'Scribe these spells? '; No cancels. */
void ScribeScrolls(void)
{
  POOL_TRACE("ScribeScrolls");
  u8 Done = 0;
  u8 Listed = 0;
  u8 Redraw = 0;
  u8 Spell = 0;
  u8 Unused = 0;
  u8 I = 0;
  u16 Choice = 0;
  PItem Item = 0;
  u8 Found = 0;
  if (!MayUseMagic(ActionScribe)) {
    return;
  }
  Done = 0;
  Choice = NoChoice;
  Spell = ChooseSpellFromList(ListScribing, 0, &Choice, &Listed);
  Redraw = 1;
  if (Listed != 0) {
    if (AskYesNo(S("\025Scribe These Spells\077 "), AskColor, WordColor, HotColor) == KeyNo) {
      CancelScribing(SelectedCharacter);
    } else {
      Done = 1;
    }
  } else {
    Redraw = 0;
  }
  Choice = NoChoice;
  while (!Done) {
    Spell = ChooseSpellFromList(ListScrolls, 3, &Choice, &Listed);
    if (Spell == 0) {
      Done = 1;
      if (Listed == 0) {
        ShowCharacterMessage(SelectedCharacter, S("\027has no copyable scrolls"), MessageColor, 1);
      } else {
        Redraw = 1;
      }
    } else {
      Redraw = 1;
      if ((*FPD(TCharacter (*), SelectedCharacter)).KnownSpells[Spell - 1] != 0) {
        ShowFlashMessage(S("\033You already know that spell"));
      } else {
        Item = (*FPD(TCharacter (*), SelectedCharacter)).Items;
        Found = 0;
        while (((Item != 0)) && !Found) {
          if (IsScroll(Item)) {
            {
              if (1 <= ScrollSpells) {
                I = 1;
                for (;;) {
                    if ((((*FPD(TMenuLine (*), Item)).Affects[I - 1] > SpellMask)) && (((((*FPD(TMenuLine (*), Item)).Affects[I - 1] & SpellMask)) == Spell))) {
                      ShowFlashMessage(S("\"You are already scibing that spell"));
                      Found = 1;
                    }
                  if (I == ScrollSpells) break;
                  I++;
                }
              }
            }
          }
          Item = (*FPD(TMenuLine (*), Item)).Next;
        }
        if (!Found) {
          if ((*FPD(TCharacter (*), SelectedCharacter)).SpellSlots[SpellTable[Spell].SpellClass][SpellTable[Spell].Level - 1] > 0) {
            Item = (*FPD(TCharacter (*), SelectedCharacter)).Items;
            while (((Item != 0)) && !Found) {
              I = 1;
              do {
                if ((*FPD(TMenuLine (*), Item)).Affects[I - 1] == Spell) {
                  (*FPD(TMenuLine (*), Item)).Affects[I - 1] = ((*FPD(TMenuLine (*), Item)).Affects[I - 1] | Pending);
                  Found = 1;
                }
                I++;
              } while (!(((I > ScrollSpells)) || Found));
              Item = (*FPD(TMenuLine (*), Item)).Next;
            }
          } else {
            ShowFlashMessage(S("\036You can not scribe that spell."));
          }
        }
      }
    }
  }
  if (Choice != NoChoice) {
    Choice = NoChoice;
    Spell = ChooseSpellFromList(ListScribing, 0, &Choice, &Listed);
    if (Listed != 0) {
      if (AskYesNo(S("\025Scribe these spells\077 "), AskColor, WordColor, HotColor) == KeyNo) {
        CancelScribing(SelectedCharacter);
      }
    }
  }
  if (Redraw != 0) {
    RedrawView();
  }
}

typedef struct Frame_DisplaySpellEffects {
  PAffect Affect;
  PMenuLine List;
  PMenuLine Last;
  PCharacter Who;
  u8 AffectId;
  u8 Spell;
  u8 Count;
  u8 Unused;
  u8 Found;
  u8 Known;
  u8 Redraw;
  String40_RES06 Name;
  s16 Choice;
  u8 Key;
} Frame_DisplaySpellEffects;

/* ovl15:0E37. Nested in DisplaySpellEffects (the static link at [bp+6], pushed by the parent):
       allocates a 46-byte menu line after Last, makes it the last line (Next nil) and sets its text
       and heading flag (Flag29: HeadingLine for a member's name, PlainLine for an affect). */
static void DisplaySpellEffects_AddDisplayLine(struct Frame_DisplaySpellEffects *up, u8 Flag, const u8 *Text_in)
{
  const u8 *Text = Text_in;
  (*FPD(TMenuLine (*), up->Last)).Next = rtl_getmem(MenuLineBytes);
  up->Last = (*FPD(TMenuLine (*), up->Last)).Next;
  (*FPD(TMenuLine (*), up->Last)).Next = 0;
  rtl_str_assign((*FPD(TMenuLine (*), up->Last)).Text, 40, Text);
  (*FPD(TMenuLine (*), up->Last)).Flag29 = Flag;
}

/* ovl15:0FBC. The camp's Display command: lists every party member (the party list PartyListHead, linked
     by Next) as a heading line followed by one line per affect on the member that the game can name,
     or ' <No Spell Effects>' when it names none, then a blank line, and shows the list in the full
     text window titled 'Display' with ChooseFromList (heading colour 11, lines 10, highlight 15,
     with Exit); the list is freed and the screen redrawn (RedrawView) afterwards. A spell affect
     (the first case list) is named by the first spell 1..$38 whose SpellTable.AffectId is the affect
     (SpellNames), or 'Funky--n' (ByteToText writes the number) when no spell has it; fourteen
     other affects have fixed names (the Affect* constants); any other affect is left out. The
     list begins with a blank line (line 0, where the highlight starts: Choice 0), so the first
     member's name is line 1. Reads: PartyListHead, SpellTable, SpellNames.
     Side effects: the heap (the lines, freed by FreeMenuList), the screen, the key pressed is ignored.
     QUIRK ovl15:0FBC: the local Unused ([bp-$14]) is never read or written; the frame needs its
     byte (Count is at [bp-$13], Found at [bp-$15]). */
void DisplaySpellEffects(void)
{
  POOL_TRACE("DisplaySpellEffects");
  Frame_DisplaySpellEffects fr;
  memset(&fr, 0, sizeof fr);
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  fr.List = rtl_getmem(MenuLineBytes);
  fr.Last = fr.List;
  (*FPD(TMenuLine (*), fr.Last)).Flag29 = PlainLine;
  rtl_str_assign((*FPD(TMenuLine (*), fr.Last)).Text, 40, S("\001 "));
  (*FPD(TMenuLine (*), fr.Last)).Next = 0;
  fr.Who = PartyListHead;
  while (fr.Who != 0) {
    fr.Count = 0;
    DisplaySpellEffects_AddDisplayLine(&fr, HeadingLine, (*FPD(TCharacter (*), fr.Who)).Name);
    fr.Affect = (*FPD(TCharacter (*), fr.Who)).Affects;
    while (fr.Affect != 0) {
      fr.Known = 1;
      fr.AffectId = (*FPD(TAffect (*), fr.Affect)).Id;
      switch (fr.AffectId) {
      case 1:
      case 2:
      case 5:
      case 8:
      case 9:
      case 10:
      case 11:
      case 12:
      case 13:
      case 14:
      case 0x10:
      case 0x11:
      case 19:
      case 20:
      case 21:
      case 22:
      case 23:
      case 24:
      case 25:
      case 0x1C:
      case 0x1D:
      case 32:
      case 33:
      case 34:
      case 36:
      case 37:
      case 38:
      case 39:
      case 0x29:
      case 0x2A:
      case 0x2D:
      case 0x2E:
      case 0x31:
      case 51:
      case 52:
      case 53:
      {
        fr.Spell = 1;
        fr.Found = 0;
        while (((fr.Spell <= LastSpell)) && ((fr.Found == 0))) {
          if (SpellTable[fr.Spell].AffectId == fr.AffectId) {
            rtl_str_assign(fr.Name, 40, SpellNames[fr.Spell]);
            fr.Found = 1;
          } else {
            fr.Spell++;
          }
        }
        if (fr.Found == 0) {
          rtl_str_assign(fr.Name, 40, rtl_str_cat(t2, 2, (const u8 *const[]){S("\007Funky--"), ByteToText(t1, fr.AffectId)}));
        }
        break;
      }
      case AffectStudyingManual:
      {
        rtl_str_assign(fr.Name, 40, S(" Studying Manual of Bodily Health"));
        break;
      }
      case AffectTrainingManual:
      {
        rtl_str_assign(fr.Name, 40, S("%Training with Manual of Bodily Health"));
        break;
      }
      case AffectFeatherFall:
      {
        rtl_str_assign(fr.Name, 40, S("\014Feather Fall"));
        break;
      }
      case AffectHelpless:
      {
        rtl_str_assign(fr.Name, 40, S("\010Helpless"));
        break;
      }
      case AffectPrayer:
      {
        rtl_str_assign(fr.Name, 40, S("\006Prayer"));
        break;
      }
      case AffectCauseDisease:
      {
        rtl_str_assign(fr.Name, 40, S("\015Cause Disease"));
        break;
      }
      case AffectMummyDisease:
      {
        rtl_str_assign(fr.Name, 40, S("\025Dreaded Mummy Disease"));
        break;
      }
      case AffectRepulsed:
      {
        rtl_str_assign(fr.Name, 40, S("\010Repulsed"));
        break;
      }
      case AffectPoisoned:
      {
        rtl_str_assign(fr.Name, 40, S("\010Poisoned"));
        break;
      }
      case AffectRegenerating:
      {
        rtl_str_assign(fr.Name, 40, S("\014Regenerating"));
        break;
      }
      case AffectFireResistance:
      {
        rtl_str_assign(fr.Name, 40, S("\017Fire Resistance"));
        break;
      }
      case AffectInvisible:
      {
        rtl_str_assign(fr.Name, 40, S("\011Invisible"));
        break;
      }
      case AffectCamouflaged:
      {
        rtl_str_assign(fr.Name, 40, S("\013Camouflaged"));
        break;
      }
      case AffectDisplaced:
      {
        rtl_str_assign(fr.Name, 40, S("\011Displaced"));
        break;
      }
      default:
      {
        fr.Known = 0;
      }
      }
      if (fr.Known != 0) {
        fr.Count++;
        DisplaySpellEffects_AddDisplayLine(&fr, PlainLine, rtl_str_cat(t3, 2, (const u8 *const[]){S("\001 "), fr.Name}));
      }
      fr.Affect = (*FPD(TAffect (*), fr.Affect)).Next;
    }
    if (fr.Count == 0) {
      DisplaySpellEffects_AddDisplayLine(&fr, PlainLine, S("\023 <No Spell Effects>"));
    }
    DisplaySpellEffects_AddDisplayLine(&fr, PlainLine, S("\001 "));
    fr.Who = (*FPD(TCharacter (*), fr.Who)).Next;
  }
  fr.Redraw = 1;
  fr.Choice = 0;
  DrawWindow(ListLeft, ListTop, ListRight, ListBottom, ListFrameSet, ListTitleColor, S("\007Display"));
  fr.Key = ChooseFromList(S("\000"), S("\000"), ListHeadingColor, ListLineColor, ListHighlightColor, ListLeft, ListFirstRow, ListRight, ListBottom, fr.List, ListWithExit, &fr.Redraw, &fr.Choice, &fr.Last);
  FreeMenuList(&fr.List);
  RedrawView();
}

/* ovl15:13F1. The camp's Magic menu 'Cast Memorize Scribe Display Rest Exit' (CampMagicMenuText)
     until Exit or the rest ends the camp (EndCamp): C CastSpells, M MemorizeSpells, S ScribeScrolls,
     D DisplaySpellEffects, R RestParty; an extended key goes to UpdateSelectedCharacter (the character keys) and
     redraws the character (DrawPartyRoster). */
void CampMagicMenu(u8 (*EndCamp))
{
  POOL_TRACE("CampMagicMenu");
  u8 Key = 0;
  u8 ExtKey = 0;
  Key = ' ';
  while ((((*EndCamp) == 0)) && !((Key == KeyNone_OVL15 || Key == 'E'))) {
    Key = ReadPromptChoice(S("\000"), CampMagicMenuText, TitleColor, WordColor, HotColor, 1, 1, &ExtKey);
    if (ExtKey != 0) {
      UpdateSelectedCharacter(Key);
      DrawPartyRoster(SelectedCharacter);
    } else {
      switch ((u8)Key) {
      case 'C':
      {
        CastSpells();
        break;
      }
      case 'M':
      {
        MemorizeSpells();
        break;
      }
      case 'S':
      {
        ScribeScrolls();
        break;
      }
      case 'D':
      {
        DisplaySpellEffects();
        break;
      }
      case 'R':
      {
        RestParty(&(*EndCamp));
        break;
      }
      }
    }
  }
}

/* ovl15:14A9. Moves SelectedCharacter one place up the party list (PartyListHead, linked by Next): it
     changes places with the member before it, and the first member goes to the end of the list. The
     Party Order menu's G key once a character is picked. */
void MoveMemberUp(void)
{
  POOL_TRACE("MoveMemberUp");
  PCharacter Before = 0;
  PCharacter Who = 0;
  PCharacter After = 0;
  Who = PartyListHead;
  Before = 0;
  if (Who == SelectedCharacter) {
    while ((*FPD(TCharacter (*), Who)).Next != 0) {
      Who = (*FPD(TCharacter (*), Who)).Next;
    }
  } else {
    while ((*FPD(TCharacter (*), Who)).Next != SelectedCharacter) {
      Before = Who;
      Who = (*FPD(TCharacter (*), Who)).Next;
    }
  }
  After = (*FPD(TCharacter (*), SelectedCharacter)).Next;
  if (PartyListHead == SelectedCharacter) {
    if (After != 0) {
      PartyListHead = After;
    }
    (*FPD(TCharacter (*), Who)).Next = SelectedCharacter;
    (*FPD(TCharacter (*), SelectedCharacter)).Next = 0;
  } else {
    (*FPD(TCharacter (*), Who)).Next = After;
    (*FPD(TCharacter (*), SelectedCharacter)).Next = Who;
    if (((Who == PartyListHead)) || ((Before == 0))) {
      PartyListHead = SelectedCharacter;
    } else {
      (*FPD(TCharacter (*), Before)).Next = SelectedCharacter;
    }
  }
}

/* ovl15:1601. Moves SelectedCharacter one place down the party list: it changes places with the
     member after it, and the last member goes to the front. The Party Order menu's O key. */
void MoveMemberDown(void)
{
  POOL_TRACE("MoveMemberDown");
  PCharacter Before = 0;
  PCharacter After = 0;
  Before = PartyListHead;
  if (Before != SelectedCharacter) {
    while ((*FPD(TCharacter (*), Before)).Next != SelectedCharacter) {
      Before = (*FPD(TCharacter (*), Before)).Next;
    }
  }
  After = (*FPD(TCharacter (*), SelectedCharacter)).Next;
  if (After == 0) {
    (*FPD(TCharacter (*), SelectedCharacter)).Next = PartyListHead;
    PartyListHead = SelectedCharacter;
    (*FPD(TCharacter (*), Before)).Next = After;
  } else {
    (*FPD(TCharacter (*), SelectedCharacter)).Next = (*FPD(TCharacter (*), After)).Next;
    if (PartyListHead == SelectedCharacter) {
      PartyListHead = After;
    }
    if (Before != SelectedCharacter) {
      (*FPD(TCharacter (*), Before)).Next = After;
    }
    (*FPD(TCharacter (*), After)).Next = SelectedCharacter;
  }
}

/* ovl15:1780. The Party Order menu 'Party Order: ' with 'Select Exit', then 'Place Exit' once a
     character is picked (Enter, P or S toggle it: 'has been selected'). Before picking, the G and O
     keys choose another character (UpdateSelectedCharacter); after, they move the picked one up (MoveMemberUp) or
     down (MoveMemberDown). */
void PartyOrderMenu(void)
{
  POOL_TRACE("PartyOrderMenu");
  u8 Picked = 0;
  u8 ExtKey = 0;
  u8 Key = 0;
  Picked = 0;
  Key = ' ';
  while (!((Key == KeyNone_OVL15 || Key == 'E'))) {
    Key = ReadPromptChoice(S("\015Party Order: "), PartyOrderMenuTexts[Picked], TitleColor, WordColor, HotColor, 1, 1, &ExtKey);
    if (ExtKey != 0) {
      if (!Picked) {
        UpdateSelectedCharacter(Key);
        DrawPartyRoster(SelectedCharacter);
      } else {
        switch ((u8)Key) {
        case 'G':
        {
          MoveMemberUp();
          break;
        }
        case 'O':
        {
          MoveMemberDown();
          break;
        }
        }
        DrawPartyRoster(SelectedCharacter);
      }
    } else if (Key == KeyEnter_OVL15 || Key == 'P' || Key == 'S') {
      Picked = !Picked;
      if (Picked) {
        ShowCharacterMessage(SelectedCharacter, S("\021has been selected"), MessageColor, 0);
      } else {
        ClearCharacterMessage();
      }
    }
  }
}

/* ovl15:18E5. The Drop command: with only one member left it asks 'quit TO DOS: ' and quits the
     game on Yes (after removing the member, RemoveSelectedCharacter). Otherwise 'will be gone' and 'Drop from
     party? ': on Yes the member 'bids you farewell' (Flag10D set) or 'is dumped in a ditch', leaves
     the party (RemoveSelectedCharacter) and the window at columns $11..$26, rows 1..$B (the portrait) is
     cleared; on No 'Breathes A sigh of relief'. */
void DropPartyMember(void)
{
  POOL_TRACE("DropPartyMember");
  if ((((*FPD(TCharacter (*), SelectedCharacter)).Next == 0)) && ((SelectedCharacter == PartyListHead))) {
    if (AskYesNo(S("\015quit TO DOS: "), AskColor, WordColor, HotColor) == KeyYes) {
      RemoveSelectedCharacter(0, 1);
      QuitGame();
    } else {
      return;
    }
  } else {
    ShowCharacterMessage(SelectedCharacter, S("\014will be gone"), MessageColor, 0);
    if (AskYesNo(S("\021Drop from party\077 "), AskColor, WordColor, HotColor) == KeyYes) {
      if ((*FPD(TCharacter (*), SelectedCharacter)).Flag10D != 0) {
        ShowCharacterMessage(SelectedCharacter, S("\021bids you farewell"), MessageColor, 1);
      } else {
        ShowCharacterMessage(SelectedCharacter, S("\024is dumped in a ditch"), MessageColor, 1);
      }
      RemoveSelectedCharacter(0, 1);
      ClearWindow(0x11, 1, 0x26, 0xB);
      DrawPartyRoster(SelectedCharacter);
    } else {
      ShowCharacterMessage(SelectedCharacter, S("\031Breathes A sigh of relief"), MessageColor, 1);
    }
  }
}

/* ovl15:1A97. The Speed command: shows 'Game Speed = n (0=fastest 9=slowest)' and the choices
     Faster (when GameSpeed is above 0), Slower (below 9) and Exit, moves GameSpeed by one (the down
     and up keys too, kept in 0..9), until Exit. QUIRK ovl15:1BC6: the F and S keys do not test the
     bounds themselves; the prompt only offers them inside 0..9. */
void CampSpeedMenu(void)
{
  POOL_TRACE("CampSpeedMenu");
  u8 Key = 0;
  u8 ExtKey = 0;
  String40_RES06 Prompt = {0};
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  u8 t5[256];
  do {
    DrawTextAt(1, 0x12, TextColor, rtl_str_cat(t2, 3, (const u8 *const[]){S("\015Game Speed = "), ByteToText(t1, GameSpeed), S("\026 (0=fastest 9=slowest)")}));
    rtl_str_assign(Prompt, 40, S("\000"));
    if (GameSpeed > 0) {
      rtl_str_assign(Prompt, 40, rtl_str_cat(t3, 2, (const u8 *const[]){Prompt, S("\007 Faster")}));
    }
    if (GameSpeed < MaxGameSpeed) {
      rtl_str_assign(Prompt, 40, rtl_str_cat(t4, 2, (const u8 *const[]){Prompt, S("\007 Slower")}));
    }
    rtl_str_assign(Prompt, 40, rtl_str_cat(t5, 2, (const u8 *const[]){Prompt, S("\005 Exit")}));
    Key = ReadPromptChoice(S("\013Game Speed:"), Prompt, TitleColor, WordColor, HotColor, 1, 1, &ExtKey);
    if (ExtKey != 0) {
      switch ((u8)Key) {
      case 'P':
      {
        if (GameSpeed > 0) {
          GameSpeed--;
        }
        break;
      }
      case 'H':
      {
        if (GameSpeed < MaxGameSpeed) {
          GameSpeed++;
        }
        break;
      }
      }
    } else {
      switch ((u8)Key) {
      case 'F':
      {
        GameSpeed--;
        break;
      }
      case 'S':
      {
        GameSpeed++;
        break;
      }
      }
    }
  } while (!(Key == KeyNone_OVL15 || Key == 'E'));
  ClearCharacterMessage();
}

/* ovl15:1C59. The camp's Alter menu 'Order Drop Speed Icon Pics Exit' (AlterMenuText): O
     PartyOrderMenu, D DropPartyMember, S CampSpeedMenu, I EditCharacterIcon and a redraw, P the submenu that
     toggles the monster pictures (ShowMonsterPics) and the portraits (ShowPortraits). */
void AlterMenu(void)
{
  POOL_TRACE("AlterMenu");
  u8 Key = 0;
  u8 Choice = 0;
  u8 ExtKey = 0;
  String40_RES06 Prompt = {0};
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  Key = ' ';
  while (!((Key == KeyNone_OVL15 || Key == 'E'))) {
    Key = ReadPromptChoice(S("\007Alter: "), AlterMenuText, TitleColor, WordColor, HotColor, 1, 1, &ExtKey);
    if (ExtKey != 0) {
      UpdateSelectedCharacter(Key);
      DrawPartyRoster(SelectedCharacter);
    } else {
      switch ((u8)Key) {
      case 'O':
      {
        PartyOrderMenu();
        break;
      }
      case 'D':
      {
        DropPartyMember();
        break;
      }
      case 'S':
      {
        CampSpeedMenu();
        break;
      }
      case 'I':
      {
        EditCharacterIcon();
        RedrawView();
        break;
      }
      case 'P':
      {
        do {
          if (ShowMonsterPics != 0) {
            rtl_str_assign(Prompt, 40, S("\015Monsters on  "));
          } else {
            rtl_str_assign(Prompt, 40, S("\016Monsters off  "));
          }
          if (ShowPortraits != 0) {
            rtl_str_assign(Prompt, 40, rtl_str_cat(t1, 2, (const u8 *const[]){Prompt, S("\016Portraits on  ")}));
          } else {
            rtl_str_assign(Prompt, 40, rtl_str_cat(t2, 2, (const u8 *const[]){Prompt, S("\017Portraits off  ")}));
          }
          rtl_str_assign(Prompt, 40, rtl_str_cat(t3, 2, (const u8 *const[]){Prompt, S("\004Exit")}));
          Choice = ReadPromptChoice(S("\000"), Prompt, TitleColor, WordColor, HotColor, 0, 1, &ExtKey);
          switch ((u8)Choice) {
          case 'M':
          {
            ShowMonsterPics = !ShowMonsterPics;
            break;
          }
          case 'P':
          {
            ShowPortraits = !ShowPortraits;
            break;
          }
          }
        } while (!(Choice == KeyNone_OVL15 || Choice == 'E'));
        break;
      }
      }
    }
  }
}

/* ovl15:1E6F. Entry 1, called by ovl03: the party makes camp. Sets the view mode to ViewModeCamp
     (restored on leaving), clears RestHealCounter and RestTime, shows 'The party makes camp...', cancels any
     unfinished study (CancelPartyStudy, again on leaving) and runs the Camp menu 'Save View Magic
     Rest Alter Exit' (CampMenuText) until Exit or EndCamp: S saves (SaveGame) and offers 'Quit TO
     DOS ', V ViewSelectedCharacter (the view), M CampMagicMenu, R RestParty, A AlterMenu. EndCamp is set by a rest
     that ends the camp (RunRestPeriod). */
void MakeCamp(u8 (*EndCamp))
{
  POOL_TRACE("MakeCamp");
  u8 SavedMode = 0;
  u8 Key = 0;
  u8 ViewFlag = 0;
  u8 ExtKey = 0;
  SavedMode = ViewMode;
  ViewMode = ViewModeCamp;
  RestHealCounter = 0;
  rtl_FillChar((void *)&RestTime, 14, 0);
  RedrawView();
  ClearWindow(1, 0x11, 0x26, 0x16);
  DrawTextAt(1, 0x12, TextColor, S("\027The party makes camp..."));
  CancelPartyStudy();
  (*EndCamp) = 0;
  Key = ' ';
  while ((((*EndCamp) == 0)) && !((Key == KeyNone_OVL15 || Key == 'E'))) {
    Key = ReadPromptChoice(S("\006Camp: "), CampMenuText, TitleColor, WordColor, HotColor, 1, 1, &ExtKey);
    if (ExtKey != 0) {
      UpdateSelectedCharacter(Key);
      DrawPartyRoster(SelectedCharacter);
    } else {
      switch ((u8)Key) {
      case 'S':
      {
        SaveGame();
        if (AskYesNo(S("\014Quit TO DOS "), AskColor, WordColor, HotColor) == KeyYes) {
          QuitGame();
        }
        break;
      }
      case 'V':
      {
        ViewSelectedCharacter(&ViewFlag);
        break;
      }
      case 'M':
      {
        CampMagicMenu(&(*EndCamp));
        break;
      }
      case 'R':
      {
        RestParty(&(*EndCamp));
        break;
      }
      case 'A':
      {
        AlterMenu();
        break;
      }
      }
    }
  }
  CancelPartyStudy();
  PickedSpellCharacter = 0;
  ViewMode = SavedMode;
  DrawLocationLine();
  ClearCharacterMessage();
  ClearPromptLine();
}

/* Initialisation part of unit OVL15. */
void init_OVL15(void)
{
  POOL_TRACE("init");
}
