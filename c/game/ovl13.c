#include "game.h"

/* ovl13:0000. Sets up Who's turn at the start of a combat round: clears and re-arms its combat
     state Combat^ (PendingSpell 0, Cast and Use-magic allowed), refreshes it through RefreshAttacks, lets
     the hooks change the attack byte HookedMoveOrAttacks (RunAffectHooks $12) and stores the result in the
     readied-weapon block (+$114); then, for a character still in the fight (Flag10D set), rolls its
     initiative (1d6 plus DexterityAttackAdjustment, at least 1, 6 lower when the round penalty word
     matches its side, else 0 outside 0..$14), and finally gives it this round's move budget
     (ComputeMovement). Called for every combatant at the start of each round (RunCombat ovl08:0063).
     The body is a `with Who^.Combat^ do` block (the compiler caches the pointer in a hidden temp
     below the locals, reloaded before every field access). QUIRK ovl13:0093: the one named byte
     local is declared and never read; it is what makes the frame 6 bytes. */
void StartCombatantRound(PCharacter Who)
{
  u8 Unused = 0;
  {
    TCombatant *w1 = &(*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat));
      w1->PendingSpell = 0;
      w1->CanCast = 1;
      w1->CanUseMagicItem = 1;
      w1->Pad8 = 0;
      w1->Pad4[0] = 2;
      RefreshAttacks(Who);
      HookedMoveOrAttacks = (*FPD(TCharacter (*), Who)).PadA2;
      HookRunning = 0;
      RunAffectHooks(HookComputeMovement, Who);
      (*FPD(TCharacter (*), Who)).AttackSlots[1] = AttacksThisRound(HookedMoveOrAttacks);
      w1->Pad4[1] = (*FPD(TCharacter (*), Who)).SweepAttacks;
      if ((*FPD(TCharacter (*), Who)).Flag10D != 0) {
        w1->Initiative = RollDice(1, InitiativeDieSides) + DexterityAttackAdjustment(Who);
        if (w1->Initiative < 1) {
          w1->Initiative = 1;
        }
        /* QUIRK ovl13:00C5: the original widens Side with cbw (a sign extend) and ANDs it with a
           16-bit signed word, then tests the low byte only; the casts reproduce that shape (Side is
           a Byte elsewhere: ovl09 and res12 compare it unsigned). */
        if ((u8)(((s16)((*FPD(TCharacter (*), Who)).Side + 1)) & (*FPD(TGameVars (*), GameVars2))[715]) != 0) {
          w1->Initiative -= InitiativePenalty;
        }
        if (((w1->Initiative < 0)) || ((w1->Initiative > MaxInitiative))) {
          w1->Initiative = 0;
        }
      } else {
        w1->Initiative = 0;
      }
  }
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves = ComputeMovement(Who);
}

/* ovl13:0123. Works out how far Who may move this round: its Movement (+$11C), raised by the
     party movement word during combat, is checked against 1..$60 and doubled into half squares, and
     the doubled value is left in HookedMoveOrAttacks and returned. The doubled value is offered to the movement
     affect hooks (RunAffectHooks $12, which may still change it). Called once per character at the
     start of each combat round (RunCombat ovl08:0063). HookRunning brackets the hook run.
     QUIRK ovl13:0161: a Movement outside 1..$60 (below 1 or above MaxMovement) becomes 1, not the
     cap, so an over-fast combatant gets the slowest move (a port clamping to $60 would give it the
     fastest). */
u8 ComputeMovement(PCharacter Who)
{
  u8 Result = 0;
  u8 Moves = 0;
  Moves = (*FPD(TCharacter (*), Who)).Movement;
  if ((*FPD(TCharacter (*), Who)).Side == SideParty) {
    Moves = Moves + (*FPD(TGameVars (*), GameVars2))[882];
  }
  HookRunning = 1;
  if (((Moves < 1)) || ((Moves > MaxMovement))) {
    Moves = 1;
  }
  HookedMoveOrAttacks = Moves * 2;
  RunAffectHooks(HookComputeMovement, Who);
  HookRunning = 0;
  Result = HookedMoveOrAttacks;
  return Result;
}

/* ovl13:0191. Rolls the damage of one attack of Attacker against Target: entry Index (1 or 2)
     of the readied weapon's attack triple gives the dice count and die size (RollDiceCounted) and the
     signed bonus (WeaponDamageBonus). The total goes to DamageAmount, a nonsensical negative clamp
     (QUIRK ovl13:01D2) is kept, a special attack (IsBackstab, the backstab) multiplies the damage
     by the thief level div 4 + 2, DamageKind becomes 0 and the damage hooks run for the attacker (4)
     and the target (5). Called for each of a combatant's attacks. */
void RollAttackDamage(PCharacter Attacker, PCharacter Target, u8 Index)
{
  DamageAmount = RollDiceCounted((*FPD(TCharacter (*), Attacker)).WeaponAttacks[Index - 1], (*FPD(TCharacter (*), Attacker)).WeaponDamage[Index - 1]) + (*FPD(TCharacter (*), Attacker)).WeaponDamageBonus[Index - 1];
  if (DamageAmount < 0) {
    DamageAmount = 0;
  }
  if (IsBackstab(Attacker, Target)) {
    DamageAmount = DamageAmount * ((s16)(((s16)((u16)(s16)((u16)(*FPD(TCharacter (*), Attacker)).ClassLevels[6] >> BackstabLevelStep) >> BackstabLevelStep)) + BackstabMultiplierBase));
  }
  DamageKind = 0;
  RunAffectHooks(HookAttackerDamage, Attacker);
  RunAffectHooks(HookTargetDamage, Target);
}

/* ovl13:02F9. Shows the result of one melee attack in the combat window: it builds the message
     ('Attacks', ' -Backstabs-' or 'slays helpless' with '(from behind) ' when Kind is 1), names
     Target and, on a hit (Hit nonzero), adds 'Hitting for <Damage> point(s) of damage' (or 'with one
     cruel blow' for Kind 3), applies DamageDealt to Target through ApplyDamage and pages the text
     out (ShowPagedText); on a miss it adds 'and Misses'. DamageDealt is the damage actually dealt:
     any value above 0 also stops Target casting and makes it lose a pending spell ('lost a spell').
     Damage is only the number the message shows and can differ: the helpless auto-hit applies the
     target's current hit points plus 5 but displays 1. A Target still in the fight that went down
     shows 'goes down' (and 'and is Dying' at Status 5, else 'is killed' when Status is in
     StatusKilled), loses its death affects and runs the death hooks; one that dies leaves the map
     through RemoveCombatant. Called from ResolveCombatantAttacks (ovl13:1406) with the attacker, the
     target, the hit kind, the damage dealt, the number displayed and the hit flag. */
void ShowAttackResult(PCharacter Attacker, PCharacter Target, u8 Kind, u8 DamageDealt, u8 Damage, u8 Hit)
{
  u8 Row = 0;
  u8 Text[81] = {0};
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  u8 t5[256];
  u8 t6[256];
  s32 t7;
  switch (Kind) {
  case 2:
  {
    rtl_str_assign(Text, 80, S("\013-Backstabs-"));
    break;
  }
  case 3:
  {
    rtl_str_assign(Text, 80, S("\016slays helpless"));
    break;
  }
  default:
  {
    rtl_str_assign(Text, 80, S("\007Attacks"));
  }
  }
  ShowCharacterMessage(Attacker, Text, 10, 0);
  Row = 12;
  DrawCharacterName(Target, 23, Row, 0);
  Row++;
  if (Kind == 1) {
    rtl_str_assign(Text, 80, S("\016(from behind) "));
  } else {
    rtl_str_assign(Text, 80, S("\000"));
  }
  if (Hit != 0) {
    if (Kind == 3) {
      rtl_str_assign(Text, 80, S("\023with one cruel blow"));
    } else {
      rtl_str_assign(Text, 80, rtl_str_cat(t2, 3, (const u8 *const[]){Text, S("\014Hitting for "), ByteToText(t1, Damage)}));
      if (Damage == 1) {
        rtl_str_assign(Text, 80, rtl_str_cat(t3, 2, (const u8 *const[]){Text, S("\007 point ")}));
      } else {
        rtl_str_assign(Text, 80, rtl_str_cat(t4, 2, (const u8 *const[]){Text, S("\010 points ")}));
      }
      rtl_str_assign(Text, 80, rtl_str_cat(t5, 2, (const u8 *const[]){Text, S("\011of damage")}));
    }
    ApplyDamage(Target, DamageDealt);
  } else {
    rtl_str_assign(Text, 80, rtl_str_cat(t6, 2, (const u8 *const[]){Text, S("\012and Misses")}));
  }
  ShowPagedText(23, Row, 38, (s16)(Row + 3), 10, 1, Text);
  Row = GlyphRow + 1;
  if (DamageDealt > 0) {
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).CanCast = 0;
    if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).PendingSpell > 0) {
      DelayByGameSpeed();
      ShowCharacterMessage(Target, S("\014lost a spell"), 12, 1);
      ForgetSpell((*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).PendingSpell);
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).PendingSpell = 0;
    } else {
      DelayByGameSpeed();
    }
  } else {
    DelayByGameSpeed();
  }
  if ((*FPD(TCharacter (*), Target)).Flag10D == 0) {
    ShowCharacterMessage(Target, S("\011goes down"), Row, 0);
    Row += 2;
    if ((*FPD(TCharacter (*), Target)).Status == StatusDying) {
      DrawTextAt(23, Row, 10, S("\014and is Dying"));
    }
    if (t7 = (*FPD(TCharacter (*), Target)).Status, (t7 >= 6 && t7 <= 8)) {
      ShowCharacterMessage(Target, S("\011is killed"), Row, 0);
    }
    Row += 2;
    RemoveDeathAffects(Target);
    RunAffectHooks(HookGoesDown, Target);
    if ((*FPD(TCharacter (*), Target)).Flag10D == 0) {
      RemoveCombatant(Target);
    } else {
      DelayByGameSpeed();
    }
  }
  ClearCharacterMessage();
}

/* ovl13:0627. Lets every enemy next to Who that is watching (Combat^.B7) and not helpless strike
     back: for each combatant CollectEnemiesInRange(Who, 1) gathers, it puts the cursor on Who, clears
     the enemy's watch flag and runs the attack through NoteAttackBearing and PerformAttack. Does nothing for a
     character that is out of the fight (Flag10D 0). Called after a move (StepCombatant). */
void GuardedEnemiesAttack(PCharacter Who)
{
  u8 Count = 0;
  u8 I = 0;
  PCharacter Enemy = 0;
  u8 Done = 0;
  u8 t1;
  Count = CollectEnemiesInRange(Who, 1);
  t1 = Count;
  I = 1;
  if (I <= t1) for (;;) {
    if ((*FPD(TCharacter (*), Who)).Flag10D != 0) {
      Enemy = CombatantRecord[CombatantScanList[I] - 1];
      if ((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Enemy)).Combat)).B7 != 0)) && !IsHelpless(Enemy)) {
        MoveCombatCursor(CombatantX(Who), CombatantY(Who), 2, 8);
        (*FPD(TCombatant (*), (*FPD(TCharacter (*), Enemy)).Combat)).B7 = 0;
        NoteAttackBearing(Enemy, Who);
        PerformAttack(Enemy, Who, 0, 0, &Done);
      }
    }
    if (I == t1) break;
    I++;
  }
}

/* ovl13:0712. Moves Who one cell in direction Dir on the combat map: a straight step costs two half
     squares and a diagonal three, and one that costs more than Combat^.Moves leaves it at 0 and gives
     up. Otherwise it takes the cost off Moves, moves the combatant's cell in CombatantTable by the
     DirStepX/DirStepY offset of Dir, and redraws and rebuilds the occupancy. A quick-fighting
     character (Quick set) is drawn facing that way and, when the new cell is outside the view, has its
     cursor moved too. Then Who's BF and B12 are cleared, the move sound plays, the guarded enemies
     next to Who make their free attacks (GuardedEnemiesAttack) and, if Who is out of the fight or now
     helpless, its Moves become 0. Called by MoveCharacter (ovl08) and MoveStep (ovl09). */
void StepCombatant(PCharacter Who, u8 Dir)
{
  u8 Step = 0;
  u8 Idx = 0;
  s8 NewX = 0;
  s8 NewY = 0;
  s8 OldX = 0;
  s8 OldY = 0;
  if (Dir & 1) {
    Step = DiagonalStepCost;
  } else {
    Step = StraightStepCost;
  }
  if (Step > (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves) {
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves = 0;
    return;
  }
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves -= Step;
  Idx = CombatantIndex(Who);
  OldX = CombatantTable[Idx].X;
  OldY = CombatantTable[Idx].Y;
  NewX = OldX + DirStepX[Dir];
  NewY = OldY + DirStepY[Dir];
  Step = StepCursorMargin;
  if ((*FPD(TCharacter (*), Who)).Quick != 0) {
    Step = ViewCentre_OVL13;
    if (!IsInView((s16)(NewX - (*FPD(TCombatMap (*), CombatMap)).ViewX), (s16)(NewY - (*FPD(TCombatMap (*), CombatMap)).ViewY))) {
      MoveCombatCursor(OldX, OldY, 2, 8);
    }
  }
  RedrawGround(0, 0, Idx);
  CombatantTable[Idx].X = NewX;
  CombatantTable[Idx].Y = NewY;
  RebuildOccupancy();
  MoveCombatCursor(NewX, NewY, Step, 8);
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).BF = 0;
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).B12 = 0;
  PlaySound(SoundStep);
  GuardedEnemiesAttack(Who);
  if ((((*FPD(TCharacter (*), Who)).Flag10D == 0)) || IsHelpless(Who)) {
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves = 0;
  }
}

