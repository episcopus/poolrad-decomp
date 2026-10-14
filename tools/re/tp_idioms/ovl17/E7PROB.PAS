{ Probe for ovl17_e7's case-body codegen (playbook 30). The original computes the body bank index
  after `les di, [WhoCache]; mov al, es:[di + 0x9e]; cwde` as `mov di, ax; mov si, di; shl di, 1;
  shl di, 1; add di, si; add di, dx; mov al, [di + base]` (the accumulator is DI). Our draft gives
  `mov si, ax; shl ax, 1; ...` (accumulator AX). Question: which source shape accumulates in DI? }
{$F+,S-,R-,I-}
program E7Prob;

type
  PCharacter = ^TCharacter;
  TCharacter = record
    Pad: array[0..$9D] of Byte;
    B9E: ShortInt;
    Pad2: array[$9F..$10F] of Byte;
  end;
  TMonsterBanks = record
    Suffix01: array[0..1] of Byte;
    Head: array[0..15] of Byte;
    BodyClass0: array[0..9] of Byte;
    BodyOther: array[0..9] of Byte;
    BodyClass5: array[0..9] of Byte;
    BodyClass6: array[0..9] of Byte;
  end;

var
  MonsterBanks: TMonsterBanks;

function RollDice(Count, Sides: Byte): Byte; begin end;

procedure A(Class: Byte; Who: PCharacter; var Bank: Byte);
const
  BodyRow = 5;
begin
  with Who^ do
    case Class of
      0: Bank := MonsterBanks.BodyClass0[B9E * BodyRow + RollDice(1, 5)];
      else Bank := MonsterBanks.BodyOther[B9E * BodyRow + RollDice(1, 5)];
    end;
end;

procedure B(Class: Byte; Who: PCharacter; var Bank: Byte);
begin
  with Who^ do
    case Class of
      0: Bank := MonsterBanks.BodyClass0[B9E * 5 + RollDice(1, 5)];
      else Bank := MonsterBanks.BodyOther[B9E * 5 + RollDice(1, 5)];
    end;
end;

begin
  A(0, nil, MonsterBanks.BodyClass0[0]);
  B(0, nil, MonsterBanks.BodyClass0[0]);
end.
