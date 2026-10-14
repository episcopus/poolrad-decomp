{ Probe helper unit for ovl16:1F37 (DROP3). Its routines live in another segment, so the calls
  compile to lcall (9a) exactly like AskYesNo (ovl25) and ShowFlashMessage (res12) in the unit. }
{$A-,O+,F+,S-,R-,G-,I-}
unit DROPU;

interface

type
  String40 = string[40];

procedure ShowFlashMessage(Text: String40);
function AskYesNo(Prompt: String40; TitleColor, WordColor, HotColor: Byte): Char;

implementation

procedure ShowFlashMessage(Text: String40);
begin
end;

function AskYesNo(Prompt: String40; TitleColor, WordColor, HotColor: Byte): Char;
begin
  AskYesNo := 'Y';
end;

end.
