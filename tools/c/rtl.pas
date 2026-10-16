{ rtl.pas: the interfaces of the Turbo Pascal runtime units the game uses (System, Crt, Dos, Overlay), in the
  dialect pasparse.py reads. The translator takes the names, types and signatures from here; the code is
  c/rtl/*.c (C names: rtl_<Name>). A variable with `absolute $1C7C:$xxxx` lives in DGROUP at that offset
  (re/dseg.toml). Routines the translator treats specially (Inc, Length, Str, Write ...) are not declared. }
unit System;
interface
type
  Registers = record
    case Integer of
      0: (AX, BX, CX, DX, BP, SI, DI, DS, ES, Flags: Word);
      1: (AL, AH, BL, BH, CL, CH, DL, DH: Byte);
  end;
var
  OvrCodeList: Word absolute $1C7C:$43EC;
  OvrHeapSize: Word absolute $1C7C:$43EE;
  OvrDebugPtr: Pointer absolute $1C7C:$43F0;
  OvrHeapOrg: Word absolute $1C7C:$43F4;
  OvrHeapPtr: Word absolute $1C7C:$43F6;
  OvrHeapEnd: Word absolute $1C7C:$43F8;
  OvrLoadList: Word absolute $1C7C:$43FA;
  OvrDosHandle: Word absolute $1C7C:$43FC;
  OvrEmsHandle: Word absolute $1C7C:$43FE;
  HeapOrg: Pointer absolute $1C7C:$4400;
  HeapPtr: Pointer absolute $1C7C:$4404;
  HeapEnd: Pointer absolute $1C7C:$4408;
  FreeList: Pointer absolute $1C7C:$440C;
  FreeZero: Pointer absolute $1C7C:$4410;
  HeapError: Pointer absolute $1C7C:$4414;
  ExitProc: Pointer absolute $1C7C:$4418;
  ExitCode: Integer absolute $1C7C:$441C;
  ErrorAddr: Pointer absolute $1C7C:$441E;
  PrefixSeg: Word absolute $1C7C:$4422;
  StackLimit: Word absolute $1C7C:$4424;
  InOutRes: Word absolute $1C7C:$4426;
  RandSeed: Longint absolute $1C7C:$4428;
  FileMode: Byte absolute $1C7C:$442C;
  Test8087: Byte absolute $1C7C:$442D;
  Input: Text absolute $1C7C:$8508;
  Output: Text absolute $1C7C:$8608;
  OvrResult: Integer absolute $1C7C:$43DC;
  OvrEmsPages: Word absolute $1C7C:$43DE;
  OvrTrapCount: Word absolute $1C7C:$43E0;
  OvrLoadCount: Word absolute $1C7C:$43E2;
  OvrFileMode: Byte absolute $1C7C:$43E4;
  CheckBreak: Boolean absolute $1C7C:$84F0;
  CheckEof: Boolean absolute $1C7C:$84F1;
  DirectVideo: Boolean absolute $1C7C:$84F2;
  CheckSnow: Boolean absolute $1C7C:$84F3;
  LastMode: Word absolute $1C7C:$84F4;
  TextAttr: Byte absolute $1C7C:$84F6;
  WindMin: Word absolute $1C7C:$84F8;
  WindMax: Word absolute $1C7C:$84FA;
function Random(Range: Word): Word;
procedure Randomize;
function MemAvail: Longint;
function MaxAvail: Longint;
function IOResult: Word;
function UpCase(Ch: Char): Char;
function ParamCount: Word;
procedure Move(var Source, Dest; Count: Word);
procedure FillChar(var Dest; Count: Word; Value: Byte);
procedure Halt(Code: Word);
procedure Intr(IntNo: Byte; var Regs: Registers);
procedure MsDos(var Regs: Registers);
procedure GetTime(var Hour, Minute, Second, Sec100: Word);
procedure GetDate(var Year, Month, Day, DayOfWeek: Word);
function KeyPressed: Boolean;
function ReadKey: Char;
procedure Delay(Ms: Word);
procedure Sound(Hz: Word);
procedure NoSound;
procedure ClrScr;
procedure GotoXY(X, Y: Byte);
procedure MkDir(Dir: string);
procedure RmDir(Dir: string);
procedure ChDir(Dir: string);
procedure OvrInit(Name: string);
procedure OvrInitEMS;
procedure OvrSetBuf(Size: Longint);
function OvrGetBuf: Longint;
procedure OvrClearBuf;
procedure OvrSetRetry(Size: Longint);
function OvrGetRetry: Longint;
implementation
end.
