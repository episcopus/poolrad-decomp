#include "game.h"

/* ovl05:0000. Computes the experience each character gets for the battle and gathers the loot.
     In a duel with VarFixedXpBattle set, Xp is 100 per level (HighestLevel) of SelectedCharacter.
     Otherwise every monster (Side 1) that did not flee adds its money to PooledMoney, its XpValue plus
     HpB1 times XpPerHp to the total, and, unless VarNoItemLoot is 1, its items as clones to the loot
     list PooledItems (FormatItemLine first): every item with a Value, but worthless items only while fewer
     than 8 items were taken and with a 1d10 of 3 or less. Then the pooled money adds its value
     (copper / 200 ... jewels * 2200) and each looted item before LootListBoundary adds 400 per point of Plus.
     Xp is the total divided by the party size (VarPartySize) less NoExperienceCount. Sets
     MonstersLooted when a monster was looted. QUIRK ovl05:002B: the level product is an Integer
     multiplication extended to LongInt. */
void ComputeBattleExperience(s32 (*Xp))
{
  PCharacter Who = 0;
  s8 Kind = 0;
  s32 Total = 0;
  PMenuLine Entry = 0;
  PMenuLine Item = 0;
  u8 Taken = 0;
  if (((DuelMode != 0)) && (((*FPD(TGameVars (*), GameVars2))[742] != 0))) {
    (*Xp) = (s16)((*FPD(TCharacter (*), SelectedCharacter)).HighestLevel * XpPerLevel);
  } else {
    Total = 0;
    Who = PartyListHead;
    Taken = 0;
    while (Who != 0) {
      Item = (*FPD(TCharacter (*), Who)).Items;
      if ((((*FPD(TCharacter (*), Who)).Side == SideMonsters)) && (((*FPD(TCharacter (*), Who)).Status != StatusFled))) {
        MonstersLooted = 1;
        Kind = 0;
        if (Kind <= LastMoneyKind_OVL05) for (;;) {
          PooledMoney[Kind] += (*FPD(TCharacter (*), Who)).Money[Kind];
          if (Kind == LastMoneyKind_OVL05) break;
          Kind++;
        }
        Total = ((*FPD(TCharacter (*), Who)).XpValue + Total) + ((*FPD(TCharacter (*), Who)).XpPerHp * (*FPD(TCharacter (*), Who)).HpB1);
        if ((*FPD(TGameVars (*), GameVars2))[739] != 1) {
          while (Item != 0) {
            if ((((*FPD(TMenuLine (*), Item)).Value > 0)) || ((((Taken < MaxWorthlessItems)) && ((RollDice(1, 10) <= WorthlessItemChance))))) {
              Taken++;
              if (PooledItems == 0) {
                PooledItems = rtl_getmem(63);
                FormatItemLine((s32)Who, Item, 0, 0, 0, 0);
                (*FPD(TMenuLine (*), PooledItems)) = (*FPD(TMenuLine (*), Item));
                (*FPD(TMenuLine (*), PooledItems)).Readied = 0;
                (*FPD(TMenuLine (*), PooledItems)).Next = 0;
              } else {
                Entry = PooledItems;
                PooledItems = rtl_getmem(63);
                FormatItemLine((s32)Who, Item, 0, 0, 0, 0);
                (*FPD(TMenuLine (*), PooledItems)) = (*FPD(TMenuLine (*), Item));
                (*FPD(TMenuLine (*), PooledItems)).Readied = 0;
                (*FPD(TMenuLine (*), PooledItems)).Next = Entry;
              }
            }
            Item = (*FPD(TMenuLine (*), Item)).Next;
          }
        }
      }
      Who = (*FPD(TCharacter (*), Who)).Next;
    }
    Total += (PooledMoney[0] / CopperPerXp);
    Total += (PooledMoney[1] / SilverPerXp);
    Total += (PooledMoney[2] / ElectrumPerXp);
    Total += PooledMoney[3];
    Total += PooledMoney[4] * XpPerPlatinum;
    Total += PooledMoney[5] * XpPerGem;
    Total += PooledMoney[6] * XpPerJewel;
    Entry = PooledItems;
    while (((Entry != 0)) && ((Entry != LootListBoundary))) {
      if ((*FPD(TMenuLine (*), Entry)).Plus > 0) {
        Total += (s16)((*FPD(TMenuLine (*), Entry)).Plus * XpPerPlus);
      }
      Entry = (*FPD(TMenuLine (*), Entry)).Next;
    }
    (*Xp) = (Total / ((u16)((*FPD(TGameVars (*), GameVars2))[830] - NoExperienceCount)));
  }
}

