#include "game.h"

/* ovl24:0000 (e1). Calls the handler of an affect: AffectHandlers[AffectId](Who, Affect, Mode),
     Mode 0 to apply or check it, 1 when it is removed. */
void CallAffectHandler(u8 AffectId, PCharacter Who, PAffect Affect, u8 Mode)
{
  ((void (*)(PCharacter, PAffect, u8))rtl_proc(AffectHandlers[AffectId]))(Who, Affect, Mode);
}

/* ovl24:0026 (e2). Removes an affect from Who's list: the given one, or when Affect is nil the
     first with AffectId. An affect whose Flag is set has its handler called with mode 1 first; the
     9 bytes are freed. Nothing happens when the character has no such affect. */
void RemoveAffect(PCharacter Who, u8 AffectId, farptr Affect)
{
  PAffect Prev = 0;
  PAffect Cur = 0;
  Cur = Affect;
  if (Cur == 0) {
    Cur = (*FPD(TCharacter (*), Who)).Affects;
    while (((Cur != 0)) && (((*FPD(TAffect (*), Cur)).Id != AffectId))) {
      Cur = (*FPD(TAffect (*), Cur)).Next;
    }
  }
  if (Cur != 0) {
    if ((*FPD(TAffect (*), Cur)).Flag != 0) {
      CallAffectHandler(AffectId, Who, Cur, ModeRemove);
    }
    if ((*FPD(TCharacter (*), Who)).Affects == Cur) {
      (*FPD(TCharacter (*), Who)).Affects = (*FPD(TAffect (*), Cur)).Next;
    } else {
      Prev = (*FPD(TCharacter (*), Who)).Affects;
      while (((Prev != 0)) && (((*FPD(TAffect (*), Prev)).Next != Cur))) {
        Prev = (*FPD(TAffect (*), Prev)).Next;
      }
      (*FPD(TAffect (*), Prev)).Next = (*FPD(TAffect (*), Cur)).Next;
    }
    rtl_freemem(Cur, AffectRecordSize);
  }
}

/* ovl24:0160. Runs one affect's hook: when Who has the affect its handler is called (mode 0). For
     the four affects $15, $2D, $2E and $31 that act around their bearer it is enough that another
     member of the party list has it and, in combat, reaches Who (ScanTargets from the bearer, 6
     squares for $31, 1 for the others); the ovl30 sort table SortEntries is saved and restored around the
     scan. */
void RunAffectHook(PCharacter Who, u8 AffectId)
{
  TSortRec Saved[72] = {0};
  PCharacter Other = 0;
  farptr Affect = 0;
  u8 Found = 0;
  u8 I = 0;
  u8 Range = 0;
  u8 t1;
  Found = 0;
  Other = PartyListHead;
  if (HasAffect(Who, AffectId, &Affect)) {
    Found = 1;
  } else if (AffectId == 0x15 || AffectId == 0x2D || AffectId == 0x2E || AffectId == 0x31) {
    rtl_Move((void *)&SortEntries[1], (void *)&Saved, 216);
    while (((Other != 0)) && !Found) {
      if (HasAffect(Other, AffectId, &Affect)) {
        if (ViewMode == ViewModeCombat) {
          if (AffectId == 0x31) {
            Range = 6;
          } else {
            Range = 1;
          }
          ScanTargets(CombatantX(Other), CombatantY(Other), Range, 0xFF, CombatantKind(Other), CombatMap);
          t1 = SortEntries[0].Val_;
          I = 1;
          if (I <= t1) for (;;) {
            if (SortEntries[I].Head == CombatantIndex(Who)) {
              Found = 1;
            }
            if (I == t1) break;
            I++;
          }
        } else {
          Found = 1;
        }
      }
      Other = (*FPD(TCharacter (*), Other)).Next;
    }
    rtl_Move((void *)&Saved, (void *)&SortEntries[1], 216);
  }
  if (Found) {
    CallAffectHandler(AffectId, Who, Affect, ModeApply);
  }
}

/* ovl24:02FA (e3). Runs the hooks of one kind of event for Who: each kind (0..$13) has a fixed list
     of affect ids whose handlers (RunAffectHook) may change the roll in progress (AttackRoll,
     SaveRoll, DamageAmount, HookAffectId). This unit uses kinds 6, 9, $A, $C, $D and $10; other
     units call it with 7, $F and $13. QUIRK ovl24:02FD: 4 bytes of frame nothing uses. */
