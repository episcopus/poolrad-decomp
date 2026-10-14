unit OVL09;
{ CombatAI (whitepaper 5.5.3): the computer's share of the combat turn. QuickTurn (called by
  CombatTurn/PlayerTurn, ovl08:01F6/031A, for a character with Quick set) reads keys, runs morale
  and the pending-spell finish, then loops into AiTurn: the turn loop that moves (MoveStep while
  panicking) and attacks (UseBestItem, the ovl13 attack routines), with ScoreTarget rating the
  victims and HandleCombatKey and CheckMorale as the interruptions.
  Complete: make match UNIT=ovl09 says unit: complete (14 routines and one proven nested). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure QuickTurn(Who: PCharacter);
function ovl09_fn_0203(Who: PCharacter): Boolean;
function SpellAccepted(Who: PCharacter; Spell, Range: Byte): Boolean;
function UseMagicItem(Who: PCharacter): Boolean;
function CastMemorizedSpell(Who: PCharacter): Byte;
function CanAffordStep(Who: PCharacter; Column, BaseDir: Byte; var OffMap: Byte): Boolean;
procedure MoveStep(Who: PCharacter);
function AiTurn(Who: PCharacter): Byte;
function ovl09_fn_0F4F(Who: PCharacter): Byte;
function HandleCombatKey(Who: PCharacter): Boolean;
function CheckMorale(Who: PCharacter): Byte;
function ScoreTarget(Actor, Foe: PCharacter): Byte;
procedure UseBestItem(Who: PCharacter);
implementation
uses Crt, RES04, RES05, RES06, RES12, OVL13, OVL19, OVL22, OVL24, OVL25, OVL30, OVL31;

const
  KeyAltM = '2';                { Alt-M: Magic On / Magic Off (ovl08 calls it KeyAltM too) }
  KeyAltX = '-';                { Alt-X: ovl13_e24 decides }
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

{ ovl09:000F. The computer's turn for Who (called by CombatTurn ovl08:01F6 and PlayerTurn
  ovl08:031A when the character is quick): it reads a key (HandleCombatKey), clears the prompt
  line, and ends the turn through res12_fn_2637 when Who is not dying (Flag10D 0). It rerolls the
  step pattern (+$15) when the current one is 1..4 and a d4 comes up 1: a d8 gives the new
  pattern, an 8 rerolls a d2 + 4, anything else a d4. Morale runs when no key was pressed; a
  panicking character (+$14 set) that is not stuck (+$10 0) shows 'flees in panic' (unit offset 0)
  through res12_fn_16EC. Then, while the turn is not over: use a magic item (UseMagicItem, ending
  through res12_fn_2637), finish a pending spell (Combat^.PendingSpell; ovl22_e5, end of turn),
  take the level-0 turn (ovl09_fn_0203, end of turn), cast a memorized spell (CastMemorizedSpell,
  Done := 1), use the best item (UseBestItem) and read keys again (HandleCombatKey); with Done
  clear it loops on ovl13_e21(Who, $FF, 1, 0): an initiative above 0 runs AiTurn, else the turn
  ends through ovl09_fn_0F4F. Globals: none. QUIRK: ovl22_e5's var result is overwritten at once. }
procedure QuickTurn(Who: PCharacter);
var
  Step: Byte;
  Done: Byte;
begin
  Done := Ord(HandleCombatKey(Who));
  ClearPromptLine;
  res12_fn_17E3;
  if Who^.Flag10D = 0 then
    Done := res12_fn_2637(Who);
  Step := PByteArray(Who^.Combat)^[$15];
  if (Step = 0) or (Step > 4) or (RollDice(1, 4) = 1) then
  begin
    Step := RollDice(1, 8);
    if Step = 8 then
      Step := RollDice(1, 2) + 4
    else
      Step := RollDice(1, 4);
  end;
  PByteArray(Who^.Combat)^[$15] := Step;
  if Done = 0 then
    Done := CheckMorale(Who);
  if (PByteArray(Who^.Combat)^[$14] <> 0) and (PByteArray(Who^.Combat)^[$10] = 0) then
    res12_fn_16EC(Who, 'flees in panic', $0A, 1);
  if Done <> 0 then
    Exit;
  if UseMagicItem(Who) then
  begin
    Done := res12_fn_2637(Who);
    Exit;
  end;
  if Who^.Combat^.PendingSpell > 0 then
  begin
    ovl22_e5(Who^.Combat^.PendingSpell, 1, 1, Done);
    Done := res12_fn_2637(Who);
    Exit;
  end;
  if ovl09_fn_0203(Who) then
  begin
    Done := res12_fn_2637(Who);
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
    if ovl13_e21(Who, $FF, 1, 0) and (Who^.Combat^.Initiative > 0) then
      Done := AiTurn(Who)
    else
      Done := ovl09_fn_0F4F(Who);
  end;
