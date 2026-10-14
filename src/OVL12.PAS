unit OVL12;
{ TrainRewards: overlay 12, the training and rewards unit, 14510 bytes of code. The loader (ovl11) hands
  over to its entry 1 (the loader section of the whitepaper). Its affect handlers and roll hooks change
  AttackRoll, DamageAmount and the morale scratch ds6825; each routine's comment says what it does. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS, RES06;
procedure CancelPendingHook(AffectId: Byte);
function TryAddAffect(Who: PCharacter; AffectId, Data: Byte; Duration: Word): Boolean;
procedure DropFromFight(Who: PCharacter; NewStatus: Byte; Msg: String40);
procedure RaiseAttackAndMorale(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure LowerAttackAndMorale(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure BoostAttackAgainstTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure StartTrainingWithManual(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure BoostFireAttackByTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure TrainConstitution(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ShiftAttackToSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ovl12_e9(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure HalveColdDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ComputerTakesOver(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ExchangeStrengthWithAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure SetCharismaFromAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure AddAffectAndDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure IgnoreAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure RaiseResistanceAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure BoostAttackVsListedTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ovl12_e18;
procedure ovl12_e19;
procedure ovl12_e20;
procedure ovl12_e21;
procedure ovl12_e22;
procedure ovl12_e23;
procedure ovl12_e24;
procedure ovl12_e25;
procedure ovl12_e26;
procedure ovl12_fn_0AE5;
procedure ovl12_e27;
procedure ovl12_fn_0B25;
procedure ovl12_fn_0B2A;
procedure ovl12_fn_0B2F;
procedure ovl12_fn_0B43;
procedure ovl12_fn_0B48;
procedure ovl12_fn_0B4D;
procedure ovl12_fn_0B52;
procedure ovl12_fn_0B57;
procedure ovl12_fn_0B61;
procedure ovl12_fn_0B70;
procedure ovl12_fn_0B75;
procedure ovl12_fn_0B7A;
procedure ovl12_fn_0B7F;
procedure ovl12_fn_0B84;
procedure ovl12_fn_0B89;
procedure ovl12_fn_0B8E;
procedure ovl12_e28;
procedure ovl12_e29;
procedure ovl12_e30;
procedure ovl12_e31;
procedure ovl12_e32;
procedure ovl12_e33;
procedure ovl12_e34;
procedure ovl12_fn_0FAC;
procedure ovl12_fn_101D;
procedure ovl12_e35;
procedure ovl12_e36;
procedure ovl12_e37;
procedure ovl12_e38;
procedure ovl12_e39;
procedure ovl12_e40;
procedure ovl12_e41;
procedure ovl12_e42;
procedure ovl12_fn_1307;
procedure ovl12_e43;
procedure ovl12_e44;
procedure ovl12_e45;
procedure ovl12_e46;
procedure ovl12_e47;
procedure ovl12_e48;
procedure ovl12_e49;
procedure ovl12_e50;
procedure ovl12_e51;
procedure ovl12_fn_1543;
procedure ovl12_fn_1545;
procedure ovl12_fn_1583;
procedure ovl12_fn_15EB;
procedure ovl12_e52;
procedure ovl12_e53;
procedure ovl12_e54;
procedure ovl12_e55;
procedure ovl12_e56;
procedure ovl12_e57;
procedure ovl12_e58;
procedure ovl12_e59;
procedure ovl12_e60;
procedure ovl12_fn_1758;
procedure ovl12_e61;
procedure ovl12_e62;
procedure ovl12_e63;
procedure ovl12_e64;
procedure ovl12_e65;
procedure ovl12_e66;
procedure ovl12_e67;
procedure ovl12_e68;
procedure ovl12_fn_1BD7;
procedure ovl12_fn_1C98;
procedure ovl12_e69;
procedure ovl12_e70;
procedure ovl12_fn_1F9B;
procedure ovl12_fn_2002;
procedure ovl12_fn_20A9;
procedure ovl12_fn_2122;
procedure ovl12_fn_2197;
procedure ovl12_fn_2233;
procedure ovl12_fn_228C;
procedure ovl12_fn_2383;
procedure ovl12_e71;
procedure ovl12_e72;
procedure ovl12_e73;
procedure ovl12_e74;
procedure ovl12_e75;
procedure ovl12_e76;
procedure ovl12_fn_257E;
procedure ovl12_e77;
procedure ovl12_e78;
procedure ovl12_fn_25C9;
procedure ovl12_e79;
procedure ovl12_e80;
procedure ovl12_e81;
procedure ovl12_e82;
procedure ovl12_e83;
procedure ovl12_e84;
procedure ovl12_e85;
procedure ovl12_e86;
procedure ovl12_e87;
procedure ovl12_e88;
procedure ovl12_fn_2915;
procedure ovl12_e89;
procedure ovl12_e90;
procedure ovl12_e91;
procedure ovl12_e92;
procedure ovl12_e93;
procedure ovl12_e94;
procedure ovl12_e95;
procedure ovl12_e96;
procedure ovl12_e97;
procedure ovl12_e98;
procedure ovl12_e99;
procedure ovl12_e100;
procedure ovl12_e101;
procedure ovl12_e102;
procedure ovl12_fn_2B6F;
procedure ovl12_e103;
procedure ovl12_fn_2B8B;
procedure ovl12_e104;
procedure ovl12_e105;
procedure ovl12_e106;
procedure ovl12_fn_2D39;
procedure ovl12_e107;
procedure ovl12_e108;
procedure ovl12_e109;
procedure ovl12_e110;
procedure ovl12_e111;
procedure ovl12_fn_2EEA;
procedure ovl12_e112;
procedure ovl12_fn_2F7B;
procedure ovl12_e113;
procedure ovl12_fn_30FB;
procedure ovl12_e114;
procedure ovl12_e115;
procedure ovl12_e116;
procedure ovl12_e1;
procedure ovl12_fn_31D7;
procedure ovl12_fn_3262;
procedure ovl12_fn_3728;
implementation
uses RES12, OVL24, OVL31;
const
  RunsHandlerOnRemove = 1;      { TAffect.Flag: the affect's handler runs when the affect is removed }
  HookGoesDown = $D;            { RunAffectHooks kind: a combatant going down (DealDamage, DropCombatant) }
  CombatViewMode = 5;           { ds49F3 during a combat (RunCombat sets it, whitepaper 5.5) }
  StatusGone = 6;               { TCharacter.Status 6, dead for good (ovl04:0510) }
  StatusStoned = 7;             { TCharacter.Status 7, stone (ovl04:093D) }
  MoraleStep = 5;               { what the affect handlers add to or take from the morale scratch ds6825 }
  TargetBonus = 2;              { what BoostAttackAgainstTarget adds to AttackRoll and to DamageAmount }
  AffectTrainingManual = 7;     { the affect id of "Training with Manual of Bodily Health" (ovl15:0FBC names it) }
  TrainingManualDuration = 43200; { $A8C0: the Duration ovl12:017F gives the affect }
  TrainingManualData = $FF;     { the Data byte ovl12:017F gives the affect }
  TrainingConstitution = 15;    { training needs at least this Constitution; a fighter level counts Constitution - 15,
                                  a non-fighter level counts twice above it (the same rule as Raise Dead, ovl04:0510) }
  FighterOnlyConstitution = 17; { from 17 up only a fighter level keeps the training gain (ovl04 uses the same limit) }
  FighterClass = 2;             { index in ClassLevels of the fighter }
  LastClass = 7;
  ConstitutionLimit = 20;       { training that takes Constitution to 20 gives AffectTrainedOut and stops }
  AffectTrainedOut = $3E;       { purpose unknown [?]: given by the training routine (ovl12:0233) at ConstitutionLimit }
  TrainedOutDuration = $3C;
  TrainedOutData = $FF;
  KindCold = 2;                 { the DamageKind bit of cold damage (ovl24:13E4, the text 'from Cold') }
  ColdSaveBonus = 3;            { what a cold hit adds to SaveRoll (ovl12:03E1) }
  ControlAppliedBit = $20;      { Affect.Data bit 5: set once the control is applied (ovl12:0400) }
  ControlSavedSideBit = $40;    { Affect.Data bit 6: the side Who had before; removing the affect gives it back }
  ControlSideBit = $80;         { Affect.Data bit 7: the side the control gives Who (TCharacter.Side) }
  ComputerRunFlag = $80;        { TCharacter.B84 high bit: the computer runs the member (ovl09 CheckMorale) }
  ComputerRunMorale = $B3;      { TCharacter.B84 of a computer-run member: the flag and morale $33 }
  AffectMorale = 100;           { what applying the control sets the morale scratch ds6825 to }
  ExceptionalStrength = 18;     { Strength 18 is written with a percentile (EncodeStrength, ovl24:10E4) }
  StrengthKept = $80;           { bit 7 of a strength affect's Data: an earlier strength is kept in it (ovl24:115C) }
  AffectStrength1 = $0C;        { the two strength affects (ovl24:115C keeps the earlier strength in them) }
  AffectStrength2 = $26;
  AffectUnknown0F = $0F;        { purpose unknown; ovl04 removes it with the poison affect $37 (ovl04:0807) }
  AffectUnknown0FDuration = 10; { the Duration ovl12:05EB gives affect $0F }
  MinimumResistance = $39;      { ovl12:064E raises ResistValue (+$111) to at least this (57) }
  ClearDamageValue = $0F;       { ovl12:064E clears DamageAmount when ds681B is this }

{ ovl12:0000. Cancels the hook of an affect: when AffectId is 0 or is the affect the hooks are offering
  (HookAffectId), HookAffectId and DamageAmount are cleared. HookAffectId 0 reads as "is Unaffected"
  (ovl24:1672), so the affect and its damage are dropped. }
procedure CancelPendingHook(AffectId: Byte);
begin
  if (AffectId = 0) or (HookAffectId = AffectId) then
  begin
    DamageAmount := 0;
    HookAffectId := 0;
  end;
end;
{ ovl12:001F. Gives Who the affect AffectId with Duration and Data unless the Temple is removing affects
  (ds681F is 1 then, set by the Temple's RemoveAffect calls, ovl04:0386): then the result is False and
  nothing is added. Otherwise AddAffect (ovl24:0E52) appends the affect with its handler marked to run
  when the affect is removed, and the result is True. }
function TryAddAffect(Who: PCharacter; AffectId, Data: Byte; Duration: Word): Boolean;
begin
  if ds681F <> 0 then
    TryAddAffect := False
  else
  begin
    TryAddAffect := True;
    AddAffect(Who, AffectId, Duration, Data, RunsHandlerOnRemove);
  end;
end;
{ ovl12:0058. Puts Who out of the fight, with Msg shown on Who in colour 10 (res12_fn_16EC). Unless Who's
  Status is 6, 7 or 8 already, its Status becomes NewStatus, its Flag10D and Flag11B are cleared, its
  death affects are removed (RemoveDeathAffects), the hooks of a combatant going down run, and Who leaves
  the map (RemoveCombatant) when Flag10D is clear. Then DelayByGameSpeed, the prompt is cleared and,
  outside combat, the selected character is redrawn. Like DropCombatant (ovl24:0F06) without the ground
  redraw. }
procedure DropFromFight(Who: PCharacter; NewStatus: Byte; Msg: String40);
begin
  res12_fn_16EC(Who, Msg, $A, 0);
  case Who^.Status of
    StatusStoned, StatusGone, 8: Exit;
  end;
  Who^.Status := NewStatus;
  Who^.Flag10D := 0;
  Who^.Flag11B := 0;
  RemoveDeathAffects(Who);
  RunAffectHooks(HookGoesDown, Who);
  if Who^.Flag10D = 0 then
    RemoveCombatant(Who);
  DelayByGameSpeed;
  res12_fn_17E3;
  if ds49F3 <> CombatViewMode then
    res12_fn_0767(SelectedCharacter);
end;
{ ovl12:010D. Affect handler of an affect (the AffectHandlers shape: Who, Affect and Mode; Mode is not read,
  so applying and removing run the same code, ovl24:0000): adds MoraleStep to the morale scratch ds6825 (ovl09 CheckMorale
  computes it) and 1 to AttackRoll. The handler at ovl12:011D takes both back. }
procedure RaiseAttackAndMorale(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Inc(ds6825, MoraleStep);
  Inc(AttackRoll);
end;
{ ovl12:011D. The handler that undoes RaiseAttackAndMorale (ovl12:010D), with the AffectHandlers shape (Who,
  Affect and Mode; Mode not read): takes MoraleStep off the morale scratch ds6825, or sets it to 0 when it
  holds less, and takes 1 off AttackRoll. }
procedure LowerAttackAndMorale(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if ds6825 < MoraleStep then
    ds6825 := 0
  else
    Dec(ds6825, MoraleStep);
  Dec(AttackRoll);
end;
{ ovl12:013B. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000).
  It copies the character Who attacked last (Who's combat Target, TCombatant at +$108 of Who, MeleeAttack
  sets it in ovl08) into AttackTarget. When that character's byte +$9F (Pad9E[$9F] of TCharacter, not named
  yet) is 4, the attack roll and the damage each gain TargetBonus. }
procedure BoostAttackAgainstTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  AttackTarget := Who^.Combat^.Target;
  if AttackTarget^.Pad9E[$9F] = 4 then
  begin
    Inc(AttackRoll, TargetBonus);
    Inc(DamageAmount, TargetBonus);
  end;
end;
{ ovl12:017F. Shows "starts to train" on Who in colour 10 (res12_fn_16EC, the message is copied to a
  stack temporary by 0AF8:0B0B first) and gives Who the training manual affect (AffectTrainingManual,
  duration TrainingManualDuration, data TrainingManualData), whose handler runs when it is removed.
  It has the AffectHandlers frame (Who, Affect, Mode); Affect and Mode are not read here. }
procedure StartTrainingWithManual(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  res12_fn_16EC(Who, 'starts to train', $A, 1);
  AddAffect(Who, AffectTrainingManual, TrainingManualDuration, TrainingManualData, RunsHandlerOnRemove);
end;
{ ovl12:01C3. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000).
  Like BoostAttackAgainstTarget (ovl12:013B) it copies Who's combat Target into AttackTarget, then gives
  a bonus to the attack roll and to the damage from the target's byte +$9F (Pad9E[$9F] of TCharacter, not
  named yet): 10 gives 1, 9 or 12 gives 2, 4 gives 3, any other value gives 0. The damage kind becomes 9
  (fire, plus the magic bit 8, ovl24:13E4). Which affect runs it is not known yet [?]. }
procedure BoostFireAttackByTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Bonus: Byte;
begin
  AttackTarget := Who^.Combat^.Target;
  case AttackTarget^.Pad9E[$9F] of
    10: Bonus := 1;
    9, 12: Bonus := 2;
    4: Bonus := 3;
  else
    Bonus := 0;
  end;
  Inc(AttackRoll, Bonus);
  Inc(DamageAmount, Bonus);
  DamageKind := 9;
end;
{ ovl12:0233. Training of Who's constitution: shows "is hardier" on Who (colour 10), Constitution goes up by one,
  and Who's hit points gain: the hit points above HpB1 (HpMax - HpB1) are divided by the class weight (fighter
  levels count Constitution - 15, non-fighter levels count twice above 15, else 1; 1 when the weight is 0),
  and the gain goes to HpMax and to the current hit points Flag11B. Nothing is gained below Constitution 15,
  nor from 17 up without a fighter level. At Constitution 20 Who gets AffectTrainedOut instead and the
  routine ends. It has the AffectHandlers frame (Who, Affect, Mode); Affect and Mode are not read here. }
procedure TrainConstitution(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Gain: Byte;                   { HpMax - HpB1 first, then the gain of this training }
  Weight: Byte;                 { the class weights summed (ovl04:0510) }
  I: ShortInt;
begin
  res12_fn_16EC(Who, 'is hardier', $A, 1);
  Inc(Who^.Constitution);
  if Who^.Constitution >= ConstitutionLimit then
  begin
    AddAffect(Who, AffectTrainedOut, TrainedOutDuration, TrainedOutData, RunsHandlerOnRemove);
    Exit;
  end;
  Gain := Who^.HpMax - Who^.HpB1;
  Weight := 0;
  if Who^.Constitution < TrainingConstitution then Exit;
  for I := 0 to LastClass do
    if Who^.ClassLevels[I] > 0 then
      if I = FighterClass then
        Inc(Weight, (Who^.Constitution - TrainingConstitution) * Who^.ClassLevels[I])
      else if Who^.Constitution > TrainingConstitution then
        Inc(Weight, Who^.ClassLevels[I] * 2)
      else
        Inc(Weight, Who^.ClassLevels[I]);
  if Weight = 0 then Weight := 1;
  Gain := Gain div Weight;
  if (Who^.Constitution < FighterOnlyConstitution) or (Who^.ClassLevels[FighterClass] > 0) then
  begin
    Inc(Who^.HpMax, Gain);
    Inc(Who^.Flag11B, Gain);
  end;
end;
{ ovl12:0377. Purpose unknown: it moves 2 from the attack roll to the saving throw roll when the selected character's
  ByteA0 (+$A0 of TCharacter, meaning not known) is 2, 5 or 8: SaveRoll (DS:6816) gains 2 and AttackRoll (DS:6822)
  loses 2. It has the 10-byte frame of the affect handlers, but reads SelectedCharacter, not its parameters
  (Who, Affect and Mode are not read). }
procedure ShiftAttackToSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (SelectedCharacter^.ByteA0 = 2) or (SelectedCharacter^.ByteA0 = 5) or (SelectedCharacter^.ByteA0 = 8) then
  begin
    Inc(SaveRoll, 2);
    Dec(AttackRoll, 2);
  end;
end;
{ ovl12:03AC. Purpose unknown: the twin of ShiftAttackToSave (ovl12:0377) with the ByteA0 values 0, 3 and 6
  (+$A0 of the selected character) in place of 2, 5 and 8: SaveRoll (DS:6816) gains 2 and AttackRoll (DS:6822)
  loses 2. Who, Affect and Mode are not read. }
procedure ovl12_e9(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (SelectedCharacter^.ByteA0 = 0) or (SelectedCharacter^.ByteA0 = 3) or (SelectedCharacter^.ByteA0 = 6) then
  begin
    Inc(SaveRoll, 2);
    Dec(AttackRoll, 2);
  end;
end;
{ ovl12:03E1. Affect handler for damage (the AffectHandlers frame: Who, Affect and Mode, none of them read): when
  the damage being dealt is cold (DamageKind bit KindCold, DS:6819), it halves DamageAmount (DS:6818) and adds
  ColdSaveBonus to SaveRoll (DS:6816). Purpose unknown: which affect runs it is not known yet [?]. }
procedure HalveColdDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (DamageKind and KindCold) <> 0 then
  begin
    DamageAmount := DamageAmount shr 1;
    Inc(SaveRoll, ColdSaveBonus);
  end;
end;
{ ovl12:0400. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode 0 applies, any other value
  removes, ovl24:0000). The affect number that runs it is not known yet [?]. Applying gives Who to the
  computer, as quick combat does (whitepaper, "Who plays"): Quick is set so QuickTurn plays the turn, Who
  becomes computer-run with morale $33 unless it already is, the target Who attacked is dropped and
  res12_fn_23DB runs (not named yet). The side becomes Affect.Data bit 7 (ControlSideBit); bit 6 keeps the
  side before (ControlSavedSideBit) and bit 5 marks the control as applied, so a second apply only sets
  the morale. Removing gives back the side from bit 6 and clears the computer-run morale while it is still
  ComputerRunMorale; it does not clear Quick. Applying also sets the morale scratch ds6825 (AffectMorale). }
procedure ComputerTakesOver(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if Mode <> 0 then
  begin
    Who^.Side := (Affect^.Data and ControlSavedSideBit) div ControlSavedSideBit;
    if Who^.B84 = ComputerRunMorale then
      Who^.B84 := 0;
  end
  else
  begin
    if (Affect^.Data and ControlAppliedBit) = 0 then
    begin
      { the side is read signed, as the original sign-extends it (cbw) }
      Affect^.Data := Affect^.Data + ControlAppliedBit + ShortInt(Who^.Side) * ControlSavedSideBit;
      Who^.Side := Affect^.Data div ControlSideBit;
      Who^.Quick := 1;
      if Who^.B84 <= ComputerRunFlag - 1 then
        Who^.B84 := ComputerRunMorale;
      Who^.Combat^.Target := nil;
      res12_fn_23DB;
    end;
    ds6825 := AffectMorale;
  end;
end;
{ ovl12:04BA. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000) of a strength
  affect whose Data holds an encoded strength (EncodeStrength, ovl24:10E4). Does nothing when Data has bit 7
  (StrengthKept): an earlier strength is kept in it. Otherwise Who's Strength and StrengthPercent take the
  affect's strength (DecodeStrength, ovl24:110D). Then the strongest other strength affect of Who, id $0C or
  $26 (AffectStrength1, AffectStrength2), gives Who its strength, and it takes the encoded strength the
  affect gave Who. Strength 18 with a percentile counts above any other 18 (ExceptionalStrength). With no
  other strength affect Who keeps the decoded strength. Which affect ids run it is not known yet [?].
  QUIRK ovl12:05B8: the earlier affect's Data is written without StrengthKept, where RaiseStrength (ovl24:115C)
  sets it. }
procedure ExchangeStrengthWithAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Strength: Byte;
  Percent: Byte;
  BestStrength: Byte;
  BestPercent: Byte;
  Scan: PAffect;
  Earlier: PAffect;
begin
  if Affect^.Data > StrengthKept - 1 then
    Exit;
  DecodeStrength(Affect, Strength, Percent);
  Who^.Strength := Strength;
  Who^.StrengthPercent := Percent;
  Earlier := nil;
  BestStrength := 0;
  BestPercent := 0;
  Scan := Who^.Affects;
  while Scan <> nil do
  begin
    if (Scan^.Id = AffectStrength1) or (Scan^.Id = AffectStrength2) then
      if Scan <> Affect then
      begin
        DecodeStrength(Scan, Strength, Percent);
        if (Strength > BestStrength) or ((BestStrength = ExceptionalStrength) and (Percent > BestPercent)) then
        begin
          BestStrength := Strength;
          BestPercent := Percent;
          Earlier := Scan;
        end;
      end;
    Scan := Scan^.Next;
  end;
  if Earlier <> nil then
  begin
    Earlier^.Data := EncodeStrength(Who^.Strength, Who^.StrengthPercent);
    Who^.Strength := BestStrength;
    Who^.StrengthPercent := BestPercent;
  end;
end;
{ ovl12:05D6. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000): Who's
  Charisma (TCharacter +$15) becomes the affect's Data byte. Applying and removing run the same code, so the
  value is set each time. Which affect id runs it is not known yet [?]. }
procedure SetCharismaFromAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Who^.Charisma := Affect^.Data;
end;
{ ovl12:05EB. Purpose unknown: an affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is
  not read, ovl24:0000). It adds affect $0F (AffectUnknown0F) to Who for AffectUnknown0FDuration with the
  Data byte of Affect, when TryAddAffect allows it. Then, while Who has more than one hit point (Flag11B,
  the current hit points [I]), it deals 1 point of plain damage (DamageKind 0, no save, DealDamage) and,
  outside combat, redraws the selected character (ds49F3 is not CombatViewMode). Which affect id runs it
  is not known yet [?]. }
procedure AddAffectAndDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if TryAddAffect(Who, AffectUnknown0F, Affect^.Data, AffectUnknown0FDuration) then
    if Who^.Flag11B > 1 then
    begin
      DamageKind := 0;
      DealDamage(Who, 1, 0, False);
      if ds49F3 <> CombatViewMode then
        res12_fn_0767(SelectedCharacter);
    end;
end;
{ ovl12:0647. Affect handler (the AffectHandlers shape: Who, Affect and Mode) that does nothing: none of its
  parameters is read and no global is written. Which affect id runs it is not known yet [?]. }
procedure IgnoreAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
end;
{ ovl12:064E. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read). Raises
  Who's ResistValue (TCharacter +$111, likely the magic resistance [I]) to at least MinimumResistance, adds one
  to SaveRoll, and when ds681B is ClearDamageValue clears DamageAmount, so the damage of the roll in progress is
  none. Which affect id runs it is not known yet [?]. }
procedure RaiseResistanceAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if Who^.ResistValue < MinimumResistance then
    Who^.ResistValue := MinimumResistance;
  Inc(SaveRoll);
  if ds681B = ClearDamageValue then
    DamageAmount := 0;
end;
{ ovl12:0679. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It copies the
  character Who attacked last (Who's combat Target) into AttackTarget, as BoostAttackAgainstTarget does. When that
  character's +$9F (Pad9E[$9F]) and CombatSize (+$6C) are both 1, AttackRoll gains 1 for each of the names
  ds0332[1..4] the character's name equals. Which affect runs it is not known yet [?]. }
procedure BoostAttackVsListedTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  I: Byte;
begin
  AttackTarget := Who^.Combat^.Target;
  if (AttackTarget^.Pad9E[$9F] = 1) and (AttackTarget^.CombatSize = 1) then
    for I := 1 to 4 do
      if AttackTarget^.Name = ds0332[I] then
        Inc(AttackRoll);
end;
{ ovl12:06E4: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e18; begin end;
{ ovl12:070F: retf 10: 10 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl12_e19; begin end;
{ ovl12:0775: retf 10: 10 bytes of parameters; 22 bytes of locals }
{@stub} procedure ovl12_e20; begin end;
{ ovl12:07E0: retf 10: 10 bytes of parameters; 20 bytes of locals }
{@stub} procedure ovl12_e21; begin end;
{ ovl12:0918: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl12_e22; begin end;
{ ovl12:0947: retf 10: 10 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl12_e23; begin end;
{ ovl12:09C0: retf 10: 10 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl12_e24; begin end;
{ ovl12:0A3D: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e25; begin end;
{ ovl12:0A65: frame not read }
{@stub} procedure ovl12_e26; begin end;
{ ovl12:0AE5: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_0AE5; begin end;
{ ovl12:0B1B: frame not read }
{@stub} procedure ovl12_e27; begin end;
{ ovl12:0B25: frame not read }
{@stub} procedure ovl12_fn_0B25; begin end;
{ ovl12:0B2A: frame not read }
{@stub} procedure ovl12_fn_0B2A; begin end;
{ ovl12:0B2F: frame not read }
{@stub} procedure ovl12_fn_0B2F; begin end;
{ ovl12:0B43: frame not read }
{@stub} procedure ovl12_fn_0B43; begin end;
{ ovl12:0B48: frame not read }
{@stub} procedure ovl12_fn_0B48; begin end;
{ ovl12:0B4D: frame not read }
{@stub} procedure ovl12_fn_0B4D; begin end;
{ ovl12:0B52: frame not read }
{@stub} procedure ovl12_fn_0B52; begin end;
{ ovl12:0B57: frame not read }
{@stub} procedure ovl12_fn_0B57; begin end;
{ ovl12:0B61: frame not read }
{@stub} procedure ovl12_fn_0B61; begin end;
{ ovl12:0B70: frame not read }
{@stub} procedure ovl12_fn_0B70; begin end;
{ ovl12:0B75: frame not read }
{@stub} procedure ovl12_fn_0B75; begin end;
{ ovl12:0B7A: frame not read }
{@stub} procedure ovl12_fn_0B7A; begin end;
{ ovl12:0B7F: frame not read }
{@stub} procedure ovl12_fn_0B7F; begin end;
{ ovl12:0B84: frame not read }
{@stub} procedure ovl12_fn_0B84; begin end;
{ ovl12:0B89: frame not read }
{@stub} procedure ovl12_fn_0B89; begin end;
{ ovl12:0B8E: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_0B8E; begin end;
{ ovl12:0BAC: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e28; begin end;
{ ovl12:0BCF: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e29; begin end;
{ ovl12:0C06: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e30; begin end;
{ ovl12:0C15: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e31; begin end;
{ ovl12:0C26: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e32; begin end;
{ ovl12:0C4B: retf 10: 10 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl12_e33; begin end;
{ ovl12:0CC3: retf 10: 10 bytes of parameters; 40 bytes of locals }
{@stub} procedure ovl12_e34; begin end;
{ ovl12:0FAC: retf 6: 6 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl12_fn_0FAC; begin end;
{ ovl12:101D: retf 4: 4 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl12_fn_101D; begin end;
{ ovl12:1086: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e35; begin end;
{ ovl12:10C1: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e36; begin end;
{ ovl12:10DE: retf 10: 10 bytes of parameters; 16 bytes of locals }
{@stub} procedure ovl12_e37; begin end;
{ ovl12:1168: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl12_e38; begin end;
{ ovl12:11F9: retf 10: 10 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl12_e39; begin end;
{ ovl12:1276: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e40; begin end;
{ ovl12:12B2: retf 10: 10 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl12_e41; begin end;
{ ovl12:12FB: frame not read }
{@stub} procedure ovl12_e42; begin end;
{ ovl12:1307: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_1307; begin end;
{ ovl12:133F: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e43; begin end;
{ ovl12:1355: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e44; begin end;
{ ovl12:135C: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e45; begin end;
{ ovl12:1363: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e46; begin end;
{ ovl12:1399: retf 10: 10 bytes of parameters; 16 bytes of locals }
{@stub} procedure ovl12_e47; begin end;
{ ovl12:1452: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e48; begin end;
{ ovl12:1472: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e49; begin end;
{ ovl12:1490: retf 10: 10 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl12_e50; begin end;
{ ovl12:14EB: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e51; begin end;
{ ovl12:1543: frame not read }
{@stub} procedure ovl12_fn_1543; begin end;
{ ovl12:1545: frame not read }
{@stub} procedure ovl12_fn_1545; begin end;
{ ovl12:1583: retf 6: 6 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_1583; begin end;
{ ovl12:15EB: retf 8: 8 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl12_fn_15EB; begin end;
{ ovl12:165D: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e52; begin end;
{ ovl12:1671: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e53; begin end;
{ ovl12:1685: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e54; begin end;
{ ovl12:1699: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e55; begin end;
{ ovl12:16BB: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e56; begin end;
{ ovl12:16E6: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e57; begin end;
{ ovl12:170B: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e58; begin end;
{ ovl12:171F: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e59; begin end;
{ ovl12:1730: frame not read }
{@stub} procedure ovl12_e60; begin end;
{ ovl12:1758: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_1758; begin end;
{ ovl12:176F: retf 10: 10 bytes of parameters; 20 bytes of locals }
{@stub} procedure ovl12_e61; begin end;
{ ovl12:18B5: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e62; begin end;
{ ovl12:1935: retf 10: 10 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl12_e63; begin end;
{ ovl12:19D9: retf 10: 10 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl12_e64; begin end;
{ ovl12:1A19: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e65; begin end;
{ ovl12:1A4C: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e66; begin end;
{ ovl12:1AAA: retf 10: 10 bytes of parameters; 28 bytes of locals }
{@stub} procedure ovl12_e67; begin end;
{ ovl12:1BA8: frame not read }
{@stub} procedure ovl12_e68; begin end;
{ ovl12:1BD7: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_1BD7; begin end;
{ ovl12:1C98: frame not read }
{@stub} procedure ovl12_fn_1C98; begin end;
{ ovl12:1CAD: retf 10: 10 bytes of parameters; 22 bytes of locals }
{@stub} procedure ovl12_e69; begin end;
{ ovl12:1E77: frame not read }
{@stub} procedure ovl12_e70; begin end;
{ ovl12:1F9B: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_1F9B; begin end;
{ ovl12:2002: frame not read }
{@stub} procedure ovl12_fn_2002; begin end;
{ ovl12:20A9: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_20A9; begin end;
{ ovl12:2122: frame not read }
{@stub} procedure ovl12_fn_2122; begin end;
{ ovl12:2197: frame not read }
{@stub} procedure ovl12_fn_2197; begin end;
{ ovl12:2233: frame not read }
{@stub} procedure ovl12_fn_2233; begin end;
{ ovl12:228C: frame not read }
{@stub} procedure ovl12_fn_228C; begin end;
{ ovl12:2383: retf 6: 6 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_2383; begin end;
{ ovl12:23A4: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e71; begin end;
{ ovl12:23C2: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e72; begin end;
{ ovl12:23EC: retf 10: 10 bytes of parameters; 16 bytes of locals }
{@stub} procedure ovl12_e73; begin end;
{ ovl12:2490: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e74; begin end;
{ ovl12:24D9: retf 10: 10 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl12_e75; begin end;
{ ovl12:2556: frame not read }
{@stub} procedure ovl12_e76; begin end;
{ ovl12:257E: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_257E; begin end;
{ ovl12:25A2: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e77; begin end;
{ ovl12:25BC: frame not read }
{@stub} procedure ovl12_e78; begin end;
{ ovl12:25C9: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_25C9; begin end;
{ ovl12:2610: retf 10: 10 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl12_e79; begin end;
{ ovl12:264B: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl12_e80; begin end;
{ ovl12:268A: retf 10: 10 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl12_e81; begin end;
{ ovl12:2700: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e82; begin end;
{ ovl12:2730: retf 10: 10 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl12_e83; begin end;
{ ovl12:27D9: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e84; begin end;
{ ovl12:2814: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl12_e85; begin end;
{ ovl12:2866: retf 10: 10 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl12_e86; begin end;
{ ovl12:28BF: retf 10: 10 bytes of parameters; 26 bytes of locals }
{@stub} procedure ovl12_e87; begin end;
{ ovl12:2901: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e88; begin end;
{ ovl12:2915: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl12_fn_2915; begin end;
{ ovl12:2976: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e89; begin end;
{ ovl12:2984: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e90; begin end;
{ ovl12:2992: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e91; begin end;
{ ovl12:29B6: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e92; begin end;
{ ovl12:29CB: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e93; begin end;
{ ovl12:29D9: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e94; begin end;
{ ovl12:29F0: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e95; begin end;
{ ovl12:2A11: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e96; begin end;
{ ovl12:2A28: retf 10: 10 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl12_e97; begin end;
{ ovl12:2A6D: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e98; begin end;
{ ovl12:2A87: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl12_e99; begin end;
{ ovl12:2AE6: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl12_e100; begin end;
{ ovl12:2B20: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl12_e101; begin end;
{ ovl12:2B63: frame not read }
{@stub} procedure ovl12_e102; begin end;
{ ovl12:2B6F: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_2B6F; begin end;
{ ovl12:2B7D: frame not read }
{@stub} procedure ovl12_e103; begin end;
{ ovl12:2B8B: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_2B8B; begin end;
{ ovl12:2BC8: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl12_e104; begin end;
{ ovl12:2C1C: retf 10: 10 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl12_e105; begin end;
{ ovl12:2D38: frame not read }
{@stub} procedure ovl12_e106; begin end;
{ ovl12:2D39: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl12_fn_2D39; begin end;
{ ovl12:2D88: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl12_e107; begin end;
{ ovl12:2DE4: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e108; begin end;
{ ovl12:2E08: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e109; begin end;
{ ovl12:2E37: retf 10: 10 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl12_e110; begin end;
{ ovl12:2EDA: frame not read }
{@stub} procedure ovl12_e111; begin end;
{ ovl12:2EEA: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_2EEA; begin end;
{ ovl12:2F57: frame not read }
{@stub} procedure ovl12_e112; begin end;
{ ovl12:2F7B: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_2F7B; begin end;
{ ovl12:30A5: frame not read }
{@stub} procedure ovl12_e113; begin end;
{ ovl12:30FB: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_30FB; begin end;
{ ovl12:3134: retf 10: 10 bytes of parameters; 30 bytes of locals }
{@stub} procedure ovl12_e114; begin end;
{ ovl12:317A: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e115; begin end;
{ ovl12:319B: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_e116; begin end;
{ ovl12:31A2: frame not read }
{@stub} procedure ovl12_e1; begin end;
{ ovl12:31D7: frame not read }
{@stub} procedure ovl12_fn_31D7; begin end;
{ ovl12:3262: frame not read }
{@stub} procedure ovl12_fn_3262; begin end;
{ ovl12:3728: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl12_fn_3728; begin end;

begin
end.
