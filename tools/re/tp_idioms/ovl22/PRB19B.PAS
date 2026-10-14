{ Probe: the exact Pascal that compiles ovl22_e19's data value to
  `mov al,Side; cbw; mov cl,7; shl ax,cl; add ax,dx` (original ovl22:123c..1246).
  The first probe (PRB19A) got cbw with a ShortInt operand but `mov cx,7` instead of
  `mov cl,7`. make tpc SRC=tools/re/tp_idioms/ovl22/PRB19B.PAS DISASM=1 }
{$A-,F+,S-,R-,G-,I-}
program SideShift2;

type
  PByteRec = ^TByteRec;
  TByteRec = record
    Side: Byte;
  end;
  PSignedRec = ^TSignedRec;
  TSignedRec = record
    Side: ShortInt;
  end;

const
  Shift1: Byte = 7;

var
  B: Byte;
  W: Word;
  R: PByteRec;
  S: PSignedRec;

function Lvl: Byte; far;
begin
  Lvl := B;
end;

procedure QA; far;              { Byte field, * 128 }
begin
  W := Lvl + R^.Side * 128;
end;

procedure QB; far;              { ShortInt field, * 128 }
begin
  W := Lvl + S^.Side * 128;
end;

procedure QC; far;              { Byte field, shl of a Byte constant }
begin
  W := Lvl + ShortInt(R^.Side) shl Shift1;
end;

procedure QD; far;              { Byte field, shl 7, no add in the expression }
var
  X: Word;
begin
  X := Lvl;
  W := X + ShortInt(R^.Side) shl 7;
end;

procedure QE; far;              { byte destination }
var
  Y: Byte;
begin
  Y := R^.Side shl 7;
  W := Y;
end;

procedure QF; far;              { Byte field, ShortInt cast, * 128 }
begin
  W := Lvl + ShortInt(R^.Side) * 128;
end;

begin
  W := 0;
  QA; QB; QC; QD; QE; QF;
end.
