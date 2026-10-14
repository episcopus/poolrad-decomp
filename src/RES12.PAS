unit RES12;
{ res12: the resident helper unit the overlays call for characters, items and combat. It
  recomputes the combat values (RecalcCombatValues and ApplyWeaponBonuses) and the strength,
  dexterity, weight and damage figures (1168, 1282, 1325, 13AB, 2228, 2199); it draws the shop
  screen and its item prompts (27D9, 0767, called by ShopMain, whitepaper 5.4), shows the
  per-character messages (16EC, 1FEB) and dispatches the area view (27D9, 2B5E, whitepaper 5.2.1).
  Many routines are still stubs. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses Crt, POOLVARS, RES03, RES06, RES07, RES09, OVL30, OVL31;
type
  { The readied-item bonus accumulator AddReadiedItemBonus fills for RecalcCombatValues: the four signed
    bytes it combines into the character's +$112 value (with the flag byte the second var
    parameter points at). RecalcCombatValues clears and sums all five bytes as Values. }
  TBonus = record
    case Integer of
      0: (Pad0: Byte;          { +0: cleared by the caller, not read by AddReadiedItemBonus }
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
procedure res12_fn_0442(Value: LongInt; P: Pointer; A, B, C, D: Byte);
procedure res12_fn_06D5;
procedure res12_fn_0712;
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
function res12_fn_2686(Who: Pointer): Byte;
procedure res12_fn_26C2;
procedure res12_fn_272A;
procedure res12_fn_27D9;
procedure res12_fn_290B;
procedure res12_fn_2B5E;
procedure res12_fn_2B88;
procedure res12_fn_2C48;
function res12_fn_2E03(Who: Pointer): Boolean;
function res12_fn_2E46(Who: Pointer): Boolean;
function res12_fn_2E8B(Who: Pointer; var W: Pointer): Byte;
procedure res12_fn_2F57;
implementation

const
  { Byte offsets into a RaceRow (DS:5582; 129 sixteen-byte rows indexed by item kind, POOLVARS).
    The readied weapon's item kind picks the row. }
  RaceRowWeaponDice = 9;        { +$9: the item kind's damage dice count [I] }
  RaceRowWeaponDieSize = $A;    { +$A: the item kind's damage die size [I] }
  RaceRowWeaponBonus = $B;      { +$B: the item kind's base damage bonus }
  RaceRowAttackFlags = $E;      { +$E: which attack bonuses the item kind gets, see below }
  { Bits of RaceRow[item kind][RaceRowAttackFlags]. }
  WeaponFlagSlot11Plus = 1;     { add the plus of slot item 11 (+$F8) }
  WeaponFlagDexToHit = 2;       { the attack adds the dexterity roll adjustment }
  WeaponFlagStrength = 4;       { the attack adds the strength roll and damage adjustments }
  WeaponFlagSlot12Plus = $80;   { add the plus of slot item 12 (+$FC) }
  { The race value (Race, +$2E) that gets one more point with the item kinds $24, $25 and $29..$2C
    (the bows and the long and short swords of AD&D); which race that is is not proven here. }
  BonusRace = 2;
  BonusKindRangeLow = $28;      { the kinds above it and below the next value get the point }
  BonusKindRangeHigh = $2D;
  BonusKindLow = $25;
  BonusKindLower = $24;
  { Item kind (RaceRow[item kind][0]) of an armour, and the movement it allows: up to
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
    movement is left alone, up to MediumLoadLimit it is 9, up to HeavyLoadLimit 6, and above
    that 3. }
  LightLoadLimit = $200;
  MediumLoadFrom = $201;
  MediumLoadLimit = $300;
  HeavyLoadFrom = $301;
  HeavyLoadLimit = $400;
  { RaceRow byte offsets AddReadiedItemBonus reads. }
  RaceRowItemKind = 0;      { +0: the item kind: 0 weapon, 1 plus item, 2 armour, 9 special }
  RaceRowBonusClass = 6;    { +6: bit 7 set means the item has a bonus class (byte and $7F) }
  PlusItemKind = 1;         { item kind whose bonus is assigned, not accumulated }
  SpecialItemKind = 9;      { item kind whose plus is kept as a maximum }
  { RecalcCombatValues: the readied item kinds whose slot index equals the kind, 0..LastDirectSlotKind;
    kind SpecialItemKind goes to the first free of slots 9 and 10. }
  LastDirectSlotKind = 8;
  { RecalcCombatValues: the item types it files into SlotItems[11] and SlotItems[12]. }
  Slot11ItemType = $49;
  Slot12ItemType = $1C;
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
  { The most records the ScanTargets table ds6718 can hold: one per combatant of CombatantTable
    (72 plus its count at entry 0), times the 3 bytes of a TSortRec. 255B saves and restores exactly
    this many records of ds6718 around its scan. }
  SavedScanBytes = $D8;

{ 00BA:0000. Applies the readied weapon to Who's attack values; RecalcCombatValues calls it after it
  has copied the character's base values. With no readied weapon (SlotItems[0], +$CC) it does
  nothing. Otherwise the weapon's item kind picks a RaceRow row (DS:5582): its byte 9 becomes
  Who^.WeaponAttacks (+$115), byte $A Who^.WeaponDamage (+$117) and byte $B the base of the
  signed Who^.WeaponDamageBonus (+$119). The attack flags byte $E adds the dexterity roll
  adjustment (DexterityAttackAdjustment, bit 2) to HitAdjust (+$110, reset to Thac0 +$2D first) and the
  strength roll (StrengthAttackAdjustment) to HitAdjust and the strength damage (StrengthDamageAdjustment) to the
  damage bonus (bit 4); bit 0 adds the plus of slot item 11 (+$F8) and bit 7 the plus of slot
  item 12 (+$FC) to the weapon's own plus. Race 2 gets one more point with the bonus kinds.
  Globals: RaceRow. }
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
  if (RaceRow[ItemType][RaceRowAttackFlags] and WeaponFlagDexToHit) <> 0 then
    Who^.HitAdjust := Who^.HitAdjust + DexterityAttackAdjustment(Who);
  Who^.WeaponDamageBonus[1] := RaceRow[ItemType][RaceRowWeaponBonus];
  if (RaceRow[ItemType][RaceRowAttackFlags] and WeaponFlagStrength) <> 0 then
  begin
    Who^.HitAdjust := Who^.HitAdjust + StrengthAttackAdjustment(Who);
    Who^.WeaponDamageBonus[1] := Who^.WeaponDamageBonus[1] + StrengthDamageAdjustment(Who);
  end;
  WeaponPlus := Weapon^.Plus;
  if RaceRow[ItemType][RaceRowAttackFlags] > $7F then
    if Who^.SlotItems[12] <> nil then
      WeaponPlus := WeaponPlus + Who^.SlotItems[12]^.Plus;
  if (RaceRow[ItemType][RaceRowAttackFlags] and WeaponFlagSlot11Plus) > 0 then
    if Who^.SlotItems[11] <> nil then
      WeaponPlus := WeaponPlus + Who^.SlotItems[11]^.Plus;
  Who^.WeaponDamageBonus[1] := Who^.WeaponDamageBonus[1] + WeaponPlus;
  if (Who^.Race = BonusRace) and
     ((Weapon^.ItemType > BonusKindRangeLow) and (Weapon^.ItemType < BonusKindRangeHigh) or
      (Weapon^.ItemType = BonusKindLow) or (Weapon^.ItemType = BonusKindLower)) then
    Inc(WeaponPlus);
  Who^.HitAdjust := Who^.HitAdjust + WeaponPlus;
  Who^.WeaponAttacks[1] := RaceRow[ItemType][RaceRowWeaponDice];
  Who^.WeaponDamage[1] := RaceRow[ItemType][RaceRowWeaponDieSize];
end;

{ 00BA:01FB. Sets Who's movement (Movement, +$11C) from a readied armour; RecalcCombatValues calls it
  for every readied item. It does nothing unless the item's kind (RaceRow[item type][0]) is 2, an
  armour. Then the armour's weight (+$37) picks the movement: at most $96 keeps the character's
  base movement (BaseMovement, +$72), $97..$18F gives 9 and anything else 6. A magic armour
  (Plus, +$32, not 0) adds 3 while the movement is at most 9.
  Globals: RaceRow. }
procedure SetArmourMovement(Who: PCharacter; Item: PItem);
begin
  if RaceRow[Item^.ItemType][0] = ArmourItemKind then
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
  kind's bonus class (RaceRow[item type][6]); with bit 7 clear the item contributes nothing. The
  item kind (RaceRow[item type][0]) and Value pick what happens: a kind-1 item assigns
  Value + Plus to Bonus.KindBonus; otherwise Value 0 adds Plus to Bonus.PlusSum (a kind-9 item
  keeps the larger Plus in Bonus.BestPlus instead) and always adds the item's PlusSave (+$33) to
  Who^.SaveBonus; a Value above 0 keeps Value + Plus as the larger Bonus.BestValue and, for a
  positive plus on a kind-2 (armour) item, sets Flag.
  Globals: RaceRow. }
procedure AddReadiedItemBonus(Who: PCharacter; Item: PItem; var Bonus: TBonus; var Flag: Byte);
var
  Value: Byte;
  Kind: Byte;
begin
  Value := RaceRow[Item^.ItemType][RaceRowBonusClass];
  if Value <= $7F then
    Exit;
  Value := Value and $7F;
  Kind := RaceRow[Item^.ItemType][RaceRowItemKind];
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
  from below. The excess picks the cap: up to $200 the movement is left alone, up to $300 it is
  9, up to $400 6, and above that 3; the movement only falls, never rises.
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
    MediumLoadFrom..MediumLoadLimit: NewMovement := MediumArmourMove;
    HeavyLoadFrom..HeavyLoadLimit: NewMovement := HeavyArmourMove;
  else
    NewMovement := 3;
  end;
  if NewMovement < Who^.Movement then
    Who^.Movement := NewMovement;
end;

{ 00BA:0442: retf 16: 16 bytes of parameters; 524 bytes of locals. BLOCKED (see re/symbols.toml
  notes): it builds an item menu line's display text (the name parts from the DS:10A7 table, a
  magic marker, the count and a plural) and optionally draws it. The draft matches everything but
  the plural rule's "bit 1 of the mask is clear" term, which is two bytes short of it. }
{@stub} procedure res12_fn_0442(Value: LongInt; P: Pointer; A, B, C, D: Byte); begin end;

{ 00BA:06D5: not a routine but a label inside res12_fn_0442 (0442 is blocked); see its re/symbols.toml
  note. Kept a stub until 0442 matches, when make match WRITE=1 removes both entries. }
{@stub} procedure res12_fn_06D5; begin end;
{ 00BA:0712: not a routine but the else-branch label of res12_fn_0442; see its re/symbols.toml note. }
{@stub} procedure res12_fn_0712; begin end;
{ 00BA:0767. Draws the roster panel the shop and the Temple show (whitepaper 5.24): a
  "Name / AC  HP" header and one line per party member of the list ds5D96. The member Who is
  drawn white from its Name, every other member through DrawCharacterName. Each line's armour value
  (DrawArmourClass) and current hit points (DrawHitPoints) are drawn in one of three columns picked
  by the value's range, and each line is cleared first. The left column is 1 while the shop is
  open (ds49F3 = 0) and $11 otherwise. Globals: ds49F3 (read), ds5D96 (read). }
procedure DrawPartyRoster(Who: PCharacter);
var
  Member: PCharacter;
  Left: Byte;
  Row: Byte;
  ValueShift: Byte;
begin
  if ds49F3 = 0 then
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
  Green: the distance from 60, Abs(Value - 60), written with a leading '-' when the value is
  above 60 (a negative armour class). Called by DrawPartyRoster and DrawCharacterPanel. }
procedure DrawArmourClass(Who: PCharacter; Col, Row: Byte);
var
  ValueText: string;
  Unused: Byte;   { the original frame carries one byte here that the code never reads }
begin
  ValueText := ByteToText(Abs(Who^.ResistValue - 60));
  if Who^.ResistValue > 60 then
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
  (res12_fn_0442 then ShowPagedText) when a weapon is readied, and finally the status name
  (StatusNames[Status], +$10c) when the character takes no part in combat (Flag10D = 0), else
  "(Helpless)" when IsHelpless says so. Side effects: video memory, the keyboard through
  ShowPagedText's paging. }
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
    res12_fn_0442(LongInt(Who), Who^.SlotItems[0], 0, 0, 0, 0);
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
{ 00BA:0BB8. Recomputes every combat value of Who from the items it carries and has readied.
  It clears the 13 per-kind slots (SlotItems, +$CC); walks the carried item list (Items, +$C8) to
  count the items (ItemCountC7), add every item's weight times its Count to CarriedWeight (+$102)
  and to the readied weight ReadiedItemWeight (DS:4846), and file each readied item into its slot (kind 0..8
  into SlotItems[kind], kind 9 into the first free of slots 9 and 10, item type $49 into slot 11,
  $1C into slot 12), raising ds100 (+$100) by the kind's RaceRow[item type][1]. It then adds the
  carried money to the weight, copies the base attack triple (+$A3..+$A8) into the readied weapon
  triple (+$115..+$11A) and the base resistance (+$A9) into ResistValue (+$111), resets SaveBonus,
  Movement and HitAdjust, adds the unarmed strength bonuses (StrengthAttackAdjustment, StrengthDamageAdjustment) when no
  weapon is readied, and runs ApplyWeaponBonuses. For every readied item it runs SetArmourMovement
  and AddReadiedItemBonus; it then cuts the weight-excluding item's 5000, floors the weight at
  ReadiedItemWeight, sets ResistValue to the sum of the accumulator, ds112 (+$112) to its best three values
  minus two, and Movement through CapMovementByLoad. Called whenever a character's equipment or
  status changes.
  Globals: RaceRow, ReadiedItemWeight (write). }
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
  Who^.ds100 := 0;
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
      ItemKind := RaceRow[Item^.ItemType][RaceRowItemKind];
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
      Who^.ds100 := Who^.ds100 + RaceRow[Item^.ItemType][1];
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
  Bonus.Pad0 := DexterityAdjustment(Who);
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
    Who^.Pad6B := Who^.ClassLevels[2]
  else
    Who^.Pad6B := 1;
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
  do: Str into a 255-character local, copied into the string result. Its only caller is in
  ovl19 (the pool of treasure shows an amount with it).
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
  the attack value (HitAdjust) for a weapon kind whose attack flags have bit 2. ovl13 also calls
  it. Globals: none. }
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
  mode 5) and a fixed window otherwise; draws Who's name (DrawCharacterName) and the paged text Text
  (ShowPagedText) and, when Wait is set, delays DelayByGameSpeed and clears the window again
  (ClearCharacterMessage). Used for the per-character combat and camp messages ('is bandaged',
  'flees in panic', 'is cured'). Globals: ds49F3 (view mode), ds6DDA (picks the window top).
  Side effects: video memory, the keyboard through ShowPagedText's paging. }
procedure ShowCharacterMessage(Who: PCharacter; Text: string; Row, Wait: Byte);
var
  Top: Byte;
begin
  if ds49F3 = 5 then
  begin
    ClearWindow($17, Row, $26, $15);
    DrawCharacterName(Who, $17, Row, 0);
    ShowPagedText($17, Row + 1, $26, $15, Green, 1, Text);
  end
  else
  begin
    if ds6DDA <> 0 then
      Top := $12
    else
    begin
      Top := $11;
      DrawWindowFrame(1, Top, $26, $16, 0);
    end;
    ClearWindow(1, Top, $26, $16);
    DrawCharacterName(Who, 1, Top + 1, 0);
    ShowPagedText(1, Top + 1 + 1, $26, $16, Green, 1, Text);
  end;
  if Wait <> 0 then
  begin
    DelayByGameSpeed;
    ClearCharacterMessage;
  end;
end;
{ 00BA:17E3. Clears the message window ShowCharacterMessage wrote in: in the combat view (view mode 5)
  the box ($17,$A)-($26,$15), otherwise the box (1,$12)-($26,$16). Called after the wait flag of
  ShowCharacterMessage and by the camp, temple and resting screens to wipe a message. Globals: ds49F3. }
procedure ClearCharacterMessage;
begin
  if ds49F3 = 5 then
    ClearWindow($17, $A, $26, $15)
  else
    ClearWindow(1, $12, $26, $16);
end;
{ 00BA:1816. Draws Who's name (Name, +0) as text at (Col, Row) in the colour of Who's state:
  LightRed when Who takes no part in combat (Flag10D, +$10d = 0), Yellow for the party side
  (Side, +$10e = 1) and LightCyan otherwise. When Mode is set it appends "'s" after the name
  (at Col + Length(Name)). Called by the roster, the character panel and ovl13, ovl16, ovl19,
  ovl21 and ovl22. Globals: none. }
procedure DrawCharacterName(Who: PCharacter; Col, Row, Mode: Byte);
var
  Color: Byte;
begin
  if Who^.Flag10D = 0 then
    Color := LightRed
  else
    if Who^.Side = 1 then
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
  is copied with RowBytes bytes and the pixel buffer (Pixels, +$13) with the quartered PixelBytes
  count for the text video adapter (VideoAdapter = 1). ReleasePicture frees the temporary.
  Called in a loop by DrawCombatIcon and by ovl13.
  Globals: ds6E36 (read), ds5E5A (read), VideoAdapter (read). }
