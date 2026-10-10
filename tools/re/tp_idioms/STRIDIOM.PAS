{ Example input for `make tpc` (docs/setup/SETUP-tp.md section 5): how TP 6.0
  compiles string assignment, Copy and concatenation with POOL's switches
  ($F+, $S-, $R-, $I-; WHITEPAPER 2.2). Compare the output with a routine's
  disassembly when a code shape is unclear. }
{$F+,S-,R-,I-}
program StrIdiom;

var
  Name: string[15];
  Line: string;

procedure Show(S: string; N: Integer); { TP 6.0 has no const parameters }
begin
  Line := Copy(S, 1, N) + ': ' + Name;
end;

begin
  Name := 'Phlan';
  Show('Welcome to the city', 10);
end.
