#include "game.h"

/* ovl04:0013. Shows Reason for the selected character (ShowCharacterMessage, e.g. "is not blind.") and
     asks "cast cure anyway: "; returns the key (Yes or not). ClearCharacterMessage clears the prompt. */
u8 AskCastAnyway(const u8 *Reason_in)
{
  POOL_TRACE("AskCastAnyway");
  const u8 *Reason = Reason_in;
  u8 Result = 0;
  ShowCharacterMessage(SelectedCharacter, Reason, 0, 0);
  Result = AskYesNo(S("\022cast cure anyway: "), PromptTitleColor_OVL04, PromptWordColor_OVL04, PromptHotColor_OVL04);
  ClearCharacterMessage();
  return Result;
}

/* ovl04:00BF. Tells what Service costs ("<service> will only cost <price> gold pieces."), asks
     "pay for cure", and on Yes takes Price from the selected character's money (CharacterMoneyValueInGold, then
     SetCharacterGold) or else from the pooled money DS:67F4 (MoneyValueInGold, then SetPooledGold). When neither
     covers the price it says "Not enough money." and the answer becomes No. On Yes it shows
     "is cured.". Returns the answer.
     QUIRK ovl04:0177: CharacterMoneyValueInGold returns a LongInt, but Money is a Word, so only AX is kept and a
     character with 65536 or more is compared and charged modulo 65536 (a price can fit when only the
     low word does, and SetCharacterGold then stores the low word less the price). QUIRK ovl04:01C8: the pool
     path computes Pooled - Price as a LongInt but SetPooledGold(Amount: Word) receives only the low word,
     so a pool above 65535 is rewritten with the truncated amount (the same truncations as ovl06's
     BuyItems). */
u8 ChargeForCure(const u8 *Service_in, u16 Price)
{
  POOL_TRACE("ChargeForCure");
  u8 Service[256];
  rtl_str_assign(Service, 255, Service_in);
  u8 Result = 0;
  u8 Answer = 0;
  u16 Money = 0;
  s32 Pooled = 0;
  u8 t1[256];
  u8 t2[256];
  rtl_str_assign(Service, 255, rtl_str_cat(t2, 4, (const u8 *const[]){Service, S("\020 will only cost "), WordToText(t1, Price), S("\015 gold pieces.")}));
  ShowPagedText(TextWindowLeft, TextWindowTop, TextWindowRight, TextWindowBottom, TextWindowColor, 1, Service);
  Answer = AskYesNo(S("\015pay for cure "), PromptTitleColor_OVL04, CostPromptWordColor, CostPromptHotColor);
  if (Answer == KeyYes) {
    Money = CharacterMoneyValueInGold(SelectedCharacter);
    if (Price <= Money) {
      Money -= Price;
      SetCharacterGold(Money);
    } else {
      Pooled = MoneyValueInGold(&PooledMoney);
      if (Price <= Pooled) {
        Pooled -= Price;
        SetPooledGold(Pooled);
      } else {
        ShowFlashMessage(S("\021Not enough money."));
        Answer = KeyNo;
      }
    }
  }
  if (Answer == KeyYes) {
    ClearCharacterMessage();
    ShowCharacterMessage(SelectedCharacter, S("\011is cured."), 0, 1);
  }
  Result = Answer;
  return Result;
}

/* ovl04:0249. Cure Blindness: asks first when the selected character is not blind (no
     AffectBlind), charges PriceCureBlindness and removes the affect. QUIRK ovl04:0250: Unused is
     cleared and never read (the same in every service routine). */
void CureBlindness(void)
{
  POOL_TRACE("CureBlindness");
  farptr Affect = 0;
  u8 Unused[256] = {0};
  u8 Answer = 0;
  rtl_str_assign(Unused, 255, S("\000"));
  Answer = KeyYes;
  if (!HasAffect(SelectedCharacter, AffectBlind, &Affect)) {
    Answer = AskCastAnyway(S("\015is not blind."));
  }
  if (Answer == KeyYes) {
    Answer = ChargeForCure(S("\016Cure Blindness"), PriceCureBlindness);
    if (Answer == KeyYes) {
      RemoveAffect(SelectedCharacter, AffectBlind, 0);
    }
  }
}

/* ovl04:02ED. Cure Disease: the character is diseased when it has one of the six
     DiseaseAffects; otherwise asks first. Charges PriceCureDisease and removes all six, with
     RemovingAffects set while it does. */