/* ovl13:08AC: retf 6: 6 bytes of parameters; 0 bytes of locals */
/* ovl13:08B2, PartingShots. The parting shots Who provokes by leaving melee: it copies the enemies adjacent to
     Who now (CollectEnemiesInRange(Who, 1) into CombatantScanList, ovl31) into Enemies, temporarily moves Who's
     cell in CombatantTable to Dir's neighbour to collect the enemies adjacent there, moves it back and
     clears the copied entries that are still adjacent, so Enemies keeps the enemies Who is leaving
     behind. For each of them, still in the fight (Flag10D set) and not IsHelpless, whom AttackTargetAllowed(Who)
     says may take the shot and who carries neither affect $4A nor $4B, it scans the directions
     IconSet+6..IconSet+10: while the combatant is due an initiative (Initiative above 0) or is not
     being drawn (BF 0) it attacks at once, otherwise only when InDirArc says Who is in the arc facing
     the scanned direction from the enemy. The enemy's unused attack slot (1, or 2 for a monster with
     Attacks 0) is marked in AttackSlots, stored in the enemy's Combat^.Pad4[4], and PerformAttack(Enemy,
     Who, 1, nil, CombatScratchFlag) makes the attack; the enemy's remembered Combat^.Target is restored after it.
     When the shot leaves Who still in the fight, Who's panel is redrawn. Called before the move by
     MoveCharacter (ovl08:09DF) and MoveStep (ovl09:07F2), so the shots happen as the combatant leaves.
     Globals: CombatantScanList, CombatantTable, DirStepX/DirStepY, CombatantRecord, CombatScratchFlag. */
void PartingShots(PCharacter Who, u8 Dir)
{
  u8 Enemies[12] = {0};
  farptr Affect = 0;
  u8 Found = 0;
  u8 DidAttack = 0;
  u8 Idx = 0;
  u8 Unused = 0;
  u8 Count = 0;
  u8 CountAfter = 0;
  u8 J = 0;
  u8 I = 0;
  u8 SlotIndex = 0;
  u8 Slot = 0;
  u8 K = 0;
  PCharacter Enemy = 0;
  PCharacter SavedTarget = 0;
  u8 t1;
  u8 t2;
  u8 t3;
  u8 t4;
  u8 t5;
  rtl_FillChar((void *)&Enemies, 12, 0);
  Idx = CombatantIndex(Who);
  Count = CollectEnemiesInRange(Who, 1);
  if (Count == 0) {
    return;
  }
  t1 = Count;
  I = 1;
  if (I <= t1) for (;;) {
    Enemies[I - 1] = CombatantScanList[I];
    if (I == t1) break;
    I++;
  }
  CombatantTable[Idx].X += DirStepX[Dir];
  CombatantTable[Idx].Y += DirStepY[Dir];
  CountAfter = CollectEnemiesInRange(Who, 1);
  CombatantTable[Idx].X -= DirStepX[Dir];
  CombatantTable[Idx].Y -= DirStepY[Dir];
  t2 = Count;
  I = 1;
  if (I <= t2) for (;;) {
    Found = 0;
    t3 = CountAfter;
    J = 1;
    if (J <= t3) for (;;) {
      if (CombatantScanList[J] == Enemies[I - 1]) {
        Found = 1;
      }
      if (J == t3) break;
      J++;
    }
    if (Found != 0) {
      Enemies[I - 1] = 0;
    }
    if (I == t2) break;
    I++;
  }
  t4 = Count;
  I = 1;
  if (I <= t4) for (;;) {
    if (Enemies[I - 1] > 0) {
      if ((*FPD(TCharacter (*), Who)).Flag10D != 0) {
        DidAttack = 0;
        Enemy = CombatantRecord[Enemies[I - 1] - 1];
        if (!IsHelpless(Enemy)) {
          if (AttackTargetAllowed(Enemy, Who)) {
            if (!HasAffect(Enemy, AffectBloodDrain, &Affect)) {
              if (!HasAffect(Enemy, AffectForcedAttack, &Affect)) {
                t5 = (s16)((*FPD(TCombatant (*), (*FPD(TCharacter (*), Enemy)).Combat)).IconSet + PartingShotLastOffset);
                K = (s16)((*FPD(TCombatant (*), (*FPD(TCharacter (*), Enemy)).Combat)).IconSet + PartingShotFirstOffset);
                if (K <= t5) for (;;) {
                  if (DidAttack == 0) {
                    if ((((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Enemy)).Combat)).Initiative > 0)) || (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Enemy)).Combat)).BF == 0)))) || InDirArc(CombatantX(Enemy), CombatantY(Enemy), CombatantX(Who), CombatantY(Who), (K % Directions))) {
                      Slot = 1;
                      if ((*FPD(TCharacter (*), Enemy)).Attacks == 0) {
                        Slot = 2;
                      }
                      SlotIndex = 1;
                      if (SlotIndex <= 2) for (;;) {
                        if ((*FPD(TCharacter (*), Enemy)).AttackSlots[SlotIndex - 1] > 0) {
                          Slot = SlotIndex;
                        }
                        if (SlotIndex == 2) break;
                        SlotIndex++;
                      }
                      if ((*FPD(TCharacter (*), Enemy)).AttackSlots[Slot - 1] == 0) {
                        (*FPD(TCharacter (*), Enemy)).AttackSlots[Slot - 1] = 1;
                      }
                      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Enemy)).Combat)).Pad4[0] = Slot;
                      SavedTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Enemy)).Combat)).Target;
                      PerformAttack(Enemy, Who, 1, 0, &CombatScratchFlag);
                      DidAttack = 1;
                      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Enemy)).Combat)).Target = SavedTarget;
                      if ((*FPD(TCharacter (*), Who)).Flag10D != 0) {
                        DrawCharacterPanel(Who);
                      }
                    }
                  }
                  if (K == t5) break;
                  K++;
                }
              }
            }
          }
        }
      }
    }
    if (I == t4) break;
    I++;
  }
}

/* ovl13:0C6A. Tries to flee the fight for Who (the Flee answer of the Move command, ovl08:0410,
     and a panicking off-map step, ovl09:0434): with no enemy at all within CollectEnemiesInRange's
     $FF it gets away; otherwise it gets away when FastestEnemyMovement(Who)'s initiative is below half Who's
     round Movement, or level with it and a RollDice(1, 2) coin comes up 1. Getting away drops the
     combatant from the fight with StatusFled ('Got Away'), a block flashes 'Escape is blocked'.
     Returns EndCombatTurn(Who), which ends the turn. Globals: none. */
u8 TryFlee(PCharacter Who)
{
  u8 Result = 0;
  u8 Escaped = 0;
  u8 Other = 0;
  u8 Moves = 0;
  Escaped = 0;
  if (CollectEnemiesInRange(Who, AllEnemiesRange) == 0) {
    Escaped = 1;
  } else {
    Moves = (s16)((u16)ComputeMovement(Who) >> 1);
    Other = FastestEnemyMovement(Who);
    if (Other < Moves) {
      Escaped = 1;
    } else if (Other == Moves) {
      if (RollDice(1, 2) == 1) {
        Escaped = 1;
      }
    }
  }
  if (Escaped) {
    DropCombatant(Who, StatusFled, S("\010Got Away"));
  } else {
    ShowFlashMessage(S("\021Escape is blocked"));
  }
  Result = EndCombatTurn(Who);
  return Result;
}

/* ovl13:0D23. Refreshes Who's readied-weapon attack count for the turn: it remembers the old
     AttackSlots[1] and seeds it from the character's Attacks (+$A1); with a ranged weapon readied
     (IsRangedWeapon and ChooseAttackItem passes) it takes the readied weapon's ItemTable attacks
     (at least 2) and remembers the aimed ammo item, else it keeps AttackSlots[1]. That attack count
     goes to HookedMoveOrAttacks, the movement/attack affect hook $12 may change it, and AttacksThisRound turns the
     changed byte into the attack count. A ranged aim caps the count at the ammo stack's Count.
     AttackSlots[1] is overwritten with that count when Who has not attacked yet this round
     (Combat^.Pad8 = 0), or the count is below the saved count, or Who has attacked (Pad8 <> 0) and
     the count is below twice the saved count and this is not a ranged aim (Ranged); otherwise the
     saved count stays. Combat^.Pad8 is the has-attacked-this-round flag: 0 at round start and 1 once
     ResolveCombatantAttacks runs (ovl13:143A). Called after StartCombatantRound and whenever the AI
     or the player readies an item (ovl08:0207, ovl09:0942). Globals: HookedMoveOrAttacks, HookRunning, ItemTable. */
void RefreshAttacks(PCharacter Who)
{
  u8 AttackCount = 0;
  u8 SavedAttacks = 0;
  u8 AmmoLimit = 0;
  u8 ReadyAttacks = 0;
  u8 Ranged = 0;
  farptr Aim = 0;
  Ranged = 0;
  SavedAttacks = (*FPD(TCharacter (*), Who)).AttackSlots[0];
  (*FPD(TCharacter (*), Who)).AttackSlots[0] = (*FPD(TCharacter (*), Who)).Attacks;
  if (IsRangedWeapon(Who) && ((ChooseAttackItem(Who, &Aim) != 0))) {
    Ranged = 1;
    ReadyAttacks = ItemTable[(*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[0])).ItemType].Attacks;
    if (ReadyAttacks < 2) {
      ReadyAttacks = 2;
    }
    HookedMoveOrAttacks = ReadyAttacks;
  } else {
    HookedMoveOrAttacks = (*FPD(TCharacter (*), Who)).AttackSlots[0];
  }
  HookRunning = 0;
  RunAffectHooks(HookComputeMovement, Who);
  AttackCount = AttacksThisRound(HookedMoveOrAttacks);
  if (Ranged && ((Aim != 0))) {
    AmmoLimit = 1;
    if (((Aim != 0)) && (((*FPD(TMenuLine (*), Aim)).Count > AmmoLimit))) {
      AmmoLimit = (*FPD(TMenuLine (*), Aim)).Count;
    }
    if (AmmoLimit < AttackCount) {
      AttackCount = AmmoLimit;
    }
  }
  if (((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Pad8 == 0)) || ((AttackCount < SavedAttacks))) || ((((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Pad8 != 0)) && ((AttackCount < (s16)(SavedAttacks * 2)))) && !Ranged))) {
    (*FPD(TCharacter (*), Who)).AttackSlots[0] = AttackCount;
  }
}

/* ovl13:0E52. Turns a doubled attack budget into the round's attack count: it copies
     DoubledAttacks, adds 1 when the combat round counter CombatRound is odd (combat rounds are
     zero-based, so the extra unit lands on even-numbered rounds), and halves the result. Called
     with the hook-modifiable byte HookedMoveOrAttacks (the character's Attacks, attacks per two rounds, or the
     readied weapon's halves); StartCombatantRound stores the result in AttackSlots[2] and
     RefreshAttacks uses it as the round's attack count. */
u8 AttacksThisRound(u8 DoubledAttacks)
{
  u8 Result = 0;
  u8 RoundAttacks = 0;
  RoundAttacks = DoubledAttacks;
  if (CombatRound & 1) {
    RoundAttacks++;
  }
  Result = (s16)((u16)RoundAttacks >> 1);
  return Result;
}

/* ovl13:0E82, SweepEnemies. The melee sweep: when the attacker Who still has attack slots left
     (AttackSlots[1] below Combat^.Pad4[5]), Target is a level-0 creature (HighestLevel 0) and
     Target stands in melee range (DistanceToTarget = 1), it sweeps the level-0 enemies around Who.
     It collects Who's adjacent enemies (CollectEnemiesInRange), counts the level-0 ones into Extra
     (remembering where Target is in the list), and when Extra still beats Who's attack slots
     (capped at Combat^.Pad4[5]) it shows 'sweeps', moves Target to the front of CombatantScanList and attacks
     each level-0 enemy in turn through NoteAttackBearing/PerformAttack, spending one attack per enemy
     (AttackSlots[1] := 1 and Dec(Extra)) until Extra runs out. Returns True when the sweep
     happened, so the caller ends the turn. Called by MeleeAttack (ovl08:0D45) and the AI
     (ovl09:0B3C). Globals: CombatantScanList (the adjacent-enemy list), CombatScratchFlag (the done flag e12 writes),
     CombatantRecord. */
