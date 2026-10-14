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
function AttackTargetAllowed(Who, Target: PCharacter): Boolean;
procedure TurnUndead(Who: PCharacter);
procedure ovl13_fn_11D8;
function SelectTurnUndeadTarget(Who: Pointer; var Selected): Boolean;
procedure ResolveCombatantAttacks(Attacker, Target: PCharacter; AttackKind: Byte; var Done: Byte);
procedure NoteAttackBearing(Attacker, Target: PCharacter);
procedure PerformAttack(Who, Target: PCharacter; AttackKind: Byte; AimedItem: Pointer; var Done: Byte);
procedure AddRangePenalty(Attacker: PCharacter; Target: PCharacter; var NeededRoll: Byte);
function FindNearbyTarget(Who: PCharacter; var Selected): Boolean;
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
procedure ovl13_fn_26B0(Who, Target: PCharacter; Item: PItem);
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
uses RES03, RES06, RES12, OVL24, OVL25, OVL30, OVL31, Crt;
type
  { A view of the two bytes ResolveCombatantAttacks selects between with the from-behind flag: TCharacter
    +$111 (ResistValue) and +$112 (ds112), accessed as a signed-indexed pair. }
  TResistView = record
    Pad: array[0..$110] of Byte;
    Pair: array[0..1] of Byte;
  end;
  PResistView = ^TResistView;
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
  { Turn undead (ovl13:116A): the d20 turning check and the d12 roll for how many undead the turn
    reaches. A cleric of level 1..8 uses its own level as the band, 9..13 use 9, any other level
    uses 10. The table ds0447 is read by monster row times 10 plus the band. }
  TurnCheckDie = 20;
  TurnCountDie = 12;
  MaxTurned = 6;
  TurnBandLow = 1;
  TurnBandHigh = 8;
  TurnBand9Low = 9;
  TurnBand9High = 13;
  TurnBandOther = 10;
  { The status a destroyed undead is left with (TCharacter.Status; in StatusKilled with 6 and 7). }
  StatusDestroyed = 8;
  { The starting smallest type row of the turn target scan (ovl13:1351), above every row of the
    Turn Undead table ds0447 (rows 0..10), so the first in-range undead always replaces it. }
  UndeadRowCeiling = 13;
  { The readied weapon takes its large-foe dice when the target is big: TCharacter.CombatSize (+$6C)
    above LargeTargetSize, or a footprint kind (bits 0..2) above LargeFootprintKind (ovl13:150D..1522). }
  LargeTargetSize = $80;
  FootprintKindMask = 7;
  LargeFootprintKind = 1;
  { An affect hook ResolveCombatantAttacks runs on the target after RecalcCombatValues (ovl13:1591); ovl24's
    table names kinds 6, 9, $A, $C, $D and $10, not this one. }
  HookAttackSetup = $B;

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
  the enemy's watch flag and runs the attack through NoteAttackBearing and PerformAttack. Does nothing for a
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
        NoteAttackBearing(Enemy, Who);
        PerformAttack(Enemy, Who, 0, nil, Done);
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
  behind. For each of them, still in the fight (Flag10D set) and not IsHelpless, whom AttackTargetAllowed(Who)
  says may take the shot and who carries neither affect $4A nor $4B, it scans the directions
  IconSet+6..IconSet+10: while the combatant is due an initiative (Initiative above 0) or is not
  being drawn (BF 0) it attacks at once, otherwise only when InDirArc says Who is in the arc facing
  the scanned direction from the enemy. The enemy's unused attack slot (1, or 2 for a monster with
  Attacks 0) is marked in AttackSlots, stored in the enemy's Combat^.Pad4[4], and PerformAttack(Enemy,
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
          if AttackTargetAllowed(Enemy, Who) then
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
                      PerformAttack(Enemy, Who, 1, nil, ds6E31);
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
  each level-0 enemy in turn through NoteAttackBearing/PerformAttack, spending one attack per enemy
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
                NoteAttackBearing(Who, Enemy);
                Who^.AttackSlots[1] := 1;
                PerformAttack(Who, Enemy, 0, nil, ds6E31);
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
{ ovl13:1085, AttackTargetAllowed. The attack's target check: it runs the target's and the attacker's affect hooks
  and reports whether the attack may go ahead. A nil Target fails, and attacking oneself is
  always allowed. Otherwise ds681E is cleared and RunAffectHooks kind 1 runs on Target; when no
  hook rejected it, Who's remembered Combat^.Target is saved, replaced by Target and the attacker's
  hook kind 0 runs, then the old target is put back. The result is True exactly when ds681E ended
  0 (no hook vetoed). Called before an attack (ovl09 AiTurn, PartingShots, ovl12_e70 and ovl13's
  e17/e21/2FD3). Globals: ds681E. }
