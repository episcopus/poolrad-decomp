{ Probe: the operand evaluation order of `res12_fn_26C2(X) + RollDiceCounted(1, 8)`.
  ovl22_e25's original evaluates res12_fn_26C2 first (push its result), then RollDiceCounted,
  then pops and adds. This checks which order matching compiles the sum.
  make tpc SRC=tools/re/tp_idioms/ovl22/PRB25.PAS DISASM=1 }
{$A-,O+,F+,S-,R-,G-,I-}
program Prb25;

type
  String40 = string[40];

var
  ds681B: Byte;

function res12_fn_26C2(Spell: Byte): Byte; far;
begin
  res12_fn_26C2 := 1;
end;

function RollDiceCounted(Count, Sides: Byte): Byte; far;
begin
  RollDiceCounted := 1;
end;

procedure ApplySpellToTargets(Spell, CasterLevel, Flag, Damage, Kind: Byte; Message: String40); far;
begin
end;

procedure A; far;
begin
  ApplySpellToTargets(ds681B, 0, 0, res12_fn_26C2(ds681B) + RollDiceCounted(1, 8), $0C, '');
end;

procedure B; far;
begin
  ApplySpellToTargets(ds681B, 0, 0, RollDiceCounted(1, 8) + res12_fn_26C2(ds681B), $0C, '');
end;

begin
  A;
  B;
end.
