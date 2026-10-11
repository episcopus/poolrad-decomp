unit OVL33;
{ ovl33: overlay unit, 252 bytes of code. Skeleton by tools/match/skeleton.py: every routine is a stub
  until decompiled (playbook 30). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses RES06;
procedure ovl33_e1(Text: String40; A, B, C: Byte);
implementation
uses POOLVARS;

{ ovl33:0004: retf 10: 10 bytes of parameters; 1066 bytes of locals }
{ Debug trace: when the STING debug mode is on (ds49F7, whitepaper 5.8), show three numbers and a message. }
procedure ovl33_e1(Text: String40; A, B, C: Byte);
var
  SA, SB, SC: string;
begin
  if ds49F7 then
  begin
    Str(A, SA);
    Str(B, SB);
    Str(C, SC);
    res06_fn_0DD3(0, 0, 39, 0);
    res06_fn_0626(0, 0, 14, SA + ' , ' + SB + ' , ' + SC);
    res06_fn_0BF5(14, Text);
    res06_fn_0DD3(0, 0, 39, 0);
  end;
end;

begin
end.
