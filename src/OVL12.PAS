unit OVL12;
{ AffectHandlers: overlay 12, the affect handler unit (InitAffectHandlers fills the AffectHandlers table; two handlers
  train with the
  Manual of Bodily Health), 14510 bytes of code. The loader (ovl11) hands
  over to its entry 1 (the loader section of the whitepaper). Its affect handlers and roll hooks change
  AttackRoll, DamageAmount and the morale scratch MoraleScratch; each routine's comment says what it does.
  L- (no local symbol information) changes no code; without it the matcher's build of every unit
  together runs out of compiler memory (variant B) once this unit is fully decompiled. }
{$A-,O+,F+,S-,R-,G-,I-,L-}
interface
uses POOLVARS, RES06;
procedure CancelPendingHook(AffectId: Byte);
function TryAddAffect(Who: PCharacter; AffectId, Data: Byte; Duration: Word): Boolean;
procedure DropFromFight(Who: PCharacter; NewStatus: Byte; Msg: String40);
procedure InitAffectHandlers;
procedure RaiseAttackAndMorale(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure LowerAttackAndMorale(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure BoostAttackAgainstUndead(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure StartTrainingWithManual(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure BoostFireAttackByTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure TrainConstitution(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ShiftAttackToSaveVsEvil(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ShiftAttackToSaveVsGood(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure HalveColdDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ApplyCharmPerson(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ApplyStrengthAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure SetCharismaFromAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure SlowPoisonDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure IgnoreAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure RaiseResistanceAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure BoostAttackVsKoboldGoblin(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure HalveFireDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ShowSilenceAndStopCasting(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure DieIfPoisoned(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure GiveSpiritualHammer(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure InvisibleTargetHardToHit(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure BoostAttackVsOrcGoblinHobgoblin(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ImageAbsorbsHit(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ReduceDamageByQuarter(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CoughStopsCasting(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CollapseAndChangeSide(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure LowerAttackSaveAndResistance(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure RunDiseaseHandlers(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure RaiseAttackAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure LowerAttackAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure SetAttackMissIfTurnPending(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ApplyHaste(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure AvoidDistantAttack(Who: PCharacter; Chance: Byte);
function FirstSlotItem(Who: PCharacter): PItem;
procedure ClearCloud(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ProtectFromNormalMissiles(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ApplySlow(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure WeakenStrength(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CauseDiseaseAndDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure LowerAttackVsOgreTrollGiant(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure LowerAttackIfSelectedIsBugbearOrGnoll(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure RaiseOrLowerAttackAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure AddHealingBlockAndHeal(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure EndAffectedCombatantTurn(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure IgnoreAffect36(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure IgnoreAffect37(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure GiveInvisibilityForOneRound(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ProgressRot(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure StopMovement(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure GiveRegainHitPointsAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ReduceFireDamageByRoll(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure PoisonAttackTarget(Who: PCharacter; Bonus: ShortInt);
procedure ParalyzeAttackTarget(Who: PCharacter; Duration: Word; Unused: Byte);
procedure AddTrainedOutAndHeal(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure PoisonAttackTargetBonus0(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure PoisonAttackTargetBonus4(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure PoisonAttackTargetBonus2(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ParalyzeAttackTargetFor2d8(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ParalyzeAttackTargetUnlessImmune(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ParalyzeAttackTargetFor1d9Plus10(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure PoisonAttackTargetBonusMinus2(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure InvisibleTargetCannotBeTargeted(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CamouflageGivesInvisibility(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure DrainBloodFromCombatant(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure StartBloodDrain(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure HoldWeakTargetFast(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ReviveOrRetryRevival(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure FireAttackTargetFor2d10(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure AcidAttackTargetFor1d4(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure FrightenSideWithFear(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ParalyzeSideWithFear(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure GazeStonesTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure DrainLevels(Who: PCharacter; Count: Byte);
procedure GazeCharmsTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure DrainAttackTargetLevel(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure DrainAttackTargetTwoLevels(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CauseRotOnAttackTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ForceFirstAttackMiss(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure DwarfHalflingPoisonSaveBonus(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ImmuneToMagicMissileAndElectricity(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure HalveFireDamageNoSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure HalveDamageForFirstSlotItem(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure FallDeadIfInFight(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CancelDamageUnlessMagicSlotItem(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure DwarfGnomeHalflingWandSpellSaveBonus(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure RegainHitPoints(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ReviveDyingCharacter(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure GiveAffectUnlessFireOrAcid(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure GiveRegeneratingUnlessAffected(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure RetryRevivalAtFullHitPoints(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure TurnGaseousAndEscape(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure RollMagicResistance(Chance: Byte);
procedure AvoidDistantAttackByChance(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CancelHookByHalfChance(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CancelHookByLowChance(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ElfResistsCharmAndSleep(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ImmuneToCharmAndSleep(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CancelParalysisHook(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CancelColdDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CancelPoisonAndParalysisHooks(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CancelFireDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ReduceFireDamageOnePerDie(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure HalveElectricityDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure HalveDamageByFirstSlotItemRow(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure HalveDamageForEnchantedSlotItem(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure SetDamageFromHolyWater(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure HalveColdDamageNoSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure CancelDamageUnlessEnchantedSlotItem(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure AvoidDistantAttackForBoulder(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure SpitAcidAtTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure SetDamageFromOilFlask(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure HalveOrCancelDamageForUnenchantedSlotItem(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure HalfElfResistsCharmAndSleep(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ImmuneToCharmSleepHoldAndPoison(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure VetoTargetWithMirrorOrWoodenHolySymbol(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure ApplyItemSecondAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure GiveExceptionalStrength(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure AlignmentBoundWeaponHurtsOthers(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure RequireGiantStrength(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure EndSpiritualHammerWhenHammerRemoved(Who: PCharacter; Affect: PAffect; Mode: Byte);
procedure IgnoreAffectShared(Who: PCharacter; Affect: PAffect; Mode: Byte);
implementation
uses RES12, OVL13, OVL23, OVL24, OVL30, OVL31, OVL33;
const
  MoraleStep = 5;               { what the affect handlers add to or take from the morale scratch MoraleScratch }
  TargetBonus = 2;              { what BoostAttackAgainstUndead adds to AttackRoll and to DamageAmount }
  TrainingManualDuration = 43200; { $A8C0: the Duration ovl12:017F gives the affect }
  TrainingManualData = $FF;     { the Data byte ovl12:017F gives the affect }
  TrainingConstitution = 15;    { training needs at least this Constitution; a fighter level counts Constitution - 15,
                                  a non-fighter level counts twice above it (the same rule as Raise Dead, ovl04:0510) }
  FighterOnlyConstitution = 17; { from 17 up only a fighter level keeps the training gain (ovl04 uses the same limit) }
  LastClass = 7;
  ConstitutionLimit = 20;       { training that takes Constitution to 20 gives AffectTrainedOut and stops }
  AffectTrainedOut = $3E;  { id 62: AddTrainedOutAndHeal (ovl12:14EB) runs for it; TrainConstitution (ovl12:0233) gives it at
  ConstitutionLimit }
  TrainedOutDuration = $3C;
  TrainedOutData = $FF;
  KindCold = 2;                 { the DamageKind bit of cold damage (ovl24:13E4, the text 'from Cold') }
  ColdSaveBonus = 3;            { what a cold hit adds to SaveRoll (ovl12:03E1) }
  KindFire = 1;                 { the DamageKind bit of fire damage (POOLVARS DamageKind: 1 fire) }
  KindMagic = 8;                { the DamageKind bit of magical damage (POOLVARS DamageKind: bit 3 magic) }
  KindAcid = $10;               { the DamageKind of acid damage (POOLVARS DamageKind: $10 acid) }
  KindElectricity = 4;          { the DamageKind bit of electricity damage (POOLVARS DamageKind: 4 electricity; ovl12:2556) }
  FireSaveBonus = 3;            { what a fire hit adds to SaveRoll (ovl12:06E4) }
  FireReductionPerDie = 2;      { what each die of the last roll takes off fire damage (ovl12:1490) }
  FireProtectionSaveBonus = 4;  { what the fire damage hook (ovl12:1490) adds to SaveRoll }
  ControlAppliedBit = $20;      { Affect.Data bit 5: set once the control is applied (ovl12:0400) }
  ControlSavedSideBit = $40;    { Affect.Data bit 6: the side Who had before; removing the affect gives it back }
  ControlSideBit = $80;         { Affect.Data bit 7: the side the control gives Who (TCharacter.Side) }
  ComputerRunMorale = $B3;      { TCharacter.B84 of a computer-run member: the flag and morale $33 }
  AffectMorale = 100;           { what applying the control sets the morale scratch MoraleScratch to }
  ExceptionalPercent = 100;     { the percentile of 18/100, the strength ovl12:2F57 raises Who to }
  GiantStrength = 19;           { the lowest Strength of the giant range 19..25 (whitepaper 5.24, StrengthRowIndex) }
  HolySymbolNameNum = $98;      { NameNum of every Holy Symbol of any god in the item files [V]; with WoodenNameNum as
    the third name: the Wooden Holy Symbol
                                  of Tyr, which sets HookVetoFlag (ovl12:2E37) }
  WoodenNameNum = $FC;          { NameNum[3] Wooden [V item files] }
  ItemAffectData = $0C;         { the Data byte ovl12:2EDA gives the affect an item names in Affects[2] }
  SaveKindParalysis = 0;        { the same kind 0 for the paralysis save of ovl12:15EB [I] (the first of the five saves) }
  AffectParalysis = $34;        { the affect of "is Paralyzed" (ovl12:15EB): a spell affect that ovl15 names by its spell [I]
  }
  ParalysisData = $0C;          { the Data byte ovl12:15EB gives the paralysis affect }
  ParalysisDuration = $3F;      { the rounds ovl12:16BB paralyses for (63) }
  ParalysisDieSides = 9;        { ovl12:16E6 paralyses for 1d9 plus ParalysisBaseRounds rounds }
  ParalysisBaseRounds = 10;
  SlowPoisonDamageDuration = 10;  { the Duration SlowPoisonDamage (ovl12:05EB) gives the affect }
  AttackPenalty = 4;            { what ovl12:0918, 0BAC, 0C15, 11F9 and 1276 take off AttackRoll }
  SavePenalty = 4;              { what ovl12:0BAC and 0C15 take off SaveRoll }
  ResistPenalty = 4;            { what ovl12:0BAC takes off Who's ArmourClassValue and RearArmourClassValue }
  MissRoll = -1;                { AttackRoll below 0 is a miss (RollToHit, ovl24:0CD5); ovl12:0C26 sets it }
  AgedBit = $10;                { Affect.Data bit 4: set once the affect has aged Who (ovl12:0C4B) }
  MissedBit = $10;              { Affect.Data bit 4 again, set by ovl12:2490 once it has made the attack roll a miss [?] }
  DataLowNibble = $0F;          { the low nibble of Affect.Data, the part ovl12:2490 keeps in the first case }
  AffectImages = $1C;           { the images affect: runs on the damage hook (kind 6, ovl24:02FA); Data counts the images [I]
  }
  AffectDrainsStrength = $2B;  { id 43: WeakenStrength (ovl12:10DE) runs for it: each run takes one off Strength; a Cure
  Disease affect (ovl04:031E), run by RunDiseaseHandlers }
  AffectCauseDiseaseDuration = 10; { the Duration ovl12:1168 gives affect AffectCauseDisease }
  MummyDiseaseDuration = 14400; { $3840: the Duration ovl12:12FB gives affect AffectMummyDisease }
  HealingBlockData = $FF;       { the Data byte ovl12:23EC gives AffectMummyDisease }
  SideDataBit = $10;            { Affect.Data bit 4: a side, 0 or 1, compared with Who's Side (ovl12:12B2) }
  CombatKindMask = $7F;         { TCharacter.CombatSize bits 0..6: the combat footprint kind (POOLVARS, +$6C) }
  CoughResistLimit = 52;        { ovl12:0A65: TCharacter.RearArmourClassValue above this steps down by CoughResistStep,
                                  else it is set to CoughResistReset }
  CoughResistReset = 50;
  CoughResistStep = 2;
  MinimumResistance = $39;      { ovl12:064E raises ArmourClassValue (+$111) to at least this (57 = AC 3) }
  HammerItemType = $14;          { TMenuLine.ItemType of the item the affect gives (ovl12:07E0) }
  GivenItemNameNum2 = $14;      { NameNum[2] of that item }
  GivenItemNameNum3 = $F3;      { NameNum[3] of that item; the search of Who's items uses it too (ovl12:07E0) }
  GivenItemPlus = 1;            { Plus of that item }
  GivenItemAffect2 = $17;       { Affects[2] of that item }
  GivenItemAffect3 = $89;       { Affects[3] of that item }
  ItemCountLimit = $10;         { no item is given once ItemCountC7 is this or more (ovl12:07E0 at 0869) [I] }
  ItemRowFlags = $81;           { bits 0 and 7 of byte 7 of an item type's ItemTable row, tested by ovl12:25BC [?] }
  SilverNameNum = $B1;       { NameNum[3] of the item that keeps the damage at ovl12:264B and ovl12:2D88 [?] }
  BodyTile = $1F;          { the tile a cloud arm gets where a body lies when the cloud clears (ovl12:0CC3) [?] }
  WeakeningDuration = $3C;      { the Duration ovl12:10DE gives the affect AffectDrainsStrength }
  AlwaysAvoids = 100;           { the Chance that avoids every roll of 1d100 (ovl12:1086) }
  AlwaysSaves = 100;            { the SaveRoll that makes a saving throw succeed (ovl24:0D63 succeeds when it reaches) [I] }
  DistantAvoidChance = 60;      { the Chance ovl12:2901 gives AvoidDistantAttack }
  SlotItemAvoidChance = 50;     { the Chance ovl12:2BC8 gives AvoidDistantAttack for a first slot item of type $57 or $58 }
  SpitChance = 25;              { the 1d100 roll at or below which Who spits acid (ovl12:2C1C) [?] }
  SpitMaxDistance = 4;          { DistanceToTarget (the distance to the target [I]) must be below this for a spit }
  SpitAnimation = $17;          { the argument of DrawCombatIcon that ovl12:2C1C shows the spit with [?] }
  SpitLineKind = 1;             { the Kind of the spit line WalkCombatLine draws (ovl12:2C1C) [?] }
  SpitLineFlag = 30;            { the Flag of that line }
  AffectSpitsAcid = $79;  { id 121: SpitAcidAtTarget (ovl12:2C1C) runs for it; the spit removes it from Who once it has spat }
  AffectSplashesAcid = $50;  { id 80: AcidAttackTargetFor1d4 (ovl12:1A4C) runs for it: acid, 1d4; the spit (ovl12:2C1C)
  removes it from Who too }
  HookChanceHalf = 50;          { the Chance ovl12:2976 gives ovl12:2915 (the hook cancel with a roll) }
  HookChanceLow = 15;           { the Chance ovl12:2984 gives ovl12:2915 }
  ElfCharmSleepResistance = 90;          { the 1d100 roll at or below which ovl12:2992 cancels its hooks }
  HalfElfCharmSleepResistance = 30;      { the 1d100 roll at or below which ovl12:2DE4 cancels the
    charm's and AffectEndsTurn's hooks
  }
  InvisibilityDuration = 1;  { the Duration ovl12:1363 gives affect AffectInvisibility }
  InvisibilityData = $0C;    { the Data byte ovl12:1363 gives affect AffectInvisibility }
  CamouflageInvisibilityChance = 95;   { ovl12:1730 gives affect AffectInvisibility when a 1d100 roll is at or
  below this }
  AffectRegainHitPoints = $62;  { id 98: RegainHitPoints (ovl12:2700) runs for it; GiveRegainHitPointsAffect
    (ovl12:1472, id 59) gives it }
  AffectRegainHitPointsData = $FF;    { the Data byte ovl12:1472 gives affect AffectRegainHitPoints }
  AffectRot = $39;              { the rot affect: Cure Disease removes it (whitepaper 5.19 table, DS:0114) }
  RotDuration = 43200;          { $A8C0: the Duration the rot handler (ovl12:1399) gives the next rot }
  RotStage = $10;               { one stage of the rot: the rot handler takes it off the affect's Data high nibble }
  RotDataLow = $0F;             { the low nibble of a new rot's Data (ovl12:23EC), kept by ProgressRot [?] }
  RotLastStage = 1;             { a rot whose stage is this or lower kills its victim (the rot handler, ovl12:1399) }
  RotCharismaLoss = 2;          { what each run of the rot handler (ovl12:1399) takes off Charisma }
  RotMinimumCharisma = 3;       { Charisma is not taken below this by the rot handler (ovl12:1399) }
  BloodDrainDuration = $CF;     { the Duration ovl12:18B5 gives AffectBloodDrain (207) }
  HeldFastData = $FF;           { the Data byte the blood drain gives AffectHeldFast }
  HeldFastDuration = 0;         { the Duration the blood drain gives AffectHeldFast }
  HeldFastStrengthLimit = $13;  { a target whose Strength (TCharacter +$10) is below this is held fast (ovl12:1935) }
  ForcedAttackDuration = 0;   { the Duration ovl12:1935 gives AffectForcedAttack }
  RevivalRetryDuration = 1;     { the Duration ovl12:19D9 gives AffectRevival }
  AffectCurse = $02;  { id 2: LowerAttackAndMorale (ovl12:011D) runs for it; FrightenSideWithFear (ovl12:1AAA) gives it
  for 'is weakened by fear' }
  FearData = $0C;               { the Data byte ovl12:1AAA gives both fear affects }
  SaveNegatesAffect = 1;        { ApplyAffect's SaveNegates: a successful save makes the affect fail (ovl24:1656) }
  AffectParalyzeSide = $52;  { id 82: ParalyzeSideWithFear (ovl12:1BA8) runs for it; that handler takes it off every party
  member first }
  FearDieSides = 4;             { ovl12:1BA8 paralyses a member with fear for 1d4 rounds }
  AffectGazeReflectable = $7F;  { id 127: IgnoreAffectShared runs for it and does nothing; the marker of a gaze that a
    Mirror can turn back, carried only by the BASILISK and the MEDUSA [V monster data, I meaning]: the gazer
    must have it
  (ovl12:1CAD) for a reflection to be looked for }
  MirrorNameNum = $76;          { NameNum[2] of the Silver Mirror and the Brass Mirror in the item files [V]: turns a
    gaze back (ovl12:1CAD) }
  GazeAnimation = $12;          { the argument of DrawCombatIcon that ovl12:1CAD shows the gaze with [?] }
  GazeLineKind = 4;             { the Kind and Flag of the gaze lines WalkCombatLine draws (ovl12:1CAD) [?] }
  GazeLineFlag = $2D;
  AffectCharm = $0B;            { the affect of "is charmed" (ovl12:1E77 gives it) [I] }
  CharmData = $0C;              { the low bits of the charm's Data (ovl12:1E77); bit 7 is the side of the gazer [?] }
  CharmSaveBonus = -2;          { what ovl12:1E77 takes off the fear save of the charmed character }
  AffectEndsTurn = $35;  { id 53: EndAffectedCombatantTurn (ovl12:133F) runs for it: it ends the affected
    combatant's turn (EndCombatTurn);
  ids 31, 51 and 52 share that handler; its hook is cancelled with the charm's (ovl12:2992, 29B6) }
  RegainedHitPoints = 3;        { what RegainHitPoints (ovl12:2700) adds to the current hit points }
  DyingRevivalPoints = 6;       { ovl12:2730: a revived dying character gets this many hit points less its DyingRounds }
  RegeneratingDuration = 3;     { the Duration ovl12:2814 gives AffectRegenerating }
  AffectFallsDead = $5F;  { id 95: FallDeadIfInFight (ovl12:2610) runs for it: a character still in the fight falls dead when
  it is removed; ovl12:2730 gives it to a revived character }
  AffectFallsDeadDieSides = 4;  { ovl12:2730 gives AffectFallsDead 1d4 plus one rounds }
  AffectReviveDying = $63;  { id 99: ReviveDyingCharacter (ovl12:2730) runs for it and removes it when the character is
  revived }
  AffectRetryRevival = $66;  { id 102: RetryRevivalAtFullHitPoints (ovl12:2866) runs for it and gives it again when the
  revival fails; GiveAffectUnlessFireOrAcid (ovl12:27D9, id 100) gives it too }
  AffectRetryRevivalDice = 3;      { ovl12:27D9 gives AffectRetryRevival 3d6 rounds: the number of dice }
  AffectRetryRevivalSides = 6;     { the sides of those dice }
  AffectRetryRevivalRetryDuration = 1; { the Duration ovl12:2866 gives AffectRetryRevival }
  LowNibble = $0F;              { the low nibble of a byte }
  ReflectRow = $C;              { the row of the message and the gaze line when a gaze is reflected (ovl12:1CAD) }
  DataFF = $FF;                 { a Data byte of $FF that several affects here are given; its meaning is not known [?] }
  { BoostFireAttackByTarget: the bonus a fire attack gets against a CreatureType (POOLVARS Creature*): trolls 1,
    stirges 2 and undead 3. Why these is not known [?]. CreatureType 9, which it also tests, belongs to no monster. }
  CreatureTypeNine = 9;
  FireBonusForTroll = 1;        { what BoostFireAttackByTarget adds to AttackRoll and DamageAmount for CreatureTroll }
  FireBonusForStirgeNine = 2;   { the same for CreatureStirge and CreatureTypeNine }
  FireBonusForUndead = 3;       { the same for CreatureUndead }
  ProtectionShift = 2;          { what ShiftAttackToSaveVsEvil and ShiftAttackToSaveVsGood move from AttackRoll to SaveRoll }
  SmallFootprintKind = 1;       { the CombatSize of the humanoids of the kobold and orc name lists [I] }
  LargeFootprintKind = 2;       { the CombatSize kind of the ogres, trolls and giants of OgreTrollGiantNames [I] }
  KoboldGoblinNameCount = 4;    { KoboldGoblinNames[1..4] }
  OrcGoblinHobgoblinNameCount = 8;
  OgreTrollGiantNameCount = 8;
  AnimatedBaseMovement = 12;    { the BaseMovement CollapseAndChangeSide gives the creature that returns to its own side }
  SideShift = 16;               { ovl22 stores Side * 16 + caster level in an Animate Dead affect's Data }
  MinimumStrength = 3;          { WeakenStrength takes no more off Strength than this; at it the target is helpless }
  FearParalysisMaxLevel = 3;    { FrightenSideWithFear: a HighestLevel of 0..3 is paralyzed with fear }
  FearWeakenMinLevel = 4;       { and one of 4 or 5 is weakened by fear }
  FearWeakenMaxLevel = 5;
  LargeSideCount = 6;           { ParalyzeSideWithFear: a side of six or more members gets a save bonus [?] }
  HumanFearSaveBonus = 2;       { the paralysis save bonus of a human }
  StrongMonsterLevel = 4;       { CancelDamageUnlessEnchantedSlotItem: a monster below this HighestLevel is not hurt }
  ItemHolyWater = $55;          { ItemType: Vial Of Holy Water [V item files] }
  ItemOilFlask = $56;           { ItemType: Flask OF Oil [V item files] }
  ItemBoulderA = $57;           { ItemType of the giants' hurled rows, boulders [I] }
  ItemBoulderB = $58;
  HolyWaterDieSides = 6;        { holy water does 1d6 + 1 damage }
  OilFlaskDiceCount = 3;        { an oil flask does 3d8 }
  OilFlaskDieSides = 8;
  SpitDiceCount = 8;            { the acid spit does 8d4 }
  SpitDieSides = 4;
  GaseousCursorMargin = 3;      { ShowCursorOn's Margin and ShowCursor arguments in TurnGaseousAndEscape [?] }
  GaseousShowCursor = 0;

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
  (RemovingAffects is 1 then, set by the Temple's RemoveAffect calls, ovl04:0386): then the result is False and
  nothing is added. Otherwise AddAffect (ovl24:0E52) appends the affect with its handler marked to run
  when the affect is removed, and the result is True. }
function TryAddAffect(Who: PCharacter; AffectId, Data: Byte; Duration: Word): Boolean;
begin
  if RemovingAffects <> 0 then
    TryAddAffect := False
  else
  begin
    TryAddAffect := True;
    AddAffect(Who, AffectId, Duration, Data, RunsHandlerOnRemove);
  end;
end;
{ ovl12:0058. Puts Who out of the fight, with Msg shown on Who at row CombatMessageRow (ShowCharacterMessage).
  Unless Who's Status is StatusDead, StatusStoned or StatusGone (6, 7 or 8) already, its Status becomes NewStatus,
  its Flag10D and HpCurrent are cleared, its death affects are removed (RemoveDeathAffects), the hooks of a combatant going
  down run, and Who leaves
  the map (RemoveCombatant) when Flag10D is clear. Then DelayByGameSpeed, the prompt is cleared and,
  outside combat, the selected character is redrawn. Like DropCombatant (ovl24:0F06) without the ground
  redraw. }
procedure DropFromFight(Who: PCharacter; NewStatus: Byte; Msg: String40);
begin
  ShowCharacterMessage(Who, Msg, CombatMessageRow, False);
  case Who^.Status of
    StatusStoned, StatusDead, StatusGone: Exit;
  end;
  Who^.Status := NewStatus;
  Who^.Flag10D := 0;
  Who^.HpCurrent := 0;
  RemoveDeathAffects(Who);
  RunAffectHooks(HookGoesDown, Who);
  if Who^.Flag10D = 0 then
    RemoveCombatant(Who);
  DelayByGameSpeed;
  ClearCharacterMessage;
  if ViewMode <> ViewModeCombat then
    DrawPartyRoster(SelectedCharacter);
end;
{ ovl12:010D. Affect handler of an affect (the AffectHandlers shape: Who, Affect and Mode; Mode is not read,
  so applying and removing run the same code, ovl24:0000): adds MoraleStep to the morale scratch MoraleScratch (ovl09
  CheckMorale
  computes it) and 1 to AttackRoll. The handler at ovl12:011D takes both back. Runs for affect $01 (id 1,
  InitAffectHandlers [V]). }
procedure RaiseAttackAndMorale(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Inc(MoraleScratch, MoraleStep);
  Inc(AttackRoll);
end;
{ ovl12:011D. The handler that undoes RaiseAttackAndMorale (ovl12:010D), with the AffectHandlers shape (Who,
  Affect and Mode; Mode not read): takes MoraleStep off the morale scratch MoraleScratch, or sets it to 0 when it
  holds less, and takes 1 off AttackRoll. Runs for affect $02 (id 2, InitAffectHandlers [V]). }
procedure LowerAttackAndMorale(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if MoraleScratch < MoraleStep then
    MoraleScratch := 0
  else
    Dec(MoraleScratch, MoraleStep);
  Dec(AttackRoll);
end;
{ ovl12:013B. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000).
  It copies the character Who attacked last (Who's combat Target, TCombatant at +$108 of Who, MeleeAttack
  sets it in ovl08) into AttackTarget. When that character's byte +$9F (CreatureType of TCharacter, purpose unknown [?])
  is CreatureUndead (4), the attack roll and the damage each gain TargetBonus. Runs for affect $03 (id 3,
  InitAffectHandlers [V]). }
procedure BoostAttackAgainstUndead(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  AttackTarget := Who^.Combat^.Target;
  if AttackTarget^.CreatureType = CreatureUndead then
  begin
    Inc(AttackRoll, TargetBonus);
    Inc(DamageAmount, TargetBonus);
  end;
end;
{ ovl12:017F. Shows "starts to train" on Who at row CombatMessageRow (ShowCharacterMessage, the message is copied to a
  stack temporary by 0AF8:0B0B first) and gives Who the training manual affect (AffectTrainingManual,
  duration TrainingManualDuration, data TrainingManualData), whose handler runs when it is removed.
  It has the AffectHandlers frame (Who, Affect, Mode); Affect and Mode are not read here. Runs for affect $04 (id 4,
  InitAffectHandlers
  [V]). }
procedure StartTrainingWithManual(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  ShowCharacterMessage(Who, 'starts to train', CombatMessageRow, True);
  AddAffect(Who, AffectTrainingManual, TrainingManualDuration, TrainingManualData, RunsHandlerOnRemove);
end;
{ ovl12:01C3. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000).
  Like BoostAttackAgainstUndead (ovl12:013B) it copies Who's combat Target into AttackTarget, then gives
  a bonus to the attack roll and to the damage from the target's byte +$9F (CreatureType of TCharacter, purpose unknown
  [?]): CreatureTroll gives FireBonusForTroll (1), CreatureTypeNine or CreatureStirge give FireBonusForStirgeNine (2),
  CreatureUndead gives FireBonusForUndead (3), any other value gives 0. The damage kind becomes KindFire or KindMagic
  (fire, plus the magic bit 8, ovl24:13E4). Runs for affect $06 (id 6, InitAffectHandlers [V]). }
procedure BoostFireAttackByTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Bonus: Byte;
begin
  AttackTarget := Who^.Combat^.Target;
  case AttackTarget^.CreatureType of
    CreatureTroll: Bonus := FireBonusForTroll;
    CreatureTypeNine, CreatureStirge: Bonus := FireBonusForStirgeNine;
    CreatureUndead: Bonus := FireBonusForUndead;
  else
    Bonus := 0;
  end;
  Inc(AttackRoll, Bonus);
  Inc(DamageAmount, Bonus);
  DamageKind := KindFire or KindMagic;
end;
{ ovl12:0233. Training of Who's constitution: shows "is hardier" on Who (row CombatMessageRow), Constitution goes up by one,
  and Who's hit points gain: the hit points above HpB1 (HpMax - HpB1) are divided by the class weight (fighter
  levels count Constitution - 15, non-fighter levels count twice above 15, else 1; 1 when the weight is 0),
  and the gain goes to HpMax and to the current hit points HpCurrent. Nothing is gained below Constitution 15,
  nor from 17 up without a fighter level. At Constitution 20 Who gets AffectTrainedOut instead and the
  routine ends. It has the AffectHandlers frame (Who, Affect, Mode); Affect and Mode are not read here. Runs for affect $07
  (id 7, InitAffectHandlers [V]). }
procedure TrainConstitution(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Gain: Byte;                   { HpMax - HpB1 first, then the gain of this training }
  Weight: Byte;                 { the class weights summed (ovl04:0510) }
  I: ShortInt;
begin
  ShowCharacterMessage(Who, 'is hardier', CombatMessageRow, True);
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
      if I = ClassFighter then
        Inc(Weight, (Who^.Constitution - TrainingConstitution) * Who^.ClassLevels[I])
      else if Who^.Constitution > TrainingConstitution then
        Inc(Weight, Who^.ClassLevels[I] * 2)
      else
        Inc(Weight, Who^.ClassLevels[I]);
  if Weight = 0 then Weight := 1;
  Gain := Gain div Weight;
  if (Who^.Constitution < FighterOnlyConstitution) or (Who^.ClassLevels[ClassFighter] > 0) then
  begin
    Inc(Who^.HpMax, Gain);
    Inc(Who^.HpCurrent, Gain);
  end;
end;
{ ovl12:0377. It moves 2 from the attack roll to the saving throw roll when the selected character's
  Alignment (+$A0 of TCharacter, the alignment index of AlignmentNames [V]) is 2, 5 or 8, Lawful, Neutral and Chaotic
  Evil: SaveRoll (DS:6816) gains 2 and AttackRoll (DS:6822) loses 2. The effect is that of Protection from Evil [I].
  It has the 10-byte frame of the affect handlers, but reads SelectedCharacter, not its parameters
  (Who, Affect and Mode are not read). Runs for affects $08 and $2D (ids 8, 45, InitAffectHandlers [V]). }
procedure ShiftAttackToSaveVsEvil(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (SelectedCharacter^.Alignment = AlignLawfulEvil) or (SelectedCharacter^.Alignment = AlignNeutralEvil) or
     (SelectedCharacter^.Alignment = AlignChaoticEvil) then
  begin
    Inc(SaveRoll, ProtectionShift);
    Dec(AttackRoll, ProtectionShift);
  end;
end;
{ ovl12:03AC. The twin of ShiftAttackToSaveVsEvil (ovl12:0377) with the Alignment values 0, 3 and 6 (Lawful, Neutral and
  Chaotic Good in AlignmentNames) in place of 2, 5 and 8, the effect of Protection from Good [I]: SaveRoll (DS:6816)
  gains 2 and AttackRoll (DS:6822)
  loses 2. Who, Affect and Mode are not read. Runs for affects $09 and $2E (ids 9, 46, InitAffectHandlers [V]). }
procedure ShiftAttackToSaveVsGood(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (SelectedCharacter^.Alignment = AlignLawfulGood) or (SelectedCharacter^.Alignment = AlignNeutralGood) or
     (SelectedCharacter^.Alignment = AlignChaoticGood) then
  begin
    Inc(SaveRoll, ProtectionShift);
    Dec(AttackRoll, ProtectionShift);
  end;
end;
{ ovl12:03E1. Affect handler for damage (the AffectHandlers frame: Who, Affect and Mode, none of them read): when
  the damage being dealt is cold (DamageKind bit KindCold, DS:6819), it halves DamageAmount (DS:6818) and adds
  ColdSaveBonus to SaveRoll (DS:6816). runs for affect $0A (id 10, InitAffectHandlers [V]). Game meaning: Resist Cold,
  the spell with SpellTable AffectId $0A (spell 8) [V]: half cold damage and +3 on the save, as the AD&D spell [I]. }
procedure HalveColdDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (DamageKind and KindCold) <> 0 then
  begin
    DamageAmount := DamageAmount shr 1;
    Inc(SaveRoll, ColdSaveBonus);
  end;
end;
{ ovl12:0400. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode 0 applies, any other value
  removes, ovl24:0000). Runs for affect $0B (id 11, InitAffectHandlers [V]). Applying gives Who to the
  computer, as quick combat does (whitepaper, "Who plays"): Quick is set so QuickTurn plays the turn, Who
  becomes computer-run with morale $33 unless it already is, the target Who attacked is dropped and
  RecountCombatSides runs. The side becomes Affect.Data bit 7 (ControlSideBit); bit 6 keeps the
  side before (ControlSavedSideBit) and bit 5 marks the control as applied, so a second apply only sets
  the morale. Removing gives back the side from bit 6 and clears the computer-run morale while it is still
  ComputerRunMorale; it does not clear Quick. Applying also sets the morale scratch MoraleScratch (AffectMorale). }
procedure ApplyCharmPerson(Who: PCharacter; Affect: PAffect; Mode: Byte);
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
      if Who^.B84 <= ComputerRun - 1 then
        Who^.B84 := ComputerRunMorale;
      Who^.Combat^.Target := nil;
      RecountCombatSides;
    end;
    MoraleScratch := AffectMorale;
  end;
end;
{ ovl12:04BA. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000) of a strength
  affect whose Data holds an encoded strength (EncodeStrength, ovl24:10E4). Does nothing when Data has bit 7
  (StrengthKept): an earlier strength is kept in it. Otherwise Who's Strength and StrengthPercent take the
  affect's strength (DecodeStrength, ovl24:110D). Then the strongest other strength affect of Who, id $0C or
  $26 (AffectEnlarge, AffectStrength), gives Who its strength, and it takes the encoded strength the
  affect gave Who. Strength 18 with a percentile counts above any other 18 (ExceptionalStrength). With no
  other strength affect Who keeps the decoded strength. Runs for affects $0C and $26 (ids 12, 38, InitAffectHandlers [V]).
  QUIRK ovl12:05B8: the earlier affect's Data is written without StrengthKept, where RaiseStrength (ovl24:115C)
  sets it. }
procedure ApplyStrengthAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
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
    if (Scan^.Id = AffectEnlarge) or (Scan^.Id = AffectStrength) then
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
  value is set each time. Runs for affect $0E (id 14, InitAffectHandlers [V]). }
procedure SetCharismaFromAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Who^.Charisma := Affect^.Data;
end;
{ ovl12:05EB. Affect handler of the slowed poison that Slow Poison (ovl22 CastSlowPoison) gives [V]: an affect handler
  (the AffectHandlers shape: Who, Affect and Mode; Mode is
  not read, ovl24:0000). It adds affect $0F (AffectSlowPoisonDamage) to Who for SlowPoisonDamageDuration with the
  Data byte of Affect, when TryAddAffect allows it. Then, while Who has more than one hit point (HpCurrent,
  the current hit points [I]), it deals 1 point of plain damage (DamageKind 0, no save, DealDamage) and,
  outside combat, redraws the selected character (ViewMode is not ViewModeCombat). Runs for affect $0F (id 15,
  InitAffectHandlers [V]). }
procedure SlowPoisonDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if TryAddAffect(Who, AffectSlowPoisonDamage, Affect^.Data, SlowPoisonDamageDuration) then
    if Who^.HpCurrent > 1 then
    begin
      DamageKind := 0;
      DealDamage(Who, 1, 0, False);
      if ViewMode <> ViewModeCombat then
        DrawPartyRoster(SelectedCharacter);
    end;
end;
{ ovl12:0647. Affect handler (the AffectHandlers shape: Who, Affect and Mode) that does nothing: none of its
  parameters is read and no global is written. Runs for affect $10 (id 16, InitAffectHandlers [V]). }
procedure IgnoreAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
end;
{ ovl12:064E. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read). Raises
  Who's ArmourClassValue (TCharacter +$111, the armour class stored as 60 minus the AC [I]) to at least
  MinimumResistance, adds one to SaveRoll, and when CastingSpell is SpellMagicMissile clears DamageAmount, so the
  damage of the roll in progress is none. Runs for affect $11 (id 17, InitAffectHandlers [V]). }
procedure RaiseResistanceAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if Who^.ArmourClassValue < MinimumResistance then
    Who^.ArmourClassValue := MinimumResistance;
  Inc(SaveRoll);
  if CastingSpell = SpellMagicMissile then
    DamageAmount := 0;
end;
{ ovl12:0679. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It copies the
  character Who attacked last (Who's combat Target) into AttackTarget, as BoostAttackAgainstUndead does. When that
  character's +$9F (CreatureType) and CombatSize (+$6C) are both 1, AttackRoll gains 1 for each of the names
  KoboldGoblinNames[1..4] the character's name equals. Runs for affect $12 (id 18, InitAffectHandlers [V]).
  Given to the gnome by CreateCharacter [V]. }
procedure BoostAttackVsKoboldGoblin(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  I: Byte;
begin
  AttackTarget := Who^.Combat^.Target;
  if (AttackTarget^.CreatureType = CreatureHumanoid) and (AttackTarget^.CombatSize = SmallFootprintKind) then
    for I := 1 to KoboldGoblinNameCount do
      if AttackTarget^.Name = KoboldGoblinNames[I] then
        Inc(AttackRoll);
end;
{ ovl12:06E4. Affect handler for damage (the AffectHandlers frame: Who, Affect and Mode, none of them read): when
  the damage being dealt is fire (DamageKind bit KindFire, DS:6819), it halves DamageAmount (DS:6818) and adds
  FireSaveBonus to SaveRoll (DS:6816), the fire twin of HalveColdDamage (ovl12:03E1). runs for affect $14
  (id 20, InitAffectHandlers [V]). Game meaning: Resist Fire, SpellTable AffectId $14 (spell 24) [V]: half fire damage
  and +3 on the save [I]. }
procedure HalveFireDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (DamageKind and KindFire) <> 0 then
  begin
    DamageAmount := DamageAmount shr 1;
    Inc(SaveRoll, FireSaveBonus);
  end;
end;
{ ovl12:070F. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). When Who's combat
  byte CanUseMagicItem (+$2 of TCombatant) is set, Who shows "is silenced" at row CombatMessageRow (ShowCharacterMessage). Then
  CanUseMagicItem and CanCast (+$1, zero hides Cast in the combat menu, ovl08:0747) are both cleared. Runs for affect $15 (id
  21, InitAffectHandlers [V]). }
procedure ShowSilenceAndStopCasting(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if Who^.Combat^.CanUseMagicItem <> 0 then
    ShowCharacterMessage(Who, 'is silenced', CombatMessageRow, True);
  Who^.Combat^.CanUseMagicItem := 0;
  Who^.Combat^.CanCast := 0;
end;
{ ovl12:0775. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read): a poisoned
  character dies. When Who has the Poisoned affect (AffectPoisoned, ovl15 names it 'Poisoned'), DropFromFight takes
  Who out of the fight with StatusDead and the text 'dies from poison'. Then AffectSlowPoisonDamage is removed from Who
  inside the RemovingAffects bracket the Temple uses around RemoveAffect (ovl04:0386), so TryAddAffect adds nothing while
  it runs. Runs for affect $16 (id 22, InitAffectHandlers [V]). }
procedure DieIfPoisoned(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  PoisonAffect: Pointer;
begin
  if HasAffect(Who, AffectPoisoned, PoisonAffect) then
    DropFromFight(Who, StatusDead, 'dies from poison');
  RemovingAffects := 1;
  RemoveAffect(Who, AffectSlowPoisonDamage, nil);
  RemovingAffects := 0;
end;
{ ovl12:07E0. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect is not read). When the affect
  is applied (Mode 0) and Who has no item of HammerItemType with NameNum[3] GivenItemNameNum3 yet, and Who's
  ItemCountC7 (+$C7, likely the item count [I]) is below ItemCountLimit, Who gets such an item (AddItemCopy adds
  it to the list, the temporary is freed) and "Gains an item" is shown at row CombatMessageRow. When it is removed (Mode not
  0) the item Who has is taken off the list (RemoveInventoryItem). Then RecalcCombatValues redraws Who. Spiritual
  Hammer: SpellTable spell 28 has AffectId $17 [V]; runs
  for affect $17 (id 23, InitAffectHandlers [V]). }
procedure GiveSpiritualHammer(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;
  Found: Boolean;
begin
  Item := Who^.Items;
  Found := False;
  while (Item <> nil) and not Found do
    if (Item^.ItemType = HammerItemType) and (Item^.NameNum[3] = GivenItemNameNum3) then
      Found := True
    else
      Item := Item^.Next;
  if Mode <> 0 then
  begin
    if Item <> nil then
      RemoveInventoryItem(Who, Item);
  end;
  if Mode = 0 then
    if not Found then
      if Who^.ItemCountC7 < ItemCountLimit then
      begin
        New(Item);
        FillChar(Item^, SizeOf(TMenuLine), 0);
        Item^.ItemType := HammerItemType;
        Item^.NameNum[2] := GivenItemNameNum2;
        Item^.NameNum[3] := GivenItemNameNum3;
        Item^.Plus := GivenItemPlus;
        Item^.Affects[2] := GivenItemAffect2;
        Item^.Affects[3] := GivenItemAffect3;
        AddItemCopy(Who, Item);
        Dispose(Item);
        ShowCharacterMessage(Who, 'Gains an item', CombatMessageRow, True);
      end;
  RecalcCombatValues(Who);
end;
{ ovl12:0918. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none of them is read). It takes
  AttackPenalty (4) off AttackRoll. When SelectedCharacter has no affect AffectDetectInvisibility ($18), HookVetoFlag
  is set to 1
  (HasAffect looks the affect up in the affect list and gives the found affect in FoundAffect). Affect $19 is
  Invisibility: SpellTable spells 30 and
  50 have AffectId $19 [V]; runs for
  affect $19 (id 25, InitAffectHandlers [V]). }
procedure InvisibleTargetHardToHit(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  FoundAffect: Pointer;
begin
  if not HasAffect(SelectedCharacter, AffectDetectInvisibility, FoundAffect) then
    HookVetoFlag := 1;
  Dec(AttackRoll, AttackPenalty);
end;
{ ovl12:0947. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). The twin of
  BoostAttackVsKoboldGoblin (ovl12:0679) with eight names: when the character Who attacked last (Who's combat
  Target, copied into AttackTarget) has CreatureType and CombatSize (+$6C) both 1, AttackRoll gains 1 for each of
  the names OrcGoblinHobgoblinNames[1..8] that the
  character's name equals. Runs for affect $1A (id 26, InitAffectHandlers [V]). Given to the dwarf by CreateCharacter [V]. }
procedure BoostAttackVsOrcGoblinHobgoblin(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  I: Byte;
begin
  AttackTarget := Who^.Combat^.Target;
  if (AttackTarget^.CreatureType = CreatureHumanoid) and (AttackTarget^.CombatSize = SmallFootprintKind) then
    for I := 1 to OrcGoblinHobgoblinNameCount do
      if AttackTarget^.Name = OrcGoblinHobgoblinNames[I] then
        Inc(AttackRoll);
end;
{ ovl12:09C0. Affect handler of the images affect (AffectImages, $1C; it runs on the damage hook, kind 6,
  ovl24:02FA; the AffectHandlers shape, Who, Affect and Mode, Mode not read). When a hit is about to land,
  one image may take it: with 1d(Data+1) (Data counts the images [I]) above 1, CastingSpell not 0 and SpellAppliedToArea 0,
  CancelPendingHook(0) drops the damage, Who shows "lost an image" at row CombatMessageRow (ShowCharacterMessage) and Data goes
  down by one. When no image is left (Data 0) affect AffectImages is removed. A roll of 1 lets the hit through
  [I]. Runs for affect $1C (id 28, InitAffectHandlers [V]). }
procedure ImageAbsorbsHit(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (RollDice(1, Affect^.Data + 1) > 1) and (CastingSpell > 0) and (SpellAppliedToArea = 0) then
  begin
    CancelPendingHook(0);
    ShowCharacterMessage(Who, 'lost an image', CombatMessageRow, True);
    Dec(Affect^.Data);
    if Affect^.Data = 0 then
      RemoveAffect(Who, AffectImages, nil);
  end;
end;
{ ovl12:0A3D. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, so the
  handler runs the same on applying and removing). It takes a quarter off the damage the hooks offer:
  DamageAmount := DamageAmount - DamageAmount div 4, so three quarters of the damage (rounded down) remain
  (the damage hook is kind 6, ovl24:02FA). Runs for affect $1D (id 29, InitAffectHandlers [V]). }
procedure ReduceDamageByQuarter(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  DamageAmount := DamageAmount - DamageAmount div 4;
end;
{ ovl12:0A65. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It stops Who
  casting: when Who's combat byte CanUseMagicItem (TCombatant +$2) is set, Who shows "is coughing" at row CombatMessageRow
  (ShowCharacterMessage), then CanUseMagicItem and CanCast (+$1, zero hides Cast in the combat menu, ovl08:0747)
  are cleared and Who is redrawn (RecalcCombatValues). Then TCharacter.RearArmourClassValue (+$112) steps down by
  CoughResistStep while above CoughResistLimit and is set to CoughResistReset otherwise, and that value becomes
  ArmourClassValue (+$111). When Who is the selected character, DrawCharacterPanel runs. The message suggests a
  gas or smoke affect [I]. Runs for affect $1E (id 30, InitAffectHandlers [V]). }
procedure CoughStopsCasting(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if Who^.Combat^.CanUseMagicItem <> 0 then
    ShowCharacterMessage(Who, 'is coughing', CombatMessageRow, True);
  Who^.Combat^.CanUseMagicItem := 0;
  Who^.Combat^.CanCast := 0;
  RecalcCombatValues(Who);
  if Who^.RearArmourClassValue > CoughResistLimit then
    Dec(Who^.RearArmourClassValue, CoughResistStep)
  else
    Who^.RearArmourClassValue := CoughResistReset;
  Who^.ArmourClassValue := Who^.RearArmourClassValue;
  if Who = SelectedCharacter then
    DrawCharacterPanel(Who);
end;
{ ovl12:0B1B. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It clears
  the affect's Flag, so the handler does not run again when the affect is removed. Unless the Temple is removing
  affects (RemovingAffects is not 0), Who collapses: DropFromFight takes Who out of the fight with StatusDead and the text
  'collapses'. Then Who's side becomes the high nibble of the affect's Data, Quick is set so the computer plays
  Who (as ApplyCharmPerson does, ovl12:0400), the morale of a computer-run member is cleared, and Who's
  SweepAttacks (+$6B) gets the fighter level, +$72 gets 12, +$76 and +$9F get 0. runs for
  affect $20 (id 32, InitAffectHandlers [V]). Game meaning: Animate Dead, SpellTable AffectId $20 (spell 36) [V]: it
  runs when the animated
  creature's affect ends; the creature collapses dead (unless Raise Dead is removing the affect) and returns to its
  own side (ovl22 stores Side * 16 + caster level in Data) [I]. }
procedure CollapseAndChangeSide(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Affect^.Flag := 0;
  if RemovingAffects = 0 then
    DropFromFight(Who, StatusDead, 'collapses');
  Who^.Side := Affect^.Data div SideShift;
  Who^.Quick := 1;
  Who^.Pad74[TurnUndeadIndex] := 0;
  Who^.SweepAttacks := Who^.ClassLevels[ClassFighter];
  Who^.BaseMovement := AnimatedBaseMovement;
  if Who^.B84 = ComputerRunMorale then
    Who^.B84 := 0;
  Who^.CreatureType := 0;
end;
{ 0BAC. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). Takes AttackPenalty
  off AttackRoll, ResistPenalty off Who's ArmourClassValue (+$111) and off RearArmourClassValue (+$112, the byte
  CoughStopsCasting copies into ArmourClassValue, ovl12:0A65), and SavePenalty off SaveRoll.
  Runs for affect $21 (id 33, InitAffectHandlers [V]). }
procedure LowerAttackSaveAndResistance(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Dec(AttackRoll, AttackPenalty);
  Dec(Who^.ArmourClassValue, ResistPenalty);
  Dec(Who^.RearArmourClassValue, ResistPenalty);
  Dec(SaveRoll, SavePenalty);
end;
{ 0BCF. Affect handler (the AffectHandlers shape: Who, Affect and Mode, passed on unchanged). Runs the handler of
  affect AffectDrainsStrength and then the handler of AffectCauseDisease with the same Who, Affect and Mode (both through
  CallAffectHandler, ovl24:0000). Both ids are in the list Cure Disease removes, so the routine runs the disease
  handlers. Runs for affect $22 (id 34, InitAffectHandlers [V]). }
procedure RunDiseaseHandlers(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  CallAffectHandler(AffectDrainsStrength, Who, Affect, Mode);
  CallAffectHandler(AffectCauseDisease, Who, Affect, Mode);
end;
{ 0C06. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). Adds 1 to SaveRoll and
  to AttackRoll, the plus of the routine at ovl12:0C15. Called by ovl12:12B2 (RaiseOrLowerAttackAndSave).
  Runs for affect $23 (id 35, InitAffectHandlers [V]). }
procedure RaiseAttackAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Inc(SaveRoll);
  Inc(AttackRoll);
end;
{ 0C15. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). Takes AttackPenalty
  off AttackRoll and SavePenalty off SaveRoll, the minus of RaiseAttackAndSave (ovl12:0C06). Runs for affect $24 (id 36,
  InitAffectHandlers [V]). }
procedure LowerAttackAndSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Dec(AttackRoll, AttackPenalty);
  Dec(SaveRoll, SavePenalty);
end;
{ 0C26. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read, ovl24:0000). When Who's combatant
  still has its turn to take (Combat^.Initiative, TCombatant +$3, above 0: CombatTurn acts only above 0), HookVetoFlag
  is set to
  1 and AttackRoll becomes MissRoll, a negative roll (a miss, ovl24:0CD5). Runs for affect $25 (id 37,
  InitAffectHandlers [V]). }
procedure SetAttackMissIfTurnPending(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if Who^.Combat^.Initiative > 0 then
  begin
    HookVetoFlag := 1;
    AttackRoll := MissRoll;
  end;
end;
{ 0C4B. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). The first run
  with AgedBit clear in the
  affect's Data sets the bit, shows "ages" on Who at row CombatMessageRow (ShowCharacterMessage) and adds
  one
  year to Who's Age (+$30). Every run doubles HookedMoveOrAttacks (shl 1), whether or not Who was aged. Runs for
  affect $27 (id 39,
  InitAffectHandlers [V]). }
procedure ApplyHaste(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (Affect^.Data and AgedBit) = 0 then
  begin
    Affect^.Data := Affect^.Data + AgedBit;
    ShowCharacterMessage(Who, 'ages', CombatMessageRow, True);
    Inc(Who^.Age);
  end;
  HookedMoveOrAttacks := HookedMoveOrAttacks shl 1;
end;
{ ovl12:0CC3. Affect handler of a cloud (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000).
  The cloud is the TCombatNode of the list CloudList whose owner is Who and whose kind is the high nibble of Affect's
  Data. Without one nothing happens. With one, "The air clears a little..." is shown (ShowFlashMessage), and the
  cloud goes: each arm still in place gets back the tile it covered, except that an arm where a body lies (BodyTable)
  shows BodyTile. The cloud is unlinked and freed, and every cloud left repaints its arms with CloudTile.
  Runs for affect $28 (id 40, InitAffectHandlers [V]). }
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
  Cloud := CloudList;
  while (Cloud <> nil) and not Found do
    if (Cloud^.Owner = Who) and (Cloud^.Kind = Index) then
      Found := True
    else
      Cloud := Cloud^.Next;
  if not Found then Exit;
  ShowFlashMessage('The air clears a little...');
  for Arm := 1 to 4 do
    if Cloud^.Arms[Arm] <> 0 then
    begin
      CellX := Cloud^.X + DirStepX[CloudArmDirections[Arm]];
      CellY := Cloud^.Y + DirStepY[CloudArmDirections[Arm]];
      Found := False;
      for Index := 1 to BodyCount do
        if (BodyTable[Index].Who <> nil) and (BodyTable[Index].X = CellX) and (BodyTable[Index].Y = CellY) then
          Found := True;
      if Found then
        CombatMap^.Cells[CellY, CellX] := BodyTile
      else
        CombatMap^.Cells[CellY, CellX] := Cloud^.Tiles[Arm];
    end;
  Node := CloudList;
  if Node = Cloud then
    CloudList := Node^.Next
  else
    while Node^.Next <> Cloud do
      Node := Node^.Next;
  Node^.Next := Cloud^.Next;
  FreeMem(Cloud, SizeOf(TCombatNode));
  Node := CloudList;
  while Node <> nil do
  begin
    for Arm := 1 to 4 do
      if Node^.Arms[Arm] <> 0 then
        CombatMap^.Cells[Node^.Y + DirStepY[CloudArmDirections[Arm]], Node^.X + DirStepX[CloudArmDirections[Arm]]] :=
          CloudTile;
    Node := Node^.Next;
  end;
end;
{ ovl12:0FAC. Called by ovl12:1086 (ProtectFromNormalMissiles) and two more routines (ovl12:2901, 2BC8).
  When SelectedCharacter has an item in its first slot (SlotItems[0]) and DistanceToTarget (the distance from
  SelectedCharacter to Who, 1 when adjacent [I]) is above 1, a roll of 1d100 at or below Chance avoids the attack:
  "Avoids it" is shown on Who (row CombatMessageRow), the damage becomes 0, the attack roll MissRoll and
  AvoidedAttackCounter goes
  down by one. the kind of attack is not known [?]. Game meaning: avoiding a ranged attack (it needs DistanceToTarget
  above 1) [V code]: used by Protection From Normal Missiles ($29, spell 54), the THRI-KREEN ($68, 60 percent) and
  hill and fire giants ($78, 50 percent) [V monster data]. }
procedure AvoidDistantAttack(Who: PCharacter; Chance: Byte);
begin
  if SelectedCharacter^.SlotItems[0] <> nil then
    if DistanceToTarget(SelectedCharacter, Who) > 1 then
      if RollDice(1, 100) <= Chance then
      begin
        ShowCharacterMessage(Who, 'Avoids it', CombatMessageRow, True);
        DamageAmount := 0;
        AttackRoll := MissRoll;
        Dec(AvoidedAttackCounter);
      end;
end;
{ ovl12:101D. The item Who keeps in its first slot (SlotItems[0], TCharacter +$CC; the 13 slots are the items the
  character remembers, POOLVARS), or nil when the slot is empty. When there is a slot item, ChooseAttackItem (Who, Item)
  runs first: its Item is kept when it returns nonzero and gives a non-nil item, otherwise the slot item is the result.
  Purpose unknown: what ChooseAttackItem finds is not known yet [?]. }
function FirstSlotItem(Who: PCharacter): PItem;
var
  Item: Pointer;                { a Pointer, the var parameter of ChooseAttackItem }
  Found: Byte;                  { the result of ChooseAttackItem }
begin
  Item := nil;
  if Who^.SlotItems[0] <> nil then
  begin
    Found := ChooseAttackItem(Who, Item);
    if (Found = 0) or (Item = nil) then
      Item := Who^.SlotItems[0];
  end;
  FirstSlotItem := PItem(Item);
end;
{ ovl12:1086. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). When the
  selected character's first remembered item (FirstSlotItem) has Plus 0, Who avoids the attack in progress at once
  (AvoidDistantAttack with AlwaysAvoids). Runs for affect $29 (id 41, InitAffectHandlers [V]). }
procedure ProtectFromNormalMissiles(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if FirstSlotItem(SelectedCharacter) <> nil then
    if FirstSlotItem(SelectedCharacter)^.Plus = 0 then
      AvoidDistantAttack(Who, AlwaysAvoids);
end;
{ ovl12:10C1. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It halves
  HookedMoveOrAttacks, the byte that ApplyHaste (ovl12:0C4B) doubles every time it runs. Runs for affect $2A (id
  42, InitAffectHandlers [V]). }
procedure ApplySlow(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  HookedMoveOrAttacks := HookedMoveOrAttacks shr 1;
end;
{ ovl12:10DE. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It gives Who
  the affect AffectDrainsStrength (a Cure Disease affect, ovl04:031E) for WeakeningDuration rounds with the Data of Affect,
  when TryAddAffect allows it. While
  Who's Strength is above 3 each run shows "is weakened" (row CombatMessageRow) and takes one
  off Strength; at 3 or less Who gets AffectHelpless unless it has it already. Runs for affect $2B (id 43,
  InitAffectHandlers [V]). }
procedure WeakenStrength(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  FoundAffect: Pointer;
begin
  if TryAddAffect(Who, AffectDrainsStrength, Affect^.Data, WeakeningDuration) then
    if Who^.Strength > MinimumStrength then
    begin
      ShowCharacterMessage(Who, 'is weakened', CombatMessageRow, True);
      Dec(Who^.Strength);
    end
    else if not HasAffect(Who, AffectHelpless, FoundAffect) then
      AddAffect(Who, AffectHelpless, PermanentDuration, DataFF, NoRemoveHandler);
end;
{ ovl12:1168. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It gives Who
  the disease affect AffectCauseDisease for AffectCauseDiseaseDuration rounds, with the Data of Affect, when TryAddAffect
  allows it. Then, while Who has more than one hit point (HpCurrent), it deals 1 point of plain damage (DamageKind 0, no
  save, DealDamage) and, outside combat, redraws the selected character. Otherwise Who gets AffectHelpless unless it has
  it already. Runs for affect $2C (id 44, InitAffectHandlers [V]). }
procedure CauseDiseaseAndDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  FoundAffect: Pointer;
begin
  if TryAddAffect(Who, AffectCauseDisease, Affect^.Data, AffectCauseDiseaseDuration) then
    if Who^.HpCurrent > 1 then
    begin
      DamageKind := 0;
      DealDamage(Who, 1, 0, False);
      if ViewMode <> ViewModeCombat then
        DrawPartyRoster(SelectedCharacter);
    end
    else if not HasAffect(Who, AffectHelpless, FoundAffect) then
      AddAffect(Who, AffectHelpless, PermanentDuration, DataFF, NoRemoveHandler);
end;
{ ovl12:11F9. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It copies
  the character Who attacked last (Who's combat Target, TCombatant at +$108 of Who, MeleeAttack sets it in ovl08) into
  AttackTarget. When the selected character has CreatureType (+$9F of TCharacter, CreatureHumanoid) and its
  CombatSize has footprint kind 2 (bits 0..6 of +$6C), AttackRoll loses AttackPenalty for each of the names
  OgreTrollGiantNames[1..8]
  that the target's name equals. Runs for affect $2F (id 47, InitAffectHandlers [V]); given to the dwarf and the gnome by
  CreateCharacter [V]. QUIRK ovl12:11F9: it tests CreatureType and CombatSize of SelectedCharacter but the
  name of AttackTarget (Who's own last target), where the sibling handlers test the target for both [?]. }
procedure LowerAttackVsOgreTrollGiant(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  I: Byte;                      { the name row 1..8 of OgreTrollGiantNames }
begin
  AttackTarget := Who^.Combat^.Target;
  if (SelectedCharacter^.CreatureType = CreatureHumanoid) and
     ((SelectedCharacter^.CombatSize and CombatKindMask) = LargeFootprintKind) then
    for I := 1 to OgreTrollGiantNameCount do
      if AttackTarget^.Name = OgreTrollGiantNames[I] then
        Dec(AttackRoll, AttackPenalty);
end;
{ ovl12:1276. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). When the selected
  character has CreatureType (+$9F of TCharacter) set to CreatureHumanoid and its name is 'BUGBEAR' or 'GNOLL', AttackRoll
  loses AttackPenalty. Runs for affect $30 (id 48, InitAffectHandlers [V]); given to the gnome by CreateCharacter [V]. }
procedure LowerAttackIfSelectedIsBugbearOrGnoll(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if SelectedCharacter^.CreatureType = CreatureHumanoid then
    if (SelectedCharacter^.Name = 'BUGBEAR') or (SelectedCharacter^.Name = 'GNOLL') then
      Dec(AttackRoll, AttackPenalty);
end;
{ ovl12:12B2. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is passed on, ovl24:0000). The side
  the affect names is Affect's Data bit 4 (SideDataBit, 0 or 1). When Who's Side (+$10E of TCharacter) equals it,
  RaiseAttackAndSave (ovl12:0C06) runs with Who, Affect and Mode; otherwise AttackRoll and SaveRoll each lose one.
  Runs for affect $31 (id 49, InitAffectHandlers [V]). }
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
  the healing block AffectMummyDisease (ovl24:175D: HealCharacter with Flag 0 does nothing while it is there) for
  MummyDiseaseDuration rounds, with the Data of Affect, when TryAddAffect allows it. Then HealCharacter heals Who
  by one hit point with Flag 1, which the block does not stop, and when that healed Who, ShowHealResult (00BA:234A, not
  named yet) runs on Who. The map also had an entry at ovl12:1307, which is the middle of this routine (its pushes
  for the first call start at 12FB), so it has no routine of its own. Runs for affect $32 (id 50, InitAffectHandlers [V]). }
procedure AddHealingBlockAndHeal(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if TryAddAffect(Who, AffectMummyDisease, Affect^.Data, MummyDiseaseDuration) then
    if HealCharacter(Who, 1, 1) then
      ShowHealResult(Who);
end;
{ ovl12:133F. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It calls
  EndCombatTurn(Who), the routine the combat units call to end a combatant's turn (ovl08, ovl09 AiTurn), and does
  nothing with its result: a Turbo Pascal statement cannot call a function, so the call is tested and the test
  stands alone. runs for affects $1F, $33, $34 and $35 (ids 31, 51, 52, 53, InitAffectHandlers [V]). }
procedure EndAffectedCombatantTurn(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if EndCombatTurn(Who) <> 0 then ;
end;
{ ovl12:1355. Affect handler (the AffectHandlers shape: Who, Affect and Mode) with an empty body, like IgnoreAffect
  (ovl12:0647): none of its parameters is read and no global is written. runs for affect $36 (id 54,
  InitAffectHandlers [V]). }
procedure IgnoreAffect36(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
end;
{ ovl12:135C. Affect handler (the AffectHandlers shape: Who, Affect and Mode) with an empty body, like IgnoreAffect
  (ovl12:0647): none of its parameters is read and no global is written. runs for affect $37 (id 55,
  InitAffectHandlers [V]). }
procedure IgnoreAffect37(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
end;
{ ovl12:1363. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It gives Who the
  affect AffectInvisibility (ovl24:0E52, AddAffect) for InvisibilityDuration rounds with the Data
  InvisibilityData,
  with NoRemoveHandler: the handler does not run when the affect is removed. AffectInvisibility is the affect
  RollToHit
  clears from the attacker (ovl24:0CB7) [I]. runs for affect $38 (id 56, InitAffectHandlers [V]). }
procedure GiveInvisibilityForOneRound(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  AddAffect(Who, AffectInvisibility, InvisibilityDuration, InvisibilityData,
  NoRemoveHandler);
end;
{ ovl12:1399. Affect handler of the rot (AffectHandlers shape: Who, Affect and Mode; Mode not read; the affect is
  AffectRot, $39, which Cure Disease removes, whitepaper 5.19). Does nothing while the Temple removes affects (RemovingAffects
  is not 0, ovl04:0386). Otherwise it shows "Rots..." on Who (row CombatMessageRow) and takes RotCharismaLoss off
  Who's Charisma
  (+$15), never below RotMinimumCharisma. Then the rot moves on: while the stage (the high nibble of the affect's
  Data) is above RotLastStage, the stage drops by one (RotStage) and TryAddAffect gives Who the rot again with that
  Data for RotDuration rounds. At the last stage Who dies: DropFromFight takes Who out with StatusGone and the
  text "Dies rots away". Runs for affect $39 (id 57, InitAffectHandlers [V]). }
procedure ProgressRot(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if RemovingAffects <> 0 then Exit;
  ShowCharacterMessage(Who, 'Rots...', CombatMessageRow, True);
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
    DropFromFight(Who, StatusGone, 'Dies rots away');
end;
{ ovl12:1452. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It stops Who's
  movement: the combat record's Moves (+$6 of TCombatant, the movement left) goes to 0. When HookRunning is set it also
  clears HookedMoveOrAttacks, the byte ApplyHaste doubles. runs for affect $3A (id 58,
  InitAffectHandlers [V]). }
procedure StopMovement(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Who^.Combat^.Moves := 0;
  if HookRunning then
    HookedMoveOrAttacks := 0;
end;
{ ovl12:1472. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It gives Who the affect
  AffectRegainHitPoints (AddAffect, ovl24:0E52) with Duration 0 (permanent), the Data AffectRegainHitPointsData and no handler
  when it is removed (NoRemoveHandler). runs for affect $3B (id 59, InitAffectHandlers [V]). }
procedure GiveRegainHitPointsAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  AddAffect(Who, AffectRegainHitPoints, PermanentDuration, AffectRegainHitPointsData, NoRemoveHandler);
end;
{ ovl12:1490. Damage hook (the AffectHandlers shape: Who, Affect and Mode; none of them read). While the damage is fire
  (DamageKind bit KindFire, DS:6819), each of the LastDiceCount dice of the last roll takes FireReductionPerDie off
  DamageAmount, and it never goes below LastDiceCount; SaveRoll then gets FireProtectionSaveBonus. Damage that is not
  magical (KindMagic clear) is cancelled altogether: CancelPendingHook(0) clears DamageAmount and HookAffectId.
  runs for affect $3D (id 61, InitAffectHandlers [V]). Game meaning: Fire Resistance, the ovl15 DisplaySpellEffects
  name of affect $3D [V]; the item side is the Ring with Affects[3] $81 and Affects[2] $3D (Ring of Fire Resistance [I]). }
procedure ReduceFireDamageByRoll(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  I: Byte;
begin
  if (DamageKind and KindFire) <> 0 then
  begin
    for I := 1 to LastDiceCount do
    begin
      Dec(DamageAmount, FireReductionPerDie);
      if DamageAmount < LastDiceCount then
        DamageAmount := LastDiceCount;
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
  that healed Who, ShowHealResult (00BA:234A) runs on Who. Runs for affect $3E (id 62,
  InitAffectHandlers [V]). }
procedure AddTrainedOutAndHeal(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if TryAddAffect(Who, AffectTrainedOut, Affect^.Data, TrainedOutDuration) then
    if HealCharacter(Who, 1, 1) then
      ShowHealResult(Who);
end;
{ ovl12:1545. Poison hook of an attack (the frame is Who and Bonus; Bonus is the save bonus, 0 in
  PoisonAttackTargetBonus0's call at ovl12:166A). AttackTarget becomes Who's Combat^.Target, the character Who
  attacked last. That character makes a poison save (SaveKindPoison, with Bonus). When it fails, "is Poisoned"
  (row CombatMessageRow) is shown on it, DelayByGameSpeed waits, it
  gets AffectPoisoned for good (AddAffect with Duration 0, Data $FF, no handler on removal) and DropFromFight kills it
  with StatusDead and "is killed". The map split this routine at ovl12:1543 and ovl12:1583, which are inside its
  literal pool and inside its code. It is the poison hook of affects $40, $41, $42 and $46 (ids 64, 65, 66, 70,
  InitAffectHandlers
  [V]). }
procedure PoisonAttackTarget(Who: PCharacter; Bonus: ShortInt);
begin
  AttackTarget := Who^.Combat^.Target;
  if not SavingThrow(AttackTarget, SaveKindPoison, Bonus) then
  begin
    ShowCharacterMessage(AttackTarget, 'is Poisoned', CombatMessageRow, False);
    DelayByGameSpeed;
    AddAffect(AttackTarget, AffectPoisoned, PermanentDuration, DataFF, NoRemoveHandler);
    DropFromFight(AttackTarget, StatusDead, 'is killed');
  end;
end;
{ ovl12:15EB. Paralyses the character Who attacked last. AttackTarget takes Who's combat Target (TCombatant +$A) and
  it makes the paralysis save (SavingThrow kind SaveKindParalysis, bonus 0). Unless it saves, "is Paralyzed" is shown
  on it (ShowHitMessage, flag 1, as ApplyAffect shows an affect's message) and it gets the affect AffectParalysis for
  Duration rounds with Data ParalysisData, with no handler when it is removed (NoRemoveHandler). Parameters: Who is the
  attacker, Duration the rounds (the callers pass a roll or 63). Unused is the third byte: both callers push 0 and this
  routine never reads it. }
procedure ParalyzeAttackTarget(Who: PCharacter; Duration: Word; Unused: Byte);
begin
  AttackTarget := Who^.Combat^.Target;
  if not SavingThrow(AttackTarget, SaveKindParalysis, 0) then
  begin
    ShowHitMessage(AttackTarget, 1, 'is Paralyzed');
    AddAffect(AttackTarget, AffectParalysis, Duration, ParalysisData, NoRemoveHandler);
  end;
end;
{ ovl12:165D. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  The poison hook of an attack with save bonus 0: PoisonAttackTarget (ovl12:1545) with Bonus 0. Runs for affect $40 (id 64,
  InitAffectHandlers [V]). }
procedure PoisonAttackTargetBonus0(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  PoisonAttackTarget(Who, 0);
end;
{ ovl12:1671. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  The poison hook of an attack with save bonus 4: PoisonAttackTarget (ovl12:1545) with Bonus 4. Runs for affect $41 (id 65,
  InitAffectHandlers [V]). }
procedure PoisonAttackTargetBonus4(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  PoisonAttackTarget(Who, 4);
end;
{ ovl12:1685. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  The poison hook of an attack with save bonus 2: PoisonAttackTarget (ovl12:1545) with Bonus 2. Runs for affect $42 (id 66,
  InitAffectHandlers [V]). }
procedure PoisonAttackTargetBonus2(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  PoisonAttackTarget(Who, 2);
end;
{ ovl12:1699. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  It paralyses the character Who attacked last for RollDice(2, 8) rounds: ParalyzeAttackTarget (ovl12:15EB) with the
  unused byte 0. The bearer is the THRI-KREEN (MON6SPC block 118) [V]; it runs for affect $43 (id 67,
  InitAffectHandlers [V]). }
procedure ParalyzeAttackTargetFor2d8(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  ParalyzeAttackTarget(Who, RollDice(2, 8), 0);
end;
{ ovl12:16BB. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  Unless the character Who attacked last (Who^.Combat^.Target) has race RaceElf, it is paralysed for
  ParalysisDuration rounds: ParalyzeAttackTarget (ovl12:15EB) with the unused byte 0. The ghoul touch: the bearer is
  the GHOUL (MON4SPC and MON8SPC block 72, for 63 rounds) [V], elves are immune [I]; it runs for affect $44 (id 68,
  InitAffectHandlers [V]). }
procedure ParalyzeAttackTargetUnlessImmune(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if Who^.Combat^.Target^.Race <> RaceElf then
    ParalyzeAttackTarget(Who, ParalysisDuration, 0);
end;
{ ovl12:16E6. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  Paralyses the character Who attacked last for 1d9 plus ParalysisBaseRounds rounds: ParalyzeAttackTarget (ovl12:15EB).
  Runs for affect $45 (id 69, InitAffectHandlers [V]). }
procedure ParalyzeAttackTargetFor1d9Plus10(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  { the third argument is the unused byte: ParalyzeAttackTarget never reads it; this caller passes $FE, the others 0 }
  ParalyzeAttackTarget(Who, RollDice(1, ParalysisDieSides) + ParalysisBaseRounds, $FE);
end;
{ ovl12:170B. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  The poison hook of an attack with save bonus -2: PoisonAttackTarget (ovl12:1545) with Bonus -2. Runs for affect $46 (id 70,
  InitAffectHandlers [V]). }
procedure PoisonAttackTargetBonusMinus2(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  PoisonAttackTarget(Who, -2);
end;
{ ovl12:171F. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). Sets
  HookVetoFlag to 1 (the flag ovl12:0918 and ovl12:0C26 also set; AttackTargetAllowed reads it, OVL13.PAS lines 647..671) and
  takes AttackPenalty off AttackRoll
  without the test InvisibleTargetHardToHit (ovl12:0918) makes first. Runs for affect $47 (id 71, InitAffectHandlers [V]). }
procedure InvisibleTargetCannotBeTargeted(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  HookVetoFlag := 1;
  Dec(AttackRoll, AttackPenalty);
end;
{ ovl12:1730. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). When a 1d100 roll
  is at or below CamouflageInvisibilityChance it gives Who affect AffectInvisibility (AddAffect, ovl24:0E52) for
  InvisibilityDuration rounds with the Data InvisibilityData and no handler when it is removed:
  the same AddAffect
  as GiveInvisibilityForOneRound (ovl12:1363), but with the roll. runs for affect $48 (id 72,
  InitAffectHandlers [V]). }
procedure CamouflageGivesInvisibility(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if RollDice(1, 100) <= CamouflageInvisibilityChance then
    AddAffect(Who, AffectInvisibility, InvisibilityDuration, InvisibilityData,
    NoRemoveHandler);
end;
{ ovl12:176F. Affect handler of the blood drain (the AffectHandlers shape: Who, Affect and Mode; Mode 0 applies, any other
  value removes, ovl24:0000). AttackTarget becomes the combatant whose index is the affect's Data (CombatantRecord,
  DS:65BD). When Mode is 0 and Who and that combatant both still take part (Flag10D), Who sucks blood from it: "Sucks some
  Blood" is shown on Who (row CombatMessageRow), 1d4 damage is dealt to the combatant without a save (RollDiceCounted,
  DealDamage),
  Who's turn is ended (EndCombatTurn, its result is not read), then the affect's Duration div 16 must stay above the
  damage, which is taken off the Duration (times 16) while the combatant is still in the fight; otherwise AffectBloodDrain
  ($4B) is removed from Who. Else AffectHeldFast ($3A) is removed from the combatant and, when Mode is 0, the affect's
  Flag is cleared and AffectBloodDrain is removed from Who. Last, when both still take part, Who's combat byte ForcedFlight
  becomes 1 (CheckMorale
  forces
  a combatant with it nonzero to flee, ovl09:10D7). Runs for affect $4B (id 75, InitAffectHandlers [V]). }
procedure DrainBloodFromCombatant(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Turn: Byte;                   { the result of EndCombatTurn (ends Who's turn), never read }
  Dice: Byte;                   { the damage of the blood sucked }
begin
  AttackTarget := CombatantRecord[Affect^.Data];
  if (Mode <> 0) or (Who^.Flag10D = 0) or (AttackTarget^.Flag10D = 0) then
  begin
    RemoveAffect(AttackTarget, AffectHeldFast, nil);
    if Mode = 0 then
    begin
      Affect^.Flag := 0;
      RemoveAffect(Who, AffectBloodDrain, Affect);
    end;
    if (Who^.Flag10D <> 0) and (AttackTarget^.Flag10D <> 0) then
      Who^.Combat^.ForcedFlight := 1;
  end
  else
  begin
    ShowCharacterMessage(Who, 'Sucks some Blood', CombatMessageRow, True);
    Dice := RollDiceCounted(1, 4);
    DamageKind := 0;
    DealDamage(AttackTarget, Dice, 0, False);
    Turn := EndCombatTurn(Who);
    if (AttackTarget^.Flag10D <> 0) and (Affect^.Duration div 16 > Dice) then
      Dec(Affect^.Duration, Dice * 16)
    else
      RemoveAffect(Who, AffectBloodDrain, Affect);
  end;
end;
{ ovl12:18B5. Affect handler that starts a blood drain (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode
  are not read, ovl24:0000). The character Who attacked last (Who's combat Target) is copied into AttackTarget. Who gets
  AffectBloodDrain for BloodDrainDuration rounds, its Data the combatant index of AttackTarget (CombatantIndex), so
  DrainBloodFromCombatant (ovl12:176F) runs on it when it is removed. AttackTarget gets AffectHeldFast and that affect's
  handler runs at once (CallAffectHandler). Runs for affect $4C (id 76, InitAffectHandlers [V]). }
procedure StartBloodDrain(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  AttackTarget := Who^.Combat^.Target;
  AddAffect(Who, AffectBloodDrain, BloodDrainDuration, CombatantIndex(AttackTarget), RunsHandlerOnRemove);
  AddAffect(AttackTarget, AffectHeldFast, HeldFastDuration, HeldFastData, NoRemoveHandler);
  CallAffectHandler(AffectHeldFast, AttackTarget, nil, 0);
end;
{ ovl12:1935. Affect handler that holds a weak combat target fast (the AffectHandlers shape: Who, Affect and Mode; Affect and
  Mode are not read, ovl24:0000). The character Who attacked last (Who's combat Target) is copied into AttackTarget. When
  AttackTarget's Strength (TCharacter +$10) is below HeldFastStrengthLimit, Who gets AffectForcedAttack (Duration 0, its
  Data the combatant index of AttackTarget; its handler is ForcedAttack, ovl13:3A86, which runs when it is removed),
  AttackTarget gets AffectHeldFast and that affect's handler runs, and "is held fast" is shown on AttackTarget at row
  CombatMessageRow
  (ShowCharacterMessage). Runs for affect $4D (id 77, InitAffectHandlers [V]). }
procedure HoldWeakTargetFast(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  AttackTarget := Who^.Combat^.Target;
  if AttackTarget^.Strength < HeldFastStrengthLimit then
  begin
    AddAffect(Who, AffectForcedAttack, ForcedAttackDuration, CombatantIndex(AttackTarget), RunsHandlerOnRemove);
    AddAffect(AttackTarget, AffectHeldFast, HeldFastDuration, HeldFastData, NoRemoveHandler);
    CallAffectHandler(AffectHeldFast, AttackTarget, nil, 0);
    ShowCharacterMessage(AttackTarget, 'is held fast', CombatMessageRow, True);
  end;
end;
{ ovl12:19D9. Affect handler that revives Who (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000).
  ReviveCombatant (ovl24:1869) puts Who back on its square at Who's current hit points (HpCurrent) and returns False when it
  cannot be placed. Then Who gets AffectRevival for RevivalRetryDuration round, with the Data of Affect, so the revival is
  tried again (TryAddAffect; its result is stored and never read). Runs for affect $4E (id 78, InitAffectHandlers [V]). }
procedure ReviveOrRetryRevival(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Added: Boolean;               { the result of TryAddAffect, stored and never read }
begin
  if not ReviveCombatant(Who, Who^.HpCurrent) then
    Added := TryAddAffect(Who, AffectRevival, Affect^.Data, RevivalRetryDuration);
end;
{ ovl12:1A19. Affect handler that burns the character Who attacked last (the AffectHandlers shape: Who, Affect and Mode;
  none is read, ovl24:0000). DamageKind becomes 9 (KindFire or KindMagic, fire with the magic bit, as
  BoostFireAttackByTarget sets it), then 2d10 damage goes to Who's combat Target (Who^.Combat^.Target) without a save
  (DealDamage, ovl24:1344). Runs for affect $4F (id 79, InitAffectHandlers [V]). }
procedure FireAttackTargetFor2d10(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  DamageKind := KindFire or KindMagic;
  DealDamage(Who^.Combat^.Target, RollDiceCounted(2, 10), 0, False);
end;
{ ovl12:1A4C. Affect handler that splashes acid on the character Who attacked last (the AffectHandlers shape: Who, Affect
  and Mode; none is read, ovl24:0000). DamageKind becomes KindAcid, then 1d4 damage goes to Who's combat Target without a
  save (DealDamage, ovl24:1344). Runs for affect $50 (id 80, InitAffectHandlers [V]). }
procedure AcidAttackTargetFor1d4(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  DamageKind := KindAcid;
  DealDamage(Who^.Combat^.Target, RollDiceCounted(1, 4), 0, False);
end;
{ ovl12:1AAA. Affect handler that frightens the side of Who (the AffectHandlers shape: Who, Affect and Mode; Affect and
  Mode are not read, ovl24:0000). It walks the party list from PartyListHead (TCharacter +$104 is the next member).
  Every member
  with Flag10D set on the side of Who (OpposingSide, the side of the actor) makes a SavingThrow of kind SaveKindSpell. Its
  HighestLevel (+$73) decides the affect: 0 to 3 gives AffectParalysis with the message 'is paralyzed with fear', 4 or 5
  gives AffectCurse with 'is weakened by fear'; the Duration is 0 for both, and a successful save negates the affect
  (ApplyAffect, ovl24:1656). Other levels get nothing. Runs for affect $51 (id 81, InitAffectHandlers [V]). }
procedure FrightenSideWithFear(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Scan: PCharacter;             { walks the party list: first member, then Next }
  FearSaved: Boolean;           { the fear save of Scan }
begin
  Scan := PCharacter(PartyListHead);
  while Scan <> nil do
  begin
    if Scan^.Flag10D <> 0 then
      if OpposingSide(Who) = Scan^.Side then
      begin
        FearSaved := SavingThrow(Scan, SaveKindSpell, 0);
        case Scan^.HighestLevel of
          0..FearParalysisMaxLevel: ApplyAffect(Scan, AffectParalysis, PermanentDuration, FearData, NoRemoveHandler,
            SaveNegatesAffect, FearSaved, 'is paralyzed with fear');
          FearWeakenMinLevel, FearWeakenMaxLevel: ApplyAffect(Scan, AffectCurse, PermanentDuration, FearData,
            NoRemoveHandler, SaveNegatesAffect, FearSaved, 'is weakened by fear');
        end;
      end;
    Scan := Scan^.Next;
  end;
end;
{ ovl12:1BA8. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It takes
  affect AffectParalyzeSide off every member of the party list (PartyListHead, +$104 is the next member) first. Then each
  member with Flag10D set on the side of Who (OpposingSide) makes a paralysis save (SaveKindParalysis) with a bonus
  of 1 when its side has six or more members (SideCounts, the side's count [?]) and 2 when it is a human,
  and gets AffectParalysis for 1d4 rounds with Data FearData; "is paralyzed with fear" is shown on it, and a successful
  save negates the affect. Runs for affect $52 (id 82, InitAffectHandlers [V]). }
procedure ParalyzeSideWithFear(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Scan: PCharacter;             { walks the party list: first member, then Next }
  Bonus: Byte;                  { the save bonus of Scan }
  Saved: Boolean;               { Scan's paralysis save }
begin
  Scan := PCharacter(PartyListHead);
  while Scan <> nil do
  begin
    RemoveAffect(Scan, AffectParalyzeSide, nil);
    if Scan^.Flag10D <> 0 then
      if OpposingSide(Who) = Scan^.Side then
      begin
        Bonus := 0;
        if SideCounts[ShortInt(Scan^.Side)] >= LargeSideCount then
          Inc(Bonus);
        if Scan^.Race = RaceHuman then
          Inc(Bonus, HumanFearSaveBonus);
        Saved := SavingThrow(Scan, SaveKindParalysis, Bonus);
        ApplyAffect(Scan, AffectParalysis, RollDice(1, FearDieSides), FearData, NoRemoveHandler, SaveNegatesAffect,
          Saved, 'is paralyzed with fear');
      end;
    Scan := Scan^.Next;
  end;
end;
{ ovl12:1CAD. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000): a stoning gaze
  [I]. "gazes..." is shown on Who (row CombatMessageRow), and the gaze line is drawn from Who to the character Who
  attacked last
  (AttackTarget, a copy of Combat^.Target). When Who has affect AffectGazeReflectable (HasAffect), the readied items of
  AttackTarget are walked: a readied item with a NameNum of MirrorNameNum turns the gaze back: "reflects it!" is shown
  on AttackTarget (row ReflectRow), the line is drawn back, and the gaze falls on Who (AttackTarget := Who). The gaze target
  then makes a stone save (SaveKindStone, no bonus); when it fails, DropFromFight takes it out of the fight with StatusStoned
  and "is Stoned". Runs for affect $53 (id 83, InitAffectHandlers [V]). }
procedure GazeStonesTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;                  { the items of AttackTarget, walked from its first }
  Reflected: Boolean;           { a readied reflecting item was found: the gaze turns back on Who }
  FoundAffect: Pointer;         { the affect HasAffect gives back for AffectGazeReflectable }
begin
  AttackTarget := Who^.Combat^.Target;
  ShowCharacterMessage(Who, 'gazes...', CombatMessageRow, False);
  DrawCombatIcon(GazeAnimation);
  WalkCombatLine(CombatantX(Who), CombatantY(Who), CombatantX(AttackTarget), CombatantY(AttackTarget),
    GazeLineKind, GazeLineFlag);
  if HasAffect(Who, AffectGazeReflectable, FoundAffect) then
  begin
    Reflected := False;
    Item := AttackTarget^.Items;
    while (Item <> nil) and not Reflected do
    begin
      if Item^.Readied then
        if (Item^.NameNum[1] = MirrorNameNum) or (Item^.NameNum[2] = MirrorNameNum) or
          (Item^.NameNum[3] = MirrorNameNum) then
        begin
          ShowCharacterMessage(AttackTarget, 'reflects it!', ReflectRow, False);
          WalkCombatLine(CombatantX(AttackTarget), CombatantY(AttackTarget), CombatantX(Who), CombatantY(Who),
            GazeLineKind, GazeLineFlag);
          Reflected := True;
          AttackTarget := Who;
        end;
      Item := Item^.Next;
    end;
  end;
  if not SavingThrow(AttackTarget, SaveKindStone, 0) then
    DropFromFight(AttackTarget, StatusStoned, 'is Stoned');
end;
{ ovl12:1E77. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000): a charm gaze
  [I]. Who's gaze reaches the character Who attacked last (AttackTarget) when AttackTargetAllowed allows it and WalkLine
  walks the line from Who to AttackTarget's cell (WalkLine may move the end cell, EndX and EndY). "Gazes..." is shown on Who
  (row CombatMessageRow), the gaze line is drawn to AttackTarget as GazeStonesTarget draws it (WalkCombatLine), CastingSpell
  becomes 10,
  and AttackTarget gets the charm affect AffectCharm for good with Data: Who's side in bit 7 (ControlSideBit) and
  CharmData. A successful fear save (SavingThrow kind 4, CharmSaveBonus) negates it, and "is charmed" is shown on it.
  Then, when AttackTarget has the affect, its handler runs at once (CallAffectHandler, Mode 0). Runs for affect $54 (id 84,
  InitAffectHandlers [V]). }
procedure GazeCharmsTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  StepCount: Word;              { the steps WalkLine takes }
  FoundAffect: Pointer;         { the charm affect of AttackTarget, as HasAffect gives it back }
  EndX, EndY: ShortInt;         { AttackTarget's cell, the end of the walk: WalkLine may change it }
begin
  AttackTarget := Who^.Combat^.Target;
  EndX := CombatantX(AttackTarget);
  EndY := CombatantY(AttackTarget);
  if not AttackTargetAllowed(Who, AttackTarget) then
    Exit;
  if not WalkLine(CombatantX(Who), CombatantY(Who), EndX, EndY, StepCount, Pointer(CombatMap)) then
    Exit;
  ShowCharacterMessage(Who, 'Gazes...', CombatMessageRow, False);
  DrawCombatIcon(GazeAnimation);
  WalkCombatLine(CombatantX(Who), CombatantY(Who), CombatantX(AttackTarget), CombatantY(AttackTarget),
    GazeLineKind, GazeLineFlag);
  CastingSpell := SpellCharmPerson;
  ApplyAffect(AttackTarget, AffectCharm, PermanentDuration, ShortInt(Who^.Side) * ControlSideBit + CharmData,
  RunsHandlerOnRemove,
    SaveNegatesAffect, SavingThrow(Who^.Combat^.Target, SaveKindSpell, CharmSaveBonus), 'is charmed');
  if HasAffect(AttackTarget, AffectCharm, FoundAffect) then
    CallAffectHandler(AffectCharm, AttackTarget, FoundAffect, 0);
end;
{ ovl12:2122. Level drain: Who loses Count levels (the callers are DrainAttackTargetLevel and
  DrainAttackTargetTwoLevels, ovl12:23A4 and 23C2).
  Shows "is drained " followed by "N levels" or "a level" on Who at row CombatMessageRow (ShowCharacterMessage). When Who's
  Status is StatusAnimated (1, "Animated" in StatusNames, not Dead: the test reads that value [I]) Who is dead forever:
  DropFromFight with StatusGone, and HpMax is 0. Otherwise,
  for each of the Count levels: the counter Pad74[DrainedLevels] (+$74, the levels drained) goes up; the total of all class
  levels (Total) is taken; Quotient = HpMax div Total hit points are lost: for each of them HpMax, HpB1 and
  HpCurrent (the current hit points) go down by one while above 0 and Pad74[LostHitPoints] (the lost hit points, the
  third number of ShowDebugTrace, ovl33:0004) goes up. Then, when Who's HighestLevel is below 2, the
  character is dead forever (with a Count of 2 its highest class level is cleared too). Otherwise one level
  comes off the class that holds the highest level (nested HighestLevelClass), and when no hit points are
  left (HpCurrent 0) and Status is not StatusDead Who is killed (DropFromFight, "is killed"). RecalcClassStats (ovl23)
  runs, then HighestLevel becomes that class's level, Experience (+$AC) the experience floor the nested
  routine found, and RecalcCombatValues redraws Who. The trace line 'max,cur,lost' is shown in debug mode only.
  Parameters: Who (the victim, a far pointer), Count (the levels drained, 1 or more).
  QUIRK ovl12:2122: Total 0 (a character with no class level) divides by zero. }
procedure DrainLevels(Who: PCharacter; Count: Byte);
var
  Msg: String40;                { the number of levels as text: "3 levels" or "a level" }
  CurXp: LongInt;               { the experience floor of the class the nested routine looks at (written by it) }
  BestXp: LongInt;              { the experience floor of the class found so far; Who's Experience after the drain }
  ClassIndex: ShortInt;         { the class counter of the total of levels (sign-extended, as the class index is) }
  Step: Byte;                   { the level being drained, 1..Count }
  Total: Byte;                  { all class levels of Who added up }
  Quotient: Byte;               { the hit points of one level: HpMax div Total }
  Point: Byte;                  { the hit point of Quotient being lost }

  { ovl12:2002 (nested in ovl12:2122, which passes its frame as the hidden parameter: push bp; push cs; call).
    Returns the class of Who with the highest level: a class whose level is at least the best so far is
    taken when its experience floor (ExperienceTable, 0 for level 1 or less) is at least BestXp or is -1
    [?]; BestXp (of the parent) and BestLevel take its values. QUIRK ovl12:2002: -1 is taken whatever the
    best so far. }
  function HighestLevelClass: ShortInt;
  var
    J: ShortInt;
    BestLevel: ShortInt;
    Level: ShortInt;
  begin
    BestXp := 0;
    BestLevel := 0;
    for J := 0 to LastClass do
    begin
      Level := Who^.ClassLevels[J];
      if Level > 1 then
        CurXp := ExperienceTable[J, Level]
      else
        CurXp := 0;
      if Level >= BestLevel then
        if (CurXp >= BestXp) or (CurXp = -1) then
        begin
          BestXp := CurXp;
          HighestLevelClass := J;
          BestLevel := Level;
        end;
    end;
  end;

begin
  if Count > 1 then
    Msg := ByteToText(Count) + ' levels'
  else
    Msg := 'a level';
  ShowCharacterMessage(Who, 'is drained ' + Msg, CombatMessageRow, True);
  if Who^.Status = StatusAnimated then
  begin
    DropFromFight(Who, StatusGone, 'is dead forever');
    Who^.HpMax := 0;
    Exit;
  end;
  for Step := 1 to Count do
  begin
    if Who^.Status <> StatusGone then
    begin
      Inc(Who^.Pad74[DrainedLevels]);
      Total := 0;
      for ClassIndex := 0 to LastClass do
        Inc(Total, Who^.ClassLevels[ClassIndex]);
      Quotient := Who^.HpMax div Total;
      ShowDebugTrace('max,cur,lost', Who^.HpMax, Who^.HpCurrent, Who^.Pad74[LostHitPoints]);
      for Point := 1 to Quotient do
      begin
        if Who^.HpMax > 0 then
          Dec(Who^.HpMax);
        if Who^.HpB1 > 0 then
          Dec(Who^.HpB1);
        if Who^.HpCurrent > 0 then
          Dec(Who^.HpCurrent);
        Inc(Who^.Pad74[LostHitPoints]);
      end;
      if Who^.HighestLevel < 2 then
      begin
        DropFromFight(Who, StatusGone, 'is dead forever');
        Who^.HpMax := 0;
        if (Who^.ClassLevels[HighestLevelClass] > 0) and (Count = 2) then
          Who^.ClassLevels[HighestLevelClass] := 0;
      end
      else
      begin
        Dec(Who^.ClassLevels[HighestLevelClass]);
        if (Who^.HpCurrent = 0) and (Who^.Status <> StatusDead) then
          DropFromFight(Who, StatusDead, 'is killed');
        RecalcClassStats(Who);
      end;
      Who^.HighestLevel := Who^.ClassLevels[HighestLevelClass];
      Who^.Experience := BestXp;
      RecalcCombatValues(Who);
    end;
  end;
end;
{ ovl12:23A4. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000)
  that drains one level from the character Who attacked last (Who's combat Target, TCombatant +$A): DrainLevels
  takes one level off it, with "is drained a level" shown on it. Runs for affect $55 (id 85, InitAffectHandlers [V]). }
procedure DrainAttackTargetLevel(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  DrainLevels(Who^.Combat^.Target, 1);
end;
{ ovl12:23C2. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000)
  that drains two levels from the character Who attacked last (Who's combat Target, TCombatant +$A): DrainLevels
  takes two levels off it, with "is drained 2 levels" shown on it. Runs for affect $56 (id 86, InitAffectHandlers [V]). }
procedure DrainAttackTargetTwoLevels(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  DrainLevels(Who^.Combat^.Target, 2);
end;
{ ovl12:23EC. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000)
  that gives the rot to the character Who attacked last (Who's combat Target, copied into AttackTarget). Unless that
  character already has the healing block AffectMummyDisease (HasAffect finds it), it gets the block for
  MummyDiseaseDuration rounds, then AffectRot for RotDuration rounds with the Data (1d6 * RotStage) + RotDataLow: the
  rot stage is the high nibble (ProgressRot, ovl12:1399). "is Diseased" is shown on it at row CombatMessageRow. Runs
  for affect $57
  (id 87, InitAffectHandlers [V]). }
procedure CauseRotOnAttackTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  FoundAffect: Pointer;         { the healing block HasAffect looks for on AttackTarget }
begin
  AttackTarget := Who^.Combat^.Target;
  if not HasAffect(AttackTarget, AffectMummyDisease, FoundAffect) then
  begin
    AddAffect(AttackTarget, AffectMummyDisease, MummyDiseaseDuration, HealingBlockData, RunsHandlerOnRemove);
    AddAffect(AttackTarget, AffectRot, RotDuration, (RollDice(1, 6) * RotStage) + RotDataLow, RunsHandlerOnRemove);
    ShowCharacterMessage(AttackTarget, 'is Diseased', CombatMessageRow, True);
  end;
end;
{ ovl12:2490. an affect handler (the AffectHandlers shape: Who, Affect and Mode; Who and Mode are not
  read, ovl24:0000). It works on Affect's Data (+3). In combat round 0 (CombatRound, the round counter, is 0) with AttackRoll 0
  it keeps only DataLowNibble of Data. Otherwise, when MissedBit is clear, AttackRoll becomes MissRoll (a miss, ovl24:0CD5)
  and MissedBit is set, so the attack misses once. Runs for affect $59 (id 89, InitAffectHandlers [V]). }
procedure ForceFirstAttackMiss(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (CombatRound = 0) and (AttackRoll = 0) then
    Affect^.Data := Affect^.Data and DataLowNibble
  else if (Affect^.Data and MissedBit) = 0 then
  begin
    AttackRoll := MissRoll;
    Affect^.Data := Affect^.Data or MissedBit;
  end;
end;
{ ovl12:24D9. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  For the first saving throw kind (SaveKind 0, SaveKindPoison [I]) it adds a bonus to SaveRoll from Who's Constitution
  (+$14): 1 for 4..6, 2 for 7..10, 3 for 11..13, 4 for 14..17 and 5 for 18..20. Runs for affect $5A (id 90,
  InitAffectHandlers [V]).
  QUIRK ovl12:24D9: a Constitution outside 4..20 sets no bonus, so the local Bonus keeps what the stack held, and that
  value is added to SaveRoll. }
procedure DwarfHalflingPoisonSaveBonus(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Bonus: Byte;                  { the bonus of Who's Constitution bracket }
begin
  if SaveKind = SaveKindPoison then
  begin
    { The bonus by Constitution bracket, the same table in ovl12:24D9 and ovl12:268A: 4..6 gives 1, 7..10 gives 2, 11..13 gives
      3, 14..17 gives 4 and 18..20 gives 5 (the dwarf, gnome and halfling bonus of AD&D [I]). }
    case Who^.Constitution of
      4..6: Bonus := 1;
      7..10: Bonus := 2;
      11..13: Bonus := 3;
      14..17: Bonus := 4;
      18..20: Bonus := 5;
    end;
    SaveRoll := SaveRoll + Bonus;
  end;
end;
{ ovl12:2556. an affect handler on the damage hook (the AffectHandlers shape: Who, Affect and Mode; Affect
  and Mode are not read, ovl24:0000; Who is read for its message). When CastingSpell is SpellMagicMissile the pending hook is
  cancelled (CancelPendingHook(0): the damage is dropped) and "is unaffected" is shown on Who at row CombatMessageRow.
  Otherwise,
  when the damage is electricity (KindElectricity in DamageKind), the hook is cancelled without the message. Runs for affect
  $5B (id 91, InitAffectHandlers [V]). }
procedure ImmuneToMagicMissileAndElectricity(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if CastingSpell = SpellMagicMissile then
  begin
    CancelPendingHook(0);
    ShowCharacterMessage(Who, 'is unaffected', CombatMessageRow, True);
  end
  else if (DamageKind and KindElectricity) <> 0 then
    CancelPendingHook(0);
end;
{ ovl12:25A2. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000).
  When the damage being dealt is fire (DamageKind bit KindFire, DS:6819), it halves DamageAmount (DS:6818): HalveFireDamage
  (ovl12:06E4) without its SaveRoll bonus. Runs for affect $5D (id 93, InitAffectHandlers [V]). }
procedure HalveFireDamageNoSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (DamageKind and KindFire) <> 0 then
    DamageAmount := DamageAmount shr 1;
end;
{ ovl12:25BC. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000).
  It takes the first slot item of SelectedCharacter (FirstSlotItem, ovl12:101D). When there is one and byte 7 of its
  ItemTable row (ItemTable[ItemType].Pad7[7], DS:5589; the row is indexed by the item type, the meaning of byte 7 is
  not known [?]) has ItemRowFlags bits set, DamageAmount is halved. runs for affect $5E (id 94,
  InitAffectHandlers
  [V]). Game meaning: carried only by the JUJU ZOMBIE (MON4SPC block 29) [V]: damage is halved when the
  attacker's weapon has ItemTable byte 7 flag $01 (piercing) or $80 (bludgeoning) [I]. }
procedure HalveDamageForFirstSlotItem(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;
begin
  Item := FirstSlotItem(SelectedCharacter);
  if Item <> nil then
    if (ItemTable[Item^.ItemType].Pad7[7] and ItemRowFlags) <> 0 then
      DamageAmount := DamageAmount shr 1;
end;
{ ovl12:2610. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It clears the
  affect's Flag, so the handler does not run again when the affect is removed. When Who still takes part in the fight
  (Flag10D set), Who falls dead: DropFromFight takes Who out with StatusDead and the text 'Falls dead'. Runs for affect $5F
  (id 95, InitAffectHandlers [V]). }
procedure FallDeadIfInFight(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Affect^.Flag := 0;
  if Who^.Flag10D <> 0 then
    DropFromFight(Who, StatusDead, 'Falls dead');
end;
{ ovl12:264B. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It cancels the
  damage (DamageAmount := 0) unless SelectedCharacter's first slot item (FirstSlotItem, ovl12:101D) is a magic item
  (Plus, +$32, not 0) or has NameNum[3] (+$31) SilverNameNum; with no first slot item the damage is cancelled.
  Runs for affect $60 (id 96, InitAffectHandlers [V]). }
procedure CancelDamageUnlessMagicSlotItem(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;
begin
  Item := FirstSlotItem(SelectedCharacter);
  if (Item = nil) or ((Item^.Plus = 0) and (Item^.NameNum[3] <> SilverNameNum)) then
    DamageAmount := 0;
end;
{ ovl12:268A. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
  For the saving throw kinds 2 and 4 (SaveKind, DS:682A; kind 4 is SaveKindSpell [I]) it adds to SaveRoll the Constitution
  bonus of DwarfHalflingPoisonSaveBonus (ovl12:24D9): 1 for 4..6, 2 for 7..10, 3 for 11..13, 4 for 14..17 and 5 for 18..20.
  Runs for affect $61 (id 97, InitAffectHandlers [V]).
  QUIRK ovl12:268A: a Constitution outside 4..20 sets no bonus, so the local Bonus keeps what the stack held, and that
  value is added to SaveRoll. }
procedure DwarfGnomeHalflingWandSpellSaveBonus(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Bonus: Byte;                  { the bonus of Who's Constitution bracket }
begin
  if (SaveKind = SaveKindSpell) or (SaveKind = SaveKindWand) then
  begin
    { The bonus by Constitution bracket, the same table in ovl12:24D9 and ovl12:268A: 4..6 gives 1, 7..10 gives 2, 11..13 gives
      3, 14..17 gives 4 and 18..20 gives 5 (the dwarf, gnome and halfling bonus of AD&D [I]). }
    case Who^.Constitution of
      4..6: Bonus := 1;
      7..10: Bonus := 2;
      11..13: Bonus := 3;
      14..17: Bonus := 4;
      18..20: Bonus := 5;
    end;
    SaveRoll := SaveRoll + Bonus;
  end;
end;
{ ovl12:2700. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read). Who gets
  RegainedHitPoints back on HpCurrent (the current hit points [I], TCharacter +$11B), but never more than HpMax (+$32).
  Runs for affect $62 (id 98, InitAffectHandlers [V]). }
procedure RegainHitPoints(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Inc(Who^.HpCurrent, RegainedHitPoints);
  if Who^.HpCurrent > Who^.HpMax then
    Who^.HpCurrent := Who^.HpMax;
end;
{ ovl12:2730. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read). A dying character
  (StatusDying) gets DyingRevivalPoints less the rounds it has bled (DyingRounds, TCombatant +$E), so one that has bled
  six rounds or more stays dead; an unconscious one (StatusUnconscious) gets DyingRevivalPoints. When ReviveCombatant
  (ovl24:1869) puts Who back on the map, Who gets AffectFallsDead for 1d4 plus one rounds, and the affect Affect has its
  Flag cleared (NoRemoveHandler) and is removed, so its handler does not run. Runs for affect $63 (id 99,
  InitAffectHandlers [V]). }
procedure ReviveDyingCharacter(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  HitPoints: Byte;              { the hit points the revival gives; 0 when there is none }
begin
  HitPoints := 0;
  if Who^.Status = StatusDying then
    if Who^.Combat^.DyingRounds < DyingRevivalPoints then
      HitPoints := DyingRevivalPoints - Who^.Combat^.DyingRounds;
  if Who^.Status = StatusUnconscious then
    HitPoints := DyingRevivalPoints;
  if HitPoints > 0 then
    if ReviveCombatant(Who, HitPoints) then
    begin
      AddAffect(Who, AffectFallsDead, RollDice(1, AffectFallsDeadDieSides) + 1, DataFF, RunsHandlerOnRemove);
      Affect^.Flag := NoRemoveHandler;
      RemoveAffect(Who, AffectReviveDying, Affect);
    end;
end;
{ ovl12:27D9. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read). Unless the damage being dealt
  (DamageKind, DS:6819) has the fire bit (KindFire) or the acid bit (KindAcid), Who gets AffectRetryRevival for 3d6 rounds
  with the Data $FF, and its handler runs when it is removed. Runs for affect $64 (id 100, InitAffectHandlers [V]). }
procedure GiveAffectUnlessFireOrAcid(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (DamageKind and KindFire) = 0 then
    if (DamageKind and KindAcid) = 0 then
      AddAffect(Who, AffectRetryRevival, RollDice(AffectRetryRevivalDice, AffectRetryRevivalSides), DataFF,
      RunsHandlerOnRemove);
end;
{ ovl12:2814. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read). Unless HasAffect finds
  AffectRegainHitPoints or AffectRegenerating on Who, Who gets AffectRegenerating (Regenerating) for RegeneratingDuration
  rounds
  with the Data $FF, and its handler runs when it is removed. Runs for affect $65 (id 101, InitAffectHandlers [V]). }
procedure GiveRegeneratingUnlessAffected(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  FoundAffect: Pointer;         { the affect HasAffect looks for; it is given back and never read }
begin
  if not HasAffect(Who, AffectRegainHitPoints, FoundAffect) then
    if not HasAffect(Who, AffectRegenerating, FoundAffect) then
      AddAffect(Who, AffectRegenerating, RegeneratingDuration, DataFF, RunsHandlerOnRemove);
end;
{ ovl12:2866. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read). ReviveCombatant
  (ovl24:1869) tries to put Who back on the map with its full HpMax (+$32). When that fails, Who gets AffectRetryRevival
  for AffectRetryRevivalRetryDuration round with the Data of Affect, when TryAddAffect allows it; the result is stored
  and never read. Runs for affect $66 (id 102, InitAffectHandlers [V]). }
procedure RetryRevivalAtFullHitPoints(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Added: Boolean;               { the result of TryAddAffect, stored and never read }
begin
  if not ReviveCombatant(Who, Who^.HpMax) then
    Added := TryAddAffect(Who, AffectRetryRevival, Affect^.Data, AffectRetryRevivalRetryDuration);
end;
{ ovl12:28BF. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read). Affect's Flag is
  cleared (NoRemoveHandler) so its handler does not run again on removal. Then the cursor is shown on Who
  (ShowCursorOn, ovl31:1298; margin 3, cursor 0 [?]) and Who drops out of the fight with StatusFled and the text
  'Turns gaseous and escapes' (DropCombatant, ovl24:0F06). Runs for affect $67 (id 103, InitAffectHandlers [V]). }
procedure TurnGaseousAndEscape(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  Affect^.Flag := NoRemoveHandler;
  ShowCursorOn(Who, GaseousCursorMargin, GaseousShowCursor);
  DropCombatant(Who, StatusFled, 'Turns gaseous and escapes');
end;
{ ovl12:2901. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It runs
  AvoidDistantAttack on Who with DistantAvoidChance (60): a 1d100 roll of 60 or less avoids the attack in progress.
  Runs for affect $68 (id 104, InitAffectHandlers [V]). }
procedure AvoidDistantAttackByChance(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  AvoidDistantAttack(Who, DistantAvoidChance);
end;
{ ovl12:2915. Helper of the two hook cancels ovl12:2976 and ovl12:2984, which pass Chance. Only when a hook is offered
  (HookAffectId is not 0) or the damage is magical (DamageKind bit KindMagic), a 1d100 roll at or below a threshold
  cancels the pending hook (CancelPendingHook(0): the damage is dropped). The threshold is Chance less 5 for each
  point that Level falls short of 11. Level is SpellCasterLevel of CastingSpell (RES12 00BA:26C2 [V]): the cleric level for
  spell class 0, the magic-user level for class 1, 12 for class 2, or 6 while ItemAffectUse is set. What the threshold
  measures is not known [?].
  QUIRK ovl12:2915: Threshold is a Byte, but Chance - 5 * (11 - Level) is worked out in 16 bits and the result is
  stored in the byte, so a negative value wraps to 256 plus the value (-5 gives 251). With Chance 15 and Level below 8,
  or Chance 50 and Level 0, the wrapped threshold is 251 or more, so the roll almost always cancels the hook. With
  Level above 11 (12 for class 2) the threshold rises above Chance. Never fixed. }
procedure RollMagicResistance(Chance: Byte);
var
  Level: Byte;                  { SpellCasterLevel of CastingSpell: a class level, 12 or 6 (see the QUIRK) }
  Threshold: Byte;              { Chance - 5 * (11 - Level), wrapped to a byte (QUIRK ovl12:2915) }
begin
  Level := SpellCasterLevel(CastingSpell);
  Threshold := Chance - 5 * (11 - Level);
  if (HookAffectId = 0) and ((DamageKind and KindMagic) = 0) then
    Exit;
  if RollDice(1, 100) <= Threshold then
    CancelPendingHook(0);
end;
{ ovl12:2976. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It calls
  RollMagicResistance with HookChanceHalf (50): the pending hook may be cancelled by a roll. Runs for affect $69 (id 105,
  InitAffectHandlers [V]). }
procedure CancelHookByHalfChance(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  RollMagicResistance(HookChanceHalf);
end;
{ ovl12:2984. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It calls
  RollMagicResistance with HookChanceLow (15): the pending hook is cancelled by a roll less often than at 50.
  Runs for affect $6A (id 106, InitAffectHandlers [V]). }
procedure CancelHookByLowChance(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  RollMagicResistance(HookChanceLow);
end;
{ ovl12:2992. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). A 1d100
  roll at or below ElfCharmSleepResistance (90) cancels the pending hook of affect AffectEndsTurn, then the one of the charm
  (AffectCharm), each through CancelPendingHook. Runs for affect $6B (id 107, InitAffectHandlers [V]). }
procedure ElfResistsCharmAndSleep(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if RollDice(1, 100) <= ElfCharmSleepResistance then
  begin
    CancelPendingHook(AffectEndsTurn);
    CancelPendingHook(AffectCharm);
  end;
end;
{ ovl12:29B6. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It cancels
  the pending hook of the charm (AffectCharm) and then the one of affect AffectEndsTurn, without a roll. Runs for affect $6C
  (id 108, InitAffectHandlers [V]). }
procedure ImmuneToCharmAndSleep(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  CancelPendingHook(AffectCharm);
  CancelPendingHook(AffectEndsTurn);
end;
{ ovl12:29CB. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). It cancels
  the pending hook of the paralysis affect (AffectParalysis, $34) with CancelPendingHook, and nothing else. 
  runs for affect $6D (id 109, InitAffectHandlers [V]). Game meaning: immunity to Hold, carried by SPECTRE, WIGHT,
  WRAITH and FERRAN MARTINEZ (MON4SPC) [V]. }
procedure CancelParalysisHook(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  CancelPendingHook(AffectParalysis);
end;
{ ovl12:29D9. Damage hook (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). While the
  damage being dealt is cold (DamageKind bit KindCold, DS:6819), CancelPendingHook(0) drops it: DamageAmount and the
  hook offered are cleared. runs for affect $6E (id 110, InitAffectHandlers [V]). Game meaning: cold immunity of the
  undead (SPECTRE, WIGHT, WRAITH, SKELETON, GIANT SKELETON, ZOMBIE, JUJU ZOMBIE, MUMMY, FERRAN MARTINEZ) [V monster data]. }
procedure CancelColdDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (DamageKind and KindCold) <> 0 then
    CancelPendingHook(0);
end;
{ ovl12:29F0. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). It cancels
  the pending hooks of the poison affect (AffectPoisoned, $37) and of the paralysis affect (AffectParalysis, $34). Then,
  when the saving throw in progress is the poison save (SaveKind 0, SaveKindPoison), SaveRoll becomes AlwaysSaves, so that
  save succeeds. runs for affect $6F (id 111, InitAffectHandlers [V]). Game meaning: poison and hold immunity of
  SPECTRE, WIGHT, WRAITH and FERRAN MARTINEZ (affect $6F, AffectPoisonImmunity) [V monster data, I meaning]. }
procedure CancelPoisonAndParalysisHooks(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  CancelPendingHook(AffectPoisoned);
  CancelPendingHook(AffectParalysis);
  if SaveKind = SaveKindPoison then
    SaveRoll := AlwaysSaves;
end;
{ ovl12:2A11. Damage hook (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). While the
  damage being dealt is fire (DamageKind bit KindFire, DS:6819), CancelPendingHook(0) drops it: DamageAmount and the
  hook offered are cleared. runs for affect $70 (id 112, InitAffectHandlers [V]). Game meaning: fire immunity, carried
  by the FIRE GIANT (MON5SPC block 56) [V]. }
procedure CancelFireDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (DamageKind and KindFire) <> 0 then
    CancelPendingHook(0);
end;
{ ovl12:2A28. Damage hook (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). While the
  damage is fire (DamageKind bit KindFire, DS:6819), each of the LastDiceCount dice of the last roll takes one point off
  DamageAmount, and it never goes below LastDiceCount. The twin of ReduceFireDamageByRoll (ovl12:1490), which takes
  FireReductionPerDie per die and also adds the save bonus and cancels a non-magic hit. runs for affect $71
  (id 113, InitAffectHandlers [V]). Game meaning: fire resistance of the EFREETI (MON4SPC 70, MON8SPC 124) [V]. }
procedure ReduceFireDamageOnePerDie(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  I: Byte;
begin
  if (DamageKind and KindFire) <> 0 then
    for I := 1 to LastDiceCount do
    begin
      Dec(DamageAmount);
      if DamageAmount < LastDiceCount then
        DamageAmount := LastDiceCount;
    end;
end;
{ ovl12:2A6D. Damage hook (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). While the
  damage is electricity (DamageKind bit KindElectricity, DS:6819), it halves DamageAmount (DS:6818): the electricity
  twin of HalveColdDamage (ovl12:03E1), without its save bonus. runs for affect $72 (id 114,
  InitAffectHandlers [V]). Game meaning: carried only by the VAMPIRE [V]. }
procedure HalveElectricityDamage(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (DamageKind and KindElectricity) <> 0 then
    DamageAmount := DamageAmount shr 1;
end;
{ ovl12:2A87. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000).
  The first slot item of SelectedCharacter (FirstSlotItem, ovl12:101D) is looked at: when there is one and its
  ItemTable byte 7 (ItemTable[ItemType].Pad7[7], DS:5589) is 0 or odd, DamageAmount is halved. runs for
  affect $73 (id 115, InitAffectHandlers [V]). Game meaning: SKELETON and GIANT SKELETON [V]: damage is halved unless
  the weapon is bludgeoning (ItemTable byte 7 is 0 or odd), the AD&D skeleton rule [I]. }
procedure HalveDamageByFirstSlotItemRow(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;
begin
  Item := FirstSlotItem(SelectedCharacter);
  if Item <> nil then
    if (ItemTable[Item^.ItemType].Pad7[7] = 0) or ((ItemTable[Item^.ItemType].Pad7[7] and 1) <> 0) then
      DamageAmount := DamageAmount shr 1;
end;
{ ovl12:2AE6. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000).
  When the first slot item of SelectedCharacter (FirstSlotItem, ovl12:101D) has Plus (+$32, a signed byte) above 0,
  DamageAmount is halved. runs for affect $74 (id 116, InitAffectHandlers [V]). Game meaning: the MUMMY only [V]: half
  damage from a weapon with Plus above 0 [I]. }
procedure HalveDamageForEnchantedSlotItem(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;
begin
  Item := FirstSlotItem(SelectedCharacter);
  if Item <> nil then
    if Item^.Plus > 0 then
      DamageAmount := DamageAmount shr 1;
end;
{ ovl12:2B20: retf 10: 10 bytes of parameters; 4 bytes of locals }
{ ovl12:2B20. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000).
  When the first slot item of SelectedCharacter (SlotItems[0], TCharacter +$CC) has ItemType $55, DamageAmount
  becomes 1d6 plus one (RollDiceCounted, ovl24:0E2E). runs for affect $75 (id 117, InitAffectHandlers [V]). Game
  meaning: every undead but FERRAN MARTINEZ (SPECTRE, WIGHT, WRAITH, SKELETONS, ZOMBIES, MUMMY, VAMPIRE) [V]; item
  type $55 is Vial Of Holy Water [V item files]: damage 1d6 + 1, holy water against undead [I]. }
procedure SetDamageFromHolyWater(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;
begin
  Item := SelectedCharacter^.SlotItems[0];
  if Item <> nil then
    if Item^.ItemType = ItemHolyWater then
      DamageAmount := RollDiceCounted(1, HolyWaterDieSides) + 1;
end;
{ ovl12:2B63. Damage hook (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). While the damage is
  cold (DamageKind bit KindCold, DS:6819), DamageAmount is halved: HalveColdDamage (ovl12:03E1) without its SaveRoll
  bonus, the cold twin of HalveFireDamageNoSave (ovl12:25A2). runs for affect $76 (id 118,
  InitAffectHandlers [V]). Game meaning: carried only by the VAMPIRE [V]. }
procedure HalveColdDamageNoSave(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if (DamageKind and KindCold) <> 0 then
    DamageAmount := DamageAmount shr 1;
end;
{ ovl12:2B7D. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000).
  Unless the first slot item of SelectedCharacter (FirstSlotItem, ovl12:101D) exists and has Plus (+$32) not 0, the
  damage is cancelled (DamageAmount := 0) when the character's Race (+$2E, a signed byte) is above 0 or its
  HighestLevel (+$73) is below 4. runs for affect $77 (id 119, InitAffectHandlers [V]). Game meaning: SPECTRE, FERRAN
  MARTINEZ, VAMPIRE, JUJU ZOMBIE and MUMMY [V]: only a weapon with Plus, or an attacker that is a monster of level 4
  or more, hurts [I]. }
procedure CancelDamageUnlessEnchantedSlotItem(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;
begin
  Item := FirstSlotItem(SelectedCharacter);
  if (Item = nil) or (Item^.Plus = 0) then
    if (SelectedCharacter^.Race > RaceMonster) or (SelectedCharacter^.HighestLevel < StrongMonsterLevel) then
      DamageAmount := 0;
end;
{ ovl12:2BC8. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). When the first slot
  item of SelectedCharacter (SlotItems[0], TCharacter +$CC) has ItemType $57 or $58 (names not known [?]), Who may avoid
  the distant attack: AvoidDistantAttack (ovl12:0FAC) with SlotItemAvoidChance. runs for affect $78 (id 120,
  InitAffectHandlers [V]). Game meaning: HILL GIANT and FIRE GIANT [V]: item types $57 and $58 are two-handed
  bludgeoning rows (the type $57 item carries Affects[3] $87, Must have Giant Strength), so this is a giant catching a
  hurled boulder, 50 percent [I]. }
procedure AvoidDistantAttackForBoulder(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;                  { the first slot item of SelectedCharacter, nil when there is none }
begin
  Item := SelectedCharacter^.SlotItems[0];
  if Item <> nil then
    if (Item^.ItemType = ItemBoulderA) or (Item^.ItemType = ItemBoulderB) then
      AvoidDistantAttack(Who, SlotItemAvoidChance);
end;
{ ovl12:2C1C. Affect handler that spits acid at the character Who attacked last (the AffectHandlers shape: Who, Affect
  and Mode; Mode is not read, ovl24:0000). AttackTarget becomes Who's combat Target (Who^.Combat^.Target). On a 1d100 roll at
  or below SpitChance, when DistanceToTarget (the distance to AttackTarget [I]) is below SpitMaxDistance: Who's turn ends
  (EndCombatTurn, its result is not read), "Spits Acid" is shown on Who at row CombatMessageRow, the spit is drawn from Who to
  AttackTarget (DrawCombatIcon with SpitAnimation, WalkCombatLine with CombatantX and CombatantY), and AttackTarget takes 8d4
  damage (DealDamage, half when its save of kind SaveKindBreath succeeds). Then AffectSpitsAcid and AffectSplashesAcid are
  removed
  from Who (RemoveAffect; Affect is the affect handled).
  QUIRK ovl12:2C1C: DamageKind is not set here (AcidAttackTargetFor1d4, ovl12:1A4C, sets KindAcid first), so the spit's
  damage is dealt with whatever kind the damage before left in DamageKind (DealDamage, ovl24:1344). Never fixed. Runs for
  affect $79 (id 121, InitAffectHandlers [V]). }
procedure SpitAcidAtTarget(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Turn: Byte;                   { the result of EndCombatTurn (ends Who's turn), never read }
begin
  AttackTarget := Who^.Combat^.Target;
  if RollDice(1, 100) <= SpitChance then
    if DistanceToTarget(Who, AttackTarget) < SpitMaxDistance then
    begin
      Turn := EndCombatTurn(Who);
      ShowCharacterMessage(Who, 'Spits Acid', CombatMessageRow, True);
      DrawCombatIcon(SpitAnimation);
      WalkCombatLine(CombatantX(Who), CombatantY(Who), CombatantX(AttackTarget), CombatantY(AttackTarget),
        SpitLineKind, SpitLineFlag);
      DealDamage(AttackTarget, RollDiceCounted(SpitDiceCount, SpitDieSides), HalfOnSave,
                 SavingThrow(AttackTarget, SaveKindBreath, 0));
      RemoveAffect(Who, AffectSpitsAcid, Affect);
      RemoveAffect(Who, AffectSplashesAcid, nil);
    end;
end;
{ ovl12:2D38. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). When the
  first slot item of SelectedCharacter (SlotItems[0], TCharacter +$CC) has ItemType $56 (name not known [?]), DamageAmount
  becomes 3d8 (RollDiceCounted, ovl24:0E2E). Then, when DamageKind has the fire or the magic bit (KindFire or KindMagic),
  the dice count of the last roll (LastDiceCount) is added to DamageAmount. runs for affect $7A (id 122,
  InitAffectHandlers [V]). The routine starts at ovl12:2D38 (its push bp); the
  map's entry at ovl12:2D39 is inside it. Game meaning: the MUMMY only [V]; item type $56 is Flask OF Oil [V]: 3d8
  plus the dice count for fire or magic damage, burning oil [I]. }
procedure SetDamageFromOilFlask(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;                  { the first slot item of SelectedCharacter, nil when there is none }
begin
  Item := SelectedCharacter^.SlotItems[0];
  if Item <> nil then
    if Item^.ItemType = ItemOilFlask then
      DamageAmount := RollDiceCounted(OilFlaskDiceCount, OilFlaskDieSides);
  if (DamageKind and (KindFire or KindMagic)) <> 0 then
    Inc(DamageAmount, LastDiceCount);
end;
{ ovl12:2D88. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). The
  first slot item of SelectedCharacter (FirstSlotItem, ovl12:101D) decides the damage. With no item, DamageAmount is
  cancelled (0). With an item whose Plus (+$32) is 0, DamageAmount is halved when its NameNum[3] (+$31) is SilverNameNum
  and cancelled otherwise. An item with Plus not 0 leaves the damage alone. runs for affect $7B (id 123,
  InitAffectHandlers [V]). Game meaning: the WRAITH only [V]; NameNum[3] $B1 is Silver on every silver item [V]: a
  silver weapon with Plus 0 does half damage, any other plain weapon none [I]. }
procedure HalveOrCancelDamageForUnenchantedSlotItem(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;                  { the first slot item of SelectedCharacter (FirstSlotItem), nil when there is none }
begin
  Item := FirstSlotItem(SelectedCharacter);
  if Item <> nil then
  begin
    if (Item^.Plus = 0) and (Item^.NameNum[3] = SilverNameNum) then
      DamageAmount := DamageAmount shr 1
    else if Item^.Plus = 0 then
      DamageAmount := 0
  end
  else
    DamageAmount := 0;
end;
{ ovl12:2DE4. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). A 1d100 roll at or
  below HalfElfCharmSleepResistance (30) cancels the pending hook of the charm (AffectCharm) and then the one of affect
  AffectEndsTurn, each through CancelPendingHook (ovl12:0000). Runs for affect $7C (id 124, InitAffectHandlers [V]). }
procedure HalfElfResistsCharmAndSleep(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if RollDice(1, 100) <= HalfElfCharmSleepResistance then
  begin
    CancelPendingHook(AffectCharm);
    CancelPendingHook(AffectEndsTurn);
  end;
end;
{ ovl12:2E08. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It cancels the
  hooks of four affects with CancelPendingHook (ovl12:0000): the charm (AffectCharm), affect AffectEndsTurn, the
  paralysis (AffectParalysis) and the poison (AffectPoisoned). Then, when the saving throw in progress is the poison
  save (SaveKind 0, SaveKindPoison), SaveRoll becomes AlwaysSaves, so that save succeeds. It is
  CancelPoisonAndParalysisHooks (ovl12:29F0) with the charm and affect $35 cancelled first. Runs for affect $7D (id 125,
  InitAffectHandlers [V]). }
procedure ImmuneToCharmSleepHoldAndPoison(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  CancelPendingHook(AffectCharm);
  CancelPendingHook(AffectEndsTurn);
  CancelPendingHook(AffectParalysis);
  CancelPendingHook(AffectPoisoned);
  if SaveKind = SaveKindPoison then
    SaveRoll := AlwaysSaves;
end;
{ ovl12:2E37. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). AttackTarget becomes
  Who's combat Target (Combat^.Target, as BoostAttackAgainstUndead at ovl12:013B does). The carried items of
  AttackTarget (Items, +$C8) are walked while HookVetoFlag is 0. Every readied item (Readied, +$34) that has
  MirrorNameNum ($76, the item that turns a gaze back, GazeStonesTarget at ovl12:1CAD) in one of its names
  (NameNum[1..3], +$2F..+$31), or HolySymbolNameNum in one name with WoodenNameNum in the third, sets HookVetoFlag to 1.
  HookVetoFlag is read by AttackTargetAllowed (OVL13.PAS lines 647..671), which refuses a vetoed target. The VAMPIRE carries
  affect $7E (MON4SPC blocks 23 and 105) [V]. Runs for affect $7E (id 126, InitAffectHandlers [V]). }
procedure VetoTargetWithMirrorOrWoodenHolySymbol(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;                  { the carried items of AttackTarget, walked from the first }
  NameIndex: Byte;              { the name 1..3 of Item that is looked at }
begin
  AttackTarget := Who^.Combat^.Target;
  Item := AttackTarget^.Items;
  while (Item <> nil) and (HookVetoFlag = 0) do
  begin
    if Item^.Readied then
      for NameIndex := 1 to 3 do
        if ((Item^.NameNum[NameIndex] = HolySymbolNameNum) and (Item^.NameNum[3] = WoodenNameNum)) or
          (Item^.NameNum[NameIndex] = MirrorNameNum) then
          HookVetoFlag := 1;
    Item := Item^.Next;
  end;
end;
{ ovl12:2EDA. Affect handler of a carried item (the AffectHandlers shape, but the Affect parameter is the item: the
  routine reads it as a PItem, Item^.Affects[2] at +$3D of TMenuLine). Any Mode other than 0 removes the affect the
  item names in Affects[2] from Who (RemoveAffect with nil). Mode 0 gives Who that affect with duration 0, Data
  ItemAffectData and no handler on removal (NoRemoveHandler), then CallAffectHandler runs the affect's handler on Who at
  once (Affect nil, Mode 0). Affects[3] $81 is the Ring of Fire Resistance (Affects[2] $3D), $85 the Cloak of
  Displacement (Affects[2] $59) and $88 the Two-Handed Sword +1 +3 vs. Undead (Affects[2] $03) [V item files]; ids
  $80, $82, $86, $8A and $8B are on no pinned item. Runs for affects $80, $81, $82, $85, $86, $88,
  $8A and $8B (ids 128, 129, 130, 133, 134, 136, 138, 139, InitAffectHandlers [V]). }
procedure ApplyItemSecondAffect(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;                  { Affect, read as the item it is }
begin
  Item := PItem(Affect);
  if Mode <> 0 then
    RemoveAffect(Who, Item^.Affects[2], nil)
  else
  begin
    AddAffect(Who, Item^.Affects[2], PermanentDuration, ItemAffectData, NoRemoveHandler);
    CallAffectHandler(Item^.Affects[2], Who, nil, 0);
  end;
end;
{ ovl12:2F57. Affect handler of the exceptional strength (the AffectHandlers shape: Who, Affect and Mode; Affect is not
  read). Mode 0 (applying) raises Who's strength to ExceptionalStrength with ExceptionalPercent (18/100) with
  RaiseStrength (ovl24:115C). When that gives True (Who was not stronger), "is stronger" is shown on Who at row
  CombatMessageRow
  (ShowCharacterMessage); in combat the view mode is set to ViewModeCamp while the text shows and back to
  ViewModeCombat after. Then RedrawItemWindow becomes 1 and affect AffectStrength is added with duration 0, Data Code (what
  RaiseStrength wrote: the strength Who had before, encoded, when it gave True) and its handler on removal
  (RunsHandlerOnRemove).
  QUIRK ovl12:302D: the affect is added even when RaiseStrength gave False (Who already stronger), with Code as
  RaiseStrength left it. Any other Mode removes a strength affect: the walk over Who's affects (Affects, +$7F) takes
  the first AffectStrength that qualifies. When Who is 18/100 now, every such affect qualifies (QUIRK ovl12:2FCF: the
  test reads the affect's Id at +0, not its Data (StrengthKept, bit 7 at +3), so it always holds); otherwise the affect
  must decode to 18/100 (DecodeStrength). The walk then goes on to the next affect, reading the Next of the removed one
  (QUIRK ovl12:2FFF), and stops once one was removed. Runs for affect $83 (id 131, InitAffectHandlers [V]). }
procedure GiveExceptionalStrength(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Code: Byte;                   { the strength Who had before, encoded as RaiseStrength gives it (ovl24:115C) }
  Strength: Byte;               { the strength of a strength affect, decoded (DecodeStrength) }
  Percent: Byte;                { the percentile of that strength }
  IsExceptional: Boolean;       { Who is 18/100 now }
  Done: Boolean;                { an affect was removed; the walk stops }
  Scan: PAffect;                { walks Who's affects }
begin
  if Mode <> 0 then
  begin
    Done := False;
    Scan := Who^.Affects;
    if (Who^.Strength = ExceptionalStrength) and (Who^.StrengthPercent = ExceptionalPercent) then
      IsExceptional := True
    else
      IsExceptional := False;
    while (Scan <> nil) and not Done do
    begin
      if Scan^.Id = AffectStrength then
      begin
        DecodeStrength(Scan, Strength, Percent);
        if (IsExceptional and (Scan^.Id < StrengthKept)) or
          ((Strength = ExceptionalStrength) and (Percent = ExceptionalPercent) and not IsExceptional) then
        begin
          RemoveAffect(Who, AffectStrength, Scan);
          Done := True;
        end;
      end;
      Scan := Scan^.Next;
    end;
  end
  else
  begin
    if RaiseStrength(Who, ExceptionalStrength, ExceptionalPercent, Code) then
    begin
      if ViewMode = ViewModeCombat then
      begin
        ViewMode := ViewModeCamp;
        ShowCharacterMessage(Who, 'is stronger', CombatMessageRow, True);
        ViewMode := ViewModeCombat;
      end
      else
        ShowCharacterMessage(Who, 'is stronger', CombatMessageRow, True);
    end;
    RedrawItemWindow := 1;
    AddAffect(Who, AffectStrength, PermanentDuration, Code, RunsHandlerOnRemove);
  end;
end;
{ ovl12:30A5. Affect handler of an alignment-bound item (table entry 132, affect $84, stub entry 113), with the
  AffectHandlers shape (Who, Affect and Mode, ovl24:0000), but the Affect parameter is the item, as in
  ApplyItemSecondAffect: ReadyItem (ovl19) calls CallAffectHandler(Item^.Affects[3], Character, PAffect(Item), Mode)
  when an item
  with Affects[3] above $7F is readied (Mode 0) or unreadied. Any other Mode than 0 does nothing. When the low nibble of the
  item's Affects[2] is not Who's Alignment (ScoreItem tests the same nibble, ovl09:128D), the item is unreadied (Readied
  cleared) and the high nibble of Affects[2] is dealt to Who as magic damage without a save (DealDamage), DrawCombatScreen
  shows it in combat view and RedrawItemWindow becomes 1. The items with Affects[3] $84 are Long Swords with Affects[2] $52 and
  $F0 [V item files]: a weapon bound to an alignment, which hurts a wielder of another one [I]. Runs for affect $84 (id 132,
  InitAffectHandlers [V]). }
procedure AlignmentBoundWeaponHurtsOthers(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;                  { Affect, read as the item it is }
  Damage: Byte;
begin
  Item := PItem(Affect);
  if Mode <> 0 then
    Exit;
  if (Item^.Affects[2] and LowNibble) <> Byte(Who^.Alignment) then
  begin
    Item^.Readied := False;
    Damage := Item^.Affects[2] div 16;
    DamageKind := KindMagic;
    if ViewMode = ViewModeCombat then
      DrawCombatScreen;
    DealDamage(Who, Damage, 0, False);
    RedrawItemWindow := 1;
  end;
end;
{ ovl12:3134. Affect handler of an item that needs a giant (table entry 135, affect $87, stub entry 114), with the
  AffectHandlers shape (Who, Affect and Mode, ovl24:0000); the Affect parameter is the item, as in
  AlignmentBoundWeaponHurtsOthers. Mode 0 applies it; any other Mode does nothing. When Who's Strength is below GiantStrength
  (19) the item is unreadied (Readied cleared) and ShowFlashMessage shows 'Must have Giant Strength' (the literal is
  copied to a stack temporary first, $O+). The only item with Affects[3] $87 in the pinned files is a type $57 two-handed
  bludgeoning row [V item files]. Runs for affect $87 (id 135, InitAffectHandlers [V]). }
procedure RequireGiantStrength(Who: PCharacter; Affect: PAffect; Mode: Byte);
var
  Item: PItem;
begin
  Item := PItem(Affect);
  if Mode <> 0 then
    Exit;
  if Who^.Strength < GiantStrength then
  begin
    Item^.Readied := False;
    ShowFlashMessage('Must have Giant Strength');
  end;
end;
{ ovl12:317A. Affect handler of table entry 137 (affect $89, stub entry 115), with the AffectHandlers shape (Who,
  Affect and Mode, ovl24:0000). Mode 0 applies it and does nothing; any other Mode, the removal (RemoveAffect,
  ovl24:0026), removes affect AffectSpiritualHammer from Who with no particular affect given. Runs for affect $89 (id 137,
  InitAffectHandlers
  [V]). }
procedure EndSpiritualHammerWhenHammerRemoved(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
  if Mode <> 0 then
    RemoveAffect(Who, AffectSpiritualHammer, nil);
end;
{ ovl12:319B. an affect handler with the AffectHandlers shape (Who, Affect and Mode, ovl24:0000)
  that does nothing: no parameter is read and no global is written, the same code as IgnoreAffect (ovl12:0647).
  It is the handler (stub entry 116, value 0264) of the affects 5, 13, 19, 24, 27, 60, 63, 92 and 127 in the
  AffectHandlers table (DS:6828). }
procedure IgnoreAffectShared(Who: PCharacter; Affect: PAffect; Mode: Byte);
begin
end;
{ ovl12:31A2. the name stays provisional because ovl11 calls it by name (ovl11:002D, StartGame);
  what it does is known. Entry 1 of the unit. It fills the affect handler table
  AffectHandlers (DS:6828, one four-byte handler per affect number) with the stub address of each affect's handler:
  this unit's stubs are in segment 0041, ovl13's in segment 0068 (entries 73 and 74). Affects 5, 13, 19, 24, 27, 60,
  63, 92 and 127 get IgnoreAffectShared, the handler that does nothing. Affect 0 and affect 88 are not set here [?]; entry 0 of
  the table is not a handler (SaveKind lies in it). }
procedure InitAffectHandlers;
begin
  AffectHandlers[1] := RaiseAttackAndMorale;
  AffectHandlers[2] := LowerAttackAndMorale;
  AffectHandlers[3] := BoostAttackAgainstUndead;
  AffectHandlers[4] := StartTrainingWithManual;
  AffectHandlers[5] := IgnoreAffectShared;
  AffectHandlers[6] := BoostFireAttackByTarget;
  AffectHandlers[7] := TrainConstitution;
  AffectHandlers[8] := ShiftAttackToSaveVsEvil;
  AffectHandlers[9] := ShiftAttackToSaveVsGood;
  AffectHandlers[10] := HalveColdDamage;
  AffectHandlers[11] := ApplyCharmPerson;
  AffectHandlers[12] := ApplyStrengthAffect;
  AffectHandlers[13] := IgnoreAffectShared;
  AffectHandlers[14] := SetCharismaFromAffect;
  AffectHandlers[15] := SlowPoisonDamage;
  AffectHandlers[16] := IgnoreAffect;
  AffectHandlers[17] := RaiseResistanceAndSave;
  AffectHandlers[18] := BoostAttackVsKoboldGoblin;
  AffectHandlers[19] := IgnoreAffectShared;
  AffectHandlers[20] := HalveFireDamage;
  AffectHandlers[21] := ShowSilenceAndStopCasting;
  AffectHandlers[22] := DieIfPoisoned;
  AffectHandlers[23] := GiveSpiritualHammer;
  AffectHandlers[24] := IgnoreAffectShared;
  AffectHandlers[25] := InvisibleTargetHardToHit;
  AffectHandlers[26] := BoostAttackVsOrcGoblinHobgoblin;
  AffectHandlers[27] := IgnoreAffectShared;
  AffectHandlers[28] := ImageAbsorbsHit;
  AffectHandlers[29] := ReduceDamageByQuarter;
  AffectHandlers[30] := CoughStopsCasting;
  AffectHandlers[31] := EndAffectedCombatantTurn;
  AffectHandlers[32] := CollapseAndChangeSide;
  AffectHandlers[33] := LowerAttackSaveAndResistance;
  AffectHandlers[34] := RunDiseaseHandlers;
  AffectHandlers[35] := RaiseAttackAndSave;
  AffectHandlers[36] := LowerAttackAndSave;
  AffectHandlers[37] := SetAttackMissIfTurnPending;
  AffectHandlers[38] := ApplyStrengthAffect;
  AffectHandlers[39] := ApplyHaste;
  AffectHandlers[40] := ClearCloud;
  AffectHandlers[41] := ProtectFromNormalMissiles;
  AffectHandlers[42] := ApplySlow;
  AffectHandlers[43] := WeakenStrength;
  AffectHandlers[44] := CauseDiseaseAndDamage;
  AffectHandlers[45] := ShiftAttackToSaveVsEvil;
  AffectHandlers[46] := ShiftAttackToSaveVsGood;
  AffectHandlers[47] := LowerAttackVsOgreTrollGiant;
  AffectHandlers[48] := LowerAttackIfSelectedIsBugbearOrGnoll;
  AffectHandlers[49] := RaiseOrLowerAttackAndSave;
  AffectHandlers[50] := AddHealingBlockAndHeal;
  AffectHandlers[51] := EndAffectedCombatantTurn;
  AffectHandlers[52] := EndAffectedCombatantTurn;
  AffectHandlers[53] := EndAffectedCombatantTurn;
  AffectHandlers[54] := IgnoreAffect36;
  AffectHandlers[55] := IgnoreAffect37;
  AffectHandlers[56] := GiveInvisibilityForOneRound;
  AffectHandlers[57] := ProgressRot;
  AffectHandlers[58] := StopMovement;
  AffectHandlers[59] := GiveRegainHitPointsAffect;
  AffectHandlers[60] := IgnoreAffectShared;
  AffectHandlers[61] := ReduceFireDamageByRoll;
  AffectHandlers[62] := AddTrainedOutAndHeal;
  AffectHandlers[63] := IgnoreAffectShared;
  AffectHandlers[64] := PoisonAttackTargetBonus0;
  AffectHandlers[65] := PoisonAttackTargetBonus4;
  AffectHandlers[66] := PoisonAttackTargetBonus2;
  AffectHandlers[67] := ParalyzeAttackTargetFor2d8;
  AffectHandlers[68] := ParalyzeAttackTargetUnlessImmune;
  AffectHandlers[69] := ParalyzeAttackTargetFor1d9Plus10;
  AffectHandlers[70] := PoisonAttackTargetBonusMinus2;
  AffectHandlers[71] := InvisibleTargetCannotBeTargeted;
  AffectHandlers[72] := CamouflageGivesInvisibility;
  AffectHandlers[73] := RakeAttack;
  AffectHandlers[74] := ForcedAttack;
  AffectHandlers[75] := DrainBloodFromCombatant;
  AffectHandlers[76] := StartBloodDrain;
  AffectHandlers[77] := HoldWeakTargetFast;
  AffectHandlers[78] := ReviveOrRetryRevival;
  AffectHandlers[79] := FireAttackTargetFor2d10;
  AffectHandlers[80] := AcidAttackTargetFor1d4;
  AffectHandlers[81] := FrightenSideWithFear;
  AffectHandlers[82] := ParalyzeSideWithFear;
  AffectHandlers[83] := GazeStonesTarget;
  AffectHandlers[84] := GazeCharmsTarget;
  AffectHandlers[85] := DrainAttackTargetLevel;
  AffectHandlers[86] := DrainAttackTargetTwoLevels;
  AffectHandlers[87] := CauseRotOnAttackTarget;
  AffectHandlers[89] := ForceFirstAttackMiss;
  AffectHandlers[90] := DwarfHalflingPoisonSaveBonus;
  AffectHandlers[91] := ImmuneToMagicMissileAndElectricity;
  AffectHandlers[92] := IgnoreAffectShared;
  AffectHandlers[93] := HalveFireDamageNoSave;
  AffectHandlers[94] := HalveDamageForFirstSlotItem;
  AffectHandlers[95] := FallDeadIfInFight;
  AffectHandlers[96] := CancelDamageUnlessMagicSlotItem;
  AffectHandlers[97] := DwarfGnomeHalflingWandSpellSaveBonus;
  AffectHandlers[98] := RegainHitPoints;
  AffectHandlers[99] := ReviveDyingCharacter;
  AffectHandlers[100] := GiveAffectUnlessFireOrAcid;
  AffectHandlers[101] := GiveRegeneratingUnlessAffected;
  AffectHandlers[102] := RetryRevivalAtFullHitPoints;
  AffectHandlers[103] := TurnGaseousAndEscape;
  AffectHandlers[104] := AvoidDistantAttackByChance;
  AffectHandlers[105] := CancelHookByHalfChance;
  AffectHandlers[106] := CancelHookByLowChance;
  AffectHandlers[107] := ElfResistsCharmAndSleep;
  AffectHandlers[108] := ImmuneToCharmAndSleep;
  AffectHandlers[109] := CancelParalysisHook;
  AffectHandlers[110] := CancelColdDamage;
  AffectHandlers[111] := CancelPoisonAndParalysisHooks;
  AffectHandlers[112] := CancelFireDamage;
  AffectHandlers[113] := ReduceFireDamageOnePerDie;
  AffectHandlers[114] := HalveElectricityDamage;
  AffectHandlers[115] := HalveDamageByFirstSlotItemRow;
  AffectHandlers[116] := HalveDamageForEnchantedSlotItem;
  AffectHandlers[117] := SetDamageFromHolyWater;
  AffectHandlers[118] := HalveColdDamageNoSave;
  AffectHandlers[119] := CancelDamageUnlessEnchantedSlotItem;
  AffectHandlers[120] := AvoidDistantAttackForBoulder;
  AffectHandlers[121] := SpitAcidAtTarget;
  AffectHandlers[122] := SetDamageFromOilFlask;
  AffectHandlers[123] := HalveOrCancelDamageForUnenchantedSlotItem;
  AffectHandlers[124] := HalfElfResistsCharmAndSleep;
  AffectHandlers[125] := ImmuneToCharmSleepHoldAndPoison;
  AffectHandlers[126] := VetoTargetWithMirrorOrWoodenHolySymbol;
  AffectHandlers[127] := IgnoreAffectShared;
  AffectHandlers[128] := ApplyItemSecondAffect;
  AffectHandlers[129] := ApplyItemSecondAffect;
  AffectHandlers[130] := ApplyItemSecondAffect;
  AffectHandlers[131] := GiveExceptionalStrength;
  AffectHandlers[132] := AlignmentBoundWeaponHurtsOthers;
  AffectHandlers[133] := ApplyItemSecondAffect;
  AffectHandlers[134] := ApplyItemSecondAffect;
  AffectHandlers[135] := RequireGiantStrength;
  AffectHandlers[136] := ApplyItemSecondAffect;
  AffectHandlers[137] := EndSpiritualHammerWhenHammerRemoved;
  AffectHandlers[138] := ApplyItemSecondAffect;
  AffectHandlers[139] := ApplyItemSecondAffect;
end;

begin
end.
