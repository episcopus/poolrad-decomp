{ Probe: how TP 6.0 compiles a nil assignment to a far-pointer global followed by an early Exit,
  as ovl22_e30 (ovl22:185B) writes ds6C95 := nil and exits. The original is
    cmp byte es:[di+10C],1 ; jne skip ; xor ax,ax ; mov [6C95],ax ; mov [6C97],ax ; jmp short epilogue
  so the block is 10 bytes and the Exit is a 2-byte short jump. Find the source form that gives it.
  make tpc SRC=tools/re/tp_idioms/ovl22/E30EXIT.PAS DISASM=1 }
{$A-,O+,F+,S-,R-,G-,I-}
program E30Exit;
type
  PRec = ^TRec;
  TRec = record
    Pad: array[0..$10B] of Byte;
    Status: Byte;
  end;
var
  ds6C95: PRec;

procedure A; far;
var
  T: PRec;
begin
  T := ds6C95;
  if T^.Status = 1 then
  begin
    ds6C95 := nil;
    Exit;
  end;
  T^.Status := 2;
end;

procedure B; far;
var
  T: PRec;
begin
  T := ds6C95;
  if T^.Status = 1 then
  begin
    ds6C95 := nil;
    Exit;
  end;
  T^.Status := 2;
  T^.Status := 3;
end;

begin
  A;
  B;
end.
