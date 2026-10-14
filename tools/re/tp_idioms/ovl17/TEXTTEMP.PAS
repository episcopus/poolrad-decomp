{ Probe for ovl17_e1's string-temp sharing across the `if FileExists(...) then Assign(...)`
  boundary (playbook 30). Question: which source shape makes FileExists and the following
  Assign share one 256-byte string temp (the original frame is $20c, one temp)? }
{$F+,S-,R-,I-}
program TextTemp;

type
  String40 = string[40];
var
  SaveDir: string;
  F: Text;

function FileExists(FileName: String40): Boolean;
begin
  FileExists := False;
end;

procedure A;
begin
  if FileExists(SaveDir + 'a') then
    Assign(F, SaveDir + 'a');
end;

procedure B;
var
  Ok: Boolean;
begin
  Ok := FileExists(SaveDir + 'a');
  if Ok then
    Assign(F, SaveDir + 'a');
end;

procedure C;
begin
  if FileExists(SaveDir + 'a') then
  begin
    Assign(F, SaveDir + 'a');
  end;
end;

procedure D;
begin
  if not FileExists(SaveDir + 'a') then Exit;
  Assign(F, SaveDir + 'a');
end;

begin
  A;
  B;
  C;
  D;
end.
