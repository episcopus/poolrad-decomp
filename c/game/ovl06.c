#include "game.h"

/* ovl06:0030 (ChooseShopItem). Builds the shop window and the item picker. Walks the stock list at
     PooledItems and rewrites each entry's Text into a 30-character field with the item name on the left
     and its Value (the price, +$3A) right-justified (a zero Value becomes 1, ovl06:0068), then draws
     the "Shop" window (DrawWindow) and runs the item picker ChooseFromList titled "Items: " with a "Buy"
     button. Action receives the picker's key, Head the chosen entry, Selected is set to Head;
     FormatItemLine is called for each entry afterwards. Parameters: Action (out, the key), Selected
     (out, the chosen entry), Head (in/out, the list the picker works on), Choice (in/out, the
     picker's position, ChooseFromList's Choice). Side effect: the screen (and the stock entries' Text and
     Value). Called from BuyItems (Buy). */
void ChooseShopItem(u8 (*Action), PMenuLine (*Selected), PMenuLine (*Head), s16 (*Choice))
{
  POOL_TRACE("ChooseShopItem");
  PMenuLine List = 0;
  PMenuLine Entry = 0;
  u8 NumStr[17] = {0};
  u8 Field[31] = {0};
  u8 N = 0;
  u8 I = 0;
  u8 MenuFlag = 0;
  MenuFlag = 1;
  Entry = PooledItems;
  while (Entry != 0) {
    rtl_str_assign(Field, 30, S("\036                              "));
    if ((*FPD(TMenuLine (*), Entry)).Value == 0) {
      (*FPD(TMenuLine (*), Entry)).Value = 1;
    }
    rtl_str_int(NumStr, 16, (*FPD(TMenuLine (*), Entry)).Value, 0);
    N = NumStr[0];
    {
      u8 limit = N;
      if (1 <= limit) {
        I = 1;
        for (;;) {
            Field[(s16)((30 - N) + I)] = NumStr[I];
          if (I == limit) break;
          I++;
        }
      }
    }
    N = (*FPD(TMenuLine (*), Entry)).Text[0];
    {
      u8 limit = N;
      if (1 <= limit) {
        I = 1;
        for (;;) {
            Field[I] = (*FPD(TMenuLine (*), Entry)).Text[I];
          if (I == limit) break;
          I++;
        }
      }
    }
    rtl_str_assign((*FPD(TMenuLine (*), Entry)).Text, 40, Field);
    /* QUIRK ovl06:012B: the length is set again although the assignment above already set it to 30 */
    (*FPD(TMenuLine (*), Entry)).Text[0] = 0x1E;
    Entry = (*FPD(TMenuLine (*), Entry)).Next;
  }
  DrawWindow(1, 1, 0x26, 0x16, 0, 0xF, S("\004Shop"));
  List = PooledItems;
  (*Action) = ChooseFromList(S("\007Items: "), S("\003Buy"), 0xD, 0xA, 0xF, 1, 4, 0x26, 0x16, List, 1, &MenuFlag, &(*Choice), &(*Head));
  (*Selected) = (*Head);
  Entry = PooledItems;
  while (Entry != 0) {
    FormatItemLine(0, Entry, 0, 0, 0, 0);
    Entry = (*FPD(TMenuLine (*), Entry)).Next;
  }
}

/* ovl06:0239 (AddInventoryItem). Appends a clone of Item to the list at SelectedCharacter^.Items
     while the inventory has room. WouldOverloadInventory (Inventory) checks the list against the item and returns
     True when it is overloaded: Overloaded is then 1 and "OverLoaded" is shown. Otherwise Overloaded is
     0 and a new TMenuLine is allocated (New), the item copied into it (record assignment of $3F bytes)
     and the node linked at the end of SelectedCharacter^.Items; RecalcCombatValues then redraws the list.
     Item is the entry to add; Overloaded receives 1 when the item was refused (ovl06:026D) and 0 when
     it was added (ovl06:0277). Called from ovl05 (TreasureShare) and BuyItems (Buy). */
