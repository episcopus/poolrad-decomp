unit OVL33;
{ Debug traces of the STING debug mode (whitepaper 5.8): one routine, called from the training and
  rewards unit (ovl12:2233), that shows numbers and a message only while DebugMode is set. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses RES06;
procedure ShowDebugTrace(Message: String40; First, Second, Third: Byte);
implementation
uses POOLVARS;

const
  Yellow = 14;                { EGA colour index }

{ ovl33:0004. When DebugMode is set, clears the top line, shows the three numbers there as
  "First , Second , Third" in yellow, shows Message on the message line (waiting for a key), and
  clears the top line again. Does nothing otherwise. }
procedure ShowDebugTrace(Message: String40; First, Second, Third: Byte);
var
  FirstText, SecondText, ThirdText: string;
begin
  if DebugMode then
  begin
    Str(First, FirstText);
    Str(Second, SecondText);
    Str(Third, ThirdText);
    res06_fn_0DD3(0, 0, 39, 0);
    res06_fn_0626(0, 0, Yellow, FirstText + ' , ' + SecondText + ' , ' + ThirdText);
    ShowMessageLine(Yellow, Message);
    res06_fn_0DD3(0, 0, 39, 0);
  end;
end;

begin
end.
