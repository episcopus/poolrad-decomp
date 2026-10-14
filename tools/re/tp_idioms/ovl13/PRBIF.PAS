(* Probe PRBIF (ovl13, 2026-10-13): branch layout TP 6.0 picks for `if Flag <> 0 then <roll> else
  Init := 0` inside a `with`. ovl13:008A is `je 0xff` (then-body first): if Who^.Flag10D = 0 jump to
  the else. Our draft compiled the same source to `jne +3` (else first). Find the source that gives
  `je` to the else.
  Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBIF.PAS DISASM=1 *)
program PrbIf;
{$A-,F+}
type
  PComb = ^TComb;
  TComb = record FA: Byte; FB: Byte; FInit: ShortInt; FMoves: Byte; FSide: Byte; end;
  PChar = ^TChar;
  TChar = record Pad0: array[0..$107] of Byte; Combat: PComb;
    Pad10C: array[$10C..$10E] of Byte; end;
var
  G: PChar;

procedure FormA(Who: PChar);
var U: Byte;
begin
  with Who^.Combat^ do
  begin
    FA := 0;
    if Who^.Pad10C[$10D] <> 0 then
    begin
      FInit := FSide + 1;
      if FInit < 1 then
        FInit := 1;
      if FInit > $14 then
        FInit := 0;
    end
    else
      FInit := 0;
  end;
  Who^.Combat^.FMoves := 0;
end;

procedure FormB(Who: PChar);
var U: Byte;
begin
  with Who^.Combat^ do
  begin
    FA := 0;
    if Who^.Pad10C[$10D] = 0 then
      FInit := 0
    else
    begin
      FInit := FSide + 1;
      if FInit < 1 then
        FInit := 1;
      if FInit > $14 then
        FInit := 0;
    end;
  end;
  Who^.Combat^.FMoves := 0;
end;

begin
  FormA(G);
  FormB(G);
end.