procedure CopyPictureItem(PicIndex, Half, Row, Mirror: Byte);
var
  Pic: Pointer;
  PixelBytes, RowBytes: Word;
begin
  RowBytes := PPicture(ds6E36)^.ByteSize;
  PixelBytes := RowBytes;
  if VideoAdapter = 1 then
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
  (multiplied by 3, the 24x24 icon pitch) through SetupLine/StepLine, collecting each step's
  direction Pattern into Path. It then walks that path: it computes the screen cell (PX, PY), draws
  the combat picture ds6E36 onto the staging buffer DrawBuf through res07_fn_0D71 (frame Frame of
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
  Line.X1 := FromX * 3;
  Line.Y1 := FromY * 3;
  Line.X2 := ToX * 3;
  Line.Y2 := ToY * 3;
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
    if (Abs(DeltaX) <= 6) and (Abs(DeltaY) <= 6) then
    begin
      LoopFlag := True;
      CursorX := FromX + DeltaX div 2;
      CursorY := FromY + DeltaY div 2;
    end
    else
    begin
      LoopFlag := False;
      CursorX := CombatMap^.ViewX + 3;
      CursorY := CombatMap^.ViewY + 3;
    end;
  end
  else
  begin
    LoopFlag := True;
    CursorX := CombatMap^.ViewX + 3;
    CursorY := CombatMap^.ViewY + 3;
  end;
  MoveCombatCursor(CursorX, CursorY, $ff, 8);
  PathLen := 0;
  AccX := 0;
  AccY := 0;
  repeat
    PX := (FromX - CombatMap^.ViewX) * 3 + AccX;
    PY := (FromY - CombatMap^.ViewY) * 3 + AccY;
    StartX := FromX;
    StartY := FromY;
    Done := False;
    repeat
      if (Mode > 0) or (PX mod 3 = 0) or (PY mod 3 = 0) then
      begin
        res07_fn_0D71(PX, PY, Frame, 5, ds6E36, DrawBuf);
        FlushPictureChanges;
        Delay(Mode);
        res07_fn_0D71(PX, PY, 0, 0, ds4A24, DrawBuf);
        Inc(Frame);
        if Frame >= Count then
          Frame := 0;
      end;
      Inc(PathLen);
      DXStep := DirStepX[Path[PathLen]];
      DYStep := DirStepY[Path[PathLen]];
      Inc(PX, DXStep);
      Inc(PY, DYStep);
      if (PX < 0) or (PX > $12) or (PY < 0) or (PY > $12) then
        Done := True;
      if (not Done) and (PathLen < PathCount) then
      begin
        Inc(AccX, DXStep);
        Inc(AccY, DYStep);
        if Abs(AccX) = 3 then
        begin
          Inc(FromX, SignOf(AccX));
          Inc(CursorX, SignOf(AccX));
          AccX := 0;
        end;
        if Abs(AccY) = 3 then
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
        if FromX >= CombatMap^.ViewX + 6 then
          CursorX := FromX + 3
        else if FromX <= CombatMap^.ViewX then
          CursorX := FromX - 3;
      end;
      if DeltaY <> 0 then
      begin
        if FromY >= CombatMap^.ViewY + 6 then
          CursorY := FromY + 3
        else if FromY <= CombatMap^.ViewY then
          CursorY := FromY - 3;
      end;
      MoveCombatCursor(CursorX, CursorY, $ff, 8);
    end
    else
    begin
      LoopFlag := True;
      if not IsInView(ToX - CombatMap^.ViewX, ToY - CombatMap^.ViewY) then
        MoveCombatCursor(ToX, ToY, 3, 8);
      PX := (ToX - CombatMap^.ViewX) * 3;
      PY := (ToY - CombatMap^.ViewY) * 3;
      res07_fn_0D71(PX, PY, Frame, 5, ds6E36, DrawBuf);
      if Mode > 0 then
      begin
        FlushPictureChanges;
        Delay(Mode);
        res07_fn_0D71(PX, PY, 0, 0, ds4A24, DrawBuf);
      end;
    end;
  until LoopFlag;
  FlushPictureChanges;
end;
{ 00BA:1FEB. Shows a per-character combat message and flashes the character's combat icon over
  its view cell. Outside the combat view (view mode 5) it only shows the message Text with a wait
  and returns. In the combat view: silences the sound driver, draws the combat icon slot $16 when
  Flag is set and $17 otherwise, puts the combat cursor on the character when it is off screen,
  plays the sound ds261C when Flag is set and ds261A otherwise, and shows Text without waiting.
  It then flashes the character's icon: for FlashCount + 1 passes it draws the four picture items
  (0..3) of the combat picture ds6E36 at the character's pixel position (three pixels per view
  cell, CombatantViewCol/CombatantViewRow), flushes and waits $46 ms, and restores the cell from
  ds4A24. Finally it resumes the sound driver and flushes; with Flag clear (FlashCount 0) it waits
  DelayByGameSpeed instead. DealDamage calls it with Flag 0 for the damage message, ApplyAffect
  with Flag 1 for an affect message, and the training code uses it too.
  Globals: ds49F3 (view mode), GameSpeed (FlashCount), ds261A/ds261C (sounds), ds6E36, ds4A24,
  DrawBuf, CombatantViewCol, CombatantViewRow. Side effects: video memory, sound, timing. }