void RunAffectHooks(u8 Kind, PCharacter Who)
{
  farptr Unused = 0;
  switch (Kind) {
  case 0:
  {
    RunAffectHook(Who, 0x7E);
    break;
  }
  case 1:
  {
    RunAffectHook(Who, 0x3F);
    RunAffectHook(Who, 0x25);
    RunAffectHook(Who, 0x19);
    RunAffectHook(Who, 0x47);
    break;
  }
  case 2:
  {
    RunAffectHook(Who, 0x55);
    RunAffectHook(Who, 0x56);
    RunAffectHook(Who, 0x57);
    RunAffectHook(Who, 0x44);
    RunAffectHook(Who, 0x4F);
    RunAffectHook(Who, 0x50);
    RunAffectHook(Who, 0x4C);
    RunAffectHook(Who, 0x49);
    RunAffectHook(Who, 0x4D);
    break;
  }
  case 3:
  {
    RunAffectHook(Who, 0x40);
    RunAffectHook(Who, 0x41);
    RunAffectHook(Who, 0x42);
    RunAffectHook(Who, 0x43);
    RunAffectHook(Who, 0x44);
    RunAffectHook(Who, 0x45);
    RunAffectHook(Who, 0x46);
    RunAffectHook(Who, 0x4F);
    RunAffectHook(Who, 0x55);
    RunAffectHook(Who, 0x56);
    RunAffectHook(Who, 0x57);
    break;
  }
  case 4:
  {
    RunAffectHook(Who, 0x1D);
    RunAffectHook(Who, 0x3);
    RunAffectHook(Who, 0x6);
    break;
  }
  case 5:
  {
    RunAffectHook(Who, 0x1C);
    RunAffectHook(Who, 0x29);
    RunAffectHook(Who, 0x68);
    RunAffectHook(Who, 0x78);
    RunAffectHook(Who, 0x65);
    RunAffectHook(Who, 0x73);
    RunAffectHook(Who, 0x74);
    RunAffectHook(Who, 0x77);
    RunAffectHook(Who, 0x7B);
    RunAffectHook(Who, 0x60);
    RunAffectHook(Who, 0x5E);
    RunAffectHook(Who, 0x3C);
    RunAffectHook(Who, 0x7A);
    RunAffectHook(Who, 0x75);
    break;
  }
  case 6:
  {
    RunAffectHook(Who, 0x71);
    RunAffectHook(Who, 0x3D);
    RunAffectHook(Who, 0x7A);
    RunAffectHook(Who, 0x3C);
    RunAffectHook(Who, 0x5B);
    RunAffectHook(Who, 0xA);
    RunAffectHook(Who, 0x14);
    RunAffectHook(Who, 0x69);
    RunAffectHook(Who, 0x6A);
    RunAffectHook(Who, 0x70);
    RunAffectHook(Who, 0x72);
    RunAffectHook(Who, 0x76);
    RunAffectHook(Who, 0x11);
    RunAffectHook(Who, 0x5D);
    RunAffectHook(Who, 0x65);
    RunAffectHook(Who, 0x1C);
    break;
  }
  case 7:
  {
    RunAffectHook(Who, 0x33);
    RunAffectHook(Who, 0x34);
    RunAffectHook(Who, 0x35);
    RunAffectHook(Who, 0x1F);
    break;
  }
  case 8:
  {
    RunAffectHook(Who, 0x63);
    RunAffectHook(Who, 0x51);
    RunAffectHook(Who, 0x52);
    RunAffectHook(Who, 0x59);
    RunAffectHook(Who, 0x48);
    RunAffectHook(Who, 0x38);
    break;
  }
  case 9:
  {
    RunAffectHook(Who, 0x69);
    RunAffectHook(Who, 0x6A);
    RunAffectHook(Who, 0x6B);
    RunAffectHook(Who, 0x6C);
    RunAffectHook(Who, 0x6D);
    RunAffectHook(Who, 0x6E);
    RunAffectHook(Who, 0x6F);
    RunAffectHook(Who, 0x70);
    RunAffectHook(Who, 0x7C);
    RunAffectHook(Who, 0x7D);
    break;
  }
  case 0xA:
  {
    RunAffectHook(Who, 0x1);
    RunAffectHook(Who, 0x2);
    RunAffectHook(Who, 0x21);
    RunAffectHook(Who, 0x24);
    RunAffectHook(Who, 0x31);
    RunAffectHook(Who, 0x3);
    RunAffectHook(Who, 0x6);
    RunAffectHook(Who, 0x12);
    RunAffectHook(Who, 0x1A);
    break;
  }
  case 0xB:
  {
    RunAffectHook(Who, 0x21);
    RunAffectHook(Who, 0x11);
    RunAffectHook(Who, 0x8);
    RunAffectHook(Who, 0x9);
    RunAffectHook(Who, 0x2D);
    RunAffectHook(Who, 0x2E);
    RunAffectHook(Who, 0x1E);
    break;
  }
  case 0xC:
  {
    RunAffectHook(Who, 0x8);
    RunAffectHook(Who, 0x9);
    RunAffectHook(Who, 0xA);
    RunAffectHook(Who, 0x11);
    RunAffectHook(Who, 0x14);
    RunAffectHook(Who, 0x21);
    RunAffectHook(Who, 0x24);
    RunAffectHook(Who, 0x2D);
    RunAffectHook(Who, 0x2E);
    RunAffectHook(Who, 0x31);
    RunAffectHook(Who, 0x3D);
    RunAffectHook(Who, 0x6F);
    RunAffectHook(Who, 0x7D);
    RunAffectHook(Who, 0x5A);
    RunAffectHook(Who, 0x61);
    break;
  }
  case 0xD:
  {
    RunAffectHook(Who, 0x63);
    RunAffectHook(Who, 0x64);
    RunAffectHook(Who, 0x67);
    RunAffectHook(Who, 0x4B);
    RunAffectHook(Who, 0x4A);
    break;
  }
  case 0xE:
  {
    RunAffectHook(Who, 0x53);
    RunAffectHook(Who, 0x54);
    RunAffectHook(Who, 0x58);
    RunAffectHook(Who, 0x79);
    break;
  }
  case 0xF:
  {
    RunAffectHook(Who, 0x15);
    RunAffectHook(Who, 0x1E);
    RunAffectHook(Who, 0x4A);
    RunAffectHook(Who, 0x4B);
    RunAffectHook(Who, 0xB);
    break;
  }
  case 0x10:
  {
    RunAffectHook(Who, 0x19);
    RunAffectHook(Who, 0x47);
    RunAffectHook(Who, 0x25);
    RunAffectHook(Who, 0x2F);
    RunAffectHook(Who, 0x30);
    RunAffectHook(Who, 0x59);
    break;
  }
  case 0x11:
  {
    RunAffectHook(Who, 0x1);
    RunAffectHook(Who, 0x2);
    RunAffectHook(Who, 0xB);
    break;
  }
  case 0x12:
  {
    RunAffectHook(Who, 0x27);
    RunAffectHook(Who, 0x2A);
    RunAffectHook(Who, 0x3A);
    break;
  }
  case 0x13:
  {
    RunAffectHook(Who, 0x62);
    RunAffectHook(Who, 0x17);
    RunAffectHook(Who, 0x48);
    RunAffectHook(Who, 0x38);
    RunAffectHook(Who, 0xB);
    break;
  }
  }
}

