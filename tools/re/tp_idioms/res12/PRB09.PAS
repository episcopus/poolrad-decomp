{ Probe for res12:0442 (playbook 30), part 6.
  Question: find the byte expression that compiles to `shr al,1` followed by a carry test, for
  the plural rule's "bit 1 of Mask is clear" term. One form per procedure. }
{$F+,S-,R-,I-}
program Res12Probe9;

var
  R: Byte;

procedure A(I: Byte);
var Mask: Byte;
begin Mask := 0;
  if (I = 2) and ((2 and Mask) = 0) then R := 1 else R := 0; end;

procedure B(I: Byte);
var Mask: Byte;
begin Mask := 0;
  if (I = 2) and (((Mask and 2) shr 1) = 0) then R := 1 else R := 0; end;

procedure C(I: Byte);
var Mask: Byte;
begin Mask := 0;
  if (I = 2) and (((Mask div 2) and 1) = 0) then R := 1 else R := 0; end;

procedure D(I: Byte);
var Mask: Byte;
begin Mask := 0;
  if (I = 2) and (Mask shr 1 and 1 = 0) then R := 1 else R := 0; end;

procedure E(I: Byte);
var Mask: Byte;
begin Mask := 0;
  if (I = 2) and (not Odd(Mask shr 1)) then R := 1 else R := 0; end;

begin
  A(0); B(0); C(0); D(0); E(0);
end.
