{ Probe: how a value string[40] parameter is copied in the prologue, and the
  argument order of the 0AF8:0B25 copy (ovl22:08C3 and ovl22:331A pass a Message on). }
{$A-,F+,S-,R-,G-,I-}
program StrParam;

type
  String40 = string[40];

procedure Show(Spell: Byte; Level: Byte; Msg: String40); far;
begin
  if Spell = 0 then
    Level := Level + 1;
end;

begin
  Show(1, 2, 'hi');
end.
