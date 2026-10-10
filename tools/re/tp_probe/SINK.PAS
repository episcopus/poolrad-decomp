{ Turbo Pascal toolchain probe (tools/re/tp_toolchain.py).
  Pulls in as much of the System, Crt, Dos and Overlay runtime as possible so
  the smart linker keeps a superset of what POOL.EXE links. It is compiled,
  never run. Must stay valid for both TP 6.0 and TP 7.0. }
{$F+}
program Sink;

uses Overlay, Crt, Dos, OVU;

{$O OVU}

type
  PRec = ^TRec;
  TRec = record
    A: Integer;
    B: Longint;
    S: string[20];
  end;
  TBig = array[0..299] of Byte;
  PObj = ^TObj;
  TObj = object
    X: Integer;
    constructor Init;
    procedure Show; virtual;
    destructor Done; virtual;
  end;

var
  F: file;
  T: Text;
  FB: file of Byte;
  B: Byte;
  S, S2: string;
  SS: string[10];
  C: Char;
  I, Code: Integer;
  W, H, M, Sec, Hs: Word;
  L, L2: Longint;
  R: Real;
  P: PRec;
  Q: Pointer;
  Buf: array[0..255] of Byte;
  St: set of Char;
  O: PObj;
  Dt: DateTime;
  Sr: SearchRec;
  Regs: Registers;
  Big1, Big2: TBig;

constructor TObj.Init;
begin
  X := 1;
end;

procedure TObj.Show;
begin
  Writeln(X);
end;

destructor TObj.Done;
begin
end;

begin
  OvrInit('SINK.OVR');
  if OvrResult <> ovrOk then Halt(1);
  OvrInitEMS;
  OvrSetBuf(OvrGetBuf);
  OvrClearBuf;

  ClrScr; GotoXY(1, 1); TextColor(7); TextBackground(0);
  Window(1, 1, 80, 25); ClrEol; InsLine; DelLine; HighVideo; LowVideo; NormVideo;
  if KeyPressed then C := ReadKey;
  Delay(1); Sound(440); NoSound; I := WhereX + WhereY; TextMode(LastMode);
  AssignCrt(T);

  S := 'abc'; S2 := Copy(S, 2, 1); S := S + S2 + 'x'; SS := S; S := C;
  I := Pos('b', S); Insert('z', S, 2); Delete(S, 1, 1);
  Str(I, S2); Str(I:5, S2); Str(L:8, S2); Str(R:8:2, S2);
  Val(S2, I, Code); Val(S2, L, Code); Val(S2, R, Code);
  C := UpCase(C); S := Concat(S, S2); I := Length(S);
  if S = S2 then I := 0;
  if S < S2 then I := 1;

  Assign(F, 'X.DAT');
  {$I-} Reset(F, 1); {$I+}
  I := IOResult;
  Rewrite(F, 1); BlockWrite(F, Buf, 10, W); Seek(F, 0); BlockRead(F, Buf, 10, W);
  BlockRead(F, Buf, 10); BlockWrite(F, Buf, 10); Truncate(F);
  L := FileSize(F); L := FilePos(F);
  if Eof(F) then I := 0;
  Close(F); Rename(F, 'Y.DAT'); Erase(F);
  Assign(FB, 'Y.DAT'); Rewrite(FB); Write(FB, B); Reset(FB); Read(FB, B);
  Seek(FB, 0); L := FileSize(FB); Close(FB);
  Assign(T, 'Z.TXT'); Rewrite(T); Writeln(T, 'x', I, L, C, R:6:2, True); Close(T);
  Append(T); Write(T, S); Flush(T); Close(T);
  Reset(T); Readln(T, S); Read(T, C); Read(T, I); Read(T, L); Read(T, R);
  if Eoln(T) then I := 2;
  if Eof(T) then I := 3;
  if SeekEof(T) then I := 4;
  if SeekEoln(T) then I := 5;
  SetTextBuf(T, Buf); Close(T);
  Write('a'); Writeln(S, I:3, L, C); Readln(S);

  New(P); P^.A := 1; Dispose(P);
  GetMem(Q, 100); FreeMem(Q, 100); Mark(Q); Release(Q);
  L := MemAvail + MaxAvail;
  Big1 := Big2; { compiler block-copy helper }
  Move(Buf[0], Buf[1], 10); FillChar(Buf, SizeOf(Buf), 0);

  Randomize; I := Random(10); R := Random;
  L := L * L2; L := L div L2; L := L mod L2; L := L shl 2; L := L shr 1;
  I := I * Code; I := I div Code; I := I mod Code;
  R := R * 2.5 + I - L / 3; I := Trunc(R); I := Round(R);
  R := Sqrt(R) + Sin(R) + Cos(R) + ArcTan(R) + Exp(R) + Ln(R) + Abs(R) + Int(R) + Frac(R) + Sqr(R);
  if R > 1.0 then I := 6;

  St := ['a'..'z'];
  if C in St then St := St + ['A'];
  St := St - ['b']; St := St * ['a', C];
  if St = [] then I := 7;
  if St <= ['a'] then I := 8;

  S := ParamStr(0); I := ParamCount; GetDir(0, S);
  {$I-} ChDir('\'); MkDir('Q'); RmDir('Q'); {$I+}

  O := New(PObj, Init); O^.Show; Dispose(O, Done);

  GetTime(H, M, Sec, Hs); GetDate(H, M, Sec, Hs); SetTime(H, M, Sec, Hs);
  FindFirst('*.*', AnyFile, Sr); FindNext(Sr);
  Intr($10, Regs); MsDos(Regs); S := GetEnv('PATH'); W := DosVersion;
  SwapVectors; Exec('X.EXE', ''); SwapVectors; I := DosExitCode;
  GetIntVec(0, Q); SetIntVec(0, Q); PackTime(Dt, L); UnpackTime(L, Dt);
  GetFAttr(F, W); SetFAttr(F, W); GetFTime(F, L); SetFTime(F, L);
  L := DiskFree(0) + DiskSize(0); S := FSearch('X', 'Y'); S := FExpand('X');
  I := EnvCount; S := EnvStr(1); GetCBreak(Boolean(B)); SetVerify(False);

  OvProc(S);

  {$R+}
  Buf[I] := 0;
  SS := S;
  {$R-}
  case I of
    1: I := 2;
    2..5: I := 3;
  end;
  if I = 9 then RunError(5);
  if I = 10 then Exit;
  Halt;
end.
