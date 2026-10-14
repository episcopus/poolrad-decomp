unit OVL13;
{ CombatSpells: the combat actions overlay (whitepaper 5.5). RunCombat calls it to set up every
  combatant's round (ComputeMovement and StartCombatantRound), to move a combatant on the combat map (StepCombatant
  and PartingShots), and to resolve what a combat action does; the ovl13_eN entry points are the ones
  the combat menu and the combat AI call. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure StartCombatantRound(Who: PCharacter);
function ComputeMovement(Who: PCharacter): Byte;
procedure RollAttackDamage(Attacker: PCharacter; Target: PCharacter; Index: Byte);
procedure ShowAttackResult(Attacker: PCharacter; Target: PCharacter; Kind, SpellFlag, Damage, Hit: Byte);
procedure GuardedEnemiesAttack(Who: PCharacter);
procedure StepCombatant(Who: PCharacter; Dir: Byte);
procedure ovl13_fn_08AC;
procedure PartingShots(Who: PCharacter; Dir: Byte);
function TryFlee(Who: PCharacter): Byte;
procedure RefreshAttacks(Who: PCharacter);
function AttacksThisRound(DoubledAttacks: Byte): Byte;
function SweepEnemies(Who, Target: PCharacter): Boolean;
procedure ovl13_fn_0FBF;
procedure ovl13_fn_104E;
function ovl13_e8(Who, Target: Pointer): Boolean;
procedure ovl13_e9(Who: Pointer);
procedure ovl13_fn_11D8;
function ovl13_e10(Who: Pointer; var B: Byte): Boolean;
procedure ovl13_fn_1406;
procedure ovl13_fn_14A1;
procedure ovl13_fn_1583;
procedure ovl13_fn_1713;
procedure ovl13_fn_1758;
procedure ovl13_e11(Who, Target: Pointer);
procedure ovl13_e12(Who, Target: Pointer; A: Byte; P: Pointer; var Done: Byte);
procedure ovl13_fn_1B1E;
procedure ovl13_fn_1BD7;
function ovl13_e13(P: Pointer; var B: Byte): Boolean;
procedure ovl13_fn_1C13;
procedure ovl13_fn_1D08;
procedure ovl13_fn_1E16;
procedure ovl13_fn_202B;
procedure ovl13_fn_20A9;
procedure ovl13_e14;
procedure ovl13_fn_2233;
procedure ovl13_fn_228C;
procedure ovl13_fn_2383;
procedure ovl13_fn_23B6;
procedure ovl13_e15(A, B: Byte; var Done: Byte);
procedure ovl13_fn_2432;
function ovl13_fn_2574(Who: PCharacter; Target: PCharacter): Boolean;
procedure ovl13_fn_257E;
procedure ovl13_fn_25C9;
function ovl13_e18(Who, Target: Pointer): Byte;
procedure ovl13_fn_26B0;
procedure ovl13_e19;
function ovl13_e20(Who: Pointer): Byte;
function ovl13_e16(Who, Target: Pointer): Boolean;
procedure ovl13_fn_2AA0;
procedure ovl13_fn_2B8B;
procedure ovl13_fn_2C3D;
procedure ovl13_fn_2D39;
procedure ovl13_fn_2DC8;
procedure ovl13_fn_2DFA;
procedure ovl13_fn_2F57;
procedure ovl13_fn_2F7B;
procedure ovl13_fn_2FD3;
procedure ovl13_fn_30FB;
procedure ovl13_fn_31D7;
procedure ovl13_fn_32E6;
procedure ovl13_fn_3389;
procedure ovl13_e17(Who: Pointer; A, B, C: Byte; var Done: Byte; var Aim);
procedure ovl13_fn_3728;
function ovl13_e21(Who: Pointer; A, B, C: Byte): Boolean;
procedure ovl13_fn_39A3;
procedure ovl13_e22;
procedure ovl13_fn_39E6;
procedure ovl13_fn_3A2B;
procedure ovl13_e23;
function ovl13_e24: Boolean;
implementation
uses RES03, RES06, RES12, OVL24, OVL30, OVL31;
const
  { The two sides of a combat (POOLVARS, ovl24:0D96). }
  SideParty = 0;
  { The round's Movement is capped at this before it is doubled into the half-square move
    budget (ovl13:0155..0165). }
  MaxMovement = $60;
  { Word 882 of ds49D6^ (byte offset $6E4): added to a party member's Movement each round
    (ovl13:0137). ovl05 calls the same word VarAfterBattle3 and EndBattle clears it; what it
    holds during a combat is not settled. }
  VarPartyMovementBonus = 882;
  { RunAffectHooks kinds (ovl24:02FA). }
  HookComputeMovement = $12;   { run while a combatant's round Movement is worked out }
  { ovl13's attack damage runs kind 4 on the attacker and kind 5 on the target after DamageAmount
    is rolled (ovl13:0212, 0220). ovl24's own table documents kinds 6, 9, $A, $C, $D and $10, so
    what 4 and 5 change is not known there. }
  HookAttackerDamage = 4;
  HookTargetDamage = 5;
  HookGoesDown = $D;           { run when a combatant goes down (ovl13:05F1, ovl24's HookGoesDown) }
  { TCharacter.Status (+$10C) values the death message tests (ovl13:0583, 05AC). }
  StatusDying = 5;
  { The status a fleeing combatant is dropped with (ovl13:0CE1; the same 3 as ovl24's StatusFled). }
  StatusFled = 3;
  { The statuses that show 'is killed': the set [6, 7, 8] at ovl13:02CF (the original bytes
    c0 01 00.. at that address are bits 6, 7 and 8). Status 5 (dying) gets 'and is Dying' instead. }
  StatusKilled = [6, 7, 8];
  { The backstab multiplier is the thief level (ClassLevels[6]) div 4 plus 2 (ovl13:01F2). The
    original shifts the level one bit at a time (shr 1 twice), not `shr 2`, so keep both shifts. }
  BackstabLevelStep = 1;
  BackstabMultiplierBase = 2;
  { The initiative a round setup rolls: 1d6 plus the dexterity adjustment, then clamped. }
  InitiativeDieSides = 6;
  InitiativePenalty = 6;       { when the round penalty word matches the side, ovl13:00D9 }
  MaxInitiative = $14;
  { Word 715 of ds49D6^ (byte offset $596): RunCombat clears it every round (ovl08:00A2). In
    ovl13:00C2 a combatant whose (Side + 1) shares a bit with it loses InitiativePenalty; what
    the word is filled with is not settled (named VarCombatWord715 in ovl08). }
  VarCombatWord715 = 715;
  { The two affects an enemy must not carry to take a parting shot (ovl13:0A91, 0AAB). ovl24
    removes the same pair when a combatant goes down or panics (ovl24:0322, 0336) and ovl24_e14
    removes them too, so what they mean is not settled (whitepaper 5.5). }
  AffectNoPartingShot1 = $4B;
  AffectNoPartingShot2 = $4A;
  { The direction scan of a parting shot: the attacker's icon set plus 6 through plus 10 approach
    the target's cell (ovl13:0AC7..0AF4); the compass direction tried each step is its index mod 8. }
  PartingShotFirstOffset = 6;
  PartingShotLastOffset = 10;
  Directions = 8;
  { CollectEnemiesInRange's range byte for "every enemy" (the $FF ovl13:0C7A passes when a flee is
    tried; range 1 is the adjacent ring). }
  AllEnemiesRange = $FF;

{ ovl13:0000. Sets up Who's turn at the start of a combat round: clears and re-arms its combat
  state Combat^ (PendingSpell 0, Cast and Use-magic allowed), refreshes it through RefreshAttacks, lets
  the hooks change the attack byte ds681A (RunAffectHooks $12) and stores the result in the
  readied-weapon block (+$114); then, for a character still in the fight (Flag10D set), rolls its
  initiative (1d6 plus DexterityAttackAdjustment, at least 1, 6 lower when the round penalty word
  matches its side, else 0 outside 0..$14), and finally gives it this round's move budget
  (ComputeMovement). Called for every combatant at the start of each round (RunCombat ovl08:0063).
  The body is a `with Who^.Combat^ do` block (the compiler caches the pointer in a hidden temp
  below the locals, reloaded before every field access). QUIRK ovl13:0093: the one named byte
  local is declared and never read; it is what makes the frame 6 bytes. }
procedure StartCombatantRound(Who: PCharacter);
var
  Unused: Byte;                  { QUIRK ovl13:0093: declared, never read }
begin
  with Who^.Combat^ do
  begin
    PendingSpell := 0;
    CanCast := 1;
    CanUseMagicItem := 1;
    Pad8 := 0;
    Pad4[4] := 2;
    RefreshAttacks(Who);
    ds681A := Who^.PadA2;
    ds681D := False;
    RunAffectHooks(HookComputeMovement, Who);
    Who^.AttackSlots[2] := AttacksThisRound(ds681A);
    Pad4[5] := Who^.Pad6B;
    if Who^.Flag10D <> 0 then
    begin
      Initiative := RollDice(1, InitiativeDieSides) + DexterityAttackAdjustment(Who);
      if Initiative < 1 then
        Initiative := 1;
      { QUIRK ovl13:00C5: the original widens Side with cbw (a sign extend) and ANDs it with a
        16-bit signed word, then tests the low byte only; the casts reproduce that shape (Side is
        a Byte elsewhere: ovl09 and res12 compare it unsigned). }
      if Byte((ShortInt(Who^.Side) + 1) and Integer(ds49D6^[VarCombatWord715])) <> 0 then
        Dec(Initiative, InitiativePenalty);
      if (Initiative < 0) or (Initiative > MaxInitiative) then
        Initiative := 0;
    end
    else
      Initiative := 0;
  end;
  Who^.Combat^.Moves := ComputeMovement(Who);
end;
{ ovl13:0123. Works out how far Who may move this round: its Movement (+$11C), raised by the
  party movement word during combat, is clamped to 1..$60, doubled into half squares and offered
  to the movement affect hooks (RunAffectHooks $12, which may still change it), and the doubled
  value is left in ds681A and returned. Called once per character at the start of each combat
  round (RunCombat ovl08:0063). ds681D brackets the hook run. }
function ComputeMovement(Who: PCharacter): Byte;
var
  Moves: Byte;
begin
  Moves := Who^.Movement;
  if Who^.Side = SideParty then
    Moves := Moves + ds49D6^[VarPartyMovementBonus];
  ds681D := True;
  if (Moves < 1) or (Moves > MaxMovement) then
    Moves := 1;
  ds681A := Moves * 2;
  RunAffectHooks(HookComputeMovement, Who);
  ds681D := False;
  ComputeMovement := ds681A;
end;
{ ovl13:0191. Rolls the damage of one attack of Attacker against Target: entry Index (1 or 2)
  of the readied weapon's attack triple gives the dice count and die size (RollDiceCounted) and the
  signed bonus (WeaponDamageBonus). The total goes to DamageAmount, a nonsensical negative clamp
  (QUIRK ovl13:01D2) is kept, a special attack (ovl13_fn_2574, the backstab) multiplies the damage
  by the thief level div 4 + 2, DamageKind becomes 0 and the damage hooks run for the attacker (4)
  and the target (5). Called for each of a combatant's attacks. }
procedure RollAttackDamage(Attacker: PCharacter; Target: PCharacter; Index: Byte);
begin
  DamageAmount := RollDiceCounted(Attacker^.WeaponAttacks[Index], Attacker^.WeaponDamage[Index])
    + Attacker^.WeaponDamageBonus[Index];
  if DamageAmount < 0 then
    DamageAmount := 0;
  if ovl13_fn_2574(Attacker, Target) then
    DamageAmount := DamageAmount * ((Attacker^.ClassLevels[6] shr BackstabLevelStep
      shr BackstabLevelStep) + BackstabMultiplierBase);
  DamageKind := 0;
  RunAffectHooks(HookAttackerDamage, Attacker);
  RunAffectHooks(HookTargetDamage, Target);
end;
{ ovl13:02F9. Shows the result of one melee attack in the combat window: it builds the message
  ('Attacks', ' -Backstabs-' or 'slays helpless' with '(from behind) ' when Kind is 1), names
  Target and, on a hit, adds 'Hitting for <Damage> point(s) of damage' (or 'with one cruel blow'
  for Kind 3) and applies the damage to Target through ApplyDamage; on a miss it adds 'and
  Misses'. The text is paged out (ShowPagedText). Then, when SpellFlag is set, Target cannot cast
  and loses a pending spell ('lost a spell'); a Target still in the fight that went down shows
  'goes down' (and 'and is Dying' at Status 5, else 'is killed' unless Status is in
  StatusNoKillMsg), loses its death affects and runs the death hooks; one that dies leaves the map
  through RemoveCombatant. Called from ovl13_fn_14A1/1713/1758 with the attacker, the target, the
  kind, the spell flag, the damage and the hit flag. }
procedure ShowAttackResult(Attacker: PCharacter; Target: PCharacter; Kind, SpellFlag, Damage, Hit: Byte);
var
  Row: Byte;
  Text: string[80];
begin
  case Kind of
    2: Text := '-Backstabs-';
    3: Text := 'slays helpless';
  else
    Text := 'Attacks';
  end;
  ShowCharacterMessage(Attacker, Text, 10, 0);
  Row := 12;
  DrawCharacterName(Target, 23, Row, 0);
  Inc(Row);
  if Kind = 1 then
    Text := '(from behind) '
  else
    Text := '';
  if Hit <> 0 then
  begin
    if Kind = 3 then
      Text := 'with one cruel blow'
    else
    begin
      Text := Text + 'Hitting for ' + ByteToText(Damage);
      if Damage = 1 then
        Text := Text + ' point '
      else
        Text := Text + ' points ';
      Text := Text + 'of damage';
    end;
    ApplyDamage(Target, SpellFlag);
  end
  else
    Text := Text + 'and Misses';
  ShowPagedText(23, Row, 38, Row + 3, 10, 1, Text);
  Row := GlyphRow + 1;
  if SpellFlag > 0 then
  begin
    Target^.Combat^.CanCast := 0;
    if Target^.Combat^.PendingSpell > 0 then
    begin
      DelayByGameSpeed;
      ShowCharacterMessage(Target, 'lost a spell', 12, 1);
      ForgetSpell(Target^.Combat^.PendingSpell);
      Target^.Combat^.PendingSpell := 0;
    end
    else
      DelayByGameSpeed;
  end
  else
    DelayByGameSpeed;
  if Target^.Flag10D = 0 then
  begin
    ShowCharacterMessage(Target, 'goes down', Row, 0);
    Inc(Row, 2);
    if Target^.Status = StatusDying then
      DrawTextAt(23, Row, 10, 'and is Dying');
    if Target^.Status in StatusKilled then
      ShowCharacterMessage(Target, 'is killed', Row, 0);
    Inc(Row, 2);
    RemoveDeathAffects(Target);
    RunAffectHooks(HookGoesDown, Target);
    if Target^.Flag10D = 0 then
      RemoveCombatant(Target)
    else
      DelayByGameSpeed;
  end;
  ClearCharacterMessage;
end;
{ ovl13:0627. Lets every enemy next to Who that is watching (Combat^.B7) and not helpless strike
  back: for each combatant CollectEnemiesInRange(Who, 1) gathers, it puts the cursor on Who, clears
  the enemy's watch flag and runs the attack through ovl13_e11 and ovl13_e12. Does nothing for a
  character that is out of the fight (Flag10D 0). Called after a move (StepCombatant). }
procedure GuardedEnemiesAttack(Who: PCharacter);
var
  Count: Byte;
  I: Byte;
  Enemy: PCharacter;
  Done: Byte;
begin
  Count := CollectEnemiesInRange(Who, 1);
  for I := 1 to Count do
  begin
    if Who^.Flag10D <> 0 then
    begin
      Enemy := CombatantRecord[ds6DE4[I]];
      if (Enemy^.Combat^.B7 <> 0) and not IsHelpless(Enemy) then
      begin
        MoveCombatCursor(CombatantX(Who), CombatantY(Who), 2, 8);
        Enemy^.Combat^.B7 := 0;
        ovl13_e11(Enemy, Who);
        ovl13_e12(Enemy, Who, 0, nil, Done);
      end;
    end;
  end;
end;
{ ovl13:0712. Moves Who one cell in direction Dir on the combat map: a straight step costs two half
  squares and a diagonal three, and one that costs more than Combat^.Moves leaves it at 0 and gives
  up. Otherwise it takes the cost off Moves, moves the combatant's cell in CombatantTable by the
  DirStepX/DirStepY offset of Dir, and redraws and rebuilds the occupancy. A quick-fighting
  character (Quick set) is drawn facing that way and, when the new cell is outside the view, has its
  cursor moved too. Then Who's BF and B12 are cleared, the move sound plays, the guarded enemies
  next to Who make their free attacks (GuardedEnemiesAttack) and, if Who is out of the fight or now
  helpless, its Moves become 0. Called by MoveCharacter (ovl08) and MoveStep (ovl09). }
procedure StepCombatant(Who: PCharacter; Dir: Byte);
var
  Step: Byte;                    { the step's cost in half squares, reused as the cursor margin }
  Idx: Byte;
  NewX: ShortInt;
  NewY: ShortInt;
  OldX: ShortInt;
  OldY: ShortInt;
begin
  if Odd(Dir) then
    Step := 3
  else
    Step := 2;
  if Step > Who^.Combat^.Moves then
  begin
    Who^.Combat^.Moves := 0;
    Exit;
  end;
  Dec(Who^.Combat^.Moves, Step);
  Idx := CombatantIndex(Who);
  OldX := CombatantTable[Idx].X;
  OldY := CombatantTable[Idx].Y;
  NewX := OldX + DirStepX[Dir];
  NewY := OldY + DirStepY[Dir];
  Step := 1;
  if Who^.Quick <> 0 then
  begin
    Step := 3;
    if not IsInView(NewX - CombatMap^.ViewX, NewY - CombatMap^.ViewY) then
      MoveCombatCursor(OldX, OldY, 2, 8);
  end;
  RedrawGround(0, 0, Idx);
  CombatantTable[Idx].X := NewX;
  CombatantTable[Idx].Y := NewY;
  RebuildOccupancy;
  MoveCombatCursor(NewX, NewY, Step, 8);
  Who^.Combat^.BF := 0;
  Who^.Combat^.B12 := 0;
  PlaySound(ds2628);
  GuardedEnemiesAttack(Who);
  if (Who^.Flag10D = 0) or IsHelpless(Who) then
    Who^.Combat^.Moves := 0;
end;
{ ovl13:08AC: retf 6: 6 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_08AC; begin end;
{ ovl13:08B2, PartingShots. The parting shots Who provokes by leaving melee: it copies the enemies adjacent to
  Who now (CollectEnemiesInRange(Who, 1) into ds6DE4, ovl31) into Enemies, temporarily moves Who's
  cell in CombatantTable to Dir's neighbour to collect the enemies adjacent there, moves it back and
  clears the copied entries that are still adjacent, so Enemies keeps the enemies Who is leaving
  behind. For each of them, still in the fight (Flag10D set) and not IsHelpless, whom ovl13_e8(Who)
  says may take the shot and who carries neither affect $4A nor $4B, it scans the directions
  IconSet+6..IconSet+10: while the combatant is due an initiative (Initiative above 0) or is not
  being drawn (BF 0) it attacks at once, otherwise only when InDirArc says Who is in the arc facing
  the scanned direction from the enemy. The enemy's unused attack slot (1, or 2 for a monster with
  Attacks 0) is marked in AttackSlots, stored in the enemy's Combat^.Pad4[4], and ovl13_e12(Enemy,
  Who, 1, nil, ds6E31) makes the attack; the enemy's remembered Combat^.Target is restored after it.
  When the shot leaves Who still in the fight, Who's panel is redrawn. Called before the move by
  MoveCharacter (ovl08:09DF) and MoveStep (ovl09:07F2), so the shots happen as the combatant leaves.
  Globals: ds6DE4, CombatantTable, DirStepX/DirStepY, CombatantRecord, ds6E31. }
procedure PartingShots(Who: PCharacter; Dir: Byte);
var
  Enemies: array[1..12] of Byte;   { the enemies adjacent before the move (12 is ds6DE4's size) }
  Affect: Pointer;                 { scratch for HasAffect }
  Found: Byte;                     { nonzero when Enemies[I] is still adjacent after the move }
  DidAttack: Byte;                 { the enemy attacked in this scan; stops the rest of the loop }
  Idx: Byte;                       { Who's entry in CombatantTable }
  Unused: Byte;                    { QUIRK ovl13:08B8: declared but never read; it pads the frame }
  Count: Byte;                     { enemies adjacent before the move }
  CountAfter: Byte;                { enemies adjacent at the destination }
  J: Byte;                         { index over CountAfter }
  I: Byte;                         { index over Enemies }
  SlotIndex: Byte;                 { index over the enemy's two attack slots }
  Slot: Byte;                      { the attack slot the enemy uses (1, or 2) }
  K: Byte;                         { the scanned direction offset (IconSet+6..+10) }
  Enemy: PCharacter;               { the enemy leaving melee }
  SavedTarget: PCharacter;         { the enemy's Combat^.Target, saved across the attack }
begin
  FillChar(Enemies, SizeOf(Enemies), 0);
  Idx := CombatantIndex(Who);
  Count := CollectEnemiesInRange(Who, 1);
  if Count = 0 then
    Exit;
  for I := 1 to Count do
    Enemies[I] := ds6DE4[I];
  Inc(CombatantTable[Idx].X, DirStepX[Dir]);
  Inc(CombatantTable[Idx].Y, DirStepY[Dir]);
  CountAfter := CollectEnemiesInRange(Who, 1);
  Dec(CombatantTable[Idx].X, DirStepX[Dir]);
  Dec(CombatantTable[Idx].Y, DirStepY[Dir]);
  for I := 1 to Count do
  begin
    Found := 0;
    for J := 1 to CountAfter do
      if ds6DE4[J] = Enemies[I] then
        Found := 1;
    if Found <> 0 then
      Enemies[I] := 0;
  end;
  for I := 1 to Count do
    if Enemies[I] > 0 then
      if Who^.Flag10D <> 0 then
      begin
        DidAttack := 0;
        Enemy := CombatantRecord[Enemies[I]];
        if not IsHelpless(Enemy) then
          if ovl13_e8(Enemy, Who) then
            if not HasAffect(Enemy, AffectNoPartingShot1, Affect) then
              if not HasAffect(Enemy, AffectNoPartingShot2, Affect) then
                for K := Enemy^.Combat^.IconSet + PartingShotFirstOffset
                  to Enemy^.Combat^.IconSet + PartingShotLastOffset do
                  if DidAttack = 0 then
                  begin
                    if ((Enemy^.Combat^.Initiative > 0) or (Enemy^.Combat^.BF = 0))
                      or InDirArc(CombatantX(Enemy), CombatantY(Enemy),
                          CombatantX(Who), CombatantY(Who), K mod Directions) then
                    begin
                      Slot := 1;
                      if Enemy^.Attacks = 0 then
                        Slot := 2;
                      for SlotIndex := 1 to 2 do
                        if Enemy^.AttackSlots[SlotIndex] > 0 then
                          Slot := SlotIndex;
                      if Enemy^.AttackSlots[Slot] = 0 then
                        Enemy^.AttackSlots[Slot] := 1;
                      Enemy^.Combat^.Pad4[4] := Slot;
                      SavedTarget := Enemy^.Combat^.Target;
                      ovl13_e12(Enemy, Who, 1, nil, ds6E31);
                      DidAttack := 1;
                      Enemy^.Combat^.Target := SavedTarget;
                      if Who^.Flag10D <> 0 then
                        DrawCharacterPanel(Who);
                    end;
                  end;
      end;
end;
{ ovl13:0C6A. Tries to flee the fight for Who (the Flee answer of the Move command, ovl08:0410,
  and a panicking off-map step, ovl09:0434): with no enemy at all within CollectEnemiesInRange's
  $FF it gets away; otherwise it gets away when ovl13_e20(Who)'s initiative is below half Who's
  round Movement, or level with it and a RollDice(1, 2) coin comes up 1. Getting away drops the
  combatant from the fight with StatusFled ('Got Away'), a block flashes 'Escape is blocked'.
  Returns EndCombatTurn(Who), which ends the turn. Globals: none. }
function TryFlee(Who: PCharacter): Byte;
var
  Escaped: Boolean;              { the flee attempt succeeded }
  Other: Byte;                   { initiative ovl13_e20 works out for Who }
  Moves: Byte;                   { half of Who's round movement budget }
begin
  Escaped := False;
  if CollectEnemiesInRange(Who, AllEnemiesRange) = 0 then
    Escaped := True
  else
  begin
    Moves := ComputeMovement(Who) shr 1;
    Other := ovl13_e20(Who);
    if Other < Moves then
      Escaped := True
    else if Other = Moves then
      if RollDice(1, 2) = 1 then
        Escaped := True;
  end;
  if Escaped then
    DropCombatant(Who, StatusFled, 'Got Away')
  else
    ShowFlashMessage('Escape is blocked');
  TryFlee := EndCombatTurn(Who);
end;
{ ovl13:0D23. Refreshes Who's readied-weapon attack count for the turn: it remembers the old
  AttackSlots[1] and seeds it from the character's Attacks (+$A1); with a ranged weapon readied
  (IsRangedWeapon and ChooseAttackItem passes) it takes the readied weapon's ItemTable attacks
  (at least 2) and remembers the aimed ammo item, else it keeps AttackSlots[1]. That attack count
  goes to ds681A, the movement/attack affect hook $12 may change it, and AttacksThisRound turns the
  changed byte into the attack count. A ranged aim caps the count at the ammo stack's Count.
  AttackSlots[1] takes the result unless a ranged attack (Ranged, i.e. ds681A is not 0) would
  more than double the saved count. Called after StartCombatantRound and whenever the AI or the
  player readies an item (ovl08:0207, ovl09:0942). Globals: ds681A, ds681D, ItemTable. }
procedure RefreshAttacks(Who: PCharacter);
var
  AttackCount: Byte;             { attacks the readied weapon gives this turn }
  SavedAttacks: Byte;            { AttackSlots[1] before the refresh }
  AmmoLimit: Byte;               { attacks left in the aimed ammo stack, at least 1 }
  ReadyAttacks: Byte;            { ItemTable attacks of the readied weapon }
  Ranged: Boolean;               { a ranged weapon and an aim were chosen }
  Aim: Pointer;                  { the item ChooseAttackItem picked (a PItem) }
begin
  Ranged := False;
  SavedAttacks := Who^.AttackSlots[1];
  Who^.AttackSlots[1] := Who^.Attacks;
  if IsRangedWeapon(Who) and (ChooseAttackItem(Who, Aim) <> 0) then
  begin
    Ranged := True;
    ReadyAttacks := ItemTable[Byte(Who^.SlotItems[0]^.ItemType)].Attacks;
    if ReadyAttacks < 2 then
      ReadyAttacks := 2;
    ds681A := ReadyAttacks;
  end
  else
    ds681A := Who^.AttackSlots[1];
  ds681D := False;
  RunAffectHooks(HookComputeMovement, Who);
  AttackCount := AttacksThisRound(ds681A);
  if Ranged and (Aim <> nil) then
  begin
    AmmoLimit := 1;
    if (Aim <> nil) and (PItem(Aim)^.Count > AmmoLimit) then
      AmmoLimit := PItem(Aim)^.Count;
    if AmmoLimit < AttackCount then
      AttackCount := AmmoLimit;
  end;
  if (Who^.Combat^.Pad8 = 0) or (AttackCount < SavedAttacks) or
     ((Who^.Combat^.Pad8 <> 0) and (AttackCount < SavedAttacks * 2) and not Ranged) then
    Who^.AttackSlots[1] := AttackCount;
end;
{ ovl13:0E52. Turns a doubled attack budget into the round's attack count: it copies
  DoubledAttacks, adds 1 when the combat round counter ds6DE3 is odd (combat rounds are
  zero-based, so the extra unit lands on even-numbered rounds), and halves the result. Called
  with the hook-modifiable byte ds681A (the character's Attacks, attacks per two rounds, or the
  readied weapon's halves); StartCombatantRound stores the result in AttackSlots[2] and
  RefreshAttacks uses it as the round's attack count. }
function AttacksThisRound(DoubledAttacks: Byte): Byte;
var
  RoundAttacks: Byte;
begin
  RoundAttacks := DoubledAttacks;
  if Odd(ds6DE3) then
    Inc(RoundAttacks);
  AttacksThisRound := RoundAttacks shr 1;
end;
{ ovl13:0E82, SweepEnemies. The melee sweep: when the attacker Who still has attack slots left
  (AttackSlots[1] below Combat^.Pad4[5]), Target is a level-0 creature (HighestLevel 0) and
  Target stands in melee range (DistanceToTarget = 1), it sweeps the level-0 enemies around Who.
  It collects Who's adjacent enemies (CollectEnemiesInRange), counts the level-0 ones into Extra
  (remembering where Target is in the list), and when Extra still beats Who's attack slots
  (capped at Combat^.Pad4[5]) it shows 'sweeps', moves Target to the front of ds6DE4 and attacks
  each level-0 enemy in turn through ovl13_e11/ovl13_e12, spending one attack per enemy
  (AttackSlots[1] := 1 and Dec(Extra)) until Extra runs out. Returns True when the sweep
  happened, so the caller ends the turn. Called by MeleeAttack (ovl08:0D45) and the AI
  (ovl09:0B3C). Globals: ds6DE4 (the adjacent-enemy list), ds6E31 (the done flag e12 writes),
  CombatantRecord. }
function SweepEnemies(Who, Target: PCharacter): Boolean;
var
  Count: Byte;                   { enemies adjacent to Who }
  Extra: Byte;                   { level-0 enemies counted, then the attacks left }
  I: Byte;                       { walk of the adjacent-enemy list }
  SavedIndex: Byte;              { where Target sits in ds6DE4 }
  Enemy: PCharacter;             { one adjacent enemy }
begin
  SweepEnemies := False;
  if Who^.AttackSlots[1] < Who^.Combat^.Pad4[5] then
    if Target^.HighestLevel = 0 then
      if DistanceToTarget(Who, Target) = 1 then
      begin
        Count := CollectEnemiesInRange(Who, 1);
        Extra := 0;
        for I := 1 to Count do
        begin
          Enemy := CombatantRecord[ds6DE4[I]];
          if Enemy = Target then
            SavedIndex := I;
          if Enemy^.HighestLevel = 0 then
            Inc(Extra);
        end;
        if Extra > Who^.AttackSlots[1] then
        begin
          if Extra > Who^.Combat^.Pad4[5] then
            Extra := Who^.Combat^.Pad4[5];
          ShowCharacterMessage(Who, 'sweeps', 10, 1);
          Enemy := CombatantRecord[ds6DE4[1]];
          if Enemy <> Target then
          begin
            ds6DE4[SavedIndex] := ds6DE4[1];
            ds6DE4[1] := CombatantIndex(Target);
          end;
          for I := 1 to Count do
            if Extra > 0 then
              if CombatantRecord[ds6DE4[I]]^.HighestLevel = 0 then
              begin
                Enemy := CombatantRecord[ds6DE4[I]];
                ovl13_e11(Who, Enemy);
                Who^.AttackSlots[1] := 1;
                ovl13_e12(Who, Enemy, 0, nil, ds6E31);
                Dec(Extra);
              end;
          SweepEnemies := True;
        end;
      end;
end;
{ ovl13:0FBF: frame not read }
{@stub} procedure ovl13_fn_0FBF; begin end;
{ ovl13:104E: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_104E; begin end;
{ ovl13:1085: retf 8: 8 bytes of parameters; 6 bytes of locals }
{@stub} function ovl13_e8(Who, Target: Pointer): Boolean; begin end;
{ ovl13:116A: frame not read }
{@stub} procedure ovl13_e9(Who: Pointer); begin end;
{ ovl13:11D8: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_11D8; begin end;
{ ovl13:1351: retf 8: 8 bytes of parameters; 10 bytes of locals }
{@stub} function ovl13_e10(Who: Pointer; var B: Byte): Boolean; begin end;
{ ovl13:1406: frame not read }
{@stub} procedure ovl13_fn_1406; begin end;
{ ovl13:14A1: frame not read }
{@stub} procedure ovl13_fn_14A1; begin end;
{ ovl13:1583: frame not read }
{@stub} procedure ovl13_fn_1583; begin end;
{ ovl13:1713: frame not read }
{@stub} procedure ovl13_fn_1713; begin end;
{ ovl13:1758: retf 14: 14 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_1758; begin end;
{ ovl13:17F6: retf 8: 8 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl13_e11(Who, Target: Pointer); begin end;
{ ovl13:1884: retf 18: 18 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl13_e12(Who, Target: Pointer; A: Byte; P: Pointer; var Done: Byte); begin end;
{ ovl13:1B1E: frame not read }
{@stub} procedure ovl13_fn_1B1E; begin end;
{ ovl13:1BD7: frame not read }
{@stub} procedure ovl13_fn_1BD7; begin end;
{ ovl13:1BF8: frame not read }
{@stub} function ovl13_e13(P: Pointer; var B: Byte): Boolean; begin end;
{ ovl13:1C13: frame not read }
{@stub} procedure ovl13_fn_1C13; begin end;
{ ovl13:1D08: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_1D08; begin end;
{ ovl13:1E16: frame not read }
{@stub} procedure ovl13_fn_1E16; begin end;
{ ovl13:202B: frame not read }
{@stub} procedure ovl13_fn_202B; begin end;
{ ovl13:20A9: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_20A9; begin end;
{ ovl13:20C3: frame not read }
{@stub} procedure ovl13_e14; begin end;
{ ovl13:2233: frame not read }
{@stub} procedure ovl13_fn_2233; begin end;
{ ovl13:228C: frame not read }
{@stub} procedure ovl13_fn_228C; begin end;
{ ovl13:2383: frame not read }
{@stub} procedure ovl13_fn_2383; begin end;
{ ovl13:23B6: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_23B6; begin end;
{ ovl13:2414: frame not read }
{@stub} procedure ovl13_e15(A, B: Byte; var Done: Byte); begin end;
{ ovl13:2432: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_2432; begin end;
{ ovl13:2574: frame not read }
{@stub} function ovl13_fn_2574(Who: PCharacter; Target: PCharacter): Boolean; begin end;
{ ovl13:257E: frame not read }
{@stub} procedure ovl13_fn_257E; begin end;
{ ovl13:25C9: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_25C9; begin end;
{ ovl13:263D: retf 8: 8 bytes of parameters; 6 bytes of locals }
{@stub} function ovl13_e18(Who, Target: Pointer): Byte; begin end;
{ ovl13:26B0: retf 12: 12 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl13_fn_26B0; begin end;
{ ovl13:2879: retf 0: 0 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl13_e19; begin end;
{ ovl13:2908: retf 4: 4 bytes of parameters; 8 bytes of locals }
{@stub} function ovl13_e20(Who: Pointer): Byte; begin end;
{ ovl13:2998: retf 8: 8 bytes of parameters; 20 bytes of locals }
{@stub} function ovl13_e16(Who, Target: Pointer): Boolean; begin end;
{ ovl13:2AA0: frame not read }
{@stub} procedure ovl13_fn_2AA0; begin end;
{ ovl13:2B8B: retf 14: 14 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_2B8B; begin end;
{ ovl13:2C3D: frame not read }
{@stub} procedure ovl13_fn_2C3D; begin end;
{ ovl13:2D39: retf 18: 18 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_2D39; begin end;
{ ovl13:2DC8: frame not read }
{@stub} procedure ovl13_fn_2DC8; begin end;
{ ovl13:2DFA: frame not read }
{@stub} procedure ovl13_fn_2DFA; begin end;
{ ovl13:2F57: frame not read }
{@stub} procedure ovl13_fn_2F57; begin end;
{ ovl13:2F7B: frame not read }
{@stub} procedure ovl13_fn_2F7B; begin end;
{ ovl13:2FD3: frame not read }
{@stub} procedure ovl13_fn_2FD3; begin end;
{ ovl13:30FB: frame not read }
{@stub} procedure ovl13_fn_30FB; begin end;
{ ovl13:31D7: retf 22: 22 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_31D7; begin end;
{ ovl13:32E6: retf 6: 6 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl13_fn_32E6; begin end;
{ ovl13:3389: retf 6: 6 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl13_fn_3389; begin end;
{ ovl13:3558: frame not read }
{@stub} procedure ovl13_e17(Who: Pointer; A, B, C: Byte; var Done: Byte; var Aim); begin end;
{ ovl13:3728: retf 18: 18 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_3728; begin end;
{ ovl13:37E4: frame not read }
{@stub} function ovl13_e21(Who: Pointer; A, B, C: Byte): Boolean; begin end;
{ ovl13:39A3: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_39A3; begin end;
{ ovl13:39D2: frame not read }
{@stub} procedure ovl13_e22; begin end;
{ ovl13:39E6: frame not read }
{@stub} procedure ovl13_fn_39E6; begin end;
{ ovl13:3A2B: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_3A2B; begin end;
{ ovl13:3A86: retf 10: 10 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl13_e23; begin end;
{ ovl13:3B93: retf 0: 0 bytes of parameters; 262 bytes of locals }
{@stub} function ovl13_e24: Boolean; begin end;

begin
end.
