#include "game.h"

/* ovl08:0000. Frees the combat data after the last round: the DS:6DBB list of $13-byte records,
     the CombatMap block, and the picture DS:6E36 (ReleasePicture). Then RestorePaletteColors0And8, and DS:6B84 becomes
     @ChooseSpellTargets. Called once by RunCombat. The word local is unused; it is there so the frame matches. */
void EndCombat(void)
{
  POOL_TRACE("EndCombat");
  PCombatNode Next = 0;
  u16 Unused = 0;
  while (CloudList != 0) {
    Next = (*FPD(TCombatNode (*), CloudList)).Next;
    rtl_freemem(CloudList, CombatNodeSize);
    CloudList = Next;
  }
  rtl_freemem(CombatMap, CombatMapSize);
  CombatMap = 0;
  ReleasePicture((void *)&CombatAnimationPicture);
  RestorePaletteColors0And8();
  SpellPickerPointer = PROC_ChooseSpellTargets;
}

/* ovl08:007A. The combat loop. Sets the view mode and DS:6B84 := @SelectSpellTargets, runs StartBattle,
     then rounds until one side's count (PartySideCount or EnemySideCount) is zero or EndCombatRound says so.
     Each round calls RecountCombatSides, StartCombatantRound for every combatant on the party list, then turns in
     initiative order (PickNextCombatant, CombatTurn). EndCombat frees the combat data. The byte
     local is unused; it is there so the frame matches. Called by RunAreaEventCommand. */
void RunCombat(void)
{
  POOL_TRACE("RunCombat");
  u8 Done = 0;
  PCharacter Who = 0;
  u8 Unused = 0;
  ViewMode = ViewModeCombat;
  SpellPickerPointer = PROC_SelectSpellTargets;
  StartBattle();
  Done = 0;
  if (((PartySideCount == 0)) || ((EnemySideCount == 0))) {
    Done = 1;
  }
  while (Done == 0) {
    RecountCombatSides();
    Who = PartyListHead;
    while (Who != 0) {
      StartCombatantRound(Who);
      Who = (*FPD(TCharacter (*), Who)).Next;
    }
    (*FPD(TGameVars (*), GameVars2))[715] = 0;
    PickNextCombatant(&Who);
    while (Who != 0) {
      CombatTurn(Who);
      PickNextCombatant(&Who);
    }
    EndCombatRound(&Done);
  }
  EndCombat();
}

/* ovl08:0131. Picks the character who acts next: of the party list (PartyListHead, which holds every
     combatant) the one with the highest positive Combat^.Initiative; each candidate rolls 1d100
     (RollDice) and among equal initiatives the higher roll wins. Best is nil when nobody has an
     initiative above 0 any more, which ends the round in RunCombat. */
void PickNextCombatant(PCharacter (*Best))
{
  POOL_TRACE("PickNextCombatant");
  u8 BestInit = 0;
  u8 BestRoll = 0;
  u8 Roll = 0;
  PCharacter Who = 0;
  u8 Unused = 0;
  BestInit = 0;
  BestRoll = 0;
  Who = PartyListHead;
  while (Who != 0) {
    Roll = RollDice(1, 100);
    if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative > BestInit) {
      BestRoll = Roll;
    }
    if ((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative >= BestInit)) && ((Roll >= BestRoll))) {
      BestRoll = Roll;
      BestInit = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative;
      (*Best) = Who;
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  if (BestInit == NoInitiative) {
    (*Best) = 0;
  }
}

/* ovl08:01F6. One combat turn of Who: clears the per-turn fields BF, B12 and B7, runs the
     RunAffectHooks hook 7 and, while Who still has an initiative, selects it (SelectedCharacter), shows it
     (ShowCursorOn, RecalcCombatValues, DrawCharacterPanel), runs hook $F and lets the computer (QuickTurn, quick
     combat) or the player (PlayerTurn) act; then RedrawMapCell at its position (CombatantX, CombatantY).
     An initiative of InitiativeQuickAll (the Alt-Q fight) counts as $13. */
