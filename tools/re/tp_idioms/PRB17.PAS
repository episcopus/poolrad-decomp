{ Probe: `if Bool then` vs `if Byte <> 0 then` (the 4th parameter of Put8x8Symbol). }
{$F+,S-,R-,I-}
program Prb17;

procedure PFlag(Flag: Boolean); far;
begin
  if Flag then Flag := False;
end;

procedure PByte(Direct: Byte); far;
begin
  if Direct <> 0 then Direct := 0;
end;

begin
  PFlag(True);
  PByte(1);
end.
