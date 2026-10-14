{ Probe for ovl16:42ED (playbook 30, batch 17). The routine calls 0AF8:0A5B and 0AF8:0A76 with
  LongInt operands (low/high in ax:dx and cx:bx). This finds which Pascal LongInt operator each
  helper is: multiply, div, mod, and which one negates (Abs / unary minus). Also checks the
  `X := Amount div Coin[I] + 1` shape (the +1 lands after the call). }
{$A-,O+,F+,S-,R-,G-,I-}
program LongOpProbe;
var
  Amount: LongInt;
  Coin: array[0..4] of LongInt;
  X: Word;
  I: Byte;

procedure Mul; begin Amount := Amount * 200; end;          { longint * const }
procedure Div1; begin X := Amount div Coin[I]; end;        { word := longint div longint }
procedure DivP1; begin X := Amount div Coin[I] + 1; end;   { the +1 after the call }
procedure Mod1; begin X := Amount mod Coin[I]; end;
procedure SubMul; begin Amount := Amount - X * Coin[I]; end;
procedure Neg; begin Amount := -Amount; end;
procedure Abs1; begin Amount := Abs(Amount); end;

begin
  Mul; Div1; DivP1; Mod1; SubMul; Neg; Abs1;
end.
