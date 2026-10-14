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
procedure HalveFireDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ShowSilenceAndStopCasting(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure DieIfPoisoned(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure GiveAffectItem(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure LowerAttackRollByFour(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure BoostAttackVsEightListed(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ImageAbsorbsHit(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ReduceDamageByQuarter(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CoughStopsCasting(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CollapseAndChangeSide(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure LowerAttackSaveAndResistance(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure RunDiseaseHandlers(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure RaiseAttackAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure LowerAttackAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure SetAttackMissIfTurnPending(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure AgeCharacterOnce(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ClearCloud(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure AvoidDistantAttack(Who: PCharacter; Chance: Byte);
function FirstSlotItem(Who: PCharacter): PItem;
procedure AvoidIfSelectedItemPlusZero(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure HalveAgeDoubling(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure WeakenStrength(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CauseDiseaseAndDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure LowerAttackVsEightListed(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure LowerAttackIfSelectedIsBugbearOrGnoll(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure RaiseOrLowerAttackAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure AddHealingBlockAndHeal(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ovl12_e43(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ovl12_e44(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ovl12_e45(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ovl12_e46(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ProgressRot(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ovl12_e48(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ovl12_e49(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ReduceFireDamageByRoll(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure AddTrainedOutAndHeal(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure PoisonAttackTarget(Who: PCharacter; Bonus: ShortInt);
procedure ParalyzeAttackTarget(Who: PCharacter; Duration: Word; Unused: Byte);
procedure PoisonAttackTargetBonus0(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure PoisonAttackTargetBonus4(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure PoisonAttackTargetBonus2(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ParalyzeAttackTargetFor2d8(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ParalyzeAttackTargetUnlessImmune(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ParalyzeAttackTargetFor1d9Plus10(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure PoisonAttackTargetBonusMinus2(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure SetFlagAndLowerAttackRollByFour(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ovl12_e60(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure DrainBloodFromCombatant(Who: PCharacter; Affect: PAffect; Mode: Byte);
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
  NoRemoveHandler = 0;          { the same Flag, clear: the affect's handler does not run when the affect is removed }
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
  KindFire = 1;                 { the DamageKind bit of fire damage (POOLVARS DamageKind: 1 fire) }
  KindMagic = 8;                { the DamageKind bit of magical damage (POOLVARS DamageKind: bit 3 magic) }
  FireSaveBonus = 3;            { what a fire hit adds to SaveRoll (ovl12:06E4) }
  FireReductionPerDie = 2;      { what each die of the last roll takes off fire damage (ovl12:1490) }
  FireProtectionSaveBonus = 4;  { what the fire damage hook (ovl12:1490) adds to SaveRoll }
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
  AffectPoisoned = $37;         { the Poisoned affect (ovl15 names it 'Poisoned'; ovl04 calls it AffectPoison) }
  SaveKindPoison = 0;           { SavingThrow kind 0, the first of the five saves: the poison save [I] (ovl12:1545) }
  SaveKindParalysis = 0;        { the same kind 0 for the paralysis save of ovl12:15EB [I] (the first of the five saves) }
  AffectParalysis = $34;        { the affect of "is Paralyzed" (ovl12:15EB): a spell affect that ovl15 names by its spell [I] }
  ParalysisData = $0C;          { the Data byte ovl12:15EB gives the paralysis affect }
  ParalysisImmuneRace = 2;      { TCharacter.Race (+$2E) that ovl12:16BB leaves unparalysed [?] }
  ParalysisDuration = $3F;      { the rounds ovl12:16BB paralyses for (63) }
  ParalysisDieSides = 9;        { ovl12:16E6 paralyses for 1d9 plus ParalysisBaseRounds rounds }
  ParalysisBaseRounds = 10;
  AffectUnknown0F = $0F;        { purpose unknown; ovl04 removes it with the poison affect $37 (ovl04:0807) }
  AffectUnknown0FDuration = 10; { the Duration ovl12:05EB gives affect $0F }
  AffectUnknown18 = $18;        { purpose unknown: the affect SelectedCharacter must have for ds681E to stay 0 (ovl12:0918) }
  AttackPenalty = 4;            { what ovl12:0918, 0BAC, 0C15, 11F9 and 1276 take off AttackRoll }
  SavePenalty = 4;              { what ovl12:0BAC and 0C15 take off SaveRoll }
  ResistPenalty = 4;            { what ovl12:0BAC takes off Who's ResistValue and Pad112[$112] }
  MissRoll = -1;                { AttackRoll below 0 is a miss (RollToHit, ovl24:0CD5); ovl12:0C26 sets it }
  AgedBit = $10;                { Affect.Data bit 4: set once the affect has aged Who (ovl12:0C4B) }
  AffectImages = $1C;           { the images affect: runs on the damage hook (kind 6, ovl24:02FA); Data counts the images [I] }
  AffectUnknown2B = $2B;        { purpose unknown; a Cure Disease affect (ovl04:031E), run by RunDiseaseHandlers }
  AffectCauseDisease = $2C;     { named in ovl15 (ovl15:0FBC); a Cure Disease affect (ovl04:031E) }
  AffectCauseDiseaseDuration = 10; { the Duration ovl12:1168 gives affect AffectCauseDisease }
  AffectHealingBlock = $32;     { HealCharacter with Flag 0 does nothing while the character has it (ovl24:175D) }
  AffectHealingBlockDuration = 14400; { $3840: the Duration ovl12:12FB gives affect AffectHealingBlock }
  SideDataBit = $10;            { Affect.Data bit 4: a side, 0 or 1, compared with Who's Side (ovl12:12B2) }
  CombatKindMask = $7F;         { TCharacter.CombatSize bits 0..6: the combat footprint kind (POOLVARS, +$6C) }
  CoughResistLimit = 52;        { ovl12:0A65: TCharacter.Pad112[$112] above this steps down by CoughResistStep,
                                  else it is set to CoughResistReset }
  CoughResistReset = 50;
  CoughResistStep = 2;
  MinimumResistance = $39;      { ovl12:064E raises ResistValue (+$111) to at least this (57) }
  ClearDamageValue = $0F;       { ovl12:064E clears DamageAmount when ds681B is this }
  GivenItemType = $14;          { TMenuLine.ItemType of the item the affect gives (ovl12:07E0) }
  GivenItemNameNum2 = $14;      { NameNum[2] of that item }
  GivenItemNameNum3 = $F3;      { NameNum[3] of that item; the search of Who's items uses it too (ovl12:07E0) }
  GivenItemPlus = 1;            { Plus of that item }
  GivenItemAffect2 = $17;       { Affects[2] of that item }
  GivenItemAffect3 = $89;       { Affects[3] of that item }
  ItemCountLimit = $10;         { no item is given once ItemCountC7 is this or more (ovl12:07E0 at 0869) [I] }
  CloudTile = $1E;              { the cloud tile ApplyCloudTile (ovl24:0AE7) tests for; ovl12:0F14 repaints the arms with it }
  CloudBodyTile = $1F;          { the tile a cloud arm gets where a body lies when the cloud clears (ovl12:0CC3) [?] }
  AffectNausea = $1F;           { the affect of a failed save against the cloud: nausea (ovl24:0AE7) }
  WeakeningDuration = $3C;      { the Duration ovl12:10DE gives the affect AffectUnknown2B }
  AlwaysAvoids = 100;           { the Chance that avoids every roll of 1d100 (ovl12:1086) }
  AffectUnknown19 = $19;        { purpose unknown [I]: RollToHit clears it from the attacker (ovl24:0CB7) }
  AffectUnknown19Duration = 1;  { the Duration ovl12:1363 gives affect AffectUnknown19 }
  AffectUnknown19Data = $0C;    { the Data byte ovl12:1363 gives affect AffectUnknown19 }
  AffectUnknown19Chance = 95;   { ovl12:1730 gives affect AffectUnknown19 when a 1d100 roll is at or below this }
  AffectUnknown62 = $62;        { purpose unknown [?]: ovl12:1472 gives it; ovl24 also runs its hook (RunAffectHook $62) }
  AffectUnknown62Data = $FF;    { the Data byte ovl12:1472 gives affect AffectUnknown62 }
  AffectRot = $39;              { the rot affect: Cure Disease removes it (whitepaper 5.19 table, DS:0114) }
  RotDuration = 43200;          { $A8C0: the Duration the rot handler (ovl12:1399) gives the next rot }
  RotStage = $10;               { one stage of the rot: the rot handler takes it off the affect's Data high nibble }
  RotLastStage = 1;             { a rot whose stage is this or lower kills its victim (the rot handler, ovl12:1399) }
  RotCharismaLoss = 2;          { what each run of the rot handler (ovl12:1399) takes off Charisma }
  RotMinimumCharisma = 3;       { Charisma is not taken below this by the rot handler (ovl12:1399) }
  StatusRotted = 8;             { TCharacter.Status 8: what the rot handler gives its victim, who dies of the rot }

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
{ ovl12:06E4. Affect handler for damage (the AffectHandlers frame: Who, Affect and Mode, none of them read): when
  the damage being dealt is fire (DamageKind bit KindFire, DS:6819), it halves DamageAmount (DS:6818) and adds
  FireSaveBonus to SaveRoll (DS:6816), the fire twin of HalveColdDamage (ovl12:03E1). Purpose unknown: which
  affect runs it is not known yet [?]. }
procedure HalveFireDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (DamageKind and KindFire) <> 0 then
  begin
    DamageAmount := DamageAmount shr 1;
    Inc(SaveRoll, FireSaveBonus);
  end;
end;
{ ovl12:070F. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). When Who's combat
  byte Pad2 (+$2 of TCombatant, not named yet) is set, Who shows "is silenced" in colour 10 (res12_fn_16EC). Then
  Pad2 and CanCast (+$1, zero hides Cast in the combat menu, ovl08:0747) are both cleared. Which affect runs it is
  not known yet [?]. }
procedure ShowSilenceAndStopCasting(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if Who^.Combat^.Pad2 <> 0 then
    res12_fn_16EC(Who, 'is silenced', $A, 1);
  Who^.Combat^.Pad2 := 0;
  Who^.Combat^.CanCast := 0;
end;
{ ovl12:0775. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read): a poisoned
  character dies. When Who has the Poisoned affect (AffectPoisoned, ovl15 names it 'Poisoned'), DropFromFight takes
  Who out of the fight with StatusGone and the text 'dies from poison'. Then AffectUnknown0F is removed from Who
  inside the ds681F bracket the Temple uses around RemoveAffect (ovl04:0386), so TryAddAffect adds nothing while
  it runs. Which affect runs it is not known yet [?]. }
procedure DieIfPoisoned(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  PoisonAffect: Pointer;
begin
  if res12_fn_2199(Who, AffectPoisoned, PoisonAffect) then
    DropFromFight(Who, StatusGone, 'dies from poison');
  ds681F := 1;
  RemoveAffect(Who, AffectUnknown0F, nil);
  ds681F := 0;
end;
{ ovl12:07E0. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect is not read). When the affect
  is applied (Mode 0) and Who has no item of GivenItemType with NameNum[3] GivenItemNameNum3 yet, and Who's
  ItemCountC7 (+$C7, likely the item count [I]) is below ItemCountLimit, Who gets such an item (res12_fn_15F7 adds
  it to the list, the temporary is freed) and "Gains an item" is shown in colour 10. When it is removed (Mode not
  0) the item Who has is taken off the list (res12_fn_1509). Then res12_fn_0BB8 redraws Who. Purpose unknown: which
  affect id runs it is not known yet [?]. }
procedure GiveAffectItem(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;
  Found: Boolean;
begin
  Item := Who^.Items;
  Found := False;
  while (Item <> nil) and not Found do
    if (Item^.ItemType = GivenItemType) and (Item^.NameNum[3] = GivenItemNameNum3) then
      Found := True
    else
      Item := Item^.Next;
  if Mode <> 0 then
  begin
    if Item <> nil then
      res12_fn_1509(Who, Item);
  end;
  if Mode = 0 then
    if not Found then
      if Who^.ItemCountC7 < ItemCountLimit then
      begin
        New(Item);
        FillChar(Item^, SizeOf(TMenuLine), 0);
        Item^.ItemType := GivenItemType;
        Item^.NameNum[2] := GivenItemNameNum2;
        Item^.NameNum[3] := GivenItemNameNum3;
        Item^.Plus := GivenItemPlus;
        Item^.Affects[2] := GivenItemAffect2;
        Item^.Affects[3] := GivenItemAffect3;
        res12_fn_15F7(Who, Item);
        Dispose(Item);
        res12_fn_16EC(Who, 'Gains an item', $A, 1);
      end;
  res12_fn_0BB8(Who);
end;
{ ovl12:0918. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none of them is read). It takes
  AttackPenalty (4) off AttackRoll. When SelectedCharacter has no affect AffectUnknown18 ($18), ds681E is set to 1
  (res12_fn_2199 looks the affect up in the affect list and gives the found affect in FoundAffect). Purpose unknown:
  which affect runs it is not known yet [?]. }
procedure LowerAttackRollByFour(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  FoundAffect: Pointer;
begin
  if not res12_fn_2199(SelectedCharacter, AffectUnknown18, FoundAffect) then
    ds681E := 1;
  Dec(AttackRoll, AttackPenalty);
end;
{ ovl12:0947. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). The twin of
  BoostAttackVsListedTarget (ovl12:0679) with eight names: when the character Who attacked last (Who's combat
  Target, copied into AttackTarget) has Pad9E[$9F] and CombatSize (+$6C) both 1, AttackRoll gains 1 for each of
  the names ds0382[1..8] that the character's name equals. Which affect runs it is not known yet [?]. }
procedure BoostAttackVsEightListed(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  I: Byte;
begin
  AttackTarget := Who^.Combat^.Target;
  if (AttackTarget^.Pad9E[$9F] = 1) and (AttackTarget^.CombatSize = 1) then
    for I := 1 to 8 do
      if AttackTarget^.Name = ds0382[I] then
        Inc(AttackRoll);
end;
{ ovl12:09C0. Affect handler of the images affect (AffectImages, $1C; it runs on the damage hook, kind 6,
  ovl24:02FA; the AffectHandlers shape, Who, Affect and Mode, Mode not read). When a hit is about to land,
  one image may take it: with 1d(Data+1) (Data counts the images [I]) above 1, ds681B not 0 and ds6820 0,
  CancelPendingHook(0) drops the damage, Who shows "lost an image" in colour 10 (res12_fn_16EC) and Data goes
  down by one. When no image is left (Data 0) affect AffectImages is removed. A roll of 1 lets the hit through
  [I]. }
procedure ImageAbsorbsHit(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (RollDice(1, Affect^.Data + 1) > 1) and (ds681B > 0) and (ds6820 = 0) then
  begin
    CancelPendingHook(0);
    res12_fn_16EC(Who, 'lost an image', $A, 1);
    Dec(Affect^.Data);
    if Affect^.Data = 0 then
      RemoveAffect(Who, AffectImages, nil);
  end;
end;
{ ovl12:0A3D. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, so the
  handler runs the same on applying and removing). It takes a quarter off the damage the hooks offer:
  DamageAmount := DamageAmount - DamageAmount div 4, so three quarters of the damage (rounded down) remain
  (the damage hook is kind 6, ovl24:02FA). Which affect runs it is not known yet [?]. }
procedure ReduceDamageByQuarter(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  DamageAmount := DamageAmount - DamageAmount div 4;
end;
{ ovl12:0A65. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It stops Who
  casting: when Who's combat byte Pad2 (TCombatant +$2, not named yet) is set, Who shows "is coughing" in colour
  10 (res12_fn_16EC), then Pad2 and CanCast (+$1, zero hides Cast in the combat menu, ovl08:0747) are cleared and
  Who is redrawn (res12_fn_0BB8). Then TCharacter.Pad112[$112] (+$112, not named yet) steps down by
  CoughResistStep while above CoughResistLimit and is set to CoughResistReset otherwise, and that value becomes
  ResistValue (+$111). When Who is the selected character, res12_fn_09E3 runs (not named yet). Which affect runs
  it is not known yet [?]; the message suggests a gas or smoke affect [I]. }
procedure CoughStopsCasting(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if Who^.Combat^.Pad2 <> 0 then
    res12_fn_16EC(Who, 'is coughing', $A, 1);
  Who^.Combat^.Pad2 := 0;
  Who^.Combat^.CanCast := 0;
  res12_fn_0BB8(Who);
  if Who^.Pad112[$112] > CoughResistLimit then
    Dec(Who^.Pad112[$112], CoughResistStep)
  else
    Who^.Pad112[$112] := CoughResistReset;
  Who^.ResistValue := Who^.Pad112[$112];
  if Who = SelectedCharacter then
    res12_fn_09E3(Who);
end;
{ ovl12:0B1B. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It clears
  the affect's Flag, so the handler does not run again when the affect is removed. Unless the Temple is removing
  affects (ds681F is not 0), Who collapses: DropFromFight takes Who out of the fight with StatusGone and the text
  'collapses'. Then Who's side becomes the high nibble of the affect's Data, Quick is set so the computer plays
  Who (as ComputerTakesOver does, ovl12:0400), the morale of a computer-run member is cleared, and Who's +$6B gets
  the fighter level, +$72 gets 12, +$76 and +$9F get 0. Purpose unknown: which affect runs it is not known yet [?]. }
procedure CollapseAndChangeSide(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Affect^.Flag := 0;
  if ds681F = 0 then
    DropFromFight(Who, StatusGone, 'collapses');
  Who^.Side := Affect^.Data div 16;
  Who^.Quick := 1;
  Who^.Pad74[$76] := 0;
  Who^.Pad6B := Who^.ClassLevels[FighterClass];
  Who^.Pad72 := 12;
  if Who^.B84 = ComputerRunMorale then
    Who^.B84 := 0;
  Who^.Pad9E[$9F] := 0;
end;
{ 0BAC. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). Takes AttackPenalty
  off AttackRoll, ResistPenalty off Who's ResistValue (+$111) and off Pad112[$112] (+$112, the byte CoughStopsCasting
  copies into ResistValue, ovl12:0A65), and SavePenalty off SaveRoll. The affect that runs it is not known yet [?]. }
procedure LowerAttackSaveAndResistance(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Dec(AttackRoll, AttackPenalty);
  Dec(Who^.ResistValue, ResistPenalty);
  Dec(Who^.Pad112[$112], ResistPenalty);
  Dec(SaveRoll, SavePenalty);
end;
{ 0BCF. Affect handler (the AffectHandlers shape: Who, Affect and Mode, passed on unchanged). Runs the handler of
  affect AffectUnknown2B and then the handler of AffectCauseDisease with the same Who, Affect and Mode (both through
  CallAffectHandler, ovl24:0000). Both ids are in the list Cure Disease removes, so the routine runs the disease
  handlers. Which affect runs it is not known yet [?]. }
procedure RunDiseaseHandlers(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  CallAffectHandler(AffectUnknown2B, Who, Affect, Mode);
  CallAffectHandler(AffectCauseDisease, Who, Affect, Mode);
end;
{ 0C06. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). Adds 1 to SaveRoll and
  to AttackRoll, the plus of the routine at ovl12:0C15. Called by ovl12:12B2 (RaiseOrLowerAttackAndSave, not decompiled yet). }
procedure RaiseAttackAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Inc(SaveRoll);
  Inc(AttackRoll);
end;
{ 0C15. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). Takes AttackPenalty
  off AttackRoll and SavePenalty off SaveRoll, the minus of RaiseAttackAndSave (ovl12:0C06). Which affect runs it is
  not known yet [?]. }
procedure LowerAttackAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Dec(AttackRoll, AttackPenalty);
  Dec(SaveRoll, SavePenalty);
end;
{ 0C26. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read, ovl24:0000). When Who's combatant
  still has its turn to take (Combat^.Initiative, TCombatant +$3, above 0: CombatTurn acts only above 0), ds681E is set to
  1 and AttackRoll becomes MissRoll, a negative roll (a miss, ovl24:0CD5). Which affect runs it is not known yet [?]. }
procedure SetAttackMissIfTurnPending(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if Who^.Combat^.Initiative > 0 then
  begin
    ds681E := 1;
    AttackRoll := MissRoll;
  end;
end;
{ 0C4B. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). The first run
  with AgedBit clear in the affect's Data sets the bit, shows "ages" on Who in colour 10 (res12_fn_16EC) and adds one
  year to Who's Age (+$30). Every run doubles ds681A (shl 1), whether or not Who was aged. Which affect runs it is not
  known yet [?]. }
procedure AgeCharacterOnce(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (Affect^.Data and AgedBit) = 0 then
  begin
    Affect^.Data := Affect^.Data + AgedBit;
    res12_fn_16EC(Who, 'ages', $A, 1);
    Inc(Who^.Age);
  end;
  ds681A := ds681A shl 1;
end;
{ ovl12:0CC3. Affect handler of a cloud (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000).
  The cloud is the TCombatNode of the list ds6DBB whose owner is Who and whose kind is the high nibble of Affect's
  Data. Without one nothing happens. With one, "The air clears a little..." is shown (res12_fn_1693), and the
  cloud goes: each arm still in place gets back the tile it covered, except that an arm where a body lies (BodyTable)
  shows CloudBodyTile. The cloud is unlinked and freed, and every cloud left repaints its arms with CloudTile.
  Which affect runs it is not known yet [?]. }
procedure ClearCloud(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Node: PCombatNode;            { walks the list: first to the cloud's predecessor, later over every cloud }
  Cloud: PCombatNode;           { the cloud of Who with this kind }
  Found: Boolean;               { a cloud was found; then, for each arm, a body stands on the arm's cell }
  Index: Byte;                  { the cloud kind while the cloud is looked up, then the body index: one byte }
  Arm: Byte;
  CellX, CellY: Byte;           { the cell of an arm }
begin
  Index := Affect^.Data div 16;
  Found := False;
  Cloud := ds6DBB;
  while (Cloud <> nil) and not Found do
    if (Cloud^.Owner = Who) and (Cloud^.Kind = Index) then
      Found := True
    else
      Cloud := Cloud^.Next;
  if not Found then Exit;
  res12_fn_1693('The air clears a little...');
  for Arm := 1 to 4 do
    if Cloud^.Arms[Arm] <> 0 then
    begin
      CellX := Cloud^.X + DirStepX[ds290D[Arm]];
      CellY := Cloud^.Y + DirStepY[ds290D[Arm]];
      Found := False;
      for Index := 1 to BodyCount do
        if (BodyTable[Index].Who <> nil) and (BodyTable[Index].X = CellX) and (BodyTable[Index].Y = CellY) then
          Found := True;
      if Found then
        CombatMap^.Cells[CellY, CellX] := CloudBodyTile
      else
        CombatMap^.Cells[CellY, CellX] := Cloud^.Tiles[Arm];
    end;
  Node := ds6DBB;
  if Node = Cloud then
    ds6DBB := Node^.Next
  else
    while Node^.Next <> Cloud do
      Node := Node^.Next;
  Node^.Next := Cloud^.Next;
  FreeMem(Cloud, SizeOf(TCombatNode));
  Node := ds6DBB;
  while Node <> nil do
  begin
    for Arm := 1 to 4 do
      if Node^.Arms[Arm] <> 0 then
        CombatMap^.Cells[Node^.Y + DirStepY[ds290D[Arm]], Node^.X + DirStepX[ds290D[Arm]]] := CloudTile;
    Node := Node^.Next;
  end;
end;
{ ovl12:0FAC. Called by ovl12:1086 (AvoidIfSelectedItemPlusZero) and two more routines (ovl12:2901, 2BC8).
  When SelectedCharacter has an item in its first slot (SlotItems[0]) and res12_fn_255B (the distance from
  SelectedCharacter to Who, 1 when adjacent [I]) is above 1, a roll of 1d100 at or below Chance avoids the attack:
  "Avoids it" is shown on Who (colour 10), the damage becomes 0, the attack roll MissRoll and ds6823 goes
  down by one. Purpose unknown: the kind of attack is not known [?]. }
procedure AvoidDistantAttack(Who: PCharacter; Chance: Byte);
begin
  if SelectedCharacter^.SlotItems[0] <> nil then
    if res12_fn_255B(SelectedCharacter, Who) > 1 then
      if RollDice(1, 100) <= Chance then
      begin
        res12_fn_16EC(Who, 'Avoids it', $A, 1);
        DamageAmount := 0;
        AttackRoll := MissRoll;
        Dec(ds6823);
      end;
end;
{ ovl12:101D. The item Who keeps in its first slot (SlotItems[0], TCharacter +$CC; the 13 slots are the items the
  character remembers, POOLVARS), or nil when the slot is empty. When there is a slot item, res12_fn_2E8B (Who, Item)
  runs first: its Item is kept when it returns nonzero and gives a non-nil item, otherwise the slot item is the result.
  Purpose unknown: what res12_fn_2E8B finds is not known yet [?]. }
function FirstSlotItem(Who: PCharacter): PItem;
var
  Item: Pointer;                { a Pointer, the var parameter of res12_fn_2E8B }
  Found: Byte;                  { the result of res12_fn_2E8B }
begin
  Item := nil;
  if Who^.SlotItems[0] <> nil then
  begin
    Found := res12_fn_2E8B(Who, Item);
    if (Found = 0) or (Item = nil) then
      Item := Who^.SlotItems[0];
  end;
  FirstSlotItem := PItem(Item);
end;
{ ovl12:1086. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). When the
  selected character's first remembered item (FirstSlotItem) has Plus 0, Who avoids the attack in progress at once
  (AvoidDistantAttack with AlwaysAvoids). Which affect runs it is not known yet [?]. }
procedure AvoidIfSelectedItemPlusZero(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if FirstSlotItem(SelectedCharacter) <> nil then
    if FirstSlotItem(SelectedCharacter)^.Plus = 0 then
      AvoidDistantAttack(Who, AlwaysAvoids);
end;
{ ovl12:10C1. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It halves
  ds681A, the byte that AgeCharacterOnce (ovl12:0C4B) doubles every time it runs. Which affect runs it is not known
  yet [?]. }
procedure HalveAgeDoubling(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  ds681A := ds681A shr 1;
end;
{ ovl12:10DE. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It gives Who
  the affect AffectUnknown2B (a Cure Disease affect, ovl04:031E) for WeakeningDuration rounds with the Data of Affect,
  when TryAddAffect allows it. While Who's Strength is above 3 each run shows "is weakened" (colour 10) and takes one
  off Strength; at 3 or less Who gets AffectNausea unless it has it already. Which affect runs it is not known yet [?]. }
procedure WeakenStrength(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  FoundAffect: Pointer;
begin
  if TryAddAffect(Who, AffectUnknown2B, Affect^.Data, WeakeningDuration) then
    if Who^.Strength > 3 then
    begin
      res12_fn_16EC(Who, 'is weakened', $A, 1);
      Dec(Who^.Strength);
    end
    else if not res12_fn_2199(Who, AffectNausea, FoundAffect) then
      AddAffect(Who, AffectNausea, 0, $FF, 0);
end;
{ ovl12:1168. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It gives Who
  the disease affect AffectCauseDisease for AffectCauseDiseaseDuration rounds, with the Data of Affect, when TryAddAffect
  allows it. Then, while Who has more than one hit point (Flag11B), it deals 1 point of plain damage (DamageKind 0, no
  save, DealDamage) and, outside combat, redraws the selected character. Otherwise Who gets AffectNausea unless it has
  it already. Which affect id runs it is not known yet [?]. }
procedure CauseDiseaseAndDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  FoundAffect: Pointer;
begin
  if TryAddAffect(Who, AffectCauseDisease, Affect^.Data, AffectCauseDiseaseDuration) then
    if Who^.Flag11B > 1 then
    begin
      DamageKind := 0;
      DealDamage(Who, 1, 0, False);
      if ds49F3 <> CombatViewMode then
        res12_fn_0767(SelectedCharacter);
    end
    else if not res12_fn_2199(Who, AffectNausea, FoundAffect) then
      AddAffect(Who, AffectNausea, 0, $FF, 0);
end;
{ ovl12:11F9. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It copies
  the character Who attacked last (Who's combat Target, TCombatant at +$108 of Who, MeleeAttack sets it in ovl08) into
  AttackTarget. When the selected character has Pad9E[$9F] (+$9F of TCharacter, not named yet) set to 1 and its
  CombatSize has footprint kind 2 (bits 0..6 of +$6C), AttackRoll loses AttackPenalty for each of the names ds0402[1..8]
  that the target's name equals. Which affect runs it is not known yet [?]. }
procedure LowerAttackVsEightListed(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  I: Byte;                      { the name row 1..8 of ds0402 }
begin
  AttackTarget := Who^.Combat^.Target;
  if (SelectedCharacter^.Pad9E[$9F] = 1) and ((SelectedCharacter^.CombatSize and CombatKindMask) = 2) then
    for I := 1 to 8 do
      if AttackTarget^.Name = ds0402[I] then
        Dec(AttackRoll, AttackPenalty);
end;
{ ovl12:1276. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). When the selected
  character has Pad9E[$9F] (+$9F of TCharacter, not named yet) set to 1 and its name is 'BUGBEAR' or 'GNOLL', AttackRoll
  loses AttackPenalty. Which affect runs it is not known yet [?]. }
procedure LowerAttackIfSelectedIsBugbearOrGnoll(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if SelectedCharacter^.Pad9E[$9F] = 1 then
    if (SelectedCharacter^.Name = 'BUGBEAR') or (SelectedCharacter^.Name = 'GNOLL') then
      Dec(AttackRoll, AttackPenalty);
end;
{ ovl12:12B2. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is passed on, ovl24:0000). The side
  the affect names is Affect's Data bit 4 (SideDataBit, 0 or 1). When Who's Side (+$10E of TCharacter) equals it,
  RaiseAttackAndSave (ovl12:0C06) runs with Who, Affect and Mode; otherwise AttackRoll and SaveRoll each lose one.
  Which affect runs it is not known yet [?]. }
procedure RaiseOrLowerAttackAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Side: Byte;                   { the side bit of Affect's Data, 0 or 1 }
begin
  Side := (Affect^.Data and SideDataBit) div 16;
  if Who^.Side = Side then
    RaiseAttackAndSave(Who, Affect, Mode)
  else
  begin
    Dec(AttackRoll);
    Dec(SaveRoll);
  end;
end;
{ ovl12:12FB. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It gives Who
  the healing block AffectHealingBlock (ovl24:175D: HealCharacter with Flag 0 does nothing while it is there) for
  AffectHealingBlockDuration rounds, with the Data of Affect, when TryAddAffect allows it. Then HealCharacter heals Who
  by one hit point with Flag 1, which the block does not stop, and when that healed Who, res12_fn_234A (00BA:234A, not
  named yet) runs on Who. The map also had an entry at ovl12:1307, which is the middle of this routine (its pushes
  for the first call start at 12FB), so it has no routine of its own. Which affect runs it is not known yet [?]. }
procedure AddHealingBlockAndHeal(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if TryAddAffect(Who, AffectHealingBlock, Affect^.Data, AffectHealingBlockDuration) then
    if HealCharacter(Who, 1, 1) then
      res12_fn_234A(Who);
end;
{ ovl12:133F. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It calls
  res12_fn_2637(Who), the routine the combat units call to end a combatant's turn (ovl08, ovl09 AiTurn), and does
  nothing with its result: a Turbo Pascal statement cannot call a function, so the call is tested and the test
  stands alone. Purpose unknown: which affect runs it is not known yet [?]. }
procedure ovl12_e43(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if res12_fn_2637(Who) <> 0 then ;
end;
{ ovl12:1355. Affect handler (the AffectHandlers shape: Who, Affect and Mode) with an empty body, like IgnoreAffect
  (ovl12:0647): none of its parameters is read and no global is written. Purpose unknown: which affect runs it is
  not known yet [?]. }
procedure ovl12_e44(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
end;
{ ovl12:135C. Affect handler (the AffectHandlers shape: Who, Affect and Mode) with an empty body, like IgnoreAffect
  (ovl12:0647): none of its parameters is read and no global is written. Purpose unknown: which affect runs it is
  not known yet [?]. }
procedure ovl12_e45(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
end;
{ ovl12:1363. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It gives Who the
  affect AffectUnknown19 (ovl24:0E52, AddAffect) for AffectUnknown19Duration rounds with the Data AffectUnknown19Data,
  with NoRemoveHandler: the handler does not run when the affect is removed. AffectUnknown19 is the affect RollToHit
  clears from the attacker (ovl24:0CB7) [I]. Purpose unknown: which affect runs it is not known yet [?]. }
procedure ovl12_e46(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  AddAffect(Who, AffectUnknown19, AffectUnknown19Duration, AffectUnknown19Data, NoRemoveHandler);
end;
{ ovl12:1399. Affect handler of the rot (AffectHandlers shape: Who, Affect and Mode; Mode not read; the affect is
  AffectRot, $39, which Cure Disease removes, whitepaper 5.19). Does nothing while the Temple removes affects (ds681F
  is not 0, ovl04:0386). Otherwise it shows "Rots..." on Who (colour 10) and takes RotCharismaLoss off Who's Charisma
  (+$15), never below RotMinimumCharisma. Then the rot moves on: while the stage (the high nibble of the affect's
  Data) is above RotLastStage, the stage drops by one (RotStage) and TryAddAffect gives Who the rot again with that
  Data for RotDuration rounds. At the last stage Who dies: DropFromFight takes Who out with StatusRotted and the
  text "Dies rots away". }
procedure ProgressRot(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if ds681F <> 0 then Exit;
  res12_fn_16EC(Who, 'Rots...', $A, 1);
  if Who^.Charisma > RotCharismaLoss then
    Dec(Who^.Charisma, RotCharismaLoss)
  else
    Who^.Charisma := 0;
  if Who^.Charisma < RotMinimumCharisma then
    Who^.Charisma := RotMinimumCharisma;
  if Affect^.Data div 16 > RotLastStage then
  begin
    Dec(Affect^.Data, RotStage);
    if TryAddAffect(Who, AffectRot, Affect^.Data, RotDuration) then ;
  end
  else
    DropFromFight(Who, StatusRotted, 'Dies rots away');
end;
{ ovl12:1452. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It stops Who's
  movement: the combat record's Moves (+$6 of TCombatant, the movement left) goes to 0. When ds681D is not 0 it also
  clears ds681A, the byte AgeCharacterOnce doubles. Purpose unknown: which affect runs it is not known yet [?]. }
procedure ovl12_e48(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Who^.Combat^.Moves := 0;
  if ds681D <> 0 then
    ds681A := 0;
end;
{ ovl12:1472. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It gives Who the affect
  AffectUnknown62 (AddAffect, ovl24:0E52) with Duration 0 (permanent), the Data AffectUnknown62Data and no handler
  when it is removed (NoRemoveHandler). Purpose unknown: which affect runs it is not known yet [?]. }
procedure ovl12_e49(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  AddAffect(Who, AffectUnknown62, 0, AffectUnknown62Data, NoRemoveHandler);
end;
{ ovl12:1490. Damage hook (the AffectHandlers shape: Who, Affect and Mode; none of them read). While the damage is fire
  (DamageKind bit KindFire, DS:6819), each of the ds681C dice of the last roll takes FireReductionPerDie off
  DamageAmount, and it never goes below ds681C; SaveRoll then gets FireProtectionSaveBonus. Damage that is not
  magical (KindMagic clear) is cancelled altogether: CancelPendingHook(0) clears DamageAmount and HookAffectId.
  Purpose unknown: which affect runs it is not known yet [?]. }
procedure ReduceFireDamageByRoll(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  I: Byte;
begin
  if (DamageKind and KindFire) <> 0 then
  begin
    for I := 1 to ds681C do
    begin
      Dec(DamageAmount, FireReductionPerDie);
      if DamageAmount < ds681C then
        DamageAmount := ds681C;
    end;
    Inc(SaveRoll, FireProtectionSaveBonus);
    if (DamageKind and KindMagic) = 0 then
      CancelPendingHook(0);
  end;
end;
{ ovl12:14EB. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode not read), the same shape as
  AddHealingBlockAndHeal (ovl12:12FB) with the trained-out affect: it gives Who AffectTrainedOut (the Constitution
  limit affect of TrainConstitution, ovl12:0233) for TrainedOutDuration rounds with the Data of Affect, when TryAddAffect
  allows it. Then HealCharacter heals Who by one hit point with Flag 1, which a healing block does not stop, and when
  that healed Who, res12_fn_234A (00BA:234A, not named yet) runs on Who. Which affect runs it is not known yet [?]. }
procedure AddTrainedOutAndHeal(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if TryAddAffect(Who, AffectTrainedOut, Affect^.Data, TrainedOutDuration) then
    if HealCharacter(Who, 1, 1) then
      res12_fn_234A(Who);
end;
{ ovl12:1545. Poison hook of an attack (the frame is Who and Bonus; Bonus is the save bonus, 0 in
  PoisonAttackTargetBonus0's call at ovl12:166A). AttackTarget becomes Who's Combat^.Target, the character Who
  attacked last. That character makes a poison save (SaveKindPoison, with Bonus). When it fails, "is Poisoned"
  (colour 10) is shown on it, DelayByGameSpeed waits, it
  gets AffectPoisoned for good (AddAffect with Duration 0, Data $FF, no handler on removal) and DropFromFight kills it
  with StatusGone and "is killed". The map split this routine at ovl12:1543 and ovl12:1583, which are inside its
  literal pool and inside its code. Which affect runs it is not known yet [?]. }
procedure PoisonAttackTarget(Who: PCharacter; Bonus: ShortInt);
begin
  AttackTarget := Who^.Combat^.Target;
  if not SavingThrow(AttackTarget, SaveKindPoison, Bonus) then
  begin
    res12_fn_16EC(AttackTarget, 'is Poisoned', $A, 0);
    DelayByGameSpeed;
    AddAffect(AttackTarget, AffectPoisoned, 0, $FF, NoRemoveHandler);
    DropFromFight(AttackTarget, StatusGone, 'is killed');
  end;
end;
{ ovl12:15EB. Paralyses the character Who attacked last. AttackTarget takes Who's combat Target (TCombatant +$A) and
  it makes the paralysis save (SavingThrow kind SaveKindParalysis, bonus 0). Unless it saves, "is Paralyzed" is shown
  on it (res12_fn_1FEB, flag 1, as ApplyAffect shows an affect's message) and it gets the affect AffectParalysis for
  Duration rounds with Data ParalysisData, with no handler when it is removed (NoRemoveHandler). Parameters: Who is the
  attacker, Duration the rounds (the callers pass a roll or 63). Unused is the third byte: both callers push 0 and this
  routine never reads it. }
procedure ParalyzeAttackTarget(Who: PCharacter; Duration: Word; Unused: Byte);
begin
  AttackTarget := Who^.Combat^.Target;
  if not SavingThrow(AttackTarget, SaveKindParalysis, 0) then
  begin
    res12_fn_1FEB(AttackTarget, 1, 'is Paralyzed');
    AddAffect(AttackTarget, AffectParalysis, Duration, ParalysisData, NoRemoveHandler);
  end;
end;
{ ovl12:165D. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  The poison hook of an attack with save bonus 0: PoisonAttackTarget (ovl12:1545) with Bonus 0. Which affect runs it
  is not known yet [?]. }
procedure PoisonAttackTargetBonus0(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  PoisonAttackTarget(Who, 0);
end;
{ ovl12:1671. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  The poison hook of an attack with save bonus 4: PoisonAttackTarget (ovl12:1545) with Bonus 4. Which affect runs it
  is not known yet [?]. }
procedure PoisonAttackTargetBonus4(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  PoisonAttackTarget(Who, 4);
end;
{ ovl12:1685. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  The poison hook of an attack with save bonus 2: PoisonAttackTarget (ovl12:1545) with Bonus 2. Which affect runs it
  is not known yet [?]. }
procedure PoisonAttackTargetBonus2(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  PoisonAttackTarget(Who, 2);
end;
{ ovl12:1699. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  It paralyses the character Who attacked last for RollDice(2, 8) rounds: ParalyzeAttackTarget (ovl12:15EB) with the
  unused byte 0. No caller is in the map (auto:entry_55), so the affect that runs it is not known yet [?]. }
procedure ParalyzeAttackTargetFor2d8(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  ParalyzeAttackTarget(Who, RollDice(2, 8), 0);
end;
{ ovl12:16BB. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  Unless the character Who attacked last (Who^.Combat^.Target) has race ParalysisImmuneRace, it is paralysed for
  ParalysisDuration rounds: ParalyzeAttackTarget (ovl12:15EB) with the unused byte 0. The map finds no direct caller
  (auto:entry_56), so the affect that runs it is not known yet [?]. }
procedure ParalyzeAttackTargetUnlessImmune(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if Who^.Combat^.Target^.Race <> ParalysisImmuneRace then
    ParalyzeAttackTarget(Who, ParalysisDuration, 0);
end;
{ ovl12:16E6. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  Paralyses the character Who attacked last for 1d9 plus ParalysisBaseRounds rounds: ParalyzeAttackTarget (ovl12:15EB).
  Which affect runs it is not known yet [?]. }
procedure ParalyzeAttackTargetFor1d9Plus10(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  { the third argument is the unused byte: ParalyzeAttackTarget never reads it; this caller passes $FE, the others 0 }
  ParalyzeAttackTarget(Who, RollDice(1, ParalysisDieSides) + ParalysisBaseRounds, $FE);
end;
{ ovl12:170B. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  The poison hook of an attack with save bonus -2: PoisonAttackTarget (ovl12:1545) with Bonus -2. Which affect runs it
  is not known yet [?]. }
procedure PoisonAttackTargetBonusMinus2(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  PoisonAttackTarget(Who, -2);
end;
{ ovl12:171F. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). Sets
  ds681E to 1 (the flag ovl12:0918 and ovl12:0C26 also set; nothing reads it yet) and takes AttackPenalty off AttackRoll
  without the test LowerAttackRollByFour (ovl12:0918) makes first. Which affect runs it is not known yet [?]. }
procedure SetFlagAndLowerAttackRollByFour(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  ds681E := 1;
  Dec(AttackRoll, AttackPenalty);
end;
{ ovl12:1730. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). When a 1d100 roll
  is at or below AffectUnknown19Chance it gives Who affect AffectUnknown19 (AddAffect, ovl24:0E52) for
  AffectUnknown19Duration rounds with the Data AffectUnknown19Data and no handler when it is removed: the same AddAffect
  as ovl12_e46 (ovl12:1363), but with the roll. Purpose unknown: which affect runs it is not known yet [?]. }
procedure ovl12_e60(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if RollDice(1, 100) <= AffectUnknown19Chance then
    AddAffect(Who, AffectUnknown19, AffectUnknown19Duration, AffectUnknown19Data, NoRemoveHandler);
end;
{ ovl12:176F. Affect handler of the blood drain (the AffectHandlers shape: Who, Affect and Mode; Mode 0 applies, any other
  value removes, ovl24:0000). AttackTarget becomes the combatant whose index is the affect's Data (CombatantRecord,
  DS:65BD). When Mode is 0 and Who and that combatant both still take part (Flag10D), Who sucks blood from it: "Sucks some
  Blood" is shown on Who (colour 10), 1d4 damage is dealt to the combatant without a save (RollDiceCounted, DealDamage),
  Who's turn is ended (res12_fn_2637, its result is not read), then the affect's Duration div 16 must stay above the
  damage, which is taken off the Duration (times 16) while the combatant is still in the fight; otherwise affect $4B is
  removed from Who. Else affect $3A is removed from the combatant and, when Mode is 0, the affect's Flag is cleared and
  affect $4B is removed from Who. Last, when both still take part, Who's combat byte Pad10 becomes 1 (CheckMorale forces
  a combatant with it nonzero to flee, ovl09:10D7). Which affect runs it is not known yet [?]. }
procedure DrainBloodFromCombatant(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Turn: Byte;                   { the result of res12_fn_2637 (ends Who's turn), never read }
  Dice: Byte;                   { the damage of the blood sucked }
begin
  AttackTarget := CombatantRecord[Affect^.Data];
  if (Mode <> 0) or (Who^.Flag10D = 0) or (AttackTarget^.Flag10D = 0) then
  begin
    RemoveAffect(AttackTarget, $3A, nil);
    if Mode = 0 then
    begin
      Affect^.Flag := 0;
      RemoveAffect(Who, $4B, Affect);
    end;
    if (Who^.Flag10D <> 0) and (AttackTarget^.Flag10D <> 0) then
      Who^.Combat^.Pad10 := 1;
  end
  else
  begin
    res12_fn_16EC(Who, 'Sucks some Blood', $A, 1);
    Dice := RollDiceCounted(1, 4);
    DamageKind := 0;
    DealDamage(AttackTarget, Dice, 0, False);
    Turn := res12_fn_2637(Who);
    if (AttackTarget^.Flag10D <> 0) and (Affect^.Duration div 16 > Dice) then
      Dec(Affect^.Duration, Dice * 16)
    else
      RemoveAffect(Who, $4B, Affect);
  end;
end;
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
