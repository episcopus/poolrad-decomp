unit OVL00;
{ The heap error handler (whitepaper 5.15): Turbo Pascal calls HeapError when New or GetMem cannot get
  Size bytes; this unit's initialisation installs HeapErrorHandler there. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
function HeapErrorHandler(Size: Word): Integer;
implementation
uses POOLVARS, RES04, RES06, OVL17;

const
  Yellow = 14;                { EGA colour index }

{ ovl00:0042. Called by the heap manager when an allocation of Size bytes fails. Warns that memory is
  short; when ds49D0 is set it lets the player act through the save and load unit (ovl17_e9) and asks
  again until ds557D says to stop, else it announces the exit. Then it always ends the game.
  QUIRK ovl00:00A3: the function result is never assigned; the handler never returns to the heap
  manager in practice, since QuitGame halts. }
function HeapErrorHandler(Size: Word): Integer;
var
  Quit: Boolean;
begin
  if Size > 0 then
  begin
    Quit := False;
    repeat
      ShowMessageLine(Yellow, 'WARNING: Insufficient Memory');
      if ds49D0 then
      begin
        ovl17_e9;
        Quit := ds557D;
      end
      else
      begin
        Quit := True;
        ShowMessageLine(Yellow, 'Insufficient Memory. Exiting Program');
      end;
    until Quit;
    QuitGame;
  end;
end;

begin
  HeapError := @HeapErrorHandler;
end.
