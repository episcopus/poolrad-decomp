#include "game.h"

/* ovl21:0000. The most weight Who may carry: 1500 plus the strength allowance StrengthWeightAllowance
     (negative for a weak character). */
u16 CarryLimit(PCharacter Who)
{
  POOL_TRACE("CarryLimit");
  u16 Result = 0;
  Result = StrengthWeightAllowance(Who) + BaseLoad;
  return Result;
}

/* ovl21:0020. Takes Amount off the weight Who carries (coins handed away). */
void RemoveCarriedWeight(PCharacter Who, u16 Amount)
{
  POOL_TRACE("RemoveCarriedWeight");
  (*FPD(TCharacter (*), Who)).CarriedWeight = (*FPD(TCharacter (*), Who)).CarriedWeight - Amount;
}

/* ovl21:003A. Adds Amount to the weight Who carries (coins taken). */
void AddCarriedWeight(PCharacter Who, u16 Amount)
{
  POOL_TRACE("AddCarriedWeight");
  (*FPD(TCharacter (*), Who)).CarriedWeight = (*FPD(TCharacter (*), Who)).CarriedWeight + Amount;
}

/* ovl21:0054. Tests whether Who would be overloaded carrying Amount more: True when the carried
     weight plus Amount exceeds the most Who may carry, with Room set to what still fits; False with
     Room 0 otherwise. */
u8 WouldOverload(PCharacter Who, u16 Amount, u16 (*Room))
{
  POOL_TRACE("WouldOverload");
  u8 Result = 0;
  if ((u16)((*FPD(TCharacter (*), Who)).CarriedWeight + Amount) > CarryLimit(Who)) {
    Result = 1;
    (*Room) = CarryLimit(Who) - (*FPD(TCharacter (*), Who)).CarriedWeight;
  } else {
    Result = 0;
    (*Room) = 0;
  }
  return Result;
}

/* ovl21:00A8. The value of Money in gold pieces, rounded: the copper value of the first five kinds
     (copper to platinum, CoinCopperValues) plus half a gold piece, divided by the gold value. Gems and
     jewelry (kinds 5 and 6) are not counted. Called by the shop, the Temple and ovl19 on the pooled
     money (PooledMoney). */
s32 MoneyValueInGold(TPartyMoney (*Money_in))
{
  POOL_TRACE("MoneyValueInGold");
  s32 (*Money) = *Money_in;
  s32 Result = 0;
  s32 Total = 0;
  s8 Kind = 0;
  Total = 0;
  {
    if (CopperCoin <= PlatinumCoin) {
      Kind = CopperCoin;
      for (;;) {
          Total += CoinCopperValues[Kind] * Money[Kind];
        if (Kind == PlatinumCoin) break;
        Kind++;
      }
    }
  }
  Result = ((Total + HalfGoldInCopper) / CoinCopperValues[3]);
  return Result;
}

/* ovl21:0130. Sets the selected character's coins to Amount gold pieces in the fewest coins:
     copper to platinum cleared, then Amount div 5 platinum and Amount mod 5 gold. Called after a
     purchase with the money left (shop, Temple). */
void SetCharacterGold(u16 Amount)
{
  POOL_TRACE("SetCharacterGold");
  s8 Kind = 0;
  {
    if (CopperCoin <= PlatinumCoin) {
      Kind = CopperCoin;
      for (;;) {
          (*FPD(TCharacter (*), SelectedCharacter)).Money[Kind] = 0;
        if (Kind == PlatinumCoin) break;
        Kind++;
      }
    }
  }
  (*FPD(TCharacter (*), SelectedCharacter)).Money[4] = (Amount / GoldPerPlatinum);
  (*FPD(TCharacter (*), SelectedCharacter)).Money[3] = (Amount % GoldPerPlatinum);
}

/* ovl21:0185. Sets the pooled money (PooledMoney) to Amount gold pieces the same way: copper to
     platinum cleared, then Amount div 5 platinum and Amount mod 5 gold. */
void SetPooledGold(u16 Amount)
{
  POOL_TRACE("SetPooledGold");
  s8 Kind = 0;
  {
    if (CopperCoin <= PlatinumCoin) {
      Kind = CopperCoin;
      for (;;) {
          PooledMoney[Kind] = 0;
        if (Kind == PlatinumCoin) break;
        Kind++;
      }
    }
  }
  PooledMoney[4] = (Amount / GoldPerPlatinum);
  PooledMoney[3] = (Amount % GoldPerPlatinum);
}

/* ovl21:0203. Gives the selected character Amount platinum pieces: when that would overload him
     he takes what fits (Room) and the rest goes into the pooled money with the message
     "Overloaded.  Money will be put in Pool."; the carried weight grows by what he takes. */
void GivePlatinum(u16 Amount)
{
  POOL_TRACE("GivePlatinum");
  u16 Room = 0;
  if (WouldOverload(SelectedCharacter, Amount, &Room)) {
    ShowFlashMessage(S("'Overloaded.  Money will be put in Pool."));
    (*FPD(TCharacter (*), SelectedCharacter)).Money[4] += Room;
    AddCarriedWeight(SelectedCharacter, Room);
    PooledMoney[4] = (Amount + PooledMoney[4]) - Room;
  } else {
    (*FPD(TCharacter (*), SelectedCharacter)).Money[4] += Amount;
    AddCarriedWeight(SelectedCharacter, Amount);
  }
}

/* ovl21:0294. Asks for an amount on the bottom row: shows Prompt in Color, then reads digits
     (shown in white after the prompt) until Enter or Escape; Backspace deletes the last digit. A
     number above Max is replaced by Max. Returns the amount typed, 0 on Escape. */