/* ovl24:0AE7 (e4). A standing combatant (Flag10D) on the cloud tile ($1E under it, ProbeStep) that
     has none of the affects $1E, $1F, $20, $6F, $7D makes a saving throw (kind 0): saved, it gets
     affect $1E for one round ('starts to cough'); failed, affect $1F for 1d4 + 1 ('chokes and gags
     from nausea'); the new affect's handler is called. A stinking cloud by its texts [I]. */
void ApplyCloudTile(PCharacter Who)
{
  u8 Tile = 0;
  u8 Occupant = 0;
  farptr Affect = 0;
  u8 Saved = 0;
  if ((*FPD(TCharacter (*), Who)).Flag10D != 0) {
    ProbeStep(Who, 8, &Occupant, &Tile);
    if (Tile == CloudTile) {
      if (!HasAffect(Who, 0x1E, &Affect)) {
        if (!HasAffect(Who, 0x1F, &Affect)) {
          if (!HasAffect(Who, 0x20, &Affect)) {
            if (!HasAffect(Who, 0x6F, &Affect)) {
              if (!HasAffect(Who, 0x7D, &Affect)) {
                Saved = SavingThrow(Who, 0, 0);
                if (Saved) {
                  ApplyAffect(Who, AffectCough, 1, 0xFF, 0, 0, Saved, S("\017starts to cough"));
                  CallAffectHandler(AffectCough, Who, Affect, ModeApply);
                } else {
                  ApplyAffect(Who, AffectHelpless, (s16)(RollDice(1, 4) + 1), 0xFF, 0, 0, Saved, S("\033chokes and gags from nausea"));
                  CallAffectHandler(AffectHelpless, Who, Affect, ModeApply);
                }
              }
            }
          }
        }
      }
    }
  }
}