end;
{ ovl09:0203. Purpose unknown: returns True and calls ovl13_e9 when the combatant may
  still turn (Combat.Turned is 0), has a level in class 0 (ClassLevels[0] above 0) and
  ovl13_e10 agrees; else returns False. Called by QuickTurn (ovl09:0169): a True result ends
  the turn through res12_fn_2637. Unused fills the two frame bytes the code never reads
  ([bp-2..-4]; B at [bp-5] is ovl13_e10's var parameter). }
function ovl09_fn_0203(Who: PCharacter): Boolean;
var
  Unused: array[0..2] of Byte;
  Done: Byte;
begin
  if (Who^.Combat^.Turned = 0) and (Who^.ClassLevels[0] > 0) and ovl13_e10(Who, Done) then
  begin
    ovl09_fn_0203 := True;
    ovl13_e9(Who);
  end
  else
    ovl09_fn_0203 := False;
end;
{ ovl09:02EB (SpellAccepted). Decides whether the AI accepts spell Spell cast at Range by Who
  (UseMagicItem 03E4 and CastMemorizedSpell 0545 keep what it accepts). Refuses at once when the
  spell row's +$D byte is below Range. A spell other than 3 whose +$E byte is 0, and spell 3 when
  ovl13_e13(Who, Done) agrees, are accepted at once. Otherwise res12_fn_2433 collects Who's
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
    res12_fn_23B7(SelectedCharacter) (that is 1 for the party side 0). Purpose unknown. }
  function DifferentSideInArea(X, Y: ShortInt; Spell: Byte): Boolean;
  var
    I: Byte;
  begin
    DifferentSideInArea := False;
    ScanTargets(X, Y, SpellTable[Spell].PadB[$F], $FF, 1, CombatMap);
    for I := 1 to ds6718[0].Val do
      if CombatantRecord[ds6718[I].Head]^.Side <> res12_fn_23B7(SelectedCharacter) then
        DifferentSideInArea := True;
  end;

begin
  SpellAccepted := False;
  if SpellTable[Spell].PadB[$D] < Range then
    Exit;
  if ((Spell <> 3) and (SpellTable[Spell].PadB[$E] = 0)) or
     ((Spell = 3) and ovl13_e13(Who, Done)) then
  begin
    SpellAccepted := True;
    Exit;
  end;
  Tries := res12_fn_2433(Who, ovl22_e3(Spell));
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
  the turn through res12_fn_2637): rolls 1d7 rounds; each round walks Who^.Items for the first
  item that passes (not ovl22_e6, Affects[3] below $80, Readied, level from Affects[2] in
  1..MaxSpell adjusted down by $17 above it, and SpellAccepted in range) and remembers it as
  Best. Afterwards a chosen Best is used through ovl19_e8 and the result is True. Early exits
  (Pad2 zero, both ds6814Sides zero, VarNoCasting set) return False at once. QUIRK ovl09:049F:
  RowByte (the RaceRow byte of the item kind) is computed but never read. QUIRK: the
  [bp-5..-6] and [bp-9..-12] frame bytes are never read (UnusedA, UnusedB). Globals: ds6814Sides
  (ds6814), GameVars, RaceRow. }
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
  if Who^.Combat^.Pad2 = 0 then
    goto Done;
  if ds6814Sides[ShortInt(res12_fn_23B7(Who))] <= 0 then
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
    RowByte := RaceRow[Target^.ItemType][0];
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
    ovl19_e8(Best, E8Done);
    UseMagicItem := True;
  end;
