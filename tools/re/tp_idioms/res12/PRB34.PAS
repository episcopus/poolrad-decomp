{ Probe for res12:0442 (playbook 30).
  Question: the original plural term at 00BA:06A6 is
    cmp byte [I],2 / jne next / mov al,[Mask] / shr al,1 / jae Then
  which is the Odd idiom (re/learnings/ovl13.toml odd-is-shr-carry-not-test) on bit 0,
  not a bit-1 test. Does `((I = 2) and not Odd(Mask))` in the middle of the OR chain
  emit that byte shift and jae to the then-body? }
{$A-,F+,S-,R-,I-}
program Res12Probe34;

var
  ItemType: Byte;
  Name3: Byte;

procedure Plural(I, Mask: Byte);
begin
  if ((1 shl (I - 1)) = Mask) or
     ((I = 1) and (Mask > 4) and (ItemType <> $56)) or
     ((I = 2) and not Odd(Mask)) or
     ((I = 3) and (ItemType = $56)) or
     (((ItemType = $49) or (ItemType = $1C)) and (Name3 <> $B1)) then
    Mask := 1
  else
    Mask := 0;
end;

begin
  Plural(2, 1);
end.
