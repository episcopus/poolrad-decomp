{ Probe for res12:0442 (playbook 30), part 2.
  Question: the exact System_StrCopy/StrConcat/StrLCopy argument and destination pattern for
  S := A + B + ' ' and for a string-function call inside a concatenation, so the formatter's
  temps can be reproduced. }
{$F+,S-,R-,I-}
program Res12Probe4;

function F(N: Byte): string;
begin
  F := '';
end;

procedure P;
var
  S, A, B: string[40];
begin
  S := A + B + ' ';
  S := A + F(3) + ' ';
end;

begin
  P;
end.
