{ Probe for ovl16:42ED (playbook 30, batch 17), variant 2. The original increments its coin-kind
  index with `mov al,[bp-3]; inc al; mov [bp-3],al` (the codegen of Succ/Pred on an enumerated type,
  INCPRB.PAS) while indexing with cwde. This mirrors the routine with an enumerated coin kind and
  Ord() at the array subscripts, since array[0..6] cannot be indexed by an enum directly. }
{$A-,O+,F+,S-,R-,G-,I-}
program PayProbe2;
type
  PCharacter = ^TCharacter;
  TCharacter = record
    Pad: array[0..$87] of Byte;
    Money: array[0..6] of Word;   { +$88 }
  end;
  TCoinKind = (CopperCoin, SilverCoin, ElectrumCoin, GoldCoin, PlatinumCoin);
var
  Selected: PCharacter;
  CoinCopperValues: array[0..4] of LongInt;

procedure Pay(Amount: LongInt; Who: PCharacter);
var
  Coins: Word;       { [bp-2] }
  Kind: TCoinKind;   { [bp-3] }
begin
  Amount := Amount * 200;
  Kind := CopperCoin;
  with Who^ do
  begin
    while Amount > 0 do
    begin
      Coins := Amount div CoinCopperValues[Ord(Kind)] + 1;
      if Coins > Money[Ord(Kind)] then
        Coins := Money[Ord(Kind)];
      Dec(Amount, Coins * CoinCopperValues[Ord(Kind)]);
      Dec(Money[Ord(Kind)], Coins);
      Kind := Succ(Kind);
    end;
    if Amount < 0 then
    begin
      Amount := Abs(Amount);
      Kind := PlatinumCoin;
      while Amount > 0 do
      begin
        Coins := Amount div CoinCopperValues[Ord(Kind)];
        Dec(Amount, Coins * CoinCopperValues[Ord(Kind)]);
        Inc(Money[Ord(Kind)], Coins);
        Kind := Pred(Kind);
      end;
    end;
  end;
end;

begin
  Pay(0, Selected);
end.
