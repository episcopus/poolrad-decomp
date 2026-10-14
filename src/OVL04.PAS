unit OVL04;
{ Temple: the town service shop (whitepaper 5.19). VisitTemple offers Heal, View, Take, Pool, Share,
  Appraise and Exit; HealMenu lists nine cleric services plus Exit. Most services check the selected
  character, ask for confirmation when unnecessary (AskCastAnyway), charge through ChargeForCure and
  remove affects through RemoveAffect. CureWounds does not ask and heals through RollDice and
  HealCharacter (ovl04:0401); RemoveCurse delegates to ovl22_e9 (ovl04:083A), not the ovl24 handlers. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
function AskCastAnyway(Reason: string): Char;
function ChargeForCure(Service: string; Price: Word): Char;
procedure CureBlindness;
procedure CureDisease;
procedure CureWounds(Strength: Byte);
procedure RaiseDead;
procedure NeutralizePoison;
procedure RemoveCurse;
procedure StoneToFlesh;
procedure HealMenu;
procedure VisitTemple;
implementation
uses POOLVARS, RES06, RES09, RES12, OVL07, OVL19, OVL21, OVL22, OVL24, OVL25;

const
  Yes = 'Y';                    { the answer key AskYesNo returns for yes }
  No = 'N';
  { Affect numbers (the ids HasAffect and RemoveAffect look for in a character's affect list). }
  AffectBlind = $21;            { Cure Blindness checks and removes it (ovl04:0262) }
  AffectCurse = $24;            { Remove Curse accepts it as a reason to cast (ovl04:08A0) }
  AffectPoison = $37;           { Neutralize Poison checks it; Raise Dead also removes it }
  AffectRemovedAtNeutralizePoison2 = $16; { purpose unknown; removed with $37 (ovl04:07F1) }
  AffectRemovedAtNeutralizePoison3 = $0F; { purpose unknown; removed with $37 (ovl04:0807) }
  AffectRemovedAtRaiseDead = $20;         { purpose unknown; removed before $37 (ovl04:05B8) }
  { Status values of TCharacter.Status. }
  StatusOkay = 0;
  StatusDead = 1;               { Raise Dead accepts 1 and 6 (ovl04:0539) }
  StatusGone = 6;
  StatusStoned = 7;             { Stone to Flesh (ovl04:093D) }
  { Prices in gold pieces (the second argument of ChargeForCure). }
  PriceCureBlindness = 1000;
  PriceCureDisease = 1000;
  PriceCureLight = 100;
  PriceCureSerious = 350;
  PriceCureCritical = 600;
  PriceNeutralizePoison = 1000;
  PriceRaiseDead = 5500;
  PriceRemoveCurse = 3500;
  PriceStoneToFlesh = 2000;
  DiseaseCount = 6;             { entries of DiseaseAffects }
  { The constitution rules of Raise Dead (ovl04:0652..0710). }
  BonusConstitution = 14;       { from 14 up the lost constitution can cost hit points }
  FighterClass = 2;             { index in ClassLevels with the larger bonus }
  HighConstitution = 15;        { above it a non-fighter class counts twice }
  FighterOnlyConstitution = 17; { from 17 up only a fighter level loses the hit points }
  LastClass = 7;
  HealMenuLines = 10;           { lines NewMenuList builds for the Heal menu }
  KeyEnter = #13;
  KeyNone = #0;                 { Escape returns #0 from ReadPromptChoice (ovl25:059F..05A7); Escape, E and #0
                                  return #0 from ChooseFromList (ovl25:105C..1074), ending HealMenu }
  AnswerNo = 1;                 { AskMenu returns the 0-based hotkey position: for '~Yes ~No' the
                                   second key (No) is 1, the value VisitTemple leaves on }
  PromptTitleColor = 13;         { title, word and hotkey colours of AskCastAnyway and VisitTemple }
  PromptWordColor = 10;
  PromptHotColor = 15;
  CostPromptWordColor = 15;      { ChargeForCure's pay prompt uses the latter two in reverse }
  CostPromptHotColor = 10;
  TempleTitleColor = $F;
  TempleFrameSet = 0;
  TempleLeft = 1;
  TempleRight = $26;
  TempleTop = 1;
  TempleBottom = $16;
  TempleHeaderBottom = 1;
  TextWindowLeft = 1;
  TextWindowTop = $11;
  TextWindowRight = $26;
  TextWindowBottom = $16;
  TextWindowColor = $A;          { the body text colour passed to ShowPagedText }
  HealListLeft = 2;
  HealListTop = 4;
  HealListRight = $26;
  HealListBottom = $F;
  HealListHeadingColor = 13;
  HealListLineColor = 10;
  HealListHighlightColor = 15;
  PromptClearLeft = 0;
  PromptClearRow = 24;
  PromptClearRight = 39;
  ScreenTopRow = 0;
  ScreenBottomRow = 24;
  AcceptExtendedKeys = 1;
  NoExtendedKeys = 0;
  NoAnimation = 0;
  ClearTextBeforeMessage = 1;    { ShowPagedText's ClearFirst parameter }

{ ovl04:0013. Shows Reason for the selected character (ShowCharacterMessage, e.g. "is not blind.") and
  asks "cast cure anyway: "; returns the key (Yes or not). ClearCharacterMessage clears the prompt. }
function AskCastAnyway(Reason: string): Char;
begin
  ShowCharacterMessage(SelectedCharacter, Reason, 0, 0);
  AskCastAnyway := AskYesNo('cast cure anyway: ', PromptTitleColor, PromptWordColor, PromptHotColor);
  ClearCharacterMessage;
end;

{ ovl04:00BF. Tells what Service costs ("<service> will only cost <price> gold pieces."), asks
  "pay for cure", and on Yes takes Price from the selected character's money (CharacterMoneyValueInGold, then
  SetCharacterGold) or else from the pooled money DS:67F4 (MoneyValueInGold, then SetPooledGold). When neither
  covers the price it says "Not enough money." and the answer becomes No. On Yes it shows
  "is cured.". Returns the answer.
  QUIRK ovl04:0177: CharacterMoneyValueInGold returns a LongInt, but Money is a Word, so only AX is kept and a
  character with 65536 or more is compared and charged modulo 65536 (a price can fit when only the
  low word does, and SetCharacterGold then stores the low word less the price). QUIRK ovl04:01C8: the pool
  path computes Pooled - Price as a LongInt but SetPooledGold(Amount: Word) receives only the low word,
  so a pool above 65535 is rewritten with the truncated amount (the same truncations as ovl06's
  BuyItems). }
function ChargeForCure(Service: string; Price: Word): Char;
var
  Answer: Char;
  Money: Word;
  Pooled: LongInt;
begin
  Service := Service + ' will only cost ' + WordToText(Price) + ' gold pieces.';
  ShowPagedText(TextWindowLeft, TextWindowTop, TextWindowRight, TextWindowBottom,
                TextWindowColor, 1, Service);
  Answer := AskYesNo('pay for cure ', PromptTitleColor, CostPromptWordColor, CostPromptHotColor);
  if Answer = Yes then
  begin
    Money := CharacterMoneyValueInGold(SelectedCharacter);   { QUIRK ovl04:0177: a LongInt kept in a Word }
    if Price <= Money then
    begin
      Dec(Money, Price);
      SetCharacterGold(Money);
    end
    else
    begin
      Pooled := MoneyValueInGold(PooledMoney);
      if Price <= Pooled then
      begin
        Dec(Pooled, Price);
        SetPooledGold(Pooled);   { QUIRK ovl04:01C8: only the low word of the LongInt is passed }
      end
      else
      begin
        ShowFlashMessage('Not enough money.');
        Answer := No;
      end;
    end;
  end;
  if Answer = Yes then
  begin
    ClearCharacterMessage;
    ShowCharacterMessage(SelectedCharacter, 'is cured.', 0, 1);
  end;
  ChargeForCure := Answer;
end;

{ ovl04:0249. Cure Blindness: asks first when the selected character is not blind (no
  AffectBlind), charges PriceCureBlindness and removes the affect. QUIRK ovl04:0250: Unused is
  cleared and never read (the same in every service routine). }
procedure CureBlindness;
var
  Affect: Pointer;
  Unused: string;
  Answer: Char;
begin
  Unused := '';
  Answer := Yes;
  if not HasAffect(SelectedCharacter, AffectBlind, Affect) then
    Answer := AskCastAnyway('is not blind.');
  if Answer = Yes then
  begin
    Answer := ChargeForCure('Cure Blindness', PriceCureBlindness);
    if Answer = Yes then RemoveAffect(SelectedCharacter, AffectBlind, nil);
  end;
end;

{ ovl04:02ED. Cure Disease: the character is diseased when it has one of the six
  DiseaseAffects; otherwise asks first. Charges PriceCureDisease and removes all six, with
  ds681F set while it does. }
procedure CureDisease;
var
  Affect: Pointer;
  Unused: string;
  Answer: Char;
  I: Byte;
  Diseased: Boolean;
begin
  Diseased := False;
  Unused := '';
  Answer := Yes;
  for I := 1 to DiseaseCount do
    if HasAffect(SelectedCharacter, DiseaseAffects[I], Affect) then Diseased := True;
  if not Diseased then Answer := AskCastAnyway('is not Diseased.');
  if Answer = Yes then
  begin
    Answer := ChargeForCure('Cure Disease', PriceCureDisease);
    if Answer = Yes then
    begin
      ds681F := 1;
      for I := 1 to DiseaseCount do RemoveAffect(SelectedCharacter, DiseaseAffects[I], nil);
      ds681F := 0;
    end;
  end;
end;

{ ovl04:0401. Cure Light, Serious or Critical Wounds (Strength 1, 2 or 3): charges 100, 350 or
  600 and heals 1d8, 2d8+1 or 3d8+3 hit points (RollDice rolls, HealCharacter heals). }
procedure CureWounds(Strength: Byte);
var
  Amount: Byte;
  Answer: Char;
  Healed: Boolean; { QUIRK ovl04:0401: HealCharacter's Boolean result is stored but never read }
begin
  case Strength of
    1:
      begin
        Answer := ChargeForCure('Cure Light Wounds', PriceCureLight);
        if Answer = Yes then
        begin
          Amount := RollDice(1, 8);
          Healed := HealCharacter(SelectedCharacter, Amount, 0);
        end;
      end;
    2:
      begin
        Answer := ChargeForCure('Cure Serious Wounds', PriceCureSerious);
        if Answer = Yes then
        begin
          Amount := RollDice(2, 8) + 1;
          Healed := HealCharacter(SelectedCharacter, Amount, 0);
        end;
      end;
    3:
      begin
        Answer := ChargeForCure('Cure Critical Wounds', PriceCureCritical);
        if Answer = Yes then
        begin
          Amount := RollDice(3, 8) + 3;
          Healed := HealCharacter(SelectedCharacter, Amount, 0);
        end;
      end;
  end;
end;

{ ovl04:0510. Raise Dead: the character is dead when Status is StatusDead or StatusGone; otherwise it
  asks first. Charges PriceRaiseDead; only a dead character is raised: AffectRemovedAtRaiseDead and
  AffectPoison are removed, Status becomes StatusOkay, Flag10D becomes 1 (battle participant eligible
  for experience, ovl05:0355), and Flag11B becomes 1. Flag11B is the current hit points [I], so this
  restores one hit point [I] (ovl24:175D). Constitution is reduced by one before the constitution
  thresholds are tested; from 14 up the hit points above HpB1 are divided by the bonus over all class
  levels (fighter levels count constitution - 14; non-fighter levels count twice above constitution 15,
  else 1). A bonus of 0 leaves the loss undivided. The loss is skipped at constitution 17 or more when
  the character has no fighter level. }
procedure RaiseDead;
var
  Affect: Pointer; { QUIRK ovl04:0510: frame pointer is never read or written }
  Unused: string;
  Answer: Char;
  Dead: Boolean;
  HpLoss: Byte;
  Bonus: Byte;
  I: ShortInt;
  Who: PCharacter;
begin
  Who := SelectedCharacter;
  Dead := False;
  Unused := '';
  Answer := Yes;
  if (Who^.Status = StatusGone) or (Who^.Status = StatusDead) then Dead := True;
  if not Dead then Answer := AskCastAnyway('is not dead.');
  if Answer = Yes then
  begin
    Answer := ChargeForCure('Raise Dead', PriceRaiseDead);
    if Answer = Yes then
      if Dead then
      begin
        ds681F := 1;
        RemoveAffect(Who, AffectRemovedAtRaiseDead, nil);
        RemoveAffect(Who, AffectPoison, nil);
        ds681F := 0;
        Who^.Flag11B := 1;
        Who^.Status := StatusOkay;
        Who^.Flag10D := 1;
        if Who^.Constitution > 0 then Dec(Who^.Constitution);
        if Who^.HpMax > Who^.HpB1 then
          HpLoss := Who^.HpMax - Who^.HpB1
        else
          HpLoss := 0;
        Bonus := 0;
        if Who^.Constitution >= BonusConstitution then
        begin
          for I := 0 to LastClass do
            if Who^.ClassLevels[I] > 0 then
              if I = FighterClass then
                Inc(Bonus, (Who^.Constitution - BonusConstitution) * Who^.ClassLevels[I])
              else if Who^.Constitution > HighConstitution then
                Inc(Bonus, Who^.ClassLevels[I] * 2)
              else
                Inc(Bonus, Who^.ClassLevels[I]);
          if Bonus > 0 then HpLoss := HpLoss div Bonus;
          if (Who^.Constitution < FighterOnlyConstitution) or (Who^.ClassLevels[FighterClass] > 0) then
            Dec(Who^.HpMax, HpLoss);
        end;
      end;
  end;
end;

{ ovl04:0751. Neutralize Poison: asks first when the character has no AffectPoison; charges
  PriceNeutralizePoison and removes AffectPoison plus values $16 and $0F (their meanings are unknown). }
procedure NeutralizePoison;
var
  Affect: Pointer;
  Unused: string;
  Answer: Char;
  Poisoned: Boolean;
begin
  Poisoned := False;
  Unused := '';
  Answer := Yes;
  if HasAffect(SelectedCharacter, AffectPoison, Affect) then Poisoned := True;
  if not Poisoned then Answer := AskCastAnyway('is not poisoned.');
  if Answer = Yes then
  begin
    Answer := ChargeForCure('Neutralize Poison', PriceNeutralizePoison);
    if Answer = Yes then
    begin
      ds681F := 1;
      RemoveAffect(SelectedCharacter, AffectPoison, nil);
      RemoveAffect(SelectedCharacter, AffectRemovedAtNeutralizePoison2, nil);
      RemoveAffect(SelectedCharacter, AffectRemovedAtNeutralizePoison3, nil);
      ds681F := 0;
    end;
  end;
end;

{ ovl04:083A. Remove Curse: the character needs it when one of its items is cursed or it has
  AffectCurse; otherwise asks first. Charges PriceRemoveCurse and hands the character to
  ovl22_e9 through ds6C95. }
procedure RemoveCurse;
var
  Cursed: Boolean;
  Item: PItem;
  Affect: Pointer;
  Unused: string;
  Answer: Char;
begin
  Unused := '';
  Answer := Yes;
  Cursed := False;
  Item := SelectedCharacter^.Items;
  while (Item <> nil) and not Cursed do
  begin
    if Item^.Cursed then Cursed := True;
    Item := Item^.Next;
  end;
  if not Cursed and not HasAffect(SelectedCharacter, AffectCurse, Affect) then
    Answer := AskCastAnyway('is not cursed.');
  if Answer = Yes then
  begin
    Answer := ChargeForCure('Remove Curse', PriceRemoveCurse);
    if Answer = Yes then
    begin
      ds6C95 := SelectedCharacter;
      ovl22_e9;
    end;
  end;
end;

{ ovl04:0928. Stone to Flesh: asks first when Status is not StatusStoned; charges PriceStoneToFlesh
  and, for a stoned character, sets Status to StatusOkay, Flag10D to 1 (experience eligible,
  ovl05:0355) and Flag11B to 1. Flag11B is the current hit points [I], so this restores one hit point [I]
  (ovl24:175D). }
procedure StoneToFlesh;
var
  Affect: Pointer; { QUIRK ovl04:0928: frame pointer is never read or written }
  Unused: string;
  Answer: Char;
begin
  Unused := '';
  Answer := Yes;
  if SelectedCharacter^.Status <> StatusStoned then Answer := AskCastAnyway('is not stoned.');
  if Answer = Yes then
  begin
    Answer := ChargeForCure('Stone to Flesh', PriceStoneToFlesh);
    if Answer = Yes then
      if SelectedCharacter^.Status = StatusStoned then
      begin
        SelectedCharacter^.Status := StatusOkay;
        SelectedCharacter^.Flag10D := 1;
        SelectedCharacter^.Flag11B := 1;
      end;
  end;
end;

{ ovl04:09D7. The Heal menu: fills ten menu lines with TempleMenuText, clears row 24, draws the windows and
  "<name>, how can we help you?", and runs ChooseFromList with "Heal Exit" until Exit or Escape.
  Heal or Enter on lines 0..8 runs that service; line 9 is Exit. RedrawList requests the initial page
  draw and is cleared by ChooseFromList. Frees the lines, clears the whole screen (columns 0..39, rows
  0..24) and redraws the view and reshows SelectedCharacter. }
procedure HealMenu;
var
  List: PMenuLine;
  First: PMenuLine;
  RedrawList: Byte;               { ChooseFromList's var Redraw: requests the entry-page draw }
  I: Byte;
  Choice: Integer;
  Done: Boolean;
  Prompt: String40;
  Key: Char;
begin
  Done := False;
  List := nil;
  First := nil;
  NewMenuList(HealMenuLines, List);
  First := List;
  I := 1;
  while List <> nil do
  begin
    List^.Text := TempleMenuText[I];
    List^.Flag29 := 0;
    List := List^.Next;
    Inc(I);
  end;
  List := First;
  ClearRect(PromptClearLeft, PromptClearRow, PromptClearRight, PromptClearRow);
  RedrawList := 1;
  DrawWindow(TempleLeft, TempleTop, TempleRight, TempleBottom, TempleFrameSet, TempleTitleColor, '');
  DrawWindow(TempleLeft, TempleTop, TempleRight, TempleHeaderBottom,
             TempleFrameSet, TempleTitleColor, '');
  repeat
    Prompt := SelectedCharacter^.Name + ', how can we help you?';
    DrawTextAt(TempleLeft, TempleTop, TempleTitleColor, Prompt);
    DrawWindow(TextWindowLeft, TextWindowTop, TextWindowRight, TextWindowBottom,
               TempleFrameSet, TempleTitleColor, '');
    Key := ChooseFromList('', 'Heal Exit', HealListHeadingColor, HealListLineColor,
                          HealListHighlightColor, HealListLeft, HealListTop, HealListRight,
                          HealListBottom, List, 0, RedrawList, Choice, First);
    case Key of
      'H', KeyEnter:
        case Choice of
          0: CureBlindness;
          1: CureDisease;
          2: CureWounds(1);
          3: CureWounds(2);
          4: CureWounds(3);
          5: NeutralizePoison;
          6: RaiseDead;
          7: RemoveCurse;
          8: StoneToFlesh;
          9: Done := True;
        end;
      KeyNone: Done := True;
    end;
  until Done;
  FreeMenuList(List);
  ClearRect(PromptClearLeft, ScreenTopRow, PromptClearRight, ScreenBottomRow);
  RedrawView;
  DrawPartyRoster(SelectedCharacter);
end;

{ ovl04:0D09. The Temple menu offers Heal, View, Take, Pool, Share, Appraise and Exit (Take and Share
  only while TreasureLeft reports pooled money). Heal and Pool run only when ExtKey is 0; View receives
  ExtKey, and G/O scan letters (Home/End, or keypad 7/1) go to UpdateSelectedCharacter. The trailing B redraw arm at
  ovl04:0F02 is not in the menu text. ReadPromptChoice can return scan letters for extended keys, but
  the physical key that yields B is unknown. Exit with money in the pool asks "Do you want to go back
  and retrieve your money?" ('~Yes ~No') and leaves on No (AskMenu returns position 1); Yes keeps the
  money in the Temple. On entry it sets ds49F3 to 1, redraws the view and character, clears PooledMoney
  and sets MoneyInPool to 0. }
procedure VisitTemple;
var
  Key: Char;
  Done: Boolean;
  ExtKey: Byte;            { 1 for an extended key (ovl25:0580..0591) or a keypad digit (ovl25:0691..06C7) }
  Prompt: String40;
  MoneyPooled: Byte;      { nonzero while money lies in the pool (TreasureLeft's first result) }
  PoolSecond: Byte;       { TreasureLeft's second result; not read here }
  LeaveAnswer: Byte;      { the choice in the "retrieve your money" question }
  Appraised: Byte;        { set by Appraise (AppraiseGems); nonzero redraws the view }
begin
  ds49F3 := 1;
  RedrawView;
  DrawPartyRoster(SelectedCharacter);
  FillChar(PooledMoney, SizeOf(PooledMoney), 0);
  MoneyInPool := 0;
  Done := False;
  repeat
    TreasureLeft(MoneyPooled, PoolSecond);
    if MoneyPooled <> 0 then
      Prompt := 'Heal View Take Pool Share Appraise Exit'
    else
      Prompt := 'Heal View Pool Appraise Exit';
    Key := ReadPromptChoice('', Prompt, PromptTitleColor, PromptWordColor, PromptHotColor,
                            AcceptExtendedKeys, NoAnimation, ExtKey);
    case Key of
      'H': if ExtKey = 0 then HealMenu;
      'V': ViewSelectedCharacter(ExtKey);
      'T': TakeMoney;
      'P': if ExtKey = 0 then PoolMoney;
      'S': ShareMoney;
      'A': AppraiseGems(Appraised);
      'E':
        begin
          TreasureLeft(MoneyPooled, PoolSecond);
          if MoneyPooled <> 0 then
          begin
            Prompt := '~Yes ~No';
            ShowPagedText(TextWindowLeft, TextWindowTop, TextWindowRight, TextWindowBottom,
              TextWindowColor, ClearTextBeforeMessage,
              'As you leave a priest says, "Excuse me but you have left some money here" ');
            ShowPagedText(TextWindowLeft, TextWindowTop, TextWindowRight, TextWindowBottom,
              TextWindowColor, ClearTextBeforeMessage, 'Do you want to go back and retrieve your money?');
            LeaveAnswer := AskMenu('', Prompt, PromptTitleColor, PromptWordColor, PromptHotColor,
                                   NoExtendedKeys, NoAnimation);
            if LeaveAnswer = AnswerNo then
              Done := True
            else
              ClearRect(TextWindowLeft, TextWindowTop, TextWindowRight, TextWindowBottom);
          end
          else
            Done := True;
        end;
      'G': UpdateSelectedCharacter(Key);
      'O': UpdateSelectedCharacter(Key);
    end;
    case Key of
      'B', 'T': RedrawView;
      'A': if Appraised <> 0 then RedrawView;
    end;
    DrawPartyRoster(SelectedCharacter);
  until Done;
end;

{ ovl04:0F32. The unit's initialisation part is empty: the compiler emits only `55 89 E5 5D CB`
  (push bp; mov bp, sp; pop bp; retf, the frame with no body), so the Temple runs no code when the
  program starts; its work happens only when VisitTemple is called. }
begin
end.
