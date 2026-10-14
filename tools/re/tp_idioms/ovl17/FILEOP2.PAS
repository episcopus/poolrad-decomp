{ Probe for ovl17_e4's file type (playbook 30).
  Question: does F: `file` or `file of Byte` make Reset push the size and Rewrite push a size?
  And which call shape matches 0AF8:161F (called with @F only)? }
{$F+,S-,R-,I-}
program FileOp2;

var
  F: file of Byte;
  U: file;
  B: Byte;

procedure TR;
begin
  Reset(F);
end;

procedure TW;
begin
  Rewrite(F);
end;

procedure UR;
begin
  Reset(U, 1);
end;

procedure UW;
begin
  Rewrite(U);
end;

begin
  TR;
  TW;
  UR;
  UW;
end.
