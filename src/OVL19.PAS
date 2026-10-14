unit OVL19;
{ Inventory: the party's carried-item menus and selection/transfer routines (whitepaper 5.4; strings at ovl19:0AB3). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure ovl19_e1;
procedure ovl19_fn_031E;
procedure ShowCharacterMoney;
procedure ovl19_e2;
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
uses RES06, RES09, RES12, OVL22;

type
  { TCharacter from its +$10 field on: the six ability scores (Strength..Charisma) indexed by row. }
  TAbilityBlock = record
    Name: string[15];
    Scores: array[0..5] of Byte;
  end;
  PAbilityBlock = ^TAbilityBlock;

{ ovl19:004A: frame not read }
{@stub} procedure ovl19_e1; begin end;
{ ovl19:031E: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl19_fn_031E; begin end;
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
{ ovl19:0608: retf 0: 0 bytes of parameters; 564 bytes of locals }
{@stub} procedure ovl19_e2; begin end;
{ ovl19:0901. Draws ability score Index of SelectedCharacter (0 Strength .. 5 Charisma) on row 7 + Index,
  in columns 5 to 11 (a score below 10 is one column further right), in bright green, or bright magenta
  when Highlight is set. A Strength of 18 with a percentile also draws it in parentheses after the score
  on row 7, two digits, 00 for 100. Called by ovl19_e1 for each of the six lines with Highlight False. }
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
