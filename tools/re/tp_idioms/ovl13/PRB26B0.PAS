(* Probe PRB26B0 (ovl13, 2026-10-14): idioms needed by ovl13:26B0 (the missile animation).
  ovl13:275E is `mov al,[Bearing]; xor ah,ah; cdq; mov cx,4; idiv cx; xchg dx,ax; mov dx,ax` (a
  signed 32-bit mod) while the quotient comes from `shr ax,1; shr ax,1`. Which source gives the mod?
  Candidates: B mod 4, B div 4, (B shr 1) shr 1, with B a Byte. Also the case label order and the
  Odd/branch shape.
  Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRB26B0.PAS DISASM=1 *)
program Prb26B0;
{$A-,F+}
var
  B: Byte;
  P: Byte;
  R: Integer;
  I: Byte;

procedure A1; begin R := B mod 4; end;
procedure A2; begin R := B div 4; end;
procedure A3; begin R := P + B mod 4; end;
procedure A4; begin R := B shr 1 shr 1; end;
procedure A5; begin R := P + (B shr 1 shr 1); end;

procedure B1;
begin
  case I of
    9, $15, $1C, $1F, $49: R := 1;
    2, 7, $14: R := 2;
    $55, $56: R := 3;
  else
    R := 4;
  end;
end;

procedure C1;
begin
  if Odd(B) then
  begin
    if (B = 3) or (B = 5) then
      R := 1
    else
      R := 2;
  end
  else
    R := 3;
end;

begin
  A1; A2; A3; A4; A5; B1; C1;
end.
