{ Probe for res12:0442 (playbook 30), part 4.
  Question: which byte expression compiles to `mov al,[bp-2]; shr al,1; jae TARGET` (the original
  term C of the plural rule: bit 1 of Mask is clear). Each procedure isolates one form. }
{$F+,S-,R-,I-}
program Res12Probe7;

var
  R: Byte;

procedure F1(I, Mask: Byte);
begin
  if (I = 2) and ((Mask and 2) = 0) then R := 1 else R := 0;
end;

procedure F2(I, Mask: Byte);
begin
  if (I = 2) and (((Mask shr 1) and 1) = 0) then R := 1 else R := 0;
end;

procedure F3(I, Mask: Byte);
begin
  if (I = 2) and (Odd(Mask shr 1) = False) then R := 1 else R := 0;
end;

procedure F4(I, Mask: Byte);
begin
  if (I = 2) and not Odd(Mask shr 1) then R := 1 else R := 0;
end;

procedure F5(I, Mask: Byte);
begin
  if (I = 2) and ((Mask and 2) <> 2) then R := 1 else R := 0;
end;

procedure F6(I, Mask: Byte);
begin
  if (I = 2) and (((Mask div 2) and 1) = 0) then R := 1 else R := 0;
end;

procedure F7(I, Mask: Byte);
var C: Byte;
begin
  C := Mask shr 1;
  if (I = 2) and ((C and 1) = 0) then R := 1 else R := 0;
end;

begin
  F1(0,0); F2(0,0); F3(0,0); F4(0,0); F5(0,0); F6(0,0); F7(0,0);
end.
