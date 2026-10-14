unit OVL13;
{ CombatSpells: the combat actions overlay (whitepaper 5.5). RunCombat calls it to set up every
  combatant's round (ComputeMovement and StartCombatantRound), to move a combatant on the combat map (StepCombatant
  and PartingShots), and to resolve what a combat action does; the ovl13_eN entry points are the ones
  the combat menu and the combat AI call. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
type
  { The record SelectSpellTargets and FindSpellTarget pass as Target: one combatant a spell is aimed at and its
    combat-map cell. Seven bytes; the last is never read (System_FillChar clears seven, ovl13:2098). }
  TSpellTarget = record
    Who: PCharacter;               { +0: the combatant the spell is aimed at }
    X: Byte;                       { +4: its column, CombatantX(Who) }
    Y: Byte;                       { +5: its row, CombatantY(Who) }
    Pad6: Byte;                    { +6: never read }
  end;
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
function FindSpellTarget(Spell, Automatic, AimFlag: Byte; var Target: TSpellTarget): Boolean;
procedure SelectSpellTargets(Spell, Automatic: Byte; var Done: Byte);
procedure CastCombatSpell(SpellNumber, NoRedraw: Byte; var Done: Byte);
procedure ovl13_fn_2432;
function IsBackstab(Who: PCharacter; Target: PCharacter): Boolean;
procedure ovl13_fn_257E;
procedure ovl13_fn_25C9;
function BearingTo(Who, Target: Pointer): Byte;
procedure ShowAttackAnimation(Who, Target: PCharacter; Item: PItem);
procedure UpdateMonsterMorale;
function FastestEnemyMovement(Who: Pointer): Byte;
function ConfirmAttackTarget(Who, Target: PCharacter): Boolean;
function ShowAimPrompt(Who, Target: PCharacter; Range: Byte; ShowRange: Byte; Unused: Byte): Char;
procedure ResolveAimedAttack(Who, Target: PCharacter; Automatic: Byte; var Done: Byte; var Aim: TSpellTarget);
procedure RunAimCursor(Who, Target: PCharacter; Range, Automatic,
  AimFlag: Byte; var Done: Byte; var Aim: TSpellTarget);
