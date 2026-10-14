program PRBDIRS;
{$A-,F+,S-,R-,G+,I-}
{ Probe: what source shape gives ovl13:2DFA's `mov al,[DirStepX[Dir]]; add byte [CurX],al`
  (an 8-bit in-place add) instead of the 16-bit `cwde; add ax,dx`? }
type
  TStepsS = array[0..8] of ShortInt;
  TStepsB = array[0..8] of Byte;
var
  StepsS: TStepsS;
  StepsB: TStepsB;
  I: Byte;

procedure IncShort;             { Inc(local ShortInt, ShortInt) }
var
  S: ShortInt;
begin
  S := 0;
  Inc(S, StepsS[I]);
end;

procedure AddShortLocal;        { local ShortInt := local ShortInt + ShortInt }
var
  S: ShortInt;
begin
  S := 0;
  S := S + StepsS[I];
end;

procedure IncByteArr;           { Inc(local ShortInt, Byte) }
var
  S: ShortInt;
begin
  S := 0;
  Inc(S, StepsB[I]);
end;

procedure AddByteArr;           { local ShortInt := local ShortInt + Byte }
var
  S: ShortInt;
begin
  S := 0;
  S := S + StepsB[I];
end;

procedure AddByteLocal;         { local Byte := local Byte + Byte }
var
  S: Byte;
begin
  S := 0;
  S := S + StepsB[I];
end;

begin
  IncShort;
  AddShortLocal;
  IncByteArr;
  AddByteArr;
  AddByteLocal;
end.