void CombatTurn(PCharacter Who)
{
  POOL_TRACE("CombatTurn");
  u16 Unused = 0;
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).BF = 0;
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).B12 = 0;
  (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).B7 = 0;
  RunAffectHooks(7, Who);
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative > 0) {
    if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative == InitiativeQuickAll_OVL08) {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative = 19;
    }
    SelectedCharacter = Who;
    ShowCursorOn(Who, 2, 1);
    RecalcCombatValues(Who);
    DrawCharacterPanel(Who);
    RunAffectHooks(0xF, Who);
    if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative > 0) {
      if ((*FPD(TCharacter (*), Who)).Quick != 0) {
        QuickTurn(Who);
      } else {
        PlayerTurn(Who);
      }
    }
    RedrawMapCell(CombatantX(Who), CombatantY(Who));
  }
}

/* ovl08:031A. The player's turn for Who: a character with Flag10D clear ends it at once
     (EndCombatTurn). A pending spell (Combat^.PendingSpell) is cast through CastChosenSpell and ends the
     turn. Otherwise the CombatMenu key is carried out until Done: M Move (MoveCharacter), V View
     (ViewSelectedCharacter), A Aim (RunAimTargets), U Use (RunItemMenu), C Cast (CastCombatSpell), T Turn (TurnUndead), Q
     Quick (SetQuickCombat, the computer finishes the turn), D Done (EndTurnMenu), Space takes
     every character with B84 below $80 out of quick combat, and the Alt keys: Alt-M toggles Magic On/Off
     (MagicToggleOn), Alt-Q makes
     everybody quick, Alt-X asks GodsIntervene. After each command that does not end the turn the
     character is shown again. Done is the turn-ended flag the commands set. */
void PlayerTurn(PCharacter Who)
{
  POOL_TRACE("PlayerTurn");
  u8 Cmd = 0;
  u8 Done = 0;
  PCharacter Member = 0;
  u8 Aim[7] = {0};
  u8 Spell = 0;
  if ((*FPD(TCharacter (*), Who)).Flag10D != 0) {
    if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).PendingSpell > 0) {
      Spell = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).PendingSpell;
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).PendingSpell = 0;
      CastChosenSpell(Spell, 0, 1, &Done);
      Done = EndCombatTurn(Who);
    } else {
      Done = 0;
      while (Done == 0) {
        CombatMenu(Who, &Cmd);
        switch ((u8)Cmd) {
        case 'M':
        {
          MoveCharacter(Who, &Done);
          break;
        }
        case 'V':
        {
          ViewSelectedCharacter(&Done);
          RefreshAttacks(Who);
          if (Done == 0) {
            DrawCombatScreen();
          }
          break;
        }
        case 'A':
        {
          RunAimTargets(Who, 0xFF, 1, 0, &Done, (void *)&Aim);
          break;
        }
        case 'U':
        {
          RunItemMenu(&Done);
          RefreshAttacks(Who);
          if (Done == 0) {
            DrawCombatScreen();
          }
          break;
        }
        case 'C':
        {
          CastCombatSpell(0, 0, &Done);
          break;
        }
        case 'T':
        {
          TurnUndead(Who);
          Done = EndCombatTurn(Who);
          break;
        }
        case 'Q':
        {
          SetQuickCombat(Who);
          ClearPromptLine();
          FlushKeyboard();
          rtl_Delay(200);
          Done = 1;
          QuickTurn(Who);
          break;
        }
        case 'D':
        {
          EndTurnMenu(Who, &Done);
          break;
        }
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
            if ((*FPD(TCharacter (*), Member)).B84 < 0x80) {
              (*FPD(TCharacter (*), Member)).Quick = 0;
            }
            Member = (*FPD(TCharacter (*), Member)).Next;
          }
          break;
        }
        case 0x10:
        {
          (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative = InitiativeQuickAll_OVL08;
          Member = PartyListHead;
          while (Member != 0) {
            SetQuickCombat(Member);
            Member = (*FPD(TCharacter (*), Member)).Next;
          }
          ClearPromptLine();
          rtl_Delay(200);
          Done = 1;
          break;
        }
        case '-':
        {
          if (GodsIntervene()) {
            ShowCursorOn(Who, 3, 0);
            Done = 1;
          } else {
            ShowFlashMessage(S("\021That doesn't work"));
          }
          break;
        }
        }
        if (Done == 0) {
          ShowCursorOn(Who, 2, 1);
          DrawCharacterPanel(Who);
        }
      }
    }
  } else {
    Done = EndCombatTurn(Who);
  }
}

