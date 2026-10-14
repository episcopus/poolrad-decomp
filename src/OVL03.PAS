unit OVL03;
{ Encounter: the command loop of the ECL script interpreter (whitepaper 5.1). ovl03_fn_2F2D
  dispatches each command by its opcode (SkippedOpcode) to a handler in this unit; the handlers
  decode their operands through OVL07 and run them. The other routines are still stubs. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS, RES09, OVL07;
procedure EndCommand;
procedure GotoCommand;
procedure GosubCommand;
procedure CompareCommand;
procedure ArithmeticCommand;
procedure ovl03_fn_0234;
procedure ovl03_fn_0245;
procedure ovl03_fn_0275;
procedure ovl03_fn_0292;
procedure ovl03_fn_02A5;
procedure ovl03_fn_02D5;
procedure ovl03_fn_02DA;
procedure ovl03_fn_02DF;
procedure ovl03_fn_02E0;
procedure ovl03_fn_02E4;
procedure ovl03_fn_02E9;
procedure ovl03_fn_02EE;
procedure ovl03_fn_02F3;
procedure ovl03_fn_02F8;
procedure ovl03_fn_02FD;
procedure ovl03_fn_0302;
procedure ovl03_fn_0307;
procedure ovl03_fn_030C;
procedure ovl03_fn_0311;
procedure ovl03_fn_0316;
procedure ovl03_fn_031B;
procedure ovl03_fn_0320;
procedure ovl03_fn_0325;
procedure ovl03_fn_032A;
procedure ovl03_fn_032F;
procedure ovl03_fn_0334;
procedure ovl03_fn_0339;
procedure ovl03_fn_033E;
procedure ovl03_fn_0343;
procedure ovl03_fn_0348;
procedure ovl03_fn_0375;
procedure ovl03_fn_03B4;
procedure ovl03_fn_0450;
procedure ovl03_fn_0745;
procedure ovl03_fn_074A;
procedure ovl03_fn_0775;
procedure ovl03_fn_07A5;
procedure ovl03_fn_07AA;
procedure ovl03_fn_0803;
procedure ovl03_fn_0817;
procedure ovl03_fn_0845;
procedure ovl03_fn_084A;
procedure ovl03_fn_0856;
procedure ovl03_fn_08E5;
procedure ovl03_fn_0951;
procedure ovl03_fn_0994;
procedure ovl03_fn_0A09;
procedure ovl03_fn_0A9F;
procedure ovl03_fn_0AED;
procedure ovl03_fn_0B39;
procedure ovl03_fn_0B43;
procedure ovl03_fn_0B48;
procedure ovl03_fn_0B52;
procedure ovl03_fn_0BD1;
procedure ovl03_fn_0C74;
procedure ovl03_fn_0D7B;
procedure ovl03_fn_0DEF;
procedure ovl03_fn_0E5E;
procedure ovl03_fn_0EBC;
procedure ovl03_fn_0F08;
procedure ovl03_fn_0FE2;
procedure ovl03_fn_10D1;
procedure ovl03_fn_125D;
procedure ovl03_fn_12C6;
procedure ovl03_fn_1307;
procedure ovl03_fn_13D7;
procedure ovl03_fn_1435;
procedure ovl03_fn_1629;
procedure ovl03_fn_16C9;
procedure ovl03_fn_1758;
procedure ovl03_fn_179B;
procedure ovl03_fn_18F8;
procedure ovl03_fn_19B0;
procedure ovl03_fn_1B42;
procedure ovl03_fn_1C13;
procedure ovl03_fn_1DB1;
procedure ovl03_fn_1EF8;
procedure ovl03_fn_238D;
procedure ovl03_fn_25CB;
procedure ovl03_fn_266A;
procedure ovl03_fn_271F;
procedure ovl03_fn_2775;
procedure ovl03_fn_2AA2;
procedure ovl03_fn_2AC1;
procedure ovl03_fn_2AEB;
procedure ovl03_fn_2B14;
procedure ovl03_fn_2B33;
procedure ovl03_fn_2B7E;
procedure ovl03_fn_2C03;
procedure ovl03_fn_2CCF;
procedure ovl03_fn_2D39;
procedure ovl03_fn_2DBA;
procedure ovl03_fn_2DCB;
procedure ovl03_fn_2DD3;
procedure ovl03_fn_2E10;
procedure ovl03_fn_2E7D;
procedure ovl03_fn_2F2D;
procedure ovl03_fn_3171;
procedure ovl03_fn_31B4;
procedure ovl03_e1;
procedure ovl03_fn_3379;
procedure ovl03_fn_34AB;
implementation

const
  { The operand types from this one up are strings: $80 a packed string, $81 the address of a
    stored one (DecodeOperands in OVL07). }
  FirstStringOperandType = $80;
  { The opcodes of the arithmetic commands (ovl03:01A3). }
  OpAdd = 4;
  OpSub = 5;
  OpDiv = 6;
  OpMul = 7;

{ ovl03:0001. The ECL command 0, the only command that takes no operands (the dispatcher at
  ovl03:2F2D calls it for SkippedOpcode 0). It clears the text windows when ds84E2 is set (the
  second one only when the game variable VarForceWallView is set, since the code reads that same
  word), selects the character at ds4436 when ds4430 is set, clears the two-byte scratch ds84C8,
  moves EclPC past the command, empties the return stack of ScriptGosub, and puts the text
  cursor at column 1, row 17 (GlyphCol, GlyphRow). }
procedure EndCommand;
begin
  if ds84E2 <> 0 then
  begin
    DrawWindow(1, 1, $F, $F, 0, $F, '');
    if GameVars^[VarForceWallView] <> 0 then
      DrawWindow(3, 3, $D, $D, 0, $F, '');
  end;
  if ds4430 <> 0 then
  begin
    SelectedCharacter := ds4436;
    ds4430 := 0;
  end;
  FillChar(ds84C8, 2, 0);
  ds84E0 := 0;
  ds84E2 := 0;
  ds442E := 1;
  Inc(EclPC);
  while ReturnStack <> nil do
  begin
    ReturnPrev := ReturnStack^.Next;
    FreeMem(ReturnStack, 6);
    ReturnStack := ReturnPrev;
  end;
  GlyphRow := $11;
  GlyphCol := 1;
  ds84DE := 0;
end;
{ ovl03:00F4. ECL command 1 (dispatcher ovl03:2F2D, SkippedOpcode 1): an unconditional jump. Its
  one operand is a script address, and EclPC moves to it (the same jump ScriptGosub makes after
  it pushes the return address). }
procedure GotoCommand;
begin
  DecodeOperands(1);
  EclPC := MakeWord(OperandLow[1], OperandHigh[1]);
end;
{ ovl03:0111. ECL command 2 (dispatcher ovl03:2F2D, SkippedOpcode 2): a subroutine call. Its one
  operand is the script address of the subroutine; ScriptGosub pushes the return address and
  jumps there. }
procedure GosubCommand;
begin
  DecodeOperands(1);
  ScriptGosub(1);
end;
{ ovl03:0126. ECL command 3 (dispatcher ovl03:2F2D, SkippedOpcode 3): compares its two operands
  and sets CompareFlags for the conditional commands. When either operand is a string (type bit 7
  set) both strings are taken from EclStrings[1] and [2], whatever the types, and compared with
  CompareStrings; otherwise the two word values are compared with CompareWords. }
procedure CompareCommand;
var
  LeftWord: Word;
  RightWord: Word;
  Left: string;
  Right: string;
begin
  DecodeOperands(2);
  if (OperandType[1] >= FirstStringOperandType) or (OperandType[2] >= FirstStringOperandType) then
  begin
    Left := EclStrings[1];
    Right := EclStrings[2];
    CompareStrings(Left, Right);
  end
  else
  begin
    LeftWord := OperandValue(1);
    RightWord := OperandValue(2);
    CompareWords(LeftWord, RightWord);
  end;
end;
{ ovl03:01A3. ECL commands 4 to 7 (dispatcher ovl03:2F2D, SkippedOpcode OpAdd, OpSub, OpDiv or
  OpMul): the values of the first two operands are combined and the answer is written with
  WriteVmWord to the script address the third operand names. Division and multiplication keep the
  low word of the answer. QUIRK ovl03:01FC: subtraction takes the second value minus the first,
  while division takes the first over the second. }
procedure ArithmeticCommand;
var
  Target: Word;
  Values: array[1..2] of Word;
  I: ShortInt;
  Answer: Word;
  Unused: Byte;                 { QUIRK ovl03:01A3: a byte of the frame nothing uses }
begin
  DecodeOperands(3);
  for I := 1 to 2 do
    Values[I] := OperandValue(I);
  Target := MakeWord(OperandLow[3], OperandHigh[3]);
  case SkippedOpcode of
    OpAdd: Answer := Values[1] + Values[2];
    OpSub: Answer := Values[2] - Values[1];
    OpDiv: Answer := Values[1] div Values[2];
    OpMul: Answer := Values[1] * Values[2];
  end;
  WriteVmWord(Target, Answer);
end;
{ ovl03:0234: frame not read }
{@stub} procedure ovl03_fn_0234; begin end;
{ ovl03:0245: frame not read }
{@stub} procedure ovl03_fn_0245; begin end;
{ ovl03:0275: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_0275; begin end;
{ ovl03:0292: frame not read }
{@stub} procedure ovl03_fn_0292; begin end;
{ ovl03:02A5: frame not read }
{@stub} procedure ovl03_fn_02A5; begin end;
{ ovl03:02D5: frame not read }
{@stub} procedure ovl03_fn_02D5; begin end;
{ ovl03:02DA: frame not read }
{@stub} procedure ovl03_fn_02DA; begin end;
{ ovl03:02DF: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_02DF; begin end;
{ ovl03:02E0: frame not read }
{@stub} procedure ovl03_fn_02E0; begin end;
{ ovl03:02E4: frame not read }
{@stub} procedure ovl03_fn_02E4; begin end;
{ ovl03:02E9: frame not read }
{@stub} procedure ovl03_fn_02E9; begin end;
{ ovl03:02EE: frame not read }
{@stub} procedure ovl03_fn_02EE; begin end;
{ ovl03:02F3: frame not read }
{@stub} procedure ovl03_fn_02F3; begin end;
{ ovl03:02F8: frame not read }
{@stub} procedure ovl03_fn_02F8; begin end;
{ ovl03:02FD: frame not read }
{@stub} procedure ovl03_fn_02FD; begin end;
{ ovl03:0302: frame not read }
{@stub} procedure ovl03_fn_0302; begin end;
{ ovl03:0307: frame not read }
{@stub} procedure ovl03_fn_0307; begin end;
{ ovl03:030C: frame not read }
{@stub} procedure ovl03_fn_030C; begin end;
{ ovl03:0311: frame not read }
{@stub} procedure ovl03_fn_0311; begin end;
{ ovl03:0316: frame not read }
{@stub} procedure ovl03_fn_0316; begin end;
{ ovl03:031B: frame not read }
{@stub} procedure ovl03_fn_031B; begin end;
{ ovl03:0320: frame not read }
{@stub} procedure ovl03_fn_0320; begin end;
{ ovl03:0325: frame not read }
{@stub} procedure ovl03_fn_0325; begin end;
{ ovl03:032A: frame not read }
{@stub} procedure ovl03_fn_032A; begin end;
{ ovl03:032F: frame not read }
{@stub} procedure ovl03_fn_032F; begin end;
{ ovl03:0334: frame not read }
{@stub} procedure ovl03_fn_0334; begin end;
{ ovl03:0339: frame not read }
{@stub} procedure ovl03_fn_0339; begin end;
{ ovl03:033E: frame not read }
{@stub} procedure ovl03_fn_033E; begin end;
{ ovl03:0343: frame not read }
{@stub} procedure ovl03_fn_0343; begin end;
{ ovl03:0348: frame not read }
{@stub} procedure ovl03_fn_0348; begin end;
{ ovl03:0375: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_0375; begin end;
{ ovl03:03B4: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl03_fn_03B4; begin end;
{ ovl03:0450: frame not read }
{@stub} procedure ovl03_fn_0450; begin end;
{ ovl03:0745: frame not read }
{@stub} procedure ovl03_fn_0745; begin end;
{ ovl03:074A: frame not read }
{@stub} procedure ovl03_fn_074A; begin end;
{ ovl03:0775: frame not read }
{@stub} procedure ovl03_fn_0775; begin end;
{ ovl03:07A5: frame not read }
{@stub} procedure ovl03_fn_07A5; begin end;
{ ovl03:07AA: frame not read }
{@stub} procedure ovl03_fn_07AA; begin end;
{ ovl03:0803: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_0803; begin end;
{ ovl03:0817: frame not read }
{@stub} procedure ovl03_fn_0817; begin end;
{ ovl03:0845: frame not read }
{@stub} procedure ovl03_fn_0845; begin end;
{ ovl03:084A: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_084A; begin end;
{ ovl03:0856: frame not read }
{@stub} procedure ovl03_fn_0856; begin end;
{ ovl03:08E5: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_08E5; begin end;
{ ovl03:0951: retf 0: 0 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl03_fn_0951; begin end;
{ ovl03:0994: retf 0: 0 bytes of parameters; 516 bytes of locals }
{@stub} procedure ovl03_fn_0994; begin end;
{ ovl03:0A09: retf 0: 0 bytes of parameters; 256 bytes of locals }
{@stub} procedure ovl03_fn_0A09; begin end;
{ ovl03:0A9F: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_0A9F; begin end;
{ ovl03:0AED: frame not read }
{@stub} procedure ovl03_fn_0AED; begin end;
{ ovl03:0B39: frame not read }
{@stub} procedure ovl03_fn_0B39; begin end;
{ ovl03:0B43: frame not read }
{@stub} procedure ovl03_fn_0B43; begin end;
{ ovl03:0B48: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_0B48; begin end;
{ ovl03:0B52: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_0B52; begin end;
{ ovl03:0BD1: retf 0: 0 bytes of parameters; 260 bytes of locals }
{@stub} procedure ovl03_fn_0BD1; begin end;
{ ovl03:0C74: frame not read }
{@stub} procedure ovl03_fn_0C74; begin end;
{ ovl03:0D7B: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_0D7B; begin end;
{ ovl03:0DEF: retf 0: 0 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl03_fn_0DEF; begin end;
{ ovl03:0E5E: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl03_fn_0E5E; begin end;
{ ovl03:0EBC: retf 0: 0 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl03_fn_0EBC; begin end;
{ ovl03:0F08: frame not read }
{@stub} procedure ovl03_fn_0F08; begin end;
{ ovl03:0FE2: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_0FE2; begin end;
{ ovl03:10D1: retf 0: 0 bytes of parameters; 320 bytes of locals }
{@stub} procedure ovl03_fn_10D1; begin end;
{ ovl03:125D: retf 0: 0 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl03_fn_125D; begin end;
{ ovl03:12C6: frame not read }
{@stub} procedure ovl03_fn_12C6; begin end;
{ ovl03:1307: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_1307; begin end;
{ ovl03:13D7: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_13D7; begin end;
{ ovl03:1435: retf 0: 0 bytes of parameters; 26 bytes of locals }
{@stub} procedure ovl03_fn_1435; begin end;
{ ovl03:1629: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl03_fn_1629; begin end;
{ ovl03:16C9: frame not read }
{@stub} procedure ovl03_fn_16C9; begin end;
{ ovl03:1758: frame not read }
{@stub} procedure ovl03_fn_1758; begin end;
{ ovl03:179B: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl03_fn_179B; begin end;
{ ovl03:18F8: retf 0: 0 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl03_fn_18F8; begin end;
{ ovl03:19B0: frame not read }
{@stub} procedure ovl03_fn_19B0; begin end;
{ ovl03:1B42: frame not read }
{@stub} procedure ovl03_fn_1B42; begin end;
{ ovl03:1C13: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_1C13; begin end;
{ ovl03:1DB1: retf 0: 0 bytes of parameters; 18 bytes of locals }
{@stub} procedure ovl03_fn_1DB1; begin end;
{ ovl03:1EF8: frame not read }
{@stub} procedure ovl03_fn_1EF8; begin end;
{ ovl03:238D: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_238D; begin end;
{ ovl03:25CB: retf 0: 0 bytes of parameters; 302 bytes of locals }
{@stub} procedure ovl03_fn_25CB; begin end;
{ ovl03:266A: retf 0: 0 bytes of parameters; 12 bytes of locals }
{@stub} procedure ovl03_fn_266A; begin end;
{ ovl03:271F: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_271F; begin end;
{ ovl03:2775: retf 0: 0 bytes of parameters; 62 bytes of locals }
{@stub} procedure ovl03_fn_2775; begin end;
{ ovl03:2AA2: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_2AA2; begin end;
{ ovl03:2AC1: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl03_fn_2AC1; begin end;
{ ovl03:2AEB: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_2AEB; begin end;
{ ovl03:2B14: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_2B14; begin end;
{ ovl03:2B33: retf 0: 0 bytes of parameters; 256 bytes of locals }
{@stub} procedure ovl03_fn_2B33; begin end;
{ ovl03:2B7E: retf 0: 0 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl03_fn_2B7E; begin end;
{ ovl03:2C03: retf 0: 0 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl03_fn_2C03; begin end;
{ ovl03:2CCF: frame not read }
{@stub} procedure ovl03_fn_2CCF; begin end;
{ ovl03:2D39: frame not read }
{@stub} procedure ovl03_fn_2D39; begin end;
{ ovl03:2DBA: frame not read }
{@stub} procedure ovl03_fn_2DBA; begin end;
{ ovl03:2DCB: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_2DCB; begin end;
{ ovl03:2DD3: retf 0: 0 bytes of parameters; 2 bytes of locals }
{@stub} procedure ovl03_fn_2DD3; begin end;
{ ovl03:2E10: retf 0: 0 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl03_fn_2E10; begin end;
{ ovl03:2E7D: retf 0: 0 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl03_fn_2E7D; begin end;
{ ovl03:2F2D: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_2F2D; begin end;
{ ovl03:3171: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_3171; begin end;
{ ovl03:31B4: retf 0: 0 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl03_fn_31B4; begin end;
{ ovl03:32F8: frame not read }
{@stub} procedure ovl03_e1; begin end;
{ ovl03:3379: frame not read }
{@stub} procedure ovl03_fn_3379; begin end;
{ ovl03:34AB: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl03_fn_34AB; begin end;

begin
end.
