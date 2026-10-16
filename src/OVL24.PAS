unit OVL24;
{ Affects, rolls and damage (whitepaper 5.21): the affect list of a character (AddAffect,
  RemoveAffect, ApplyAffect, CureAffect) and the handler table AffectHandlers the affects act
  through (CallAffectHandler); the hooks every roll runs (RunAffectHooks: for each kind of event a
  list of affect ids whose handlers may change the roll); the dice (RollDice), saving throws
  (SavingThrow), attack and resistance rolls (RollToHit, RollBeatsResistance); damage, going down
  and healing (DealDamage, DropCombatant, HealCharacter, ReviveCombatant); and strength changes kept
  in an affect (EncodeStrength, DecodeStrength, RaiseStrength). }
{$A-,O+,F+,S-,R-,G-,I-,L-}
interface
uses POOLVARS, RES06;
procedure CallAffectHandler(AffectId: Byte; Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure RemoveAffect(Who: PCharacter; AffectId: Byte; Affect: Pointer);
procedure RunAffectHook(Who: PCharacter; AffectId: Byte);
procedure RunAffectHooks(Kind: Byte; Who: PCharacter);
procedure ApplyCloudTile(Who: PCharacter);
function RollBeatsResistance(Who: PCharacter; Level: Byte): Boolean;
function RollToHit(Attacker, Target: PCharacter; Needed: Byte): Boolean;
function SavingThrow(Who: PCharacter; Kind, Bonus: ShortInt): Boolean;
function RollDice(Count, Sides: Byte): Byte;
function RollDiceCounted(Count, Sides: Byte): Byte;
procedure AddAffect(Who: PCharacter; AffectId: Byte; Duration: Word; Data, Flag: Byte);
procedure DropCombatant(Who: PCharacter; NewStatus: Byte; Msg: String40);
procedure ClearAttackerAffect(Who: PCharacter);
procedure RemoveDeathAffects(Who: PCharacter);
procedure RemoveExtraDeathAffects(Who: PCharacter);
function CureAffect(Who: PCharacter; AffectId: Byte): Boolean;
function EncodeStrength(Strength, Percent: Byte): Byte;
procedure DecodeStrength(Affect: PAffect; var Strength, Percent: Byte);
function RaiseStrength(Who: PCharacter; Strength, Percent: Byte; var Code: Byte): Boolean;
procedure DealDamage(Who: PCharacter; Damage, SaveEffect: Byte; Saved: Boolean);
procedure ApplyAffect(Who: PCharacter; AffectId: Byte; Duration: Word; Data, Flag, SaveNegates: Byte;
  Saved: Boolean; Msg: String40);
function HealCharacter(Who: PCharacter; Amount, Flag: Byte): Boolean;
function ReviveCombatant(Who: PCharacter; HitPoints: Byte): Boolean;
implementation
uses RES07, RES12, OVL30, OVL31;

const
  { The kinds of RunAffectHooks the rolls of this unit use. }
  HookDamage = 6;               { DealDamage, on DamageAmount }
  HookApplyAffect = 9;          { ApplyAffect, on HookAffectId }
  HookAttacker = $A;            { RollToHit, on the attacker }
  HookSave = $C;                { SavingThrow, on SaveRoll }
  HookTarget = $10;             { RollToHit and RollBeatsResistance, on the target }
  NaturalOne = 1;               { a d20 of 1 always fails }
  NaturalTwenty = 20;           { a d20 of 20 always succeeds }
  TwentyCounts = 100;           { what a 20 counts in the attack and resistance rolls }
  VarSideBonusParty = 881;      { a game word added to the party's attack rolls (low byte, signed) }
  VarSideBonusMonsters = 880;   { the same for the other side }
  { Strength as one byte (EncodeStrength): 18 with a percentile is 1..101, other values 100 up. }
  StrengthOffset = 100;
  DeathAffectCount = 16;        { entries of DeathAffects }

{ ovl24:0000 (e1). Calls the handler of an affect: AffectHandlers[AffectId](Who, Affect, Mode),
  Mode 0 to apply or check it, 1 when it is removed. }
procedure CallAffectHandler(AffectId: Byte; Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  AffectHandlers[AffectId](Who, Affect, Mode);
end;

{ ovl24:0026 (e2). Removes an affect from Who's list: the given one, or when Affect is nil the
  first with AffectId. An affect whose Flag is set has its handler called with mode 1 first; the
  9 bytes are freed. Nothing happens when the character has no such affect. }
procedure RemoveAffect(Who: PCharacter; AffectId: Byte; Affect: Pointer);
var
  Prev: PAffect;
  Cur: PAffect;
begin
  Cur := Affect;
  if Cur = nil then
  begin
    Cur := Who^.Affects;
    while (Cur <> nil) and (Cur^.Id <> AffectId) do
      Cur := Cur^.Next;
  end;
  if Cur <> nil then
  begin
    if Cur^.Flag <> 0 then
      CallAffectHandler(AffectId, Who, Cur, ModeRemove);
    if Who^.Affects = Cur then
      Who^.Affects := Cur^.Next
    else
    begin
      Prev := Who^.Affects;
      while (Prev <> nil) and (Prev^.Next <> Cur) do
        Prev := Prev^.Next;
      Prev^.Next := Cur^.Next;
    end;
    FreeMem(Cur, AffectRecordSize);
  end;
end;

{ ovl24:0160. Runs one affect's hook: when Who has the affect its handler is called (mode 0). For
  the four affects $15, $2D, $2E and $31 that act around their bearer it is enough that another
  member of the party list has it and, in combat, reaches Who (ScanTargets from the bearer, 6
  squares for $31, 1 for the others); the ovl30 sort table SortEntries is saved and restored around the
  scan. }
procedure RunAffectHook(Who: PCharacter; AffectId: Byte);
var
  Saved: array[1..72] of TSortRec;
  Other: PCharacter;
  Affect: Pointer;
  Found: Boolean;
  I: Byte;
  Range: Byte;
begin
  Found := False;
  Other := PCharacter(PartyListHead);
  if HasAffect(Who, AffectId, Affect) then
    Found := True
  else if AffectId in [$15, $2D, $2E, $31] then
  begin
    Move(SortEntries[1], Saved, SizeOf(Saved));
    while (Other <> nil) and not Found do
    begin
      if HasAffect(Other, AffectId, Affect) then
      begin
        if ViewMode = ViewModeCombat then
        begin
          if AffectId = $31 then
            Range := 6
          else
            Range := 1;
          ScanTargets(CombatantX(Other), CombatantY(Other), Range, $FF, CombatantKind(Other), CombatMap);
          for I := 1 to SortEntries[0].Val do
            if SortEntries[I].Head = CombatantIndex(Who) then
              Found := True;
        end
        else
          Found := True;
      end;
      Other := Other^.Next;
    end;
    Move(Saved, SortEntries[1], SizeOf(Saved));
  end;
  if Found then
    CallAffectHandler(AffectId, Who, Affect, ModeApply);
end;

{ ovl24:02FA (e3). Runs the hooks of one kind of event for Who: each kind (0..$13) has a fixed list
  of affect ids whose handlers (RunAffectHook) may change the roll in progress (AttackRoll,
  SaveRoll, DamageAmount, HookAffectId). This unit uses kinds 6, 9, $A, $C, $D and $10; other
  units call it with 7, $F and $13. QUIRK ovl24:02FD: 4 bytes of frame nothing uses. }
procedure RunAffectHooks(Kind: Byte; Who: PCharacter);
var
  Unused: Pointer;              { QUIRK ovl24:02FD: the frame has 4 bytes nothing uses }
begin
  case Kind of
    0: RunAffectHook(Who, $7E);
    1:
      begin
        RunAffectHook(Who, $3F);
        RunAffectHook(Who, $25);
        RunAffectHook(Who, $19);
        RunAffectHook(Who, $47);
      end;
    2:
      begin
        RunAffectHook(Who, $55);
        RunAffectHook(Who, $56);
        RunAffectHook(Who, $57);
        RunAffectHook(Who, $44);
        RunAffectHook(Who, $4F);
        RunAffectHook(Who, $50);
        RunAffectHook(Who, $4C);
        RunAffectHook(Who, $49);
        RunAffectHook(Who, $4D);
      end;
    3:
      begin
        RunAffectHook(Who, $40);
        RunAffectHook(Who, $41);
        RunAffectHook(Who, $42);
        RunAffectHook(Who, $43);
        RunAffectHook(Who, $44);
        RunAffectHook(Who, $45);
        RunAffectHook(Who, $46);
        RunAffectHook(Who, $4F);
        RunAffectHook(Who, $55);
        RunAffectHook(Who, $56);
        RunAffectHook(Who, $57);
      end;
    4:
      begin
        RunAffectHook(Who, $1D);
        RunAffectHook(Who, $03);
        RunAffectHook(Who, $06);
      end;
    5:
      begin
        RunAffectHook(Who, $1C);
        RunAffectHook(Who, $29);
        RunAffectHook(Who, $68);
        RunAffectHook(Who, $78);
        RunAffectHook(Who, $65);
        RunAffectHook(Who, $73);
        RunAffectHook(Who, $74);
        RunAffectHook(Who, $77);
        RunAffectHook(Who, $7B);
        RunAffectHook(Who, $60);
        RunAffectHook(Who, $5E);
        RunAffectHook(Who, $3C);
        RunAffectHook(Who, $7A);
        RunAffectHook(Who, $75);
      end;
    6:
      begin
        RunAffectHook(Who, $71);
        RunAffectHook(Who, $3D);
        RunAffectHook(Who, $7A);
        RunAffectHook(Who, $3C);
        RunAffectHook(Who, $5B);
        RunAffectHook(Who, $0A);
        RunAffectHook(Who, $14);
        RunAffectHook(Who, $69);
        RunAffectHook(Who, $6A);
        RunAffectHook(Who, $70);
        RunAffectHook(Who, $72);
        RunAffectHook(Who, $76);
        RunAffectHook(Who, $11);
        RunAffectHook(Who, $5D);
        RunAffectHook(Who, $65);
        RunAffectHook(Who, $1C);
      end;
    7:
      begin
        RunAffectHook(Who, $33);
        RunAffectHook(Who, $34);
        RunAffectHook(Who, $35);
        RunAffectHook(Who, $1F);
      end;
    8:
      begin
        RunAffectHook(Who, $63);
        RunAffectHook(Who, $51);
        RunAffectHook(Who, $52);
        RunAffectHook(Who, $59);
        RunAffectHook(Who, $48);
        RunAffectHook(Who, $38);
      end;
    9:
      begin
        RunAffectHook(Who, $69);
        RunAffectHook(Who, $6A);
        RunAffectHook(Who, $6B);
        RunAffectHook(Who, $6C);
        RunAffectHook(Who, $6D);
        RunAffectHook(Who, $6E);
        RunAffectHook(Who, $6F);
        RunAffectHook(Who, $70);
        RunAffectHook(Who, $7C);
        RunAffectHook(Who, $7D);
      end;
    $A:
      begin
        RunAffectHook(Who, $01);
        RunAffectHook(Who, $02);
        RunAffectHook(Who, $21);
        RunAffectHook(Who, $24);
        RunAffectHook(Who, $31);
        RunAffectHook(Who, $03);
        RunAffectHook(Who, $06);
        RunAffectHook(Who, $12);
        RunAffectHook(Who, $1A);
      end;
    $B:
      begin
        RunAffectHook(Who, $21);
        RunAffectHook(Who, $11);
        RunAffectHook(Who, $08);
        RunAffectHook(Who, $09);
        RunAffectHook(Who, $2D);
        RunAffectHook(Who, $2E);
        RunAffectHook(Who, $1E);
      end;
    $C:
      begin
        RunAffectHook(Who, $08);
        RunAffectHook(Who, $09);
        RunAffectHook(Who, $0A);
        RunAffectHook(Who, $11);
        RunAffectHook(Who, $14);
        RunAffectHook(Who, $21);
        RunAffectHook(Who, $24);
        RunAffectHook(Who, $2D);
        RunAffectHook(Who, $2E);
        RunAffectHook(Who, $31);
        RunAffectHook(Who, $3D);
        RunAffectHook(Who, $6F);
        RunAffectHook(Who, $7D);
        RunAffectHook(Who, $5A);
        RunAffectHook(Who, $61);
      end;
    $D:
      begin
        RunAffectHook(Who, $63);
        RunAffectHook(Who, $64);
        RunAffectHook(Who, $67);
        RunAffectHook(Who, $4B);
        RunAffectHook(Who, $4A);
      end;
    $E:
      begin
        RunAffectHook(Who, $53);
        RunAffectHook(Who, $54);
        RunAffectHook(Who, $58);
        RunAffectHook(Who, $79);
      end;
    $F:
      begin
        RunAffectHook(Who, $15);
        RunAffectHook(Who, $1E);
        RunAffectHook(Who, $4A);
        RunAffectHook(Who, $4B);
        RunAffectHook(Who, $0B);
      end;
    $10:
      begin
        RunAffectHook(Who, $19);
        RunAffectHook(Who, $47);
        RunAffectHook(Who, $25);
        RunAffectHook(Who, $2F);
        RunAffectHook(Who, $30);
        RunAffectHook(Who, $59);
      end;
    $11:
      begin
        RunAffectHook(Who, $01);
        RunAffectHook(Who, $02);
        RunAffectHook(Who, $0B);
      end;
    $12:
      begin
        RunAffectHook(Who, $27);
        RunAffectHook(Who, $2A);
        RunAffectHook(Who, $3A);
      end;
    $13:
      begin
        RunAffectHook(Who, $62);
        RunAffectHook(Who, $17);
        RunAffectHook(Who, $48);
        RunAffectHook(Who, $38);
        RunAffectHook(Who, $0B);
      end;
  end;
end;

{ ovl24:0AE7 (e4). A standing combatant (Flag10D) on the cloud tile ($1E under it, ProbeStep) that
  has none of the affects $1E, $1F, $20, $6F, $7D makes a saving throw (kind 0): saved, it gets
  affect $1E for one round ('starts to cough'); failed, affect $1F for 1d4 + 1 ('chokes and gags
  from nausea'); the new affect's handler is called. A stinking cloud by its texts [I]. }
procedure ApplyCloudTile(Who: PCharacter);
var
  Tile: Byte;
  Occupant: Byte;
  Affect: Pointer;
  Saved: Boolean;
begin
  if Who^.Flag10D <> 0 then
  begin
    ProbeStep(Who, 8, Occupant, Tile);
    if Tile = CloudTile then
      if not HasAffect(Who, $1E, Affect) then
        if not HasAffect(Who, $1F, Affect) then
          if not HasAffect(Who, $20, Affect) then
            if not HasAffect(Who, $6F, Affect) then
              if not HasAffect(Who, $7D, Affect) then
              begin
                Saved := SavingThrow(Who, 0, 0);
                if Saved then
                begin
                  ApplyAffect(Who, AffectCough, 1, $FF, 0, 0, Saved, 'starts to cough');
                  CallAffectHandler(AffectCough, Who, Affect, ModeApply);
                end
                else
                begin
                  ApplyAffect(Who, AffectHelpless, RollDice(1, 4) + 1, $FF, 0, 0, Saved, 'chokes and gags from nausea');
                  CallAffectHandler(AffectHelpless, Who, Affect, ModeApply);
                end;
              end;
  end;
end;

{ ovl24:0C4F (e5). A resistance roll against Who: AttackRoll is a d20 (a 1 fails, a 20 counts
  100), the target hooks ($10) may change it; True when it is not negative and AttackRoll plus
  Level exceeds Who's ArmourClassValue (+$111). }
function RollBeatsResistance(Who: PCharacter; Level: Byte): Boolean;
begin
  RollBeatsResistance := False;
  AttackRoll := RollDice(1, 20);
  if AttackRoll > NaturalOne then
  begin
    if AttackRoll = NaturalTwenty then
      AttackRoll := TwentyCounts;
    RunAffectHooks(HookTarget, Who);
    if AttackRoll >= 0 then
      if AttackRoll + Level > Who^.ArmourClassValue then
        RollBeatsResistance := True;
  end;
end;

{ ovl24:0CB7 (e6). An attack roll: the attacker loses affect $19 (ClearAttackerAffect), AttackRoll
  is a d20 (1 misses, 20 counts 100) changed by the attacker's ($A) and the target's ($10) hooks;
  True when it is not negative and AttackRoll + the attacker's HitAdjust (+$110) + the game word
  of its side (881 for the party, 880 for the others, low byte signed) reaches Needed. }
function RollToHit(Attacker, Target: PCharacter; Needed: Byte): Boolean;
var
  SideBonus: ShortInt;
begin
  RollToHit := False;
  ClearAttackerAffect(Attacker);
  AttackRoll := RollDice(1, 20);
  if AttackRoll > NaturalOne then
  begin
    if AttackRoll = NaturalTwenty then
      AttackRoll := TwentyCounts;
    RunAffectHooks(HookAttacker, Attacker);
    RunAffectHooks(HookTarget, Target);
    if Attacker^.Side = SideParty then
      SideBonus := GameVars2^[VarSideBonusParty]
    else
      SideBonus := GameVars2^[VarSideBonusMonsters];
    if AttackRoll >= 0 then
      if AttackRoll + Attacker^.HitAdjust + SideBonus >= Needed then
        RollToHit := True;
  end;
end;

{ ovl24:0D63 (e7). A saving throw of Who of the given kind (an index of SavingThrows, 0..4):
  SaveRoll is a d20; a 1 fails and a 20 succeeds, otherwise SaveRoll + SaveBonus (+$101) + Bonus,
  changed by the save hooks ($C, with SaveKind), succeeds when it reaches SavingThrows[Kind]. }
function SavingThrow(Who: PCharacter; Kind, Bonus: ShortInt): Boolean;
begin
  SaveRoll := RollDice(1, 20);
  case SaveRoll of
    NaturalOne: SavingThrow := False;
    NaturalTwenty: SavingThrow := True;
  else
    SaveRoll := SaveRoll + Who^.SaveBonus + Bonus;
    SaveKind := Kind;
    RunAffectHooks(HookSave, Who);
    if Who^.SavingThrows[Kind] <= SaveRoll then
      SavingThrow := True
    else
      SavingThrow := False;
  end;
end;

{ ovl24:0DE3 (e8). Rolls Count dice of Sides faces (Random(Sides) + 1 each) and returns the sum,
  0 for no dice. The game's dice: ovl04 rolls 1d8, 2d8 and 3d8 for the cure spells. QUIRK: the
  sum is a Byte and wraps above 255. }
function RollDice(Count, Sides: Byte): Byte;
var
  I: Byte;
  Total: Byte;
begin
  Total := 0;
  if Count > 0 then
    for I := 1 to Count do
      Inc(Total, Random(Sides) + 1);
  RollDice := Total;
end;

{ ovl24:0E2E (e9). RollDice(Count, Sides), keeping Count in LastDiceCount (who reads it is not known
  yet). }
function RollDiceCounted(Count, Sides: Byte): Byte;
begin
  LastDiceCount := Count;
  RollDiceCounted := RollDice(Count, Sides);
end;

{ ovl24:0E52 (e10). Appends a new affect (9 bytes) at the end of Who's affect list with the
  given id, duration, data and flag. }
procedure AddAffect(Who: PCharacter; AffectId: Byte; Duration: Word; Data, Flag: Byte);
var
  Added: PAffect;
  Last: PAffect;
begin
  New(Added);
  if Who^.Affects = nil then
    Who^.Affects := Added
  else
  begin
    Last := Who^.Affects;
    while Last^.Next <> nil do
      Last := Last^.Next;
    Last^.Next := Added;
  end;
  Added^.Next := nil;
  Added^.Id := AffectId;
  Added^.Duration := Duration;
  Added^.Flag := Flag;
  Added^.Data := Data;
end;

{ ovl24:0F06 (e11). Takes a standing combatant out of the fight: shows Msg on it, clears Flag10D,
  sets its Status (and its hit points to 0 unless it fled), redraws its ground, clears its entry
  of CombatantTable and the occupancy; when EndCombatTurn says so its death affects are removed
  (RemoveDeathAffects). }
procedure DropCombatant(Who: PCharacter; NewStatus: Byte; Msg: String40);
var
  Index: Byte;
begin
  if Who^.Flag10D <> 0 then
  begin
    Index := CombatantIndex(Who);
    ShowCursorOn(Who, 3, 0);
    ShowCharacterMessage(Who, Msg, $A, True);
    Who^.Flag10D := 0;
    Who^.Status := NewStatus;
    if Who^.Status <> StatusFled then
      Who^.HpCurrent := 0;
    RedrawGround(0, 0, Index);
    FlushPictureChanges;
    CombatantTable[Index].Kind := 0;
    RebuildOccupancy;
    if EndCombatTurn(Who) <> 0 then
      RemoveDeathAffects(Who);
  end;
end;

{ ovl24:0FD2 (e12). Removes every affect $19 from Who; RollToHit calls it for the attacker
  before rolling, so attacking ends the affect (an invisibility by that rule [I]). }
procedure ClearAttackerAffect(Who: PCharacter);
var
  Affect: Pointer;
begin
  while HasAffect(Who, AffectInvisibility, Affect) do
    RemoveAffect(Who, AffectInvisibility, Affect);
end;

{ ovl24:100A (e13). Removes the sixteen affects of DeathAffects from Who: what a combatant loses
  when it goes down (DropCombatant, DealDamage). }
procedure RemoveDeathAffects(Who: PCharacter);
var
  I: Byte;
begin
  for I := 1 to DeathAffectCount do
    RemoveAffect(Who, DeathAffects[I], nil);
end;

{ ovl24:1041 (e14). removes the two affects of ExtraDeathAffects ($4A and $4B, the last two
  of DeathAffects too) from Who; an entry of the overlay, its callers are not decompiled yet. }
procedure RemoveExtraDeathAffects(Who: PCharacter);
var
  I: Byte;
begin
  for I := 1 to 2 do
    RemoveAffect(Who, ExtraDeathAffects[I], nil);
end;

{ ovl24:1081 (e15). When Who has the affect: shows 'is Cured', removes it and returns True;
  False otherwise. }
function CureAffect(Who: PCharacter; AffectId: Byte): Boolean;
var
  Affect: Pointer;
begin
  CureAffect := False;
  if HasAffect(Who, AffectId, Affect) then
  begin
    ShowCharacterMessage(Who, 'is Cured', $A, True);
    RemoveAffect(Who, AffectId, Affect);
    CureAffect := True;
  end;
end;

{ ovl24:10E4 (e16). Strength and exceptional strength in one byte: Strength + 100, or for 18 the
  percentile + 1 (1..101). }
function EncodeStrength(Strength, Percent: Byte): Byte;
begin
  EncodeStrength := Strength + StrengthOffset;
  if Strength = ExceptionalStrength then
    EncodeStrength := Percent + 1;
end;

{ ovl24:110D (e17). The inverse of EncodeStrength on an affect's Data (bit 7 masked): up to 101
  is 18 with Data - 1 percent, above is Data - 100 with no percent. }
procedure DecodeStrength(Affect: PAffect; var Strength, Percent: Byte);
begin
  Percent := 0;
  Strength := Affect^.Data and not StrengthKept;
  if Strength <= StrengthOffset + 1 then
  begin
    Percent := Strength - 1;
    Strength := ExceptionalStrength;
  end
  else
    Strength := Strength - StrengthOffset;
end;

{ ovl24:115C (e18). Sets Who's strength to Strength / Percent unless that is lower than the
  current one (then False and Code is the new value encoded plus $80). Otherwise the first
  strength affect ($C or $26) not yet holding an earlier strength gets the current one encoded
  plus $80, Strength and StrengthPercent change (RecalcCombatValues recomputes), Code is the earlier
  strength encoded, and the result is True. }
function RaiseStrength(Who: PCharacter; Strength, Percent: Byte; var Code: Byte): Boolean;
var
  Cur: PAffect;
  Found: PAffect;
  OldStrength: Byte;
  OldPercent: Byte;
  OldCode: Byte;
begin
  OldStrength := Who^.Strength;
  OldPercent := Who^.StrengthPercent;
  if (Strength < OldStrength) or ((Strength = ExceptionalStrength) and (Percent < OldPercent)) then
  begin
    RaiseStrength := False;
    Code := EncodeStrength(Strength, Percent) + StrengthKept;
  end
  else
  begin
    Found := nil;
    Cur := Who^.Affects;
    while (Cur <> nil) and (Found = nil) do
    begin
      if ((Cur^.Id = AffectEnlarge) or (Cur^.Id = AffectStrength)) and (Cur^.Data < StrengthKept) then
        Found := Cur;
      Cur := Cur^.Next;
    end;
    if Found <> nil then
    begin
      OldCode := EncodeStrength(OldStrength, OldPercent);
      DecodeStrength(Found, OldStrength, OldPercent);
      Found^.Data := OldCode + StrengthKept;
    end;
    Who^.Strength := Strength;
    Who^.StrengthPercent := Percent;
    RecalcCombatValues(Who);
    Code := EncodeStrength(OldStrength, OldPercent);
    RaiseStrength := True;
  end;
end;

{ ovl24:1344 (e19). Deals damage to Who: the damage hooks (6) may change DamageAmount; a save
  (Saved) makes it none (SaveEffect 1) or half (2). Shows 'takes <n> points of damage' (or 1
  point) with 'from Fire', 'from Cold', 'from Electricity', 'from Acid' or 'from Magic' by
  DamageKind, deals it (ApplyDamage); in combat the combatant cannot cast any more and a pending
  spell is lost ('lost a spell'). A combatant that went down shows 'Goes Down', ', and is Dying'
  or 'is killed' (status 6..8); in combat it loses its death affects, the hooks $D run and it
  leaves the map (RemoveCombatant) unless they stood it up again. }
procedure DealDamage(Who: PCharacter; Damage, SaveEffect: Byte; Saved: Boolean);
var
  Msg: string;
begin
  DamageAmount := Damage;
  RunAffectHooks(HookDamage, Who);
  if Saved then
    case SaveEffect of
      1: DamageAmount := 0;
      2: DamageAmount := DamageAmount div 2;
    end;
  if DamageAmount > 0 then
  begin
    if DamageAmount <> 1 then
      Msg := 'takes ' + ByteToText(DamageAmount) + ' points of damage '
    else
      Msg := 'takes 1 point of damage ';
    case DamageKind and $F7 of
      1: Msg := Msg + 'from Fire';
      2: Msg := Msg + 'from Cold';
      4: Msg := Msg + 'from Electricity';
      $10: Msg := Msg + 'from Acid';
    end;
    if DamageKind and 8 = DamageKind then
      Msg := Msg + 'from Magic';
    ShowHitMessage(Who, 0, Msg);
    ApplyDamage(Who, DamageAmount);
    if ViewMode = ViewModeCombat then
    begin
      Who^.Combat^.CanCast := 0;
      if Who^.Combat^.PendingSpell > 0 then
      begin
        ShowCharacterMessage(Who, 'lost a spell', $C, True);
        ForgetSpell(Who^.Combat^.PendingSpell);
        Who^.Combat^.PendingSpell := 0;
      end;
    end;
    if Who^.Flag10D = 0 then
    begin
      Msg := 'Goes Down';
      if Who^.Status = StatusDying then
        Msg := Msg + ', and is Dying';
      if Who^.Status in [6, 7, 8] then
        Msg := 'is killed';
      ShowCharacterMessage(Who, Msg, GlyphRow + 1, False);
      if ViewMode <> ViewModeCombat then
        DelayByGameSpeed
      else
      begin
        RemoveDeathAffects(Who);
        RunAffectHooks(HookGoesDown, Who);
        if Who^.Flag10D = 0 then
          RemoveCombatant(Who)
        else
          DelayByGameSpeed;
      end;
    end;
    ClearCharacterMessage;
  end;
end;

{ ovl24:1656 (e20). Gives Who an affect: the hooks of kind 9 may refuse it (HookAffectId
  cleared), as does a save when SaveNegates is 1; then 'is Unaffected'. Otherwise an affect of the
  same id with a shorter limited duration (or any, for a permanent new one) is removed, the new
  one is added (AddAffect) and Msg, when not empty, is shown. QUIRK ovl24:1659: one frame byte
  nothing uses. }
procedure ApplyAffect(Who: PCharacter; AffectId: Byte; Duration: Word; Data, Flag, SaveNegates: Byte;
  Saved: Boolean; Msg: String40);
var
  Existing: Pointer;
  Unused: Byte;                 { QUIRK ovl24:1659: a frame byte nothing uses }
begin
  HookAffectId := AffectId;
  RunAffectHooks(HookApplyAffect, Who);
  if (HookAffectId = 0) or (Saved and (SaveNegates = 1)) then
    ShowCharacterMessage(Who, 'is Unaffected', $A, True)
  else
  begin
    if HasAffect(Who, AffectId, Existing) then
      if ((PAffect(Existing)^.Duration > 0) and (Duration > PAffect(Existing)^.Duration)) or (Duration = 0) then
        RemoveAffect(Who, AffectId, Existing);
    AddAffect(Who, AffectId, Duration, Data, Flag);
    if Msg <> '' then
    begin
      ShowHitMessage(Who, 1, Msg);
      ClearCharacterMessage;
    end;
  end;
end;

{ ovl24:175D (e21). Heals Who by Amount hit points (HpCurrent, capped at HpMax) when its status is
  0, 1, 4 or 5 and either it is wounded and Flag is set, or Flag is 0 and it has no affect $32. A
  fallen character that is dying becomes unconscious; an unconscious one outside combat has the
  handler of affect $4E called (mode 1). Returns True when it healed. ovl04's cure spells call it
  with Flag 0. }
function HealCharacter(Who: PCharacter; Amount, Flag: Byte): Boolean;
var
  Affect: Pointer;
begin
  HealCharacter := False;
  if Who^.Status in [0, 1, 4, 5] then
    if ((Who^.HpCurrent < Who^.HpMax) and (Flag <> 0)) or
      (not HasAffect(Who, AffectMummyDisease, Affect) and (Flag = 0)) then
    begin
      Who^.HpCurrent := Who^.HpCurrent + Amount;
      if Who^.HpCurrent > Who^.HpMax then
        Who^.HpCurrent := Who^.HpMax;
      if Who^.Flag10D = 0 then
      begin
        if Who^.Status = StatusDying then
          Who^.Status := StatusUnconscious;
        if (Who^.Status = StatusUnconscious) and (ViewMode <> ViewModeCombat) then
          CallAffectHandler(AffectRevival, Who, nil, ModeRemove);
      end;
      HealCharacter := True;
    end;
end;

{ ovl24:1869 (e22). Puts a fallen combatant back on its square (PlaceCombatant): status okay,
  Flag10D set, HitPoints hit points, the cursor on it in combat, and 'stands up and grins' (a
  monster) or 'gets back up'. False when it cannot be placed. }
function ReviveCombatant(Who: PCharacter; HitPoints: Byte): Boolean;
var
  Msg: string[40];
begin
  if PlaceCombatant(Who, CombatantX(Who), CombatantY(Who), 1) then
  begin
    Who^.Status := StatusOkay;
    Who^.Flag10D := 1;
    Who^.HpCurrent := HitPoints;
    if ViewMode = ViewModeCombat then
      ShowCursorOn(Who, 3, 0);
    if Who^.Side = SideMonsters then
      Msg := 'stands up and grins'
    else
      Msg := 'gets back up';
    ShowCharacterMessage(Who, Msg, $A, True);
    RecountCombatSides;
    ReviveCombatant := True;
  end
  else
    ReviveCombatant := False;
end;

{ ovl24:1932. The unit's initialisation part is empty (push bp; mov bp, sp; pop bp; retf). }
begin
end.