procedure ShowHitMessage(Who: Pointer; Flag: Byte; Text: String40);
var
  Col, Row: ShortInt;
  Icon: Byte;
  Frame, Pass: Byte;
  FlashCount: Byte;
begin
  if ds49F3 = 5 then
  begin
    SetSoundDriverIdle(0);
    if Flag <> 0 then
      Icon := $16
    else
      Icon := $17;
    DrawCombatIcon(Icon);
    if not IsCombatantInView(Who, 1) then
      MoveCombatCursor(CombatantX(Who), CombatantY(Who), 3, 8);
    if Flag <> 0 then
      PlaySound(ds261C)
    else
      PlaySound(ds261A);
    ShowCharacterMessage(Who, Text, $A, 0);
    if Flag <> 0 then
      FlashCount := GameSpeed
    else
      FlashCount := 0;
    Col := CombatantViewCol[CombatantIndex(Who)] * 3;
    Row := CombatantViewRow[CombatantIndex(Who)] * 3;
    for Pass := 0 to FlashCount do
      for Frame := 0 to 3 do
      begin
        res07_fn_0D71(Col, Row, Frame, 5, ds6E36, DrawBuf);
        FlushPictureChanges;
        Delay($46);
        res07_fn_0D71(Col, Row, 0, 0, ds4A24, DrawBuf);
      end;
    SetSoundDriverIdle($A);
    FlushPictureChanges;
    if FlashCount = 0 then
      DelayByGameSpeed;
  end
  else
    ShowCharacterMessage(Who, Text, $A, 1);
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
  Remaining = HpCurrent - Damage otherwise (the other stays 0), then sets the status: dead
  (StatusDead) when the overkill is above 9 or when a hit exactly reaches 0 while Who was already
  StatusAnimated; dying (StatusDying) when there is any overkill, recording the overkill in
  Combat^.DyingRounds (+$E) in the combat view; unconscious (StatusUnconscious) when the hit
  exactly reaches 0 otherwise. When the resulting status is not the standing set StatusOkay +
  StatusAnimated Who leaves combat: Flag10D and the hit points are cleared and, in the combat
  view, its side's count (ds6814Sides, by Side) and its initiative (Combat^.Initiative, +$3) drop;
  a standing character just takes Remaining as its hit points. DealDamage, DamageWithMessage and
  ovl13 call it. Globals: ds49F3 (view mode), ds6814Sides.
  StatusDead (6): is the character dead, StatusAnimated (1): already dead-like (the heal code
  counts 1 and 6); from the image status names. }
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
    if ds49F3 = 5 then
      PCharacter(Who)^.Combat^.DyingRounds := Overkill;
  end
  else if Remaining = 0 then
    PCharacter(Who)^.Status := StatusUnconscious;
  if not (PCharacter(Who)^.Status in [StatusOkay, StatusAnimated]) then
  begin
    PCharacter(Who)^.Flag10D := 0;
    PCharacter(Who)^.Flag11B := 0;
    if ds49F3 = 5 then
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
  ShowCharacterMessage(Who, Message, $A, 1);
  if ds49F3 <> 5 then
    DrawPartyRoster(SelectedCharacter);
