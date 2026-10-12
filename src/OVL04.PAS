unit OVL04;
{ Temple: the temple shop of a town (whitepaper 5.19). The entry (VisitTemple) offers Heal, View,
  Take, Pool, Share, Appraise and Exit; HealMenu lists nine cleric services plus Exit, each a
  routine here
  (CureBlindness, CureDisease, CureWounds, NeutralizePoison, RaiseDead, RemoveCurse,
  StoneToFlesh). Most of them check the selected character, ask for confirmation when the service
  is not needed (AskCastAnyway), take the price (ChargeForCure) and add or remove the affect
  through ovl24_e2/e5; the ones that differ: CureWounds never asks (ovl04:0401) and heals through
  ovl24_e8/e21, and RemoveCurse applies through ovl22_e9 (ovl04:083A), not the ovl24 affect
  routines. }
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
  Yes = 'Y';                    { the answer key ovl25_e5 returns for yes }
  No = 'N';
  { Affect numbers (the ids res12_fn_2199 and ovl24_e2 look for in a character's affect list). }
  AffectBlind = $21;            { Cure Blindness checks and removes it (ovl04:0262) }
  AffectCurse = $24;            { Remove Curse accepts it as a reason to cast (ovl04:08A0) }
  AffectPoison = $37;           { Neutralize Poison checks it; Raise Dead also removes it }
  AffectPoison2 = $16;          { removed with AffectPoison by Neutralize Poison (ovl04:07F1) }
  AffectPoison3 = $0F;          { removed with AffectPoison by Neutralize Poison (ovl04:0807) }
  AffectDeath = $20;            { removed by Raise Dead before AffectPoison (ovl04:05B8) }
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
  HealMenuLines = 10;           { lines ovl25_e6 builds for the Heal menu }
  KeyEnter = #13;
  KeyNone = #0;                 { treated as Escape/Cancel; ovl25_e2/e4 are still stubs, so this comes
                                  from the callers (an extended key returns #0 first, whitepaper 5.8), not
                                  from the callee's own bytes }
  AnswerNo = 1;                 { ovl07_e13 returns the 0-based hotkey position: for '~Yes ~No' the
                                  second key (No) is 1, the value VisitTemple leaves on }

{ ovl04:0013. Shows Reason for the selected character (res12_fn_16EC, e.g. "is not blind.") and
  asks "cast cure anyway: "; returns the key (Yes or not). res12_fn_17E3 clears the prompt. }
function AskCastAnyway(Reason: string): Char;
begin
  res12_fn_16EC(SelectedCharacter, Reason, 0, 0);
  AskCastAnyway := ovl25_e5('cast cure anyway: ', 13, 10, 15);
  res12_fn_17E3;
end;

{ ovl04:00BF. Tells what Service costs ("<service> will only cost <price> gold pieces."), asks
  "pay for cure", and on Yes takes Price from the selected character's money (ovl19_e11, then
  ovl21_e10) or else from the pooled money DS:67F4 (ovl21_e12, then ovl21_e11). When neither
  covers the price it says "Not enough money." and the answer becomes No. On Yes it shows
  "is cured.". Returns the answer.
  QUIRK ovl04:0177: ovl19_e11 returns a LongInt, but Money is a Word, so only AX is kept and a
  character with 65536 or more is compared and charged modulo 65536 (a price can fit when only the
  low word does, and ovl21_e10 then stores the low word less the price). QUIRK ovl04:01C8: the pool
  path computes Pooled - Price as a LongInt but ovl21_e11(Amount: Word) receives only the low word,
  so a pool above 65535 is rewritten with the truncated amount (the same truncations as ovl06's
  BuyItems). }
function ChargeForCure(Service: string; Price: Word): Char;
var
  Answer: Char;
  Money: Word;
  Pooled: LongInt;
begin
  Service := Service + ' will only cost ' + res12_fn_1073(Price) + ' gold pieces.';
  ShowPagedText(1, $11, $26, $16, $A, 1, Service);
  Answer := ovl25_e5('pay for cure ', 13, 15, 10);
  if Answer = Yes then
  begin
    Money := ovl19_e11(SelectedCharacter);   { QUIRK ovl04:0177: a LongInt kept in a Word }
    if Price <= Money then
    begin
      Dec(Money, Price);
      ovl21_e10(Money);
    end
    else
    begin
      Pooled := ovl21_e12(ds67F4);
      if Price <= Pooled then
      begin
        Dec(Pooled, Price);
        ovl21_e11(Pooled);   { QUIRK ovl04:01C8: only the low word of the LongInt is passed }
      end
      else
      begin
        res12_fn_1693('Not enough money.');
        Answer := No;
      end;
    end;
  end;
  if Answer = Yes then
  begin
    res12_fn_17E3;
    res12_fn_16EC(SelectedCharacter, 'is cured.', 0, 1);
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
  if not res12_fn_2199(SelectedCharacter, AffectBlind, Affect) then
    Answer := AskCastAnyway('is not blind.');
  if Answer = Yes then
  begin
    Answer := ChargeForCure('Cure Blindness', PriceCureBlindness);
    if Answer = Yes then ovl24_e2(SelectedCharacter, AffectBlind, nil);
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
    if res12_fn_2199(SelectedCharacter, DiseaseAffects[I], Affect) then Diseased := True;
  if not Diseased then Answer := AskCastAnyway('is not Diseased.');
  if Answer = Yes then
  begin
    Answer := ChargeForCure('Cure Disease', PriceCureDisease);
    if Answer = Yes then
    begin
      ds681F := 1;
      for I := 1 to DiseaseCount do ovl24_e2(SelectedCharacter, DiseaseAffects[I], nil);
      ds681F := 0;
    end;
  end;
end;

{ ovl04:0401. Cure Light, Serious or Critical Wounds (Strength 1, 2 or 3): charges 100, 350 or
  600 and heals 1d8, 2d8+1 or 3d8+3 hit points (ovl24_e8 rolls, ovl24_e21 heals). }
procedure CureWounds(Strength: Byte);
var
  Amount: Byte;
  Answer: Char;
  Healed: Boolean;
begin
  case Strength of
    1:
      begin
        Answer := ChargeForCure('Cure Light Wounds', PriceCureLight);
        if Answer = Yes then
        begin
          Amount := ovl24_e8(1, 8);
          Healed := ovl24_e21(SelectedCharacter, Amount, 0);
        end;
      end;
    2:
      begin
        Answer := ChargeForCure('Cure Serious Wounds', PriceCureSerious);
        if Answer = Yes then
        begin
          Amount := ovl24_e8(2, 8) + 1;
          Healed := ovl24_e21(SelectedCharacter, Amount, 0);
        end;
      end;
    3:
      begin
        Answer := ChargeForCure('Cure Critical Wounds', PriceCureCritical);
        if Answer = Yes then
        begin
          Amount := ovl24_e8(3, 8) + 3;
          Healed := ovl24_e21(SelectedCharacter, Amount, 0);
        end;
      end;
  end;
end;

{ ovl04:0510. Raise Dead: the character is dead when its Status is StatusDead or StatusGone;
  otherwise asks first. Charges PriceRaiseDead; only a dead character is raised: AffectDeath
  and AffectPoison are removed, Status becomes StatusOkay, Flag10D and Flag11B become 1, and the
  character loses a point of constitution. From constitution 14 up the hit points above HpB1 are
  divided by the constitution bonus of all its class levels (a fighter level counts
  constitution - 14; a non-fighter level counts twice once the constitution is above 15, else 1),
  and that share is taken off HpMax unless the constitution is 17 or more and the character has
  no fighter level. }
procedure RaiseDead;
var
  Affect: Pointer;
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
        ovl24_e2(Who, AffectDeath, nil);
        ovl24_e2(Who, AffectPoison, nil);
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
  PriceNeutralizePoison and removes AffectPoison, AffectPoison2 and AffectPoison3. }
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
  if res12_fn_2199(SelectedCharacter, AffectPoison, Affect) then Poisoned := True;
  if not Poisoned then Answer := AskCastAnyway('is not poisoned.');
  if Answer = Yes then
  begin
    Answer := ChargeForCure('Neutralize Poison', PriceNeutralizePoison);
    if Answer = Yes then
    begin
      ds681F := 1;
      ovl24_e2(SelectedCharacter, AffectPoison, nil);
      ovl24_e2(SelectedCharacter, AffectPoison2, nil);
      ovl24_e2(SelectedCharacter, AffectPoison3, nil);
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
  if not Cursed and not res12_fn_2199(SelectedCharacter, AffectCurse, Affect) then
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

{ ovl04:0928. Stone to Flesh: asks first when the character's Status is not StatusStoned;
  charges PriceStoneToFlesh and, for a stoned character, sets Status to StatusOkay and Flag10D
  and Flag11B to 1. }
procedure StoneToFlesh;
var
  Affect: Pointer;
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

{ ovl04:09D7. The Heal menu: fills ten menu lines (ovl25_e6) with TempleMenuText, draws the
  windows and "<name>, how can we help you?", and runs the menu (ovl25_e4, keys "Heal Exit")
  until Exit or Escape; Heal or Enter on lines 0..8 runs that service, line 9 is Exit. Frees the
  lines (ovl25_e7), clears the text area (ClearRect(0, 0, 39, 24)), redraws the view
  (res12_fn_27D9) and reshows the character (res12_fn_0767(SelectedCharacter)). }
procedure HealMenu;
var
  List: PMenuLine;
  First: PMenuLine;
  MenuFlag: Byte;                 { the var Flag of ovl25_e4: set to 1 before the menu and never
                                    read here (VisitTemple gates on its own MenuFlag) }
  I: Byte;
  Choice: Integer;
  Done: Boolean;
  Prompt: String40;
  Key: Char;
begin
  Done := False;
  List := nil;
  First := nil;
  ovl25_e6(HealMenuLines, List);
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
  ClearRect(0, 24, 39, 24);
  MenuFlag := 1;
  DrawWindow(1, 1, $26, $16, 0, $F, '');
  DrawWindow(1, 1, $26, 1, 0, $F, '');
  repeat
    Prompt := SelectedCharacter^.Name + ', how can we help you?';
    res06_fn_0626(1, 1, $F, Prompt);
    DrawWindow(1, $11, $26, $16, 0, $F, '');
    Key := ovl25_e4('', 'Heal Exit', 13, 10, 15, 2, 4, $26, $F, List, 0, MenuFlag, Choice, First);
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
  ovl25_e7(List);
  ClearRect(0, 0, 39, 24);
  res12_fn_27D9;
  res12_fn_0767(SelectedCharacter);
end;

{ ovl04:0D09. The Temple: the menu Heal, View, Take, Pool, Share, Appraise, Exit (Take and
  Share only while ovl21_e9 reports pooled money). Heal opens HealMenu and Pool runs only when
  MenuFlag is 0; View ovl19_e5 receives MenuFlag, Take
  ovl21_e4, Pool ovl21_e2, Share ovl21_e3, Appraise ovl21_e14, G and O ovl19_e10. Exit with
  money left in the pool asks "Do you want to go back and retrieve your money?" ('~Yes ~No') and
  leaves on No (ovl07_e13 returns the 0-based hotkey position, 1 = No = AnswerNo); Yes keeps the
  money in the Temple. The trailing case (ovl04:0F02) also runs res12_fn_27D9 for a 'B'
  key with 'T' and for 'A' when Appraised is set, but neither menu text offers 'B'; what produces
  it is unknown. On entry it sets the view mode ds49F3 := 1, redraws the view (res12_fn_27D9) and
  reshows the character (res12_fn_0767), clears the pooled money DS:67F4 and sets ds6DC0 := 0. }
procedure VisitTemple;
var
  Key: Char;
  Done: Boolean;
  MenuFlag: Byte;         { the var Flag of ovl25_e2: 0 when the key was a menu choice, nonzero
                            when the menu did not take it (then H and P are skipped and View gets
                            it) [I] }
  Prompt: String40;
  MoneyPooled: Byte;      { nonzero while money lies in the pool (ovl21_e9's first result) }
  PoolSecond: Byte;       { ovl21_e9's second result; not read here }
  LeaveAnswer: Byte;      { the choice in the "retrieve your money" question }
  Appraised: Byte;        { set by Appraise (ovl21_e14); nonzero redraws the view }
begin
  ds49F3 := 1;
  res12_fn_27D9;
  res12_fn_0767(SelectedCharacter);
  FillChar(ds67F4, SizeOf(ds67F4), 0);
  ds6DC0 := 0;
  Done := False;
  repeat
    ovl21_e9(MoneyPooled, PoolSecond);
    if MoneyPooled <> 0 then
      Prompt := 'Heal View Take Pool Share Appraise Exit'
    else
      Prompt := 'Heal View Pool Appraise Exit';
    Key := ovl25_e2('', Prompt, 13, 10, 15, 1, 0, MenuFlag);
    case Key of
      'H': if MenuFlag = 0 then HealMenu;
      'V': ovl19_e5(MenuFlag);
      'T': ovl21_e4;
      'P': if MenuFlag = 0 then ovl21_e2;
      'S': ovl21_e3;
      'A': ovl21_e14(Appraised);
      'E':
        begin
          ovl21_e9(MoneyPooled, PoolSecond);
          if MoneyPooled <> 0 then
          begin
            Prompt := '~Yes ~No';
            ShowPagedText(1, $11, $26, $16, $A, 1,
              'As you leave a priest says, "Excuse me but you have left some money here" ');
            ShowPagedText(1, $11, $26, $16, $A, 1, 'Do you want to go back and retrieve your money?');
            LeaveAnswer := ovl07_e13('', Prompt, 13, 10, 15, 0, 0);
            if LeaveAnswer = AnswerNo then
              Done := True
            else
              ClearRect(1, $11, $26, $16);
          end
          else
            Done := True;
        end;
      'G': ovl19_e10(Key);
      'O': ovl19_e10(Key);
    end;
    case Key of
      'B', 'T': res12_fn_27D9;
      'A': if Appraised <> 0 then res12_fn_27D9;
    end;
    res12_fn_0767(SelectedCharacter);
  until Done;
end;

{ ovl04:0F32. The unit's initialisation part is empty: the compiler emits only `55 89 E5 5D CB`
  (push bp; mov bp, sp; pop bp; retf, the frame with no body), so the Temple runs no code when the
  program starts; its work happens only when VisitTemple is called. }
begin
end.
