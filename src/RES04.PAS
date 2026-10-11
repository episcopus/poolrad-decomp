unit RES04;
{$A-,F+,S-,R-,G-,I-}
interface
procedure res04_fn_0000;
function res04_fn_0059: Char;
procedure res04_fn_0104;
procedure res04_fn_0122;
implementation
uses Crt, Dos, POOLVARS, RES03;

procedure res04_fn_0000;
begin
  ds5372 := ds5373;
  res03_fn_00DC(ds2612);
  Regs.AH := 0;
  Regs.AL := ds4A1C;
  Intr($10, Regs);
  Halt;
end;

function res04_fn_0059: Char;
var
  Key: Char;
begin
  Key := ReadKey;
  if Key = #19 then
    if ds5372 <> 2 then
    begin
      ds5373 := ds5372;
      res03_fn_00DC(ds2612);
      ds5372 := 2;
    end
    else if ds5373 in [0, 1] then
    begin
      ds5372 := ds5373;
      res03_fn_017B;
    end;
  if ParamStr(1) = 'STING' then
  begin
    if Key = #4 then ds49F7 := not ds49F7;
    if Key = #3 then res04_fn_0000;
  end;
  if Key <> #0 then
    while KeyPressed do Key := ReadKey;
  res04_fn_0059 := Key;
end;

procedure res04_fn_0104;
var
  Key: Char;
begin
  Exit;
  while KeyPressed do Key := res04_fn_0059;
end;

procedure res04_fn_0122;
var
  Key: Char;
begin
  if KeyPressed then Key := res04_fn_0059;
end;

begin
end.
