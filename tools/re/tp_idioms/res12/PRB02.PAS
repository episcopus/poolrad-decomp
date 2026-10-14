{ Probe for res12:0282 (playbook 30).
  Question: which Pascal reproduces res12_fn_0282 byte-for-byte (the routine is one byte short
  of a match). Same types and offsets as POOLVARS/res12: RaceRow indexed by item kind, TBonus
  fields at +1..+4, Who^.SaveBonus +101h. }
{$F+,S-,R-,I-}
program Res12Probe2;

type
  TRaceRow = array[0..15] of Byte;
  TItem = record
    Text: string[40];
    Flag29: Byte;
    Next: Pointer;
    ItemType: Byte;
    NameNum: array[1..3] of Byte;
    Plus: ShortInt;
    PlusSave: ShortInt;
    Readied: Boolean;
    HiddenNames: Byte;
    Cursed: Boolean;
    Weight: Word;
    Count: Byte;
    Value: Word;
    Affects: array[1..3] of Byte;
  end;
  PItem = ^TItem;
  TCharacter = record
    Pad: array[0..$100] of Byte;
    SaveBonus: ShortInt;
    Pad2: array[$102..$11C] of Byte;
  end;
  PCharacter = ^TCharacter;
  TBonus = record
    Pad0: Byte;
    KindBonus: ShortInt;
    PlusSum: ShortInt;
    BestPlus: ShortInt;
    BestValue: ShortInt;
  end;

const
  RaceRowItemKind = 0;
  RaceRowBonusClass = 6;
  PlusItemKind = 1;
  SpecialItemKind = 9;
  ArmourItemKind = 2;

var
  RaceRow: array[0..128] of TRaceRow;
  Who: PCharacter;
  Item: PItem;
  Bonus: TBonus;
  Flag: Byte;

procedure AddItemBonus(Who: PCharacter; Item: PItem; var Bonus: TBonus; var Flag: Byte);
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

begin
  AddItemBonus(Who, Item, Bonus, Flag);
end.
