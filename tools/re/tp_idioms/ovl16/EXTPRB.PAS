{ Probe for ovl16_e1 (playbook 30). Question: Byte + const vs ShortInt + const: which emits cwde
  and which xor ah,ah, when passed to a Byte parameter? }
{$A-,O+,F+,S-,R-,G-,I-}
program ExtPrb;
type String40 = string[40];
procedure D(Col, Row, Colour: Byte; Text: String40);
begin
end;
procedure P1;
var B: Byte;
begin D(2, B + $C, $F, ''); end;
procedure P2;
var S: ShortInt;
begin D(2, S + $C, $F, ''); end;
begin
  P1; P2;
end.
