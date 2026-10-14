(* Probe PRBPARAM (ovl13, 2026-10-13): the parameter offset rule for a far procedure with two
  pointer parameters. Which of X and Y is at [bp+6]? (The string-parameter learning says the last
  declared value param is at [bp+6], but ovl13_e11 vs ovl08 call sites disagree.)
  Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBPARAM.PAS DISASM=1 *)
program PrbParam;
{$A-,F+}
type
  PRec = ^TRec;
  TRec = record FA: Byte; FB: Byte; end;
var
  G: PRec;

procedure Two(X: PRec; Y: PRec);
begin
  X^.FA := 1;
  Y^.FB := 2;
end;

procedure Three(P: Byte; X: PRec; Y: PRec);
begin
  P := 3;
  X^.FA := P;
  Y^.FB := P;
end;

begin
  Two(G, G);
  Three(0, G, G);
end.