/* ovl05:0355. Adds Xp to the Experience of every member of the party list (PartyListHead) that has Flag10D
     set and is not dead: 10% more for a cleric, fighter, magic-user or thief whose prime requisite
     (Wisdom, Strength, Intelligence, Dexterity) is above 15, half for the two-class combinations and
     a third for the three-class ones (ClassCombo 8, 10..14, 16 and 9, 15). */
void AwardExperience(s32 Xp)
{
  PCharacter Who = 0;
  s32 Gain = 0;
  Who = PartyListHead;
  while (Who != 0) {
    if ((((*FPD(TCharacter (*), Who)).Flag10D != 0)) && (((*FPD(TCharacter (*), Who)).Status != StatusAnimated))) {
      Gain = Xp;
      switch ((*FPD(TCharacter (*), Who)).ClassCombo) {
      case ClassCleric:
      {
        if ((*FPD(TCharacter (*), Who)).Wisdom > PrimeRequisiteBonus) {
          Gain = (Xp / 10) + Xp;
        }
        break;
      }
      case ClassFighter:
      {
        if ((*FPD(TCharacter (*), Who)).Strength > PrimeRequisiteBonus) {
          Gain = (Xp / 10) + Xp;
        }
        break;
      }
      case ClassMagicUser:
      {
        if ((*FPD(TCharacter (*), Who)).Intelligence > PrimeRequisiteBonus) {
          Gain = (Xp / 10) + Xp;
        }
        break;
      }
      case ClassThief:
      {
        if ((*FPD(TCharacter (*), Who)).Dexterity > PrimeRequisiteBonus) {
          Gain = (Xp / 10) + Xp;
        }
        break;
      }
      case 8:
      case 10:
      case 11:
      case 12:
      case 13:
      case 14:
      case 16:
      {
        Gain = (Xp / 2);
        break;
      }
      case 9:
      case 15:
      {
        Gain = (Xp / 3);
        break;
      }
      }
      (*FPD(TCharacter (*), Who)).Experience += Gain;
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
}

/* ovl05:04C9. Decides how the battle ended and applies it to the party list (PartyListHead); the walks stop
     at the first extra combatant (TCombatant.NoBody = 1). PartyFled is set when a member has fled
     (Status 3). In a battle (not DuelMode): PartyDestroyed stays 1 unless a player-run member (Side 0,
     B84 below $80) is okay, dead or fled (or VarFixedXpBattle is 1); BattleWon is set and PartyFled
     cleared when a combatant is okay or dead; NoExperienceCount counts the members without Flag10D or
     dead. A won battle computes and awards BattleExperience. A surviving party gets its fled members
     back (Status 0, Flag10D 1), dying ones unconscious, unconscious ones with HpCurrent back to okay; a
     fled party (VarBattleOutcome $81) keeps only its fled members, the others leave the list
     (RemoveSelectedCharacter). A destroyed party leaves the list entirely and VarPartySize becomes 0. In a duel the
     duelist (Flag10D 1, okay, not a monster) wins the experience, every okay or dead combatant gets
     Flag10D and the dying become unconscious. */
void SettleBattleOutcome(void)
{
  PCharacter Who = 0;
  u8 Stop = 0;
  u8 Unused = 0;
  NoExperienceCount = 0;
  PartyDestroyed = 1;
  PartyFled = 0;
  Who = PartyListHead;
  while (((Who != 0)) && (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).NoBody != ExtraCombatant))) {
    if ((*FPD(TCharacter (*), Who)).Status == StatusFled) {
      PartyFled = 1;
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  if (DuelMode != 0) {
    PartyDestroyed = 0;
  }
  BattleWon = 0;
  Who = PartyListHead;
  if (DuelMode == 0) {
    while (((Who != 0)) && (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).NoBody != ExtraCombatant))) {
      if (((((((((*FPD(TCharacter (*), Who)).Status == StatusFled)) || (((*FPD(TCharacter (*), Who)).Status == StatusAnimated))) || (((*FPD(TCharacter (*), Who)).Status == StatusOkay))) || (((*FPD(TGameVars (*), GameVars2))[742] == 1)))) && (((*FPD(TCharacter (*), Who)).Side == SideParty))) && (((*FPD(TCharacter (*), Who)).B84 < ComputerRun))) {
        PartyDestroyed = 0;
      }
      if ((((*FPD(TCharacter (*), Who)).Status == StatusAnimated)) || (((*FPD(TCharacter (*), Who)).Status == StatusOkay))) {
        BattleWon = 1;
        PartyFled = 0;
      }
      if ((((*FPD(TCharacter (*), Who)).Flag10D == 0)) || (((*FPD(TCharacter (*), Who)).Status == StatusAnimated))) {
        NoExperienceCount++;
      }
      Who = (*FPD(TCharacter (*), Who)).Next;
    }
    if (BattleWon != 0) {
      ComputeBattleExperience(&BattleExperience);
      AwardExperience(BattleExperience);
    }
    Who = PartyListHead;
    if (PartyDestroyed == 0) {
      while (((Who != 0)) && (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).NoBody != ExtraCombatant))) {
        if (PartyFled == 0) {
          switch ((*FPD(TCharacter (*), Who)).Status) {
          case StatusFled:
          {
            (*FPD(TCharacter (*), Who)).Status = StatusOkay;
            (*FPD(TCharacter (*), Who)).Flag10D = 1;
            break;
          }
          case StatusDying:
          {
            (*FPD(TCharacter (*), Who)).Status = StatusUnconscious;
            break;
          }
          case StatusUnconscious:
          {
            if ((*FPD(TCharacter (*), Who)).HpCurrent > 0) {
              (*FPD(TCharacter (*), Who)).Status = StatusOkay;
              (*FPD(TCharacter (*), Who)).Flag10D = 1;
            }
            break;
          }
          }
        } else {
          (*FPD(TGameVars (*), GameVars2))[711] = BattleOutcomeFled;
          if ((*FPD(TCharacter (*), Who)).Status == StatusFled) {
            (*FPD(TCharacter (*), Who)).Status = StatusOkay;
            (*FPD(TCharacter (*), Who)).Flag10D = 1;
          } else {
            SelectedCharacter = Who;
            RemoveSelectedCharacter(0, 1);
          }
        }
        Who = (*FPD(TCharacter (*), Who)).Next;
      }
    } else {
      Who = PartyListHead;
      Stop = 0;
      while (((Who != 0)) && !Stop) {
        if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).NoBody != ExtraCombatant) {
          SelectedCharacter = Who;
          RemoveSelectedCharacter(0, 1);
        } else {
          Stop = 1;
        }
        Who = (*FPD(TCharacter (*), Who)).Next;
      }
      (*FPD(TGameVars (*), GameVars2))[830] = 0;
    }
  } else {
    Who = PartyListHead;
    while (Who != 0) {
      if (((((*FPD(TCharacter (*), Who)).Flag10D == 1)) && (((*FPD(TCharacter (*), Who)).Status == StatusOkay))) && (((*FPD(TCharacter (*), Who)).Side != SideMonsters))) {
        BattleWon = 1;
        ComputeBattleExperience(&BattleExperience);
        AwardExperience(BattleExperience);
      }
      Who = (*FPD(TCharacter (*), Who)).Next;
    }
    Who = PartyListHead;
    while (Who != 0) {
      if ((((*FPD(TCharacter (*), Who)).Status == StatusOkay)) || (((*FPD(TCharacter (*), Who)).Status == StatusAnimated))) {
        (*FPD(TCharacter (*), Who)).Flag10D = 1;
      }
      if ((*FPD(TCharacter (*), Who)).Status == StatusDying) {
        (*FPD(TCharacter (*), Who)).Status = StatusUnconscious;
      }
      Who = (*FPD(TCharacter (*), Who)).Next;
    }
  }
}

