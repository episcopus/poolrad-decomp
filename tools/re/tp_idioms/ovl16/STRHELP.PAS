{ Probe for ovl16_e1's roster drawing (playbook 30). Question: which Pascal string expressions
  produce the runtime helpers 0AF8:0C3B and 0AF8:0B57 with the argument shapes seen at
  ovl16:0249 (2, col, $F, dest, byte) and ovl16:0278 (3, col, $A, dest, src, 2, len-1)? }
{$A-,O+,F+,S-,R-,G-,I-}
program ProbeStr;

type
  String40 = string[40];

var
  Name: string[41];
  I: Byte;

procedure DrawTextAt(Col, Row, Colour: Byte; Text: String40);
begin
end;

begin
  DrawTextAt(2, I + $C, $F, Name[1]);
  DrawTextAt(3, I + $C, $A, Copy(Name, 2, Length(Name) - 1));
end.
