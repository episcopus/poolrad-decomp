unit RES12;
{ res12: the resident helper unit the overlays call for character, item, view and combat work
  (whitepaper 5.24). It recomputes a character's combat values (RecalcCombatValues,
  ApplyWeaponBonuses, SetArmourMovement, AddReadiedItemBonus, CapMovementByLoad), the strength
  figures (StrengthRowIndex, StrengthAttackAdjustment, StrengthDamageAdjustment,
  StrengthWeightAllowance), the dexterity figures (DexterityAdjustment,
  DexterityAttackAdjustment), the race level cap (IsMaxClassLevel) and the spell caster level
  (SpellCasterLevel), and formats numbers (ByteToText, WordToText, LongIntToText). It draws the
  character panels (DrawPartyRoster, DrawArmourClass, DrawHitPoints, DrawCharacterPanel), the
  view dispatcher and its screens (RedrawView, DrawViewWindows, DrawLocationLine,
  DrawWildernessScreen, DrawCombatScreen) and the character messages and names
  (ShowCharacterMessage, ClearCharacterMessage, ShowFlashMessage, DrawCharacterName), builds an
  item menu line from the DS:10A7 name parts (FormatItemLine) and picks a party member
  (SelectPartyMember). Its combat-side helpers are ApplyDamage, RecountCombatSides, OpposingSide,
  CollectEnemiesInRange, DistanceToTarget, EndCombatTurn and GuardTurn; its weapon helpers
  IsRangedWeapon, RangedWeaponCanMelee and ChooseAttackItem; its combat animation WalkCombatLine,
  ShowHitMessage, CopyPictureItem and DrawCombatIcon; and its inventory list helpers
  RemoveInventoryItem and AddItemCopy. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses Crt, POOLVARS, RES03, RES06, RES07, RES09, OVL25, OVL26, OVL27, OVL28, OVL30, OVL31;
type
  { The readied-item bonus accumulator AddReadiedItemBonus fills for RecalcCombatValues: five signed
    bytes (with the flag byte the second var parameter points at). RecalcCombatValues clears all five,
    stores the dexterity adjustment in DexAdjust, and sums all five as Values into ResistValue (+$111);
    only BestValue, PlusSum and BestPlus (minus two) go into ds112 (+$112). }
  TBonus = record
    case Integer of
      0: (DexAdjust: Byte;     { +0: the dexterity adjustment RecalcCombatValues stores }
          KindBonus: ShortInt; { +1: Value + Plus of a kind-1 item }
          PlusSum: ShortInt;   { +2: the plus of every other non-kind-9 item }
          BestPlus: ShortInt;  { +3: the largest plus of a kind-9 item }
          BestValue: ShortInt);{ +4: the largest Value + Plus of a Value <> 0 item }
      1: (Values: array[0..4] of ShortInt);  { the five bytes as RecalcCombatValues clears and sums them }
  end;
procedure ApplyWeaponBonuses(Who: PCharacter);
procedure SetArmourMovement(Who: PCharacter; Item: PItem);
procedure AddReadiedItemBonus(Who: PCharacter; Item: PItem; var Bonus: TBonus; var Flag: Byte);
procedure CapMovementByLoad(Who: PCharacter);
procedure FormatItemLine(Value: LongInt; Item: PItem; Col, Row, ShowReadied, ShowText: Byte);
procedure DrawPartyRoster(Who: PCharacter);
procedure DrawArmourClass(Who: PCharacter; Col, Row: Byte);
procedure DrawHitPoints(Who: PCharacter; Col, Row, Flag: Byte);
procedure DrawCharacterPanel(Who: PCharacter);
function IsHelpless(Who: Pointer): Boolean;
procedure RecalcCombatValues(Who: PCharacter);
function ByteToText(Value: Byte): string;
function WordToText(Value: Word): string;
function LongIntToText(Value: LongInt): string;
function DexterityAdjustment(Who: PCharacter): Byte;
function DexterityAttackAdjustment(Who: PCharacter): ShortInt;
function StrengthRowIndex(Who: PCharacter): Byte;
function StrengthAttackAdjustment(Who: PCharacter): ShortInt;
function StrengthDamageAdjustment(Who: PCharacter): ShortInt;
function StrengthWeightAllowance(Who: PCharacter): Integer;
procedure ForgetSpell(Spell: Byte);
procedure RemoveInventoryItem(Who: PCharacter; Item: PItem);
procedure AddItemCopy(Who: PCharacter; Item: PItem);
procedure ShowFlashMessage(Text: String40);
procedure ShowCharacterMessage(Who: PCharacter; Text: string; Row, Wait: Byte);
procedure ClearCharacterMessage;
procedure DrawCharacterName(Who: PCharacter; Col, Row, Mode: Byte);
procedure CopyPictureItem(PicIndex, Half, Row, Mirror: Byte);
procedure DrawCombatIcon(PicIndex: Byte);
procedure WalkCombatLine(FromX, FromY, ToX, ToY: ShortInt; Count, Mode: Byte);
procedure ShowHitMessage(Who: Pointer; Flag: Byte; Text: String40);
function HasAffect(Who: Pointer; AffectId: Byte; var Affect: Pointer): Boolean;
procedure ApplyDamage(Who: Pointer; Damage: Byte);
procedure ShowHealResult(Who: Pointer);
function OpposingSide(Who: Pointer): Byte;
procedure RecountCombatSides;
function CollectEnemiesInRange(Who: Pointer; Range: Byte): Byte;
function DistanceToTarget(Who, Target: Pointer): Byte;
function EndCombatTurn(Who: Pointer): Byte;
function GuardTurn(Who: Pointer): Byte;
function SpellCasterLevel(Spell: Byte): Byte;
procedure DrawViewWindows(WithInner: Byte);
procedure RedrawView;
procedure DrawLocationLine;
procedure DrawWildernessScreen;
procedure DrawCombatScreen;
procedure SelectPartyMember(Title: String40; WithExit: Byte; var Selected: PCharacter);
function IsRangedWeapon(Who: Pointer): Boolean;
function RangedWeaponCanMelee(Who: Pointer): Boolean;
function ChooseAttackItem(Who: Pointer; var Aim: Pointer): Byte;
function IsMaxClassLevel(Who: PCharacter; ClassIndex: ShortInt): Boolean;
implementation