void CureDisease(void)
{
  POOL_TRACE("CureDisease");
  farptr Affect = 0;
  u8 Unused[256] = {0};
  u8 Answer = 0;
  u8 I = 0;
  u8 Diseased = 0;
  Diseased = 0;
  rtl_str_assign(Unused, 255, S("\000"));
  Answer = KeyYes;
  {
    if (1 <= DiseaseCount) {
      I = 1;
      for (;;) {
          if (HasAffect(SelectedCharacter, DiseaseAffects[I], &Affect)) {
            Diseased = 1;
          }
        if (I == DiseaseCount) break;
        I++;
      }
    }
  }
  if (!Diseased) {
    Answer = AskCastAnyway(S("\020is not Diseased."));
  }
  if (Answer == KeyYes) {
    Answer = ChargeForCure(S("\014Cure Disease"), PriceCureDisease);
    if (Answer == KeyYes) {
      RemovingAffects = 1;
      {
        if (1 <= DiseaseCount) {
          I = 1;
          for (;;) {
              RemoveAffect(SelectedCharacter, DiseaseAffects[I], 0);
            if (I == DiseaseCount) break;
            I++;
          }
        }
      }
      RemovingAffects = 0;
    }
  }
}

/* ovl04:0401. Cure Light, Serious or Critical Wounds (Strength 1, 2 or 3): charges 100, 350 or
     600 and heals 1d8, 2d8+1 or 3d8+3 hit points (RollDice rolls, HealCharacter heals). */
void CureWounds(u8 Strength)
{
  POOL_TRACE("CureWounds");
  u8 Amount = 0;
  u8 Answer = 0;
  u8 Healed = 0;
  switch (Strength) {
  case 1:
  {
    Answer = ChargeForCure(S("\021Cure Light Wounds"), PriceCureLight);
    if (Answer == KeyYes) {
      Amount = RollDice(1, 8);
      Healed = HealCharacter(SelectedCharacter, Amount, 0);
    }
    break;
  }
  case 2:
  {
    Answer = ChargeForCure(S("\023Cure Serious Wounds"), PriceCureSerious);
    if (Answer == KeyYes) {
      Amount = RollDice(2, 8) + 1;
      Healed = HealCharacter(SelectedCharacter, Amount, 0);
    }
    break;
  }
  case 3:
  {
    Answer = ChargeForCure(S("\024Cure Critical Wounds"), PriceCureCritical);
    if (Answer == KeyYes) {
      Amount = RollDice(3, 8) + 3;
      Healed = HealCharacter(SelectedCharacter, Amount, 0);
    }
    break;
  }
  }
}

/* ovl04:0510. Raise Dead: the character is dead when Status is StatusAnimated (1) or StatusDead (6) (ovl04:0539); otherwise it
     asks first. Charges PriceRaiseDead; only a dead character is raised: AffectAnimateDead and
     AffectPoisoned are removed, Status becomes StatusOkay, Flag10D becomes 1 (battle participant eligible
     for experience, ovl05:0355), and HpCurrent becomes 1. HpCurrent is the current hit points [I], so this
     restores one hit point [I] (ovl24:175D). Constitution is reduced by one before the constitution
     thresholds are tested; from 14 up the hit points above HpB1 are divided by the bonus over all class
     levels (fighter levels count constitution - 14; non-fighter levels count twice above constitution 15,
     else 1). A bonus of 0 leaves the loss undivided. The loss is skipped at constitution 17 or more when
     the character has no fighter level. */
