{ Probe for ovl16_e1 (playbook 30). Question: after System_SetIn (0AF8:0DC0) for `K in ['G','O']`,
  which conditional jump means the element IS in the set? }
{$A-,O+,F+,S-,R-,G-,I-}
program SetPrb;

var
  K: Char;
  N: Byte;

begin
  N := 0;
  if K in ['G', 'O'] then
    N := 1;
  if not (K in ['E', 'S']) then
    N := 2;
end.