function AttackTargetAllowed(Who, Target: PCharacter): Boolean;
var
  SavedTarget: PCharacter;       { Who^.Combat^.Target around the attacker's hook }
begin
  AttackTargetAllowed := False;
  if Target <> nil then
    if Who = Target then
      AttackTargetAllowed := True
    else
    begin
      ds681E := 0;
      RunAffectHooks(1, Target);
      if ds681E = 0 then
      begin
        SavedTarget := Who^.Combat^.Target;
        Who^.Combat^.Target := Target;
        RunAffectHooks(0, Who);
        Who^.Combat^.Target := SavedTarget;
      end;
      AttackTargetAllowed := ds681E = 0;
    end;
end;
{ ovl13:116A, TurnUndead. The Turn Undead action of a cleric Who: it shows 'turns undead...',
  marks Who's turn used (Combat^.Turned), then rolls how many undead the turn reaches
  (RollDice(1, 12)) and the d20 turning check. Who's cleric level (ClassLevels[0]) is mapped to a
  table band (1..8 itself, 9..13 to 9, else 10). While SelectTurnUndeadTarget hands over an undead in range and
  the reach and the stop flag allow it, the table ds0447 gives the number to beat for that
  monster's row (Pad74[$76] times 10 plus the band); a d20 at or above its absolute value turns it.
  A positive entry forces flight (Combat^.ForcedFlight, 'is turned'); a nonpositive one destroys
  it ('Is destroyed', RemoveCombatant, Status 8, out of the fight). Each result spends one of the
  six turns and one of the reach; when a destroyed one used the last reach a positive target puts
  it back. When nothing was turned it flashes 'Nothing Happens...'. Finally it recounts the sides,
  stores EndCombatTurn's result in ds6E31 and clears the message. Called by PlayerTurn's T case
  (ovl08:031A) and TryTurnUndead (ovl09:0203). Globals: ds0447, ds6E31. }
procedure TurnUndead(Who: PCharacter);
var
  Roll20: Byte;                  { the d20 turning check }
  Remaining: Byte;               { undead the turn still reaches, from RollDice(1, 12) }
  TurnsLeft: Byte;               { the six undead a turn may still affect }
  Result: ShortInt;              { the table entry: positive turns, nonpositive destroys }
  AnyTurned: Byte;               { nonzero once any undead was turned or destroyed }
  Stop: Byte;                    { set when the turning check fails, stops the loop }
  Selected: PCharacter;          { the undead SelectTurnUndeadTarget hands over }
  LevelBand: ShortInt;           { Who's cleric level mapped to the table column }
begin
  ShowCharacterMessage(Who, 'turns undead...', 10, 0);
  ClearPromptLine;
  DelayByGameSpeed;
  AnyTurned := 0;
  Stop := 0;
  Who^.Combat^.Turned := 1;
  TurnsLeft := MaxTurned;
  Remaining := RollDice(1, TurnCountDie);
  Roll20 := RollDice(1, TurnCheckDie);
  case Who^.ClassLevels[0] of
    TurnBandLow..TurnBandHigh:
      LevelBand := Who^.ClassLevels[0];
    TurnBand9Low..TurnBand9High:
      LevelBand := TurnBand9Low;
  else
    LevelBand := TurnBandOther;
  end;
  while SelectTurnUndeadTarget(Who, Selected) and (Remaining > 0) and (Stop = 0) do
  begin
    Result := ds0447[ShortInt(Selected^.Pad74[$76]), LevelBand];
    if Roll20 >= Abs(Result) then
    begin
      AnyTurned := 1;
      ShowCursorOn(Selected, 3, 0);
      DrawCharacterPanel(Selected);
      if Result > 0 then
      begin
        Selected^.Combat^.ForcedFlight := 1;
        ShowHitMessage(Selected, 1, 'is turned');
      end
      else
      begin
        ShowCharacterMessage(Selected, 'Is destroyed', 10, 0);
        RemoveCombatant(Selected);
        Selected^.Status := StatusDestroyed;
        Selected^.Flag10D := 0;
      end;
      if TurnsLeft > 0 then
        Dec(TurnsLeft);
      Dec(Remaining);
      if (Remaining = 0) and (TurnsLeft > 0) and (Result < 0) then
        Inc(Remaining);
      ClearCharacterMessage;
    end
    else
      Stop := 1;
  end;
  if AnyTurned = 0 then
    ShowFlashMessage('Nothing Happens...');
  RecountCombatSides;
  ds6E31 := EndCombatTurn(Who);
  ClearCharacterMessage;
end;
{ ovl13:11D8: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_11D8; begin end;
{ ovl13:1351. Picks the undead TurnUndead tries to turn next: of the enemies the range scan
  CollectEnemiesInRange(Who, AllEnemiesRange) lists it keeps the one with the lowest signed type row
  (TCharacter.Pad74[$76], above 0) whose combat state is not already forced to flee
  (Combat^.ForcedFlight 0), clearing Selected first, and returns whether one was found. Pad74[$76]
  is the monster row the Turn Undead table ds0447 is indexed by, so the scan picks the undead with
  the lowest row first. QUIRK ovl13:135B: Selected is untyped, so TurnUndead passes a
  PCharacter while ovl09 TryTurnUndead passes a 1-byte Done; the routine writes a 4-byte far pointer
  through it either way. Globals: ds6DE4 (the scan's combatant list), CombatantRecord. }
function SelectTurnUndeadTarget(Who: Pointer; var Selected): Boolean;
var
  Count: Byte;                   { enemies CollectEnemiesInRange listed }
  I: Byte;                       { walk of the enemy list }
  MinRow: ShortInt;              { the lowest type row kept so far }
  Enemy: PCharacter;             { one listed enemy }
begin
  MinRow := UndeadRowCeiling;
  PCharacter(Selected) := nil;
  Count := CollectEnemiesInRange(Who, AllEnemiesRange);
  SelectTurnUndeadTarget := False;
  for I := 1 to Count do
  begin
    Enemy := CombatantRecord[ds6DE4[I]];
    if Enemy^.Combat^.ForcedFlight = 0 then
      if ShortInt(Enemy^.Pad74[$76]) > 0 then
        if ShortInt(Enemy^.Pad74[$76]) < MinRow then
        begin
          MinRow := Enemy^.Pad74[$76];
          PCharacter(Selected) := Enemy;
          SelectTurnUndeadTarget := True;
        end;
  end;
end;
{ ovl13:1406. Resolves all of one combatant's melee attacks for its turn, the work PerformAttack wraps
  (this routine covers 1406..17F6: the map's entries 14A1, 1583, 1713 and 1758 lie inside it):
  it clears the attack-slot counters (ds6822[1..2], ds6E2C[1..2]) and the damage, marks the
  attacker's Combat^.Pad8, then either takes the helpless auto-hit (no roll, ShowAttackResult kind 3
  with the target's Flag11B + 5, ClearAttackerAffect, both attack slots cleared) or, against a target
  that fights back, switches the readied weapon to its large-foe dice when the target is big
  (CombatSize above $80 or a footprint kind above 1), recomputes the target's combat values, runs hook
  $B on it, works out the needed to-hit roll and the hit kind (a from-behind hit uses the ds112 pair
  and kind 1, a backstab kind 2), then walks the attacker's attack slots downward: each slot with
  attacks left fires once, RollToHit (or a helpless target) lands it, RollAttackDamage rolls the
  damage, ShowAttackResult shows it and the death hook runs; when nothing landed a miss is shown.
  Done is left nonzero when the turn ends (EndCombatTurn) and zero while another attack remains.
  QUIRK ovl13:1733: DamageAmount is passed as ShowAttackResult's second and third bytes. Called by
  PerformAttack (ovl13:19D6). Globals: ds6822, ds6E2C, DamageAmount, ds2622, ds2626. }
procedure ResolveCombatantAttacks(Attacker, Target: PCharacter; AttackKind: Byte; var Done: Byte);
var
  Item: TItemRow;                { the readied slot-0 item's row, when the large-foe dice are used }
  Landed: Byte;                  { set once any attack of the turn landed }
  TargetDown: Byte;              { set when the target left the fight during the attacks }
  Behind: Byte;                  { the from-behind flag (AttackKind, set by the e18 icon test too) }
  NeededRoll: Byte;              { the to-hit value RollToHit must reach for this attack }
  SlotIndex: Byte;               { the attack slot being resolved, and the counter of the tail loop }
  SlotCount: Byte;               { the attacker's current attack slot (Combat^.Pad4[4]) }
  HitKind: Byte;                 { the ShowAttackResult kind: 0 plain, 1 from behind, 2 backstab }
  RearAttack: ShortInt;          { nonzero selects the ds112 byte instead of ResistValue }
begin
  Behind := AttackKind;
  Done := 0;
  ds6822[1] := 0;
  ds6822[2] := 0;
  ds6E2C[1] := 0;
  ds6E2C[2] := 0;
  Landed := 0;
  TargetDown := 0;
  DamageAmount := 0;
  Attacker^.Combat^.Pad8 := 1;
  if IsHelpless(Target) then
  begin
    PlaySound(ds2622);
    while Attacker^.AttackSlots[Attacker^.Combat^.Pad4[4]] = 0 do
      Dec(Attacker^.Combat^.Pad4[4]);
    Inc(ds6E2C[Attacker^.Combat^.Pad4[4]]);
    ShowAttackResult(Attacker, Target, 3, Target^.Flag11B + 5, 1, 1);
    ClearAttackerAffect(Attacker);
    for SlotIndex := 1 to 2 do
      Attacker^.AttackSlots[SlotIndex] := 0;
    Landed := 1;
    Done := 1;
  end
  else
  begin
    if (Attacker^.SlotItems[0] <> nil) and
       ((Target^.CombatSize > LargeTargetSize) or
        ((Target^.CombatSize and FootprintKindMask) > LargeFootprintKind)) then
    begin
      Item := ItemTable[Attacker^.SlotItems[0]^.ItemType];
      Attacker^.WeaponAttacks[1] := Item.DiceCountLarge;
      Attacker^.WeaponDamage[1] := Item.DiceSizeLarge;
      Attacker^.WeaponDamageBonus[1] := Attacker^.WeaponDamageBonus[1] - Item.BonusNormal
        + Item.BonusLarge;
    end;
    RecalcCombatValues(Target);
    RunAffectHooks(HookAttackSetup, Target);
    RearAttack := 0;
    if ovl13_fn_2574(Attacker, Target) then
      NeededRoll := Target^.ds112 - 2
    else
    begin
      if Target^.Combat^.BF > 1 then
        if ovl13_e18(Attacker, Target) = Target^.Combat^.IconSet then
          if Target^.Combat^.B12 > 4 then
            Behind := 1;
      if Behind <> 0 then
        RearAttack := 1;
      NeededRoll := PResistView(Target)^.Pair[RearAttack];
    end;
    AddRangePenalty(Attacker, Target, NeededRoll);
    HitKind := 0;
    if Behind <> 0 then
      HitKind := 1;
    if ovl13_fn_2574(Attacker, Target) then
      HitKind := 2;
    SlotCount := Attacker^.Combat^.Pad4[4];
    for SlotIndex := SlotCount downto 1 do
      while (Attacker^.AttackSlots[SlotIndex] > 0) and (TargetDown = 0) do
      begin
        Dec(Attacker^.AttackSlots[SlotIndex]);
        Attacker^.Combat^.Pad4[4] := SlotIndex;
        Inc(ds6E2C[SlotIndex]);
        if RollToHit(Attacker, Target, NeededRoll) or IsHelpless(Target) then
        begin
          Inc(ds6822[SlotIndex]);
          PlaySound(ds2622);
          Landed := 1;
          RollAttackDamage(Attacker, Target, SlotIndex);
          ShowAttackResult(Attacker, Target, HitKind, DamageAmount, DamageAmount, 1);
          if Target^.Flag10D <> 0 then
            RunAffectHooks(SlotIndex + 1, Attacker);
          if Target^.Flag10D = 0 then
            TargetDown := 1;
        end;
      end;
    if Landed = 0 then
    begin
      PlaySound(ds2626);
      ShowAttackResult(Attacker, Target, HitKind, 0, 0, 0);
    end;
    Done := 1;
    for SlotIndex := 1 to 2 do
      if Attacker^.AttackSlots[SlotIndex] > 0 then
        Done := 0;
    Attacker^.Combat^.Pad4[5] := 0;
  end;
  if Done <> 0 then
    Done := EndCombatTurn(Attacker);
end;
{ ovl13:17F6. Notes the attack Target is about to take from Attacker: Target's attack count Combat^.BF
  is raised and Combat^.B12 gains the angular error between Target's facing (Combat^.IconSet) and
  the bearing from Target to Attacker (ovl13_e18), wrapped into 0..4, modulo 8. Called with the
  target as the second argument just before PerformAttack resolves the attack (ovl08 MeleeAttack,
  ovl09 AiTurn, GuardedEnemiesAttack, SweepEnemies). }
procedure NoteAttackBearing(Attacker, Target: PCharacter);
var
  Error: Byte;                   { Target's facing error, wrapped into 0..4 }
  Bearing: Byte;                 { the direction from Target to Attacker (ovl13_e18) }
begin
  Inc(Target^.Combat^.BF);
  Bearing := ovl13_e18(Target, Attacker);
  Error := (Bearing - Target^.Combat^.IconSet + 8) mod 8;
  if Error > 4 then
    Error := 8 - Error;
  Target^.Combat^.B12 := (Target^.Combat^.B12 + Error) mod 8;
end;
{ ovl13:1884. Carries out one combat action of Who against Target, the wrapper around
  ResolveCombatantAttacks (this routine covers 1884..1B1E; the map's entries inside it were merged):
  it turns Target to face Who (once, while Target's attack count Combat^.BF is below TargetTurnLimit
  and AttackKind is 0), turns Who to face Target (SetCombatantIcon, mirror) and redraws Who's panel,
  remembers Target in Who^.Combat^.Target, pauses, lets ovl13_fn_26B0 play the aimed item AimedItem
  and a BowItemKind readied item, then, when Who has any attack slot left, saves SelectedCharacter,
  makes Who the selected character and resolves the attack (AttackKind is the attack kind, Done the
  turn-done flag), spends one round of the aimed ammo (Count drops by ds6E2C[1]; an emptied stack
  whose ammo can be thrown is copied into a new menu line linked into ds6810, recorded in ds5D9A and
  removed from the inventory, else it is just removed), recomputes Who's combat values and restores
  SelectedCharacter. Ends the turn when Done is set and re-lays Who's icon when it is in view. Called
  by MeleeAttack (ovl08), AiTurn (ovl09), GuardedEnemiesAttack, PartingShots and SweepEnemies.
  QUIRK ovl13:198D: Who^.SlotItems[0] is read without a nil test. Globals: SelectedCharacter,
  ds6810, ds5D9A, ds6E2C. }
procedure PerformAttack(Who, Target: PCharacter; AttackKind: Byte; AimedItem: Pointer; var Done: Byte);
const
  { Target turns to face Who only while its attack count Combat^.BF is below this (ovl13:1892). }
  TargetTurnLimit = 3;
  { The readied item kind ovl13_fn_26B0 is given a second time alongside the ammo (ovl13:195A): a
    launcher whose own missile is drawn; which item kind this is is not settled, it is read as a bow. }
  BowItemKind = $2F;
  { The AimedItem^.Affects[3] value that stops an emptied ammo stack being copied into the loot list
    ds6810 (ovl13:1A14 compares it; what the affect means is not settled). }
  NoLootCopyAffect = $89;
  { Milliseconds Delay lets the attack be seen (ovl13:1933). }
  AttackPause = 100;
var
  NewItem: PMenuLine;            { the ammo copy linked into the shop's item list ds6810 }
  SavedSelection: PCharacter;    { SelectedCharacter around ResolveCombatantAttacks }
  Bearing: Byte;                 { a direction from ovl13_e18 }
begin
  if (Target^.Combat^.BF < TargetTurnLimit) and (AttackKind = 0) then
  begin
    Bearing := ovl13_e18(Target, Who);
    if IsCombatantInView(Target, 0) then
      SetCombatantIcon(Target, Bearing, 0, 0)
    else
      Target^.Combat^.IconSet := Bearing;
  end;
  Bearing := ovl13_e18(Who, Target);
  DrawCharacterPanel(Who);
  SetCombatantIcon(Who, Bearing, 1, 0);
  Who^.Combat^.Target := Target;
  Delay(AttackPause);
  if AimedItem <> nil then
    ovl13_fn_26B0(Who, Target, PItem(AimedItem));
  if Who^.SlotItems[0]^.ItemType = BowItemKind then
    ovl13_fn_26B0(Who, Target, Who^.SlotItems[0]);
  Done := 1;
  if (Who^.AttackSlots[1] > 0) or (Who^.AttackSlots[2] > 0) then
  begin
    SavedSelection := SelectedCharacter;
    SelectedCharacter := Who;
    ResolveCombatantAttacks(Who, Target, AttackKind, Done);
    if AimedItem <> nil then
    begin
      if PItem(AimedItem)^.Count > 0 then
        Dec(PItem(AimedItem)^.Count, ds6E2C[1]);
      if PItem(AimedItem)^.Count = 0 then
      begin
        if RangedWeaponCanMelee(Who) and (PItem(AimedItem)^.Affects[3] <> NoLootCopyAffect) then
        begin
          New(NewItem);
          Move(PItem(AimedItem)^, NewItem^, SizeOf(TMenuLine));
          NewItem^.Next := ds6810;
          ds6810 := NewItem;
          NewItem^.Readied := False;
          RemoveInventoryItem(Who, PItem(AimedItem));
          ds5D9A := NewItem;
        end
        else
          RemoveInventoryItem(Who, PItem(AimedItem));
      end;
    end;
    RecalcCombatValues(Who);
    SelectedCharacter := SavedSelection;
  end;
  if Done <> 0 then
    Done := EndCombatTurn(Who);
  if IsCombatantInView(Who, 0) then
  begin
    SetCombatantIcon(Who, Who^.Combat^.IconSet, 1, 1);
    SetCombatantIcon(Who, Who^.Combat^.IconSet, 0, 0);
  end;
end;
{ ovl13:1B1E. Adds the attack's range penalty to NeededRoll, the to-hit value RollToHit must reach:
  it takes the distance to Target (DistanceToTarget) and, for a ranged weapon (IsRangedWeapon),
  reduces it by the readied weapon's range band ItemTable[SlotItems[0]^.ItemType].Range div 3
  ((Range - 1) div 3, at least 0). While the distance then still exceeds the band it takes the band
  off the distance and adds 2, then 3 to NeededRoll (two bands at most). A melee weapon's band is the
  distance itself, so no penalty. Called by ResolveCombatantAttacks after the resistance/ds112
  NeededRoll. Globals: ItemTable. }
procedure AddRangePenalty(Attacker, Target: PCharacter; var NeededRoll: Byte);
var
  RangeBand: ShortInt;           { the weapon's range band, or the distance for a melee weapon }
  Distance: ShortInt;            { the distance to Target, reduced band by band }
begin
  Distance := DistanceToTarget(Attacker, Target);
  if IsRangedWeapon(Attacker) then
    RangeBand := (ItemTable[Attacker^.SlotItems[0]^.ItemType].Range - 1) div 3
  else
    RangeBand := Distance;
  if Distance - RangeBand > 0 then
  begin
    Distance := Distance - RangeBand;
    NeededRoll := NeededRoll + 2;
  end;
  if Distance - RangeBand > 0 then
  begin
    Distance := Distance - RangeBand;
    NeededRoll := NeededRoll + 3;
  end;
end;
{ ovl13:1BF8. Picks the combatant SelectTurnUndeadTarget's scan and the spell-3 area test work on, the
  enemy standing next to Who: it walks the nine directions Dir 0..8 from Who (Dir 8 is Who's own
  cell, DirStepX[8]/DirStepY[8] are 0,0), maps each with GetMapCell, and for an occupied cell keeps
  the same-side combatant whose current hit points are below its maximum when it is the most wounded
  so far (BestHp) or, for Who's own cell (the occupant is Who), when it is below half its maximum;
  a body cell (tile $1F) with no occupant makes it walk BodyTable for a body standing on the scanned
  cell whose owner is not yet dead (Status not in StatusKilled, 6..8). It then hands over the
  chosen combatant: SelectedWho when an occupant was picked (BestHp below 8) or no body was found,
  else the body's owner, and returns whether one was stored. Writes the 4-byte pointer through the
  untyped var Selected, so a caller passing a 1-byte Done (ovl09 SpellAccepted) has the rest
  clobbered. QUIRK ovl13:1DBB: BodyTable[FoundIndex] is read with FoundIndex 0 when nothing was
  chosen, so the else reads the 7 bytes before BodyTable. Globals: CombatantRecord, BodyTable,
  BodyCount. }
function FindNearbyTarget(Who: PCharacter; var Selected): Boolean;
const
  { The map tile a body is drawn over; a cell with it and no combatant makes the scan look for a
    body (ovl13:1D24). }
  BodyTile = $1F;
  { Below this picked hit point value the scan hands over an occupant instead of a body
    (ovl13:1DBB). }
  ChosenHpLimit = 8;
var
  SelectedWho: PCharacter;       { the most-wounded same-side occupant found }
  CellX: ShortInt;               { the scanned cell column }
  CellY: ShortInt;               { the scanned cell row }
  FoundIndex: Byte;              { the BodyTable entry on the scanned cell, 0 for none }
  BestHp: Byte;                  { the picked combatant's hit points, $FF before the first pick }
  Dir: Byte;                     { the direction scanned, 0..8 (8 is no step, Who's own cell) }
  BodyIndex: Byte;               { walk of BodyTable }
  Occupant: Byte;                { the combatant GetMapCell finds on the scanned cell }
  Tile: Byte;                    { the tile GetMapCell finds on the scanned cell }
begin
  SelectedWho := nil;
  FoundIndex := 0;
  BestHp := $FF;
  for Dir := 0 to 8 do
  begin
    CellX := CombatantX(Who) + DirStepX[Dir];
    CellY := CombatantY(Who) + DirStepY[Dir];
    GetMapCell(CellX, CellY, Occupant, Tile);
    if Occupant > 0 then
    begin
      PCharacter(Selected) := CombatantRecord[Occupant];
      if (PCharacter(Selected)^.Side = Who^.Side) and
         (PCharacter(Selected)^.Flag11B < PCharacter(Selected)^.HpMax) then
        if (PCharacter(Selected)^.Flag11B < BestHp) or
           ((PCharacter(Selected) = Who) and
            (PCharacter(Selected)^.Flag11B < PCharacter(Selected)^.HpMax shr 1)) then
        begin
          SelectedWho := PCharacter(Selected);
          BestHp := PCharacter(Selected)^.Flag11B;
        end;
    end
    else if Tile = BodyTile then
      for BodyIndex := 1 to BodyCount do
        if BodyTable[BodyIndex].Who <> nil then
          if not (BodyTable[BodyIndex].Who^.Status in StatusKilled) then
            if (BodyTable[BodyIndex].X = CellX) and (BodyTable[BodyIndex].Y = CellY) then
              FoundIndex := BodyIndex;
  end;
  if (BestHp < ChosenHpLimit) or (FoundIndex = 0) then
    PCharacter(Selected) := SelectedWho
  else
    PCharacter(Selected) := BodyTable[FoundIndex].Who;
  if PCharacter(Selected) <> nil then
    FindNearbyTarget := True
  else
    FindNearbyTarget := False;
end;
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
{@stub} procedure ovl13_fn_26B0(Who, Target: PCharacter; Item: PItem); begin end;
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