void RaiseDead(void)
{
  POOL_TRACE("RaiseDead");
  farptr Affect = 0;
  u8 Unused[256] = {0};
  u8 Answer = 0;
  u8 Dead = 0;
  u8 HpLoss = 0;
  u8 Bonus = 0;
  s8 I = 0;
  PCharacter Who = 0;
  Who = SelectedCharacter;
  Dead = 0;
  rtl_str_assign(Unused, 255, S("\000"));
  Answer = KeyYes;
  if ((((*FPD(TCharacter (*), Who)).Status == StatusDead)) || (((*FPD(TCharacter (*), Who)).Status == StatusAnimated))) {
    Dead = 1;
  }
  if (!Dead) {
    Answer = AskCastAnyway(S("\014is not dead."));
  }
  if (Answer == KeyYes) {
    Answer = ChargeForCure(S("\012Raise Dead"), PriceRaiseDead);
    if (Answer == KeyYes) {
      if (Dead) {
        RemovingAffects = 1;
        RemoveAffect(Who, AffectAnimateDead, 0);
        RemoveAffect(Who, AffectPoisoned, 0);
        RemovingAffects = 0;
        (*FPD(TCharacter (*), Who)).HpCurrent = 1;
        (*FPD(TCharacter (*), Who)).Status = StatusOkay;
        (*FPD(TCharacter (*), Who)).Flag10D = 1;
        if ((*FPD(TCharacter (*), Who)).Constitution > 0) {
          (*FPD(TCharacter (*), Who)).Constitution--;
        }
        if ((*FPD(TCharacter (*), Who)).HpMax > (*FPD(TCharacter (*), Who)).HpB1) {
          HpLoss = (*FPD(TCharacter (*), Who)).HpMax - (*FPD(TCharacter (*), Who)).HpB1;
        } else {
          HpLoss = 0;
        }
        Bonus = 0;
        if ((*FPD(TCharacter (*), Who)).Constitution >= BonusConstitution) {
          {
            if (0 <= LastClass_OVL04) {
              I = 0;
              for (;;) {
                  if ((*FPD(TCharacter (*), Who)).ClassLevels[I] > 0) {
                    if (I == ClassFighter) {
                      Bonus += (s16)(((s16)((*FPD(TCharacter (*), Who)).Constitution - BonusConstitution)) * (*FPD(TCharacter (*), Who)).ClassLevels[I]);
                    } else if ((*FPD(TCharacter (*), Who)).Constitution > HighConstitution) {
                      Bonus += (s16)((*FPD(TCharacter (*), Who)).ClassLevels[I] * 2);
                    } else {
                      Bonus += (*FPD(TCharacter (*), Who)).ClassLevels[I];
                    }
                  }
                if (I == LastClass_OVL04) break;
                I++;
              }
            }
          }
          if (Bonus > 0) {
            HpLoss = (HpLoss / Bonus);
          }
          if ((((*FPD(TCharacter (*), Who)).Constitution < FighterOnlyConstitution)) || (((*FPD(TCharacter (*), Who)).ClassLevels[2] > 0))) {
            (*FPD(TCharacter (*), Who)).HpMax -= HpLoss;
          }
        }
      }
    }
  }
}

/* ovl04:0751. Neutralize Poison: asks first when the character has no AffectPoisoned; charges
     PriceNeutralizePoison and removes AffectPoisoned plus values $16 and $0F (their meanings are unknown). */
void NeutralizePoison(void)
{
  POOL_TRACE("NeutralizePoison");
  farptr Affect = 0;
  u8 Unused[256] = {0};
  u8 Answer = 0;
  u8 Poisoned = 0;
  Poisoned = 0;
  rtl_str_assign(Unused, 255, S("\000"));
  Answer = KeyYes;
  if (HasAffect(SelectedCharacter, AffectPoisoned, &Affect)) {
    Poisoned = 1;
  }
  if (!Poisoned) {
    Answer = AskCastAnyway(S("\020is not poisoned."));
  }
  if (Answer == KeyYes) {
    Answer = ChargeForCure(S("\021Neutralize Poison"), PriceNeutralizePoison);
    if (Answer == KeyYes) {
      RemovingAffects = 1;
      RemoveAffect(SelectedCharacter, AffectPoisoned, 0);
      RemoveAffect(SelectedCharacter, AffectSlowPoison, 0);
      RemoveAffect(SelectedCharacter, AffectSlowPoisonDamage, 0);
      RemovingAffects = 0;
    }
  }
}

/* ovl04:083A. Remove Curse: the character needs it when one of its items is cursed or it has
     AffectBestowCurse; otherwise asks first. Charges PriceRemoveCurse and hands the character to
     CastRemoveCurse through FirstSpellTarget. */
void RemoveCurse(void)
{
  POOL_TRACE("RemoveCurse");
  u8 Cursed = 0;
  PItem Item = 0;
  farptr Affect = 0;
  u8 Unused[256] = {0};
  u8 Answer = 0;
  rtl_str_assign(Unused, 255, S("\000"));
  Answer = KeyYes;
  Cursed = 0;
  Item = (*FPD(TCharacter (*), SelectedCharacter)).Items;
  while (((Item != 0)) && !Cursed) {
    if ((*FPD(TMenuLine (*), Item)).Cursed) {
      Cursed = 1;
    }
    Item = (*FPD(TMenuLine (*), Item)).Next;
  }
  if (!Cursed && !HasAffect(SelectedCharacter, AffectBestowCurse, &Affect)) {
    Answer = AskCastAnyway(S("\016is not cursed."));
  }
  if (Answer == KeyYes) {
    Answer = ChargeForCure(S("\014Remove Curse"), PriceRemoveCurse);
    if (Answer == KeyYes) {
      FirstSpellTarget = SelectedCharacter;
      CastRemoveCurse();
    }
  }
}

