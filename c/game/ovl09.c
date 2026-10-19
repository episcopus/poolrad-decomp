#include "game.h"

/* ovl09:000F. The computer's turn for Who (called by CombatTurn ovl08:01F6 and PlayerTurn
     ovl08:031A when the character is quick): it reads a key (HandleCombatKey), clears the prompt
     line, and ends the turn through EndCombatTurn when Who has left the fight (Flag10D 0). It rerolls
     the step pattern (StepPattern, +$15) when the current one is 0 or above 4, or when a d4 comes up 1:
     a d8 gives the new pattern, an 8 rerolls a d2 + 4, anything else a d4. Morale (CheckMorale) runs
     when no key was pressed; a panicking character (Panic, +$14) that is not forced to flee (ForcedFlight,
     +$10 zero) shows 'flees in panic' (the unit's string at offset 0) through ShowCharacterMessage. Then, while
     the turn is not over: use a magic item (UseMagicItem, ending through EndCombatTurn), finish a
     pending spell (Combat^.PendingSpell; CastChosenSpell, end of turn), take the Turn action (TryTurnUndead,
     Turn Undead for a cleric, end of turn), cast a memorized spell (CastMemorizedSpell, Done := 1), use
     the best item (UseBestItem) and read keys again (HandleCombatKey); with Done clear it loops on
     ChooseCombatTarget(Who, $FF, 1, 0): an initiative above 0 runs AiTurn, else the turn ends through
     EndOrGuardTurn. Globals: none. QUIRK: CastChosenSpell's var result is overwritten at once. */
void QuickTurn(PCharacter Who)
{
  POOL_TRACE("QuickTurn");
  u8 Pattern = 0;
  u8 Done = 0;
  Done = HandleCombatKey(Who);
  ClearPromptLine();
  ClearCharacterMessage();
  if ((*FPD(TCharacter (*), Who)).Flag10D == 0) {
    Done = EndCombatTurn(Who);
  }
  Pattern = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).StepPattern;
  if ((((Pattern == 0)) || ((Pattern > 4))) || ((RollDice(1, 4) == 1))) {
    Pattern = RollDice(1, 8);
    if (Pattern == 8) {
      Pattern = RollDice(1, 2) + 4;
    } else {
      Pattern = RollDice(1, 4);
    }
  }
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).StepPattern = Pattern;
  if (Done == 0) {
    Done = CheckMorale(Who);
  }
  if ((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Panic != 0)) && (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).ForcedFlight == 0))) {
    ShowCharacterMessage(Who, S("\016flees in panic"), 0xA, 1);
  }
  if (Done != 0) {
    return;
  }
  if (UseMagicItem(Who)) {
    Done = EndCombatTurn(Who);
    return;
  }
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).PendingSpell > 0) {
    CastChosenSpell((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).PendingSpell, 1, 1, &Done);
    Done = EndCombatTurn(Who);
    return;
  }
  if (TryTurnUndead(Who)) {
    Done = EndCombatTurn(Who);
    return;
  }
  if (CastMemorizedSpell(Who) != 0) {
    Done = 1;
    return;
  }
  UseBestItem(Who);
  Done = HandleCombatKey(Who);
  while (Done == 0) {
    if (ChooseCombatTarget(Who, 0xFF, 1, 0) && (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative > 0))) {
      Done = AiTurn(Who);
    } else {
      Done = EndOrGuardTurn(Who);
    }
  }
}

/* ovl09:0203 (TryTurnUndead). The computer's Turn action, Turn Undead for a cleric: it returns True
     and calls TurnUndead (the Turn of PlayerTurn's T case, src/OVL08.PAS:220) when the combatant has not
     turned yet (Combat.Turned is 0), has a level in class 0 (ClassLevels[0] above 0; CombatMenu offers
     Turn on the same two tests, ovl08:0795) and SelectTurnUndeadTarget agrees; else it
     returns False. Called by QuickTurn (ovl09:0170): a True result ends the turn through EndCombatTurn.
     Unused fills the two frame bytes the code never reads ([bp-2..-4]; Done at [bp-5] is
     SelectTurnUndeadTarget's untyped var parameter). */
u8 TryTurnUndead(PCharacter Who)
{
  POOL_TRACE("TryTurnUndead");
  u8 Result = 0;
  u8 Unused[3] = {0};
  u8 Done = 0;
  if (((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Turned == 0)) && (((*FPD(TCharacter (*), Who)).ClassLevels[0] > 0))) && SelectTurnUndeadTarget(Who, (void *)&Done)) {
    Result = 1;
    TurnUndead(Who);
  } else {
    Result = 0;
  }
  return Result;
}

typedef struct Frame_SpellAccepted {
  PCharacter Who;
  u8 Spell;
  u8 Range;
  u8 Result;
  u8 Unused[3];
  u8 Done;
  u8 Tries;
  u8 I;
} Frame_SpellAccepted;

/* Nested in SpellAccepted (ovl09:0255): scans the DS:5F27 map entities around (X, Y) with the
       area pattern of spell Spell (its +$F byte is the line budget, direction omni, footprint base
       1) into SortEntries, then answers True when one of the found combatants has a Side different from
       OpposingSide(SelectedCharacter) (that is 1 for the party side 0). Purpose unknown. */
static u8 SpellAccepted_DifferentSideInArea(struct Frame_SpellAccepted *up, s8 X, s8 Y, u8 Spell)
{
  u8 Result = 0;
  u8 I = 0;
  Result = 0;
  ScanTargets(X, Y, SpellTable[Spell].PadB[4], 0xFF, 1, CombatMap);
  {
    u8 limit = SortEntries[0].Val_;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          if ((*FPD(TCharacter (*), CombatantRecord[SortEntries[I].Head - 1])).Side != OpposingSide(SelectedCharacter)) {
            Result = 1;
          }
        if (I == limit) break;
        I++;
      }
    }
  }
  return Result;
}

