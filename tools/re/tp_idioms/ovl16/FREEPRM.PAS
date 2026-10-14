{ Probe for ovl16_fn_0000 (playbook 30). Question: what does TP 6.0 emit for FreeMem(P, Size)
  followed by P := nil, for a value parameter vs a var parameter? The target ends with:
  push [bp+8]; push [bp+6]; push $11D; call System_FreeMem; mov [bp+6],0; mov [bp+8],0 }
{$A-,O+,F+,S-,R-,G-,I-}
program FreePrm;

type
  PByte = ^Byte;

procedure TestVal(P: PByte);
begin
  FreeMem(P, 5);
  P := nil;
end;

procedure TestVar(var P: PByte);
begin
  FreeMem(P, 5);
  P := nil;
end;

var
  G, H: PByte;

begin
  TestVal(G);
  TestVar(H);
end.