u8 SweepEnemies(PCharacter Who, PCharacter Target)
{
  u8 Result = 0;
  u8 Count = 0;
  u8 Extra = 0;
  u8 I = 0;
  u8 SavedIndex = 0;
  PCharacter Enemy = 0;
  u8 t1;
  u8 t2;
  Result = 0;
  if ((*FPD(TCharacter (*), Who)).AttackSlots[0] < (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Pad4[1]) {
    if ((*FPD(TCharacter (*), Target)).HighestLevel == 0) {
      if (DistanceToTarget(Who, Target) == 1) {
        Count = CollectEnemiesInRange(Who, 1);
        Extra = 0;
        t1 = Count;
        I = 1;
        if (I <= t1) for (;;) {
          Enemy = CombatantRecord[CombatantScanList[I] - 1];
          if (Enemy == Target) {
            SavedIndex = I;
          }
          if ((*FPD(TCharacter (*), Enemy)).HighestLevel == 0) {
            Extra++;
          }
          if (I == t1) break;
          I++;
        }
        if (Extra > (*FPD(TCharacter (*), Who)).AttackSlots[0]) {
          if (Extra > (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Pad4[1]) {
            Extra = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Pad4[1];
          }
          ShowCharacterMessage(Who, S("\006sweeps"), 10, 1);
          Enemy = CombatantRecord[CombatantScanList[1] - 1];
          if (Enemy != Target) {
            CombatantScanList[SavedIndex] = CombatantScanList[1];
            CombatantScanList[1] = CombatantIndex(Target);
          }
          t2 = Count;
          I = 1;
          if (I <= t2) for (;;) {
            if (Extra > 0) {
              if ((*FPD(TCharacter (*), CombatantRecord[CombatantScanList[I] - 1])).HighestLevel == 0) {
                Enemy = CombatantRecord[CombatantScanList[I] - 1];
                NoteAttackBearing(Who, Enemy);
                (*FPD(TCharacter (*), Who)).AttackSlots[0] = 1;
                PerformAttack(Who, Enemy, 0, 0, &CombatScratchFlag);
                Extra--;
              }
            }
            if (I == t2) break;
            I++;
          }
          Result = 1;
        }
      }
    }
  }
  return Result;
}

/* ovl13:0FBF: frame not read */
/* ovl13:104E: retf 8: 8 bytes of parameters; 0 bytes of locals */
/* ovl13:1085, AttackTargetAllowed. The attack's target check: it runs the target's and the attacker's affect hooks
     and reports whether the attack may go ahead. A nil Target fails, and attacking oneself is
     always allowed. Otherwise HookVetoFlag is cleared and RunAffectHooks kind 1 runs on Target; when no
     hook rejected it, Who's remembered Combat^.Target is saved, replaced by Target and the attacker's
     hook kind 0 runs, then the old target is put back. The result is True exactly when HookVetoFlag ended
     0 (no hook vetoed). Called before an attack (ovl09 AiTurn, PartingShots, GazeCharmsTarget and ovl13's
     e17/e21/2FD3). Globals: HookVetoFlag. */
u8 AttackTargetAllowed(PCharacter Who, PCharacter Target)
{
  u8 Result = 0;
  PCharacter SavedTarget = 0;
  Result = 0;
  if (Target != 0) {
    if (Who == Target) {
      Result = 1;
    } else {
      HookVetoFlag = 0;
      RunAffectHooks(1, Target);
      if (HookVetoFlag == 0) {
        SavedTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
        (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target = Target;
        RunAffectHooks(0, Who);
        (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target = SavedTarget;
      }
      Result = (HookVetoFlag == 0);
    }
  }
  return Result;
}

/* ovl13:116A, TurnUndead. The Turn Undead action of a cleric Who: it shows 'turns undead...',
     marks Who's turn used (Combat^.Turned), then rolls how many undead the turn reaches
     (RollDice(1, 12)) and the d20 turning check. Who's cleric level (ClassLevels[0]) is mapped to a
     table band (1..8 itself, 9..13 to 9, else 10). While SelectTurnUndeadTarget hands over an undead in range and
     the reach and the stop flag allow it, the table TurnUndeadTable gives the number to beat for that
     monster's row (Pad74[TurnUndeadIndex] times 10 plus the band); a d20 at or above its absolute value turns it.
     A positive entry forces flight (Combat^.ForcedFlight, 'is turned'); a nonpositive one destroys
     it ('Is destroyed', RemoveCombatant, Status 8, out of the fight). Each result spends one of the
     six turns and one of the reach; when a destroyed undead used the last reach, a strictly negative
     table entry and turns still left give the reach back, while a positive entry (turned) does not
     and an entry of exactly 0 destroys without giving it back (QUIRK ovl13:1302: the test is
     Result < 0, though the Result comment calls every nonpositive entry destroying). When nothing was
     turned it flashes 'Nothing Happens...'. Finally it recounts the sides,
     stores EndCombatTurn's result in CombatScratchFlag and clears the message. Called by PlayerTurn's T case
     (ovl08:031A) and TryTurnUndead (ovl09:0203). Globals: TurnUndeadTable, CombatScratchFlag. */
void TurnUndead(PCharacter Who)
{
  u8 Roll20 = 0;
  u8 Remaining = 0;
  u8 TurnsLeft = 0;
  s8 Result_ = 0;
  u8 AnyTurned = 0;
  u8 Stop = 0;
  PCharacter Selected = 0;
  s8 LevelBand = 0;
  ShowCharacterMessage(Who, S("\017turns undead..."), 10, 0);
  ClearPromptLine();
  DelayByGameSpeed();
  AnyTurned = 0;
  Stop = 0;
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Turned = 1;
  TurnsLeft = MaxTurned;
  Remaining = RollDice(1, TurnCountDie);
  Roll20 = RollDice(1, TurnCheckDie);
  switch ((*FPD(TCharacter (*), Who)).ClassLevels[0]) {
  case 1:
  case 2:
  case 3:
  case 4:
  case 5:
  case 6:
  case 7:
  case 8:
  {
    LevelBand = (*FPD(TCharacter (*), Who)).ClassLevels[0];
    break;
  }
  case 9:
  case 10:
  case 11:
  case 12:
  case 13:
  {
    LevelBand = TurnBand9Low;
    break;
  }
  default:
  {
    LevelBand = TurnBandOther;
  }
  }
  while ((SelectTurnUndeadTarget(Who, (void *)&Selected) && ((Remaining > 0))) && ((Stop == 0))) {
    Result_ = TurnUndeadTable[(*FPD(TCharacter (*), Selected)).Pad74[2]][LevelBand];
    if (Roll20 >= rtl_abs(Result_)) {
      AnyTurned = 1;
      ShowCursorOn(Selected, ViewCentre_OVL13, 0);
      DrawCharacterPanel(Selected);
      if (Result_ > 0) {
        (*FPD(TCombatant (*), (*FPD(TCharacter (*), Selected)).Combat)).ForcedFlight = 1;
        ShowHitMessage(Selected, 1, S("\011is turned"));
      } else {
        ShowCharacterMessage(Selected, S("\014Is destroyed"), 10, 0);
        RemoveCombatant(Selected);
        (*FPD(TCharacter (*), Selected)).Status = StatusGone;
        (*FPD(TCharacter (*), Selected)).Flag10D = 0;
      }
      if (TurnsLeft > 0) {
        TurnsLeft--;
      }
      Remaining--;
      if ((((Remaining == 0)) && ((TurnsLeft > 0))) && ((Result_ < 0))) {
        Remaining++;
      }
      ClearCharacterMessage();
    } else {
      Stop = 1;
    }
  }
  if (AnyTurned == 0) {
    ShowFlashMessage(S("\022Nothing Happens..."));
  }
  RecountCombatSides();
  CombatScratchFlag = EndCombatTurn(Who);
  ClearCharacterMessage();
}

/* ovl13:11D8: retf 4: 4 bytes of parameters; 0 bytes of locals */
/* ovl13:1351. Picks the undead TurnUndead tries to turn next: of the enemies the range scan
     CollectEnemiesInRange(Who, AllEnemiesRange) lists it keeps the one with the lowest signed type row
     (TCharacter.Pad74[TurnUndeadIndex], above 0) whose combat state is not already forced to flee
     (Combat^.ForcedFlight 0), clearing Selected first, and returns whether one was found. Pad74[TurnUndeadIndex]
     is the monster row the Turn Undead table TurnUndeadTable is indexed by, so the scan picks the undead with
     the lowest row first. QUIRK ovl13:135B: Selected is untyped, so TurnUndead passes a
     PCharacter while ovl09 TryTurnUndead passes a 1-byte Done; the routine writes a 4-byte far pointer
     through it either way. Globals: CombatantScanList (the scan's combatant list), CombatantRecord. */
u8 SelectTurnUndeadTarget(farptr Who, void *Selected)
{
  u8 Result = 0;
  u8 Count = 0;
  u8 I = 0;
  s8 MinRow = 0;
  PCharacter Enemy = 0;
  u8 t1;
  MinRow = UndeadRowCeiling;
  (*(PCharacter (*))Selected) = 0;
  Count = CollectEnemiesInRange(Who, AllEnemiesRange);
  Result = 0;
  t1 = Count;
  I = 1;
  if (I <= t1) for (;;) {
    Enemy = CombatantRecord[CombatantScanList[I] - 1];
    if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Enemy)).Combat)).ForcedFlight == 0) {
      if ((*FPD(TCharacter (*), Enemy)).Pad74[2] > 0) {
        if ((*FPD(TCharacter (*), Enemy)).Pad74[2] < MinRow) {
          MinRow = (*FPD(TCharacter (*), Enemy)).Pad74[2];
          (*(PCharacter (*))Selected) = Enemy;
          Result = 1;
        }
      }
    }
    if (I == t1) break;
    I++;
  }
  return Result;
}

/* ovl13:1406. Resolves all of one combatant's melee attacks for its turn, the work PerformAttack wraps
     (this routine covers 1406..17F6: the map's entries 14A1, 1583, 1713 and 1758 lie inside it):
     it clears the attack-slot counters (AttackSlotRolls[1..2], AttackSlotCounts[1..2]) and the damage, marks the
     attacker's Combat^.Pad8, then either takes the helpless auto-hit (no roll, ShowAttackResult kind 3
     passing the target's current hit points (HpCurrent) plus 5 as the damage dealt and 1 as the number
     displayed, ClearAttackerAffect, both attack slots cleared) or, against a target
     that fights back, switches the readied weapon to its large-foe dice when the target is big
     (CombatSize above $80 or a footprint kind above 1), recomputes the target's combat values, runs hook
     $B on it, works out the needed to-hit roll and the hit kind (a from-behind hit uses the RearArmourClassValue pair
     and kind 1, a backstab kind 2), then walks the attacker's attack slots downward: each slot with
     attacks left fires once, RollToHit (or a helpless target) lands it, RollAttackDamage rolls the
     damage, ShowAttackResult shows it and the death hook runs; when nothing landed a miss is shown.
     Done is left nonzero when the turn ends (EndCombatTurn) and zero while another attack remains.
     QUIRK ovl13:1733: the damage dealt and the number displayed are both DamageAmount (the miss at
     ovl13:1797 passes 0 for both, the helpless hit passes HpCurrent + 5 and 1). Called by
     PerformAttack (ovl13:19D6). Globals: AttackRoll, AttackSlotCounts, DamageAmount, SoundNoAction, SoundAttackMissed. */
