{ Probe: the codegen of an early `if X = 0 then Exit` versus `if X <> 0 then Exit`
  (ovl22:08C3's is `cmp ds6C94,0; jne skip; jmp epilogue`). }
{$A-,F+,S-,R-,G-,I-}
program ExitIf;

var
  B: Byte;
  S: Byte;

procedure PEq; far;
begin
  if B = 0 then
    Exit;
  S := 1;
end;

procedure PNe; far;
begin
  if B <> 0 then
    Exit;
  S := 1;
end;

begin
  PEq;
  PNe;
end.
