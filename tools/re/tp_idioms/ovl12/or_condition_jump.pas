{$A-,O+,F+,S-,R-,G-,I-}
program P;
{ Probe for ovl12:2915: `if (A) or (B) then` compiles B as `je end`; the original has `jne body; jmp end`. }
var
  HookAffectId: Byte;
  DamageKind: Byte;
  Chance: Byte;
  Threshold: Byte;
procedure CancelPendingHook(AffectId: Byte); begin end;
function RollDice(Count, Sides: Byte): Byte; begin RollDice := 0 end;
begin
  Threshold := Chance - 5 * (11 - 0);
  if (HookAffectId <> 0) or ((DamageKind and 8) <> 0) then
    if RollDice(1, 100) <= Threshold then
      CancelPendingHook(0);
end.
