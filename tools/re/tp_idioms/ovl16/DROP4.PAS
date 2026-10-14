{ Probe for ovl16:1F37 (DropCharacter, playbook 30, batch 11). The original loads
  SelectedCharacter with `les di,[0x5d92]; mov [bp-5],di; mov [bp-3],es` and reads Name and
  Flag10D through [bp-5]: the `with SelectedCharacter^ do` compiler temp, not `Who := SelectedCharacter`
  (which is word moves). This probe checks the temp offset and the one-byte named local the original
  frame shows above it. Far callees from DROPU so the call lengths match the unit. }
{$A-,O+,F+,S-,R-,G-,I-}
program DropProbe4;

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
begin
  if SelectedCharacter = nil then Exit;
  with SelectedCharacter^ do
  begin
    if (AskYesNo('Drop ' + Name + ' forever? ', $E, $A, $F) = 'Y')
       and (AskYesNo('Are you sure? ', $E, $A, $F) = 'Y') then
    begin
      if Flag10D = 0 then
        ShowFlashMessage('You dump ' + Name + ' out back.')
      else
        ShowFlashMessage(Name + ' bids you farewell.');
      e2(False, True);
    end
    else
      ShowFlashMessage(Name + ' breathes a sigh of relief.');
  end;
end;

begin
  DropCharacter;
end.