/* ovl08:0666. Shows the combat menu of Who and returns the key in Cmd: Move while it has moves
     left, View Aim, Use when it carries items, Cast when it has a memorized spell, may cast and the
     game variable VarNoCasting is 0, Turn for a cleric (ClassLevels[0]) that has not turned yet, and
     Quick Done. With the key flag of ReadPromptChoice set only the Alt keys pass; the menu repeats until one
     of the command keys of PlayerTurn comes. Flag first records whether a spell is memorized, then
     holds ReadPromptChoice's key flag. */
void CombatMenu(PCharacter Who, u8 (*Cmd))
{
  POOL_TRACE("CombatMenu");
  u8 Menu[41] = {0};
  u8 I = 0;
  u8 Flag = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  u8 t5[256];
  u8 t6[256];
  s32 t7;
  s32 t8;
  RunAffectHooks(0xF, Who);
  rtl_str_assign(Menu, 40, S("\000"));
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves > 0) {
    rtl_str_assign(Menu, 40, rtl_str_cat(t1, 2, (const u8 *const[]){Menu, S("\005Move ")}));
  }
  rtl_str_assign(Menu, 40, rtl_str_cat(t2, 2, (const u8 *const[]){Menu, S("\011View Aim ")}));
  if ((*FPD(TCharacter (*), Who)).ItemCountC7 > 0) {
    rtl_str_assign(Menu, 40, rtl_str_cat(t3, 2, (const u8 *const[]){Menu, S("\004Use ")}));
  }
  Flag = 0;
  {
    if (0 <= 20) {
      I = 0;
      for (;;) {
          if ((*FPD(TCharacter (*), Who)).Spells[I] > 0) {
            Flag = 1;
          }
        if (I == 20) break;
        I++;
      }
    }
  }
  if ((((Flag != 0)) && (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).CanCast != 0))) && (((*FPD(TGameVars (*), GameVars))[229] == 0))) {
    rtl_str_assign(Menu, 40, rtl_str_cat(t4, 2, (const u8 *const[]){Menu, S("\005Cast ")}));
  }
  if ((((*FPD(TCharacter (*), Who)).ClassLevels[0] > 0)) && (((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Turned == 0))) {
    rtl_str_assign(Menu, 40, rtl_str_cat(t5, 2, (const u8 *const[]){Menu, S("\005Turn ")}));
  }
  rtl_str_assign(Menu, 40, rtl_str_cat(t6, 2, (const u8 *const[]){Menu, S("\012Quick Done")}));
  do {
    (*Cmd) = ReadPromptChoice(S("\000"), Menu, 0xD, 0xA, MenuColors, 1, 0, &Flag);
    if (((Flag != 0)) && !(((t7 = (*Cmd)), (t7 == KeyQuickAll || t7 == KeyAltR || t7 == KeyAltX_OVL08 || t7 == KeyAltM_OVL08)))) {
      (*Cmd) = 0x00;
    }
  } while (!((t8 = (*Cmd)), (t8 == KeyQuickAll || t8 == KeyAltR || t8 == ' ' || t8 == KeyAltX_OVL08 || t8 == KeyAltM_OVL08 || t8 == 'A' || t8 == 'C' || t8 == 'D' || t8 == 'M' || t8 == 'Q' || t8 == 'T' || t8 == 'U' || t8 == 'V')));
}

/* ovl08:0880. The end of a combat round: AdvanceGameClock(1, 1), the round counter CombatRound, UpdateMonsterMorale,
     then for each character the RunAffectHooks hook $13 and ApplyCloudTile; a dying character (StatusDying)
     bleeds one more round and after LastDyingRound rounds is StatusDead. Warns Your Teammate is
     Dying while a party member can be bandaged, redraws the map around the CombatMap view position
     (MoveCombatCursor), and sets Done when one side is empty (PartySideCount or EnemySideCount zero). When only the
     enemies are gone and SuppressContinuePrompt is 0 it asks Continue Battle: and Y clears Done again. Index is
     counted but never used. */