/* ovl24:0C4F (e5). A resistance roll against Who: AttackRoll is a d20 (a 1 fails, a 20 counts
     100), the target hooks ($10) may change it; True when it is not negative and AttackRoll plus
     Level exceeds Who's ArmourClassValue (+$111). */
u8 RollBeatsResistance(PCharacter Who, u8 Level)
{
  u8 Result = 0;
  Result = 0;
  AttackRoll = RollDice(1, 20);
  if (AttackRoll > NaturalOne) {
    if (AttackRoll == NaturalTwenty) {
      AttackRoll = TwentyCounts;
    }
    RunAffectHooks(HookTarget, Who);
    if (AttackRoll >= 0) {
      if ((s16)(AttackRoll + Level) > (*FPD(TCharacter (*), Who)).ArmourClassValue) {
        Result = 1;
      }
    }
  }
  return Result;
}

/* ovl24:0CB7 (e6). An attack roll: the attacker loses affect $19 (ClearAttackerAffect), AttackRoll
     is a d20 (1 misses, 20 counts 100) changed by the attacker's ($A) and the target's ($10) hooks;
     True when it is not negative and AttackRoll + the attacker's HitAdjust (+$110) + the game word
     of its side (881 for the party, 880 for the others, low byte signed) reaches Needed. */
u8 RollToHit(PCharacter Attacker, PCharacter Target, u8 Needed)
{
  u8 Result = 0;
  s8 SideBonus = 0;
  Result = 0;
  ClearAttackerAffect(Attacker);
  AttackRoll = RollDice(1, 20);
  if (AttackRoll > NaturalOne) {
    if (AttackRoll == NaturalTwenty) {
      AttackRoll = TwentyCounts;
    }
    RunAffectHooks(HookAttacker, Attacker);
    RunAffectHooks(HookTarget, Target);
    if ((*FPD(TCharacter (*), Attacker)).Side == SideParty) {
      SideBonus = (*FPD(TGameVars (*), GameVars2))[881];
    } else {
      SideBonus = (*FPD(TGameVars (*), GameVars2))[880];
    }
    if (AttackRoll >= 0) {
      if ((s16)((AttackRoll + (*FPD(TCharacter (*), Attacker)).HitAdjust) + SideBonus) >= Needed) {
        Result = 1;
      }
    }
  }
  return Result;
}

/* ovl24:0D63 (e7). A saving throw of Who of the given kind (an index of SavingThrows, 0..4):
     SaveRoll is a d20; a 1 fails and a 20 succeeds, otherwise SaveRoll + SaveBonus (+$101) + Bonus,
     changed by the save hooks ($C, with SaveKind), succeeds when it reaches SavingThrows[Kind]. */
u8 SavingThrow(PCharacter Who, s8 Kind, s8 Bonus)
{
  u8 Result = 0;
  SaveRoll = RollDice(1, 20);
  switch (SaveRoll) {
  case NaturalOne:
  {
    Result = 0;
    break;
  }
  case NaturalTwenty:
  {
    Result = 1;
    break;
  }
  default:
  {
    SaveRoll = (SaveRoll + (*FPD(TCharacter (*), Who)).SaveBonus) + Bonus;
    SaveKind = Kind;
    RunAffectHooks(HookSave, Who);
    if ((*FPD(TCharacter (*), Who)).SavingThrows[Kind] <= SaveRoll) {
      Result = 1;
    } else {
      Result = 0;
    }
  }
  }
  return Result;
}

/* ovl24:0DE3 (e8). Rolls Count dice of Sides faces (Random(Sides) + 1 each) and returns the sum,
     0 for no dice. The game's dice: ovl04 rolls 1d8, 2d8 and 3d8 for the cure spells. QUIRK: the
     sum is a Byte and wraps above 255. */
