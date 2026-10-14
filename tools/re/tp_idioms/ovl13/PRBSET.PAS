(* Probe PRBSET (ovl13, 2026-10-13): the jcc TP 6.0 emits for `not (x in S)` vs `x in S then
  else`. ovl13:05BF is `je` (skip the 'is killed' when the status IS in [6,7,8]); our
  `if not (Status in [6,7,8])` gave `jne`.
  Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBSET.PAS DISASM=1 *)
program PrbSet;
{$A-,F+}
var
  B: Byte;
  R: Byte;

procedure P;
begin if not (B in [6, 7, 8]) then R := 1; end;

procedure Q;
begin if B in [6, 7, 8] then R := 0 else R := 1; end;

procedure S;
begin if not (B in [6, 7, 8]) then R := 1 else R := 0; end;

begin
  P; Q; S;
end.