void ResolveCombatantAttacks(PCharacter Attacker, PCharacter Target, u8 AttackKind, u8 (*Done))
{
  TItemRow Item = {0};
  u8 Landed = 0;
  u8 TargetDown = 0;
  u8 Behind = 0;
  u8 NeededRoll = 0;
  u8 SlotIndex = 0;
  u8 SlotCount = 0;
  u8 HitKind = 0;
  s8 RearAttack = 0;
  Behind = AttackKind;
  (*Done) = 0;
  AttackSlotRolls[1] = 0;
  AttackSlotRolls[2] = 0;
  AttackSlotCounts[1] = 0;
  AttackSlotCounts[2] = 0;
  Landed = 0;
  TargetDown = 0;
  DamageAmount = 0;
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Attacker)).Combat)).Pad8 = 1;
  if (IsHelpless(Target)) {
    PlaySound(SoundNoAction);
    while ((*FPD(TCharacter (*), Attacker)).AttackSlots[(*FPD(TCombatant (*), (*FPD(TCharacter (*), Attacker)).Combat)).Pad4[0] - 1] == 0) {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Attacker)).Combat)).Pad4[0]--;
    }
    AttackSlotCounts[(*FPD(TCombatant (*), (*FPD(TCharacter (*), Attacker)).Combat)).Pad4[0]]++;
    ShowAttackResult(Attacker, Target, 3, (s16)((*FPD(TCharacter (*), Target)).HpCurrent + 5), 1, 1);
    ClearAttackerAffect(Attacker);
    SlotIndex = 1;
    if (SlotIndex <= 2) for (;;) {
      (*FPD(TCharacter (*), Attacker)).AttackSlots[SlotIndex - 1] = 0;
      if (SlotIndex == 2) break;
      SlotIndex++;
    }
    Landed = 1;
    (*Done) = 1;
  } else {
    if ((((*FPD(TCharacter (*), Attacker)).SlotItems[0] != 0)) && (((((*FPD(TCharacter (*), Target)).CombatSize > LargeTargetSize)) || (((((*FPD(TCharacter (*), Target)).CombatSize & FootprintKindMask)) > LargeFootprintKind))))) {
      Item = ItemTable[(*FPD(TMenuLine (*), (*FPD(TCharacter (*), Attacker)).SlotItems[0])).ItemType];
      (*FPD(TCharacter (*), Attacker)).WeaponAttacks[0] = Item.DiceCountLarge;
      (*FPD(TCharacter (*), Attacker)).WeaponDamage[0] = Item.DiceSizeLarge;
      (*FPD(TCharacter (*), Attacker)).WeaponDamageBonus[0] = ((*FPD(TCharacter (*), Attacker)).WeaponDamageBonus[0] - Item.BonusNormal) + Item.BonusLarge;
    }
    RecalcCombatValues(Target);
    RunAffectHooks(HookAttackSetup, Target);
    RearAttack = 0;
    if (IsBackstab(Attacker, Target)) {
      NeededRoll = (*FPD(TCharacter (*), Target)).RearArmourClassValue - 2;
    } else {
      if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).BF > 1) {
        if (BearingTo(Attacker, Target) == (*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).IconSet) {
          if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).B12 > 4) {
            Behind = 1;
          }
        }
      }
      if (Behind != 0) {
        RearAttack = 1;
      }
      NeededRoll = (*FPD(TResistView (*), Target)).Pair[RearAttack];
    }
    AddRangePenalty(Attacker, Target, &NeededRoll);
    HitKind = 0;
    if (Behind != 0) {
      HitKind = 1;
    }
    if (IsBackstab(Attacker, Target)) {
      HitKind = 2;
    }
    SlotCount = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Attacker)).Combat)).Pad4[0];
    SlotIndex = SlotCount;
    if (SlotIndex >= 1) for (;;) {
      while ((((*FPD(TCharacter (*), Attacker)).AttackSlots[SlotIndex - 1] > 0)) && ((TargetDown == 0))) {
        (*FPD(TCharacter (*), Attacker)).AttackSlots[SlotIndex - 1]--;
        (*FPD(TCombatant (*), (*FPD(TCharacter (*), Attacker)).Combat)).Pad4[0] = SlotIndex;
        AttackSlotCounts[SlotIndex]++;
        if (RollToHit(Attacker, Target, NeededRoll) || IsHelpless(Target)) {
          AttackSlotRolls[SlotIndex]++;
          PlaySound(SoundNoAction);
          Landed = 1;
          RollAttackDamage(Attacker, Target, SlotIndex);
          ShowAttackResult(Attacker, Target, HitKind, DamageAmount, DamageAmount, 1);
          if ((*FPD(TCharacter (*), Target)).Flag10D != 0) {
            RunAffectHooks((s16)(SlotIndex + 1), Attacker);
          }
          if ((*FPD(TCharacter (*), Target)).Flag10D == 0) {
            TargetDown = 1;
          }
        }
      }
      if (SlotIndex == 1) break;
      SlotIndex--;
    }
    if (Landed == 0) {
      PlaySound(SoundAttackMissed);
      ShowAttackResult(Attacker, Target, HitKind, 0, 0, 0);
    }
    (*Done) = 1;
    SlotIndex = 1;
    if (SlotIndex <= 2) for (;;) {
      if ((*FPD(TCharacter (*), Attacker)).AttackSlots[SlotIndex - 1] > 0) {
        (*Done) = 0;
      }
      if (SlotIndex == 2) break;
      SlotIndex++;
    }
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Attacker)).Combat)).Pad4[1] = 0;
  }
  if ((*Done) != 0) {
    (*Done) = EndCombatTurn(Attacker);
  }
}

/* ovl13:17F6. Notes the attack Target is about to take from Attacker: Target's attack count Combat^.BF
     is raised and Combat^.B12 gains the angular error between Target's facing (Combat^.IconSet) and
     the bearing from Target to Attacker (BearingTo), wrapped into 0..4, modulo 8. Called with the
     target as the second argument just before PerformAttack resolves the attack (ovl08 MeleeAttack,
     ovl09 AiTurn, GuardedEnemiesAttack, SweepEnemies). */
void NoteAttackBearing(PCharacter Attacker, PCharacter Target)
{
  u8 Error = 0;
  u8 Bearing = 0;
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).BF++;
  Bearing = BearingTo(Target, Attacker);
  Error = (((s16)((Bearing - (*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).IconSet) + 8)) % 8);
  if (Error > 4) {
    Error = 8 - Error;
  }
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).B12 = (((s16)((*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).B12 + Error)) % 8);
}

/* ovl13:1884. Carries out one combat action of Who against Target, the wrapper around
     ResolveCombatantAttacks (this routine covers 1884..1B1E; the map's entries inside it were merged):
     it turns Target to face Who (once, while Target's attack count Combat^.BF is below TargetTurnLimit
     and AttackKind is 0), turns Who to face Target (SetCombatantIcon, mirror) and redraws Who's panel,
     remembers Target in Who^.Combat^.Target, pauses, lets ShowAttackAnimation play the aimed item AimedItem
     and a BowItemKind readied item, then, when Who has any attack slot left, saves SelectedCharacter,
     makes Who the selected character and resolves the attack (AttackKind is the attack kind, Done the
     turn-done flag), spends one round of the aimed ammo (Count drops by AttackSlotCounts[1]; an emptied stack
     whose ammo can be thrown is copied into a new menu line linked into PooledItems, recorded in LootListBoundary and
     removed from the inventory, else it is just removed), recomputes Who's combat values and restores
     SelectedCharacter. Ends the turn when Done is set and re-lays Who's icon when it is in view. Called
     by MeleeAttack (ovl08), AiTurn (ovl09), GuardedEnemiesAttack, PartingShots and SweepEnemies.
     QUIRK ovl13:198D: Who^.SlotItems[0] is read without a nil test. Globals: SelectedCharacter,
     PooledItems, LootListBoundary, AttackSlotCounts. */
void PerformAttack(PCharacter Who, PCharacter Target, u8 AttackKind, farptr AimedItem, u8 (*Done))
{
  PMenuLine NewItem = 0;
  PCharacter SavedSelection = 0;
  u8 Bearing = 0;
  if ((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).BF < PerformAttack_TargetTurnLimit)) && ((AttackKind == 0))) {
    Bearing = BearingTo(Target, Who);
    if (IsCombatantInView(Target, 0)) {
      SetCombatantIcon(Target, Bearing, 0, 0);
    } else {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).IconSet = Bearing;
    }
  }
  Bearing = BearingTo(Who, Target);
  DrawCharacterPanel(Who);
  SetCombatantIcon(Who, Bearing, 1, 0);
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target = Target;
  rtl_Delay(PerformAttack_AttackPause);
  if (AimedItem != 0) {
    ShowAttackAnimation(Who, Target, AimedItem);
  }
  if ((*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[0])).ItemType == PerformAttack_BowItemKind) {
    ShowAttackAnimation(Who, Target, (*FPD(TCharacter (*), Who)).SlotItems[0]);
  }
  (*Done) = 1;
  if ((((*FPD(TCharacter (*), Who)).AttackSlots[0] > 0)) || (((*FPD(TCharacter (*), Who)).AttackSlots[1] > 0))) {
    SavedSelection = SelectedCharacter;
    SelectedCharacter = Who;
    ResolveCombatantAttacks(Who, Target, AttackKind, &(*Done));
    if (AimedItem != 0) {
      if ((*FPD(TMenuLine (*), AimedItem)).Count > 0) {
        (*FPD(TMenuLine (*), AimedItem)).Count -= AttackSlotCounts[1];
      }
      if ((*FPD(TMenuLine (*), AimedItem)).Count == 0) {
        if (RangedWeaponCanMelee(Who) && (((*FPD(TMenuLine (*), AimedItem)).Affects[2] != PerformAttack_NoLootCopyAffect))) {
          NewItem = rtl_getmem(63);
          rtl_Move((void *)&(*FPD(TMenuLine (*), AimedItem)), (void *)&(*FPD(TMenuLine (*), NewItem)), 63);
          (*FPD(TMenuLine (*), NewItem)).Next = PooledItems;
          PooledItems = NewItem;
          (*FPD(TMenuLine (*), NewItem)).Readied = 0;
          RemoveInventoryItem(Who, AimedItem);
          LootListBoundary = NewItem;
        } else {
          RemoveInventoryItem(Who, AimedItem);
        }
      }
    }
    RecalcCombatValues(Who);
    SelectedCharacter = SavedSelection;
  }
  if ((*Done) != 0) {
    (*Done) = EndCombatTurn(Who);
  }
  if (IsCombatantInView(Who, 0)) {
    SetCombatantIcon(Who, (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).IconSet, 1, 1);
    SetCombatantIcon(Who, (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).IconSet, 0, 0);
  }
}

/* ovl13:1B1E. Adds the attack's range penalty to NeededRoll, the to-hit value RollToHit must reach:
     it takes the distance to Target (DistanceToTarget) and, for a ranged weapon (IsRangedWeapon),
     reduces it by the readied weapon's range band ItemTable[SlotItems[0]^.ItemType].Range div 3
     ((Range - 1) div 3, at least 0). While the distance then still exceeds the band it takes the band
     off the distance and adds 2, then 3 to NeededRoll (two bands at most). A melee weapon's band is the
     distance itself, so no penalty. Called by ResolveCombatantAttacks after the resistance/RearArmourClassValue
     NeededRoll. Globals: ItemTable. */
void AddRangePenalty(PCharacter Attacker, PCharacter Target, u8 (*NeededRoll))
{
  s8 RangeBand = 0;
  s8 Distance = 0;
  Distance = DistanceToTarget(Attacker, Target);
  if (IsRangedWeapon(Attacker)) {
    RangeBand = (((s16)(ItemTable[(*FPD(TMenuLine (*), (*FPD(TCharacter (*), Attacker)).SlotItems[0])).ItemType].Range - 1)) / 3);
  } else {
    RangeBand = Distance;
  }
  if ((s16)(Distance - RangeBand) > 0) {
    Distance = Distance - RangeBand;
    (*NeededRoll) = (*NeededRoll) + 2;
  }
  if ((s16)(Distance - RangeBand) > 0) {
    Distance = Distance - RangeBand;
    (*NeededRoll) = (*NeededRoll) + 3;
  }
}

/* ovl13:1BF8. The healing-target pick: it hands over the combatant a cure (spell 3) is aimed at,
     the routine FindSpellTarget and ovl09 SpellAccepted use. It walks the nine directions Dir 0..8
     from Who (Dir 8 is Who's own cell, DirStepX[8]/DirStepY[8] are 0,0), maps each with GetMapCell,
     and for an occupied cell keeps the SAME-side combatant (Side = Who^.Side) whose current hit
     points (HpCurrent) are below its maximum (HpMax) when it is the most wounded so far (BestHp) or,
     for Who's own cell (the occupant is Who), when it is below half its maximum; a body cell (tile
     BodyTile) with no occupant makes it walk BodyTable for a body standing on the scanned cell whose
     owner is not yet dead (Status not in StatusKilled, 6..8). It then hands over the chosen
     combatant: SelectedWho when an occupant was picked (BestHp below ChosenHpLimit, 8) or no body was
     found, else the body's owner, and returns whether one was stored. Writes the 4-byte pointer
     through the untyped var Selected, so a caller passing a 1-byte Done (ovl09 SpellAccepted) has the
     rest clobbered. QUIRK ovl13:1DBB: BodyTable[FoundIndex] is read with FoundIndex 0 when nothing
     was chosen, so the else reads the 7 bytes before BodyTable. Globals: CombatantRecord, BodyTable,
     BodyCount. */
u8 FindNearbyTarget(PCharacter Who, void *Selected)
{
  u8 Result = 0;
  PCharacter SelectedWho = 0;
  s8 CellX = 0;
  s8 CellY = 0;
  u8 FoundIndex = 0;
  u8 BestHp = 0;
  u8 Dir = 0;
  u8 BodyIndex = 0;
  u8 Occupant = 0;
  u8 Tile = 0;
  u8 t1;
  s32 t2;
  SelectedWho = 0;
  FoundIndex = 0;
  BestHp = 0xFF;
  Dir = 0;
  if (Dir <= 8) for (;;) {
    CellX = CombatantX(Who) + DirStepX[Dir];
    CellY = CombatantY(Who) + DirStepY[Dir];
    GetMapCell(CellX, CellY, &Occupant, &Tile);
    if (Occupant > 0) {
      (*(PCharacter (*))Selected) = CombatantRecord[Occupant - 1];
      if ((((*FPD(TCharacter (*), (*(PCharacter (*))Selected))).Side == (*FPD(TCharacter (*), Who)).Side)) && (((*FPD(TCharacter (*), (*(PCharacter (*))Selected))).HpCurrent < (*FPD(TCharacter (*), (*(PCharacter (*))Selected))).HpMax))) {
        if ((((*FPD(TCharacter (*), (*(PCharacter (*))Selected))).HpCurrent < BestHp)) || (((((*(PCharacter (*))Selected) == Who)) && (((*FPD(TCharacter (*), (*(PCharacter (*))Selected))).HpCurrent < (s16)((u16)(*FPD(TCharacter (*), (*(PCharacter (*))Selected))).HpMax >> 1)))))) {
          SelectedWho = (*(PCharacter (*))Selected);
          BestHp = (*FPD(TCharacter (*), (*(PCharacter (*))Selected))).HpCurrent;
        }
      }
    } else if (Tile == BodyTile) {
      t1 = BodyCount;
      BodyIndex = 1;
      if (BodyIndex <= t1) for (;;) {
        if (BodyTable[BodyIndex - 1].Who != 0) {
          if (!((t2 = (*FPD(TCharacter (*), BodyTable[BodyIndex - 1].Who)).Status, (t2 >= 6 && t2 <= 8)))) {
            if (((BodyTable[BodyIndex - 1].X == CellX)) && ((BodyTable[BodyIndex - 1].Y == CellY))) {
              FoundIndex = BodyIndex;
            }
          }
        }
        if (BodyIndex == t1) break;
        BodyIndex++;
      }
    }
    if (Dir == 8) break;
    Dir++;
  }
  if (((BestHp < FindNearbyTarget_ChosenHpLimit)) || ((FoundIndex == 0))) {
    (*(PCharacter (*))Selected) = SelectedWho;
  } else {
    (*(PCharacter (*))Selected) = BodyTable[FoundIndex - 1].Who;
  }
  if ((*(PCharacter (*))Selected) != 0) {
    Result = 1;
  } else {
    Result = 0;
  }
  return Result;
}

