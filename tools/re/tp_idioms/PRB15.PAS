{ Probe: string assignment and empty assignment shapes. }
{$F+,S-,R-,I-}
program Prb15;

var
  A: string[40];
  B: string;

begin
  A := B;
  B := A;
  B := '';
end.
