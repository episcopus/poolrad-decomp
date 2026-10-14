program CASEAX;
{ Probe for ovl03:1435 (ScanPartyCommand). A case on a Word local loads it into AX once and compares
  AX with each label (mov ax,[x]; cmp ax,0; cmp ax,6BA7 ...), while a chain of ifs on the same local
  compares the memory operand each time (cmp word [x],0). Sum := Sum + V compiles to a load and a store
  (add ax,[Sum]; mov [Sum],ax), Inc(Sum, V) adds in place (add [Sum],ax). Run:
  make tpc SRC=tools/re/tp_idioms/ovl03/CASEAX.PAS DISASM=1 }
var
  Stat: Word;
  Hits: Byte;
  Sum: Word;
  V: Byte;

procedure CaseArms;
begin
  case Stat of
    0: Hits := 1;
    $6BA7: Hits := 2;
    $6C1B: Hits := 3;
  end;
end;

procedure IfArms;
begin
  if Stat = 0 then
    Hits := 1
  else if Stat = $6BA7 then
    Hits := 2;
end;

procedure SumArms;
begin
  Sum := Sum + V;
  Inc(Sum, V);
end;

begin
  CaseArms;
  IfArms;
  SumArms;
end.
