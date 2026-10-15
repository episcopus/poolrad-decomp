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

{ ovl00:0042. Called by the heap manager when an allocation of Size bytes fails. A zero size
  returns at once with an unassigned Integer result (QUIRK ovl00:004C: jbe to ovl00:00A3, which
  loads AX from the result word at [bp-2] and returns without calling QuitGame). A non-zero
  size warns that memory is short; when OfferSaveOnHeapError is set it lets the player act through the save
  and load unit (SaveGame) and asks again until HeapErrorStop says to stop, else it announces the
  exit. Then it always ends the game through QuitGame, so that path never returns to the heap
  manager. }
function HeapErrorHandler(Size: Word): Integer;
var
  Quit: Boolean;
begin
  if Size > 0 then
  begin
    Quit := False;
    repeat
      ShowMessageLine(Yellow, 'WARNING: Insufficient Memory');
      if OfferSaveOnHeapError then
      begin
        SaveGame;
        Quit := HeapErrorStop;
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

{ Initialisation (ovl00:00AC): stores @HeapErrorHandler as the far pointer at DS:4414, the
  HeapError vector Turbo Pascal calls when an allocation fails (whitepaper 3.6). }
begin
  HeapError := @HeapErrorHandler;
end.
