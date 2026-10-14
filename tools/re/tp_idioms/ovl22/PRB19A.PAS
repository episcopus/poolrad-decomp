{ Probe: which Pascal construct compiles ovl22_e19's data value
  `res12_fn_26C2(Spell) + SelectedCharacter^.Side shl 7` to `mov al,Side; cbw; mov cl,7;
  shl ax,cl; add ax,dx` (the original ovl22:123c..1246). A Byte field shifts with
  `xor ah,ah; mov cx,7`; a ShortInt field or a ShortInt cast sign-extends with cbw and
  `mov cl,7`. ovl22:11DD.
  make tpc SRC=tools/re/tp_idioms/ovl22/PRB19A.PAS DISASM=1 }
{$A-,F+,S-,R-,G-,I-}
program SideShift;

type
  PByteRec = ^TByteRec;
  TByteRec = record
    Side: Byte;
  end;
  PSignedRec = ^TSignedRec;
  TSignedRec = record
    Side: ShortInt;
  end;

var
  B: Byte;
  Wb: Word;
  R: PByteRec;
  S: PSignedRec;

function Lvl: Byte; far;
begin
  Lvl := B;
end;

procedure Q1; far;              { Byte field, Side shl 7 }
begin
  Wb := Lvl + R^.Side shl 7;
end;

procedure Q2; far;              { ShortInt field, Side shl 7 }
begin
  Wb := Lvl + S^.Side shl 7;
end;

procedure Q3; far;              { Byte field, ShortInt cast }
begin
  Wb := Lvl + ShortInt(R^.Side) shl 7;
end;

begin
  Wb := 0;
  Q1; Q2; Q3;
end.
