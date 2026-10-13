unit OVL09;
{ CombatAI (whitepaper 5.5): the computer's share of the combat turn. ovl09_e1 acts for a
  quick-combat character (called by CombatTurn, ovl08:01F6): morale and panic, spell use,
  movement and attacks through the routines below. ScoreTarget rates a candidate victim for
  the target choice. Partly decompiled; the map's entries from 0675 to 1758 need a mapper pass
  (several real routines were split into far-call fragments, see the hand-off note). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure ovl09_e1(Who: Pointer);
function ovl09_fn_0203(Who: PCharacter): Boolean;
procedure ovl09_fn_0255;
function ovl09_fn_02EB(Who: Pointer; Spell, N: Byte): Boolean;
function UseMagicItem(Who: PCharacter): Boolean;
function CastMemorizedSpell(Who: PCharacter): Byte;
function CanAffordStep(Who: PCharacter; Column, BaseDir: Byte; var OffMap: Byte): Boolean;
procedure ovl09_fn_06AA;
procedure ovl09_fn_06AF;
procedure ovl09_fn_06B4;
procedure ovl09_fn_06B9;
procedure ovl09_fn_06BE;
procedure ovl09_fn_06C3;
procedure ovl09_fn_06C8;
procedure ovl09_fn_06CD;
procedure ovl09_fn_06D2;
procedure ovl09_fn_06D7;
procedure ovl09_fn_06DC;
procedure ovl09_fn_06E1;
procedure ovl09_fn_06EB;
procedure ovl09_fn_06FA;
procedure ovl09_fn_0704;
procedure ovl09_fn_0709;
procedure ovl09_fn_0718;
procedure ovl09_fn_07F2;
procedure ovl09_fn_0893;
procedure ovl09_fn_0898;
procedure ovl09_fn_098F;
procedure ovl09_fn_0999;
procedure ovl09_fn_099E;
procedure ovl09_fn_0B2A;
procedure ovl09_fn_0B2F;
procedure ovl09_fn_0B34;
procedure ovl09_fn_0B3C;
procedure ovl09_fn_0B48;
procedure ovl09_fn_0B57;
procedure ovl09_fn_0B66;
procedure ovl09_fn_0B96;
function ovl09_fn_0F4F(Who: PCharacter): Byte;
function HandleCombatKey(Who: PCharacter): Boolean;
function CheckMorale(Who: PCharacter): Byte;
function ScoreTarget(Actor, Foe: PCharacter): Byte;
procedure ovl09_fn_13CA;
procedure ovl09_fn_1583;
procedure ovl09_fn_1713;
procedure ovl09_fn_1758;
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

{ ovl09:000F: retf 4: 4 bytes of parameters; 18 bytes of locals }
{@stub} procedure ovl09_e1(Who: Pointer); begin end;
{ ovl09:0203. Purpose unknown: returns True and calls ovl13_e9 when the combatant may
  still turn (Combat.Turned is 0), has a level in class 0 (ClassLevels[0] above 0) and
  ovl13_e10 agrees; else returns False. Called by ovl09_e1 (ovl09:0169): a True result ends
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
{ ovl09:0255: retf 8: 8 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl09_fn_0255; begin end;
{ ovl09:02EB: retf 8: 4 bytes of parameters; 8 bytes of locals }
{@stub} function ovl09_fn_02EB(Who: Pointer; Spell, N: Byte): Boolean; begin end;
{ ovl09:03E4. Uses a magic item for the computer's turn (called by ovl09_e1; True ends
  the turn through res12_fn_2637): rolls 1d7 rounds; each round walks Who^.Items for the first
  item that passes (not ovl22_e6, Affects[3] below $80, Readied, level from Affects[2] in
  1..MaxSpell adjusted down by $17 above it, and ovl09_fn_02EB in range) and remembers it as
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
            if ovl09_fn_02EB(Who, Level, Range) then
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
{ ovl09:0545. Casts a memorized spell for the computer's turn (called by ovl09_e1; the
  nonzero result ends the turn): collects Who's nonzero memorized Spells (when CanCast allows),
  rolls rounds with a shrinking level, tries up to three random spells per round through
  ovl09_fn_02EB (Who, Spell, Level) and casts the first in range through ovl13_e15 (the Cast of
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
          if ovl09_fn_02EB(Who, Spell, Level) then
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
  tile is unaffordable unless Who has one of the four AffectKept affects. Called by
  ovl09_fn_0898 (ovl09:094B). Globals: StepTurnOffsets, CombatTiles. Affect receives the affect
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
{ ovl09:06AA: frame not read }
{@stub} procedure ovl09_fn_06AA; begin end;
{ ovl09:06AF: frame not read }
{@stub} procedure ovl09_fn_06AF; begin end;
{ ovl09:06B4: frame not read }
{@stub} procedure ovl09_fn_06B4; begin end;
{ ovl09:06B9: retf 47513: 47513 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl09_fn_06B9; begin end;
{ ovl09:06BE: frame not read }
{@stub} procedure ovl09_fn_06BE; begin end;
{ ovl09:06C3: frame not read }
{@stub} procedure ovl09_fn_06C3; begin end;
{ ovl09:06C8: frame not read }
{@stub} procedure ovl09_fn_06C8; begin end;
{ ovl09:06CD: frame not read }
{@stub} procedure ovl09_fn_06CD; begin end;
{ ovl09:06D2: frame not read }
{@stub} procedure ovl09_fn_06D2; begin end;
{ ovl09:06D7: frame not read }
{@stub} procedure ovl09_fn_06D7; begin end;
{ ovl09:06DC: frame not read }
{@stub} procedure ovl09_fn_06DC; begin end;
{ ovl09:06E1: frame not read }
{@stub} procedure ovl09_fn_06E1; begin end;
{ ovl09:06EB: frame not read }
{@stub} procedure ovl09_fn_06EB; begin end;
{ ovl09:06FA: frame not read }
{@stub} procedure ovl09_fn_06FA; begin end;
{ ovl09:0704: frame not read }
{@stub} procedure ovl09_fn_0704; begin end;
{ ovl09:0709: frame not read }
{@stub} procedure ovl09_fn_0709; begin end;
{ ovl09:0718: retf 12: 12 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl09_fn_0718; begin end;
{ ovl09:07F2: frame not read }
{@stub} procedure ovl09_fn_07F2; begin end;
{ ovl09:0893: frame not read }
{@stub} procedure ovl09_fn_0893; begin end;
{ ovl09:0898: frame not read }
{@stub} procedure ovl09_fn_0898; begin end;
{ ovl09:098F: frame not read }
{@stub} procedure ovl09_fn_098F; begin end;
{ ovl09:0999: frame not read }
{@stub} procedure ovl09_fn_0999; begin end;
{ ovl09:099E: frame not read }
{@stub} procedure ovl09_fn_099E; begin end;
{ ovl09:0B2A: frame not read }
{@stub} procedure ovl09_fn_0B2A; begin end;
{ ovl09:0B2F: frame not read }
{@stub} procedure ovl09_fn_0B2F; begin end;
{ ovl09:0B34: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl09_fn_0B34; begin end;
{ ovl09:0B3C: frame not read }
{@stub} procedure ovl09_fn_0B3C; begin end;
{ ovl09:0B48: frame not read }
{@stub} procedure ovl09_fn_0B48; begin end;
{ ovl09:0B57: frame not read }
{@stub} procedure ovl09_fn_0B57; begin end;
{ ovl09:0B66: frame not read }
{@stub} procedure ovl09_fn_0B66; begin end;
{ ovl09:0B96: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl09_fn_0B96; begin end;
{ ovl09:0F4F. Purpose unknown: returns res12_fn_2637(Who) when res12_fn_0B73(Who) or
  res12_fn_2E03(Who) is true or the combatant's Initiative is 0, else res12_fn_2686(Who).
  Called by ovl09_e1 (ovl09:01EE) and from the 07F2 and 0B3C regions. res12_fn_17E3 runs first
  (parameterless). }
function ovl09_fn_0F4F(Who: PCharacter): Byte;
begin
  res12_fn_17E3;
  if res12_fn_0B73(Who) or res12_fn_2E03(Who) or (Who^.Combat^.Initiative = 0) then
    ovl09_fn_0F4F := res12_fn_2637(Who)
  else
    ovl09_fn_0F4F := res12_fn_2686(Who);
end;
{ ovl09:0FC1. Handles a key pressed during the computer's combat turn (called by
  ovl09_e1 and the 07F2 region, who act when it returns True). Alt-M toggles the ds6E30 Magic
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
{ ovl09:10D7. The morale gauntlet for the computer's turn (called by ovl09_e1 when
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
  known-spell bytes, and the actor's combat state. ovl09_fn_13CA calls it for each candidate and
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
  if Row[1] + Actor^.PadCC[$100] > 3 then
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
{ ovl09:13CA: frame not read }
{@stub} procedure ovl09_fn_13CA; begin end;
{ ovl09:1583: frame not read }
{@stub} procedure ovl09_fn_1583; begin end;
{ ovl09:1713: frame not read }
{@stub} procedure ovl09_fn_1713; begin end;
{ ovl09:1758: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl09_fn_1758; begin end;

begin
end.
