unit OVL23;
{ Character derived stats (whitepaper 5.3): RecalcCharacter recomputes THAC0, MaxSlot, Bonus,
  Flags and the class values of a character record through class tables; the leaves
  IncrementBonuses, MinimizeLeast and ComputeClassVal do one part each. Three routines are
  drafted but unmatched over one Turbo Pascal codegen rule (di- versus ax-accumulated table
  indices; blocked notes in re/symbols.toml). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure RecalcCharacter(Character: Pointer);
procedure IncrementBonuses(Character: Pointer);
procedure MinimizeLeast(Character: Pointer);
procedure ComputeClassVal(Character: Pointer);
implementation
uses POOLVARS;

{ ovl23:0000. Recomputes a character's derived stats: THAC0 as the max over seven class
  slots of table 3C7C, MaxSlot as the max slot class, the Bonus and Flags bytes for young
  slots, the upper Bonus bytes for old ones, then MinimizeLeast always and ComputeClassVal
  when SlotClass[6] is set. Called when characters are made or loaded (ovl12, ovl16, ovl17,
  ovl22). DRAFT: matches except one address computation (blocked note in re/symbols.toml). }
procedure RecalcCharacter(Character: Pointer);
var
  I, J, CurClass: ShortInt;
  K: Byte;
  Tab: ^TFlagEntry;
begin
  PCharacter(Character)^.THAC0 := 0;
  for I := 0 to 6 do
  begin
    CurClass := PCharacter(Character)^.SlotClass[I];
    if ds3C7C[I, CurClass] > PCharacter(Character)^.THAC0 then
      PCharacter(Character)^.THAC0 := ds3C7C[I, CurClass];
    if PCharacter(Character)^.MaxSlot < CurClass then
      PCharacter(Character)^.MaxSlot := CurClass;
    case I of
      2:
        if CurClass > 6 then
          PCharacter(Character)^.ModeA1 := 3
        else
          PCharacter(Character)^.ModeA1 := 2;
      0:
        if CurClass > 1 then
        begin
          for J := 1 to 3 do
            PCharacter(Character)^.Bonus[J] := ds40BC[CurClass, J];
          IncrementBonuses(Character);
          for K := 1 to $38 do
          begin
            Tab := @ds31FA[K];
            if (Tab^.Skip = 0) and (PCharacter(Character)^.Bonus[Tab^.BonusIdx] > 0) then
              PCharacter(Character)^.Flags32[K] := 1;
          end;
        end;
      5:
        if CurClass > 1 then
          for J := 1 to 3 do
            PCharacter(Character)^.BonusHi[J] := ds41D4[CurClass, J];
    end;
  end;
  MinimizeLeast(Character);
  if PCharacter(Character)^.SlotClass[6] > 0 then
    ComputeClassVal(Character);
end;
{ ovl23:01AF. Bumps the character's Bonus counters when its third ability score passes
  12 to 16: Bonus[1] gains a point at 13 and 14, Bonus[2] at 15 and 16, Bonus[3] at 17, each
  only when already nonzero. Called after the Bonus bytes are seeded (ovl16 three times,
  RecalcCharacter). The ability and bonus meanings are still open (whitepaper 5.3). }
procedure IncrementBonuses(Character: Pointer);
begin
  with PCharacter(Character)^ do
  begin
    if (Ability[2] > $0C) and (Bonus[1] > 0) then Inc(Bonus[1]);
    if (Ability[2] > $0D) and (Bonus[1] > 0) then Inc(Bonus[1]);
    if (Ability[2] > $0E) and (Bonus[2] > 0) then Inc(Bonus[2]);
    if (Ability[2] > $0F) and (Bonus[2] > 0) then Inc(Bonus[2]);
    if (Ability[2] > $10) and (Bonus[3] > 0) then Inc(Bonus[3]);
  end;
end;
{ ovl23:0255. Keeps the five Least minima over the eight class slots: each starts at $14
  and takes the smaller of itself and table 426E for every slot whose class is set. Runs
  after the Bonus bytes are seeded. DRAFT: matches except one address computation (blocked
  note in re/symbols.toml). }
procedure MinimizeLeast(Character: Pointer);
var
  I, J: ShortInt;
  Unused: Word;                 { never read or written; the frame needs two bytes here (sub sp,4) }
begin
  for I := 0 to 4 do
  begin
    PCharacter(Character)^.Least[I] := $14;
    for J := 0 to 7 do
      if PCharacter(Character)^.SlotClass[J] > 0 then
        if PCharacter(Character)^.Least[I] > ds426E[J, PCharacter(Character)^.SlotClass[J] * 5 + I] then
          PCharacter(Character)^.Least[I] := ds426E[J, PCharacter(Character)^.SlotClass[J] * 5 + I];
  end;
end;
{ ovl23:0329. Computes the eight ClassVal bytes from the class tables: a non-negative
  first table byte copies the summed tables, a negative one with a bigger absolute value
  zeroes the slot instead, and young slots add table 3D4E on top. DRAFT: matches except one
  address computation (blocked note in re/symbols.toml). }
procedure ComputeClassVal(Character: Pointer);
var
  I: Byte;
begin
  with PCharacter(Character)^ do
  begin
    for I := 1 to 8 do
    begin
      if (ds3D3B[Race, I] < 0) and (Abs(ds3D3B[Race, I]) > ds3CF3[SlotClass[6], I]) then
        ClassVal[I] := 0
      else
      begin
        ClassVal[I] := ds3D3B[Race, I] + ds3CF3[SlotClass[6], I];
        if I < 6 then
          ClassVal[I] := ClassVal[I] + ds3D4E[Ability[3], I];
      end;
    end;
  end;
end;

begin
end.