/* ovl04:0928. Stone to Flesh: asks first when Status is not StatusStoned; charges PriceStoneToFlesh
     and, for a stoned character, sets Status to StatusOkay, Flag10D to 1 (experience eligible,
     ovl05:0355) and HpCurrent to 1. HpCurrent is the current hit points [I], so this restores one hit point [I]
     (ovl24:175D). */
void StoneToFlesh(void)
{
  POOL_TRACE("StoneToFlesh");
  farptr Affect = 0;
  u8 Unused[256] = {0};
  u8 Answer = 0;
  rtl_str_assign(Unused, 255, S("\000"));
  Answer = KeyYes;
  if ((*FPD(TCharacter (*), SelectedCharacter)).Status != StatusStoned) {
    Answer = AskCastAnyway(S("\016is not stoned."));
  }
  if (Answer == KeyYes) {
    Answer = ChargeForCure(S("\016Stone to Flesh"), PriceStoneToFlesh);
    if (Answer == KeyYes) {
      if ((*FPD(TCharacter (*), SelectedCharacter)).Status == StatusStoned) {
        (*FPD(TCharacter (*), SelectedCharacter)).Status = StatusOkay;
        (*FPD(TCharacter (*), SelectedCharacter)).Flag10D = 1;
        (*FPD(TCharacter (*), SelectedCharacter)).HpCurrent = 1;
      }
    }
  }
}

/* ovl04:09D7. The Heal menu: fills ten menu lines with TempleMenuText, clears row 24, draws the windows and
     "<name>, how can we help you?", and runs ChooseFromList with "Heal Exit" until Exit or Escape.
     Heal or Enter on lines 0..8 runs that service; line 9 is Exit. RedrawList requests the initial page
     draw and is cleared by ChooseFromList. Frees the lines, clears the whole screen (columns 0..39, rows
     0..24) and redraws the view and reshows SelectedCharacter. */
void HealMenu(void)
{
  POOL_TRACE("HealMenu");
  PMenuLine List = 0;
  PMenuLine First = 0;
  u8 RedrawList = 0;
  u8 I = 0;
  s16 Choice = 0;
  u8 Done = 0;
  String40_RES06 Prompt = {0};
  u8 Key = 0;
  u8 t1[38];
  Done = 0;
  List = 0;
  First = 0;
  NewMenuList(HealMenuLines, &List);
  First = List;
  I = 1;
  while (List != 0) {
    rtl_str_assign((*FPD(TMenuLine (*), List)).Text, 40, TempleMenuText[I]);
    (*FPD(TMenuLine (*), List)).Flag29 = 0;
    List = (*FPD(TMenuLine (*), List)).Next;
    I++;
  }
  List = First;
  ClearRect(PromptClearLeft, PromptClearRow, PromptClearRight, PromptClearRow);
  RedrawList = 1;
  DrawWindow(TempleLeft, TempleTop, TempleRight, TempleBottom, TempleFrameSet, TempleTitleColor, S("\000"));
  DrawWindow(TempleLeft, TempleTop, TempleRight, TempleHeaderBottom, TempleFrameSet, TempleTitleColor, S("\000"));
  do {
    rtl_str_assign(Prompt, 40, rtl_str_cat(t1, 2, (const u8 *const[]){(*FPD(TCharacter (*), SelectedCharacter)).Name, S("\026, how can we help you\077")}));
    DrawTextAt(TempleLeft, TempleTop, TempleTitleColor, Prompt);
    DrawWindow(TextWindowLeft, TextWindowTop, TextWindowRight, TextWindowBottom, TempleFrameSet, TempleTitleColor, S("\000"));
    Key = ChooseFromList(S("\000"), S("\011Heal Exit"), HealListHeadingColor, HealListLineColor, HealListHighlightColor, HealListLeft, HealListTop, HealListRight, HealListBottom, List, 0, &RedrawList, &Choice, &First);
    switch ((u8)Key) {
    case 'H':
    case 0x0D:
    {
      switch (Choice) {
      case 0:
      {
        CureBlindness();
        break;
      }
      case 1:
      {
        CureDisease();
        break;
      }
      case 2:
      {
        CureWounds(1);
        break;
      }
      case 3:
      {
        CureWounds(2);
        break;
      }
      case 4:
      {
        CureWounds(3);
        break;
      }
      case 5:
      {
        NeutralizePoison();
        break;
      }
      case 6:
      {
        RaiseDead();
        break;
      }
      case 7:
      {
        RemoveCurse();
        break;
      }
      case 8:
      {
        StoneToFlesh();
        break;
      }
      case 9:
      {
        Done = 1;
        break;
      }
      }
      break;
    }
    case 0x00:
    {
      Done = 1;
      break;
    }
    }
  } while (!(Done));
  FreeMenuList(&List);
  ClearRect(PromptClearLeft, ScreenTopRow, PromptClearRight, ScreenBottomRow);
  RedrawView();
  DrawPartyRoster(SelectedCharacter);
}

