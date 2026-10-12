unit OVL21;
{ Money: the party's coins and their weight. The value of money in gold (MoneyValueInGold), setting a
  character's or the pool's money from a gold amount (SetCharacterGold, SetPooledGold), the carried
  weight and its limit (CarryLimit, WouldOverload), and the Take, Pool, Share and Appraise commands the
  shop, the Temple and the treasure menu share (whitepaper 5.4). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
function CarryLimit(Who: PCharacter): Word;
procedure RemoveCarriedWeight(Who: PCharacter; Amount: Word);
procedure AddCarriedWeight(Who: PCharacter; Amount: Word);
function WouldOverload(Who: PCharacter; Amount: Word; var Room: Word): Boolean;
function MoneyValueInGold(Money: TPartyMoney): LongInt;
procedure SetCharacterGold(Amount: Word);
procedure SetPooledGold(Amount: Word);
procedure GivePlatinum(Amount: Word);
procedure ovl21_e6;
procedure ovl21_e7;
procedure ovl21_e2;
procedure ovl21_fn_05E0;
procedure ovl21_e3;
procedure ovl21_fn_07D1;
procedure ovl21_e8;
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
uses RES12;

const
  BaseLoad = 1500;      { the load every character may carry before the strength allowance }
  CopperCoin = 0;       { the money kinds, indexes of TCharacter.Money and TPartyMoney }
  GoldCoin = 3;
  PlatinumCoin = 4;
  GoldPerPlatinum = 5;
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
{ ovl21:0294: retf 8: 8 bytes of parameters; 580 bytes of locals }
{@stub} procedure ovl21_e6; begin end;
{ ovl21:044C: retf 12: 12 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl21_e7; begin end;
{ ovl21:0508: retf 0: 0 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl21_e2; begin end;
{ ovl21:05E0: retf 0: 0 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl21_fn_05E0; begin end;
{ ovl21:063A: frame not read }
{@stub} procedure ovl21_e3; begin end;
{ ovl21:07D1: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl21_fn_07D1; begin end;
{ ovl21:0A01: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl21_e8; begin end;
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
