unit OVL21;
{ Money: the party's coins and their weight (whitepaper 5.4.1). The value of money in gold
  (MoneyValueInGold), setting a character's or the pool's money from a gold amount (SetCharacterGold,
  SetPooledGold), the carried weight and its limit (CarryLimit, WouldOverload), the Take, Pool, Share
  and Appraise commands the shop, the Temple and the treasure menu share (TakeMoney, PoolMoney,
  ShareMoney, AppraiseGems), and BuildTreasureItem, which makes the items a treasure holds. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS, RES06;
function CarryLimit(Who: PCharacter): Word;
procedure RemoveCarriedWeight(Who: PCharacter; Amount: Word);
procedure AddCarriedWeight(Who: PCharacter; Amount: Word);
function WouldOverload(Who: PCharacter; Amount: Word; var Room: Word): Boolean;
function MoneyValueInGold(Money: TPartyMoney): LongInt;
procedure SetCharacterGold(Amount: Word);
procedure SetPooledGold(Amount: Word);
procedure GivePlatinum(Amount: Word);
function ReadAmount(Max: Word; Prompt: String40; Color: Byte): Word;
procedure TransferMoney(var Giver, Taker: PCharacter; Amount: Word; Kind: ShortInt);
procedure PoolMoney;
function CountSharers: Byte;
procedure ShareMoney;
procedure DropMoney(Who: PCharacter; Amount: Word; Kind: ShortInt);
procedure TakeFromPool(Who: PCharacter; Amount: Word; Kind: ShortInt);
function MoneyKindOfLine(Line: string; var Name: string): ShortInt;
procedure TakeMoney;
procedure TreasureLeft(var MoneyLeft, ItemsLeft: Byte);
function RollItemBonus: ShortInt;
procedure BuildTreasureItem(Kind: Byte; var Item: TMenuLine);
procedure AppraiseGems(var Redraw: Byte);
implementation
uses RES04, RES09, RES12, OVL24, OVL25;

const
  BaseLoad = 1500;      { the load every character may carry before the strength allowance }
  CopperCoin = 0;       { the money kinds, indexes of TCharacter.Money and TPartyMoney }
  SilverCoin = 1;
  ElectrumCoin = 2;
  GoldCoin = 3;
  PlatinumCoin = 4;
  GemsKind = 5;
  JewelryKind = 6;
  GoldPerPlatinum = 5;
  PromptRow = 24;       { the bottom text row, where amounts are typed }
  ScreenCols = 40;
  White = 15;
  KeyBackspace = #8;
  KeyEnter = #13;
  KeyEscape = #27;
  LastMoneyKind = JewelryKind;    { seven kinds: copper, silver, electrum, gold, platinum, gems, jewelry }
  { TCharacter.B84 values of the members that pool and share money: 0 and $B3 (a player-run
    member; what $B3 marks is not known) }
  SharerB84 = $B3;
  ComputerRunB84 = $80; { B84 from $80 up: a member run by the computer, who gets no share }
  ViewShop = 1;         { ds49F3 view modes where dropped money goes into the pool: a shop or }
  ViewTreasure = 6;     { the Temple (1), the treasure after a battle (6) }
  MenuLineBytes = $2E;  { the Text, Flag29 and Next fields of TMenuLine, as NewMenuList allocates }
  MaxItems = 16;        { a character carries at most 16 items (TCharacter.ItemCountC7) }
  GemItemName = $65;    { the name number of a kept gem (NameNum[3]) }
  JewelItemName = $D6;  { the name number of a kept piece of jewelry }
  GemItemType = $46;    { the item type of a kept gem or jewel }
  HalfGoldInCopper = 100;  { added before dividing by the gold value: rounds to the nearest gold piece }

{ ovl21:0000. The most weight Who may carry: 1500 plus the strength allowance StrengthWeightAllowance
  (negative for a weak character). }
function CarryLimit(Who: PCharacter): Word;
begin
  CarryLimit := StrengthWeightAllowance(Who) + BaseLoad;
end;
{ ovl21:0020. Takes Amount off the weight Who carries (coins handed away). }
procedure RemoveCarriedWeight(Who: PCharacter; Amount: Word);
begin
  Who^.CarriedWeight := Who^.CarriedWeight - Amount;
end;
{ ovl21:003A. Adds Amount to the weight Who carries (coins taken). }
procedure AddCarriedWeight(Who: PCharacter; Amount: Word);
begin
  Who^.CarriedWeight := Who^.CarriedWeight + Amount;
end;
{ ovl21:0054. Tests whether Who would be overloaded carrying Amount more: True when the carried
  weight plus Amount exceeds the most Who may carry, with Room set to what still fits; False with
  Room 0 otherwise. }
function WouldOverload(Who: PCharacter; Amount: Word; var Room: Word): Boolean;
begin
  if Who^.CarriedWeight + Amount > CarryLimit(Who) then
  begin
    WouldOverload := True;
    Room := CarryLimit(Who) - Who^.CarriedWeight;
  end
  else
  begin
    WouldOverload := False;
    Room := 0;
  end;
end;
{ ovl21:00A8. The value of Money in gold pieces, rounded: the copper value of the first five kinds
  (copper to platinum, CoinCopperValues) plus half a gold piece, divided by the gold value. Gems and
  jewelry (kinds 5 and 6) are not counted. Called by the shop, the Temple and ovl19 on the pooled
  money (PooledMoney). }
function MoneyValueInGold(Money: TPartyMoney): LongInt;
var
  Total: LongInt;
  Kind: ShortInt;
begin
  Total := 0;
  for Kind := CopperCoin to PlatinumCoin do
    Inc(Total, CoinCopperValues[Kind] * Money[Kind]);
  MoneyValueInGold := (Total + HalfGoldInCopper) div CoinCopperValues[GoldCoin];
end;
{ ovl21:0130. Sets the selected character's coins to Amount gold pieces in the fewest coins:
  copper to platinum cleared, then Amount div 5 platinum and Amount mod 5 gold. Called after a
  purchase with the money left (shop, Temple). }
procedure SetCharacterGold(Amount: Word);
var
  Kind: ShortInt;
begin
  for Kind := CopperCoin to PlatinumCoin do
    SelectedCharacter^.Money[Kind] := 0;
  SelectedCharacter^.Money[PlatinumCoin] := Amount div GoldPerPlatinum;
  SelectedCharacter^.Money[GoldCoin] := Amount mod GoldPerPlatinum;
end;
{ ovl21:0185. Sets the pooled money (PooledMoney) to Amount gold pieces the same way: copper to
  platinum cleared, then Amount div 5 platinum and Amount mod 5 gold. }
procedure SetPooledGold(Amount: Word);
var
  Kind: ShortInt;
begin
  for Kind := CopperCoin to PlatinumCoin do
    PooledMoney[Kind] := 0;
  PooledMoney[PlatinumCoin] := Amount div GoldPerPlatinum;
  PooledMoney[GoldCoin] := Amount mod GoldPerPlatinum;
end;
{ ovl21:0203. Gives the selected character Amount platinum pieces: when that would overload him
  he takes what fits (Room) and the rest goes into the pooled money with the message
  "Overloaded.  Money will be put in Pool."; the carried weight grows by what he takes. }
procedure GivePlatinum(Amount: Word);
var
  Room: Word;
begin
  if WouldOverload(SelectedCharacter, Amount, Room) then
  begin
    ShowFlashMessage('Overloaded.  Money will be put in Pool.');
    Inc(SelectedCharacter^.Money[PlatinumCoin], Room);
    AddCarriedWeight(SelectedCharacter, Room);
    PooledMoney[PlatinumCoin] := Amount + PooledMoney[PlatinumCoin] - Room;
  end
  else
  begin
    Inc(SelectedCharacter^.Money[PlatinumCoin], Amount);
    AddCarriedWeight(SelectedCharacter, Amount);
  end;
end;
{ ovl21:0294. Asks for an amount on the bottom row: shows Prompt in Color, then reads digits
  (shown in white after the prompt) until Enter or Escape; Backspace deletes the last digit. A
  number above Max is replaced by Max. Returns the amount typed, 0 on Escape. }
function ReadAmount(Max: Word; Prompt: String40; Color: Byte): Word;
var
  Col: Byte;              { the column after the last digit }
  Unused: Byte;
  Start: Byte;            { the column of the first digit, right after the prompt }
  MaxText: string[5];
  Digits: string[6];
  Key: Char;
  Typed: LongInt;
  Code: Integer;
  Amount: Word;
begin
  ClearTextCells(0, PromptRow, 0, ScreenCols);
  DrawTextAt(0, PromptRow, Color, Prompt);
  Start := Length(Prompt);
  Col := Start;
  Str(Max, MaxText);
  Digits := '';
  repeat
    Key := ReadGameKey;
    case Key of
      '0'..'9':
        begin
          Digits := Concat(Digits, Key);
          Val(Digits, Typed, Code);
          if Max >= Typed then
            Inc(Col)
          else
          begin
            Digits := MaxText;
            Col := Start + Length(MaxText);
          end;
          DrawTextAt(Start, PromptRow, White, Digits);
        end;
      KeyBackspace:
        if Length(Digits) > 0 then
        begin
          Digits := Copy(Digits, 1, Length(Digits) - 1);
          ClearTextCells(Col, PromptRow, 0, 1);
          Dec(Col);
        end;
    end;
  until (Key = KeyEnter) or (Key = KeyEscape);
  ClearTextCells(0, PromptRow, 0, ScreenCols);
  if Key = KeyEscape then
    Amount := 0
  else
    Val(Digits, Amount, Code);
  ReadAmount := Amount;
end;
{ ovl21:044C. Hands Amount coins of money kind Kind from Giver to Taker, moving their weight
  with them (but see the quirk); when Taker cannot carry that much more it shows "Overloaded" and nothing moves. }
procedure TransferMoney(var Giver, Taker: PCharacter; Amount: Word; Kind: ShortInt);
begin
  if Taker^.CarriedWeight + Amount <= CarryLimit(Taker) then
  begin
    Giver^.Money[Kind] := Giver^.Money[Kind] - Amount;
    RemoveCarriedWeight(Giver, Amount);
    Taker^.Money[Kind] := Taker^.Money[Kind] + Amount;
    { QUIRK ovl21:04DB: the weight is added back to Giver, not to Taker: Giver's weight ends
      unchanged and Taker's does not grow }
    AddCarriedWeight(Giver, Amount);
  end
  else
    ShowFlashMessage('Overloaded');
end;
{ ovl21:0508. The Pool command: every player-run member (B84 0 or $B3) puts all seven kinds of
  his money into the pool (PooledMoney) and loses its weight; sets MoneyInPool (money in the pool). }
procedure PoolMoney;
var
  Who: PCharacter;
  Kind: ShortInt;
  Slot: ShortInt;
begin
  Who := PCharacter(ds5D96);
  MoneyInPool := 1;
  while Who <> nil do
  begin
    if (Who^.B84 = 0) or (Who^.B84 = SharerB84) then
    begin
      for Kind := 0 to LastMoneyKind do
      begin
        Slot := Kind;
        PooledMoney[Slot] := Who^.Money[Slot] + PooledMoney[Slot];
        RemoveCarriedWeight(Who, Who^.Money[Slot]);
      end;
      FillChar(Who^.Money, SizeOf(Who^.Money), 0);
    end;
    Who := Who^.Next;
  end;
end;
{ ovl21:05E0. The number of members who take part in pooling and sharing (B84 0 or $B3). }
function CountSharers: Byte;
var
  Who: PCharacter;
  Count: Byte;
begin
  Who := PCharacter(ds5D96);
  Count := 0;
  while Who <> nil do
  begin
    if (Who^.B84 = 0) or (Who^.B84 = SharerB84) then
      Inc(Count);
    Who := Who^.Next;
  end;
  CountSharers := Count;
end;
{ ovl21:063A. The Share command: each kind of pooled money is divided by the number of sharers
  (CountSharers). Walking the party, every member below B84 $80 takes his share of each kind, from
  jewelry down to copper, as far as his load allows, plus one coin of the remainder when it fits;
  what he cannot carry goes back to the remainder. The remainders are then handed out to whoever
  can still carry them (any member), and what is left stays in the pool; MoneyInPool says whether any
  money is left there. }
procedure ShareMoney;
var
  Who: PCharacter;
  Unused1: Pointer;
  Sharers: Byte;
  Unused2: Byte;
  Room: Word;
  Share: array[0..LastMoneyKind] of Word;
  Remainder: array[0..LastMoneyKind] of Word;
  Kind: ShortInt;
begin
  Who := PCharacter(ds5D96);
  Unused2 := 0;
  Sharers := CountSharers;
  FillChar(Share, SizeOf(Share), 0);
  FillChar(Remainder, SizeOf(Remainder), 0);
  for Kind := 0 to LastMoneyKind do
    if PooledMoney[Kind] > 0 then
    begin
      Share[Kind] := PooledMoney[Kind] div Sharers;
      Remainder[Kind] := PooledMoney[Kind] mod Sharers;
    end
    else
    begin
      Share[Kind] := 0;
      Remainder[Kind] := 0;
    end;
  while Who <> nil do
  begin
    if Who^.B84 < ComputerRunB84 then
      for Kind := LastMoneyKind downto 0 do
        if not WouldOverload(Who, Share[Kind], Room) then
        begin
          Who^.Money[Kind] := Share[Kind] + Who^.Money[Kind];
          AddCarriedWeight(Who, Share[Kind]);
          if Remainder[Kind] > 0 then
            if not WouldOverload(Who, Remainder[Kind], Room) then
            begin
              Who^.Money[Kind] := Who^.Money[Kind] + 1;
              AddCarriedWeight(Who, 1);
              Dec(Remainder[Kind]);
            end;
        end
        else
        begin
          Who^.Money[Kind] := Who^.Money[Kind] + Room;
          Remainder[Kind] := Remainder[Kind] + Share[Kind] - Room;
          AddCarriedWeight(Who, Room);
        end;
    Who := Who^.Next;
  end;
  for Kind := LastMoneyKind downto 0 do
    if Remainder[Kind] > 0 then
    begin
      Who := PCharacter(ds5D96);
      while Who <> nil do
      begin
        Room := CarryLimit(Who) - Who^.CarriedWeight;
        if Room > 0 then
          if Remainder[Kind] > Room then
          begin
            Who^.Money[Kind] := Who^.Money[Kind] + Room;
            AddCarriedWeight(Who, Room);
            Remainder[Kind] := Remainder[Kind] - Room;
          end
          else
          begin
            Who^.Money[Kind] := Who^.Money[Kind] + Remainder[Kind];
            AddCarriedWeight(Who, Remainder[Kind]);
            Remainder[Kind] := 0;
          end;
        Who := Who^.Next;
      end;
    end;
  MoneyInPool := 0;
  for Kind := 0 to LastMoneyKind do
  begin
    PooledMoney[Kind] := Remainder[Kind];
    if PooledMoney[Kind] <> 0 then
      MoneyInPool := 1;
  end;
end;
{ ovl21:0A01. Drops Amount coins of money kind Kind from Who, with their weight; in a shop or the
  Temple (view mode 1) or at a battle's treasure (6) they go into the pool, elsewhere they are lost. }
procedure DropMoney(Who: PCharacter; Amount: Word; Kind: ShortInt);
begin
  Who^.Money[Kind] := Who^.Money[Kind] - Amount;
  RemoveCarriedWeight(Who, Amount);
  if (ds49F3 = ViewTreasure) or (ds49F3 = ViewShop) then
    PooledMoney[Kind] := PooledMoney[Kind] + Amount;
end;
{ ovl21:0A88. Who takes Amount of money kind Kind from the pool: "Overloaded" and nothing taken when
  he cannot carry that much more; otherwise at most what the pool holds moves to his money, with its
  weight. }
procedure TakeFromPool(Who: PCharacter; Amount: Word; Kind: ShortInt);
var
  Room: Word;
begin
  if WouldOverload(Who, Amount, Room) then
    ShowFlashMessage('Overloaded')
  else
  begin
    if Amount > PooledMoney[Kind] then
      Amount := PooledMoney[Kind];
    PooledMoney[Kind] := PooledMoney[Kind] - Amount;
    Who^.Money[Kind] := Who^.Money[Kind] + Amount;
    AddCarriedWeight(Who, Amount);
  end;
end;
{ ovl21:0B93. The money kind a line of the Take menu names, from its first letter after the leading
  blanks: G is Gems when an E follows, else Gold; P Platinum, E electrum, S silver, C Copper, J
  Jewelry. Name receives the kind's name with a trailing blank for the "How much" prompt.
  QUIRK ovl21:0CB1: for any other letter the result is never assigned. }
function MoneyKindOfLine(Line: string; var Name: string): ShortInt;
var
  I: Byte;
begin
  I := 1;
  while Line[I] = ' ' do
    Inc(I);
  case Line[I] of
    'G':
      if UpCase(Line[I + 1]) = 'E' then
      begin
        MoneyKindOfLine := GemsKind;
        Name := 'Gems ';
      end
      else
      begin
        Name := 'Gold ';
        MoneyKindOfLine := GoldCoin;
      end;
    'P':
      begin
        Name := 'Platinum ';
        MoneyKindOfLine := PlatinumCoin;
      end;
    'E':
      begin
        Name := 'electrum ';
        MoneyKindOfLine := ElectrumCoin;
      end;
    'S':
      begin
        Name := 'silver ';
        MoneyKindOfLine := SilverCoin;
      end;
    'C':
      begin
        Name := 'Copper ';
        MoneyKindOfLine := CopperCoin;
      end;
    'J':
      begin
        Name := 'Jewelry ';
        MoneyKindOfLine := JewelryKind;
      end;
  end;
end;
{ ovl21:0CEB. The Take command for pooled money: in a window, lists every kind of money in the pool
  with its amount ("Select type of coin"), asks "How much <kind> will you take?" (ReadAmount, at most
  the pooled amount) and gives it to the selected character (TakeFromPool); repeats while money is
  left in the pool, until the list is left without a choice. Updates MoneyInPool.
  QUIRK ovl21:0D5C: Count is incremented for every listed kind but never set or read.
  QUIRK ovl21:0EA3: leaving the list without a choice does not free the menu lines. }
procedure TakeMoney;
var
  Kind: ShortInt;
  CoinKind: ShortInt;
  Unused: Word;
  List: PMenuLine;
  Chosen: PMenuLine;
  Head: PMenuLine;
  Count: Word;
  Choice: Integer;
  Text: string;
  Amount: Word;
  Done: Boolean;
  Redraw: Byte;
  Key: Char;
begin
  DrawWindow(1, 1, $26, $16, 0, $0A, '');
  Choice := 0;
  repeat
    Redraw := 1;
    List := nil;
    Chosen := nil;
    for Kind := LastMoneyKind downto 0 do
      if PooledMoney[Kind] > 0 then
      begin
        Inc(Count);
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
        Str(PooledMoney[Kind], Text);
        List^.Text := MoneyKindNames[Kind] + ' ' + Text;
        List^.Flag29 := 0;
      end;
    Chosen := List;
    Head := List;
    Key := ChooseFromList('Select type of coin', '', $0D, $0A, $0F, 2, 2, $0F, 8, List, 1, Redraw, Choice,
      Chosen);
    if (Chosen = nil) or (Key = #0) then
      Done := True
    else
    begin
      Done := False;
      CoinKind := MoneyKindOfLine(Chosen^.Text, Text);
      Text := 'How much ' + Text + 'will you take? ';
      Amount := ReadAmount(PooledMoney[CoinKind], Text, $0A);
      TakeFromPool(SelectedCharacter, Amount, CoinKind);
      FreeMenuList(Head);
      MoneyInPool := 0;
      Done := True;
      for Kind := 0 to LastMoneyKind do
        if PooledMoney[Kind] > 0 then
        begin
          MoneyInPool := 1;
          Done := False;
        end;
    end;
  until Done;
end;
{ ovl21:0F7E. Reports what treasure is left: MoneyLeft 1 when any kind of pooled money is not 0,
  ItemsLeft 1 when the loot list (ds6810) is not empty, else 0. The shop, the Temple and the treasure
  menu build their menus from it. }
procedure TreasureLeft(var MoneyLeft, ItemsLeft: Byte);
var
  Kind: ShortInt;
begin
  MoneyLeft := 0;
  ItemsLeft := 0;
  for Kind := 0 to LastMoneyKind do
    if PooledMoney[Kind] <> 0 then
      MoneyLeft := 1;
  if ds6810 <> nil then
    ItemsLeft := 1;
end;
{ ovl21:0FD2. Rolls the magic bonus of a treasure item: 1 on 1..14 of a d20, 2 on 15..19, 3 on 20. }
function RollItemBonus: ShortInt;
var
  Roll: Byte;
begin
  Roll := RollDice(1, 20);
  case Roll of
    1..14: RollItemBonus := 1;
    15..19: RollItemBonus := 2;
  else
    RollItemBonus := 3;
  end;
end;
{ ovl21:1010. Builds a treasure item of type Kind into Item. Weapons and armour (types 1..$3B, $49,
  $4D, $5D) get a magic bonus (RollItemBonus) and the name numbers, weight and value of their type;
  types $3D and $3E get 1..3 random affects; the other types listed take a fixed row of TreasureItemRows
  chosen by type and a die roll (names, weight, value, affects, bonus 1, 2 for row $61).
  QUIRK ovl21:10D5: type $15 on a 5 of a d5 takes the row at $90, one word before the row at $91.
  QUIRK ovl21:1753: type $4E rolls 2..4, so its row 1 choice is never taken and a 4 takes no row.
  QUIRK ovl21:17A6: type $47 rolls a d11; 11 takes no row. }
procedure BuildTreasureItem(Kind: Byte; var Item: TMenuLine);
var
  Roll: Byte;
  NumAffects: Byte;
  I: Byte;
  Row: Byte;
  Affect: Byte;
begin
  FillChar(Item, SizeOf(Item), 0);
  Row := 0;
  with Item do
  begin
    FillChar(Affects, SizeOf(Affects), 0);
    Next := nil;
    Readied := False;
    HiddenNames := 6;
    Cursed := False;
    ItemType := Kind;
    FillChar(NameNum, SizeOf(NameNum), 0);
    case ItemType of
      1..$3B, $49, $4D, $5D:
        begin
          Plus := RollItemBonus;
          case ItemType of
            $15:
              begin
                Roll := RollDice(1, 5);
                if Roll = 5 then
                  Row := $90;
                NameNum[3] := $15;
                NameNum[2] := Plus + $A1;
              end;
            $1C:
              begin
                NameNum[3] := $1C;
                NameNum[2] := Plus + $A1;
              end;
            $32, $33:
              begin
                NameNum[3] := ItemType;
                NameNum[2] := $31;
                NameNum[1] := Plus + $A1;
                HiddenNames := 4;
              end;
            $34:
              begin
                NameNum[3] := ItemType;
                NameNum[2] := $32;
                NameNum[1] := Plus + $A1;
                HiddenNames := 4;
              end;
            $35..$3A:
              begin
                NameNum[3] := ItemType;
                NameNum[2] := $30;
                NameNum[1] := Plus + $A1;
                HiddenNames := 4;
              end;
            $49:
              begin
                NameNum[3] := $3D;
                NameNum[2] := Plus + $A1;
              end;
            $4D:
              begin
                NameNum[3] := $4F;
                NameNum[2] := $A7;
                Plus := Plus * 2 + 2;
                case Plus of
                  4: NameNum[1] := $DD;
                  6: NameNum[1] := $DE;
                  8: NameNum[1] := $DC;
                end;
              end;
            $5D:
              begin
                NameNum[3] := $42;
                NameNum[2] := $E0;
                NameNum[1] := Plus + $A1;
              end;
          else
            NameNum[3] := ItemType;
            NameNum[2] := Plus + $A1;
          end;
          PlusSave := 0;
          Count := 0;
          case ItemType of
            1, $0D, $0E, $23: Weight := $4B;
            2, $14, $1D, $1F, $20, $21, $27, $2A, $2C, $2E, $3B: Weight := $32;
            3, $18, $28: Weight := $7D;
            4, $0F, $17, $22, $2B, $2D, $33: Weight := $64;
            5, $0C, $11, $13, $32: Weight := $96;
            6: Weight := $0F;
            7: Weight := $1E;
            8, $4D: Weight := $0A;
            9:
              begin
                Weight := $19;
                Count := 5;
              end;
            $0A, $1A, $24: Weight := $3C;
            $0B, $10, $19, $1B, $29, $2F: Weight := $50;
            $12: Weight := $AF;
            $15: Weight := $14;
            $16, $1E: Weight := $28;
            $25: Weight := $23;
            $26, $35: Weight := $FA;
            $34: Weight := $C8;
            $36, $38: Weight := $190;
            $37: Weight := $12C;
            $39: Weight := $15E;
            $3A: Weight := $1C2;
            $2F, $5D: Weight := 1;
          else
            Weight := $28;
            Count := $0A;
          end;
          case ItemType of
            $3B: Value := Plus * $9C4;
            $49, $1C: Value := Plus * $96;
            $35, $36: Value := Plus * $BB8;
            $37, $38: Value := Plus * $DAC;
            $39: Value := Plus * $FA0;
            $3A: Value := Plus * $1388;
            $4D: Value := Plus * $BB8;
          else
            Value := Plus * $7D0;
          end;
        end;
      $3D, $3E:
        begin
          NumAffects := RollDice(1, 3);
          if ItemType = $3D then
            NameNum[3] := $D1
          else
            NameNum[3] := $D0;
          NameNum[2] := NumAffects + $D1;
          NameNum[1] := 0;
          Plus := 1;
          Weight := $19;
          Count := 0;
          Value := 0;
          for I := 1 to NumAffects do
          begin
            Roll := RollDice(1, 3);
            if ItemType = $3D then
              case Roll of
                1: Affect := RollDice(1, $0D) + 8;
                2: Affect := RollDice(1, 7) + $1C;
                3: Affect := RollDice(1, $0B) + $2C;
              end
            else
              case Roll of
                1: Affect := RollDice(1, 8);
                2: Affect := RollDice(1, 7) + $15;
                3: Affect := RollDice(1, 9) + $23;
              end;
            Affects[I] := Affect;
            Value := Roll * $12C + Value;
          end;
        end;
      $3F: Row := $49;
      $43: Row := $91;
      $45:
        begin
          Roll := RollDice(1, 10);
          case Roll of
            1: Row := $29;
            2..6: Row := $79;
            7..10: Row := $81;
          end;
        end;
      $4E:
        begin
          Roll := RollDice(1, 3) + 1;
          case Roll of
            1: Row := $31;
            2: Row := $41;
            3: Row := $71;
          end;
        end;
      $4F: Row := $39;
      $54: Row := 9;
      $5C: Row := $61;
      $47:
        begin
          Roll := RollDice(1, $0B);
          case Roll of
            1..5: Row := $11;
            6..8: Row := 1;
            9: Row := $19;
            10: Row := $51;
          end;
        end;
      $46:
        begin
          Roll := RollDice(1, 10);
          case Roll of
            1..7: Row := $59;
            8..10: Row := $89;
          end;
        end;
    end;
    if Row <> 0 then
    begin
      for I := 0 to 2 do
        NameNum[I + 1] := TreasureItemRows[Row + I];
      Plus := 1;
      PlusSave := 1;
      if Row = $61 then
      begin
        Plus := 2;
        PlusSave := 2;
      end;
      Weight := TreasureItemRows[Row + 3];
      Count := 0;
      Value := TreasureItemRows[Row + 4];
      for I := 1 to 3 do
        Affects[I] := TreasureItemRows[Row + 4 + I];
    end;
  end;
end;
{ ovl21:19B2. The Appraise command of the shop and the Temple for the selected character's gems
  and jewelry: "No Gems or Jewelry" (and Redraw 0) when he has none; otherwise it shows "You have a
  fine collection of:" with the counts and asks "Appraise :  Gems  Jewelry Exit". Each gem or piece
  appraised is taken from his money, valued with a d100 ("The Gem is Valued at <n> gp.", jewels
  "The Jewel is Valued at ..."), and either sold for a fifth of its value in platinum (GivePlatinum)
  or, when he can carry it and has fewer than 16 items, kept as an item of type $46 with that value.
  Repeats until Exit or nothing is left; Redraw is 1 unless there was nothing to appraise.
  QUIRK ovl21:1E74, 21C7: a character with no items does not get the kept gem (the new item is only
  stored in a local), and a kept gem adds no weight. }
procedure AppraiseGems(var Redraw: Byte);
var
  GemsText: String40;
  JewelryText: String40;
  Key: Char;
  Menu: String40;
  SellMenu: String40;
  Roll: Byte;
  Value: Word;
  Room: Word;
  Last: PMenuLine;
  NewItem: PMenuLine;
  Done: Boolean;
  ExtKey: Byte;
  MustSell: Boolean;
begin
  Redraw := 1;
  if (SelectedCharacter^.Money[GemsKind] = 0) and (SelectedCharacter^.Money[JewelryKind] = 0) then
  begin
    ShowFlashMessage('No Gems or Jewelry');
    Redraw := 0;
    Exit;
  end;
  repeat
    if (SelectedCharacter^.Money[GemsKind] = 0) and (SelectedCharacter^.Money[JewelryKind] = 0) then
      Done := True
    else
    begin
      Done := False;
      Str(SelectedCharacter^.Money[GemsKind], GemsText);
      Str(SelectedCharacter^.Money[JewelryKind], JewelryText);
      case SelectedCharacter^.Money[GemsKind] of
        0: GemsText := '';
        1: GemsText := GemsText + ' Gem';
      else
        GemsText := GemsText + ' Gems';
      end;
      case SelectedCharacter^.Money[JewelryKind] of
        0: JewelryText := '';
        1: JewelryText := JewelryText + ' piece of Jewelry';
      else
        JewelryText := JewelryText + ' pieces of Jewelry';
      end;
      ClearRect(1, 1, $26, $16);
      DrawCharacterName(SelectedCharacter, 1, 1, 0);
      DrawTextAt(1, 7, White, 'You have a fine collection of:');
      DrawTextAt(1, 9, White, GemsText);
      DrawTextAt(1, $0A, White, JewelryText);
      Menu := '';
      if SelectedCharacter^.Money[GemsKind] <> 0 then
        Menu := '  Gems';
      if SelectedCharacter^.Money[JewelryKind] <> 0 then
        Menu := Menu + '  Jewelry';
      Menu := Menu + ' Exit';
      Key := ReadPromptChoice('Appraise : ', Menu, $0D, $0A, White, 1, 0, ExtKey);
      case Key of
        'G':
          if SelectedCharacter^.Money[GemsKind] <> 0 then
          begin
            Dec(SelectedCharacter^.Money[GemsKind]);
            Roll := RollDice(1, 100);
            case Roll of
              1..25: Value := 10;
              26..50: Value := 50;
              51..70: Value := 100;
              71..90: Value := 500;
              91..99: Value := 1000;
              100: Value := 5000;
            end;
            Str(Value, GemsText);
            GemsText := 'The Gem is Valued at ' + GemsText + ' gp.';
            DrawTextAt(1, $0C, White, GemsText);
            if WouldOverload(SelectedCharacter, 1, Room) or (SelectedCharacter^.ItemCountC7 >= MaxItems) then
            begin
              SellMenu := 'Sell';
              MustSell := True;
            end
            else
            begin
              SellMenu := 'Sell Keep';
              MustSell := False;
            end;
            Key := ReadPromptChoice('You can : ', SellMenu, $0D, $0A, White, 1, 0, ExtKey);
            if (Key = 'K') and not MustSell then
            begin
              New(NewItem);
              FillChar(NewItem^, SizeOf(NewItem^), 0);
              NewItem^.Next := nil;
              NewItem^.Readied := False;
              NewItem^.NameNum[3] := GemItemName;
              NewItem^.NameNum[2] := 0;
              NewItem^.NameNum[1] := 0;
              NewItem^.ItemType := GemItemType;
              NewItem^.Value := Value;
              NewItem^.Weight := 1;
              NewItem^.HiddenNames := 0;
              Last := SelectedCharacter^.Items;
              if Last = nil then
                Last := NewItem
              else
              begin
                while Last^.Next <> nil do
                  Last := Last^.Next;
                Last^.Next := NewItem;
              end;
            end
            else
            begin
              Value := Value div GoldPerPlatinum;
              GivePlatinum(Value);
            end;
          end;
        'J':
          if SelectedCharacter^.Money[JewelryKind] <> 0 then
          begin
            Dec(SelectedCharacter^.Money[JewelryKind]);
            Roll := RollDice(1, 100);
            case Roll of
              1..10: Value := Trunc(Random(900)) + 100;
              11..20: Value := Trunc(Random(1000)) + 200;
              21..40: Value := Trunc(Random(1500)) + 300;
              41..50: Value := Trunc(Random(2500)) + 500;
              51..70: Value := Trunc(Random(5000)) + 1000;
              71..90: Value := Trunc(Random(6000)) + 2000;
              91..100: Value := Trunc(Random(10000)) + 2000;
            end;
            Str(Value, JewelryText);
            GemsText := 'The Jewel is Valued at ' + JewelryText + ' gp.';
            DrawTextAt(1, $0C, White, GemsText);
            if WouldOverload(SelectedCharacter, 1, Room) or (SelectedCharacter^.ItemCountC7 >= MaxItems) then
            begin
              SellMenu := 'Sell';
              MustSell := True;
            end
            else
            begin
              SellMenu := 'Sell Keep';
              MustSell := False;
            end;
            Key := ReadPromptChoice('You can : ', SellMenu, $0D, $0A, White, 1, 0, ExtKey);
            if (Key = 'K') and not MustSell then
            begin
              New(NewItem);
              FillChar(NewItem^, SizeOf(NewItem^), 0);
              NewItem^.Next := nil;
              NewItem^.Readied := False;
              NewItem^.NameNum[3] := JewelItemName;
              NewItem^.NameNum[2] := 0;
              NewItem^.NameNum[1] := 0;
              NewItem^.ItemType := GemItemType;
              NewItem^.Value := Value;
              NewItem^.Weight := 1;
              NewItem^.HiddenNames := 0;
              Last := SelectedCharacter^.Items;
              if Last = nil then
                Last := NewItem
              else
              begin
                while Last^.Next <> nil do
                  Last := Last^.Next;
                Last^.Next := NewItem;
              end;
            end
            else
            begin
              Value := Value div GoldPerPlatinum;
              GivePlatinum(Value);
            end;
          end;
        'E', #0: Done := True;
      end;
      RecalcCombatValues(SelectedCharacter);
    end;
  until Done;
end;

begin
end.
