{ Probe for ovl16:1F37 (DropCharacter, playbook 30, batch 11). Callees that live in other units
  (AskYesNo in ovl25, ShowFlashMessage in res12) are declared in DROPU so they compile to lcall;
  ovl16_e2 stays a local procedure (same unit). This reproduces the exact byte length of the
  original then-body so a three-byte difference can be located. Read TPC output for the routine's
  disassembly. }
{$A-,O+,F+,S-,R-,G-,I-}
program DropProbe3;

uses DROPU;

type
  PCharacter = ^TCharacter;
  TCharacter = record
    Name: string[15];
    Pad: array[$10..$10C] of Byte;
    Flag10D: Byte;
  end;

var
  SelectedCharacter: PCharacter;

procedure e2(Uncounted, FreePicture: Boolean); begin end;

procedure DropCharacter;
var
  Unused: Byte;
  Who: PCharacter;
begin
  if SelectedCharacter = nil then Exit;
  Who := SelectedCharacter;
  if (AskYesNo('Drop ' + Who^.Name + ' forever? ', $E, $A, $F) = 'Y')
     and (AskYesNo('Are you sure? ', $E, $A, $F) = 'Y') then
  begin
    if Who^.Flag10D = 0 then
      ShowFlashMessage('You dump ' + Who^.Name + ' out back.')
    else
      ShowFlashMessage(Who^.Name + ' bids you farewell.');
    e2(False, True);
  end
  else
    ShowFlashMessage(Who^.Name + ' breathes a sigh of relief.');
end;

begin
  DropCharacter;
end.
