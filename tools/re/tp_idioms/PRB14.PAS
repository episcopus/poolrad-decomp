{ Probe: a function with a var file parameter and named string[40] value parameters. }
{$F+,S-,R-,I-}
program Prb14;
type
  String40 = string[40];

function Open(A: String40; B: String40; C: Byte; var F: file): Byte; far;
begin
  Open := C;
end;

begin
end.
