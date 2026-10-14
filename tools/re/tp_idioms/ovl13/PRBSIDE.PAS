(* Probe PRBSIDE (ovl13, 2026-10-13): which source makes `(Side + 1) and Word715 <> 0` extend the
  side byte with the one-byte sign-extend (cbw) as ovl13:00C5 does
  (`mov al,es:[di+0x10e]; cbw; inc ax; ...; or al,al`) instead of the two-byte `xor ah,ah`.
  Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBSIDE.PAS DISASM=1 *)
program PrbSide;
{$A-,F+}
var
  B: Byte;
  S: ShortInt;
  W: Word;

procedure A1;
begin if ((B + 1) and W) <> 0 then B := 0; end;

procedure A2;
begin if ((S + 1) and W) <> 0 then B := 0; end;

procedure A3;
begin if ((ShortInt(B) + 1) and W) <> 0 then B := 0; end;

procedure A4;
begin if ((B + 1) and ShortInt(W)) <> 0 then B := 0; end;

begin
  A1; A2; A3; A4;
end.