/* ovl13:1E16. Finds a target for the spell Spell while it is aimed, and hands it over through the
     untyped var Target (a TSpellTarget: the combatant and its cell).
       - Automatic = 0 lets RunAimTargets pick (the player's cursor); else the spell row's own data picks it:
         when the spell's range/targeting mode, the row's byte +$E (PadB[$E]), is 0 the spell targets
         its caster (and FindNearbyTarget is asked when Spell is 3); otherwise up to 20 times
         ChooseCombatTarget offers the next aim (SpellAreaSize(Spell) is the
         spell's range) and the aim is accepted while the spell's area (ScanTargets with the row's +$F
         byte as the line budget) holds only the caster's enemies and the target is either not helpless or
         the row's AffectId (+$A) is not one of HelplessAffects.
     Returns True when a target was stored, and then leaves its cell in SpellAimX/SpellAimY; False clears the
     seven bytes of Target. AimFlag is passed to RunAimTargets as its third flag (1 for the spell rows whose
     Pad2[6] nibble is 8..14). Globals: SelectedCharacter, SpellAimX, SpellAimY. */
u8 FindSpellTarget(u8 Spell, u8 Automatic, u8 AimFlag, TSpellTarget (*Target))
{
  u8 Result = 0;
  u8 Chosen = 0;
  u8 Valid = 0;
  PCharacter SavedTarget = 0;
  u8 I = 0;
  u8 Attempts = 0;
  u8 t1;
  Chosen = 0;
  if (Automatic == 0) {
    RunAimTargets(SelectedCharacter, SpellAreaSize(Spell), 0, AimFlag, &Chosen, (void *)&(*Target));
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), SelectedCharacter)).Combat)).Target = (*Target).Who;
  } else {
    if (SpellTable[Spell].PadB[3] == 0) {
      (*Target).Who = SelectedCharacter;
      if (((Spell != 3)) || FindNearbyTarget(SelectedCharacter, (void *)&(*Target))) {
        (*Target).X = CombatantX((*Target).Who);
        (*Target).Y = CombatantY((*Target).Who);
        Chosen = 1;
      }
    } else {
      Attempts = 20;
      while (((Attempts > 0)) && ((Chosen == 0))) {
        Valid = 1;
        if (ChooseCombatTarget(SelectedCharacter, SpellAreaSize(Spell), 0, 1)) {
          SavedTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), SelectedCharacter)).Combat)).Target;
          if (SpellTable[Spell].PadB[4] > 0) {
            ScanTargets(CombatantX(SavedTarget), CombatantY(SavedTarget), SpellTable[Spell].PadB[4], 0xFF, 1, CombatMap);
            t1 = SortEntries[0].Val_;
            I = 1;
            if (I <= t1) for (;;) {
              if ((*FPD(TCharacter (*), CombatantRecord[SortEntries[I].Head - 1])).Side != OpposingSide(SelectedCharacter)) {
                Valid = 0;
              }
              if (I == t1) break;
              I++;
            }
          }
          if (IsHelpless(SavedTarget)) {
            I = 1;
            if (I <= 4) for (;;) {
              if (SpellTable[Spell].AffectId == HelplessAffects[I]) {
                Valid = 0;
              }
              if (I == 4) break;
              I++;
            }
          }
          if (Valid != 0) {
            (*Target).Who = (*FPD(TCombatant (*), (*FPD(TCharacter (*), SelectedCharacter)).Combat)).Target;
            (*Target).X = CombatantX((*Target).Who);
            (*Target).Y = CombatantY((*Target).Who);
            Chosen = 1;
          }
        }
        Attempts--;
      }
    }
  }
  if (Chosen != 0) {
    Result = 1;
    SpellAimX = (*Target).X;
    SpellAimY = (*Target).Y;
  } else {
    Result = 0;
    rtl_FillChar((void *)&(*Target), 7, 0);
  }
  return Result;
}

/* ovl13:20C3, SelectSpellTargets. The spell window RunCombat sets SpellPickerPointer to (ovl08:0088): it fills the target
     list SpellTargets for the spell Spell (1-based, count SpellTargetCount) and leaves the chosen target's cell in
     SpellAimX/SpellAimY. The spell row's byte +6 (Pad2[6]) switches:
       - nibble 0: the caster itself is the only target (FirstSpellTarget := SelectedCharacter);
       - nibble $F: FindSpellTarget aims (AimFlag 0); an aim on some combatant (Combat^.Target set) is
         used alone, an empty one scans the spell's area (ScanTargets, line budget (Pad2[6] and $F) shr 4,
         which is always 0 here: QUIRK ovl13:2198) and copies every found combatant into SpellTargets;
       - nibble 8..14: FindSpellTarget aims (AimFlag 1) and the spell's area (line budget Pad2[6] and 7)
         always fills SpellTargets;
       - any other nibble: up to (Pad2[6] and 3) + 1 aiming passes collect that many distinct targets;
         a target already in the list only flashes 'Already been targeted' when Automatic is 0.
     Done is set to 0 when nothing was collected (or an aim was refused). SpellAppliedToArea is set to 1 once the
     area scan filled the list. Globals: SelectedCharacter, SpellTargets, SpellTargetCount, SpellAimX, SpellAimY,
     SpellAppliedToArea. */
void SelectSpellTargets(u8 Spell, u8 Automatic, u8 (*Done))
{
  u8 TargetsLeft = 0;
  u8 Count = 0;
  u8 J = 0;
  TSpellTarget Target = {0};
  u8 Duplicate = 0;
  u8 t1;
  u8 t2;
  u8 t3;
  (*Done) = 1;
  SpellTargetCount = 0;
  SpellAppliedToArea = 0;
  SpellAimX = CombatantX(SelectedCharacter);
  SpellAimY = CombatantY(SelectedCharacter);
  switch ((SpellTable[Spell].Pad2[4] & 0xF)) {
  case 0:
  {
    FirstSpellTarget = SelectedCharacter;
    SpellTargetCount = 1;
    break;
  }
  case 0xF:
  {
    if (FindSpellTarget(Spell, Automatic, 0, &Target)) {
      if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), SelectedCharacter)).Combat)).Target != 0) {
        FirstSpellTarget = (*FPD(TCombatant (*), (*FPD(TCharacter (*), SelectedCharacter)).Combat)).Target;
        SpellTargetCount = 1;
      } else {
        /* QUIRK ovl13:2198: the line budget (Pad2[6] and $F) shr 4 is always 0 here, because
           this branch is taken only when the low nibble is $F; an area spell aimed at nothing
           with Combat^.Target nil scans only the centre cell. */
        ScanTargets(SpellAimX, SpellAimY, (s16)((u16)((SpellTable[Spell].Pad2[4] & 0xF)) >> 4), 0xFF, 1, CombatMap);
        t1 = SortEntries[0].Val_;
        Count = 1;
        if (Count <= t1) for (;;) {
          SpellTargets[Count] = CombatantRecord[SortEntries[Count].Head - 1];
          if (Count == t1) break;
          Count++;
        }
        SpellTargetCount = SortEntries[0].Val_;
        SpellAppliedToArea = 1;
      }
    } else {
      (*Done) = 0;
    }
    break;
  }
  case 8:
  case 9:
  case 10:
  case 11:
  case 12:
  case 13:
  case 14:
  {
    if (FindSpellTarget(Spell, Automatic, 1, &Target)) {
      ScanTargets(SpellAimX, SpellAimY, (SpellTable[Spell].Pad2[4] & 7), 0xFF, 1, CombatMap);
      t2 = SortEntries[0].Val_;
      Count = 1;
      if (Count <= t2) for (;;) {
        SpellTargets[Count] = CombatantRecord[SortEntries[Count].Head - 1];
        if (Count == t2) break;
        Count++;
      }
      SpellTargetCount = SortEntries[0].Val_;
      SpellAppliedToArea = 1;
    } else {
      (*Done) = 0;
    }
    break;
  }
  default:
  {
    {
      TargetsLeft = ((SpellTable[Spell].Pad2[4] & 3)) + 1;
      Count = 0;
      while (TargetsLeft > 0) {
        if (FindSpellTarget(Spell, Automatic, 0, &Target)) {
          Duplicate = 0;
          t3 = Count;
          J = 1;
          if (J <= t3) for (;;) {
            if (SpellTargets[J] == Target.Who) {
              Duplicate = 1;
            }
            if (J == t3) break;
            J++;
          }
          if (Duplicate == 0) {
            Count++;
            SpellTargets[Count] = Target.Who;
            TargetsLeft--;
          } else if (Automatic == 0) {
            ShowFlashMessage(S("\025Already been targeted"));
          } else {
            TargetsLeft--;
          }
          RedrawMapCell(CombatantX(SpellTargets[Count]), CombatantY(SpellTargets[Count]));
        } else {
          TargetsLeft--;
        }
      }
      SpellTargetCount = Count;
      if (Count == 0) {
        (*Done) = 0;
      }
    }
  }
  }
}

/* ovl13:2414. The C Cast command and the AI's memorized-spell cast: SpellNumber is the spell to
     cast (0 opens ChooseSpellFromList at once, the list position starting at NoChoice), NoRedraw is
     nonzero when the caller is the computer (the combat screen, cursor and panel are then not
     redrawn). A spell whose
     SpellTable byte +$B is 0 cannot be cast in combat ('Camp Only Spell'). When the spell's byte +$C
     div 3 (its casting delay) is 0 the spell goes off at once through CastChosenSpell and the turn ends
     (EndCombatTurn); otherwise the caster 'Begins Casting' (Done set), the spell is remembered in
     Combat^.PendingSpell and the delay is taken off Combat^.Initiative (at least 1), so the spell
     finishes on the caster's next turn (PlayerTurn ovl08:031A, ovl09 CastMemorizedSpell).
     QUIRK ovl13:2417: the byte local after Spell is declared and never read; it shifts every later
     local down one byte and is what makes the frame $1A. Globals: SelectedCharacter. */
void CastCombatSpell(u8 SpellNumber, u8 NoRedraw, u8 (*Done))
{
  u8 Spell = 0;
  u8 Unused = 0;
  u8 CastTime = 0;
  u16 Choice = 0;
  u8 Listed = 0;
  PCharacter ChosenChar = 0;
  ChosenChar = SelectedCharacter;
  Listed = 1;
  Choice = NoChoice;
  (*Done) = 0;
  Spell = SpellNumber;
  if (Spell == 0) {
    Spell = ChooseSpellFromList(0, 1, &Choice, &Listed);
  }
  if (Spell > 0) {
    if (SpellTable[Spell].PadB[0] == 0) {
      ShowFlashMessage(S("\017Camp Only Spell"));
      Spell = 0;
    }
  }
  if (NoRedraw == 0) {
    DrawCombatScreen();
    ShowCursorOn(ChosenChar, 3, 1);
    DrawCharacterPanel(ChosenChar);
  }
  if (Spell <= 0) {
    return;
  }
  CastTime = (SpellTable[Spell].PadB[1] / 3);
  if (CastTime == 0) {
    CastChosenSpell(Spell, NoRedraw, 1, &(*Done));
    (*Done) = EndCombatTurn(ChosenChar);
  } else {
    (*Done) = 1;
    ShowCharacterMessage(ChosenChar, S("\016Begins Casting"), CombatMessageRow, 1);
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), ChosenChar)).Combat)).PendingSpell = Spell;
    if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), ChosenChar)).Combat)).Initiative > CastTime) {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), ChosenChar)).Combat)).Initiative -= CastTime;
    } else {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), ChosenChar)).Combat)).Initiative = 1;
    }
  }
}

/* ovl13:2432: retf 8: 8 bytes of parameters; 0 bytes of locals */
/* ovl13:2574. Reports whether Who's attack on Target is a thief's backstab: Who's thief level
     (ClassLevels[6]) must be above 0 and Who must carry no slot-2 item but the one type below, with a
     backstab-capable readied weapon (SlotItems[0] empty or an item kind in the set below); then Target
     must have been attacked (Combat^.BF above 1) and must face Who (the direction from Who to Target,
     BearingTo, equals Target's Combat^.IconSet). The item kinds are read from ItemTable: 7 and 8 and
     $23..$25 are one-handed weapons, $22 and $26 are two-handed (excluded). RollAttackDamage applies
     the thief-level damage multiplier and ResolveCombatantAttacks uses it for the RearArmourClassValue - 2 to-hit and
     attack kind 2. Globals: none. */