u8 RollDice(u8 Count, u8 Sides)
{
  u8 Result = 0;
  u8 I = 0;
  u8 Total = 0;
  u8 t1;
  Total = 0;
  if (Count > 0) {
    t1 = Count;
    I = 1;
    if (I <= t1) for (;;) {
      Total += (u16)(rtl_Random(Sides) + 1);
      if (I == t1) break;
      I++;
    }
  }
  Result = Total;
  return Result;
}

/* ovl24:0E2E (e9). RollDice(Count, Sides), keeping Count in LastDiceCount (who reads it is not known
     yet). */
u8 RollDiceCounted(u8 Count, u8 Sides)
{
  u8 Result = 0;
  LastDiceCount = Count;
  Result = RollDice(Count, Sides);
  return Result;
}

/* ovl24:0E52 (e10). Appends a new affect (9 bytes) at the end of Who's affect list with the
     given id, duration, data and flag. */
void AddAffect(PCharacter Who, u8 AffectId, u16 Duration, u8 Data, u8 Flag)
{
  PAffect Added = 0;
  PAffect Last = 0;
  Added = rtl_getmem(9);
  if ((*FPD(TCharacter (*), Who)).Affects == 0) {
    (*FPD(TCharacter (*), Who)).Affects = Added;
  } else {
    Last = (*FPD(TCharacter (*), Who)).Affects;
    while ((*FPD(TAffect (*), Last)).Next != 0) {
      Last = (*FPD(TAffect (*), Last)).Next;
    }
    (*FPD(TAffect (*), Last)).Next = Added;
  }
  (*FPD(TAffect (*), Added)).Next = 0;
  (*FPD(TAffect (*), Added)).Id = AffectId;
  (*FPD(TAffect (*), Added)).Duration = Duration;
  (*FPD(TAffect (*), Added)).Flag = Flag;
  (*FPD(TAffect (*), Added)).Data = Data;
}

/* ovl24:0F06 (e11). Takes a standing combatant out of the fight: shows Msg on it, clears Flag10D,
     sets its Status (and its hit points to 0 unless it fled), redraws its ground, clears its entry
     of CombatantTable and the occupancy; when EndCombatTurn says so its death affects are removed
     (RemoveDeathAffects). */
void DropCombatant(PCharacter Who, u8 NewStatus, const u8 *Msg_in)
{
  const u8 *Msg = Msg_in;
  u8 Index = 0;
  if ((*FPD(TCharacter (*), Who)).Flag10D != 0) {
    Index = CombatantIndex(Who);
    ShowCursorOn(Who, 3, 0);
    ShowCharacterMessage(Who, Msg, 0xA, 1);
    (*FPD(TCharacter (*), Who)).Flag10D = 0;
    (*FPD(TCharacter (*), Who)).Status = NewStatus;
    if ((*FPD(TCharacter (*), Who)).Status != StatusFled) {
      (*FPD(TCharacter (*), Who)).HpCurrent = 0;
    }
    RedrawGround(0, 0, Index);
    FlushPictureChanges();
    CombatantTable[Index].Kind = 0;
    RebuildOccupancy();
    if (EndCombatTurn(Who) != 0) {
      RemoveDeathAffects(Who);
    }
  }
}

/* ovl24:0FD2 (e12). Removes every affect $19 from Who; RollToHit calls it for the attacker
     before rolling, so attacking ends the affect (an invisibility by that rule [I]). */
void ClearAttackerAffect(PCharacter Who)
{
  farptr Affect = 0;
  while (HasAffect(Who, AffectInvisibility, &Affect)) {
    RemoveAffect(Who, AffectInvisibility, Affect);
  }
}

/* ovl24:100A (e13). Removes the sixteen affects of DeathAffects from Who: what a combatant loses
     when it goes down (DropCombatant, DealDamage). */
void RemoveDeathAffects(PCharacter Who)
{
  u8 I = 0;
  I = 1;
  if (I <= DeathAffectCount) for (;;) {
    RemoveAffect(Who, DeathAffects[I], 0);
    if (I == DeathAffectCount) break;
    I++;
  }
}

/* ovl24:1041 (e14). removes the two affects of ExtraDeathAffects ($4A and $4B, the last two
     of DeathAffects too) from Who; an entry of the overlay, its callers are not decompiled yet. */
void RemoveExtraDeathAffects(PCharacter Who)
{
  u8 I = 0;
  I = 1;
  if (I <= 2) for (;;) {
    RemoveAffect(Who, ExtraDeathAffects[I], 0);
    if (I == 2) break;
    I++;
  }
}

