unit OVL22;
{ CastSpell: the spell study and casting overlay. It builds the spell lists the camp's
  ChooseSpellFromList shows (BuildSpellList and its helpers, whitepaper 5.22), runs the picker
  (ovl22_e1), gives a spell's area pattern size (SpellAreaSize) and casts, scribes, memorizes
  and learns spells for combat (ovl09) and the camp (ovl15). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS, RES03, RES06, RES09, RES12, OVL24, OVL25, OVL30, OVL31;
function ovl22_e1(Mode: Byte; var Choice: Word): Byte;
procedure AddSpellMenuLine(Spell: Byte);
procedure AddItemSpells(Pending: Byte);
procedure AddScrollSpells(Pending: Byte);
function BuildSpellList(Kind: Byte): Byte;
function SpellAreaSize(Spell: Byte): Byte;
function SpellAffectDuration(Spell: Byte): Word;
procedure ApplySpellToTargets(Spell, CasterLevel, Flag, Damage, Kind: Byte; Message: String40);
procedure ChooseSpellTargets(Spell: Byte; Unused: Byte; var Done: Byte);
procedure CastChosenSpell(Spell, Quick, Announce: Byte; var Done: Byte);
procedure ApplySpellToSide(Side: Byte; Message: String40);
procedure CastBless;
procedure CastCurse;
procedure CastCureLightWounds;
procedure CastCauseLightWounds;
procedure CastDetectionSpell;
procedure CastProtection;
procedure CastResistCold;
procedure CastBurningHands;
procedure CastCharmPerson;
procedure CastEnlarge;
procedure CastReduce;
procedure CastFriends;
procedure CastMagicMissile;
procedure CastShield;
procedure CastShockingGrasp;
procedure CastSleep;
procedure CastHoldPerson;
procedure CastResistFire;
procedure CastSilence;
procedure CastSlowPoison;
procedure CastSnakeCharm;
procedure CastSpiritualHammer;
procedure CastInvisibility;
procedure CastKnock;
procedure CastMirrorImage;
procedure CastRayOfEnfeeblement;
procedure CastStinkingCloud;
procedure CastStrength;
procedure CastAnimateDead;
procedure CastCureBlindness;
procedure CastCauseBlindness;
function CureDiseaseAffects: Boolean;
procedure CastCureDisease;
procedure CastCauseDisease;
procedure CastDispelMagic;
procedure CastPrayer;
procedure CastRemoveCurse;
procedure CastBestowCurse;
procedure ovl22_e47;
procedure ovl22_e48;
procedure ovl22_fn_2764;
procedure ovl22_e49;
procedure ovl22_fn_28BC;
procedure ovl22_fn_295B;
procedure ovl22_fn_2B8B;
procedure ovl22_e50;
procedure ovl22_e51;
procedure ovl22_e52;
procedure ovl22_fn_2D39;
procedure ovl22_e53;
procedure ovl22_e54;
procedure ovl22_e55;
procedure ovl22_fn_2EEA;
procedure ovl22_e56;
procedure ovl22_fn_2F57;
procedure ovl22_e57;
procedure ovl22_e58;
procedure ovl22_fn_2FD3;
procedure ovl22_e59;
procedure ovl22_e60;
procedure ovl22_e61;
procedure ovl22_e62;
procedure ovl22_e63;
procedure ovl22_fn_31D7;
function ovl22_e6(Item: Pointer): Boolean;
procedure ovl22_fn_3262;
procedure ovl22_e7(Who: PCharacter; Item: PItem; Spell: Byte);
procedure ovl22_e8(Who: PCharacter; Message: String40; Spell: Byte);
procedure ovl22_fn_3379;
procedure ovl22_e10;
implementation

{ ovl22:008A: retf 6: 6 bytes of parameters; 98 bytes of locals }
{@stub} function ovl22_e1(Mode: Byte; var Choice: Word): Byte; begin end;
{ ovl22:028D: retf 2: 2 bytes of parameters; 262 bytes of locals }
{ ovl22:028D. Appends one line for spell Spell to the spell menu list SpellMenuList (BuildSpellList calls this
  once per spell, in list order). The line's text is ' *' when the pending bit $80 of Spell is set,
  else '  ', followed by SpellNames[Spell and $7F]; when the spell's level differs from the level of
  the previous line a heading line (SpellLevelNames[level]: '1st Level' and so on) is inserted first.
  SpellMenuSpells[Count] keeps the spell number (pending bit cleared) of the line added. Called by BuildSpellList
  and AddItemSpells. }
procedure AddSpellMenuLine(Spell: Byte);
const
  MenuLineBytes = $2E;            { a menu line node: Text, Flag29 and Next, the used part of TMenuLine }
var
  Line: PMenuLine;
  Count: ShortInt;                { ShortInt, not Byte: indexing SpellMenuSpells and the level compare
                                    sign-extend with cwde (ovl22:0304, 035E) }
  PrevLevel: ShortInt;
begin
  Line := SpellMenuList;
  if SpellMenuList = nil then
  begin
    GetMem(Line, MenuLineBytes);
    SpellMenuList := Line;
    PrevLevel := 0;
    Count := 0;
  end
  else
  begin
    Count := 1;
    while Line^.Next <> nil do
    begin
      if Line^.Flag29 = 0 then
        Inc(Count);
      Line := Line^.Next;
    end;
    PrevLevel := SpellTable[SpellMenuSpells[Count - 1]].Level;
    GetMem(Line^.Next, MenuLineBytes);
    Line := Line^.Next;
  end;
  Line^.Next := nil;
  if SpellTable[Spell and $7F].Level <> PrevLevel then
  begin
    Line^.Text := SpellLevelNames[SpellTable[Spell and $7F].Level];
    Line^.Flag29 := 1;
    GetMem(Line^.Next, MenuLineBytes);
    Line := Line^.Next;
    Line^.Next := nil;
  end;
  if Spell > $7F then
    Line^.Text := ' *'
  else
    Line^.Text := '  ';
  Line^.Text := Line^.Text + SpellNames[Spell and $7F];
  Line^.Flag29 := 0;
  SpellMenuSpells[Count] := Spell and $7F;
end;
{ ovl22:044E: retf 2: 2 bytes of parameters; 6 bytes of locals }
{ ovl22:044E. Adds the spell affects of the current item (CurrentItem, set by AddScrollSpells or by the
  caller) to the spell menu list: for each of its three spell affects it calls AddSpellMenuLine and
  records the item in SpellMenuItems[SpellMenuItemCount]. Pending selects which affects count: nonzero
  takes the pending ones (bit $80 set, > $80), zero the plain ones (> 0). First it clears the item's
  HiddenNames when res12_fn_2199(SelectedCharacter, $10) reports the affect, or when the character is
  a cleric (ClassLevels[0] > 0) and RaceRow[ItemType][0] is $0C; a hidden item is skipped. Called by
  BuildSpellList (Kind 2) and AddScrollSpells. }
procedure AddItemSpells(Pending: Byte);
var
  I: Byte;
  Affect: Pointer;
begin
  if res12_fn_2199(SelectedCharacter, $10, Affect) or
     ((SelectedCharacter^.ClassLevels[0] > 0) and (RaceRow[CurrentItem^.ItemType][0] = $0C)) then
    CurrentItem^.HiddenNames := 0;
  if CurrentItem^.HiddenNames = 0 then
    for I := 1 to 3 do
      if ((Pending <> 0) and (CurrentItem^.Affects[I] > $80)) or
         ((Pending = 0) and (CurrentItem^.Affects[I] > 0)) then
      begin
        AddSpellMenuLine(CurrentItem^.Affects[I]);
        SpellMenuItems[SpellMenuItemCount] := CurrentItem;
        Inc(SpellMenuItemCount);
      end;
end;
{ ovl22:051C: retf 2: 2 bytes of parameters; 2 bytes of locals }
{ ovl22:051C. Builds the spell menu list from the selected character's carried items: it clears
  SpellMenuItems and SpellMenuItemCount, then walks SelectedCharacter^.Items and, for every scroll
  (ovl22_e6), calls AddItemSpells with its Pending argument. Called by BuildSpellList for the "on Scrolls"
  (Pending 0) and "to be scribed" (Pending 1) lists. }
procedure AddScrollSpells(Pending: Byte);
var
  I: Byte;
begin
  for I := 0 to $30 do
    SpellMenuItems[I] := nil;
  SpellMenuItemCount := 0;
  CurrentItem := SelectedCharacter^.Items;
  while CurrentItem <> nil do
  begin
    if ovl22_e6(CurrentItem) then
      AddItemSpells(Pending);
    CurrentItem := CurrentItem^.Next;
  end;
end;
{ ovl22:059C: retf 2: 2 bytes of parameters; 2 bytes of locals }
{ ovl22:059C. Builds the spell menu list SpellMenuList for the requested list kind and returns whether it
  is not empty. Kind (ChooseSpellFromList's SpellListKind): 0 the memorized spells (Spells[0..$14], plain),
  5 the pending memorized ones (bit $80), 1 the spell book (KnownSpells[1..$37]), 2 the selected
  character's first scroll item, 3 all scroll items plain, 6 all scroll items pending, 4 the spells the
  character has a slot for and does not know yet (SpellTable 1..$38). It clears SpellMenuSpells first.
  Called by ovl19:299C ChooseSpellFromList. }
function BuildSpellList(Kind: Byte): Byte;
var
  I: Byte;
begin
  BuildSpellList := 0;
  SpellMenuList := nil;
  for I := 0 to $14 do
    SpellMenuSpells[I] := 0;
  case Kind of
    0:
      for I := 0 to $14 do
        if (SelectedCharacter^.Spells[I] > 0) and (SelectedCharacter^.Spells[I] < $80) then
          AddSpellMenuLine(SelectedCharacter^.Spells[I]);
    5:
      for I := 0 to $14 do
        if SelectedCharacter^.Spells[I] > $7F then
          AddSpellMenuLine(SelectedCharacter^.Spells[I]);
    1:
      for I := 1 to $37 do
        if SelectedCharacter^.KnownSpells[I] <> 0 then
          AddSpellMenuLine(I);
    2: AddItemSpells(0);
    3: AddScrollSpells(0);
    6: AddScrollSpells(1);
    4:
      for I := 1 to $38 do
        if (SelectedCharacter^.SpellSlots[SpellTable[I].SpellClass, SpellTable[I].Level] > 0) and
           (SelectedCharacter^.KnownSpells[I] = 0) then
          AddSpellMenuLine(I);
  end;
  if SpellMenuList <> nil then
    BuildSpellList := 1;
end;
{ ovl22:0729: retf 2: 2 bytes of parameters; 2 bytes of locals }
{ ovl22:0729. The size of the area pattern of spell Spell: res12_fn_2433 collects the targets it
  reaches. A 16-byte SpellTable row gives a base (row +2) and a per-level byte (row +3), so the
  result is base + per-level * caster level, the level from res12_fn_26C2 (or * 6 while ds6DBF is
  set). A zero base with row +6 set becomes 1, and $FF (omni) becomes 1 too. Called by SpellAccepted
  (ovl09:02EB) and ovl13:1E16. }
function SpellAreaSize(Spell: Byte): Byte;
var
  Area: Byte;
begin
  if ds6DBF = 0 then
    Area := SpellTable[Spell].Pad2[2] + SpellTable[Spell].Pad2[3] * res12_fn_26C2(Spell)
  else
    Area := SpellTable[Spell].Pad2[3] * 6 + SpellTable[Spell].Pad2[2];
  if Area = 0 then
    if SpellTable[Spell].Pad2[6] <> 0 then
      Area := 1;
  if Area = $FF then
    Area := 1;
  SpellAreaSize := Area;
end;
{ ovl22:07D6. The duration (in ApplyAffect's time unit) of the affect a spell leaves. A few
  spells are rolled for instead of read from the table: spell or affect $28 is 1d6*10, $39 and $3D are
  5d4, $3B is 1d4*10+40, $3F is 2d10*10 in combat (view mode 5) else (1d10+10)*10, and $43 is a flat
  $5A0. Every other value uses the SpellTable row's duration base (byte +4) plus its per-level byte
  (byte +5) times the caster level from res12_fn_26C2. Called by ApplySpellToTargets (as ApplyAffect's
  Duration) and CastEnlarge, CastHoldPerson, CastStrength, ovl22_fn_2EEA. }
function SpellAffectDuration(Spell: Byte): Word;
const
  { The few spells whose affect time is rolled for instead of read from SpellTable; the values
    are the spell or affect codes the callers pass (the codes above $38 are affects, not spells). }
  RolledSpell28 = $28;             { 1d6 * 10 }
  RolledSpell39 = $39;             { 5d4 }
  RolledSpell3B = $3B;             { 1d4 * 10 + 40 }
  RolledSpell3D = $3D;             { 5d4 }
  RolledSpell3F = $3F;             { 2d10 * 10 in combat, else (1d10 + 10) * 10 }
  FixedSpell43 = $43;              { a flat $5A0 }
  CombatViewMode = 5;              { ds49F3 during combat (whitepaper 5.5) }
  Scale = 10;
var
  Value: Word;
begin
  case Spell of
    RolledSpell28:
      Value := RollDice(1, 6) * Scale;
    RolledSpell39, RolledSpell3D:
      Value := RollDice(5, 4);
    RolledSpell3B:
      Value := RollDice(1, 4) * Scale + 40;
    RolledSpell3F:
      if ds49F3 = CombatViewMode then
        Value := RollDice(2, 10) * Scale
      else
        Value := (RollDice(1, 10) + Scale) * Scale;
    FixedSpell43:
      Value := $5A0;
  else
    Value := SpellTable[Spell].Pad2[4] + SpellTable[Spell].Pad2[5] * res12_fn_26C2(Spell);
  end;
  SpellAffectDuration := Value;
end;
{ ovl22:08C3. Applies the chosen spell Spell to every target in ds6C91[1..ds6C94] (the list the
  picker ChooseSpellTargets filled). It first sets the global DamageKind (Kind when the spell deals Damage,
  else 0) and returns at once with no targets. For each non-nil target: it rolls the spell's own
  saving throw (SpellTable row byte +8 nonzero, the save kind in +9) into Saved, and, when the
  current spell's row byte +2 is $FF, runs the affect hooks, and rolls to hit the target's
  ResistValue (+$111); a miss cancels the damage and counts as saved. It deals Damage through
  DealDamage and, when the spell's AffectId (row byte +$A) is set, applies the affect through
  ApplyAffect with SpellAffectDuration(Spell), the caster level (CasterLevel, or res12_fn_26C2
  when 0), Flag, the row's save effect and Message. Called by the spell menus; the caster level is
  real or computed. }
procedure ApplySpellToTargets(Spell, CasterLevel, Flag, Damage, Kind: Byte; Message: String40);
var
  Level: Byte;                    { the caster level used as ApplyAffect's Data }
  I: Byte;                        { the target index, 1..ds6C94 }
  Target: PCharacter;             { the target ds6C91[I] the spell is applied to }
  Saved: Boolean;                 { whether the target saved against the spell }
begin
  if Damage = 0 then
    DamageKind := 0
  else
    DamageKind := Kind;
  if ds6C94 = 0 then
    Exit;
  if CasterLevel = 0 then
    Level := res12_fn_26C2(Spell)
  else
    Level := CasterLevel;
  for I := 1 to ds6C94 do
    if ds6C91[I] <> nil then
    begin
      Target := ds6C91[I];
      if SpellTable[Spell].Pad2[8] = 0 then
        Saved := False
      else
        Saved := SavingThrow(Target, SpellTable[Spell].Pad2[9], 0);
      if SpellTable[ds681B].Pad2[2] = $FF then
      begin
        res12_fn_0BB8(Target);
        RunAffectHooks($0B, Target);
        if not RollToHit(SelectedCharacter, Target, Target^.ResistValue) then
        begin
          Damage := 0;
          Saved := True;
        end;
      end;
      if Damage > 0 then
        DealDamage(Target, Damage, SpellTable[Spell].Pad2[8], Saved);
      if SpellTable[Spell].AffectId > 0 then
        ApplyAffect(Target, SpellTable[Spell].AffectId, SpellAffectDuration(Spell),
          Level, Flag, SpellTable[Spell].Pad2[8], Saved, Message);
    end;
  DamageKind := 0;
end;
{ ovl22:0A91. Picks the targets of a spell being cast and reports through Done whether the cast should
  go ahead. It defaults the picker's chosen character ds6DB5 to the selected character, sets the
  target count ds6C94 to 1 and the first target ds6C95 to the selected character, and Done to 1, then
  switches on the spell's target mode (SpellTable row byte +7): mode 1 keeps only the caster; mode 2
  asks 'Cast Spell on whom' (res12_fn_2C48 picks into ds6DB5) and keeps the pick, or clears Done and
  the list when none was picked; mode 4 adds every character of the party list ds5D96, walking Next
  (+$104), to the list; any other mode clears Done. The second byte parameter is unused (QUIRK
  ovl22:0A91: the original frame reserves it). Called as the DS:6B84 combat callback (ovl08 EndCombat
  stores @ChooseSpellTargets). }
procedure ChooseSpellTargets(Spell: Byte; Unused: Byte; var Done: Byte);
var
  { Never read: the original frame reserves one pointer (QUIRK ovl22:0A91); it is declared so the
    frame and the string temporary below it land where the original put them. }
  Spare: PCharacter;
begin
  if ds6DB5 = nil then
    ds6DB5 := SelectedCharacter;
  ds6C95 := SelectedCharacter;
  ds6C94 := 1;
  Done := 1;
  case SpellTable[Spell].Pad2[7] of
    1: ;
    2:
    begin
      res12_fn_27D9;
      res12_fn_2C48('Cast Spell on whom', 1, ds6DB5);
      if ds6DB5 = nil then
      begin
        ds6C95 := nil;
        ds6C94 := 0;
        Done := 0;
      end
      else
        ds6C95 := ds6DB5;
    end;
    4:
      begin
        ds6C91[ds6C94] := PCharacter(ds5D96);
        while ds6C91[ds6C94]^.Next <> nil do
        begin
          ds6C91[ds6C94 + 1] := ds6C91[ds6C94]^.Next;
          Inc(ds6C94);
        end;
      end;
  else
    Done := 0;
  end;
end;
{ ovl22:0C20 (e5). Casts a spell. Spell is the spell number, Quick (nonzero in quick combat)
  means the computer plays the cast so the player is not asked to give it up, and Announce
  (nonzero normally) is whether 'NAME casts SPELL' is shown; it is cleared when the spell is
  refused. Done is the target picker's out flag.
  Outside combat a spell with no target mode (SpellTable[Spell].Pad2[7] = 0) is combat-only: in
  the camp the player is asked to lose it, in the wilds to use the item that holds it. Then the
  target picker stored in DS:6B84 (SpellTargetPicker) fills Done; when it picked nothing the
  player may try again ('Abort Spell? ' in combat, or directly in quick combat) or the cast is
  given up. On a cast the caster is animated (res12_fn_19DE, faced towards the aim point ds6DB9/
  ds6DBA through InDirArc, a sound and a res12_fn_1A29 line) and the spell's handler
  SpellHandlers[Spell] runs with ds681B set. res12_fn_17E3 clears the prompt afterwards. Called
  by the combat and camp cast paths (ovl08:031A, ovl09:000F, ovl05:0ECD, ovl13:2432, ovl15:04A1,
  ovl19:1BD7). Globals: SelectedCharacter, ds49F3, ds6DBF, ds6DB9/ds6DBA, ds681B, ds6820 and the
  SpellHandlers table. }
procedure CastChosenSpell(Spell, Quick, Announce: Byte; var Done: Byte);
const
  CombatViewMode = 5;             { ds49F3 while a combat runs (whitepaper 5.5) }
  Fireball = $2F;                 { the two spells whose cast has its own sound }
  LightningBolt = $33;
  AimStep = 4;                    { the line res12_fn_1A29 walks for the cast animation }
  AimWidth = $1E;
  AnimationKind = $12;            { res12_fn_19DE's argument that starts the cast animation }
var
  OK: Boolean;                    { True while the cast should be tried again }
  { QUIRK ovl22:0C20: the byte at [bp-2] is allocated but never referenced; it is declared so the
    later locals land where the original put them. }
  Unused: Byte;
  CasterX, CasterY: ShortInt;                 { the caster's combat position (CombatantX/CombatantY) }
  Dir: Byte;                      { the direction the caster is turned towards the aim point }
  Caster: PCharacter;             { the caster: SelectedCharacter copied at entry }
begin
  Caster := SelectedCharacter;
  OK := True;
  if (ds49F3 <> CombatViewMode) and (SpellTable[Spell].Pad2[7] = 0) then
  begin
    if ds6DBF = 0 then
    begin
      DrawTextAt(1, $13, $A, SpellNames[Spell]);
      DrawTextAt(1, $14, $A, 'is a combat-only spell...');
      if AskYesNo('Lose it? ', $D, $F, $A) = 'Y' then
        res12_fn_148B(Spell);
    end
    else
    begin
      DrawTextAt(1, $13, $A, 'That Item');
      DrawTextAt(1, $14, $A, 'is a combat-only item...');
      if AskYesNo('Use it? ', $D, $F, $A) = 'Y' then
        Done := 1;
    end;
    Announce := 0;
    OK := False;
  end;
  if (Announce <> 0) and (ds6DBF = 0) then
    ovl22_e8(Caster, 'casts', Spell);
  while OK do
  begin
    SpellTargetPicker(Spell, Quick, Done);
    if Done <> 0 then
    begin
      OK := False;
      if ds49F3 = CombatViewMode then
      begin
        res12_fn_19DE(AnimationKind);
        CasterX := CombatantX(Caster);
        CasterY := CombatantY(Caster);
        Dir := 0;
        while not InDirArc(CasterX, CasterY, ds6DB9, ds6DBA, Dir) do
          Inc(Dir);
        SetCombatantIcon(Caster, Dir, 1, 0);
        SetSoundDriverIdle(0);
        case Spell of
          Fireball: PlaySound(ds262A);
          LightningBolt: PlaySound(ds2624);
        else
          PlaySound(ds2618);
        end;
        res12_fn_1A29(CasterX, CasterY, ds6DB9, ds6DBA, AimStep, AimWidth);
        SetSoundDriverIdle($A);
        if IsCombatantInView(Caster, 0) then
        begin
          SetCombatantIcon(Caster, Caster^.Combat^.IconSet, 1, 1);
          SetCombatantIcon(Caster, Caster^.Combat^.IconSet, 0, 0);
        end;
      end;
      ClearAttackerAffect(Caster);
      if ds6DBF = 0 then
        res12_fn_148B(Spell);
      ds681B := Spell;
      SpellHandlers[ds681B];
      ds681B := 0;
      ds6820 := 0;
    end
    else
    begin
      if ds49F3 <> CombatViewMode then
        OK := False
      else if (Quick <> 0) or (AskYesNo('Abort Spell? ', $E, $A, $F) = 'Y') then
      begin
        res12_fn_1693('Spell Aborted');
        if ds6DBF = 0 then
          res12_fn_148B(Spell);
        OK := False;
      end;
    end;
  end;
  res12_fn_17E3;
  if ds49F3 = CombatViewMode then
    ClearWindow(0, $17, $27, $17);
end;
{ ovl22:0F4F. Applies the current spell ds681B to the chosen targets (ds6C91[1..ds6C94]) but keeps
  only those on Side: a target whose TCharacter.Side differs is dropped (set nil) and, for spell 1
  (Bless) in combat, a target the spell's area already reaches (res12_fn_2433 nonzero) is dropped
  too. Sets ds6820 and calls ApplySpellToTargets with Message and no damage or affect of its own.
  Called by the cast handlers of spells 1 and 2 (Bless and Curse). }
procedure ApplySpellToSide(Side: Byte; Message: String40);
var
  I: Byte;                        { the target index, 1..ds6C94 }
begin
  ds6820 := 1;
  for I := 1 to ds6C94 do
    if (ds6C91[I]^.Side <> Side) or
       ((ds681B = 1) and (ds49F3 = 5) and (res12_fn_2433(ds6C91[I], 1) > 0)) then
      ds6C91[I] := nil;
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, Message);
end;
{ ovl22:100F (e11). Cast handler of spell 1, Bless: applies the current spell ds681B to the party
  side of the selected character (SelectedCharacter^.Side) with the message 'is Blessed'. One of the
  per-spell handlers in SpellHandlers (SpellHandlers[1], filled by ovl22_e10). }
procedure CastBless;
begin
  ApplySpellToSide(SelectedCharacter^.Side, 'is Blessed');
end;
{ ovl22:1040 (e12). Cast handler of spell 2, Curse: applies the current spell ds681B to the side
  opposite the selected character (res12_fn_23B7 returns 1 for side 0, else 0) with the message
  'is Cursed'. One of the per-spell handlers in SpellHandlers (SpellHandlers[2]). }
procedure CastCurse;
begin
  ApplySpellToSide(res12_fn_23B7(SelectedCharacter), 'is Cursed');
end;
{ ovl22:106B (e13). Cast handler of spell 3, Cure Light Wounds: when a target was chosen (ds6C94
  nonzero) it rolls 1d8 (RollDice) and heals the first target ds6C95 through HealCharacter (flag 0),
  then reports through res12_fn_234A whether the target is fully or partially healed. One of the
  per-spell handlers in SpellHandlers (SpellHandlers[3], filled by ovl22_e10). }
procedure CastCureLightWounds;
begin
  if ds6C94 = 0 then
    Exit;
  if HealCharacter(ds6C95, RollDice(1, 8), 0) then
    res12_fn_234A(ds6C95);
end;
{ ovl22:10A7 (e14). Cast handler of spell 4, Cause Light Wounds: applies the current spell ds681B
  to the chosen targets with 1d8 damage of kind 8 and no message (ApplySpellToTargets; the dice go
  through RollDiceCounted, which also records their count in ds681C). One of the per-spell handlers
  in SpellHandlers (SpellHandlers[4], filled by ovl22_e10). }
procedure CastCauseLightWounds;
begin
  ApplySpellToTargets(ds681B, 0, 0, RollDiceCounted(1, 8), 8, '');
end;
{ ovl22:10E9 (e15). Cast handler of the detection spells, spells 5 and 11 (Detect Magic), 18 (Read
  Magic), 22 (Find Traps) and 29 (Detect Invisibility): applies the current spell ds681B to the
  chosen targets with the message 'is affected' and no damage of its own (ApplySpellToTargets; the
  spell's own AffectId does the work). One of the per-spell handlers in SpellHandlers
  (SpellHandlers[5], [11], [18], [22] and [29]; the table is filled by ovl22_e10). }
procedure CastDetectionSpell;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'is affected');
end;
{ ovl22:1123 (e16). Cast handler of the protection spells, spells 6 and 16 (Protection From Evil) and
  7 and 17 (Protection From Good): applies the current spell ds681B to the chosen targets with the
  message 'is protected' and no damage of its own (ApplySpellToTargets; the spell's own AffectId does
  the work). One of the per-spell handlers in SpellHandlers (SpellHandlers[6], [7], [16] and [17];
  filled by ovl22_e10). }
procedure CastProtection;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'is protected');
end;
{ ovl22:1162 (e17). Cast handler of spell 8, Resist Cold: applies the current spell ds681B to the
  chosen targets with the message 'is cold-resistant' and no damage of its own (ApplySpellToTargets;
  the spell's own AffectId does the work). One of the per-spell handlers in SpellHandlers
  (SpellHandlers[8], filled by ovl22_e10). }
procedure CastResistCold;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'is cold-resistant');
end;
{ ovl22:1190 (e18). Cast handler of spell 9, Burning Hands: deals res12_fn_26C2(ds681B) (the caster
  level) damage of kind DamageKindFire to the chosen targets with no message (ApplySpellToTargets;
  DealDamage classifies kind 9 as fire, ovl24:1389). One of the per-spell handlers in SpellHandlers
  (SpellHandlers[9], filled by ovl22_e10). }
procedure CastBurningHands;
const
  { The kind of damage Burning Hands deals: DealDamage names kind 9 'from Fire' (its test is
    DamageKind and $F7 = 1, ovl24:1389). }
  DamageKindFire = 9;
begin
  ApplySpellToTargets(ds681B, 0, 0, res12_fn_26C2(ds681B), DamageKindFire, '');
end;
{ ovl22:11DD (e19). Cast handler of spell 10, Charm Person: it first refuses a target that is not a
  person, i.e. one whose CreatureType is above 1 or whose combat footprint kind (CombatSize, bits 0..6)
  is above 1, showing 'is unaffected' (res12_fn_16EC). Otherwise it applies the current spell ds681B
  to the targets with the charm affect's data (the caster level res12_fn_26C2(ds681B) plus the
  caster's Side in bit 7, so the charmed creature joins that side) and runs the affect through
  CallAffectHandler ($0B, the charm affect id). One of the per-spell handlers in SpellHandlers
  (SpellHandlers[10], filled by ovl22_e10). Reads ds6C95 (the first chosen target), SelectedCharacter;
  changes the affect list of the target through CallAffectHandler. }
procedure CastCharmPerson;
const
  CharmAffect = $0B;              { the charm affect CallAffectHandler runs and res12_fn_2199 finds }
  CharmableType = 1;              { the largest CreatureType Charm Person can affect (a person) }
  CharmableSize = 1;              { the largest CombatSize (combat footprint kind) it can affect }
  { The caster's side goes into bit 7 of the affect's data (Side * SideScale). }
  SideScale = 128;
  { Charm Person's side effect: the affect handler runs when the affect is removed (Flag 1). }
  RunHandlerOnRemoval = 1;
  ModeApply = 0;                  { CallAffectHandler's mode: apply (not remove) the affect }
  MessageColour = $A;             { the colour res12_fn_16EC shows the message in }
  TimedMessage = 1;               { nonzero: res12_fn_16EC delays by the game speed and clears it }
var
  Affect: Pointer;                { the charm affect res12_fn_2199 finds on the target }
  Target: PCharacter;             { the first chosen target ds6C95, tested and charmed }
begin
  Target := ds6C95;
  if (Target^.CreatureType > CharmableType) or (Target^.CombatSize > CharmableSize) then
    res12_fn_16EC(Target, 'is unaffected', MessageColour, TimedMessage)
  else
  begin
    ApplySpellToTargets(ds681B,
      res12_fn_26C2(ds681B) + ShortInt(SelectedCharacter^.Side) * SideScale, RunHandlerOnRemoval, 0, 0,
      'is charmed');
    if res12_fn_2199(Target, CharmAffect, Affect) then
      CallAffectHandler(CharmAffect, ds6C95, PAffect(Affect), ModeApply);
  end;
end;
{ ovl22:12A5 (e20). Cast handler of spell 12, Enlarge: gives the first chosen target ds6C95 the
  strength 18 (ExceptionalStrength) with the percentile for the caster level (res12_fn_26C2(ds681B):
  0 at level 1 up to 100 at level 6), through RaiseStrength, and shows 'is stronger' when the
  strength actually rose; it then adds the strength affect (id $0C, ovl24's AffectStrength1) with
  the spell's duration, RaiseStrength's earlier-strength code and flag 1 (on removal it restores the
  old strength, ovl24:AddAffect). The level and percentile go through the shared working globals
  ds4844/ds4845. One of the per-spell handlers in SpellHandlers (SpellHandlers[12], filled by
  ovl22_e10). }
procedure CastEnlarge;
const
  ExceptionalStrength = 18;       { strength 18, whose RaiseStrength takes a percentile (ovl24) }
  StrengthAffect = $0C;           { the strength affect id AddAffect keeps the earlier strength in }
  { The exceptional-strength percentile Enlarge grants by caster level 1..6. }
  PercentLevel1 = 0;
  PercentLevel2 = 1;
  PercentLevel3 = $33;
  PercentLevel4 = $4C;
  PercentLevel5 = $5B;
  PercentLevel6 = $64;
  MessageColour = $A;             { the colour res12_fn_16EC shows the message in }
  TimedMessage = 1;               { nonzero: res12_fn_16EC delays by the game speed and clears it }
var
  Code: Byte;                     { RaiseStrength's earlier-strength code, passed to AddAffect as Data }
begin
  ds4844 := ExceptionalStrength;
  case res12_fn_26C2(ds681B) of
    1: ds4845 := PercentLevel1;
    2: ds4845 := PercentLevel2;
    3: ds4845 := PercentLevel3;
    4: ds4845 := PercentLevel4;
    5: ds4845 := PercentLevel5;
    6: ds4845 := PercentLevel6;
  end;
  if RaiseStrength(ds6C95, ds4844, ds4845, Code) then
    res12_fn_16EC(ds6C95, 'is stronger', MessageColour, TimedMessage);
  AddAffect(ds6C95, StrengthAffect, SpellAffectDuration(ds681B), Code, 1);
end;
{ ovl22:136E (e21). Cast handler of spell 13, Reduce (SpellHandlers[13]; ovl22_e10 fills the table,
  whitepaper 5.22.2): when targets were chosen, a target that fails its saving throw (SavingThrow kind 4,
  a spell) loses the strength affect $0C that Enlarge adds (CureAffect) and is told 'has been reduced'.
  A target that saves, or that carries no strength affect, is left alone. Reads ds6C94 and ds6C95. }
procedure CastReduce;
const
  SaveKind = 4;                   { SavingThrow's kind for a spell (whitepaper 5.22.2) }
  StrengthAffect = $0C;           { the strength affect Enlarge adds; Reduce cancels it (ovl22:12A5) }
  MessageColour = $A;             { the colour res12_fn_16EC shows the message in }
  TimedMessage = 1;               { nonzero: res12_fn_16EC delays by the game speed and clears it }
begin
  if ds6C94 > 0 then
    if not SavingThrow(ds6C95, SaveKind, 0) then
      if CureAffect(ds6C95, StrengthAffect) then
        res12_fn_16EC(ds6C95, 'has been reduced', MessageColour, TimedMessage);
end;
{ ovl22:13D8 (e22). Cast handler of spell 14, Friends (SpellHandlers[14]; ovl22_e10 fills the table,
  whitepaper 5.22.2): raises the chosen target ds6C95's Charisma by 2d4, capped at 25 ($19), and calls
  ApplySpellToTargets with the pre-roll Charisma as the affect's Data and the restore flag set, so the
  affect's handler puts the old Charisma back when the affect ends; the message is 'is friendly'.
  Reads ds6C95 and ds681B. }
procedure CastFriends;
const
  DiceCount = 2;                  { 2d4 Charisma points (the AD&D Friends spell) }
  DiceSides = 4;
  CharismaCap = $19;              { Charisma's maximum, 25 }
  RestoreOnRemoval = 1;           { Flag: the affect handler runs when the affect is removed }
  MessageColour = $A;
  TimedMessage = 1;
var
  OldCharisma: Byte;              { the target's Charisma before the roll, the affect's Data }
begin
  OldCharisma := ds6C95^.Charisma;
  Inc(ds6C95^.Charisma, RollDice(DiceCount, DiceSides));
  if ds6C95^.Charisma > CharismaCap then
    ds6C95^.Charisma := CharismaCap;
  ApplySpellToTargets(ds681B, OldCharisma, RestoreOnRemoval, 0, 0, 'is friendly');
end;
{ ovl22:1439 (e23). Cast handler of spell 15, Magic Missile (SpellHandlers[15]; ovl22_e10 fills the
  table, whitepaper 5.22.2): the caster level from res12_fn_26C2 gives one missile per two levels, so
  it deals RollDiceCounted(Level div 2, 4) (a d4 per missile, its count kept in ds681C) plus Level div 2
  (one point per missile) to the chosen targets, with no message. Reads ds681B. }
procedure CastMagicMissile;
const
  LevelsPerMissile = 2;           { one magic missile per two caster levels }
  MissileSides = 4;               { each missile does 1d4, plus 1 per missile }
  DamageKind = 8;                 { DealDamage's kind for the missiles (as Cause Light Wounds, ovl22:10A7) }
var
  Level: Byte;                    { the caster level, res12_fn_26C2(ds681B) }
begin
  Level := res12_fn_26C2(ds681B);
  ApplySpellToTargets(ds681B, 0, 0,
    RollDiceCounted(Level div LevelsPerMissile, MissileSides) + Level div LevelsPerMissile,
    DamageKind, '');
end;
{ ovl22:1499 (e24). Cast handler of spell 19, Shield (SpellHandlers[19]; ovl22_e10 fills the table,
  whitepaper 5.22.2): applies the current spell ds681B (its own affect does the work) to the chosen
  targets with the message 'is shielded', no damage or flag of its own. Reads ds681B. }
procedure CastShield;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'is shielded');
end;
{ ovl22:14C7 (e25). Cast handler of spell 20, Shocking Grasp (SpellHandlers[20]; ovl22_e10 fills the
  table, whitepaper 5.22.2): deals the caster level from res12_fn_26C2 plus 1d8 (RollDiceCounted, count
  kept in ds681C) of electrical damage to the chosen targets, with no message. Reads ds681B. }
procedure CastShockingGrasp;
const
  DiceSides = 8;                  { 1d8 plus one point per caster level (the AD&D Shocking Grasp) }
  DamageKindElectric = $0C;       { DealDamage: kind and $F7 = 4 names electricity (ovl24:1389) }
begin
  { QUIRK ovl22:14D7: TP 6.0 evaluates the right operand of `+` first when both are calls, so the
    original's res12_fn_26C2-before-RollDiceCounted order needs the sum written with the level on the
    right; the add is commutative and the bytes match only this way. }
  ApplySpellToTargets(ds681B, 0, 0,
    RollDiceCounted(1, DiceSides) + res12_fn_26C2(ds681B), DamageKindElectric, '');
end;
{ ovl22:151B (e26). Cast handler of spell 21, Sleep (SpellHandlers[21]; ovl22_e10 fills the table,
  whitepaper 5.22.2): sets ds6820 and rolls the 4d4 pool ds4844. For every chosen target ds6C91[I] it
  charges a cost in ds4845 by the target's HighestLevel (+$73, a monster's hit dice) and level 5's Race
  (+$2E). A target is slept (the cost comes off the pool) only when it is not dead (Status <> 1), does
  not already carry the sleep affect $35 (res12_fn_2199) and the pool still covers its cost; otherwise
  it is dropped (ds6C91[I] := nil). ApplySpellToTargets then applies the spell's own affect to the
  survivors with 'falls asleep'. Reads ds6C94, ds681B; changes ds6820, ds4844, ds4845 and the target list. }
procedure CastSleep;
const
  SleepAffect = $35;              { the affect that marks a target already asleep }
  PoolDiceCount = 4;              { the 4d4 pool of hit dice Sleep can affect }
  PoolDiceSides = 4;
  DeadStatus = 1;                 { TCharacter.Status 1 counts as dead (whitepaper 4.2.5) }
  { The pool cost of one target, by its HighestLevel (a monster's hit dice), the AD&D Sleep table. }
  CostLevel0 = 1;
  CostLevel2 = 2;
  CostLevel3 = 4;
  CostLevel4 = 6;
  CostLevel5Small = $A;           { a level-5 creature of Race 0 (a smaller kind) costs 10 }
  CostLevel5Large = $14;          { any other level-5 or higher creature costs 20 }
var
  I: Byte;                        { the target index, 1..ds6C94 }
  Affect: Pointer;                { res12_fn_2199's out pointer, the target's sleep affect }
begin
  ds6820 := 1;
  ds4844 := RollDice(PoolDiceCount, PoolDiceSides);
  for I := 1 to ds6C94 do
  begin
    case ds6C91[I]^.HighestLevel of
      0..1: ds4845 := CostLevel0;
      2: ds4845 := CostLevel2;
      3: ds4845 := CostLevel3;
      4: ds4845 := CostLevel4;
      5:
        if ds6C91[I]^.Race = 0 then
          ds4845 := CostLevel5Small
        else
          ds4845 := CostLevel5Large;
    else
      ds4845 := CostLevel5Large;
    end;
    { QUIRK ovl22:15FE: the guard is written positive on purpose; the equivalent negative
      `(Status = 1) or res12_fn_2199(...) or (pool < cost)` then-drop-else-Dec form compiles with the
      two branches laid out the other way round (probe PRB26.PAS) and does not match. }
    if (ds6C91[I]^.Status <> DeadStatus) and not res12_fn_2199(ds6C91[I], SleepAffect, Affect) and
       (ds4844 >= ds4845) then
      Dec(ds4844, ds4845)
    else
      ds6C91[I] := nil;
  end;
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'falls asleep');
end;
{ ovl22:1658. Cast handler of spell 23, Hold Person (entry 27: ovl22_e10 maps DS:6B84+23*4 to overlay
  stub 0096:00A7; SpellNames[23] is 'Hold Person' at DS:2C98): for every chosen target ds6C91[I]
  it rolls a saving throw whose bonus shrinks as more targets were picked (one target -3, or -2 when
  the spell is Hold Person itself, two targets -1, three or four none), drawing a beam from the caster
  to every target but the first (SetSoundDriverIdle, PlaySound(ds2618), the cast animation
  res12_fn_19DE($12) and the res12_fn_1A29 line), and applies the spell's own affect with the message
  'is held' through ApplyAffect. A target that is not a person (CreatureType above 1 or CombatSize
  above 1, as CastCharmPerson tests) is treated as having saved, and a nil target is skipped. Reads
  ds6C94, ds6C91, ds681B and SelectedCharacter. }
procedure CastHoldPerson;
const
  HoldPerson = $17;               { the spell whose lone target saves at -2 instead of -3 (spell 23) }
  { The saving-throw bonus by number of chosen targets (a negative bonus makes the save harder):
    fewer targets mean the spell is concentrated, so the single-target save is the hardest. }
  OneTargetBonus = -3;
  HoldPersonBonus = -2;
  TwoTargetsBonus = -1;
  ThreeOrFourBonus = 0;
  FriendlyType = 1;               { the largest CreatureType Hold Person can affect (a person) }
  FriendlySize = 1;               { the largest CombatSize (combat footprint kind) it can affect }
  AnimationKind = $12;            { res12_fn_19DE's argument that starts the cast animation }
  AimStep = 4;                    { the line res12_fn_1A29 walks for the cast animation }
  AimWidth = $1E;
var
  Target: PCharacter;             { ds6C91[I], the target this pass applies the spell to }
  Saved: Boolean;                 { whether the target saved (or is not a person) }
  I: Byte;                        { the target index, ds6C94 downto 1 }
  SaveBonus: ShortInt;            { the saving-throw bonus for this many targets }
begin
  case ds6C94 of
    1:
      if ds681B = HoldPerson then
        SaveBonus := HoldPersonBonus
      else
        SaveBonus := OneTargetBonus;
    2: SaveBonus := TwoTargetsBonus;
    3, 4: SaveBonus := ThreeOrFourBonus;
  end;
  for I := ds6C94 downto 1 do
    if ds6C91[I] <> nil then
    begin
      Target := ds6C91[I];
      if I < ds6C94 then
      begin
        SetSoundDriverIdle(0);
        PlaySound(ds2618);
        res12_fn_19DE(AnimationKind);
        res12_fn_1A29(CombatantX(SelectedCharacter), CombatantY(SelectedCharacter),
          CombatantX(Target), CombatantY(Target), AimStep, AimWidth);
        SetSoundDriverIdle($A);
      end;
      Saved := SavingThrow(Target, SpellTable[ds681B].Pad2[9], SaveBonus);
      if (Target^.CreatureType > FriendlyType) or (Target^.CombatSize > FriendlySize) then
        Saved := True;
      ApplyAffect(Target, SpellTable[ds681B].AffectId, SpellAffectDuration(ds681B),
        res12_fn_26C2(ds681B), 0, SpellTable[ds681B].Pad2[8], Saved, 'is held');
    end;
end;
{ ovl22:17E9. Cast handler of spell 24, Resist Fire (entry 28: ovl22_e10 maps DS:6B84+24*4 to overlay
  stub 0096:00AC; SpellNames[24] is 'Resist Fire' at DS:2CC1): applies the current spell ds681B to the
  chosen targets with the message 'is fire resistant' and no damage or flag of its own
  (ApplySpellToTargets; the spell's own affect does the work). One of the per-spell handlers in
  SpellHandlers (whitepaper 5.22.2). }
procedure CastResistFire;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'is fire resistant');
end;
{ ovl22:1822. Cast handler of spell 25, Silence, 15' Radius (entry 29: ovl22_e10 maps DS:6B84+25*4 to
  overlay stub 0096:00B1; SpellNames[25] is "Silence, 15' Radius" at DS:2CEA): applies the current spell
  ds681B to the chosen targets with the message 'is silenced' and no damage or flag of its own
  (ApplySpellToTargets; the spell's own affect does the work). One of the per-spell handlers in
  SpellHandlers (whitepaper 5.22.2). }
procedure CastSilence;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'is silenced');
end;
{ ovl22:185B. Cast handler of spell 26, Slow Poison (entry 30: ovl22_e10 maps DS:6B84+26*4 to overlay
  stub 0096:00B6; SpellNames[26] is 'Slow Poison' at DS:2D13). It needs the first chosen target ds6C95
  to still be alive (Status is not 1) and to carry the Poisoned affect $37 (res12_fn_2199); anything
  else is dropped (ds6C95 := nil) and the cast does nothing. A poisoned target at 0 hit points is
  brought back to 1 (Flag11B), the spell's own affect is applied to the targets ('is affected'), the
  revival affect's removal handler is run (CallAffectHandler($4E), which heals an unconscious
  character, ovl24 AffectRevival) and the poison-slowing affect $0F is added for $A units. Reads
  ds6C95 and ds681B. }
procedure CastSlowPoison;
const
  DeadStatus = 1;                 { TCharacter.Status 1 counts as dead (whitepaper 4.2.5) }
  PoisonedAffect = $37;           { the Poisoned affect the target must carry (ovl15 names $37 Poisoned) }
  { The revival affect whose removal handler heals an unconscious character (ovl24 AffectRevival). }
  RevivalAffect = $4E;
  ReviveHitPoints = 1;            { a poisoned character at 0 hit points is brought back to 1 }
  SlowPoisonAffect = $0F;         { the poison-slowing affect; Neutralize Poison removes it with the poison (ovl04) }
  SlowPoisonDuration = $A;        { the affect lasts ten units }
  SlowPoisonData = $FF;           { the affect's data byte }
  RunHandlerOnRemoval = 1;        { Flag: the affect's handler runs when the affect is removed }
  FullCasterLevel = $FF;          { ApplySpellToTargets uses this caster level instead of res12_fn_26C2 }
  ModeRemove = 1;                 { CallAffectHandler's mode: run the handler as if removing the affect }
var
  Affect: Pointer;                { res12_fn_2199's out pointer, the target's Poisoned affect }
  Target: PCharacter;             { ds6C95, the first chosen target }
begin
  Target := ds6C95;
  if Target^.Status = DeadStatus then
  begin
    ds6C95 := nil;
    Exit;
  end;
  if res12_fn_2199(Target, PoisonedAffect, Affect) then
  begin
    if Target^.Flag11B = 0 then
      Target^.Flag11B := ReviveHitPoints;
    ApplySpellToTargets(ds681B, FullCasterLevel, RunHandlerOnRemoval, 0, 0, 'is affected');
    CallAffectHandler(RevivalAffect, Target, nil, ModeRemove);
    AddAffect(Target, SlowPoisonAffect, SlowPoisonDuration, SlowPoisonData, RunHandlerOnRemoval);
  end;
end;
{ ovl22:190F. Cast handler of spell 27, Snake Charm (entry 31: ovl22_e10 maps DS:6B84+27*4 to overlay
  stub 0096:00BB; SpellNames[27] is 'Snake Charm' at DS:2D3C). The caster's own current hit points
  (SelectedCharacter^.Flag11B) become the pool ds4844; it then walks the party list ds5D96 and, for
  every giant snake (CreatureType $E) whose hit points fit the remaining pool, subtracts them, counts
  it in ds6C94 and adds it to the chosen targets ds6C91. The spell's own affect is then applied to the
  charmed snakes with the message 'is charmed'. Reads SelectedCharacter, ds5D96 and ds681B; changes
  ds4844, ds6C94 and the target list. }
procedure CastSnakeCharm;
const
  SnakeType = $E;                 { the CreatureType of a giant snake (MON*CHA, as ovl12 tests) }
var
  Current: PCharacter;            { the walker of the party list ds5D96 }
begin
  ds4844 := SelectedCharacter^.Flag11B;
  ds6C94 := 0;
  Current := PCharacter(ds5D96);
  while Current <> nil do
  begin
    if (Current^.CreatureType = SnakeType) and (ds4844 >= Current^.Flag11B) then
    begin
      ds4844 := ds4844 - Current^.Flag11B;
      Inc(ds6C94);
      ds6C91[ds6C94] := Current;
    end;
    Current := Current^.Next;
  end;
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'is charmed');
end;
{ ovl22:19C3 (e32). Cast handler of spell 28, Spiritual Hammer (SpellHandlers[28]: ovl22_e10 maps
  DS:6B84+28*4 to overlay stub 0096:00C0; SpellNames[28] is 'Spiritual Hammer' at DS:2D65, the
  spell's own affect is $17). It applies the current spell ds681B to the chosen targets with no
  message of its own and the affect set to run its handler on removal (ApplySpellToTargets, Flag 1),
  then runs the handler of affect $17 on the first chosen target ds6C95 (CallAffectHandler, mode 0),
  which is the spell's hammer. Reads ds681B and ds6C95. }
procedure CastSpiritualHammer;
const
  SpiritualHammerAffect = $17;    { the spell's own affect (SpellTable[28].AffectId): its handler is run here }
  RunHandlerOnRemoval = 1;        { ApplySpellToTargets' Flag: the affect's handler runs when it is removed }
  ModeApply = 0;                  { CallAffectHandler's mode: apply (not remove) the affect }
begin
  ApplySpellToTargets(ds681B, 0, RunHandlerOnRemoval, 0, 0, '');
  CallAffectHandler(SpiritualHammerAffect, ds6C95, nil, ModeApply);
end;
{ ovl22:1A16 (e33). Cast handler of spell 30, Invisibility (SpellHandlers[30]: ovl22_e10 maps
  DS:6B84+30*4 to overlay stub 0096:00C5; SpellNames[30] is 'Invisibility' at DS:2DB7; its
  SpellTable affect byte is 0). It only applies the current spell ds681B to the chosen targets with
  the message 'is invisible'; the spell's own affect does the hiding, so the handler has nothing else
  to do. Reads ds681B. }
procedure CastInvisibility;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'is invisible');
end;
{ ovl22:1A4F (e34). Cast handler of spell 31, Knock (SpellHandlers[31]: ovl22_e10 maps
  DS:6B84+31*4 to overlay stub 0096:00CA; SpellNames[31] is 'Knock' at DS:2DE0). It only applies
  the current spell ds681B to the chosen targets with the message 'Knock-Knock'; the spell's own
  affect $1C opens the lock, so the handler has nothing else to do. Reads ds681B. }
procedure CastKnock;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'Knock-Knock');
end;
{ ovl22:1A8A (e35). Cast handler of spell 32, Mirror Image (SpellHandlers[32]: ovl22_e10 maps
  DS:6B84+32*4 to overlay stub 0096:00CF; SpellNames[32] is 'Mirror Image' at DS:2E09). It applies
  the current spell ds681B to the chosen targets with the message 'is duplicated' and the caster
  level set to 1d4 (RollDice(1, 4)); that roll is the number of images and becomes the affect's
  Data. Reads ds681B. }
procedure CastMirrorImage;
const
  ImagesCount = 1;                { the images are 1d4 (RollDice(Count, Sides)) }
  ImagesSides = 4;
begin
  ApplySpellToTargets(ds681B, RollDice(ImagesCount, ImagesSides), 0, 0, 0, 'is duplicated');
end;
{ ovl22:1ACC (e36). Cast handler of spell 33, Ray of Enfeeblement (SpellHandlers[33]: ovl22_e10 maps
  DS:6B84+33*4 to overlay stub 0096:00D4; SpellNames[33] is 'Ray of Enfeeblement' at DS:2E32). It
  only applies the current spell ds681B to the chosen targets with the message 'is weakened'; the
  spell's own affect lowers the target's strength, so the handler has nothing else to do. Reads
  ds681B. }
procedure CastRayOfEnfeeblement;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'is weakened');
end;
{ ovl22:1B11 (e37). Cast handler of spell 34, Stinking Cloud (SpellHandlers[34]: ovl22_e10 maps
  DS:6B84+34*4 to overlay stub 0096:00D9; SpellNames[34] is 'Stinking Cloud' at DS:2E5B). It leaves
  a marker in the list ds6DBB (a list of $13-byte TCombatNode records) for the aim point ds6DB9/
  ds6DBA: the caster, the aim cell, and for each of the four aim directions (SpellNamesPrefix.AimDirs,
  DS:290E) the tile it found around the aim cell, whether the cell may hold the cloud, and the cloud's
  own affect $28 with the caster level. A cell whose tile is $1E (the cloud tile) borrows the tile of
  an earlier cloud marker that already reaches it; a cell whose tile is $1F borrows the tile of a body
  there (BodyTable). The cloud cell itself is painted into the combat map, the cast is announced
  ('Creates a noxious cloud'), the cursor is moved to the aim point and the cloud affect runs on every
  combatant in the four cells (ApplyCloudTile). Reads ds681B, ds6DB9/ds6DBA, ds5D96 (SelectedCharacter's
  side), BodyCount, CombatTiles, CombatMap and CombatantRecord; changes ds6820, ds6DBB, the combat map
  and the affects of the targets. }
procedure CastStinkingCloud;
const
  CloudTile = $1E;                { a noxious cloud cell (ApplyCloudTile tests the tile under a combatant for it) }
  CloudEdgeTile = $1F;            { the second cloud tile the aim scan looks for; meaning open }
  CloudAffect = $28;              { the affect the cast leaves on the caster and his clouds }
  { The cloud count goes into the affect's data in bits 4..7 (Count * CloudCountScale). }
  CloudCountScale = 16;
  RefusedTileCost = $FF;          { a combat tile cost this high refuses the cell (TCombatTile.Cost) }
  AimCursorMargin = $FF;          { the margin MoveCombatCursor centres the view with }
  AimCursorDir = 8;               { the omni direction MoveCombatCursor steps in (DirStepX/DirStepY) }
  MessageColour = $A;             { the colour res12_fn_16EC shows the message in }
var
  Cloud: PCombatNode;             { the walker of the ds6DBB cloud list }
  Node: PCombatNode;              { the cloud marker this cast fills }
  Occupant: array[1..4] of Byte;  { the combatant standing in each aim cell (GetMapCell's out) }
  J: Byte;                        { the aim direction or the body index being looked at }
  Count: Byte;                    { how many cloud markers the caster already had }
  Tile: Byte;                     { the tile GetMapCell found, or one the scan borrows }
  Level: Byte;                    { the caster level, res12_fn_26C2(ds681B) }
  I: Byte;                        { the aim direction index, 1..4 }
  Dir: Byte;                      { the compass direction of aim direction I (SpellNamesPrefix.AimDirs) }
begin
  ds6820 := 1;
  Level := res12_fn_26C2(ds681B);
  Count := 0;
  Node := ds6DBB;
  if ds6DBB = nil then
  begin
    GetMem(ds6DBB, SizeOf(TCombatNode));
    Node := ds6DBB;
  end
  else
  begin
    while Node^.Next <> nil do
    begin
      if Node^.Who = SelectedCharacter then
        Inc(Count);
      Node := Node^.Next;
    end;
    GetMem(Node^.Next, SizeOf(TCombatNode));
    Node := Node^.Next;
  end;
  FillChar(Node^, SizeOf(TCombatNode), 0);
  AddAffect(SelectedCharacter, CloudAffect, Level, Level + Count * CloudCountScale, 1);
  Node^.Who := SelectedCharacter;
  Node^.Clouds := Count;
  Node^.X := ds6DB9;
  Node^.Y := ds6DBA;
  for I := 1 to 4 do
  begin
    Dir := SpellNamesPrefix.AimDirs[I];
    GetMapCell(ds6DB9 + DirStepX[Dir], ds6DBA + DirStepY[Dir], Occupant[I], Tile);
    if (Tile > 0) and (CombatTiles[Tile].Cost < RefusedTileCost) then
      Node^.Flags[I] := 1
    else
      Node^.Flags[I] := 0;
    if Tile = CloudTile then
    begin
      Cloud := ds6DBB;
      while Cloud <> nil do
      begin
        if Cloud <> Node then
          for J := 1 to 4 do
            if Cloud^.Flags[J] <> 0 then
              if (Cloud^.X + DirStepX[SpellNamesPrefix.AimDirs[J]] = ds6DB9 + DirStepX[Dir]) and
                 (Cloud^.Y + DirStepY[SpellNamesPrefix.AimDirs[J]] = ds6DBA + DirStepY[Dir]) and
                 (Cloud^.Tiles[J] <> CloudTile) then
                Tile := Cloud^.Tiles[J];
        Cloud := Cloud^.Next;
      end;
    end
    else if Tile = CloudEdgeTile then
      for J := 1 to BodyCount do
        if (BodyTable[J].X = ds6DB9 + DirStepX[Dir]) and
           (BodyTable[J].Y = ds6DBA + DirStepY[Dir]) then
          Tile := BodyTable[J].Tile;
    Node^.Tiles[I] := Tile;
    if Node^.Flags[I] <> 0 then
      CombatMap^.Cells[ds6DBA + DirStepY[Dir], ds6DB9 + DirStepX[Dir]] := CloudTile;
  end;
  res12_fn_16EC(SelectedCharacter, 'Creates a noxious cloud', MessageColour, 0);
  MoveCombatCursor(ds6DB9, ds6DBA, AimCursorMargin, AimCursorDir);
  DelayByGameSpeed;
  res12_fn_17E3;
  for I := 1 to 4 do
    if Occupant[I] > 0 then
      ApplyCloudTile(CombatantRecord[Occupant[I]]);
end;
{ ovl22:1F41. Cast handler that raises the chosen target ds6C95's Strength (the Strength spell):
  it rolls the class bonus die (1d4 for a magic-user level, 1d6 for a cleric or thief level, 1d8
  for a fighter level; the later class wins) and adds it to the target's Strength. A result above
  18 is clamped to 18; for a fighter level the overflow becomes the exceptional-strength percentile
  (10 per point above 18 plus the target's StrengthPercent, capped at 100). RaiseStrength applies the
  new Strength (showing 'is stronger' when it rose) and the strength affect $26 is added for the
  spell's duration. Reads ds6C95 and ds681B. }
procedure CastStrength;
const
  ExceptionalStrength = 18;       { 18, the largest plain Strength; the overflow becomes the percentile }
  MaxPercent = 100;               { the exceptional-strength percentile ceiling }
  PercentStep = 10;               { each point of Strength above 18 is 10 percent }
  StrengthAffect = $26;           { the strength affect this spell leaves (same vehicle RaiseStrength updates) }
  { The class whose level picks the bonus die: magic-user (d4), cleric or thief (d6), fighter (d8). }
  MagicUserClass = 5;
  ClericClass = 0;
  ThiefClass = 6;
  FighterClass = 2;
  { The bonus die by class. }
  MagicUserSides = 4;
  ClericSides = 6;
  FighterSides = 8;
  MessageColour = $A;             { the colour res12_fn_16EC shows 'is stronger' in }
  TimedMessage = 1;               { nonzero: res12_fn_16EC delays by the game speed and clears it }
  RunHandlerOnRemoval = 1;        { AddAffect Flag: the affect's handler runs when the affect is removed }
var
  Target: PCharacter;             { ds6C95, the chosen target whose Strength is raised }
  Percent: Byte;                  { the exceptional-strength percentile passed to RaiseStrength }
  Bonus: Byte;                    { the class bonus die roll (unset when the target has no class: QUIRK ovl22:1F47) }
  Strength: Byte;                 { the new Strength, the sum of the target's Strength and the roll }
  Code: Byte;                     { RaiseStrength's earlier-strength code, passed to AddAffect as Data }
begin
  Percent := 0;
  Target := ds6C95;
  if Target^.ClassLevels[MagicUserClass] > 0 then
    Bonus := RollDice(1, MagicUserSides);
  if (Target^.ClassLevels[ClericClass] > 0) or (Target^.ClassLevels[ThiefClass] > 0) then
    Bonus := RollDice(1, ClericSides);
  if Target^.ClassLevels[FighterClass] > 0 then
    Bonus := RollDice(1, FighterSides);
  Strength := Target^.Strength + Bonus;
  { QUIRK ovl22:1FFB: the cap is repeated in both branches (Strength 18 in each); the compiler keeps
    one store per branch instead of hoisting it, which is the original's layout. }
  if Strength > ExceptionalStrength then
  begin
    if Target^.ClassLevels[FighterClass] > 0 then
    begin
      { QUIRK ovl22:1FD4: TP 6.0 evaluates the right operand of `+` first, so the percentile sum is
        written target-first to keep the product on the left of the add in the original. }
      Percent := Target^.StrengthPercent + (Strength - ExceptionalStrength) * PercentStep;
      if Percent > MaxPercent then
        Percent := MaxPercent;
      Strength := ExceptionalStrength;
    end
    else
      Strength := ExceptionalStrength;
  end;
  if RaiseStrength(Target, Strength, Percent, Code) then
    res12_fn_16EC(Target, 'is stronger', MessageColour, TimedMessage);
  AddAffect(Target, StrengthAffect, SpellAffectDuration(ds681B), Code, RunHandlerOnRemoval);
end;
{ ovl22:206F. Cast handler of spell 36, Animate Dead: for up to the caster level corpses still in the
  party list ds5D96 (Status 6, CreatureType 0) it places the body on the combat map at its own cell
  (PlaceCombatant) and turns it into an undead creature under the caster's side: CreatureType 4, Quick
  set, the memorized spells, the AI state and the combat target cleared, B84 $B2 when it was already a
  computer-run member (above $7F) else $B3, and Side copied from SelectedCharacter. The corpse is then
  revived (ReviveCombatant at HpMax) and, on success, carries the animate affect $20 (Data: the caster's
  Side in bits 4..7 plus the caster level) with the message 'is animated'. Reads ds681B, ds5D96,
  SelectedCharacter and ds49F3; changes ds6820, ds6C94 and the corpse records. }
procedure CastAnimateDead;
const
  DeadStatus = 6;                 { TCharacter.Status 6: a corpse Animate Dead can raise }
  HumanType = 0;                  { CreatureType 0: the party's (human) corpses }
  UndeadType = 4;                 { CreatureType 4 marks the undead (whitepaper 5.22.2) }
  AnimateAffect = $20;            { the affect Animate Dead leaves on the animated corpse }
  MaxSpellSlot = $14;             { Spells is array[0..$14] }
  { B84 (whitepaper 4.2.5): above $7F marks a computer-run member, which keeps its higher morale. }
  AiThreshold = $7F;
  HirelingMorale = $B2;           { the animated member was computer-run }
  CreatureMorale = $B3;           { the animated member was player-run }
  { The caster's Side goes into bits 4..7 of the affect's data. Written as a multiply, not `shl 4`:
    TP 6.0 compiles `X * 16` to `mov cl,4; shl ax,cl` (b1 04) but `X shl 4` to `mov cx,4; shl ax,cl`
    (b9 04 00), and the original at ovl22:210B has the byte form (probe PRB27.PAS). }
  SideScale = 16;
  AnimatedMark = 2;               { the byte at +$76 Animate Dead sets (ScoreTarget reads it, ovl09:128D) }
  CombatViewMode = 5;             { ds49F3 during combat (whitepaper 5.5) }
  RunHandlerOnRemoval = 1;        { ApplyAffect Flag: the affect's handler runs when it is removed }
  NoSaveNegates = 0;              { ApplyAffect SaveNegates }
  NotSaved = False;               { ApplyAffect Saved }
  RestoreCell = 1;                { PlaceCombatant Restore }
var
  I: Byte;                        { the spell slot index, 0..$14 }
  SaveData: Byte;                 { the affect data: the caster's Side in bits 4..7 plus the level }
  Level: Byte;                    { the caster level, one corpse per level, counted down }
  Current: PCharacter;            { the walker of the party list ds5D96 }
begin
  ds6820 := 1;
  Level := res12_fn_26C2(ds681B);
  ds6C94 := 0;
  Current := PCharacter(ds5D96);
  while (Current <> nil) and (Level > 0) do
  begin
    if Current^.Status = DeadStatus then
      if Current^.CreatureType = HumanType then
        if PlaceCombatant(Current, CombatantX(Current), CombatantY(Current), RestoreCell) then
        begin
          { The caster's Side goes into bits 4..7 of the affect data, the caster level into the low
            nibble (QUIRK ovl22:2105: the original sign-extends Side with cwde, so it is treated as a
            ShortInt here even though TCharacter.Side is a Byte). }
          SaveData := ShortInt(Current^.Side) * SideScale + res12_fn_26C2(ds681B);
          Current^.Side := SelectedCharacter^.Side;
          Current^.Quick := 1;
          Current^.Pad74[$76] := AnimatedMark;
          Current^.Pad6B := 0;
          Current^.Pad72 := 6;
          for I := 0 to MaxSpellSlot do
            Current^.Spells[I] := 0;
          if Current^.B84 > AiThreshold then
            Current^.B84 := HirelingMorale
          else
            Current^.B84 := CreatureMorale;
          Current^.CreatureType := UndeadType;
          if ds49F3 = CombatViewMode then
            Current^.Combat^.Target := nil;
          Dec(Level);
          if ReviveCombatant(Current, Current^.HpMax) then
          begin
            ApplyAffect(Current, AnimateAffect, 0, SaveData, RunHandlerOnRemoval, NoSaveNegates,
              NotSaved, 'is animated');
            Current^.Status := 1;
          end;
        end;
    Current := Current^.Next;
  end;
end;
{ ovl22:2217. Cast handler of spell 37, Cure Blindness (SpellTable[37].AffectId is $21): removes the
  blindness affect $21 from the first chosen target ds6C95 (CureAffect) and, only when the target
  actually carried it, tells 'can see' through res12_fn_1FEB. Reads ds6C95. }
procedure CastCureBlindness;
const
  BlindnessAffect = $21;          { the blindness affect CureAffect removes; the affect of spell 37 }
  ShowAbout = 1;                  { res12_fn_1FEB's Flag argument }
begin
  if CureAffect(ds6C95, BlindnessAffect) then
    res12_fn_1FEB(ds6C95, ShowAbout, 'can see');
end;
{ ovl22:225D. Cast handler of spell 38, Cause Blindness (SpellHandlers[38]: ovl22_e10 maps
  DS:6B84+38*4 to overlay stub 0096:00ED; SpellNames[38] is 'Cause Blindness' at DS:2EFF). It only
  applies the current spell ds681B to the chosen targets with the message 'is blind'; the spell's own
  affect $21 does the blinding (the affect Cure Blindness removes, ovl22:2217), so the handler has
  nothing else to do. Reads ds681B. }
procedure CastCauseBlindness;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'is blind');
end;
{ ovl22:228A. Cures the six disease affects of the Temple (DiseaseAffects[1..6] at DS:0114: $1F,
  $22, $2B, $2C, $32, $39) from the chosen target ds6C95 and returns whether it cured any: it cures
  the $22 spell affect on its own, and curing $2B clears its companions $2C (Cause Disease) and $1F
  (Helpless) too, while curing $32 (Dreaded Mummy Disease) clears $39. ds681F is set while the
  affects go so the removal does not trigger the Temple's own cure. Called by CastCureDisease (spell 39,
  Cure Disease) and ovl22_e54. }
function CureDiseaseAffects: Boolean;
const
  DiseaseAffectHelpless = $1F;     { the Display names it Helpless (ovl15 AffectHelpless) }
  DiseaseAffectCured = $22;        { cured on its own; a spell affect (ovl15 names $20..$22 by their spell) }
  DiseaseAffectCause = $2B;        { cured with its two companions below }
  DiseaseAffectCauseDisease = $2C; { the Display names it Cause Disease (ovl15 AffectCauseDisease) }
  DiseaseAffectMummy = $32;        { the Display names it Dreaded Mummy Disease (ovl15 AffectMummyDisease) }
  DiseaseAffectMummyCleared = $39; { cleared with Dreaded Mummy Disease }
begin
  CureDiseaseAffects := False;
  ds681F := 1;
  if CureAffect(ds6C95, DiseaseAffectCured) then
    CureDiseaseAffects := True;
  if CureAffect(ds6C95, DiseaseAffectCause) then
  begin
    CureDiseaseAffects := True;
    RemoveAffect(ds6C95, DiseaseAffectCauseDisease, nil);
    RemoveAffect(ds6C95, DiseaseAffectHelpless, nil);
  end;
  if CureAffect(ds6C95, DiseaseAffectMummy) then
  begin
    CureDiseaseAffects := True;
    RemoveAffect(ds6C95, DiseaseAffectMummyCleared, nil);
  end;
  ds681F := 0;
end;
{ ovl22:232F. Cast handler of spell 39, Cure Disease (SpellHandlers[39]: ovl22_e10 maps
  DS:6B84+39*4 to overlay stub 0096:00F2; SpellNames[39] is 'Cure Disease' at DS:2F28). It calls
  CureDiseaseAffects to cure the chosen target ds6C95 and stores the result in a local it never
  reads, so the cure happens through that call alone (SpellHandlers is a table of procedures and
  takes no result). QUIRK ovl22:232F: the Boolean local Cured is written and never read. }
procedure CastCureDisease;
var
  Cured: Boolean;
begin
  Cured := CureDiseaseAffects;
end;
{ ovl22:234C. Cast handler of spell 40, Cause Disease (SpellHandlers[40]: ovl22_e10 maps
  DS:6B84+40*4 to overlay stub 0096:00F7; SpellNames[40] is 'Cause Disease' at DS:2F51). It applies
  the current spell ds681B to the chosen targets with the message 'is diseased' and no damage of its
  own, but with Flag 1 so the spell's affect runs its handler when it is removed (the affect the
  Temple's Cure Disease and CureDiseaseAffects clear). Reads ds681B. }
procedure CastCauseDisease;
const
  RunHandlerOnRemoval = 1;        { ApplySpellToTargets' Flag: the affect's handler runs when it is removed }
begin
  ApplySpellToTargets(ds681B, 0, RunHandlerOnRemoval, 0, 0, 'is diseased');
end;
{ ovl22:2385 (e44). Cast handler of spells 41 and 46, Dispel Magic (ovl22_e10 maps both
  DS:6B84+41*4 and DS:6B84+46*4 to overlay stub 0096:00FC; SpellNames[41] and SpellNames[46] are
  both 'Dispel Magic' at DS:2F7A and DS:3047). It tries to dispel the affects of the chosen target
  ds6C95: for every affect of the target's list whose Data byte is below $FF it takes the effect's
  level from the low nibble of Data, turns the caster level (res12_fn_26C2(ds681B)) and that level
  into a chance (50 percent, +5 for each level the caster is above the effect, -2 for each level
  below), and rolls 1d100: a roll up to that chance removes the affect (RemoveAffect) and, when
  anything was removed, the target is told 'is affected' (res12_fn_1FEB). ds6820 marks the cast.
  QUIRK ovl22:2385: the outer loop runs ds6C94 times but the body always reads the same first target
  ds6C95 (it is never indexed by the loop counter), so a cast with several targets rolls on the
  first one once per target and can show 'is affected' more than once. Reads ds681B, ds6C94, ds6C95;
  changes ds6820, ds4844, ds4845 and the target's affect list. }
procedure CastDispelMagic;
const
  MaxAffectData = $FF;            { an affect whose Data byte is this high is left alone }
  LevelMask = $0F;                { the effect's level is the low nibble of the affect's Data byte }
  BaseChance = $32;               { 50 percent, the base Dispel Magic chance }
  LevelStep = 5;                  { +5 percent for each caster level above the effect's level }
  LevelPenalty = 2;               { -2 percent for each caster level below it }
  DiceSides = 100;                { the chance is rolled on 1d100 }
  ShowAbout = 1;                  { res12_fn_1FEB's Flag argument }
var
  I: Byte;                        { the outer loop counter, 1..ds6C94 }
  Level: Byte;                    { the caster level, res12_fn_26C2(ds681B) }
  Target: PCharacter;             { the chosen target ds6C95 whose affects are dispelled }
  Dispelled: Boolean;             { whether this pass removed any affect }
  Affect: PAffect;                { the walker of Target's affect list }
  Next: PAffect;                  { the affect's successor, kept before a removal }
begin
  ds6820 := 1;
  Level := res12_fn_26C2(ds681B);
  for I := 1 to ds6C94 do
  begin
    Dispelled := False;
    Target := ds6C95;
    Affect := PAffect(Target^.Affects);
    while Affect <> nil do
    begin
      Next := Affect^.Next;
      if Affect^.Data < MaxAffectData then
      begin
        ds4845 := Affect^.Data and LevelMask;
        if Level > ds4845 then
          ds4844 := (Level - ds4845) * LevelStep + BaseChance
        else if Level < ds4845 then
          ds4844 := BaseChance - (ds4845 - Level) * LevelPenalty
        else
          ds4844 := BaseChance;
        if RollDice(1, DiceSides) <= ds4844 then
        begin
          RemoveAffect(Target, Affect^.Id, Affect);
          Dispelled := True;
        end;
      end;
      Affect := Next;
    end;
    if Dispelled then
      res12_fn_1FEB(Target, ShowAbout, 'is affected');
  end;
end;
{ ovl22:24D6 (e45). Cast handler of spell 42, Prayer (ovl22_e10 maps DS:6B84+42*4 to overlay stub
  0096:00... ; SpellNames[42] is 'Prayer'). It applies the current spell ds681B to the chosen targets
  with no flag, damage or kind of its own and the message 'is praying'; the caster level it passes as
  the affect's Data is the caster level (res12_fn_26C2(ds681B)) plus the caster's Side scaled by 16, so
  the affect's handler can tell whose side the prayer favours (the same Side-in-the-data trick as
  Charm Person and Animate Dead). Reads ds681B and SelectedCharacter; changes the targets' affects. }
procedure CastPrayer;
const
  { The caster's Side goes above the caster level in the affect's data (Side * SideScale). Written as
    a multiply, not `shl 4`: TP 6.0 compiles `X * 16` to `mov cl,4; shl ax,cl` but `X shl 4` to
    `mov cx,4; shl ax,cl` (probe PRB27.PAS). }
  SideScale = 16;
begin
  { QUIRK ovl22:24F1: the original sign-extends Side with cwde, so it is read as a ShortInt even
    though TCharacter.Side is a Byte. }
  ApplySpellToTargets(ds681B, res12_fn_26C2(ds681B) + ShortInt(SelectedCharacter^.Side) * SideScale,
    0, 0, 0, 'is praying');
end;
{ ovl22:2540 (e9). Cast handler of spell 43, Remove Curse, and the routine the Temple's Remove
  Curse service calls (ovl22_e10 maps DS:6B84+43*4 to overlay stub 0096:007E; SpellNames[43] is
  'Remove Curse' at DS:2FCC; the Temple's RemoveCurse ovl04:083A stores the character in ds6C95 and
  calls this). It first tries to cure the curse affect $24 from the character ds6C95 and, when it was
  there, says 'is un-cursed' (res12_fn_1FEB). Otherwise it walks the character's carried items
  (ds6C95^.Items, the list at +$C8) and clears the Cursed flag (+$36) of the first cursed item it
  finds, saying ''s item is un-cursed'. Reads ds6C95; changes the character's affects and its items. }
procedure CastRemoveCurse;
const
  CurseAffect = $24;              { the curse affect CureAffect removes (AffectCurse, ovl04:08A0) }
  ShowAbout = 1;                  { res12_fn_1FEB's Flag argument }
var
  Item: PItem;                    { the walker of the character's carried items }
  UnCursed: Boolean;              { whether a cursed item was found and cleared }
begin
  if CureAffect(ds6C95, CurseAffect) then
    res12_fn_1FEB(ds6C95, ShowAbout, 'is un-cursed')
  else
  begin
    UnCursed := False;
    Item := ds6C95^.Items;
    while (Item <> nil) and not UnCursed do
    begin
      if Item^.Cursed then
      begin
        UnCursed := True;
        Item^.Cursed := False;
      end;
      Item := Item^.Next;
    end;
    if UnCursed then
      res12_fn_1FEB(ds6C95, ShowAbout, '''s item is un-cursed');
  end;
end;
{ ovl22:2604. Cast handler of spell 44, Bestow Curse (ovl22_e10 maps DS:6B84+44*4 to overlay
  stub 0096:0106; SpellNames[44] is 'Bestow Curse' at DS:2FF5 and SpellTable[44].AffectId is the curse
  affect $24). It only applies the current spell ds681B to the chosen targets with the message
  'has been cursed!'; the spell's own affect does the cursing, so the handler has nothing else to do.
  Reads ds681B. }
procedure CastBestowCurse;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'has been cursed!');
end;
{ ovl22:263D. Cast handler of spell 45, Blink (ovl22_e10 maps DS:6B84+45*4 to overlay stub 0096:010B;
  SpellNames[45] is 'Blink' at DS:301E and SpellTable[45].AffectId is the blink affect $25). It only
  applies the current spell ds681B to the chosen targets with the message 'is blinking'; the spell's
  own affect does the blinking, so the handler has nothing else to do. Reads ds681B. }
procedure ovl22_e47;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'is blinking');
end;
{ ovl22:266B: retf 0: 0 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl22_e48; begin end;
{ ovl22:2764: retf 8: 8 bytes of parameters; 44 bytes of locals }
{@stub} procedure ovl22_fn_2764; begin end;
{ ovl22:2892: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl22_e49; begin end;
{ ovl22:28BC: retf 12: 12 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl22_fn_28BC; begin end;
{ ovl22:295B: frame not read }
{@stub} procedure ovl22_fn_295B; begin end;
{ ovl22:2B8B: frame not read }
{@stub} procedure ovl22_fn_2B8B; begin end;
{ ovl22:2BB7: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_e50; begin end;
{ ovl22:2C09: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl22_e51; begin end;
{ ovl22:2C43: frame not read }
{@stub} procedure ovl22_e52; begin end;
{ ovl22:2D39: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_2D39; begin end;
{ ovl22:2E02: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl22_e53; begin end;
{ ovl22:2E4D: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e54; begin end;
{ ovl22:2EE5: frame not read }
{@stub} procedure ovl22_e55; begin end;
{ ovl22:2EEA: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_2EEA; begin end;
{ ovl22:2F4D: frame not read }
{@stub} procedure ovl22_e56; begin end;
{ ovl22:2F57: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_2F57; begin end;
{ ovl22:2F99: retf 0: 0 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl22_e57; begin end;
{ ovl22:2FD0: frame not read }
{@stub} procedure ovl22_e58; begin end;
{ ovl22:2FD3: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl22_fn_2FD3; begin end;
{ ovl22:302A: retf 0: 0 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl22_e59; begin end;
{ ovl22:3058: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_e60; begin end;
{ ovl22:3092: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_e61; begin end;
{ ovl22:30A2: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e62; begin end;
{ ovl22:30D9: frame not read }
{@stub} procedure ovl22_e63; begin end;
{ ovl22:31D7: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_31D7; begin end;
{ ovl22:323D: frame not read }
{@stub} function ovl22_e6(Item: Pointer): Boolean; begin end;
{ ovl22:3262: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_3262; begin end;
{ ovl22:328A: retf 10: 10 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl22_e7(Who: PCharacter; Item: PItem; Spell: Byte); begin end;
{ ovl22:331A: frame not read }
{@stub} procedure ovl22_e8(Who: PCharacter; Message: String40; Spell: Byte); begin end;
{ ovl22:3379: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_3379; begin end;
{ ovl22:3413: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_e10; begin end;

begin
end.
