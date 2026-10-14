(* Probe PRBSHR (ovl13, 2026-10-13): ovl13:01FB is `cbw; shr ax,1; shr ax,1` (two one-bit shifts),
  but `S shr 2` with S: ShortInt compiled to `mov cx,2; shr ax,cl`. Which source gives the repeated
  one-bit shifts? Candidates: div 4, shr 1 twice, a Byte level with a ShortInt cast.
  Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBSHR.PAS DISASM=1 *)
program PrbShr;
{$A-,F+}
var
  S: ShortInt;
  B: Byte;
  R: Integer;

procedure A1; begin R := S shr 2; end;
procedure A2; begin R := S div 4; end;
procedure A3; begin R := B shr 2; end;
procedure A4; begin R := ShortInt(B) shr 2; end;
procedure A5; begin R := S shr 1 shr 1; end;

begin
  A1; A2; A3; A4; A5;
end.