/* ovl05:0916. Shows the result of the battle in a window: 'You have lost the duel.' (and no
     experience), 'You have won the duel.' or 'The party has won.' when MonstersLooted or DuelMode,
     else 'The party has fled.' (no experience) or 'The party has found Treasure!'; then 'The duelist
     receives <Xp>' or 'Each character receives <Xp>', 'experience points.', and waits for Enter. */
void ShowBattleResult(s32 Xp)
{
  u8 XpText[11] = {0};
  u8 Line[256] = {0};
  u8 Key = 0;
  u8 Title[2] = {0};
  u8 ExtKey = 0;
  u8 t1[256];
  u8 t2[256];
  rtl_str_assign(Title, 1, S("\000"));
  DrawWindow(1, 1, 0x26, 0x16, 0, 0xF, S("\000"));
  if (((MonstersLooted != 0)) || ((DuelMode != 0))) {
    if (((DuelMode != 0)) && ((BattleWon == 0))) {
      DrawTextAt(1, 3, 0xA, S("\027You have lost the duel."));
      Xp = 0;
    } else if (DuelMode != 0) {
      DrawTextAt(1, 3, 0xA, S("\026You have won the duel."));
    } else {
      DrawTextAt(1, 3, 0xA, S("\022The party has won."));
    }
  } else if (PartyFled != 0) {
    DrawTextAt(1, 3, 0xA, S("\023The party has fled."));
    Xp = 0;
  } else {
    DrawTextAt(1, 3, 0xA, S("\035The party has found Treasure!"));
  }
  rtl_str_int(XpText, 10, Xp, 0);
  if (DuelMode != 0) {
    rtl_str_assign(Line, 255, rtl_str_cat(t1, 2, (const u8 *const[]){S("\025The duelist receives "), XpText}));
  } else {
    rtl_str_assign(Line, 255, rtl_str_cat(t2, 2, (const u8 *const[]){S("\030Each character receives "), XpText}));
  }
  DrawTextAt(1, 5, 0xA, Line);
  DrawTextAt(1, 7, 0xA, S("\022experience points."));
  Key = ReadPromptChoice(Title, S("\"press <enter>/<return> to continue"), 15, 15, 15, 1, 0, &ExtKey);
}