void AddInventoryItem(PMenuLine Item, u8 (*Overloaded))
{
  POOL_TRACE("AddInventoryItem");
  PMenuLine Tail = 0;
  PMenuLine NewItem = 0;
  if (WouldOverloadInventory(SelectedCharacter, Item)) {
    ShowFlashMessage(S("\012OverLoaded"));
    (*Overloaded) = 1;
  } else {
    (*Overloaded) = 0;
    Tail = (*FPD(TCharacter (*), SelectedCharacter)).Items;
    if (Tail == 0) {
      Tail = rtl_getmem(63);
      (*FPD(TMenuLine (*), Tail)) = (*FPD(TMenuLine (*), Item));
      (*FPD(TMenuLine (*), Tail)).Next = 0;
      (*FPD(TCharacter (*), SelectedCharacter)).Items = Tail;
    } else {
      while ((*FPD(TMenuLine (*), Tail)).Next != 0) {
        Tail = (*FPD(TMenuLine (*), Tail)).Next;
      }
      NewItem = rtl_getmem(63);
      (*FPD(TMenuLine (*), NewItem)) = (*FPD(TMenuLine (*), Item));
      (*FPD(TMenuLine (*), NewItem)).Next = 0;
      (*FPD(TMenuLine (*), Tail)).Next = NewItem;
    }
    RecalcCombatValues(SelectedCharacter);
  }
}

/* ovl06:0361 (BuyItems). The shop's Buy flow, called from ShopMain on the 'B' menu key. It loops on
     ChooseShopItem until the player cancels (any key other than 'B' or Enter). For a chosen entry the
     Price is its Value (+$3A, ovl06:0361). It first reads the selected character's money
     (CharacterMoneyValueInGold); if the Price fits it adds the item to the character's items (AddInventoryItem) and,
     when that worked, stores the money less the Price (SetCharacterGold). Otherwise it reads the money pooled
     in the shop (MoneyValueInGold on PooledMoney); if the Price fits it adds the item and stores the pool less the
     Price (SetPooledGold), else it shows "Not enough Money." (ShowFlashMessage). No parameters; side effects:
     the character's items, the money and the screen.
     QUIRK ovl06:03C7: CharacterMoneyValueInGold returns a LongInt, but Money is a Word, so only AX is kept and a
     character with 65536 or more is compared and charged modulo 65536 (a price can fit when only the
     low word does, or the pool pays when it does not, and SetCharacterGold then stores the low word less the
     price, ovl06:03E7..03F3). QUIRK ovl06:0449: the pool path computes Pooled - Price as a LongInt
     (ovl06:0430..0446) but SetPooledGold(Amount: Word) receives only the low word, so a pool above 65535
     is rewritten with the truncated amount (the same truncations as ovl04's ChargeForCure). */
void BuyItems(void)
{
  POOL_TRACE("BuyItems");
  PMenuLine Selected = 0;
  u8 Action = 0;
  u8 Cancelled = 0;
  u16 Price = 0;
  u16 Money = 0;
  s32 Pooled = 0;
  u8 Overloaded = 0;
  PMenuLine Head = 0;
  s16 Choice = 0;
  Selected = 0;
  Head = PooledItems;
  Choice = 1;
  do {
    ChooseShopItem(&Action, &Selected, &Head, &Choice);
    if (((Action != 'B')) && ((Action != 0x0D))) {
      Cancelled = 1;
    } else {
      Cancelled = 0;
      Price = (*FPD(TMenuLine (*), Selected)).Value;
      Money = CharacterMoneyValueInGold(SelectedCharacter);
      if (Price <= Money) {
        AddInventoryItem(Selected, &Overloaded);
        if (Overloaded == 0) {
          Money = Money - Price;
          SetCharacterGold(Money);
        }
      } else {
        Pooled = MoneyValueInGold(&PooledMoney);
        if (Price <= Pooled) {
          AddInventoryItem(Selected, &Overloaded);
          if (Overloaded == 0) {
            Pooled = Pooled - Price;
            SetPooledGold(Pooled);
          }
        } else {
          ShowFlashMessage(S("\021Not enough Money."));
        }
      }
    }
  } while (!(Cancelled));
}

