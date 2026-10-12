unit OVL05;
{ TreasureShare: the aftermath of a battle (whitepaper 5.20). EndBattle, the overlay's entry, runs after
  a combat: SettleBattleOutcome decides from the combatants' Status and Side whether the party won,
  fled or was destroyed and awards the experience (ComputeBattleExperience, AwardExperience);
  RemoveBattleCombatants takes the monsters out of the party list; TakeHirelingShares lets the
  computer-run members take their share of the money; ShowBattleResult shows the result and the
  experience; TreasureMenu (View Take Pool Share Detect Exit) hands out the loot, with TakeTreasure,
  TakeLootItems and ChooseLootItem for the items. A destroyed party gets "The END!" instead. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure ComputeBattleExperience(var Xp: LongInt);
procedure AwardExperience(Xp: LongInt);
procedure SettleBattleOutcome;
procedure ShowBattleResult(Xp: LongInt);
procedure ChooseLootItem(var Key: Char; var Item: PMenuLine; var Selected: PMenuLine; var Choice: Integer);
procedure TakeLootItems;
procedure TakeTreasure(var MoneyLeft, ItemsLeft: Byte);
procedure TreasureMenu;
procedure RemoveBattleCombatants;
procedure TakeHirelingShares;
procedure EndBattle;
implementation
uses RES06, RES09, RES12, OVL06, OVL07, OVL16, OVL19, OVL21, OVL22, OVL24, OVL25;

const
  { Words of ds49D6^ (the second game word block) this unit reads or writes. }
  VarBattleOutcome = 711;       { EndBattle sets 0, $80 when the party is destroyed, $81 when it fled (ovl05:06B1) }
  VarRemovedCount = 712;        { combatants RemoveBattleCombatants removed whose Flag10D is not 1 (ovl05:11FA) }
  VarNoItemLoot = 739;          { 1: the defeated monsters' items are not looted (ovl05:00FB) }
  { Nonzero: a duel gives 100 experience per level of the selected character (ovl05:000D), and a
    non-duel battle counts every player-run member as standing (ovl05:058D). Cleared by EndBattle. }
  VarFixedXpBattle = 742;
  VarPartySize = 830;           { the members; ovl16_e2 decrements it when it removes a counted one }
  VarAfterBattle1 = 880;        { three words EndBattle clears (ovl05:163C..1652); meaning unknown }
  VarAfterBattle2 = 881;
  VarAfterBattle3 = 882;
  BattleOutcomeDestroyed = $80;
  BattleOutcomeFled = $81;
  { TCharacter.Status values. }
  StatusOkay = 0;
  StatusDead = 1;
  StatusFled = 3;               { left the battle: back to okay when the party survives }
  StatusUnconscious = 4;        { what Bandage gives (whitepaper 5.5) }
  StatusDying = 5;              { becomes unconscious when the battle ends }
  { TCharacter.Side values. }
  SideParty = 0;
  SideMonsters = 1;
  ComputerRun = $80;            { TCharacter.B84 from $80 up: a member the player does not run (a hireling) }
  ShareMask = 7;                { the bits of HirelingShare that are the share }
  ExtraCombatant = 1;           { TCombatant.NoBody: a combatant that is not a real party member }
  { TCharacter.ClassMask values of AwardExperience: the four single classes whose prime requisite
    above PrimeRequisiteBonus gives 10% more experience. }
  ClassCleric = 0;
  ClassFighter = 2;
  ClassMagicUser = 5;
  ClassThief = 6;
  PrimeRequisiteBonus = 15;
  { The two memorized spells that add Detect to the treasure menu [I]: the cleric's and the
    magic-user's Detect Magic in the order of the Gold Box spell list. }
  SpellClericDetectMagic = 5;
  SpellMageDetectMagic = $B;
  LastSpellSlot = 20;           { TCharacter.Spells is 0..20 }
  LastMoneyKind = 6;            { TPartyMoney and TCharacter.Money are 0..6 }
  { The experience value of each kind of pooled money (ComputeBattleExperience). }
  CopperPerXp = 200;
  SilverPerXp = 20;
  ElectrumPerXp = 2;
  XpPerPlatinum = 5;
  XpPerGem = 250;
  XpPerJewel = 2200;
  XpPerPlus = 400;              { per point of Plus of a looted magic item }
  XpPerLevel = 100;             { a fixed-experience duel }
  MaxWorthlessItems = 8;        { items of no value taken from monsters before they are left behind }
  WorthlessItemChance = 3;      { a worthless item is taken when 1d10 is at most this }
  ItemListSize = $3F;           { SizeOf(TMenuLine): FreeMem sizes }
  CombatStateSize = $16;        { the size of a character's combat state (TCharacter.Combat) }
  AnswerNo = 1;                 { AskMenu returns the 0-based word of '~Yes ~No' }
  KeyEnter = #13;
  KeyNone = #0;

{ ovl05:0000. Computes the experience each character gets for the battle and gathers the loot.
  In a duel with VarFixedXpBattle set, Xp is 100 per level (HighestLevel) of SelectedCharacter.
  Otherwise every monster (Side 1) that did not flee adds its money to PooledMoney, its XpValue plus
  HpB1 times XpPerHp to the total, and, unless VarNoItemLoot is 1, its items as clones to the loot
  list ds6810 (res12_fn_0442 first): every item with a Value, but worthless items only while fewer
  than 8 items were taken and with a 1d10 of 3 or less. Then the pooled money adds its value
  (copper / 200 ... jewels * 2200) and each looted item before ds5D9A adds 400 per point of Plus.
  Xp is the total divided by the party size (VarPartySize) less NoExperienceCount. Sets
  MonstersLooted when a monster was looted. QUIRK ovl05:002B: the level product is an Integer
  multiplication extended to LongInt. }
procedure ComputeBattleExperience(var Xp: LongInt);
var
  Who: PCharacter;
  Kind: ShortInt;
  Total: LongInt;
  Entry: PMenuLine;             { the earlier head of the loot list, then the loot walk }
  Item: PMenuLine;
  Taken: Byte;
begin
  if (DuelMode <> 0) and (ds49D6^[VarFixedXpBattle] <> 0) then
    Xp := SelectedCharacter^.HighestLevel * XpPerLevel
  else
  begin
    Total := 0;
    Who := PCharacter(ds5D96);
    Taken := 0;
    while Who <> nil do
    begin
      Item := Who^.Items;
      if (Who^.Side = SideMonsters) and (Who^.Status <> StatusFled) then
      begin
        MonstersLooted := 1;
        for Kind := 0 to LastMoneyKind do
          Inc(PooledMoney[Kind], Who^.Money[Kind]);
        Total := Who^.XpValue + Total + Who^.XpPerHp * Who^.HpB1;
        if ds49D6^[VarNoItemLoot] <> 1 then
          while Item <> nil do
          begin
            if (Item^.Value > 0) or
              ((Taken < MaxWorthlessItems) and (RollDice(1, 10) <= WorthlessItemChance)) then
            begin
              Inc(Taken);
              if ds6810 = nil then
              begin
                New(ds6810);
                res12_fn_0442(LongInt(Who), Item, 0, 0, 0, 0);
                ds6810^ := Item^;
                ds6810^.Readied := False;
                ds6810^.Next := nil;
              end
              else
              begin
                Entry := ds6810;
                New(ds6810);
                res12_fn_0442(LongInt(Who), Item, 0, 0, 0, 0);
                ds6810^ := Item^;
                ds6810^.Readied := False;
                ds6810^.Next := Entry;
              end;
            end;
            Item := Item^.Next;
          end;
      end;
      Who := Who^.Next;
    end;
    Inc(Total, PooledMoney[0] div CopperPerXp);
    Inc(Total, PooledMoney[1] div SilverPerXp);
    Inc(Total, PooledMoney[2] div ElectrumPerXp);
    Inc(Total, PooledMoney[3]);
    Inc(Total, PooledMoney[4] * XpPerPlatinum);
    Inc(Total, PooledMoney[5] * XpPerGem);
    Inc(Total, PooledMoney[6] * XpPerJewel);
    Entry := ds6810;
    while (Entry <> nil) and (Entry <> ds5D9A) do
    begin
      if Entry^.Plus > 0 then
        Inc(Total, Entry^.Plus * XpPerPlus);
      Entry := Entry^.Next;
    end;
    Xp := Total div (ds49D6^[VarPartySize] - NoExperienceCount);
  end;
end;

{ ovl05:0355. Adds Xp to the Experience of every member of the party list (ds5D96) that has Flag10D
  set and is not dead: 10% more for a cleric, fighter, magic-user or thief whose prime requisite
  (Wisdom, Strength, Intelligence, Dexterity) is above 15, half for the two-class combinations and
  a third for the three-class ones (ClassMask 8, 10..14, 16 and 9, 15). }
procedure AwardExperience(Xp: LongInt);
var
  Who: PCharacter;
  Gain: LongInt;
begin
  Who := PCharacter(ds5D96);
  while Who <> nil do
  begin
    if (Who^.Flag10D <> 0) and (Who^.Status <> StatusDead) then
    begin
      Gain := Xp;
      case Who^.ClassMask of
        ClassCleric: if Who^.Wisdom > PrimeRequisiteBonus then Gain := Xp div 10 + Xp;
        ClassFighter: if Who^.Strength > PrimeRequisiteBonus then Gain := Xp div 10 + Xp;
        ClassMagicUser: if Who^.Intelligence > PrimeRequisiteBonus then Gain := Xp div 10 + Xp;
        ClassThief: if Who^.Dexterity > PrimeRequisiteBonus then Gain := Xp div 10 + Xp;
        8, 10..14, 16: Gain := Xp div 2;
        9, 15: Gain := Xp div 3;
      end;
      Inc(Who^.Experience, Gain);
    end;
    Who := Who^.Next;
  end;
end;

{ ovl05:04C9. Decides how the battle ended and applies it to the party list (ds5D96); the walks stop
  at the first extra combatant (TCombatant.NoBody = 1). PartyFled is set when a member has fled
  (Status 3). In a battle (not DuelMode): PartyDestroyed stays 1 unless a player-run member (Side 0,
  B84 below $80) is okay, dead or fled (or VarFixedXpBattle is 1); BattleWon is set and PartyFled
  cleared when a combatant is okay or dead; NoExperienceCount counts the members without Flag10D or
  dead. A won battle computes and awards BattleExperience. A surviving party gets its fled members
  back (Status 0, Flag10D 1), dying ones unconscious, unconscious ones with Flag11B back to okay; a
  fled party (VarBattleOutcome $81) keeps only its fled members, the others leave the list
  (ovl16_e2). A destroyed party leaves the list entirely and VarPartySize becomes 0. In a duel the
  duelist (Flag10D 1, okay, not a monster) wins the experience, every okay or dead combatant gets
  Flag10D and the dying become unconscious. }
procedure SettleBattleOutcome;
var
  Who: PCharacter;
  Stop: Boolean;
  Unused: Byte;                 { QUIRK ovl05:04CC: the frame has a sixth byte nothing uses }
begin
  NoExperienceCount := 0;
  PartyDestroyed := 1;
  PartyFled := 0;
  Who := PCharacter(ds5D96);
  while (Who <> nil) and (Who^.Combat^.NoBody <> ExtraCombatant) do
  begin
    if Who^.Status = StatusFled then
      PartyFled := 1;
    Who := Who^.Next;
  end;
  if DuelMode <> 0 then
    PartyDestroyed := 0;
  BattleWon := 0;
  Who := PCharacter(ds5D96);
  if DuelMode = 0 then
  begin
    while (Who <> nil) and (Who^.Combat^.NoBody <> ExtraCombatant) do
    begin
      if ((Who^.Status = StatusFled) or (Who^.Status = StatusDead) or (Who^.Status = StatusOkay) or
        (ds49D6^[VarFixedXpBattle] = 1)) and (Who^.Side = SideParty) and (Who^.B84 < ComputerRun) then
        PartyDestroyed := 0;
      if (Who^.Status = StatusDead) or (Who^.Status = StatusOkay) then
      begin
        BattleWon := 1;
        PartyFled := 0;
      end;
      if (Who^.Flag10D = 0) or (Who^.Status = StatusDead) then
        Inc(NoExperienceCount);
      Who := Who^.Next;
    end;
    if BattleWon <> 0 then
    begin
      ComputeBattleExperience(BattleExperience);
      AwardExperience(BattleExperience);
    end;
    Who := PCharacter(ds5D96);
    if PartyDestroyed = 0 then
    begin
      while (Who <> nil) and (Who^.Combat^.NoBody <> ExtraCombatant) do
      begin
        if PartyFled = 0 then
        begin
          case Who^.Status of
            StatusFled:
              begin
                Who^.Status := StatusOkay;
                Who^.Flag10D := 1;
              end;
            StatusDying: Who^.Status := StatusUnconscious;
            StatusUnconscious:
              if Who^.Flag11B > 0 then
              begin
                Who^.Status := StatusOkay;
                Who^.Flag10D := 1;
              end;
          end;
        end
        else
        begin
          ds49D6^[VarBattleOutcome] := BattleOutcomeFled;
          if Who^.Status = StatusFled then
          begin
            Who^.Status := StatusOkay;
            Who^.Flag10D := 1;
          end
          else
          begin
            SelectedCharacter := Who;
            ovl16_e2(False, True);
          end;
        end;
        Who := Who^.Next;
      end;
    end
    else
    begin
      Who := PCharacter(ds5D96);
      Stop := False;
      while (Who <> nil) and not Stop do
      begin
        if Who^.Combat^.NoBody <> ExtraCombatant then
        begin
          SelectedCharacter := Who;
          ovl16_e2(False, True);
        end
        else
          Stop := True;
        Who := Who^.Next;
      end;
      ds49D6^[VarPartySize] := 0;
    end;
  end
  else
  begin
    Who := PCharacter(ds5D96);
    while Who <> nil do
    begin
      if (Who^.Flag10D = 1) and (Who^.Status = StatusOkay) and (Who^.Side <> SideMonsters) then
      begin
        BattleWon := 1;
        ComputeBattleExperience(BattleExperience);
        AwardExperience(BattleExperience);
      end;
      Who := Who^.Next;
    end;
    Who := PCharacter(ds5D96);
    while Who <> nil do
    begin
      if (Who^.Status = StatusOkay) or (Who^.Status = StatusDead) then
        Who^.Flag10D := 1;
      if Who^.Status = StatusDying then
        Who^.Status := StatusUnconscious;
      Who := Who^.Next;
    end;
  end;
end;

{ ovl05:0916. Shows the result of the battle in a window: 'You have lost the duel.' (and no
  experience), 'You have won the duel.' or 'The party has won.' when MonstersLooted or DuelMode,
  else 'The party has fled.' (no experience) or 'The party has found Treasure!'; then 'The duelist
  receives <Xp>' or 'Each character receives <Xp>', 'experience points.', and waits for Enter. }
procedure ShowBattleResult(Xp: LongInt);
var
  XpText: string[10];
  Line: string;
  Key: Char;
  Title: string[1];
  ExtKey: Byte;
begin
  Title := '';
  DrawWindow(1, 1, $26, $16, 0, $F, '');
  if (MonstersLooted <> 0) or (DuelMode <> 0) then
  begin
    if (DuelMode <> 0) and (BattleWon = 0) then
    begin
      DrawTextAt(1, 3, $A, 'You have lost the duel.');
      Xp := 0;
    end
    else if DuelMode <> 0 then
      DrawTextAt(1, 3, $A, 'You have won the duel.')
    else
      DrawTextAt(1, 3, $A, 'The party has won.');
  end
  else if PartyFled <> 0 then
  begin
    DrawTextAt(1, 3, $A, 'The party has fled.');
    Xp := 0;
  end
  else
    DrawTextAt(1, 3, $A, 'The party has found Treasure!');
  Str(Xp, XpText);
  if DuelMode <> 0 then
    Line := 'The duelist receives ' + XpText
  else
    Line := 'Each character receives ' + XpText;
  DrawTextAt(1, 5, $A, Line);
  DrawTextAt(1, 7, $A, 'experience points.');
  Key := ReadPromptChoice(Title, 'press <enter>/<return> to continue', 15, 15, 15, 1, 0, ExtKey);
end;

{ ovl05:0B14. Draws the 'Loot' window, prepares every entry of the loot list ds6810 for display
  (res12_fn_0442) and lets the player pick one (ChooseFromList, 'Items: ' with a 'Take' button).
  Key is the key of the choice, Item the chosen entry; Selected and Choice carry the list
  position between calls. }
procedure ChooseLootItem(var Key: Char; var Item: PMenuLine; var Selected: PMenuLine; var Choice: Integer);
var
  List: PMenuLine;
  Unused: array[0..18] of Byte; { QUIRK ovl05:0B17: 19 bytes of the frame nothing uses }
  Redraw: Byte;
  Entry: PMenuLine;
begin
  Redraw := 1;
  DrawWindow(1, 1, $26, $16, 0, $F, 'Loot');
  Entry := ds6810;
  while Entry <> nil do
  begin
    res12_fn_0442(0, Entry, 0, 0, 0, 0);
    Entry := Entry^.Next;
  end;
  List := ds6810;
  Key := ChooseFromList('Items: ', 'Take', 13, 10, 15, 1, 4, $26, $16, List, 1, Redraw, Choice, Selected);
  Item := Selected;
end;

{ ovl05:0C06. Lets the player take items from the loot list ds6810 until another key than Take or
  Enter is pressed or the list is empty: the chosen item goes to SelectedCharacter
  (AddInventoryItem) and, unless the character is overloaded, is unlinked from the loot and freed.
  Redraws the screen (res12_fn_27D9) at the end. }
procedure TakeLootItems;
var
  Chosen: PMenuLine;
  Prev: PMenuLine;
  Key: Char;
  Done: Boolean;
  Selected: PMenuLine;
  Choice: Integer;
  Overloaded: Byte;
begin
  Chosen := nil;
  Selected := ds6810;
  Choice := 0;
  repeat
    ChooseLootItem(Key, Chosen, Selected, Choice);
    if (Key <> 'T') and (Key <> KeyEnter) then
      Done := True
    else
    begin
      Done := False;
      AddInventoryItem(Chosen, Overloaded);
      if Overloaded = 0 then
      begin
        Prev := ds6810;
        if Prev = Chosen then
          ds6810 := Chosen^.Next
        else
        begin
          while Prev^.Next <> Chosen do
            Prev := Prev^.Next;
          Prev^.Next := Chosen^.Next;
        end;
        Chosen^.Next := nil;
        if Chosen <> nil then
          FreeMem(Chosen, ItemListSize);
        if ds6810 = nil then
          Done := True;
      end;
    end;
  until Done;
  res12_fn_27D9;
end;

{ ovl05:0D38. The Take command of the treasure menu. MoneyLeft and ItemsLeft are TreasureLeft's two
  results (money in the pool, items in the loot). With only items it goes to TakeLootItems, with
  only money it takes the money (TakeMoney); with both it loops on 'Take: Money Items Exit' until
  Exit or one of them runs out (G and O, in no menu text, go to ovl19_e10 as in the shop). }
procedure TakeTreasure(var MoneyLeft, ItemsLeft: Byte);
var
  Key: Char;
  Done: Boolean;
  ExtKey: Byte;
begin
  Done := False;
  if MoneyLeft <> 0 then
  begin
    if ItemsLeft <> 0 then
    begin
      repeat
        Key := ReadPromptChoice('Take: ', 'Money Items Exit', 13, 10, 15, 1, 1, ExtKey);
        case Key of
          'M':
            begin
              TakeMoney;
              res12_fn_27D9;
            end;
          'I': TakeLootItems;
          'E', KeyNone: Done := True;
          'G': ovl19_e10(Key);
          'O': ovl19_e10(Key);
        end;
        res12_fn_0767(SelectedCharacter);
        TreasureLeft(MoneyLeft, ItemsLeft);
        if (MoneyLeft = 0) or (ItemsLeft = 0) then
          Done := True;
      until Done;
    end
    else
    begin
      TakeMoney;
      res12_fn_27D9;
    end;
  end
  else
    TakeLootItems;
end;

{ ovl05:0ECD. The treasure menu after a won battle: 'View Pool Exit', with Take while there is loot
  and Share while there is pooled money, and Detect when SelectedCharacter has Detect Magic
  memorized and there are items (Detect casts it through ovl22_e5). V views (ovl19_e5), T takes
  (TakeTreasure), P pools (PoolMoney) when the key flag is clear, S shares (ShareMoney). Exit with
  treasure left asks 'There is still treasure left.  Do you want to go back and claim your
  treasure?' and leaves on No. }
procedure TreasureMenu;
var
  MoneyLeft: Byte;
  ItemsLeft: Byte;
  Unused: Byte;                 { QUIRK ovl05:0ED0: a byte of the frame nothing uses }
  Menu: string;
  Key: Char;
  Done: Boolean;
  ExtKey: Byte;
  Title: string[1];
  Answer: Byte;
  Slot: Byte;
  DetectSpell: Byte;
  HasDetect: Boolean;
  ExitText: string[13];
begin
  Title := '';
  Done := False;
  res12_fn_27D9;
  MoneyLeft := 0;
  repeat
    TreasureLeft(MoneyLeft, ItemsLeft);
    Menu := 'View Pool Exit';
    Slot := 0;
    ExitText := ' Exit';
    HasDetect := False;
    if ItemsLeft <> 0 then
      while (Slot <= LastSpellSlot) and not HasDetect do
      begin
        if (SelectedCharacter^.Spells[Slot] = SpellClericDetectMagic) or
          (SelectedCharacter^.Spells[Slot] = SpellMageDetectMagic) then
        begin
          HasDetect := True;
          DetectSpell := SelectedCharacter^.Spells[Slot];
        end;
        Inc(Slot);
      end;
    if HasDetect then
      ExitText := ' Detect Exit';
    if MoneyLeft <> 0 then
      Menu := 'View Take Pool Share' + ExitText
    else if ItemsLeft <> 0 then
      Menu := 'View Take Pool' + ExitText;
    Key := ReadPromptChoice(Title, Menu, 13, 10, 15, 1, 1, ExtKey);
    case Key of
      'V': ovl19_e5(ExtKey);
      'T': TakeTreasure(MoneyLeft, ItemsLeft);
      'P': if ExtKey = 0 then PoolMoney;
      'S': ShareMoney;
      'D': ovl22_e5(DetectSpell, 0, 0, ExtKey);
      'E', KeyNone:
        begin
          TreasureLeft(MoneyLeft, ItemsLeft);
          if (MoneyLeft <> 0) or (ItemsLeft <> 0) then
          begin
            Menu := '~Yes ~No';
            ShowPagedText(1, $11, $26, $16, $A, 1, 'There is still treasure left.  ');
            ShowPagedText(1, $11, $26, $16, $F, 0, 'Do you want to go back and claim your treasure?');
            Answer := AskMenu(Title, Menu, 13, 10, 15, 0, 0);
            if Answer = AnswerNo then
              Done := True
            else
              ClearRect(1, $11, $26, $16);
          end
          else
            Done := True;
        end;
      'G':
        begin
          ovl19_e10(Key);
          res12_fn_0767(SelectedCharacter);
        end;
      'O':
        begin
          ovl19_e10(Key);
          res12_fn_0767(SelectedCharacter);
        end;
    end;
  until Done;
end;

{ ovl05:11AC. Takes the monsters (Side 1) and the extra combatants (TCombatant.NoBody = 1) out of the
  party list (ovl16_e2 on SelectedCharacter; an extra combatant does not lower VarPartySize) and
  counts in VarRemovedCount the removed ones whose Flag10D is not 1; the remaining members' combat
  state is freed. SelectedCharacter is the first member afterwards. }
procedure RemoveBattleCombatants;
var
  Who: PCharacter;
  NextWho: PCharacter;
begin
  ds49D6^[VarRemovedCount] := 0;
  Who := PCharacter(ds5D96);
  while Who <> nil do
  begin
    if (Who^.Combat^.NoBody = ExtraCombatant) or (Who^.Side = SideMonsters) then
    begin
      if Who^.Flag10D <> 1 then
        Inc(ds49D6^[VarRemovedCount]);
      NextWho := Who^.Next;
      SelectedCharacter := Who;
      ovl16_e2(Who^.Combat^.NoBody = ExtraCombatant, True);
      Who := NextWho;
    end
    else
    begin
      if Who^.Combat <> nil then
      begin
        FreeMem(Who^.Combat, CombatStateSize);
        Who^.Combat := nil;
      end;
      Who := Who^.Next;
    end;
  end;
  SelectedCharacter := PCharacter(ds5D96);
end;

{ ovl05:12E8. The hirelings' share: every okay member the player does not run (B84 $80 and up) has
  HirelingShare and 7 shares, every other member one. When hirelings have shares, each kind of
  pooled money above 0 loses the hirelings' part (PooledMoney div all shares, as a Byte, times the
  hirelings' shares) and a window lists '<name> takes and hides his share.' for each hireling.
  QUIRK ovl05:13A5: the share of one kind is truncated to a Byte. }
procedure TakeHirelingShares;
var
  Who: PCharacter;
  HirelingShares: Byte;
  TotalShares: Byte;
  Share: Byte;
  Row: Byte;
  Kind: ShortInt;
  Unused: array[0..8] of Byte;  { QUIRK ovl05:12EB: nine bytes of the frame nothing uses }
  Taken: Boolean;
  ExtKey: Byte;
  Key: Char;
begin
  Taken := False;
  Who := PCharacter(ds5D96);
  HirelingShares := 0;
  TotalShares := 0;
  while Who <> nil do
  begin
    if (Who^.B84 > ComputerRun - 1) and (Who^.Status = StatusOkay) then
    begin
      Inc(HirelingShares, Who^.HirelingShare and ShareMask);
      Inc(TotalShares, Who^.HirelingShare and ShareMask);
    end
    else
      Inc(TotalShares);
    Who := Who^.Next;
  end;
  if HirelingShares > 0 then
    for Kind := 0 to LastMoneyKind do
      if PooledMoney[Kind] > 0 then
      begin
        Share := PooledMoney[Kind] div TotalShares;
        Dec(PooledMoney[Kind], HirelingShares * Share);
        Taken := True;
      end;
  if Taken then
  begin
    DrawWindow(1, 1, $26, $16, 0, $F, '');
    Who := PCharacter(ds5D96);
    Row := 0;
    while Who <> nil do
    begin
      if (Who^.B84 > ComputerRun - 1) and (Who^.Status = StatusOkay) and (Who^.HirelingShare > 0) then
      begin
        ShowPagedText(5, Row + 5, $22, $16, $A, 1, Who^.Name + ' takes and hides his share.');
        Inc(Row, 2);
      end;
      Who := Who^.Next;
    end;
    Key := ReadPromptChoice('', 'press <enter>/<return> to continue', 15, 15, 15, 1, 0, ExtKey);
  end;
end;

{ ovl05:1527 (e1). The end of a battle: clears VarBattleOutcome and MonstersLooted, sets the view
  mode ds49F3 to 6, settles the outcome and removes the monsters. While the party lives (or in a
  duel) the hirelings take their share, the result is shown, the treasure menu runs and the loot
  left in ds6810 is freed. A destroyed party gets VarBattleOutcome $80, 'The END!' and 'The monsters
  rejoice for the party has been destroyed'. Then sets ds4A00 and clears VarAfterBattle1..3,
  VarNoItemLoot and VarFixedXpBattle. }
procedure EndBattle;
var
  Entry: PMenuLine;
  Doomed: PMenuLine;
begin
  ds49D6^[VarBattleOutcome] := 0;
  MonstersLooted := 0;
  ds49F3 := 6;
  SettleBattleOutcome;
  RemoveBattleCombatants;
  if (PartyDestroyed = 0) or (DuelMode <> 0) then
  begin
    TakeHirelingShares;
    ShowBattleResult(BattleExperience);
    TreasureMenu;
    Entry := ds6810;
    while Entry <> nil do
    begin
      Doomed := Entry;
      Entry := Entry^.Next;
      FreeMem(Doomed, ItemListSize);
    end;
    ds6810 := nil;
  end
  else
  begin
    ds49D6^[VarBattleOutcome] := BattleOutcomeDestroyed;
    DrawWindow(1, 1, $26, $16, 0, $F, 'The END!');
    GlyphCol := 2;
    GlyphRow := 6;
    ShowPagedText(2, 5, $25, $16, $A, 1, 'The monsters rejoice for the party has been destroyed');
    ShowMessageLine($D, 'Press any key to continue');
  end;
  ds4A00 := 1;
  ds49D6^[VarAfterBattle1] := 0;
  ds49D6^[VarAfterBattle2] := 0;
  ds49D6^[VarAfterBattle3] := 0;
  ds49D6^[VarNoItemLoot] := 0;
  ds49D6^[VarFixedXpBattle] := 0;
end;

{ ovl05:1671. The unit's initialisation part is empty (push bp; mov bp, sp; pop bp; retf). }
begin
end.