/* ovl05:0B14. Draws the 'Loot' window, prepares every entry of the loot list PooledItems for display
     (FormatItemLine) and lets the player pick one (ChooseFromList, 'Items: ' with a 'Take' button).
     Key is the key of the choice, Item the chosen entry; Selected and Choice carry the list
     position between calls. */
void ChooseLootItem(u8 (*Key), PMenuLine (*Item), PMenuLine (*Selected), s16 (*Choice))
{
  PMenuLine List = 0;
  u8 Unused[19] = {0};
  u8 Redraw = 0;
  PMenuLine Entry = 0;
  Redraw = 1;
  DrawWindow(1, 1, 0x26, 0x16, 0, 0xF, S("\004Loot"));
  Entry = PooledItems;
  while (Entry != 0) {
    FormatItemLine(0, Entry, 0, 0, 0, 0);
    Entry = (*FPD(TMenuLine (*), Entry)).Next;
  }
  List = PooledItems;
  (*Key) = ChooseFromList(S("\007Items: "), S("\004Take"), 13, 10, 15, 1, 4, 0x26, 0x16, List, 1, &Redraw, &(*Choice), &(*Selected));
  (*Item) = (*Selected);
}

/* ovl05:0C06. Lets the player take items from the loot list PooledItems until another key than Take or
     Enter is pressed or the list is empty: the chosen item goes to SelectedCharacter
     (AddInventoryItem) and, unless the character is overloaded, is unlinked from the loot and freed.
     Redraws the screen (RedrawView) at the end. */
void TakeLootItems(void)
{
  PMenuLine Chosen = 0;
  PMenuLine Prev = 0;
  u8 Key = 0;
  u8 Done = 0;
  PMenuLine Selected = 0;
  s16 Choice = 0;
  u8 Overloaded = 0;
  Chosen = 0;
  Selected = PooledItems;
  Choice = 0;
  do {
    ChooseLootItem(&Key, &Chosen, &Selected, &Choice);
    if (((Key != 'T')) && ((Key != KeyEnter_OVL05))) {
      Done = 1;
    } else {
      Done = 0;
      AddInventoryItem(Chosen, &Overloaded);
      if (Overloaded == 0) {
        Prev = PooledItems;
        if (Prev == Chosen) {
          PooledItems = (*FPD(TMenuLine (*), Chosen)).Next;
        } else {
          while ((*FPD(TMenuLine (*), Prev)).Next != Chosen) {
            Prev = (*FPD(TMenuLine (*), Prev)).Next;
          }
          (*FPD(TMenuLine (*), Prev)).Next = (*FPD(TMenuLine (*), Chosen)).Next;
        }
        (*FPD(TMenuLine (*), Chosen)).Next = 0;
        if (Chosen != 0) {
          rtl_freemem(Chosen, ItemListSize);
        }
        if (PooledItems == 0) {
          Done = 1;
        }
      }
    }
  } while (!(Done));
  RedrawView();
}