u16 ReadAmount(u16 Max, const u8 *Prompt_in, u8 Color)
{
  POOL_TRACE("ReadAmount");
  const u8 *Prompt = Prompt_in;
  u16 Result = 0;
  u8 Col = 0;
  u8 Unused = 0;
  u8 Start = 0;
  u8 MaxText[6] = {0};
  u8 Digits[7] = {0};
  u8 Key = 0;
  s32 Typed = 0;
  s16 Code = 0;
  u16 Amount = 0;
  u8 t1[2];
  u8 t2[8];
  u8 t3[7];
  ClearTextCells(0, BottomRow, 0, ScreenCols);
  DrawTextAt(0, BottomRow, Color, Prompt);
  Start = Prompt[0];
  Col = Start;
  rtl_str_int(MaxText, 5, Max, 0);
  rtl_str_assign(Digits, 6, S("\000"));
  do {
    Key = ReadGameKey();
    switch ((u8)Key) {
    case '0':
    case '1':
    case '2':
    case '3':
    case '4':
    case '5':
    case '6':
    case '7':
    case '8':
    case '9':
    {
      rtl_str_assign(Digits, 6, rtl_str_cat(t2, 2, (const u8 *const[]){Digits, rtl_str_char(t1, Key)}));
      rtl_str_val(Digits, &Typed, 4, 1, &Code);
      if (Max >= Typed) {
        Col++;
      } else {
        rtl_str_assign(Digits, 6, MaxText);
        Col = Start + MaxText[0];
      }
      DrawTextAt(Start, BottomRow, White_OVL21, Digits);
      break;
    }
    case 0x08:
    {
      if (Digits[0] > 0) {
        rtl_str_assign(Digits, 6, rtl_str_copy(t3, Digits, 1, (s16)(Digits[0] - 1)));
        ClearTextCells(Col, BottomRow, 0, 1);
        Col--;
      }
      break;
    }
    }
  } while (!(((Key == KeyEnter_OVL21)) || ((Key == KeyEscape_OVL21))));
  ClearTextCells(0, BottomRow, 0, ScreenCols);
  if (Key == KeyEscape_OVL21) {
    Amount = 0;
  } else {
    rtl_str_val(Digits, &Amount, 2, 0, &Code);
  }
  Result = Amount;
  return Result;
}

/* ovl21:044C. Hands Amount coins of money kind Kind from Giver to Taker, moving their weight
     with them (but see the quirk); when Taker cannot carry that much more it shows "Overloaded" and nothing moves. */
void TransferMoney(PCharacter (*Giver), PCharacter (*Taker), u16 Amount, s8 Kind)
{
  POOL_TRACE("TransferMoney");
  if ((u16)((*FPD(TCharacter (*), (*Taker))).CarriedWeight + Amount) <= CarryLimit((*Taker))) {
    (*FPD(TCharacter (*), (*Giver))).Money[Kind] = (*FPD(TCharacter (*), (*Giver))).Money[Kind] - Amount;
    RemoveCarriedWeight((*Giver), Amount);
    (*FPD(TCharacter (*), (*Taker))).Money[Kind] = (*FPD(TCharacter (*), (*Taker))).Money[Kind] + Amount;
    /* QUIRK ovl21:04DB: the weight is added back to Giver, not to Taker: Giver's weight ends
       unchanged and Taker's does not grow */
    AddCarriedWeight((*Giver), Amount);
  } else {
    ShowFlashMessage(S("\012Overloaded"));
  }
}

/* ovl21:0508. The Pool command: every player-run member (B84 0 or $B3) puts all seven kinds of
     his money into the pool (PooledMoney) and loses its weight; sets MoneyInPool (money in the pool). */