u8 IsBackstab(PCharacter Who, PCharacter Target)
{
  u8 Result = 0;
  PItem Weapon = 0;
  PItem SlotTwo = 0;
  u8 ItemKind = 0;
  u8 FromBehind = 0;
  FromBehind = 0;
  Weapon = (*FPD(TCharacter (*), Who)).SlotItems[0];
  if (Weapon != 0) {
    ItemKind = (*FPD(TMenuLine (*), Weapon)).ItemType;
  }
  SlotTwo = (*FPD(TCharacter (*), Who)).SlotItems[2];
  if ((*FPD(TCharacter (*), Who)).ClassLevels[6] > 0) {
    if (((SlotTwo == 0)) || (((*FPD(TMenuLine (*), SlotTwo)).ItemType == IsBackstab_BackstabSlotTwoKind))) {
      if (((((Weapon == 0)) || ((ItemKind == IsBackstab_BackstabWeaponKind1))) || ((ItemKind == IsBackstab_BackstabWeaponKind2))) || ((((ItemKind > IsBackstab_BackstabWeaponKindLow)) && ((ItemKind < IsBackstab_BackstabWeaponKindHigh))))) {
        FromBehind = 1;
      }
    }
  }
  if ((((FromBehind != 0)) && (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).BF > 1))) && ((BearingTo(Who, Target) == (*FPD(TCombatant (*), (*FPD(TCharacter (*), Target)).Combat)).IconSet))) {
    Result = 1;
  } else {
    Result = 0;
  }
  return Result;
}

/* ovl13:257E: frame not read */
/* ovl13:25C9: retf 8: 8 bytes of parameters; 0 bytes of locals */
/* ovl13:263D. Returns the compass direction from Who's cell towards Target's cell: it reads both
     combat-map cells (CombatantX/CombatantY) and walks Dir 0..8, returning the first direction whose
     90-degree arc at Who (InDirArc) holds Target. Called to face a combatant at another: PerformAttack
     turns Target with the direction from Target to Who, NoteAttackBearing measures the target's
     facing error against it, and ovl09 uses the direction from Who to Combat^.Target as the AI's move
     direction (ovl09:07F2, 0B3C). */
u8 BearingTo(farptr Who, farptr Target)
{
  u8 Result = 0;
  u8 Dir = 0;
  s8 WhoX = 0;
  s8 WhoY = 0;
  s8 TargetX = 0;
  s8 TargetY = 0;
  WhoX = CombatantX(Who);
  WhoY = CombatantY(Who);
  TargetX = CombatantX(Target);
  TargetY = CombatantY(Target);
  Dir = 0;
  while (!InDirArc(WhoX, WhoY, TargetX, TargetY, Dir)) {
    Dir++;
  }
  Result = Dir;
  return Result;
}

/* ovl13:26B0. Shows one attack's missile flying from Who to Target: it picks a picture by Item's item
     kind (the missile sprite of the bearing from Who to Target for most kinds, a 2x2 combat icon or
     two rows of another picture for the rest) and draws it at Who's cell, then animates it along the
     line between the two combatants (WalkCombatLine), with a launch and an impact sound. Called by
     PerformAttack for the aimed item and for a readied bow. Globals: CombatAnimationPicture (the combat picture whose
     bytes-per-item word is read), VideoAdapter, SoundAttackLeaves and SoundAttackArrives (the two sounds). QUIRK ovl13:26DD:
     PixelBytes is worked out and never read. */
void ShowAttackAnimation(PCharacter Who, PCharacter Target, PItem Item)
{
  u8 PicIndex = 0;
  u8 Frames = 0;
  u8 Bearing = 0;
  u8 Mode = 0;
  u16 PixelBytes = 0;
  Bearing = BearingTo(Who, Target);
  Frames = ShowAttackAnimation_MissileFrames;
  Mode = ShowAttackAnimation_MissileMode;
  PicIndex = ShowAttackAnimation_MissilePicBase;
  PixelBytes = (*FPD(TPictureHeader (*), CombatAnimationPicture)).ByteSize;
  if (VideoAdapter == AdapterEga) {
    PixelBytes = (PixelBytes / 4);
  }
  switch ((*FPD(TMenuLine (*), Item)).ItemType) {
  case 9:
  case 0x15:
  case 0x1C:
  case 0x1F:
  case 0x49:
  {
    if (Bearing & 1) {
      if (((Bearing == 3)) || ((Bearing == 5))) {
        CopyPictureItem((s16)(PicIndex + 1), 1, 0, (Bearing == 5));
      } else {
        CopyPictureItem((s16)(PicIndex + 1), 0, 0, (Bearing == 7));
      }
    } else {
      CopyPictureItem((s16)(PicIndex + (Bearing % 4)), (Bearing / 4), 0, 0);
    }
    break;
  }
  case 2:
  case 7:
  case 0x14:
  {
    DrawCombatIcon((s16)(PicIndex + ShowAttackAnimation_IconPicOffset1));
    Frames = ShowAttackAnimation_IconFrames;
    Mode = ShowAttackAnimation_IconMode;
    break;
  }
  case 0x55:
  case 0x56:
  {
    DrawCombatIcon((s16)(PicIndex + ShowAttackAnimation_IconPicOffset2));
    Frames = ShowAttackAnimation_IconFrames;
    Mode = ShowAttackAnimation_IconMode;
    break;
  }
  default:
  {
    {
      if ((*FPD(TMenuLine (*), Item)).ItemType == ShowAttackAnimation_BowItemKind) {
        PicIndex++;
      }
      CopyPictureItem((s16)(PicIndex + ShowAttackAnimation_SwingPicOffset), 0, 0, 0);
      CopyPictureItem((s16)(PicIndex + ShowAttackAnimation_SwingPicOffset), 1, 1, 0);
      Frames = ShowAttackAnimation_SwingFrames;
      Mode = ShowAttackAnimation_SwingMode;
    }
  }
  }
  SetSoundDriverIdle(SoundIdleOff);
  PlaySound(SoundAttackLeaves);
  WalkCombatLine(CombatantX(Who), CombatantY(Who), CombatantX(Target), CombatantY(Target), Frames, Mode);
  PlaySound(SoundAttackArrives);
  SetSoundDriverIdle(SoundIdleDefault);
}

/* ovl13:2879. Works out the monster side's remaining hit points as a percentage and stores it in the
     morale byte SecondMoraleByte, the value CheckMorale reads for a monster's second morale test: it walks the
     battle's character list PartyListHead and, for every combatant on the monster side (Side = SideMonsters),
     adds its maximum hit points (HpMax, +$32) and, when it is still in the fight (Flag10D set), its
     current hit points (HpCurrent, +$11B). A monster whose Flag10D is clear keeps its maximum counted
     while its current hit points fall out of the sum, so damage lowers the percentage. The result is
     20 * current div maximum * 5 (0 when the monster side has no maximum hit points at all, which
     leaves SecondMoraleByte unchanged). Called by StartBattle (ovl10:1E31, before the first round) and
     EndCombatRound (ovl08:0880, every round). Globals: PartyListHead (read), SecondMoraleByte (written). */
