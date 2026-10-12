{ Probe: far pointer assignment shapes (ovl28_e3's `List := Rec`). }
{$F+,S-,R-,I-}
program Prb18;

type
  PB = ^Byte;

var
  List: PB;

procedure P(Rec: PB); far;
begin
  List := Rec;
end;

procedure Q(Rec: PB); far;
var
  L: PB;
begin
  L := Rec;
  if L <> nil then List := L;
end;

begin
  P(nil);
  Q(nil);
end.
