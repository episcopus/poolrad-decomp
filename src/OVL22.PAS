unit OVL22;
{ CastSpell: the spell study and casting overlay. It builds the spell lists the camp's
  ChooseSpellFromList shows (BuildSpellList and its helpers, whitepaper 5.22), runs the picker
  (PickSpellFromMenu), gives a spell's area pattern size (SpellAreaSize) and casts, scribes, memorizes
  and learns spells for combat (ovl09) and the camp (ovl15). }
{$A-,O+,F+,S-,R-,G-,I-,L-}
interface
uses POOLVARS, RES03, RES06, RES09, RES12, OVL23, OVL24, OVL25, OVL30, OVL31;
function PickSpellFromMenu(Mode: Byte; var Choice: Word): Byte;
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
function IsScroll(Item: PItem): Boolean;
procedure ConsumeScrollSpell(Who: PCharacter; Item: PItem; Spell: Byte);
procedure ShowSpellMessage(Who: PCharacter; Message: String40; Spell: Byte);
procedure CastRemoveCurse;
procedure InitSpellHandlers;
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
function CureDiseaseAffects: Boolean;
procedure CastStinkingCloud;
procedure CastStrength;
procedure CastAnimateDead;
procedure CastCureBlindness;
procedure CastCauseBlindness;
procedure CastCureDisease;
procedure CastCauseDisease;
procedure CastDispelMagic;
procedure ApplySpellToSideUpToLevel(Affect, Side: Byte; Message: String40);
procedure CastPrayer;
procedure DamageTargetInCell(CellX, CellY, Damage, SaveKind: Byte; var Blocked: Boolean);
procedure CastLineBeam(Range, Damage, SaveKind, Bounce: Byte);
procedure CastBestowCurse;
procedure CastBlink;
procedure CastFireball;
procedure CastHaste;
procedure CastLightningBolt;
procedure CastSlow;
procedure CastRestoration;
procedure CastMonsterHaste;
procedure CastMonsterHeal;
procedure CastMonsterStrength;
procedure CastMonsterBeam;
procedure CastMonsterParalyze;
procedure CastMonsterHealWounds;
procedure CastMonsterInvisibility;
procedure CastMonsterMagicDamage;
procedure CastMonsterNoEffect;
procedure CastMonsterReadMagic;
procedure MonsterBreath(Who: PCharacter; Affect: PAffect; Unused: Byte);
implementation