end;
{ ovl09:0545. Casts a memorized spell for the computer's turn (called by QuickTurn; the
  nonzero result ends the turn): collects Who's nonzero memorized Spells (when CanCast allows),
  rolls rounds with a shrinking level, tries up to three random spells per round through
  SpellAccepted (Who, Spell, Level) and casts the first in range through ovl13_e15 (the Cast of
  CombatMenu). Skips everything when no spell is memorized. QUIRK: the [bp-0x17..-0x1A] and
  [bp-0x24] frame bytes are never read (UnusedC, UnusedD). Globals: ds6814Sides (ds6814),
  ds6E30, GameVars (word 710). }
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
    if ds6814Sides[ShortInt(res12_fn_23B7(Who))] > 0 then
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
    ovl13_e15(Chosen, 1, CastDone)
  else
    CastDone := 0;
  CastMemorizedSpell := CastDone;
end;
{ ovl09:0675. Decides whether the computer's combatant Who can afford the step of attempt
  Column of its step pattern: the direction is BaseDir plus StepTurnOffsets[Combat+$15, Column] mod 8,
  ProbeStep looks at the cells; when the probed tile is 0 (off the map, GetMapCell) OffMap is 1
  and the result False at once (ovl09:06EC). Otherwise the result is True when no combatant is
  in the way, the tile cost is below the moves left and the
  step's cost (tile cost times 2, or 3 on a diagonal) is at or below the moves left; a TileKept
  tile is unaffordable unless Who has one of the four AffectKept affects. Called by MoveStep
  (ovl09:094B). Globals: StepTurnOffsets, CombatTiles. Affect receives the affect
  res12_fn_2199 finds and is never read. }
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
  Turn := StepTurnOffsets[PByteArray(Who^.Combat)^[$15], Column];
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
        if not res12_fn_2199(Who, AffectKeptA, Affect) then
          if not res12_fn_2199(Who, AffectKeptB, Affect) then
            if not res12_fn_2199(Who, AffectKeptC, Affect) then
              if not res12_fn_2199(Who, AffectKeptD, Affect) then
                Cost := Who^.Combat^.Moves + 1;
      if Who^.Combat^.Moves >= Cost then
        CanAffordStep := True;
    end;
end;
{ ovl09:07F2 (MoveStep). One step of the AI's move for Who (called by the turn loop at ovl09:0B3C,
  ovl09:0BD3 and 0D7C; the caller loops while the turn lasts): shows 'Move/Attack, Move Left = n'
  with DrawTextAt(0, 24, 10, ...), lets HandleCombatKey interrupt (True ends the step), then gives
  up on the same NoStep path when no half-move is left, the initiative is gone, or a magic-user
  (ClassMask 5) is not panicking. A clear Panic byte +$14 asks ovl13_e18(Who, Combat^.Target) for
  the direction; a panicking one rerolls the step pattern (+$15, RollDice(1, 2)) and derives a
  direction from the party marker facing PartyFacing (+ 4 on the party side, mod 8). The step then tries
  patterns Step = 1..5 while CanAffordStep refuses them (a panicking actor that is off the map ends
  through ovl13_e5); with no affordable step, or one that would step back (ds443C = (Turn + 4)
  mod 8), the pattern is advanced (ds443D counts the turns) and the actor may instead end the turn
  through ovl09_fn_0F4F or ovl13_e21. A step taken sets the icon (SetCombatantIcon with the turn),
  runs ovl13_e4 (or ovl13_e3 once Flag10D is set past it) and ApplyCloudTile; an ending turn runs
  res12_fn_2637. QUIRK: the jumps to MoveEnd and from there to Finish (ovl09:0B27) are the
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
  if (PByteArray(Who^.Combat)^[$14] = 0) and (Who^.ClassMask = 5) then
    goto NoStep;
  if PByteArray(Who^.Combat)^[$14] = 0 then
    Dir := ovl13_e18(Who, Who^.Combat^.Target)
  else
  begin
    PByteArray(Who^.Combat)^[$15] := RollDice(1, 2);
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
    if (PByteArray(Who^.Combat)^[$14] <> 0) and (OffMap <> 0) then
      Done := ovl13_e5(Who)
    else
      Inc(Step);
  end;
  if Done <> 0 then
  begin
    Who^.Combat^.Moves := 0;
    PByteArray(Who^.Combat)^[$14] := 0;
    Done := res12_fn_2637(Who);
    goto AfterMove;
  end;
  Turn := (Dir + StepTurnOffsets[PByteArray(Who^.Combat)^[$15], Step])
    mod Directions;
  if (Step = 6) or (ds443C = ((Turn + 4) mod Directions)) then
  begin
    Inc(ds443D);
    PByteArray(Who^.Combat)^[$15] := PByteArray(Who^.Combat)^[$15] mod 6 + 1;
    if ds443D > 1 then
    begin
      Who^.Combat^.Target := nil;
      if ds443D > 2 then
      begin
        Who^.Combat^.Moves := 0;
        Done := 1;
        goto CheckStep;
      end;
      if not ovl13_e21(Who, $FF, 1, 0) then
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
  ovl13_e4(Who, Who^.Combat^.IconSet);
  if Who^.Flag10D = 0 then
  begin
    Done := res12_fn_2637(Who);
    goto MoveEnd;
  end;
  ovl13_e3(Who, Who^.Combat^.IconSet);
  if Who^.Flag10D = 0 then
    Done := res12_fn_2637(Who);
  ApplyCloudTile(Who);
