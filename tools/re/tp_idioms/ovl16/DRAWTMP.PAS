{ Probe for ovl16_e1 (playbook 30). Question: how does TP 6.0 under $O+ lay out the frame and
  the string-constant temporary for DrawWindow(1,1,$26,$16,0,0,'Choose a function '), and where
  does the String40 argument temporary sit relative to the declared locals? }
{$A-,O+,F+,S-,R-,G-,I-}
program DrawTmp;

type
  String40 = string[40];

procedure DrawWindow(LeftCol, TopRow, RightCol, BottomRow: ShortInt; FrameSet, TextColour: Byte;
  Text: String40);
begin
end;

procedure P;
var
  I: Byte;
  Key: Byte;
  ExtKey: Byte;
  Done: Byte;
  Row: Byte;
  Show: Byte;
  Mode: Byte;
begin
  DrawWindow(1, 1, $26, $16, 0, 0, 'Choose a function ');
  I := 0; Key := 0; ExtKey := 0; Done := 0; Row := 0; Show := 0; Mode := 0;
end;

begin
  P;
end.
