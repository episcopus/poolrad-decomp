{ Probe for ovl17_e2's file read/write and string runtime entries (playbook 30).
  Question: which Pascal statements produce 0AF8:056C (not the 0567 of Reset), 0AF8:0919,
  0AF8:084A, 0AF8:0C3B and 0AF8:04A2? }
{$F+,S-,R-,I-}
program FileProbe;

var
  F: Text;
  S: string;

procedure DoRewrite;
begin
  Rewrite(F);
end;

procedure DoReset;
begin
  Reset(F);
end;

procedure DoWrite;
begin
  Write(F, S);
end;

procedure DoWriteLn;
begin
  WriteLn(F, S);
end;

procedure DoWriteChar;
begin
  Write(F, S[1]);
end;

procedure DoDelete;
begin
  Delete(S, 1, 2);
end;

procedure DoCopy;
begin
  S := Copy(S, 2, 40);
end;

begin
  DoRewrite;
  DoReset;
  DoWrite;
  DoWriteLn;
  DoWriteChar;
  DoDelete;
  DoCopy;
end.
