program WHILETRU;
{ Probe for ovl03:32F8 (ovl03_e1, the wilderness loop). The loop ends only through Exit, with an unconditional jmp
  back to its head (ovl03:3449 jmp 33b9). Does `while True do` add a test at the head or at the bottom? Compare
  the code of a while True loop with the same loop written as repeat ... until False. Run:
  make tpc SRC=tools/re/tp_idioms/ovl03/WHILETRU.PAS DISASM=1 }
var
  K: Byte;

procedure LoopWhileTrue;
begin
  while True do
  begin
    if K > 1 then
      K := 0
    else
    begin
      K := 1;
      if K = 9 then Exit;
    end;
  end;
end;

procedure LoopRepeatFalse;
begin
  repeat
    if K > 1 then
      K := 0
    else
    begin
      K := 1;
      if K = 9 then Exit;
    end;
  until False;
end;

begin
  LoopWhileTrue;
  LoopRepeatFalse;
end.