/* ovl24:1081 (e15). When Who has the affect: shows 'is Cured', removes it and returns True;
     False otherwise. */
u8 CureAffect(PCharacter Who, u8 AffectId)
{
  u8 Result = 0;
  farptr Affect = 0;
  Result = 0;
  if (HasAffect(Who, AffectId, &Affect)) {
    ShowCharacterMessage(Who, S("\010is Cured"), 0xA, 1);
    RemoveAffect(Who, AffectId, Affect);
    Result = 1;
  }
  return Result;
}

/* ovl24:10E4 (e16). Strength and exceptional strength in one byte: Strength + 100, or for 18 the
     percentile + 1 (1..101). */
u8 EncodeStrength(u8 Strength, u8 Percent)
{
  u8 Result = 0;
  Result = Strength + StrengthOffset;
  if (Strength == ExceptionalStrength) {
    Result = Percent + 1;
  }
  return Result;
}

/* ovl24:110D (e17). The inverse of EncodeStrength on an affect's Data (bit 7 masked): up to 101
     is 18 with Data - 1 percent, above is Data - 100 with no percent. */
void DecodeStrength(PAffect Affect, u8 (*Strength), u8 (*Percent))
{
  (*Percent) = 0;
  (*Strength) = ((*FPD(TAffect (*), Affect)).Data & (u8)~StrengthKept);
  if ((*Strength) <= 101) {
    (*Percent) = (*Strength) - 1;
    (*Strength) = ExceptionalStrength;
  } else {
    (*Strength) = (*Strength) - StrengthOffset;
  }
}

/* ovl24:115C (e18). Sets Who's strength to Strength / Percent unless that is lower than the
     current one (then False and Code is the new value encoded plus $80). Otherwise the first
     strength affect ($C or $26) not yet holding an earlier strength gets the current one encoded
     plus $80, Strength and StrengthPercent change (RecalcCombatValues recomputes), Code is the earlier
     strength encoded, and the result is True. */
u8 RaiseStrength(PCharacter Who, u8 Strength, u8 Percent, u8 (*Code))
{
  u8 Result = 0;
  PAffect Cur = 0;
  PAffect Found = 0;
  u8 OldStrength = 0;
  u8 OldPercent = 0;
  u8 OldCode = 0;
  OldStrength = (*FPD(TCharacter (*), Who)).Strength;
  OldPercent = (*FPD(TCharacter (*), Who)).StrengthPercent;
  if (((Strength < OldStrength)) || ((((Strength == ExceptionalStrength)) && ((Percent < OldPercent))))) {
    Result = 0;
    (*Code) = EncodeStrength(Strength, Percent) + StrengthKept;
  } else {
    Found = 0;
    Cur = (*FPD(TCharacter (*), Who)).Affects;
    while (((Cur != 0)) && ((Found == 0))) {
      if ((((((*FPD(TAffect (*), Cur)).Id == AffectEnlarge)) || (((*FPD(TAffect (*), Cur)).Id == AffectStrength)))) && (((*FPD(TAffect (*), Cur)).Data < StrengthKept))) {
        Found = Cur;
      }
      Cur = (*FPD(TAffect (*), Cur)).Next;
    }
    if (Found != 0) {
      OldCode = EncodeStrength(OldStrength, OldPercent);
      DecodeStrength(Found, &OldStrength, &OldPercent);
      (*FPD(TAffect (*), Found)).Data = OldCode + StrengthKept;
    }
    (*FPD(TCharacter (*), Who)).Strength = Strength;
    (*FPD(TCharacter (*), Who)).StrengthPercent = Percent;
    RecalcCombatValues(Who);
    (*Code) = EncodeStrength(OldStrength, OldPercent);
    Result = 1;
  }
  return Result;
}

/* ovl24:1344 (e19). Deals damage to Who: the damage hooks (6) may change DamageAmount; a save
     (Saved) makes it none (SaveEffect 1) or half (2). Shows 'takes <n> points of damage' (or 1
     point) with 'from Fire', 'from Cold', 'from Electricity', 'from Acid' or 'from Magic' by
     DamageKind, deals it (ApplyDamage); in combat the combatant cannot cast any more and a pending
     spell is lost ('lost a spell'). A combatant that went down shows 'Goes Down', ', and is Dying'
     or 'is killed' (status 6..8); in combat it loses its death affects, the hooks $D run and it
     leaves the map (RemoveCombatant) unless they stood it up again. */
