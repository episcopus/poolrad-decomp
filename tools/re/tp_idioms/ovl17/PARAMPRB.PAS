{ Probe for ovl17_fn_032F's dispatch and parameter use (playbook 30).
  Question 1: `case VideoAdapter of 0, 2: ...; 1: ...` compiles to `mov al,[VideoAdapter];
  cmp al,0; je A; cmp al,2; je A; jmp CheckB` (the original's shape), unlike the equivalent
  `if (V=0) or (V=2) ... else if V=1` which compares the memory operand directly.
  Question 2: with `procedure T(Source, Dest: Pointer)` the LAST declared parameter is nearest bp
  ([bp+6]) and the first at [bp+0xa], so `Source` (read only) is the first and `Dest` (written)
  the second. }
{$F+,S-,R-,I-}
program ParamProbe;

type
  PMemPic = ^TMemPic;
  TMemPic = record
    Head: array[0..$10] of Byte;
    ByteSize: Word;
    Pixels: ^Byte;
    Tail: array[0..20000] of Byte;
  end;
  PByteArray = ^TByteArray;
  TByteArray = array[0..65519] of Byte;

var
  V: Byte;

procedure T(Dest, Source: Pointer);
var
  I: Word;
begin
  case V of
    0, 2:
      begin
        for I := 0 to PMemPic(Source)^.ByteSize - 1 do
        begin
          PMemPic(Dest)^.Tail[I] := PMemPic(Dest)^.Tail[I] or PMemPic(Source)^.Tail[I];
          PByteArray(PMemPic(Dest)^.Pixels)^[I] :=
            PByteArray(PMemPic(Dest)^.Pixels)^[I] and PByteArray(PMemPic(Source)^.Pixels)^[I];
        end;
      end;
    1:
      begin
        for I := 0 to PMemPic(Source)^.ByteSize - 1 do
          PMemPic(Dest)^.Tail[I] := PMemPic(Dest)^.Tail[I] or PMemPic(Source)^.Tail[I];
      end;
  end;
end;

begin
  T(nil, nil);
end.