void EndCombatRound(u8 (*Done))
{
  POOL_TRACE("EndCombatRound");
  PCharacter Who = 0;
  u8 Unused = 0;
  u8 Index = 0;
  AdvanceGameClock(1, 1);
  CombatRound++;
  UpdateMonsterMorale();
  Who = PartyListHead;
  Index = 1;
  while (Who != 0) {
    RunAffectHooks(0x13, Who);
    ApplyCloudTile(Who);
    if ((*FPD(TCharacter (*), Who)).Status == StatusDying) {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).DyingRounds++;
      if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).DyingRounds > LastDyingRound) {
        (*FPD(TCharacter (*), Who)).Status = StatusDead;
      }
    }
    Index++;
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  if (BandageDying(0) != 0) {
    ShowFlashMessage(S("\026Your Teammate is Dying"));
  }
  RecountCombatSides();
  MoveCombatCursor((s16)((*FPD(TCombatMap (*), CombatMap)).ViewX + 3), (s16)((*FPD(TCombatMap (*), CombatMap)).ViewY + 3), 0xFF, 8);
  if (((PartySideCount == 0)) || ((EnemySideCount == 0))) {
    (*Done) = 1;
  }
  if ((((PartySideCount > 0)) && ((EnemySideCount == 0))) && ((SuppressContinuePrompt == 0))) {
    if (AskYesNo(S("\020Continue Battle:"), 0xD, 0xA, MenuColors) == 'Y') {
      (*Done) = 0;
    }
  }
}

/* ovl08:09DF. The Move command: while Who has more than one half-move left the prompt Move/Attack,
     Move Left = n takes keypad keys (KeyUp..KeyHome give the directions 0..7). A step towards a
     combatant attacks it (MeleeAttack, CombatantRecord by the number ProbeStep returns); a step off the map
     asks Flee: (TryFlee on Y); a step whose ground costs more than the moves left says Blocked;
     otherwise PartingShots and StepCombatant move the character, and a character whose Flag10D clears or
     for whom IsHelpless says so ends the turn (EndCombatTurn). Key #0 (Esc on the prompt) takes
     the move back: the saved moves, position (PlaceCombatant) and B9 return. Fewer than two half-moves
     left become 0. */
void MoveCharacter(PCharacter Who, u8 (*Done))
{
  POOL_TRACE("MoveCharacter");
  u8 SavedMoves = 0;
  u8 SavedIconSet = 0;
  u8 Col = 0;
  u8 Row = 0;
  u16 Unused = 0;
  u8 Dir = 0;
  u8 Other = 0;
  u8 Ground = 0;
  u8 Key = 0;
  u8 t1[256];
  u8 t2[256];
  SavedMoves = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves;
  SavedIconSet = (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).IconSet;
  Col = CombatantX(Who);
  Row = CombatantY(Who);
  Key = ' ';
  (*Done) = 0;
  Dir = NoDirection;
  while (((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves > 1)) && ((Key != 0x00))) && ((Key != 0x0D))) {
    ClearWindow(0x18, 0x18, 0x27, 0x18);
    Key = ReadPromptChoice(rtl_str_cat(t2, 3, (const u8 *const[]){S("\031Move/Attack, Move Left = "), ByteToText(t1, (s16)((u16)(*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves >> 1)), S("\001 ")}), S("\000"), 0xA, 0xA, MenuColors, 1, 0, &CombatScratchFlag);
    switch ((u8)Key) {
    case 0x00:
    {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves = SavedMoves;
      RedrawGround(0, 0, CombatantIndex(Who));
      (*Done) = !PlaceCombatant(Who, Col, Row, 0);
      MoveCombatCursor(CombatantX(Who), CombatantY(Who), 0, 8);
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).IconSet = SavedIconSet;
      Dir = NoDirection;
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
    default:
    {
      Dir = NoDirection;
    }
    }
    if (Dir < NoDirection) {
      SetCombatantIcon(Who, Dir, 0, 0);
      ProbeStep(Who, Dir, &Other, &Ground);
      if (Other > 0) {
        MeleeAttack(Who, CombatantRecord[Other - 1], &(*Done));
      } else if (Ground == 0) {
        switch ((u8)AskYesNo(S("\005Flee:"), 0xD, 0xA, MenuColors)) {
        case 'Y':
        {
          (*Done) = TryFlee(Who);
          break;
        }
        case 'N':
        {
          (*Done) = 0;
          break;
        }
        }
      } else if (CombatTiles[Ground].Cost > (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves) {
        ShowFlashMessage(S("\007Blocked"));
      } else {
        PartingShots(Who, Dir);
        if ((*FPD(TCharacter (*), Who)).Flag10D == 0) {
          (*Done) = EndCombatTurn(Who);
        } else {
          StepCombatant(Who, Dir);
          if ((*FPD(TCharacter (*), Who)).Flag10D == 0) {
            (*Done) = EndCombatTurn(Who);
          }
          ApplyCloudTile(Who);
          if (IsHelpless(Who)) {
            (*Done) = EndCombatTurn(Who);
          }
        }
      }
    }
  }
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves < 2) {
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Moves = 0;
  }
}