void DealDamage(PCharacter Who, u8 Damage, u8 SaveEffect, u8 Saved)
{
  u8 Msg[256] = {0};
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  u8 t5[256];
  u8 t6[256];
  u8 t7[256];
  u8 t8[256];
  s32 t9;
  DamageAmount = Damage;
  RunAffectHooks(HookDamage, Who);
  if (Saved) {
    switch (SaveEffect) {
    case 1:
    {
      DamageAmount = 0;
      break;
    }
    case 2:
    {
      DamageAmount = (DamageAmount / 2);
      break;
    }
    }
  }
  if (DamageAmount > 0) {
    if (DamageAmount != 1) {
      rtl_str_assign(Msg, 255, rtl_str_cat(t2, 3, (const u8 *const[]){S("\006takes "), ByteToText(t1, DamageAmount), S("\022 points of damage ")}));
    } else {
      rtl_str_assign(Msg, 255, S("\030takes 1 point of damage "));
    }
    switch ((DamageKind & 0xF7)) {
    case 1:
    {
      rtl_str_assign(Msg, 255, rtl_str_cat(t3, 2, (const u8 *const[]){Msg, S("\011from Fire")}));
      break;
    }
    case 2:
    {
      rtl_str_assign(Msg, 255, rtl_str_cat(t4, 2, (const u8 *const[]){Msg, S("\011from Cold")}));
      break;
    }
    case 4:
    {
      rtl_str_assign(Msg, 255, rtl_str_cat(t5, 2, (const u8 *const[]){Msg, S("\020from Electricity")}));
      break;
    }
    case 0x10:
    {
      rtl_str_assign(Msg, 255, rtl_str_cat(t6, 2, (const u8 *const[]){Msg, S("\011from Acid")}));
      break;
    }
    }
    if ((DamageKind & 8) == DamageKind) {
      rtl_str_assign(Msg, 255, rtl_str_cat(t7, 2, (const u8 *const[]){Msg, S("\012from Magic")}));
    }
    ShowHitMessage(Who, 0, Msg);
    ApplyDamage(Who, DamageAmount);
    if (ViewMode == ViewModeCombat) {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).CanCast = 0;
      if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).PendingSpell > 0) {
        ShowCharacterMessage(Who, S("\014lost a spell"), 0xC, 1);
        ForgetSpell((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).PendingSpell);
        (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).PendingSpell = 0;
      }
    }
    if ((*FPD(TCharacter (*), Who)).Flag10D == 0) {
      rtl_str_assign(Msg, 255, S("\011Goes Down"));
      if ((*FPD(TCharacter (*), Who)).Status == StatusDying) {
        rtl_str_assign(Msg, 255, rtl_str_cat(t8, 2, (const u8 *const[]){Msg, S("\016, and is Dying")}));
      }
      if ((t9 = (*FPD(TCharacter (*), Who)).Status), (t9 == 6 || t9 == 7 || t9 == 8)) {
        rtl_str_assign(Msg, 255, S("\011is killed"));
      }
      ShowCharacterMessage(Who, Msg, (s16)(GlyphRow + 1), 0);
      if (ViewMode != ViewModeCombat) {
        DelayByGameSpeed();
      } else {
        RemoveDeathAffects(Who);
        RunAffectHooks(HookGoesDown, Who);
        if ((*FPD(TCharacter (*), Who)).Flag10D == 0) {
          RemoveCombatant(Who);
        } else {
          DelayByGameSpeed();
        }
      }
    }
    ClearCharacterMessage();
  }
}

/* ovl24:1656 (e20). Gives Who an affect: the hooks of kind 9 may refuse it (HookAffectId
     cleared), as does a save when SaveNegates is 1; then 'is Unaffected'. Otherwise an affect of the
     same id with a shorter limited duration (or any, for a permanent new one) is removed, the new
     one is added (AddAffect) and Msg, when not empty, is shown. QUIRK ovl24:1659: one frame byte
     nothing uses. */
