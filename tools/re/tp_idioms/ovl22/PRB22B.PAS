{ Probe: which source form increments a pointed-to byte field in place with a function result:
  `F := F + R` (word-extends, `xor ah,ah`), or `Inc(F, R)`, or a `with` block. ovl22_e22's
  original is `call RollDice; les di,[ds6C95]; add es:[di+0x15], al` (a byte add in place).
  make tpc SRC=tools/re/tp_idioms/ovl22/PRB22B.PAS DISASM=1 }
{$A-,F+,S-,R-,G-,I-}
program Prb22B;

type
  PCharacter = ^TCharacter;
  TCharacter = record
    Pad: array[0..$14] of Byte;
    Charisma: Byte;
  end;

var
  C: PCharacter;

function R: Byte; far;
begin
  R := 1;
end;

procedure A; far;
begin
  C^.Charisma := C^.Charisma + R;
end;

procedure B; far;
begin
  Inc(C^.Charisma, R);
end;

procedure D; far;
begin
  with C^ do
    Charisma := Charisma + R;
end;

begin
  A; B; D;
end.
