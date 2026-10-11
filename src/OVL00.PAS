unit OVL00;
{ The heap error handler: Turbo Pascal calls HeapError when New or GetMem cannot get Size bytes. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
function ovl00_e1(Size: Word): Integer;
implementation
uses POOLVARS, RES04, RES06, OVL17;

function ovl00_e1(Size: Word): Integer;
var
  Quit: Boolean;
begin
  if Size > 0 then
  begin
    Quit := False;
    repeat
      res06_fn_0BF5(14, 'WARNING: Insufficient Memory');
      if ds49D0 then
      begin
        ovl17_e9;
        Quit := ds557D;
      end
      else
      begin
        Quit := True;
        res06_fn_0BF5(14, 'Insufficient Memory. Exiting Program');
      end;
    until Quit;
    res04_fn_0000;
  end;
end;

begin
  HeapError := @ovl00_e1;
end.