void UpdateMonsterMorale(void)
{
  u16 TotalMaxHp = 0;
  u16 TotalCurrentHp = 0;
  PCharacter Who = 0;
  TotalMaxHp = 0;
  TotalCurrentHp = 0;
  Who = PartyListHead;
  while (Who != 0) {
    if ((*FPD(TCharacter (*), Who)).Side == SideMonsters) {
      if ((*FPD(TCharacter (*), Who)).Flag10D != 0) {
        TotalCurrentHp = TotalCurrentHp + (*FPD(TCharacter (*), Who)).HpCurrent;
      }
      TotalMaxHp = TotalMaxHp + (*FPD(TCharacter (*), Who)).HpMax;
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  if (TotalMaxHp > 0) {
    SecondMoraleByte = ((u16)(20 * TotalCurrentHp) / TotalMaxHp) * 5;
  }
}

/* ovl13:2908. Returns half of the largest round Movement (ComputeMovement div 2) among the combatants
     on the side opposing Who that are still in the fight (Flag10D set), and 0 when there is none: it
     walks the battle's character list PartyListHead and keeps the highest value. TryFlee compares the result
     with half of Who's own round Movement to decide whether Who outruns every enemy (Other < Moves
     gets away; level with it needs a coin) and CheckMorale panics Who when the result is at most half
     of Who's own Movement. Globals: PartyListHead (read). */
u8 FastestEnemyMovement(farptr Who)
{
  u8 Result = 0;
  u8 Best = 0;
  u8 Moves = 0;
  PCharacter Member = 0;
  Best = 0;
  Member = PartyListHead;
  while (Member != 0) {
    if (OpposingSide(Who) == (*FPD(TCharacter (*), Member)).Side) {
      if ((*FPD(TCharacter (*), Member)).Flag10D != 0) {
        Moves = (ComputeMovement(Member) / 2);
        if (Moves > Best) {
          Best = Moves;
        }
      }
    }
    Member = (*FPD(TCharacter (*), Member)).Next;
  }
  Result = Best;
  return Result;
}

/* ovl13:2998. Tells whether an attack on Target may go ahead: it is allowed without asking when Target
     is on the side opposing Who (OpposingSide) or is run by the computer (Quick), otherwise the player
     is asked 'Attack Ally: ' (AskYesNo) and that answer decides. On a yes it also turns the fight into
     a brawl: AllyAttackConfirmed and word 819 of GameVars2^ are set, every party member the computer runs (StatusOkay,
     B84 above $7F) is moved to the monster side (Side 1) and loses its remembered target, and the side
     counts are recomputed (RecountCombatSides). Called by MeleeAttack (ovl08:0D45) and ResolveAimedAttack.
     Globals: AllyAttackConfirmed, GameVars2 and PartyListHead (read and written). */
u8 ConfirmAttackTarget(PCharacter Who, PCharacter Target)
{
  u8 Result = 0;
  PCharacter Member = 0;
  if (((OpposingSide(Target) == (*FPD(TCharacter (*), Who)).Side)) || (((*FPD(TCharacter (*), Who)).Quick != 0))) {
    Result = 1;
  } else {
    if (AskYesNo(S("\015Attack Ally: "), 0xD, 0xA, 0xF) != 'Y') {
      Result = 0;
    } else {
      Result = 1;
      AllyAttackConfirmed = 1;
      (*FPD(TGameVars (*), GameVars2))[819] = 1;
      Member = PartyListHead;
      while (Member != 0) {
        if ((((*FPD(TCharacter (*), Member)).Status == StatusOkay)) && (((*FPD(TCharacter (*), Member)).B84 > 0x7F))) {
          (*FPD(TCharacter (*), Member)).Side = SideMonsters;
          (*FPD(TCombatant (*), (*FPD(TCharacter (*), Member)).Combat)).Target = 0;
        }
        Member = (*FPD(TCharacter (*), Member)).Next;
      }
      RecountCombatSides();
    }
  }
  return Result;
}

/* ovl13:2AA0. Shows the manual-aim prompt and returns the key the player pressed: it draws the
     target's character panel and puts the combat cursor on it (DrawCharacterPanel, ShowCursorOn), shows
     'Range = ' with the distance when ShowRange is nonzero, builds the aim menu 'Next Prev Manual ' +
     the target name + 'Center Exit' and reads a key from it through ReadPromptChoice ('Aim:'). The
     target name is 'Target ' when the distance is within Range and the aim is worth naming: always when
     ShowRange is 0, else only for a ranged weapon (IsRangedWeapon, ChooseAttackItem, and either no
     adjacent enemy or an ammo that can strike in melee). Called by RunAimTargets, the player's aim cursor.
     Globals: none. QUIRK ovl13:2ACF: Bearing is worked out and never read. */
u8 ShowAimPrompt(PCharacter Who, PCharacter Target, u8 Range, u8 ShowRange, u8 Unused)
{
  u8 Result = 0;
  u8 Aim[41] = {0};
  u8 ExtKey = 0;
  farptr AimItem = 0;
  u8 Distance = 0;
  u8 Bearing = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  rtl_str_assign(Aim, 40, S("\000"));
  Distance = DistanceToTarget(Who, Target);
  Bearing = BearingTo(Who, Target);
  if (ShowRange != 0) {
    DrawTextAt(0, 0x17, 0xA, rtl_str_cat(t2, 3, (const u8 *const[]){S("\010Range = "), ByteToText(t1, Distance), S("\002  ")}));
  }
  if (Distance <= Range) {
    if (ShowRange == 0) {
      rtl_str_assign(Aim, 40, S("\007Target "));
    } else if (Who != Target) {
      if (!IsRangedWeapon(Who)) {
        rtl_str_assign(Aim, 40, S("\007Target "));
      } else if (ChooseAttackItem(Who, &AimItem) != 0) {
        if (((CollectEnemiesInRange(Who, 1) == 0)) || RangedWeaponCanMelee(Who)) {
          rtl_str_assign(Aim, 40, S("\007Target "));
        }
      }
    }
  }
  rtl_str_assign(Aim, 40, rtl_str_cat(t3, 3, (const u8 *const[]){S("\021Next Prev Manual "), Aim, S("\013Center Exit")}));
  ShowCursorOn(Target, 3, 1);
  DrawCharacterPanel(Target);
  Result = ReadPromptChoice(S("\004Aim:"), Aim, 0xD, 0xA, 0xF, 0, 0, &ExtKey);
  return Result;
}

/* ovl13:2C3D. Records the aim on Target and, when Automatic is 1, attacks it: it sets Done and, in
     attack mode, first asks ConfirmAttackTarget (an attack on an ally is confirmed by the player) and
     clears Done on a no. When Done is still set it stores Target in the aim record Aim (Who, and the
     cell from CombatantX/CombatantY), clears CombatMap's show-cursor and moves the combat cursor to
     the centre of the 7x7 view (CombatMap^.ViewX + ViewCentre, ViewY + ViewCentre, margin ViewCentre,
     the no-step direction 8), away from the target's cell it was just set from: Purpose unknown (the
     target was not chosen as the cursor's cell); in attack mode it then sweeps the adjacent
     level-0 enemies (SweepEnemies, ending the turn when it swept) or names the ranged weapon's ammo
     (ChooseAttackItem, dropped to nil in melee range) and resolves the attack through PerformAttack.
     When Done was cleared the aim record is cleared (FillChar 7). Called by RunAimCursor (ovl13:2DFA)
     and RunAimTargets (ovl13:3558). Globals: CombatMap (write).
     QUIRK ovl13:2C3D: the byte local is declared and never read; it makes the frame 6 bytes. */
void ResolveAimedAttack(PCharacter Who, PCharacter Target, u8 Automatic, u8 (*Done), TSpellTarget (*Aim))
{
  u8 Unused = 0;
  farptr AimItem = 0;
  AimItem = 0;
  (*Done) = 1;
  if (Automatic == 1) {
    if (!ConfirmAttackTarget(Who, Target)) {
      (*Done) = 0;
    }
  }
  if ((*Done) != 0) {
    (*Aim).Who = Target;
    (*Aim).X = CombatantX(Target);
    (*Aim).Y = CombatantY(Target);
    (*FPD(TCombatMap (*), CombatMap)).ShowCursor = 0;
    MoveCombatCursor((s16)((*FPD(TCombatMap (*), CombatMap)).ViewX + ViewCentre_OVL13), (s16)((*FPD(TCombatMap (*), CombatMap)).ViewY + ViewCentre_OVL13), ViewCentre_OVL13, 8);
    if (Automatic == 1) {
      if (SweepEnemies(Who, Target)) {
        (*Done) = EndCombatTurn(Who);
      } else {
        NoteAttackBearing(Who, Target);
        if (IsRangedWeapon(Who)) {
          if (ChooseAttackItem(Who, &AimItem) != 0) {
            if (RangedWeaponCanMelee(Who)) {
              if (DistanceToTarget(Who, Target) == 1) {
                AimItem = 0;
              }
            }
          }
        }
        PerformAttack(Who, Target, 0, AimItem, &(*Done));
      }
    }
  } else {
    rtl_FillChar((void *)&(*Aim), 7, 0);
  }
}

/* ovl13:2DFA. The manual aim cursor: clears the aim record Aim and starts the cursor on Target's cell
     (CombatantX/CombatantY), shows the combat cursor and loops until the player presses a key that ends
     the aim ([#0, #13, 'E', 'T']). Each pass moves the cursor one step in Dir (MoveCombatCursor, clamped
     to the 50x25 map), reads the cell (GetMapCell), walks a line of sight from Who (WalkLine, its step
     count halved) and, with Automatic set, shows 'Range = ' with the halved distance (WordToText,
     DrawTextAt) or clears the line when the walk is blocked. The combatant on the cell or the body left
     there becomes Target (CombatantRecord / BodyTable) and its panel is drawn. The aim is legal (Valid)
     only when the distance is within Range, the tile is passable (CombatTiles[Tile].Cost <> $FF), an
     existing Target passes AttackTargetAllowed and, for a ranged weapon with Automatic set,
     ChooseAttackItem finds usable ammo that can melee any adjacent enemy; with no target, AimFlag 0
     makes the aim illegal. It builds the prompt 'Center Exit', prefixed 'Target ' when legal, and reads
     a key under the title '(Use Cursor keys) ' (ReadPromptChoice, CombatScratchFlag): Enter or 'T' confirms (the
     cell and Target go into Aim and, when Automatic, ResolveAimedAttack resolves the attack, else Done
     is set; a failed aim redraws the cell and clears Aim), H/I/M/Q/P/O/K/G set Dir 0..7, #0 or 'E'
     cancels, 'C' centres the cursor (Dir 8) and any other key clears Dir. Called by the aim wrapper e17.
     Globals: CombatMap, BodyCount, BodyTable, CombatantRecord, CombatTiles, DirStepX, DirStepY, CombatScratchFlag. */
void RunAimCursor(PCharacter Who, PCharacter Target, u8 Range, u8 Automatic, u8 AimFlag, u8 (*Done), TSpellTarget (*Aim))
{
  u8 AimText[41] = {0};
  u8 Key = 0;
  farptr AimItem = 0;
  u8 Dir = 0;
  u8 I = 0;
  s8 WalkX = 0;
  s8 WalkY = 0;
  s8 CurX = 0;
  s8 CurY = 0;
  u8 Occupant = 0;
  u8 Tile = 0;
  u16 Distance = 0;
  u8 Valid = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3;
  u8 t4[256];
  rtl_FillChar((void *)&(*Aim), 7, 0);
  CurX = CombatantX(Target);
  CurY = CombatantY(Target);
  Key = ' ';
  Dir = 8;
  (*Done) = 0;
  (*FPD(TCombatMap (*), CombatMap)).ShowCursor = 1;
  (*FPD(TCombatMap (*), CombatMap)).CursorKind = 1;
  while (!((Key == 0x00 || Key == 0x0D || Key == 'E' || Key == 'T'))) {
    MoveCombatCursor(CurX, CurY, ViewCentre_OVL13, Dir);
    CurX += DirStepX[Dir];
    CurY += DirStepY[Dir];
    if (CurX < 0) {
      CurX = 0;
    }
    if (CurY < 0) {
      CurY = 0;
    }
    if (CurX > 0x31) {
      CurX = 0x31;
    }
    if (CurY > 0x18) {
      CurY = 0x18;
    }
    GetMapCell(CurX, CurY, &Occupant, &Tile);
    FlushKeyboard();
    Valid = 0;
    Distance = 0xFF;
    WalkX = CurX;
    WalkY = CurY;
    if (WalkLine(CombatantX(Who), CombatantY(Who), &WalkX, &WalkY, &Distance, CombatMap)) {
      Valid = 1;
      if (Automatic != 0) {
        DrawTextAt(0, 0x17, 0xA, rtl_str_cat(t2, 3, (const u8 *const[]){S("\010Range = "), WordToText(t1, (u16)((u16)Distance >> 1)), S("\002  ")}));
      }
    } else if (Automatic != 0) {
      ClearWindow(0, 0x17, 0x27, 0x17);
    }
    Distance = (u16)((u16)Distance >> 1);
    Target = 0;
    if (Valid) {
      if (Occupant > 0) {
        Target = CombatantRecord[Occupant - 1];
      } else if (Tile == BodyTile) {
        t3 = BodyCount;
        I = 1;
        if (I <= t3) for (;;) {
          if (((BodyTable[I - 1].X == CurX)) && ((BodyTable[I - 1].Y == CurY))) {
            Target = BodyTable[I - 1].Who;
          }
          if (I == t3) break;
          I++;
        }
      }
    }
    if (Target != 0) {
      DrawCharacterPanel(Target);
    } else {
      ClearWindow(0x17, 1, 0x26, 0x15);
    }
    if (((Range < Distance)) || ((CombatTiles[Tile].Cost == 0xFF))) {
      Valid = 0;
    }
    if (Target != 0) {
      if (!AttackTargetAllowed(Who, Target)) {
        Valid = 0;
      }
      if (Automatic == 1) {
        if (((Who == Target)) || ((((Occupant == 0)) && ((Tile == BodyTile))))) {
          Valid = 0;
        } else if (IsRangedWeapon(Who)) {
          if (((ChooseAttackItem(Who, &AimItem) == 0)) || ((((CollectEnemiesInRange(Who, 1) > 0)) && !RangedWeaponCanMelee(Who)))) {
            Valid = 0;
          }
        }
      }
    } else if (AimFlag == 0) {
      Valid = 0;
    }
    rtl_str_assign(AimText, 40, S("\013Center Exit"));
    if (Valid) {
      rtl_str_assign(AimText, 40, rtl_str_cat(t4, 2, (const u8 *const[]){S("\007Target "), AimText}));
    }
    Key = ReadPromptChoice(S("\022(Use Cursor keys) "), AimText, 0xD, 0xA, 0xF, 1, 0, &CombatScratchFlag);
    switch ((u8)Key) {
    case 0x0D:
    case 'T':
    {
      (*FPD(TCombatMap (*), CombatMap)).ShowCursor = 0;
      if (Valid) {
        (*Aim).X = CurX;
        (*Aim).Y = CurY;
        if (Target != 0) {
          (*Aim).Who = Target;
        } else {
          (*Aim).Who = 0;
        }
        if (Automatic == 1) {
          ResolveAimedAttack(Who, (*Aim).Who, Automatic, &(*Done), &(*Aim));
        } else {
          (*Done) = 1;
        }
      }
      if ((!Valid) || (((*Done) == 0))) {
        RedrawMapCell(CurX, CurY);
        (*Done) = 0;
        rtl_FillChar((void *)&(*Aim), 7, 0);
      }
      break;
    }
    case 'H':
    {
      Dir = 0;
      break;
    }
    case 'I':
    {
      Dir = 1;
      break;
    }
    case 'M':
    {
      Dir = 2;
      break;
    }
    case 'Q':
    {
      Dir = 3;
      break;
    }
    case 'P':
    {
      Dir = 4;
      break;
    }
    case 'O':
    {
      Dir = 5;
      break;
    }
    case 'K':
    {
      Dir = 6;
      break;
    }
    case 'G':
    {
      Dir = 7;
      break;
    }
    case 0x00:
    case 'E':
    {
      RedrawMapCell(CurX, CurY);
      rtl_FillChar((void *)&(*Aim), 7, 0);
      (*Done) = 0;
      break;
    }
    case 'C':
    {
      MoveCombatCursor(CurX, CurY, 0, 8);
      Dir = 8;
      break;
    }
    default:
    {
      Dir = 8;
    }
    }
  }
}

typedef struct Frame_RunAimTargets {
  PCharacter Who;
  u8 Range;
  u8 Automatic;
  u8 AimFlag;
  u8 (*Done);
  void *Aim;
  TSortRec Targets[72];
  u8 AimRange;
  u8 Count;
  u8 Index;
  u8 NextDelta;
  u8 Walk;
  s8 FromX;
  s8 FromY;
  s8 ToX;
  s8 ToY;
  PCharacter Target;
  u8 Key;
} Frame_RunAimTargets;

/* ovl13:32E6. Lists the targets Who can reach: ScanTargets over the whole map ($7F steps, every
       direction, Who's own footprint kind) into SortEntries and copies SortEntries[1..Count] into Targets. The
       count goes into the enclosing Count. Called with Who by e17. */
static void RunAimTargets_ListAimTargets(struct Frame_RunAimTargets *up, PCharacter Who)
{
  u8 I = 0;
  u8 t1;
  ScanTargets(CombatantX(Who), CombatantY(Who), 0x7F, 0xFF, CombatantKind(Who), CombatMap);
  up->Count = SortEntries[0].Val_;
  t1 = up->Count;
  I = 1;
  if (I <= t1) for (;;) {
    up->Targets[I - 1] = SortEntries[I];
    if (I == t1) break;
    I++;
  }
}

/* ovl13:3389. Steps the aim cursor through Targets by Delta and returns the target there: with
       Step set it remembers the current cell (CombatantTable), otherwise it redraws the old cell
       (RedrawMapCell). The index wraps into 1..Count, the new target's cell is remembered and, with
       Step set, WalkCombatLine draws the cursor's move from the old cell to it. Called by e17. */
static PCharacter RunAimTargets_StepAimCursor(struct Frame_RunAimTargets *up, u8 Delta, u8 Step)
{
  PCharacter Result = 0;
  u8 Unused[4] = {0};
  if (Step != 0) {
    up->FromX = CombatantTable[up->Targets[up->Index - 1].Head].X;
    up->FromY = CombatantTable[up->Targets[up->Index - 1].Head].Y;
  } else {
    RedrawMapCell(up->FromX, up->FromY);
  }
  up->Index += Delta;
  if (up->Index == 0) {
    up->Index = up->Count;
  }
  if (up->Index > up->Count) {
    up->Index = 1;
  }
  Result = CombatantRecord[up->Targets[up->Index - 1].Head - 1];
  up->ToX = CombatantTable[up->Targets[up->Index - 1].Head].X;
  up->ToY = CombatantTable[up->Targets[up->Index - 1].Head].Y;
  if (Step != 0) {
    WalkCombatLine(up->FromX, up->FromY, up->ToX, up->ToY, 1, 0);
    up->FromX = up->ToX;
    up->FromY = up->ToY;
  }
  return Result;
}

/* ovl13:3558. The aim cursor of the combat A command: it clears the aim record Aim and Done, works
     out the effective range AimRange (Range itself, or for the $FF "any" the readied weapon's
     ItemTable range minus one, at least 1) and lists the targets reachable from Who
     (ListAimTargets, the ScanTargets scan). It starts on the first target (StepAimCursor) and loops
     while Done is clear and the player has not pressed #0 or 'E': when Who may not attack the current
     target (AttackTargetAllowed) it steps the cursor on; otherwise it asks ShowAimPrompt and (N/P move
     the cursor, M runs the free aim cursor RunAimCursor, T resolves the aimed attack, C centres the
     cursor) then redraws the target's cell and steps to the next. When it finally ends and Automatic is
     set it clears the range line. Called by PlayerTurn (ovl08:0310, Range $FF, Automatic 1) and
     FindSpellTarget (Range from SpellAreaSize, Automatic 0). Globals: ItemTable, CombatantTable,
     CombatantRecord, SortEntries (the scan table ListAimTargets copies into Targets). */
void RunAimTargets(PCharacter Who, u8 Range, u8 Automatic, u8 AimFlag, u8 (*Done), void *Aim)
{
  Frame_RunAimTargets fr;
  memset(&fr, 0, sizeof fr);
  fr.Who = Who;
  fr.Range = Range;
  fr.Automatic = Automatic;
  fr.AimFlag = AimFlag;
  fr.Done = Done;
  fr.Aim = Aim;
  CopyPictureItem(AimCursorPicture, 0, 0, 0);
  rtl_FillChar((void *)fr.Aim, 7, 0);
  (*fr.Done) = 0;
  fr.AimRange = fr.Range;
  if (fr.AimRange == 0xFF) {
    if ((*FPD(TCharacter (*), fr.Who)).SlotItems[0] != 0) {
      fr.AimRange = ItemTable[(*FPD(TMenuLine (*), (*FPD(TCharacter (*), fr.Who)).SlotItems[0])).ItemType].Range - 1;
    } else {
      fr.AimRange = 1;
    }
  }
  if (((fr.AimRange == 0)) || ((fr.AimRange == 0xFF))) {
    fr.AimRange = 1;
  }
  RunAimTargets_ListAimTargets(&fr, fr.Who);
  fr.Index = 1;
  fr.NextDelta = 0;
  fr.Target = RunAimTargets_StepAimCursor(&fr, fr.NextDelta, 1);
  fr.NextDelta = 1;
  fr.Key = ' ';
  while ((((*fr.Done) == 0)) && !((fr.Key == 0x00 || fr.Key == 'E'))) {
    if (!AttackTargetAllowed(fr.Who, fr.Target)) {
      fr.Target = RunAimTargets_StepAimCursor(&fr, fr.NextDelta, 0);
    } else {
      fr.Key = ShowAimPrompt(fr.Who, fr.Target, fr.AimRange, fr.Automatic, fr.AimFlag);
      switch ((u8)fr.Key) {
      case 'N':
      {
        fr.NextDelta = 1;
        fr.Walk = 1;
        break;
      }
      case 'P':
      {
        fr.NextDelta = 0xFF;
        fr.Walk = 0xFF;
        break;
      }
      case 'M':
      {
        RunAimCursor(fr.Who, fr.Target, fr.AimRange, fr.Automatic, fr.AimFlag, &(*fr.Done), &(*(TSpellTarget (*))fr.Aim));
        CopyPictureItem(AimCursorPicture, 0, 0, 0);
        RunAimTargets_ListAimTargets(&fr, fr.Who);
        fr.Walk = 0;
        break;
      }
      case 'T':
      {
        ResolveAimedAttack(fr.Who, fr.Target, fr.Automatic, &(*fr.Done), &(*(TSpellTarget (*))fr.Aim));
        CopyPictureItem(AimCursorPicture, 0, 0, 0);
        RunAimTargets_ListAimTargets(&fr, fr.Who);
        fr.Walk = 0;
        break;
      }
      case 'C':
      {
        MoveCombatCursor(CombatantX(fr.Target), CombatantY(fr.Target), 0, 8);
        fr.Walk = 0;
        break;
      }
      }
      RedrawMapCell(CombatantX(fr.Target), CombatantY(fr.Target));
      fr.Target = RunAimTargets_StepAimCursor(&fr, fr.Walk, ((((*fr.Done) == 0)) && !((fr.Key == 0x00 || fr.Key == 'E'))));
    }
  }
  if (fr.Automatic != 0) {
    ClearWindow(0, 0x17, 0x27, 0x17);
  }
}

/* ovl13:37E4: frame not read */
/* ovl13:37E4. Picks an enemy inside Range for Who, the target search the automatic spell aim and the
     AI movement use: it first drops Who's remembered Combat^.Target unless ForgetTarget is 0 and the
     remembered target still fights (Flag10D set) on the other side and AttackTargetAllowed accepts it,
     in which case the result is True at once. Otherwise it searches in two passes: while no target is
     Found and the second pass has not been taken, it lists the enemies CollectEnemiesInRange(Who,
     Range) holds and, up to AimSearchTries times, picks one at random (RollDice); a pick is accepted
     when ThroughWalls and CombatMap^.Head6 are both set or AttackTargetAllowed allows it, and then
     Who^.Combat^.Target takes it; a refused pick is zeroed in CombatantScanList and the pass goes on only while
     another entry is left. The first pass leaves CombatMap^.Head6 as it is, the second opens it when
     ForgetTarget is 0, so it can see through a blocking tile; Head6 is cleared again at the end.
     Returns whether a target was set. Called by FindSpellTarget (aim, ForgetTarget 1) and ovl09
     QuickTurn, MoveStep and AiTurn. Globals: CombatantScanList (the scan list), CombatantRecord, CombatMap (Head6). */
u8 ChooseCombatTarget(PCharacter Who, u8 Range, u8 ThroughWalls, u8 ForgetTarget)
{
  u8 Result = 0;
  u8 Count = 0;
  u8 Attempts = 0;
  u8 Index = 0;
  u8 Retry = 0;
  u8 Found = 0;
  u8 Searched = 0;
  PCharacter Target = 0;
  u8 t1;
  Searched = 0;
  Found = 0;
  Retry = 0;
  Target = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  if (((ForgetTarget != 0)) || ((((Target != 0)) && ((((((*FPD(TCharacter (*), Target)).Side == (*FPD(TCharacter (*), Who)).Side)) || (((*FPD(TCharacter (*), Target)).Flag10D == 0))) || !AttackTargetAllowed(Who, Target)))))) {
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target = 0;
  }
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target != 0) {
    Found = 1;
  }
  while ((!Found) && (!Retry)) {
    Retry = Searched;
    if (Searched && ((ForgetTarget == 0))) {
      (*FPD(TCombatMap (*), CombatMap)).Head6 = 1;
    }
    Attempts = AimSearchTries;
    Count = CollectEnemiesInRange(Who, Range);
    while ((((Attempts > 0)) && (!Found)) && ((Count > 0))) {
      Attempts--;
      Index = RollDice(1, Count);
      if (CombatantScanList[Index] > 0) {
        Target = CombatantRecord[CombatantScanList[Index] - 1];
        if (((((ThroughWalls != 0)) && (((*FPD(TCombatMap (*), CombatMap)).Head6 != 0)))) || AttackTargetAllowed(Who, Target)) {
          Found = 1;
          (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target = Target;
        } else {
          CombatantScanList[Index] = 0;
          t1 = Count;
          Index = 1;
          if (Index <= t1) for (;;) {
            if (CombatantScanList[Index] > 0) {
              Found = 1;
            }
            if (Index == t1) break;
            Index++;
          }
          if (Found) {
            Found = 0;
          } else {
            Count = 0;
          }
        }
      }
    }
    if (!Searched) {
      Searched = 1;
    }
  }
  (*FPD(TCombatMap (*), CombatMap)).Head6 = 0;
  Result = Found;
  return Result;
}

/* ovl13:39D2. The affect $49 handler, the rake: the ovl12 initialiser that fills AffectHandlers
     (the store at ovl12 code 0x354D) puts this routine in AffectHandlers[$49]. When Who's last attack
     resolution landed both of its slot-1 attacks (AttackSlotRolls[1] = 2, counted in ResolveCombatantAttacks)
     and the target it remembers (Combat^.Target) is still in the fight (Flag10D set), Who rakes it:
     the readied second attack form is armed in attack slot 2 (AttackSlots[2] 2, WeaponAttacks[2] 2,
     WeaponDamage[2] 4), slot 1 is emptied so only that form fires, 'Rakes...' is shown, and
     PerformAttack resolves the rake against the remembered target; the turn then ends through
     EndCombatTurn. Called through the affect hooks (affect $49 is in the kind 2 list, ovl24:02FA)
     or when the affect is removed, so Affect and Mode are not read. Globals: AttackRoll (read). */
void RakeAttack(PCharacter Who, PAffect Affect, u8 Mode)
{
  u8 Done = 0;
  if (AttackSlotRolls[1] != 2) {
    return;
  }
  if ((*FPD(TCharacter (*), (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target)).Flag10D == 0) {
    return;
  }
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Pad4[0] = 2;
  (*FPD(TCharacter (*), Who)).AttackSlots[1] = 2;
  (*FPD(TCharacter (*), Who)).WeaponAttacks[1] = 2;
  (*FPD(TCharacter (*), Who)).WeaponDamage[1] = 4;
  (*FPD(TCharacter (*), Who)).AttackSlots[0] = 0;
  ShowCharacterMessage(Who, S("\010Rakes..."), 10, 1);
  PerformAttack(Who, (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target, 0, 0, &Done);
  Done = EndCombatTurn(Who);
}

/* ovl13:3A86. The affect $4A handler: the ovl12 initialiser that fills AffectHandlers (the store at
     ovl12 code 0x354D) puts this routine in AffectHandlers[$4A]. While Who carries it and both Who and
     the combatant its affect records (CombatantRecord[Affect^.Data], the affect's +3 byte) are in the
     fight (Flag10D set), Who is made to attack that combatant: slot 1 takes the second attack form
     (AttackSlots[1] 1, AttackSlots[2] 0, WeaponAttacks[1] 3, WeaponDamage[1] 4), PerformAttack is
     called from behind (attack kind 1) and the turn ends through EndCombatTurn; the affect is removed
     from Who when the attack left the combatant out of the fight. Otherwise the combatant loses affect
     $3A, and (mode 0 only) the affect's removal flag is cleared and it is removed from Who, which runs
     this handler again with mode 1 and so does not recurse. Globals: AttackTarget (the recorded combatant),
     CombatantRecord. */
void ForcedAttack(PCharacter Who, PAffect Affect, u8 Mode)
{
  u8 Done = 0;
  u8 Unused = 0;
  AttackTarget = CombatantRecord[(*FPD(TAffect (*), Affect)).Data - 1];
  if ((((Mode != 0)) || (((*FPD(TCharacter (*), Who)).Flag10D == 0))) || (((*FPD(TCharacter (*), AttackTarget)).Flag10D == 0))) {
    RemoveAffect(AttackTarget, AffectHeldFast, 0);
    if (Mode == 0) {
      (*FPD(TAffect (*), Affect)).Flag = 0;
      RemoveAffect(Who, AffectForcedAttack, Affect);
    }
  } else {
    (*FPD(TCharacter (*), Who)).AttackSlots[0] = 1;
    (*FPD(TCharacter (*), Who)).AttackSlots[1] = 0;
    (*FPD(TCharacter (*), Who)).WeaponAttacks[0] = 3;
    (*FPD(TCharacter (*), Who)).WeaponDamage[0] = 4;
    PerformAttack(Who, AttackTarget, 1, 0, &Done);
    Done = EndCombatTurn(Who);
    if ((*FPD(TCharacter (*), AttackTarget)).Flag10D == 0) {
      RemoveAffect(Who, AffectForcedAttack, Affect);
    }
  }
}

/* ovl13:3B93. The Alt-X debug command of the combat keys (ovl08:0264 PlayerTurn, ovl09:0690
     HandleCombatKey, which shows 'That doesn''t work' when this returns False): it acts only when the
     program was started with the STING argument (ParamStr(1) = 'STING', the same argument res04's
     ReadGameKey uses to turn on DebugMode), the developers' 'the gods intervene'. It returns True,
     flashes 'The Gods intervene!', then walks the battle character list PartyListHead and, for every monster
     it holds (Side = SideMonsters), takes it out of the fight (Flag10D 0), leaves it dead (Status
     StatusDead) and clears its combat-map cell (CombatantTable[CombatantIndex(Who)].Kind 0);
     EndCombatTurn then runs for EVERY combatant of the list, party members included, because the call
     sits outside the monster test, and its result is never read (QUIRK ovl13:3C29). The cursor is
     finally centred on the centre of the 7x7 view (CombatMap^.ViewX + ViewCentre, ViewY +
     ViewCentre, margin $FF so the view does not scroll, no step). Globals:
     PartyListHead, CombatMap, CombatantTable. */
u8 GodsIntervene(void)
{
  u8 Result = 0;
  u8 Done = 0;
  PCharacter Who = 0;
  u8 t1[256];
  Result = 0;
  if (rtl_str_cmp(rtl_paramstr(t1, 1), S("\005STING")) != 0) {
    return Result;
  }
  Result = 1;
  ShowFlashMessage(S("\023The Gods intervene!"));
  Who = PartyListHead;
  while (Who != 0) {
    if ((*FPD(TCharacter (*), Who)).Side == SideMonsters) {
      (*FPD(TCharacter (*), Who)).Flag10D = 0;
      (*FPD(TCharacter (*), Who)).Status = StatusDead;
      CombatantTable[CombatantIndex(Who)].Kind = 0;
    }
    /* QUIRK ovl13:3C29: this runs for every combatant of the list, party members included (the
       call is outside the monster-only block), and its result is never read. */
    Done = EndCombatTurn(Who);
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  MoveCombatCursor((s16)((*FPD(TCombatMap (*), CombatMap)).ViewX + ViewCentre_OVL13), (s16)((*FPD(TCombatMap (*), CombatMap)).ViewY + ViewCentre_OVL13), 0xFF, 8);
  return Result;
}

/* Initialisation part of unit OVL13. */
void init_OVL13(void)
{
}