/* ovl06:053E (ShopMain). The shop's entry and main loop, called from ovl03 (the area logic) when the
     party enters a shop. It marks the shop open (ViewMode), redraws the shop screen (RedrawView,
     DrawPartyRoster on SelectedCharacter), clears the money block PooledMoney and clears MoneyInPool, then shows the
     menu (ReadPromptChoice) with a text chosen by TreasureLeft (the Take/Share entries appear only while
     MoneyPooled says money lies in the pool) and dispatches the key: B BuyItems, V ViewSelectedCharacter, T TakeMoney,
     P PoolMoney (when MenuFlag is 0), S ShareMoney, A AppraiseGems (Appraise), E leaves, and G and O, which
     neither menu text shows, call UpdateSelectedCharacter with the key. With money left in the pool, E first asks
     "Do you want to go back and get your Money?" ('~Yes ~No' through AskMenu, which returns the
     0-based hotkey position) and the party leaves on No (AnswerNo); Yes clears the message window
     (ClearRect) and stays. A second case redraws the screen (RedrawView) after B and T, and
     after A when Appraised is set. No parameters; side effects: the screen, the items and the money
     through the called routines. */
void ShopMain(void)
{
  POOL_TRACE("ShopMain");
  u8 MenuText[41] = {0};
  u8 Title[2] = {0};
  u8 MenuFlag = 0;
  u8 Done = 0;
  u8 Key = 0;
  u8 MoneyPooled = 0;
  u8 PoolSecond = 0;
  u8 LeaveAnswer = 0;
  u8 Appraised = 0;
  PMenuLine Entry = 0;
  ViewMode = 1;
  RedrawView();
  DrawPartyRoster(SelectedCharacter);
  rtl_FillChar((void *)&PooledMoney, 28, 0);
  rtl_str_assign(Title, 1, S("\000"));
  MoneyInPool = 0;
  Done = 0;
  Entry = PooledItems;
  while (Entry != 0) {
    FormatItemLine(0, Entry, 0, 0, 0, 0);
    Entry = (*FPD(TMenuLine (*), Entry)).Next;
  }
  do {
    TreasureLeft(&MoneyPooled, &PoolSecond);
    if (MoneyPooled != 0) {
      rtl_str_assign(MenuText, 40, S("&Buy View Take Pool Share Appraise Exit"));
    } else {
      rtl_str_assign(MenuText, 40, S("\033Buy View Pool Appraise Exit"));
    }
    Key = ReadPromptChoice(Title, MenuText, 0xD, 0xA, 0xF, 1, 0, &MenuFlag);
    switch ((u8)Key) {
    case 'B':
    {
      BuyItems();
      break;
    }
    case 'V':
    {
      ViewSelectedCharacter(&MenuFlag);
      break;
    }
    case 'T':
    {
      TakeMoney();
      break;
    }
    case 'P':
    {
      if (MenuFlag == 0) {
        PoolMoney();
      }
      break;
    }
    case 'S':
    {
      ShareMoney();
      break;
    }
    case 'A':
    {
      AppraiseGems(&Appraised);
      break;
    }
    case 'E':
    {
      TreasureLeft(&MoneyPooled, &PoolSecond);
      if (MoneyPooled != 0) {
        rtl_str_assign(MenuText, 40, S("\010~Yes ~No"));
        ShowPagedText(1, 0x11, 0x26, 0x16, 0xA, 1, S("RAs you Leave the Shopkeeper says, \"Excuse me but you have Left Some Money here.\"  "));
        ShowPagedText(1, 0x11, 0x26, 0x16, 0xF, 0, S("*Do you want to go back and get your Money\077"));
        LeaveAnswer = AskMenu(Title, MenuText, 0xD, 0xA, 0xF, 0, 0);
        if (LeaveAnswer == AnswerNo) {
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
      break;
    }
    case 'O':
    {
      UpdateSelectedCharacter(Key);
      break;
    }
    }
    switch ((u8)Key) {
    case 'B':
    case 'T':
    {
      RedrawView();
      break;
    }
    case 'A':
    {
      if (Appraised != 0) {
        RedrawView();
      }
      break;
    }
    }
    DrawPartyRoster(SelectedCharacter);
  } while (!(Done != 0));
}

/* Initialisation part of unit OVL06. */
void init_OVL06(void)
{
  POOL_TRACE("init");
  /* Initialisation (ovl06:0798): empty (55 89 E5 5D CB). */
}
