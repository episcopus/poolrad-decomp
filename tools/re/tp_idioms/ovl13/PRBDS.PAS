(* Probe PRBDS (ovl13, 2026-10-13): which DS offsets do the POOLVARS declarations compile to? The
   var section mixes plain declarations and `absolute` overlays, so read the actual offsets.
   Compile with: make tpc SRC=tools/re/tp_idioms/ovl13/PRBDS.PAS DISASM=1 *)
program PrbDs;
uses POOLVARS;
var
  P: Pointer;
begin
  P := @ds2622;
  P := @ds260A;
  P := @ds0447;
  P := @ds6825;
  P := @ds6E2F;
  P := @ds6E31;
  P := @SaveKind;
end.
