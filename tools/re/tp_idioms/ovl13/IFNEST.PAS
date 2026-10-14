(* Probe IFNEST (ovl13, 2026-10-14): the block order TP 6.0 emits for an if/else whose
   condition is an `and` or `or` chain, and how a trailing `Exit` changes it. ovl13:3A86
   (the affect $4A handler) emits [condition tests][the RemoveAffect block][jmp epilogue]
   [the PerformAttack block][epilogue], which is neither the and-form nor a plain or-form
   (its last test jumps to the *second* block on true). Compile with:
   make tpc SRC=tools/re/tp_idioms/ovl13/IFNEST.PAS DISASM=1 *)

program Ifnest;

var
  Mode, F1, F2: Byte;

procedure Attack;
begin
  Mode := 1;
  F1 := 2;
  F2 := 3;
  Mode := 4;
end;

procedure Cleanup;
begin
  F1 := 5;
  F2 := 6;
  Mode := 7;
end;

procedure P1;                       { and-form, then is the attack }
begin
  if (Mode = 0) and (F1 <> 0) and (F2 <> 0) then
    Attack
  else
    Cleanup;
end;

procedure P2;                       { or-form, then is the cleanup }
begin
  if (Mode <> 0) or (F1 = 0) or (F2 = 0) then
    Cleanup
  else
    Attack;
end;

procedure P3;                       { early Exit, cleanup first }
begin
  if (Mode <> 0) or (F1 = 0) or (F2 = 0) then
  begin
    Cleanup;
    Exit;
  end;
  Attack;
end;

procedure P4;                       { early Exit, attack first }
begin
  if (Mode = 0) and (F1 <> 0) and (F2 <> 0) then
  begin
    Attack;
    Exit;
  end;
  Cleanup;
end;

begin
  P1;
  P2;
  P3;
  P4;
end.
