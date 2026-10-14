unit OVL19;
{ Inventory: the party's carried-item menus and selection/transfer routines (whitepaper 5.4; strings at ovl19:0AB3). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure ShowCharacterSheet;
procedure ShowCharacterMoney;
procedure ShowCombatStats;
procedure ShowAbilityScore(Index: ShortInt; Highlight: Boolean);
procedure ovl19_e5(var Flag: Byte);
procedure ovl19_fn_0B25;
procedure ovl19_fn_0D70;
procedure ovl19_e6(var Done: Byte);
procedure ovl19_fn_0FE2;
procedure ovl19_fn_148F;
procedure ovl19_e7(P: Pointer);
procedure ovl19_fn_1513;
procedure ovl19_fn_1734;
procedure ovl19_fn_1758;
procedure ovl19_fn_17ED;
procedure ovl19_fn_189D;
procedure ovl19_e8(P: Pointer; var B: Byte);
procedure ovl19_fn_1BA6;
procedure ovl19_fn_1BD7;
procedure ovl19_fn_1C13;
procedure ovl19_fn_1C4D;
procedure ovl19_fn_1CEE;
procedure ovl19_fn_1F4B;
procedure ovl19_fn_1F52;
procedure ovl19_fn_20A9;
procedure ovl19_fn_2156;
procedure ovl19_fn_2197;
procedure ovl19_fn_2233;
procedure ovl19_fn_228C;
procedure ovl19_fn_2383;
procedure ovl19_fn_23B6;
procedure ovl19_fn_24A7;
function WouldOverloadInventory(Character: PCharacter; Item: PMenuLine): Boolean;
procedure UpdateSelectedCharacter(Key: Char);
function CharacterMoneyValueInGold(Who: PCharacter): LongInt;
function ChooseSpellFromList(SpellListKind, DisplayMode: Byte; var Choice: Word;
  var Listed: Byte): Byte;
implementation
uses RES06, RES09, RES12, OVL22, OVL28;

type
  { The sheet reads three TCharacter bytes as signed table indexes (cwde at ovl19:00C6, 0198 and 04DE). }
  TSheetFields = record
    Filler: array[0..$9D] of Byte;
    Sex: ShortInt;                { +$9E }
    Pad9F: Byte;
    Alignment: ShortInt;          { +$A0 }
    Filler2: array[$A1..$10B] of Byte;
    Status: ShortInt;             { +$10C }
  end;
  PSheetFields = ^TSheetFields;
  { TCharacter from its +$10 field on: the six ability scores (Strength..Charisma) indexed by row. }
  TAbilityBlock = record
    Name: string[15];
    Scores: array[0..5] of Byte;
  end;
  PAbilityBlock = ^TAbilityBlock;
  { TCharacter's damage dice and bonus, bytes of its Pad112 field in POOLVARS (+$115, +$117, +$119). }
  TDamageDice = record
    Filler: array[0..$114] of Byte;
    Count: Byte;                  { +$115 }
    Pad116: Byte;
    Sides: Byte;                  { +$117 }
    Pad118: Byte;
    Bonus: ShortInt;              { +$119 }
  end;
  PDamageDice = ^TDamageDice;

{ ovl19:004A. Draws the character sheet of SelectedCharacter in the window 1..38 x 1..22: the name line
  (res12_fn_1816), the sex, race and age on row 3, the alignment on row 4, the class on row 5, the six
  ability lines (ShowAbilityScore) with their labels from row 7, the money (ShowCharacterMoney), the
  class levels and experience on row 15, the combat block (ShowCombatStats) on rows 17 and 18, the weapon
  and armor on rows 20 and 21 and the status on row 22, and the head and body portraits when they are
  on (ShowPortraits) and the tile set is 3. Called by ovl19_e5 (the View command), ovl19_fn_0B25,
  ovl19_fn_2197 and ovl16 (ovl16_fn_0B52, ovl16_fn_1DCB, ovl16_fn_209F). SheetCharacter keeps the
  character for the whole drawing. }
procedure ShowCharacterSheet;
const
  SheetRight = 38;
  SheetBottom = 22;
  NpcTagGap = 3;
  ComputerRunThreshold = $7F;
  NameRow = 3;
  AlignmentRow = 4;
  ClassRow = 5;
  FirstAbilityRow = 7;
  StatLabelColor = 10;
  LevelRow = 15;
  WeaponRow = 20;
  TextColor = 15;
  ValueColor = 10;
  HeadBodyTileSet = 3;
var
  { SpareFirst and SpareSecond fill the two bytes the frame reserves (ovl19:004A, [bp-1] and [bp-4]);
    the code never reads them }
  SpareFirst: Byte;
  Row: Byte;
  Col: Byte;
  SpareSecond: Byte;
  Stat: ShortInt;
  ClassSlot: ShortInt;
  Text: string;
  NeedSlash: Boolean;
begin
  SheetCharacter := SelectedCharacter;
  ClearFullScreen;
  DrawWindowFrame(1, 1, SheetRight, SheetBottom, 0);
  res12_fn_1816(SheetCharacter, 1, 1, 0);
  if SheetCharacter^.B84 > ComputerRunThreshold then
    DrawTextAt(Length(SheetCharacter^.Name) + NpcTagGap, 1, ValueColor, '(NPC)');
  Col := 1;
  Text := SexNames[PSheetFields(SheetCharacter)^.Sex];
  DrawTextAt(Col, NameRow, TextColor, Text);
  Col := Col + Length(Text) + 1;
  Text := RaceNames[SheetCharacter^.Race];
  DrawTextAt(Col, NameRow, TextColor, Text);
  Col := Col + Length(Text) + 1;
  DrawTextAt(Col, NameRow, TextColor, 'Age ' + res12_fn_1073(SheetCharacter^.Age));
  Text := AlignmentNames[PSheetFields(SheetCharacter)^.Alignment];
  DrawTextAt(1, AlignmentRow, TextColor, Text);
  Text := ClassNames[SheetCharacter^.ClassMask];
  DrawTextAt(1, ClassRow, TextColor, Text);
  for Stat := 0 to 5 do
  begin
    case Stat of
      0: Text := 'STR ';
      1: Text := 'INT ';
      2: Text := 'WIS ';
      3: Text := 'DEX ';
      4: Text := 'CON ';
      5: Text := 'CHA ';
    end;
    DrawTextAt(1, Stat + FirstAbilityRow, StatLabelColor, Text);
    ShowAbilityScore(Stat, False);
  end;
  ShowCharacterMoney;
  DrawTextAt(1, LevelRow, TextColor, 'Level');
  NeedSlash := False;
  Text := '';
  for ClassSlot := 0 to 7 do
    if SheetCharacter^.ClassLevels[ClassSlot] > 0 then
    begin
      if NeedSlash then
        Text := Text + '/';
      Text := Text + res12_fn_1037(SheetCharacter^.ClassLevels[ClassSlot]);
      NeedSlash := True;
    end;
  DrawTextAt(7, LevelRow, TextColor, Text);
  DrawTextAt(17, LevelRow, TextColor, 'Exp ' + res12_fn_10AD(SheetCharacter^.Experience));
  ShowCombatStats;
  Row := WeaponRow;
  if SheetCharacter^.SlotItems[0] <> nil then
  begin
    DrawTextAt(1, Row, TextColor, 'Weapon');
    res12_fn_0442(LongInt(SheetCharacter), SheetCharacter^.SlotItems[0], 8, Row, 0, 1);
  end;
  Inc(Row);
  if SheetCharacter^.SlotItems[2] <> nil then
  begin
    { QUIRK ovl19:0467: the Armor label is drawn in column 2, one column right of Weapon and Status }
    DrawTextAt(2, Row, TextColor, 'Armor');
    res12_fn_0442(LongInt(SheetCharacter), SheetCharacter^.SlotItems[2], 8, Row, 0, 1);
  end;
  Inc(Row);
  DrawTextAt(1, Row, TextColor, 'Status');
  DrawTextAt(8, Row, ValueColor, StatusNames[PSheetFields(SheetCharacter)^.Status]);
  if ShowPortraits <> 0 then
    if TileSet = HeadBodyTileSet then
      ShowHeadBodyWindow;
end;
{ ovl19:050D. Clears the money window (columns 12 to 26, rows 7 to 14) and lists the kinds of money
  SelectedCharacter holds, from Jewelry (6) down to Copper (0): each kind with a nonzero Money entry gets
  a row, its name ending in column 19 and its amount in column 21. The Money entries are Words at +$88. }
procedure ShowCharacterMoney;
const
  MoneyWindowLeft = 12;
  MoneyWindowTop = 7;
  MoneyWindowRight = 26;
  MoneyWindowBottom = 14;
  MoneyNameRight = 20;
  MoneyAmountColumn = 21;
  MoneyColor = 10;
  LastMoneyKind = 6;
var
  Row: Byte;
  Kind: ShortInt;
  Name: String40;
begin
  ClearWindow(MoneyWindowLeft, MoneyWindowTop, MoneyWindowRight, MoneyWindowBottom);
  Row := MoneyWindowTop;
  for Kind := LastMoneyKind downto 0 do
    if SelectedCharacter^.Money[Kind] > 0 then
    begin
      Name := MoneyKindNames[Kind];
      DrawTextAt(MoneyNameRight - Length(Name), Row, MoneyColor, Name);
      DrawTextAt(MoneyAmountColumn, Row, MoneyColor,
        res12_fn_1073(SelectedCharacter^.Money[Kind]));
      Inc(Row);
    end;
end;
{ ovl19:0608. Draws the combat block of SelectedCharacter on the sheet: on row 17, AC (res12_fn_08EF) and
  THAC0 (60 minus HitAdjust, column 9 label, 15 value) and Encumbrance (CarriedWeight, column 22 label,
  34 value); on row 18, HP (res12_fn_0973), Damage (dice count, d, sides, then the bonus with its sign)
  and Movement (the Movement byte doubled by affect $2A and halved by affect $27, column 25 label,
  34 value). Labels are drawn in bright white (15), values in bright green (10). Called by ShowCharacterSheet
  (its call at ovl19:03F5) and by ovl16 (ovl16_fn_1DCB, ovl16_fn_2639). }
procedure ShowCombatStats;
const
  LabelColor = 15;
  ValueColor = 10;
  CombatRow = 17;
  ArmorLabelColumn = 1;
  ArmorValueColumn = 4;
  { the displayed THAC0 counts 60 minus HitAdjust (the to-hit bonus of RollToHit, ovl24:0CB7); why 60 [I] }
  ThacBase = 60;
  { the code doubles the movement for affect $2A and halves it for $27; the POOLVARS comment on
    Movement says the reverse, and the matched code is the evidence }
  DoublingAffect = $2A;
  HalvingAffect = $27;
var
  Character: PCharacter;
  Row: Byte;
  Col: Byte;
  Move: Byte;
  Damage: String40;
  Affect: Pointer;
begin
  Character := SelectedCharacter;
  res12_fn_0BB8(Character);
  Row := CombatRow;
  DrawTextAt(ArmorLabelColumn, Row, LabelColor, 'AC    ');
  res12_fn_08EF(Character, ArmorValueColumn, Row);
  DrawTextAt(ArmorLabelColumn, Row + 1, LabelColor, 'HP    ');
  res12_fn_0973(Character, ArmorValueColumn, Row + 1, 0);
  Col := 8;
  DrawTextAt(Col + 1, Row, LabelColor, 'THAC0   ');
  DrawTextAt(Col + 7, Row, ValueColor, res12_fn_1037(ThacBase - Character^.HitAdjust));
  Damage := res12_fn_1037(PDamageDice(Character)^.Count) + 'd' +
    res12_fn_1037(PDamageDice(Character)^.Sides);
  if PDamageDice(Character)^.Bonus > 0 then
    Damage := Damage + '+' + res12_fn_1037(PDamageDice(Character)^.Bonus);
  if PDamageDice(Character)^.Bonus < 0 then
    Damage := Damage + '-' + res12_fn_1037(Abs(PDamageDice(Character)^.Bonus));
  DrawTextAt(Col, Row + 1, LabelColor, 'Damage        ');
  DrawTextAt(Col + 7, Row + 1, ValueColor, Damage);
  Col := 22;
  DrawTextAt(Col, Row, LabelColor, 'Encumbrance      ');
  DrawTextAt(Col + 12, Row, ValueColor, res12_fn_1073(Character^.CarriedWeight));
  Move := Character^.Movement;
  if res12_fn_2199(Character, DoublingAffect, Affect) then
    Move := Move * 2;
  if res12_fn_2199(Character, HalvingAffect, Affect) then
    Move := Move div 2;
  DrawTextAt(Col + 3, Row + 1, LabelColor, 'Movement   ');
  DrawTextAt(Col + 12, Row + 1, ValueColor, res12_fn_1037(Move));
end;
{ ovl19:0901. Draws ability score Index of SelectedCharacter (0 Strength .. 5 Charisma) on row 7 + Index,
  in columns 5 to 11 (a score below 10 is one column further right), in bright green, or bright magenta
  when Highlight is set. A Strength of 18 with a percentile also draws it in parentheses after the score
  on row 7, two digits, 00 for 100. Called by ShowCharacterSheet for each of the six lines with Highlight False. }
procedure ShowAbilityScore(Index: ShortInt; Highlight: Boolean);
const
  ExceptionalStrength = 18;
  FirstScoreColumn = 5;
  LastScoreColumn = 11;
  ScoreRow = 7;
  ScoreColor = 10;
  HighlightColor = 13;
  FirstTwoDigitValue = 10;
  PercentileMax = 100;
  PercentileColumn = 7;
var
  Percentile: String40;
  Col: Byte;
  Color: Byte;
begin
  if Highlight then
    Color := HighlightColor
  else
    Color := ScoreColor;
  Col := FirstScoreColumn;
  ClearWindow(Col, Index + ScoreRow, LastScoreColumn, Index + ScoreRow);
  if PAbilityBlock(SelectedCharacter)^.Scores[Index] < FirstTwoDigitValue then
    Inc(Col);
  DrawTextAt(Col, Index + ScoreRow, Color,
    res12_fn_1037(PAbilityBlock(SelectedCharacter)^.Scores[Index]));
  if Index = 0 then
    if SelectedCharacter^.Strength = ExceptionalStrength then
      if SelectedCharacter^.StrengthPercent > 0 then
      begin
        Percentile := res12_fn_1037(SelectedCharacter^.StrengthPercent);
        if SelectedCharacter^.StrengthPercent < FirstTwoDigitValue then
          Percentile := '0' + Percentile;
        if SelectedCharacter^.StrengthPercent = PercentileMax then
          Percentile := '00';
        DrawTextAt(PercentileColumn, ScoreRow, Color, '(' + Percentile + ')');
      end;
end;
{ ovl19:0AB3: one var parameter (the Temple's View command). }
{@stub} procedure ovl19_e5(var Flag: Byte); begin end;
{ ovl19:0B25: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl19_fn_0B25; begin end;
{ ovl19:0D70: retf 4: 4 bytes of parameters; 40 bytes of locals }
{@stub} procedure ovl19_fn_0D70; begin end;
{ ovl19:0EF8: frame not read }
{@stub} procedure ovl19_e6(var Done: Byte); begin end;
{ ovl19:0FE2: frame not read }
{@stub} procedure ovl19_fn_0FE2; begin end;
{ ovl19:148F: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl19_fn_148F; begin end;
{ ovl19:14D0: frame not read }
{@stub} procedure ovl19_e7(P: Pointer); begin end;
{ ovl19:1513: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl19_fn_1513; begin end;
{ ovl19:1734: frame not read }
{@stub} procedure ovl19_fn_1734; begin end;
{ ovl19:1758: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl19_fn_1758; begin end;
{ ovl19:17ED: retf 4: 4 bytes of parameters; 24 bytes of locals }
{@stub} procedure ovl19_fn_17ED; begin end;
{ ovl19:189D: retf 4: 4 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl19_fn_189D; begin end;
{ ovl19:1A8A: frame not read }
{@stub} procedure ovl19_e8(P: Pointer; var B: Byte); begin end;
{ ovl19:1BA6: frame not read }
{@stub} procedure ovl19_fn_1BA6; begin end;
{ ovl19:1BD7: frame not read }
{@stub} procedure ovl19_fn_1BD7; begin end;
{ ovl19:1C13: frame not read }
{@stub} procedure ovl19_fn_1C13; begin end;
{ ovl19:1C4D: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl19_fn_1C4D; begin end;
{ ovl19:1CEE: retf 4: 4 bytes of parameters; 520 bytes of locals }
{@stub} procedure ovl19_fn_1CEE; begin end;
{ ovl19:1F4B: frame not read }
{@stub} procedure ovl19_fn_1F4B; begin end;
{ ovl19:1F52: frame not read }
{@stub} procedure ovl19_fn_1F52; begin end;
{ ovl19:20A9: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl19_fn_20A9; begin end;
{ ovl19:2156: frame not read }
{@stub} procedure ovl19_fn_2156; begin end;
{ ovl19:2197: frame not read }
{@stub} procedure ovl19_fn_2197; begin end;
{ ovl19:2233: frame not read }
{@stub} procedure ovl19_fn_2233; begin end;
{ ovl19:228C: frame not read }
{@stub} procedure ovl19_fn_228C; begin end;
{ ovl19:2383: frame not read }
{@stub} procedure ovl19_fn_2383; begin end;
{ ovl19:23B6: frame not read }
{@stub} procedure ovl19_fn_23B6; begin end;
{ ovl19:24A7: retf 0: 0 bytes of parameters; 558 bytes of locals }
{@stub} procedure ovl19_fn_24A7; begin end;
{ ovl19:275B: rejects an item when the character already has more than 15 items or when its added
  weight exceeds the character's strength-based capacity plus 1500. The item weight is multiplied
  by its count only when the count is nonzero. The call to res12_fn_0BB8 occurs before the checks. }
function WouldOverloadInventory(Character: PCharacter; Item: PMenuLine): Boolean;
const
  MaximumItemCount = 15;
  BaseCarryAllowance = 1500;
var
  Overloaded: Boolean;
  AddedWeight: Word;
begin
  res12_fn_0BB8(Character);
  Overloaded := False;
  if Character^.ItemCountC7 > MaximumItemCount then
    Overloaded := True;
  AddedWeight := Item^.Weight;
  if Item^.Count > 0 then
    AddedWeight := AddedWeight * Item^.Count;
  if Character^.CarriedWeight + AddedWeight >
    res12_fn_13AB(Character) + BaseCarryAllowance then
    Overloaded := True;
  WouldOverloadInventory := Overloaded;
end;
{ ovl19:27DF. Updates SelectedCharacter from the party list: G selects the previous member, wrapping
  from the first member to the last; O selects the next member, wrapping to the head; other keys
  select the head. }
procedure UpdateSelectedCharacter(Key: Char);
var
  Character: PCharacter;
begin
  Character := PCharacter(ds5D96);
  if Character <> nil then
  begin
    case Key of
      'G':
        begin
          if Character = SelectedCharacter then
          begin
            while Character^.Next <> nil do
              Character := Character^.Next;
          end
          else
          begin
            while (Character <> nil) and
              (Character^.Next <> SelectedCharacter) do
              Character := Character^.Next;
          end;
        end;
      'O':
        begin
          if SelectedCharacter^.Next <> nil then
            Character := SelectedCharacter^.Next;
        end;
    else
      Character := PCharacter(ds5D96);
    end;
  end;
  SelectedCharacter := Character;
end;
{ ovl19:28BE: converts Who's five coin words (+$88..+$90) to gold using CoinCopperValues, adds half a
  gold piece in copper before division, and returns the rounded total as a LongInt. The Temple keeps
  only its low word (ovl04:0177). QUIRK ovl19:28BE: the frame reserves [bp-$A], which is never accessed. }
function CharacterMoneyValueInGold(Who: PCharacter): LongInt;
const
  LastCoinIndex = 4;
  GoldCoinIndex = 3;
  HalfGoldCopperValue = 100;
var
  TotalCopper: LongInt;
  CoinIndex: ShortInt;
  UnusedFrameByte: Byte;
begin
  TotalCopper := 0;
  for CoinIndex := 0 to LastCoinIndex do
    Inc(TotalCopper, CoinCopperValues[CoinIndex] * Who^.Money[CoinIndex]);
  CharacterMoneyValueInGold := (TotalCopper + HalfGoldCopperValue) div CoinCopperValues[GoldCoinIndex];
end;
{ ovl19:299C. Sets Listed from the requested spell list. If Choice is negative it opens and titles the
  spell window; it then delegates selection to ovl22. }
function ChooseSpellFromList(SpellListKind, DisplayMode: Byte; var Choice: Word;
  var Listed: Byte): Byte;
const
  SpellListInMemory = 0;
  SpellListInSpellBook = 1;
  SpellListOnScroll = 2;
  SpellListOnScrolls = 3;
  SpellListToChooseFrom = 4;
  SpellListToMemorize = 5;
  SpellListToScribe = 6;
  TitleRow = 1;
  TitleColor = 10;
var
  ModeDescription: String40;
begin
  case SpellListKind of
    SpellListInMemory: ModeDescription := 'in Memory';
    SpellListInSpellBook: ModeDescription := 'in Spell Book';
    SpellListOnScroll: ModeDescription := 'on Scroll';
    SpellListOnScrolls: ModeDescription := 'on Scrolls';
    SpellListToChooseFrom: ModeDescription := 'to choose from';
    SpellListToMemorize: ModeDescription := 'to be memorized';
    SpellListToScribe: ModeDescription := 'to be scribed';
  else
    ModeDescription[0] := #0;
  end;
  Listed := ovl22_e2(SpellListKind);
  if Listed <> 0 then
  begin
    if Integer(Choice) < 0 then
    begin
      DrawWindow(1, 1, $26, 1, 0, 0, '');
      res12_fn_1816(SelectedCharacter, 1, 1, 1);
      DrawTextAt(Length(SelectedCharacter^.Name) + 4, TitleRow,
        TitleColor, 'Spells ' + ModeDescription);
    end;
    ChooseSpellFromList := ovl22_e1(DisplayMode, Choice);
  end
  else
    ChooseSpellFromList := 0;
end;

begin
end.
