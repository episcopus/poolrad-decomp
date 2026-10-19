#include "game.h"

/* ovl12:0000. Cancels the hook of an affect: when AffectId is 0 or is the affect the hooks are offering
     (HookAffectId), HookAffectId and DamageAmount are cleared. HookAffectId 0 reads as "is Unaffected"
     (ovl24:1672), so the affect and its damage are dropped. */
void CancelPendingHook(u8 AffectId)
{
  POOL_TRACE("CancelPendingHook");
  if (((AffectId == 0)) || ((HookAffectId == AffectId))) {
    DamageAmount = 0;
    HookAffectId = 0;
  }
}

/* ovl12:001F. Gives Who the affect AffectId with Duration and Data unless the Temple is removing affects
     (RemovingAffects is 1 then, set by the Temple's RemoveAffect calls, ovl04:0386): then the result is False and
     nothing is added. Otherwise AddAffect (ovl24:0E52) appends the affect with its handler marked to run
     when the affect is removed, and the result is True. */
u8 TryAddAffect(PCharacter Who, u8 AffectId, u8 Data, u16 Duration)
{
  POOL_TRACE("TryAddAffect");
  u8 Result = 0;
  if (RemovingAffects != 0) {
    Result = 0;
  } else {
    Result = 1;
    AddAffect(Who, AffectId, Duration, Data, RunsHandlerOnRemove);
  }
  return Result;
}

/* ovl12:0058. Puts Who out of the fight, with Msg shown on Who at row CombatMessageRow (ShowCharacterMessage).
     Unless Who's Status is StatusDead, StatusStoned or StatusGone (6, 7 or 8) already, its Status becomes NewStatus,
     its Flag10D and HpCurrent are cleared, its death affects are removed (RemoveDeathAffects), the hooks of a combatant going
     down run, and Who leaves
     the map (RemoveCombatant) when Flag10D is clear. Then DelayByGameSpeed, the prompt is cleared and,
     outside combat, the selected character is redrawn. Like DropCombatant (ovl24:0F06) without the ground
     redraw. */
void DropFromFight(PCharacter Who, u8 NewStatus, const u8 *Msg_in)
{
  POOL_TRACE("DropFromFight");
  const u8 *Msg = Msg_in;
  ShowCharacterMessage(Who, Msg, CombatMessageRow, 0);
  switch ((*FPD(TCharacter (*), Who)).Status) {
  case StatusStoned:
  case StatusDead:
  case StatusGone:
  {
    return;
    break;
  }
  }
  (*FPD(TCharacter (*), Who)).Status = NewStatus;
  (*FPD(TCharacter (*), Who)).Flag10D = 0;
  (*FPD(TCharacter (*), Who)).HpCurrent = 0;
  RemoveDeathAffects(Who);
  RunAffectHooks(HookGoesDown, Who);
  if ((*FPD(TCharacter (*), Who)).Flag10D == 0) {
    RemoveCombatant(Who);
  }
  DelayByGameSpeed();
  ClearCharacterMessage();
  if (ViewMode != ViewModeCombat) {
    DrawPartyRoster(SelectedCharacter);
  }
}

/* ovl12:010D. Affect handler of an affect (the AffectHandlers shape: Who, Affect and Mode; Mode is not read,
     so applying and removing run the same code, ovl24:0000): adds MoraleStep to the morale scratch MoraleScratch (ovl09
     CheckMorale
     computes it) and 1 to AttackRoll. The handler at ovl12:011D takes both back. Runs for affect $01 (id 1,
     InitAffectHandlers [V]). */
void RaiseAttackAndMorale(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("RaiseAttackAndMorale");
  MoraleScratch += MoraleStep;
  AttackRoll++;
}

/* ovl12:011D. The handler that undoes RaiseAttackAndMorale (ovl12:010D), with the AffectHandlers shape (Who,
     Affect and Mode; Mode not read): takes MoraleStep off the morale scratch MoraleScratch, or sets it to 0 when it
     holds less, and takes 1 off AttackRoll. Runs for affect $02 (id 2, InitAffectHandlers [V]). */
void LowerAttackAndMorale(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("LowerAttackAndMorale");
  if (MoraleScratch < MoraleStep) {
    MoraleScratch = 0;
  } else {
    MoraleScratch -= MoraleStep;
  }
  AttackRoll--;
}

/* ovl12:013B. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000).
     It copies the character Who attacked last (Who's combat Target, TCombatant at +$108 of Who, MeleeAttack
     sets it in ovl08) into AttackTarget. When that character's byte +$9F (CreatureType of TCharacter, purpose unknown [?])
     is CreatureUndead (4), the attack roll and the damage each gain TargetBonus. Runs for affect $03 (id 3,
     InitAffectHandlers [V]). */
void BoostAttackAgainstUndead(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("BoostAttackAgainstUndead");
  AttackTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  if ((*FPD(TCharacter (*), AttackTarget)).CreatureType == CreatureUndead) {
    AttackRoll += TargetBonus;
    DamageAmount += TargetBonus;
  }
}

/* ovl12:017F. Shows "starts to train" on Who at row CombatMessageRow (ShowCharacterMessage, the message is copied to a
     stack temporary by 0AF8:0B0B first) and gives Who the training manual affect (AffectTrainingManual,
     duration TrainingManualDuration, data TrainingManualData), whose handler runs when it is removed.
     It has the AffectHandlers frame (Who, Affect, Mode); Affect and Mode are not read here. Runs for affect $04 (id 4,
     InitAffectHandlers
     [V]). */
void StartTrainingWithManual(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("StartTrainingWithManual");
  ShowCharacterMessage(Who, S("\017starts to train"), CombatMessageRow, 1);
  AddAffect(Who, AffectTrainingManual, TrainingManualDuration, TrainingManualData, RunsHandlerOnRemove);
}

/* ovl12:01C3. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000).
     Like BoostAttackAgainstUndead (ovl12:013B) it copies Who's combat Target into AttackTarget, then gives
     a bonus to the attack roll and to the damage from the target's byte +$9F (CreatureType of TCharacter, purpose unknown
     [?]): CreatureTroll gives FireBonusForTroll (1), CreatureTypeNine or CreatureStirge give FireBonusForStirgeNine (2),
     CreatureUndead gives FireBonusForUndead (3), any other value gives 0. The damage kind becomes KindFire or KindMagic
     (fire, plus the magic bit 8, ovl24:13E4). Runs for affect $06 (id 6, InitAffectHandlers [V]). */
void BoostFireAttackByTarget(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("BoostFireAttackByTarget");
  u8 Bonus = 0;
  AttackTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  switch ((*FPD(TCharacter (*), AttackTarget)).CreatureType) {
  case CreatureTroll:
  {
    Bonus = FireBonusForTroll;
    break;
  }
  case CreatureTypeNine:
  case CreatureStirge:
  {
    Bonus = FireBonusForStirgeNine;
    break;
  }
  case CreatureUndead:
  {
    Bonus = FireBonusForUndead;
    break;
  }
  default:
  {
    Bonus = 0;
  }
  }
  AttackRoll += Bonus;
  DamageAmount += Bonus;
  DamageKind = (KindFire | KindMagic);
}

/* ovl12:0233. Training of Who's constitution: shows "is hardier" on Who (row CombatMessageRow), Constitution goes up by one,
     and Who's hit points gain: the hit points above HpB1 (HpMax - HpB1) are divided by the class weight (fighter
     levels count Constitution - 15, non-fighter levels count twice above 15, else 1; 1 when the weight is 0),
     and the gain goes to HpMax and to the current hit points HpCurrent. Nothing is gained below Constitution 15,
     nor from 17 up without a fighter level. At Constitution 20 Who gets AffectTrainedOut instead and the
     routine ends. It has the AffectHandlers frame (Who, Affect, Mode); Affect and Mode are not read here. Runs for affect $07
     (id 7, InitAffectHandlers [V]). */
void TrainConstitution(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("TrainConstitution");
  u8 Gain = 0;
  u8 Weight = 0;
  s8 I = 0;
  ShowCharacterMessage(Who, S("\012is hardier"), CombatMessageRow, 1);
  (*FPD(TCharacter (*), Who)).Constitution++;
  if ((*FPD(TCharacter (*), Who)).Constitution >= ConstitutionLimit) {
    AddAffect(Who, AffectTrainedOut, TrainedOutDuration, TrainedOutData, RunsHandlerOnRemove);
    return;
  }
  Gain = (*FPD(TCharacter (*), Who)).HpMax - (*FPD(TCharacter (*), Who)).HpB1;
  Weight = 0;
  if ((*FPD(TCharacter (*), Who)).Constitution < TrainingConstitution) {
    return;
  }
  {
    if (0 <= LastClass_OVL12) {
      I = 0;
      for (;;) {
          if ((*FPD(TCharacter (*), Who)).ClassLevels[I] > 0) {
            if (I == ClassFighter) {
              Weight += (s16)(((s16)((*FPD(TCharacter (*), Who)).Constitution - TrainingConstitution)) * (*FPD(TCharacter (*), Who)).ClassLevels[I]);
            } else if ((*FPD(TCharacter (*), Who)).Constitution > TrainingConstitution) {
              Weight += (s16)((*FPD(TCharacter (*), Who)).ClassLevels[I] * 2);
            } else {
              Weight += (*FPD(TCharacter (*), Who)).ClassLevels[I];
            }
          }
        if (I == LastClass_OVL12) break;
        I++;
      }
    }
  }
  if (Weight == 0) {
    Weight = 1;
  }
  Gain = (Gain / Weight);
  if ((((*FPD(TCharacter (*), Who)).Constitution < FighterOnlyConstitution_OVL12)) || (((*FPD(TCharacter (*), Who)).ClassLevels[2] > 0))) {
    (*FPD(TCharacter (*), Who)).HpMax += Gain;
    (*FPD(TCharacter (*), Who)).HpCurrent += Gain;
  }
}

/* ovl12:0377. It moves 2 from the attack roll to the saving throw roll when the selected character's
     Alignment (+$A0 of TCharacter, the alignment index of AlignmentNames [V]) is 2, 5 or 8, Lawful, Neutral and Chaotic
     Evil: SaveRoll (DS:6816) gains 2 and AttackRoll (DS:6822) loses 2. The effect is that of Protection from Evil [I].
     It has the 10-byte frame of the affect handlers, but reads SelectedCharacter, not its parameters
     (Who, Affect and Mode are not read). Runs for affects $08 and $2D (ids 8, 45, InitAffectHandlers [V]). */
void ShiftAttackToSaveVsEvil(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ShiftAttackToSaveVsEvil");
  if (((((*FPD(TCharacter (*), SelectedCharacter)).Alignment == AlignLawfulEvil)) || (((*FPD(TCharacter (*), SelectedCharacter)).Alignment == AlignNeutralEvil))) || (((*FPD(TCharacter (*), SelectedCharacter)).Alignment == AlignChaoticEvil))) {
    SaveRoll += ProtectionShift;
    AttackRoll -= ProtectionShift;
  }
}

/* ovl12:03AC. The twin of ShiftAttackToSaveVsEvil (ovl12:0377) with the Alignment values 0, 3 and 6 (Lawful, Neutral and
     Chaotic Good in AlignmentNames) in place of 2, 5 and 8, the effect of Protection from Good [I]: SaveRoll (DS:6816)
     gains 2 and AttackRoll (DS:6822)
     loses 2. Who, Affect and Mode are not read. Runs for affects $09 and $2E (ids 9, 46, InitAffectHandlers [V]). */
void ShiftAttackToSaveVsGood(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ShiftAttackToSaveVsGood");
  if (((((*FPD(TCharacter (*), SelectedCharacter)).Alignment == AlignLawfulGood)) || (((*FPD(TCharacter (*), SelectedCharacter)).Alignment == AlignNeutralGood))) || (((*FPD(TCharacter (*), SelectedCharacter)).Alignment == AlignChaoticGood))) {
    SaveRoll += ProtectionShift;
    AttackRoll -= ProtectionShift;
  }
}

/* ovl12:03E1. Affect handler for damage (the AffectHandlers frame: Who, Affect and Mode, none of them read): when
     the damage being dealt is cold (DamageKind bit KindCold, DS:6819), it halves DamageAmount (DS:6818) and adds
     ColdSaveBonus to SaveRoll (DS:6816). runs for affect $0A (id 10, InitAffectHandlers [V]). Game meaning: Resist Cold,
     the spell with SpellTable AffectId $0A (spell 8) [V]: half cold damage and +3 on the save, as the AD&D spell [I]. */
void HalveColdDamage(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("HalveColdDamage");
  if (((DamageKind & KindCold)) != 0) {
    DamageAmount = (s16)((u16)DamageAmount >> 1);
    SaveRoll += ColdSaveBonus;
  }
}

/* ovl12:0400. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode 0 applies, any other value
     removes, ovl24:0000). Runs for affect $0B (id 11, InitAffectHandlers [V]). Applying gives Who to the
     computer, as quick combat does (whitepaper, "Who plays"): Quick is set so QuickTurn plays the turn, Who
     becomes computer-run with morale $33 unless it already is, the target Who attacked is dropped and
     RecountCombatSides runs. The side becomes Affect.Data bit 7 (ControlSideBit); bit 6 keeps the
     side before (ControlSavedSideBit) and bit 5 marks the control as applied, so a second apply only sets
     the morale. Removing gives back the side from bit 6 and clears the computer-run morale while it is still
     ComputerRunMorale; it does not clear Quick. Applying also sets the morale scratch MoraleScratch (AffectMorale). */
void ApplyCharmPerson(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ApplyCharmPerson");
  if (Mode != 0) {
    (*FPD(TCharacter (*), Who)).Side = ((((*FPD(TAffect (*), Affect)).Data & ControlSavedSideBit)) / ControlSavedSideBit);
    if ((*FPD(TCharacter (*), Who)).B84 == ComputerRunMorale) {
      (*FPD(TCharacter (*), Who)).B84 = 0;
    }
  } else {
    if ((((*FPD(TAffect (*), Affect)).Data & ControlAppliedBit)) == 0) {
      /* the side is read signed, as the original sign-extends it (cbw) */
      (*FPD(TAffect (*), Affect)).Data = ((*FPD(TAffect (*), Affect)).Data + ControlAppliedBit) + ((*FPD(TCharacter (*), Who)).Side * ControlSavedSideBit);
      (*FPD(TCharacter (*), Who)).Side = ((*FPD(TAffect (*), Affect)).Data / ControlSideBit);
      (*FPD(TCharacter (*), Who)).Quick = 1;
      if ((*FPD(TCharacter (*), Who)).B84 <= 127) {
        (*FPD(TCharacter (*), Who)).B84 = ComputerRunMorale;
      }
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target = 0;
      RecountCombatSides();
    }
    MoraleScratch = AffectMorale;
  }
}

/* ovl12:04BA. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000) of a strength
     affect whose Data holds an encoded strength (EncodeStrength, ovl24:10E4). Does nothing when Data has bit 7
     (StrengthKept): an earlier strength is kept in it. Otherwise Who's Strength and StrengthPercent take the
     affect's strength (DecodeStrength, ovl24:110D). Then the strongest other strength affect of Who, id $0C or
     $26 (AffectEnlarge, AffectStrength), gives Who its strength, and it takes the encoded strength the
     affect gave Who. Strength 18 with a percentile counts above any other 18 (ExceptionalStrength). With no
     other strength affect Who keeps the decoded strength. Runs for affects $0C and $26 (ids 12, 38, InitAffectHandlers [V]).
     QUIRK ovl12:05B8: the earlier affect's Data is written without StrengthKept, where RaiseStrength (ovl24:115C)
     sets it. */
void ApplyStrengthAffect(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ApplyStrengthAffect");
  u8 Strength = 0;
  u8 Percent = 0;
  u8 BestStrength = 0;
  u8 BestPercent = 0;
  PAffect Scan = 0;
  PAffect Earlier = 0;
  if ((*FPD(TAffect (*), Affect)).Data > 127) {
    return;
  }
  DecodeStrength(Affect, &Strength, &Percent);
  (*FPD(TCharacter (*), Who)).Strength = Strength;
  (*FPD(TCharacter (*), Who)).StrengthPercent = Percent;
  Earlier = 0;
  BestStrength = 0;
  BestPercent = 0;
  Scan = (*FPD(TCharacter (*), Who)).Affects;
  while (Scan != 0) {
    if ((((*FPD(TAffect (*), Scan)).Id == AffectEnlarge)) || (((*FPD(TAffect (*), Scan)).Id == AffectStrength))) {
      if (Scan != Affect) {
        DecodeStrength(Scan, &Strength, &Percent);
        if (((Strength > BestStrength)) || ((((BestStrength == ExceptionalStrength)) && ((Percent > BestPercent))))) {
          BestStrength = Strength;
          BestPercent = Percent;
          Earlier = Scan;
        }
      }
    }
    Scan = (*FPD(TAffect (*), Scan)).Next;
  }
  if (Earlier != 0) {
    (*FPD(TAffect (*), Earlier)).Data = EncodeStrength((*FPD(TCharacter (*), Who)).Strength, (*FPD(TCharacter (*), Who)).StrengthPercent);
    (*FPD(TCharacter (*), Who)).Strength = BestStrength;
    (*FPD(TCharacter (*), Who)).StrengthPercent = BestPercent;
  }
}

/* ovl12:05D6. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000): Who's
     Charisma (TCharacter +$15) becomes the affect's Data byte. Applying and removing run the same code, so the
     value is set each time. Runs for affect $0E (id 14, InitAffectHandlers [V]). */
void SetCharismaFromAffect(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("SetCharismaFromAffect");
  (*FPD(TCharacter (*), Who)).Charisma = (*FPD(TAffect (*), Affect)).Data;
}

