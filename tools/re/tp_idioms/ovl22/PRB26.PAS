{ Probe: the codegen of ovl22_e26's Sleep loop body (ovl22:151B). Rebuilds the record field reads
  (HighestLevel +$73, Race +$2E, Status +$10C), the 4d4 pool, the per-target cost case and the drop
  test, to find the 10 bytes the draft is longer than the original's 229-byte body.
  make tpc SRC=tools/re/tp_idioms/ovl22/PRB26.PAS DISASM=1 }
{$A-,O+,F+,S-,R-,G-,I-}
program Prb26;

type
  String40 = string[40];
  PCharacter = ^TCharacter;
  TCharacter = record
    Pad0: array[0..$2D] of Byte;
    Race: ShortInt;                 { +$2E }
    Pad2F: array[$2F..$72] of Byte;
    HighestLevel: ShortInt;         { +$73 }
    Pad74: array[$74..$10B] of Byte;
    Status: Byte;                   { +$10C }
  end;

var
  ds6C91: array[0..71] of PCharacter;
  ds6C94: Byte;
  ds681B: Byte;
  ds6820: Byte;
  ds4844: Byte;
  ds4845: Byte;

function RollDice(Count, Sides: Byte): Byte; far;
begin
  RollDice := 1;
end;

function res12_fn_2199(Who: Pointer; AffectId: Byte; var Affect: Pointer): Boolean; far;
begin
  res12_fn_2199 := False;
end;

procedure ApplySpellToTargets(Spell, CasterLevel, Flag, Damage, Kind: Byte; Message: String40); far;
begin
end;

procedure e26; far;
const
  SleepAffect = $35;
  PoolDiceCount = 4;
  PoolDiceSides = 4;
  DeadStatus = 1;
  CostLevel0 = 1;
  CostLevel2 = 2;
  CostLevel3 = 4;
  CostLevel4 = 6;
  CostLevel5Small = $A;
  CostLevel5Large = $14;
var
  I: Byte;
  Affect: Pointer;
begin
  ds6820 := 1;
  ds4844 := RollDice(PoolDiceCount, PoolDiceSides);
  for I := 1 to ds6C94 do
  begin
    case ds6C91[I]^.HighestLevel of
      0..1: ds4845 := CostLevel0;
      2: ds4845 := CostLevel2;
      3: ds4845 := CostLevel3;
      4: ds4845 := CostLevel4;
      5:
        if ds6C91[I]^.Race = 0 then
          ds4845 := CostLevel5Small
        else
          ds4845 := CostLevel5Large;
    else
      ds4845 := CostLevel5Large;
    end;
    if (ds6C91[I]^.Status <> DeadStatus) and not res12_fn_2199(ds6C91[I], SleepAffect, Affect) and
       (ds4844 >= ds4845) then
      Dec(ds4844, ds4845)
    else
      ds6C91[I] := nil;
  end;
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'falls asleep');
end;

begin
  e26;
end.