{ ovl22:008A: retf 6: 6 bytes of parameters; 98 bytes of locals }
{ ovl22:008A. The spell menu picker ChooseSpellFromList (ovl19:299C) calls once BuildSpellList has filled
  SpellMenuList: it shows the list in the spell window through ChooseFromList, asking again until the player
  picks a word (Cast, Learn, Memorize or Scribe), presses Enter or leaves, and returns the spell number of the
  chosen line, or 0 when the player left (Exit or Escape). Mode (ChooseSpellFromList's DisplayMode) picks the
  button word: 1 'Cast', 2 'Memorize', 3 'Scribe', 4 'Learn' (any other Mode: no button and no title); the
  title is 'Choose Spell: ' for Modes 1 to 4. Mode 2 uses the short window (bottom row $0F, else $16) and
  Mode 4 offers no Exit. Choice is the list position the picker starts on and receives the position it ends
  on; a negative Choice (-1 from UseItem) first draws the spell window frame (rows 3 to the bottom) and
  restarts at 0. The page is redrawn on entry for a new window, and always for Learn and Cast. Mode 3 (Scribe)
  copies the item the chosen line came from, SpellMenuItems[index of the line], to CurrentItem. The list is
  freed (FreeMenuList) before returning. Globals: SpellMenuList (freed), SpellMenuSpells, SpellMenuItems,
  CurrentItem. Side effects: the screen, the heap.
  Choice stays the Word its callers declare and reaches ChooseFromList (var Choice: Integer) through the
  typecast Integer(Choice), a variable reference TP 6.0 accepts (probe VARCAST.PAS; WDTOIN.PAS shows the
  plain Word is refused).
  QUIRK ovl22:0194: the byte at [bp-5C] is allocated but never read or written.
  QUIRK ovl22:0230: with a left picker (Key #0) Selected is nil, the walk ends at the list's end and SpellIndex
  is the count of spell lines; Mode 3 then still copies SpellMenuItems[SpellIndex] to CurrentItem.
  QUIRK ovl22:01E8: the loop ends on the Key set [#0, Enter, 'C', 'E', 'L', 'M', 'S'] (the first letters of the
  buttons Cast, Exit, Learn, Memorize and Scribe), although ChooseFromList itself returns #0 for E and
  Escape. }
function PickSpellFromMenu(Mode: Byte; var Choice: Word): Byte;
const
  CastMode = 1;
  MemorizeMode = 2;
  ScribeMode = 3;
  LearnMode = 4;
  KeyNone = #0;
  KeyEnter = #13;
  ShortWindowBottom = $0F;      { the Memorize window ends on row 15 }
  TallWindowBottom = $16;       { the other windows end on row 22 }
  WindowLeft = 1;
  WindowFrameTop = 3;           { the frame drawn on a negative Choice starts two rows above the list }
  ListTop = 5;
  WindowRight = $26;
  HeadingColor = $0D;
  LineColor = $0A;
  HighlightColor = $0F;
var
  Selected: PMenuLine;          { the line ChooseFromList left highlighted, nil when the player left }
  WalkPtr: PMenuLine;           { walks the list up to Selected, counting the spell lines }
  Title: String40;              { the window title, 'Choose Spell: ' for Modes 1 to 4 }
  Prompt: String40;             { the button word list: 'Cast', 'Memorize', 'Scribe', 'Learn' or '' }
  UnusedByte: Byte;
  SpellIndex: Byte;             { the position of the chosen line among the spell lines (headings not counted) }
  Bottom: ShortInt;             { the window's bottom row }
  Key: Char;                    { the key ChooseFromList returned }
  WithExit: Byte;               { 1 shows the Exit word, 0 for Learn }
  Redraw: Byte;                 { ChooseFromList's var Redraw: 1 draws the entry page }
begin
  case Mode of
    CastMode: Prompt := 'Cast';
    MemorizeMode: Prompt := 'Memorize';
    ScribeMode: Prompt := 'Scribe';
    LearnMode: Prompt := 'Learn';
  else
    Prompt := '';
  end;
  if Mode in [CastMode..LearnMode] then
    Title := 'Choose Spell: '
  else
    Title := '';
  if Mode = MemorizeMode then
    Bottom := ShortWindowBottom
  else
    Bottom := TallWindowBottom;
  if Mode = LearnMode then
    WithExit := 0
  else
    WithExit := 1;
  Redraw := 0;
  if Integer(Choice) < 0 then
  begin
    DrawWindow(WindowLeft, WindowFrameTop, WindowRight, Bottom, 0, 0, '');
    Redraw := 1;
    Choice := 0;
  end;
  if (Mode = LearnMode) or (Mode = CastMode) then
    Redraw := 1;
  Selected := nil;
  repeat
    Key := ChooseFromList(Title, Prompt, HeadingColor, LineColor, HighlightColor, WindowLeft, ListTop,
      WindowRight, Bottom, SpellMenuList, WithExit, Redraw, Integer(Choice), Selected);
  until Key in [KeyNone, KeyEnter, 'C', 'E', 'L', 'M', 'S'];
  WalkPtr := SpellMenuList;
  SpellIndex := 0;
  while WalkPtr <> Selected do
  begin
    if WalkPtr^.Flag29 = 0 then
      Inc(SpellIndex);
    WalkPtr := WalkPtr^.Next;
  end;
  if Key in [KeyNone, 'E'] then
    PickSpellFromMenu := 0
  else
    PickSpellFromMenu := SpellMenuSpells[SpellIndex];
  if Mode = ScribeMode then
    CurrentItem := SpellMenuItems[SpellIndex];
  FreeMenuList(SpellMenuList);
end;
{ ovl22:028D: retf 2: 2 bytes of parameters; 262 bytes of locals }
{ ovl22:028D. Appends one line for spell Spell to the spell menu list SpellMenuList (BuildSpellList calls this
  once per spell, in list order). The line's text is ' *' when the pending bit $80 of Spell is set,
  else '  ', followed by SpellNames[Spell and $7F]; when the spell's level differs from the level of
  the previous line a heading line (SpellLevelNames[level]: '1st Level' and so on) is inserted first.
  SpellMenuSpells[Count] keeps the spell number (pending bit cleared) of the line added. Called by BuildSpellList
  and AddItemSpells. }
procedure AddSpellMenuLine(Spell: Byte);
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
  if SpellTable[Spell and SpellMask].Level <> PrevLevel then
  begin
    Line^.Text := SpellLevelNames[SpellTable[Spell and SpellMask].Level];
    Line^.Flag29 := 1;
    GetMem(Line^.Next, MenuLineBytes);
    Line := Line^.Next;
    Line^.Next := nil;
  end;
  if Spell > SpellMask then
    Line^.Text := ' *'
  else
    Line^.Text := '  ';
  Line^.Text := Line^.Text + SpellNames[Spell and SpellMask];
  Line^.Flag29 := 0;
  SpellMenuSpells[Count] := Spell and SpellMask;
end;
{ ovl22:044E: retf 2: 2 bytes of parameters; 6 bytes of locals }
{ ovl22:044E. Adds the spell affects of the current item (CurrentItem, set by AddScrollSpells or by the
  caller) to the spell menu list: for each of its three spell affects it calls AddSpellMenuLine and
  records the item in SpellMenuItems[SpellMenuItemCount]. Pending selects which affects count: nonzero
  takes the pending ones (the pending bit $80 set, > $80), zero the plain ones (> 0). First it clears
  the item's HiddenNames so its spells can be listed: a character carrying the Read Magic affect
  (HasAffect(SelectedCharacter, ReadMagicAffect)) sees the item's hidden spell names, and a cleric
  (ClassLevels[0] > 0) sees a cleric's scroll (ItemTable[CurrentItem^.ItemType].Slot =
  ClericScrollClass); an item whose HiddenNames is not cleared is skipped. Called by BuildSpellList
  (Kind 2) and AddScrollSpells. }
procedure AddItemSpells(Pending: Byte);
const
  { The Read Magic affect (spell 18 Read Magic, SpellTable[18].AffectId): while the character
    carries it he sees the item's hidden spell names. }
  ReadMagicAffect = $10;
  { ItemTable[ItemType].Slot of a cleric's scroll (item type $3E, BuildTreasureItem ovl21:1010):
    a cleric sees the scroll's spells without Read Magic. }
  ClericScrollClass = $0C;
  PendingSpell = $80;             { the pending bit above the spell number in an item's spell affect }
var
  I: Byte;
  Affect: Pointer;
begin
  if HasAffect(SelectedCharacter, ReadMagicAffect, Affect) or
     ((SelectedCharacter^.ClassLevels[0] > 0) and
      (ItemTable[CurrentItem^.ItemType].Slot = ClericScrollClass)) then
    CurrentItem^.HiddenNames := 0;
  if CurrentItem^.HiddenNames = 0 then
    for I := 1 to 3 do
      if ((Pending <> 0) and (CurrentItem^.Affects[I] > PendingSpell)) or
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
  (IsScroll), calls AddItemSpells with its Pending argument. Called by BuildSpellList for the "on Scrolls"
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
    if IsScroll(CurrentItem) then
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
const
  PendingSpell = $80;             { the pending bit above the spell number }
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
        if (SelectedCharacter^.Spells[I] > 0) and (SelectedCharacter^.Spells[I] < PendingSpell) then
          AddSpellMenuLine(SelectedCharacter^.Spells[I]);
    5:
      for I := 0 to $14 do
        if SelectedCharacter^.Spells[I] > SpellMask then
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
{ ovl22:0729. The size of the area pattern of spell Spell: CollectEnemiesInRange collects the targets it
  reaches. A 16-byte SpellTable row gives a base (row +2) and a per-level byte (row +3), so the
  result is base + per-level * caster level, the level from SpellCasterLevel (or * 6 while ItemAffectUse is
  set). A zero base with row +6 set becomes 1, and $FF (omni) becomes 1 too. Called by SpellAccepted
  (ovl09:02EB) and ovl13:1E16. }
function SpellAreaSize(Spell: Byte): Byte;
var
  Area: Byte;
begin
  if not ItemAffectUse then
    Area := SpellTable[Spell].Pad2[2] + SpellTable[Spell].Pad2[3] * SpellCasterLevel(Spell)
  else
    Area := SpellTable[Spell].Pad2[3] * 6 + SpellTable[Spell].Pad2[2];
  if Area = 0 then
    if SpellTable[Spell].Pad2[6] <> 0 then
      Area := 1;
  if Area = $FF then
    Area := 1;
  SpellAreaSize := Area;
end;
{ ovl22:07D6. The duration (in ApplyAffect's time unit) of the affect a spell leaves. Spell is the
  spell number (the cast handlers pass CastingSpell). A few spells are rolled for instead of read from the
  table: spell 40 Cause Disease is 1d6*10, spells 57 and 61 are 5d4, spell 59 is 1d4*10+40, spell 63 is
  2d10*10 in combat (view mode 5) else (1d10+10)*10, and spell 67 is a flat $5A0. Every other value
  uses the SpellTable row's duration base (byte +4) plus its per-level byte (byte +5) times the caster
  level from SpellCasterLevel. Called by ApplySpellToTargets (as ApplyAffect's Duration) and
  CastEnlarge, CastHoldPerson, CastStrength, CastMonsterStrength. }
function SpellAffectDuration(Spell: Byte): Word;
const
  { The few spells whose affect time is rolled for instead of read from SpellTable, by spell number
    (CastingSpell); the values are spell numbers, not affect ids. }
  CauseDisease = $28;              { spell 40: 1d6 * 10 }
  MonsterHaste = $39;              { spell 57: 5d4 }
  MonsterStrength = $3B;           { spell 59: 1d4 * 10 + 40 }
  MonsterParalyze = $3D;           { spell 61: 5d4 }
  MonsterInvisibility = $3F;       { spell 63: 2d10 * 10 in combat, else (1d10 + 10) * 10 }
  MonsterReadMagic = $43;          { spell 67: a flat $5A0 }
  Scale = 10;
var
  Value: Word;
begin
  case Spell of
    CauseDisease:
      Value := RollDice(1, 6) * Scale;
    MonsterHaste, MonsterParalyze:
      Value := RollDice(5, 4);
    MonsterStrength:
      Value := RollDice(1, 4) * Scale + 40;
    MonsterInvisibility:
      if ViewMode = ViewModeCombat then
        Value := RollDice(2, 10) * Scale
      else
        Value := (RollDice(1, 10) + Scale) * Scale;
    MonsterReadMagic:
      Value := $5A0;
  else
    Value := SpellTable[Spell].Pad2[4] + SpellTable[Spell].Pad2[5] * SpellCasterLevel(Spell);
  end;
  SpellAffectDuration := Value;
end;
{ ovl22:08C3. Applies the chosen spell Spell to every target in SpellTargets[1..SpellTargetCount] (the list the
  picker ChooseSpellTargets filled). It first sets the global DamageKind (Kind when the spell deals Damage,
  else 0) and returns at once with no targets. For each non-nil target: it rolls the spell's own
  saving throw (SpellTable row byte +8 nonzero, the save kind in +9) into Saved, and, when the
  current spell's row byte +2 is $FF, runs the affect hooks, and rolls to hit the target's
  ArmourClassValue (+$111); a miss cancels the damage and counts as saved. It deals Damage through
  DealDamage and, when the spell's AffectId (row byte +$A) is set, applies the affect through
  ApplyAffect with SpellAffectDuration(Spell), the caster level (CasterLevel, or SpellCasterLevel
  when 0), Flag, the row's save effect and Message. Called by the spell menus; the caster level is
  real or computed. }
procedure ApplySpellToTargets(Spell, CasterLevel, Flag, Damage, Kind: Byte; Message: String40);
var
  Level: Byte;                    { the caster level used as ApplyAffect's Data }
  I: Byte;                        { the target index, 1..SpellTargetCount }
  Target: PCharacter;             { the target SpellTargets[I] the spell is applied to }
  Saved: Boolean;                 { whether the target saved against the spell }
begin
  if Damage = 0 then
    DamageKind := 0
  else
    DamageKind := Kind;
  if SpellTargetCount = 0 then
    Exit;
  if CasterLevel = 0 then
    Level := SpellCasterLevel(Spell)
  else
    Level := CasterLevel;
  for I := 1 to SpellTargetCount do
    if SpellTargets[I] <> nil then
    begin
      Target := SpellTargets[I];
      if SpellTable[Spell].Pad2[8] = 0 then
        Saved := False
      else
        Saved := SavingThrow(Target, SpellTable[Spell].Pad2[9], 0);
      if SpellTable[CastingSpell].Pad2[2] = $FF then
      begin
        RecalcCombatValues(Target);
        RunAffectHooks($0B, Target);
        if not RollToHit(SelectedCharacter, Target, Target^.ArmourClassValue) then
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
  go ahead. It defaults the picker's chosen character PickedSpellCharacter to the selected character, sets the
  target count SpellTargetCount to 1 and the first target FirstSpellTarget to the selected character, and Done to 1, then
  switches on the spell's target mode (SpellTable row byte +7): mode 1 keeps only the caster; mode 2
  asks 'Cast Spell on whom' (SelectPartyMember picks into PickedSpellCharacter) and keeps the pick, or clears Done and
  the list when none was picked; mode 4 adds every character of the party list PartyListHead, walking Next
  (+$104), to the list; any other mode clears Done. The second byte parameter is unused (QUIRK
  ovl22:0A91: the original frame reserves it). Called as the DS:6B84 combat callback (ovl08 EndCombat
  stores @ChooseSpellTargets). }
procedure ChooseSpellTargets(Spell: Byte; Unused: Byte; var Done: Byte);
var
  { Never read: the original frame reserves one pointer (QUIRK ovl22:0A91); it is declared so the
    frame and the string temporary below it land where the original put them. }
  Spare: PCharacter;
begin
  if PickedSpellCharacter = nil then
    PickedSpellCharacter := SelectedCharacter;
  FirstSpellTarget := SelectedCharacter;
  SpellTargetCount := 1;
  Done := 1;
  case SpellTable[Spell].Pad2[7] of
    1: ;
    2:
    begin
      RedrawView;
      SelectPartyMember('Cast Spell on whom', True, PickedSpellCharacter);
      if PickedSpellCharacter = nil then
      begin
        FirstSpellTarget := nil;
        SpellTargetCount := 0;
        Done := 0;
      end
      else
        FirstSpellTarget := PickedSpellCharacter;
    end;
    4:
      begin
        SpellTargets[SpellTargetCount] := PCharacter(PartyListHead);
        while SpellTargets[SpellTargetCount]^.Next <> nil do
        begin
          SpellTargets[SpellTargetCount + 1] := SpellTargets[SpellTargetCount]^.Next;
          Inc(SpellTargetCount);
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
  given up. On a cast the caster is animated (DrawCombatIcon, faced towards the aim point SpellAimX/
  SpellAimY through InDirArc, a sound and a WalkCombatLine line) and the spell's handler
  SpellHandlers[Spell] runs with CastingSpell set. ClearCharacterMessage clears the prompt afterwards. Called
  by the combat and camp cast paths (ovl08:031A, ovl09:000F, ovl05:0ECD, ovl13:2432, ovl15:04A1,
  ovl19:1BD7). Globals: SelectedCharacter, ViewMode, ItemAffectUse, SpellAimX/SpellAimY, CastingSpell,
  SpellAppliedToArea and the
  SpellHandlers table. }
procedure CastChosenSpell(Spell, Quick, Announce: Byte; var Done: Byte);
const
  Fireball = $2F;                 { the two spells whose cast has its own sound }
  LightningBolt = $33;
  AimStep = 4;                    { the line WalkCombatLine walks for the cast animation }
  AimWidth = $1E;
  AnimationKind = $12;            { DrawCombatIcon's argument that starts the cast animation }
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
  if (ViewMode <> ViewModeCombat) and (SpellTable[Spell].Pad2[7] = 0) then
  begin
    if not ItemAffectUse then
    begin
      DrawTextAt(1, $13, $A, SpellNames[Spell]);
      DrawTextAt(1, $14, $A, 'is a combat-only spell...');
      if AskYesNo('Lose it? ', $D, $F, $A) = 'Y' then
        ForgetSpell(Spell);
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
  if (Announce <> 0) and (not ItemAffectUse) then
    ShowSpellMessage(Caster, 'casts', Spell);
  while OK do
  begin
    SpellTargetPicker(Spell, Quick, Done);
    if Done <> 0 then
    begin
      OK := False;
      if ViewMode = ViewModeCombat then
      begin
        DrawCombatIcon(AnimationKind);
        CasterX := CombatantX(Caster);
        CasterY := CombatantY(Caster);
        Dir := 0;
        while not InDirArc(CasterX, CasterY, SpellAimX, SpellAimY, Dir) do
          Inc(Dir);
        SetCombatantIcon(Caster, Dir, 1, 0);
        SetSoundDriverIdle(SoundIdleOff);
        case Spell of
          Fireball: PlaySound(SoundFireball);
          LightningBolt: PlaySound(SoundLightningBolt);
        else
          PlaySound(SoundSpellDefault);
        end;
        WalkCombatLine(CasterX, CasterY, SpellAimX, SpellAimY, AimStep, AimWidth);
        SetSoundDriverIdle(SoundIdleDefault);
        if IsCombatantInView(Caster, 0) then
        begin
          SetCombatantIcon(Caster, Caster^.Combat^.IconSet, 1, 1);
          SetCombatantIcon(Caster, Caster^.Combat^.IconSet, 0, 0);
        end;
      end;
      ClearAttackerAffect(Caster);
      if not ItemAffectUse then
        ForgetSpell(Spell);
      CastingSpell := Spell;
      SpellHandlers[CastingSpell];
      CastingSpell := 0;
      SpellAppliedToArea := 0;
    end
    else
    begin
      if ViewMode <> ViewModeCombat then
        OK := False
      else if (Quick <> 0) or (AskYesNo('Abort Spell? ', $E, $A, $F) = 'Y') then
      begin
        ShowFlashMessage('Spell Aborted');
        if not ItemAffectUse then
          ForgetSpell(Spell);
        OK := False;
      end;
    end;
  end;
  ClearCharacterMessage;
  if ViewMode = ViewModeCombat then
    ClearWindow(0, $17, $27, $17);
end;
{ ovl22:0F4F. Applies the current spell CastingSpell to the chosen targets (SpellTargets[1..SpellTargetCount]) but keeps
  only those on Side: a target whose TCharacter.Side differs is dropped (set nil) and, for spell 1
  (Bless) in combat, a target the spell's area already reaches (CollectEnemiesInRange nonzero) is dropped
  too. Sets SpellAppliedToArea and calls ApplySpellToTargets with Message and no damage or affect of its own.
  Called by the cast handlers of spells 1 and 2 (Bless and Curse). }
procedure ApplySpellToSide(Side: Byte; Message: String40);
var
  I: Byte;                        { the target index, 1..SpellTargetCount }
begin
  SpellAppliedToArea := 1;
  for I := 1 to SpellTargetCount do
    if (SpellTargets[I]^.Side <> Side) or
       ((CastingSpell = 1) and (ViewMode = 5) and (CollectEnemiesInRange(SpellTargets[I], 1) > 0)) then
      SpellTargets[I] := nil;
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, Message);
end;
{ ovl22:100F (e11). Cast handler of spell 1, Bless: applies the current spell CastingSpell to the party
  side of the selected character (SelectedCharacter^.Side) with the message 'is Blessed'. One of the
  per-spell handlers in SpellHandlers (SpellHandlers[1], filled by InitSpellHandlers). }
procedure CastBless;
begin
  ApplySpellToSide(SelectedCharacter^.Side, 'is Blessed');
end;
{ ovl22:1040 (e12). Cast handler of spell 2, Curse: applies the current spell CastingSpell to the side
  opposite the selected character (OpposingSide returns 1 for side 0, else 0) with the message
  'is Cursed'. One of the per-spell handlers in SpellHandlers (SpellHandlers[2]). }
procedure CastCurse;
begin
  ApplySpellToSide(OpposingSide(SelectedCharacter), 'is Cursed');
end;
{ ovl22:106B (e13). Cast handler of spell 3, Cure Light Wounds: when a target was chosen (SpellTargetCount
  nonzero) it rolls 1d8 (RollDice) and heals the first target FirstSpellTarget through HealCharacter (flag 0),
  then reports through ShowHealResult whether the target is fully or partially healed. One of the
  per-spell handlers in SpellHandlers (SpellHandlers[3], filled by InitSpellHandlers). }
procedure CastCureLightWounds;
begin
  if SpellTargetCount = 0 then
    Exit;
  if HealCharacter(FirstSpellTarget, RollDice(1, 8), 0) then
    ShowHealResult(FirstSpellTarget);
end;
{ ovl22:10A7 (e14). Cast handler of spell 4, Cause Light Wounds: applies the current spell CastingSpell
  to the chosen targets with 1d8 damage of kind 8 and no message (ApplySpellToTargets; the dice go
  through RollDiceCounted, which also records their count in LastDiceCount). One of the per-spell handlers
  in SpellHandlers (SpellHandlers[4], filled by InitSpellHandlers). }
procedure CastCauseLightWounds;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, RollDiceCounted(1, 8), 8, '');
end;
{ ovl22:10E9 (e15). Cast handler of the detection spells, spells 5 and 11 (Detect Magic), 18 (Read
  Magic), 22 (Find Traps) and 29 (Detect Invisibility): applies the current spell CastingSpell to the
  chosen targets with the message 'is affected' and no damage of its own (ApplySpellToTargets; the
  spell's own AffectId does the work). One of the per-spell handlers in SpellHandlers
  (SpellHandlers[5], [11], [18], [22] and [29]; the table is filled by InitSpellHandlers). }
procedure CastDetectionSpell;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'is affected');
end;
{ ovl22:1123 (e16). Cast handler of the protection spells, spells 6 and 16 (Protection From Evil) and
  7 and 17 (Protection From Good): applies the current spell CastingSpell to the chosen targets with the
  message 'is protected' and no damage of its own (ApplySpellToTargets; the spell's own AffectId does
  the work). One of the per-spell handlers in SpellHandlers (SpellHandlers[6], [7], [16] and [17];
  filled by InitSpellHandlers). }
procedure CastProtection;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'is protected');
end;
{ ovl22:1162 (e17). Cast handler of spell 8, Resist Cold: applies the current spell CastingSpell to the
  chosen targets with the message 'is cold-resistant' and no damage of its own (ApplySpellToTargets;
  the spell's own AffectId does the work). One of the per-spell handlers in SpellHandlers
  (SpellHandlers[8], filled by InitSpellHandlers). }
procedure CastResistCold;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'is cold-resistant');
end;
{ ovl22:1190 (e18). Cast handler of spell 9, Burning Hands: deals SpellCasterLevel(CastingSpell) (the caster
  level) damage of kind DamageKindFire to the chosen targets with no message (ApplySpellToTargets;
  DealDamage classifies kind 9 as fire, ovl24:1389). One of the per-spell handlers in SpellHandlers
  (SpellHandlers[9], filled by InitSpellHandlers). }
procedure CastBurningHands;
const
  { The kind of damage Burning Hands deals: DealDamage names kind 9 'from Fire' (its test is
    DamageKind and $F7 = 1, ovl24:1389). }
  DamageKindFire = 9;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, SpellCasterLevel(CastingSpell), DamageKindFire, '');
end;
{ ovl22:11DD (e19). Cast handler of spell 10, Charm Person: it first refuses a target that is not a
  person, i.e. one whose CreatureType is above 1 or whose combat footprint kind (CombatSize, bits 0..6)
  is above 1, showing 'is unaffected' (ShowCharacterMessage). Otherwise it applies the current spell CastingSpell
  to the targets with the charm affect's data (the caster level SpellCasterLevel(CastingSpell) plus the
  caster's Side in bit 7, so the charmed creature joins that side) and runs the affect through
  CallAffectHandler ($0B, the charm affect id). One of the per-spell handlers in SpellHandlers
  (SpellHandlers[10], filled by InitSpellHandlers). Reads FirstSpellTarget (the first chosen target), SelectedCharacter;
  changes the affect list of the target through CallAffectHandler. }
procedure CastCharmPerson;
const
  CharmAffect = $0B;              { the charm affect CallAffectHandler runs and HasAffect finds }
  CharmableType = CreatureHumanoid;              { the largest CreatureType Charm Person can affect (a person) }
  CharmableSize = 1;              { the largest CombatSize (combat footprint kind) it can affect }
  { The caster's side goes into bit 7 of the affect's data (Side * SideScale). }
  SideScale = 128;
  { Charm Person's side effect: the affect handler runs when the affect is removed (Flag 1). }
  MessageColor = $A;             { the colour ShowCharacterMessage shows the message in }
var
  Affect: Pointer;                { the charm affect HasAffect finds on the target }
  Target: PCharacter;             { the first chosen target FirstSpellTarget, tested and charmed }
begin
  Target := FirstSpellTarget;
  if (Target^.CreatureType > CharmableType) or (Target^.CombatSize > CharmableSize) then
    ShowCharacterMessage(Target, 'is unaffected', MessageColor, TimedMessage)
  else
  begin
    ApplySpellToTargets(CastingSpell,
      SpellCasterLevel(CastingSpell) + ShortInt(SelectedCharacter^.Side) * SideScale, RunsHandlerOnRemove, 0, 0,
      'is charmed');
    if HasAffect(Target, CharmAffect, Affect) then
      CallAffectHandler(CharmAffect, FirstSpellTarget, PAffect(Affect), ModeApply);
  end;
end;
{ ovl22:12A5 (e20). Cast handler of spell 12, Enlarge: gives the first chosen target FirstSpellTarget the
  strength 18 (ExceptionalStrength) with the percentile for the caster level (SpellCasterLevel(CastingSpell):
  0 at level 1 up to 100 at level 6), through RaiseStrength, and shows 'is stronger' when the
  strength actually rose; it then adds the strength affect (id $0C, ovl24's AffectEnlarge) with
  the spell's duration, RaiseStrength's earlier-strength code and flag 1 (on removal it restores the
  old strength, ovl24:AddAffect). The level and percentile go through the shared working globals
  SpellWorkByteA/SpellWorkByteB. One of the per-spell handlers in SpellHandlers (SpellHandlers[12], filled by
  InitSpellHandlers). }
procedure CastEnlarge;
const
  StrengthAffect = $0C;           { the strength affect id AddAffect keeps the earlier strength in }
  { The exceptional-strength percentile Enlarge grants by caster level 1..6. }
  PercentLevel1 = 0;
  PercentLevel2 = 1;
  PercentLevel3 = $33;
  PercentLevel4 = $4C;
  PercentLevel5 = $5B;
  PercentLevel6 = $64;
  MessageColor = $A;             { the colour ShowCharacterMessage shows the message in }
var
  Code: Byte;                     { RaiseStrength's earlier-strength code, passed to AddAffect as Data }
begin
  SpellWorkByteA := ExceptionalStrength;
  case SpellCasterLevel(CastingSpell) of
    1: SpellWorkByteB := PercentLevel1;
    2: SpellWorkByteB := PercentLevel2;
    3: SpellWorkByteB := PercentLevel3;
    4: SpellWorkByteB := PercentLevel4;
    5: SpellWorkByteB := PercentLevel5;
    6: SpellWorkByteB := PercentLevel6;
  end;
  if RaiseStrength(FirstSpellTarget, SpellWorkByteA, SpellWorkByteB, Code) then
    ShowCharacterMessage(FirstSpellTarget, 'is stronger', MessageColor, TimedMessage);
  AddAffect(FirstSpellTarget, StrengthAffect, SpellAffectDuration(CastingSpell), Code, 1);
end;
{ ovl22:136E (e21). Cast handler of spell 13, Reduce (SpellHandlers[13]; InitSpellHandlers fills the table,
  whitepaper 5.22.2): when targets were chosen, a target that fails its saving throw (SavingThrow kind 4,
  a spell) loses the strength affect $0C that Enlarge adds (CureAffect) and is told 'has been reduced'.
  A target that saves, or that carries no strength affect, is left alone. Reads SpellTargetCount and FirstSpellTarget. }
procedure CastReduce;
const
  SaveKind = 4;                   { SavingThrow's kind for a spell (whitepaper 5.22.2) }
  StrengthAffect = $0C;           { the strength affect Enlarge adds; Reduce cancels it (ovl22:12A5) }
  MessageColor = $A;             { the colour ShowCharacterMessage shows the message in }
begin
  if SpellTargetCount > 0 then
    if not SavingThrow(FirstSpellTarget, SaveKind, 0) then
      if CureAffect(FirstSpellTarget, StrengthAffect) then
        ShowCharacterMessage(FirstSpellTarget, 'has been reduced', MessageColor, TimedMessage);
end;
{ ovl22:13D8 (e22). Cast handler of spell 14, Friends (SpellHandlers[14]; InitSpellHandlers fills the table,
  whitepaper 5.22.2): raises the chosen target FirstSpellTarget's Charisma by 2d4, capped at 25 ($19), and calls
  ApplySpellToTargets with the pre-roll Charisma as the affect's Data and the restore flag set, so the
  affect's handler puts the old Charisma back when the affect ends; the message is 'is friendly'.
  Reads FirstSpellTarget and CastingSpell. }
procedure CastFriends;
const
  DiceCount = 2;                  { 2d4 Charisma points (the AD&D Friends spell) }
  DiceSides = 4;
  CharismaCap = $19;              { Charisma's maximum, 25 }
  RestoreOnRemoval = 1;           { Flag: the affect handler runs when the affect is removed }
  MessageColor = $A;
var
  OldCharisma: Byte;              { the target's Charisma before the roll, the affect's Data }
begin
  OldCharisma := FirstSpellTarget^.Charisma;
  Inc(FirstSpellTarget^.Charisma, RollDice(DiceCount, DiceSides));
  if FirstSpellTarget^.Charisma > CharismaCap then
    FirstSpellTarget^.Charisma := CharismaCap;
  ApplySpellToTargets(CastingSpell, OldCharisma, RestoreOnRemoval, 0, 0, 'is friendly');
end;
{ ovl22:1439 (e23). Cast handler of spell 15, Magic Missile (SpellHandlers[15]; InitSpellHandlers fills the
  table, whitepaper 5.22.2): the caster level from SpellCasterLevel gives one missile per two levels, so
  it deals RollDiceCounted(Level div 2, 4) (a d4 per missile, its count kept in LastDiceCount) plus Level div 2
  (one point per missile) to the chosen targets, with no message. Reads CastingSpell. }
procedure CastMagicMissile;
const
  LevelsPerMissile = 2;           { one magic missile per two caster levels }
  MissileSides = 4;               { each missile does 1d4, plus 1 per missile }
  DamageKind = 8;                 { DealDamage's kind for the missiles (as Cause Light Wounds, ovl22:10A7) }
var
  Level: Byte;                    { the caster level, SpellCasterLevel(CastingSpell) }
begin
  Level := SpellCasterLevel(CastingSpell);
  ApplySpellToTargets(CastingSpell, 0, 0,
    RollDiceCounted(Level div LevelsPerMissile, MissileSides) + Level div LevelsPerMissile,
    DamageKind, '');
end;
{ ovl22:1499 (e24). Cast handler of spell 19, Shield (SpellHandlers[19]; InitSpellHandlers fills the table,
  whitepaper 5.22.2): applies the current spell CastingSpell (its own affect does the work) to the chosen
  targets with the message 'is shielded', no damage or flag of its own. Reads CastingSpell. }
procedure CastShield;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'is shielded');
end;
{ ovl22:14C7 (e25). Cast handler of spell 20, Shocking Grasp (SpellHandlers[20]; InitSpellHandlers fills the
  table, whitepaper 5.22.2): deals the caster level from SpellCasterLevel plus 1d8 (RollDiceCounted, count
  kept in LastDiceCount) of electrical damage to the chosen targets, with no message. Reads CastingSpell. }
procedure CastShockingGrasp;
const
  DiceSides = 8;                  { 1d8 plus one point per caster level (the AD&D Shocking Grasp) }
  DamageKindElectric = $0C;       { DealDamage: kind and $F7 = 4 names electricity (ovl24:1389) }
begin
  { QUIRK ovl22:14D7: TP 6.0 evaluates the right operand of `+` first when both are calls, so the
    original's SpellCasterLevel-before-RollDiceCounted order needs the sum written with the level on the
    right; the add is commutative and the bytes match only this way. }
  ApplySpellToTargets(CastingSpell, 0, 0,
    RollDiceCounted(1, DiceSides) + SpellCasterLevel(CastingSpell), DamageKindElectric, '');
end;
{ ovl22:151B (e26). Cast handler of spell 21, Sleep (SpellHandlers[21]; InitSpellHandlers fills the table,
  whitepaper 5.22.2): sets SpellAppliedToArea and rolls the 4d4 pool SpellWorkByteA. For every chosen target SpellTargets[I] it
  charges a cost in SpellWorkByteB by the target's HighestLevel (+$73, a monster's hit dice) and level 5's Race
  (+$2E). A target is slept (the cost comes off the pool) only when it is not Animated (Status <> 1,
  an undead), does not already carry the sleep affect $35 (HasAffect) and the pool still covers its
  cost; otherwise it is dropped (SpellTargets[I] := nil). ApplySpellToTargets then applies the spell's own
  affect to the survivors with 'falls asleep'. Reads SpellTargetCount, CastingSpell; changes SpellAppliedToArea,
  SpellWorkByteA, SpellWorkByteB
  and the target list. }
procedure CastSleep;
const
  SleepAffect = $35;              { the affect that marks a target already asleep }
  PoolDiceCount = 4;              { the 4d4 pool of hit dice Sleep can affect }
  PoolDiceSides = 4;
  { The pool cost of one target, by its HighestLevel (a monster's hit dice), the AD&D Sleep table. }
  CostLevel0 = 1;
  CostLevel2 = 2;
  CostLevel3 = 4;
  CostLevel4 = 6;
  CostLevel5Small = $A;           { a level-5 monster (Race 0, a hit-dice creature) costs 10 }
  CostLevel5Large = $14;          { any other level-5 or higher creature costs 20 }
var
  I: Byte;                        { the target index, 1..SpellTargetCount }
  Affect: Pointer;                { HasAffect's out pointer, the target's sleep affect }
begin
  SpellAppliedToArea := 1;
  SpellWorkByteA := RollDice(PoolDiceCount, PoolDiceSides);
  for I := 1 to SpellTargetCount do
  begin
    case SpellTargets[I]^.HighestLevel of
      0..1: SpellWorkByteB := CostLevel0;
      2: SpellWorkByteB := CostLevel2;
      3: SpellWorkByteB := CostLevel3;
      4: SpellWorkByteB := CostLevel4;
      5:
        if SpellTargets[I]^.Race = 0 then
          SpellWorkByteB := CostLevel5Small
        else
          SpellWorkByteB := CostLevel5Large;
    else
      SpellWorkByteB := CostLevel5Large;
    end;
    { QUIRK ovl22:15FE: the guard is written positive on purpose; the equivalent negative
      `(Status = Animated) or HasAffect(...) or (pool < cost)` then-drop-else-Dec form compiles with
      the two branches laid out the other way round (probe PRB26.PAS) and does not match. }
    if (SpellTargets[I]^.Status <> StatusAnimated) and not HasAffect(SpellTargets[I], SleepAffect, Affect) and
       (SpellWorkByteA >= SpellWorkByteB) then
      Dec(SpellWorkByteA, SpellWorkByteB)
    else
      SpellTargets[I] := nil;
  end;
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'falls asleep');
end;
{ ovl22:1658. Cast handler of spell 23, Hold Person (entry 27: InitSpellHandlers maps DS:6B84+23*4 to overlay
  stub 0096:00A7; SpellNames[23] is 'Hold Person' at DS:2C98): for every chosen target SpellTargets[I]
  it rolls a saving throw whose bonus shrinks as more targets were picked (one target -3, or -2 when
  the spell is Hold Person itself, two targets -1, three or four none), drawing a beam from the caster
  to every target but the first (SetSoundDriverIdle, PlaySound(SoundSpellDefault), the cast animation
  DrawCombatIcon($12) and the WalkCombatLine line), and applies the spell's own affect with the message
  'is held' through ApplyAffect. A target that is not a person (CreatureType above 1 or CombatSize
  above 1, as CastCharmPerson tests) is treated as having saved, and a nil target is skipped. Reads
  SpellTargetCount, SpellTargets, CastingSpell and SelectedCharacter. }
procedure CastHoldPerson;
const
  HoldPerson = $17;               { the spell whose lone target saves at -2 instead of -3 (spell 23) }
  { The saving-throw bonus by number of chosen targets (a negative bonus makes the save harder):
    fewer targets mean the spell is concentrated, so the single-target save is the hardest. }
  OneTargetBonus = -3;
  HoldPersonBonus = -2;
  TwoTargetsBonus = -1;
  ThreeOrFourBonus = 0;
  FriendlyType = CreatureHumanoid;               { the largest CreatureType Hold Person can affect (a person) }
  FriendlySize = 1;               { the largest CombatSize (combat footprint kind) it can affect }
  AnimationKind = $12;            { DrawCombatIcon's argument that starts the cast animation }
  AimStep = 4;                    { the line WalkCombatLine walks for the cast animation }
  AimWidth = $1E;
var
  Target: PCharacter;             { SpellTargets[I], the target this pass applies the spell to }
  Saved: Boolean;                 { whether the target saved (or is not a person) }
  I: Byte;                        { the target index, SpellTargetCount downto 1 }
  SaveBonus: ShortInt;            { the saving-throw bonus for this many targets }
begin
  case SpellTargetCount of
    1:
      if CastingSpell = HoldPerson then
        SaveBonus := HoldPersonBonus
      else
        SaveBonus := OneTargetBonus;
    2: SaveBonus := TwoTargetsBonus;
    3, 4: SaveBonus := ThreeOrFourBonus;
  end;
  for I := SpellTargetCount downto 1 do
    if SpellTargets[I] <> nil then
    begin
      Target := SpellTargets[I];
      if I < SpellTargetCount then
      begin
        SetSoundDriverIdle(SoundIdleOff);
        PlaySound(SoundSpellDefault);
        DrawCombatIcon(AnimationKind);
        WalkCombatLine(CombatantX(SelectedCharacter), CombatantY(SelectedCharacter),
          CombatantX(Target), CombatantY(Target), AimStep, AimWidth);
        SetSoundDriverIdle(SoundIdleDefault);
      end;
      Saved := SavingThrow(Target, SpellTable[CastingSpell].Pad2[9], SaveBonus);
      if (Target^.CreatureType > FriendlyType) or (Target^.CombatSize > FriendlySize) then
        Saved := True;
      ApplyAffect(Target, SpellTable[CastingSpell].AffectId, SpellAffectDuration(CastingSpell),
        SpellCasterLevel(CastingSpell), 0, SpellTable[CastingSpell].Pad2[8], Saved, 'is held');
    end;
end;
{ ovl22:17E9. Cast handler of spell 24, Resist Fire (entry 28: InitSpellHandlers maps DS:6B84+24*4 to overlay
  stub 0096:00AC; SpellNames[24] is 'Resist Fire' at DS:2CC1): applies the current spell CastingSpell to the
  chosen targets with the message 'is fire resistant' and no damage or flag of its own
  (ApplySpellToTargets; the spell's own affect does the work). One of the per-spell handlers in
  SpellHandlers (whitepaper 5.22.2). }
procedure CastResistFire;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'is fire resistant');
end;
{ ovl22:1822. Cast handler of spell 25, Silence, 15' Radius (entry 29: InitSpellHandlers maps DS:6B84+25*4 to
  overlay stub 0096:00B1; SpellNames[25] is "Silence, 15' Radius" at DS:2CEA): applies the current spell
  CastingSpell to the chosen targets with the message 'is silenced' and no damage or flag of its own
  (ApplySpellToTargets; the spell's own affect does the work). One of the per-spell handlers in
  SpellHandlers (whitepaper 5.22.2). }
procedure CastSilence;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'is silenced');
end;
{ ovl22:185B. Cast handler of spell 26, Slow Poison (entry 30: InitSpellHandlers maps DS:6B84+26*4 to overlay
  stub 0096:00B6; SpellNames[26] is 'Slow Poison' at DS:2D13). It needs the first chosen target FirstSpellTarget
  to not be Animated (Status is not 1, an undead) and to carry the Poisoned affect $37 (HasAffect);
  anything else is dropped (FirstSpellTarget := nil) and the cast does nothing. A poisoned target at 0 hit
  points is brought back to 1 (HpCurrent), the spell's own affect is applied to the targets
  ('is affected'), the revival affect's removal handler is run (CallAffectHandler($4E), which heals
  an unconscious character, ovl24 AffectRevival) and the poison-slowing affect $0F is added for $A
  units. Reads FirstSpellTarget and CastingSpell. }
procedure CastSlowPoison;
const
  PoisonedAffect = $37;           { the Poisoned affect the target must carry (ovl15 names $37 Poisoned) }
  { The revival affect whose removal handler heals an unconscious character (ovl24 AffectRevival). }
  RevivalAffect = $4E;
  ReviveHitPoints = 1;            { a poisoned character at 0 hit points is brought back to 1 }
  SlowPoisonAffect = $0F;         { the poison-slowing affect; Neutralize Poison removes it with the poison (ovl04) }
  SlowPoisonDuration = $A;        { the affect lasts ten units }
  SlowPoisonData = $FF;           { the affect's data byte }
  FullCasterLevel = $FF;          { ApplySpellToTargets uses this caster level instead of SpellCasterLevel }
var
  Affect: Pointer;                { HasAffect's out pointer, the target's Poisoned affect }
  Target: PCharacter;             { FirstSpellTarget, the first chosen target }
begin
  Target := FirstSpellTarget;
  if Target^.Status = StatusAnimated then
  begin
    FirstSpellTarget := nil;
    Exit;
  end;
  if HasAffect(Target, PoisonedAffect, Affect) then
  begin
    if Target^.HpCurrent = 0 then
      Target^.HpCurrent := ReviveHitPoints;
    ApplySpellToTargets(CastingSpell, FullCasterLevel, RunsHandlerOnRemove, 0, 0, 'is affected');
    CallAffectHandler(RevivalAffect, Target, nil, ModeRemove);
    AddAffect(Target, SlowPoisonAffect, SlowPoisonDuration, SlowPoisonData, RunsHandlerOnRemove);
  end;
end;
{ ovl22:190F. Cast handler of spell 27, Snake Charm (entry 31: InitSpellHandlers maps DS:6B84+27*4 to overlay
  stub 0096:00BB; SpellNames[27] is 'Snake Charm' at DS:2D3C). The caster's own current hit points
  (SelectedCharacter^.HpCurrent) become the pool SpellWorkByteA; it then walks the party list PartyListHead and, for
  every giant snake (CreatureType $E) whose hit points fit the remaining pool, subtracts them, counts
  it in SpellTargetCount and adds it to the chosen targets SpellTargets. The spell's own affect is then applied to the
  charmed snakes with the message 'is charmed'. Reads SelectedCharacter, PartyListHead and CastingSpell; changes
  SpellWorkByteA, SpellTargetCount and the target list. }
procedure CastSnakeCharm;
var
  Current: PCharacter;            { the walker of the party list PartyListHead }
begin
  SpellWorkByteA := SelectedCharacter^.HpCurrent;
  SpellTargetCount := 0;
  Current := PCharacter(PartyListHead);
  while Current <> nil do
  begin
    if (Current^.CreatureType = CreatureSnake) and (SpellWorkByteA >= Current^.HpCurrent) then
    begin
      SpellWorkByteA := SpellWorkByteA - Current^.HpCurrent;
      Inc(SpellTargetCount);
      SpellTargets[SpellTargetCount] := Current;
    end;
    Current := Current^.Next;
  end;
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'is charmed');
end;
{ ovl22:19C3 (e32). Cast handler of spell 28, Spiritual Hammer (SpellHandlers[28]: InitSpellHandlers maps
  DS:6B84+28*4 to overlay stub 0096:00C0; SpellNames[28] is 'Spiritual Hammer' at DS:2D65, the
  spell's own affect is $17). It applies the current spell CastingSpell to the chosen targets with no
  message of its own and the affect set to run its handler on removal (ApplySpellToTargets, Flag 1),
  then runs the handler of affect $17 on the first chosen target FirstSpellTarget (CallAffectHandler, mode 0),
  which is the spell's hammer. Reads CastingSpell and FirstSpellTarget. }
procedure CastSpiritualHammer;
const
  SpiritualHammerAffect = $17;    { the spell's own affect (SpellTable[28].AffectId): its handler is run here }
begin
  ApplySpellToTargets(CastingSpell, 0, RunsHandlerOnRemove, 0, 0, '');
  CallAffectHandler(SpiritualHammerAffect, FirstSpellTarget, nil, ModeApply);
end;
{ ovl22:1A16 (e33). Cast handler of spell 30, Invisibility (SpellHandlers[30]: InitSpellHandlers maps
  DS:6B84+30*4 to overlay stub 0096:00C5; SpellNames[30] is 'Invisibility' at DS:2DB7, its
  SpellTable affect byte is $19). It only applies the current spell CastingSpell to the chosen targets with
  the message 'is invisible'; the spell's own affect $19 does the hiding, so the handler has nothing
  else to do. Reads CastingSpell. }
procedure CastInvisibility;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'is invisible');
end;
{ ovl22:1A4F (e34). Cast handler of spell 31, Knock (SpellHandlers[31]: InitSpellHandlers maps
  DS:6B84+31*4 to overlay stub 0096:00CA; SpellNames[31] is 'Knock' at DS:2DE0). It only applies
  the current spell CastingSpell to the chosen targets with the message 'Knock-Knock'; Knock's SpellTable
  affect byte is 0, so no affect is applied here. The door effect lives elsewhere: ovl14's wilderness
  door code looks for Knock among the memorized spells. Reads CastingSpell. }
procedure CastKnock;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'Knock-Knock');
end;
{ ovl22:1A8A (e35). Cast handler of spell 32, Mirror Image (SpellHandlers[32]: InitSpellHandlers maps
  DS:6B84+32*4 to overlay stub 0096:00CF; SpellNames[32] is 'Mirror Image' at DS:2E09). It applies
  the current spell CastingSpell to the chosen targets with the message 'is duplicated' and the caster
  level set to 1d4 (RollDice(1, 4)); that roll is the number of images and becomes the affect's
  Data. Reads CastingSpell. }
procedure CastMirrorImage;
const
  ImagesCount = 1;                { the images are 1d4 (RollDice(Count, Sides)) }
  ImagesSides = 4;
begin
  ApplySpellToTargets(CastingSpell, RollDice(ImagesCount, ImagesSides), 0, 0, 0, 'is duplicated');
end;
{ ovl22:1ACC (e36). Cast handler of spell 33, Ray of Enfeeblement (SpellHandlers[33]: InitSpellHandlers maps
  DS:6B84+33*4 to overlay stub 0096:00D4; SpellNames[33] is 'Ray of Enfeeblement' at DS:2E32). It
  only applies the current spell CastingSpell to the chosen targets with the message 'is weakened'; the
  spell's own affect lowers the target's strength, so the handler has nothing else to do. Reads
  CastingSpell. }
procedure CastRayOfEnfeeblement;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'is weakened');
end;
{ ovl22:1B11 (e37). Cast handler of spell 34, Stinking Cloud (SpellHandlers[34]: InitSpellHandlers maps
  DS:6B84+34*4 to overlay stub 0096:00D9; SpellNames[34] is 'Stinking Cloud' at DS:2E5B). It leaves
  a marker in the list CloudList (a list of $13-byte TCombatNode records) for the aim point SpellAimX/
  SpellAimY: the caster, the aim cell, and for each of the four aim directions (SpellNamesPrefix.AimDirs,
  DS:290E) the tile it found around the aim cell, whether the cell may hold the cloud, and the cloud's
  own affect $28 with the caster level. A cell whose tile is $1E (the cloud tile) borrows the tile of
  an earlier cloud marker that already reaches it; a cell whose tile is $1F (a body on the map)
  borrows the body's tile there (BodyTable). The cloud cell itself is painted into the combat map, the
  cast is announced ('Creates a noxious cloud'), the cursor is moved to the aim point and the cloud
  affect runs on every combatant in the four cells (ApplyCloudTile). Reads CastingSpell, SpellAimX/SpellAimY,
  CloudList, SelectedCharacter, BodyCount, BodyTable, CombatTiles, CombatMap and CombatantRecord; changes
  SpellAppliedToArea, CloudList, the combat map and the affects of the targets. }
procedure CastStinkingCloud;
const
  CloudAffect = $28;              { the affect the cast leaves on the caster and his clouds }
  { The cloud count goes into the affect's data in bits 4..7 (Count * CloudCountScale). }
  CloudCountScale = 16;
  RefusedTileCost = $FF;          { a combat tile cost this high refuses the cell (TCombatTile.Cost) }
  AimCursorMargin = $FF;          { the margin MoveCombatCursor centres the view with }
  AimCursorDir = 8;               { the omni direction MoveCombatCursor steps in (DirStepX/DirStepY) }
  MessageColor = $A;             { the colour ShowCharacterMessage shows the message in }
var
  Cloud: PCombatNode;             { the walker of the CloudList cloud list }
  Node: PCombatNode;              { the cloud marker this cast fills }
  Occupant: array[1..4] of Byte;  { the combatant standing in each aim cell (GetMapCell's out) }
  J: Byte;                        { the aim direction or the body index being looked at }
  Count: Byte;                    { how many cloud markers the caster already had }
  Tile: Byte;                     { the tile GetMapCell found, or one the scan borrows }
  Level: Byte;                    { the caster level, SpellCasterLevel(CastingSpell) }
  I: Byte;                        { the aim direction index, 1..4 }
  Dir: Byte;                      { the compass direction of aim direction I (SpellNamesPrefix.AimDirs) }
begin
  SpellAppliedToArea := 1;
  Level := SpellCasterLevel(CastingSpell);
  Count := 0;
  Node := CloudList;
  if CloudList = nil then
  begin
    GetMem(CloudList, SizeOf(TCombatNode));
    Node := CloudList;
  end
  else
  begin
    while Node^.Next <> nil do
    begin
      if Node^.Owner = SelectedCharacter then
        Inc(Count);
      Node := Node^.Next;
    end;
    GetMem(Node^.Next, SizeOf(TCombatNode));
    Node := Node^.Next;
  end;
  FillChar(Node^, SizeOf(TCombatNode), 0);
  AddAffect(SelectedCharacter, CloudAffect, Level, Level + Count * CloudCountScale, 1);
  Node^.Owner := SelectedCharacter;
  Node^.Kind := Count;
  Node^.X := SpellAimX;
  Node^.Y := SpellAimY;
  for I := 1 to 4 do
  begin
    Dir := SpellNamesPrefix.AimDirs[I];
    GetMapCell(SpellAimX + DirStepX[Dir], SpellAimY + DirStepY[Dir], Occupant[I], Tile);
    if (Tile > 0) and (CombatTiles[Tile].Cost < RefusedTileCost) then
      Node^.Arms[I] := 1
    else
      Node^.Arms[I] := 0;
    if Tile = CloudTile then
    begin
      Cloud := CloudList;
      while Cloud <> nil do
      begin
        if Cloud <> Node then
          for J := 1 to 4 do
            if Cloud^.Arms[J] <> 0 then
              if (Cloud^.X + DirStepX[SpellNamesPrefix.AimDirs[J]] = SpellAimX + DirStepX[Dir]) and
                 (Cloud^.Y + DirStepY[SpellNamesPrefix.AimDirs[J]] = SpellAimY + DirStepY[Dir]) and
                 (Cloud^.Tiles[J] <> CloudTile) then
                Tile := Cloud^.Tiles[J];
        Cloud := Cloud^.Next;
      end;
    end
    else if Tile = BodyTile then
      for J := 1 to BodyCount do
        if (BodyTable[J].X = SpellAimX + DirStepX[Dir]) and
           (BodyTable[J].Y = SpellAimY + DirStepY[Dir]) then
          Tile := BodyTable[J].Tile;
    Node^.Tiles[I] := Tile;
    if Node^.Arms[I] <> 0 then
      CombatMap^.Cells[SpellAimY + DirStepY[Dir], SpellAimX + DirStepX[Dir]] := CloudTile;
  end;
  ShowCharacterMessage(SelectedCharacter, 'Creates a noxious cloud', MessageColor, False);
  MoveCombatCursor(SpellAimX, SpellAimY, AimCursorMargin, AimCursorDir);
  DelayByGameSpeed;
  ClearCharacterMessage;
  for I := 1 to 4 do
    if Occupant[I] > 0 then
      ApplyCloudTile(CombatantRecord[Occupant[I]]);
end;
{ ovl22:1F41. Cast handler that raises the chosen target FirstSpellTarget's Strength (the Strength spell):
  it rolls the class bonus die (1d4 for a magic-user level, 1d6 for a cleric or thief level, 1d8
  for a fighter level; the later class wins) and adds it to the target's Strength. A result above
  18 is clamped to 18; for a fighter level the overflow becomes the exceptional-strength percentile
  (10 per point above 18 plus the target's StrengthPercent, capped at 100). RaiseStrength applies the
  new Strength (showing 'is stronger' when it rose) and the strength affect $26 is added for the
  spell's duration. Reads FirstSpellTarget and CastingSpell. }
procedure CastStrength;
const
  MaxPercent = 100;               { the exceptional-strength percentile ceiling }
  PercentStep = 10;               { each point of Strength above 18 is 10 percent }
  StrengthAffect = $26;           { the strength affect this spell leaves (same vehicle RaiseStrength updates) }
  { The class whose level picks the bonus die: magic-user (d4), cleric or thief (d6), fighter (d8). }
  MagicUserClass = 5;
  { The bonus die by class. }
  MagicUserSides = 4;
  ClericSides = 6;
  FighterSides = 8;
  MessageColor = $A;             { the colour ShowCharacterMessage shows 'is stronger' in }
var
  Target: PCharacter;             { FirstSpellTarget, the chosen target whose Strength is raised }
  Percent: Byte;                  { the exceptional-strength percentile passed to RaiseStrength }
  Bonus: Byte;                    { the class bonus die roll (unset when the target has no class: QUIRK ovl22:1F47) }
  Strength: Byte;                 { the new Strength, the sum of the target's Strength and the roll }
  Code: Byte;                     { RaiseStrength's earlier-strength code, passed to AddAffect as Data }
begin
  Percent := 0;
  Target := FirstSpellTarget;
  if Target^.ClassLevels[MagicUserClass] > 0 then
    Bonus := RollDice(1, MagicUserSides);
  if (Target^.ClassLevels[ClassCleric] > 0) or (Target^.ClassLevels[ClassThief] > 0) then
    Bonus := RollDice(1, ClericSides);
  if Target^.ClassLevels[ClassFighter] > 0 then
    Bonus := RollDice(1, FighterSides);
  Strength := Target^.Strength + Bonus;
  { QUIRK ovl22:1FFB: the cap is repeated in both branches (Strength 18 in each); the compiler keeps
    one store per branch instead of hoisting it, which is the original's layout. }
  if Strength > ExceptionalStrength then
  begin
    if Target^.ClassLevels[ClassFighter] > 0 then
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
    ShowCharacterMessage(Target, 'is stronger', MessageColor, TimedMessage);
  AddAffect(Target, StrengthAffect, SpellAffectDuration(CastingSpell), Code, RunsHandlerOnRemove);
end;
{ ovl22:206F. Cast handler of spell 36, Animate Dead: for up to the caster level corpses still in the
  party list PartyListHead (Status 6, CreatureType 0) it places the body on the combat map at its own cell
  (PlaceCombatant) and turns it into an undead creature under the caster's side: CreatureType 4, Quick
  set, the memorized spells, the AI state and the combat target cleared, B84 $B2 when it was already a
  computer-run member (above $7F) else $B3, and Side copied from SelectedCharacter. The corpse is then
  revived (ReviveCombatant at HpMax) and, on success, carries the animate affect $20 (Data: the caster's
  Side in bits 4..7 plus the caster level) with the message 'is animated'. Reads CastingSpell, PartyListHead,
  SelectedCharacter and ViewMode; changes SpellAppliedToArea, SpellTargetCount and the corpse records. }
procedure CastAnimateDead;
const
  DeadStatus = 6;                 { TCharacter.Status 6: a corpse Animate Dead can raise }
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
  AnimatedMark = 2;               { the byte at +$76 Animate Dead sets (ScoreItem reads it, ovl09:128D) }
  NoSaveNegates = 0;              { ApplyAffect SaveNegates }
  NotSaved = False;               { ApplyAffect Saved }
  RestoreCell = 1;                { PlaceCombatant Restore }
var
  I: Byte;                        { the spell slot index, 0..$14 }
  SaveData: Byte;                 { the affect data: the caster's Side in bits 4..7 plus the level }
  Level: Byte;                    { the caster level, one corpse per level, counted down }
  Current: PCharacter;            { the walker of the party list PartyListHead }
begin
  SpellAppliedToArea := 1;
  Level := SpellCasterLevel(CastingSpell);
  SpellTargetCount := 0;
  Current := PCharacter(PartyListHead);
  while (Current <> nil) and (Level > 0) do
  begin
    if Current^.Status = DeadStatus then
      if Current^.CreatureType = CreatureHuman then
        if PlaceCombatant(Current, CombatantX(Current), CombatantY(Current), RestoreCell) then
        begin
          { The caster's Side goes into bits 4..7 of the affect data, the caster level into the low
            nibble (QUIRK ovl22:2105: the original sign-extends Side with cwde, so it is treated as a
            ShortInt here even though TCharacter.Side is a Byte). }
          SaveData := ShortInt(Current^.Side) * SideScale + SpellCasterLevel(CastingSpell);
          Current^.Side := SelectedCharacter^.Side;
          Current^.Quick := 1;
          Current^.Pad74[$76] := AnimatedMark;
          Current^.SweepAttacks := 0;
          Current^.BaseMovement := 6;
          for I := 0 to MaxSpellSlot do
            Current^.Spells[I] := 0;
          if Current^.B84 > AiThreshold then
            Current^.B84 := HirelingMorale
          else
            Current^.B84 := CreatureMorale;
          Current^.CreatureType := CreatureUndead;
          if ViewMode = ViewModeCombat then
            Current^.Combat^.Target := nil;
          Dec(Level);
          if ReviveCombatant(Current, Current^.HpMax) then
          begin
            ApplyAffect(Current, AnimateAffect, 0, SaveData, RunsHandlerOnRemove, NoSaveNegates,
              NotSaved, 'is animated');
            Current^.Status := 1;
          end;
        end;
    Current := Current^.Next;
  end;
end;
{ ovl22:2217. Cast handler of spell 37, Cure Blindness (SpellTable[37].AffectId is 0): removes the
  blindness affect $21 that spell 38 Cause Blindness leaves (SpellTable[38].AffectId) from the first
  chosen target FirstSpellTarget (CureAffect) and, only when the target actually carried it, tells 'can see'
  through ShowHitMessage. Reads FirstSpellTarget. }
procedure CastCureBlindness;
const
  BlindnessAffect = $21;          { the blindness affect CureAffect removes; spell 38 Cause Blindness leaves it }
  ShowAbout = 1;                  { ShowHitMessage's Flag argument }
begin
  if CureAffect(FirstSpellTarget, BlindnessAffect) then
    ShowHitMessage(FirstSpellTarget, ShowAbout, 'can see');
end;
{ ovl22:225D. Cast handler of spell 38, Cause Blindness (SpellHandlers[38]: InitSpellHandlers maps
  DS:6B84+38*4 to overlay stub 0096:00ED; SpellNames[38] is 'Cause Blindness' at DS:2EFF). It only
  applies the current spell CastingSpell to the chosen targets with the message 'is blind'; the spell's own
  affect $21 does the blinding (the affect Cure Blindness removes, ovl22:2217), so the handler has
  nothing else to do. Reads CastingSpell. }
procedure CastCauseBlindness;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'is blind');
end;
{ ovl22:228A. Cures the six disease affects of the Temple (DiseaseAffects[1..6] at DS:0114: $1F,
  $22, $2B, $2C, $32, $39) from the chosen target FirstSpellTarget and returns whether it cured any: it cures
  the $22 spell affect on its own, and curing $2B clears its companions $2C (Cause Disease) and $1F
  (Helpless) too, while curing $32 (Dreaded Mummy Disease) clears $39. RemovingAffects is set while the
  affects go so the removal does not trigger the Temple's own cure. Called by CastCureDisease (spell 39,
  Cure Disease) and CastMonsterHeal. }
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
  RemovingAffects := 1;
  if CureAffect(FirstSpellTarget, DiseaseAffectCured) then
    CureDiseaseAffects := True;
  if CureAffect(FirstSpellTarget, DiseaseAffectCause) then
  begin
    CureDiseaseAffects := True;
    RemoveAffect(FirstSpellTarget, DiseaseAffectCauseDisease, nil);
    RemoveAffect(FirstSpellTarget, DiseaseAffectHelpless, nil);
  end;
  if CureAffect(FirstSpellTarget, DiseaseAffectMummy) then
  begin
    CureDiseaseAffects := True;
    RemoveAffect(FirstSpellTarget, DiseaseAffectMummyCleared, nil);
  end;
  RemovingAffects := 0;
end;
{ ovl22:232F. Cast handler of spell 39, Cure Disease (SpellHandlers[39]: InitSpellHandlers maps
  DS:6B84+39*4 to overlay stub 0096:00F2; SpellNames[39] is 'Cure Disease' at DS:2F28). It calls
  CureDiseaseAffects to cure the chosen target FirstSpellTarget and stores the result in a local it never
  reads, so the cure happens through that call alone (SpellHandlers is a table of procedures and
  takes no result). QUIRK ovl22:232F: the Boolean local Cured is written and never read. }
procedure CastCureDisease;
var
  Cured: Boolean;
begin
  Cured := CureDiseaseAffects;
end;
{ ovl22:234C. Cast handler of spell 40, Cause Disease (SpellHandlers[40]: InitSpellHandlers maps
  DS:6B84+40*4 to overlay stub 0096:00F7; SpellNames[40] is 'Cause Disease' at DS:2F51). It applies
  the current spell CastingSpell to the chosen targets with the message 'is diseased' and no damage of its
  own, but with Flag 1 so the spell's affect runs its handler when it is removed (the affect the
  Temple's Cure Disease and CureDiseaseAffects clear). Reads CastingSpell. }
procedure CastCauseDisease;
begin
  ApplySpellToTargets(CastingSpell, 0, RunsHandlerOnRemove, 0, 0, 'is diseased');
end;
{ ovl22:2385 (e44). Cast handler of spells 41 and 46, Dispel Magic (InitSpellHandlers maps both
  DS:6B84+41*4 and DS:6B84+46*4 to overlay stub 0096:00FC; SpellNames[41] and SpellNames[46] are
  both 'Dispel Magic' at DS:2F7A and DS:3047). It tries to dispel the affects of the chosen target
  FirstSpellTarget: for every affect of the target's list whose Data byte is below $FF it takes the effect's
  level from the low nibble of Data, turns the caster level (SpellCasterLevel(CastingSpell)) and that level
  into a chance (50 percent, +5 for each level the caster is above the effect, -2 for each level
  below), and rolls 1d100: a roll up to that chance removes the affect (RemoveAffect) and, when
  anything was removed, the target is told 'is affected' (ShowHitMessage). SpellAppliedToArea marks the cast.
  QUIRK ovl22:2385: the outer loop runs SpellTargetCount times but the body always reads the same first target
  FirstSpellTarget (it is never indexed by the loop counter), so a cast with several targets rolls on the
  first one once per target and can show 'is affected' more than once. Reads CastingSpell, SpellTargetCount, FirstSpellTarget;
  changes SpellAppliedToArea, SpellWorkByteA, SpellWorkByteB and the target's affect list. }
procedure CastDispelMagic;
const
  MaxAffectData = $FF;            { an affect whose Data byte is this high is left alone }
  LevelMask = $0F;                { the effect's level is the low nibble of the affect's Data byte }
  BaseChance = $32;               { 50 percent, the base Dispel Magic chance }
  LevelStep = 5;                  { +5 percent for each caster level above the effect's level }
  LevelPenalty = 2;               { -2 percent for each caster level below it }
  DiceSides = 100;                { the chance is rolled on 1d100 }
  ShowAbout = 1;                  { ShowHitMessage's Flag argument }
var
  I: Byte;                        { the outer loop counter, 1..SpellTargetCount }
  Level: Byte;                    { the caster level, SpellCasterLevel(CastingSpell) }
  Target: PCharacter;             { the chosen target FirstSpellTarget whose affects are dispelled }
  Dispelled: Boolean;             { whether this pass removed any affect }
  Affect: PAffect;                { the walker of Target's affect list }
  Next: PAffect;                  { the affect's successor, kept before a removal }
begin
  SpellAppliedToArea := 1;
  Level := SpellCasterLevel(CastingSpell);
  for I := 1 to SpellTargetCount do
  begin
    Dispelled := False;
    Target := FirstSpellTarget;
    Affect := PAffect(Target^.Affects);
    while Affect <> nil do
    begin
      Next := Affect^.Next;
      if Affect^.Data < MaxAffectData then
      begin
        SpellWorkByteB := Affect^.Data and LevelMask;
        if Level > SpellWorkByteB then
          SpellWorkByteA := (Level - SpellWorkByteB) * LevelStep + BaseChance
        else if Level < SpellWorkByteB then
          SpellWorkByteA := BaseChance - (SpellWorkByteB - Level) * LevelPenalty
        else
          SpellWorkByteA := BaseChance;
        if RollDice(1, DiceSides) <= SpellWorkByteA then
        begin
          RemoveAffect(Target, Affect^.Id, Affect);
          Dispelled := True;
        end;
      end;
      Affect := Next;
    end;
    if Dispelled then
      ShowHitMessage(Target, ShowAbout, 'is affected');
  end;
end;
{ ovl22:24D6 (e45). Cast handler of spell 42, Prayer (InitSpellHandlers maps DS:6B84+42*4 to overlay stub
  0096:0101; SpellNames[42] is 'Prayer'). It applies the current spell CastingSpell to the chosen targets
  with no flag, damage or kind of its own and the message 'is praying'; the caster level it passes as
  the affect's Data is the caster level (SpellCasterLevel(CastingSpell)) plus the caster's Side scaled by 16, so
  the affect's handler can tell whose side the prayer favours (the same Side-in-the-data trick as
  Charm Person and Animate Dead). Reads CastingSpell and SelectedCharacter; changes the targets' affects. }
procedure CastPrayer;
const
  { The caster's Side goes above the caster level in the affect's data (Side * SideScale). Written as
    a multiply, not `shl 4`: TP 6.0 compiles `X * 16` to `mov cl,4; shl ax,cl` but `X shl 4` to
    `mov cx,4; shl ax,cl` (probe PRB27.PAS). }
  SideScale = 16;
begin
  { QUIRK ovl22:24F1: the original sign-extends Side with cwde, so it is read as a ShortInt even
    though TCharacter.Side is a Byte. }
  ApplySpellToTargets(CastingSpell, SpellCasterLevel(CastingSpell) + ShortInt(SelectedCharacter^.Side) * SideScale,
    0, 0, 0, 'is praying');
end;
{ ovl22:2540 (e9). Cast handler of spell 43, Remove Curse, and the routine the Temple's Remove
  Curse service calls (InitSpellHandlers maps DS:6B84+43*4 to overlay stub 0096:007E; SpellNames[43] is
  'Remove Curse' at DS:2FCC; the Temple's RemoveCurse ovl04:083A stores the character in FirstSpellTarget and
  calls this). It first tries to cure the curse affect $24 from the character FirstSpellTarget and, when it was
  there, says 'is un-cursed' (ShowHitMessage). Otherwise it walks the character's carried items
  (FirstSpellTarget^.Items, the list at +$C8) and clears the Cursed flag (+$36) of the first cursed item it
  finds, saying ''s item is un-cursed'. Reads FirstSpellTarget; changes the character's affects and its items. }
procedure CastRemoveCurse;
const
  ShowAbout = 1;                  { ShowHitMessage's Flag argument }
var
  Item: PItem;                    { the walker of the character's carried items }
  UnCursed: Boolean;              { whether a cursed item was found and cleared }
begin
  if CureAffect(FirstSpellTarget, AffectBestowCurse) then
    ShowHitMessage(FirstSpellTarget, ShowAbout, 'is un-cursed')
  else
  begin
    UnCursed := False;
    Item := FirstSpellTarget^.Items;
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
      ShowHitMessage(FirstSpellTarget, ShowAbout, '''s item is un-cursed');
  end;
end;
{ ovl22:2604. Cast handler of spell 44, Bestow Curse (InitSpellHandlers maps DS:6B84+44*4 to overlay
  stub 0096:0106; SpellNames[44] is 'Bestow Curse' at DS:2FF5 and SpellTable[44].AffectId is the curse
  affect $24). It only applies the current spell CastingSpell to the chosen targets with the message
  'has been cursed!'; the spell's own affect does the cursing, so the handler has nothing else to do.
  Reads CastingSpell. }
procedure CastBestowCurse;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'has been cursed!');
end;
{ ovl22:263D. Cast handler of spell 45, Blink (InitSpellHandlers maps DS:6B84+45*4 to overlay stub 0096:010B;
  SpellNames[45] is 'Blink' at DS:301E and SpellTable[45].AffectId is the blink affect $25). It only
  applies the current spell CastingSpell to the chosen targets with the message 'is blinking'; the spell's
  own affect does the blinking, so the handler has nothing else to do. Reads CastingSpell. }
procedure CastBlink;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'is blinking');
end;
{ ovl22:266B. Cast handler of spells 47 and 64, Fireball (InitSpellHandlers maps both DS:6B84+47*4 and
  DS:6B84+64*4 to overlay stub 0096:0110; SpellNames[47] is 'Fireball', and spell 64 has an empty
  name, a monster's fireball). It sets SpellAppliedToArea and takes the caster level from SpellCasterLevel (the
  spell's d6-per-level damage) except for the monster's spell 64, whose level is the roll 1d3*2+1.
  When the 3D wall view is off (GameVars^[VarForceWallView] = 0) it collects into SpellTargets[1..SpellTargetCount]
  the combatants ScanTargets finds within two steps of the aim point SpellAimX/SpellAimY; it then moves
  the combat cursor onto the aim point and applies the spell to the targets with RollDiceCounted
  (the d6 per level), fire damage and no message. Called through SpellHandlers[47] and [64]. }
procedure CastFireball;
const
  MonsterFireball = $40;          { spell 64, the monster's fireball sharing this handler with spell 47 }
  LevelDiceCount = 1;             { the monster's level is 1d3 * 2 + 1: 3, 5 or 7 }
  LevelDiceSides = 3;
  LevelScale = 2;
  ScanSteps = 2;                  { ScanTargets' MaxSteps around the aim point }
  FootprintBase = 1;              { ScanTargets' Base: the FootprintCell neighbour base }
  DamageDiceSides = 6;            { one d6 per caster level }
  DamageKindFire = 9;             { DealDamage classifies kind 9 as fire (ovl24:1389) }
  AimCursorMargin = 0;            { MoveCombatCursor's Margin }
  AimCursorDir = 8;               { MoveCombatCursor's omni direction }
var
  Level: Byte;                    { the caster level, or the monster's rolled one }
  I: Byte;                        { the target index, 1..SortEntries[0].Val }
begin
  SpellAppliedToArea := 1;
  if CastingSpell = MonsterFireball then
    Level := RollDice(LevelDiceCount, LevelDiceSides) * LevelScale + 1
  else
    Level := SpellCasterLevel(CastingSpell);
  if GameVars^[VarForceWallView] = 0 then
  begin
    ScanTargets(SpellAimX, SpellAimY, ScanSteps, OmniDir, FootprintBase, CombatMap);
    for I := 1 to SortEntries[0].Val do
      SpellTargets[I] := CombatantRecord[SortEntries[I].Head];
    SpellTargetCount := SortEntries[0].Val;
  end;
  MoveCombatCursor(SpellAimX, SpellAimY, AimCursorMargin, AimCursorDir);
  ApplySpellToTargets(CastingSpell, 0, 0, RollDiceCounted(Level, DamageDiceSides), DamageKindFire, '');
end;
{ ovl22:2764. Applies the current spell CastingSpell to up to the caster level (SpellCasterLevel) of the
  chosen targets SpellTargets[1..SpellTargetCount] that stand on Side, after removing from them the counter-affect
  Affect: a target on Side with budget left spends one point of the level and, if it already carries
  Affect, has it cured and is dropped, so the surviving targets are the ones the spell then affects.
  It sets SpellAppliedToArea, applies the spell through ApplySpellToTargets with Message, and finally runs the
  affect hooks $12 on each surviving target. Called by CastHaste (ovl22:2892) and the Slow handler
  (ovl22:2C09). Haste passes the slow affect $2A, Slow the haste affect $27 (the two
  spells' SpellTable affect ids), so each removes the opposite spell from the side before it casts. }
procedure ApplySpellToSideUpToLevel(Affect, Side: Byte; Message: String40);
const
  AffectHooks = $12;              { RunAffectHooks' kind for the affect this handler leaves }
var
  Level: Byte;                    { the caster level, the number of targets the spell may reach }
  I: Byte;                        { the target index, 1..SpellTargetCount }
begin
  SpellAppliedToArea := 1;
  Level := SpellCasterLevel(CastingSpell);
  for I := 1 to SpellTargetCount do
    if (SpellTargets[I]^.Side = Side) and (Level > 0) then
    begin
      Dec(Level);
      if CureAffect(SpellTargets[I], Affect) then
        SpellTargets[I] := nil;
    end
    else
      SpellTargets[I] := nil;
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, Message);
  for I := 1 to SpellTargetCount do
    if SpellTargets[I] <> nil then
      RunAffectHooks(AffectHooks, SpellTargets[I]);
end;
{ ovl22:2892. Cast handler of spell 48, Haste (InitSpellHandlers maps DS:6B84+48*4 to overlay stub
  0096:0115; SpellNames[48] is 'Haste' and SpellTable[48].AffectId is the haste affect $27). It hands
  the caster's own side and the slow affect $2A (SpellTable[55].AffectId) to ApplySpellToSideUpToLevel,
  which cures Slow from up to caster-level members of the side and then applies Haste to the rest with
  'is Hasted'. One of the per-spell handlers in SpellHandlers (SpellHandlers[48]). }
procedure CastHaste;
const
  SlowAffect = $2A;               { the slow affect Haste removes from the caster's side (spell 55) }
begin
  ApplySpellToSideUpToLevel(SlowAffect, SelectedCharacter^.Side, 'is Hasted');
end;
{ ovl22:28BC. One cell of a line spell's beam: it reads the cell (CellX, CellY) through GetMapCell
  and reports in Blocked whether the tile refuses the beam (Tile > 0 with a CombatTiles cost of $FF,
  the impassable cost). When a combatant stands in the cell (Occupant > 0) it deals Damage to it with
  the spell's saving throw (SavingThrow with SaveKind and no bonus; the damage is halved on a save,
  DealDamage's SaveEffect 2) as electrical damage (DamageKind $0C) and plays the zap animation
  DrawCombatIcon($13). Called by the line-area helpers (CastLineBeam and its callers, the Lightning
  Bolt handler CastLightningBolt among them). }
procedure DamageTargetInCell(CellX, CellY, Damage, SaveKind: Byte; var Blocked: Boolean);
const
  RefusedTileCost = $FF;          { TCombatTile.Cost this high refuses the cell (CastStinkingCloud names it) }
  DamageKindElectric = $0C;       { DealDamage: kind and $F7 = 4 names electricity (ovl24:1389) }
  ZapAnimation = $13;             { DrawCombatIcon's argument for the line spell's zap animation }
  NoBonus = 0;                    { SavingThrow's Bonus: the line spell gives none }
var
  Target: PCharacter;             { the combatant standing in the cell }
  Occupant: Byte;                 { GetMapCell's out: the combatant index in the cell, 0 for none }
  Tile: Byte;                     { GetMapCell's out: the cell's tile id, 0 off the map }
  { QUIRK ovl22:28BF: the original frame reserves two bytes no instruction reads (sub sp, 8 with
    only six bytes of locals in use); the original declared one more local, kept here so the frame
    lands where it did. }
  Unused: Boolean;
begin
  Blocked := False;
  GetMapCell(CellX, CellY, Occupant, Tile);
  if (Tile > 0) and (CombatTiles[Tile].Cost = RefusedTileCost) then
    Blocked := True;
  if Occupant > 0 then
  begin
    Target := CombatantRecord[Occupant];
    DamageKind := DamageKindElectric;
    DealDamage(Target, Damage, HalfOnSave, SavingThrow(Target, SaveKind, NoBonus));
    DrawCombatIcon(ZapAnimation);
    DamageKind := 0;
  end;
end;
{ ovl22:295B. The line-beam helper of the line spells: it draws the beam of the Lightning Bolt handler
  CastLightningBolt and of the monster beams (CastMonsterBeam, the dragon breath MonsterBreath) and damages every combatant it
  passes. It starts at the aim cell SpellAimX/SpellAimY (playing the zap animation DrawCombatIcon($13)) and
  walks a line away from the caster with a budget of Range * 2 (a TLineState filled by SetupLine and
  advanced by StepLine, whose First counter grows by 2 for a straight step and 3 for a diagonal one, so
  the budget is in half squares); it draws each step through WalkCombatLine and deals Damage (electrical, SavingThrow kind
  SaveKind) through DamageTargetInCell. The walk stops at the end of the line, when the line leaves the
  map (Tile 0), at a tile whose CombatTiles cost is above MaxPassableCost, or when the occupant of the
  cell changes (a fresh combatant, so the beam does not pass through bodies). When Blocked (the tile
  refused the beam), it moves the aim cell to the wall and turns the beam around (DirSign flips): this
  happens at every wall, whatever Bounce says. Bounce only matters at the first wall: when it is set
  and that wall is close to the caster (a line from the wall back to the caster ends with First at most
  8), the beam loses 8 half squares of its budget (Inc(Line.First, 8)); then Bounce clears. The budget
  also loses Line.First after every stop, and First counts from the start of the line, so a stop on a
  body charges the distance walked so far again. Sets SpellAppliedToArea.
  Parameters: Range the spell's reach (a budget of Range * 2 half squares); Damage the damage dealt per
  cell; SaveKind the SavingThrow kind; Bounce nonzero shortens the beam when the first wall it meets is
  near the caster. Earlier notes read this flag as "bounce once"; the turn (ovl22:2B71) is outside
  its test. Globals:
  SpellAimX/SpellAimY (the aim cell, moved to the bounce point), SpellAppliedToArea, SelectedCharacter and CombatTiles.
  Called by CastLightningBolt (Lightning Bolt), CastMonsterBeam and MonsterBreath (the dragon breath). }
procedure CastLineBeam(Range, Damage, SaveKind, Bounce: Byte);
const
  LineStep = 4;                   { WalkCombatLine's step: it walks the beam line in steps of 4 }
  LineWidth = $32;                { WalkCombatLine's width for the beam line }
  MaxPassableCost = 1;            { a tile the beam passes through has a CombatTiles cost at most this }
  BounceFirstLimit = 8;           { the bounce line's First step counter must be at most this to count }
  BounceExtraSteps = 8;           { half squares the beam loses at a near first wall (Line.First is advanced by 8) }
  ZapAnimation = $13;             { DrawCombatIcon's argument that plays the zap animation (as DamageTargetInCell) }
var
  Line, Line2: TLineState;        { the walked beam line and the line back to the caster at a bounce }
  CasterX, CasterY: ShortInt;     { the caster's cell (CombatantX/Y of SelectedCharacter) }
  StartX, StartY: Byte;           { the cell the current step of the beam starts from, for WalkCombatLine }
  DirSign: ShortInt;              { +1 or -1: whether the beam goes away from the caster or back to it }
  Blocked, StepDone: Boolean;     { the cell refused the beam; StepLine advanced the line }
  Bouncing: Byte;                 { the Bounce flag, cleared at the first wall (the beam turns at every wall) }
  PrevOccupant: Byte;             { the occupant of the previous cell, to stop at a fresh combatant }
  Occupant, Tile: Byte;           { GetMapCell's out values for the current cell }
  Length: Byte;                   { the remaining beam steps, Range * 2 at the start }
begin
  DrawCombatIcon(ZapAnimation);
  GetMapCell(SpellAimX, SpellAimY, PrevOccupant, Tile);
  DirSign := 1;
  CasterX := CombatantX(SelectedCharacter);
  CasterY := CombatantY(SelectedCharacter);
  Bouncing := Bounce;
  if (CasterX = SpellAimX) and (CasterY = SpellAimY) then
    Exit;
  Length := Range * 2;
  SpellAppliedToArea := 1;
  while Length > 0 do
  begin
    FillChar(Line, SizeOf(Line), 0);
    Line.X1 := SpellAimX;
    Line.Y1 := SpellAimY;
    Line.X2 := SpellAimX + (SpellAimX - CasterX) * DirSign * Length;
    Line.Y2 := SpellAimY + (SpellAimY - CasterY) * DirSign * Length;
    SetupLine(@Line);
    repeat
      StartX := Line.X;
      StartY := Line.Y;
      { The beam steps the line while it still has room (`if (X1 <> X2) or (Y1 <> Y2)`), and the
        stops are the `until` disjunction: the loop ends when StepLine stops, a fresh occupant
        blocks the beam, the line leaves the map, the tile refuses it, or the reach is spent. }
      if (Line.X1 <> Line.X2) or (Line.Y1 <> Line.Y2) then
        repeat
          StepDone := StepLine(@Line);
          GetMapCell(Line.X, Line.Y, Occupant, Tile);
        until (not StepDone) or ((Occupant > 0) and (Occupant <> PrevOccupant)) or (Tile = 0) or
              (CombatTiles[Tile].Cost > MaxPassableCost) or (Line.First >= Length);
      PrevOccupant := Occupant;
      if Tile = 0 then
        Length := 0;
      WalkCombatLine(StartX, StartY, Line.X, Line.Y, LineStep, LineWidth);
      DamageTargetInCell(Line.X, Line.Y, Damage, SaveKind, Blocked);
      if Blocked then
      begin
        SpellAimX := Line.X;
        SpellAimY := Line.Y;
        FillChar(Line2, SizeOf(Line2), 0);
        Line2.X1 := SpellAimX;
        Line2.Y1 := SpellAimY;
        Line2.X2 := CasterX;
        Line2.Y2 := CasterY;
        SetupLine(@Line2);
        while StepLine(@Line2) do ;
        if (Bouncing <> 0) and (Line2.First <= BounceFirstLimit) then
          Inc(Line.First, BounceExtraSteps);
        { QUIRK ovl22:2B71: written `0 - DirSign`, not `-DirSign`: TP 6.0 compiles unary minus to
          `neg ax` but the subtraction to `mov dx,ax; xor ax,ax; sub ax,dx`, which is the original's
          bytes (probe NEG.PAS). }
        DirSign := 0 - DirSign;
        Bouncing := 0;
        PrevOccupant := 0;
      end;
      if Line.First < Length then
        Dec(Length, Line.First)
      else
        Length := 0;
    until (Blocked) or (Length = 0);
  end;
  SpellAppliedToArea := 0;
end;
{ ovl22:2BB7 (e50). Cast handler of spell 51, Lightning Bolt: it rolls one d6 per caster level
  (SpellCasterLevel(CastingSpell), RollDice) as the damage, deals it to the combatant on the aim cell
  SpellAimX/SpellAimY (DamageTargetInCell, electrical, save kind 4) and then runs the beam CastLineBeam
  with reach 8, the same damage and save kind and the bounce flag 1. The beam turns around at every
  wall; the flag only shortens it when the first wall is near the caster (see CastLineBeam). Reads
  CastingSpell. Called through SpellHandlers[51] (InitSpellHandlers). }
procedure CastLightningBolt;
const
  LevelDiceSides = 6;             { one d6 per caster level (the AD&D Lightning Bolt) }
  BeamReach = 8;                  { CastLineBeam's reach: a budget of 16 half squares }
  BounceFlag = 1;                 { CastLineBeam's Bounce: shortens the beam at a near first wall }
var
  Damage: Byte;                   { the rolled damage (caster level d6) }
  Blocked: Boolean;               { whether the aim cell's tile refuses the beam (not read) }
begin
  Damage := RollDice(SpellCasterLevel(CastingSpell), LevelDiceSides);
  DamageTargetInCell(SpellAimX, SpellAimY, Damage, SaveKindSpell, Blocked);
  CastLineBeam(BeamReach, Damage, SaveKindSpell, BounceFlag);
end;
{ ovl22:2C09 (e51). Cast handler of spell 55, Slow: hands the opposite side of the selected character
  (OpposingSide) and the haste affect $27 (SpellTable[48].AffectId) to ApplySpellToSideUpToLevel,
  which cures Haste from up to caster-level members of that side and then applies Slow to the rest
  with 'is Slowed'. One of the per-spell handlers in SpellHandlers (SpellHandlers[55], filled by
  InitSpellHandlers; the Haste handler CastHaste does the mirror image with the slow affect $2A). Reads
  SelectedCharacter. }
procedure CastSlow;
const
  HasteAffect = $27;              { the haste affect Slow removes from the opposite side }
begin
  ApplySpellToSideUpToLevel(HasteAffect, OpposingSide(SelectedCharacter), 'is Slowed');
end;
{ ovl22:2C43 (e52). Cast handler of spell 56, Restoration: it gives the selected character FirstSpellTarget back
  one drained level. The character's drained levels are Pad74[$74] and the hit points lost with them
  Pad74[$75] (a character shows +$32 max, +$11B current and +$75 lost hit points, ovl33:0004), so one
  restored level gives back Pad74[$75] div Pad74[$74] hit points, added to HpMax (+$32), the current
  hit points (+$11B) and HpB1 (+$B1), then the drained-level count is decremented. It then picks the
  class to advance (ClassLevels, +$96): over the eight classes it takes the class whose current level
  is not above the best so far and whose entry one level up in the experience table ExperienceTable
  has the smallest positive value, and keeps the class whose IsMaxClassLevel call is false; that class gains one
  level, the character's Experience (+$AC) is raised to at least that entry, RecalcClassStats
  recomputes the derived values and the character is told 'is restored' (ShowCharacterMessage). A character
  with no drained level (Pad74[$74] = 0) is left alone. Reads FirstSpellTarget; changes the character's drained
  levels, hit points, class level and Experience. }
procedure CastRestoration;
const
  MaxRestoredLevel = 13;          { a class level above this is never advanced ($D) }
  MaxExperience = 10000000;       { the initial 'smallest' experience value the loop compares against }
  LastClass = 7;                  { the last class index of ClassLevels }
  MessageColor = $A;             { the colour ShowCharacterMessage shows 'is restored' in }
var
  Target: PCharacter;             { FirstSpellTarget, the selected character being restored }
  PerLevel: Byte;                 { the hit points one restored level gives back }
  MaxLevel: ShortInt;             { the highest class level a later class may still advance from }
  Level: ShortInt;                { the class level the loop is looking at (ClassLevels[Class]) }
  BestXp: LongInt;                { the smallest experience entry found so far, MaxExperience at the start }
  BestClass: ShortInt;            { the class the level is restored in }
  Class: ShortInt;                { the class index, 0..LastClass }
begin
  Target := FirstSpellTarget;
  if Target^.Pad74[DrainedLevels] <= 0 then
    Exit;
  PerLevel := Target^.Pad74[LostHitPoints] div Target^.Pad74[DrainedLevels];
  Inc(Target^.HpMax, PerLevel);
  Inc(Target^.HpCurrent, PerLevel);
  Inc(Target^.HpB1, PerLevel);
  Dec(Target^.Pad74[LostHitPoints], PerLevel);
  Dec(Target^.Pad74[DrainedLevels]);
  MaxLevel := MaxRestoredLevel;
  BestXp := MaxExperience;
  { QUIRK ovl22:2CAE: BestClass is never initialized, only set by an accepted class; a character with
    no class that can advance would advance whatever class the stale local names. }
  for Class := 0 to LastClass do
  begin
    Level := Target^.ClassLevels[Class];
    if (Level > 0) and (Level <= MaxLevel) and (ExperienceTable[Class, Succ(Level)] > 0) and
       (ExperienceTable[Class, Succ(Level)] < BestXp) and not IsMaxClassLevel(Target, Class) then
    begin
      MaxLevel := Level;
      BestClass := Class;
      BestXp := ExperienceTable[Class, Succ(Level)];
    end;
  end;
  Inc(Target^.ClassLevels[BestClass]);
  if Target^.Experience < BestXp then
    Target^.Experience := BestXp;
  RecalcClassStats(Target);
  ShowCharacterMessage(Target, 'is restored', MessageColor, TimedMessage);
end;
{ ovl22:2E02. Cast handler of spell 57, a monster-only spell: SpellNames[57] is empty, and the
  InitSpellHandlers table points element 57 of SpellHandlers at this stub. It first cancels the slow affect
  $2A from the first chosen target FirstSpellTarget (CureAffect, which shows 'is Cured'); when the target was
  not slowed it applies the current spell CastingSpell to the chosen targets with 'is Speedy', so the
  affected target carries the spell's own (haste) affect. It is CastHaste's single-target sibling. }
procedure CastMonsterHaste;
const
  SlowAffect = $2A;               { the slow affect the spell cancels (SpellTable[55].AffectId, as CastHaste) }
begin
  if not CureAffect(FirstSpellTarget, SlowAffect) then
    ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'is Speedy');
end;
{ ovl22:2E4D. Cast handler of spell 58, a monster-only spell: SpellNames[58] is empty, and the
  InitSpellHandlers table points element 58 of SpellHandlers at this stub. It cures the first chosen target
  FirstSpellTarget: when the target carries the Poisoned affect $37 (CureAffect) it also removes the affect $16
  that the poison leaves behind, with RemovingAffects set so the removals do not run ovl04's own cure handlers.
  A target that is not poisoned is cured of disease instead (CureDiseaseAffects) and, when neither
  cure applies, heals 1d4 + 8 hit points through HealCharacter and reports 'is Healed'. }
procedure CastMonsterHeal;
const
  PoisonedAffect = $37;           { the Poisoned affect CureAffect removes (ovl15 names $37 Poisoned) }
  { The affect removed together with the Poisoned one, meaning unknown: ovl04's Neutralize Poison
    removes the same pair (ovl04:07F1, its AffectSlowPoison). }
  PoisonAidAffect = $16;
  HealDiceCount = 1;              { the cure heals 1d4 hit points }
  HealDiceSides = 4;
  HealBase = 8;                   { ...plus this flat amount }
  NoFlag = 0;                     { HealCharacter's Flag: no side effect }
  ShowAbout = 1;                  { ShowHitMessage's Flag argument }
var
  { Never read: the original frame reserves one byte no instruction touches (QUIRK ovl22:2E4D); it is
    declared so the 'is Healed' string temporary below it lands where the original put it. }
  Spare: Byte;
begin
  if CureAffect(FirstSpellTarget, PoisonedAffect) then
  begin
    RemovingAffects := 1;
    RemoveAffect(FirstSpellTarget, PoisonAidAffect, nil);
    RemovingAffects := 0;
  end
  else
    if not CureDiseaseAffects then
      if HealCharacter(FirstSpellTarget, RollDice(HealDiceCount, HealDiceSides) + HealBase, NoFlag) then
        ShowHitMessage(FirstSpellTarget, ShowAbout, 'is Healed');
end;
{ ovl22:2EE5. Cast handler of spell 59, a monster-only spell: SpellNames[59] is empty, and the
  InitSpellHandlers table points element 59 of SpellHandlers at this stub. It gives the first chosen target
  FirstSpellTarget a fixed Strength of 21 with no exceptional percentile (RaiseStrength; a monster's strength),
  shows 'is stronger' when the strength actually rose (ShowCharacterMessage) and adds the strength affect $26
  (the affect CastStrength and this routine leave, SpellTable[35] and [59]; Enlarge's is $0C, ovl24
  RaiseStrength) for the current spell's own duration (SpellAffectDuration). }
procedure CastMonsterStrength;
const
  MonsterStrength = 21;           { the Strength RaiseStrength applies }
  NoPercent = 0;                  { no exceptional-strength percentile }
  StrengthAffect = $26;           { the strength affect left on the target (as CastStrength, ovl22:1F41) }
  MessageColor = $A;             { the colour ShowCharacterMessage shows 'is stronger' in }
var
  Code: Byte;                     { RaiseStrength's earlier-strength code, passed to AddAffect as Data }
begin
  if RaiseStrength(FirstSpellTarget, MonsterStrength, NoPercent, Code) then
    ShowCharacterMessage(FirstSpellTarget, 'is stronger', MessageColor, TimedMessage);
  AddAffect(FirstSpellTarget, StrengthAffect, SpellAffectDuration(CastingSpell), Code, RunsHandlerOnRemove);
end;
{ ovl22:2F4D. Cast handler of spell 60, a monster-only spell: SpellNames[60] is empty, and the
  InitSpellHandlers table points element 60 of SpellHandlers at this stub. It strikes the combatant on the aim
  cell SpellAimX/SpellAimY for 1d6 + 20 points (DamageTargetInCell: the spell's saving throw kind 4, half
  damage on a save, and the zap animation) and then runs a short beam CastLineBeam(3, 20, 4, 0): a budget
  of six half squares at 20 points, away from the caster; with the flag 0 a wall still turns it around. }
procedure CastMonsterBeam;
const
  { The strike on the aim cell and the beam's per-cell damage: a flat 20, the direct hit rolls 1d6
    more (the two numbers are separate in the original). }
  StrikeDiceCount = 1;
  StrikeDiceSides = 6;
  StrikeBase = 20;
  BeamReach = 3;                  { CastLineBeam's budget is Range * 2 half squares }
  BeamDamage = 20;
  NoBounce = 0;                   { Bounce 0: a wall turns the beam, but never shortens it }
var
  Blocked: Boolean;               { DamageTargetInCell's out flag: the aim cell's tile refuses the beam (not read) }
begin
  DamageTargetInCell(SpellAimX, SpellAimY, RollDice(StrikeDiceCount, StrikeDiceSides) + StrikeBase, SaveKindSpell, Blocked);
  CastLineBeam(BeamReach, BeamDamage, SaveKindSpell, NoBounce);
end;
{ ovl22:2F99 (e57). Cast handler of spell 61, a monster-only spell: SpellNames[61] is empty and the
  InitSpellHandlers handler table points element 61 of SpellHandlers at this stub. It only applies the current
  spell CastingSpell to the chosen targets with the message 'is paralyzed'; the spell's own affect does the
  paralyzing (as CastCauseBlindness does the blinding). Reads CastingSpell. }
procedure CastMonsterParalyze;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'is paralyzed');
end;
{ ovl22:2FD0 (e58). Cast handler of spell 62, a monster-only spell: SpellNames[62] is empty and the
  InitSpellHandlers handler table points element 62 of SpellHandlers at this stub. It heals the first chosen
  target FirstSpellTarget through HealCharacter for 2d4 + 2 hit points (RollDice, no flag) and reports
  'is Healed' when the heal went through (ShowHitMessage, its Flag 1). The map read the routine's
  own prologue as a separate 3-byte routine ovl22_fn_2FD3 at the sub sp word; make match WRITE=1
  removed that entry (nothing calls it, and the entry stubs point at 2FD0, overlay entry 58).
  Reads FirstSpellTarget. }
procedure CastMonsterHealWounds;
begin
  if HealCharacter(FirstSpellTarget, RollDice(2, 4) + 2, 0) then
    ShowHitMessage(FirstSpellTarget, 1, 'is Healed');
end;
{ ovl22:302A (e59). Cast handler of spell 63, a monster-only spell: SpellNames[63] is empty and the
  InitSpellHandlers handler table points element 63 of SpellHandlers at this stub. It only applies the current
  spell CastingSpell to the chosen targets with the message 'is invisible'; the spell's own affect does the
  work (as CastDetectionSpell and CastCauseBlindness leave it to the affect). Reads CastingSpell. }
procedure CastMonsterInvisibility;
begin
  ApplySpellToTargets(CastingSpell, 0, 0, 0, 0, 'is invisible');
end;
{ ovl22:3058 (e60). Cast handler of spell 65, a monster-only spell: SpellNames[65] is empty and the
  InitSpellHandlers handler table points element 65 of SpellHandlers at this stub. It applies the current
  spell CastingSpell to the chosen targets for 2d4 + 2 points (RollDiceCounted, its count kept in LastDiceCount)
  of magic damage with no message. The roll is the damage CastMagicMissile deals for a caster of
  level 3 or 4 (two missiles of 1d4 + 1, ovl22:1439), fixed here since a monster has no caster level.
  Reads CastingSpell; changes LastDiceCount. }
procedure CastMonsterMagicDamage;
const
  DiceCount = 2;                  { the two missiles of a 3rd or 4th level Magic Missile }
  DiceSides = 4;                  { each missile does 1d4 plus 1 }
  DamageBonus = 2;                { one point per missile }
  DamageKind = 8;                 { DealDamage: kind 8 is magic (as CastMagicMissile, ovl22:1439) }
begin
  ApplySpellToTargets(CastingSpell, 0, 0,
    RollDiceCounted(DiceCount, DiceSides) + DamageBonus, DamageKind, '');
end;
{ ovl22:3092 (e61). Cast handler of spell 66, a monster-only spell: SpellNames[66] is empty and the
  InitSpellHandlers handler table points element 66 of SpellHandlers at this stub. The handler is empty: the
  picker has already chosen the targets (CastChosenSpell calls SpellTargetPicker, the DS:6B84
  callback, before the handler) and the spell then does nothing, since ApplySpellToTargets is never
  called here, unlike its neighbours CastMonsterParalyze (spell 61) and CastMonsterMagicDamage
  (spell 65). }
procedure CastMonsterNoEffect;
begin
end;
{ ovl22:30A2 (e62). Cast handler of the monster-only spell 67 (SpellHandlers element 67, whose
  SpellNames entry is empty, whitepaper 5.22.2): applies the current spell CastingSpell to the chosen
  targets with caster level $FF (a fixed affect data, as CastSlowPoison's FullCasterLevel), Flag 1
  so the affect's handler runs when it is removed, no damage or kind of its own, and the message
  'is Reading'. }
procedure CastMonsterReadMagic;
begin
  ApplySpellToTargets(CastingSpell, $FF, 1, 0, 0, 'is Reading');
end;
{ ovl22:30D9. MonsterBreath: the breath attack of a monster (the dragon breath the line spells'
  comments name). When CombatRound is set (a combat round counter) it first rolls 1d100 and gives up on a
  roll of 50 or less, so the monster does not breathe every round. It takes the breather's combat cell
  (CombatantX/Y of Who), shows 'Breathes!', asks the target picker SpellTargetPicker for the aim
  (spell $33, the Lightning Bolt, quick) with its Done at PickerDone, and nudges the aim cell
  SpellAimX/SpellAimY one cell towards the breather (SignOf) and off the cell beside him. It clears the
  breather's attacker affect, plays the zap animation (DrawCombatIcon($13)), draws the breath line
  (WalkCombatLine) from the breather to the aim cell, damages the aim cell for his maximum hit points
  (DamageTargetInCell: electrical, save kind 3) and runs the line beam CastLineBeam($A, HpMax, 3, 0).
  Finally it spends the breath affect Affect: while its Data byte is above $FD it is only decremented,
  otherwise the affect $58 is removed; EndCombatTurn(Who) then runs and its byte result is left in the
  unread Blocked local (QUIRK ovl22:30D9). Globals: CombatRound, SpellAimX/SpellAimY, PickerDone. Parameters: Who the
  breathing monster, Affect its breath affect, Unused is never read (QUIRK ovl22:30D9). }
procedure MonsterBreath(Who: PCharacter; Affect: PAffect; Unused: Byte);
const
  BreatheChance = $32;            { the monster does not breathe on a 1d100 roll up to this }
  ChanceSides = $64;              { the chance is rolled on 1d100 }
  MessageColor = $A;             { the colour ShowCharacterMessage shows 'Breathes!' in }
  PickerSpell = $33;              { the picker uses the Lightning Bolt's target mode }
  PickerQuick = 1;                { the picker's second argument }
  ZapAnimation = $13;             { DrawCombatIcon's zap animation, as DamageTargetInCell }
  BeamStep = 4;                   { WalkCombatLine's step for the breath line }
  BeamWidth = $32;                { WalkCombatLine's width for the breath line }
  BeamReach = $A;                 { CastLineBeam's reach: the breath walks this many cells each way }
  NoBounce = 0;                   { Bounce 0: a wall turns the breath line, but never shortens it }
  BreathAffect = $58;             { the affect removed once its data byte is spent }
  BreathDataLimit = $FD;          { while the affect's data is above this it is only decremented }
var
  Blocked: Boolean;               { DamageTargetInCell's out flag, then EndCombatTurn's result }
  CasterX, CasterY: ShortInt;     { the breather's combat cell (CombatantX/Y) }
begin
  if (CombatRound <> 0) and (RollDice(1, ChanceSides) <= BreatheChance) then
    Exit;
  CasterX := CombatantX(Who);
  CasterY := CombatantY(Who);
  ShowCharacterMessage(Who, 'Breathes!', MessageColor, TimedMessage);
  SpellTargetPicker(PickerSpell, PickerQuick, PickerDone);
  SpellAimX := CasterX + SignOf(SpellAimX - CasterX);
  SpellAimY := CasterY + SignOf(SpellAimY - CasterY);
  if SpellAimX = CasterX + 1 then
    Inc(SpellAimX);
  if SpellAimY = CasterY + 1 then
    Inc(SpellAimY);
  ClearAttackerAffect(Who);
  DrawCombatIcon(ZapAnimation);
  WalkCombatLine(CasterX, CasterY, SpellAimX, SpellAimY, BeamStep, BeamWidth);
  DamageTargetInCell(SpellAimX, SpellAimY, Who^.HpMax, SaveKindBreath, Blocked);
  CastLineBeam(BeamReach, Who^.HpMax, SaveKindBreath, NoBounce);
  if Affect^.Data > BreathDataLimit then
    Dec(Affect^.Data)
  else
    RemoveAffect(Who, BreathAffect, Affect);
  Blocked := Boolean(EndCombatTurn(Who));
end;
{ ovl22:323D. IsScroll: whether Item is a spell scroll. It rejects a nil item first, then tests the
  item's class byte ItemTable[Item^.ItemType].Slot (the first byte of the 16-byte row for the item type
  in the ItemTable table at DS:5582): the three values $B, $C and $D are the spell scrolls whose
  Affects[1..3] hold spell numbers (AddItemSpells and the scribing helpers read them). Callers use it
  to find the carried scrolls: AddScrollSpells, ScribeScrolls, StudyRestMinutes, CancelScribing,
  ProcessPendingScribedSpell, UseMagicItem and the inventory. }
function IsScroll(Item: PItem): Boolean;
const
  { ItemTable[ItemType].Slot is the item class; a scroll's class is above $A and below $E. }
  NotAScrollBelow = $A;           { the scroll classes start above this }
  NotAScrollAbove = $E;           { ... and end below this }
begin
  if (Item <> nil) and (ItemTable[Item^.ItemType].Slot > NotAScrollBelow) and
     (ItemTable[Item^.ItemType].Slot < NotAScrollAbove) then
    IsScroll := True
  else
    IsScroll := False;
end;
{ ovl22:328A. ConsumeScrollSpell: removes one scribed spell from a scroll. The spell number (the low
  seven bits of Spell) is looked for among the scroll's three spell bytes Item^.Affects[1..3]; the
  last slot whose low seven bits match is cleared, the scroll's second name number (NameNum[2],
  +$30) is decremented and, when it drops below $D2 (no spells left), the scroll is removed from
  Who's items (RemoveInventoryItem unlinks it and frees it; nothing is redrawn).
  ProcessPendingScribedSpell calls it after marking the scribed spell known, and ovl19's item code
  calls it too. Nothing happens when the spell is not on the scroll (Slot stays 0). }
procedure ConsumeScrollSpell(Who: PCharacter; Item: PItem; Spell: Byte);
const
  { A scroll's NameNum[2] is its remaining spell count plus $D1 (BuildTreasureItem, ovl21:1010); a
    value below this means no spells are left and the used-up scroll is removed. }
  UsedUpScrollBelow = $D2;
var
  SpellNumber: Byte;              { Spell with the pending bit cleared, the number looked for }
  I: Byte;                        { the scroll spell slot, 1..3 }
  Slot: Byte;                     { the slot the spell was found in, 0 when it was not found }
begin
  SpellNumber := Spell and SpellMask;
  Slot := 0;
  for I := 1 to 3 do
    if (Item^.Affects[I] and SpellMask) = SpellNumber then
      Slot := I;
  if Slot = 0 then
    Exit;
  Item^.Affects[Slot] := 0;
  Dec(Item^.NameNum[2]);
  if Item^.NameNum[2] < UsedUpScrollBelow then
    RemoveInventoryItem(Who, Item);
end;
{ ovl22:331A. Announces a spell event for a named character. In combat (ViewMode = 5) it shows the timed
  message 'Casts a Spell' and, on the combat message row, 'Spell:' with the spell's name at column 0.
  Outside combat it clears the message window, draws Who's name at column 1 of row $13 (DrawCharacterName),
  draws Message right after the name (two columns past the name's length: 'casts', 'has memorized' or
  'has scribed'), draws the spell's name at column 1 of the next row, waits a game-speed delay and
  clears the prompt (ClearCharacterMessage). Called by ovl20's ProcessMemorizedSpell and
  ProcessPendingScribedSpell and by CastChosenSpell (which passes 'casts'). The map's ovl22_fn_3379
  entry at 3379 was invented inside this routine; make match WRITE=1 removed it. }
procedure ShowSpellMessage(Who: PCharacter; Message: String40; Spell: Byte);
const
  TextColumn = 1;                 { the column the name and the spell's name are drawn at }
  MessageRow = $13;               { the row Who's name and Message are drawn on, out of combat }
  SpellNameRow = $14;             { the row the spell's name is drawn on }
  GapAfterName = 2;               { Message starts this many columns past the name's length }
  MessageColor = $A;             { the colour of the messages }
begin
  if ViewMode = ViewModeCombat then
  begin
    ShowCharacterMessage(Who, 'Casts a Spell', MessageColor, TimedMessage);
    ClearWindow(0, $17, $27, $17);
    DrawTextAt(0, $17, MessageColor, 'Spell:' + SpellNames[Spell]);
  end
  else
  begin
    ClearWindow(TextColumn, $12, $26, $16);
    DrawCharacterName(Who, TextColumn, MessageRow, False);
    DrawTextAt(Length(Who^.Name) + GapAfterName, MessageRow, MessageColor, Message);
    DrawTextAt(TextColumn, SpellNameRow, MessageColor, SpellNames[Spell]);
    DelayByGameSpeed;
    ClearCharacterMessage;
  end;
end;
{ ovl22:3413 (e10). Initialises the spell-casting tables and globals once at start-up (ovl11:002D
  StartGame calls it). It fills the DS:6B84 block SpellHandlers: element 0 is the target picker
  (@ChooseSpellTargets) and elements 1..$43 the cast handler of every spell number 1..$43, each an
  overlay stub of this unit (several spells share one handler: elements 5, 11, 18, 22 and 29 are
  CastDetectionSpell; 6, 7, 16, 17 and 52..54 are CastProtection; 46 is CastDispelMagic with 41).
  Then it stores @MonsterBreath in DS:6988 (MonsterBreathVector), clears the affect-removal flag RemovingAffects, the
  item-cast flag ItemAffectUse (set while the Use action casts a spell from an item, ovl19; the
  spell is then not forgotten and SpellCasterLevel returns 6) and the picker's chosen character
  PickedSpellCharacter, and sets RedrawItemWindow to 1. }
procedure InitSpellHandlers;
begin
  SpellTargetPicker := ChooseSpellTargets;
  RemovingAffects := 0;
  ItemAffectUse := False;
  PickedSpellCharacter := nil;
  RedrawItemWindow := 1;
  SpellHandlers[1] := CastBless;                { 1 Bless }
  SpellHandlers[2] := CastCurse;                { 2 Curse }
  SpellHandlers[3] := CastCureLightWounds;      { 3 Cure Light Wounds }
  SpellHandlers[4] := CastCauseLightWounds;     { 4 Cause Light Wounds }
  SpellHandlers[5] := CastDetectionSpell;       { 5 Detect Magic }
  SpellHandlers[6] := CastProtection;           { 6 Protection From Evil }
  SpellHandlers[7] := CastProtection;           { 7 Protection from Good }
  SpellHandlers[8] := CastResistCold;           { 8 Resist Cold }
  SpellHandlers[9] := CastBurningHands;         { 9 Burning Hands }
  SpellHandlers[10] := CastCharmPerson;         { 10 Charm Person }
  SpellHandlers[11] := CastDetectionSpell;      { 11 Detect Magic }
  SpellHandlers[12] := CastEnlarge;             { 12 Enlarge }
  SpellHandlers[13] := CastReduce;              { 13 Reduce }
  SpellHandlers[14] := CastFriends;             { 14 Friends }
  SpellHandlers[15] := CastMagicMissile;        { 15 Magic Missile }
  SpellHandlers[16] := CastProtection;          { 16 Protection From Evil }
  SpellHandlers[17] := CastProtection;          { 17 Protection From Good }
  SpellHandlers[18] := CastDetectionSpell;      { 18 Read Magic }
  SpellHandlers[19] := CastShield;              { 19 Shield }
  SpellHandlers[20] := CastShockingGrasp;       { 20 Shocking Grasp }
  SpellHandlers[21] := CastSleep;               { 21 Sleep }
  SpellHandlers[22] := CastDetectionSpell;      { 22 Find Traps }
  SpellHandlers[23] := CastHoldPerson;          { 23 Hold Person }
  SpellHandlers[24] := CastResistFire;          { 24 Resist Fire }
  SpellHandlers[25] := CastSilence;             { 25 Silence, 15' Radius }
  SpellHandlers[26] := CastSlowPoison;          { 26 Slow Poison }
  SpellHandlers[27] := CastSnakeCharm;          { 27 Snake Charm }
  SpellHandlers[28] := CastSpiritualHammer;     { 28 Spiritual Hammer }
  SpellHandlers[29] := CastDetectionSpell;      { 29 Detect Invisibility }
  SpellHandlers[30] := CastInvisibility;        { 30 Invisibility }
  SpellHandlers[31] := CastKnock;               { 31 Knock }
  SpellHandlers[32] := CastMirrorImage;         { 32 Mirror Image }
  SpellHandlers[33] := CastRayOfEnfeeblement;   { 33 Ray of Enfeeblement }
  SpellHandlers[34] := CastStinkingCloud;       { 34 Stinking Cloud }
  SpellHandlers[35] := CastStrength;            { 35 Strength }
  SpellHandlers[36] := CastAnimateDead;         { 36 Animate Dead }
  SpellHandlers[37] := CastCureBlindness;       { 37 Cure Blindness }
  SpellHandlers[38] := CastCauseBlindness;      { 38 Cause Blindness }
  SpellHandlers[39] := CastCureDisease;         { 39 Cure Disease }
  SpellHandlers[40] := CastCauseDisease;        { 40 Cause Disease }
  SpellHandlers[41] := CastDispelMagic;         { 41 Dispel Magic }
  SpellHandlers[42] := CastPrayer;              { 42 Prayer }
  SpellHandlers[43] := CastRemoveCurse;         { 43 Remove Curse }
  SpellHandlers[44] := CastBestowCurse;         { 44 Bestow Curse }
  SpellHandlers[45] := CastBlink;               { 45 Blink }
  SpellHandlers[46] := CastDispelMagic;         { 46 Dispel Magic }
  SpellHandlers[47] := CastFireball;            { 47 Fireball }
  SpellHandlers[48] := CastHaste;               { 48 Haste }
  SpellHandlers[49] := CastHoldPerson;          { 49 Hold Person }
  SpellHandlers[50] := CastInvisibility;        { 50 Invisibility, 10' Radius }
  SpellHandlers[51] := CastLightningBolt;        { 51 Lightning Bolt }
  SpellHandlers[52] := CastProtection;          { 52 Protection From Evil }
  SpellHandlers[53] := CastProtection;          { 53 Protection From Good, 10' Radius }
  SpellHandlers[54] := CastProtection;          { 54 Protection From Normal Missiles }
  SpellHandlers[55] := CastSlow;                { 55 Slow }
  SpellHandlers[56] := CastRestoration;         { 56 Restoration }
  SpellHandlers[57] := CastMonsterHaste;        { 57 (monster-only, no name) }
  SpellHandlers[58] := CastMonsterHeal;         { 58 (monster-only, no name) }
  SpellHandlers[59] := CastMonsterStrength;     { 59 (monster-only, no name) }
  SpellHandlers[60] := CastMonsterBeam;         { 60 (monster-only, no name) }
  SpellHandlers[61] := CastMonsterParalyze;     { 61 (monster-only, no name) }
  SpellHandlers[62] := CastMonsterHealWounds;   { 62 (monster-only, no name) }
  SpellHandlers[63] := CastMonsterInvisibility; { 63 (monster-only, no name) }
  SpellHandlers[64] := CastFireball;            { 64 (monster-only, no name) }
  SpellHandlers[65] := CastMonsterMagicDamage;  { 65 (monster-only, no name) }
  SpellHandlers[66] := CastMonsterNoEffect;     { 66 (monster-only, no name) }
  SpellHandlers[67] := CastMonsterReadMagic;    { 67 (monster-only, no name) }
  MonsterBreathVector := @MonsterBreath;
end;

begin
end.
