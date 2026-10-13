program PRB19MNY;
{$A-,O+,F+,S-,R-,G-,I-}
type
  TMoneyHolder = record
    Money: array[0..4] of Word;
  end;
  PMoneyHolder = ^TMoneyHolder;
var
  Who: PMoneyHolder;
  CoinValues: array[0..4] of LongInt;
  CoinIndex: ShortInt;
  Total: LongInt;
begin
  Total := Total + Who^.Money[CoinIndex] * CoinValues[CoinIndex];
  Total := Total + CoinValues[CoinIndex] * Who^.Money[CoinIndex];
  Inc(Total, CoinValues[CoinIndex] * Who^.Money[CoinIndex]);
end.
