{ Probe for res12:1FEB (playbook 30).
  Question: in what declaration order does TP 6.0 place locals when a value String40
  parameter copy also occupies the frame? The original frame is sub sp,0x30 with the
  parameter copy at [bp-0x29] and six byte locals at [bp-0x2a..bp-0x2f]. }
{$A-,F+,S-,R-,G-,I-}
program Res12Probe19;

type
  String40 = string[40];

var
  Probe: Byte;

procedure Q(Who: Pointer; Flag: Byte; Text: String40);
var
  Col, Row, Icon, Inner, Outer, Count: Byte;
begin
  Col := 1;
  Row := 2;
  Icon := 3;
  Inner := 4;
  Outer := 5;
  Count := 6;
  Probe := Col + Row + Icon + Inner + Outer + Count;
end;

begin
  Q(nil, 0, '');
end.
