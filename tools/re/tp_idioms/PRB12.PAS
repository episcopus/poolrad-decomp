{ Probe: parameter push order and frames for far procedures and functions (playbook 30). }
{$F+,S-,R-,I-}
program Prb12;

type
  PB = ^Byte;

procedure Proc(A, B: Word); far;
begin
  A := A + B;
end;

function Func(A, B: Word): Pointer; far;
begin
  Func := Pointer(A + B);
end;

function FStr(Dest, Source: Pointer): Pointer; far;
begin
  FStr := Dest;
end;

var
  Q: Pointer;
  S: array[0..31] of Char;
  D: array[0..31] of Char;

begin
  Proc(1, 2);
  Q := Func(3, 4);
  FillChar(D, 4, 0);
end.
