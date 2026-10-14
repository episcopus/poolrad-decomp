program FNSTMT;
{ Probe for ovl12:133F (ovl12_e43). A Byte function called only for its effect, with its result dropped, is not
  a statement in Turbo Pascal 6.0: the compiler stops with Error 122 (Invalid variable reference) on the bare call.
  Compile with make tpc SRC=tools/re/tp_idioms/ovl12/FNSTMT.PAS. The original calls res12_fn_2637 and tests the
  result with or al, al; je next, so the source form that matches is `if F(P) <> 0 then ;`. }
function F(P: Pointer): Byte;
begin
  F := 1;
end;

var
  P: Pointer;

begin
  F(P);
end.
