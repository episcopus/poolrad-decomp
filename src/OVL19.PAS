unit OVL19;
{ Inventory: the party's carried-item menus and selection/transfer routines (whitepaper 5.4; strings at ovl19:0AB3). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure ShowCharacterSheet;
procedure ShowCharacterMoney;
procedure ShowCombatStats;
procedure ShowAbilityScore(Index: ShortInt; Highlight: Boolean);
procedure ViewSelectedCharacter(var Done: Byte);
function CanGiveUpItem(Item: PMenuLine): Boolean;
procedure RunItemMenu(var Done: Byte);
procedure ReadyItem(Item: PMenuLine);
procedure TradeItem(Item: PMenuLine);
procedure HalveItem(Item: PMenuLine);
procedure JoinItem(Item: PMenuLine);
procedure UseItem(Item: PMenuLine; var Done: Byte);
procedure SellItem(Item: PMenuLine);
procedure IdentifyItem(Item: PMenuLine; var Redraw: Byte);
procedure TradeMoney;
procedure ChooseAndDropMoney;
function WouldOverloadInventory(Character: PCharacter; Item: PMenuLine): Boolean;
procedure UpdateSelectedCharacter(Key: Char);
function CharacterMoneyValueInGold(Who: PCharacter): LongInt;
function ChooseSpellFromList(SpellListKind, DisplayMode: Byte; var Choice: Word;
  var Listed: Byte): Byte;
implementation
uses RES06, RES09, RES12, OVL21, OVL22, OVL24, OVL25, OVL28, OVL31;

const
  { The ds49F3 view modes the View command and the item menu test (whitepaper 5.4): 1 is the shop and
    the Temple (VisitTemple sets it, ovl04:0D0F; the value OVL21 names ViewShop), 2 the camp (MakeCamp
    sets it, ovl15:1E6F), 3 and 4 the two area-view pages (ShowAreaView sets them, whitepaper 5.2.1)
    and 5 a combat (RunCombat sets it, ovl08:0080). }
  ViewModeShop = 1;
  ViewModeCamp = 2;
  ViewModeMap = 3;
  ViewModeView = 4;
  ViewModeCombat = 5;
  { B84 bit 7 marks a member the computer runs (PrepareCombatants, ovl10:0675; OVL05 and OVL21 name
    the same bit ComputerRun). The code tests the bit from below as `B84 < ComputerRunB84` and, where
    it branches on the seven low bits, from above as `B84 > ComputerRunThreshold`; the two spellings
    compile to the original's two forms (probe tools/re/tp_idioms/ovl19/PB19BIT.PAS). }
  ComputerRunB84 = $80;
  ComputerRunThreshold = $7F;
  { Affects[3] bit 7 marks an item with an affect of its own (ReadyItem applies it through
    CallAffectHandler). ReadyItem tests it from above as `Affects[3] > AffectThreshold`, UseItem and
    RunItemMenu test it from below as `Affects[3] < AffectFlag` (then the item's spell is Affects[2]). }
  AffectFlag = $80;
  AffectThreshold = $7F;
  { The pending-scribe bit (bit 7) of a scroll's affects (whitepaper 5.22): CanGiveUpItem tests
    Affects[1..3] above this before "was going to scribe from that scroll". }
  ScribeAffectThreshold = $7F;

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
  (DrawCharacterName) with an "(NPC)" tag after it for a computer-run member (B84 bit 7), the sex, race
  and age on row 3, the alignment on row 4, the class on row 5 (ClassNames, indexed by ClassMask: 0..7
  are the single classes and 8..16 the multi-class names Cleric/Fighter .. Magic-User/Thief), the six
  ability lines (ShowAbilityScore) with their labels from row 7, the money (ShowCharacterMoney), the
  class levels and experience on row 15, the combat block (ShowCombatStats) on rows 17 and 18, the weapon
  and armor on rows 20 and 21 and the status on row 22, and the head and body portraits when they are
  on (ShowPortraits) and the tile set is 3. Called by ViewSelectedCharacter (the View command),
  TradeMoney (ovl19:219D) and ovl16 (ovl16_fn_0B52, ovl16_fn_1DCB, ovl16_fn_209F). SheetCharacter keeps the
  character for the whole drawing. }
procedure ShowCharacterSheet;
const
  SheetRight = 38;
  SheetBottom = 22;
  NpcTagGap = 3;
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
  DrawCharacterName(SheetCharacter, 1, 1, 0);
  if SheetCharacter^.B84 > ComputerRunThreshold then
    DrawTextAt(Length(SheetCharacter^.Name) + NpcTagGap, 1, ValueColor, '(NPC)');
  Col := 1;
  Text := SexNames[PSheetFields(SheetCharacter)^.Sex];
  DrawTextAt(Col, NameRow, TextColor, Text);
  Col := Col + Length(Text) + 1;
  Text := RaceNames[SheetCharacter^.Race];
  DrawTextAt(Col, NameRow, TextColor, Text);
  Col := Col + Length(Text) + 1;
  DrawTextAt(Col, NameRow, TextColor, 'Age ' + WordToText(SheetCharacter^.Age));
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
      Text := Text + ByteToText(SheetCharacter^.ClassLevels[ClassSlot]);
      NeedSlash := True;
    end;
  DrawTextAt(7, LevelRow, TextColor, Text);
  DrawTextAt(17, LevelRow, TextColor, 'Exp ' + LongIntToText(SheetCharacter^.Experience));
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
        WordToText(SelectedCharacter^.Money[Kind]));
      Inc(Row);
    end;
end;
{ ovl19:0608. Draws the combat block of SelectedCharacter on the sheet: on row 17, AC (DrawArmourClass) and
  THAC0 (60 minus HitAdjust, column 9 label, 15 value) and Encumbrance (CarriedWeight, column 22 label,
  34 value); on row 18, HP (DrawHitPoints), Damage (dice count, d, sides, then the bonus with its sign)
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
  RecalcCombatValues(Character);
  Row := CombatRow;
  DrawTextAt(ArmorLabelColumn, Row, LabelColor, 'AC    ');
  DrawArmourClass(Character, ArmorValueColumn, Row);
  DrawTextAt(ArmorLabelColumn, Row + 1, LabelColor, 'HP    ');
  DrawHitPoints(Character, ArmorValueColumn, Row + 1, 0);
  Col := 8;
  DrawTextAt(Col + 1, Row, LabelColor, 'THAC0   ');
  DrawTextAt(Col + 7, Row, ValueColor, ByteToText(ThacBase - Character^.HitAdjust));
  Damage := ByteToText(PDamageDice(Character)^.Count) + 'd' +
    ByteToText(PDamageDice(Character)^.Sides);
  if PDamageDice(Character)^.Bonus > 0 then
    Damage := Damage + '+' + ByteToText(PDamageDice(Character)^.Bonus);
  if PDamageDice(Character)^.Bonus < 0 then
    Damage := Damage + '-' + ByteToText(Abs(PDamageDice(Character)^.Bonus));
  DrawTextAt(Col, Row + 1, LabelColor, 'Damage        ');
  DrawTextAt(Col + 7, Row + 1, ValueColor, Damage);
  Col := 22;
  DrawTextAt(Col, Row, LabelColor, 'Encumbrance      ');
  DrawTextAt(Col + 12, Row, ValueColor, WordToText(Character^.CarriedWeight));
  Move := Character^.Movement;
  if HasAffect(Character, DoublingAffect, Affect) then
    Move := Move * 2;
  if HasAffect(Character, HalvingAffect, Affect) then
    Move := Move div 2;
  DrawTextAt(Col + 3, Row + 1, LabelColor, 'Movement   ');
  DrawTextAt(Col + 12, Row + 1, ValueColor, ByteToText(Move));
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
    ByteToText(PAbilityBlock(SelectedCharacter)^.Scores[Index]));
  if Index = 0 then
    if SelectedCharacter^.Strength = ExceptionalStrength then
      if SelectedCharacter^.StrengthPercent > 0 then
      begin
        Percentile := ByteToText(SelectedCharacter^.StrengthPercent);
        if SelectedCharacter^.StrengthPercent < FirstTwoDigitValue then
          Percentile := '0' + Percentile;
        if SelectedCharacter^.StrengthPercent = PercentileMax then
          Percentile := '00';
        DrawTextAt(PercentileColumn, ScoreRow, Color, '(' + Percentile + ')');
      end;
end;
{ ovl19:0AB3. The View command (whitepaper 5.4; the shop's V key, the Temple's and the camp's View): draws
  the sheet of SelectedCharacter and shows the prompt "View:" with the words Items (I), Spells (S), Trade
  (T), Drop (D) and Exit (E) until Exit or Escape (#0) is chosen or Done is set. Items runs RunItemMenu,
  Spells runs ChooseSpellFromList, Trade runs TradeMoney and Drop runs ChooseAndDropMoney and then
  ShowCharacterMoney. The sheet is drawn again after Items, Spells and Trade. In view mode 5 (combat)
  ovl31_e3 runs on entry and ovl31_e2 on exit. Done: the stop flag, 0 keeps the view going; RunItemMenu gets
  it too. ViewedCharacter keeps a copy of SelectedCharacter (ovl19:0AD1). }
procedure ViewSelectedCharacter(var Done: Byte);
var
  Key: Char;                    { the key of the View prompt; a space until the first one is read }
  Spare: Byte;                  { the frame reserves this byte (ovl19:0AB3, [bp-2]); the code never reads it }
  Menu: String40;               { the words of the View prompt, built from the character's contents }
  HasMoney: Boolean;            { the character carries money of one of the seven kinds }
  HasSpells: Byte;              { 1 when a spell is memorized; ChooseSpellFromList then overwrites it }
  ExtKey: Byte;                 { the extended-key flag of the prompt; the View never reads it }
  Spell: Byte;                  { the spell slot index of the scan, then the spell ChooseSpellFromList returns }
  Kind: ShortInt;               { the money kind index of the scan (signed: cwde at ovl19:0B3F) }
  Choice: Word;                 { -1: ChooseSpellFromList opens its window and asks for a spell }
begin
  if ds49F3 = ViewModeCombat then
    ovl31_e3;
  Key := ' ';
  Done := 0;
  ViewedCharacter := SelectedCharacter;
  ShowCharacterSheet;
  while not (Key in [#0, 'E']) and (Done = 0) do
  begin
    Menu := '';
    HasSpells := 0;
    HasMoney := False;
    for Spell := 0 to 20 do
      if SheetCharacter^.Spells[Spell] > 0 then
        HasSpells := 1;
    for Kind := 0 to 6 do
      if SheetCharacter^.Money[Kind] > 0 then
        HasMoney := True;
    if SheetCharacter^.Items <> nil then
      Menu := Menu + 'Items ';
    if HasSpells <> 0 then
      Menu := Menu + 'Spells ';
    if (SheetCharacter^.B84 < ComputerRunB84) or (SheetCharacter^.Flag10D = 0) or
      (SheetCharacter^.Status = 1) then
      if HasMoney and (ds49F3 <> ViewModeCombat) then
        Menu := Menu + 'Trade ';
    if HasMoney then
      Menu := Menu + 'Drop ';
    Menu := Menu + 'Exit';
    Key := ReadPromptChoice('View:', Menu, 13, 10, 15, 0, 0, ExtKey);
    Choice := $FFFF;
    case Key of
      'I': RunItemMenu(Done);
      'S': Spell := ChooseSpellFromList(0, 0, Choice, HasSpells);
      'T': TradeMoney;
      'D':
        begin
          ChooseAndDropMoney;
          ShowCharacterMoney;
        end;
    end;
    if (Done = 0) and (Key in ['I', 'S', 'T']) then
      ShowCharacterSheet;
  end;
  if ds49F3 = ViewModeCombat then
    ovl31_e2;
  RedrawView;
end;
{ ovl19:0D70. Asks whether Item may leave the character: ovl19:0EF8 calls it before its T, D and S
  actions (the call sites at ovl19:1339, 1365 and 1443). False when the item is readied: "Must be
  unreadied" is shown. True for an item that is not a scroll (ovl22_e6 is false). For a scroll
  (ovl22_e6 true) with a pending scribe (bit 7 set in one of Affects[1..3], whitepaper 5.22) it shows
  "<name> was going to scribe from that scroll" after the name and asks "is it Okay to lose it?";
  True only on Y. Otherwise True. Result: whether the item may go.
  Globals: SelectedCharacter (the name), GlyphCol and GlyphRow (the message follows the name on row 21).
  Side effect: rows 21 and 22 (columns 1 to 38) are cleared on every path. }
function CanGiveUpItem(Item: PMenuLine): Boolean;
begin
  CanGiveUpItem := False;
  if Item^.Readied then
    ShowFlashMessage('Must be unreadied')
  else if not ovl22_e6(Item) then
    CanGiveUpItem := True
  else if (Item^.Affects[1] > ScribeAffectThreshold) or (Item^.Affects[2] > ScribeAffectThreshold) or
    (Item^.Affects[3] > ScribeAffectThreshold) then
  begin
    DrawCharacterName(SelectedCharacter, 1, 21, 0);
    GlyphCol := Length(SelectedCharacter^.Name) + 2;
    GlyphRow := 21;
    ShowPagedText(1, 21, 38, 22, 14, 0, ' was going to scribe from that scroll');
    if AskYesNo('is it Okay to lose it? ', 13, 10, 15) = 'Y' then
      CanGiveUpItem := True;
  end
  else
    CanGiveUpItem := True;
  ClearWindow(1, 21, 38, 22);
end;
{ ovl19:0EF8. The Items command of the View prompt (ViewSelectedCharacter's I key; whitepaper 5.4). It
  lists the items of SelectedCharacter with ChooseFromList under the words Ready (R), Use (U), Trade (T),
  Drop (D), Halve (H), Join (J), Sell (S) and Id (I), runs the chosen action and repeats until Escape or E
  is pressed, or Done is set. Ready runs ReadyItem. Use needs a readied item ("Must be Readied" otherwise)
  that ovl22_e6 accepts, or one with Affects[2] above 0 and Affects[3] below $80; then it runs UseItem.
  Trade and Sell ask CanGiveUpItem, then run TradeItem or SellItem. Drop asks CanGiveUpItem,
  shows "Your <item> will be gone forever" and then "Drop It?", and on Y calls RemoveInventoryItem with
  SelectedCharacter and the item. Halve, Join and Id run HalveItem, JoinItem and IdentifyItem.
  Done: the stop flag shared with ViewSelectedCharacter; UseItem may set it. The item menu is drawn
  only when the character carries items; the Items window (rows 1 to 22) is drawn when DrawItemWindow
  is set or ds6821 is nonzero. The view mode ds49F3 decides which words are offered: 1 (set by
  VisitTemple, ovl04:0D0F) offers Sell and Id; 2, 3 and 4 offer Use, and 5 (combat) offers Use only to
  a character whose Combat^.CanUseMagicItem is set. Trade is not offered in combat. }
procedure RunItemMenu(var Done: Byte);
const
  VarNoCasting = 229;          { the game word that forbids casting (ovl07, ovl08, ovl09, ovl15); Use is not
                                 offered while it is nonzero (ovl19:0F98) }
var
  Key: Char;                    { the key of the item menu; a space until the first one is read }
  Menu: String40;               { the words of the item menu, built from the character and the view mode }
  Spare: Byte;                  { the frame reserves this byte (ovl19:0EF8, [bp-$2B]); the code never reads it }
  DrawItemWindow: Boolean;      { the Items window is to be drawn again }
  Redraw: Byte;                 { ChooseFromList's Redraw: 1 when the list must be drawn again }
  Cursor: PMenuLine;            { the item the loop that draws the list stands on }
  Selected: PMenuLine;          { the item ChooseFromList returns: the one the action is taken on }
  Choice: Integer;              { ChooseFromList's highlighted line }
  Spare2: array[0..3] of Byte;  { the frame reserves four bytes (ovl19:0EF8, [bp-$3B..-$38]); never read }
  Character: PCharacter;        { SelectedCharacter on entry; the items are his }
  OldCount: Byte;               { his item count before the action (a change redraws the list) }
  Spare3: Byte;                 { the frame reserves one more byte (ovl19:0EF8, [bp-$41]); never read }
begin
  Character := SelectedCharacter;
  Key := ' ';
  Selected := Character^.Items;
  Choice := 0;
  Redraw := 1;
  DrawItemWindow := True;
  while not (Key in [#0, 'E']) and (Done = 0) do
  begin
    if not (Character^.ItemCountC7 > 0) then
      Exit;
    OldCount := Character^.ItemCountC7;
    if Character^.Items <> nil then
    begin
      Menu := 'Ready';
      if Character^.Flag10D <> 0 then
        if GameVars^[VarNoCasting] = 0 then
          if (ds49F3 = ViewModeCamp) or (ds49F3 = ViewModeMap) or (ds49F3 = ViewModeView) or
            ((ds49F3 = ViewModeCombat) and (Character^.Combat^.CanUseMagicItem <> 0)) then
            Menu := Menu + ' Use';
      if ((Character^.B84 < ComputerRunB84) or (Character^.Flag10D = 0) or (Character^.Status = 1)) and
        (ds49F3 <> ViewModeCombat) then
        Menu := Menu + ' Trade';
      Menu := Menu + ' Drop';
      if Character^.ItemCountC7 < 16 then
        Menu := Menu + ' Halve';
      Menu := Menu + ' Join';
      if ((Character^.B84 < ComputerRunB84) or (Character^.Flag10D = 0) or (Character^.Status = 1)) and
        (ds49F3 = ViewModeShop) then
        Menu := Menu + ' Sell';
      if ds49F3 = ViewModeShop then
        Menu := Menu + ' Id';
      Cursor := Character^.Items;
      while Cursor <> nil do
      begin
        res12_fn_0442(LongInt(Character), Cursor, 0, 0, 1, 0);
        Cursor := Cursor^.Next;
      end;
      if DrawItemWindow or (ds6821 <> 0) then
      begin
        ClearFullScreen;
        DrawWindowFrame(1, 1, 38, 22, 0);
        DrawCharacterName(Character, 1, 1, 1);
        DrawTextAt(Length(Character^.Name) + 4, 1, 10, 'Items');
        DrawWindow(1, 3, 38, 22, 0, 0, '');
        DrawTextAt(1, 3, 15, 'Ready Item');
        Redraw := 1;
        DrawItemWindow := False;
        ds6821 := 0;
      end;
      Key := ChooseFromList('', Menu, 13, 10, 15, 1, 5, 38, 22, Character^.Items, 1, Redraw, Choice,
        Selected);
      if Selected <> nil then
        case Key of
          'R': ReadyItem(Selected);
          'U':
            if not Selected^.Readied then
            begin
              ShowFlashMessage('Must be Readied');
              Key := ' ';
            end
            else if ovl22_e6(Selected) or ((Selected^.Affects[2] > 0) and (Selected^.Affects[3] < AffectFlag)) then
            begin
              UseItem(Selected, Done);
              if ds49F3 <> ViewModeCombat then
                Done := 0;
              if Done = 0 then
                DrawItemWindow := True;
            end;
          'T':
            begin
              if CanGiveUpItem(Selected) then
                TradeItem(Selected)
              else
                Key := ' ';
              DrawItemWindow := True;
            end;
          'D':
            if CanGiveUpItem(Selected) then
            begin
              res12_fn_0442(LongInt(Character), Selected, 0, 0, 0, 0);
              ShowPagedText(1, 21, 38, 22, 14, 1, 'Your ' + Selected^.Text + 'will be gone forever');
              if AskYesNo('Drop It? ', 13, 10, 15) = 'Y' then
              begin
                RemoveInventoryItem(SelectedCharacter, Selected);
                Redraw := 1;
              end;
              ClearWindow(1, 21, 38, 22);
            end
            else
              Key := ' ';
          'H': HalveItem(Selected);
          'J': JoinItem(Selected);
          'S':
            if CanGiveUpItem(Selected) then
              SellItem(Selected)
            else
              Key := ' ';
          'I': IdentifyItem(Selected, Redraw);
        end;
      RecalcCombatValues(Character);
    end;
    if Character^.ItemCountC7 <> OldCount then
      Redraw := 1;
  end;
end;
{ ovl19:14D0. The Ready action of the item menu (RunItemMenu's R key, ovl19:0EF8) and of the AI's item step
  (ovl09:13CA): readies Item for SelectedCharacter, or unreadies it when it is readied. Readying runs three
  groups of checks and the last one that fails sets Reason: the hands (HandsInUse plus the item's
  ItemTable[ItemType].Hands above MaxHands gives "Your hands are full!", not shown in combat when the computer
  fights for the character, Quick), the body slot ItemTable[ItemType].Slot (an item already in it gives "already
  using <name>"; the kinds $49 and $1C also check slots 11 and 12), and the classes ItemTable[ItemType].ClassMask
  allows (none of them in the character's ClassBits gives "Wrong Class"). When every check passes, the item is
  marked Readied and its affect is applied: CallAffectHandler with the item's Affects[3] byte when that byte
  is above $7F. Unreadying a readied item refuses a cursed one ("It's Cursed") and otherwise clears Readied
  and removes the affect. The routine never stores the item in SlotItems.
  Parameter: Item, the item. Globals: SelectedCharacter, ds49F3 (the view mode, 5 for combat), ItemTable
  (indexed by item type, not by race). Side effects: messages (ShowFlashMessage); the "already using" case
  first redraws the slot item (res12_fn_0442). QUIRK ovl19:15BB: slot 9 is tested at SlotItems[10]
  (+$F4) but the message names SlotItems[9] (+$F0). }
procedure ReadyItem(Item: PMenuLine);
const
  MaxHands = 2;
  LastBodySlot = 8;
  QuirkSlot = 9;
  ReadyOk = 0;
  ReadyWrongClass = 1;
  ReadySlotUsed = 2;
  ReadyHandsFull = 3;
var
  AffectOn: Boolean;            { the item's Affects[3] byte is above AffectThreshold: it has an affect }
  Reason: Byte;                 { ReadyOk, or the check that failed }
  Slot: Byte;                   { the body slot of the item: ItemTable[ItemType].Slot, or 11 and 12 for $49 and $1C }
  Character: PCharacter;        { SelectedCharacter on entry }
begin
  AffectOn := Item^.Affects[3] > AffectThreshold;
  Character := SelectedCharacter;
  if Item^.Readied then
  begin
    if Item^.Cursed then
      ShowFlashMessage('It''s Cursed')
    else
    begin
      Item^.Readied := False;
      if AffectOn then
        CallAffectHandler(Item^.Affects[3], Character, PAffect(Item), 1);
    end;
  end
  else
  begin
    Reason := ReadyOk;
    if Character^.HandsInUse + ItemTable[Item^.ItemType].Hands > MaxHands then
      Reason := ReadyHandsFull;
    Slot := ItemTable[Item^.ItemType].Slot;
    case Slot of
      0..LastBodySlot:
        if Character^.SlotItems[ShortInt(Slot)] <> nil then
          Reason := ReadySlotUsed;
      QuirkSlot:
        if Character^.SlotItems[10] <> nil then
          Reason := ReadySlotUsed;
    end;
    if Item^.ItemType = $49 then
      if Character^.SlotItems[11] <> nil then
      begin
        Reason := ReadySlotUsed;
        Slot := 11;
      end;
    if Item^.ItemType = $1C then
      if Character^.SlotItems[12] <> nil then
      begin
        Reason := ReadySlotUsed;
        Slot := 12;
      end;
    if (ItemTable[Item^.ItemType].ClassMask and Character^.ClassBits) = 0 then
      Reason := ReadyWrongClass;
    case Reason of
      ReadyOk:
        begin
          Item^.Readied := True;
          if AffectOn then
            CallAffectHandler(Item^.Affects[3], Character, PAffect(Item), 0);
        end;
      ReadyWrongClass:
        ShowFlashMessage('Wrong Class');
      ReadySlotUsed:
        begin
          res12_fn_0442(LongInt(Character), Character^.SlotItems[ShortInt(Slot)], 0, 0, 0, 0);
          ShowFlashMessage('already using ' + Character^.SlotItems[ShortInt(Slot)]^.Text);
        end;
      ReadyHandsFull:
        if (ds49F3 <> ViewModeCombat) or (Character^.Quick = 0) then
          ShowFlashMessage('Your hands are full!');
    end;
  end;
end;
{ ovl19:1734. The Trade action of the item menu (RunItemMenu's T key, after CanGiveUpItem; ovl19:0EF8).
  Redraws the screen, then asks "Trade with Whom?" (SelectPartyMember), which picks the recipient into Recipient,
  starting from the viewed character (ViewedCharacter). Nothing is traded when no member is picked. Otherwise ViewedCharacter
  is set to the recipient. When WouldOverloadInventory refuses the recipient, "Overloaded" is shown and the
  item stays. Otherwise the item goes to AddItemCopy with the recipient and to RemoveInventoryItem with
  SelectedCharacter (the Drop action makes the same RemoveInventoryItem call), and the recipient's carried weight
  is recalculated (RecalcCombatValues). Parameter: Item, the item traded. Globals: ViewedCharacter (the viewed character),
  SelectedCharacter (the giver). Side effects: the screen (RedrawView) and the messages. }
procedure TradeItem(Item: PMenuLine);
var
  Recipient: PCharacter;
begin
  Recipient := ViewedCharacter;
  RedrawView;
  SelectPartyMember('Trade with Whom?', 1, Recipient);
  if Recipient <> nil then
  begin
    ViewedCharacter := Recipient;
    if WouldOverloadInventory(Recipient, Item) then
      ShowFlashMessage('Overloaded')
    else
    begin
      AddItemCopy(Recipient, Item);
      RemoveInventoryItem(SelectedCharacter, Item);
      RecalcCombatValues(Recipient);
    end;
  end;
end;
{ ovl19:17ED. The Halve action of the item menu (RunItemMenu's H key, ovl19:0EF8): splits the stack Item
  in two. Half is its Count div 2; when Half is zero "Can't halve that" is shown. Otherwise a new record
  (New, 63 bytes) is a copy of Item with Count Half and not Readied, linked in after Item: it takes Item's
  old Next, and Item keeps the rest of the count (Count minus Half) and points at the new record. Parameter:
  Item, the stack halved. Side effects: a new item record is allocated (it is never freed here); the
  message (ShowFlashMessage). }
procedure HalveItem(Item: PMenuLine);
var
  NewItem: PMenuLine;           { the second half of the stack }
  Half: Byte;                   { the count the new record takes }
  Rest: Byte;                   { the count Item keeps }
begin
  Half := Item^.Count div 2;
  if Half > 0 then
  begin
    Rest := Item^.Count - Half;
    New(NewItem);
    Move(Item^, NewItem^, SizeOf(TMenuLine));
    NewItem^.Count := Half;
    NewItem^.Readied := False;
    NewItem^.Next := Item^.Next;
    Item^.Count := Rest;
    Item^.Next := NewItem;
  end
  else
    ShowFlashMessage('Can''t halve that');
end;
{ ovl19:189D. The Join action of the item menu (RunItemMenu's J key, ovl19:0EF8): gathers into Item the counts
  of the other items of SelectedCharacter that match it. A match has a nonzero Count, the same NameNum[1..3],
  ItemType, Plus, PlusSave, Cursed and Weight, and Affects[1] below 2 (QUIRK ovl19:19A1 below). Each match is
  taken off the character (RemoveInventoryItem) and its count added to the total, while the total stays at most
  255. When the total would pass 255, Target is filled to 255, the match gives up what is needed to make
  255 (its count drops) and the match becomes the item that gathers the rest. Parameter: Item, the stack
  that gathers. Globals: SelectedCharacter (its Items list). Side effects: matches leave the list.
  QUIRK ovl19:19A1: the Affects[1], Affects[2] and Affects[3] tests compare the match with itself (both
  sides read Cursor), so they never reject a match; only the Affects[1] below 2 test (ovl19:19B4) does. }
procedure JoinItem(Item: PMenuLine);
var
  Cursor: PMenuLine;            { the item of the character's list being looked at }
  Next: PMenuLine;              { the item after Cursor, read before Cursor can leave the list }
  Target: PMenuLine;            { the stack that gathers the counts: Item, then a match that was filled up }
  Total: Byte;                  { the count Target will hold }
begin
  Target := Item;
  Total := Target^.Count;
  Cursor := SelectedCharacter^.Items;
  while Cursor <> nil do
  begin
    Next := Cursor^.Next;
    if (Cursor <> Target) and (Cursor^.Count > 0) and
      (Cursor^.NameNum[1] = Target^.NameNum[1]) and (Cursor^.NameNum[2] = Target^.NameNum[2]) and
      (Cursor^.NameNum[3] = Target^.NameNum[3]) and (Cursor^.ItemType = Target^.ItemType) and
      (Cursor^.Plus = Target^.Plus) and (Cursor^.PlusSave = Target^.PlusSave) and
      (Cursor^.Cursed = Target^.Cursed) and (Cursor^.Weight = Target^.Weight) and
      (Cursor^.Affects[1] = Cursor^.Affects[1]) and (Cursor^.Affects[1] < 2) and
      (Cursor^.Affects[2] = Cursor^.Affects[2]) and (Cursor^.Affects[3] = Cursor^.Affects[3]) then
    begin
      if Total + Cursor^.Count <= 255 then
      begin
        Inc(Total, Cursor^.Count);
        RemoveInventoryItem(SelectedCharacter, Cursor);
      end
      else
      begin
        Target^.Count := 255;
        Cursor^.Count := Cursor^.Count - (255 - Total);
        Total := Cursor^.Count;
        Target := Cursor;
      end;
    end;
    Cursor := Next;
  end;
  Target^.Count := Total;
end;
{ ovl19:1A8A. The Use action: Item, one of SelectedCharacter's items, is used and Done (the stop flag of the View
  prompt and the item menu) is set to what the use ends with. Called by RunItemMenu (the U key, ovl19:0EF8) and by
  UseMagicItem (ovl09:03E4). A scroll (ovl22_e6 true) gives its spell by ChooseSpellFromList ("on Scroll", with
  Choice -1 it opens the Spells window) and is remembered in UsedScroll. Any other item with Affects[2] above 0 and
  Affects[3] below AffectFlag gives the spell Affects[2] and sets ItemAffectUse. No spell (0, or none chosen) sets
  Done to 0. Otherwise, in combat (view mode 5) for a character the computer does not fight for (Quick 0),
  DrawCombatScreen runs first. An affect item's use shows "uses an item" and the item's line (ShowCharacterMessage,
  res12_fn_0442, a delay). ovl22_e5 casts the spell and sets Done; in combat a spell whose SpellTable row has byte
  +$B set takes Done from EndCombatTurn instead. With Done set, a scroll is used up through ovl22_e7; an item that
  is not a scroll and has Affects[1] above 0 loses one of its Count when the count is above 1, else one charge
  (Affects[1]), and leaves the character (RemoveInventoryItem) with its last charge. Parameters: Item, Done. Globals:
  SelectedCharacter, ds49F3 (the view mode, 5 for combat), SpellTable, UsedScroll, ItemAffectUse. Side effects:
  messages, the screen (the item line is on row 22, or 23 in combat). }
procedure UseItem(Item: PMenuLine; var Done: Byte);
const
  TitleColor = 10;
  ItemPromptRow = 23;
  SpellListOnScroll = 2;
  UseListMode = 1;              { ChooseSpellFromList's DisplayMode for a use; ovl22_e1 receives it, meaning not known yet }
  LastSpell = $38;              { the last row of SpellTable; an affect value above it is shifted down by SpellShift }
  SpellShift = $17;
var
  Spell: Byte;                  { the spell the use casts, from the scroll or Affects[2]; 0 when there is none }
  Choice: Word;                 { -1: ChooseSpellFromList opens its window and asks for a spell }
  Listed: Byte;                 { ChooseSpellFromList's Listed: nonzero when the list has spells }
begin
  Choice := $FFFF;
  ItemAffectUse := False;
  Spell := 0;
  if ovl22_e6(Item) then
  begin
    UsedScroll := Item;
    Spell := ChooseSpellFromList(SpellListOnScroll, UseListMode, Choice, Listed);
  end
  else if (Item^.Affects[2] > 0) and (Item^.Affects[3] < AffectFlag) then
  begin
    ItemAffectUse := True;
    Spell := Item^.Affects[2];
  end;
  if Spell = 0 then
    Done := 0
  else
  begin
    if (ds49F3 = ViewModeCombat) and (SelectedCharacter^.Quick = 0) then
      DrawCombatScreen;
    if ItemAffectUse then
    begin
      if Spell > LastSpell then
        Dec(Spell, SpellShift);
      ShowCharacterMessage(SelectedCharacter, 'uses an item', 10, 0);
      if ds49F3 = ViewModeCombat then
      begin
        DrawTextAt(0, ItemPromptRow, TitleColor, 'Item:');
        res12_fn_0442(LongInt(SelectedCharacter), Item, 5, ItemPromptRow, 0, 1);
      end
      else
        res12_fn_0442(LongInt(SelectedCharacter), Item, 1, 22, 0, 1);
      DelayByGameSpeed;
      ClearCharacterMessage;
    end;
    ItemAffectUse := True;
    ovl22_e5(Spell, SelectedCharacter^.Quick, 0, Done);
    ItemAffectUse := False;
    if (ds49F3 = ViewModeCombat) and (SpellTable[Spell].PadB[$B] <> 0) then
      Done := EndCombatTurn(SelectedCharacter);
  end;
  if Done <> 0 then
  begin
    if ovl22_e6(Item) then
      ovl22_e7(SelectedCharacter, Item, Spell)
    else if Item^.Affects[1] > 0 then
    begin
      if Item^.Count > 1 then
        Dec(Item^.Count)
      else
      begin
        Dec(Item^.Affects[1]);
        if Item^.Affects[1] = 0 then
          RemoveInventoryItem(SelectedCharacter, Item);
      end;
    end;
  end;
end;
{ ovl19:1CEE. The Sell action of the item menu (RunItemMenu's S key, ovl19:0EF8, after CanGiveUpItem): the offer for
  Item is half its Value in gold (Value div 2), and a stack of more than one item is offered its Count times that
  offer divided by StackDivisor (QUIRK ovl19:1D1A). The offer is shown on row 21 as "I'll give you <offer> gold
  pieces for your <name>" and the character is asked "Is It a Deal? ". On Y, "Sold!" is shown, the item leaves
  SelectedCharacter (RemoveInventoryItem) and the offer is paid as platinum (GoldPerPlatinum gold each, Offer div 5) and
  gold (Offer mod 5). Every coin weighs one, so WouldOverload (ovl21:0054) may refuse them: then "Overloaded.
  Money will be put in pool." is shown, Room (what he can still carry) limits the platinum that goes to him, and
  the rest goes to PooledMoney[PlatinumKind]. Parameter: Item. Globals: SelectedCharacter (the seller),
  SheetCharacter (the item line res12_fn_0442 draws at ovl19:1D55), PooledMoney. Side effects: messages, the
  window rows 21 and 22 (cleared at the end). QUIRK ovl19:1D1A: the test for kind $49 is followed by a test of the
  same kind for $1C, so the $1C branch (ovl19:1D46, the stack offer without the division) is never taken. }
procedure SellItem(Item: PMenuLine);
const
  MessageLeft = 1;
  MessageTop = 21;
  MessageRight = 38;
  MessageBottom = 22;
  MessageColor = 14;
  ItemKindSlot11 = $49;         { ReadyItem checks body slot 11 for this kind (ovl19:14D0) }
  ItemKindSlot12 = $1C;         { and body slot 12 for this kind }
  StackDivisor = 20;            { the divisor of a stack's offer [I] }
  GoldPerPlatinum = 5;          { platinum is 1000 copper against 200 for gold (CoinCopperValues) }
  GoldKind = 3;                 { the MoneyKindNames indexes of gold and platinum }
  PlatinumKind = 4;
var
  Offer: Word;                  { the offer in gold: half the Value, a stack's Count times it divided by StackDivisor }
  Platinum: Word;               { the part of the offer paid in platinum: Offer div GoldPerPlatinum }
  Gold: Word;                   { the rest of the offer, paid in gold: Offer mod GoldPerPlatinum }
  Room: Word;                   { WouldOverload's Room: the coins the character can still carry (ovl21:0054) [I] }
begin
  Offer := 0;
  if Item^.Value > 0 then
    Offer := Item^.Value div 2;
  if Item^.Count > 1 then
    if not ((Item^.ItemType = ItemKindSlot11) and (Item^.ItemType = ItemKindSlot12)) then
      Offer := (Offer * Item^.Count) div StackDivisor
    else
      Offer := Offer * Item^.Count;
  res12_fn_0442(LongInt(SheetCharacter), Item, 0, 0, 0, 0);
  ShowPagedText(MessageLeft, MessageTop, MessageRight, MessageBottom, MessageColor, 1,
    'I''ll give you ' + WordToText(Offer) + ' gold pieces for your ' + Item^.Text);
  if AskYesNo('Is It a Deal? ', 13, 10, 15) = 'Y' then
  begin
    ShowFlashMessage('Sold!');
    RemoveInventoryItem(SelectedCharacter, Item);
    Platinum := Offer div GoldPerPlatinum;
    Gold := Offer mod GoldPerPlatinum;
    if WouldOverload(SelectedCharacter, Gold + Platinum, Room) then
    begin
      ShowFlashMessage('Overloaded.  Money will be put in pool.');
      if Room > Platinum then
        Inc(SelectedCharacter^.Money[PlatinumKind], Platinum)
      else
      begin
        Inc(SelectedCharacter^.Money[PlatinumKind], Room);
        Inc(PooledMoney[PlatinumKind], Platinum - Room);
      end;
      Inc(SelectedCharacter^.Money[GoldKind], Gold);
    end
    else
    begin
      Inc(SelectedCharacter^.Money[PlatinumKind], Platinum);
      Inc(SelectedCharacter^.Money[GoldKind], Gold);
    end;
  end;
  ClearWindow(MessageLeft, MessageTop, MessageRight, MessageBottom);
end;
{ ovl19:1F52. The Id action of the item menu (RunItemMenu's I key, ovl19:0EF8; whitepaper 5.4): identifies Item
  for 200 gold pieces. It shows "For 200 gold pieces I'll identify your <item>" and asks "Is It a Deal? ". On Y
  the price comes from SelectedCharacter's money (CharacterMoneyValueInGold, SetCharacterGold) or else from the
  pooled money (PooledMoney, SetPooledGold); when neither covers it, "Not Enough Money" is shown. A paid item
  whose HiddenNames is set is identified: HiddenNames is cleared, its line is drawn again (res12_fn_0442), "It
  looks like some sort of <item>" is shown and Redraw is set. Otherwise "I can't tell anything new about your
  <item>" is shown. Parameters: Item, the item; Redraw, the var flag of the item list (1: draw it again).
  Side effects: rows 21 and 22 (columns 1 to 38) are cleared at the end; DelayByGameSpeed after a payment. }
procedure IdentifyItem(Item: PMenuLine; var Redraw: Byte);
const
  MessageLeft = 1;
  MessageTop = 21;
  MessageRight = 38;
  MessageBottom = 22;
  MessageColor = 14;
  ClearTextBeforeMessage = 1;
  IdentifyPrice = 200;
  PromptTitleColor = 13;
  PromptWordColor = 10;
  PromptHotColor = 15;
var
  CharacterGold: LongInt;       { the gold value of SelectedCharacter's money }
  PooledGold: LongInt;          { the gold value of the pooled money }
  Paid: Boolean;                { the price was taken from the character's money or from the pool }
begin
  Paid := False;
  res12_fn_0442(LongInt(SheetCharacter), Item, 0, 0, 0, 0);
  ShowPagedText(MessageLeft, MessageTop, MessageRight, MessageBottom, MessageColor, ClearTextBeforeMessage,
    'For 200 gold pieces I''ll identify your ' + Item^.Text);
  if AskYesNo('Is It a Deal? ', PromptTitleColor, PromptWordColor, PromptHotColor) = 'Y' then
  begin
    CharacterGold := CharacterMoneyValueInGold(SelectedCharacter);
    if CharacterGold >= IdentifyPrice then
    begin
      Paid := True;
      Dec(CharacterGold, IdentifyPrice);
      SetCharacterGold(CharacterGold);
    end
    else
    begin
      PooledGold := MoneyValueInGold(PooledMoney);
      if PooledGold >= IdentifyPrice then
      begin
        Paid := True;
        Dec(PooledGold, IdentifyPrice);
        SetPooledGold(PooledGold);
      end
      else
        ShowFlashMessage('Not Enough Money');
    end;
  end;
  if Paid then
  begin
    if Item^.HiddenNames = 0 then
      ShowPagedText(MessageLeft, MessageTop, MessageRight, MessageBottom, MessageColor, ClearTextBeforeMessage,
        'I can''t tell anything new about your ' + Item^.Text)
    else
    begin
      Item^.HiddenNames := 0;
      res12_fn_0442(LongInt(SheetCharacter), Item, 0, 0, 0, 0);
      ShowPagedText(MessageLeft, MessageTop, MessageRight, MessageBottom, MessageColor, ClearTextBeforeMessage,
        'It looks like some sort of ' + Item^.Text);
      Redraw := 1;
    end;
  end;
  if Paid then
    DelayByGameSpeed;
  ClearWindow(MessageLeft, MessageTop, MessageRight, MessageBottom);
end;
{ ovl19:2156. The Trade command of the View prompt for money (ViewSelectedCharacter's T key; whitepaper 5.4):
  gives money of SelectedCharacter to another member. "Trade to?" asks for the recipient (SelectPartyMember), which
  is kept in ViewedCharacter. The coin kinds SelectedCharacter holds are listed under "Select type of coin", each with
  its amount, its name right-aligned in eight columns. The chosen kind is asked for ("How much <kind> will you
  trade? ", ReadAmount, at most the character's money of that kind) and TransferMoney moves it to the recipient.
  The list is built again while money is left, and the recipient is asked again when the list is left with
  money still held. Parameters: none. Globals: ViewedCharacter (the recipient), SelectedCharacter (the giver).
  Side effects: the screen (RedrawView, ShowCharacterSheet, ShowCharacterMoney) and the menu lines (GetMem,
  FreeMenuList). Its list is the one TakeMoney (ovl21:0CEB) builds for the pool.
  QUIRK ovl19:21EE: Kinds is incremented for every listed kind and never read.
  QUIRK ovl19:2468: Finished is not set when the list is cancelled before any transfer, so the test reads the
  byte the frame held before the call. }
procedure TradeMoney;
const
  MenuLineBytes = $2E;          { the Text, Flag29 and Next fields of a menu line, as NewMenuList allocates }
  LastMoneyKind = 6;
  NameColumnWidth = 8;          { the coin names are right-aligned in this many columns }
  ListHeadingColor = 13;
  ListLineColor = 10;
  ListHighlightColor = 15;
  ListLeft = 12;
  ListTop = 7;
  ListRight = 25;
  ListBottom = 13;
  AmountColor = 10;
var
  Recipient: PCharacter;        { the member the money goes to: ViewedCharacter, then the answer of "Trade to?" }
  Kind: ShortInt;               { the coin kind of the loops }
  CoinKind: ShortInt;           { the coin kind the list gave }
  I: Byte;                      { the padding loop counter }
  Pad: Byte;                    { the spaces that right-align a coin name }
  List: PMenuLine;              { the coin lines, passed to ChooseFromList }
  Chosen: PMenuLine;            { the line ChooseFromList returns; also the old first line while the list grows }
  Head: PMenuLine;              { the first line of the list, freed with FreeMenuList }
  Kinds: Word;                  { the count of listed kinds }
  Choice: Integer;              { ChooseFromList's highlighted line }
  Num: string[15];              { the amount of a coin kind as text }
  Spaces: string[4];            { the padding of a coin name }
  Text: string;                 { the coin name, then the prompt "How much <kind> will you trade? " }
  Key: Char;                    { the key ChooseFromList returned; never read }
  Amount: Word;                 { the amount given }
  Finished: Boolean;            { the trade is over: no recipient, or no money is left }
  Done: Boolean;                { the list ends: it was left, or no money is left }
  Redraw: Byte;                 { ChooseFromList's Redraw }
begin
  repeat
    Recipient := ViewedCharacter;
    RedrawView;
    SelectPartyMember('Trade to?', 1, Recipient);
    if Recipient = nil then
      Finished := True
    else
    begin
      ShowCharacterSheet;
      repeat
        ShowCharacterMoney;
        ViewedCharacter := Recipient;
        List := nil;
        Chosen := nil;
        Head := nil;
        Kinds := 0;
        for Kind := 0 to LastMoneyKind do
          if SelectedCharacter^.Money[Kind] <> 0 then
          begin
            Inc(Kinds);
            if List = nil then
            begin
              GetMem(List, MenuLineBytes);
              List^.Next := nil;
            end
            else
            begin
              Chosen := List;
              GetMem(List, MenuLineBytes);
              List^.Next := Chosen;
            end;
            Str(SelectedCharacter^.Money[Kind], Num);
            Pad := NameColumnWidth - Length(MoneyKindNames[Kind]);
            Spaces := '';
            Spaces[0] := Chr(Pad);
            for I := 1 to Pad do
              Spaces[I] := ' ';
            List^.Text := Spaces + MoneyKindNames[Kind] + ' ' + Num;
            List^.Flag29 := 0;
          end;
        Head := List;
        Choice := 0;
        Redraw := 1;
        Key := ChooseFromList('Select type of coin', '', ListHeadingColor, ListLineColor, ListHighlightColor,
          ListLeft, ListTop, ListRight, ListBottom, List, 1, Redraw, Choice, Chosen);
        if Chosen = nil then
          Done := True
        else
        begin
          Text := '';
          CoinKind := MoneyKindOfLine(Chosen^.Text, Text);
          Text := 'How much ' + Text + 'will you trade? ';
          Amount := ReadAmount(SelectedCharacter^.Money[CoinKind], Text, AmountColor);
          TransferMoney(SelectedCharacter, Recipient, Amount, CoinKind);
          Done := True;
          Finished := True;
          for Kind := 0 to LastMoneyKind do
            if SelectedCharacter^.Money[Kind] > 0 then
            begin
              Finished := False;
              Done := False;
            end;
        end;
        if Head <> nil then
          FreeMenuList(Head);
      until Done;
    end;
  until Finished;
end;
{ ovl19:24A7. The Drop command for money of the View prompt (ViewSelectedCharacter's D key, whitepaper 5.4; the
  Drop entry shows only while the character holds money): draws the money window (ShowCharacterMoney), then lists
  the coin kinds SelectedCharacter holds under "Select type of coin", each with its amount, and asks for one
  (ChooseFromList). "How much <kind> will you drop? " asks for the amount (ReadAmount, at most the money of that kind)
  and DropMoney takes it away (ovl21:0A01). The list is built again while money is left; the menu ends when the
  list is left or no money is left. Parameters: none. Globals: SelectedCharacter (the giver). Side effects: the
  screen (the list, the prompt) and the list lines (GetMem, FreeMenuList).
  QUIRK ovl19:24EF: Kinds is incremented for every listed kind and never read. }
procedure ChooseAndDropMoney;
const
  MenuLineBytes = $2E;          { the Text, Flag29 and Next fields of a menu line, as NewMenuList allocates }
  LastMoneyKind = 6;
  NameColumnWidth = 8;          { the coin names are right-aligned in this many columns }
  ListHeadingColor = 13;
  ListLineColor = 10;
  ListHighlightColor = 15;
  ListLeft = 12;
  ListTop = 7;
  ListRight = 25;
  ListBottom = 13;
  AmountColor = 10;
var
  Kind: ShortInt;               { the coin kind of the loops }
  CoinKind: ShortInt;           { the coin kind the list gave }
  Pad: Byte;                    { the spaces that right-align a coin name }
  I: Byte;                      { the padding loop counter }
  Kinds: Word;                  { the count of listed kinds }
  Choice: Integer;              { ChooseFromList's highlighted line }
  List: PMenuLine;              { the coin lines, passed to ChooseFromList }
  Chosen: PMenuLine;            { the line ChooseFromList returns; also the old first line while the list grows }
  Head: PMenuLine;              { the first line of the list, freed with FreeMenuList }
  Done: Boolean;                { the menu ends: no money is left, or the list was left }
  Redraw: Byte;                 { ChooseFromList's Redraw }
  Num: string[15];              { the amount of a coin kind as text }
  Spaces: string[4];            { the padding of a coin name }
  Text: string;                 { the coin name, then the prompt "How much <kind> will you drop? " }
  Key: Char;                    { the key ChooseFromList returned; never read }
  Amount: Word;                 { the amount given }
begin
  repeat
    ShowCharacterMoney;
    List := nil;
    Chosen := nil;
    Head := nil;
    Kinds := 0;
    for Kind := 0 to LastMoneyKind do
      if SelectedCharacter^.Money[Kind] <> 0 then
      begin
        Inc(Kinds);
        if List = nil then
        begin
          GetMem(List, MenuLineBytes);
          List^.Next := nil;
        end
        else
        begin
          Chosen := List;
          GetMem(List, MenuLineBytes);
          List^.Next := Chosen;
        end;
        Str(SelectedCharacter^.Money[Kind], Num);
        Pad := NameColumnWidth - Length(MoneyKindNames[Kind]);
        Spaces := '';
        Spaces[0] := Chr(Pad);
        for I := 1 to Pad do
          Spaces[I] := ' ';
        List^.Text := Spaces + MoneyKindNames[Kind] + ' ' + Num;
        List^.Flag29 := 0;
      end;
    Head := List;
    Choice := 0;
    Redraw := 1;
    Key := ChooseFromList('Select type of coin', '', ListHeadingColor, ListLineColor, ListHighlightColor,
      ListLeft, ListTop, ListRight, ListBottom, List, 1, Redraw, Choice, Chosen);
    if Chosen = nil then
      Done := True
    else
    begin
      Text := '';
      CoinKind := MoneyKindOfLine(Chosen^.Text, Text);
      Text := 'How much ' + Text + 'will you drop? ';
      Amount := ReadAmount(SelectedCharacter^.Money[CoinKind], Text, AmountColor);
      DropMoney(SelectedCharacter, Amount, CoinKind);
      Done := True;
      for Kind := 0 to LastMoneyKind do
        if SelectedCharacter^.Money[Kind] > 0 then
          Done := False;
    end;
    if Head <> nil then
      FreeMenuList(Head);
  until Done;
end;
{ ovl19:275B: rejects an item when the character already has more than 15 items or when its added
  weight exceeds the character's strength-based capacity plus 1500. The item weight is multiplied
  by its count only when the count is nonzero. The call to RecalcCombatValues occurs before the checks. }
function WouldOverloadInventory(Character: PCharacter; Item: PMenuLine): Boolean;
const
  MaximumItemCount = 15;
  BaseCarryAllowance = 1500;
var
  Overloaded: Boolean;
  AddedWeight: Word;
begin
  RecalcCombatValues(Character);
  Overloaded := False;
  if Character^.ItemCountC7 > MaximumItemCount then
    Overloaded := True;
  AddedWeight := Item^.Weight;
  if Item^.Count > 0 then
    AddedWeight := AddedWeight * Item^.Count;
  if Character^.CarriedWeight + AddedWeight >
    StrengthWeightAllowance(Character) + BaseCarryAllowance then
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
      DrawCharacterName(SelectedCharacter, 1, 1, 1);
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