const
  { Bits of ItemTable[item kind].Flags (DS:5582; 129 sixteen-byte rows indexed by item kind, POOLVARS):
    which attack bonuses the item kind gets. The readied weapon's item kind picks the row. }
  WeaponFlagSlot11Plus = 1;     { add the plus of slot item 11 (+$F8) }
  WeaponFlagDexToHit = 2;       { the attack adds the dexterity roll adjustment }
  WeaponFlagStrength = 4;       { the attack adds the strength roll and damage adjustments }
  WeaponFlagMelee = $10;        { the kind can strike with the readied weapon itself (2E46, 2E8B) }
  WeaponFlagAmmo = $08;         { the kind fires an ammo item: slot 11 or 12 (ChooseAttackItem) }
  WeaponFlagSlot12Plus = $80;   { add the plus of slot item 12 (+$FC) }
  { The race value (Race, +$2E) that gets one more point with the item kinds $24, $25 and $29..$2C
    (the bows and the long and short swords of AD&D); which race that is is not proven here. }
  BonusRace = 2;
  BonusKindRangeLow = $28;      { the kinds above it and below the next value get the point }
  BonusKindRangeHigh = $2D;
  BonusKindLow = $25;
  BonusKindLower = $24;
  { Item kind (ItemTable[item kind].Slot) of an armour, and the movement it allows: up to
    LightArmourWeight the character keeps its BaseMovement, up to HeavyArmourWeight it is
    MediumArmourMove, and above it HeavyArmourMove. A magic armour adds MagicArmourMoveBonus. }
  ArmourItemKind = 2;
  LightArmourWeight = $96;
  MediumArmourWeight = $97;
  HeavyArmourWeight = $18F;
  MediumArmourMove = 9;
  HeavyArmourMove = 6;
  MagicArmourMoveBonus = 3;
  { The load limits of CapMovementByLoad (the excess carried weight): up to LightLoadLimit the
    movement is left alone, up to MediumLoadLimit it is MediumLoadMove, up to HeavyLoadLimit
    HeavyLoadMove, and above that OverloadMove. }
  LightLoadLimit = $200;
  MediumLoadFrom = $201;
  MediumLoadLimit = $300;
  HeavyLoadFrom = $301;
  HeavyLoadLimit = $400;
  MediumLoadMove = 9;
  HeavyLoadMove = 6;
  OverloadMove = 3;
  { Item kinds AddReadiedItemBonus tells apart (ItemTable[item kind].Slot): 0 weapon, 2 armour. }
  PlusItemKind = 1;         { item kind whose bonus is assigned, not accumulated }
  SpecialItemKind = 9;      { item kind whose plus is kept as a maximum }
  { RecalcCombatValues: the readied item kinds whose slot index equals the kind, 0..LastDirectSlotKind;
    kind SpecialItemKind goes to the first free of slots 9 and 10. }
  LastDirectSlotKind = 8;
  { RecalcCombatValues: the item types it files into SlotItems[11] and SlotItems[12].
    00BA:0442 also treats these two kinds as the ones whose plural 's' is suppressed when
    NameNum[3] is NoPluralNameNum (00BA:06BD). }
  Slot11ItemType = $49;
  Slot12ItemType = $1C;
  { 00BA:0442: a party member with this affect makes a Plus, PlusSave or Cursed item show '* '
    before its name. Which spell or item grants affect 5 is not proven here. }
  MagicMarkAffect = 5;
  { 00BA:0442: the item type whose plural 's' attaches to name part 3 (00BA:06B6); name part 1
    does not take the plural for this type (00BA:0699). ovl12:2D38 and the attack animation also
    special-case $56; which item it is is not proven. }
  PluralOnThirdPartType = $56;
  { 00BA:0442: NameNum[3] that keeps a slot-11 or slot-12 item from taking the plural 's'
    (00BA:06D4). The same index keeps an unenchanted slot item's damage (ovl12:264B, ovl12:2D88);
    which name it is is not proven. }
  NoPluralNameNum = $B1;
  { 00BA:0442: the mask bit of name part 3 (1 shl 2). A mask above this means part 3 is shown,
    because the part-1 and part-2 bits sum to at most 3 (00BA:0690, jbe). }
  ThirdNameBit = 4;
  { RecalcCombatValues: a readied item whose NameNum[1] is $BA instead counts ExcludedWeight (5000 less)
    in the carried weight. $BA is an index of the DS:10A7 name table; which item it is is not proven. }
  BagNameNum = $BA;
  ExcludedWeight = $1388;
  { DexterityAdjustment maps Who's dexterity (+$13) to its adjustment: dexterity 1..3 gives -4, 4..6
    the dexterity minus 7, 7..14 gives 0, 15..18 the dexterity minus 14, 19..20 gives 4, 21..23
    gives 5 and 24..25 gives 6. }
  DexBand1Low = 1;
  DexBand1High = 3;
  DexBand1Adjust = $FC;   { -4 }
  DexBand2Low = 4;
  DexBand2High = 6;
  DexBand2Offset = 7;
  DexBand3Low = $F;
  DexBand3High = $12;
  DexBand3Offset = $E;
  DexBand4Low = $13;
  DexBand4High = $14;
  DexBand4Adjust = 4;
  DexBand5Low = $15;
  DexBand5High = $17;
  DexBand5Adjust = 5;
  DexBand6Low = $18;
  DexBand6High = $19;
  DexBand6Adjust = 6;
  { EGA text colours DrawTextAt draws the character and shop panels in (whitepaper 5.24). }
  Green = $0A;
  LightCyan = $0B;
  LightRed = $0C;
  LightMagenta = $0D;
  Yellow = $0E;
  White = $0F;
  { CopyPictureItem reads VideoAdapter: 1 is the EGA display pages, where the pixel buffer holds one
    plane byte per four data bytes of the EGA layout (whitepaper 5.23). }
  VideoAdapterEga = 1;
  { SizeOf(TMenuLine): the item record GetMem allocates and FreeMem frees in 1509 and 15F7
    (the original pushes $3f) and ovl05 frees with ItemListSize. }
  ItemListSize = $3F;
  { The bottom message line 1509 reports a lost item on and 1693 flashes on. }
  BottomRow = 24;
  ScreenLastCol = 39;
  { TCharacter.Status values this unit uses (the image names 0 Okay, 1 Animated, 4 Unconscious,
    5 Dying, 6 Dead). ShowDamage uses the set StatusOkay + StatusAnimated as "still standing". }
  StatusOkay = 0;
  StatusAnimated = 1;
  StatusUnconscious = 4;
  StatusDying = 5;
  StatusDead = 6;
  { TCharacter.Side values: the party is 0, the monsters 1 (SetQuickCombat compares them). }
  SideParty = 0;
  SideMonsters = 1;
  { IsMaxClassLevel's race values (Race, +$2E, the RaceNames table DS:0F03) and the strength scores
    at which a demihuman's level limit in a class rises (the AD&D demihuman level limits [H]). }
  RaceDwarf = 1;
  RaceElf = 2;
  RaceGnome = 3;
  RaceHalfElf = 4;
  RaceHalfling = 5;
  Strength17 = $11;   { 17, raises the fighter limit by one }
  Strength18 = $12;   { 18, raises it by two }
  { The ClassLevels indices IsMaxClassLevel and SpellCasterLevel test (ClassNames DS:0D38). }
  ClassCleric = 0;
  ClassFighter = 2;
  ClassMagicUser = 5;
  { SpellCasterLevel: the SpellTable.SpellClass values (ClassNames order: 0 cleric, 1 magic-user, 2
    a fixed level) and the fixed levels it returns for class 2 and while ItemAffectUse is set. What
    spell class 2 and ItemAffectUse are is not proven [?]. }
  SpellClassCleric = 0;
  SpellClassMagicUser = 1;
  SpellClassFixed = 2;
  SpecialSpellLevel = $0C;   { 12 }
  ItemSpellLevel = 6;
  { The most records the ScanTargets table ds6718 can hold: one per combatant of CombatantTable
    (72 plus its count at entry 0), times the 3 bytes of a TSortRec. 255B saves and restores exactly
    this many records of ds6718 around its scan. }
  SavedScanBytes = $D8;
  { The game clock is a seven-digit mixed-radix count in the game variables (VarsAt4900^[$49C6+Digit];
    AdvanceGameClock advances it and ShowRestTime reads the same digits). The location line (00BA:290B) reads
    digit 1 and 2 (the minute ones and tens) and digit 3 (the hours) to show the time as hours:minutes. }
  ClockMinutes = $49C7;
  ClockTenMinutes = $49C8;
  ClockHours = $49C9;
  { The movement mode word of the second game word block (ds49D6^[714]; HandleWildernessKeys toggles
    bit 0 with the S (search) key and sets bit 1 with L). The location line (00BA:290B) appends
    ' search' while bit 0 is set. }
  VarTravelMode = 714;
  { The ds49F3 view modes RedrawView dispatches on (the setters are in the other units): 0 is the
    plain full-window layout of the create-character and training screens (RunCharacterMenu,
    ovl16:0161, sets it); 1 is set by the Temple (VisitTemple, ovl04:0D09) and the shop (ShopMain,
    ovl06:053E), 2 by the camp (MakeCamp, ovl15:1E6F), 3 and 4 select the area view (ShowAreaView;
    whitepaper 5.2.1), 5 by combat (StartBattle and RunCombat) and 6 by the end of battle (EndBattle,
    ovl05:1527). }
  ViewModePlain = 0;
  ViewModePortrait = 1;
  ViewModeCamp = 2;
  ViewModeMap = 3;
  ViewModeView = 4;
  ViewModeCombat = 5;
  ViewModeLoot = 6;
  { The width of one area map page: DrawLocationLine adds this many columns of the 44-wide map grid
    per map page for AreaViewKind 3 (one page, added once) and 4 (two pages, added twice). }
  MapPageWidth = $D;
  { The keys SelectPartyMember's loop ends on: Enter and Escape leave the selection as it is, S does
    too (the hotkey of the prompt's "Select" word), and E exits the screen (the "Exit" hotkey,
    WithExit) and clears the selection. }
  KeyEnter = #13;
  KeyEscape = #27;
  KeyExit = 'E';
  KeySelect = 'S';
  { DrawCombatScreen: MoveCombatCursor's margin ($FF passes its view-scroll test) and direction
    (index 8 of DirStepX/DirStepY is (0,0), so the cursor stays on its cell), and the view origin's
    centre cell (the 7x7 view's middle, three cells from the origin). }
  CursorMargin = $FF;
  CursorNoStep = 8;
  ViewCentreCell = 3;
  { DrawArmourClass shows the armour class as the distance from ArmourClassBase (60): the stored
    ResistValue is 60 minus the AC (whitepaper 5.24; where the 60 comes from is not proven [?]). }
  ArmourClassBase = 60;
  { ShowHitMessage: the combat picture slots of an affect message (Flag set) and a damage message,
    and the delay after each drawn animation frame. }
  AffectHitIcon = $16;
  DamageHitIcon = $17;
  FlashDelay = $46;
  { The two per-character message boxes ShowCharacterMessage and ClearCharacterMessage write: in the
    combat view (ViewModeCombat) the box (CombatMessageLeft,CombatMessageRow) down to
    (CombatMessageRight,CombatMessageBottom), and elsewhere the box
    (MessageLeft,MessageTop)-(MessageRight,MessageBottom) with MessageFrameTop as the top when
    ShowCharacterMessage draws the frame. }
  CombatMessageLeft = $17;
  CombatMessageRight = $26;
  CombatMessageBottom = $15;
  CombatMessageRow = $A;
  MessageLeft = 1;
  MessageRight = $26;
  MessageTop = $12;
  MessageFrameTop = $11;
  MessageBottom = $16;
  { WalkCombatLine: a view cell is CellPitch (3) pixels (the 24x24 icon pitch); the view reaches
    ViewLimit (6) cells and ViewPixelLimit ($12) pixels from its origin, and a cursor more than
    CursorCentreMargin (3) cells from a cell scrolls the view (ovl31's CentreMargin). }
  CellPitch = 3;
  ViewLimit = 6;
  ViewPixelLimit = $12;
  CursorCentreMargin = 3;

{ 00BA:0000. Applies the readied weapon to Who's attack values; RecalcCombatValues calls it after it
  has copied the character's base values. With no readied weapon (SlotItems[0], +$CC) it does
  nothing. Otherwise the weapon's item kind picks a ItemTable row (DS:5582): its byte 9 becomes
  Who^.WeaponAttacks (+$115), byte $A Who^.WeaponDamage (+$117) and byte $B the base of the
  signed Who^.WeaponDamageBonus (+$119). The attack flags byte $E adds the dexterity roll
  adjustment (DexterityAttackAdjustment) to HitAdjust (+$110, reset to Thac0 +$2D first) when mask
  WeaponFlagDexToHit (2) is set, and the strength roll (StrengthAttackAdjustment) to HitAdjust and the
  strength damage (StrengthDamageAdjustment) to the damage bonus when mask WeaponFlagStrength (4) is set;
  mask WeaponFlagSlot11Plus (1) adds the plus of slot item 11 (+$F8) and mask WeaponFlagSlot12Plus
  ($80) the plus of slot item 12 (+$FC) to the weapon's own plus. Race BonusRace (2) gets one more
  point with the bonus kinds.
  Globals: ItemTable. }
procedure ApplyWeaponBonuses(Who: PCharacter);
var
  Weapon: PItem;
  ItemType: Byte;
  WeaponPlus: ShortInt;
begin
  Weapon := Who^.SlotItems[0];
  if Weapon = nil then
    Exit;
  ItemType := Weapon^.ItemType;
  Who^.HitAdjust := Who^.Thac0;
  if (ItemTable[ItemType].Flags and WeaponFlagDexToHit) <> 0 then
    Who^.HitAdjust := Who^.HitAdjust + DexterityAttackAdjustment(Who);
  Who^.WeaponDamageBonus[1] := ItemTable[ItemType].BonusNormal;
  if (ItemTable[ItemType].Flags and WeaponFlagStrength) <> 0 then
  begin
    Who^.HitAdjust := Who^.HitAdjust + StrengthAttackAdjustment(Who);
    Who^.WeaponDamageBonus[1] := Who^.WeaponDamageBonus[1] + StrengthDamageAdjustment(Who);
  end;
  WeaponPlus := Weapon^.Plus;
  if ItemTable[ItemType].Flags > $7F then
    if Who^.SlotItems[12] <> nil then
      WeaponPlus := WeaponPlus + Who^.SlotItems[12]^.Plus;
  if (ItemTable[ItemType].Flags and WeaponFlagSlot11Plus) > 0 then
    if Who^.SlotItems[11] <> nil then
      WeaponPlus := WeaponPlus + Who^.SlotItems[11]^.Plus;
  Who^.WeaponDamageBonus[1] := Who^.WeaponDamageBonus[1] + WeaponPlus;
  if (Who^.Race = BonusRace) and
     ((Weapon^.ItemType > BonusKindRangeLow) and (Weapon^.ItemType < BonusKindRangeHigh) or
      (Weapon^.ItemType = BonusKindLow) or (Weapon^.ItemType = BonusKindLower)) then
    Inc(WeaponPlus);
  Who^.HitAdjust := Who^.HitAdjust + WeaponPlus;
  Who^.WeaponAttacks[1] := ItemTable[ItemType].DiceCountNormal;
  Who^.WeaponDamage[1] := ItemTable[ItemType].DiceSizeNormal;
end;

{ 00BA:01FB. Sets Who's movement (Movement, +$11C) from a readied armour; RecalcCombatValues calls it
  for every readied item. It does nothing unless the item's kind (ItemTable[item type].Slot) is 2, an
  armour. Then the armour's weight (+$37) picks the movement: at most $96 keeps the character's
  base movement (BaseMovement, +$72), $97..$18F gives 9 and anything else 6. A magic armour
  (Plus, +$32, not 0) adds 3 while the movement is at most 9.
  Globals: ItemTable. }
procedure SetArmourMovement(Who: PCharacter; Item: PItem);
begin
  if ItemTable[Item^.ItemType].Slot = ArmourItemKind then
  begin
    case Item^.Weight of
      0..LightArmourWeight: Who^.Movement := Who^.BaseMovement;
      MediumArmourWeight..HeavyArmourWeight: Who^.Movement := MediumArmourMove;
    else
      Who^.Movement := HeavyArmourMove;
    end;
    if Item^.Plus <> 0 then
      if Who^.Movement <= MediumArmourMove then
        Who^.Movement := Who^.Movement + MagicArmourMoveBonus;
  end;
end;

{ 00BA:0282. Adds one readied item's bonuses into the accumulator Bonus (TBonus) that
  RecalcCombatValues keeps; called for every readied item after SetArmourMovement. Value is the item
  kind's bonus class (ItemTable[item type].BonusClass); with bit 7 clear the item contributes nothing. The
  item kind (ItemTable[item type].Slot) and Value pick what happens: a kind-1 item assigns
  Value + Plus to Bonus.KindBonus; otherwise Value 0 adds Plus to Bonus.PlusSum (a kind-9 item
  keeps the larger Plus in Bonus.BestPlus instead) and always adds the item's PlusSave (+$33) to
  Who^.SaveBonus; a Value above 0 keeps Value + Plus as the larger Bonus.BestValue and, for a
  positive plus on a kind-2 (armour) item, sets Flag.
  Globals: ItemTable. }
procedure AddReadiedItemBonus(Who: PCharacter; Item: PItem; var Bonus: TBonus; var Flag: Byte);
var
  Value: Byte;
  Kind: Byte;
begin
  Value := ItemTable[Item^.ItemType].BonusClass;
  if Value <= $7F then
    Exit;
  Value := Value and $7F;
  Kind := ItemTable[Item^.ItemType].Slot;
  if Kind = PlusItemKind then
  begin
    Bonus.KindBonus := Value + Item^.Plus;
    Exit;
  end;
  if Value = 0 then
  begin
    if Kind = SpecialItemKind then
    begin
      if Item^.Plus > Bonus.BestPlus then
        Bonus.BestPlus := Item^.Plus;
    end
    else
      Bonus.PlusSum := Bonus.PlusSum + Item^.Plus;
    Who^.SaveBonus := Who^.SaveBonus + Item^.PlusSave;
  end
  else
  begin
    if Value + Item^.Plus > Bonus.BestValue then
    begin
      Bonus.BestValue := Value + Item^.Plus;
      if (Item^.Plus > 0) and (Kind = ArmourItemKind) then
        Flag := 1;
    end;
  end;
end;

{ 00BA:03A0. Caps Who's movement by the weight the character carries above its strength
  allowance; RecalcCombatValues calls it once after the readied-item loop. Weight is
  CarriedWeight (+$102) minus StrengthWeightAllowance(Who) (the strength weight allowance), clamped at 0
  from below. The excess picks the cap: up to LightLoadLimit the movement is left alone, up to
  MediumLoadLimit it is MediumLoadMove (9), up to HeavyLoadLimit HeavyLoadMove (6), and above that
  OverloadMove (3); the movement only falls, never rises.
  Globals: none beyond Who. }
procedure CapMovementByLoad(Who: PCharacter);
var
  Weight: Integer;
  NewMovement: Byte;
begin
  Weight := Who^.CarriedWeight - StrengthWeightAllowance(Who);
  if Weight < 0 then
    Weight := 0;
  case Weight of
    0..LightLoadLimit: NewMovement := Who^.Movement;
    MediumLoadFrom..MediumLoadLimit: NewMovement := MediumLoadMove;
    HeavyLoadFrom..HeavyLoadLimit: NewMovement := HeavyLoadMove;
  else
    NewMovement := OverloadMove;
  end;
  if NewMovement < Who^.Movement then
    Who^.Movement := NewMovement;
end;

{ 00BA:0442. Builds an item menu line's display text in Item^.Text and, when ShowText is set,
  draws it at (Col, Row) in Green. Clears Text, then, when ShowReadied is set, prefixes ' Yes  '
  or ' No   ' from Readied. When any member of the party list ds5D96 has MagicMarkAffect (affect
  5, HasAffect), a Plus, PlusSave or Cursed item is marked '* '. A Count above 0 is written in
  front of the name. The three NameNum parts (ds10A7, 256 string[20] at DS:10A7) are appended
  from part 3 down to 1, skipping a part whose HiddenNames bit is set, and each shown part is
  followed by 's ' or ' '. The 's ' is used, once, when Count is at least 2 and this part is the
  only one shown, or part 1 is shown with part 3 also shown (Mask > ThirdNameBit) and the item
  type is not PluralOnThirdPartType ($56), or part 2 is shown while part 1 is not (not Odd(Mask):
  bit 0 of the mask is clear, 00BA:06A6), or part 3 is shown for PluralOnThirdPartType, or the
  item type is Slot11ItemType or Slot12ItemType and NameNum[3] is not NoPluralNameNum ($B1).
  Callers: the shop, loot and inventory lists (ShowText 0, they draw Text themselves) and the
  character sheet (ShowText 1).
  QUIRK 00BA:0442: the LongInt Value is never read (callers pass LongInt(the character) or 0).
  Globals: ds5D96 (read), ds10A7 (read). Side effects: Item^.Text, and the screen when ShowText
  is set. }
procedure FormatItemLine(Value: LongInt; Item: PItem; Col, Row, ShowReadied, ShowText: Byte);
var
  I: Byte;
  Mask: Byte;
  Affect: Pointer;
  Found: Byte;
  Plural: Byte;
  Member: PCharacter;
begin
  Item^.Text := '';
  if ShowReadied <> 0 then
  begin
    if Item^.Readied then
      Item^.Text := ' Yes  '
    else
      Item^.Text := ' No   ';
  end;
  Found := 0;
  Member := PCharacter(ds5D96);
  while (Member <> nil) and (Found = 0) do
  begin
    if HasAffect(Member, MagicMarkAffect, Affect) then
      Found := 1;
    Member := Member^.Next;
  end;
  if Found <> 0 then
    if (Item^.Plus > 0) or (Item^.PlusSave > 0) or Item^.Cursed then
      Item^.Text := Item^.Text + '*' + ' ';
  if Item^.Count > 0 then
    Item^.Text := Item^.Text + ByteToText(Item^.Count) + ' ';
  Mask := 0;
  for I := 1 to 3 do
    if (Item^.NameNum[I] <> 0) and (((Item^.HiddenNames shr (3 - I)) and 1) = 0) then
      Inc(Mask, 1 shl (I - 1));
  Plural := 0;
  for I := 3 downto 1 do
    if ((Mask shr (I - 1)) and 1) > 0 then
    begin
      Item^.Text := Item^.Text + ds10A7[Item^.NameNum[I]];
      if (Item^.Count < 2) or (Plural <> 0) then
        Item^.Text := Item^.Text + ' '
      else if ((1 shl (I - 1)) = Mask) or
              ((I = 1) and (Mask > ThirdNameBit) and
               (Item^.ItemType <> PluralOnThirdPartType)) or
              ((I = 2) and not Odd(Mask)) or
              ((I = 3) and (Item^.ItemType = PluralOnThirdPartType)) or
              (((Item^.ItemType = Slot11ItemType) or (Item^.ItemType = Slot12ItemType)) and
               (Item^.NameNum[3] <> NoPluralNameNum)) then
      begin
        Item^.Text := Item^.Text + 's ';
        Plural := 1;
      end
      else
        Item^.Text := Item^.Text + ' ';
    end;
  if ShowText <> 0 then
    DrawTextAt(Col, Row, Green, Item^.Text);
end;

{ 00BA:0767. Draws the roster panel the view screens show (whitepaper 5.24): a "Name / AC  HP"
  header and one line per party member of the list ds5D96. The member Who is drawn white from its
  Name, every other member through DrawCharacterName. Each line's armour value (DrawArmourClass) and
  current hit points (DrawHitPoints) are drawn in one of three columns picked by the value's range,
  and each line is cleared first. The left column is 1 in the plain full-window layout (ViewModePlain,
  the create-character and training screens, RunCharacterMenu ovl16:0161) and $11 in every other view: the shop and the
  Temple (ViewModePortrait, beside the portrait window), the camp and area views (RedrawView) and the
  loot screen. Callers: the shop, the Temple, RedrawView (camp, area view and loot), SelectPartyMember
  and DrawWildernessScreen. Globals: ds49F3 (read), ds5D96 (read). }
procedure DrawPartyRoster(Who: PCharacter);
var
  Member: PCharacter;
  Left: Byte;
  Row: Byte;
  ValueShift: Byte;
begin
  if ds49F3 = ViewModePlain then
    Left := 1
  else
    Left := $11;
  Row := 2;
  DrawTextAt(Left, Row, White, 'Name');
  DrawTextAt($21, Row, White, 'AC  HP');
  Inc(Row, 2);
  Member := PCharacter(ds5D96);
  while Member <> nil do
  begin
    ClearWindow(Left, Row, $26, Row);
    if Member = Who then
      DrawTextAt(Left, Row, White, Member^.Name)
    else
      DrawCharacterName(Member, Left, Row, 0);
    case Member^.ResistValue of
      0..$32: ValueShift := 1;
      $33..$3C: ValueShift := 2;
      $3D..$45: ValueShift := 1;
    else
      ValueShift := 0;
    end;
    DrawArmourClass(Member, ValueShift + $20, Row);
    case Member^.Flag11B of
      0..9: ValueShift := 2;
      $A..$63: ValueShift := 1;
    else
      ValueShift := 0;
    end;
    DrawHitPoints(Member, ValueShift + $24, Row, 0);
    Inc(Row);
    Member := Member^.Next;
  end;
  ClearWindow(Left, Row, $26, Row);
end;
{ 00BA:08EF. Draws the character's armour value (the byte +$111 ovl24's RollBeatsResistance compares a
  d20+level against; DrawCharacterPanel shows it under the "AC" heading) as text at (Col, Row) in
  Green: the distance from ArmourClassBase, Abs(Value - ArmourClassBase), written with a leading '-'
  when the value is above ArmourClassBase (a negative armour class). Called by DrawPartyRoster and
  DrawCharacterPanel. }
procedure DrawArmourClass(Who: PCharacter; Col, Row: Byte);
var
  ValueText: string;
  Unused: Byte;   { the original frame carries one byte here that the code never reads }
begin
  ValueText := ByteToText(Abs(Who^.ResistValue - ArmourClassBase));
  if Who^.ResistValue > ArmourClassBase then
    ValueText := '-' + ValueText;
  DrawTextAt(Col, Row, Green, ValueText);
end;

{ 00BA:0973. Draws Who's current hit points (Flag11B, +$11b) as text at (Col, Row). The colour is
  Yellow while the hit points are below the maximum (HpMax, +$32), Green at the maximum, and
  LightMagenta when Flag is set (the caller's highlight). Called by DrawPartyRoster and
  DrawCharacterPanel. }
procedure DrawHitPoints(Who: PCharacter; Col, Row, Flag: Byte);
var
  ValueColor: Byte;
  Unused: Byte;   { the original frame carries one byte here that the code never reads }
begin
  if Who^.Flag11B < Who^.HpMax then
    ValueColor := Yellow
  else
    ValueColor := Green;
  if Flag <> 0 then
    ValueColor := LightMagenta;
  DrawTextAt(Col, Row, ValueColor, ByteToText(Who^.Flag11B));
end;

{ 00BA:09E3. Draws the character panel the combat and inventory screens show (whitepaper 5.24): it
  clears the box ($17,1)-($26,$15), writes the name line through ShowCharacterMessage, the "Hitpoints" and
  "AC" headings with their values (DrawHitPoints, DrawArmourClass), the readied weapon's paged text
  (FormatItemLine then ShowPagedText) when a weapon is readied, and finally the status name
  (StatusNames[Status], +$10c) when the character takes no part in combat (Flag10D = 0), else
  "(Helpless)" when IsHelpless says so. The status row is not fixed: the routine stores
  GlyphRow := Row + 1 before the weapon test, ShowPagedText leaves GlyphRow past the lines the
  weapon text took, and the status is then drawn at GlyphRow + 2 (Row := GlyphRow + 1, then
  Row + 1), so the row follows the weapon text and the assignment is what makes the no-weapon path
  work.
  Globals: GlyphRow (written, then read after ShowPagedText leaves it past the weapon text).
  Side effects: video memory, the keyboard through ShowPagedText's paging. }
procedure DrawCharacterPanel(Who: PCharacter);
var
  Color: Byte;
  Row: Byte;
begin
  ClearWindow($17, 1, $26, $15);
  Row := 1;
  ShowCharacterMessage(Who, ' ', Row, 0);
  Inc(Row);
  DrawTextAt($17, Row + 1, Green, 'Hitpoints');
  DrawHitPoints(Who, $21, Row + 1, 0);
  Inc(Row, 2);
  DrawTextAt($17, Row + 1, Green, 'AC');
  DrawArmourClass(Who, $1A, Row + 1);
  GlyphRow := Row + 1;
  if Who^.SlotItems[0] <> nil then
  begin
    Inc(Row, 2);
    Color := $17;   { QUIRK 00BA:0AAE: the original stores Color here and never reads it }
    FormatItemLine(LongInt(Who), Who^.SlotItems[0], 0, 0, 0, 0);
    { QUIRK 00BA:0AE2: the bottom row is the three additions Row + 1 + 1 + 1 (three inc ax); the
      folded Row + 3 compiles to add ax, 3 and does not match the original }
    ShowPagedText($17, Row + 1, $26, Row + 1 + 1 + 1, Green, 1, Who^.SlotItems[0]^.Text);
  end;
  Row := GlyphRow + 1;
  if Who^.Flag10D = 0 then
    DrawTextAt($17, Row + 1, White, StatusNames[ShortInt(Who^.Status)])
  else
    if IsHelpless(Who) then
      DrawTextAt($17, Row + 1, White, '(Helpless)');
end;
{ 00BA:0B73. Returns whether Who is helpless: True when any of the four affects in
  HelplessAffects (DS:286B, entries 1..4) is on Who's affect list (HasAffect). DrawCharacterPanel
  shows '(Helpless)' when it is True; ovl13 skips a helpless combatant. Called by eight
  overlay routines and DrawCharacterPanel.
  Globals: HelplessAffects (read). }
function IsHelpless(Who: Pointer): Boolean;
var
  I: Byte;
  Affect: Pointer;
begin
  IsHelpless := False;
  for I := 1 to 4 do
    if HasAffect(Who, HelplessAffects[I], Affect) then
      IsHelpless := True;
end;
{ 00BA:0BB8. Recomputes every combat value of Who from the items it carries and has readied; called
  whenever a character's equipment or status changes (ovl03, ovl06, ovl08..ovl10, ovl12, ovl13,
  ovl16, ovl19, ovl21, ovl24).
  It clears the 13 per-kind slots (SlotItems, +$CC); walks the carried item list (Items, +$C8) to
  count the items (ItemCountC7, +$C7), add every item's Weight (+$37) times its Count (+$39) to
  CarriedWeight (+$102) and to the readied weight ReadiedItemWeight (DS:4846), and file each readied
  item into its slot (kind 0..8 into SlotItems[kind], kind 9 into the first free of slots 9 and 10,
  item type $49 into slot 11 and $1C into slot 12), raising HandsInUse (+$100) by the kind's
  ItemTable[item type].Hands. It adds the seven carried money words (Money, +$88, coins count one
  each) to the weight, copies the base attack triple (+$A3..+$A8) into the readied weapon triple
  (+$115..+$11A) and the base resistance (ResistBase, +$A9) into ResistValue (+$111), then clears the
  five accumulator bytes (TBonus), SaveBonus (+$101) and the armour-plus flag, sets Movement (+$11C)
  to BaseMovement (+$72) and HitAdjust (+$110) to Thac0 (+$2D), and stores the dexterity adjustment
  (DexterityAdjustment) in DexAdjust. With no readied weapon it adds the unarmed strength bonuses
  (StrengthAttackAdjustment, StrengthDamageAdjustment) to HitAdjust and the damage bonus, then runs
  ApplyWeaponBonuses. For every readied item it runs SetArmourMovement and AddReadiedItemBonus; a
  positive plus on a kind-2 (armour) item sets ArmourPlusFlag, and after the loop that flag clears
  Bonus.BestPlus (a magic armour drops the largest kind-9 plus; why is not proven [?]). A readied item
  whose NameNum[1] is BagNameNum instead counts ExcludedWeight (5000) less, floored at
  ReadiedItemWeight. CapMovementByLoad then caps Movement by the load, and only after that does
  BestValue reach its final value: it is first raised to the base ResistValue (so the armour base
  counts once), ResistValue becomes the sum of all five accumulator bytes (DexAdjust, KindBonus,
  PlusSum, BestPlus and BestValue), and ds112 (+$112) becomes BestValue + PlusSum + BestPlus - 2
  (DexAdjust and KindBonus do not go into it). Finally SweepAttacks (+$6B) is set: the fighter level
  (ClassLevels[2]) when it is above 0 and Race (+$2E) is above 0, else 1.
  Globals: reads ItemTable, writes ReadiedItemWeight, and reads and writes Who's Race, ClassLevels,
  Money and the fields SlotItems, ItemCountC7, HandsInUse, CarriedWeight,
  WeaponAttacks/WeaponDamage/WeaponDamageBonus, SaveBonus, ResistValue, Movement, HitAdjust, ds112
  and SweepAttacks. }
procedure RecalcCombatValues(Who: PCharacter);
var
  TripleIndex: Byte;
  BonusIndex: ShortInt;
  Item: PItem;
  ArmourPlusFlag: Byte;
  IgnoresWeight: Byte;
  Bonus: TBonus;
  SlotIndex: ShortInt;
  Unused: Byte;   { the original frame carries a byte no instruction of this routine reads }
  MoneyKind: ShortInt;
  Weight: Word;
  ItemKind: ShortInt;
begin
  for SlotIndex := 0 to 12 do
    Who^.SlotItems[SlotIndex] := nil;
  IgnoresWeight := 0;
  Who^.ItemCountC7 := 0;
  Item := Who^.Items;
  Who^.HandsInUse := 0;
  Who^.CarriedWeight := 0;
  ReadiedItemWeight := 0;
  while Item <> nil do
  begin
    Inc(Who^.ItemCountC7);
    Weight := Item^.Weight;
    if Item^.Count > 0 then
      Weight := Item^.Count * Weight;
    Inc(Who^.CarriedWeight, Weight);
    if Item^.Readied then
    begin
      Inc(ReadiedItemWeight, Weight);
      ItemKind := ItemTable[Item^.ItemType].Slot;
      { QUIRK 00BA:0C8C: ItemKind indexes SlotItems signed (cwde) but the case reads it
        unsigned (jb/ja), so the selector is written as the Byte view of the ShortInt }
      case Byte(ItemKind) of
        0..LastDirectSlotKind: Who^.SlotItems[ItemKind] := Item;
        SpecialItemKind:
          if Who^.SlotItems[SpecialItemKind] <> nil then
          begin
            if Who^.SlotItems[SpecialItemKind + 1] = nil then
              Who^.SlotItems[SpecialItemKind + 1] := Item;
          end
          else
            Who^.SlotItems[SpecialItemKind] := Item;
      end;
      if Item^.ItemType = Slot11ItemType then
        Who^.SlotItems[11] := Item;
      if Item^.ItemType = Slot12ItemType then
        Who^.SlotItems[12] := Item;
      if Item^.NameNum[1] = BagNameNum then
        IgnoresWeight := 1;
      Who^.HandsInUse := Who^.HandsInUse + ItemTable[Item^.ItemType].Hands;
    end;
    Item := Item^.Next;
  end;
  for MoneyKind := 0 to 6 do
    Who^.CarriedWeight := Who^.CarriedWeight + Who^.Money[MoneyKind];
  for TripleIndex := 1 to 2 do
  begin
    Who^.WeaponAttacks[TripleIndex] := Who^.BaseAttacks[TripleIndex];
    Who^.WeaponDamage[TripleIndex] := Who^.BaseDamage[TripleIndex];
    Who^.WeaponDamageBonus[TripleIndex] := Who^.BaseDamageBonus[TripleIndex];
  end;
  for BonusIndex := 0 to 4 do
    Bonus.Values[BonusIndex] := 0;
  ArmourPlusFlag := 0;
  Who^.SaveBonus := 0;
  Who^.ResistValue := Who^.ResistBase;
  Who^.Movement := Who^.BaseMovement;
  Who^.HitAdjust := Who^.Thac0;
  Bonus.DexAdjust := DexterityAdjustment(Who);
  if Who^.SlotItems[0] = nil then
  begin
    Who^.HitAdjust := Who^.HitAdjust + StrengthAttackAdjustment(Who);
    Who^.WeaponDamageBonus[1] := Who^.WeaponDamageBonus[1] + StrengthDamageAdjustment(Who);
  end;
  ApplyWeaponBonuses(Who);
  Item := Who^.Items;
  while Item <> nil do
  begin
    if Item^.Readied then
    begin
      SetArmourMovement(Who, Item);
      AddReadiedItemBonus(Who, Item, Bonus, ArmourPlusFlag);
    end;
    Item := Item^.Next;
  end;
  if ArmourPlusFlag <> 0 then
    Bonus.BestPlus := 0;
  if IgnoresWeight <> 0 then
  begin
    if Who^.CarriedWeight < ExcludedWeight then
      Who^.CarriedWeight := 0
    else
      Dec(Who^.CarriedWeight, ExcludedWeight);
    if Who^.CarriedWeight < ReadiedItemWeight then
      Who^.CarriedWeight := ReadiedItemWeight;
  end;
  CapMovementByLoad(Who);
  if Bonus.BestValue < Who^.ResistValue then
    Bonus.BestValue := Who^.ResistValue;
  Who^.ResistValue := 0;
  for BonusIndex := 0 to 4 do
    Who^.ResistValue := Who^.ResistValue + Bonus.Values[BonusIndex];
  Who^.ds112 := Bonus.BestValue + Bonus.PlusSum + Bonus.BestPlus - 2;
  if (Who^.ClassLevels[2] > 0) and (Who^.Race > 0) then
    Who^.SweepAttacks := Who^.ClassLevels[2]
  else
    Who^.SweepAttacks := 1;
end;
{ 00BA:1037. Formats the byte N as its decimal text: it writes N into a 255-character local through
  Str and copies that into the string result. DrawArmourClass and DrawHitPoints show the AC and
  hit-point values with it, and TwoDigitText (ovl20:0565) keeps the first two characters. }
function ByteToText(Value: Byte): string;
var
  Text: string[255];
begin
  Str(Value, Text);
  ByteToText := Text;
end;
{ 00BA:1073. Formats the word Value as its decimal text, the same way ByteToText does for a byte:
  Str into a 255-character local, copied into the string result. The shops and the Temple put
  prices and amounts into messages with it.
  Globals: none. }
function WordToText(Value: Word): string;
var
  Text: string[255];
begin
  Str(Value, Text);
  WordToText := Text;
end;
{ 00BA:10AD. Formats the LongInt Value as its decimal text, the same way ByteToText and WordToText
  do: Str into a 255-character local, copied into the string result. ovl19's character sheet
  (ShowCharacterSheet) writes the character's experience points (Experience, +$AC) with it.
  Globals: none. }
function LongIntToText(Value: LongInt): string;
var
  Text: string[255];
begin
  Str(Value, Text);
  LongIntToText := Text;
end;
{ 00BA:10E6. Returns the AD&D dexterity adjustment of Who's dexterity (Dexterity, +$13):
  dexterity 1..3 gives -4, 4..6 the dexterity minus 7, 7..14 gives 0, 15..18 the dexterity
  minus 14, 19..20 gives 4, 21..23 gives 5 and 24..25 gives 6. RecalcCombatValues stores it in
  the accumulator's first byte, which it sums into the character's combat value. }
function DexterityAdjustment(Who: PCharacter): Byte;
var
  Dex: Byte;
begin
  Dex := Who^.Dexterity;
  case Dex of
    DexBand1Low..DexBand1High: DexterityAdjustment := DexBand1Adjust;
    DexBand2Low..DexBand2High: DexterityAdjustment := Dex - DexBand2Offset;
    DexBand3Low..DexBand3High: DexterityAdjustment := Dex - DexBand3Offset;
    DexBand4Low..DexBand4High: DexterityAdjustment := DexBand4Adjust;
    DexBand5Low..DexBand5High: DexterityAdjustment := DexBand5Adjust;
    DexBand6Low..DexBand6High: DexterityAdjustment := DexBand6Adjust;
  else
    DexterityAdjustment := 0;
  end;
end;
{ 00BA:1168. Maps Who's dexterity (Dexterity, +$13) to its AD&D reaction/attack adjustment:
  dexterity 0..2 gives -4, 3..5 the dexterity minus 6, 6..15 gives 0, 16..18 the dexterity
  minus 15, 19..20 gives 3, 21..23 gives 4 and 24..25 gives 5. ApplyWeaponBonuses adds it to
  the attack value (HitAdjust) for a weapon kind whose attack flags carry mask WeaponFlagDexToHit
  (2). ovl13 also calls it. Globals: none. }
function DexterityAttackAdjustment(Who: PCharacter): ShortInt;
var
  Dex: Byte;
begin
  Dex := Who^.Dexterity;
  case Dex of
    0..2: DexterityAttackAdjustment := -4;
    3..5: DexterityAttackAdjustment := Dex - 6;
    $10..$12: DexterityAttackAdjustment := Dex - $F;
    $13..$14: DexterityAttackAdjustment := 3;
    $15..$17: DexterityAttackAdjustment := 4;
    $18..$19: DexterityAttackAdjustment := 5;
  else
    DexterityAttackAdjustment := 0;
  end;
end;
{ 00BA:11EA. Maps a character's strength (Strength, +$10) to a 0..30 row of the strength table:
  strength 0..17 is itself, strength 18 is 18 plus the exceptional strength (StrengthPercent,
  +$16: 0 gives 18, 1..50 gives 19, 51..75 gives 20, 76..90 gives 21, 91..99 gives 22 and 100
  gives 23), and strength 19..25 gives 24..30. StrengthAttackAdjustment, StrengthDamageAdjustment and StrengthWeightAllowance
  use it to look up the reaction, damage and weight allowances of a strength.
  QUIRK 00BA:1258: a strength above 25, or a strength-18 percentage above 100, leaves the result
  unassigned (the original returns whatever the frame held).
  Globals: none. }
function StrengthRowIndex(Who: PCharacter): Byte;
begin
  case Who^.Strength of
    0..$11: StrengthRowIndex := Who^.Strength;
    $12:
      case Who^.StrengthPercent of
        0: StrengthRowIndex := $12;
        1..$32: StrengthRowIndex := $13;
        $33..$4B: StrengthRowIndex := $14;
        $4C..$5A: StrengthRowIndex := $15;
        $5B..$63: StrengthRowIndex := $16;
        $64: StrengthRowIndex := $17;
      end;
    $13..$19: StrengthRowIndex := Who^.Strength + 5;
  end;
end;
{ 00BA:1282. Returns the strength reaction/attack adjustment of Who: StrengthRowIndex (00BA:11EA)
  maps the strength to a 0..30 table row and the row picks the bonus (1..3 gives -3, 4..5 -2,
  6..7 -1, 17..19 +1, 20..22 +2, 23..25 +3, 26..27 +4 and 28..30 the row minus 23; every other row
  gives 0). ApplyWeaponBonuses and RecalcCombatValues add it to HitAdjust. The whole adjustment is 0
  unless Who^.StrengthBonusFlag (+$AA) is nonzero. Globals: none. }
function StrengthAttackAdjustment(Who: PCharacter): ShortInt;
var
  Row: Byte;
begin
  StrengthAttackAdjustment := 0;
  Row := StrengthRowIndex(Who);
  if Who^.StrengthBonusFlag <> 0 then
    case Row of
      1..3: StrengthAttackAdjustment := -3;
      4..5: StrengthAttackAdjustment := -2;
      6..7: StrengthAttackAdjustment := -1;
      $11..$13: StrengthAttackAdjustment := 1;
      $14..$16: StrengthAttackAdjustment := 2;
      $17..$19: StrengthAttackAdjustment := 3;
      $1A..$1B: StrengthAttackAdjustment := 4;
      $1C..$1E: StrengthAttackAdjustment := Row - $17;
    end;
end;
{ 00BA:1325. Returns the strength damage adjustment of Who: StrengthRowIndex (00BA:11EA) maps the
  strength to a 0..30 table row and the row picks the damage bonus (1..2 gives -2, 3..5 -1, 16 +1,
  17..19 the row minus 16, 20..29 the row minus 17 and 30 +14; every other row gives 0).
  ApplyWeaponBonuses and RecalcCombatValues add it to WeaponDamageBonus. The whole adjustment is 0
  unless Who^.StrengthBonusFlag (+$AA) is nonzero. Globals: none. }
function StrengthDamageAdjustment(Who: PCharacter): ShortInt;
var
  Row: Byte;
begin
  StrengthDamageAdjustment := 0;
  Row := StrengthRowIndex(Who);
  if Who^.StrengthBonusFlag <> 0 then
    case Row of
      1..2: StrengthDamageAdjustment := -2;
      3..5: StrengthDamageAdjustment := -1;
      $10: StrengthDamageAdjustment := 1;
      $11..$13: StrengthDamageAdjustment := Row - $10;
      $14..$1D: StrengthDamageAdjustment := Row - $11;
      $1E: StrengthDamageAdjustment := 14;
    end;
end;
{ 00BA:13AB. Returns the weight a character of Who's strength can carry, in coins: StrengthRowIndex
  (00BA:11EA) maps the strength to a 0..30 table row and the row picks the allowance (rows 1..3
  give -350, 4..5 -250, 6..7 -150, 12..13 100, 14..15 200, 16 350, 17..21 (row-17)*250+500,
  22..26 (row-22)*1000+2000, 27 7500, 28..30 (row-28)*3000+9000, every other row 0).
  CapMovementByLoad subtracts it from the carried weight; ovl21's CarryLimit adds 1500 to it.
  Globals: none. }
function StrengthWeightAllowance(Who: PCharacter): Integer;
var
  Row: Byte;
  Unused: Byte;   { the original frame carries one byte here that the code never reads }
begin
  Row := StrengthRowIndex(Who);
  case Row of
    1..3: StrengthWeightAllowance := -350;
    4..5: StrengthWeightAllowance := -250;
    6..7: StrengthWeightAllowance := -150;
    $C..$D: StrengthWeightAllowance := 100;
    $E..$F: StrengthWeightAllowance := 200;
    $10: StrengthWeightAllowance := 350;
    $11..$15: StrengthWeightAllowance := (Row - $11) * $FA + $1F4;
    $16..$1A: StrengthWeightAllowance := (Row - $16) * $3E8 + $7D0;
    $1B: StrengthWeightAllowance := $1D4C;
    $1C..$1E: StrengthWeightAllowance := (Row - $1C) * $BB8 + $2328;
  else
    StrengthWeightAllowance := 0;
  end;
end;
{ 00BA:148B. Clears the spell Spell from the selected character's memorized spells (SelectedCharacter,
  DS:5D92; Spells at +$17, 21 slots 0..$14): it scans the slots and empties the first one that holds
  Spell. DealDamage calls it ("loses a pending spell"), ovl13 and ovl22 also call it. }
procedure ForgetSpell(Spell: Byte);
var
  I: Byte;
begin
  I := 0;
  while I <= $14 do
  begin
    if SelectedCharacter^.Spells[I] = Spell then
    begin
      SelectedCharacter^.Spells[I] := 0;
      I := $15;
    end;
    Inc(I);
  end;
end;
{ 00BA:1509. Removes Item from the carried-item list Who^.Items (+$C8) and frees the record:
  when Item is the head it re-points the head at Item^.Next, otherwise it walks the list for the
  record whose Next is Item; a nil Item or an Item not on the list only reports through
  ShowMessageLine. The item is unlinked (Item^.Next := nil) and freed (ItemListSize). Called by
  ovl07 LoseItems for every lost item, and by ovl13, ovl19 and ovl22 when an item is consumed.
  Globals: none. }
procedure RemoveInventoryItem(Who: PCharacter; Item: PItem);
var
  Prev: PItem;
begin
  if Item = nil then
    ShowMessageLine(Yellow, 'Nil Item pointer...')
  else
  begin
    Prev := Who^.Items;
    if Prev = Item then
      Who^.Items := Item^.Next
    else
      while (Prev <> nil) and (Prev^.Next <> Item) do
        Prev := Prev^.Next;
    if Prev = nil then
      ShowMessageLine(Yellow, 'Tried to Lose item & couldn''t find it!')
    else
    begin
      Prev^.Next := Item^.Next;
      Item^.Next := nil;
      FreeMem(Item, ItemListSize);
    end;
  end;
end;
{ 00BA:15F7. Allocates an item record (ItemListSize), deep-copies Item into it (Move) with its Next
  cleared, and appends it to the end of the carried-item list Who^.Items (+$C8); an empty list keeps
  the copy as the head. Used when a character is given a copy of an item, not the item itself.
  Globals: none. }
procedure AddItemCopy(Who: PCharacter; Item: PItem);
var
  Prev: PItem;
  NewItem: PItem;
begin
  GetMem(NewItem, ItemListSize);
  Move(Item^, NewItem^, ItemListSize);
  NewItem^.Next := nil;
  Prev := Who^.Items;
  if Prev = nil then
    Who^.Items := NewItem
  else
  begin
    while Prev^.Next <> nil do
      Prev := Prev^.Next;
    Prev^.Next := NewItem;
  end;
end;
{ 00BA:1693. Flashes Text on the bottom message line (row 24, columns 0..39) in green: clears the
  row, writes the text, waits DelayByGameSpeed, and clears the row again. No key is waited for.
  Called with 'Not enough money.', 'OverLoaded' and similar combat and shop notices.
  Globals: none. }
procedure ShowFlashMessage(Text: String40);
begin
  ClearWindow(0, BottomRow, ScreenLastCol, BottomRow);
  DrawTextAt(0, BottomRow, Green, Text);
  DelayByGameSpeed;
  ClearWindow(0, BottomRow, ScreenLastCol, BottomRow);
end;
{ 00BA:16EC. Shows a message about Who in a small window, its top Row in the combat view (view
  mode ViewModeCombat) and a fixed window otherwise; draws Who's name (DrawCharacterName) and the paged text Text
  (ShowPagedText) and, when Wait is set, delays DelayByGameSpeed and clears the window again
  (ClearCharacterMessage). Used for the per-character combat and camp messages ('is bandaged',
  'flees in panic', 'is cured'). Globals: ds49F3 (view mode), RestWindowActive (picks the window top).
  Side effects: video memory, the keyboard through ShowPagedText's paging. }
procedure ShowCharacterMessage(Who: PCharacter; Text: string; Row, Wait: Byte);
var
  Top: Byte;
begin
  if ds49F3 = ViewModeCombat then
  begin
    ClearWindow(CombatMessageLeft, Row, CombatMessageRight, CombatMessageBottom);
    DrawCharacterName(Who, CombatMessageLeft, Row, 0);
    ShowPagedText(CombatMessageLeft, Row + 1, CombatMessageRight, CombatMessageBottom, Green, 1, Text);
  end
  else
  begin
    if RestWindowActive <> 0 then
      Top := MessageTop
    else
    begin
      Top := MessageFrameTop;
      DrawWindowFrame(MessageLeft, Top, MessageRight, MessageBottom, 0);
    end;
    ClearWindow(MessageLeft, Top, MessageRight, MessageBottom);
    DrawCharacterName(Who, MessageLeft, Top + 1, 0);
    ShowPagedText(MessageLeft, Top + 1 + 1, MessageRight, MessageBottom, Green, 1, Text);
  end;
  if Wait <> 0 then
  begin
    DelayByGameSpeed;
    ClearCharacterMessage;
  end;
end;
{ 00BA:17E3. Clears the message window ShowCharacterMessage wrote in: in the combat view (ViewModeCombat)
  the box (CombatMessageLeft,CombatMessageRow)-(CombatMessageRight,CombatMessageBottom), otherwise the
  box (MessageLeft,MessageTop)-(MessageRight,MessageBottom). Called after the wait flag of
  ShowCharacterMessage and by the camp, temple and resting screens to wipe a message. Globals: ds49F3. }
procedure ClearCharacterMessage;
begin
  if ds49F3 = ViewModeCombat then
    ClearWindow(CombatMessageLeft, CombatMessageRow, CombatMessageRight, CombatMessageBottom)
  else
    ClearWindow(MessageLeft, MessageTop, MessageRight, MessageBottom);
end;
{ 00BA:1816. Draws Who's name (Name, +0) as text at (Col, Row) in the colour of Who's state:
  LightRed when Who takes no part in combat (Flag10D, +$10d = 0), Yellow for a monster
  (SideMonsters = 1) and LightCyan otherwise (the party, SideParty = 0). When Mode is set it appends "'s" after the name
  (at Col + Length(Name)). Called by the roster, the character panel and ovl13, ovl16, ovl19,
  ovl21 and ovl22. Globals: none. }
procedure DrawCharacterName(Who: PCharacter; Col, Row, Mode: Byte);
var
  Color: Byte;
begin
  if Who^.Flag10D = 0 then
    Color := LightRed
  else
    if Who^.Side = SideMonsters then
      Color := Yellow
    else
      Color := LightCyan;
  DrawTextAt(Col, Row, Color, Who^.Name);
  if Mode <> 0 then
    DrawTextAt(Col + Length(Who^.Name), Row, Color, '''s');
end;
{ 00BA:1892. Copies one row of a 24x3 picture into the combat picture ds6E36. PicIndex selects a
  slot of the picture table ds5E5A and Half picks one of the slot's two pointers
  (ds5E5A[PicIndex].Pics[Half]); Row is the destination row, copied at byte offset Row times the
  picture's bytes-per-item (ByteSize, +$11). When Mirror is not 0 the source picture is first
  mirrored into a temporary 24x3 picture (AllocatePicture then MirrorPicture) and that copy is
  blitted, otherwise the table picture is blitted directly. In both cases the bitmap (Data, +$17)
  is copied with RowBytes bytes and the pixel buffer (Pixels, +$13) with PixelBytes, a quarter of
  RowBytes on the EGA (VideoAdapterEga, 1: the EGA layout holds one plane byte per four data bytes,
  whitepaper 5.23). ReleasePicture frees the temporary.
  Called in a loop by DrawCombatIcon and by ovl13.
  Globals: ds6E36 (read), ds5E5A (read), VideoAdapter (read). }
procedure CopyPictureItem(PicIndex, Half, Row, Mirror: Byte);
var
  Pic: Pointer;
  PixelBytes, RowBytes: Word;
begin
  RowBytes := PPicture(ds6E36)^.ByteSize;
  PixelBytes := RowBytes;
  if VideoAdapter = VideoAdapterEga then
    PixelBytes := PixelBytes div 4;
  if Mirror <> 0 then
  begin
    AllocatePicture($18, 3, 1, 1, Pic);
    MirrorPicture(ds5E5A[PicIndex].Pics[Half], Pic);
    Move(PPicture(Pic)^.Data[0], PPicture(ds6E36)^.Data[Row * RowBytes], RowBytes);
    Move(PPicture(Pic)^.Pixels^[0], PPicture(ds6E36)^.Pixels^[Row * PixelBytes], PixelBytes);
    ReleasePicture(Pic);
  end
  else
  begin
    Move(PPicture(ds5E5A[PicIndex].Pics[Half])^.Data[0], PPicture(ds6E36)^.Data[Row * RowBytes], RowBytes);
    Move(PPicture(ds5E5A[PicIndex].Pics[Half])^.Pixels^[0], PPicture(ds6E36)^.Pixels^[Row * PixelBytes], PixelBytes);
  end;
end;
{ 00BA:19DE. Draws the four items of a 2-wide combat icon into the combat picture ds6E36: it calls
  CopyPictureItem four times with Half 0, 0, 1, 1 and Row 0, 1, 2, 3, mirroring the second and
  third item (Mirror 0, 1, 1, 0). PicIndex is the source slot in the picture table ds5E5A.
  Called by ovl12, ovl13 and ovl22 (a combatant's icon into the battle picture). Globals: none. }
procedure DrawCombatIcon(PicIndex: Byte);
begin
  CopyPictureItem(PicIndex, 0, 0, 0);
  CopyPictureItem(PicIndex, 0, 1, 1);
  CopyPictureItem(PicIndex, 1, 2, 1);
  CopyPictureItem(PicIndex, 1, 3, 0);
end;
{ 00BA:1A29. Walks the line from cell (FromX, FromY) to cell (ToX, ToY) and animates the combat cursor
  along it (whitepaper 5.18, combat movement). It builds the Bresenham path between the two cells
  (multiplied by CellPitch, 3, the 24x24 icon pitch) through SetupLine/StepLine, collecting each step's
  direction Pattern into Path. It then walks that path: it computes the screen cell (PX, PY), draws
  the combat picture ds6E36 onto the staging buffer DrawBuf through DrawPictureItemClipped (frame Frame of
  Count), flushes and delays, steps PX/PY by DirStepX/DirStepY[Path[I]], and keeps the cursor on
  the cell (CursorX, CursorY) through MoveCombatCursor. The Mode byte > 0 forces drawing every
  step; Count is the number of animation frames. Count/Mode/position come from ovl12, ovl13 and
  ovl22 (the aiming and movement code).
  Globals: CombatMap (read), ds6E36 (read), DrawBuf (read), ds4A24 (read), DirStepX, DirStepY.
  Calls ovl30's line routines and ovl31's cursor/view routines. Side effects: video memory, timing. }
procedure WalkCombatLine(FromX, FromY, ToX, ToY: ShortInt; Count, Mode: Byte);
var
  Path: array[0..$93] of Byte;    { [bp-$94] the direction code of each step of the line }
  Line: TLineState;               { [bp-$ae] the Bresenham line state }
  PadA, PadB: Byte;               { [bp-$af, bp-$b0] frame bytes the code never reads }
  PathLen: Byte;                  { [bp-$b1] the current index into Path }
  PathCount: Byte;                { [bp-$b2] the number of steps in Path }
  Frame: Byte;                    { [bp-$b3] the animation frame, 0..Count-1 }
  PadC: Byte;                     { [bp-$b4] a frame byte the code never reads }
  LoopFlag: Boolean;              { [bp-$b5] repeat the walk when False }
  Done: Boolean;                  { [bp-$b6] the walk left the 19x19 view }
  CursorX, CursorY: ShortInt;     { [bp-$b7, bp-$b8] the cursor cell }
  StartX, StartY: ShortInt;       { [bp-$b9, bp-$ba] the cell the walk started at }
  AccX, AccY: ShortInt;           { [bp-$bb, bp-$bc] the sub-cell pixel accumulators }
  DeltaX, DeltaY: ShortInt;       { [bp-$bd, bp-$be] ToX-FromX and ToY-FromY }
  DXStep, DYStep: ShortInt;       { [bp-$bf, bp-$c0] the current step direction }
  PX, PY: ShortInt;               { [bp-$c1, bp-$c2] the current icon pixel position }
begin
  StartX := FromX;
  StartY := FromY;
  FillChar(Path, $94, 8);
  FillChar(Line, $1a, 0);
  PathLen := 0;
  Frame := 0;
  Line.X1 := FromX * CellPitch;
  Line.Y1 := FromY * CellPitch;
  Line.X2 := ToX * CellPitch;
  Line.Y2 := ToY * CellPitch;
  SetupLine(@Line);
  repeat
    Done := not StepLine(@Line);
    Path[PathLen] := Line.Pattern;
    Inc(PathLen);
  until Done;
  PathCount := PathLen;
  if PathCount < 2 then
    Exit;
  DeltaX := ToX - FromX;
  DeltaY := ToY - FromY;
  if not (IsInView(FromX - CombatMap^.ViewX, FromY - CombatMap^.ViewY) and
          IsInView(ToX - CombatMap^.ViewX, ToY - CombatMap^.ViewY)) then
  begin
    if (Abs(DeltaX) <= ViewLimit) and (Abs(DeltaY) <= ViewLimit) then
    begin
      LoopFlag := True;
      CursorX := FromX + DeltaX div 2;
      CursorY := FromY + DeltaY div 2;
    end
    else
    begin
      LoopFlag := False;
      CursorX := CombatMap^.ViewX + ViewCentreCell;
      CursorY := CombatMap^.ViewY + ViewCentreCell;
    end;
  end
  else
  begin
    LoopFlag := True;
    CursorX := CombatMap^.ViewX + ViewCentreCell;
    CursorY := CombatMap^.ViewY + ViewCentreCell;
  end;
  MoveCombatCursor(CursorX, CursorY, CursorMargin, CursorNoStep);
  PathLen := 0;
  AccX := 0;
  AccY := 0;
  repeat
    PX := (FromX - CombatMap^.ViewX) * CellPitch + AccX;
    PY := (FromY - CombatMap^.ViewY) * CellPitch + AccY;
    StartX := FromX;
    StartY := FromY;
    Done := False;
    repeat
      if (Mode > 0) or (PX mod CellPitch = 0) or (PY mod CellPitch = 0) then
      begin
        DrawPictureItemClipped(PX, PY, Frame, 5, ds6E36, DrawBuf);
        FlushPictureChanges;
        Delay(Mode);
        DrawPictureItemClipped(PX, PY, 0, 0, ds4A24, DrawBuf);
        Inc(Frame);
        if Frame >= Count then
          Frame := 0;
      end;
      Inc(PathLen);
      DXStep := DirStepX[Path[PathLen]];
      DYStep := DirStepY[Path[PathLen]];
      Inc(PX, DXStep);
      Inc(PY, DYStep);
      if (PX < 0) or (PX > ViewPixelLimit) or (PY < 0) or (PY > ViewPixelLimit) then
        Done := True;
      if (not Done) and (PathLen < PathCount) then
      begin
        Inc(AccX, DXStep);
        Inc(AccY, DYStep);
        if Abs(AccX) = CellPitch then
        begin
          Inc(FromX, SignOf(AccX));
          Inc(CursorX, SignOf(AccX));
          AccX := 0;
        end;
        if Abs(AccY) = CellPitch then
        begin
          Inc(FromY, SignOf(AccY));
          Inc(CursorY, SignOf(AccY));
          AccY := 0;
        end;
      end;
    until (PathLen >= PathCount) or Done;
    if PathLen < PathCount then
    begin
      DeltaX := SignOf(StartX - FromX);
      DeltaY := SignOf(StartY - FromY);
      if DeltaX <> 0 then
      begin
        if FromX >= CombatMap^.ViewX + ViewLimit then
          CursorX := FromX + CursorCentreMargin
        else if FromX <= CombatMap^.ViewX then
          CursorX := FromX - CursorCentreMargin;
      end;
      if DeltaY <> 0 then
      begin
        if FromY >= CombatMap^.ViewY + ViewLimit then
          CursorY := FromY + CursorCentreMargin
        else if FromY <= CombatMap^.ViewY then
          CursorY := FromY - CursorCentreMargin;
      end;
      MoveCombatCursor(CursorX, CursorY, CursorMargin, CursorNoStep);
    end
    else
    begin
      LoopFlag := True;
      if not IsInView(ToX - CombatMap^.ViewX, ToY - CombatMap^.ViewY) then
        MoveCombatCursor(ToX, ToY, CursorCentreMargin, CursorNoStep);
      PX := (ToX - CombatMap^.ViewX) * CellPitch;
      PY := (ToY - CombatMap^.ViewY) * CellPitch;
      DrawPictureItemClipped(PX, PY, Frame, 5, ds6E36, DrawBuf);
      if Mode > 0 then
      begin
        FlushPictureChanges;
        Delay(Mode);
        DrawPictureItemClipped(PX, PY, 0, 0, ds4A24, DrawBuf);
      end;
    end;
  until LoopFlag;
  FlushPictureChanges;
end;
{ 00BA:1FEB. Shows a per-character combat message and flashes the character's combat icon over
  its view cell. Outside the combat view (ViewModeCombat) it only shows the message Text with a wait
  and returns. In the combat view: silences the sound driver, draws the combat icon slot AffectHitIcon
  ($16) when Flag is set and DamageHitIcon ($17) otherwise, puts the combat cursor on the character
  when it is off screen, plays the sound ds261C when Flag is set and ds261A otherwise, and shows Text
  without waiting. It then flashes the character's icon: for FlashCount + 1 passes it draws the four
  picture items (0..3) of the combat picture ds6E36 at the character's pixel position (CellPitch, 3,
  pixels per view cell, CombatantViewCol/CombatantViewRow), flushes and waits FlashDelay ($46) ms, and
  restores the cell from ds4A24. Finally it resumes the sound driver and flushes; with Flag clear
  (FlashCount 0) it waits DelayByGameSpeed instead. DealDamage calls it with Flag 0 for the damage
  message, ApplyAffect with Flag 1 for an affect message, and the training code uses it too.
  Globals: ds49F3 (view mode), GameSpeed (FlashCount), ds261A/ds261C (sounds), ds6E36, ds4A24,
  DrawBuf, CombatantViewCol, CombatantViewRow. Side effects: video memory, sound, timing. }
procedure ShowHitMessage(Who: Pointer; Flag: Byte; Text: String40);
var
  Col, Row: ShortInt;
  Icon: Byte;
  Frame, Pass: Byte;
  FlashCount: Byte;
begin
  if ds49F3 = ViewModeCombat then
  begin
    SetSoundDriverIdle(0);
    if Flag <> 0 then
      Icon := AffectHitIcon
    else
      Icon := DamageHitIcon;
    DrawCombatIcon(Icon);
    if not IsCombatantInView(Who, 1) then
      MoveCombatCursor(CombatantX(Who), CombatantY(Who), CursorCentreMargin, CursorNoStep);
    if Flag <> 0 then
      PlaySound(ds261C)
    else
      PlaySound(ds261A);
    ShowCharacterMessage(Who, Text, CombatMessageRow, 0);
    if Flag <> 0 then
      FlashCount := GameSpeed
    else
      FlashCount := 0;
    Col := CombatantViewCol[CombatantIndex(Who)] * CellPitch;
    Row := CombatantViewRow[CombatantIndex(Who)] * CellPitch;
    for Pass := 0 to FlashCount do
      for Frame := 0 to 3 do
      begin
        DrawPictureItemClipped(Col, Row, Frame, 5, ds6E36, DrawBuf);
        FlushPictureChanges;
        Delay(FlashDelay);
        DrawPictureItemClipped(Col, Row, 0, 0, ds4A24, DrawBuf);
      end;
    SetSoundDriverIdle($A);
    FlushPictureChanges;
    if FlashCount = 0 then
      DelayByGameSpeed;
  end
  else
    ShowCharacterMessage(Who, Text, CombatMessageRow, 1);
end;
{ 00BA:2199. Returns whether Who has the affect AffectId on its affect list (TCharacter.Affects, +$7F).
  It leaves in the caller's Affect the matching affect record when found, or the nil end of the list
  otherwise (the callers only test the result). The list is walked until Found or the end. Called by
  CureBlindness, CureDisease, NeutralizePoison, RemoveCurse and the movement, step and campaign code.
  Globals: none. }
function HasAffect(Who: Pointer; AffectId: Byte; var Affect: Pointer): Boolean;
var
  Found: Boolean;
begin
  Found := False;
  Affect := PCharacter(Who)^.Affects;
  while (Affect <> nil) and not Found do
  begin
    if PAffect(Affect)^.Id = AffectId then
      Found := True
    else
      Affect := PAffect(Affect)^.Next;
  end;
  HasAffect := Found;
end;
{ 00BA:2228. Applies Damage hit points to Who and updates its status. It computes Overkill =
  Damage - HpCurrent when the damage exceeds Who's current hit points (Flag11B, +$11B) and
  Remaining = HpCurrent - Damage otherwise (the other stays 0, so Remaining = 0 whenever the
  damage is at or above HpCurrent; that is the code's "reaches 0 or below"). The status tests run
  in this order: dead (StatusDead) when the overkill is above 9, or when Remaining = 0 and Who was
  already StatusAnimated (an animated character is Dead for every blow that reaches 0 or below,
  never Dying); otherwise dying (StatusDying) when there is any overkill, recording the overkill in
  Combat^.DyingRounds (+$E) in the combat view; otherwise unconscious (StatusUnconscious) when
  Remaining = 0, that is an exact hit to 0. When the resulting status is not the standing set
  StatusOkay + StatusAnimated Who leaves combat: Flag10D and the hit points are cleared and, in the
  combat view, its side's count (ds6814Sides, by Side) and its initiative (Combat^.Initiative, +$3)
  drop; a standing character just takes Remaining as its hit points. DealDamage, DamageWithMessage
  and ovl13 call it. Globals: ds49F3 (view mode), ds6814Sides. }
procedure ApplyDamage(Who: Pointer; Damage: Byte);
var
  Overkill, Remaining: Byte;
begin
  Overkill := 0;
  Remaining := 0;
  if PCharacter(Who)^.Flag11B >= Damage then
    Remaining := PCharacter(Who)^.Flag11B - Damage
  else
    Overkill := Damage - PCharacter(Who)^.Flag11B;
  if (Overkill > 9) or ((Remaining = 0) and (PCharacter(Who)^.Status = StatusAnimated)) then
    PCharacter(Who)^.Status := StatusDead
  else if Overkill > 0 then
  begin
    PCharacter(Who)^.Status := StatusDying;
    if ds49F3 = ViewModeCombat then
      PCharacter(Who)^.Combat^.DyingRounds := Overkill;
  end
  else if Remaining = 0 then
    PCharacter(Who)^.Status := StatusUnconscious;
  if not (PCharacter(Who)^.Status in [StatusOkay, StatusAnimated]) then
  begin
    PCharacter(Who)^.Flag10D := 0;
    PCharacter(Who)^.Flag11B := 0;
    if ds49F3 = ViewModeCombat then
    begin
      Dec(ds6814Sides[ShortInt(PCharacter(Who)^.Side)]);
      PCharacter(Who)^.Combat^.Initiative := 0;
    end;
  end
  else
    PCharacter(Who)^.Flag11B := Remaining;
end;
{ 00BA:234A. Shows how far a heal brought Who: "is fully healed" when its current hit points (the
  byte +$11B) equal its maximum (HpMax, +$32) and "is partially healed" otherwise, through
  ShowCharacterMessage with a wait. Outside the combat view it then redraws the party roster
  (DrawPartyRoster) for the selected character. ovl12 and ovl22 (the healing and training code)
  call it. Globals: ds49F3 (view mode), SelectedCharacter. }
procedure ShowHealResult(Who: Pointer);
var
  Message: String40;
begin
  if PCharacter(Who)^.Flag11B = PCharacter(Who)^.HpMax then
    Message := 'is fully healed'
  else
    Message := 'is partially healed';
  ShowCharacterMessage(Who, Message, CombatMessageRow, 1);
  if ds49F3 <> ViewModeCombat then
    DrawPartyRoster(SelectedCharacter);
end;
{ 00BA:23B7. Returns the side opposite Who's (Side, +$10E): 1 when Who is on the party side (0) and
  0 otherwise. The combat AI indexes the per-side counts ds6814Sides with it to count Who's
  enemies (UseMagicItem, CastMemorizedSpell, DifferentSideInArea) and ovl12/ovl13/ovl22 use it
  too. Globals: none. }
function OpposingSide(Who: Pointer): Byte;
begin
  if PCharacter(Who)^.Side = SideParty then
    OpposingSide := SideMonsters
  else
    OpposingSide := SideParty;
end;
{ 00BA:23DB. Recounts the living combatants of each side: it clears both per-side counts
  (ds6814Sides) and walks the character list (ds5D96) adding one for every member that takes part
  in combat (Flag10D, +$10D, set) to its own side's count. RunCombat and EndCombatRound call it at
  the start of a battle and each round; PlaceAllCombatants and ReviveCombatant also call it.
  Globals: ds5D96 (read), ds6814Sides (write). }
procedure RecountCombatSides;
var
  Member: PCharacter;
begin
  ds6814Sides[SideParty] := 0;
  ds6814Sides[SideMonsters] := 0;
  Member := PCharacter(ds5D96);
  while Member <> nil do
  begin
    if Member^.Flag10D <> 0 then
      Inc(ds6814Sides[ShortInt(Member^.Side)]);
    Member := Member^.Next;
  end;
end;
{ 00BA:2433. Collects Who's enemies that an area scan can reach into the target list ds6DE4 and
  returns how many there are. It scans the map for every combatant whose footprint line from Who is
  at most Range steps away (ScanTargets, direction omni, footprint kind of Who), then keeps only the
  records whose combatant is on the side opposite Who's (Side of CombatantRecord[ds6718[I].Head]
  equals OpposingSide(Who)): each kept record is compacted into ds6718 (Move) and the table count
  (ds6718[0].Val) is lowered to the kept count. Finally the combatant index of every kept record
  (ds6718[I].Head) is written into ds6DE4[1..Count], the combatant order the AI and the area spells
  work through (ovl09:02EB, 0B3C). The result is that count; 0 when no enemy is in range. }
function CollectEnemiesInRange(Who: Pointer; Range: Byte): Byte;
var
  Count: Byte;    { [bp-2] the scan count, then the kept count }
  Found: Byte;    { [bp-3] the kept records so far }
  Index: Byte;    { [bp-4] the walk of the scan table }
begin
  ScanTargets(CombatantX(PCharacter(Who)), CombatantY(PCharacter(Who)), Range, $FF,
              CombatantKind(PCharacter(Who)), CombatMap);
  Count := ds6718[0].Val;
  Found := 0;
  if Count > 0 then
  begin
    for Index := 1 to Count do
      if CombatantRecord[ds6718[Index].Head]^.Side = OpposingSide(Who) then
      begin
        Inc(Found);
        Move(ds6718[Index], ds6718[Found], SizeOf(TSortRec));
      end;
    Count := Found;
    ds6718[0].Val := Found;
  end;
  CollectEnemiesInRange := Count;
  for Index := 1 to Count do
    ds6DE4[Index] := ds6718[Index].Head;
end;
{ 00BA:255B. Returns half the distance, in map steps, of Target from Who. It preserves the current
  scan result (ds6718, the 72 records ScanTargets can fill), opens the WalkLine tile gate
  (CombatMap^.Head6, +6) so the line is not blocked by the tile the combatants stand on, scans from
  Who (ScanTargets over $FF steps, direction omni, footprint kind of Who), closes the gate again,
  and looks Target up among the found combatants (CombatantRecord[ds6718[I].Head] = Target; the
  first index I with a match, or the scan count when it is not found). The result is that record's
  shortest walk length (Key, the fewest WalkLine steps) divided by two, the distance in map cells;
  ovl09:0B3C and others test it = 1 as melee range. The saved records are put back before the
  return. Globals: ds6718 (read/write), CombatMap (write), CombatantRecord (read).
  QUIRK 00BA:2617: when Target is not found the result comes from the record at the scan count
  (or from record 1 when nothing was found), not from a defined value. }
function DistanceToTarget(Who, Target: Pointer): Byte;
var
  Saved: array[1..255] of TSortRec;   { [bp-$2fe] the scan table saved around the scan }
  Index: Byte;                        { [bp-$2ff] the walk of the scan table }
begin
  Move(ds6718[1], Saved, SavedScanBytes);
  CombatMap^.Head6 := 1;
  ScanTargets(CombatantX(PCharacter(Who)), CombatantY(PCharacter(Who)), $FF, $FF,
              CombatantKind(PCharacter(Who)), CombatMap);
  CombatMap^.Head6 := 0;
  Index := 1;
  while (CombatantRecord[ds6718[Index].Head] <> PCharacter(Target)) and
        (Index < ds6718[0].Val) do
    Inc(Index);
  DistanceToTarget := ds6718[Index].Key shr 1;
  Move(Saved, ds6718[1], SavedScanBytes);
end;
{ 00BA:2637. Ends Who's combat turn: it clears the pending spell (PendingSpell, +$0; CastChosenSpell
  casts it when the turn ends), the turn order (Initiative, +$3), the guard byte (B7, +$7; the Guard
  command of the Done menu sets it to 1) and the movement left (Moves, +$6), then returns 1 (the
  turn is over). The Done menu's Quit command, every "the turn ends" path of the AI and the self-end
  checks call it (ovl08:031A, 09DF, 0E45; ovl09:000F, 07F2, 0B3C, 10D7; ovl12; ovl13).
  Globals: none. }
function EndCombatTurn(Who: Pointer): Byte;
begin
  PCharacter(Who)^.Combat^.Initiative := 0;
  PCharacter(Who)^.Combat^.PendingSpell := 0;
  PCharacter(Who)^.Combat^.B7 := 0;
  PCharacter(Who)^.Combat^.Moves := 0;
  EndCombatTurn := 1;
end;
{ 00BA:2686. Guards: ends Who's combat turn (EndCombatTurn) so the initiative, movement and pending
  spell are gone, then sets the guard byte (Combat^.B7, +$7) to 1 and flashes 'Guarding' on the
  bottom line (ShowFlashMessage). The Done menu's Guard command (ovl08:0E45) and ovl09_fn_0F4F
  (the AI's fallback when the character has nothing to do) call it; the return value is the 1
  EndCombatTurn gives, so the turn is over. Globals: none. }
function GuardTurn(Who: Pointer): Byte;
begin
  GuardTurn := EndCombatTurn(Who);
  PCharacter(Who)^.Combat^.B7 := 1;
  ShowFlashMessage('Guarding');
end;
{ 00BA:26C2. Returns the level the selected character casts a spell at: the spell's class
  (SpellTable[Spell].SpellClass, byte 0 of the 16-byte row; SpellClassCleric 0, SpellClassMagicUser 1) picks the
  character's level in that class (ClassLevels: ClassCleric 0, ClassMagicUser 5; whitepaper 5.6), and a spell
  class SpellClassFixed (2) gives SpecialSpellLevel (12). When ItemAffectUse is set every class except
  SpellClassFixed gives ItemSpellLevel (6) instead. SpellAreaSize multiplies the
  spell row's +3 byte by the result, so this is the power the spell is cast with; the res12 wrapper
  takes the spell number. Called by the ovl22 casting routines.
  Purpose unknown: what spell class SpellClassFixed and ItemAffectUse are.
  QUIRK 00BA:26FB: a spell class other than SpellClassCleric, SpellClassMagicUser or SpellClassFixed
  leaves the result unassigned (the frame byte is returned).
  Globals: SpellTable, SelectedCharacter (read), ItemAffectUse (read). }
function SpellCasterLevel(Spell: Byte): Byte;
begin
  case SpellTable[Spell].SpellClass of
    SpellClassCleric: SpellCasterLevel := SelectedCharacter^.ClassLevels[ClassCleric];
    SpellClassMagicUser: SpellCasterLevel := SelectedCharacter^.ClassLevels[ClassMagicUser];
    SpellClassFixed: SpellCasterLevel := SpecialSpellLevel;
  end;
  if ItemAffectUse and (SpellTable[Spell].SpellClass <> SpellClassFixed) then
    SpellCasterLevel := ItemSpellLevel;
end;
{ 00BA:272A. Draws the window frames of a view screen (one DrawWindow each): the full screen
  (1,1)-(38,22), the bottom text window (1,17)-(38,22) and the upper-left window (1,1)-(15,15);
  when WithInner is set it also draws the inner window (3,3)-(13,13) that frames the character
  portrait or the 3D view. RedrawView calls it before drawing the portrait, the sprites or the
  area view. Side effect: the screen (DrawWindow clears and frames each window). }
procedure DrawViewWindows(WithInner: Byte);
begin
  DrawWindow(1, 1, $26, $16, 0, $F, '');
  DrawWindow(1, $11, $26, $16, 0, $F, '');
  DrawWindow(1, 1, $F, $F, 0, $F, '');
  if WithInner <> 0 then
    DrawWindow(3, 3, $D, $D, 0, $F, '');
end;
{ 00BA:27D9. Redraws the whole screen for the current view mode (ds49F3), the resident unit's view
  dispatcher. Mode 0 is the plain full window; mode 1 the character portrait screen
  (DrawViewWindows then the HEAD and BODY sprites at (3,3)); mode 2 the camp (the portrait
  windows, the PIC sprite list and the roster); modes 3 and 4 the area view (DrawViewWindows,
  ShowAreaView and the roster, the inner window drawn only for mode 4); mode 6 the loot screen
  (the portrait windows, the PIC block 1 sprites and the roster). Modes 2, 3 and 4 draw the
  character roster and the location line, mode 6 the roster only; modes 0 and 1 draw neither
  (mode 1 shows the portrait). Called by the shop, the Temple, the loot, camp and combat menus to
  redraw their screen.
  Globals: ds49F3 (read), ds49FD, ds49FE, PictureAnimation, SelectedCharacter (read). }
procedure RedrawView;
begin
  case ds49F3 of
    ViewModePlain: DrawWindow(1, 1, $26, $16, 0, $F, '');
    ViewModePortrait:
      begin
        DrawViewWindows(1);
        LoadHeadBodySprites(ds49FD, ds49FE);
        ShowHeadBodySprites(3, 3, 1);
      end;
    ViewModeCamp:
      begin
        DrawViewWindows(1);
        LoadSpriteList('PIC', $1D, 0, @PictureAnimation);
        DrawPartyRoster(SelectedCharacter);
        DrawLocationLine;
      end;
    ViewModeView:
      begin
        DrawViewWindows(1);
        ShowAreaView;
        DrawPartyRoster(SelectedCharacter);
        DrawLocationLine;
      end;
    ViewModeMap:
      begin
        DrawViewWindows(0);
        ShowAreaView;
        DrawPartyRoster(SelectedCharacter);
        DrawLocationLine;
      end;
    ViewModeLoot:
      begin
        DrawViewWindows(1);
        LoadSpriteList('PIC', 1, 0, @PictureAnimation);
        DrawPartyRoster(SelectedCharacter);
      end;
  end;
end;
{ 00BA:290B. Builds the party location line and draws it on row 15 of the side window (ClearWindow
  (17,15)-(38,15), then DrawTextAt (17,15) in Green): the party position (PartyMapColumn and
  PartyMapRow, or the game map position GameVars^[VarMapX/Y] for the area view, the column shifted
  by the map page width for AreaViewKind 3 and 4), the facing (FacingNames) and the game clock time
  as hours:minutes (the game clock digits, each number padded to two digits with a leading zero).
  Outside the 3D view (GameVars^[VarShowWallOverlays] = 0) the position "column,row " is
  prepended; in the camp (ViewModeCamp) " camping" is appended and in the wilderness search mode
  (bit 0 of the travel mode word ds49D6^[714]) " search". Called by the camp and wilderness screens.
  Globals: PartyMapColumn, PartyMapRow, GameVars, AreaViewKind, VarsAt4900, FacingNames,
  PartyFacing, ds49F3, ds49D6 (all read). Side effect: the screen. }
procedure DrawLocationLine;
var
  Col, Row: ShortInt;               { the party position shown in the line }
  Hours, Minutes: string[2];        { the two-digit clock fields }
  Line: string[40];                 { the line built and drawn }
begin
  Line := '';
  Col := PartyMapColumn;
  Row := PartyMapRow;
  if AreaViewKind > 1 then
  begin
    Col := GameVars^[VarMapX];
    Row := GameVars^[VarMapY];
    if AreaViewKind = 3 then
      Inc(Col, MapPageWidth);
    if AreaViewKind = 4 then
      Inc(Col, MapPageWidth * 2);
  end;
  Hours := WordToText(VarsAt4900^[ClockHours]);
  if Length(Hours) < 2 then
    Hours := '0' + Hours;
  Minutes := WordToText(10 * VarsAt4900^[ClockTenMinutes] + VarsAt4900^[ClockMinutes]);
  if Length(Minutes) < 2 then
    Minutes := '0' + Minutes;
  if GameVars^[VarShowWallOverlays] = 0 then
    Line := ByteToText(Col) + ',' + ByteToText(Row) + ' ';
  Line := Line + FacingNames[PartyFacing] + ' ';
  Line := Line + Hours + ':' + Minutes;
  if ds49F3 = ViewModeCamp then
    Line := Line + ' camping'
  else if (ds49D6^[VarTravelMode] and 1) > 0 then
    Line := Line + ' search';
  ClearWindow($11, $F, $26, $F);
  DrawTextAt($11, $F, $0A, Line);
end;
{ 00BA:2B5E. Draws the wilderness map screen: it sets the view mode to ViewModeMap (3), draws the
  adventure screen's three windows (DrawAdventureScreen), the area view (ShowAreaView), the party
  marker (DrawPartyMarker), the location line and the character roster. Called by ovl14's
  HandleWildernessKeys when the party moves in the wilderness.
  Globals: ds49F3 (write). Side effect: the screen. }
procedure DrawWildernessScreen;
begin
  ds49F3 := ViewModeMap;
  DrawAdventureScreen;
  ShowAreaView;
  DrawPartyMarker;
  DrawLocationLine;
  DrawPartyRoster(SelectedCharacter);
end;
{ 00BA:2B88. Draws the combat screen: ovl31_e2 prepares the EGA palette, the left window
  (1,1)-(21,21) and the right window (23,1)-(38,21) are drawn with DrawWindow, the bottom two rows
  (0,23)-(39,24) are cleared, and the cursor is placed on the combat map's view origin plus three
  cells (MoveCombatCursor: margin CursorMargin, direction CursorNoStep). Called by StartBattle,
  PlayerTurn and the combat overlays. Globals: CombatMap (read). Side effect: the screen. }
procedure DrawCombatScreen;
begin
  ovl31_e2;
  DrawWindow(1, 1, $15, $15, 0, 0, '');
  DrawWindow($17, 1, $26, $15, 0, 0, '');
  ClearWindow(0, $17, $27, $18);
  MoveCombatCursor(CombatMap^.ViewX + ViewCentreCell, CombatMap^.ViewY + ViewCentreCell,
                   CursorMargin, CursorNoStep);
end;
{ 00BA:2C48. The party-member picker: it loops showing the character roster (DrawPartyRoster) and
  a ReadPromptChoice prompt titled Title with the word "Select" (and " Exit" when WithExit is set),
  updating the caller's Selected pointer. When ReadPromptChoice sets its extended-key flag ExtKey,
  the scan code 'O' (End) steps to the next member and 'G' (Home) to the previous (both wrap around
  the party list ds5D96); with ExtKey clear a typed G or O does nothing. A typed 'E', or a key code
  #0 with ExtKey clear, clears the selection. QUIRK 00BA:2C48: the #0 test runs only when ExtKey is
  clear, so #0 is not an extended-key prefix but the key code 0 returned with the flag clear. The
  loop ends on Enter, Escape, 'E' or 'S'; Enter, Escape and 'S' (the hotkey of the prompt's "Select"
  word) keep the current selection, 'E' clears it. Animate for ReadPromptChoice is 1 in the camp
  (ViewModeCamp) and loot (ViewModeLoot) screens. Called by ovl03, ovl19 and ovl22.
  Globals: ds49F3 (read), ds5D96 (read). Side effects: the screen, the keyboard. }
procedure SelectPartyMember(Title: String40; WithExit: Byte; var Selected: PCharacter);
var
  Key: Char;                        { the key ReadPromptChoice returns }
  ExtKey: Byte;                     { ReadPromptChoice's extended-key flag }
  Animate: Byte;                    { 1 in the camp and loot screens }
  PartyMember: PCharacter;          { the member the key selects }
  Extra: string[40];                { " Exit" when WithExit is set, else empty }
begin
  Key := ' ';
  Extra := '';
  if WithExit <> 0 then
    Extra := ' Exit';
  while not (Key in [KeyEnter, KeyEscape, KeyExit, KeySelect]) do
  begin
    DrawPartyRoster(Selected);
    if (ds49F3 = ViewModeCamp) or (ds49F3 = ViewModeLoot) then
      Animate := 1
    else
      Animate := 0;
    Key := ReadPromptChoice(Title + ' ', 'Select' + Extra, $D, $A, $F, 1, Animate, ExtKey);
    PartyMember := Selected;
    if ExtKey <> 0 then
      case Key of
        'O':
          begin
            PartyMember := PartyMember^.Next;
            if PartyMember = nil then
              PartyMember := PCharacter(ds5D96);
          end;
        'G':
          begin
            PartyMember := PCharacter(ds5D96);
            if Selected <> PCharacter(ds5D96) then
              while PartyMember^.Next <> Selected do
                PartyMember := PartyMember^.Next
            else
              while PartyMember^.Next <> nil do
                PartyMember := PartyMember^.Next;
          end;
      end
    else if (Key = KeyExit) or (Key = #0) then
      PartyMember := nil;
    Selected := PartyMember;
  end;
end;
{ 00BA:2E03. Returns whether Who's readied weapon (SlotItems[0], +$CC) is a missile weapon: False
  with no readied weapon, otherwise True when the weapon kind's ItemTable attack range (byte $C) is
  above 1 (a melee weapon has range 1). ovl08's MeleeAttack refuses a missile-only weapon
  (IsRangedWeapon and not RangedWeaponCanMelee); the combat AI and ovl13 test it too.
  Globals: ItemTable (read). }
function IsRangedWeapon(Who: Pointer): Boolean;
begin
  if (PCharacter(Who)^.SlotItems[0] <> nil) and
     (ItemTable[PCharacter(Who)^.SlotItems[0]^.ItemType].Range > 1) then
    IsRangedWeapon := True
  else
    IsRangedWeapon := False;
end;
{ 00BA:2E46. Returns whether Who's readied missile weapon (IsRangedWeapon) can also strike in
  melee: True when IsRangedWeapon holds and the weapon kind's ItemTable attack flags carry both the
  melee bit ($10) and the strength bit ($04). ovl08's MeleeAttack allows the attack only when
  IsRangedWeapon implies this too (else "Not with that weapon"); ovl09 and ovl13 test it.
  Globals: ItemTable (read). }
function RangedWeaponCanMelee(Who: Pointer): Boolean;
begin
  if IsRangedWeapon(Who) and
     ((ItemTable[PCharacter(Who)^.SlotItems[0]^.ItemType].Flags and
       (WeaponFlagMelee or WeaponFlagStrength)) = (WeaponFlagMelee or WeaponFlagStrength)) then
    RangedWeaponCanMelee := True
  else
    RangedWeaponCanMelee := False;
end;
{ 00BA:2E8B. Picks the item Who's attack aims with and returns whether it found one, clearing Aim
  first. With a readied weapon (SlotItems[0], +$CC): its kind's ItemTable attack flags (byte $E)
  decide the aim. The melee bit ($10) aims the weapon itself; the launcher bit ($08) aims the item
  in slot 11 (+$F8) when the slot-11 bit ($01) is set, or the item in slot 12 (+$FC) when the
  slot-12 bit ($80) is set. The result is 1 when an item was aimed, or when the flags are exactly
  $A (that case returns 1 with Aim still nil; why is not proven); 0 otherwise. ovl09's AiTurn
  passes the aimed item to PerformAttack for the attack. Globals: ItemTable (read). }
function ChooseAttackItem(Who: Pointer; var Aim: Pointer): Byte;
var
  Item: PItem;
  Flags: Byte;
begin
  ChooseAttackItem := 0;
  Item := PCharacter(Who)^.SlotItems[0];
  Aim := nil;
  Flags := 0;
  if Item <> nil then
  begin
    Flags := ItemTable[Item^.ItemType].Flags;
    if (Flags and WeaponFlagMelee) <> 0 then
      Aim := Item;
    if (Flags and WeaponFlagAmmo) <> 0 then
    begin
      if (Flags and WeaponFlagSlot11Plus) <> 0 then
        Aim := PCharacter(Who)^.SlotItems[11];
      if (Flags and WeaponFlagSlot12Plus) <> 0 then
        Aim := PCharacter(Who)^.SlotItems[12];
    end;
  end;
  if (Aim <> nil) or (Flags = $A) then
    ChooseAttackItem := 1;
end;
{ 00BA:2F57. Returns whether Who's level in one class has reached the maximum its race allows:
  CastRestoration (ovl22:2C43, spell 56 Restoration) picks the class that regains a drained level
  and skips a class this reaches, so it never raises ClassLevels[ClassIndex] (+$96) past the cap.
  The training hall's TrainCharacter (ovl16:29AE) does not call this: it inlines the same race and
  strength limits. False when the level is 0; otherwise Who's race (+$2E) and
  strength (+$10) pick the limit (the AD&D demihuman level limits [H]): a dwarf (RaceDwarf 1) in the
  fighter class (ClassFighter 2) stops at level 8 with Strength17 (17), at 7 with less; an elf
  (RaceElf 2) stops at 7, at 6 with Strength17, at 5 with less; a gnome (RaceGnome 3) stops at 6, at
  5 with strength below Strength18 (18); a half-elf (RaceHalfElf 4) stops at 5 in the cleric class
  (ClassCleric 0) and at 8 in the fighter class, at 7 with Strength17, at 6 with less; a halfling
  (RaceHalfling 5) stops at 6, at 5 with Strength17, at 4 with less.
  ClassIndex is the class index 0..7. Globals: none. }
function IsMaxClassLevel(Who: PCharacter; ClassIndex: ShortInt): Boolean;
var
  Level: ShortInt;
begin
  IsMaxClassLevel := False;
  with Who^ do
  begin
    Level := ClassLevels[ClassIndex];
    if Level > 0 then
      case Race of
        RaceDwarf:
          if (ClassIndex = ClassFighter) and
             ((Level = 8) and (Strength = Strength17) or
              (Level = 7) and (Strength < Strength17)) then
            IsMaxClassLevel := True;
        RaceElf:
          if (ClassIndex = ClassFighter) and
             ((Level = 7) or
              (Level = 6) and (Strength = Strength17) or
              (Level = 5) and (Strength < Strength17)) then
            IsMaxClassLevel := True;
        RaceGnome:
          if (ClassIndex = ClassFighter) and
             ((Level = 6) or
              (Level = 5) and (Strength < Strength18)) then
            IsMaxClassLevel := True;
        RaceHalfElf:
          if (ClassIndex = ClassCleric) and (Level = 5) then
            IsMaxClassLevel := True
          else if (ClassIndex = ClassFighter) and
                  ((Level = 8) or
                   (Level = 7) and (Strength = Strength17) or
                   (Level = 6) and (Strength < Strength17)) then
            IsMaxClassLevel := True;
        RaceHalfling:
          if (ClassIndex = ClassFighter) and
             ((Level = 6) or
              (Level = 5) and (Strength = Strength17) or
              (Level = 4) and (Strength < Strength17)) then
            IsMaxClassLevel := True;
      end;
  end;
end;

begin
end.
