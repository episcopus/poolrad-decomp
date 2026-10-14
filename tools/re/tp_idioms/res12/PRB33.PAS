{ Probe for res12:2F57 (playbook 30).
  Question: the original 00BA:2F57 copies its far-pointer parameter into a local with
  `les di,[bp+8]; mov [bp-6],di; mov [bp-4],es`. Which declaration/expression makes TP 6.0
  emit that instead of `mov ax,[bp+8]; mov dx,[bp+0xa]; mov [bp-6],ax; mov [bp-4],dx`? }
{$A-,F+,S-,R-,G-,I-}
program Res12Probe33;

type
  PX = ^TX;
  TX = record
    Pad: array[0..$2D] of Byte;
    Race: ShortInt;               { +$2E }
    Pad2: array[$2F..$95] of Byte;
    Levels: array[0..7] of ShortInt;  { +$96 }
  end;

function ATyped(Who: PX; Idx: ShortInt): ShortInt; far;
var
  Member: PX;
  Level: ShortInt;
begin
  Member := Who;
  Level := Member^.Levels[Idx];
  ATyped := Level;
end;

function BUntyped(Who: Pointer; Idx: ShortInt): ShortInt; far;
var
  Member: PX;
  Level: ShortInt;
begin
  Member := Who;
  Level := Member^.Levels[Idx];
  BUntyped := Level;
end;

var
  X: ShortInt;
begin
  X := ATyped(nil, 0) + BUntyped(nil, 0);
end.