/* ovl09:02EB (SpellAccepted). Decides whether the AI accepts spell Spell cast at Range by Who
     (UseMagicItem 03E4 and CastMemorizedSpell 0545 keep what it accepts). Refuses at once when the
     spell row's +$D byte is below Range. A spell other than 3 whose +$E byte is 0, and spell 3 when
     FindNearbyTarget(Who, Done) agrees, are accepted at once. Otherwise CollectEnemiesInRange collects Who's
     enemies the area pattern of SpellAreaSize(Spell) reaches (CombatantScanList, count Tries): a zero count refuses,
     a zero +$F byte accepts; else each collected enemy is asked through the nested
     DifferentSideInArea, a Yes refuses the spell and a No (or no enemy at all) accepts it.
     The +$D..+$F bytes are the spell row's last three bytes of SpellTable (16-byte stride).
     QUIRK: the [bp-2..-4] frame bytes are never read (Unused). Globals: SpellTable, CombatantScanList,
     CombatantTable, SortEntries, CombatantRecord, SelectedCharacter, CombatMap. */
u8 SpellAccepted(PCharacter Who, u8 Spell, u8 Range)
{
  POOL_TRACE("SpellAccepted");
  Frame_SpellAccepted fr;
  memset(&fr, 0, sizeof fr);
  fr.Who = Who;
  fr.Spell = Spell;
  fr.Range = Range;
  fr.Result = 0;
  if (SpellTable[fr.Spell].PadB[2] < fr.Range) {
    return fr.Result;
  }
  if (((((fr.Spell != 3)) && ((SpellTable[fr.Spell].PadB[3] == 0)))) || ((((fr.Spell == 3)) && FindNearbyTarget(fr.Who, (void *)&fr.Done)))) {
    fr.Result = 1;
    return fr.Result;
  }
  fr.Tries = CollectEnemiesInRange(fr.Who, SpellAreaSize(fr.Spell));
  if (fr.Tries > 0) {
    if (SpellTable[fr.Spell].PadB[4] == 0) {
      fr.Result = 1;
      return fr.Result;
    }
    {
      u8 limit = fr.Tries;
      if (1 <= limit) {
        fr.I = 1;
        for (;;) {
            if (SpellAccepted_DifferentSideInArea(&fr, CombatantTable[CombatantScanList[fr.I]].X, CombatantTable[CombatantScanList[fr.I]].Y, fr.Spell)) {
              return fr.Result;
            }
          if (fr.I == limit) break;
          fr.I++;
        }
      }
    }
    fr.Result = 1;
  }
  return fr.Result;
}

/* ovl09:03E4. Uses a magic item for the computer's turn (called by QuickTurn; True ends
     the turn through EndCombatTurn): rolls 1d7 rounds; each round walks Who^.Items for the first
     item that passes (not IsScroll, Affects[3] below $80, Readied, level from Affects[2] in
     1..MaxSpell adjusted down by $17 above it, and SpellAccepted in range) and remembers it as
     Best. Afterwards a chosen Best is used through UseItem and the result is True. Early exits
     (CanUseMagicItem zero, the actor's side count SideCounts zero, VarNoCasting set) return False at
     once. QUIRK ovl09:049F: RowByte (the Slot byte of the item's ItemTable row) is computed but never read. QUIRK: the
     [bp-5..-6] and [bp-9..-12] frame bytes are never read (UnusedA, UnusedB). Globals: SideCounts
     (PartySideCount), GameVars, ItemTable. */
u8 UseMagicItem(PCharacter Who)
{
  POOL_TRACE("UseMagicItem");
  u8 Result = 0;
  u8 Range = 0;
  u8 Roll = 0;
  u8 I = 0;
  u8 UnusedA[2] = {0};
  u8 RowByte = 0;
  u8 Level = 0;
  u8 UnusedB[4] = {0};
  PItem Target = 0;
  PItem Best = 0;
  u8 E8Done = 0;
  Result = 0;
  Best = 0;
  Range = 7;
  Roll = RollDice(1, 7);
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).CanUseMagicItem == 0) {
    goto L_Done;
  }
  if (SideCounts[(s8)OpposingSide(Who)] <= 0) {
    goto L_Done;
  }
  if ((*FPD(TGameVars (*), GameVars))[229] != 0) {
    goto L_Done;
  }
  {
    u8 limit = Roll;
    if (1 <= limit) {
      I = 1;
      for (;;) {
          Target = (*FPD(TCharacter (*), Who)).Items;
        L_NextItem:
          ;
          if (Target == 0) {
            goto L_NextRound;
          }
          if (Best != 0) {
            goto L_NextRound;
          }
          Level = (*FPD(TMenuLine (*), Target)).Affects[1];
          RowByte = ItemTable[(*FPD(TMenuLine (*), Target)).ItemType].Slot;
          if (!IsScroll(Target)) {
            if ((*FPD(TMenuLine (*), Target)).Affects[2] < 0x80) {
              if ((*FPD(TMenuLine (*), Target)).Readied) {
                if (Level > 0) {
                  if (Level > MaxSpell) {
                    Level = Level - 0x17;
                  }
                  if (SpellAccepted(Who, Level, Range)) {
                    Best = Target;
                  }
                }
              }
            }
          }
        L_Advance:
          ;
          Target = (*FPD(TMenuLine (*), Target)).Next;
          goto L_NextItem;
        L_NextRound:
          ;
          Range--;
        if (I == limit) break;
        I++;
      }
    }
  }
L_Done:
  ;
  if (Best != 0) {
    UseItem(Best, &E8Done);
    Result = 1;
  }
  return Result;
}

