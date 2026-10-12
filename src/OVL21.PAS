unit OVL21;
{ Money: the party's coins and their weight. The value of money in gold (MoneyValueInGold), setting a
  character's or the pool's money from a gold amount (SetCharacterGold, SetPooledGold), the carried
  weight and its limit (CarryLimit, WouldOverload), and the Take, Pool, Share and Appraise commands the
  shop, the Temple and the treasure menu share (whitepaper 5.4). }
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
procedure ovl21_fn_0A88;
procedure ovl21_fn_0B48;
procedure ovl21_e5;
procedure ovl21_e4;
procedure ovl21_fn_0F21;
procedure ovl21_e9(var A, B: Byte);
procedure ovl21_fn_0FD2;
procedure ovl21_e13;
procedure ovl21_fn_1758;
procedure ovl21_e14(var Flag: Byte);
procedure ovl21_fn_1F4B;
procedure ovl21_fn_2233;
implementation
uses RES04, RES12;

const
  BaseLoad = 1500;      { the load every character may carry before the strength allowance }
  CopperCoin = 0;       { the money kinds, indexes of TCharacter.Money and TPartyMoney }
  GoldCoin = 3;
  PlatinumCoin = 4;
  GoldPerPlatinum = 5;
  PromptRow = 24;       { the bottom text row, where amounts are typed }
  ScreenCols = 40;
  White = 15;
  KeyBackspace = #8;
  KeyEnter = #13;
  KeyEscape = #27;
  LastMoneyKind = 6;    { seven kinds: copper, silver, electrum, gold, platinum, gems, jewelry }
  { TCharacter.B84 values of the members that pool and share money: 0 and $B3 (a player-run
    member; what $B3 marks is not known) }
  SharerB84 = $B3;
  ComputerRunB84 = $80; { B84 from $80 up: a member run by the computer, who gets no share }
  ViewShop = 1;         { ds49F3 view modes where dropped money goes into the pool: a shop or }
  ViewTreasure = 6;     { the Temple (1), the treasure after a battle (6) }
  HalfGoldInCopper = 100;  { added before dividing by the gold value: rounds to the nearest gold piece }

{ ovl21:0000. The most weight Who may carry: 1500 plus the strength allowance res12_fn_13AB
  (negative for a weak character). }
function CarryLimit(Who: PCharacter): Word;
begin
  CarryLimit := res12_fn_13AB(Who) + BaseLoad;
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
    res12_fn_1693('Overloaded.  Money will be put in Pool.');
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
    res12_fn_1693('Overloaded');
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
{ ovl21:0A88: frame not read }
{@stub} procedure ovl21_fn_0A88; begin end;
{ ovl21:0B48: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl21_fn_0B48; begin end;
{ ovl21:0B93: retf 8: 8 bytes of parameters; 258 bytes of locals }
{@stub} procedure ovl21_e5; begin end;
{ ovl21:0CEB: frame not read }
{@stub} procedure ovl21_e4; begin end;
{ ovl21:0F21: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl21_fn_0F21; begin end;
{ ovl21:0F7E: retf 8; two var parameters; the Temple tests the first for nonzero. }
{@stub} procedure ovl21_e9(var A, B: Byte); begin end;
{ ovl21:0FD2: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl21_fn_0FD2; begin end;
{ ovl21:1010: frame not read }
{@stub} procedure ovl21_e13; begin end;
{ ovl21:1758: frame not read }
{@stub} procedure ovl21_fn_1758; begin end;
{ ovl21:19B2: one var parameter (the Temple passes a local byte it tests afterwards). }
{@stub} procedure ovl21_e14(var Flag: Byte); begin end;
{ ovl21:1F4B: frame not read }
{@stub} procedure ovl21_fn_1F4B; begin end;
{ ovl21:2233: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl21_fn_2233; begin end;

begin
end.