/* ovl05:0D38. The Take command of the treasure menu. MoneyLeft and ItemsLeft are TreasureLeft's two
     results (money in the pool, items in the loot). With only items it goes to TakeLootItems, with
     only money it takes the money (TakeMoney); with both it loops on 'Take: Money Items Exit' until
     Exit or one of them runs out (G and O, in no menu text, go to UpdateSelectedCharacter as in the shop). */
void TakeTreasure(u8 (*MoneyLeft), u8 (*ItemsLeft))
{
  u8 Key = 0;
  u8 Done = 0;
  u8 ExtKey = 0;
  Done = 0;
  if ((*MoneyLeft) != 0) {
    if ((*ItemsLeft) != 0) {
      do {
        Key = ReadPromptChoice(S("\006Take: "), S("\020Money Items Exit"), 13, 10, 15, 1, 1, &ExtKey);
        switch ((u8)Key) {
        case 'M':
        {
          TakeMoney();
          RedrawView();
          break;
        }
        case 'I':
        {
          TakeLootItems();
          break;
        }
        case 'E':
        case 0x00:
        {
          Done = 1;
          break;
        }
        case 'G':
        {
          UpdateSelectedCharacter(Key);
          break;
        }
        case 'O':
        {
          UpdateSelectedCharacter(Key);
          break;
        }
        }
        DrawPartyRoster(SelectedCharacter);
        TreasureLeft(&(*MoneyLeft), &(*ItemsLeft));
        if ((((*MoneyLeft) == 0)) || (((*ItemsLeft) == 0))) {
          Done = 1;
        }
      } while (!(Done));
    } else {
      TakeMoney();
      RedrawView();
    }
  } else {
    TakeLootItems();
  }
}

/* ovl05:0ECD. The treasure menu after a won battle: 'View Pool Exit', with Take while there is loot
     and Share while there is pooled money, and Detect when SelectedCharacter has Detect Magic
     memorized and there are items (Detect casts it through CastChosenSpell). V views (ViewSelectedCharacter), T takes
     (TakeTreasure), P pools (PoolMoney) when the key flag is clear, S shares (ShareMoney). Exit with
     treasure left asks 'There is still treasure left.  Do you want to go back and claim your
     treasure?' and leaves on No. */