/* ovl09:0545. Casts a memorized spell for the computer's turn (called by QuickTurn; the nonzero
     result ends the turn). It collects Who's nonzero Spells (slots 0..20) only when Combat^.CanCast
     is nonzero (+1, the Cast offer of CombatMenu, ovl08:0747). Nothing is tried unless a spell was
     collected, the Magic toggle MagicToggleOn is on (Alt-M: Magic On) or Who is computer-run (B84 above $7F),
     and the actor's side count SideCounts[OpposingSide(Who)] is above 0. Then RollDice(1, 7) rounds
     run with the level starting at 7 and falling by one per round: each round tries up to three random
     memorized spells through SpellAccepted (Who, Spell, Level) and casts the first accepted one through
     CastCombatSpell (the Cast of CombatMenu). This routine does not read VarNoCasting (CombatMenu hides Cast
     with it) or CanUseMagicItem (UseMagicItem's gate). QUIRK: the [bp-0x17..-0x1A] and [bp-0x24] frame
     bytes are never read (UnusedC, UnusedD). Globals: SideCounts (PartySideCount), MagicToggleOn. */
u8 CastMemorizedSpell(PCharacter Who)
{
  POOL_TRACE("CastMemorizedSpell");
  u8 Result = 0;
  u8 SpellList[21] = {0};
  u8 UnusedC[4] = {0};
  u8 Level = 0;
  u8 Roll = 0;
  u8 CastDone = 0;
  u8 Round_ = 0;
  u8 J = 0;
  u8 Count = 0;
  u8 I = 0;
  u8 Spell = 0;
  u8 Chosen = 0;
  u8 UnusedD = 0;
  Count = 0;
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).CanCast != 0) {
    {
      if (0 <= 0x14) {
        I = 0;
        for (;;) {
            if ((*FPD(TCharacter (*), Who)).Spells[I] > 0) {
              SpellList[Count] = (*FPD(TCharacter (*), Who)).Spells[I];
              Count++;
            }
          if (I == 0x14) break;
          I++;
        }
      }
    }
  }
  Chosen = 0;
  Level = 7;
  Roll = RollDice(1, 7);
  Round_ = 1;
  if (Count <= 0) {
    goto L_Done;
  }
  if ((((*FPD(TCharacter (*), Who)).B84 > 0x7F)) || MagicToggleOn) {
    if (SideCounts[(s8)OpposingSide(Who)] > 0) {
      while (((Round_ <= Roll)) && ((Chosen == 0))) {
        J = 1;
        while (((J < 4)) && ((Chosen == 0))) {
          I = RollDice(1, Count) - 1;
          Spell = SpellList[I];
          if (SpellAccepted(Who, Spell, Level)) {
            Chosen = Spell;
          }
          J++;
        }
        Level--;
        Round_++;
      }
    }
  }
L_Done:
  ;
  if (Chosen > 0) {
    CastCombatSpell(Chosen, 1, &CastDone);
  } else {
    CastDone = 0;
  }
  Result = CastDone;
  return Result;
}

/* ovl09:0675. Decides whether the computer's combatant Who can afford the step of attempt
     Column of its step pattern: the direction is BaseDir plus StepTurnOffsets[StepPattern, Column] mod 8,
     ProbeStep looks at the cells; when the probed tile is 0 (off the map, GetMapCell) OffMap is 1
     and the result False at once (ovl09:06EC). Otherwise the result is True when no combatant is
     in the way, the tile cost is below the moves left and the
     step's cost (tile cost times 2, or 3 on a diagonal) is at or below the moves left; a CloudTile
     tile is unaffordable unless Who has one of the four AffectKept affects. Called by MoveStep
     (ovl09:094B). Globals: StepTurnOffsets, CombatTiles. Affect receives the affect
     HasAffect finds and is never read. */
u8 CanAffordStep(PCharacter Who, u8 Column, u8 BaseDir, u8 (*OffMap))
{
  POOL_TRACE("CanAffordStep");
  u8 Result = 0;
  farptr Affect = 0;
  u8 Turn = 0;
  u8 Dir = 0;
  u8 Occupant = 0;
  u8 Tile = 0;
  u8 Cost = 0;
  (*OffMap) = 0;
  Result = 0;
  Turn = StepTurnOffsets[(*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).StepPattern][Column];
  Dir = (((s16)(BaseDir + Turn)) % Directions);
  ProbeStep(Who, Dir, &Occupant, &Tile);
  if (Tile == 0) {
    (*OffMap) = 1;
    return Result;
  }
  if (Occupant == 0) {
    if (CombatTiles[Tile].Cost < (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves) {
      Cost = StraightCost;
      if (Dir & 1) {
        Cost = DiagonalCost;
      }
      Cost = Cost * CombatTiles[Tile].Cost;
      if (Tile == CloudTile) {
        if (!HasAffect(Who, AffectAnimateDead, &Affect)) {
          if (!HasAffect(Who, AffectCough, &Affect)) {
            if (!HasAffect(Who, AffectPoisonImmunity, &Affect)) {
              if (!HasAffect(Who, AffectUndeadImmunity, &Affect)) {
                Cost = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves + 1;
              }
            }
          }
        }
      }
      if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves >= Cost) {
        Result = 1;
      }
    }
  }
  return Result;
}

/* ovl09:07F2 (MoveStep). One step of the AI's move for Who (called by the turn loop at ovl09:0B3C,
     ovl09:0BD3 and 0D7C; the caller loops while the turn lasts): shows 'Move/Attack, Move Left = n'
     with DrawTextAt(0, 24, 10, ...), lets HandleCombatKey interrupt (True ends the step), then gives
     up on the same NoStep path when no half-move is left, the initiative is gone, or a magic-user
     (ClassCombo 5) is not panicking. A clear Panic byte +$14 asks BearingTo(Who, Combat^.Target) for
     the direction; a panicking one rerolls the step pattern (StepPattern, RollDice(1, 2)) and derives a
     direction from the party marker facing PartyFacing (+ 4 on the party side, mod 8). The step then tries
     patterns Step = 1..5 while CanAffordStep refuses them (a panicking actor that is off the map ends
     through TryFlee); with no affordable step, or one that would step back (AiLastDirection = (Turn + 4)
     mod 8), the pattern is advanced (AiStepTurns counts the turns) and the actor may instead end the turn
     through EndOrGuardTurn or ChooseCombatTarget. A step taken sets the icon (SetCombatantIcon with the turn),
     runs PartingShots (or StepCombatant once Flag10D is set past it) and ApplyCloudTile; an ending turn runs
     EndCombatTurn. QUIRK: the jumps to MoveEnd and from there to Finish (ovl09:0B27) are the
     original's; NoStep only computes EndOrGuardTurn. Globals: PartyFacing, AiLastDirection, AiStepTurns. */
