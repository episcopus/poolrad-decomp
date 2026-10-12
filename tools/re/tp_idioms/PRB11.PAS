{ Probe for ovl11_e1's buffer allocation and fill shapes (playbook 30).
  Question: does ovl11:0034 (mov ax,$800; push ax; lcall 0AF8:023F; mov P,ax; mov P+2,dx)
  come from New(P) for a 2048-byte type, or from GetMem? }
{$F+,S-,R-,I-}
program Ovl11Probe;

type
  TBig = array[0..1023] of Word;
var
  P: ^TBig;

begin
  New(P);
  FillChar(P^, $800, 0);
end.