MoveEnd:
  goto Finish;
  { QUIRK: the original jumps to MoveEnd and from there to Finish (ovl09:0B27), then runs the
    NoStep block before the epilogue. }
NoStep:
  Done := ovl09_fn_0F4F(Who);
Finish:
end;
{ ovl09:0B3C. The AI's whole turn for Who (called by QuickTurn when the initiative allows): it
  clears the AI scratch (ds443C/D/E), runs affect hook $0E, ends at once when the initiative is
  0, and loops (Done = 0 and CanAct <> 0): while panicking (+$14) it steps MoveStep until the
  moves run out, initiative leaves 1..$13 or the panic clears; then it stumbles ($14 set: no
  step) or attacks. After 20 turns it gives up; the attack range comes from the race row byte
  +12 of the item in slot 0 (+$CC, minus 1, clamped). The remembered Combat^.Target is
  dropped when it is not dying or is on the party side, and a target is attacked when line of
  sight (WalkLine) reaches it within Range and ovl13_e8 allows it; otherwise a random enemy of
  the res12_fn_2433(Who, Range) scan (ds6DE4) is picked (or UseBestItem chooses one when
  res12_fn_2E03 says to). The attack runs ovl13_e7/e11/e12 and ends the turn through
  res12_fn_2637. Result: 1 when the turn is over (CanAct = 0). QUIRK: [bp-3] is reused for
  res12_fn_2E8B's dead result; the +$CC deref runs before its nil test. Globals: ds443C, ds443D,
  ds443E, RaceRow, ds6DE4, CombatantRecord, CombatMap. }
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
  RunAffectHooks($0E, Who);
  if Who^.Combat^.Initiative = 0 then
    CanAct := 0;
Loop:
  if Done <> 0 then
    goto Finish;
  if CanAct = 0 then
    goto Finish;
  if PByteArray(Who^.Combat)^[$14] <> 0 then
    while (Who^.Combat^.Moves > 0) and (Who^.Combat^.Initiative > 0) and
          (Who^.Combat^.Initiative < $14) do
      MoveStep(Who);
  if (Who^.Combat^.Initiative = 0) or (Who^.Combat^.Initiative = $14) then
    CanAct := 0
  else
    Done := 0;
  if Done <> 0 then
    goto Next;
  if CanAct = 0 then
    goto Next;
  Inc(I);
  if I > $14 then
  begin
    Done := 1;
    CanAct := Ord(ovl09_fn_0F4F(Who) = 0);
  end;
  Flag := 0;
  Range := 1;
  if Who^.SlotItems[0] <> nil then
    Range := RaceRow[Byte(Who^.SlotItems[0]^.ItemType)][12] - 1;
  if (Range = 0) or (Range = $FF) then
    Range := 1;
  Target := Who^.Combat^.Target;
  if (Target^.Flag10D = 0) or (Target^.Side = 0) then
    Target := nil;
  if Target <> nil then
    if ovl13_e8(Who, Target) then
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
  Count := res12_fn_2433(Who, Range);
  if Count = 0 then
  begin
    if ovl13_e21(Who, $FF, 0, 0) then
      MoveStep(Who)
    else
      Done := ovl09_fn_0F4F(Who);
    goto Attack;
  end;
  Index := RollDice(1, Count);
  Target := CombatantRecord[ds6DE4[Index]];
  if res12_fn_2E03(Who) then
    if not res12_fn_2E46(Who) then
      if res12_fn_2433(Who, 1) > 0 then
      begin
        UseBestItem(Who);
        Done := 1;
        goto Attack;
      end;
  if (res12_fn_255B(Who, Target) = 1) or ovl13_e8(Who, Target) then
    Flag := 1;