void MoveStep(PCharacter Who)
{
  POOL_TRACE("MoveStep");
  u8 Dir = 0;
  u8 Turn = 0;
  u8 Step = 0;
  u8 OffMap = 0;
  u8 Done = 0;
  u8 ts1[256];
  u8 ts2[256];
  DrawTextAt(0, 24, 10, rtl_str_cat(ts2, 3, (const u8 *const[]){S("\031Move/Attack, Move Left = "), ByteToText(ts1, (s16)((u16)(*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves >> 1)), S("\001 ")}));
  if (HandleCombatKey(Who)) {
    return;
  }
  if ((s16)((u16)(*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves >> 1) <= 0) {
    goto L_NoStep;
  }
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative <= 0) {
    goto L_NoStep;
  }
  if ((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Panic == 0)) && (((*FPD(TCharacter (*), Who)).ClassCombo == 5))) {
    goto L_NoStep;
  }
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Panic == 0) {
    Dir = BearingTo(Who, (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target);
  } else {
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).StepPattern = RollDice(1, 2);
    Dir = PartyFacing - ((((((s16)(PartyFacing + 2)) % 4)) / 2));
    if ((*FPD(TCharacter (*), Who)).Side == 0) {
      Dir = Dir + 4;
    }
    Dir = (Dir % Directions);
  }
  OffMap = 0;
  Done = 0;
  Step = 1;
  while ((((Step < 6)) && ((Done == 0))) && !CanAffordStep(Who, Step, Dir, &OffMap)) {
    if ((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Panic != 0)) && ((OffMap != 0))) {
      Done = TryFlee(Who);
    } else {
      Step++;
    }
  }
  if (Done != 0) {
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves = 0;
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Panic = 0;
    Done = EndCombatTurn(Who);
    goto L_AfterMove;
  }
  Turn = (((s16)(Dir + StepTurnOffsets[(*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).StepPattern][Step])) % Directions);
  if (((Step == 6)) || ((AiLastDirection == ((((s16)(Turn + 4)) % Directions))))) {
    AiStepTurns++;
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).StepPattern = ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).StepPattern % 6) + 1;
    if (AiStepTurns > 1) {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target = 0;
      if (AiStepTurns > 2) {
        (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves = 0;
        Done = 1;
        goto L_CheckStep;
      }
      if (!ChooseCombatTarget(Who, 0xFF, 1, 0)) {
        Done = EndOrGuardTurn(Who);
      }
    }
  }
L_CheckStep:
  ;
  if (Step < 6) {
    AiLastDirection = Turn;
  } else {
    Done = 1;
  }
L_AfterMove:
  ;
  if (Done != 0) {
    goto L_MoveEnd;
  }
  SetCombatantIcon(Who, Turn, 0, 0);
  PartingShots(Who, (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).IconSet);
  if ((*FPD(TCharacter (*), Who)).Flag10D == 0) {
    Done = EndCombatTurn(Who);
    goto L_MoveEnd;
  }
  StepCombatant(Who, (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).IconSet);
  if ((*FPD(TCharacter (*), Who)).Flag10D == 0) {
    Done = EndCombatTurn(Who);
  }
  ApplyCloudTile(Who);
L_MoveEnd:
  ;
  goto L_Finish;
  /* QUIRK: the original jumps to MoveEnd and from there to Finish (ovl09:0B27), then runs the
     NoStep block before the epilogue. */
L_NoStep:
  ;
  Done = EndOrGuardTurn(Who);
L_Finish:
  ;
}

/* ovl09:0B3C. The AI's whole turn for Who (called by QuickTurn when the initiative allows). It
     clears the AI scratch (AiLastDirection/D/E) and runs affect hook HookTurnStart ($0E). An initiative of 0
     ends the turn at once. Otherwise the loop (Done = 0 and CanAct <> 0) first, while panicking (Panic,
     +$14), steps with MoveStep for as long as the moves last, the initiative is above 0 and below
     InitiativeQuickAll ($14). Then an initiative of 0 or InitiativeQuickAll ends the turn without any
     action. Each pass counts I: after AiTurnLimit (20) passes Done is set and EndOrGuardTurn decides
     (a nonzero result ends the turn), and the pass still goes on to its attack. The attack range is the
     Range byte (+$C) of the item in slot 0 (SlotItems[0], +$CC) minus 1; a result of 0 or $FF (a Range of
     0 or 1) becomes 1. The remembered Combat^.Target is dropped when it is not dying or is on the party
     side. A target is attacked when line of sight (WalkLine, step count halved) reaches it within Range
     and AttackTargetAllowed allows it; otherwise a random enemy of the CollectEnemiesInRange(Who, Range) scan
     (CombatantScanList) is
     picked, or UseBestItem chooses one when IsRangedWeapon holds, RangedWeaponCanMelee does not and a 1-step
     scan finds an enemy. The attack runs SweepEnemies/e11/e12 and ends the turn through EndCombatTurn.
     Result: 1 when the turn is over (CanAct = 0). The arguments of ChooseCombatTarget ($FF, 0, 0) are Purpose unknown.
     QUIRK ovl09:0C8E: Target := Combat^.Target is
     dereferenced (Target^.Flag10D at 0C91, Target^.Side at 0C9C) before its nil test at 0CAC, so a
     character with no remembered target reads through a nil pointer. QUIRK: [bp-3] is reused for
     ChooseAttackItem's dead result. Globals: AiLastDirection, AiStepTurns, AiScratch, ItemTable, CombatantScanList,
     CombatantRecord,
     CombatMap. */
