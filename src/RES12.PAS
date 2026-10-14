unit RES12;
{ res12: the resident helper unit the overlays call for characters, items and combat. It
  recomputes the combat values (res12_fn_0BB8 and ApplyWeaponBonuses) and the strength,
  dexterity, weight and damage figures (1168, 1282, 1325, 13AB, 2228, 2199); it draws the shop
  screen and its item prompts (27D9, 0767, called by ShopMain, whitepaper 5.4), shows the
  per-character messages (16EC, 1FEB) and dispatches the area view (27D9, 2B5E, whitepaper 5.2.1).
  Many routines are still stubs. }
{$A-,F+,S-,R-,G-,I-}
interface
uses POOLVARS, RES06;
procedure ApplyWeaponBonuses(Who: PCharacter);
procedure SetArmourMovement(Who: PCharacter; Item: PItem);
procedure res12_fn_0282;
procedure res12_fn_03A0;
procedure res12_fn_0442(Value: LongInt; P: Pointer; A, B, C, D: Byte);
procedure res12_fn_06D5;
procedure res12_fn_0712;
procedure res12_fn_0767(Who: Pointer);
procedure res12_fn_08EF;
procedure res12_fn_0973;
procedure res12_fn_09E3(Who: Pointer);
procedure res12_fn_0B4F;
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

{ 00BA:0282: retf 16: 16 bytes of parameters; 2 bytes of locals }
{@stub} procedure res12_fn_0282; begin end;
{ 00BA:03A0: retf 4: 4 bytes of parameters; 4 bytes of locals }
{@stub} procedure res12_fn_03A0; begin end;
{ 00BA:0442: frame not read }
{@stub} procedure res12_fn_0442(Value: LongInt; P: Pointer; A, B, C, D: Byte); begin end;
{ 00BA:06D5: frame not read }
{@stub} procedure res12_fn_06D5; begin end;
{ 00BA:0712: retf 16: 16 bytes of parameters; 0 bytes of locals }
{@stub} procedure res12_fn_0712; begin end;
{ 00BA:0767: retf 4; compares its pointer parameter with other pointers. ovl04 passes the selected
  character. }
{@stub} procedure res12_fn_0767(Who: Pointer); begin end;
{ 00BA:08EF: retf 8: 8 bytes of parameters; 514 bytes of locals }
{@stub} procedure res12_fn_08EF; begin end;
{ 00BA:0973: retf 10: 10 bytes of parameters; 258 bytes of locals }
{@stub} procedure res12_fn_0973; begin end;
{ 00BA:09E3: frame not read }
{@stub} procedure res12_fn_09E3(Who: Pointer); begin end;
{ 00BA:0B4F: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure res12_fn_0B4F; begin end;
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
