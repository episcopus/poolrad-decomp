unit OVL33;
{ Debug traces of the STING debug mode (whitepaper 5.8): one routine, called from the training and
  rewards unit (ovl12:2233), that shows numbers and a message only while DebugMode is set. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses RES06;
procedure ShowDebugTrace(Message: String40; Max, Current, Lost: Byte);
implementation
uses POOLVARS;

const
  Yellow = 14;                { EGA colour index the trace draws in }
  { The top text line of the 40-column text grid (whitepaper 5.2) the trace uses: leftmost column
    0, the inclusive right column 39 (res06_fn_0DD3 fills Right - Left + 1 = 40 columns) and
    character row 0 for both the top and the bottom of its one-row rectangle (it covers rows Top
    through Bottom). }
  TraceLeft = 0;
  TraceTop = 0;
  TraceRight = 39;
  TraceBottom = 0;

{ ovl33:0004. When DebugMode (DS:49F7) is set, clears the top line, shows the three numbers there
  separated by ' , ' in Yellow, shows Message on the message line and waits for a key, then clears
  the top line again. Does nothing (not even the clear) otherwise.
  The numbers are shown with res06_fn_0626(TraceLeft, TraceTop, Yellow, ...) and Message with
  ShowMessageLine(Yellow, Message) (whitepaper 5.15); both are coloured Yellow. The clear is
  res06_fn_0DD3 with the top line rectangle, through the video hardware VideoAdapter selects.
  The only caller is the training and rewards unit (ovl12:2233), which passes the label
  'max,cur,lost' and the three hit point bytes of a character: hp_max (at +$32 of the 285 byte
  character record) and the bytes at +$11B and +$75, so the three numbers are a character's
  maximum, current and lost hit points (whitepaper 4.2.5). The routine itself only shows the three
  bytes it is given.
  Parameters: Message the label shown on the message line; Max, Current, Lost the three byte values
  shown on the top line. Reads DebugMode. Side effects: the screen, and a wait for a key (through
  ShowMessageLine). }
procedure ShowDebugTrace(Message: String40; Max, Current, Lost: Byte);
var
  MaxText, CurrentText, LostText: string;
begin
  if DebugMode then
  begin
    Str(Max, MaxText);
    Str(Current, CurrentText);
    Str(Lost, LostText);
    res06_fn_0DD3(TraceLeft, TraceTop, TraceRight, TraceBottom);
    res06_fn_0626(TraceLeft, TraceTop, Yellow, MaxText + ' , ' + CurrentText + ' , ' + LostText);
    ShowMessageLine(Yellow, Message);
    res06_fn_0DD3(TraceLeft, TraceTop, TraceRight, TraceBottom);
  end;
end;

begin
end.
