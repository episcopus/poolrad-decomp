{ Probe for res12:0442 (playbook 30), part 5.
  Question: term C with Mask a LOCAL var (the real routine's [bp-2]), and a few more forms that
  might compile to `mov al,[bp-2]; shr al,1; jae true`. }
{$F+,S-,R-,I-}
program Res12Probe8;

var
  R: Byte;

procedure F1(I: Byte);
var
  Mask: Byte;
begin
  Mask := 0;
  if (I = 2) and ((Mask and 2) = 0) then R := 1 else R := 0;
end;

procedure F2(I: Byte);
var
  Mask: Byte;
begin
  Mask := 0;
  if ((1 shl (I - 1)) = Mask) or ((I = 2) and ((Mask and 2) = 0)) then R := 1 else R := 0;
end;

procedure F3(I: Byte);
var
  Mask: Byte;
begin
  Mask := 0;
  if ((1 shl (I - 1)) = Mask) or ((I = 2) and (((Mask shr 1) and 1) = 0)) then R := 1 else R := 0;
end;

begin
  F1(0); F2(0); F3(0);
end.