/* ovl12:05EB. Affect handler of the slowed poison that Slow Poison (ovl22 CastSlowPoison) gives [V]: an affect handler
     (the AffectHandlers shape: Who, Affect and Mode; Mode is
     not read, ovl24:0000). It adds affect $0F (AffectSlowPoisonDamage) to Who for SlowPoisonDamageDuration with the
     Data byte of Affect, when TryAddAffect allows it. Then, while Who has more than one hit point (HpCurrent,
     the current hit points [I]), it deals 1 point of plain damage (DamageKind 0, no save, DealDamage) and,
     outside combat, redraws the selected character (ViewMode is not ViewModeCombat). Runs for affect $0F (id 15,
     InitAffectHandlers [V]). */
void SlowPoisonDamage(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("SlowPoisonDamage");
  if (TryAddAffect(Who, AffectSlowPoisonDamage, (*FPD(TAffect (*), Affect)).Data, SlowPoisonDamageDuration)) {
    if ((*FPD(TCharacter (*), Who)).HpCurrent > 1) {
      DamageKind = 0;
      DealDamage(Who, 1, 0, 0);
      if (ViewMode != ViewModeCombat) {
        DrawPartyRoster(SelectedCharacter);
      }
    }
  }
}

/* ovl12:0647. Affect handler (the AffectHandlers shape: Who, Affect and Mode) that does nothing: none of its
     parameters is read and no global is written. Runs for affect $10 (id 16, InitAffectHandlers [V]). */
void IgnoreAffect(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("IgnoreAffect");
}

/* ovl12:064E. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read). Raises
     Who's ArmourClassValue (TCharacter +$111, the armour class stored as 60 minus the AC [I]) to at least
     MinimumResistance, adds one to SaveRoll, and when CastingSpell is SpellMagicMissile clears DamageAmount, so the
     damage of the roll in progress is none. Runs for affect $11 (id 17, InitAffectHandlers [V]). */
void RaiseResistanceAndSave(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("RaiseResistanceAndSave");
  if ((*FPD(TCharacter (*), Who)).ArmourClassValue < MinimumResistance) {
    (*FPD(TCharacter (*), Who)).ArmourClassValue = MinimumResistance;
  }
  SaveRoll++;
  if (CastingSpell == SpellMagicMissile) {
    DamageAmount = 0;
  }
}

/* ovl12:0679. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It copies the
     character Who attacked last (Who's combat Target) into AttackTarget, as BoostAttackAgainstUndead does. When that
     character's +$9F (CreatureType) and CombatSize (+$6C) are both 1, AttackRoll gains 1 for each of the names
     KoboldGoblinNames[1..4] the character's name equals. Runs for affect $12 (id 18, InitAffectHandlers [V]).
     Given to the gnome by CreateCharacter [V]. */
void BoostAttackVsKoboldGoblin(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("BoostAttackVsKoboldGoblin");
  u8 I = 0;
  AttackTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  if ((((*FPD(TCharacter (*), AttackTarget)).CreatureType == CreatureHumanoid)) && (((*FPD(TCharacter (*), AttackTarget)).CombatSize == SmallFootprintKind))) {
    {
      if (1 <= KoboldGoblinNameCount) {
        I = 1;
        for (;;) {
            if (rtl_str_cmp((*FPD(TCharacter (*), AttackTarget)).Name, KoboldGoblinNames[I]) == 0) {
              AttackRoll++;
            }
          if (I == KoboldGoblinNameCount) break;
          I++;
        }
      }
    }
  }
}

/* ovl12:06E4. Affect handler for damage (the AffectHandlers frame: Who, Affect and Mode, none of them read): when
     the damage being dealt is fire (DamageKind bit KindFire, DS:6819), it halves DamageAmount (DS:6818) and adds
     FireSaveBonus to SaveRoll (DS:6816), the fire twin of HalveColdDamage (ovl12:03E1). runs for affect $14
     (id 20, InitAffectHandlers [V]). Game meaning: Resist Fire, SpellTable AffectId $14 (spell 24) [V]: half fire damage
     and +3 on the save [I]. */
void HalveFireDamage(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("HalveFireDamage");
  if (((DamageKind & KindFire)) != 0) {
    DamageAmount = (s16)((u16)DamageAmount >> 1);
    SaveRoll += FireSaveBonus;
  }
}

/* ovl12:070F. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). When Who's combat
     byte CanUseMagicItem (+$2 of TCombatant) is set, Who shows "is silenced" at row CombatMessageRow (ShowCharacterMessage). Then
     CanUseMagicItem and CanCast (+$1, zero hides Cast in the combat menu, ovl08:0747) are both cleared. Runs for affect $15 (id
     21, InitAffectHandlers [V]). */
void ShowSilenceAndStopCasting(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ShowSilenceAndStopCasting");
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).CanUseMagicItem != 0) {
    ShowCharacterMessage(Who, S("\013is silenced"), CombatMessageRow, 1);
  }
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).CanUseMagicItem = 0;
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).CanCast = 0;
}

/* ovl12:0775. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read): a poisoned
     character dies. When Who has the Poisoned affect (AffectPoisoned, ovl15 names it 'Poisoned'), DropFromFight takes
     Who out of the fight with StatusDead and the text 'dies from poison'. Then AffectSlowPoisonDamage is removed from Who
     inside the RemovingAffects bracket the Temple uses around RemoveAffect (ovl04:0386), so TryAddAffect adds nothing while
     it runs. Runs for affect $16 (id 22, InitAffectHandlers [V]). */
void DieIfPoisoned(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("DieIfPoisoned");
  farptr PoisonAffect = 0;
  if (HasAffect(Who, AffectPoisoned, &PoisonAffect)) {
    DropFromFight(Who, StatusDead, S("\020dies from poison"));
  }
  RemovingAffects = 1;
  RemoveAffect(Who, AffectSlowPoisonDamage, 0);
  RemovingAffects = 0;
}

/* ovl12:07E0. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect is not read). When the affect
     is applied (Mode 0) and Who has no item of HammerItemType with NameNum[3] GivenItemNameNum3 yet, and Who's
     ItemCountC7 (+$C7, likely the item count [I]) is below ItemCountLimit, Who gets such an item (AddItemCopy adds
     it to the list, the temporary is freed) and "Gains an item" is shown at row CombatMessageRow. When it is removed (Mode not
     0) the item Who has is taken off the list (RemoveInventoryItem). Then RecalcCombatValues redraws Who. Spiritual
     Hammer: SpellTable spell 28 has AffectId $17 [V]; runs
     for affect $17 (id 23, InitAffectHandlers [V]). */
void GiveSpiritualHammer(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("GiveSpiritualHammer");
  PItem Item = 0;
  u8 Found = 0;
  Item = (*FPD(TCharacter (*), Who)).Items;
  Found = 0;
  while (((Item != 0)) && !Found) {
    if ((((*FPD(TMenuLine (*), Item)).ItemType == HammerItemType)) && (((*FPD(TMenuLine (*), Item)).NameNum[2] == GivenItemNameNum3))) {
      Found = 1;
    } else {
      Item = (*FPD(TMenuLine (*), Item)).Next;
    }
  }
  if (Mode != 0) {
    if (Item != 0) {
      RemoveInventoryItem(Who, Item);
    }
  }
  if (Mode == 0) {
    if (!Found) {
      if ((*FPD(TCharacter (*), Who)).ItemCountC7 < ItemCountLimit) {
        Item = rtl_getmem(63);
        rtl_FillChar((void *)&(*FPD(TMenuLine (*), Item)), 63, 0);
        (*FPD(TMenuLine (*), Item)).ItemType = HammerItemType;
        (*FPD(TMenuLine (*), Item)).NameNum[1] = GivenItemNameNum2;
        (*FPD(TMenuLine (*), Item)).NameNum[2] = GivenItemNameNum3;
        (*FPD(TMenuLine (*), Item)).Plus = GivenItemPlus;
        (*FPD(TMenuLine (*), Item)).Affects[1] = GivenItemAffect2;
        (*FPD(TMenuLine (*), Item)).Affects[2] = GivenItemAffect3;
        AddItemCopy(Who, Item);
        rtl_freemem(Item, 63);
        ShowCharacterMessage(Who, S("\015Gains an item"), CombatMessageRow, 1);
      }
    }
  }
  RecalcCombatValues(Who);
}

/* ovl12:0918. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none of them is read). It takes
     AttackPenalty (4) off AttackRoll. When SelectedCharacter has no affect AffectDetectInvisibility ($18), HookVetoFlag
     is set to 1
     (HasAffect looks the affect up in the affect list and gives the found affect in FoundAffect). Affect $19 is
     Invisibility: SpellTable spells 30 and
     50 have AffectId $19 [V]; runs for
     affect $19 (id 25, InitAffectHandlers [V]). */
void InvisibleTargetHardToHit(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("InvisibleTargetHardToHit");
  farptr FoundAffect = 0;
  if (!HasAffect(SelectedCharacter, AffectDetectInvisibility, &FoundAffect)) {
    HookVetoFlag = 1;
  }
  AttackRoll -= AttackPenalty;
}

/* ovl12:0947. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). The twin of
     BoostAttackVsKoboldGoblin (ovl12:0679) with eight names: when the character Who attacked last (Who's combat
     Target, copied into AttackTarget) has CreatureType and CombatSize (+$6C) both 1, AttackRoll gains 1 for each of
     the names OrcGoblinHobgoblinNames[1..8] that the
     character's name equals. Runs for affect $1A (id 26, InitAffectHandlers [V]). Given to the dwarf by CreateCharacter [V]. */
void BoostAttackVsOrcGoblinHobgoblin(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("BoostAttackVsOrcGoblinHobgoblin");
  u8 I = 0;
  AttackTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  if ((((*FPD(TCharacter (*), AttackTarget)).CreatureType == CreatureHumanoid)) && (((*FPD(TCharacter (*), AttackTarget)).CombatSize == SmallFootprintKind))) {
    {
      if (1 <= OrcGoblinHobgoblinNameCount) {
        I = 1;
        for (;;) {
            if (rtl_str_cmp((*FPD(TCharacter (*), AttackTarget)).Name, OrcGoblinHobgoblinNames[I - 1]) == 0) {
              AttackRoll++;
            }
          if (I == OrcGoblinHobgoblinNameCount) break;
          I++;
        }
      }
    }
  }
}

/* ovl12:09C0. Affect handler of the images affect (AffectImages, $1C; it runs on the damage hook, kind 6,
     ovl24:02FA; the AffectHandlers shape, Who, Affect and Mode, Mode not read). When a hit is about to land,
     one image may take it: with 1d(Data+1) (Data counts the images [I]) above 1, CastingSpell not 0 and SpellAppliedToArea 0,
     CancelPendingHook(0) drops the damage, Who shows "lost an image" at row CombatMessageRow (ShowCharacterMessage) and Data goes
     down by one. When no image is left (Data 0) affect AffectImages is removed. A roll of 1 lets the hit through
     [I]. Runs for affect $1C (id 28, InitAffectHandlers [V]). */
void ImageAbsorbsHit(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ImageAbsorbsHit");
  if ((((RollDice(1, (s16)((*FPD(TAffect (*), Affect)).Data + 1)) > 1)) && ((CastingSpell > 0))) && ((SpellAppliedToArea == 0))) {
    CancelPendingHook(0);
    ShowCharacterMessage(Who, S("\015lost an image"), CombatMessageRow, 1);
    (*FPD(TAffect (*), Affect)).Data--;
    if ((*FPD(TAffect (*), Affect)).Data == 0) {
      RemoveAffect(Who, AffectImages, 0);
    }
  }
}

/* ovl12:0A3D. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, so the
     handler runs the same on applying and removing). It takes a quarter off the damage the hooks offer:
     DamageAmount := DamageAmount - DamageAmount div 4, so three quarters of the damage (rounded down) remain
     (the damage hook is kind 6, ovl24:02FA). Runs for affect $1D (id 29, InitAffectHandlers [V]). */
void ReduceDamageByQuarter(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ReduceDamageByQuarter");
  DamageAmount = DamageAmount - (DamageAmount / 4);
}

/* ovl12:0A65. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It stops Who
     casting: when Who's combat byte CanUseMagicItem (TCombatant +$2) is set, Who shows "is coughing" at row CombatMessageRow
     (ShowCharacterMessage), then CanUseMagicItem and CanCast (+$1, zero hides Cast in the combat menu, ovl08:0747)
     are cleared and Who is redrawn (RecalcCombatValues). Then TCharacter.RearArmourClassValue (+$112) steps down by
     CoughResistStep while above CoughResistLimit and is set to CoughResistReset otherwise, and that value becomes
     ArmourClassValue (+$111). When Who is the selected character, DrawCharacterPanel runs. The message suggests a
     gas or smoke affect [I]. Runs for affect $1E (id 30, InitAffectHandlers [V]). */
void CoughStopsCasting(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("CoughStopsCasting");
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).CanUseMagicItem != 0) {
    ShowCharacterMessage(Who, S("\013is coughing"), CombatMessageRow, 1);
  }
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).CanUseMagicItem = 0;
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).CanCast = 0;
  RecalcCombatValues(Who);
  if ((*FPD(TCharacter (*), Who)).RearArmourClassValue > CoughResistLimit) {
    (*FPD(TCharacter (*), Who)).RearArmourClassValue -= CoughResistStep;
  } else {
    (*FPD(TCharacter (*), Who)).RearArmourClassValue = CoughResistReset;
  }
  (*FPD(TCharacter (*), Who)).ArmourClassValue = (*FPD(TCharacter (*), Who)).RearArmourClassValue;
  if (Who == SelectedCharacter) {
    DrawCharacterPanel(Who);
  }
}

/* ovl12:0B1B. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It clears
     the affect's Flag, so the handler does not run again when the affect is removed. Unless the Temple is removing
     affects (RemovingAffects is not 0), Who collapses: DropFromFight takes Who out of the fight with StatusDead and the text
     'collapses'. Then Who's side becomes the high nibble of the affect's Data, Quick is set so the computer plays
     Who (as ApplyCharmPerson does, ovl12:0400), the morale of a computer-run member is cleared, and Who's
     SweepAttacks (+$6B) gets the fighter level, +$72 gets 12, +$76 and +$9F get 0. runs for
     affect $20 (id 32, InitAffectHandlers [V]). Game meaning: Animate Dead, SpellTable AffectId $20 (spell 36) [V]: it
     runs when the animated
     creature's affect ends; the creature collapses dead (unless Raise Dead is removing the affect) and returns to its
     own side (ovl22 stores Side * 16 + caster level in Data) [I]. */
void CollapseAndChangeSide(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("CollapseAndChangeSide");
  (*FPD(TAffect (*), Affect)).Flag = 0;
  if (RemovingAffects == 0) {
    DropFromFight(Who, StatusDead, S("\011collapses"));
  }
  (*FPD(TCharacter (*), Who)).Side = ((*FPD(TAffect (*), Affect)).Data / SideShift);
  (*FPD(TCharacter (*), Who)).Quick = 1;
  (*FPD(TCharacter (*), Who)).Pad74[2] = 0;
  (*FPD(TCharacter (*), Who)).SweepAttacks = (*FPD(TCharacter (*), Who)).ClassLevels[2];
  (*FPD(TCharacter (*), Who)).BaseMovement = AnimatedBaseMovement;
  if ((*FPD(TCharacter (*), Who)).B84 == ComputerRunMorale) {
    (*FPD(TCharacter (*), Who)).B84 = 0;
  }
  (*FPD(TCharacter (*), Who)).CreatureType = 0;
}

/* 0BAC. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). Takes AttackPenalty
     off AttackRoll, ResistPenalty off Who's ArmourClassValue (+$111) and off RearArmourClassValue (+$112, the byte
     CoughStopsCasting copies into ArmourClassValue, ovl12:0A65), and SavePenalty off SaveRoll.
     Runs for affect $21 (id 33, InitAffectHandlers [V]). */
void LowerAttackSaveAndResistance(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("LowerAttackSaveAndResistance");
  AttackRoll -= AttackPenalty;
  (*FPD(TCharacter (*), Who)).ArmourClassValue -= ResistPenalty;
  (*FPD(TCharacter (*), Who)).RearArmourClassValue -= ResistPenalty;
  SaveRoll -= SavePenalty;
}

/* 0BCF. Affect handler (the AffectHandlers shape: Who, Affect and Mode, passed on unchanged). Runs the handler of
     affect AffectDrainsStrength and then the handler of AffectCauseDisease with the same Who, Affect and Mode (both through
     CallAffectHandler, ovl24:0000). Both ids are in the list Cure Disease removes, so the routine runs the disease
     handlers. Runs for affect $22 (id 34, InitAffectHandlers [V]). */
void RunDiseaseHandlers(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("RunDiseaseHandlers");
  CallAffectHandler(AffectDrainsStrength, Who, Affect, Mode);
  CallAffectHandler(AffectCauseDisease, Who, Affect, Mode);
}

/* 0C06. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). Adds 1 to SaveRoll and
     to AttackRoll, the plus of the routine at ovl12:0C15. Called by ovl12:12B2 (RaiseOrLowerAttackAndSave).
     Runs for affect $23 (id 35, InitAffectHandlers [V]). */
void RaiseAttackAndSave(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("RaiseAttackAndSave");
  SaveRoll++;
  AttackRoll++;
}

/* 0C15. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). Takes AttackPenalty
     off AttackRoll and SavePenalty off SaveRoll, the minus of RaiseAttackAndSave (ovl12:0C06). Runs for affect $24 (id 36,
     InitAffectHandlers [V]). */
void LowerAttackAndSave(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("LowerAttackAndSave");
  AttackRoll -= AttackPenalty;
  SaveRoll -= SavePenalty;
}

