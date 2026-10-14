unit OVL09;
{ CombatAI (whitepaper 5.5.3): the computer's share of the combat turn. QuickTurn (called by
  CombatTurn/PlayerTurn, ovl08:01F6/031A, for a character with Quick set) reads keys, runs morale
  and the pending-spell finish, then loops into AiTurn: the turn loop that moves (MoveStep while
  panicking) and attacks (UseBestItem, the ovl13 attack routines), with ScoreItem rating the
  items for the item step, and HandleCombatKey and CheckMorale as the interruptions.
  Complete: make match UNIT=ovl09 says unit: complete (14 routines and one proven nested). }
{$A-,O+,F+,S-,R-,G-,I-,L-}
interface
uses POOLVARS;
procedure QuickTurn(Who: PCharacter);
function TryTurnUndead(Who: PCharacter): Boolean;
function SpellAccepted(Who: PCharacter; Spell, Range: Byte): Boolean;
function UseMagicItem(Who: PCharacter): Boolean;
function CastMemorizedSpell(Who: PCharacter): Byte;
function CanAffordStep(Who: PCharacter; Column, BaseDir: Byte; var OffMap: Byte): Boolean;
procedure MoveStep(Who: PCharacter);
function AiTurn(Who: PCharacter): Byte;
function ovl09_fn_0F4F(Who: PCharacter): Byte;
function HandleCombatKey(Who: PCharacter): Boolean;
function CheckMorale(Who: PCharacter): Byte;
function ScoreItem(Actor: PCharacter; Item: PItem): Byte;
procedure UseBestItem(Who: PCharacter);
implementation
uses Crt, RES04, RES05, RES06, RES12, OVL13, OVL19, OVL22, OVL24, OVL25, OVL30, OVL31;