void ApplyAffect(PCharacter Who, u8 AffectId, u16 Duration, u8 Data, u8 Flag, u8 SaveNegates, u8 Saved, const u8 *Msg_in)
{
  const u8 *Msg = Msg_in;
  farptr Existing = 0;
  u8 Unused = 0;
  HookAffectId = AffectId;
  RunAffectHooks(HookApplyAffect, Who);
  if (((HookAffectId == 0)) || ((Saved && ((SaveNegates == 1))))) {
    ShowCharacterMessage(Who, S("\015is Unaffected"), 0xA, 1);
  } else {
    if (HasAffect(Who, AffectId, &Existing)) {
      if ((((((*FPD(TAffect (*), Existing)).Duration > 0)) && ((Duration > (*FPD(TAffect (*), Existing)).Duration)))) || ((Duration == 0))) {
        RemoveAffect(Who, AffectId, Existing);
      }
    }
    AddAffect(Who, AffectId, Duration, Data, Flag);
    if (rtl_str_cmp(Msg, S("\000")) != 0) {
      ShowHitMessage(Who, 1, Msg);
      ClearCharacterMessage();
    }
  }
}

/* ovl24:175D (e21). Heals Who by Amount hit points (HpCurrent, capped at HpMax) when its status is
     0, 1, 4 or 5 and either it is wounded and Flag is set, or Flag is 0 and it has no affect $32. A
     fallen character that is dying becomes unconscious; an unconscious one outside combat has the
     handler of affect $4E called (mode 1). Returns True when it healed. ovl04's cure spells call it
     with Flag 0. */
u8 HealCharacter(PCharacter Who, u8 Amount, u8 Flag)
{
  u8 Result = 0;
  farptr Affect = 0;
  s32 t1;
  Result = 0;
  if ((t1 = (*FPD(TCharacter (*), Who)).Status), (t1 == 0 || t1 == 1 || t1 == 4 || t1 == 5)) {
    if ((((((*FPD(TCharacter (*), Who)).HpCurrent < (*FPD(TCharacter (*), Who)).HpMax)) && ((Flag != 0)))) || ((!HasAffect(Who, AffectMummyDisease, &Affect) && ((Flag == 0))))) {
      (*FPD(TCharacter (*), Who)).HpCurrent = (*FPD(TCharacter (*), Who)).HpCurrent + Amount;
      if ((*FPD(TCharacter (*), Who)).HpCurrent > (*FPD(TCharacter (*), Who)).HpMax) {
        (*FPD(TCharacter (*), Who)).HpCurrent = (*FPD(TCharacter (*), Who)).HpMax;
      }
      if ((*FPD(TCharacter (*), Who)).Flag10D == 0) {
        if ((*FPD(TCharacter (*), Who)).Status == StatusDying) {
          (*FPD(TCharacter (*), Who)).Status = StatusUnconscious;
        }
        if ((((*FPD(TCharacter (*), Who)).Status == StatusUnconscious)) && ((ViewMode != ViewModeCombat))) {
          CallAffectHandler(AffectRevival, Who, 0, ModeRemove);
        }
      }
      Result = 1;
    }
  }
  return Result;
}

/* ovl24:1869 (e22). Puts a fallen combatant back on its square (PlaceCombatant): status okay,
     Flag10D set, HitPoints hit points, the cursor on it in combat, and 'stands up and grins' (a
     monster) or 'gets back up'. False when it cannot be placed. */
u8 ReviveCombatant(PCharacter Who, u8 HitPoints)
{
  u8 Result = 0;
  u8 Msg[41] = {0};
  if (PlaceCombatant(Who, CombatantX(Who), CombatantY(Who), 1)) {
    (*FPD(TCharacter (*), Who)).Status = StatusOkay;
    (*FPD(TCharacter (*), Who)).Flag10D = 1;
    (*FPD(TCharacter (*), Who)).HpCurrent = HitPoints;
    if (ViewMode == ViewModeCombat) {
      ShowCursorOn(Who, 3, 0);
    }
    if ((*FPD(TCharacter (*), Who)).Side == SideMonsters) {
      rtl_str_assign(Msg, 40, S("\023stands up and grins"));
    } else {
      rtl_str_assign(Msg, 40, S("\014gets back up"));
    }
    ShowCharacterMessage(Who, Msg, 0xA, 1);
    RecountCombatSides();
    Result = 1;
  } else {
    Result = 0;
  }
  return Result;
}

/* Initialisation part of unit OVL24. */
void init_OVL24(void)
{
  /* ovl24:1932. The unit's initialisation part is empty (push bp; mov bp, sp; pop bp; retf). */
}