Attack:
  if Flag <> 0 then
    MoveCombatCursor(CombatantX(Who), CombatantY(Who), 2,
      ovl13_e18(Who, Target));
  if Flag = 0 then
    goto Next;
  if ovl13_e7(Who, Target) then
  begin
    Done := res12_fn_2637(Who);
    goto Next;
  end;
  ovl13_e11(Who, Target);
  Aim := nil;
  if res12_fn_2E03(Who) then
  begin
    Flag := res12_fn_2E8B(Who, Aim);
    if res12_fn_2E46(Who) and (res12_fn_255B(Who, Target) = 1) then
      Aim := nil;
  end;
  ovl13_e12(Who, Target, 0, Aim, Done);
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
{ ovl09:0F4F. Purpose unknown: returns res12_fn_2637(Who) when IsHelpless(Who) or
  res12_fn_2E03(Who) is true or the combatant's Initiative is 0, else res12_fn_2686(Who).
  Called by QuickTurn (ovl09:01EE) and from the 07F2 and 0B3C regions. res12_fn_17E3 runs first
  (parameterless). }
function ovl09_fn_0F4F(Who: PCharacter): Byte;
begin
  res12_fn_17E3;
  if IsHelpless(Who) or res12_fn_2E03(Who) or (Who^.Combat^.Initiative = 0) then
    ovl09_fn_0F4F := res12_fn_2637(Who)
  else
    ovl09_fn_0F4F := res12_fn_2686(Who);
end;
{ ovl09:0FC1. Handles a key pressed during the computer's combat turn (called by
  QuickTurn and the 07F2 region, who act when it returns True). Alt-M toggles the ds6E30 Magic
  flag with the same 'Magic On'/'Magic Off' message as PlayerTurn (ovl08:031A); Space clears
  Quick on every party member (B84 below $80, Status not 1) and, when Who is not quick yet,
  marks Who quick (Initiative := InitiativeQuickAll) and returns True; Alt-X asks ovl13_e24.
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
            res12_fn_1693('Magic On')
          else
            res12_fn_1693('Magic Off');
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
        if ovl13_e24 then
        begin
        end;
    end;
  end;
  FlushKeyboard;
end;
{ ovl09:10D7. The morale gauntlet for the computer's turn (called by QuickTurn when
  HandleCombatKey is false): clears the combat byte at +$14, then walks a chain of early exits
  to the end (result 0). A nonzero Combat^.Pad10 forces flight ('is forced to flee' through
  res12_fn_16EC); B84 at or below $7F ends it; otherwise ds6825 ((B84 and $7F) * 2, zeroed above
  $66) is compared against two hit-point percentages (Who's Flag11B loss and game word 710),
  each failure ending it. Survivors with a good ovl13_e20 roll against half the ovl13_e2 roll
  and Intelligence above 5 offer surrender ('Surrenders' through DropCombatant) and return
  res12_fn_2637(Who); the rest get two RemoveAffect affects ($4A, $4B) and also end it.
  QUIRK ovl09:1141: the B84 gate is an inverted test with an empty then-branch. QUIRK
  ovl09:11AD: Saved6825 is saved from ds6825 and never used. The +$14 combat byte lies past
  TCombatant (NoBody at +$13). Globals: ds6825, ds6E2F. }
function CheckMorale(Who: PCharacter): Byte;
var
  E20Result: Byte;
  Saved6825: Byte;
begin
  CheckMorale := 0;
  PByteArray(Who^.Combat)^[$14] := 0;
  ovl24_e14(Who);
  if Who^.Combat^.Pad10 <> 0 then
  begin
    PByteArray(Who^.Combat)^[$14] := 1;
    res12_fn_16EC(Who, 'is forced to flee', $0A, 1);
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
      if (ds6825 < 100 - ds49D6^[710]) or (ds6825 = 0) or (Who^.Side = 0) then
      begin
        E20Result := ovl13_e20(Who);
        if E20Result <= ovl13_e2(Who) div 2 then
        begin
          PByteArray(Who^.Combat)^[$14] := 1;
          RemoveAffect(Who, $4A, nil);
          RemoveAffect(Who, $4B, nil);
        end
        else if Who^.Intelligence > 5 then
        begin
          DropCombatant(Who, 4, 'Surrenders');
          CheckMorale := res12_fn_2637(Who);
        end;
      end;
    end;
  end;
