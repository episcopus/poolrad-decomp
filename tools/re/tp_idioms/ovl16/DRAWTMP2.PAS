{ Probe for ovl16_e1 (playbook 30). Question: with several string arguments in one routine, in
  which order does TP 6.0 place their hidden stack temporaries in the frame? }
{$A-,O+,F+,S-,R-,G-,I-}
program DrawTmp2;

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
begin
  DrawWindow(1, 1, $26, $16, 0, 0, 'Choose a function ');
  DrawWindow(1, 1, $26, $16, 0, 0, 'Another title here');
  DrawWindow(1, 1, $26, $16, 0, 0, 'Quit to DOS ');
  I := 0; Key := 0;
end;

begin
  P;
end.