const
  KeyAltM = '2';                { Alt-M: Magic On / Magic Off (ovl08 calls it KeyAltM too) }
  KeyAltX = '-';                { Alt-X: GodsIntervene decides }
  InitiativeQuickAll = $14;     { Initiative marking a quick-combat character (ovl08: InitiativeQuickAll) }
  VarNoCasting = 229;           { game variable (+$1CA) that hides Cast (ovl08: VarNoCasting) }
  MaxSpell = $38;               { highest spell number (ovl23: LastSpell) }
  Directions = 8;               { the eight combat directions (DirStepX/DirStepY) }
  StraightCost = 2;             { a straight step costs twice the tile cost in half squares (ovl09:0718) }
  DiagonalCost = 3;             { a diagonal step (odd direction) three times (ovl09:0723) }
  TileKept = $1E;               { the tile ProbeStep always answers when a cell has it (ovl31: TileKept) }
  { The four affects that let a combatant step onto a TileKept cell (ovl09:0744..07A4); which
    spells leave them is not known. }
  AffectKeptA = $20;
  AffectKeptB = $1E;
  AffectKeptC = $6F;
  AffectKeptD = $7D;
  AiTurnLimit = 20;             { AiTurn gives up after this many passes of its loop (ovl09:0B3C) }
  HookTurnStart = $0E;          { the affect hook kind AiTurn runs first, at the start of the turn [I] }
  RangeWrapped = $FF;           { a Range of 0 minus one wraps to this byte (AiTurn) }
  HandThreshold = 2;            { hands in use: above it UseBestItem readies the slot-1 item or the pick }
  SlotType49 = 11;              { SlotItems index of item type $49 (+$F8; ovl19 reads it, TCharacter.SlotItems) [I] }
  SlotType1C = 12;              { SlotItems index of item type $1C (+$FC) [I] }
  { ItemTable Flags bits (TItemRow.Flags); what the AI's item step reads them for [I] }
  FlagSlot11 = 1;               { bit 0: with FlagAttack the item's slot is SlotItems[SlotType49] }
  FlagAttack = 8;               { bit 3: an attack item (ScoreItem adds 2 per attack beyond the first) }
  FlagSlotItem = $10;           { bit 4: the item is itself a slot item (SlotPick := AttackPick) }
  FlagSlot12 = $80;             { bit 7: with FlagAttack the item's slot is SlotItems[SlotType1C] }
  FlagBothKinds = $14;          { bits $04 and $10 together (BothKinds) }
  FlagsSlotless = $0A;          { exactly $02 and $08: an attack item with no slot bit still counts as a found slot }

{ ovl09:000F. The computer's turn for Who (called by CombatTurn ovl08:01F6 and PlayerTurn
  ovl08:031A when the character is quick): it reads a key (HandleCombatKey), clears the prompt
  line, and ends the turn through EndCombatTurn when Who has left the fight (Flag10D 0). It rerolls
  the step pattern (StepPattern, +$15) when the current one is 0 or above 4, or when a d4 comes up 1:
  a d8 gives the new pattern, an 8 rerolls a d2 + 4, anything else a d4. Morale (CheckMorale) runs
  when no key was pressed; a panicking character (Panic, +$14) that is not forced to flee (ForcedFlight,
  +$10 zero) shows 'flees in panic' (the unit's string at offset 0) through ShowCharacterMessage. Then, while
  the turn is not over: use a magic item (UseMagicItem, ending through EndCombatTurn), finish a
  pending spell (Combat^.PendingSpell; ovl22_e5, end of turn), take the Turn action (TryTurnUndead,
  Turn Undead for a cleric, end of turn), cast a memorized spell (CastMemorizedSpell, Done := 1), use
  the best item (UseBestItem) and read keys again (HandleCombatKey); with Done clear it loops on
  ChooseCombatTarget(Who, $FF, 1, 0): an initiative above 0 runs AiTurn, else the turn ends through
  ovl09_fn_0F4F. Globals: none. QUIRK: ovl22_e5's var result is overwritten at once. }
procedure QuickTurn(Who: PCharacter);
var
  Pattern: Byte;
  Done: Byte;
begin
  Done := Ord(HandleCombatKey(Who));
  ClearPromptLine;
  ClearCharacterMessage;
  if Who^.Flag10D = 0 then
    Done := EndCombatTurn(Who);
  Pattern := Who^.Combat^.StepPattern;
  if (Pattern = 0) or (Pattern > 4) or (RollDice(1, 4) = 1) then
  begin
    Pattern := RollDice(1, 8);
    if Pattern = 8 then
      Pattern := RollDice(1, 2) + 4
    else
      Pattern := RollDice(1, 4);
  end;
  Who^.Combat^.StepPattern := Pattern;
  if Done = 0 then
    Done := CheckMorale(Who);
  if (Who^.Combat^.Panic <> 0) and (Who^.Combat^.ForcedFlight = 0) then
    ShowCharacterMessage(Who, 'flees in panic', $0A, 1);
  if Done <> 0 then
    Exit;
  if UseMagicItem(Who) then
  begin
    Done := EndCombatTurn(Who);
    Exit;
  end;
  if Who^.Combat^.PendingSpell > 0 then
  begin
    ovl22_e5(Who^.Combat^.PendingSpell, 1, 1, Done);
    Done := EndCombatTurn(Who);
    Exit;
  end;
  if TryTurnUndead(Who) then
  begin
    Done := EndCombatTurn(Who);
    Exit;
  end;
  if CastMemorizedSpell(Who) <> 0 then
  begin
    Done := 1;
    Exit;
  end;
  UseBestItem(Who);
  Done := Ord(HandleCombatKey(Who));
  while Done = 0 do
  begin
    if ChooseCombatTarget(Who, $FF, 1, 0) and (Who^.Combat^.Initiative > 0) then
      Done := AiTurn(Who)
    else
      Done := ovl09_fn_0F4F(Who);
  end;
end;
{ ovl09:0203 (TryTurnUndead). The computer's Turn action, Turn Undead for a cleric: it returns True
  and calls TurnUndead (the Turn of PlayerTurn's T case, src/OVL08.PAS:220) when the combatant has not
  turned yet (Combat.Turned is 0), has a level in class 0 (ClassLevels[0] above 0; CombatMenu offers
  Turn on the same two tests, ovl08:0795) and SelectTurnUndeadTarget agrees; else it
  returns False. Called by QuickTurn (ovl09:0170): a True result ends the turn through EndCombatTurn.
  Unused fills the two frame bytes the code never reads ([bp-2..-4]; Done at [bp-5] is
  SelectTurnUndeadTarget's untyped var parameter). }
function TryTurnUndead(Who: PCharacter): Boolean;
var
  Unused: array[0..2] of Byte;
  Done: Byte;
begin
  if (Who^.Combat^.Turned = 0) and (Who^.ClassLevels[0] > 0) and SelectTurnUndeadTarget(Who, Done) then
  begin
    TryTurnUndead := True;
    TurnUndead(Who);
  end
  else
    TryTurnUndead := False;
end;
{ ovl09:02EB (SpellAccepted). Decides whether the AI accepts spell Spell cast at Range by Who
  (UseMagicItem 03E4 and CastMemorizedSpell 0545 keep what it accepts). Refuses at once when the
  spell row's +$D byte is below Range. A spell other than 3 whose +$E byte is 0, and spell 3 when
  FindNearbyTarget(Who, Done) agrees, are accepted at once. Otherwise CollectEnemiesInRange collects Who's
  enemies the area pattern of ovl22_e3(Spell) reaches (ds6DE4, count Tries): a zero count refuses,
  a zero +$F byte accepts; else each collected enemy is asked through the nested
  DifferentSideInArea, a Yes refuses the spell and a No (or no enemy at all) accepts it.
  The +$D..+$F bytes are the spell row's last three bytes of SpellTable (16-byte stride).
  QUIRK: the [bp-2..-4] frame bytes are never read (Unused). Globals: SpellTable, ds6DE4,
  CombatantTable, ds6718, CombatantRecord, SelectedCharacter, CombatMap. }
function SpellAccepted(Who: PCharacter; Spell, Range: Byte): Boolean;
var
  Unused: array[0..2] of Byte;
  Done: Byte;
  Tries: Byte;
  I: Byte;

  { Nested in SpellAccepted (ovl09:0255): scans the DS:5F27 map entities around (X, Y) with the
    area pattern of spell Spell (its +$F byte is the line budget, direction omni, footprint base
    1) into ds6718, then answers True when one of the found combatants has a Side different from
    OpposingSide(SelectedCharacter) (that is 1 for the party side 0). Purpose unknown. }
  function DifferentSideInArea(X, Y: ShortInt; Spell: Byte): Boolean;
  var
    I: Byte;
  begin
    DifferentSideInArea := False;
    ScanTargets(X, Y, SpellTable[Spell].PadB[$F], $FF, 1, CombatMap);
    for I := 1 to ds6718[0].Val do
      if CombatantRecord[ds6718[I].Head]^.Side <> OpposingSide(SelectedCharacter) then
        DifferentSideInArea := True;
  end;

begin
  SpellAccepted := False;
  if SpellTable[Spell].PadB[$D] < Range then
    Exit;
  if ((Spell <> 3) and (SpellTable[Spell].PadB[$E] = 0)) or
     ((Spell = 3) and FindNearbyTarget(Who, Done)) then
  begin
    SpellAccepted := True;
    Exit;
  end;
  Tries := CollectEnemiesInRange(Who, ovl22_e3(Spell));
  if Tries > 0 then
  begin
    if SpellTable[Spell].PadB[$F] = 0 then
    begin
      SpellAccepted := True;
      Exit;
    end;
    for I := 1 to Tries do
      if DifferentSideInArea(CombatantTable[ds6DE4[I]].X, CombatantTable[ds6DE4[I]].Y, Spell) then
        Exit;
    SpellAccepted := True;
  end;
end;
{ ovl09:03E4. Uses a magic item for the computer's turn (called by QuickTurn; True ends
  the turn through EndCombatTurn): rolls 1d7 rounds; each round walks Who^.Items for the first
  item that passes (not ovl22_e6, Affects[3] below $80, Readied, level from Affects[2] in
  1..MaxSpell adjusted down by $17 above it, and SpellAccepted in range) and remembers it as
  Best. Afterwards a chosen Best is used through UseItem and the result is True. Early exits
  (CanUseMagicItem zero, the actor's side count ds6814Sides zero, VarNoCasting set) return False at
  once. QUIRK ovl09:049F: RowByte (the Slot byte of the item's ItemTable row) is computed but never read. QUIRK: the
  [bp-5..-6] and [bp-9..-12] frame bytes are never read (UnusedA, UnusedB). Globals: ds6814Sides
  (ds6814), GameVars, ItemTable. }
function UseMagicItem(Who: PCharacter): Boolean;
label
  NextItem, Advance, NextRound, Done;
var
  Range: Byte;
  Roll: Byte;
  I: Byte;
  UnusedA: array[0..1] of Byte;
  RowByte: Byte;
  Level: Byte;
  UnusedB: array[0..3] of Byte;
  Target: PItem;
  Best: PItem;
  E8Done: Byte;
begin
  UseMagicItem := False;
  Best := nil;
  Range := 7;
  Roll := RollDice(1, 7);
  if Who^.Combat^.CanUseMagicItem = 0 then
    goto Done;
  if ds6814Sides[ShortInt(OpposingSide(Who))] <= 0 then
    goto Done;
  if GameVars^[VarNoCasting] <> 0 then
    goto Done;
  for I := 1 to Roll do
  begin
    Target := Who^.Items;
  NextItem:
    if Target = nil then
      goto NextRound;
    if Best <> nil then
      goto NextRound;
    Level := Target^.Affects[2];
    RowByte := ItemTable[Target^.ItemType].Slot;
    if not ovl22_e6(Target) then
      if Target^.Affects[3] < $80 then
        if Target^.Readied then
          if Level > 0 then
          begin
            if Level > MaxSpell then
              Level := Level - $17;
            if SpellAccepted(Who, Level, Range) then
              Best := Target;
          end;
  Advance:
    Target := Target^.Next;
    goto NextItem;
  NextRound:
    Dec(Range);
  end;
Done:
  if Best <> nil then
  begin
    UseItem(Best, E8Done);
    UseMagicItem := True;
  end;
end;
{ ovl09:0545. Casts a memorized spell for the computer's turn (called by QuickTurn; the nonzero
  result ends the turn). It collects Who's nonzero Spells (slots 0..20) only when Combat^.CanCast
  is nonzero (+1, the Cast offer of CombatMenu, ovl08:0747). Nothing is tried unless a spell was
  collected, the Magic toggle ds6E30 is on (Alt-M: Magic On) or Who is computer-run (B84 above $7F),
  and the actor's side count ds6814Sides[OpposingSide(Who)] is above 0. Then RollDice(1, 7) rounds
  run with the level starting at 7 and falling by one per round: each round tries up to three random
  memorized spells through SpellAccepted (Who, Spell, Level) and casts the first accepted one through
  CastCombatSpell (the Cast of CombatMenu). This routine does not read VarNoCasting (CombatMenu hides Cast
  with it) or CanUseMagicItem (UseMagicItem's gate). QUIRK: the [bp-0x17..-0x1A] and [bp-0x24] frame
  bytes are never read (UnusedC, UnusedD). Globals: ds6814Sides (ds6814), ds6E30. }
function CastMemorizedSpell(Who: PCharacter): Byte;
label
  Done;
var
  SpellList: array[0..20] of Byte;
  UnusedC: array[0..3] of Byte;
  Level: Byte;
  Roll: Byte;
  CastDone: Byte;
  Round: Byte;
  J: Byte;
  Count: Byte;
  I: Byte;
  Spell: Byte;
  Chosen: Byte;
  UnusedD: Byte;
begin
  Count := 0;
  if Who^.Combat^.CanCast <> 0 then
    for I := 0 to $14 do
      if Who^.Spells[I] > 0 then
      begin
        SpellList[Count] := Who^.Spells[I];
        Inc(Count);
      end;
  Chosen := 0;
  Level := 7;
  Roll := RollDice(1, 7);
  Round := 1;
  if Count <= 0 then
    goto Done;
  if (Who^.B84 > $7F) or ds6E30 then
  begin
    if ds6814Sides[ShortInt(OpposingSide(Who))] > 0 then
    begin
      while (Round <= Roll) and (Chosen = 0) do
      begin
        J := 1;
        while (J < 4) and (Chosen = 0) do
        begin
          I := RollDice(1, Count) - 1;
          Spell := SpellList[I];
          if SpellAccepted(Who, Spell, Level) then
            Chosen := Spell;
          Inc(J);
        end;
        Dec(Level);
        Inc(Round);
      end;
    end;
  end;
Done:
  if Chosen > 0 then
    CastCombatSpell(Chosen, 1, CastDone)
  else
    CastDone := 0;
  CastMemorizedSpell := CastDone;
end;
{ ovl09:0675. Decides whether the computer's combatant Who can afford the step of attempt
  Column of its step pattern: the direction is BaseDir plus StepTurnOffsets[StepPattern, Column] mod 8,
  ProbeStep looks at the cells; when the probed tile is 0 (off the map, GetMapCell) OffMap is 1
  and the result False at once (ovl09:06EC). Otherwise the result is True when no combatant is
  in the way, the tile cost is below the moves left and the
  step's cost (tile cost times 2, or 3 on a diagonal) is at or below the moves left; a TileKept
  tile is unaffordable unless Who has one of the four AffectKept affects. Called by MoveStep
  (ovl09:094B). Globals: StepTurnOffsets, CombatTiles. Affect receives the affect
  HasAffect finds and is never read. }
function CanAffordStep(Who: PCharacter; Column, BaseDir: Byte; var OffMap: Byte): Boolean;
var
  Affect: Pointer;
  Turn: Byte;
  Dir: Byte;
  Occupant: Byte;
  Tile: Byte;
  Cost: Byte;
begin
  OffMap := 0;
  CanAffordStep := False;
  Turn := StepTurnOffsets[Who^.Combat^.StepPattern, Column];
  Dir := (BaseDir + Turn) mod Directions;
  ProbeStep(Who, Dir, Occupant, Tile);
  if Tile = 0 then
  begin
    OffMap := 1;
    Exit;
  end;
  if Occupant = 0 then
    if CombatTiles[Tile].Cost < Who^.Combat^.Moves then
    begin
      Cost := StraightCost;
      if Odd(Dir) then
        Cost := DiagonalCost;
      Cost := Cost * CombatTiles[Tile].Cost;
      if Tile = TileKept then
        if not HasAffect(Who, AffectKeptA, Affect) then
          if not HasAffect(Who, AffectKeptB, Affect) then
            if not HasAffect(Who, AffectKeptC, Affect) then
              if not HasAffect(Who, AffectKeptD, Affect) then
                Cost := Who^.Combat^.Moves + 1;
      if Who^.Combat^.Moves >= Cost then
        CanAffordStep := True;
    end;
end;
{ ovl09:07F2 (MoveStep). One step of the AI's move for Who (called by the turn loop at ovl09:0B3C,
  ovl09:0BD3 and 0D7C; the caller loops while the turn lasts): shows 'Move/Attack, Move Left = n'
  with DrawTextAt(0, 24, 10, ...), lets HandleCombatKey interrupt (True ends the step), then gives
  up on the same NoStep path when no half-move is left, the initiative is gone, or a magic-user
  (ClassMask 5) is not panicking. A clear Panic byte +$14 asks BearingTo(Who, Combat^.Target) for
  the direction; a panicking one rerolls the step pattern (StepPattern, RollDice(1, 2)) and derives a
  direction from the party marker facing PartyFacing (+ 4 on the party side, mod 8). The step then tries
  patterns Step = 1..5 while CanAffordStep refuses them (a panicking actor that is off the map ends
  through TryFlee); with no affordable step, or one that would step back (ds443C = (Turn + 4)
  mod 8), the pattern is advanced (ds443D counts the turns) and the actor may instead end the turn
  through ovl09_fn_0F4F or ChooseCombatTarget. A step taken sets the icon (SetCombatantIcon with the turn),
  runs PartingShots (or StepCombatant once Flag10D is set past it) and ApplyCloudTile; an ending turn runs
  EndCombatTurn. QUIRK: the jumps to MoveEnd and from there to Finish (ovl09:0B27) are the
  original's; NoStep only computes ovl09_fn_0F4F. Globals: PartyFacing, ds443C, ds443D. }
procedure MoveStep(Who: PCharacter);
label
  TryTurn, CheckStep, AfterMove, MoveEnd, NoStep, Finish;
var
  Dir: Byte;
  Turn: Byte;
  Step: Byte;
  OffMap: Byte;
  Done: Byte;
begin
  DrawTextAt(0, 24, 10, 'Move/Attack, Move Left = ' +
    ByteToText(Who^.Combat^.Moves shr 1) + ' ');
  if HandleCombatKey(Who) then
    Exit;
  if Who^.Combat^.Moves shr 1 <= 0 then
    goto NoStep;
  if Who^.Combat^.Initiative <= 0 then
    goto NoStep;
  if (Who^.Combat^.Panic = 0) and (Who^.ClassMask = 5) then
    goto NoStep;
  if Who^.Combat^.Panic = 0 then
    Dir := BearingTo(Who, Who^.Combat^.Target)
  else
  begin
    Who^.Combat^.StepPattern := RollDice(1, 2);
    Dir := PartyFacing - (((PartyFacing + 2) mod 4) div 2);
    if Who^.Side = 0 then
      Dir := Dir + 4;
    Dir := Dir mod Directions;
  end;
  OffMap := 0;
  Done := 0;
  Step := 1;
  while (Step < 6) and (Done = 0) and
        not CanAffordStep(Who, Step, Dir, OffMap) do
  begin
    if (Who^.Combat^.Panic <> 0) and (OffMap <> 0) then
      Done := TryFlee(Who)
    else
      Inc(Step);
  end;
  if Done <> 0 then
  begin
    Who^.Combat^.Moves := 0;
    Who^.Combat^.Panic := 0;
    Done := EndCombatTurn(Who);
    goto AfterMove;
  end;
  Turn := (Dir + StepTurnOffsets[Who^.Combat^.StepPattern, Step])
    mod Directions;
  if (Step = 6) or (ds443C = ((Turn + 4) mod Directions)) then
  begin
    Inc(ds443D);
    Who^.Combat^.StepPattern := Who^.Combat^.StepPattern mod 6 + 1;
    if ds443D > 1 then
    begin
      Who^.Combat^.Target := nil;
      if ds443D > 2 then
      begin
        Who^.Combat^.Moves := 0;
        Done := 1;
        goto CheckStep;
      end;
      if not ChooseCombatTarget(Who, $FF, 1, 0) then
        Done := ovl09_fn_0F4F(Who);
    end;
  end;
CheckStep:
  if Step < 6 then
    ds443C := Turn
  else
    Done := 1;
AfterMove:
  if Done <> 0 then
    goto MoveEnd;
  SetCombatantIcon(Who, Turn, 0, 0);
  PartingShots(Who, Who^.Combat^.IconSet);
  if Who^.Flag10D = 0 then
  begin
    Done := EndCombatTurn(Who);
    goto MoveEnd;
  end;
  StepCombatant(Who, Who^.Combat^.IconSet);
  if Who^.Flag10D = 0 then
    Done := EndCombatTurn(Who);
  ApplyCloudTile(Who);
MoveEnd:
  goto Finish;
  { QUIRK: the original jumps to MoveEnd and from there to Finish (ovl09:0B27), then runs the
    NoStep block before the epilogue. }
NoStep:
  Done := ovl09_fn_0F4F(Who);
Finish:
end;
{ ovl09:0B3C. The AI's whole turn for Who (called by QuickTurn when the initiative allows). It
  clears the AI scratch (ds443C/D/E) and runs affect hook HookTurnStart ($0E). An initiative of 0
  ends the turn at once. Otherwise the loop (Done = 0 and CanAct <> 0) first, while panicking (Panic,
  +$14), steps with MoveStep for as long as the moves last, the initiative is above 0 and below
  InitiativeQuickAll ($14). Then an initiative of 0 or InitiativeQuickAll ends the turn without any
  action. Each pass counts I: after AiTurnLimit (20) passes Done is set and ovl09_fn_0F4F decides
  (a nonzero result ends the turn), and the pass still goes on to its attack. The attack range is the
  Range byte (+$C) of the item in slot 0 (SlotItems[0], +$CC) minus 1; a result of 0 or $FF (a Range of
  0 or 1) becomes 1. The remembered Combat^.Target is dropped when it is not dying or is on the party
  side. A target is attacked when line of sight (WalkLine, step count halved) reaches it within Range
  and AttackTargetAllowed allows it; otherwise a random enemy of the CollectEnemiesInRange(Who, Range) scan (ds6DE4) is
  picked, or UseBestItem chooses one when IsRangedWeapon holds, RangedWeaponCanMelee does not and a 1-step
  scan finds an enemy. The attack runs SweepEnemies/e11/e12 and ends the turn through EndCombatTurn.
  Result: 1 when the turn is over (CanAct = 0). The arguments of ChooseCombatTarget ($FF, 0, 0) are Purpose unknown.
  QUIRK ovl09:0C8E: Target := Combat^.Target is
  dereferenced (Target^.Flag10D at 0C91, Target^.Side at 0C9C) before its nil test at 0CAC, so a
  character with no remembered target reads through a nil pointer. QUIRK: [bp-3] is reused for
  ChooseAttackItem's dead result. Globals: ds443C, ds443D, ds443E, ItemTable, ds6DE4, CombatantRecord,
  CombatMap. }
function AiTurn(Who: PCharacter): Byte;
label
  Loop, Next, Attack, Finish;
var
  Done: Byte;
  Flag: Byte;
  CanAct: Byte;
  Range: Byte;
  StepCount: Word;
  Count: Byte;
  Index: Byte;
  Aim: Pointer;
  Target: PCharacter;
  TargetX, TargetY: ShortInt;
  I: Byte;
begin
  ds443C := 8;
  ds443D := 0;
  ds443E := 0;
  I := 0;
  CanAct := 1;
  Done := 0;
  RunAffectHooks(HookTurnStart, Who);
  if Who^.Combat^.Initiative = 0 then
    CanAct := 0;
Loop:
  if Done <> 0 then
    goto Finish;
  if CanAct = 0 then
    goto Finish;
  if Who^.Combat^.Panic <> 0 then
    while (Who^.Combat^.Moves > 0) and (Who^.Combat^.Initiative > 0) and
          (Who^.Combat^.Initiative < InitiativeQuickAll) do
      MoveStep(Who);
  if (Who^.Combat^.Initiative = 0) or (Who^.Combat^.Initiative = InitiativeQuickAll) then
    CanAct := 0
  else
    Done := 0;
  if Done <> 0 then
    goto Next;
  if CanAct = 0 then
    goto Next;
  Inc(I);
  if I > AiTurnLimit then
  begin
    Done := 1;
    CanAct := Ord(ovl09_fn_0F4F(Who) = 0);
  end;
  Flag := 0;
  Range := 1;
  if Who^.SlotItems[0] <> nil then
    Range := ItemTable[Byte(Who^.SlotItems[0]^.ItemType)].Range - 1;
  if (Range = 0) or (Range = RangeWrapped) then
    Range := 1;
  Target := Who^.Combat^.Target;
  if (Target^.Flag10D = 0) or (Target^.Side = 0) then
    Target := nil;
  if Target <> nil then
    if AttackTargetAllowed(Who, Target) then
    begin
      TargetX := CombatantX(Target);
      TargetY := CombatantY(Target);
      StepCount := Range;
      if WalkLine(CombatantX(Who), CombatantY(Who), TargetX, TargetY, StepCount,
                  Pointer(CombatMap)) then
        if StepCount shr 1 <= Range then
          Flag := 1;
    end;
  if Flag <> 0 then
    goto Attack;
  Count := CollectEnemiesInRange(Who, Range);
  if Count = 0 then
  begin
    if ChooseCombatTarget(Who, $FF, 0, 0) then
      MoveStep(Who)
    else
      Done := ovl09_fn_0F4F(Who);
    goto Attack;
  end;
  Index := RollDice(1, Count);
  Target := CombatantRecord[ds6DE4[Index]];
  if IsRangedWeapon(Who) then
    if not RangedWeaponCanMelee(Who) then
      if CollectEnemiesInRange(Who, 1) > 0 then
      begin
        UseBestItem(Who);
        Done := 1;
        goto Attack;
      end;
  if (DistanceToTarget(Who, Target) = 1) or AttackTargetAllowed(Who, Target) then
    Flag := 1;
Attack:
  if Flag <> 0 then
    MoveCombatCursor(CombatantX(Who), CombatantY(Who), 2,
      BearingTo(Who, Target));
  if Flag = 0 then
    goto Next;
  if SweepEnemies(Who, Target) then
  begin
    Done := EndCombatTurn(Who);
    goto Next;
  end;
  NoteAttackBearing(Who, Target);
  Aim := nil;
  if IsRangedWeapon(Who) then
  begin
    Flag := ChooseAttackItem(Who, Aim);
    if RangedWeaponCanMelee(Who) and (DistanceToTarget(Who, Target) = 1) then
      Aim := nil;
  end;
  PerformAttack(Who, Target, 0, Aim, Done);
  if Done <> 0 then
  begin
    CanAct := 0;
    goto Next;
  end;
  if Target^.Flag10D = 0 then
    Done := 1;
Next:
  goto Loop;
Finish:
  AiTurn := Ord(CanAct = 0);
end;
{ ovl09:0F4F. Purpose unknown: returns EndCombatTurn(Who) when IsHelpless(Who) or
  IsRangedWeapon(Who) is true or the combatant's Initiative is 0, else GuardTurn(Who).
  Called by QuickTurn (ovl09:01EE) and from the 07F2 and 0B3C regions. ClearCharacterMessage runs first
  (parameterless). }
function ovl09_fn_0F4F(Who: PCharacter): Byte;
begin
  ClearCharacterMessage;
  if IsHelpless(Who) or IsRangedWeapon(Who) or (Who^.Combat^.Initiative = 0) then
    ovl09_fn_0F4F := EndCombatTurn(Who)
  else
    ovl09_fn_0F4F := GuardTurn(Who);
end;
{ ovl09:0FC1. Handles a key pressed during the computer's combat turn (called by
  QuickTurn and the 07F2 region, who act when it returns True). Alt-M toggles the ds6E30 Magic
  flag with the same 'Magic On'/'Magic Off' message as PlayerTurn (ovl08:031A); Space clears
  Quick on every party member (B84 below $80, Status not 1) and, when Who is not quick yet,
  marks Who quick (Initiative := InitiativeQuickAll) and returns True; Alt-X asks GodsIntervene.
  QUIRK ovl09:10AA: the Alt-X answer is tested and nothing happens either way (empty then).
  QUIRK ovl09:0FD2: the KeyPressed test is inverted with an empty then-branch (if not
  KeyPressed then else). FlushKeyboard always runs at the end. }
function HandleCombatKey(Who: PCharacter): Boolean;
var
  Member: PCharacter;
  Key: Char;
begin
  HandleCombatKey := False;
  if not KeyPressed then
  else
  begin
    Key := ReadGameKey;
    if Key = #0 then
      Key := ReadGameKey;
    case Key of
      KeyAltM:
        begin
          ds6E30 := not ds6E30;
          if ds6E30 then
            ShowFlashMessage('Magic On')
          else
            ShowFlashMessage('Magic Off');
        end;
      ' ':
        begin
          Member := PCharacter(ds5D96);
          while Member <> nil do
          begin
            if (Member^.B84 < $80) and (Member^.Status <> 1) then
              Member^.Quick := 0;
            Member := Member^.Next;
          end;
          if Who^.Quick = 0 then
          begin
            Who^.Combat^.Initiative := InitiativeQuickAll;
            HandleCombatKey := True;
          end;
        end;
      KeyAltX:
        if GodsIntervene then
        begin
        end;
    end;
  end;
  FlushKeyboard;
end;
{ ovl09:10D7. The morale check of the computer's turn for Who (QuickTurn calls it when no key was
  pressed). Its result is 0 to go on, or the end of turn through EndCombatTurn after a surrender.
  Panic (+$14) is cleared first. A nonzero ForcedFlight (+$10) forces flight: Panic is set and 'is
  forced to flee' is shown through ShowCharacterMessage, and nothing else is checked. A character with B84
  at or below $7F (not computer-run) is not checked either. Otherwise the morale is ds6825 =
  (B84 and $7F) * 2, zeroed above $66, which the hook kind $11 (RunAffectHooks) may change. The first
  test holds when the morale is below the percentage of hit points lost (100 minus Flag11B * 100
  div HpMax; Flag11B is the current hit points) or is zero. Then ds6825 takes ds6E2F, the hook runs
  again, and the second test holds when it is below 100 minus ds49D6^[Var2Morale] (word 710 of the
  second game word block, $6B00..$6EFF, not GameVars; the morale source of ovl10), or is zero, or Who
  is on the party side (Side 0). Only when both tests hold is there a roll: FastestEnemyMovement at or below half
  of ComputeMovement's value sets Panic and removes affects $4A and $4B (the character panics and the turn
  goes on); a higher roll with Intelligence above 5 surrenders (DropCombatant(Who, 4, 'Surrenders'),
  result EndCombatTurn(Who)); otherwise nothing happens. QUIRK ovl09:1141: the B84 gate is an inverted
  test with an empty then-branch. QUIRK ovl09:11AD: Saved6825 is saved from ds6825 and never used.
  Globals: ds6825, ds6E2F, ds49D6 (word Var2Morale). }
function CheckMorale(Who: PCharacter): Byte;
var
  E20Result: Byte;
  Saved6825: Byte;
begin
  CheckMorale := 0;
  Who^.Combat^.Panic := 0;
  ovl24_e14(Who);
  if Who^.Combat^.ForcedFlight <> 0 then
  begin
    Who^.Combat^.Panic := 1;
    ShowCharacterMessage(Who, 'is forced to flee', $0A, 1);
  end
  else if Who^.B84 <= $7F then
  else
  begin
    ds6825 := (Who^.B84 and $7F) * 2;
    if ds6825 > $66 then
      ds6825 := 0;
    RunAffectHooks($11, Who);
    if (ds6825 < 100 - Who^.Flag11B * 100 div Who^.HpMax) or (ds6825 = 0) then
    begin
      Saved6825 := ds6825;
      ds6825 := ds6E2F;
      RunAffectHooks($11, Who);
      if (ds6825 < 100 - ds49D6^[Var2Morale]) or (ds6825 = 0) or (Who^.Side = 0) then
      begin
        E20Result := FastestEnemyMovement(Who);
        if E20Result <= ComputeMovement(Who) div 2 then
        begin
          Who^.Combat^.Panic := 1;
          RemoveAffect(Who, $4A, nil);
          RemoveAffect(Who, $4B, nil);
        end
        else if Who^.Intelligence > 5 then
        begin
          DropCombatant(Who, 4, 'Surrenders');
          CheckMorale := EndCombatTurn(Who);
        end;
      end;
    end;
  end;
end;
{ ovl09:128D (ScoreItem). Rates an item for the AI's item step: UseBestItem calls it for each carried
  item whose class bits fit the character and keeps the highest score (ovl09:1543). Actor is the
  character the step runs for (its Combat^.Target, HandsInUse and ByteA0 are read); Item is the
  candidate (its ItemType, Plus, Affects and Cursed are read). The score is the item's largest damage
  against normal-size foes (DiceCountNormal times DiceSizeNormal), plus eight times Plus when Plus is
  above 0 (weapons and armour carry a bonus of 1..3, whitepaper 5.4), plus twice BonusNormal when that
  is above 0, plus 2 per attack beyond the first on an attack item (FlagAttack, Attacks), plus 3 when the
  item takes one hand or none. It is 0 when the item's Hands plus the actor's HandsInUse are above 3,
  when Affects[3] is $84 and the low nibble of Affects[2] differs from the actor's ByteA0, when Affects[2]
  is $53, or when the item is cursed. Purpose unknown: the $84 and $53 rules, and the score of 8 for an
  item of type $55 when the actor's target's Pad74[$76] byte is above 0 (not named yet). Result: the
  score. Globals: ItemTable. }
function ScoreItem(Actor: PCharacter; Item: PItem): Byte;
var
  Score: Byte;
  Row: TItemRow;
begin
  Row := ItemTable[Item^.ItemType];
  Score := Row.DiceSizeNormal * Row.DiceCountNormal;
  if Item^.Plus > 0 then
    Score := Score + Item^.Plus * 8;
  if Row.BonusNormal > 0 then
    Score := Score + Row.BonusNormal * 2;
  if Item^.ItemType = $55 then
    if Actor^.Combat^.Target <> nil then
      if ShortInt(Actor^.Combat^.Target^.Pad74[$76]) > 0 then
        Score := 8;
  if (Row.Flags and FlagAttack) > 0 then
    Score := Score + (Row.Attacks - 1) * 2;
  if Row.Hands <= 1 then
    Score := Score + 3;
  if Row.Hands + Actor^.HandsInUse > 3 then
    Score := 0;
  if Item^.Affects[3] = $84 then
    if (Item^.Affects[2] and $0F) <> Byte(Actor^.ByteA0) then
      Score := 0;
  if Item^.Affects[2] = $53 then
    Score := 0;
  if Item^.Cursed then
    Score := 0;
  ScoreItem := Score;
end;
{ ovl09:13CA. The AI's item step for Who (called by QuickTurn every turn and by AiTurn before
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
  SlotItems, HandsInUse, ClassBits, BaseAttacks, BaseDamage and BaseDamageBonus. }
procedure UseBestItem(Who: PCharacter);
label
  AfterFirst, SkipSlotUse;
var
  AttackPick: PItem;
  OtherPick: PItem;
  PlusPick: PItem;
  Candidate: PItem;
  SlotPick: PItem;
  AttackScore: Byte;
  OtherScore: Byte;
  PlusScore: Byte;
  Score: Byte;
  ItemType: Byte;
  AttackFlags: Byte;
  Unused1: Byte;
  SlotUsable: Byte;
  Used: Byte;
  BothKinds: Byte;
  SlotFound: Byte;
  Unused2: Byte;
begin
  if Who^.SlotItems[0] <> nil then
    Who^.HandsInUse := Who^.HandsInUse - ItemTable[Byte(Who^.SlotItems[0]^.ItemType)].Hands;
  if Who^.SlotItems[1] <> nil then
    Who^.HandsInUse := Who^.HandsInUse - ItemTable[Byte(Who^.SlotItems[1]^.ItemType)].Hands;
  AttackPick := nil;
  OtherPick := nil;
  PlusPick := nil;
  AttackScore := 1;
  OtherScore := Who^.BaseDamage[1] * Who^.BaseAttacks[1];
  if Who^.BaseDamageBonus[1] > 0 then
    OtherScore := OtherScore + Who^.BaseDamageBonus[1] * 2;
  PlusScore := 0;
  Candidate := Who^.Items;
  while Candidate <> nil do
  begin
    ItemType := Candidate^.ItemType;
    if ItemTable[ItemType].Slot = 0 then
    begin
      if (ItemTable[ItemType].ClassMask and Who^.ClassBits) = 0 then
        goto AfterFirst;
      Score := ScoreItem(Who, Candidate);
      if ((ItemTable[ItemType].Flags and FlagAttack) <> 0) or
         ((ItemTable[ItemType].Flags and FlagSlotItem) <> 0) then
        if Score > AttackScore then
        begin
          AttackPick := Candidate;
          AttackScore := Score;
        end;
      if (ItemTable[ItemType].Flags and FlagAttack) = 0 then
        if Score > OtherScore then
        begin
          OtherPick := Candidate;
          OtherScore := Score;
        end;
    end;
  AfterFirst:
    if ItemTable[ItemType].Slot = 1 then
      if (ItemTable[ItemType].ClassMask and Who^.ClassBits) > 0 then
      begin
        if Candidate^.Plus >= 0 then
          Score := Byte(Candidate^.Plus + 1)
        else
          Score := 0;
        if Score > PlusScore then
        begin
          PlusPick := Candidate;
          PlusScore := Score;
        end;
      end;
    Candidate := Candidate^.Next;
  end;
  if (AttackPick <> nil) and (ItemTable[Byte(AttackPick^.ItemType)].Range > 1) and
     ((ItemTable[Byte(AttackPick^.ItemType)].Flags and FlagBothKinds) = FlagBothKinds) then
    BothKinds := 1
  else
    BothKinds := 0;
  SlotFound := 0;
  SlotPick := nil;
  AttackFlags := 0;
  if AttackPick <> nil then
  begin
    AttackFlags := ItemTable[Byte(AttackPick^.ItemType)].Flags;
    if (AttackFlags and FlagSlotItem) <> 0 then
      SlotPick := AttackPick;
    if (AttackFlags and FlagAttack) <> 0 then
    begin
      if (AttackFlags and FlagSlot11) <> 0 then
        SlotPick := Who^.SlotItems[SlotType49];
      if (AttackFlags and FlagSlot12) <> 0 then
        SlotPick := Who^.SlotItems[SlotType1C];
    end;
  end;
  if (SlotPick <> nil) or (AttackFlags = FlagsSlotless) then
    SlotFound := 1;
  if (AttackPick <> nil) and (AttackScore > OtherScore shr 1) and (SlotFound <> 0) and
     ((BothKinds <> 0) or (CollectEnemiesInRange(Who, 1) = 0)) then
    Candidate := AttackPick
  else
    Candidate := OtherPick;
  Used := 0;
  SlotUsable := 1;
  if Who^.SlotItems[0] <> nil then
    if (Who^.SlotItems[0] = Candidate) or Who^.SlotItems[0]^.Cursed then
      SlotUsable := 0;
  if SlotUsable = 0 then
    goto SkipSlotUse;
  if Who^.SlotItems[0] <> nil then
    ReadyItem(Who^.SlotItems[0]);
  RecalcCombatValues(Who);
  if Who^.SlotItems[1] <> nil then
    if not Who^.SlotItems[1]^.Cursed then
      Who^.HandsInUse := Who^.HandsInUse - ItemTable[Byte(Who^.SlotItems[1]^.ItemType)].Hands;
  if Candidate <> nil then
    ReadyItem(Candidate);
  Used := 1;
SkipSlotUse:
  RecalcCombatValues(Who);
  RefreshAttacks(Who);
  SlotUsable := 1;
  if Who^.SlotItems[1] <> nil then
    if (Who^.SlotItems[1] = PlusPick) or Who^.SlotItems[1]^.Cursed then
      SlotUsable := 0;
  if Who^.HandsInUse > HandThreshold then
  begin
    if (Who^.SlotItems[1] = nil) or Who^.SlotItems[1]^.Cursed then
    begin
      ReadyItem(Candidate);
      Used := 1;
    end
    else
    begin
      ReadyItem(Who^.SlotItems[1]);
      Used := 1;
    end;
  end
  else if Who^.HandsInUse < HandThreshold then
    if SlotUsable <> 0 then
    begin
      if Who^.SlotItems[1] <> nil then
        ReadyItem(Who^.SlotItems[1]);
      RecalcCombatValues(Who);
      if PlusPick <> nil then
        ReadyItem(PlusPick);
      Used := 1;
    end;
  RecalcCombatValues(Who);
  if Used <> 0 then
    DrawCharacterPanel(Who);
end;

begin
end.