/* ovl08:0D45. Attacker attacks Target in melee: refused with Not with that weapon when
     IsRangedWeapon holds and RangedWeaponCanMelee does not (a weapon that cannot strike in melee, by the
     message); otherwise when ConfirmAttackTarget allows the attack Target becomes Attacker's Combat^.Target and
     either SweepEnemies ends the turn (Done := 1) or NoteAttackBearing and PerformAttack carry the attack out. */
void MeleeAttack(PCharacter Attacker, PCharacter Target, u8 (*Done))
{
  POOL_TRACE("MeleeAttack");
  if (IsRangedWeapon(Attacker) && !RangedWeaponCanMelee(Attacker)) {
    ShowFlashMessage(S("\024Not with that weapon"));
  } else if (ConfirmAttackTarget(Attacker, Target)) {
    (*FPD(TCombatant (*), (*FPD(TCharacter (*), Attacker)).Combat)).Target = Target;
    if (SweepEnemies(Attacker, Target)) {
      (*Done) = 1;
    } else {
      NoteAttackBearing(Attacker, Target);
      PerformAttack(Attacker, Target, 0, 0, &(*Done));
    }
  }
}

/* ovl08:0E45. The Done command's menu for Who: Guard (offered unless Not with that weapon would
     apply, GuardTurn), Delay (initiative InitiativeLast: act at the end of the round), Quit (end
     the turn), Bandage (when BandageDying finds a dying party member), Speed (GameSpeedMenu) and
     Exit. Repeats until Exit, Esc or a command that ends the turn. */
void EndTurnMenu(PCharacter Who, u8 (*Done))
{
  POOL_TRACE("EndTurnMenu");
  u8 Menu[41] = {0};
  u8 Key = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  (*Done) = 0;
  rtl_str_assign(Menu, 40, S("\000"));
  if (!IsRangedWeapon(Who) || RangedWeaponCanMelee(Who)) {
    rtl_str_assign(Menu, 40, rtl_str_cat(t1, 2, (const u8 *const[]){Menu, S("\006Guard ")}));
  }
  rtl_str_assign(Menu, 40, rtl_str_cat(t2, 2, (const u8 *const[]){Menu, S("\013Delay Quit ")}));
  if (BandageDying(0) != 0) {
    rtl_str_assign(Menu, 40, rtl_str_cat(t3, 2, (const u8 *const[]){Menu, S("\010Bandage ")}));
  }
  rtl_str_assign(Menu, 40, rtl_str_cat(t4, 2, (const u8 *const[]){Menu, S("\012Speed Exit")}));
  Key = ' ';
  while (!((Key == 0x00 || Key == 'E')) && (((*Done) == 0))) {
    Key = ReadPromptChoice(S("\000"), Menu, 0xD, 0xA, MenuColors, 0, 0, &CombatScratchFlag);
    switch ((u8)Key) {
    case 'G':
    {
      (*Done) = GuardTurn(Who);
      break;
    }
    case 'D':
    {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Initiative = InitiativeLast;
      (*Done) = 1;
      break;
    }
    case 'Q':
    {
      (*Done) = EndCombatTurn(Who);
      break;
    }
    case 'B':
    {
      (*Done) = BandageDying(1);
      (*Done) = EndCombatTurn(Who);
      break;
    }
    case 'S':
    {
      GameSpeedMenu();
      break;
    }
    }
  }
}