/* 0C26. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read, ovl24:0000). When Who's combatant
     still has its turn to take (Combat^.Initiative, TCombatant +$3, above 0: CombatTurn acts only above 0), HookVetoFlag
     is set to
     1 and AttackRoll becomes MissRoll, a negative roll (a miss, ovl24:0CD5). Runs for affect $25 (id 37,
     InitAffectHandlers [V]). */
void SetAttackMissIfTurnPending(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("SetAttackMissIfTurnPending");
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative > 0) {
    HookVetoFlag = 1;
    AttackRoll = MissRoll;
  }
}

/* 0C4B. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). The first run
     with AgedBit clear in the
     affect's Data sets the bit, shows "ages" on Who at row CombatMessageRow (ShowCharacterMessage) and adds
     one
     year to Who's Age (+$30). Every run doubles HookedMoveOrAttacks (shl 1), whether or not Who was aged. Runs for
     affect $27 (id 39,
     InitAffectHandlers [V]). */
void ApplyHaste(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ApplyHaste");
  if ((((*FPD(TAffect (*), Affect)).Data & AgedBit)) == 0) {
    (*FPD(TAffect (*), Affect)).Data = (*FPD(TAffect (*), Affect)).Data + AgedBit;
    ShowCharacterMessage(Who, S("\004ages"), CombatMessageRow, 1);
    (*FPD(TCharacter (*), Who)).Age++;
  }
  HookedMoveOrAttacks = HookedMoveOrAttacks << 1;
}

/* ovl12:0CC3. Affect handler of a cloud (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000).
     The cloud is the TCombatNode of the list CloudList whose owner is Who and whose kind is the high nibble of Affect's
     Data. Without one nothing happens. With one, "The air clears a little..." is shown (ShowFlashMessage), and the
     cloud goes: each arm still in place gets back the tile it covered, except that an arm where a body lies (BodyTable)
     shows BodyTile. The cloud is unlinked and freed, and every cloud left repaints its arms with CloudTile.
     Runs for affect $28 (id 40, InitAffectHandlers [V]). */
void ClearCloud(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ClearCloud");
  PCombatNode Node = 0;
  PCombatNode Cloud = 0;
  u8 Found = 0;
  u8 Index = 0;
  u8 Arm = 0;
  u8 CellX = 0;
  u8 CellY = 0;
  Index = ((*FPD(TAffect (*), Affect)).Data / 16);
  Found = 0;
  Cloud = CloudList;
  while (((Cloud != 0)) && !Found) {
    if ((((*FPD(TCombatNode (*), Cloud)).Owner == Who)) && (((*FPD(TCombatNode (*), Cloud)).Kind == Index))) {
      Found = 1;
    } else {
      Cloud = (*FPD(TCombatNode (*), Cloud)).Next;
    }
  }
  if (!Found) {
    return;
  }
  ShowFlashMessage(S("\032The air clears a little..."));
  {
    if (1 <= 4) {
      Arm = 1;
      for (;;) {
          if ((*FPD(TCombatNode (*), Cloud)).Arms[Arm - 1] != 0) {
            CellX = (*FPD(TCombatNode (*), Cloud)).X + DirStepX[CloudArmDirections[Arm]];
            CellY = (*FPD(TCombatNode (*), Cloud)).Y + DirStepY[CloudArmDirections[Arm]];
            Found = 0;
            {
              u8 limit = BodyCount;
              if (1 <= limit) {
                Index = 1;
                for (;;) {
                    if ((((BodyTable[Index - 1].Who != 0)) && ((BodyTable[Index - 1].X == CellX))) && ((BodyTable[Index - 1].Y == CellY))) {
                      Found = 1;
                    }
                  if (Index == limit) break;
                  Index++;
                }
              }
            }
            if (Found) {
              (*FPD(TCombatMap (*), CombatMap)).Cells[CellY][CellX] = BodyTile_OVL12;
            } else {
              (*FPD(TCombatMap (*), CombatMap)).Cells[CellY][CellX] = (*FPD(TCombatNode (*), Cloud)).Tiles[Arm - 1];
            }
          }
        if (Arm == 4) break;
        Arm++;
      }
    }
  }
  Node = CloudList;
  if (Node == Cloud) {
    CloudList = (*FPD(TCombatNode (*), Node)).Next;
  } else {
    while ((*FPD(TCombatNode (*), Node)).Next != Cloud) {
      Node = (*FPD(TCombatNode (*), Node)).Next;
    }
  }
  (*FPD(TCombatNode (*), Node)).Next = (*FPD(TCombatNode (*), Cloud)).Next;
  rtl_freemem(Cloud, 19);
  Node = CloudList;
  while (Node != 0) {
    {
      if (1 <= 4) {
        Arm = 1;
        for (;;) {
            if ((*FPD(TCombatNode (*), Node)).Arms[Arm - 1] != 0) {
              (*FPD(TCombatMap (*), CombatMap)).Cells[(s16)((*FPD(TCombatNode (*), Node)).Y + DirStepY[CloudArmDirections[Arm]])][(s16)((*FPD(TCombatNode (*), Node)).X + DirStepX[CloudArmDirections[Arm]])] = CloudTile;
            }
          if (Arm == 4) break;
          Arm++;
        }
      }
    }
    Node = (*FPD(TCombatNode (*), Node)).Next;
  }
}

/* ovl12:0FAC. Called by ovl12:1086 (ProtectFromNormalMissiles) and two more routines (ovl12:2901, 2BC8).
     When SelectedCharacter has an item in its first slot (SlotItems[0]) and DistanceToTarget (the distance from
     SelectedCharacter to Who, 1 when adjacent [I]) is above 1, a roll of 1d100 at or below Chance avoids the attack:
     "Avoids it" is shown on Who (row CombatMessageRow), the damage becomes 0, the attack roll MissRoll and
     AvoidedAttackCounter goes
     down by one. the kind of attack is not known [?]. Game meaning: avoiding a ranged attack (it needs DistanceToTarget
     above 1) [V code]: used by Protection From Normal Missiles ($29, spell 54), the THRI-KREEN ($68, 60 percent) and
     hill and fire giants ($78, 50 percent) [V monster data]. */
void AvoidDistantAttack(PCharacter Who, u8 Chance)
{
  POOL_TRACE("AvoidDistantAttack");
  if ((*FPD(TCharacter (*), SelectedCharacter)).SlotItems[0] != 0) {
    if (DistanceToTarget(SelectedCharacter, Who) > 1) {
      if (RollDice(1, 100) <= Chance) {
        ShowCharacterMessage(Who, S("\011Avoids it"), CombatMessageRow, 1);
        DamageAmount = 0;
        AttackRoll = MissRoll;
        AvoidedAttackCounter--;
      }
    }
  }
}

/* ovl12:101D. The item Who keeps in its first slot (SlotItems[0], TCharacter +$CC; the 13 slots are the items the
     character remembers, POOLVARS), or nil when the slot is empty. When there is a slot item, ChooseAttackItem (Who, Item)
     runs first: its Item is kept when it returns nonzero and gives a non-nil item, otherwise the slot item is the result.
     Purpose unknown: what ChooseAttackItem finds is not known yet [?]. */
PItem FirstSlotItem(PCharacter Who)
{
  POOL_TRACE("FirstSlotItem");
  PItem Result = 0;
  farptr Item = 0;
  u8 Found = 0;
  Item = 0;
  if ((*FPD(TCharacter (*), Who)).SlotItems[0] != 0) {
    Found = ChooseAttackItem(Who, &Item);
    if (((Found == 0)) || ((Item == 0))) {
      Item = (*FPD(TCharacter (*), Who)).SlotItems[0];
    }
  }
  Result = Item;
  return Result;
}

/* ovl12:1086. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). When the
     selected character's first remembered item (FirstSlotItem) has Plus 0, Who avoids the attack in progress at once
     (AvoidDistantAttack with AlwaysAvoids). Runs for affect $29 (id 41, InitAffectHandlers [V]). */
void ProtectFromNormalMissiles(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ProtectFromNormalMissiles");
  if (FirstSlotItem(SelectedCharacter) != 0) {
    if ((*FPD(TMenuLine (*), FirstSlotItem(SelectedCharacter))).Plus == 0) {
      AvoidDistantAttack(Who, AlwaysAvoids);
    }
  }
}

/* ovl12:10C1. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It halves
     HookedMoveOrAttacks, the byte that ApplyHaste (ovl12:0C4B) doubles every time it runs. Runs for affect $2A (id
     42, InitAffectHandlers [V]). */
void ApplySlow(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ApplySlow");
  HookedMoveOrAttacks = (s16)((u16)HookedMoveOrAttacks >> 1);
}

/* ovl12:10DE. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It gives Who
     the affect AffectDrainsStrength (a Cure Disease affect, ovl04:031E) for WeakeningDuration rounds with the Data of Affect,
     when TryAddAffect allows it. While
     Who's Strength is above 3 each run shows "is weakened" (row CombatMessageRow) and takes one
     off Strength; at 3 or less Who gets AffectHelpless unless it has it already. Runs for affect $2B (id 43,
     InitAffectHandlers [V]). */
void WeakenStrength(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("WeakenStrength");
  farptr FoundAffect = 0;
  if (TryAddAffect(Who, AffectDrainsStrength, (*FPD(TAffect (*), Affect)).Data, WeakeningDuration)) {
    if ((*FPD(TCharacter (*), Who)).Strength > MinimumStrength) {
      ShowCharacterMessage(Who, S("\013is weakened"), CombatMessageRow, 1);
      (*FPD(TCharacter (*), Who)).Strength--;
    } else if (!HasAffect(Who, AffectHelpless, &FoundAffect)) {
      AddAffect(Who, AffectHelpless, PermanentDuration, DataFF, NoRemoveHandler);
    }
  }
}

/* ovl12:1168. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It gives Who
     the disease affect AffectCauseDisease for AffectCauseDiseaseDuration rounds, with the Data of Affect, when TryAddAffect
     allows it. Then, while Who has more than one hit point (HpCurrent), it deals 1 point of plain damage (DamageKind 0, no
     save, DealDamage) and, outside combat, redraws the selected character. Otherwise Who gets AffectHelpless unless it has
     it already. Runs for affect $2C (id 44, InitAffectHandlers [V]). */
void CauseDiseaseAndDamage(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("CauseDiseaseAndDamage");
  farptr FoundAffect = 0;
  if (TryAddAffect(Who, AffectCauseDisease, (*FPD(TAffect (*), Affect)).Data, AffectCauseDiseaseDuration)) {
    if ((*FPD(TCharacter (*), Who)).HpCurrent > 1) {
      DamageKind = 0;
      DealDamage(Who, 1, 0, 0);
      if (ViewMode != ViewModeCombat) {
        DrawPartyRoster(SelectedCharacter);
      }
    } else if (!HasAffect(Who, AffectHelpless, &FoundAffect)) {
      AddAffect(Who, AffectHelpless, PermanentDuration, DataFF, NoRemoveHandler);
    }
  }
}

/* ovl12:11F9. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It copies
     the character Who attacked last (Who's combat Target, TCombatant at +$108 of Who, MeleeAttack sets it in ovl08) into
     AttackTarget. When the selected character has CreatureType (+$9F of TCharacter, CreatureHumanoid) and its
     CombatSize has footprint kind 2 (bits 0..6 of +$6C), AttackRoll loses AttackPenalty for each of the names
     OgreTrollGiantNames[1..8]
     that the target's name equals. Runs for affect $2F (id 47, InitAffectHandlers [V]); given to the dwarf and the gnome by
     CreateCharacter [V]. QUIRK ovl12:11F9: it tests CreatureType and CombatSize of SelectedCharacter but the
     name of AttackTarget (Who's own last target), where the sibling handlers test the target for both [?]. */
void LowerAttackVsOgreTrollGiant(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("LowerAttackVsOgreTrollGiant");
  u8 I = 0;
  AttackTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  if ((((*FPD(TCharacter (*), SelectedCharacter)).CreatureType == CreatureHumanoid)) && (((((*FPD(TCharacter (*), SelectedCharacter)).CombatSize & CombatKindMask)) == LargeFootprintKind_OVL12))) {
    {
      if (1 <= OgreTrollGiantNameCount) {
        I = 1;
        for (;;) {
            if (rtl_str_cmp((*FPD(TCharacter (*), AttackTarget)).Name, OgreTrollGiantNames[I - 1]) == 0) {
              AttackRoll -= AttackPenalty;
            }
          if (I == OgreTrollGiantNameCount) break;
          I++;
        }
      }
    }
  }
}

/* ovl12:1276. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). When the selected
     character has CreatureType (+$9F of TCharacter) set to CreatureHumanoid and its name is 'BUGBEAR' or 'GNOLL', AttackRoll
     loses AttackPenalty. Runs for affect $30 (id 48, InitAffectHandlers [V]); given to the gnome by CreateCharacter [V]. */
void LowerAttackIfSelectedIsBugbearOrGnoll(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("LowerAttackIfSelectedIsBugbearOrGnoll");
  if ((*FPD(TCharacter (*), SelectedCharacter)).CreatureType == CreatureHumanoid) {
    if (((rtl_str_cmp((*FPD(TCharacter (*), SelectedCharacter)).Name, S("\007BUGBEAR")) == 0)) || ((rtl_str_cmp((*FPD(TCharacter (*), SelectedCharacter)).Name, S("\005GNOLL")) == 0))) {
      AttackRoll -= AttackPenalty;
    }
  }
}

/* ovl12:12B2. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is passed on, ovl24:0000). The side
     the affect names is Affect's Data bit 4 (SideDataBit, 0 or 1). When Who's Side (+$10E of TCharacter) equals it,
     RaiseAttackAndSave (ovl12:0C06) runs with Who, Affect and Mode; otherwise AttackRoll and SaveRoll each lose one.
     Runs for affect $31 (id 49, InitAffectHandlers [V]). */
void RaiseOrLowerAttackAndSave(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("RaiseOrLowerAttackAndSave");
  u8 Side = 0;
  Side = ((((*FPD(TAffect (*), Affect)).Data & SideDataBit)) / 16);
  if ((*FPD(TCharacter (*), Who)).Side == Side) {
    RaiseAttackAndSave(Who, Affect, Mode);
  } else {
    AttackRoll--;
    SaveRoll--;
  }
}

/* ovl12:12FB. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It gives Who
     the healing block AffectMummyDisease (ovl24:175D: HealCharacter with Flag 0 does nothing while it is there) for
     MummyDiseaseDuration rounds, with the Data of Affect, when TryAddAffect allows it. Then HealCharacter heals Who
     by one hit point with Flag 1, which the block does not stop, and when that healed Who, ShowHealResult (00BA:234A, not
     named yet) runs on Who. The map also had an entry at ovl12:1307, which is the middle of this routine (its pushes
     for the first call start at 12FB), so it has no routine of its own. Runs for affect $32 (id 50, InitAffectHandlers [V]). */
void AddHealingBlockAndHeal(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("AddHealingBlockAndHeal");
  if (TryAddAffect(Who, AffectMummyDisease, (*FPD(TAffect (*), Affect)).Data, MummyDiseaseDuration)) {
    if (HealCharacter(Who, 1, 1)) {
      ShowHealResult(Who);
    }
  }
}

/* ovl12:133F. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It calls
     EndCombatTurn(Who), the routine the combat units call to end a combatant's turn (ovl08, ovl09 AiTurn), and does
     nothing with its result: a Turbo Pascal statement cannot call a function, so the call is tested and the test
     stands alone. runs for affects $1F, $33, $34 and $35 (ids 31, 51, 52, 53, InitAffectHandlers [V]). */
void EndAffectedCombatantTurn(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("EndAffectedCombatantTurn");
  if (EndCombatTurn(Who) != 0) {
  }
}

/* ovl12:1355. Affect handler (the AffectHandlers shape: Who, Affect and Mode) with an empty body, like IgnoreAffect
     (ovl12:0647): none of its parameters is read and no global is written. runs for affect $36 (id 54,
     InitAffectHandlers [V]). */
void IgnoreAffect36(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("IgnoreAffect36");
}

/* ovl12:135C. Affect handler (the AffectHandlers shape: Who, Affect and Mode) with an empty body, like IgnoreAffect
     (ovl12:0647): none of its parameters is read and no global is written. runs for affect $37 (id 55,
     InitAffectHandlers [V]). */
void IgnoreAffect37(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("IgnoreAffect37");
}

/* ovl12:1363. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It gives Who the
     affect AffectInvisibility (ovl24:0E52, AddAffect) for InvisibilityDuration rounds with the Data
     InvisibilityData,
     with NoRemoveHandler: the handler does not run when the affect is removed. AffectInvisibility is the affect
     RollToHit
     clears from the attacker (ovl24:0CB7) [I]. runs for affect $38 (id 56, InitAffectHandlers [V]). */
void GiveInvisibilityForOneRound(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("GiveInvisibilityForOneRound");
  AddAffect(Who, AffectInvisibility, InvisibilityDuration, InvisibilityData, NoRemoveHandler);
}

/* ovl12:1399. Affect handler of the rot (AffectHandlers shape: Who, Affect and Mode; Mode not read; the affect is
     AffectRot, $39, which Cure Disease removes, whitepaper 5.19). Does nothing while the Temple removes affects (RemovingAffects
     is not 0, ovl04:0386). Otherwise it shows "Rots..." on Who (row CombatMessageRow) and takes RotCharismaLoss off
     Who's Charisma
     (+$15), never below RotMinimumCharisma. Then the rot moves on: while the stage (the high nibble of the affect's
     Data) is above RotLastStage, the stage drops by one (RotStage) and TryAddAffect gives Who the rot again with that
     Data for RotDuration rounds. At the last stage Who dies: DropFromFight takes Who out with StatusGone and the
     text "Dies rots away". Runs for affect $39 (id 57, InitAffectHandlers [V]). */