procedure ovl13_fn_32E6;
procedure ovl13_fn_3389;
procedure ovl13_e17(Who: Pointer; A, B, C: Byte; var Done: Byte; var Aim);
procedure ovl13_fn_3728;
function ChooseCombatTarget(Who: PCharacter; Range, ThroughWalls, ForgetTarget: Byte): Boolean;
procedure ovl13_e22;
procedure ovl13_fn_39E6;
procedure ovl13_fn_3A2B;
procedure ovl13_e23;
function ovl13_e24: Boolean;
implementation
uses RES03, RES04, RES06, RES09, RES12, OVL19, OVL22, OVL24, OVL25, OVL30, OVL31, Crt;
type
  { A view of the two bytes ResolveCombatantAttacks selects between with the from-behind flag: TCharacter
    +$111 (ResistValue) and +$112 (ds112), accessed as a signed-indexed pair. }
  TResistView = record
    Pad: array[0..$110] of Byte;
    Pair: array[0..1] of Byte;
  end;
  PResistView = ^TResistView;
  { A view of the header of the 24x3 combat picture AllocatePicture makes ds6E36 point at (the
    TPicture res12's CopyPictureItem reads): only the bytes-per-item word at +$11 is needed here
    to quarter it for the text adapter, the rest of the header is not read. }
  TPictureHeader = record
    Head: array[0..$10] of Byte;
    ByteSize: Word;
  end;
  PPictureHeader = ^TPictureHeader;
const
  { The two sides of a combat (POOLVARS, ovl24:0D96). }
  SideParty = 0;
  { The monster side (ovl05's SideMonsters and ovl10's SideEnemy): the combatants ovl13:2879 totals
    the hit points of into ds6E2F. }
  SideMonsters = 1;
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
  { The health status of a combatant still standing (TCharacter.Status 0; ovl05's StatusOkay). }
  StatusOkay = 0;
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
  { Word 819 of ds49D6^: set to 1 with ds6DE2 when the player confirms attacking an ally
    (ovl13:2998); ovl10's StartBattle clears it every battle as Var2BattleWord, so its meaning is
    not settled beyond that. }
  Var2AllyAttack = 819;
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
  { The random picks ChooseCombatTarget gets in one pass of its target search (ovl13:38A0). }
  AimSearchTries = $14;
  { The combat picture CopyPictureItem draws when the aim cursor is reset (ovl13:355F, 36D6, 371D). }
  AimCursorPicture = $19;

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
  (QUIRK ovl13:01D2) is kept, a special attack (IsBackstab, the backstab) multiplies the damage
  by the thief level div 4 + 2, DamageKind becomes 0 and the damage hooks run for the attacker (4)
  and the target (5). Called for each of a combatant's attacks. }
procedure RollAttackDamage(Attacker: PCharacter; Target: PCharacter; Index: Byte);
begin
  DamageAmount := RollDiceCounted(Attacker^.WeaponAttacks[Index], Attacker^.WeaponDamage[Index])
    + Attacker^.WeaponDamageBonus[Index];
  if DamageAmount < 0 then
    DamageAmount := 0;
  if IsBackstab(Attacker, Target) then
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
  $FF it gets away; otherwise it gets away when FastestEnemyMovement(Who)'s initiative is below half Who's
  round Movement, or level with it and a RollDice(1, 2) coin comes up 1. Getting away drops the
  combatant from the fight with StatusFled ('Got Away'), a block flashes 'Escape is blocked'.
  Returns EndCombatTurn(Who), which ends the turn. Globals: none. }
function TryFlee(Who: PCharacter): Byte;
var
  Escaped: Boolean;              { the flee attempt succeeded }
  Other: Byte;                   { initiative FastestEnemyMovement works out for Who }
  Moves: Byte;                   { half of Who's round movement budget }
begin
  Escaped := False;
  if CollectEnemiesInRange(Who, AllEnemiesRange) = 0 then
    Escaped := True
  else
  begin
    Moves := ComputeMovement(Who) shr 1;
    Other := FastestEnemyMovement(Who);
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
    if IsBackstab(Attacker, Target) then
      NeededRoll := Target^.ds112 - 2
    else
    begin
      if Target^.Combat^.BF > 1 then
        if BearingTo(Attacker, Target) = Target^.Combat^.IconSet then
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
    if IsBackstab(Attacker, Target) then
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
  the bearing from Target to Attacker (BearingTo), wrapped into 0..4, modulo 8. Called with the
  target as the second argument just before PerformAttack resolves the attack (ovl08 MeleeAttack,
  ovl09 AiTurn, GuardedEnemiesAttack, SweepEnemies). }
procedure NoteAttackBearing(Attacker, Target: PCharacter);
var
  Error: Byte;                   { Target's facing error, wrapped into 0..4 }
  Bearing: Byte;                 { the direction from Target to Attacker (BearingTo) }
begin
  Inc(Target^.Combat^.BF);
  Bearing := BearingTo(Target, Attacker);
  Error := (Bearing - Target^.Combat^.IconSet + 8) mod 8;
  if Error > 4 then
    Error := 8 - Error;
  Target^.Combat^.B12 := (Target^.Combat^.B12 + Error) mod 8;
end;
{ ovl13:1884. Carries out one combat action of Who against Target, the wrapper around
  ResolveCombatantAttacks (this routine covers 1884..1B1E; the map's entries inside it were merged):
  it turns Target to face Who (once, while Target's attack count Combat^.BF is below TargetTurnLimit
  and AttackKind is 0), turns Who to face Target (SetCombatantIcon, mirror) and redraws Who's panel,
  remembers Target in Who^.Combat^.Target, pauses, lets ShowAttackAnimation play the aimed item AimedItem
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
  { The readied item kind ShowAttackAnimation is given a second time alongside the ammo (ovl13:195A): a
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
  Bearing: Byte;                 { a direction from BearingTo }
begin
  if (Target^.Combat^.BF < TargetTurnLimit) and (AttackKind = 0) then
  begin
    Bearing := BearingTo(Target, Who);
    if IsCombatantInView(Target, 0) then
      SetCombatantIcon(Target, Bearing, 0, 0)
    else
      Target^.Combat^.IconSet := Bearing;
  end;
  Bearing := BearingTo(Who, Target);
  DrawCharacterPanel(Who);
  SetCombatantIcon(Who, Bearing, 1, 0);
  Who^.Combat^.Target := Target;
  Delay(AttackPause);
  if AimedItem <> nil then
    ShowAttackAnimation(Who, Target, PItem(AimedItem));
  if Who^.SlotItems[0]^.ItemType = BowItemKind then
    ShowAttackAnimation(Who, Target, Who^.SlotItems[0]);
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
{ ovl13:1E16. Finds a target for the spell Spell while it is aimed, and hands it over through the
  untyped var Target (a TSpellTarget: the combatant and its cell).
    - Automatic = 0 lets ovl13_e17 pick (the player's cursor); else the spell row's own data picks it:
      when the row's byte +6 (Pad2[6]) is 0 the caster itself is taken (and FindNearbyTarget is asked
      when Spell is 3); otherwise up to 20 times ChooseCombatTarget offers the next aim (ovl22_e3(Spell) is the
      spell's range) and the aim is accepted while the spell's area (ScanTargets with the row's +$F
      byte as the line budget) holds only the caster's enemies and the target is either not helpless or
      the row's AffectId (+$A) is not one of HelplessAffects.
  Returns True when a target was stored, and then leaves its cell in ds6DB9/ds6DBA; False clears the
  seven bytes of Target. AimFlag is passed to ovl13_e17 as its third flag (1 for the spell rows whose
  Pad2[6] nibble is 8..14). Globals: SelectedCharacter, ds6DB9, ds6DBA. }
function FindSpellTarget(Spell, Automatic, AimFlag: Byte; var Target: TSpellTarget): Boolean;
var
  Chosen: Byte;                  { nonzero once a target was stored }
  Valid: Byte;                   { the current aim passes the area and affect checks }
  SavedTarget: PCharacter;       { SelectedCharacter^.Combat^.Target around the aim checks }
  I: Byte;                       { walk of the scanned area list }
  Attempts: Byte;                { the 20 tries the automatic aim gets }
begin
  Chosen := 0;
  if Automatic = 0 then
  begin
    ovl13_e17(SelectedCharacter, ovl22_e3(Spell), 0, AimFlag, Chosen, Target);
    SelectedCharacter^.Combat^.Target := Target.Who;
  end
  else
  begin
    if SpellTable[Spell].PadB[$E] = 0 then
    begin
      Target.Who := SelectedCharacter;
      if (Spell <> 3) or FindNearbyTarget(SelectedCharacter, Target) then
      begin
        Target.X := CombatantX(Target.Who);
        Target.Y := CombatantY(Target.Who);
        Chosen := 1;
      end;
    end
    else
    begin
      Attempts := 20;
      while (Attempts > 0) and (Chosen = 0) do
      begin
        Valid := 1;
        if ChooseCombatTarget(SelectedCharacter, ovl22_e3(Spell), 0, 1) then
        begin
          SavedTarget := SelectedCharacter^.Combat^.Target;
          if SpellTable[Spell].PadB[$F] > 0 then
          begin
            ScanTargets(CombatantX(SavedTarget), CombatantY(SavedTarget),
              SpellTable[Spell].PadB[$F], $FF, 1, CombatMap);
            for I := 1 to ds6718[0].Val do
              if CombatantRecord[ds6718[I].Head]^.Side <> OpposingSide(SelectedCharacter) then
                Valid := 0;
          end;
          if IsHelpless(SavedTarget) then
            for I := 1 to 4 do
              if SpellTable[Spell].AffectId = HelplessAffects[I] then
                Valid := 0;
          if Valid <> 0 then
          begin
            Target.Who := SelectedCharacter^.Combat^.Target;
            Target.X := CombatantX(Target.Who);
            Target.Y := CombatantY(Target.Who);
            Chosen := 1;
          end;
        end;
        Dec(Attempts);
      end;
    end;
  end;
  if Chosen <> 0 then
  begin
    FindSpellTarget := True;
    ds6DB9 := Target.X;
    ds6DBA := Target.Y;
  end
  else
  begin
    FindSpellTarget := False;
    FillChar(Target, 7, 0);
  end;
end;
{ ovl13:20C3, SelectSpellTargets. The spell window RunCombat sets ds6B84 to (ovl08:0088): it fills the target
  list ds6C91 for the spell Spell (1-based, count ds6C94) and leaves the chosen target's cell in
  ds6DB9/ds6DBA. The spell row's byte +6 (Pad2[6]) switches:
    - nibble 0: the caster itself is the only target (ds6C95 := SelectedCharacter);
    - nibble $F: FindSpellTarget aims (AimFlag 0); an aim on some combatant (Combat^.Target set) is
      used alone, an empty one scans the spell's area (ScanTargets, line budget (Pad2[6] and $F) shr 4)
      and copies every found combatant into ds6C91;
    - nibble 8..14: FindSpellTarget aims (AimFlag 1) and the spell's area (line budget Pad2[6] and 7)
      always fills ds6C91;
    - any other nibble: up to (Pad2[6] and 3) + 1 aiming passes collect that many distinct targets;
      a target already in the list only flashes 'Already been targeted' when Automatic is 0.
  Done is set to 0 when nothing was collected (or an aim was refused). ds6820 is set to 1 once the
  area scan filled the list. Globals: SelectedCharacter, ds6C91, ds6C94, ds6DB9, ds6DBA, ds6820. }
procedure SelectSpellTargets(Spell, Automatic: Byte; var Done: Byte);
var
  TargetsLeft: Byte;             { the aiming passes the default branch still gets }
  Count: Byte;                   { the number of targets collected }
  J: Byte;                       { walk of the targets collected so far }
  Target: TSpellTarget;          { one aim FindSpellTarget hands over }
  Duplicate: Byte;               { nonzero when Target is already in ds6C91 }
begin
  Done := 1;
  ds6C94 := 0;
  ds6820 := 0;
  ds6DB9 := CombatantX(SelectedCharacter);
  ds6DBA := CombatantY(SelectedCharacter);
  case SpellTable[Spell].Pad2[6] and $F of
    0:
      begin
        ds6C95 := SelectedCharacter;
        ds6C94 := 1;
      end;
    $F:
      begin
        if FindSpellTarget(Spell, Automatic, 0, Target) then
        begin
          if SelectedCharacter^.Combat^.Target <> nil then
          begin
            ds6C95 := SelectedCharacter^.Combat^.Target;
            ds6C94 := 1;
          end
          else
          begin
            ScanTargets(ds6DB9, ds6DBA,
              (SpellTable[Spell].Pad2[6] and $F) shr 4, $FF, 1, CombatMap);
            for Count := 1 to ds6718[0].Val do
              ds6C91[Count] := CombatantRecord[ds6718[Count].Head];
            ds6C94 := ds6718[0].Val;
            ds6820 := 1;
          end;
        end
        else
          Done := 0;
      end;
    8..14:
      begin
        if FindSpellTarget(Spell, Automatic, 1, Target) then
        begin
          ScanTargets(ds6DB9, ds6DBA, SpellTable[Spell].Pad2[6] and 7, $FF, 1, CombatMap);
          for Count := 1 to ds6718[0].Val do
            ds6C91[Count] := CombatantRecord[ds6718[Count].Head];
          ds6C94 := ds6718[0].Val;
          ds6820 := 1;
        end
        else
          Done := 0;
      end;
  else
    begin
      TargetsLeft := (SpellTable[Spell].Pad2[6] and 3) + 1;
      Count := 0;
      while TargetsLeft > 0 do
      begin
        if FindSpellTarget(Spell, Automatic, 0, Target) then
        begin
          Duplicate := 0;
          for J := 1 to Count do
            if ds6C91[J] = Target.Who then
              Duplicate := 1;
          if Duplicate = 0 then
          begin
            Inc(Count);
            ds6C91[Count] := Target.Who;
            Dec(TargetsLeft);
          end
          else if Automatic = 0 then
            ShowFlashMessage('Already been targeted')
          else
            Dec(TargetsLeft);
          RedrawMapCell(CombatantX(ds6C91[Count]), CombatantY(ds6C91[Count]));
        end
        else
          Dec(TargetsLeft);
      end;
      ds6C94 := Count;
      if Count = 0 then
        Done := 0;
    end;
  end;
end;
{ ovl13:2414. The C Cast command and the AI's memorized-spell cast: SpellNumber is the spell to
  cast (0 opens ChooseSpellFromList at once, the list position starting at NoChoice), NoRedraw is
  nonzero when the caller is the computer (the combat screen, cursor and panel are then not
  redrawn). A spell whose
  SpellTable byte +$B is 0 cannot be cast in combat ('Camp Only Spell'). When the spell's byte +$C
  div 3 (its casting delay) is 0 the spell goes off at once through ovl22_e5 and the turn ends
  (EndCombatTurn); otherwise the caster 'Begins Casting' (Done set), the spell is remembered in
  Combat^.PendingSpell and the delay is taken off Combat^.Initiative (at least 1), so the spell
  finishes on the caster's next turn (PlayerTurn ovl08:031A, ovl09 CastMemorizedSpell).
  QUIRK ovl13:2417: the byte local after Spell is declared and never read; it shifts every later
  local down one byte and is what makes the frame $1A. Globals: SelectedCharacter. }
procedure CastCombatSpell(SpellNumber, NoRedraw: Byte; var Done: Byte);
const
  { The list position ChooseSpellFromList starts from and returns when nothing was picked. }
  NoChoice = $FFFF;
  { The SpellTable bytes e15 tests (TSpellEntry.PadB). }
  SpellCombatFlag = $B;          { +$B: 0 marks a spell castable only in camp }
  SpellCastDelay = $C;           { +$C: div 3 gives the casting delay in rows }
  { The colour/row ShowCharacterMessage shows 'Begins Casting' on. }
  CastMessageRow = 10;
var
  Spell: Byte;                   { the spell number cast, 0 while none is chosen }
  Unused: Byte;                  { QUIRK ovl13:2417: declared but never read }
  CastTime: Byte;                { the spell's casting delay, PadB[$C] div 3 }
  Choice: Word;                  { ChooseSpellFromList's list position }
  Listed: Byte;                  { nonzero when ChooseSpellFromList has spells to show }
  ChosenChar: PCharacter;        { the caster (SelectedCharacter at entry) }
begin
  ChosenChar := SelectedCharacter;
  Listed := 1;
  Choice := NoChoice;
  Done := 0;
  Spell := SpellNumber;
  if Spell = 0 then
    Spell := ChooseSpellFromList(0, 1, Choice, Listed);
  if Spell > 0 then
    if SpellTable[Spell].PadB[SpellCombatFlag] = 0 then
    begin
      ShowFlashMessage('Camp Only Spell');
      Spell := 0;
    end;
  if NoRedraw = 0 then
  begin
    DrawCombatScreen;
    ShowCursorOn(ChosenChar, 3, 1);
    DrawCharacterPanel(ChosenChar);
  end;
  if Spell <= 0 then
    Exit;
  CastTime := SpellTable[Spell].PadB[SpellCastDelay] div 3;
  if CastTime = 0 then
  begin
    ovl22_e5(Spell, NoRedraw, 1, Done);
    Done := EndCombatTurn(ChosenChar);
  end
  else
  begin
    Done := 1;
    ShowCharacterMessage(ChosenChar, 'Begins Casting', CastMessageRow, 1);
    ChosenChar^.Combat^.PendingSpell := Spell;
    if ChosenChar^.Combat^.Initiative > CastTime then
      Dec(ChosenChar^.Combat^.Initiative, CastTime)
    else
      ChosenChar^.Combat^.Initiative := 1;
  end;
end;
{ ovl13:2432: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_2432; begin end;
{ ovl13:2574. Reports whether Who's attack on Target is a thief's backstab: Who's thief level
  (ClassLevels[6]) must be above 0 and Who must carry no slot-2 item but the one type below, with a
  backstab-capable readied weapon (SlotItems[0] empty or an item kind in the set below); then Target
  must have been attacked (Combat^.BF above 1) and must face Who (the direction from Who to Target,
  BearingTo, equals Target's Combat^.IconSet). The item kinds are read from ItemTable: 7 and 8 and
  $23..$25 are one-handed weapons, $22 and $26 are two-handed (excluded). RollAttackDamage applies
  the thief-level damage multiplier and ResolveCombatantAttacks uses it for the ds112 - 2 to-hit and
  attack kind 2. Globals: none. }
function IsBackstab(Who: PCharacter; Target: PCharacter): Boolean;
const
  { The readied-weapon (slot 0) item kinds that may backstab (ItemTable: kinds 7 and 8 and the
    one-handed weapons $23..$25; $22 and $26 are two-handed). }
  BackstabWeaponKind1 = 7;
  BackstabWeaponKind2 = 8;
  BackstabWeaponKindLow = $22;   { weapon kinds above this ... (ovl13:25E7) }
  BackstabWeaponKindHigh = $26;  { ... and below this are one-handed }
  { The only slot-2 item kind a backstab allows (ItemTable type 0, an armour). }
  BackstabSlotTwoKind = $32;
var
  Weapon: PItem;                 { Who's readied slot-0 item, SlotItems[0] }
  SlotTwo: PItem;                { Who's slot-2 item, SlotItems[2] }
  ItemKind: Byte;                { Weapon^.ItemType, only defined when Weapon is not nil }
  FromBehind: Byte;              { nonzero once the thief's backstab setup passes }
begin
  FromBehind := 0;
  Weapon := Who^.SlotItems[0];
  if Weapon <> nil then
    ItemKind := Weapon^.ItemType;
  SlotTwo := Who^.SlotItems[2];
  if Who^.ClassLevels[6] > 0 then
    if (SlotTwo = nil) or (SlotTwo^.ItemType = BackstabSlotTwoKind) then
      if (Weapon = nil) or (ItemKind = BackstabWeaponKind1) or (ItemKind = BackstabWeaponKind2) or
         ((ItemKind > BackstabWeaponKindLow) and (ItemKind < BackstabWeaponKindHigh)) then
        FromBehind := 1;
  if (FromBehind <> 0) and (Target^.Combat^.BF > 1) and
     (BearingTo(Who, Target) = Target^.Combat^.IconSet) then
    IsBackstab := True
  else
    IsBackstab := False;
end;
{ ovl13:257E: frame not read }
{@stub} procedure ovl13_fn_257E; begin end;
{ ovl13:25C9: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_25C9; begin end;
{ ovl13:263D. Returns the compass direction from Who's cell towards Target's cell: it reads both
  combat-map cells (CombatantX/CombatantY) and walks Dir 0..8, returning the first direction whose
  90-degree arc at Who (InDirArc) holds Target. Called to face a combatant at another: PerformAttack
  turns Target with the direction from Target to Who, NoteAttackBearing measures the target's
  facing error against it, and ovl09 uses the direction from Who to Combat^.Target as the AI's move
  direction (ovl09:07F2, 0B3C). }
function BearingTo(Who, Target: Pointer): Byte;
var
  Dir: Byte;                     { the direction walked, 0..8 }
  WhoX, WhoY: ShortInt;          { Who's combat-map cell }
  TargetX, TargetY: ShortInt;    { Target's combat-map cell }
begin
  WhoX := CombatantX(Who);
  WhoY := CombatantY(Who);
  TargetX := CombatantX(Target);
  TargetY := CombatantY(Target);
  Dir := 0;
  while not InDirArc(WhoX, WhoY, TargetX, TargetY, Dir) do
    Inc(Dir);
  BearingTo := Dir;
end;
{ ovl13:26B0. Shows one attack's missile flying from Who to Target: it picks a picture by Item's item
  kind (the missile sprite of the bearing from Who to Target for most kinds, a 2x2 combat icon or
  two rows of another picture for the rest) and draws it at Who's cell, then animates it along the
  line between the two combatants (WalkCombatLine), with a launch and an impact sound. Called by
  PerformAttack for the aimed item and for a readied bow. Globals: ds6E36 (the combat picture whose
  bytes-per-item word is read), VideoAdapter, ds2620 and ds262C (the two sounds). QUIRK ovl13:26DD:
  PixelBytes is worked out and never read. }
procedure ShowAttackAnimation(Who, Target: PCharacter; Item: PItem);
const
  { The first of the three directional missile pictures of the picture table ds5E5A (ovl13:26D1):
    an even bearing uses this slot plus Bearing mod 4, its half selected by Bearing div 4; an odd
    bearing uses the next slot, one half and a mirror for the westward directions. }
  MissilePicBase = 13;
  { The picture the kinds with neither a missile nor an icon copy: two rows of the slot seven past
    the base (ovl13:27E2, 27F9). }
  SwingPicOffset = 7;
  { The 2x2 combat icons drawn for the remaining kinds (ovl13:27A1, 27C1): three and four past the
    missile base, DrawCombatIcon's own four CopyPictureItem calls. }
  IconPicOffset1 = 3;
  IconPicOffset2 = 4;
  { The item kind whose own picture is drawn instead of the missile: the readied bow
    (ovl13:27D3, the same kind PerformAttack tests). }
  BowItemKind = $2F;
  { WalkCombatLine's Count and Mode for each picture kind (ovl13:26C9/26CD the missile, 27A6/27AA the
    icons, 280B/280F the swing). }
  MissileFrames = 1;
  MissileMode = 10;
  IconFrames = 4;
  IconMode = $32;
  SwingFrames = 2;
  SwingMode = $14;
var
  PicIndex: Byte;                { [bp-1] the picture slot the copies start from, 13 for a missile }
  Frames: Byte;                  { [bp-2] WalkCombatLine's Count: the animation frames }
  Bearing: Byte;                 { [bp-3] the direction from Who's cell to Target's cell (BearingTo) }
  Mode: Byte;                    { [bp-4] WalkCombatLine's Mode: nonzero draws every step }
  PixelBytes: Word;              { [bp-6] the picture's bytes per item quartered for the text adapter }
begin
  Bearing := BearingTo(Who, Target);
  Frames := MissileFrames;
  Mode := MissileMode;
  PicIndex := MissilePicBase;
  PixelBytes := PPictureHeader(ds6E36)^.ByteSize;
  if VideoAdapter = 1 then
    PixelBytes := PixelBytes div 4;
  case Item^.ItemType of
    9, $15, $1C, $1F, $49:
      if Odd(Bearing) then
      begin
        if (Bearing = 3) or (Bearing = 5) then
          CopyPictureItem(PicIndex + 1, 1, 0, Byte(Bearing = 5))
        else
          CopyPictureItem(PicIndex + 1, 0, 0, Byte(Bearing = 7));
      end
      else
        CopyPictureItem(PicIndex + Bearing mod 4, Bearing div 4, 0, 0);
    2, 7, $14:
      begin
        DrawCombatIcon(PicIndex + IconPicOffset1);
        Frames := IconFrames;
        Mode := IconMode;
      end;
    $55, $56:
      begin
        DrawCombatIcon(PicIndex + IconPicOffset2);
        Frames := IconFrames;
        Mode := IconMode;
      end;
  else
    begin
      if Item^.ItemType = BowItemKind then
        Inc(PicIndex);
      CopyPictureItem(PicIndex + SwingPicOffset, 0, 0, 0);
      CopyPictureItem(PicIndex + SwingPicOffset, 1, 1, 0);
      Frames := SwingFrames;
      Mode := SwingMode;
    end;
  end;
  SetSoundDriverIdle(0);
  PlaySound(ds2620);
  WalkCombatLine(CombatantX(Who), CombatantY(Who), CombatantX(Target), CombatantY(Target),
    Frames, Mode);
  PlaySound(ds262C);
  SetSoundDriverIdle(10);
end;
{ ovl13:2879. Works out the monster side's remaining hit points as a percentage and stores it in the
  morale byte ds6E2F, the value CheckMorale reads for a monster's second morale test: it walks the
  battle's character list ds5D96 and, for every combatant on the monster side (Side = SideMonsters),
  adds its maximum hit points (HpMax, +$32) and, when it is still in the fight (Flag10D set), its
  current hit points (Flag11B, +$11B). A monster whose Flag10D is clear keeps its maximum counted
  while its current hit points fall out of the sum, so damage lowers the percentage. The result is
  20 * current div maximum * 5 (0 when the monster side has no maximum hit points at all, which
  leaves ds6E2F unchanged). Called by StartBattle (ovl10:1E31, before the first round) and
  EndCombatRound (ovl08:0880, every round). Globals: ds5D96 (read), ds6E2F (written). }
procedure UpdateMonsterMorale;
var
  TotalMaxHp: Word;              { [bp-2] the monster side's total maximum hit points }
  TotalCurrentHp: Word;          { [bp-4] their total current hit points (the Flag10D combatants) }
  Who: PCharacter;               { [bp-8] the combatant walked in ds5D96 }
begin
  TotalMaxHp := 0;
  TotalCurrentHp := 0;
  Who := PCharacter(ds5D96);
  while Who <> nil do
  begin
    if Who^.Side = SideMonsters then
    begin
      if Who^.Flag10D <> 0 then
        TotalCurrentHp := TotalCurrentHp + Who^.Flag11B;
      TotalMaxHp := TotalMaxHp + Who^.HpMax;
    end;
    Who := Who^.Next;
  end;
  if TotalMaxHp > 0 then
    ds6E2F := 20 * TotalCurrentHp div TotalMaxHp * 5;
end;
{ ovl13:2908. Returns half of the largest round Movement (ComputeMovement div 2) among the combatants
  on the side opposing Who that are still in the fight (Flag10D set), and 0 when there is none: it
  walks the battle's character list ds5D96 and keeps the highest value. TryFlee compares the result
  with half of Who's own round Movement to decide whether Who outruns every enemy (Other < Moves
  gets away; level with it needs a coin) and CheckMorale panics Who when the result is at most half
  of Who's own Movement. Globals: ds5D96 (read). }
function FastestEnemyMovement(Who: Pointer): Byte;
var
  Best: Byte;                    { [bp-2] the largest half-movement found }
  Moves: Byte;                   { [bp-3] the current combatant's half-movement }
  Member: PCharacter;            { [bp-7] the combatant walked in ds5D96 }
begin
  Best := 0;
  Member := PCharacter(ds5D96);
  while Member <> nil do
  begin
    if OpposingSide(Who) = Member^.Side then
      if Member^.Flag10D <> 0 then
      begin
        Moves := ComputeMovement(Member) div 2;
        if Moves > Best then
          Best := Moves;
      end;
    Member := Member^.Next;
  end;
  FastestEnemyMovement := Best;
end;
{ ovl13:2998. Tells whether an attack on Target may go ahead: it is allowed without asking when Target
  is on the side opposing Who (OpposingSide) or is run by the computer (Quick), otherwise the player
  is asked 'Attack Ally: ' (AskYesNo) and that answer decides. On a yes it also turns the fight into
  a brawl: ds6DE2 and word 819 of ds49D6^ are set, every party member the computer runs (StatusOkay,
  B84 above $7F) is moved to the monster side (Side 1) and loses its remembered target, and the side
  counts are recomputed (RecountCombatSides). Called by MeleeAttack (ovl08:0D45) and ResolveAimedAttack.
  Globals: ds6DE2, ds49D6 and ds5D96 (read and written). }
function ConfirmAttackTarget(Who, Target: PCharacter): Boolean;
var
  Member: PCharacter;            { [bp-5] the combatant walked in ds5D96 }
begin
  if (OpposingSide(Target) = Who^.Side) or (Who^.Quick <> 0) then
    ConfirmAttackTarget := True
  else
  begin
    if AskYesNo('Attack Ally: ', $D, $A, $F) <> 'Y' then
      ConfirmAttackTarget := False
    else
    begin
      ConfirmAttackTarget := True;
      ds6DE2 := 1;
      ds49D6^[Var2AllyAttack] := 1;
      Member := PCharacter(ds5D96);
      while Member <> nil do
      begin
        if (Member^.Status = StatusOkay) and (Member^.B84 > $7F) then
        begin
          Member^.Side := 1;
          Member^.Combat^.Target := nil;
        end;
        Member := Member^.Next;
      end;
      RecountCombatSides;
    end;
  end;
end;
{ ovl13:2AA0. Shows the manual-aim prompt and returns the key the player pressed: it draws the
  target's character panel and puts the combat cursor on it (DrawCharacterPanel, ShowCursorOn), shows
  'Range = ' with the distance when ShowRange is nonzero, builds the aim menu 'Next Prev Manual ' +
  the target name + 'Center Exit' and reads a key from it through ReadPromptChoice ('Aim:'). The
  target name is 'Target ' when the distance is within Range and the aim is worth naming: always when
  ShowRange is 0, else only for a ranged weapon (IsRangedWeapon, ChooseAttackItem, and either no
  adjacent enemy or an ammo that can strike in melee). Called by ovl13_e17, the player's aim cursor.
  Globals: none. QUIRK ovl13:2ACF: Bearing is worked out and never read. }
function ShowAimPrompt(Who, Target: PCharacter; Range: Byte; ShowRange: Byte; Unused: Byte): Char;
var
  Aim: string[40];               { [bp-$2A] the menu text under the panel }
  ExtKey: Byte;                  { [bp-$2B] the extended key ReadPromptChoice returns }
  AimItem: Pointer;              { [bp-$2F] the ammo ChooseAttackItem picks for a ranged aim }
  Distance: Byte;                { [bp-$30] the distance from Who to Target (DistanceToTarget) }
  Bearing: Byte;                 { [bp-$31] the direction from Who to Target (BearingTo) }
begin
  Aim := '';
  Distance := DistanceToTarget(Who, Target);
  Bearing := BearingTo(Who, Target);
  if ShowRange <> 0 then
    DrawTextAt(0, $17, $A, 'Range = ' + ByteToText(Distance) + '  ');
  if Distance <= Range then
  begin
    if ShowRange = 0 then
      Aim := 'Target '
    else if Who <> Target then
      if not IsRangedWeapon(Who) then
        Aim := 'Target '
      else if ChooseAttackItem(Who, AimItem) <> 0 then
        if (CollectEnemiesInRange(Who, 1) = 0) or RangedWeaponCanMelee(Who) then
          Aim := 'Target ';
  end;
  Aim := 'Next Prev Manual ' + Aim + 'Center Exit';
  ShowCursorOn(Target, 3, 1);
  DrawCharacterPanel(Target);
  ShowAimPrompt := ReadPromptChoice('Aim:', Aim, $D, $A, $F, 0, 0, ExtKey);
end;
{ ovl13:2C3D. Records the aim on Target and, when Automatic is 1, attacks it: it sets Done and, in
  attack mode, first asks ConfirmAttackTarget (an attack on an ally is confirmed by the player) and
  clears Done on a no. When Done is still set it stores Target in the aim record Aim (Who, and the
  cell from CombatantX/CombatantY), clears CombatMap's show-cursor and centres the combat cursor on
  the target's cell (margin 3, the no-step direction 8); in attack mode it then sweeps the adjacent
  level-0 enemies (SweepEnemies, ending the turn when it swept) or names the ranged weapon's ammo
  (ChooseAttackItem, dropped to nil in melee range) and resolves the attack through PerformAttack.
  When Done was cleared the aim record is cleared (FillChar 7). Called by the manual aim cursor
  (ovl13_e17 through ovl13:2DFA) and ovl13:31D7. Globals: CombatMap (write).
  QUIRK ovl13:2C3D: the byte local is declared and never read; it makes the frame 6 bytes. }
procedure ResolveAimedAttack(Who, Target: PCharacter; Automatic: Byte; var Done: Byte; var Aim: TSpellTarget);
var
  Unused: Byte;                  { QUIRK ovl13:2C3D: declared, never read (the frame is 6 bytes) }
  AimItem: Pointer;              { [bp-5] the ammo ChooseAttackItem picks for a ranged attack }
begin
  AimItem := nil;
  Done := 1;
  if Automatic = 1 then
    if not ConfirmAttackTarget(Who, Target) then
      Done := 0;
  if Done <> 0 then
  begin
    Aim.Who := Target;
    Aim.X := CombatantX(Target);
    Aim.Y := CombatantY(Target);
    CombatMap^.ShowCursor := 0;
    MoveCombatCursor(CombatMap^.ViewX + 3, CombatMap^.ViewY + 3, 3, 8);
    if Automatic = 1 then
    begin
      if SweepEnemies(Who, Target) then
        Done := EndCombatTurn(Who)
      else
      begin
        NoteAttackBearing(Who, Target);
        if IsRangedWeapon(Who) then
          if ChooseAttackItem(Who, AimItem) <> 0 then
            if RangedWeaponCanMelee(Who) then
              if DistanceToTarget(Who, Target) = 1 then
                AimItem := nil;
        PerformAttack(Who, Target, 0, AimItem, Done);
      end;
    end;
  end
  else
    FillChar(Aim, SizeOf(Aim), 0);
end;
{ ovl13:2DFA. The manual aim cursor: clears the aim record Aim and starts the cursor on Target's cell
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
  a key under the title '(Use Cursor keys) ' (ReadPromptChoice, ds6E31): Enter or 'T' confirms (the
  cell and Target go into Aim and, when Automatic, ResolveAimedAttack resolves the attack, else Done
  is set; a failed aim redraws the cell and clears Aim), H/I/M/Q/P/O/K/G set Dir 0..7, #0 or 'E'
  cancels, 'C' centres the cursor (Dir 8) and any other key clears Dir. Called by the aim wrapper e17.
  Globals: CombatMap, BodyCount, BodyTable, CombatantRecord, CombatTiles, DirStepX, DirStepY, ds6E31. }
procedure RunAimCursor(Who, Target: PCharacter; Range, Automatic, AimFlag: Byte; var Done: Byte; var Aim: TSpellTarget);
var
  AimText: string[40];           { [bp-$29] the prompt text 'Center Exit' / 'Target Center Exit' }
  Key: Char;                     { [bp-$2A] the key ReadPromptChoice returns (space to start) }
  AimItem: Pointer;              { [bp-$2E] the ammo ChooseAttackItem picks for a ranged aim }
  Dir: Byte;                     { [bp-$2F] the cursor's step direction }
  I: Byte;                       { [bp-$30] walk of BodyTable }
  WalkX, WalkY: ShortInt;        { [bp-$31], [bp-$32] the walk's endpoint }
  CurX, CurY: ShortInt;          { [bp-$33], [bp-$34] the cursor's cell }
  Occupant, Tile: Byte;          { [bp-$35], [bp-$36] the cursor cell's occupant and tile }
  Distance: Word;                { [bp-$38] the walk's step count }
  Valid: Boolean;                { [bp-$39] the cursor is on a legal aim }
begin
  FillChar(Aim, SizeOf(Aim), 0);
  CurX := CombatantX(Target);
  CurY := CombatantY(Target);
  Key := ' ';
  Dir := 8;
  Done := 0;
  CombatMap^.ShowCursor := 1;
  CombatMap^.CursorKind := 1;
  while not (Key in [#0, #13, 'E', 'T']) do
  begin
    MoveCombatCursor(CurX, CurY, 3, Dir);
    Inc(CurX, DirStepX[Dir]);
    Inc(CurY, DirStepY[Dir]);
    if CurX < 0 then
      CurX := 0;
    if CurY < 0 then
      CurY := 0;
    if CurX > $31 then
      CurX := $31;
    if CurY > $18 then
      CurY := $18;
    GetMapCell(CurX, CurY, Occupant, Tile);
    FlushKeyboard;
    Valid := False;
    Distance := $FF;
    WalkX := CurX;
    WalkY := CurY;
    if WalkLine(CombatantX(Who), CombatantY(Who), WalkX, WalkY, Distance, PMapRows(CombatMap)) then
    begin
      Valid := True;
      if Automatic <> 0 then
        DrawTextAt(0, $17, $A, 'Range = ' + WordToText(Distance shr 1) + '  ');
    end
    else if Automatic <> 0 then
      ClearWindow(0, $17, $27, $17);
    Distance := Distance shr 1;
    Target := nil;
    if Valid then
      if Occupant > 0 then
        Target := CombatantRecord[Occupant]
      else if Tile = $1F then
        for I := 1 to BodyCount do
          if (BodyTable[I].X = CurX) and (BodyTable[I].Y = CurY) then
            Target := BodyTable[I].Who;
    if Target <> nil then
      DrawCharacterPanel(Target)
    else
      ClearWindow($17, 1, $26, $15);
    if (Range < Distance) or (CombatTiles[Tile].Cost = $FF) then
      Valid := False;
    if Target <> nil then
    begin
      if not AttackTargetAllowed(Who, Target) then
        Valid := False;
      if Automatic = 1 then
        if (Who = Target) or ((Occupant = 0) and (Tile = $1F)) then
          Valid := False
        else if IsRangedWeapon(Who) then
          if (ChooseAttackItem(Who, AimItem) = 0) or
             ((CollectEnemiesInRange(Who, 1) > 0) and not RangedWeaponCanMelee(Who)) then
            Valid := False;
    end
    else if AimFlag = 0 then
      Valid := False;
    AimText := 'Center Exit';
    if Valid then
      AimText := 'Target ' + AimText;
    Key := ReadPromptChoice('(Use Cursor keys) ', AimText, $D, $A, $F, 1, 0, ds6E31);
    case Key of
      #13, 'T':
        begin
          CombatMap^.ShowCursor := 0;
          if Valid then
          begin
            Aim.X := CurX;
            Aim.Y := CurY;
            if Target <> nil then
              Aim.Who := Target
            else
              Aim.Who := nil;
            if Automatic = 1 then
              ResolveAimedAttack(Who, Aim.Who, Automatic, Done, Aim)
            else
              Done := 1;
          end;
          if (not Valid) or (Done = 0) then
          begin
            RedrawMapCell(CurX, CurY);
            Done := 0;
            FillChar(Aim, SizeOf(Aim), 0);
          end;
        end;
      'H': Dir := 0;
      'I': Dir := 1;
      'M': Dir := 2;
      'Q': Dir := 3;
      'P': Dir := 4;
      'O': Dir := 5;
      'K': Dir := 6;
      'G': Dir := 7;
      #0, 'E':
        begin
          RedrawMapCell(CurX, CurY);
          FillChar(Aim, SizeOf(Aim), 0);
          Done := 0;
        end;
      'C':
        begin
          MoveCombatCursor(CurX, CurY, 0, 8);
          Dir := 8;
        end;
    else
      Dir := 8;
    end;
  end;
end;
{ ovl13:32E6: retf 6: 6 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl13_fn_32E6; begin end;
{ ovl13:3389: retf 6: 6 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl13_fn_3389; begin end;
{ ovl13:3558: frame not read }
{@stub} procedure ovl13_e17(Who: Pointer; A, B, C: Byte; var Done: Byte; var Aim); begin end;
{ ovl13:3728: retf 18: 18 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_3728; begin end;
{ ovl13:37E4: frame not read }
{ ovl13:37E4. Picks an enemy inside Range for Who, the target search the automatic spell aim and the
  AI movement use: it first drops Who's remembered Combat^.Target unless ForgetTarget is 0 and the
  remembered target still fights (Flag10D set) on the other side and AttackTargetAllowed accepts it,
  in which case the result is True at once. Otherwise it searches in two passes: while no target is
  Found and the second pass has not been taken, it lists the enemies CollectEnemiesInRange(Who,
  Range) holds and, up to AimSearchTries times, picks one at random (RollDice); a pick is accepted
  when ThroughWalls and CombatMap^.Head6 are both set or AttackTargetAllowed allows it, and then
  Who^.Combat^.Target takes it; a refused pick is zeroed in ds6DE4 and the pass goes on only while
  another entry is left. The first pass leaves CombatMap^.Head6 as it is, the second opens it when
  ForgetTarget is 0, so it can see through a blocking tile; Head6 is cleared again at the end.
  Returns whether a target was set. Called by FindSpellTarget (aim, ForgetTarget 1) and ovl09
  QuickTurn, MoveStep and AiTurn. Globals: ds6DE4 (the scan list), CombatantRecord, CombatMap (Head6). }
function ChooseCombatTarget(Who: PCharacter; Range, ThroughWalls, ForgetTarget: Byte): Boolean;
var
  Count: Byte;                   { enemies the scan listed }
  Attempts: Byte;                { random picks left in this pass }
  Index: Byte;                   { the picked entry in ds6DE4 }
  Retry: Boolean;                { the second (open-gate) pass was taken }
  Found: Boolean;                { a target was accepted }
  Searched: Boolean;             { the open-gate pass already ran }
  Target: PCharacter;            { the remembered or picked target }
begin
  Searched := False;
  Found := False;
  Retry := False;
  Target := Who^.Combat^.Target;
  if (ForgetTarget <> 0) or ((Target <> nil) and ((Target^.Side = Who^.Side) or
     (Target^.Flag10D = 0) or not AttackTargetAllowed(Who, Target))) then
    Who^.Combat^.Target := nil;
  if Who^.Combat^.Target <> nil then
    Found := True;
  while (not Found) and (not Retry) do
  begin
    Retry := Searched;
    if Searched and (ForgetTarget = 0) then
      CombatMap^.Head6 := 1;
    Attempts := AimSearchTries;
    Count := CollectEnemiesInRange(Who, Range);
    while (Attempts > 0) and (not Found) and (Count > 0) do
    begin
      Dec(Attempts);
      Index := RollDice(1, Count);
      if ds6DE4[Index] > 0 then
      begin
        Target := CombatantRecord[ds6DE4[Index]];
        if ((ThroughWalls <> 0) and (CombatMap^.Head6 <> 0)) or
           AttackTargetAllowed(Who, Target) then
        begin
          Found := True;
          Who^.Combat^.Target := Target;
        end
        else
        begin
          ds6DE4[Index] := 0;
          for Index := 1 to Count do
            if ds6DE4[Index] > 0 then
              Found := True;
          if Found then
            Found := False
          else
            Count := 0;
        end;
      end;
    end;
    if not Searched then
      Searched := True;
  end;
  CombatMap^.Head6 := 0;
  ChooseCombatTarget := Found;
end;
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
