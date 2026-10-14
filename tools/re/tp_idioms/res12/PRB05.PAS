{ Probe for res12:0442 (playbook 30), part 3.
  Question: the codegen of the plural rule's compound OR with LOCAL byte operands (the real
  routine keeps I, Mask, ItemType in locals), so the exact source form can be recovered. }
{$F+,S-,R-,I-}
program Res12Probe5;

var
  ItemType: Byte;

procedure Test(I, Mask: Byte);
begin
  if ((1 shl (I - 1)) = Mask) or
     ((I = 1) and (Mask > 4) and (ItemType <> $56)) or
     ((I = 2) and (not Odd(Mask shr 1))) or
     ((I = 3) and (ItemType = $56)) or
     (((ItemType = $49) or (ItemType = $1C)) and (Mask <> $B1)) then
    Mask := 1
  else
    Mask := 0;
end;

begin
  Test(1, 0);
end.