/* ovl04:0D09. The Temple menu offers Heal, View, Take, Pool, Share, Appraise and Exit (Take and Share
     only while TreasureLeft reports pooled money). Heal and Pool run only when ExtKey is 0; View receives
     ExtKey, and G/O scan letters (Home/End, or keypad 7/1) go to UpdateSelectedCharacter. The trailing B redraw arm at
     ovl04:0F02 is not in the menu text. ReadPromptChoice can return scan letters for extended keys, but
     the physical key that yields B is unknown. Exit with money in the pool asks "Do you want to go back
     and retrieve your money?" ('~Yes ~No') and leaves on No (AskMenu returns position 1); Yes keeps the
     money in the Temple. On entry it sets ViewMode to 1, redraws the view and character, clears PooledMoney
     and sets MoneyInPool to 0. */
void VisitTemple(void)
{
  POOL_TRACE("VisitTemple");
  u8 Key = 0;
  u8 Done = 0;
  u8 ExtKey = 0;
  String40_RES06 Prompt = {0};
  u8 MoneyPooled = 0;
  u8 PoolSecond = 0;
  u8 LeaveAnswer = 0;
  u8 Appraised = 0;
  ViewMode = 1;
  RedrawView();
  DrawPartyRoster(SelectedCharacter);
  rtl_FillChar((void *)&PooledMoney, 28, 0);
  MoneyInPool = 0;
  Done = 0;
  do {
    TreasureLeft(&MoneyPooled, &PoolSecond);
    if (MoneyPooled != 0) {
      rtl_str_assign(Prompt, 40, S("'Heal View Take Pool Share Appraise Exit"));
    } else {
      rtl_str_assign(Prompt, 40, S("\034Heal View Pool Appraise Exit"));
    }
    Key = ReadPromptChoice(S("\000"), Prompt, PromptTitleColor_OVL04, PromptWordColor_OVL04, PromptHotColor_OVL04, AcceptExtendedKeys, NoAnimation, &ExtKey);
    switch ((u8)Key) {
    case 'H':
    {
      if (ExtKey == 0) {
        HealMenu();
      }
      break;
    }
    case 'V':
    {
      ViewSelectedCharacter(&ExtKey);
      break;
    }
    case 'T':
    {
      TakeMoney();
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
    case 'A':
    {
      AppraiseGems(&Appraised);
      break;
    }
    case 'E':
    {
      TreasureLeft(&MoneyPooled, &PoolSecond);
      if (MoneyPooled != 0) {
        rtl_str_assign(Prompt, 40, S("\010~Yes ~No"));
        ShowPagedText(TextWindowLeft, TextWindowTop, TextWindowRight, TextWindowBottom, TextWindowColor, ClearTextBeforeMessage, S("JAs you leave a priest says, \"Excuse me but you have left some money here\" "));
        ShowPagedText(TextWindowLeft, TextWindowTop, TextWindowRight, TextWindowBottom, TextWindowColor, ClearTextBeforeMessage, S("/Do you want to go back and retrieve your money\077"));
        LeaveAnswer = AskMenu(S("\000"), Prompt, PromptTitleColor_OVL04, PromptWordColor_OVL04, PromptHotColor_OVL04, NoExtendedKeys, NoAnimation);
        if (LeaveAnswer == AnswerNo) {
          Done = 1;
        } else {
          ClearRect(TextWindowLeft, TextWindowTop, TextWindowRight, TextWindowBottom);
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
  } while (!(Done));
}

/* Initialisation part of unit OVL04. */
void init_OVL04(void)
{
  POOL_TRACE("init");
  /* ovl04:0F32. The unit's initialisation part is empty: the compiler emits only `55 89 E5 5D CB`
     (push bp; mov bp, sp; pop bp; retf, the frame with no body), so the Temple runs no code when the
     program starts; its work happens only when VisitTemple is called. */
}
