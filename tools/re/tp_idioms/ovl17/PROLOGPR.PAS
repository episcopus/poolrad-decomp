{ Probe for ovl17_e4's prologue (playbook 30).
  Question: where does the String8 value-parameter copy go, relative to the `if Name = ''` test? }
{$F+,S-,R-,I-}
program PrologProbe;

type
  String8 = string[8];
  PCharacter = ^TCharacter;
  TCharacter = record Name: string[15]; Pad: array[0..$FF] of Byte; end;

procedure T(Name: String8; Who: PCharacter);
begin
  if Name = '' then
    Who := nil;
end;

begin
  T('', nil);
end.
