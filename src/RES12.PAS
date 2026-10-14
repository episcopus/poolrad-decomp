unit RES12;
{ res12: the resident helper unit the overlays call for characters, items and combat. It
  recomputes the combat values (res12_fn_0BB8 and ApplyWeaponBonuses) and the strength,
  dexterity, weight and damage figures (1168, 1282, 1325, 13AB, 2228, 2199); it draws the shop
  screen and its item prompts (27D9, 0767, called by ShopMain, whitepaper 5.4), shows the
  per-character messages (16EC, 1FEB) and dispatches the area view (27D9, 2B5E, whitepaper 5.2.1).
  Many routines are still stubs. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS, RES06, RES09;
type
  { The readied-item bonus accumulator AddReadiedItemBonus fills for res12_fn_0BB8: the four signed
    bytes it combines into the character's +$112 value (with the flag byte the second var
    parameter points at). Only the fields this unit reads are named. }
  TBonus = record
    Pad0: Byte;            { +0: cleared by the caller, not read by AddReadiedItemBonus }
    KindBonus: ShortInt;   { +1: Value + Plus of a kind-1 item }
    PlusSum: ShortInt;     { +2: the plus of every other non-kind-9 item }
    BestPlus: ShortInt;    { +3: the largest plus of a kind-9 item }
    BestValue: ShortInt;   { +4: the largest Value + Plus of a Value <> 0 item }
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
function res12_fn_0B73(Who: Pointer): Boolean;
procedure res12_fn_0BB8(Who: Pointer);
function res12_fn_1037(N: Byte): string;
function res12_fn_1073(Value: Word): string;
procedure res12_fn_10AD;
procedure res12_fn_10E6;
function res12_fn_1168(Who: PCharacter): ShortInt;
procedure res12_fn_11EA;
function res12_fn_1282(Who: PCharacter): ShortInt;
function res12_fn_1325(Who: PCharacter): ShortInt;
function res12_fn_13AB(Who: Pointer): Integer;
procedure res12_fn_148B(Spell: Byte);
procedure res12_fn_1509(Who: Pointer; Item: Pointer);
procedure res12_fn_15F7;
procedure res12_fn_1693(Text: String40);
procedure res12_fn_16EC(Who: Pointer; Text: string; A, B: Byte);
procedure res12_fn_17E3;
procedure res12_fn_1816(Who: Pointer; Col, Row, Mode: Byte);
procedure res12_fn_1857;
procedure res12_fn_187D;
procedure res12_fn_1892;
procedure res12_fn_18A3;
procedure res12_fn_18CF;
procedure res12_fn_190D;
procedure res12_fn_19DE;
procedure res12_fn_1A29;
procedure res12_fn_1CBA;
procedure res12_fn_1CE0;
procedure res12_fn_1FEB(Who: Pointer; Flag: Byte; Text: String40);
function res12_fn_2199(Who: Pointer; AffectId: Byte; var Affect: Pointer): Boolean;
procedure res12_fn_2228(Who: Pointer; Damage: Byte);
procedure res12_fn_234A;
function res12_fn_23B7(Who: Pointer): Byte;
procedure res12_fn_23DB;
function res12_fn_2433(P: Pointer; B: Byte): Byte;
function res12_fn_255B(Who, Target: Pointer): Byte;
procedure res12_fn_2571;
function res12_fn_2637(Who: Pointer): Byte;
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
  { EGA text colours DrawTextAt draws the character and shop panels in (whitepaper 5.24). }
  Green = $0A;
  LightMagenta = $0D;
  Yellow = $0E;
  White = $0F;