void PoolMoney(void)
{
  POOL_TRACE("PoolMoney");
  PCharacter Who = 0;
  s8 Kind = 0;
  s8 Slot = 0;
  Who = PartyListHead;
  MoneyInPool = 1;
  while (Who != 0) {
    if ((((*FPD(TCharacter (*), Who)).B84 == 0)) || (((*FPD(TCharacter (*), Who)).B84 == SharerB84))) {
      {
        if (0 <= LastMoneyKind) {
          Kind = 0;
          for (;;) {
              Slot = Kind;
              PooledMoney[Slot] = (*FPD(TCharacter (*), Who)).Money[Slot] + PooledMoney[Slot];
              RemoveCarriedWeight(Who, (*FPD(TCharacter (*), Who)).Money[Slot]);
            if (Kind == LastMoneyKind) break;
            Kind++;
          }
        }
      }
      rtl_FillChar((void *)&(*FPD(TCharacter (*), Who)).Money, 14, 0);
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
}

/* ovl21:05E0. The number of members who take part in pooling and sharing (B84 0 or $B3). */
u8 CountSharers(void)
{
  POOL_TRACE("CountSharers");
  u8 Result = 0;
  PCharacter Who = 0;
  u8 Count = 0;
  Who = PartyListHead;
  Count = 0;
  while (Who != 0) {
    if ((((*FPD(TCharacter (*), Who)).B84 == 0)) || (((*FPD(TCharacter (*), Who)).B84 == SharerB84))) {
      Count++;
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  Result = Count;
  return Result;
}

/* ovl21:063A. The Share command: each kind of pooled money is divided by the number of sharers
     (CountSharers). Walking the party, every member below B84 $80 takes his share of each kind, from
     jewelry down to copper, as far as his load allows, plus one coin of the remainder when it fits;
     what he cannot carry goes back to the remainder. The remainders are then handed out to whoever
     can still carry them (any member), and what is left stays in the pool; MoneyInPool says whether any
     money is left there. */
void ShareMoney(void)
{
  POOL_TRACE("ShareMoney");
  PCharacter Who = 0;
  farptr Unused1 = 0;
  u8 Sharers = 0;
  u8 Unused2 = 0;
  u16 Room = 0;
  u16 Share[7] = {0};
  u16 Remainder[7] = {0};
  s8 Kind = 0;
  Who = PartyListHead;
  Unused2 = 0;
  Sharers = CountSharers();
  rtl_FillChar((void *)&Share, 14, 0);
  rtl_FillChar((void *)&Remainder, 14, 0);
  {
    if (0 <= LastMoneyKind) {
      Kind = 0;
      for (;;) {
          if (PooledMoney[Kind] > 0) {
            Share[Kind] = (PooledMoney[Kind] / Sharers);
            Remainder[Kind] = (PooledMoney[Kind] % Sharers);
          } else {
            Share[Kind] = 0;
            Remainder[Kind] = 0;
          }
        if (Kind == LastMoneyKind) break;
        Kind++;
      }
    }
  }
  while (Who != 0) {
    if ((*FPD(TCharacter (*), Who)).B84 < ComputerRun) {
      {
        if (LastMoneyKind >= 0) {
          Kind = LastMoneyKind;
          for (;;) {
              if (!WouldOverload(Who, Share[Kind], &Room)) {
                (*FPD(TCharacter (*), Who)).Money[Kind] = Share[Kind] + (*FPD(TCharacter (*), Who)).Money[Kind];
                AddCarriedWeight(Who, Share[Kind]);
                if (Remainder[Kind] > 0) {
                  if (!WouldOverload(Who, Remainder[Kind], &Room)) {
                    (*FPD(TCharacter (*), Who)).Money[Kind] = (*FPD(TCharacter (*), Who)).Money[Kind] + 1;
                    AddCarriedWeight(Who, 1);
                    Remainder[Kind]--;
                  }
                }
              } else {
                (*FPD(TCharacter (*), Who)).Money[Kind] = (*FPD(TCharacter (*), Who)).Money[Kind] + Room;
                Remainder[Kind] = (Remainder[Kind] + Share[Kind]) - Room;
                AddCarriedWeight(Who, Room);
              }
            if (Kind == 0) break;
            Kind--;
          }
        }
      }
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  {
    if (LastMoneyKind >= 0) {
      Kind = LastMoneyKind;
      for (;;) {
          if (Remainder[Kind] > 0) {
            Who = PartyListHead;
            while (Who != 0) {
              Room = CarryLimit(Who) - (*FPD(TCharacter (*), Who)).CarriedWeight;
              if (Room > 0) {
                if (Remainder[Kind] > Room) {
                  (*FPD(TCharacter (*), Who)).Money[Kind] = (*FPD(TCharacter (*), Who)).Money[Kind] + Room;
                  AddCarriedWeight(Who, Room);
                  Remainder[Kind] = Remainder[Kind] - Room;
                } else {
                  (*FPD(TCharacter (*), Who)).Money[Kind] = (*FPD(TCharacter (*), Who)).Money[Kind] + Remainder[Kind];
                  AddCarriedWeight(Who, Remainder[Kind]);
                  Remainder[Kind] = 0;
                }
              }
              Who = (*FPD(TCharacter (*), Who)).Next;
            }
          }
        if (Kind == 0) break;
        Kind--;
      }
    }
  }
  MoneyInPool = 0;
  {
    if (0 <= LastMoneyKind) {
      Kind = 0;
      for (;;) {
          PooledMoney[Kind] = Remainder[Kind];
          if (PooledMoney[Kind] != 0) {
            MoneyInPool = 1;
          }
        if (Kind == LastMoneyKind) break;
        Kind++;
      }
    }
  }
}

/* ovl21:0A01. Drops Amount coins of money kind Kind from Who, with their weight; in a shop or the
     Temple (view mode 1) or at a battle's treasure (6) they go into the pool, elsewhere they are lost. */
void DropMoney(PCharacter Who, u16 Amount, s8 Kind)
{
  POOL_TRACE("DropMoney");
  (*FPD(TCharacter (*), Who)).Money[Kind] = (*FPD(TCharacter (*), Who)).Money[Kind] - Amount;
  RemoveCarriedWeight(Who, Amount);
  if (((ViewMode == ViewTreasure)) || ((ViewMode == ViewShop))) {
    PooledMoney[Kind] = PooledMoney[Kind] + Amount;
  }
}

/* ovl21:0A88. Who takes Amount of money kind Kind from the pool: "Overloaded" and nothing taken when
     he cannot carry that much more; otherwise at most what the pool holds moves to his money, with its
     weight. */
void TakeFromPool(PCharacter Who, u16 Amount, s8 Kind)
{
  POOL_TRACE("TakeFromPool");
  u16 Room = 0;
  if (WouldOverload(Who, Amount, &Room)) {
    ShowFlashMessage(S("\012Overloaded"));
  } else {
    if (Amount > PooledMoney[Kind]) {
      Amount = PooledMoney[Kind];
    }
    PooledMoney[Kind] = PooledMoney[Kind] - Amount;
    (*FPD(TCharacter (*), Who)).Money[Kind] = (*FPD(TCharacter (*), Who)).Money[Kind] + Amount;
    AddCarriedWeight(Who, Amount);
  }
}

/* ovl21:0B93. The money kind a line of the Take menu names, from its first letter after the leading
     blanks: G is Gems when an E follows, else Gold; P Platinum, E electrum, S silver, C Copper, J
     Jewelry. Name receives the kind's name with a trailing blank for the "How much" prompt.
     QUIRK ovl21:0CB1: for any other letter the result is never assigned. */
s8 MoneyKindOfLine(const u8 *Line_in, u8 (*Name)[256])
{
  POOL_TRACE("MoneyKindOfLine");
  const u8 *Line = Line_in;
  s8 Result = 0;
  u8 I = 0;
  I = 1;
  while (Line[I] == ' ') {
    I++;
  }
  switch ((u8)Line[I]) {
  case 'G':
  {
    if (rtl_upcase(Line[(s16)(I + 1)]) == 'E') {
      Result = GemsKind;
      rtl_str_assign((*Name), 255, S("\005Gems "));
    } else {
      rtl_str_assign((*Name), 255, S("\005Gold "));
      Result = GoldCoin;
    }
    break;
  }
  case 'P':
  {
    rtl_str_assign((*Name), 255, S("\011Platinum "));
    Result = PlatinumCoin;
    break;
  }
  case 'E':
  {
    rtl_str_assign((*Name), 255, S("\011electrum "));
    Result = ElectrumCoin;
    break;
  }
  case 'S':
  {
    rtl_str_assign((*Name), 255, S("\007silver "));
    Result = SilverCoin;
    break;
  }
  case 'C':
  {
    rtl_str_assign((*Name), 255, S("\007Copper "));
    Result = CopperCoin;
    break;
  }
  case 'J':
  {
    rtl_str_assign((*Name), 255, S("\010Jewelry "));
    Result = JewelryKind;
    break;
  }
  }
  return Result;
}

/* ovl21:0CEB. The Take command for pooled money: in a window, lists every kind of money in the pool
     with its amount ("Select type of coin"), asks "How much <kind> will you take?" (ReadAmount, at most
     the pooled amount) and gives it to the selected character (TakeFromPool); repeats while money is
     left in the pool, until the list is left without a choice. Updates MoneyInPool.
     QUIRK ovl21:0D5C: Count is incremented for every listed kind but never set or read.
     QUIRK ovl21:0EA3: leaving the list without a choice does not free the menu lines. */
void TakeMoney(void)
{
  POOL_TRACE("TakeMoney");
  s8 Kind = 0;
  s8 CoinKind = 0;
  u16 Unused = 0;
  PMenuLine List = 0;
  PMenuLine Chosen = 0;
  PMenuLine Head = 0;
  u16 Count = 0;
  s16 Choice = 0;
  u8 Text[256] = {0};
  u16 Amount = 0;
  u8 Done = 0;
  u8 Redraw = 0;
  u8 Key = 0;
  u8 t1[256];
  u8 t2[256];
  DrawWindow(1, 1, 0x26, 0x16, 0, 0xA, S("\000"));
  Choice = 0;
  do {
    Redraw = 1;
    List = 0;
    Chosen = 0;
    {
      if (LastMoneyKind >= 0) {
        Kind = LastMoneyKind;
        for (;;) {
            if (PooledMoney[Kind] > 0) {
              Count++;
              if (List == 0) {
                List = rtl_getmem(MenuLineBytes);
                (*FPD(TMenuLine (*), List)).Next = 0;
              } else {
                Chosen = List;
                List = rtl_getmem(MenuLineBytes);
                (*FPD(TMenuLine (*), List)).Next = Chosen;
              }
              rtl_str_int(Text, 255, PooledMoney[Kind], 0);
              rtl_str_assign((*FPD(TMenuLine (*), List)).Text, 40, rtl_str_cat(t1, 3, (const u8 *const[]){MoneyKindNames[Kind], S("\001 "), Text}));
              (*FPD(TMenuLine (*), List)).Flag29 = 0;
            }
          if (Kind == 0) break;
          Kind--;
        }
      }
    }
    Chosen = List;
    Head = List;
    Key = ChooseFromList(S("\023Select type of coin"), S("\000"), 0xD, 0xA, 0xF, 2, 2, 0xF, 8, List, 1, &Redraw, &Choice, &Chosen);
    if (((Chosen == 0)) || ((Key == 0x00))) {
      Done = 1;
    } else {
      Done = 0;
      CoinKind = MoneyKindOfLine((*FPD(TMenuLine (*), Chosen)).Text, &Text);
      rtl_str_assign(Text, 255, rtl_str_cat(t2, 3, (const u8 *const[]){S("\011How much "), Text, S("\017will you take\077 ")}));
      Amount = ReadAmount(PooledMoney[CoinKind], Text, 0xA);
      TakeFromPool(SelectedCharacter, Amount, CoinKind);
      FreeMenuList(&Head);
      MoneyInPool = 0;
      Done = 1;
      {
        if (0 <= LastMoneyKind) {
          Kind = 0;
          for (;;) {
              if (PooledMoney[Kind] > 0) {
                MoneyInPool = 1;
                Done = 0;
              }
            if (Kind == LastMoneyKind) break;
            Kind++;
          }
        }
      }
    }
  } while (!(Done));
}

/* ovl21:0F7E. Reports what treasure is left: MoneyLeft 1 when any kind of pooled money is not 0,
     ItemsLeft 1 when the loot list (PooledItems) is not empty, else 0. The shop, the Temple and the treasure
     menu build their menus from it. */
void TreasureLeft(u8 (*MoneyLeft), u8 (*ItemsLeft))
{
  POOL_TRACE("TreasureLeft");
  s8 Kind = 0;
  (*MoneyLeft) = 0;
  (*ItemsLeft) = 0;
  {
    if (0 <= LastMoneyKind) {
      Kind = 0;
      for (;;) {
          if (PooledMoney[Kind] != 0) {
            (*MoneyLeft) = 1;
          }
        if (Kind == LastMoneyKind) break;
        Kind++;
      }
    }
  }
  if (PooledItems != 0) {
    (*ItemsLeft) = 1;
  }
}

/* ovl21:0FD2. Rolls the magic bonus of a treasure item: 1 on 1..14 of a d20, 2 on 15..19, 3 on 20. */
s8 RollItemBonus(void)
{
  POOL_TRACE("RollItemBonus");
  s8 Result = 0;
  u8 Roll = 0;
  Roll = RollDice(1, 20);
  switch (Roll) {
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
  {
    Result = 1;
    break;
  }
  case 15:
  case 16:
  case 17:
  case 18:
  case 19:
  {
    Result = 2;
    break;
  }
  default:
  {
    Result = 3;
  }
  }
  return Result;
}

/* ovl21:1010. Builds a treasure item of type Kind into Item. Weapons and armour (types 1..$3B, $49,
     $4D, $5D) get a magic bonus (RollItemBonus) and the name numbers, weight and value of their type;
     types $3D and $3E get 1..3 random affects; the other types listed take a fixed row of TreasureItemRows
     chosen by type and a die roll (names, weight, value, affects, bonus 1, 2 for row $61).
     QUIRK ovl21:10D5: type $15 on a 5 of a d5 takes the row at $90, one word before the row at $91.
     QUIRK ovl21:1753: type $4E rolls 2..4, so its row 1 choice is never taken and a 4 takes no row.
     QUIRK ovl21:17A6: type $47 rolls a d11; 11 takes no row. */
void BuildTreasureItem(u8 Kind, TMenuLine (*Item))
{
  POOL_TRACE("BuildTreasureItem");
  u8 Roll = 0;
  u8 NumAffects = 0;
  u8 I = 0;
  u8 Row = 0;
  u8 Affect = 0;
  rtl_FillChar((void *)&(*Item), 63, 0);
  Row = 0;
  {
    TMenuLine *w1 = &(*Item);
      rtl_FillChar((void *)&w1->Affects, 3, 0);
      w1->Next = 0;
      w1->Readied = 0;
      w1->HiddenNames = 6;
      w1->Cursed = 0;
      w1->ItemType = Kind;
      rtl_FillChar((void *)&w1->NameNum, 3, 0);
      switch (w1->ItemType) {
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
      case 0x49:
      case 0x4D:
      case 0x5D:
      {
        w1->Plus = RollItemBonus();
        switch (w1->ItemType) {
        case 0x15:
        {
          Roll = RollDice(1, 5);
          if (Roll == 5) {
            Row = 0x90;
          }
          w1->NameNum[2] = 0x15;
          w1->NameNum[1] = w1->Plus + 0xA1;
          break;
        }
        case 0x1C:
        {
          w1->NameNum[2] = 0x1C;
          w1->NameNum[1] = w1->Plus + 0xA1;
          break;
        }
        case 0x32:
        case 0x33:
        {
          w1->NameNum[2] = w1->ItemType;
          w1->NameNum[1] = 0x31;
          w1->NameNum[0] = w1->Plus + 0xA1;
          w1->HiddenNames = 4;
          break;
        }
        case 0x34:
        {
          w1->NameNum[2] = w1->ItemType;
          w1->NameNum[1] = 0x32;
          w1->NameNum[0] = w1->Plus + 0xA1;
          w1->HiddenNames = 4;
          break;
        }
        case 53:
        case 54:
        case 55:
        case 56:
        case 57:
        case 58:
        {
          w1->NameNum[2] = w1->ItemType;
          w1->NameNum[1] = 0x30;
          w1->NameNum[0] = w1->Plus + 0xA1;
          w1->HiddenNames = 4;
          break;
        }
        case 0x49:
        {
          w1->NameNum[2] = 0x3D;
          w1->NameNum[1] = w1->Plus + 0xA1;
          break;
        }
        case 0x4D:
        {
          w1->NameNum[2] = 0x4F;
          w1->NameNum[1] = 0xA7;
          w1->Plus = (w1->Plus * 2) + 2;
          switch (w1->Plus) {
          case 4:
          {
            w1->NameNum[0] = 0xDD;
            break;
          }
          case 6:
          {
            w1->NameNum[0] = 0xDE;
            break;
          }
          case 8:
          {
            w1->NameNum[0] = 0xDC;
            break;
          }
          }
          break;
        }
        case 0x5D:
        {
          w1->NameNum[2] = 0x42;
          w1->NameNum[1] = 0xE0;
          w1->NameNum[0] = w1->Plus + 0xA1;
          break;
        }
        default:
        {
          w1->NameNum[2] = w1->ItemType;
          w1->NameNum[1] = w1->Plus + 0xA1;
        }
        }
        w1->PlusSave = 0;
        w1->Count = 0;
        switch (w1->ItemType) {
        case 1:
        case 0xD:
        case 0xE:
        case 0x23:
        {
          w1->Weight = 0x4B;
          break;
        }
        case 2:
        case 0x14:
        case 0x1D:
        case 0x1F:
        case 0x20:
        case 0x21:
        case 0x27:
        case 0x2A:
        case 0x2C:
        case 0x2E:
        case 0x3B:
        {
          w1->Weight = 0x32;
          break;
        }
        case 3:
        case 0x18:
        case 0x28:
        {
          w1->Weight = 0x7D;
          break;
        }
        case 4:
        case 0xF:
        case 0x17:
        case 0x22:
        case 0x2B:
        case 0x2D:
        case 0x33:
        {
          w1->Weight = 0x64;
          break;
        }
        case 5:
        case 0xC:
        case 0x11:
        case 0x13:
        case 0x32:
        {
          w1->Weight = 0x96;
          break;
        }
        case 6:
        {
          w1->Weight = 0xF;
          break;
        }
        case 7:
        {
          w1->Weight = 0x1E;
          break;
        }
        case 8:
        case 0x4D:
        {
          w1->Weight = 0xA;
          break;
        }
        case 9:
        {
          w1->Weight = 0x19;
          w1->Count = 5;
          break;
        }
        case 0xA:
        case 0x1A:
        case 0x24:
        {
          w1->Weight = 0x3C;
          break;
        }
        case 0xB:
        case 0x10:
        case 0x19:
        case 0x1B:
        case 0x29:
        case 0x2F:
        {
          w1->Weight = 0x50;
          break;
        }
        case 0x12:
        {
          w1->Weight = 0xAF;
          break;
        }
        case 0x15:
        {
          w1->Weight = 0x14;
          break;
        }
        case 0x16:
        case 0x1E:
        {
          w1->Weight = 0x28;
          break;
        }
        case 0x25:
        {
          w1->Weight = 0x23;
          break;
        }
        case 0x26:
        case 0x35:
        {
          w1->Weight = 0xFA;
          break;
        }
        case 0x34:
        {
          w1->Weight = 0xC8;
          break;
        }
        case 0x36:
        case 0x38:
        {
          w1->Weight = 0x190;
          break;
        }
        case 0x37:
        {
          w1->Weight = 0x12C;
          break;
        }
        case 0x39:
        {
          w1->Weight = 0x15E;
          break;
        }
        case 0x3A:
        {
          w1->Weight = 0x1C2;
          break;
        }
        case 0x5D:
        {
          w1->Weight = 1;
          break;
        }
        default:
        {
          w1->Weight = 0x28;
          w1->Count = 0xA;
        }
        }
        switch (w1->ItemType) {
        case 0x3B:
        {
          w1->Value = w1->Plus * 0x9C4;
          break;
        }
        case 0x49:
        case 0x1C:
        {
          w1->Value = w1->Plus * 0x96;
          break;
        }
        case 0x35:
        case 0x36:
        {
          w1->Value = w1->Plus * 0xBB8;
          break;
        }
        case 0x37:
        case 0x38:
        {
          w1->Value = w1->Plus * 0xDAC;
          break;
        }
        case 0x39:
        {
          w1->Value = w1->Plus * 0xFA0;
          break;
        }
        case 0x3A:
        {
          w1->Value = w1->Plus * 0x1388;
          break;
        }
        case 0x4D:
        {
          w1->Value = w1->Plus * 0xBB8;
          break;
        }
        default:
        {
          w1->Value = w1->Plus * 0x7D0;
        }
        }
        break;
      }
      case 0x3D:
      case 0x3E:
      {
        NumAffects = RollDice(1, 3);
        if (w1->ItemType == 0x3D) {
          w1->NameNum[2] = 0xD1;
        } else {
          w1->NameNum[2] = 0xD0;
        }
        w1->NameNum[1] = NumAffects + 0xD1;
        w1->NameNum[0] = 0;
        w1->Plus = 1;
        w1->Weight = 0x19;
        w1->Count = 0;
        w1->Value = 0;
        {
          u8 limit = NumAffects;
          if (1 <= limit) {
            I = 1;
            for (;;) {
                Roll = RollDice(1, 3);
                if (w1->ItemType == 0x3D) {
                  switch (Roll) {
                  case 1:
                  {
                    Affect = RollDice(1, 0xD) + 8;
                    break;
                  }
                  case 2:
                  {
                    Affect = RollDice(1, 7) + 0x1C;
                    break;
                  }
                  case 3:
                  {
                    Affect = RollDice(1, 0xB) + 0x2C;
                    break;
                  }
                  }
                } else {
                  switch (Roll) {
                  case 1:
                  {
                    Affect = RollDice(1, 8);
                    break;
                  }
                  case 2:
                  {
                    Affect = RollDice(1, 7) + 0x15;
                    break;
                  }
                  case 3:
                  {
                    Affect = RollDice(1, 9) + 0x23;
                    break;
                  }
                  }
                }
                w1->Affects[I - 1] = Affect;
                w1->Value = (Roll * 0x12C) + w1->Value;
              if (I == limit) break;
              I++;
            }
          }
        }
        break;
      }
      case 0x3F:
      {
        Row = 0x49;
        break;
      }
      case 0x43:
      {
        Row = 0x91;
        break;
      }
      case 0x45:
      {
        Roll = RollDice(1, 10);
        switch (Roll) {
        case 1:
        {
          Row = 0x29;
          break;
        }
        case 2:
        case 3:
        case 4:
        case 5:
        case 6:
        {
          Row = 0x79;
          break;
        }
        case 7:
        case 8:
        case 9:
        case 10:
        {
          Row = 0x81;
          break;
        }
        }
        break;
      }
      case 0x4E:
      {
        Roll = RollDice(1, 3) + 1;
        switch (Roll) {
        case 1:
        {
          Row = 0x31;
          break;
        }
        case 2:
        {
          Row = 0x41;
          break;
        }
        case 3:
        {
          Row = 0x71;
          break;
        }
        }
        break;
      }
      case 0x4F:
      {
        Row = 0x39;
        break;
      }
      case 0x54:
      {
        Row = 9;
        break;
      }
      case 0x5C:
      {
        Row = 0x61;
        break;
      }
      case 0x47:
      {
        Roll = RollDice(1, 0xB);
        switch (Roll) {
        case 1:
        case 2:
        case 3:
        case 4:
        case 5:
        {
          Row = 0x11;
          break;
        }
        case 6:
        case 7:
        case 8:
        {
          Row = 1;
          break;
        }
        case 9:
        {
          Row = 0x19;
          break;
        }
        case 10:
        {
          Row = 0x51;
          break;
        }
        }
        break;
      }
      case 0x46:
      {
        Roll = RollDice(1, 10);
        switch (Roll) {
        case 1:
        case 2:
        case 3:
        case 4:
        case 5:
        case 6:
        case 7:
        {
          Row = 0x59;
          break;
        }
        case 8:
        case 9:
        case 10:
        {
          Row = 0x89;
          break;
        }
        }
        break;
      }
      }
      if (Row != 0) {
        {
          if (0 <= 2) {
            I = 0;
            for (;;) {
                w1->NameNum[(s16)(I + 1) - 1] = TreasureItemRows[(s16)(Row + I)];
              if (I == 2) break;
              I++;
            }
          }
        }
        w1->Plus = 1;
        w1->PlusSave = 1;
        if (Row == 0x61) {
          w1->Plus = 2;
          w1->PlusSave = 2;
        }
        w1->Weight = TreasureItemRows[(s16)(Row + 3)];
        w1->Count = 0;
        w1->Value = TreasureItemRows[(s16)(Row + 4)];
        {
          if (1 <= 3) {
            I = 1;
            for (;;) {
                w1->Affects[I - 1] = TreasureItemRows[(s16)((Row + 4) + I)];
              if (I == 3) break;
              I++;
            }
          }
        }
      }
  }
}

/* ovl21:19B2. The Appraise command of the shop and the Temple for the selected character's gems
     and jewelry: "No Gems or Jewelry" (and Redraw 0) when he has none; otherwise it shows "You have a
     fine collection of:" with the counts and asks "Appraise :  Gems  Jewelry Exit". Each gem or piece
     appraised is taken from his money, valued with a d100 ("The Gem is Valued at <n> gp.", jewels
     "The Jewel is Valued at ..."), and either sold for a fifth of its value in platinum (GivePlatinum)
     or, when he can carry it and has fewer than 16 items, kept as an item of type $46 with that value.
     Repeats until Exit or nothing is left; Redraw is 1 unless there was nothing to appraise.
     QUIRK ovl21:1E74, 21C7: a character with no items does not get the kept gem (the new item is only
     stored in a local), and a kept gem adds no weight. */
void AppraiseGems(u8 (*Redraw))
{
  POOL_TRACE("AppraiseGems");
  String40_RES06 GemsText = {0};
  String40_RES06 JewelryText = {0};
  u8 Key = 0;
  String40_RES06 Menu = {0};
  String40_RES06 SellMenu = {0};
  u8 Roll = 0;
  u16 Value = 0;
  u16 Room = 0;
  PMenuLine Last = 0;
  PMenuLine NewItem = 0;
  u8 Done = 0;
  u8 ExtKey = 0;
  u8 MustSell = 0;
  u8 t1[45];
  u8 t2[46];
  u8 t3[58];
  u8 t4[59];
  u8 t5[50];
  u8 t6[46];
  u8 t7[66];
  u8 t8[68];
  (*Redraw) = 1;
  if ((((*FPD(TCharacter (*), SelectedCharacter)).Money[5] == 0)) && (((*FPD(TCharacter (*), SelectedCharacter)).Money[6] == 0))) {
    ShowFlashMessage(S("\022No Gems or Jewelry"));
    (*Redraw) = 0;
    return;
  }
  do {
    if ((((*FPD(TCharacter (*), SelectedCharacter)).Money[5] == 0)) && (((*FPD(TCharacter (*), SelectedCharacter)).Money[6] == 0))) {
      Done = 1;
    } else {
      Done = 0;
      rtl_str_int(GemsText, 40, (*FPD(TCharacter (*), SelectedCharacter)).Money[5], 0);
      rtl_str_int(JewelryText, 40, (*FPD(TCharacter (*), SelectedCharacter)).Money[6], 0);
      switch ((*FPD(TCharacter (*), SelectedCharacter)).Money[5]) {
      case 0:
      {
        rtl_str_assign(GemsText, 40, S("\000"));
        break;
      }
      case 1:
      {
        rtl_str_assign(GemsText, 40, rtl_str_cat(t1, 2, (const u8 *const[]){GemsText, S("\004 Gem")}));
        break;
      }
      default:
      {
        rtl_str_assign(GemsText, 40, rtl_str_cat(t2, 2, (const u8 *const[]){GemsText, S("\005 Gems")}));
      }
      }
      switch ((*FPD(TCharacter (*), SelectedCharacter)).Money[6]) {
      case 0:
      {
        rtl_str_assign(JewelryText, 40, S("\000"));
        break;
      }
      case 1:
      {
        rtl_str_assign(JewelryText, 40, rtl_str_cat(t3, 2, (const u8 *const[]){JewelryText, S("\021 piece of Jewelry")}));
        break;
      }
      default:
      {
        rtl_str_assign(JewelryText, 40, rtl_str_cat(t4, 2, (const u8 *const[]){JewelryText, S("\022 pieces of Jewelry")}));
      }
      }
      ClearRect(1, 1, 0x26, 0x16);
      DrawCharacterName(SelectedCharacter, 1, 1, 0);
      DrawTextAt(1, 7, White_OVL21, S("\036You have a fine collection of:"));
      DrawTextAt(1, 9, White_OVL21, GemsText);
      DrawTextAt(1, 0xA, White_OVL21, JewelryText);
      rtl_str_assign(Menu, 40, S("\000"));
      if ((*FPD(TCharacter (*), SelectedCharacter)).Money[5] != 0) {
        rtl_str_assign(Menu, 40, S("\006  Gems"));
      }
      if ((*FPD(TCharacter (*), SelectedCharacter)).Money[6] != 0) {
        rtl_str_assign(Menu, 40, rtl_str_cat(t5, 2, (const u8 *const[]){Menu, S("\011  Jewelry")}));
      }
      rtl_str_assign(Menu, 40, rtl_str_cat(t6, 2, (const u8 *const[]){Menu, S("\005 Exit")}));
      Key = ReadPromptChoice(S("\013Appraise : "), Menu, 0xD, 0xA, White_OVL21, 1, 0, &ExtKey);
      switch ((u8)Key) {
      case 'G':
      {
        if ((*FPD(TCharacter (*), SelectedCharacter)).Money[5] != 0) {
          (*FPD(TCharacter (*), SelectedCharacter)).Money[5]--;
          Roll = RollDice(1, 100);
          switch (Roll) {
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
          {
            Value = 10;
            break;
          }
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
            Value = 50;
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
          {
            Value = 100;
            break;
          }
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
            Value = 500;
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
            Value = 1000;
            break;
          }
          case 100:
          {
            Value = 5000;
            break;
          }
          }
          rtl_str_int(GemsText, 40, Value, 0);
          rtl_str_assign(GemsText, 40, rtl_str_cat(t7, 3, (const u8 *const[]){S("\025The Gem is Valued at "), GemsText, S("\004 gp.")}));
          DrawTextAt(1, 0xC, White_OVL21, GemsText);
          if (WouldOverload(SelectedCharacter, 1, &Room) || (((*FPD(TCharacter (*), SelectedCharacter)).ItemCountC7 >= MaxItems))) {
            rtl_str_assign(SellMenu, 40, S("\004Sell"));
            MustSell = 1;
          } else {
            rtl_str_assign(SellMenu, 40, S("\011Sell Keep"));
            MustSell = 0;
          }
          Key = ReadPromptChoice(S("\012You can : "), SellMenu, 0xD, 0xA, White_OVL21, 1, 0, &ExtKey);
          if (((Key == 'K')) && !MustSell) {
            NewItem = rtl_getmem(63);
            rtl_FillChar((void *)&(*FPD(TMenuLine (*), NewItem)), 63, 0);
            (*FPD(TMenuLine (*), NewItem)).Next = 0;
            (*FPD(TMenuLine (*), NewItem)).Readied = 0;
            (*FPD(TMenuLine (*), NewItem)).NameNum[2] = GemItemName;
            (*FPD(TMenuLine (*), NewItem)).NameNum[1] = 0;
            (*FPD(TMenuLine (*), NewItem)).NameNum[0] = 0;
            (*FPD(TMenuLine (*), NewItem)).ItemType = GemItemType;
            (*FPD(TMenuLine (*), NewItem)).Value = Value;
            (*FPD(TMenuLine (*), NewItem)).Weight = 1;
            (*FPD(TMenuLine (*), NewItem)).HiddenNames = 0;
            Last = (*FPD(TCharacter (*), SelectedCharacter)).Items;
            if (Last == 0) {
              Last = NewItem;
            } else {
              while ((*FPD(TMenuLine (*), Last)).Next != 0) {
                Last = (*FPD(TMenuLine (*), Last)).Next;
              }
              (*FPD(TMenuLine (*), Last)).Next = NewItem;
            }
          } else {
            Value = (Value / GoldPerPlatinum);
            GivePlatinum(Value);
          }
        }
        break;
      }
      case 'J':
      {
        if ((*FPD(TCharacter (*), SelectedCharacter)).Money[6] != 0) {
          (*FPD(TCharacter (*), SelectedCharacter)).Money[6]--;
          Roll = RollDice(1, 100);
          switch (Roll) {
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
          {
            Value = rtl_trunc((double)rtl_Random(900)) + 100;
            break;
          }
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
          {
            Value = rtl_trunc((double)rtl_Random(1000)) + 200;
            break;
          }
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
          {
            Value = rtl_trunc((double)rtl_Random(1500)) + 300;
            break;
          }
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
            Value = rtl_trunc((double)rtl_Random(2500)) + 500;
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
          {
            Value = rtl_trunc((double)rtl_Random(5000)) + 1000;
            break;
          }
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
            Value = rtl_trunc((double)rtl_Random(6000)) + 2000;
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
          case 100:
          {
            Value = rtl_trunc((double)rtl_Random(10000)) + 2000;
            break;
          }
          }
          rtl_str_int(JewelryText, 40, Value, 0);
          rtl_str_assign(GemsText, 40, rtl_str_cat(t8, 3, (const u8 *const[]){S("\027The Jewel is Valued at "), JewelryText, S("\004 gp.")}));
          DrawTextAt(1, 0xC, White_OVL21, GemsText);
          if (WouldOverload(SelectedCharacter, 1, &Room) || (((*FPD(TCharacter (*), SelectedCharacter)).ItemCountC7 >= MaxItems))) {
            rtl_str_assign(SellMenu, 40, S("\004Sell"));
            MustSell = 1;
          } else {
            rtl_str_assign(SellMenu, 40, S("\011Sell Keep"));
            MustSell = 0;
          }
          Key = ReadPromptChoice(S("\012You can : "), SellMenu, 0xD, 0xA, White_OVL21, 1, 0, &ExtKey);
          if (((Key == 'K')) && !MustSell) {
            NewItem = rtl_getmem(63);
            rtl_FillChar((void *)&(*FPD(TMenuLine (*), NewItem)), 63, 0);
            (*FPD(TMenuLine (*), NewItem)).Next = 0;
            (*FPD(TMenuLine (*), NewItem)).Readied = 0;
            (*FPD(TMenuLine (*), NewItem)).NameNum[2] = JewelItemName;
            (*FPD(TMenuLine (*), NewItem)).NameNum[1] = 0;
            (*FPD(TMenuLine (*), NewItem)).NameNum[0] = 0;
            (*FPD(TMenuLine (*), NewItem)).ItemType = GemItemType;
            (*FPD(TMenuLine (*), NewItem)).Value = Value;
            (*FPD(TMenuLine (*), NewItem)).Weight = 1;
            (*FPD(TMenuLine (*), NewItem)).HiddenNames = 0;
            Last = (*FPD(TCharacter (*), SelectedCharacter)).Items;
            if (Last == 0) {
              Last = NewItem;
            } else {
              while ((*FPD(TMenuLine (*), Last)).Next != 0) {
                Last = (*FPD(TMenuLine (*), Last)).Next;
              }
              (*FPD(TMenuLine (*), Last)).Next = NewItem;
            }
          } else {
            Value = (Value / GoldPerPlatinum);
            GivePlatinum(Value);
          }
        }
        break;
      }
      case 'E':
      case 0x00:
      {
        Done = 1;
        break;
      }
      }
      RecalcCombatValues(SelectedCharacter);
    }
  } while (!(Done));
}

/* Initialisation part of unit OVL21. */
void init_OVL21(void)
{
  POOL_TRACE("init");
}
