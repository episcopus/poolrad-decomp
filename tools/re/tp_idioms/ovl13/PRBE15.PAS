{ Probe PRBE15 (ovl13, 2026-10-14): the local layout of ovl13:2414 (e15, CastSpell). The original
  uses ChosenChar [bp-0xa] (a far pointer, word at -0xa, segment at -8), Listed [bp-6], Choice
  [bp-5] (Word), CastTime [bp-3] and Spell [bp-1]. Question: which declaration order and sizes give
  those offsets, and what frame does the compiler reserve? Compile with
  make tpc SRC=tools/re/tp_idioms/ovl13/PRBE15.PAS DISASM=1 }
program PrbE15;
{$A-,F+,S-,R-,G-,I-}

type
  PCharacter = ^TCharacter;
  TCharacter = record
    Pad: array[0..$10B] of Byte;
  end;

var
  SelectedCharacter: PCharacter;

procedure CastSpell(A, B: Byte; var Done: Byte);
var
  Spell: Byte;
  CastTime: Byte;
  Choice: Word;
  Listed: Byte;
  ChosenChar: PCharacter;
begin
  ChosenChar := SelectedCharacter;
  Listed := 1;
  Choice := 65535;
  Spell := A;
  Done := 0;
  if Spell = 0 then
    Spell := 0;
  if Spell > 0 then
    CastTime := 5 div 3;
  if B = 0 then
    Done := 1;
  if CastTime <> 0 then
    Done := 2;
  Spell := B;
  if Spell > 0 then
    Done := 3;
end;

var
  Done: Byte;
begin
  CastSpell(0, 0, Done);
end.