void TreasureMenu(void)
{
  u8 MoneyLeft = 0;
  u8 ItemsLeft = 0;
  u8 Unused = 0;
  u8 Menu[256] = {0};
  u8 Key = 0;
  u8 Done = 0;
  u8 ExtKey = 0;
  u8 Title[2] = {0};
  u8 Answer = 0;
  u8 Slot = 0;
  u8 DetectSpell = 0;
  u8 HasDetect = 0;
  u8 ExitText[14] = {0};
  u8 t1[256];
  u8 t2[256];
  rtl_str_assign(Title, 1, S("\000"));
  Done = 0;
  RedrawView();
  MoneyLeft = 0;
  do {
    TreasureLeft(&MoneyLeft, &ItemsLeft);
    rtl_str_assign(Menu, 255, S("\016View Pool Exit"));
    Slot = 0;
    rtl_str_assign(ExitText, 13, S("\005 Exit"));
    HasDetect = 0;
    if (ItemsLeft != 0) {
      while (((Slot <= LastSpellSlot)) && !HasDetect) {
        if ((((*FPD(TCharacter (*), SelectedCharacter)).Spells[Slot] == SpellClericDetectMagic)) || (((*FPD(TCharacter (*), SelectedCharacter)).Spells[Slot] == SpellMageDetectMagic))) {
          HasDetect = 1;
          DetectSpell = (*FPD(TCharacter (*), SelectedCharacter)).Spells[Slot];
        }
        Slot++;
      }
    }
    if (HasDetect) {
      rtl_str_assign(ExitText, 13, S("\014 Detect Exit"));
    }
    if (MoneyLeft != 0) {
      rtl_str_assign(Menu, 255, rtl_str_cat(t1, 2, (const u8 *const[]){S("\024View Take Pool Share"), ExitText}));
    } else if (ItemsLeft != 0) {
      rtl_str_assign(Menu, 255, rtl_str_cat(t2, 2, (const u8 *const[]){S("\016View Take Pool"), ExitText}));
    }
    Key = ReadPromptChoice(Title, Menu, 13, 10, 15, 1, 1, &ExtKey);
    switch ((u8)Key) {
    case 'V':
    {
      ViewSelectedCharacter(&ExtKey);
      break;
    }
    case 'T':
    {
      TakeTreasure(&MoneyLeft, &ItemsLeft);
      break;
    }
    case 'P':
    {
      if (ExtKey == 0) {
        PoolMoney();
      }
      break;
    }
    case 'S':
    {
      ShareMoney();
      break;
    }
    case 'D':
    {
      CastChosenSpell(DetectSpell, 0, 0, &ExtKey);
      break;
    }
    case 'E':
    case 0x00:
    {
      TreasureLeft(&MoneyLeft, &ItemsLeft);
      if (((MoneyLeft != 0)) || ((ItemsLeft != 0))) {
        rtl_str_assign(Menu, 255, S("\010~Yes ~No"));
        ShowPagedText(1, 0x11, 0x26, 0x16, 0xA, 1, S("\037There is still treasure left.  "));
        ShowPagedText(1, 0x11, 0x26, 0x16, 0xF, 0, S("/Do you want to go back and claim your treasure\077"));
        Answer = AskMenu(Title, Menu, 13, 10, 15, 0, 0);
        if (Answer == AnswerNo) {
          Done = 1;
        } else {
          ClearRect(1, 0x11, 0x26, 0x16);
        }
      } else {
        Done = 1;
      }
      break;
    }
    case 'G':
    {
      UpdateSelectedCharacter(Key);
      DrawPartyRoster(SelectedCharacter);
      break;
    }
    case 'O':
    {
      UpdateSelectedCharacter(Key);
      DrawPartyRoster(SelectedCharacter);
      break;
    }
    }
  } while (!(Done));
}

/* ovl05:11AC. Takes the monsters (Side 1) and the extra combatants (TCombatant.NoBody = 1) out of the
     party list (RemoveSelectedCharacter on SelectedCharacter; an extra combatant does not lower VarPartySize) and
     counts in VarRemovedCount the removed ones whose Flag10D is not 1; the remaining members' combat
     state is freed. SelectedCharacter is the first member afterwards. */
void RemoveBattleCombatants(void)
{
  PCharacter Who = 0;
  PCharacter NextWho = 0;
  (*FPD(TGameVars (*), GameVars2))[712] = 0;
  Who = PartyListHead;
  while (Who != 0) {
    if ((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).NoBody == ExtraCombatant)) || (((*FPD(TCharacter (*), Who)).Side == SideMonsters))) {
      if ((*FPD(TCharacter (*), Who)).Flag10D != 1) {
        (*FPD(TGameVars (*), GameVars2))[712]++;
      }
      NextWho = (*FPD(TCharacter (*), Who)).Next;
      SelectedCharacter = Who;
      RemoveSelectedCharacter(((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).NoBody == ExtraCombatant), 1);
      Who = NextWho;
    } else {
      if ((*FPD(TCharacter (*), Who)).Combat != 0) {
        rtl_freemem((*FPD(TCharacter (*), Who)).Combat, CombatStateSize);
        (*FPD(TCharacter (*), Who)).Combat = 0;
      }
      Who = (*FPD(TCharacter (*), Who)).Next;
    }
  }
  SelectedCharacter = PartyListHead;
}

/* ovl05:12E8. The hirelings' share: every okay member the player does not run (B84 $80 and up) has
     HirelingShare and 7 shares, every other member one. When hirelings have shares, each kind of
     pooled money above 0 loses the hirelings' part (PooledMoney div all shares, as a Byte, times the
     hirelings' shares) and a window lists '<name> takes and hides his share.' for each hireling.
     QUIRK ovl05:13A5: the share of one kind is truncated to a Byte. */
