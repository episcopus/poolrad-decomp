{ Probe: how TP 6.0 loads the shift count for `X shl 4` on a signed byte field: the original at
  ovl22:2105 is `mov al,es:[di+0x10e]; cwde; mov cl,4 (b1 04); shl ax,cl`. Which source emits
  `mov cl,4` (a byte load) rather than `mov cx,4` (b9 04 00): a literal 4, an untyped constant, a
  Byte-typed constant, a Byte variable, or `X * 16`?
  make tpc SRC=tools/re/tp_idioms/ovl22/PRB27.PAS DISASM=1 }
{$A-,F+,S-,R-,G-,I-}
program Prb27;

type
  PCharacter = ^TCharacter;
  TCharacter = record
    Pad: array[0..$10D] of Byte;
    Side: Byte;
  end;

const
  Untyped4 = 4;
  Byte4: Byte = 4;

var
  C: PCharacter;
  R: Byte;
  N: Byte;

procedure Lit; far;
begin
  R := ShortInt(C^.Side) shl 4;
end;

procedure Untyped; far;
begin
  R := ShortInt(C^.Side) shl Untyped4;
end;

procedure ByteConst; far;
begin
  R := ShortInt(C^.Side) shl Byte4;
end;

procedure ByteVar; far;
begin
  R := ShortInt(C^.Side) shl N;
end;

procedure Times; far;
begin
  R := ShortInt(C^.Side) * 16;
end;

begin
  Lit; Untyped; ByteConst; ByteVar; Times;
end.
