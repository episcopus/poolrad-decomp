{ Probe: the codegen of ovl22_e21's body (ovl22:136E). Reproduces the guard `if ds6C94 > 0`,
  the SavingThrow/CureAffect early exits and the 'has been reduced' message, to see which form
  produces the original's 77-byte body (`jbe` displacement 0x4D). The externals are dummies with
  the real signatures; only their addresses differ from the game.
  make tpc SRC=tools/re/tp_idioms/ovl22/PRB21.PAS DISASM=1 }
{$A-,O+,F+,S-,R-,G-,I-}
program Prb21;

var
  ds6C94: Byte;
  ds6C95: Pointer;

function SavingThrow(Who: Pointer; Kind, Bonus: ShortInt): Boolean; far;
begin
  SavingThrow := False;
end;

function CureAffect(Who: Pointer; AffectId: Byte): Boolean; far;
begin
  CureAffect := False;
end;

procedure res12_fn_16EC(Who: Pointer; Text: string; A, B: Byte); far;
begin
end;

procedure e21; far;
const
  SaveKind = 4;
  StrengthAffect = $0C;
  MessageColour = $A;
  TimedMessage = 1;
begin
  if ds6C94 > 0 then
    if not SavingThrow(ds6C95, SaveKind, 0) then
      if CureAffect(ds6C95, StrengthAffect) then
        res12_fn_16EC(ds6C95, 'has been reduced', MessageColour, TimedMessage);
end;

begin
  e21;
end.