u8 AiTurn(PCharacter Who)
{
  POOL_TRACE("AiTurn");
  u8 Result = 0;
  u8 Done = 0;
  u8 Flag = 0;
  u8 CanAct = 0;
  u8 Range = 0;
  u16 StepCount = 0;
  u8 Count = 0;
  u8 Index = 0;
  farptr Aim = 0;
  PCharacter Target = 0;
  s8 TargetX = 0;
  s8 TargetY = 0;
  u8 I = 0;
  AiLastDirection = 8;
  AiStepTurns = 0;
  AiScratch = 0;
  I = 0;
  CanAct = 1;
  Done = 0;
  RunAffectHooks(HookTurnStart, Who);
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative == 0) {
    CanAct = 0;
  }
L_Loop:
  ;
  if (Done != 0) {
    goto L_Finish;
  }
  if (CanAct == 0) {
    goto L_Finish;
  }
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Panic != 0) {
    while (((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves > 0)) && (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative > 0))) && (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative < InitiativeQuickAll))) {
      MoveStep(Who);
    }
  }
  if ((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative == 0)) || (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative == InitiativeQuickAll))) {
    CanAct = 0;
  } else {
    Done = 0;
  }
  if (Done != 0) {
    goto L_Next;
  }
  if (CanAct == 0) {
    goto L_Next;
  }
  I++;
  if (I > AiTurnLimit) {
    Done = 1;
    CanAct = (EndOrGuardTurn(Who) == 0);
  }
  Flag = 0;
  Range = 1;
  if ((*FPD(TCharacter (*), Who)).SlotItems[0] != 0) {
    Range = ItemTable[(*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[0])).ItemType].Range - 1;
  }
  if (((Range == 0)) || ((Range == RangeWrapped))) {
    Range = 1;
  }
  Target = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target;
  if ((((*FPD(TCharacter (*), Target)).Flag10D == 0)) || (((*FPD(TCharacter (*), Target)).Side == 0))) {
    Target = 0;
  }
  if (Target != 0) {
    if (AttackTargetAllowed(Who, Target)) {
      TargetX = CombatantX(Target);
      TargetY = CombatantY(Target);
      StepCount = Range;
      if (WalkLine(CombatantX(Who), CombatantY(Who), &TargetX, &TargetY, &StepCount, CombatMap)) {
        if ((u16)((u16)StepCount >> 1) <= Range) {
          Flag = 1;
        }
      }
    }
  }
  if (Flag != 0) {
    goto L_Attack;
  }
  Count = CollectEnemiesInRange(Who, Range);
  if (Count == 0) {
    if (ChooseCombatTarget(Who, 0xFF, 0, 0)) {
      MoveStep(Who);
    } else {
      Done = EndOrGuardTurn(Who);
    }
    goto L_Attack;
  }
  Index = RollDice(1, Count);
  Target = CombatantRecord[CombatantScanList[Index] - 1];
  if (IsRangedWeapon(Who)) {
    if (!RangedWeaponCanMelee(Who)) {
      if (CollectEnemiesInRange(Who, 1) > 0) {
        UseBestItem(Who);
        Done = 1;
        goto L_Attack;
      }
    }
  }
  if (((DistanceToTarget(Who, Target) == 1)) || AttackTargetAllowed(Who, Target)) {
    Flag = 1;
  }
L_Attack:
  ;
  if (Flag != 0) {
    MoveCombatCursor(CombatantX(Who), CombatantY(Who), 2, BearingTo(Who, Target));
  }
  if (Flag == 0) {
    goto L_Next;
  }
  if (SweepEnemies(Who, Target)) {
    Done = EndCombatTurn(Who);
    goto L_Next;
  }
  NoteAttackBearing(Who, Target);
  Aim = 0;
  if (IsRangedWeapon(Who)) {
    Flag = ChooseAttackItem(Who, &Aim);
    if (RangedWeaponCanMelee(Who) && ((DistanceToTarget(Who, Target) == 1))) {
      Aim = 0;
    }
  }
  PerformAttack(Who, Target, 0, Aim, &Done);
  if (Done != 0) {
    CanAct = 0;
    goto L_Next;
  }
  if ((*FPD(TCharacter (*), Target)).Flag10D == 0) {
    Done = 1;
  }
L_Next:
  ;
  goto L_Loop;
L_Finish:
  ;
  Result = (CanAct == 0);
  return Result;
}

/* ovl09:0F4F. returns EndCombatTurn(Who) when IsHelpless(Who) or
     IsRangedWeapon(Who) is true or the combatant's Initiative is 0, else GuardTurn(Who).
     Called by QuickTurn (ovl09:01EE) and from the 07F2 and 0B3C regions. ClearCharacterMessage runs first
     (parameterless). */
u8 EndOrGuardTurn(PCharacter Who)
{
  POOL_TRACE("EndOrGuardTurn");
  u8 Result = 0;
  ClearCharacterMessage();
  if ((IsHelpless(Who) || IsRangedWeapon(Who)) || (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative == 0))) {
    Result = EndCombatTurn(Who);
  } else {
    Result = GuardTurn(Who);
  }
  return Result;
}

/* ovl09:0FC1. Handles a key pressed during the computer's combat turn (called by
     QuickTurn and the 07F2 region, who act when it returns True). Alt-M toggles the MagicToggleOn Magic
     flag with the same 'Magic On'/'Magic Off' message as PlayerTurn (ovl08:031A); Space clears
     Quick on every party member (B84 below $80, Status not 1) and, when Who is not quick yet,
     marks Who quick (Initiative := InitiativeQuickAll) and returns True; Alt-X asks GodsIntervene.
     QUIRK ovl09:10AA: the Alt-X answer is tested and nothing happens either way (empty then).
     QUIRK ovl09:0FD2: the KeyPressed test is inverted with an empty then-branch (if not
     KeyPressed then else). FlushKeyboard always runs at the end. */
