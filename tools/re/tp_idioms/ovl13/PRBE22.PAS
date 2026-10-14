program PRBE22;
{ Probe: which construct adds the hidden frame byte in ovl13:37E4's body. }
{$A-,F+,S-,R-,G-,I-}
type
  PCharacter = ^Byte;
var
  ds6DE4: array[0..72] of Byte;
  CombatantRecord: array[0..72] of PCharacter;
  CombatMapHead6: Byte;
  Who: PCharacter;

function CollectEnemiesInRange(W: PCharacter; Range: Byte): Byte;
begin
  CollectEnemiesInRange := W^ + Range;
end;
function AttackTargetAllowed(W, T: PCharacter): Boolean;
begin
  AttackTargetAllowed := W^ > T^;
end;
function RollDice(Count, Sides: Byte): Byte;
begin
  RollDice := Count + Sides;
end;

function F1(W: PCharacter; Range, ThroughWalls, ForgetTarget: Byte): Boolean;
var
  Count: Byte; Attempts: Byte; Index: Byte; Retry: Boolean; Found: Boolean;
  Searched: Boolean; Target: PCharacter; CountCopy: Byte;
begin
  Searched := False; Found := False; Retry := False; Target := W;
  F1 := Found;
end;

function F2(W: PCharacter; Range, ThroughWalls, ForgetTarget: Byte): Boolean;
var
  Count: Byte; Attempts: Byte; Index: Byte; Retry: Boolean; Found: Boolean;
  Searched: Boolean; Target: PCharacter; CountCopy: Byte;
begin
  Searched := False; Found := False; Retry := False; Target := W;
  if (ForgetTarget <> 0) or ((Target <> nil) and ((Target^ = W^) or
     (Target^ = 0) or not AttackTargetAllowed(W, Target))) then
    Target := nil;
  F2 := Found;
end;

function F3(W: PCharacter; Range, ThroughWalls, ForgetTarget: Byte): Boolean;
var
  Count: Byte; Attempts: Byte; Index: Byte; Retry: Boolean; Found: Boolean;
  Searched: Boolean; Target: PCharacter; CountCopy: Byte;
begin
  Searched := False; Found := False; Retry := False; Target := W;
  Count := CollectEnemiesInRange(W, Range);
  while (Attempts > 0) and (not Found) and (Count > 0) do
  begin
    Dec(Attempts);
    Index := RollDice(1, Count);
    if ((ThroughWalls <> 0) and (CombatMapHead6 <> 0)) or
       AttackTargetAllowed(W, Target) then
      Found := True
    else
      Found := False;
  end;
  F3 := Found;
end;

function F4(W: PCharacter; Range, ThroughWalls, ForgetTarget: Byte): Boolean;
var
  Count: Byte; Attempts: Byte; Index: Byte; Retry: Boolean; Found: Boolean;
  Searched: Boolean; Target: PCharacter; CountCopy: Byte;
begin
  Searched := False; Found := False; Retry := False; Target := W;
  CountCopy := Count;
  for Index := 1 to CountCopy do
    if ds6DE4[Index] > 0 then
      Found := True;
  F4 := Found;
end;

function F5(W: PCharacter; Range, ThroughWalls, ForgetTarget: Byte): Boolean;
var
  Count: Byte; Attempts: Byte; Index: Byte; Retry: Boolean; Found: Boolean;
  Searched: Boolean; Target: PCharacter; CountCopy: Byte;
begin
  Searched := False; Found := False; Retry := False; Target := W;
  while (not Found) and (not Retry) do
  begin
    Retry := Searched;
    if Searched and (ForgetTarget = 0) then
      CombatMapHead6 := 1;
    if not Searched then
      Searched := True;
  end;
  F5 := Found;
end;

begin
  New(Who);
  Who^ := 0;
  ds6DE4[0] := 0;
  CombatantRecord[0] := nil;
  CombatMapHead6 := 0;
  if F1(Who, 0, 0, 0) then ds6DE4[0] := 1;
  if F2(Who, 0, 0, 0) then ds6DE4[0] := 2;
  if F3(Who, 0, 0, 0) then ds6DE4[0] := 3;
  if F4(Who, 0, 0, 0) then ds6DE4[0] := 4;
  if F5(Who, 0, 0, 0) then ds6DE4[0] := 5;
end.
