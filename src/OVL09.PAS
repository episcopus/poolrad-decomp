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
procedure ovl09_fn_03E4;
procedure ovl09_fn_0545;
procedure ovl09_fn_0675;
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
procedure ovl09_fn_0FC1;
procedure ovl09_fn_10D7;
function ScoreTarget(Actor, Foe: PCharacter): Byte;
procedure ovl09_fn_13CA;
procedure ovl09_fn_1583;
procedure ovl09_fn_1713;
procedure ovl09_fn_1758;
implementation
uses RES04, RES06, RES12, OVL13, OVL19, OVL22, OVL24, OVL25, OVL30, OVL31;

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
{ ovl09:03E4: retf 4: 4 bytes of parameters; 22 bytes of locals }
{@stub} procedure ovl09_fn_03E4; begin end;
{ ovl09:0545: retf 4: 4 bytes of parameters; 36 bytes of locals }
{@stub} procedure ovl09_fn_0545; begin end;
{ ovl09:0675: frame not read }
{@stub} procedure ovl09_fn_0675; begin end;
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
{ ovl09:0FC1: retf 4: 4 bytes of parameters; 16 bytes of locals }
{@stub} procedure ovl09_fn_0FC1; begin end;
{ ovl09:10D7: retf 4: 4 bytes of parameters; 22 bytes of locals }
{@stub} procedure ovl09_fn_10D7; begin end;
{ ovl09:128D. Scores a potential target for the computer's combat turn: copies the
  sixteen-byte RaceRow of the foe's race and builds a score from it, the foe's hit points and
  known-spell bytes, and the actor's combat state. ovl09_fn_13CA calls it for each candidate and
  keeps the highest score (ovl09:1543). Actor is 13CA's character (its Combat, PadCC[$100] and
  Pad9E[$A0] bytes are read); Foe is the candidate (its Race, HpMax and KnownSpells bytes are
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
    if (Foe^.KnownSpells[$0B] and $0F) <> Actor^.Pad9E[$A0] then
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
