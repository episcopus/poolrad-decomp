{ Probe for res12:0442 (playbook 30), part 7.
  Question: find the byte expression that compiles to a single `shr al,1` plus a carry test
  (bit 1 of Mask clear) inside an OR chain. }
{$F+,S-,R-,I-}
program Res12Probe10;

var
  R: Byte;

procedure A(I: Byte);
var Mask: Byte;
begin Mask := 0;
  if (I = 2) and not (Mask and 2 <> 0) then R := 1 else R := 0; end;

procedure B(I: Byte);
var Mask: Byte;
begin Mask := 0;
  if (I = 2) and not ((Mask shr 1) and 1 <> 0) then R := 1 else R := 0; end;

procedure C(I: Byte);
var Mask: Byte;
begin Mask := 0;
  if (I = 2) and ((Mask and 2) <> 2) then R := 1 else R := 0; end;

procedure D(I: Byte);
var Mask: Byte;
begin Mask := 0;
  if (I = 2) and (((Mask shr 1) and 1) <> 1) then R := 1 else R := 0; end;

procedure E(I: Byte);
var Mask: Byte;
begin Mask := 0;
  if (I = 2) and (((Mask and 2) div 2) = 0) then R := 1 else R := 0; end;

procedure F(I: Byte);
var Mask: Byte;
begin Mask := 0;
  if (I = 2) and (((Mask and 3) and 2) = 0) then R := 1 else R := 0; end;

begin
  A(0); B(0); C(0); D(0); E(0); F(0);
end.