{ 00BA:0000. Applies the readied weapon to Who's attack values; res12_fn_0BB8 calls it after it
  has copied the character's base values. With no readied weapon (SlotItems[0], +$CC) it does
  nothing. Otherwise the weapon's item kind picks a RaceRow row (DS:5582): its byte 9 becomes
  Who^.WeaponAttacks (+$115), byte $A Who^.WeaponDamage (+$117) and byte $B the base of the
  signed Who^.WeaponDamageBonus (+$119). The attack flags byte $E adds the dexterity roll
  adjustment (res12_fn_1168, bit 2) to HitAdjust (+$110, reset to Thac0 +$2D first) and the
  strength roll (res12_fn_1282) to HitAdjust and the strength damage (res12_fn_1325) to the
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
    Who^.HitAdjust := Who^.HitAdjust + res12_fn_1168(Who);
  Who^.WeaponDamageBonus := RaceRow[ItemType][RaceRowWeaponBonus];
  if (RaceRow[ItemType][RaceRowAttackFlags] and WeaponFlagStrength) <> 0 then
  begin
    Who^.HitAdjust := Who^.HitAdjust + res12_fn_1282(Who);
    Who^.WeaponDamageBonus := Who^.WeaponDamageBonus + res12_fn_1325(Who);
  end;
  WeaponPlus := Weapon^.Plus;
  if RaceRow[ItemType][RaceRowAttackFlags] > $7F then
    if Who^.SlotItems[12] <> nil then
      WeaponPlus := WeaponPlus + Who^.SlotItems[12]^.Plus;
  if (RaceRow[ItemType][RaceRowAttackFlags] and WeaponFlagSlot11Plus) > 0 then
    if Who^.SlotItems[11] <> nil then
      WeaponPlus := WeaponPlus + Who^.SlotItems[11]^.Plus;
  Who^.WeaponDamageBonus := Who^.WeaponDamageBonus + WeaponPlus;
  if (Who^.Race = BonusRace) and
     ((Weapon^.ItemType > BonusKindRangeLow) and (Weapon^.ItemType < BonusKindRangeHigh) or
      (Weapon^.ItemType = BonusKindLow) or (Weapon^.ItemType = BonusKindLower)) then
    Inc(WeaponPlus);
  Who^.HitAdjust := Who^.HitAdjust + WeaponPlus;
  Who^.WeaponAttacks := RaceRow[ItemType][RaceRowWeaponDice];
  Who^.WeaponDamage := RaceRow[ItemType][RaceRowWeaponDieSize];
end;

{ 00BA:01FB. Sets Who's movement (Movement, +$11C) from a readied armour; res12_fn_0BB8 calls it
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
  res12_fn_0BB8 keeps; called for every readied item after SetArmourMovement. Value is the item
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
  allowance; res12_fn_0BB8 calls it once after the readied-item loop. Weight is
  CarriedWeight (+$102) minus res12_fn_13AB(Who) (the strength weight allowance), clamped at 0
  from below. The excess picks the cap: up to $200 the movement is left alone, up to $300 it is
  9, up to $400 6, and above that 3; the movement only falls, never rises.
  Globals: none beyond Who. }
procedure CapMovementByLoad(Who: PCharacter);
var
  Weight: Integer;
  NewMovement: Byte;
begin
  Weight := Who^.CarriedWeight - res12_fn_13AB(Who);
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
  drawn white from its Name, every other member through res12_fn_1816. Each line's armour value
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
      res12_fn_1816(Member, Left, Row, 0);
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
  ValueText := res12_fn_1037(Abs(Who^.ResistValue - 60));
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
  DrawTextAt(Col, Row, ValueColor, res12_fn_1037(Who^.Flag11B));
end;

{ 00BA:09E3. Draws the character panel the combat and inventory screens show (whitepaper 5.24): it
  clears the box ($17,1)-($26,$15), writes the name line through res12_fn_16EC, the "Hitpoints" and
  "AC" headings with their values (DrawHitPoints, DrawArmourClass), the readied weapon's paged text
  (res12_fn_0442 then ShowPagedText) when a weapon is readied, and finally the status name
  (StatusNames[Status], +$10c) when the character takes no part in combat (Flag10D = 0), else
  "(Helpless)" when res12_fn_0B73 says so. Side effects: video memory, the keyboard through
  ShowPagedText's paging. }
procedure DrawCharacterPanel(Who: PCharacter);
var
  Color: Byte;
  Row: Byte;
begin
  ClearWindow($17, 1, $26, $15);
  Row := 1;
  res12_fn_16EC(Who, ' ', Row, 0);
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
    if res12_fn_0B73(Who) then
      DrawTextAt($17, Row + 1, White, '(Helpless)');
end;
{ 00BA:0B73: retf 4: 4 bytes of parameters; 6 bytes of locals }
{@stub} function res12_fn_0B73(Who: Pointer): Boolean; begin end;
{ 00BA:0BB8: retf 4: 4 bytes of parameters; 20 bytes of locals }
{@stub} procedure res12_fn_0BB8(Who: Pointer); begin end;
{ 00BA:1037: retf 2: 2 bytes of parameters; 256 bytes of locals }
{@stub} function res12_fn_1037(N: Byte): string; begin end;
{ 00BA:1073: retf 2, a string function (the caller pushes the result temporary first); ovl04 puts
  a price into a message with it. }
{@stub} function res12_fn_1073(Value: Word): string; begin end;
{ 00BA:10AD: retf 4: 4 bytes of parameters; 256 bytes of locals }
{@stub} procedure res12_fn_10AD; begin end;
{ 00BA:10E6: retf 4: 4 bytes of parameters; 2 bytes of locals }
{@stub} procedure res12_fn_10E6; begin end;
{ 00BA:1168: retf 4: 4 bytes of parameters; 2 bytes of locals }
{@stub} function res12_fn_1168(Who: PCharacter): ShortInt; begin end;
{ 00BA:11EA: retf 4: 4 bytes of parameters; 2 bytes of locals }
{@stub} procedure res12_fn_11EA; begin end;
{ 00BA:1282: retf 4: 4 bytes of parameters; 2 bytes of locals }
{@stub} function res12_fn_1282(Who: PCharacter): ShortInt; begin end;
{ 00BA:1325: retf 4: 4 bytes of parameters; 2 bytes of locals }
{@stub} function res12_fn_1325(Who: PCharacter): ShortInt; begin end;
{ 00BA:13AB: retf 4: 4 bytes of parameters; 4 bytes of locals }
{@stub} function res12_fn_13AB(Who: Pointer): Integer; begin end;
{ 00BA:148B: retf 2: 2 bytes of parameters; 2 bytes of locals }
{@stub} procedure res12_fn_148B(Spell: Byte); begin end;
{ 00BA:1509: retf 8: 8 bytes of parameters; 44 bytes of locals }
{@stub} procedure res12_fn_1509(Who: Pointer; Item: Pointer); begin end;
{ 00BA:15F7: retf 8: 8 bytes of parameters; 8 bytes of locals }
{@stub} procedure res12_fn_15F7; begin end;
{ 00BA:1693: retf 4; copies a string[40] value (limit $28). ovl04 passes 'Not enough money.'. }
{@stub} procedure res12_fn_1693(Text: String40); begin end;
{ 00BA:16EC: retf 12. ovl04 passes the selected character, a message and two bytes (0, 0 or 0, 1). }
{@stub} procedure res12_fn_16EC(Who: Pointer; Text: string; A, B: Byte); begin end;
{ 00BA:17E3: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure res12_fn_17E3; begin end;
{ 00BA:1816: frame not read }
{@stub} procedure res12_fn_1816(Who: Pointer; Col, Row, Mode: Byte); begin end;
{ 00BA:1857: frame not read }
{@stub} procedure res12_fn_1857; begin end;
{ 00BA:187D: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure res12_fn_187D; begin end;
{ 00BA:1892: frame not read }
{@stub} procedure res12_fn_1892; begin end;
{ 00BA:18A3: frame not read }
{@stub} procedure res12_fn_18A3; begin end;
{ 00BA:18CF: frame not read }
{@stub} procedure res12_fn_18CF; begin end;
{ 00BA:190D: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure res12_fn_190D; begin end;
{ 00BA:19DE: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure res12_fn_19DE; begin end;
{ 00BA:1A29: frame not read }
{@stub} procedure res12_fn_1A29; begin end;
{ 00BA:1CBA: frame not read }
{@stub} procedure res12_fn_1CBA; begin end;
{ 00BA:1CE0: retf 12: 12 bytes of parameters; 0 bytes of locals }
{@stub} procedure res12_fn_1CE0; begin end;
{ 00BA:1FEB: retf 10: 10 bytes of parameters; 48 bytes of locals }
{@stub} procedure res12_fn_1FEB(Who: Pointer; Flag: Byte; Text: String40); begin end;
{ 00BA:2199: retf 10; walks the affect list of Who (+$7F) for AffectId, leaves the affect in
  Affect and returns 1 when found. }
{@stub} function res12_fn_2199(Who: Pointer; AffectId: Byte; var Affect: Pointer): Boolean;
  begin end;
{ 00BA:2228: retf 6: 6 bytes of parameters; 2 bytes of locals }
{@stub} procedure res12_fn_2228(Who: Pointer; Damage: Byte); begin end;
{ 00BA:234A: retf 4: 4 bytes of parameters; 42 bytes of locals }
{@stub} procedure res12_fn_234A; begin end;
{ 00BA:23B7: retf 4: 4 bytes of parameters; 2 bytes of locals }
{@stub} function res12_fn_23B7(Who: Pointer): Byte; begin end;
{ 00BA:23DB: retf 0: 0 bytes of parameters; 4 bytes of locals }
{@stub} procedure res12_fn_23DB; begin end;
{ 00BA:2433: retf 6: 6 bytes of parameters; 6 bytes of locals }
{@stub} function res12_fn_2433(P: Pointer; B: Byte): Byte; begin end;
{ 00BA:255B: frame not read }
{@stub} function res12_fn_255B(Who, Target: Pointer): Byte; begin end;
{ 00BA:2571: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure res12_fn_2571; begin end;
{ 00BA:2637: retf 4: 4 bytes of parameters; 2 bytes of locals }
{@stub} function res12_fn_2637(Who: Pointer): Byte; begin end;
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
