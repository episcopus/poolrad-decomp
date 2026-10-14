program E61SHL;
{ Probe for ovl12:176F (ovl12_e61): Dec(Affect^.Duration, n) with Dice a Byte local and Duration a Word field through
  a pointer. The original shape is xor ah, ah; mov cl, 4; shl ax, cl; sub word [es:di+1], ax (two-byte mov cl).
  Result (make tpc DISASM=1): Dice * 16 gives mov cl, 4; shl ax, cl (the original); Dice shl 4 and Word(Dice) shl 4
  and (Dice shl 4) div 1 give mov cx, 4; shl ax, cl (three bytes, one byte too long). }
type
  PAff = ^TAff;
  TAff = record
    Id: Byte;
    Duration: Word;
    Data: Byte;
    Flag: Byte;
    Next: PAff;
  end;
var
  P: PAff;
procedure ShlByte(Dice: Byte);
begin
  Dec(P^.Duration, Dice shl 4);
end;
procedure MulByte(Dice: Byte);
begin
  Dec(P^.Duration, Dice * 16);
end;
procedure ShlWord(Dice: Byte);
begin
  Dec(P^.Duration, Word(Dice) shl 4);
end;
procedure DivWord(Dice: Byte);
begin
  Dec(P^.Duration, (Dice shl 4) div 1);
end;
begin
  P := nil;
  ShlByte(1);
  MulByte(2);
  ShlWord(3);
  DivWord(4);
end.
