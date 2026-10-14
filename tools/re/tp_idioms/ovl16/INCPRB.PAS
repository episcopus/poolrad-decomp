{ Probe for ovl16:42ED (playbook 30, batch 17). The original increments its coin-kind index with
  `mov al,[bp-3]; inc al; mov [bp-3],al` (8-bit) while indexing the coin table with cwde (signed),
  and decrements with the same shape (`dec al`). Find which declaration/expression gives both. }
{$A-,O+,F+,S-,R-,G-,I-}
program IncProbe;
type
  TKind = (Copper, Silver, Electrum, Gold, Platinum);
var
  K: ShortInt;
  B: Byte;
  E: TKind;
  T: array[0..4] of LongInt;
  V: LongInt;

procedure A1; begin K := K + 1; end;
procedure A2; begin Inc(K); end;
procedure A3; begin K := Succ(K); end;
procedure A4; begin B := B + 1; end;
procedure A5; begin Inc(B); end;
procedure A6; begin K := K - 1; end;
procedure A7; begin E := Succ(E); end;
procedure A8; begin E := Pred(E); end;
procedure B1; begin V := T[K]; end;
procedure B2; begin V := T[B]; end;
procedure B3; begin V := T[Ord(E)]; end;

begin
  A1; A2; A3; A4; A5; A6; A7; A8; B1; B2; B3;
end.
