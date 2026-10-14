{ Probe: TP 6.0 conditional codegen for the forms ovl22:08C3 uses. }
{$A-,F+,S-,R-,G-,I-}
program Conds;

type
  P = ^Byte;

var
  B: Byte;
  Ptr: P;
  S: Byte;

function R: Boolean; far;
begin
  R := B = 1;
end;

procedure P1; far;
begin
  if B > 0 then S := 1;
end;

procedure P2; far;
begin
  if B <> 0 then S := 1;
end;

procedure P3; far;
begin
  if Ptr <> nil then S := 1;
end;

procedure P4; far;
begin
  if Ptr = nil then S := 1;
end;

procedure P5; far;
begin
  if not R then S := 1;
end;

begin
  P1; P2; P3; P4; P5;
end.
