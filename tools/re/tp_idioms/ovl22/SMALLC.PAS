{ Probe: how a small constant added to a Byte-valued function result compiles.
  ovl22:2FD0 (CastMonsterHealWounds) adds 2 to RollDice's Byte result and the original has
  `xor ah,ah; inc ax; inc ax`, while ovl22:2E4D (CastMonsterHeal) adds 8 to the same call and
  the original has `xor ah,ah; add ax,8` (ovl22:2EA4). This checks the boundary.
  make tpc SRC=tools/re/tp_idioms/ovl22/SMALLC.PAS DISASM=1 }
{$A-,F+,S-,R-,G-,I-}
program SmallC;

function G: Byte; far;
begin
  G := 4;
end;

procedure P1; far;
var
  W: Word;
begin
  W := G + 1;
end;

procedure P2; far;
var
  W: Word;
begin
  W := G + 2;
end;

procedure P3; far;
var
  W: Word;
begin
  W := G + 3;
end;

procedure P8; far;
var
  W: Word;
begin
  W := G + 8;
end;

begin
  P1;
  P2;
  P3;
  P8;
end.