u8 HandleCombatKey(PCharacter Who)
{
  POOL_TRACE("HandleCombatKey");
  u8 Result = 0;
  PCharacter Member = 0;
  u8 Key = 0;
  Result = 0;
  if (!rtl_KeyPressed()) {
  } else {
    Key = ReadGameKey();
    if (Key == 0x00) {
      Key = ReadGameKey();
    }
    switch ((u8)Key) {
    case '2':
    {
      MagicToggleOn = !MagicToggleOn;
      if (MagicToggleOn) {
        ShowFlashMessage(S("\010Magic On"));
      } else {
        ShowFlashMessage(S("\011Magic Off"));
      }
      break;
    }
    case ' ':
    {
      Member = PartyListHead;
      while (Member != 0) {
        if ((((*FPD(TCharacter (*), Member)).B84 < 0x80)) && (((*FPD(TCharacter (*), Member)).Status != 1))) {
          (*FPD(TCharacter (*), Member)).Quick = 0;
        }
        Member = (*FPD(TCharacter (*), Member)).Next;
      }
      if ((*FPD(TCharacter (*), Who)).Quick == 0) {
        (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative = InitiativeQuickAll;
        Result = 1;
      }
      break;
    }
    case '-':
    {
      if (GodsIntervene()) {
      }
      break;
    }
    }
  }
  FlushKeyboard();
  return Result;
}

/* ovl09:10D7. The morale check of the computer's turn for Who (QuickTurn calls it when no key was
     pressed). Its result is 0 to go on, or the end of turn through EndCombatTurn after a surrender.
     Panic (+$14) is cleared first. A nonzero ForcedFlight (+$10) forces flight: Panic is set and 'is
     forced to flee' is shown through ShowCharacterMessage, and nothing else is checked. A character with B84
     at or below $7F (not computer-run) is not checked either. Otherwise the morale is MoraleScratch =
     (B84 and $7F) * 2, zeroed above $66, which the hook kind $11 (RunAffectHooks) may change. The first
     test holds when the morale is below the percentage of hit points lost (100 minus HpCurrent * 100
     div HpMax; HpCurrent is the current hit points) or is zero. Then MoraleScratch takes SecondMoraleByte, the hook runs
     again, and the second test holds when it is below 100 minus GameVars2^[Var2Morale] (word 710 of the
     second game word block, $6B00..$6EFF, not GameVars; the morale source of ovl10), or is zero, or Who
     is on the party side (Side 0). Only when both tests hold is there a roll: FastestEnemyMovement at or below half
     of ComputeMovement's value sets Panic and removes affects $4A and $4B (the character panics and the turn
     goes on); a higher roll with Intelligence above 5 surrenders (DropCombatant(Who, 4, 'Surrenders'),
     result EndCombatTurn(Who)); otherwise nothing happens. QUIRK ovl09:1141: the B84 gate is an inverted
     test with an empty then-branch. QUIRK ovl09:11AD: Saved6825 is saved from MoraleScratch and never used.
     Globals: MoraleScratch, SecondMoraleByte, GameVars2 (word Var2Morale). */
u8 CheckMorale(PCharacter Who)
{
  POOL_TRACE("CheckMorale");
  u8 Result = 0;
  u8 E20Result = 0;
  u8 Saved6825 = 0;
  Result = 0;
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Panic = 0;
  RemoveExtraDeathAffects(Who);
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).ForcedFlight != 0) {
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Panic = 1;
    ShowCharacterMessage(Who, S("\021is forced to flee"), 0xA, 1);
  } else if ((*FPD(TCharacter (*), Who)).B84 <= 0x7F) {
  } else {
    MoraleScratch = (((*FPD(TCharacter (*), Who)).B84 & 0x7F)) * 2;
    if (MoraleScratch > 0x66) {
      MoraleScratch = 0;
    }
    RunAffectHooks(0x11, Who);
    if (((MoraleScratch < (s16)(100 - ((s16)((*FPD(TCharacter (*), Who)).HpCurrent * 100) / (*FPD(TCharacter (*), Who)).HpMax)))) || ((MoraleScratch == 0))) {
      Saved6825 = MoraleScratch;
      MoraleScratch = SecondMoraleByte;
      RunAffectHooks(0x11, Who);
      if ((((MoraleScratch < (u16)(100 - (*FPD(TGameVars (*), GameVars2))[710]))) || ((MoraleScratch == 0))) || (((*FPD(TCharacter (*), Who)).Side == 0))) {
        E20Result = FastestEnemyMovement(Who);
        if (E20Result <= (ComputeMovement(Who) / 2)) {
          (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Panic = 1;
          RemoveAffect(Who, 0x4A, 0);
          RemoveAffect(Who, 0x4B, 0);
        } else if ((*FPD(TCharacter (*), Who)).Intelligence > 5) {
          DropCombatant(Who, 4, S("\012Surrenders"));
          Result = EndCombatTurn(Who);
        }
      }
    }
  }
  return Result;
}

/* ovl09:128D (ScoreItem). Rates an item for the AI's item step: UseBestItem calls it for each carried
     item whose class bits fit the character and keeps the highest score (ovl09:1543). Actor is the
     character the step runs for (its Combat^.Target, HandsInUse and Alignment are read); Item is the
     candidate (its ItemType, Plus, Affects and Cursed are read). The score is the item's largest damage
     against normal-size foes (DiceCountNormal times DiceSizeNormal), plus eight times Plus when Plus is
     above 0 (weapons and armour carry a bonus of 1..3, whitepaper 5.4), plus twice BonusNormal when that
     is above 0, plus 2 per attack beyond the first on an attack item (FlagAttack, Attacks), plus 3 when the
     item takes one hand or none. It is 0 when the item's Hands plus the actor's HandsInUse are above 3,
     when Affects[3] is $84 and the low nibble of Affects[2] differs from the actor's Alignment, when Affects[2]
     is $53, or when the item is cursed. Purpose unknown: the $84 and $53 rules, and the score of 8 for an
     item of type $55 when the actor's target's Pad74[TurnUndeadIndex] byte is above 0 (not named yet). Result: the
     score. Globals: ItemTable. */
