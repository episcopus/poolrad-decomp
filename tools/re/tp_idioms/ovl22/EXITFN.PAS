{ Probe: which source form of an early `if <boolean> then Exit` gives the original's DIRECT
  conditional jump to the epilogue (`or al,al; jne epilogue`) instead of the two-instruction
  `je skip; jmp epilogue`. ovl22_e21 (ovl22:136E) uses the direct form twice, inside
  `if ds6C94 > 0 then begin ... end`.
  make tpc SRC=tools/re/tp_idioms/ovl22/EXITFN.PAS DISASM=1 }
{$A-,F+,S-,R-,G-,I-}
program ExitFn;
var
  S: Byte;

function R: Boolean; far;
begin
  R := S = 1;
end;

function Q: Boolean; far;
begin
  Q := S = 2;
end;

procedure A; far;
begin
  if R then
    Exit;
  S := 1;
end;

procedure B; far;
begin
  if R then
    Exit;
  if not Q then
    Exit;
  S := 1;
end;

procedure C; far;
begin
  if S > 0 then
  begin
    if R then
      Exit;
    if not Q then
      Exit;
    S := 1;
  end;
end;

begin
  A; B; C;
end.
