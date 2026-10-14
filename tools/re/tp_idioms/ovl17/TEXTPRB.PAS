{ Probe for ovl17_e1's text file reading (playbook 30).
  Question: which System runtime entries do Assign/Reset/Eof/ReadLn/Close and the
  "Dir + literal" string expression compile to, and what frame does a Text local take? }
{$F+,S-,R-,I-}
program TextProbe;

var
  F: Text;
  Line: string;

procedure OnlyAssign(Name: string);
begin
  Assign(F, Name);
end;

procedure OnlyReset;
begin
  Reset(F);
end;

procedure OnlyEof;
var
  B: Boolean;
begin
  B := Eof(F);
  if B then Halt;
end;

procedure OnlyReadLn;
begin
  ReadLn(F, Line);
end;

procedure OnlyClose;
begin
  Close(F);
end;

begin
  OnlyAssign('x');
  OnlyReset;
  OnlyEof;
  OnlyReadLn;
  OnlyClose;
end.