u8 ScoreItem(PCharacter Actor, PItem Item)
{
  POOL_TRACE("ScoreItem");
  u8 Result = 0;
  u8 Score = 0;
  TItemRow Row = {0};
  Row = ItemTable[(*FPD(TMenuLine (*), Item)).ItemType];
  Score = Row.DiceSizeNormal * Row.DiceCountNormal;
  if ((*FPD(TMenuLine (*), Item)).Plus > 0) {
    Score = Score + ((*FPD(TMenuLine (*), Item)).Plus * 8);
  }
  if (Row.BonusNormal > 0) {
    Score = Score + (Row.BonusNormal * 2);
  }
  if ((*FPD(TMenuLine (*), Item)).ItemType == 0x55) {
    if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Actor)).Combat)).Target != 0) {
      if ((*FPD(TCharacter (*), (*FPD(TCombatant (*), (*FPD(TCharacter (*), Actor)).Combat)).Target)).Pad74[2] > 0) {
        Score = 8;
      }
    }
  }
  if (((Row.Flags & FlagAttack)) > 0) {
    Score = Score + (((s16)(Row.Attacks - 1)) * 2);
  }
  if (Row.Hands <= 1) {
    Score = Score + 3;
  }
  if ((s16)(Row.Hands + (*FPD(TCharacter (*), Actor)).HandsInUse) > 3) {
    Score = 0;
  }
  if ((*FPD(TMenuLine (*), Item)).Affects[2] == 0x84) {
    if ((((*FPD(TMenuLine (*), Item)).Affects[1] & 0xF)) != (*FPD(TCharacter (*), Actor)).Alignment) {
      Score = 0;
    }
  }
  if ((*FPD(TMenuLine (*), Item)).Affects[1] == 0x53) {
    Score = 0;
  }
  if ((*FPD(TMenuLine (*), Item)).Cursed) {
    Score = 0;
  }
  Result = Score;
  return Result;
}

/* ovl09:13CA. The AI's item step for Who (called by QuickTurn every turn and by AiTurn before
     attacking). It first takes the Hands of the slot-0 and slot-1 items off HandsInUse, then scans
     the carried items (Who^.Items). An item of slot kind 0 whose ClassMask shares a bit with the
     character's ClassBits is scored by ScoreItem: an item with the attack flag (FlagAttack) or the
     slot-item flag (FlagSlotItem) that scores above AttackScore (starts at 1) becomes AttackPick; an
     item without FlagAttack that scores above OtherScore becomes OtherPick. OtherScore starts at the
     character's own attack score, BaseDamage[1] times BaseAttacks[1] plus twice BaseDamageBonus[1] when that is
     above 0. An item of slot kind 1 whose ClassMask fits scores its Plus + 1 (0 when Plus is negative),
     and the best of them is PlusPick (PlusScore). Then Candidate, which the scan used as its cursor, is
     the item to use: AttackPick when it scores above half of OtherScore, SlotFound is set and either
     BothKinds (range above 1 and FlagBothKinds in its flags) or no enemy stands within one step
     (CollectEnemiesInRange(Who, 1) = 0); otherwise OtherPick. SlotFound is set when the attack pick's flags name
     a slot: FlagSlotItem makes the pick its own slot, FlagSlot11 with FlagAttack picks SlotItems[SlotType49]
     and FlagSlot12 with FlagAttack picks SlotItems[SlotType1C]; the exact flags FlagsSlotless also count.
     When SlotItems[0] holds the pick or a cursed item the whole slot block is skipped. Otherwise the
     slot-0 item is readied through ReadyItem (the Ready Item entry that the whitepaper's overlay table
     lists for ovl19), the slot-1 item's Hands are taken off again when it is not cursed, and the pick is
     readied. After that
     (SkipSlotUse) RecalcCombatValues and RefreshAttacks run, and HandsInUse decides: above HandThreshold (2) the
     slot-1 item is readied, or the pick when slot 1 is empty or cursed; below it the slot-1 item and then
     PlusPick are readied, unless slot 1 holds PlusPick or a cursed item. A use runs RecalcCombatValues, and a
     use at all ends with DrawCharacterPanel. Purpose unknown: the game names of the slot-0 and slot-1 items
     (weapon and armour is the reading of ovl08 and whitepaper 5.5.3, not proven here). QUIRK: the [bp-1b]
     and [bp-20] frame bytes are never read (Unused1, Unused2). Globals: ItemTable; TCharacter slots
     SlotItems, HandsInUse, ClassBits, BaseAttacks, BaseDamage and BaseDamageBonus. */
