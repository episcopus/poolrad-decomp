unit OVL13;
{ CombatSpells: the combat actions overlay (whitepaper 5.5). RunCombat calls it to set up every
  combatant's round (ComputeMovement and StartCombatantRound), to move a combatant on the combat map (StepCombatant
  and ovl13_e4), and to resolve what a combat action does; the ovl13_eN entry points are the ones
  the combat menu and the combat AI call. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure StartCombatantRound(Who: PCharacter);
function ComputeMovement(Who: PCharacter): Byte;
procedure RollAttackDamage(Attacker: PCharacter; Target: PCharacter; Index: Byte);
procedure ovl13_fn_02F9;
procedure GuardedEnemiesAttack(Who: PCharacter);
procedure StepCombatant(Who: PCharacter; Dir: Byte);
procedure ovl13_fn_08AC;
procedure ovl13_e4(Who: Pointer; Dir: Byte);
procedure ovl13_fn_098F;
procedure ovl13_fn_0999;
procedure ovl13_fn_0B2A;
procedure ovl13_fn_0B2F;
procedure ovl13_fn_0B3E;
procedure ovl13_fn_0B48;
procedure ovl13_fn_0B4D;
procedure ovl13_fn_0B57;
procedure ovl13_fn_0B5C;
procedure ovl13_fn_0B61;
function ovl13_e5(Who: Pointer): Byte;
procedure ovl13_fn_0CEE;
procedure ovl13_e6(Who: PCharacter);
procedure ovl13_fn_0D92;
procedure ovl13_fn_0D99;
procedure ovl13_fn_0E08;
function ovl13_fn_0E52(Value: Byte): Byte;
function ovl13_e7(Who, Target: Pointer): Boolean;
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
uses RES03, RES06, RES12, OVL24, OVL31;
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

{ ovl13:0000. Sets up Who's turn at the start of a combat round: clears and re-arms its combat
  state Combat^ (PendingSpell 0, Cast and Use-magic allowed), refreshes it through ovl13_e6, lets
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
    ovl13_e6(Who);
    ds681A := Who^.PadA2;
    ds681D := False;
    RunAffectHooks(HookComputeMovement, Who);
    Who^.Pad113[$114] := ovl13_fn_0E52(ds681A);
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
{ ovl13:02F9: retf 16: 16 bytes of parameters; 594 bytes of locals }
{@stub} procedure ovl13_fn_02F9; begin end;
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
{ ovl13:08B2: frame not read }
{@stub} procedure ovl13_e4(Who: Pointer; Dir: Byte); begin end;
{ ovl13:098F: frame not read }
{@stub} procedure ovl13_fn_098F; begin end;
{ ovl13:0999: frame not read }
{@stub} procedure ovl13_fn_0999; begin end;
{ ovl13:0B2A: frame not read }
{@stub} procedure ovl13_fn_0B2A; begin end;
{ ovl13:0B2F: frame not read }
{@stub} procedure ovl13_fn_0B2F; begin end;
{ ovl13:0B3E: frame not read }
{@stub} procedure ovl13_fn_0B3E; begin end;
{ ovl13:0B48: frame not read }
{@stub} procedure ovl13_fn_0B48; begin end;
{ ovl13:0B4D: frame not read }
{@stub} procedure ovl13_fn_0B4D; begin end;
{ ovl13:0B57: frame not read }
{@stub} procedure ovl13_fn_0B57; begin end;
{ ovl13:0B5C: frame not read }
{@stub} procedure ovl13_fn_0B5C; begin end;
{ ovl13:0B61: retf 6: 6 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_0B61; begin end;
{ ovl13:0C6A: frame not read }
{@stub} function ovl13_e5(Who: Pointer): Byte; begin end;
{ ovl13:0CEE: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_0CEE; begin end;
{ ovl13:0D23: frame not read }
{@stub} procedure ovl13_e6(Who: PCharacter); begin end;
{ ovl13:0D92: frame not read }
{@stub} procedure ovl13_fn_0D92; begin end;
{ ovl13:0D99: frame not read }
{@stub} procedure ovl13_fn_0D99; begin end;
{ ovl13:0E08: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl13_fn_0E08; begin end;
{ ovl13:0E52: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} function ovl13_fn_0E52(Value: Byte): Byte; begin end;
{ ovl13:0E82: frame not read }
{@stub} function ovl13_e7(Who, Target: Pointer): Boolean; begin end;
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
