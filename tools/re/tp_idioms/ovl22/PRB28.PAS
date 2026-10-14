{ Probe: what a `function F: Boolean; begin F := G; end;` compiles to when G is a far
  Boolean function, versus a procedure with a Boolean local.
  ovl22:232F (ovl22_e42) is `push cs; call 228A; mov [bp-1],al; mov sp,bp; pop bp; retf`,
  a 2-byte local and no final `mov al,[bp-1]`. This checks which source produces it.
  make tpc SRC=tools/re/tp_idioms/ovl22/PRB28.PAS DISASM=1 }
{$A-,F+,S-,R-,G-,I-}
program Prb28;

function G: Boolean; far;
begin
  G := True;
end;

function F1: Boolean; far;
begin
  F1 := G;
end;

procedure P1; far;
var
  B: Boolean;
begin
  B := G;
end;

function F2: Boolean; far;
begin
  F2 := G;
  F2 := F2;
end;

begin
  if F1 then P1;
  if F2 then P1;
end.