end;
{ ovl09:128D. Scores a potential target for the computer's combat turn: copies the
  sixteen-byte RaceRow of the foe's race and builds a score from it, the foe's hit points and
  known-spell bytes, and the actor's combat state. UseBestItem calls it for each candidate and
  keeps the highest score (ovl09:1543). Actor is 13CA's character (its Combat, PadCC[$100] and
  ByteA0 bytes are read); Foe is the candidate (its Race, HpMax and KnownSpells bytes are
  read). Result: the target score. Globals: RaceRow (ds5582). The $55 race and the $84/$53
  known-spell values have no proven meaning yet; the ShortInt conversions of HpMax and the row
  bytes are the original's (signed compares and cbw, ovl09:12CA..12F2). }
function ScoreTarget(Actor, Foe: PCharacter): Byte;
var
  Score: Byte;
  Row: TRaceRow;
begin
  Row := RaceRow[Byte(Foe^.Race)];
  Score := Row[10] * Row[9];
  if ShortInt(Foe^.HpMax) > 0 then
    Score := Score + ShortInt(Foe^.HpMax) * 8;
  if ShortInt(Row[11]) > 0 then
    Score := Score + ShortInt(Row[11]) * 2;
  if Foe^.Race = $55 then
    if Actor^.Combat^.Target <> nil then
      if ShortInt(Actor^.Combat^.Target^.Pad74[$76]) > 0 then
        Score := 8;
  if (Row[14] and 8) > 0 then
    Score := Score + (Row[5] - 1) * 2;
  if Row[1] <= 1 then
    Score := Score + 3;
  if Row[1] + Actor^.ds100 > 3 then
    Score := 0;
  if Foe^.KnownSpells[$0C] = $84 then
    if (Foe^.KnownSpells[$0B] and $0F) <> Byte(Actor^.ByteA0) then
      Score := 0;
  if Foe^.KnownSpells[$0B] = $53 then
    Score := 0;
  if Foe^.KnownSpells[4] <> 0 then
    Score := 0;
  ScoreTarget := Score;
end;
{ ovl09:13CA. The AI's item step for Who (called by QuickTurn every turn and by AiTurn before
  attacking): it pays the two per-kind slot items (RaceRow[item type][1] off Who^.ds100), scores
  the carried items (ScoreTarget on the item record: its type indexes RaceRow) and keeps the best
  'attack' item (row[14] bit 3 or bit $10; AttackPick/Best), the best other item (bit 3 clear;
  OtherPick/Score2) and the best type-1 item by its Plus (row[0] = 1; PlusPick/Best2). The item
  to use is AttackPick when it beats half of Score2 and the row-14 bits point at a slot item,
  else OtherPick. It then uses the slot-0 item (unless it is the pick or cursed), the slot-1
  item (when not cursed, also paying its row[1] again) and the pick through ovl19_e7, and when
  Who^.ds100 is above 2 uses the slot-1 item or the pick, below 2 the slot-1 item, then PlusPick;
  every use runs RecalcCombatValues (and ovl13_e6 once), and a use ends with DrawCharacterPanel. Globals:
  RaceRow; TCharacter slots SlotItems and ds100/BaseAttacks/BaseDamage/BaseDamageBonus/dsB0. QUIRK: the [bp-1b] and
  [bp-20] frame bytes are never read. }
procedure UseBestItem(Who: PCharacter);
label
  AfterFirst, SkipSlotUse;
var
  AttackPick: PItem;
  OtherPick: PItem;
  PlusPick: PItem;
  Pick: PItem;
  SlotPick: PItem;
  Best: Byte;
  Score2: Byte;
  Best2: Byte;
  Score: Byte;
  ItemType: Byte;
  Row14: Byte;
  Unused1: Byte;
  SlotUsable: Byte;
  Used: Byte;
  BothKinds: Byte;
  SlotFound: Byte;
  Unused2: Byte;