void TakeHirelingShares(void)
{
  PCharacter Who = 0;
  u8 HirelingShares = 0;
  u8 TotalShares = 0;
  u8 Share = 0;
  u8 Row = 0;
  s8 Kind = 0;
  u8 Unused[9] = {0};
  u8 Taken = 0;
  u8 ExtKey = 0;
  u8 Key = 0;
  u8 t1[256];
  Taken = 0;
  Who = PartyListHead;
  HirelingShares = 0;
  TotalShares = 0;
  while (Who != 0) {
    if ((((*FPD(TCharacter (*), Who)).B84 > 127)) && (((*FPD(TCharacter (*), Who)).Status == StatusOkay))) {
      HirelingShares += ((*FPD(TCharacter (*), Who)).HirelingShare & ShareMask);
      TotalShares += ((*FPD(TCharacter (*), Who)).HirelingShare & ShareMask);
    } else {
      TotalShares++;
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  if (HirelingShares > 0) {
    Kind = 0;
    if (Kind <= LastMoneyKind_OVL05) for (;;) {
      if (PooledMoney[Kind] > 0) {
        Share = (PooledMoney[Kind] / TotalShares);
        PooledMoney[Kind] -= (s16)(HirelingShares * Share);
        Taken = 1;
      }
      if (Kind == LastMoneyKind_OVL05) break;
      Kind++;
    }
  }
  if (Taken) {
    DrawWindow(1, 1, 0x26, 0x16, 0, 0xF, S("\000"));
    Who = PartyListHead;
    Row = 0;
    while (Who != 0) {
      if (((((*FPD(TCharacter (*), Who)).B84 > 127)) && (((*FPD(TCharacter (*), Who)).Status == StatusOkay))) && (((*FPD(TCharacter (*), Who)).HirelingShare > 0))) {
        ShowPagedText(5, (s16)(Row + 5), 0x22, 0x16, 0xA, 1, rtl_str_cat(t1, 2, (const u8 *const[]){(*FPD(TCharacter (*), Who)).Name, S("\033 takes and hides his share.")}));
        Row += 2;
      }
      Who = (*FPD(TCharacter (*), Who)).Next;
    }
    Key = ReadPromptChoice(S("\000"), S("\"press <enter>/<return> to continue"), 15, 15, 15, 1, 0, &ExtKey);
  }
}

/* ovl05:1527 (e1). The end of a battle: clears VarBattleOutcome and MonstersLooted, sets the view
     mode ViewMode to 6, settles the outcome and removes the monsters. While the party lives (or in a
     duel) the hirelings take their share, the result is shown, the treasure menu runs and the loot
     left in PooledItems is freed. A destroyed party gets VarBattleOutcome $80, 'The END!' and 'The monsters
     rejoice for the party has been destroyed'. Then sets DelayPerGlyph and clears VarAfterBattle1..3,
     VarNoItemLoot and VarFixedXpBattle. */
void EndBattle(void)
{
  PMenuLine Entry = 0;
  PMenuLine Doomed = 0;
  (*FPD(TGameVars (*), GameVars2))[711] = 0;
  MonstersLooted = 0;
  ViewMode = 6;
  SettleBattleOutcome();
  RemoveBattleCombatants();
  if (((PartyDestroyed == 0)) || ((DuelMode != 0))) {
    TakeHirelingShares();
    ShowBattleResult(BattleExperience);
    TreasureMenu();
    Entry = PooledItems;
    while (Entry != 0) {
      Doomed = Entry;
      Entry = (*FPD(TMenuLine (*), Entry)).Next;
      rtl_freemem(Doomed, ItemListSize);
    }
    PooledItems = 0;
  } else {
    (*FPD(TGameVars (*), GameVars2))[711] = BattleOutcomeDestroyed;
    DrawWindow(1, 1, 0x26, 0x16, 0, 0xF, S("\010The END!"));
    GlyphCol = 2;
    GlyphRow = 6;
    ShowPagedText(2, 5, 0x25, 0x16, 0xA, 1, S("5The monsters rejoice for the party has been destroyed"));
    ShowMessageLine(0xD, S("\031Press any key to continue"));
  }
  DelayPerGlyph = 1;
  (*FPD(TGameVars (*), GameVars2))[880] = 0;
  (*FPD(TGameVars (*), GameVars2))[881] = 0;
  (*FPD(TGameVars (*), GameVars2))[882] = 0;
  (*FPD(TGameVars (*), GameVars2))[739] = 0;
  (*FPD(TGameVars (*), GameVars2))[742] = 0;
}

/* Initialisation part of unit OVL05. */
void init_OVL05(void)
{
  /* ovl05:1671. The unit's initialisation part is empty (push bp; mov bp, sp; pop bp; retf). */
}