void ProgressRot(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ProgressRot");
  if (RemovingAffects != 0) {
    return;
  }
  ShowCharacterMessage(Who, S("\007Rots..."), CombatMessageRow, 1);
  if ((*FPD(TCharacter (*), Who)).Charisma > RotCharismaLoss) {
    (*FPD(TCharacter (*), Who)).Charisma -= RotCharismaLoss;
  } else {
    (*FPD(TCharacter (*), Who)).Charisma = 0;
  }
  if ((*FPD(TCharacter (*), Who)).Charisma < RotMinimumCharisma) {
    (*FPD(TCharacter (*), Who)).Charisma = RotMinimumCharisma;
  }
  if (((*FPD(TAffect (*), Affect)).Data / 16) > RotLastStage) {
    (*FPD(TAffect (*), Affect)).Data -= RotStage;
    if (TryAddAffect(Who, AffectRot, (*FPD(TAffect (*), Affect)).Data, RotDuration)) {
    }
  } else {
    DropFromFight(Who, StatusGone, S("\016Dies rots away"));
  }
}

/* ovl12:1452. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It stops Who's
     movement: the combat record's Moves (+$6 of TCombatant, the movement left) goes to 0. When HookRunning is set it also
     clears HookedMoveOrAttacks, the byte ApplyHaste doubles. runs for affect $3A (id 58,
     InitAffectHandlers [V]). */
void StopMovement(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("StopMovement");
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves = 0;
  if (HookRunning) {
    HookedMoveOrAttacks = 0;
  }
}

/* ovl12:1472. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). It gives Who the affect
     AffectRegainHitPoints (AddAffect, ovl24:0E52) with Duration 0 (permanent), the Data AffectRegainHitPointsData and no handler
     when it is removed (NoRemoveHandler). runs for affect $3B (id 59, InitAffectHandlers [V]). */
void GiveRegainHitPointsAffect(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("GiveRegainHitPointsAffect");
  AddAffect(Who, AffectRegainHitPoints, PermanentDuration, AffectRegainHitPointsData, NoRemoveHandler);
}

/* ovl12:1490. Damage hook (the AffectHandlers shape: Who, Affect and Mode; none of them read). While the damage is fire
     (DamageKind bit KindFire, DS:6819), each of the LastDiceCount dice of the last roll takes FireReductionPerDie off
     DamageAmount, and it never goes below LastDiceCount; SaveRoll then gets FireProtectionSaveBonus. Damage that is not
     magical (KindMagic clear) is cancelled altogether: CancelPendingHook(0) clears DamageAmount and HookAffectId.
     runs for affect $3D (id 61, InitAffectHandlers [V]). Game meaning: Fire Resistance, the ovl15 DisplaySpellEffects
     name of affect $3D [V]; the item side is the Ring with Affects[3] $81 and Affects[2] $3D (Ring of Fire Resistance [I]). */
void ReduceFireDamageByRoll(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ReduceFireDamageByRoll");
  u8 I = 0;
  if (((DamageKind & KindFire)) != 0) {
    {
      u8 limit = LastDiceCount;
      if (1 <= limit) {
        I = 1;
        for (;;) {
            DamageAmount -= FireReductionPerDie;
            if (DamageAmount < LastDiceCount) {
              DamageAmount = LastDiceCount;
            }
          if (I == limit) break;
          I++;
        }
      }
    }
    SaveRoll += FireProtectionSaveBonus;
    if (((DamageKind & KindMagic)) == 0) {
      CancelPendingHook(0);
    }
  }
}

/* ovl12:14EB. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode not read), the same shape as
     AddHealingBlockAndHeal (ovl12:12FB) with the trained-out affect: it gives Who AffectTrainedOut (the Constitution
     limit affect of TrainConstitution, ovl12:0233) for TrainedOutDuration rounds with the Data of Affect, when TryAddAffect
     allows it. Then HealCharacter heals Who by one hit point with Flag 1, which a healing block does not stop, and when
     that healed Who, ShowHealResult (00BA:234A) runs on Who. Runs for affect $3E (id 62,
     InitAffectHandlers [V]). */
void AddTrainedOutAndHeal(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("AddTrainedOutAndHeal");
  if (TryAddAffect(Who, AffectTrainedOut, (*FPD(TAffect (*), Affect)).Data, TrainedOutDuration)) {
    if (HealCharacter(Who, 1, 1)) {
      ShowHealResult(Who);
    }
  }
}

/* ovl12:1545. Poison hook of an attack (the frame is Who and Bonus; Bonus is the save bonus, 0 in
     PoisonAttackTargetBonus0's call at ovl12:166A). AttackTarget becomes Who's Combat^.Target, the character Who
     attacked last. That character makes a poison save (SaveKindPoison, with Bonus). When it fails, "is Poisoned"
     (row CombatMessageRow) is shown on it, DelayByGameSpeed waits, it
     gets AffectPoisoned for good (AddAffect with Duration 0, Data $FF, no handler on removal) and DropFromFight kills it
     with StatusDead and "is killed". The map split this routine at ovl12:1543 and ovl12:1583, which are inside its
     literal pool and inside its code. It is the poison hook of affects $40, $41, $42 and $46 (ids 64, 65, 66, 70,
     InitAffectHandlers
     [V]). */
void PoisonAttackTarget(PCharacter Who, s8 Bonus)
{
  POOL_TRACE("PoisonAttackTarget");
  AttackTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  if (!SavingThrow(AttackTarget, SaveKindPoison, Bonus)) {
    ShowCharacterMessage(AttackTarget, S("\013is Poisoned"), CombatMessageRow, 0);
    DelayByGameSpeed();
    AddAffect(AttackTarget, AffectPoisoned, PermanentDuration, DataFF, NoRemoveHandler);
    DropFromFight(AttackTarget, StatusDead, S("\011is killed"));
  }
}

/* ovl12:15EB. Paralyses the character Who attacked last. AttackTarget takes Who's combat Target (TCombatant +$A) and
     it makes the paralysis save (SavingThrow kind SaveKindParalysis, bonus 0). Unless it saves, "is Paralyzed" is shown
     on it (ShowHitMessage, flag 1, as ApplyAffect shows an affect's message) and it gets the affect AffectParalysis for
     Duration rounds with Data ParalysisData, with no handler when it is removed (NoRemoveHandler). Parameters: Who is the
     attacker, Duration the rounds (the callers pass a roll or 63). Unused is the third byte: both callers push 0 and this
     routine never reads it. */
void ParalyzeAttackTarget(PCharacter Who, u16 Duration, u8 Unused)
{
  POOL_TRACE("ParalyzeAttackTarget");
  AttackTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  if (!SavingThrow(AttackTarget, SaveKindParalysis, 0)) {
    ShowHitMessage(AttackTarget, 1, S("\014is Paralyzed"));
    AddAffect(AttackTarget, AffectParalysis, Duration, ParalysisData, NoRemoveHandler);
  }
}

/* ovl12:165D. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
     The poison hook of an attack with save bonus 0: PoisonAttackTarget (ovl12:1545) with Bonus 0. Runs for affect $40 (id 64,
     InitAffectHandlers [V]). */
void PoisonAttackTargetBonus0(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("PoisonAttackTargetBonus0");
  PoisonAttackTarget(Who, 0);
}

/* ovl12:1671. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
     The poison hook of an attack with save bonus 4: PoisonAttackTarget (ovl12:1545) with Bonus 4. Runs for affect $41 (id 65,
     InitAffectHandlers [V]). */
void PoisonAttackTargetBonus4(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("PoisonAttackTargetBonus4");
  PoisonAttackTarget(Who, 4);
}

/* ovl12:1685. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
     The poison hook of an attack with save bonus 2: PoisonAttackTarget (ovl12:1545) with Bonus 2. Runs for affect $42 (id 66,
     InitAffectHandlers [V]). */
void PoisonAttackTargetBonus2(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("PoisonAttackTargetBonus2");
  PoisonAttackTarget(Who, 2);
}

/* ovl12:1699. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
     It paralyses the character Who attacked last for RollDice(2, 8) rounds: ParalyzeAttackTarget (ovl12:15EB) with the
     unused byte 0. The bearer is the THRI-KREEN (MON6SPC block 118) [V]; it runs for affect $43 (id 67,
     InitAffectHandlers [V]). */
void ParalyzeAttackTargetFor2d8(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ParalyzeAttackTargetFor2d8");
  ParalyzeAttackTarget(Who, RollDice(2, 8), 0);
}

/* ovl12:16BB. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
     Unless the character Who attacked last (Who^.Combat^.Target) has race RaceElf, it is paralysed for
     ParalysisDuration rounds: ParalyzeAttackTarget (ovl12:15EB) with the unused byte 0. The ghoul touch: the bearer is
     the GHOUL (MON4SPC and MON8SPC block 72, for 63 rounds) [V], elves are immune [I]; it runs for affect $44 (id 68,
     InitAffectHandlers [V]). */
void ParalyzeAttackTargetUnlessImmune(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ParalyzeAttackTargetUnlessImmune");
  if ((*FPD(TCharacter (*), (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target)).Race != RaceElf) {
    ParalyzeAttackTarget(Who, ParalysisDuration, 0);
  }
}

/* ovl12:16E6. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
     Paralyses the character Who attacked last for 1d9 plus ParalysisBaseRounds rounds: ParalyzeAttackTarget (ovl12:15EB).
     Runs for affect $45 (id 69, InitAffectHandlers [V]). */
void ParalyzeAttackTargetFor1d9Plus10(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ParalyzeAttackTargetFor1d9Plus10");
  /* the third argument is the unused byte: ParalyzeAttackTarget never reads it; this caller passes $FE, the others 0 */
  ParalyzeAttackTarget(Who, (s16)(RollDice(1, ParalysisDieSides) + ParalysisBaseRounds), 0xFE);
}

/* ovl12:170B. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
     The poison hook of an attack with save bonus -2: PoisonAttackTarget (ovl12:1545) with Bonus -2. Runs for affect $46 (id 70,
     InitAffectHandlers [V]). */
void PoisonAttackTargetBonusMinus2(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("PoisonAttackTargetBonusMinus2");
  PoisonAttackTarget(Who, (-2));
}

/* ovl12:171F. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). Sets
     HookVetoFlag to 1 (the flag ovl12:0918 and ovl12:0C26 also set; AttackTargetAllowed reads it, OVL13.PAS lines 647..671) and
     takes AttackPenalty off AttackRoll
     without the test InvisibleTargetHardToHit (ovl12:0918) makes first. Runs for affect $47 (id 71, InitAffectHandlers [V]). */
void InvisibleTargetCannotBeTargeted(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("InvisibleTargetCannotBeTargeted");
  HookVetoFlag = 1;
  AttackRoll -= AttackPenalty;
}

/* ovl12:1730. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). When a 1d100 roll
     is at or below CamouflageInvisibilityChance it gives Who affect AffectInvisibility (AddAffect, ovl24:0E52) for
     InvisibilityDuration rounds with the Data InvisibilityData and no handler when it is removed:
     the same AddAffect
     as GiveInvisibilityForOneRound (ovl12:1363), but with the roll. runs for affect $48 (id 72,
     InitAffectHandlers [V]). */
void CamouflageGivesInvisibility(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("CamouflageGivesInvisibility");
  if (RollDice(1, 100) <= CamouflageInvisibilityChance) {
    AddAffect(Who, AffectInvisibility, InvisibilityDuration, InvisibilityData, NoRemoveHandler);
  }
}

/* ovl12:176F. Affect handler of the blood drain (the AffectHandlers shape: Who, Affect and Mode; Mode 0 applies, any other
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
     a combatant with it nonzero to flee, ovl09:10D7). Runs for affect $4B (id 75, InitAffectHandlers [V]). */
void DrainBloodFromCombatant(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("DrainBloodFromCombatant");
  u8 Turn = 0;
  u8 Dice = 0;
  AttackTarget = CombatantRecord[(*FPD(TAffect (*), Affect)).Data - 1];
  if ((((Mode != 0)) || (((*FPD(TCharacter (*), Who)).Flag10D == 0))) || (((*FPD(TCharacter (*), AttackTarget)).Flag10D == 0))) {
    RemoveAffect(AttackTarget, AffectHeldFast, 0);
    if (Mode == 0) {
      (*FPD(TAffect (*), Affect)).Flag = 0;
      RemoveAffect(Who, AffectBloodDrain, Affect);
    }
    if ((((*FPD(TCharacter (*), Who)).Flag10D != 0)) && (((*FPD(TCharacter (*), AttackTarget)).Flag10D != 0))) {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).ForcedFlight = 1;
    }
  } else {
    ShowCharacterMessage(Who, S("\020Sucks some Blood"), CombatMessageRow, 1);
    Dice = RollDiceCounted(1, 4);
    DamageKind = 0;
    DealDamage(AttackTarget, Dice, 0, 0);
    Turn = EndCombatTurn(Who);
    if ((((*FPD(TCharacter (*), AttackTarget)).Flag10D != 0)) && ((((*FPD(TAffect (*), Affect)).Duration / 16) > Dice))) {
      (*FPD(TAffect (*), Affect)).Duration -= (s16)(Dice * 16);
    } else {
      RemoveAffect(Who, AffectBloodDrain, Affect);
    }
  }
}

/* ovl12:18B5. Affect handler that starts a blood drain (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode
     are not read, ovl24:0000). The character Who attacked last (Who's combat Target) is copied into AttackTarget. Who gets
     AffectBloodDrain for BloodDrainDuration rounds, its Data the combatant index of AttackTarget (CombatantIndex), so
     DrainBloodFromCombatant (ovl12:176F) runs on it when it is removed. AttackTarget gets AffectHeldFast and that affect's
     handler runs at once (CallAffectHandler). Runs for affect $4C (id 76, InitAffectHandlers [V]). */
void StartBloodDrain(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("StartBloodDrain");
  AttackTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  AddAffect(Who, AffectBloodDrain, BloodDrainDuration, CombatantIndex(AttackTarget), RunsHandlerOnRemove);
  AddAffect(AttackTarget, AffectHeldFast, HeldFastDuration, HeldFastData, NoRemoveHandler);
  CallAffectHandler(AffectHeldFast, AttackTarget, 0, 0);
}

/* ovl12:1935. Affect handler that holds a weak combat target fast (the AffectHandlers shape: Who, Affect and Mode; Affect and
     Mode are not read, ovl24:0000). The character Who attacked last (Who's combat Target) is copied into AttackTarget. When
     AttackTarget's Strength (TCharacter +$10) is below HeldFastStrengthLimit, Who gets AffectForcedAttack (Duration 0, its
     Data the combatant index of AttackTarget; its handler is ForcedAttack, ovl13:3A86, which runs when it is removed),
     AttackTarget gets AffectHeldFast and that affect's handler runs, and "is held fast" is shown on AttackTarget at row
     CombatMessageRow
     (ShowCharacterMessage). Runs for affect $4D (id 77, InitAffectHandlers [V]). */
void HoldWeakTargetFast(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("HoldWeakTargetFast");
  AttackTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  if ((*FPD(TCharacter (*), AttackTarget)).Strength < HeldFastStrengthLimit) {
    AddAffect(Who, AffectForcedAttack, ForcedAttackDuration, CombatantIndex(AttackTarget), RunsHandlerOnRemove);
    AddAffect(AttackTarget, AffectHeldFast, HeldFastDuration, HeldFastData, NoRemoveHandler);
    CallAffectHandler(AffectHeldFast, AttackTarget, 0, 0);
    ShowCharacterMessage(AttackTarget, S("\014is held fast"), CombatMessageRow, 1);
  }
}

/* ovl12:19D9. Affect handler that revives Who (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000).
     ReviveCombatant (ovl24:1869) puts Who back on its square at Who's current hit points (HpCurrent) and returns False when it
     cannot be placed. Then Who gets AffectRevival for RevivalRetryDuration round, with the Data of Affect, so the revival is
     tried again (TryAddAffect; its result is stored and never read). Runs for affect $4E (id 78, InitAffectHandlers [V]). */
void ReviveOrRetryRevival(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ReviveOrRetryRevival");
  u8 Added = 0;
  if (!ReviveCombatant(Who, (*FPD(TCharacter (*), Who)).HpCurrent)) {
    Added = TryAddAffect(Who, AffectRevival, (*FPD(TAffect (*), Affect)).Data, RevivalRetryDuration);
  }
}

/* ovl12:1A19. Affect handler that burns the character Who attacked last (the AffectHandlers shape: Who, Affect and Mode;
     none is read, ovl24:0000). DamageKind becomes 9 (KindFire or KindMagic, fire with the magic bit, as
     BoostFireAttackByTarget sets it), then 2d10 damage goes to Who's combat Target (Who^.Combat^.Target) without a save
     (DealDamage, ovl24:1344). Runs for affect $4F (id 79, InitAffectHandlers [V]). */