void UseBestItem(PCharacter Who)
{
  POOL_TRACE("UseBestItem");
  PItem AttackPick = 0;
  PItem OtherPick = 0;
  PItem PlusPick = 0;
  PItem Candidate = 0;
  PItem SlotPick = 0;
  u8 AttackScore = 0;
  u8 OtherScore = 0;
  u8 PlusScore = 0;
  u8 Score = 0;
  u8 ItemType = 0;
  u8 AttackFlags = 0;
  u8 Unused1 = 0;
  u8 SlotUsable = 0;
  u8 Used = 0;
  u8 BothKinds = 0;
  u8 SlotFound = 0;
  u8 Unused2 = 0;
  if ((*FPD(TCharacter (*), Who)).SlotItems[0] != 0) {
    (*FPD(TCharacter (*), Who)).HandsInUse = (*FPD(TCharacter (*), Who)).HandsInUse - ItemTable[(*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[0])).ItemType].Hands;
  }
  if ((*FPD(TCharacter (*), Who)).SlotItems[1] != 0) {
    (*FPD(TCharacter (*), Who)).HandsInUse = (*FPD(TCharacter (*), Who)).HandsInUse - ItemTable[(*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[1])).ItemType].Hands;
  }
  AttackPick = 0;
  OtherPick = 0;
  PlusPick = 0;
  AttackScore = 1;
  OtherScore = (*FPD(TCharacter (*), Who)).BaseDamage[0] * (*FPD(TCharacter (*), Who)).BaseAttacks[0];
  if ((*FPD(TCharacter (*), Who)).BaseDamageBonus[0] > 0) {
    OtherScore = OtherScore + ((*FPD(TCharacter (*), Who)).BaseDamageBonus[0] * 2);
  }
  PlusScore = 0;
  Candidate = (*FPD(TCharacter (*), Who)).Items;
  while (Candidate != 0) {
    ItemType = (*FPD(TMenuLine (*), Candidate)).ItemType;
    if (ItemTable[ItemType].Slot == 0) {
      if (((ItemTable[ItemType].ClassMask & (*FPD(TCharacter (*), Who)).ClassBits)) == 0) {
        goto L_AfterFirst;
      }
      Score = ScoreItem(Who, Candidate);
      if (((((ItemTable[ItemType].Flags & FlagAttack)) != 0)) || ((((ItemTable[ItemType].Flags & FlagSlotItem)) != 0))) {
        if (Score > AttackScore) {
          AttackPick = Candidate;
          AttackScore = Score;
        }
      }
      if (((ItemTable[ItemType].Flags & FlagAttack)) == 0) {
        if (Score > OtherScore) {
          OtherPick = Candidate;
          OtherScore = Score;
        }
      }
    }
  L_AfterFirst:
    ;
    if (ItemTable[ItemType].Slot == 1) {
      if (((ItemTable[ItemType].ClassMask & (*FPD(TCharacter (*), Who)).ClassBits)) > 0) {
        if ((*FPD(TMenuLine (*), Candidate)).Plus >= 0) {
          Score = (u8)(s16)((*FPD(TMenuLine (*), Candidate)).Plus + 1);
        } else {
          Score = 0;
        }
        if (Score > PlusScore) {
          PlusPick = Candidate;
          PlusScore = Score;
        }
      }
    }
    Candidate = (*FPD(TMenuLine (*), Candidate)).Next;
  }
  if ((((AttackPick != 0)) && ((ItemTable[(*FPD(TMenuLine (*), AttackPick)).ItemType].Range > 1))) && ((((ItemTable[(*FPD(TMenuLine (*), AttackPick)).ItemType].Flags & FlagBothKinds)) == FlagBothKinds))) {
    BothKinds = 1;
  } else {
    BothKinds = 0;
  }
  SlotFound = 0;
  SlotPick = 0;
  AttackFlags = 0;
  if (AttackPick != 0) {
    AttackFlags = ItemTable[(*FPD(TMenuLine (*), AttackPick)).ItemType].Flags;
    if (((AttackFlags & FlagSlotItem)) != 0) {
      SlotPick = AttackPick;
    }
    if (((AttackFlags & FlagAttack)) != 0) {
      if (((AttackFlags & FlagSlot11)) != 0) {
        SlotPick = (*FPD(TCharacter (*), Who)).SlotItems[11];
      }
      if (((AttackFlags & FlagSlot12)) != 0) {
        SlotPick = (*FPD(TCharacter (*), Who)).SlotItems[12];
      }
    }
  }
  if (((SlotPick != 0)) || ((AttackFlags == FlagsSlotless))) {
    SlotFound = 1;
  }
  if (((((AttackPick != 0)) && ((AttackScore > (s16)((u16)OtherScore >> 1)))) && ((SlotFound != 0))) && ((((BothKinds != 0)) || ((CollectEnemiesInRange(Who, 1) == 0))))) {
    Candidate = AttackPick;
  } else {
    Candidate = OtherPick;
  }
  Used = 0;
  SlotUsable = 1;
  if ((*FPD(TCharacter (*), Who)).SlotItems[0] != 0) {
    if ((((*FPD(TCharacter (*), Who)).SlotItems[0] == Candidate)) || (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[0])).Cursed) {
      SlotUsable = 0;
    }
  }
  if (SlotUsable == 0) {
    goto L_SkipSlotUse;
  }
  if ((*FPD(TCharacter (*), Who)).SlotItems[0] != 0) {
    ReadyItem((*FPD(TCharacter (*), Who)).SlotItems[0]);
  }
  RecalcCombatValues(Who);
  if ((*FPD(TCharacter (*), Who)).SlotItems[1] != 0) {
    if (!(*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[1])).Cursed) {
      (*FPD(TCharacter (*), Who)).HandsInUse = (*FPD(TCharacter (*), Who)).HandsInUse - ItemTable[(*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[1])).ItemType].Hands;
    }
  }
  if (Candidate != 0) {
    ReadyItem(Candidate);
  }
  Used = 1;
L_SkipSlotUse:
  ;
  RecalcCombatValues(Who);
  RefreshAttacks(Who);
  SlotUsable = 1;
  if ((*FPD(TCharacter (*), Who)).SlotItems[1] != 0) {
    if ((((*FPD(TCharacter (*), Who)).SlotItems[1] == PlusPick)) || (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[1])).Cursed) {
      SlotUsable = 0;
    }
  }
  if ((*FPD(TCharacter (*), Who)).HandsInUse > HandThreshold) {
    if ((((*FPD(TCharacter (*), Who)).SlotItems[1] == 0)) || (*FPD(TMenuLine (*), (*FPD(TCharacter (*), Who)).SlotItems[1])).Cursed) {
      ReadyItem(Candidate);
      Used = 1;
    } else {
      ReadyItem((*FPD(TCharacter (*), Who)).SlotItems[1]);
      Used = 1;
    }
  } else if ((*FPD(TCharacter (*), Who)).HandsInUse < HandThreshold) {
    if (SlotUsable != 0) {
      if ((*FPD(TCharacter (*), Who)).SlotItems[1] != 0) {
        ReadyItem((*FPD(TCharacter (*), Who)).SlotItems[1]);
      }
      RecalcCombatValues(Who);
      if (PlusPick != 0) {
        ReadyItem(PlusPick);
      }
      Used = 1;
    }
  }
  RecalcCombatValues(Who);
  if (Used != 0) {
    DrawCharacterPanel(Who);
  }
}

/* Initialisation part of unit OVL09. */
void init_OVL09(void)
{
  POOL_TRACE("init");
}
