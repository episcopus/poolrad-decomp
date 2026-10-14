program WILDLOOP;
{ Probe for ovl03:32F8 (the wilderness loop). The original tests the inner condition at the top
  (33B9: word > 1 skips UpCase, UpCase <> 'E' jumps to the code after the loop, then PartyDestroyed
  <> 0 jumps there too) and jumps back to that test (3449). The outer loop's test is at the bottom
  (34F5: cmp destroyed, 0; jne clear; jmp head; clear; epilogue); a short head compiles as je head
  instead, so the jne/jmp form is the far-head form of until <> 0. A <> compares as LongInt when
  one side is Word and the other ShortInt, and the right operand is evaluated first: ShortInt <> Word
  loads the word first (xor dx,dx, saved in BX:CX) then the ShortInt (cwde/cdq), which is ovl03:3497.
  Run: make tpc SRC=tools/re/tp_idioms/ovl03/WILDLOOP.PAS DISASM=1 }
var
  Word714: Word;
  Key: Char;
  Destroyed: Byte;
  StepFlag: Byte;
  SavedCol: Word;
  Col: ShortInt;
  SavedRow: Word;
  Row: ShortInt;
  Mode: Byte;

procedure InnerWhile;
begin
  while ((Word714 > 1) or (UpCase(Key) = 'E')) and (Destroyed = 0) do
  begin
    if UpCase(Key) = 'E' then
      Mode := 1
    else
    begin
      Mode := Word714 and 1;
      Word714 := 1;
      Word714 := Mode;
    end;
    if Destroyed = 0 then
      Key := 'A';
  end;
  if Destroyed = 0 then
    Mode := 2;
  if StepFlag <> 0 then
    Mode := 3
  else if Destroyed = 0 then
  begin
    SavedCol := Col;
    SavedRow := Row;
    if (SavedCol <> Col) or (SavedRow <> Row) then
      Mode := 4;
  end;
end;

procedure OuterRepeat;
begin
  Mode := 0;
  repeat
    Key := 'B';
    Mode := Mode;
    while Destroyed = 0 do
      Mode := 1;
    if StepFlag <> 0 then
      Mode := 2
    else if Destroyed = 0 then
      Mode := 3;
  until Destroyed <> 0;
  Destroyed := 0;
end;

procedure CompareOrder;
begin
  { Right operand of <> is evaluated first and saved. ShortInt <> Word loads the word
    first (xor dx,dx, saved in BX:CX) then the ShortInt (cwde/cdq), which is ovl03:3497. }
  if (Col <> SavedCol) or (Row <> SavedRow) then
    Mode := 5;
end;

begin
  InnerWhile;
  OuterRepeat;
  CompareOrder;
end.