/* ovl08:0FFF. Returns 1 when a party character (Side 0) is dying (StatusDying) and may be
     bandaged (Combat^.NoBody 0), else 0. With DoIt nonzero the first one found is bandaged: Status
     StatusUnconscious, the bleeding count reset and the message is bandaged (ShowCharacterMessage). */
u8 BandageDying(u8 DoIt)
{
  POOL_TRACE("BandageDying");
  u8 Result = 0;
  PCharacter Who = 0;
  u8 Found = 0;
  Found = 0;
  Who = PartyListHead;
  while (Who != 0) {
    if (((((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).NoBody == 0)) && (((*FPD(TCharacter (*), Who)).Side == 0))) && (((*FPD(TCharacter (*), Who)).Status == StatusDying))) {
      Found = 1;
      if (DoIt != 0) {
        (*FPD(TCharacter (*), Who)).Status = StatusUnconscious;
        (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).DyingRounds = 0;
        ShowCharacterMessage(Who, S("\013is bandaged"), 10, 1);
        DoIt = 0;
      }
    }
    Who = (*FPD(TCharacter (*), Who)).Next;
  }
  Result = Found;
  return Result;
}

/* ovl08:10F6. The game speed menu: GameSpeed (n) : with Slower (while below MaxGameSpeed, raises
     GameSpeed), Faster (while above 0, lowers it) and Exit; repeats until Exit or Esc. */
void GameSpeedMenu(void)
{
  POOL_TRACE("GameSpeedMenu");
  u8 Menu[41] = {0};
  u8 Title[41] = {0};
  u8 Key = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  u8 t5[256];
  Key = ' ';
  while (!((Key == 0x00 || Key == 'E'))) {
    rtl_str_assign(Title, 40, rtl_str_cat(t2, 3, (const u8 *const[]){S("\013GameSpeed ("), ByteToText(t1, GameSpeed), S("\003) :")}));
    rtl_str_assign(Menu, 40, S("\001 "));
    if (GameSpeed < MaxGameSpeed) {
      rtl_str_assign(Menu, 40, rtl_str_cat(t3, 2, (const u8 *const[]){Menu, S("\007Slower ")}));
    }
    if (GameSpeed > 0) {
      rtl_str_assign(Menu, 40, rtl_str_cat(t4, 2, (const u8 *const[]){Menu, S("\007Faster ")}));
    }
    rtl_str_assign(Menu, 40, rtl_str_cat(t5, 2, (const u8 *const[]){Menu, S("\004Exit")}));
    Key = ReadPromptChoice(Title, Menu, 0xD, 0xA, MenuColors, 0, 0, &CombatScratchFlag);
    switch ((u8)Key) {
    case 'S':
    {
      GameSpeed++;
      break;
    }
    case 'F':
    {
      GameSpeed--;
      break;
    }
    }
  }
}

/* ovl08:122B. Puts Who in quick combat (Quick := 1, the computer plays it from now on) and drops
     its remembered Combat^.Target when that target is on its own side. */
void SetQuickCombat(PCharacter Who)
{
  POOL_TRACE("SetQuickCombat");
  (*FPD(TCharacter (*), Who)).Quick = 1;
  if ((*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target != 0) {
    if ((*FPD(TCharacter (*), (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target)).Side == (*FPD(TCharacter (*), Who)).Side) {
      (*FPD(TCombatant (*), (*FPD(TCharacter (*), Who)).Combat)).Target = 0;
    }
  }
}

/* Initialisation part of unit OVL08. */
void init_OVL08(void)
{
  POOL_TRACE("init");
}
