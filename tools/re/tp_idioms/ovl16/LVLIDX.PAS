{ Probe for ovl16:29AE (TrainCharacter). The experience table index is
  `mov al,[level]; inc al; cwde; shl ax,1; shl ax,1` (and two inc al for level+2).
  Level + 1 on a ShortInt is `cwde; inc ax` instead. Succ(Level) as the subscript,
  not assigned back, is the inc-then-sign-extend form. }
{$A-,O+,F+,S-,R-,G-,I-}
program LvlIdx;
var
  Level: ShortInt;
  I: ShortInt;
  Table: array[0..7, 0..13] of LongInt;
  Got: LongInt;

procedure PlusOne; begin Got := Table[I, Level + 1]; end;
procedure SuccOne; begin Got := Table[I, Succ(Level)]; end;
procedure SuccTwo; begin Got := Table[I, Succ(Succ(Level))]; end;

begin
  PlusOne;
  SuccOne;
  SuccTwo;
end.
