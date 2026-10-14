{ Probe: how TP 6.0 compiles a Byte guard against zero at the start of a routine.
  ovl22_e21 (ovl22:136E) shows `cmp byte [ds6C94],0; jbe epilogue`, which is not what
  ApplySpellToTargets' `if ds6C94 = 0 then Exit` emitted (`jne` skip then `jmp`).
  This tells `= 0` from `<= 0` (and `< 1`).
  make tpc SRC=tools/re/tp_idioms/ovl22/CMPZERO.PAS DISASM=1 }
{$A-,F+,S-,R-,G-,I-}
program CmpZero;

var
  Count: Byte;
  Sink: Byte;

procedure EqZero; far;
begin
  if Count = 0 then
    Exit;
  Sink := 1;
end;

procedure LeZero; far;
begin
  if Count <= 0 then
    Exit;
  Sink := 1;
end;

procedure LtOne; far;
begin
  if Count < 1 then
    Exit;
  Sink := 1;
end;

begin
  EqZero; LeZero; LtOne;
end.
