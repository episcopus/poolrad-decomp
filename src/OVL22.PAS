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
procedure ovl22_e19;
procedure ovl22_e20;
procedure ovl22_e21;
procedure ovl22_e22;
procedure ovl22_e23;
procedure ovl22_e24;
procedure ovl22_e25;
procedure ovl22_e26;
procedure ovl22_e27;
procedure ovl22_fn_1758;
procedure ovl22_e28;
procedure ovl22_e29;
procedure ovl22_e30;
procedure ovl22_e31;
procedure ovl22_e32;
procedure ovl22_e33;
procedure ovl22_e34;
procedure ovl22_e35;
procedure ovl22_e36;
procedure ovl22_e37;
procedure ovl22_e38;
procedure ovl22_fn_202B;
procedure ovl22_e39;
procedure ovl22_fn_20A9;
procedure ovl22_e40;
procedure ovl22_fn_2233;
procedure ovl22_e41;
procedure ovl22_fn_228A;
procedure ovl22_fn_228C;
procedure ovl22_e42;
procedure ovl22_e43;
procedure ovl22_fn_2383;
procedure ovl22_e44;
procedure ovl22_fn_23B6;
procedure ovl22_e45;
procedure ovl22_e9;
procedure ovl22_fn_257E;
procedure ovl22_fn_25C9;
procedure ovl22_e46;
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
  Duration) and ovl22_e20, ovl22_fn_1758, ovl22_fn_202B, ovl22_fn_2EEA. }
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
{ ovl22:10E9: retf 0: 0 bytes of parameters; 12 bytes of locals }
{ ovl22:10E9 (e15). Cast handler of the detection spells, spells 5 and 11 (Detect Magic), 18 (Read
  Magic), 22 (Find Traps) and 29 (Detect Invisibility): applies the current spell ds681B to the
  chosen targets with the message 'is affected' and no damage of its own (ApplySpellToTargets; the
  spell's own AffectId does the work). One of the per-spell handlers in SpellHandlers
  (SpellHandlers[5], [11], [18], [22] and [29]; the table is filled by ovl22_e10). }
procedure CastDetectionSpell;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'is affected');
end;
{ ovl22:1123: retf 0: 0 bytes of parameters; 14 bytes of locals }
{ ovl22:1123 (e16). Cast handler of the protection spells, spells 6 and 16 (Protection From Evil) and
  7 and 17 (Protection From Good): applies the current spell ds681B to the chosen targets with the
  message 'is protected' and no damage of its own (ApplySpellToTargets; the spell's own AffectId does
  the work). One of the per-spell handlers in SpellHandlers (SpellHandlers[6], [7], [16] and [17];
  filled by ovl22_e10). }
procedure CastProtection;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'is protected');
end;
{ ovl22:1162: retf 0: 0 bytes of parameters; 18 bytes of locals }
{ ovl22:1162 (e17). Cast handler of spell 8, Resist Cold: applies the current spell ds681B to the
  chosen targets with the message 'is cold-resistant' and no damage of its own (ApplySpellToTargets;
  the spell's own AffectId does the work). One of the per-spell handlers in SpellHandlers
  (SpellHandlers[8], filled by ovl22_e10). }
procedure CastResistCold;
begin
  ApplySpellToTargets(ds681B, 0, 0, 0, 0, 'is cold-resistant');
end;
{ ovl22:1190: retf 0: 0 bytes of parameters; 2 bytes of locals }
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
{ ovl22:11DD: retf 0: 0 bytes of parameters; 22 bytes of locals }
{@stub} procedure ovl22_e19; begin end;
{ ovl22:12A5: retf 0: 0 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl22_e20; begin end;
{ ovl22:136E: retf 0: 0 bytes of parameters; 18 bytes of locals }
{@stub} procedure ovl22_e21; begin end;
{ ovl22:13D8: retf 0: 0 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl22_e22; begin end;
{ ovl22:1439: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_e23; begin end;
{ ovl22:1499: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e24; begin end;
{ ovl22:14C7: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_e25; begin end;
{ ovl22:151B: retf 0: 0 bytes of parameters; 18 bytes of locals }
{@stub} procedure ovl22_e26; begin end;
{ ovl22:1658: frame not read }
{@stub} procedure ovl22_e27; begin end;
{ ovl22:1758: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_1758; begin end;
{ ovl22:17E9: retf 0: 0 bytes of parameters; 18 bytes of locals }
{@stub} procedure ovl22_e28; begin end;
{ ovl22:1822: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e29; begin end;
{ ovl22:185B: retf 0: 0 bytes of parameters; 20 bytes of locals }
{@stub} procedure ovl22_e30; begin end;
{ ovl22:190F: retf 0: 0 bytes of parameters; 16 bytes of locals }
{@stub} procedure ovl22_e31; begin end;
{ ovl22:19C3: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_e32; begin end;
{ ovl22:1A16: retf 0: 0 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl22_e33; begin end;
{ ovl22:1A4F: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e34; begin end;
{ ovl22:1A8A: retf 0: 0 bytes of parameters; 14 bytes of locals }
{@stub} procedure ovl22_e35; begin end;
{ ovl22:1ACC: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e36; begin end;
{ ovl22:1B11: retf 0: 0 bytes of parameters; 42 bytes of locals }
{@stub} procedure ovl22_e37; begin end;
{ ovl22:1F41: frame not read }
{@stub} procedure ovl22_e38; begin end;
{ ovl22:202B: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_202B; begin end;
{ ovl22:206F: frame not read }
{@stub} procedure ovl22_e39; begin end;
{ ovl22:20A9: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_20A9; begin end;
{ ovl22:2217: frame not read }
{@stub} procedure ovl22_e40; begin end;
{ ovl22:2233: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_2233; begin end;
{ ovl22:225D: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl22_e41; begin end;
{ ovl22:228A: frame not read }
{@stub} procedure ovl22_fn_228A; begin end;
{ ovl22:228C: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_228C; begin end;
{ ovl22:232F: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl22_e42; begin end;
{ ovl22:234C: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e43; begin end;
{ ovl22:2383: frame not read }
{@stub} procedure ovl22_fn_2383; begin end;
{ ovl22:2385: frame not read }
{@stub} procedure ovl22_e44; begin end;
{ ovl22:23B6: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_23B6; begin end;
{ ovl22:24D6: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e45; begin end;
{ ovl22:2540: frame not read }
{@stub} procedure ovl22_e9; begin end;
{ ovl22:257E: frame not read }
{@stub} procedure ovl22_fn_257E; begin end;
{ ovl22:25C9: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl22_fn_25C9; begin end;
{ ovl22:2604: retf 0: 0 bytes of parameters; 18 bytes of locals }
{@stub} procedure ovl22_e46; begin end;
{ ovl22:263D: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl22_e47; begin end;
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