void FireAttackTargetFor2d10(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("FireAttackTargetFor2d10");
  DamageKind = (KindFire | KindMagic);
  DealDamage((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target, RollDiceCounted(2, 10), 0, 0);
}

/* ovl12:1A4C. Affect handler that splashes acid on the character Who attacked last (the AffectHandlers shape: Who, Affect
     and Mode; none is read, ovl24:0000). DamageKind becomes KindAcid, then 1d4 damage goes to Who's combat Target without a
     save (DealDamage, ovl24:1344). Runs for affect $50 (id 80, InitAffectHandlers [V]). */
void AcidAttackTargetFor1d4(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("AcidAttackTargetFor1d4");
  DamageKind = KindAcid;
  DealDamage((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target, RollDiceCounted(1, 4), 0, 0);
}

/* ovl12:1AAA. Affect handler that frightens the side of Who (the AffectHandlers shape: Who, Affect and Mode; Affect and
     Mode are not read, ovl24:0000). It walks the party list from PartyListHead (TCharacter +$104 is the next member).
     Every member
     with Flag10D set on the side of Who (OpposingSide, the side of the actor) makes a SavingThrow of kind SaveKindSpell. Its
     HighestLevel (+$73) decides the affect: 0 to 3 gives AffectParalysis with the message 'is paralyzed with fear', 4 or 5
     gives AffectCurse with 'is weakened by fear'; the Duration is 0 for both, and a successful save negates the affect
     (ApplyAffect, ovl24:1656). Other levels get nothing. Runs for affect $51 (id 81, InitAffectHandlers [V]). */
void FrightenSideWithFear(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("FrightenSideWithFear");
  PCharacter Scan = 0;
  u8 FearSaved = 0;
  Scan = PartyListHead;
  while (Scan != 0) {
    if ((*FPD(TCharacter (*), Scan)).Flag10D != 0) {
      if (OpposingSide(Who) == (*FPD(TCharacter (*), Scan)).Side) {
        FearSaved = SavingThrow(Scan, SaveKindSpell, 0);
        switch ((*FPD(TCharacter (*), Scan)).HighestLevel) {
        case 0:
        case 1:
        case 2:
        case 3:
        {
          ApplyAffect(Scan, AffectParalysis, PermanentDuration, FearData, NoRemoveHandler, SaveNegatesAffect, FearSaved, S("\026is paralyzed with fear"));
          break;
        }
        case FearWeakenMinLevel:
        case FearWeakenMaxLevel:
        {
          ApplyAffect(Scan, AffectCurse, PermanentDuration, FearData, NoRemoveHandler, SaveNegatesAffect, FearSaved, S("\023is weakened by fear"));
          break;
        }
        }
      }
    }
    Scan = (*FPD(TCharacter (*), Scan)).Next;
  }
}

/* ovl12:1BA8. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It takes
     affect AffectParalyzeSide off every member of the party list (PartyListHead, +$104 is the next member) first. Then each
     member with Flag10D set on the side of Who (OpposingSide) makes a paralysis save (SaveKindParalysis) with a bonus
     of 1 when its side has six or more members (SideCounts, the side's count [?]) and 2 when it is a human,
     and gets AffectParalysis for 1d4 rounds with Data FearData; "is paralyzed with fear" is shown on it, and a successful
     save negates the affect. Runs for affect $52 (id 82, InitAffectHandlers [V]). */
void ParalyzeSideWithFear(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ParalyzeSideWithFear");
  PCharacter Scan = 0;
  u8 Bonus = 0;
  u8 Saved = 0;
  Scan = PartyListHead;
  while (Scan != 0) {
    RemoveAffect(Scan, AffectParalyzeSide, 0);
    if ((*FPD(TCharacter (*), Scan)).Flag10D != 0) {
      if (OpposingSide(Who) == (*FPD(TCharacter (*), Scan)).Side) {
        Bonus = 0;
        if (SideCounts[(*FPD(TCharacter (*), Scan)).Side] >= LargeSideCount) {
          Bonus++;
        }
        if ((*FPD(TCharacter (*), Scan)).Race == RaceHuman) {
          Bonus += HumanFearSaveBonus;
        }
        Saved = SavingThrow(Scan, SaveKindParalysis, Bonus);
        ApplyAffect(Scan, AffectParalysis, RollDice(1, FearDieSides), FearData, NoRemoveHandler, SaveNegatesAffect, Saved, S("\026is paralyzed with fear"));
      }
    }
    Scan = (*FPD(TCharacter (*), Scan)).Next;
  }
}

/* ovl12:1CAD. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000): a stoning gaze
     [I]. "gazes..." is shown on Who (row CombatMessageRow), and the gaze line is drawn from Who to the character Who
     attacked last
     (AttackTarget, a copy of Combat^.Target). When Who has affect AffectGazeReflectable (HasAffect), the readied items of
     AttackTarget are walked: a readied item with a NameNum of MirrorNameNum turns the gaze back: "reflects it!" is shown
     on AttackTarget (row ReflectRow), the line is drawn back, and the gaze falls on Who (AttackTarget := Who). The gaze target
     then makes a stone save (SaveKindStone, no bonus); when it fails, DropFromFight takes it out of the fight with StatusStoned
     and "is Stoned". Runs for affect $53 (id 83, InitAffectHandlers [V]). */
void GazeStonesTarget(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("GazeStonesTarget");
  PItem Item = 0;
  u8 Reflected = 0;
  farptr FoundAffect = 0;
  AttackTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  ShowCharacterMessage(Who, S("\010gazes..."), CombatMessageRow, 0);
  DrawCombatIcon(GazeAnimation);
  WalkCombatLine(CombatantX(Who), CombatantY(Who), CombatantX(AttackTarget), CombatantY(AttackTarget), GazeLineKind, GazeLineFlag);
  if (HasAffect(Who, AffectGazeReflectable, &FoundAffect)) {
    Reflected = 0;
    Item = (*FPD(TCharacter (*), AttackTarget)).Items;
    while (((Item != 0)) && !Reflected) {
      if ((*FPD(TMenuLine (*), Item)).Readied) {
        if (((((*FPD(TMenuLine (*), Item)).NameNum[0] == MirrorNameNum)) || (((*FPD(TMenuLine (*), Item)).NameNum[1] == MirrorNameNum))) || (((*FPD(TMenuLine (*), Item)).NameNum[2] == MirrorNameNum))) {
          ShowCharacterMessage(AttackTarget, S("\014reflects it!"), ReflectRow, 0);
          WalkCombatLine(CombatantX(AttackTarget), CombatantY(AttackTarget), CombatantX(Who), CombatantY(Who), GazeLineKind, GazeLineFlag);
          Reflected = 1;
          AttackTarget = Who;
        }
      }
      Item = (*FPD(TMenuLine (*), Item)).Next;
    }
  }
  if (!SavingThrow(AttackTarget, SaveKindStone, 0)) {
    DropFromFight(AttackTarget, StatusStoned, S("\011is Stoned"));
  }
}

/* ovl12:1E77. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000): a charm gaze
     [I]. Who's gaze reaches the character Who attacked last (AttackTarget) when AttackTargetAllowed allows it and WalkLine
     walks the line from Who to AttackTarget's cell (WalkLine may move the end cell, EndX and EndY). "Gazes..." is shown on Who
     (row CombatMessageRow), the gaze line is drawn to AttackTarget as GazeStonesTarget draws it (WalkCombatLine), CastingSpell
     becomes 10,
     and AttackTarget gets the charm affect AffectCharm for good with Data: Who's side in bit 7 (ControlSideBit) and
     CharmData. A successful fear save (SavingThrow kind 4, CharmSaveBonus) negates it, and "is charmed" is shown on it.
     Then, when AttackTarget has the affect, its handler runs at once (CallAffectHandler, Mode 0). Runs for affect $54 (id 84,
     InitAffectHandlers [V]). */
void GazeCharmsTarget(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("GazeCharmsTarget");
  u16 StepCount = 0;
  farptr FoundAffect = 0;
  s8 EndX = 0;
  s8 EndY = 0;
  AttackTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  EndX = CombatantX(AttackTarget);
  EndY = CombatantY(AttackTarget);
  if (!AttackTargetAllowed(Who, AttackTarget)) {
    return;
  }
  if (!WalkLine(CombatantX(Who), CombatantY(Who), &EndX, &EndY, &StepCount, CombatMap)) {
    return;
  }
  ShowCharacterMessage(Who, S("\010Gazes..."), CombatMessageRow, 0);
  DrawCombatIcon(GazeAnimation);
  WalkCombatLine(CombatantX(Who), CombatantY(Who), CombatantX(AttackTarget), CombatantY(AttackTarget), GazeLineKind, GazeLineFlag);
  CastingSpell = SpellCharmPerson;
  ApplyAffect(AttackTarget, AffectCharm, PermanentDuration, (s16)(((*FPD(TCharacter (*), Who)).Side * ControlSideBit) + CharmData), RunsHandlerOnRemove, SaveNegatesAffect, SavingThrow((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target, SaveKindSpell, CharmSaveBonus), S("\012is charmed"));
  if (HasAffect(AttackTarget, AffectCharm, &FoundAffect)) {
    CallAffectHandler(AffectCharm, AttackTarget, FoundAffect, 0);
  }
}

typedef struct Frame_DrainLevels {
  PCharacter Who;
  u8 Count;
  String40_RES06 Msg;
  s32 CurXp;
  s32 BestXp;
  s8 ClassIndex;
  u8 Step;
  u8 Total;
  u8 Quotient;
  u8 Point;
} Frame_DrainLevels;

/* ovl12:2002 (nested in ovl12:2122, which passes its frame as the hidden parameter: push bp; push cs; call).
       Returns the class of Who with the highest level: a class whose level is at least the best so far is
       taken when its experience floor (ExperienceTable, 0 for level 1 or less) is at least BestXp or is -1
       [?]; BestXp (of the parent) and BestLevel take its values. QUIRK ovl12:2002: -1 is taken whatever the
       best so far. */
static s8 DrainLevels_HighestLevelClass(struct Frame_DrainLevels *up)
{
  s8 Result = 0;
  s8 J = 0;
  s8 BestLevel = 0;
  s8 Level = 0;
  up->BestXp = 0;
  BestLevel = 0;
  {
    if (0 <= LastClass_OVL12) {
      J = 0;
      for (;;) {
          Level = (*FPD(TCharacter (*), up->Who)).ClassLevels[J];
          if (Level > 1) {
            up->CurXp = ExperienceTable[J][Level];
          } else {
            up->CurXp = 0;
          }
          if (Level >= BestLevel) {
            if (((up->CurXp >= up->BestXp)) || ((up->CurXp == (-1)))) {
              up->BestXp = up->CurXp;
              Result = J;
              BestLevel = Level;
            }
          }
        if (J == LastClass_OVL12) break;
        J++;
      }
    }
  }
  return Result;
}

/* ovl12:2122. Level drain: Who loses Count levels (the callers are DrainAttackTargetLevel and
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
     QUIRK ovl12:2122: Total 0 (a character with no class level) divides by zero. */
void DrainLevels(PCharacter Who, u8 Count)
{
  POOL_TRACE("DrainLevels");
  Frame_DrainLevels fr;
  memset(&fr, 0, sizeof fr);
  fr.Who = Who;
  fr.Count = Count;
  u8 ts1[256];
  u8 ts2[256];
  if (fr.Count > 1) {
    rtl_str_assign(fr.Msg, 40, rtl_str_cat(ts2, 2, (const u8 *const[]){ByteToText(ts1, fr.Count), S("\007 levels")}));
  } else {
    rtl_str_assign(fr.Msg, 40, S("\007a level"));
  }
  ShowCharacterMessage(fr.Who, rtl_str_cat(ts1, 2, (const u8 *const[]){S("\013is drained "), fr.Msg}), CombatMessageRow, 1);
  if ((*FPD(TCharacter (*), fr.Who)).Status == StatusAnimated) {
    DropFromFight(fr.Who, StatusGone, S("\017is dead forever"));
    (*FPD(TCharacter (*), fr.Who)).HpMax = 0;
    return;
  }
  {
    u8 limit = fr.Count;
    if (1 <= limit) {
      fr.Step = 1;
      for (;;) {
          if ((*FPD(TCharacter (*), fr.Who)).Status != StatusGone) {
            (*FPD(TCharacter (*), fr.Who)).Pad74[0]++;
            fr.Total = 0;
            {
              if (0 <= LastClass_OVL12) {
                fr.ClassIndex = 0;
                for (;;) {
                    fr.Total += (*FPD(TCharacter (*), fr.Who)).ClassLevels[fr.ClassIndex];
                  if (fr.ClassIndex == LastClass_OVL12) break;
                  fr.ClassIndex++;
                }
              }
            }
            fr.Quotient = ((*FPD(TCharacter (*), fr.Who)).HpMax / fr.Total);
            ShowDebugTrace(S("\014max,cur,lost"), (*FPD(TCharacter (*), fr.Who)).HpMax, (*FPD(TCharacter (*), fr.Who)).HpCurrent, (*FPD(TCharacter (*), fr.Who)).Pad74[1]);
            {
              u8 limit = fr.Quotient;
              if (1 <= limit) {
                fr.Point = 1;
                for (;;) {
                    if ((*FPD(TCharacter (*), fr.Who)).HpMax > 0) {
                      (*FPD(TCharacter (*), fr.Who)).HpMax--;
                    }
                    if ((*FPD(TCharacter (*), fr.Who)).HpB1 > 0) {
                      (*FPD(TCharacter (*), fr.Who)).HpB1--;
                    }
                    if ((*FPD(TCharacter (*), fr.Who)).HpCurrent > 0) {
                      (*FPD(TCharacter (*), fr.Who)).HpCurrent--;
                    }
                    (*FPD(TCharacter (*), fr.Who)).Pad74[1]++;
                  if (fr.Point == limit) break;
                  fr.Point++;
                }
              }
            }
            if ((*FPD(TCharacter (*), fr.Who)).HighestLevel < 2) {
              DropFromFight(fr.Who, StatusGone, S("\017is dead forever"));
              (*FPD(TCharacter (*), fr.Who)).HpMax = 0;
              if ((((*FPD(TCharacter (*), fr.Who)).ClassLevels[DrainLevels_HighestLevelClass(&fr)] > 0)) && ((fr.Count == 2))) {
                (*FPD(TCharacter (*), fr.Who)).ClassLevels[DrainLevels_HighestLevelClass(&fr)] = 0;
              }
            } else {
              (*FPD(TCharacter (*), fr.Who)).ClassLevels[DrainLevels_HighestLevelClass(&fr)]--;
              if ((((*FPD(TCharacter (*), fr.Who)).HpCurrent == 0)) && (((*FPD(TCharacter (*), fr.Who)).Status != StatusDead))) {
                DropFromFight(fr.Who, StatusDead, S("\011is killed"));
              }
              RecalcClassStats(fr.Who);
            }
            (*FPD(TCharacter (*), fr.Who)).HighestLevel = (*FPD(TCharacter (*), fr.Who)).ClassLevels[DrainLevels_HighestLevelClass(&fr)];
            (*FPD(TCharacter (*), fr.Who)).Experience = fr.BestXp;
            RecalcCombatValues(fr.Who);
          }
        if (fr.Step == limit) break;
        fr.Step++;
      }
    }
  }
}

/* ovl12:23A4. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000)
     that drains one level from the character Who attacked last (Who's combat Target, TCombatant +$A): DrainLevels
     takes one level off it, with "is drained a level" shown on it. Runs for affect $55 (id 85, InitAffectHandlers [V]). */
void DrainAttackTargetLevel(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("DrainAttackTargetLevel");
  DrainLevels((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target, 1);
}

/* ovl12:23C2. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000)
     that drains two levels from the character Who attacked last (Who's combat Target, TCombatant +$A): DrainLevels
     takes two levels off it, with "is drained 2 levels" shown on it. Runs for affect $56 (id 86, InitAffectHandlers [V]). */
void DrainAttackTargetTwoLevels(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("DrainAttackTargetTwoLevels");
  DrainLevels((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target, 2);
}

/* ovl12:23EC. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000)
     that gives the rot to the character Who attacked last (Who's combat Target, copied into AttackTarget). Unless that
     character already has the healing block AffectMummyDisease (HasAffect finds it), it gets the block for
     MummyDiseaseDuration rounds, then AffectRot for RotDuration rounds with the Data (1d6 * RotStage) + RotDataLow: the
     rot stage is the high nibble (ProgressRot, ovl12:1399). "is Diseased" is shown on it at row CombatMessageRow. Runs
     for affect $57
     (id 87, InitAffectHandlers [V]). */
void CauseRotOnAttackTarget(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("CauseRotOnAttackTarget");
  farptr FoundAffect = 0;
  AttackTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  if (!HasAffect(AttackTarget, AffectMummyDisease, &FoundAffect)) {
    AddAffect(AttackTarget, AffectMummyDisease, MummyDiseaseDuration, HealingBlockData, RunsHandlerOnRemove);
    AddAffect(AttackTarget, AffectRot, RotDuration, (s16)(((s16)(RollDice(1, 6) * RotStage)) + RotDataLow), RunsHandlerOnRemove);
    ShowCharacterMessage(AttackTarget, S("\013is Diseased"), CombatMessageRow, 1);
  }
}

/* ovl12:2490. an affect handler (the AffectHandlers shape: Who, Affect and Mode; Who and Mode are not
     read, ovl24:0000). It works on Affect's Data (+3). In combat round 0 (CombatRound, the round counter, is 0) with AttackRoll 0
     it keeps only DataLowNibble of Data. Otherwise, when MissedBit is clear, AttackRoll becomes MissRoll (a miss, ovl24:0CD5)
     and MissedBit is set, so the attack misses once. Runs for affect $59 (id 89, InitAffectHandlers [V]). */
void ForceFirstAttackMiss(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ForceFirstAttackMiss");
  if (((CombatRound == 0)) && ((AttackRoll == 0))) {
    (*FPD(TAffect (*), Affect)).Data = ((*FPD(TAffect (*), Affect)).Data & DataLowNibble);
  } else if ((((*FPD(TAffect (*), Affect)).Data & MissedBit)) == 0) {
    AttackRoll = MissRoll;
    (*FPD(TAffect (*), Affect)).Data = ((*FPD(TAffect (*), Affect)).Data | MissedBit);
  }
}

/* ovl12:24D9. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
     For the first saving throw kind (SaveKind 0, SaveKindPoison [I]) it adds a bonus to SaveRoll from Who's Constitution
     (+$14): 1 for 4..6, 2 for 7..10, 3 for 11..13, 4 for 14..17 and 5 for 18..20. Runs for affect $5A (id 90,
     InitAffectHandlers [V]).
     QUIRK ovl12:24D9: a Constitution outside 4..20 sets no bonus, so the local Bonus keeps what the stack held, and that
     value is added to SaveRoll. */
void DwarfHalflingPoisonSaveBonus(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("DwarfHalflingPoisonSaveBonus");
  u8 Bonus = 0;
  if (SaveKind == SaveKindPoison) {
    /* The bonus by Constitution bracket, the same table in ovl12:24D9 and ovl12:268A: 4..6 gives 1, 7..10 gives 2, 11..13 gives
       3, 14..17 gives 4 and 18..20 gives 5 (the dwarf, gnome and halfling bonus of AD&D [I]). */
    switch ((*FPD(TCharacter (*), Who)).Constitution) {
    case 4:
    case 5:
    case 6:
    {
      Bonus = 1;
      break;
    }
    case 7:
    case 8:
    case 9:
    case 10:
    {
      Bonus = 2;
      break;
    }
    case 11:
    case 12:
    case 13:
    {
      Bonus = 3;
      break;
    }
    case 14:
    case 15:
    case 16:
    case 17:
    {
      Bonus = 4;
      break;
    }
    case 18:
    case 19:
    case 20:
    {
      Bonus = 5;
      break;
    }
    }
    SaveRoll = SaveRoll + Bonus;
  }
}

/* ovl12:2556. an affect handler on the damage hook (the AffectHandlers shape: Who, Affect and Mode; Affect
     and Mode are not read, ovl24:0000; Who is read for its message). When CastingSpell is SpellMagicMissile the pending hook is
     cancelled (CancelPendingHook(0): the damage is dropped) and "is unaffected" is shown on Who at row CombatMessageRow.
     Otherwise,
     when the damage is electricity (KindElectricity in DamageKind), the hook is cancelled without the message. Runs for affect
     $5B (id 91, InitAffectHandlers [V]). */
void ImmuneToMagicMissileAndElectricity(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ImmuneToMagicMissileAndElectricity");
  if (CastingSpell == SpellMagicMissile) {
    CancelPendingHook(0);
    ShowCharacterMessage(Who, S("\015is unaffected"), CombatMessageRow, 1);
  } else if (((DamageKind & KindElectricity)) != 0) {
    CancelPendingHook(0);
  }
}

/* ovl12:25A2. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000).
     When the damage being dealt is fire (DamageKind bit KindFire, DS:6819), it halves DamageAmount (DS:6818): HalveFireDamage
     (ovl12:06E4) without its SaveRoll bonus. Runs for affect $5D (id 93, InitAffectHandlers [V]). */
void HalveFireDamageNoSave(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("HalveFireDamageNoSave");
  if (((DamageKind & KindFire)) != 0) {
    DamageAmount = (s16)((u16)DamageAmount >> 1);
  }
}

/* ovl12:25BC. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000).
     It takes the first slot item of SelectedCharacter (FirstSlotItem, ovl12:101D). When there is one and byte 7 of its
     ItemTable row (ItemTable[ItemType].Pad7[7], DS:5589; the row is indexed by the item type, the meaning of byte 7 is
     not known [?]) has ItemRowFlags bits set, DamageAmount is halved. runs for affect $5E (id 94,
     InitAffectHandlers
     [V]). Game meaning: carried only by the JUJU ZOMBIE (MON4SPC block 29) [V]: damage is halved when the
     attacker's weapon has ItemTable byte 7 flag $01 (piercing) or $80 (bludgeoning) [I]. */
void HalveDamageForFirstSlotItem(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("HalveDamageForFirstSlotItem");
  PItem Item = 0;
  Item = FirstSlotItem(SelectedCharacter);
  if (Item != 0) {
    if (((ItemTable[(*FPD(TMenuLine (*), Item)).ItemType].Pad7[0] & ItemRowFlags)) != 0) {
      DamageAmount = (s16)((u16)DamageAmount >> 1);
    }
  }
}

/* ovl12:2610. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read, ovl24:0000). It clears the
     affect's Flag, so the handler does not run again when the affect is removed. When Who still takes part in the fight
     (Flag10D set), Who falls dead: DropFromFight takes Who out with StatusDead and the text 'Falls dead'. Runs for affect $5F
     (id 95, InitAffectHandlers [V]). */
void FallDeadIfInFight(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("FallDeadIfInFight");
  (*FPD(TAffect (*), Affect)).Flag = 0;
  if ((*FPD(TCharacter (*), Who)).Flag10D != 0) {
    DropFromFight(Who, StatusDead, S("\012Falls dead"));
  }
}

/* ovl12:264B. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It cancels the
     damage (DamageAmount := 0) unless SelectedCharacter's first slot item (FirstSlotItem, ovl12:101D) is a magic item
     (Plus, +$32, not 0) or has NameNum[3] (+$31) SilverNameNum; with no first slot item the damage is cancelled.
     Runs for affect $60 (id 96, InitAffectHandlers [V]). */
void CancelDamageUnlessMagicSlotItem(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("CancelDamageUnlessMagicSlotItem");
  PItem Item = 0;
  Item = FirstSlotItem(SelectedCharacter);
  if (((Item == 0)) || (((((*FPD(TMenuLine (*), Item)).Plus == 0)) && (((*FPD(TMenuLine (*), Item)).NameNum[2] != SilverNameNum_OVL12))))) {
    DamageAmount = 0;
  }
}

/* ovl12:268A. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read, ovl24:0000).
     For the saving throw kinds 2 and 4 (SaveKind, DS:682A; kind 4 is SaveKindSpell [I]) it adds to SaveRoll the Constitution
     bonus of DwarfHalflingPoisonSaveBonus (ovl12:24D9): 1 for 4..6, 2 for 7..10, 3 for 11..13, 4 for 14..17 and 5 for 18..20.
     Runs for affect $61 (id 97, InitAffectHandlers [V]).
     QUIRK ovl12:268A: a Constitution outside 4..20 sets no bonus, so the local Bonus keeps what the stack held, and that
     value is added to SaveRoll. */
void DwarfGnomeHalflingWandSpellSaveBonus(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("DwarfGnomeHalflingWandSpellSaveBonus");
  u8 Bonus = 0;
  if (((SaveKind == SaveKindSpell)) || ((SaveKind == SaveKindWand))) {
    /* The bonus by Constitution bracket, the same table in ovl12:24D9 and ovl12:268A: 4..6 gives 1, 7..10 gives 2, 11..13 gives
       3, 14..17 gives 4 and 18..20 gives 5 (the dwarf, gnome and halfling bonus of AD&D [I]). */
    switch ((*FPD(TCharacter (*), Who)).Constitution) {
    case 4:
    case 5:
    case 6:
    {
      Bonus = 1;
      break;
    }
    case 7:
    case 8:
    case 9:
    case 10:
    {
      Bonus = 2;
      break;
    }
    case 11:
    case 12:
    case 13:
    {
      Bonus = 3;
      break;
    }
    case 14:
    case 15:
    case 16:
    case 17:
    {
      Bonus = 4;
      break;
    }
    case 18:
    case 19:
    case 20:
    {
      Bonus = 5;
      break;
    }
    }
    SaveRoll = SaveRoll + Bonus;
  }
}

/* ovl12:2700. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Affect and Mode are not read). Who gets
     RegainedHitPoints back on HpCurrent (the current hit points [I], TCharacter +$11B), but never more than HpMax (+$32).
     Runs for affect $62 (id 98, InitAffectHandlers [V]). */
void RegainHitPoints(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("RegainHitPoints");
  (*FPD(TCharacter (*), Who)).HpCurrent += RegainedHitPoints;
  if ((*FPD(TCharacter (*), Who)).HpCurrent > (*FPD(TCharacter (*), Who)).HpMax) {
    (*FPD(TCharacter (*), Who)).HpCurrent = (*FPD(TCharacter (*), Who)).HpMax;
  }
}

/* ovl12:2730. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read). A dying character
     (StatusDying) gets DyingRevivalPoints less the rounds it has bled (DyingRounds, TCombatant +$E), so one that has bled
     six rounds or more stays dead; an unconscious one (StatusUnconscious) gets DyingRevivalPoints. When ReviveCombatant
     (ovl24:1869) puts Who back on the map, Who gets AffectFallsDead for 1d4 plus one rounds, and the affect Affect has its
     Flag cleared (NoRemoveHandler) and is removed, so its handler does not run. Runs for affect $63 (id 99,
     InitAffectHandlers [V]). */
void ReviveDyingCharacter(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ReviveDyingCharacter");
  u8 HitPoints = 0;
  HitPoints = 0;
  if ((*FPD(TCharacter (*), Who)).Status == StatusDying) {
    if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).DyingRounds < DyingRevivalPoints) {
      HitPoints = DyingRevivalPoints - (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).DyingRounds;
    }
  }
  if ((*FPD(TCharacter (*), Who)).Status == StatusUnconscious) {
    HitPoints = DyingRevivalPoints;
  }
  if (HitPoints > 0) {
    if (ReviveCombatant(Who, HitPoints)) {
      AddAffect(Who, AffectFallsDead, (s16)(RollDice(1, AffectFallsDeadDieSides) + 1), DataFF, RunsHandlerOnRemove);
      (*FPD(TAffect (*), Affect)).Flag = NoRemoveHandler;
      RemoveAffect(Who, AffectReviveDying, Affect);
    }
  }
}

/* ovl12:27D9. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read). Unless the damage being dealt
     (DamageKind, DS:6819) has the fire bit (KindFire) or the acid bit (KindAcid), Who gets AffectRetryRevival for 3d6 rounds
     with the Data $FF, and its handler runs when it is removed. Runs for affect $64 (id 100, InitAffectHandlers [V]). */
void GiveAffectUnlessFireOrAcid(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("GiveAffectUnlessFireOrAcid");
  if (((DamageKind & KindFire)) == 0) {
    if (((DamageKind & KindAcid)) == 0) {
      AddAffect(Who, AffectRetryRevival, RollDice(AffectRetryRevivalDice, AffectRetryRevivalSides), DataFF, RunsHandlerOnRemove);
    }
  }
}

/* ovl12:2814. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read). Unless HasAffect finds
     AffectRegainHitPoints or AffectRegenerating on Who, Who gets AffectRegenerating (Regenerating) for RegeneratingDuration
     rounds
     with the Data $FF, and its handler runs when it is removed. Runs for affect $65 (id 101, InitAffectHandlers [V]). */
void GiveRegeneratingUnlessAffected(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("GiveRegeneratingUnlessAffected");
  farptr FoundAffect = 0;
  if (!HasAffect(Who, AffectRegainHitPoints, &FoundAffect)) {
    if (!HasAffect(Who, AffectRegenerating, &FoundAffect)) {
      AddAffect(Who, AffectRegenerating, RegeneratingDuration, DataFF, RunsHandlerOnRemove);
    }
  }
}

/* ovl12:2866. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read). ReviveCombatant
     (ovl24:1869) tries to put Who back on the map with its full HpMax (+$32). When that fails, Who gets AffectRetryRevival
     for AffectRetryRevivalRetryDuration round with the Data of Affect, when TryAddAffect allows it; the result is stored
     and never read. Runs for affect $66 (id 102, InitAffectHandlers [V]). */
void RetryRevivalAtFullHitPoints(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("RetryRevivalAtFullHitPoints");
  u8 Added = 0;
  if (!ReviveCombatant(Who, (*FPD(TCharacter (*), Who)).HpMax)) {
    Added = TryAddAffect(Who, AffectRetryRevival, (*FPD(TAffect (*), Affect)).Data, AffectRetryRevivalRetryDuration);
  }
}

/* ovl12:28BF. Affect handler (the AffectHandlers shape: Who, Affect and Mode; Mode is not read). Affect's Flag is
     cleared (NoRemoveHandler) so its handler does not run again on removal. Then the cursor is shown on Who
     (ShowCursorOn, ovl31:1298; margin 3, cursor 0 [?]) and Who drops out of the fight with StatusFled and the text
     'Turns gaseous and escapes' (DropCombatant, ovl24:0F06). Runs for affect $67 (id 103, InitAffectHandlers [V]). */
void TurnGaseousAndEscape(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("TurnGaseousAndEscape");
  (*FPD(TAffect (*), Affect)).Flag = NoRemoveHandler;
  ShowCursorOn(Who, GaseousCursorMargin, GaseousShowCursor);
  DropCombatant(Who, StatusFled, S("\031Turns gaseous and escapes"));
}

/* ovl12:2901. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It runs
     AvoidDistantAttack on Who with DistantAvoidChance (60): a 1d100 roll of 60 or less avoids the attack in progress.
     Runs for affect $68 (id 104, InitAffectHandlers [V]). */
void AvoidDistantAttackByChance(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("AvoidDistantAttackByChance");
  AvoidDistantAttack(Who, DistantAvoidChance);
}

/* ovl12:2915. Helper of the two hook cancels ovl12:2976 and ovl12:2984, which pass Chance. Only when a hook is offered
     (HookAffectId is not 0) or the damage is magical (DamageKind bit KindMagic), a 1d100 roll at or below a threshold
     cancels the pending hook (CancelPendingHook(0): the damage is dropped). The threshold is Chance less 5 for each
     point that Level falls short of 11. Level is SpellCasterLevel of CastingSpell (RES12 00BA:26C2 [V]): the cleric level for
     spell class 0, the magic-user level for class 1, 12 for class 2, or 6 while ItemAffectUse is set. What the threshold
     measures is not known [?].
     QUIRK ovl12:2915: Threshold is a Byte, but Chance - 5 * (11 - Level) is worked out in 16 bits and the result is
     stored in the byte, so a negative value wraps to 256 plus the value (-5 gives 251). With Chance 15 and Level below 8,
     or Chance 50 and Level 0, the wrapped threshold is 251 or more, so the roll almost always cancels the hook. With
     Level above 11 (12 for class 2) the threshold rises above Chance. Never fixed. */
void RollMagicResistance(u8 Chance)
{
  POOL_TRACE("RollMagicResistance");
  u8 Level = 0;
  u8 Threshold = 0;
  Level = SpellCasterLevel(CastingSpell);
  Threshold = Chance - (5 * ((s16)(11 - Level)));
  if (((HookAffectId == 0)) && ((((DamageKind & KindMagic)) == 0))) {
    return;
  }
  if (RollDice(1, 100) <= Threshold) {
    CancelPendingHook(0);
  }
}

/* ovl12:2976. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It calls
     RollMagicResistance with HookChanceHalf (50): the pending hook may be cancelled by a roll. Runs for affect $69 (id 105,
     InitAffectHandlers [V]). */
void CancelHookByHalfChance(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("CancelHookByHalfChance");
  RollMagicResistance(HookChanceHalf);
}

/* ovl12:2984. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It calls
     RollMagicResistance with HookChanceLow (15): the pending hook is cancelled by a roll less often than at 50.
     Runs for affect $6A (id 106, InitAffectHandlers [V]). */
void CancelHookByLowChance(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("CancelHookByLowChance");
  RollMagicResistance(HookChanceLow);
}

/* ovl12:2992. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). A 1d100
     roll at or below ElfCharmSleepResistance (90) cancels the pending hook of affect AffectEndsTurn, then the one of the charm
     (AffectCharm), each through CancelPendingHook. Runs for affect $6B (id 107, InitAffectHandlers [V]). */
void ElfResistsCharmAndSleep(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ElfResistsCharmAndSleep");
  if (RollDice(1, 100) <= ElfCharmSleepResistance) {
    CancelPendingHook(AffectEndsTurn);
    CancelPendingHook(AffectCharm);
  }
}

/* ovl12:29B6. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It cancels
     the pending hook of the charm (AffectCharm) and then the one of affect AffectEndsTurn, without a roll. Runs for affect $6C
     (id 108, InitAffectHandlers [V]). */
void ImmuneToCharmAndSleep(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ImmuneToCharmAndSleep");
  CancelPendingHook(AffectCharm);
  CancelPendingHook(AffectEndsTurn);
}

/* ovl12:29CB. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). It cancels
     the pending hook of the paralysis affect (AffectParalysis, $34) with CancelPendingHook, and nothing else. 
     runs for affect $6D (id 109, InitAffectHandlers [V]). Game meaning: immunity to Hold, carried by SPECTRE, WIGHT,
     WRAITH and FERRAN MARTINEZ (MON4SPC) [V]. */
void CancelParalysisHook(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("CancelParalysisHook");
  CancelPendingHook(AffectParalysis);
}

/* ovl12:29D9. Damage hook (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). While the
     damage being dealt is cold (DamageKind bit KindCold, DS:6819), CancelPendingHook(0) drops it: DamageAmount and the
     hook offered are cleared. runs for affect $6E (id 110, InitAffectHandlers [V]). Game meaning: cold immunity of the
     undead (SPECTRE, WIGHT, WRAITH, SKELETON, GIANT SKELETON, ZOMBIE, JUJU ZOMBIE, MUMMY, FERRAN MARTINEZ) [V monster data]. */
void CancelColdDamage(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("CancelColdDamage");
  if (((DamageKind & KindCold)) != 0) {
    CancelPendingHook(0);
  }
}

/* ovl12:29F0. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). It cancels
     the pending hooks of the poison affect (AffectPoisoned, $37) and of the paralysis affect (AffectParalysis, $34). Then,
     when the saving throw in progress is the poison save (SaveKind 0, SaveKindPoison), SaveRoll becomes AlwaysSaves, so that
     save succeeds. runs for affect $6F (id 111, InitAffectHandlers [V]). Game meaning: poison and hold immunity of
     SPECTRE, WIGHT, WRAITH and FERRAN MARTINEZ (affect $6F, AffectPoisonImmunity) [V monster data, I meaning]. */
void CancelPoisonAndParalysisHooks(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("CancelPoisonAndParalysisHooks");
  CancelPendingHook(AffectPoisoned);
  CancelPendingHook(AffectParalysis);
  if (SaveKind == SaveKindPoison) {
    SaveRoll = AlwaysSaves;
  }
}

/* ovl12:2A11. Damage hook (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). While the
     damage being dealt is fire (DamageKind bit KindFire, DS:6819), CancelPendingHook(0) drops it: DamageAmount and the
     hook offered are cleared. runs for affect $70 (id 112, InitAffectHandlers [V]). Game meaning: fire immunity, carried
     by the FIRE GIANT (MON5SPC block 56) [V]. */
void CancelFireDamage(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("CancelFireDamage");
  if (((DamageKind & KindFire)) != 0) {
    CancelPendingHook(0);
  }
}

/* ovl12:2A28. Damage hook (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). While the
     damage is fire (DamageKind bit KindFire, DS:6819), each of the LastDiceCount dice of the last roll takes one point off
     DamageAmount, and it never goes below LastDiceCount. The twin of ReduceFireDamageByRoll (ovl12:1490), which takes
     FireReductionPerDie per die and also adds the save bonus and cancels a non-magic hit. runs for affect $71
     (id 113, InitAffectHandlers [V]). Game meaning: fire resistance of the EFREETI (MON4SPC 70, MON8SPC 124) [V]. */
void ReduceFireDamageOnePerDie(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ReduceFireDamageOnePerDie");
  u8 I = 0;
  if (((DamageKind & KindFire)) != 0) {
    {
      u8 limit = LastDiceCount;
      if (1 <= limit) {
        I = 1;
        for (;;) {
            DamageAmount--;
            if (DamageAmount < LastDiceCount) {
              DamageAmount = LastDiceCount;
            }
          if (I == limit) break;
          I++;
        }
      }
    }
  }
}

/* ovl12:2A6D. Damage hook (the AffectHandlers shape: Who, Affect and Mode; none of them is read, ovl24:0000). While the
     damage is electricity (DamageKind bit KindElectricity, DS:6819), it halves DamageAmount (DS:6818): the electricity
     twin of HalveColdDamage (ovl12:03E1), without its save bonus. runs for affect $72 (id 114,
     InitAffectHandlers [V]). Game meaning: carried only by the VAMPIRE [V]. */
void HalveElectricityDamage(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("HalveElectricityDamage");
  if (((DamageKind & KindElectricity)) != 0) {
    DamageAmount = (s16)((u16)DamageAmount >> 1);
  }
}

/* ovl12:2A87. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000).
     The first slot item of SelectedCharacter (FirstSlotItem, ovl12:101D) is looked at: when there is one and its
     ItemTable byte 7 (ItemTable[ItemType].Pad7[7], DS:5589) is 0 or odd, DamageAmount is halved. runs for
     affect $73 (id 115, InitAffectHandlers [V]). Game meaning: SKELETON and GIANT SKELETON [V]: damage is halved unless
     the weapon is bludgeoning (ItemTable byte 7 is 0 or odd), the AD&D skeleton rule [I]. */
void HalveDamageByFirstSlotItemRow(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("HalveDamageByFirstSlotItemRow");
  PItem Item = 0;
  Item = FirstSlotItem(SelectedCharacter);
  if (Item != 0) {
    if (((ItemTable[(*FPD(TMenuLine (*), Item)).ItemType].Pad7[0] == 0)) || ((((ItemTable[(*FPD(TMenuLine (*), Item)).ItemType].Pad7[0] & 1)) != 0))) {
      DamageAmount = (s16)((u16)DamageAmount >> 1);
    }
  }
}

/* ovl12:2AE6. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000).
     When the first slot item of SelectedCharacter (FirstSlotItem, ovl12:101D) has Plus (+$32, a signed byte) above 0,
     DamageAmount is halved. runs for affect $74 (id 116, InitAffectHandlers [V]). Game meaning: the MUMMY only [V]: half
     damage from a weapon with Plus above 0 [I]. */
void HalveDamageForEnchantedSlotItem(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("HalveDamageForEnchantedSlotItem");
  PItem Item = 0;
  Item = FirstSlotItem(SelectedCharacter);
  if (Item != 0) {
    if ((*FPD(TMenuLine (*), Item)).Plus > 0) {
      DamageAmount = (s16)((u16)DamageAmount >> 1);
    }
  }
}

/* ovl12:2B20: retf 10: 10 bytes of parameters; 4 bytes of locals */
/* ovl12:2B20. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000).
     When the first slot item of SelectedCharacter (SlotItems[0], TCharacter +$CC) has ItemType $55, DamageAmount
     becomes 1d6 plus one (RollDiceCounted, ovl24:0E2E). runs for affect $75 (id 117, InitAffectHandlers [V]). Game
     meaning: every undead but FERRAN MARTINEZ (SPECTRE, WIGHT, WRAITH, SKELETONS, ZOMBIES, MUMMY, VAMPIRE) [V]; item
     type $55 is Vial Of Holy Water [V item files]: damage 1d6 + 1, holy water against undead [I]. */
void SetDamageFromHolyWater(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("SetDamageFromHolyWater");
  PItem Item = 0;
  Item = (*FPD(TCharacter (*), SelectedCharacter)).SlotItems[0];
  if (Item != 0) {
    if ((*FPD(TMenuLine (*), Item)).ItemType == ItemHolyWater) {
      DamageAmount = RollDiceCounted(1, HolyWaterDieSides) + 1;
    }
  }
}

/* ovl12:2B63. Damage hook (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). While the damage is
     cold (DamageKind bit KindCold, DS:6819), DamageAmount is halved: HalveColdDamage (ovl12:03E1) without its SaveRoll
     bonus, the cold twin of HalveFireDamageNoSave (ovl12:25A2). runs for affect $76 (id 118,
     InitAffectHandlers [V]). Game meaning: carried only by the VAMPIRE [V]. */
void HalveColdDamageNoSave(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("HalveColdDamageNoSave");
  if (((DamageKind & KindCold)) != 0) {
    DamageAmount = (s16)((u16)DamageAmount >> 1);
  }
}

/* ovl12:2B7D. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000).
     Unless the first slot item of SelectedCharacter (FirstSlotItem, ovl12:101D) exists and has Plus (+$32) not 0, the
     damage is cancelled (DamageAmount := 0) when the character's Race (+$2E, a signed byte) is above 0 or its
     HighestLevel (+$73) is below 4. runs for affect $77 (id 119, InitAffectHandlers [V]). Game meaning: SPECTRE, FERRAN
     MARTINEZ, VAMPIRE, JUJU ZOMBIE and MUMMY [V]: only a weapon with Plus, or an attacker that is a monster of level 4
     or more, hurts [I]. */
void CancelDamageUnlessEnchantedSlotItem(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("CancelDamageUnlessEnchantedSlotItem");
  PItem Item = 0;
  Item = FirstSlotItem(SelectedCharacter);
  if (((Item == 0)) || (((*FPD(TMenuLine (*), Item)).Plus == 0))) {
    if ((((*FPD(TCharacter (*), SelectedCharacter)).Race > RaceMonster)) || (((*FPD(TCharacter (*), SelectedCharacter)).HighestLevel < StrongMonsterLevel))) {
      DamageAmount = 0;
    }
  }
}

/* ovl12:2BC8. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). When the first slot
     item of SelectedCharacter (SlotItems[0], TCharacter +$CC) has ItemType $57 or $58 (names not known [?]), Who may avoid
     the distant attack: AvoidDistantAttack (ovl12:0FAC) with SlotItemAvoidChance. runs for affect $78 (id 120,
     InitAffectHandlers [V]). Game meaning: HILL GIANT and FIRE GIANT [V]: item types $57 and $58 are two-handed
     bludgeoning rows (the type $57 item carries Affects[3] $87, Must have Giant Strength), so this is a giant catching a
     hurled boulder, 50 percent [I]. */
void AvoidDistantAttackForBoulder(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("AvoidDistantAttackForBoulder");
  PItem Item = 0;
  Item = (*FPD(TCharacter (*), SelectedCharacter)).SlotItems[0];
  if (Item != 0) {
    if ((((*FPD(TMenuLine (*), Item)).ItemType == ItemBoulderA)) || (((*FPD(TMenuLine (*), Item)).ItemType == ItemBoulderB))) {
      AvoidDistantAttack(Who, SlotItemAvoidChance);
    }
  }
}

/* ovl12:2C1C. Affect handler that spits acid at the character Who attacked last (the AffectHandlers shape: Who, Affect
     and Mode; Mode is not read, ovl24:0000). AttackTarget becomes Who's combat Target (Who^.Combat^.Target). On a 1d100 roll at
     or below SpitChance, when DistanceToTarget (the distance to AttackTarget [I]) is below SpitMaxDistance: Who's turn ends
     (EndCombatTurn, its result is not read), "Spits Acid" is shown on Who at row CombatMessageRow, the spit is drawn from Who to
     AttackTarget (DrawCombatIcon with SpitAnimation, WalkCombatLine with CombatantX and CombatantY), and AttackTarget takes 8d4
     damage (DealDamage, half when its save of kind SaveKindBreath succeeds). Then AffectSpitsAcid and AffectSplashesAcid are
     removed
     from Who (RemoveAffect; Affect is the affect handled).
     QUIRK ovl12:2C1C: DamageKind is not set here (AcidAttackTargetFor1d4, ovl12:1A4C, sets KindAcid first), so the spit's
     damage is dealt with whatever kind the damage before left in DamageKind (DealDamage, ovl24:1344). Never fixed. Runs for
     affect $79 (id 121, InitAffectHandlers [V]). */
void SpitAcidAtTarget(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("SpitAcidAtTarget");
  u8 Turn = 0;
  AttackTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  if (RollDice(1, 100) <= SpitChance) {
    if (DistanceToTarget(Who, AttackTarget) < SpitMaxDistance) {
      Turn = EndCombatTurn(Who);
      ShowCharacterMessage(Who, S("\012Spits Acid"), CombatMessageRow, 1);
      DrawCombatIcon(SpitAnimation);
      WalkCombatLine(CombatantX(Who), CombatantY(Who), CombatantX(AttackTarget), CombatantY(AttackTarget), SpitLineKind, SpitLineFlag);
      DealDamage(AttackTarget, RollDiceCounted(SpitDiceCount, SpitDieSides), HalfOnSave, SavingThrow(AttackTarget, SaveKindBreath, 0));
      RemoveAffect(Who, AffectSpitsAcid, Affect);
      RemoveAffect(Who, AffectSplashesAcid, 0);
    }
  }
}

/* ovl12:2D38. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). When the
     first slot item of SelectedCharacter (SlotItems[0], TCharacter +$CC) has ItemType $56 (name not known [?]), DamageAmount
     becomes 3d8 (RollDiceCounted, ovl24:0E2E). Then, when DamageKind has the fire or the magic bit (KindFire or KindMagic),
     the dice count of the last roll (LastDiceCount) is added to DamageAmount. runs for affect $7A (id 122,
     InitAffectHandlers [V]). The routine starts at ovl12:2D38 (its push bp); the
     map's entry at ovl12:2D39 is inside it. Game meaning: the MUMMY only [V]; item type $56 is Flask OF Oil [V]: 3d8
     plus the dice count for fire or magic damage, burning oil [I]. */
void SetDamageFromOilFlask(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("SetDamageFromOilFlask");
  PItem Item = 0;
  Item = (*FPD(TCharacter (*), SelectedCharacter)).SlotItems[0];
  if (Item != 0) {
    if ((*FPD(TMenuLine (*), Item)).ItemType == ItemOilFlask) {
      DamageAmount = RollDiceCounted(OilFlaskDiceCount, OilFlaskDieSides);
    }
  }
  if (((DamageKind & ((KindFire | KindMagic)))) != 0) {
    DamageAmount += LastDiceCount;
  }
}

/* ovl12:2D88. Affect handler for damage (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). The
     first slot item of SelectedCharacter (FirstSlotItem, ovl12:101D) decides the damage. With no item, DamageAmount is
     cancelled (0). With an item whose Plus (+$32) is 0, DamageAmount is halved when its NameNum[3] (+$31) is SilverNameNum
     and cancelled otherwise. An item with Plus not 0 leaves the damage alone. runs for affect $7B (id 123,
     InitAffectHandlers [V]). Game meaning: the WRAITH only [V]; NameNum[3] $B1 is Silver on every silver item [V]: a
     silver weapon with Plus 0 does half damage, any other plain weapon none [I]. */
void HalveOrCancelDamageForUnenchantedSlotItem(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("HalveOrCancelDamageForUnenchantedSlotItem");
  PItem Item = 0;
  Item = FirstSlotItem(SelectedCharacter);
  if (Item != 0) {
    if ((((*FPD(TMenuLine (*), Item)).Plus == 0)) && (((*FPD(TMenuLine (*), Item)).NameNum[2] == SilverNameNum_OVL12))) {
      DamageAmount = (s16)((u16)DamageAmount >> 1);
    } else if ((*FPD(TMenuLine (*), Item)).Plus == 0) {
      DamageAmount = 0;
    }
  } else {
    DamageAmount = 0;
  }
}

/* ovl12:2DE4. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). A 1d100 roll at or
     below HalfElfCharmSleepResistance (30) cancels the pending hook of the charm (AffectCharm) and then the one of affect
     AffectEndsTurn, each through CancelPendingHook (ovl12:0000). Runs for affect $7C (id 124, InitAffectHandlers [V]). */
void HalfElfResistsCharmAndSleep(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("HalfElfResistsCharmAndSleep");
  if (RollDice(1, 100) <= HalfElfCharmSleepResistance) {
    CancelPendingHook(AffectCharm);
    CancelPendingHook(AffectEndsTurn);
  }
}

/* ovl12:2E08. Affect handler (the AffectHandlers shape: Who, Affect and Mode; none is read, ovl24:0000). It cancels the
     hooks of four affects with CancelPendingHook (ovl12:0000): the charm (AffectCharm), affect AffectEndsTurn, the
     paralysis (AffectParalysis) and the poison (AffectPoisoned). Then, when the saving throw in progress is the poison
     save (SaveKind 0, SaveKindPoison), SaveRoll becomes AlwaysSaves, so that save succeeds. It is
     CancelPoisonAndParalysisHooks (ovl12:29F0) with the charm and affect $35 cancelled first. Runs for affect $7D (id 125,
     InitAffectHandlers [V]). */
void ImmuneToCharmSleepHoldAndPoison(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ImmuneToCharmSleepHoldAndPoison");
  CancelPendingHook(AffectCharm);
  CancelPendingHook(AffectEndsTurn);
  CancelPendingHook(AffectParalysis);
  CancelPendingHook(AffectPoisoned);
  if (SaveKind == SaveKindPoison) {
    SaveRoll = AlwaysSaves;
  }
}

/* ovl12:2E37. Affect handler (the AffectHandlers shape: Who, Affect and Mode; only Who is read). AttackTarget becomes
     Who's combat Target (Combat^.Target, as BoostAttackAgainstUndead at ovl12:013B does). The carried items of
     AttackTarget (Items, +$C8) are walked while HookVetoFlag is 0. Every readied item (Readied, +$34) that has
     MirrorNameNum ($76, the item that turns a gaze back, GazeStonesTarget at ovl12:1CAD) in one of its names
     (NameNum[1..3], +$2F..+$31), or HolySymbolNameNum in one name with WoodenNameNum in the third, sets HookVetoFlag to 1.
     HookVetoFlag is read by AttackTargetAllowed (OVL13.PAS lines 647..671), which refuses a vetoed target. The VAMPIRE carries
     affect $7E (MON4SPC blocks 23 and 105) [V]. Runs for affect $7E (id 126, InitAffectHandlers [V]). */
void VetoTargetWithMirrorOrWoodenHolySymbol(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("VetoTargetWithMirrorOrWoodenHolySymbol");
  PItem Item = 0;
  u8 NameIndex = 0;
  AttackTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  Item = (*FPD(TCharacter (*), AttackTarget)).Items;
  while (((Item != 0)) && ((HookVetoFlag == 0))) {
    if ((*FPD(TMenuLine (*), Item)).Readied) {
      {
        if (1 <= 3) {
          NameIndex = 1;
          for (;;) {
              if ((((((*FPD(TMenuLine (*), Item)).NameNum[NameIndex - 1] == HolySymbolNameNum)) && (((*FPD(TMenuLine (*), Item)).NameNum[2] == WoodenNameNum)))) || (((*FPD(TMenuLine (*), Item)).NameNum[NameIndex - 1] == MirrorNameNum))) {
                HookVetoFlag = 1;
              }
            if (NameIndex == 3) break;
            NameIndex++;
          }
        }
      }
    }
    Item = (*FPD(TMenuLine (*), Item)).Next;
  }
}

/* ovl12:2EDA. Affect handler of a carried item (the AffectHandlers shape, but the Affect parameter is the item: the
     routine reads it as a PItem, Item^.Affects[2] at +$3D of TMenuLine). Any Mode other than 0 removes the affect the
     item names in Affects[2] from Who (RemoveAffect with nil). Mode 0 gives Who that affect with duration 0, Data
     ItemAffectData and no handler on removal (NoRemoveHandler), then CallAffectHandler runs the affect's handler on Who at
     once (Affect nil, Mode 0). Affects[3] $81 is the Ring of Fire Resistance (Affects[2] $3D), $85 the Cloak of
     Displacement (Affects[2] $59) and $88 the Two-Handed Sword +1 +3 vs. Undead (Affects[2] $03) [V item files]; ids
     $80, $82, $86, $8A and $8B are on no pinned item. Runs for affects $80, $81, $82, $85, $86, $88,
     $8A and $8B (ids 128, 129, 130, 133, 134, 136, 138, 139, InitAffectHandlers [V]). */
void ApplyItemSecondAffect(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("ApplyItemSecondAffect");
  PItem Item = 0;
  Item = Affect;
  if (Mode != 0) {
    RemoveAffect(Who, (*FPD(TMenuLine (*), Item)).Affects[1], 0);
  } else {
    AddAffect(Who, (*FPD(TMenuLine (*), Item)).Affects[1], PermanentDuration, ItemAffectData, NoRemoveHandler);
    CallAffectHandler((*FPD(TMenuLine (*), Item)).Affects[1], Who, 0, 0);
  }
}

/* ovl12:2F57. Affect handler of the exceptional strength (the AffectHandlers shape: Who, Affect and Mode; Affect is not
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
     (QUIRK ovl12:2FFF), and stops once one was removed. Runs for affect $83 (id 131, InitAffectHandlers [V]). */
void GiveExceptionalStrength(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("GiveExceptionalStrength");
  u8 Code = 0;
  u8 Strength = 0;
  u8 Percent = 0;
  u8 IsExceptional = 0;
  u8 Done = 0;
  PAffect Scan = 0;
  if (Mode != 0) {
    Done = 0;
    Scan = (*FPD(TCharacter (*), Who)).Affects;
    if ((((*FPD(TCharacter (*), Who)).Strength == ExceptionalStrength)) && (((*FPD(TCharacter (*), Who)).StrengthPercent == ExceptionalPercent))) {
      IsExceptional = 1;
    } else {
      IsExceptional = 0;
    }
    while (((Scan != 0)) && !Done) {
      if ((*FPD(TAffect (*), Scan)).Id == AffectStrength) {
        DecodeStrength(Scan, &Strength, &Percent);
        if (((IsExceptional && (((*FPD(TAffect (*), Scan)).Id < StrengthKept)))) || (((((Strength == ExceptionalStrength)) && ((Percent == ExceptionalPercent))) && !IsExceptional))) {
          RemoveAffect(Who, AffectStrength, Scan);
          Done = 1;
        }
      }
      Scan = (*FPD(TAffect (*), Scan)).Next;
    }
  } else {
    if (RaiseStrength(Who, ExceptionalStrength, ExceptionalPercent, &Code)) {
      if (ViewMode == ViewModeCombat) {
        ViewMode = ViewModeCamp;
        ShowCharacterMessage(Who, S("\013is stronger"), CombatMessageRow, 1);
        ViewMode = ViewModeCombat;
      } else {
        ShowCharacterMessage(Who, S("\013is stronger"), CombatMessageRow, 1);
      }
    }
    RedrawItemWindow = 1;
    AddAffect(Who, AffectStrength, PermanentDuration, Code, RunsHandlerOnRemove);
  }
}

/* ovl12:30A5. Affect handler of an alignment-bound item (table entry 132, affect $84, stub entry 113), with the
     AffectHandlers shape (Who, Affect and Mode, ovl24:0000), but the Affect parameter is the item, as in
     ApplyItemSecondAffect: ReadyItem (ovl19) calls CallAffectHandler(Item^.Affects[3], Character, PAffect(Item), Mode)
     when an item
     with Affects[3] above $7F is readied (Mode 0) or unreadied. Any other Mode than 0 does nothing. When the low nibble of the
     item's Affects[2] is not Who's Alignment (ScoreItem tests the same nibble, ovl09:128D), the item is unreadied (Readied
     cleared) and the high nibble of Affects[2] is dealt to Who as magic damage without a save (DealDamage), DrawCombatScreen
     shows it in combat view and RedrawItemWindow becomes 1. The items with Affects[3] $84 are Long Swords with Affects[2] $52 and
     $F0 [V item files]: a weapon bound to an alignment, which hurts a wielder of another one [I]. Runs for affect $84 (id 132,
     InitAffectHandlers [V]). */
void AlignmentBoundWeaponHurtsOthers(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("AlignmentBoundWeaponHurtsOthers");
  PItem Item = 0;
  u8 Damage = 0;
  Item = Affect;
  if (Mode != 0) {
    return;
  }
  if ((((*FPD(TMenuLine (*), Item)).Affects[1] & LowNibble)) != (*FPD(TCharacter (*), Who)).Alignment) {
    (*FPD(TMenuLine (*), Item)).Readied = 0;
    Damage = ((*FPD(TMenuLine (*), Item)).Affects[1] / 16);
    DamageKind = KindMagic;
    if (ViewMode == ViewModeCombat) {
      DrawCombatScreen();
    }
    DealDamage(Who, Damage, 0, 0);
    RedrawItemWindow = 1;
  }
}

/* ovl12:3134. Affect handler of an item that needs a giant (table entry 135, affect $87, stub entry 114), with the
     AffectHandlers shape (Who, Affect and Mode, ovl24:0000); the Affect parameter is the item, as in
     AlignmentBoundWeaponHurtsOthers. Mode 0 applies it; any other Mode does nothing. When Who's Strength is below GiantStrength
     (19) the item is unreadied (Readied cleared) and ShowFlashMessage shows 'Must have Giant Strength' (the literal is
     copied to a stack temporary first, $O+). The only item with Affects[3] $87 in the pinned files is a type $57 two-handed
     bludgeoning row [V item files]. Runs for affect $87 (id 135, InitAffectHandlers [V]). */
void RequireGiantStrength(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("RequireGiantStrength");
  PItem Item = 0;
  Item = Affect;
  if (Mode != 0) {
    return;
  }
  if ((*FPD(TCharacter (*), Who)).Strength < GiantStrength) {
    (*FPD(TMenuLine (*), Item)).Readied = 0;
    ShowFlashMessage(S("\030Must have Giant Strength"));
  }
}

/* ovl12:317A. Affect handler of table entry 137 (affect $89, stub entry 115), with the AffectHandlers shape (Who,
     Affect and Mode, ovl24:0000). Mode 0 applies it and does nothing; any other Mode, the removal (RemoveAffect,
     ovl24:0026), removes affect AffectSpiritualHammer from Who with no particular affect given. Runs for affect $89 (id 137,
     InitAffectHandlers
     [V]). */
void EndSpiritualHammerWhenHammerRemoved(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("EndSpiritualHammerWhenHammerRemoved");
  if (Mode != 0) {
    RemoveAffect(Who, AffectSpiritualHammer, 0);
  }
}

/* ovl12:319B. an affect handler with the AffectHandlers shape (Who, Affect and Mode, ovl24:0000)
     that does nothing: no parameter is read and no global is written, the same code as IgnoreAffect (ovl12:0647).
     It is the handler (stub entry 116, value 0264) of the affects 5, 13, 19, 24, 27, 60, 63, 92 and 127 in the
     AffectHandlers table (DS:6828). */
void IgnoreAffectShared(PCharacter Who, PAffect Affect, u8 Mode)
{
  POOL_TRACE("IgnoreAffectShared");
}

/* ovl12:31A2. the name stays provisional because ovl11 calls it by name (ovl11:002D, StartGame);
     what it does is known. Entry 1 of the unit. It fills the affect handler table
     AffectHandlers (DS:6828, one four-byte handler per affect number) with the stub address of each affect's handler:
     this unit's stubs are in segment 0041, ovl13's in segment 0068 (entries 73 and 74). Affects 5, 13, 19, 24, 27, 60,
     63, 92 and 127 get IgnoreAffectShared, the handler that does nothing. Affect 0 and affect 88 are not set here [?]; entry 0 of
     the table is not a handler (SaveKind lies in it). */
void InitAffectHandlers(void)
{
  POOL_TRACE("InitAffectHandlers");
  AffectHandlers[1] = PROC_RaiseAttackAndMorale;
  AffectHandlers[2] = PROC_LowerAttackAndMorale;
  AffectHandlers[3] = PROC_BoostAttackAgainstUndead;
  AffectHandlers[4] = PROC_StartTrainingWithManual;
  AffectHandlers[5] = PROC_IgnoreAffectShared;
  AffectHandlers[6] = PROC_BoostFireAttackByTarget;
  AffectHandlers[7] = PROC_TrainConstitution;
  AffectHandlers[8] = PROC_ShiftAttackToSaveVsEvil;
  AffectHandlers[9] = PROC_ShiftAttackToSaveVsGood;
  AffectHandlers[10] = PROC_HalveColdDamage;
  AffectHandlers[11] = PROC_ApplyCharmPerson;
  AffectHandlers[12] = PROC_ApplyStrengthAffect;
  AffectHandlers[13] = PROC_IgnoreAffectShared;
  AffectHandlers[14] = PROC_SetCharismaFromAffect;
  AffectHandlers[15] = PROC_SlowPoisonDamage;
  AffectHandlers[16] = PROC_IgnoreAffect;
  AffectHandlers[17] = PROC_RaiseResistanceAndSave;
  AffectHandlers[18] = PROC_BoostAttackVsKoboldGoblin;
  AffectHandlers[19] = PROC_IgnoreAffectShared;
  AffectHandlers[20] = PROC_HalveFireDamage;
  AffectHandlers[21] = PROC_ShowSilenceAndStopCasting;
  AffectHandlers[22] = PROC_DieIfPoisoned;
  AffectHandlers[23] = PROC_GiveSpiritualHammer;
  AffectHandlers[24] = PROC_IgnoreAffectShared;
  AffectHandlers[25] = PROC_InvisibleTargetHardToHit;
  AffectHandlers[26] = PROC_BoostAttackVsOrcGoblinHobgoblin;
  AffectHandlers[27] = PROC_IgnoreAffectShared;
  AffectHandlers[28] = PROC_ImageAbsorbsHit;
  AffectHandlers[29] = PROC_ReduceDamageByQuarter;
  AffectHandlers[30] = PROC_CoughStopsCasting;
  AffectHandlers[31] = PROC_EndAffectedCombatantTurn;
  AffectHandlers[32] = PROC_CollapseAndChangeSide;
  AffectHandlers[33] = PROC_LowerAttackSaveAndResistance;
  AffectHandlers[34] = PROC_RunDiseaseHandlers;
  AffectHandlers[35] = PROC_RaiseAttackAndSave;
  AffectHandlers[36] = PROC_LowerAttackAndSave;
  AffectHandlers[37] = PROC_SetAttackMissIfTurnPending;
  AffectHandlers[38] = PROC_ApplyStrengthAffect;
  AffectHandlers[39] = PROC_ApplyHaste;
  AffectHandlers[40] = PROC_ClearCloud;
  AffectHandlers[41] = PROC_ProtectFromNormalMissiles;
  AffectHandlers[42] = PROC_ApplySlow;
  AffectHandlers[43] = PROC_WeakenStrength;
  AffectHandlers[44] = PROC_CauseDiseaseAndDamage;
  AffectHandlers[45] = PROC_ShiftAttackToSaveVsEvil;
  AffectHandlers[46] = PROC_ShiftAttackToSaveVsGood;
  AffectHandlers[47] = PROC_LowerAttackVsOgreTrollGiant;
  AffectHandlers[48] = PROC_LowerAttackIfSelectedIsBugbearOrGnoll;
  AffectHandlers[49] = PROC_RaiseOrLowerAttackAndSave;
  AffectHandlers[50] = PROC_AddHealingBlockAndHeal;
  AffectHandlers[51] = PROC_EndAffectedCombatantTurn;
  AffectHandlers[52] = PROC_EndAffectedCombatantTurn;
  AffectHandlers[53] = PROC_EndAffectedCombatantTurn;
  AffectHandlers[54] = PROC_IgnoreAffect36;
  AffectHandlers[55] = PROC_IgnoreAffect37;
  AffectHandlers[56] = PROC_GiveInvisibilityForOneRound;
  AffectHandlers[57] = PROC_ProgressRot;
  AffectHandlers[58] = PROC_StopMovement;
  AffectHandlers[59] = PROC_GiveRegainHitPointsAffect;
  AffectHandlers[60] = PROC_IgnoreAffectShared;
  AffectHandlers[61] = PROC_ReduceFireDamageByRoll;
  AffectHandlers[62] = PROC_AddTrainedOutAndHeal;
  AffectHandlers[63] = PROC_IgnoreAffectShared;
  AffectHandlers[64] = PROC_PoisonAttackTargetBonus0;
  AffectHandlers[65] = PROC_PoisonAttackTargetBonus4;
  AffectHandlers[66] = PROC_PoisonAttackTargetBonus2;
  AffectHandlers[67] = PROC_ParalyzeAttackTargetFor2d8;
  AffectHandlers[68] = PROC_ParalyzeAttackTargetUnlessImmune;
  AffectHandlers[69] = PROC_ParalyzeAttackTargetFor1d9Plus10;
  AffectHandlers[70] = PROC_PoisonAttackTargetBonusMinus2;
  AffectHandlers[71] = PROC_InvisibleTargetCannotBeTargeted;
  AffectHandlers[72] = PROC_CamouflageGivesInvisibility;
  AffectHandlers[73] = PROC_RakeAttack;
  AffectHandlers[74] = PROC_ForcedAttack;
  AffectHandlers[75] = PROC_DrainBloodFromCombatant;
  AffectHandlers[76] = PROC_StartBloodDrain;
  AffectHandlers[77] = PROC_HoldWeakTargetFast;
  AffectHandlers[78] = PROC_ReviveOrRetryRevival;
  AffectHandlers[79] = PROC_FireAttackTargetFor2d10;
  AffectHandlers[80] = PROC_AcidAttackTargetFor1d4;
  AffectHandlers[81] = PROC_FrightenSideWithFear;
  AffectHandlers[82] = PROC_ParalyzeSideWithFear;
  AffectHandlers[83] = PROC_GazeStonesTarget;
  AffectHandlers[84] = PROC_GazeCharmsTarget;
  AffectHandlers[85] = PROC_DrainAttackTargetLevel;
  AffectHandlers[86] = PROC_DrainAttackTargetTwoLevels;
  AffectHandlers[87] = PROC_CauseRotOnAttackTarget;
  AffectHandlers[89] = PROC_ForceFirstAttackMiss;
  AffectHandlers[90] = PROC_DwarfHalflingPoisonSaveBonus;
  AffectHandlers[91] = PROC_ImmuneToMagicMissileAndElectricity;
  AffectHandlers[92] = PROC_IgnoreAffectShared;
  AffectHandlers[93] = PROC_HalveFireDamageNoSave;
  AffectHandlers[94] = PROC_HalveDamageForFirstSlotItem;
  AffectHandlers[95] = PROC_FallDeadIfInFight;
  AffectHandlers[96] = PROC_CancelDamageUnlessMagicSlotItem;
  AffectHandlers[97] = PROC_DwarfGnomeHalflingWandSpellSaveBonus;
  AffectHandlers[98] = PROC_RegainHitPoints;
  AffectHandlers[99] = PROC_ReviveDyingCharacter;
  AffectHandlers[100] = PROC_GiveAffectUnlessFireOrAcid;
  AffectHandlers[101] = PROC_GiveRegeneratingUnlessAffected;
  AffectHandlers[102] = PROC_RetryRevivalAtFullHitPoints;
  AffectHandlers[103] = PROC_TurnGaseousAndEscape;
  AffectHandlers[104] = PROC_AvoidDistantAttackByChance;
  AffectHandlers[105] = PROC_CancelHookByHalfChance;
  AffectHandlers[106] = PROC_CancelHookByLowChance;
  AffectHandlers[107] = PROC_ElfResistsCharmAndSleep;
  AffectHandlers[108] = PROC_ImmuneToCharmAndSleep;
  AffectHandlers[109] = PROC_CancelParalysisHook;
  AffectHandlers[110] = PROC_CancelColdDamage;
  AffectHandlers[111] = PROC_CancelPoisonAndParalysisHooks;
  AffectHandlers[112] = PROC_CancelFireDamage;
  AffectHandlers[113] = PROC_ReduceFireDamageOnePerDie;
  AffectHandlers[114] = PROC_HalveElectricityDamage;
  AffectHandlers[115] = PROC_HalveDamageByFirstSlotItemRow;
  AffectHandlers[116] = PROC_HalveDamageForEnchantedSlotItem;
  AffectHandlers[117] = PROC_SetDamageFromHolyWater;
  AffectHandlers[118] = PROC_HalveColdDamageNoSave;
  AffectHandlers[119] = PROC_CancelDamageUnlessEnchantedSlotItem;
  AffectHandlers[120] = PROC_AvoidDistantAttackForBoulder;
  AffectHandlers[121] = PROC_SpitAcidAtTarget;
  AffectHandlers[122] = PROC_SetDamageFromOilFlask;
  AffectHandlers[123] = PROC_HalveOrCancelDamageForUnenchantedSlotItem;
  AffectHandlers[124] = PROC_HalfElfResistsCharmAndSleep;
  AffectHandlers[125] = PROC_ImmuneToCharmSleepHoldAndPoison;
  AffectHandlers[126] = PROC_VetoTargetWithMirrorOrWoodenHolySymbol;
  AffectHandlers[127] = PROC_IgnoreAffectShared;
  AffectHandlers[128] = PROC_ApplyItemSecondAffect;
  AffectHandlers[129] = PROC_ApplyItemSecondAffect;
  AffectHandlers[130] = PROC_ApplyItemSecondAffect;
  AffectHandlers[131] = PROC_GiveExceptionalStrength;
  AffectHandlers[132] = PROC_AlignmentBoundWeaponHurtsOthers;
  AffectHandlers[133] = PROC_ApplyItemSecondAffect;
  AffectHandlers[134] = PROC_ApplyItemSecondAffect;
  AffectHandlers[135] = PROC_RequireGiantStrength;
  AffectHandlers[136] = PROC_ApplyItemSecondAffect;
  AffectHandlers[137] = PROC_EndSpiritualHammerWhenHammerRemoved;
  AffectHandlers[138] = PROC_ApplyItemSecondAffect;
  AffectHandlers[139] = PROC_ApplyItemSecondAffect;
}

/* Initialisation part of unit OVL12. */
void init_OVL12(void)
{
  POOL_TRACE("init");
}