begin
  if Who^.SlotItems[0] <> nil then
    Who^.ds100 := Who^.ds100 - RaceRow[Byte(Who^.SlotItems[0]^.ItemType)][1];
  if Who^.SlotItems[1] <> nil then
    Who^.ds100 := Who^.ds100 - RaceRow[Byte(Who^.SlotItems[1]^.ItemType)][1];
  AttackPick := nil;
  OtherPick := nil;
  PlusPick := nil;
  Best := 1;
  Score2 := Who^.BaseDamage[1] * Who^.BaseAttacks[1];
  if Who^.BaseDamageBonus[1] > 0 then
    Score2 := Score2 + Who^.BaseDamageBonus[1] * 2;
  Best2 := 0;
  Pick := Who^.Items;
  while Pick <> nil do
  begin
    ItemType := Pick^.ItemType;
    if RaceRow[ItemType][0] = 0 then
    begin
      if (RaceRow[ItemType][13] and Who^.PadB0) = 0 then
        goto AfterFirst;
      Score := ScoreTarget(Who, PCharacter(Pick));
      if ((RaceRow[ItemType][14] and 8) <> 0) or
         ((RaceRow[ItemType][14] and $10) <> 0) then
        if Score > Best then
        begin
          AttackPick := Pick;
          Best := Score;
        end;
      if (RaceRow[ItemType][14] and 8) = 0 then
        if Score > Score2 then
        begin
          OtherPick := Pick;
          Score2 := Score;
        end;
    end;
  AfterFirst:
    if RaceRow[ItemType][0] = 1 then
      if (RaceRow[ItemType][13] and Who^.PadB0) > 0 then
      begin
        if Pick^.Plus >= 0 then
          Score := Byte(Pick^.Plus + 1)
        else
          Score := 0;
        if Score > Best2 then
        begin
          PlusPick := Pick;
          Best2 := Score;
        end;
      end;
    Pick := Pick^.Next;
  end;
  if (AttackPick <> nil) and (RaceRow[Byte(AttackPick^.ItemType)][12] > 1) and
     ((RaceRow[Byte(AttackPick^.ItemType)][14] and $14) = $14) then
    BothKinds := 1
  else
    BothKinds := 0;
  SlotFound := 0;
  SlotPick := nil;
  Row14 := 0;
  if AttackPick <> nil then
  begin
    Row14 := RaceRow[Byte(AttackPick^.ItemType)][14];
    if (Row14 and $10) <> 0 then
      SlotPick := AttackPick;
    if (Row14 and 8) <> 0 then
    begin
      if (Row14 and 1) <> 0 then
        SlotPick := Who^.SlotItems[11];
      if (Row14 and $80) <> 0 then
        SlotPick := Who^.SlotItems[12];
    end;
  end;
  if (SlotPick <> nil) or (Row14 = $0A) then
    SlotFound := 1;
  if (AttackPick <> nil) and (Best > Score2 shr 1) and (SlotFound <> 0) and
     ((BothKinds <> 0) or (res12_fn_2433(Who, 1) = 0)) then
    Pick := AttackPick
  else
    Pick := OtherPick;
  Used := 0;
  SlotUsable := 1;
  if Who^.SlotItems[0] <> nil then
    if (Who^.SlotItems[0] = Pick) or Who^.SlotItems[0]^.Cursed then
      SlotUsable := 0;
  if SlotUsable = 0 then
    goto SkipSlotUse;
  if Who^.SlotItems[0] <> nil then
    ovl19_e7(Who^.SlotItems[0]);
  RecalcCombatValues(Who);
  if Who^.SlotItems[1] <> nil then
    if not Who^.SlotItems[1]^.Cursed then
      Who^.ds100 := Who^.ds100 - RaceRow[Byte(Who^.SlotItems[1]^.ItemType)][1];
  if Pick <> nil then
    ovl19_e7(Pick);
  Used := 1;
SkipSlotUse:
  RecalcCombatValues(Who);
  ovl13_e6(Who);
  SlotUsable := 1;
  if Who^.SlotItems[1] <> nil then
    if (Who^.SlotItems[1] = PlusPick) or Who^.SlotItems[1]^.Cursed then
      SlotUsable := 0;
  if Who^.ds100 > 2 then
  begin
    if (Who^.SlotItems[1] = nil) or Who^.SlotItems[1]^.Cursed then
    begin
      ovl19_e7(Pick);
      Used := 1;
    end
    else
    begin
      ovl19_e7(Who^.SlotItems[1]);
      Used := 1;
    end;
  end
  else if Who^.ds100 < 2 then
    if SlotUsable <> 0 then
    begin
      if Who^.SlotItems[1] <> nil then
        ovl19_e7(Who^.SlotItems[1]);
      RecalcCombatValues(Who);
      if PlusPick <> nil then
        ovl19_e7(PlusPick);
      Used := 1;
    end;
  RecalcCombatValues(Who);
  if Used <> 0 then
    DrawCharacterPanel(Who);
end;

begin
end.