end;
{ 00BA:23B7. Returns the side opposite Who's (Side, +$10E): 1 when Who is on the party side (0) and
  0 otherwise. The combat AI indexes the per-side counts ds6814Sides with it to count Who's
  enemies (UseMagicItem, CastMemorizedSpell, DifferentSideInArea) and ovl12/ovl13/ovl22 use it
  too. Globals: none. }
function OpposingSide(Who: Pointer): Byte;
begin
  if PCharacter(Who)^.Side = SideParty then
    OpposingSide := 1
  else
    OpposingSide := 0;
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
{ 00BA:2637. Ends Who's combat turn: it clears the pending spell (PendingSpell, +$0; ovl22_e5
  casts it when the turn ends), the turn order (Initiative, +$3), the guard byte (B7, +$7; GuardTurn
  sets it to 1) and the movement left (Moves, +$6), then returns 1 (the turn is over). The Done
  menu's Quit command, every "the turn ends" path of the AI and the self-end checks call it
  (ovl08:031A, 09DF, 0E45; ovl09:000F, 07F2, 0B3C, 10D7; ovl12; ovl13). Globals: none. }
function EndCombatTurn(Who: Pointer): Byte;
begin
  PCharacter(Who)^.Combat^.Initiative := 0;
  PCharacter(Who)^.Combat^.PendingSpell := 0;
  PCharacter(Who)^.Combat^.B7 := 0;
  PCharacter(Who)^.Combat^.Moves := 0;
  EndCombatTurn := 1;
end;
{ 00BA:2686: retf 4: 4 bytes of parameters; 10 bytes of locals }
{@stub} function res12_fn_2686(Who: Pointer): Byte; begin end;
{ 00BA:26C2: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} procedure res12_fn_26C2; begin end;
{ 00BA:272A: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} procedure res12_fn_272A; begin end;
{ 00BA:27D9: retf 0: 0 bytes of parameters; 4 bytes of locals }
{@stub} procedure res12_fn_27D9; begin end;
{ 00BA:290B: retf 0: 0 bytes of parameters; 562 bytes of locals }
{@stub} procedure res12_fn_290B; begin end;
{ 00BA:2B5E: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure res12_fn_2B5E; begin end;
{ 00BA:2B88: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure res12_fn_2B88; begin end;
{ 00BA:2C48: retf 10: 10 bytes of parameters; 602 bytes of locals }
{@stub} procedure res12_fn_2C48; begin end;
{ 00BA:2E03: retf 4: 4 bytes of parameters; 2 bytes of locals }
{@stub} function res12_fn_2E03(Who: Pointer): Boolean; begin end;
{ 00BA:2E46: retf 4: 4 bytes of parameters; 2 bytes of locals }
{@stub} function res12_fn_2E46(Who: Pointer): Boolean; begin end;
{ 00BA:2E8B: retf 8: 8 bytes of parameters; 6 bytes of locals }
{@stub} function res12_fn_2E8B(Who: Pointer; var W: Pointer): Byte; begin end;
{ 00BA:2F57: retf 6: 6 bytes of parameters; 6 bytes of locals }
{@stub} procedure res12_fn_2F57; begin end;

begin
end.
