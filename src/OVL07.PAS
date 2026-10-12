unit OVL07;
{ EclVm: the ECL script machine's memory, operands and helpers (whitepaper 5.1). The interpreter in
  ovl03 decodes each command's operands through this unit and reads and writes script addresses
  through ReadVmWord and WriteVmWord: MemRegion maps an address to the game variables, two more
  word blocks, the bytes of the loaded script (EclCode) or the engine variables, and
  GetCharacterVar and SetCharacterVar overlay the selected character's fields on the second block.
  It also loads the script (LoadEcl), resets the machine for a new area, shows the HEAD and BODY
  pictures (ShowHeadBody) and asks the menus and questions the scripts pose. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS, RES05, RES06;
procedure DecodeOperands(Count: Byte);
function OperandValue(N: ShortInt): Word;
procedure InitScript;
procedure LoadEcl(BlockId: Byte);
procedure ovl07_e5;
procedure ovl07_e6;
procedure ShowHeadBody(HeadBank, BodyBank: Byte);
procedure ovl07_e8;
function MakeWord(Lo, Hi: Byte): Word;
function SixBitChar(Code: Byte): Char;
function MemRegion(Addr: Word): Byte;
function PartyIndexOf(Who: PCharacter): Byte;
function GetCharacterVar(Addr: Word; var Found: Boolean): Word;
procedure SetCharacterVar(Addr, Value: Word);
procedure WriteVmWord(Addr, Value: Word);
function ReadVmWord(Addr: Word): Word;
procedure WriteVmString(Addr: Word; Text: string);
procedure DecodeString(Len, Index: Byte);
procedure ReadVmString(Index: Byte; Addr: Word);
procedure ParseHotkeys(var Text: string; var Keys: String40);
function AskMenu(Title: String40; Text: string; TitleColor, WordColor, HotColor, AcceptEnter,
  Animate: Byte): Byte;
procedure AskListMenu(Title: String40; Text: string; HeadingColor, LineColor, HighlightColor: Byte;
  Left, Top, Right, Bottom: ShortInt; List: PMenuLine; WithExit: Byte; var Redraw: Byte;
  var Choice: Integer; var Selected: PMenuLine);
procedure ovl07_e15;
procedure ovl07_e16;
procedure ovl07_e17;
procedure ovl07_e19;
procedure ovl07_e18;
procedure ovl07_e20;
procedure ovl07_e21;
procedure ovl07_e22;
procedure ovl07_e23;
procedure ovl07_fn_20A9;
procedure ovl07_e24;
implementation
uses OVL19, OVL25, OVL28, OVL29, RES12;

const
  { The blocks of the script's address space (MemRegion). }
  RegionGameVars = 0;
  RegionWords6B00 = 1;
  RegionWords9700 = 2;
  RegionCode = 3;
  RegionSpecial = 4;
  HotkeyMark = '~';              { marks the hotkey letter in a menu text (ParseHotkeys) }
  KeyReturn = #13;
  VarNoCasting = 229;            { the game variable (+$1CA) that forbids casting here (as in ovl08, ovl15) }

{ ovl07:0000. DecodeOperands: reads the Count operands of the current command from the script at
  EclPC + 1 into OperandType, OperandLow and OperandHigh, and leaves EclPC on the next command.
  Each operand is a type byte and a low byte, plus a high byte for types 1, 2, 3 and $81; a
  packed string (type $80, the low byte its length) is unpacked into the next EclStrings entry
  (DecodeString), and a string address (type $81) copied into it (ReadVmString). }
procedure DecodeOperands(Count: Byte);
var
  I: Byte;
  StrIndex: Byte;
  Value: Word;
  Len: Word;
begin
  StrIndex := 0;
  for I := 1 to Count do
  begin
    OperandType[I] := EclCode^[EclPC + 1];
    OperandLow[I] := EclCode^[EclPC + 2];
    EclPC := EclPC + 2;
    case OperandType[I] of
      1, 2, 3:
        begin
          Inc(EclPC);
          OperandHigh[I] := EclCode^[EclPC];
        end;
      $80:
        begin
          Inc(StrIndex);
          Len := OperandLow[I];
          if Len > 0 then
            DecodeString(Len, StrIndex)
          else
            EclStrings[StrIndex] := '';
        end;
      $81:
        begin
          Inc(StrIndex);
          Inc(EclPC);
          OperandHigh[I] := EclCode^[EclPC];
          Value := MakeWord(OperandLow[I], OperandHigh[I]);
          ReadVmString(StrIndex, Value);
        end;
    end;
  end;
  Inc(EclPC);
end;
{ ovl07:0136. OperandValue: the value of decoded operand N: the byte itself (type 0), the word at
  the address it names (types 1, 3 and $80, ReadVmWord) or the word itself (types 2 and $81).
  QUIRK ovl07:01AD: other types leave the result unassigned. }
function OperandValue(N: ShortInt): Word;
var
  Unused: array[0..5] of Byte;  { QUIRK ovl07:0139: six bytes of the frame nothing uses }
  Lo: Byte;
  Hi: Byte;
begin
  Lo := OperandLow[N];
  Hi := OperandHigh[N];
  case OperandType[N] of
    0: OperandValue := Lo;
    1, 3, $80: OperandValue := ReadVmWord(Hi * 256 + Lo);
    2, $81: OperandValue := MakeWord(Lo, Hi);
  end;
end;
{ ovl07:01B6. InitScript: resets the script machine for a newly loaded script: clears its flags,
  sets the special view codes ($41 and 9), points EclPC at the start of the script ($9900) and
  reads the five entry addresses of its header into ds49E3..ds49EB; clears game variable
  VarNoCasting and some words of ds49D6, forces the wall view, and (unless ds49F8 asks to keep
  them, which it then clears) clears game variables $4A00..$4A1F and words $6E79..$6E82 of
  ds49D6. }
procedure InitScript;
var
  Unused: Byte;                 { QUIRK ovl07:01B9: a byte of the frame nothing uses }
  I: Word;
begin
  ds84E0 := 0;
  ds84E2 := 0;
  ds84D2 := 0;
  ds84D3 := 0;
  ds6F68 := $41;
  ds6F69 := 9;
  ds84E5 := 1;
  FillChar(ds84C8, 2, 0);
  ds6F83 := 8;
  EclPC := $9900;
  ds70C6 := 0;
  ds6F70 := nil;
  ds6F74 := nil;
  FillChar(ds6F78, 6, 0);
  ds49D6^[$2E1] := $FF;
  ds49D6^[$2D2] := 0;
  ds49D6^[$2D3] := 0;
  GameVars^[VarNoCasting] := 0;
  DecodeOperands(1);
  ds49E3 := MakeWord(OperandLow[1], OperandHigh[1]);
  DecodeOperands(1);
  ds49E5 := MakeWord(OperandLow[1], OperandHigh[1]);
  DecodeOperands(1);
  ds49E7 := MakeWord(OperandLow[1], OperandHigh[1]);
  DecodeOperands(1);
  ds49E9 := MakeWord(OperandLow[1], OperandHigh[1]);
  DecodeOperands(1);
  ds49EB := MakeWord(OperandLow[1], OperandHigh[1]);
  GameVars^[VarForceWallView] := 1;
  if ds49F8 = 0 then
  begin
    for I := 1 to $20 do
      VarsAt4900^[I + $49FF] := 0;
    for I := 0 to 9 do
      VarsAt6B00^[I + $6E79] := 0;
  end
  else
    ds49F8 := 0;
end;
{ ovl07:0341. LoadEcl: loads block BlockId of ECL<TileSet>.DAX into EclCode (whitepaper 4.2.2):
  clears the buffer, shows 'Loading...Please Wait' on the prompt line and loads the block until
  it holds at least the leading word (LoadDaxBlock), copies the bytes after that word, frees the
  block and clears the prompt line. }
procedure LoadEcl(BlockId: Byte);
var
  Unused: array[0..3] of Byte;  { QUIRK ovl07:0344: four bytes of the frame nothing uses }
  Num: string[1];
  Size: Word;
  Block: Pointer;
begin
  FillChar(EclCode^, $1E00, 0);
  ds557C := 0;
  repeat
    ClearPromptLine;
    DrawTextAt(0, $18, $F, 'Loading...Please Wait');
    Str(TileSet, Num);
    LoadDaxBlock('ECL' + Num, '.dax', BlockId, Size, Block);
  until Size >= 2;
  Move(PByteArray(Block)^[2], EclCode^, Size - 2);
  FreeMem(Block, Size);
  ClearPromptLine;
end;
{ ovl07:0411: retf 14: 14 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl07_e5; begin end;
{ ovl07:0482: retf 6: 6 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl07_e6; begin end;
{ ovl07:0511. ShowHeadBody: loads the HEAD and BODY picture banks HeadBank and BodyBank
  (LoadHeadBodySprites), remembers them in ds49FD and ds49FE, and shows them at column 3, row 3
  with the body (ShowHeadBodySprites). Clears ds84E1. Called by ovl03 and ovl07_e8. }
procedure ShowHeadBody(HeadBank, BodyBank: Byte);
begin
  ds84E1 := 0;
  ds49FD := HeadBank;
  ds49FE := BodyBank;
  LoadHeadBodySprites(HeadBank, BodyBank);
  ShowHeadBodySprites(3, 3, 1);
end;
{ ovl07:054E: retf 10: 10 bytes of parameters; 16 bytes of locals }
{@stub} procedure ovl07_e8; begin end;
{ ovl07:06AF. MakeWord: the word whose low byte is Lo and high byte Hi (an operand's two bytes,
  OperandLow and OperandHigh). }
function MakeWord(Lo, Hi: Byte): Word;
begin
  MakeWord := Hi * 256 + Lo;
end;
{ ovl07:06D3. SixBitChar: the character of a 6-bit code of a packed script string: codes $20..$3F
  are themselves (space, digits, punctuation), codes 1..$1F become $41..$5F (the letters). }
function SixBitChar(Code: Byte): Char;
begin
  if Code > $1F then
    SixBitChar := Chr(Code)
  else
    SixBitChar := Chr(Code + $40);
end;
{ ovl07:06FB. MemRegion: which block a script address names: RegionGameVars ($4900..$4CFF, the
  words of GameVars), RegionWords6B00 ($6B00..$6EFF, the words of ds49D6, overlaid by the selected
  character's fields), RegionWords9700 ($9700..$98FF, the words of ds49DA), RegionCode
  ($9900..$B6FF, the bytes of the loaded script) or RegionSpecial (anything else, the engine
  variables ReadVmWord and WriteVmWord handle one by one). }
function MemRegion(Addr: Word): Byte;
begin
  MemRegion := RegionSpecial;
  if (Addr >= $4900) and (Addr <= $4CFF) then
    MemRegion := RegionGameVars;
  if (Addr >= $6B00) and (Addr <= $6EFF) then
    MemRegion := RegionWords6B00;
  if (Addr >= $9700) and (Addr <= $98FF) then
    MemRegion := RegionWords9700;
  if (Addr >= $9900) and (Addr <= $B6FF) then
    MemRegion := RegionCode;
end;
{ ovl07:0756. PartyIndexOf: the 0-based position of Who in the party list (ds5D96); the length
  of the list when Who is not in it. }
function PartyIndexOf(Who: PCharacter): Byte;
var
  Index: Byte;
  Member: PCharacter;
  Found: Boolean;
begin
  Member := PCharacter(ds5D96);
  Found := False;
  Index := 0;
  while (Member <> nil) and not Found do
  begin
    if Member = Who then
      Found := True
    else
    begin
      Inc(Index);
      Member := Member^.Next;
    end;
  end;
  PartyIndexOf := Index;
end;
{ ovl07:07BC. GetCharacterVar: the value of script address Addr ($6B00..$6EFF) when it names a
  field of the selected character (SelectedCharacter) or another engine value; Found is False
  (and the result undefined) for the addresses it does not handle, which ReadVmWord then reads
  from ds49D6. The offsets are those of the script's character record, not of TCharacter.
  QUIRK ovl07:095A: address $6C0D sets Found but leaves the result unassigned. }
function GetCharacterVar(Addr: Word; var Found: Boolean): Word;
var
  Index: Byte;
begin
  Found := True;
  Addr := Addr - $6B00;
  case Addr of
    $18: GetCharacterVar := SelectedCharacter^.Constitution;
    $9B: GetCharacterVar := SelectedCharacter^.SavingThrows[1];
    $A0: GetCharacterVar := SelectedCharacter^.HighestLevel;
    $A5..$AC:
      begin
        Index := Addr - $A4;
        GetCharacterVar := SelectedCharacter^.ThiefSkills[Index];
      end;
    $B8: GetCharacterVar := SelectedCharacter^.B84;
    $BB: GetCharacterVar := SelectedCharacter^.Money[0];
    $BD: GetCharacterVar := SelectedCharacter^.Money[1];
    $BF: GetCharacterVar := SelectedCharacter^.Money[2];
    $C1: GetCharacterVar := SelectedCharacter^.Money[3];
    $C3: GetCharacterVar := SelectedCharacter^.Money[4];
    $D8: GetCharacterVar := SelectedCharacter^.ByteA0;
    $F7: GetCharacterVar := SelectedCharacter^.XpValue;
    $F9: GetCharacterVar := SelectedCharacter^.XpPerHp;
    $100:
      if SelectedCharacter^.Flag10D <> 0 then
        GetCharacterVar := 1
      else
        GetCharacterVar := $80;
    $10C:
      if (SelectedCharacter^.Side = 0) and (SelectedCharacter^.Quick <> 0) then
        GetCharacterVar := $80
      else if SelectedCharacter^.Side = 1 then
        GetCharacterVar := $81
      else
        GetCharacterVar := 0;
    $10D: ;
    $11B: GetCharacterVar := SelectedCharacter^.Pad11C;
    $2B1: GetCharacterVar := PartyIndexOf(SelectedCharacter);
    $2B4: GetCharacterVar := PartyIndexOf(SelectedCharacter);
    $2CF:
      case SelectedCharacter^.Charisma of
        3: GetCharacterVar := 0;
        4: GetCharacterVar := 5;
        5: GetCharacterVar := 10;
        6: GetCharacterVar := 15;
        7: GetCharacterVar := 20;
        8..12: GetCharacterVar := 25;
        13: GetCharacterVar := 30;
        14: GetCharacterVar := 35;
        15: GetCharacterVar := 40;
        16: GetCharacterVar := 50;
        17: GetCharacterVar := 55;
        18..25: GetCharacterVar := 60;
      end;
    $312: GetCharacterVar := TileSet;
    $33E: GetCharacterVar := ds49D6^[$33E];
  else
    Found := False;
  end;
end;
{ ovl07:0A74. SetCharacterVar: applies a script write of Value to address Addr ($6B00..$6EFF) to
  the selected character's fields and engine state (WriteVmWord has already stored it in ds49D6).
  QUIRK ovl07:0AA3: addresses $6B20..$6B70 write the byte at Spells[Addr - $6B1F], past the 21
  spell slots into the bytes that follow. }
procedure SetCharacterVar(Addr, Value: Word);
var
  Index: Byte;
begin
  Addr := Addr - $6B00;
  case Addr of
    0:
      if Value = 0 then
        ds84D3 := 1;
    $20..$70:
      begin
        Index := Addr - $1F;
        SelectedCharacter^.Spells[Index] := Value;
      end;
    $B8:
      begin
        if Value > $B2 then
          Dec(Value, $32);
        SelectedCharacter^.B84 := Value;
      end;
    $BB: SelectedCharacter^.Money[0] := Value;
    $BD: SelectedCharacter^.Money[1] := Value;
    $BF: SelectedCharacter^.Money[2] := Value;
    $C1: SelectedCharacter^.Money[3] := Value;
    $C3: SelectedCharacter^.Money[4] := Value;
    $F7: SelectedCharacter^.XpValue := Value;
    $F9: SelectedCharacter^.XpPerHp := Value;
    $100:
      begin
        if Value >= $80 then
        begin
          SelectedCharacter^.Flag10D := 0;
          if Value = $87 then
            SelectedCharacter^.Status := 7;
        end;
        if Value = 0 then
          ds84D2 := 1;
      end;
    $10C:
      case Value of
        0:
          begin
            SelectedCharacter^.Side := 0;
            SelectedCharacter^.Quick := 0;
          end;
        $80:
          begin
            SelectedCharacter^.Side := 0;
            SelectedCharacter^.Quick := 1;
          end;
        $81:
          begin
            SelectedCharacter^.Side := 1;
            SelectedCharacter^.Quick := 1;
          end;
      end;
    $312: SelectTileSet(Value);
    $322:
      if Value > $80 then
      begin
        Value := Value and $7F;
        LoadWallSet(Value, 1);
      end;
    $324:
      if Value > $80 then
      begin
        Value := Value and $7F;
        LoadWallSet(Value, 2);
      end;
    $326:
      if Value > $80 then
      begin
        Value := Value and $7F;
        LoadWallSet(Value, 3);
      end;
  end;
end;
{ ovl07:0C77. WriteVmWord: the script's store of Value at address Addr: a word of GameVars,
  ds49D6 (then also SetCharacterVar) or ds49DA, a byte of the loaded script, or one of the engine
  variables at the special addresses (the party's position and marker, the special view codes). }
procedure WriteVmWord(Addr, Value: Word);
var
  Region: Byte;
  Done: Byte;
begin
  Region := MemRegion(Addr);
  case Region of
    RegionGameVars:
      begin
        VarsAt4900^[Addr] := Value;
        if (Addr = $49FD) or (Addr = $49FE) then
          ds84E8 := 1;
      end;
    RegionWords6B00:
      begin
        VarsAt6B00^[Addr] := Value;
        SetCharacterVar(Addr, Value);
      end;
    RegionWords9700: VarsAt9700^[Addr] := Value;
    RegionCode: EclCode^[Addr] := Value;
    RegionSpecial:
      if Addr < $BF68 then
        case Addr of
          $FB: ;
          $FC: ;
          $B1: ;
          $3DE: ds84CC := Value;
          $B8: ds84CE := Value;
          $B9: ds84D0 := Value;
        end
      else
      begin
        Addr := Addr - $BF68;
        case Addr of
          $E3:
            begin
              ds84E6 := 1;
              ds6AAD := Value;
            end;
          $E4:
            begin
              ds6AAE := Value;
              ds84E6 := 1;
            end;
          $E5:
            begin
              repeat
                Done := 1;
                case Value of
                  0: ds6AAF := 0;
                  1: ds6AAF := 2;
                  2: ds6AAF := 4;
                  3: ds6AAF := 6;
                else
                  Done := 0;
                  Dec(Value, 4);
                end;
              until Done = 1;
              ds84E6 := 1;
            end;
          $F1:
            begin
              ds6F68 := Value;
              ds84E5 := 1;
            end;
          $F7:
            begin
              ds6F69 := Value;
              ds84E5 := 1;
            end;
          $10BA: ;
        end;
      end;
  end;
end;
{ ovl07:0E0C. ReadVmWord: the script's load of the word at address Addr: a word of GameVars,
  ds49D6 (unless GetCharacterVar answers it from the selected character) or ds49DA, a byte of the
  loaded script, or an engine variable at the special addresses. QUIRK ovl07:0EE7, 0F45: the
  addresses it does not know leave the result unassigned. }
function ReadVmWord(Addr: Word): Word;
var
  Region: Byte;
  Found: Boolean;
  Unused: Word;                 { QUIRK ovl07:0E0F: two bytes of the frame nothing uses }
begin
  Region := MemRegion(Addr);
  Found := False;
  case Region of
    RegionGameVars: ReadVmWord := VarsAt4900^[Addr];
    RegionWords6B00:
      begin
        ReadVmWord := GetCharacterVar(Addr, Found);
        if not Found then
          ReadVmWord := VarsAt6B00^[Addr];
      end;
    RegionWords9700: ReadVmWord := VarsAt9700^[Addr];
    RegionCode: ReadVmWord := EclCode^[Addr];
    RegionSpecial:
      if Addr < $C04B then
        case Addr of
          $B1: ReadVmWord := ds6F6E;
          $FB: ReadVmWord := ds6F6A;
          $FC: ReadVmWord := ds6F6C;
          $33D: ReadVmWord := ds6AAF;
          $35F: ;
        end
      else
      begin
        Addr := Addr - $C04B;
        case Addr of
          0: ReadVmWord := ds6AAD;
          1: ReadVmWord := ds6AAE;
          2: ReadVmWord := ds6AAF shr 1;
          3: ReadVmWord := ds6AB0;
          4: ReadVmWord := ds6AB1;
          $E: ;
        end;
      end;
  end;
end;
{ ovl07:0F53. WriteVmString: stores Text at script address Addr, one character per word of
  GameVars, ds49D6 or ds49DA or per byte of the script, followed by a 0; address $6B00 is the
  selected character's name instead (up to 15 characters). Nothing for the special addresses. }
procedure WriteVmString(Addr: Word; Text: string);
var
  Region: Byte;
  Len: Byte;
  I: Byte;
begin
  Region := MemRegion(Addr);
  Len := Length(Text);
  case Region of
    RegionGameVars:
      begin
        for I := 0 to Len - 1 do
          VarsAt4900^[I + Addr] := Ord(Text[I + 1]);
        VarsAt4900^[Len + Addr] := 0;
      end;
    RegionWords6B00:
      if Addr = $6B00 then
        SelectedCharacter^.Name := Text
      else
      begin
        for I := 0 to Len - 1 do
          VarsAt6B00^[I + Addr] := Ord(Text[I + 1]);
        VarsAt6B00^[Len + Addr] := 0;
      end;
    RegionWords9700:
      begin
        for I := 0 to Len - 1 do
          VarsAt9700^[I + Addr] := Ord(Text[I + 1]);
        VarsAt9700^[Len + Addr] := 0;
      end;
    RegionCode:
      begin
        for I := 0 to Len - 1 do
          EclCode^[I + Addr] := Ord(Text[I + 1]);
        EclCode^[Len + Addr] := 0;
      end;
  end;
end;
{ ovl07:1153. DecodeString: unpacks a packed string operand of Len bytes from the script at
  EclPC + 1 into EclStrings[Index], advancing EclPC: every three bytes hold four 6-bit codes,
  SixBitChar turns each nonzero code into a character, code 0 is skipped. }
procedure DecodeString(Len, Index: Byte);
var
  Count: Byte;
  Unused: Byte;                 { QUIRK ovl07:1156: a byte of the frame nothing uses }
  Cur: Byte;
  Prev: Byte;
  Code: Byte;
  Phase: Byte;
  Ch: Char;
begin
  EclStrings[Index] := '';
  Count := 0;
  Phase := 1;
  while Count < Len do
  begin
    if Phase < 4 then
    begin
      Inc(EclPC);
      Prev := Cur;
      Cur := EclCode^[EclPC];
      Inc(Count);
    end;
    case Phase of
      1: Code := Cur shr 2;
      2:
        begin
          Code := Prev shl 6 + Cur shr 2;
          Code := Code shr 2;
        end;
      3:
        begin
          Code := Prev shl 4 + Cur shr 4;
          Code := Code shr 2;
        end;
      4: Code := Cur and $3F;
    end;
    if Phase < 4 then
      Inc(Phase)
    else
      Phase := 1;
    if Code <> 0 then
    begin
      Ch := SixBitChar(Code);
      EclStrings[Index] := Concat(EclStrings[Index], Ch);
    end;
  end;
  if Phase = 4 then
  begin
    Code := Cur and $3F;
    if Code <> 0 then
    begin
      Ch := SixBitChar(Code);
      EclStrings[Index] := Concat(EclStrings[Index], Ch);
    end;
  end;
end;
{ ovl07:12FB. ReadVmString: copies the string stored at script address Addr (one character per
  word of GameVars, ds49D6 or ds49DA or per byte of the script, up to a 0) into
  EclStrings[Index]; address $6B00 is the selected character's name. }
procedure ReadVmString(Index: Byte; Addr: Word);
var
  Region: Byte;
  I: Byte;
begin
  Region := MemRegion(Addr);
  EclStrings[Index] := '';
  I := 0;
  case Region of
    RegionGameVars:
      while VarsAt4900^[I + Addr] <> 0 do
      begin
        EclStrings[Index] := Concat(EclStrings[Index], Chr(VarsAt4900^[I + Addr]));
        Inc(I);
      end;
    RegionWords6B00:
      if Addr = $6B00 then
        EclStrings[Index] := SelectedCharacter^.Name
      else
        while VarsAt6B00^[I + Addr] <> 0 do
        begin
          EclStrings[Index] := Concat(EclStrings[Index], Chr(VarsAt6B00^[I + Addr]));
          Inc(I);
        end;
    RegionWords9700:
      while VarsAt9700^[I + Addr] <> 0 do
      begin
        EclStrings[Index] := Concat(EclStrings[Index], Chr(VarsAt9700^[I + Addr]));
        Inc(I);
      end;
    RegionCode:
      while EclCode^[I + Addr] <> 0 do
      begin
        EclStrings[Index] := Concat(EclStrings[Index], Chr(EclCode^[I + Addr]));
        Inc(I);
      end;
  end;
end;
{ ovl07:156D. ParseHotkeys: prepares a menu text for the prompt: turns its letters and digits to
  lower case (+$20), and for every '~' removes it, upper-cases the character after it and appends
  that character to Keys, the menu's hotkeys in order. QUIRK ovl07:15BF: digits are moved by $20
  as well ('0'..'9' become 'P'..'Y'). }
procedure ParseHotkeys(var Text: string; var Keys: String40);
var
  I: Byte;
begin
  Keys := '';
  for I := 1 to Length(Text) do
  begin
    if Text[I] in ['0'..'9', 'A'..'Z'] then
      Text[I] := Chr(Ord(Text[I]) + $20);
    if Text[I] = HotkeyMark then
    begin
      Delete(Text, I, 1);
      Text[I] := UpCase(Text[I]);
      Keys := Keys + Text[I];
    end;
  end;
end;
{ ovl07:1684. AskMenu: shows Title and the menu Text on the prompt line (ReadPromptChoice, in the
  three colours, Animate passed on) and waits for one of its '~' hotkeys (ParseHotkeys); Return
  also answers when AcceptEnter is set. Returns the 0-based position of the hotkey in the menu
  (so '~Yes ~No' gives 0 or 1), 0 for Return, $FF for a letter or digit that is not a hotkey.
  An extended key goes to ovl19_e10 and the selected character is redrawn (res12_fn_0767)
  before asking again. Callers: ovl03, the Temple, the treasure menu and the shop. }
function AskMenu(Title: String40; Text: string; TitleColor, WordColor, HotColor, AcceptEnter,
  Animate: Byte): Byte;
var
  Keys: String40;
  I: Byte;
  Key: Char;
  ExtKey: Byte;
begin
  ParseHotkeys(Text, Keys);
  repeat
    Key := ReadPromptChoice(Title, Text, TitleColor, WordColor, HotColor, 1, Animate, ExtKey);
    if ExtKey <> 0 then
    begin
      ovl19_e10(Key);
      res12_fn_0767(SelectedCharacter);
      Key := #0;
    end;
  until (Key in ['0'..'9', 'A'..'Z']) or ((Key = KeyReturn) and (AcceptEnter <> 0));
  case Key of
    KeyReturn: AskMenu := 0;
  else
    I := 1;
    while (I <= Length(Keys)) and (Keys[I] <> Key) do
      Inc(I);
    if I <= Length(Keys) then
      AskMenu := I - 1
    else
      AskMenu := $FF;
  end;
end;
{ ovl07:1788. AskListMenu: ParseHotkeys on the menu Text, then the scrolling list menu
  ChooseFromList with Title, the prepared Text and every other parameter passed on; the key it
  returns is dropped (only the var results Redraw, Choice and Selected matter). Called by ovl03. }
procedure AskListMenu(Title: String40; Text: string; HeadingColor, LineColor, HighlightColor: Byte;
  Left, Top, Right, Bottom: ShortInt; List: PMenuLine; WithExit: Byte; var Redraw: Byte;
  var Choice: Integer; var Selected: PMenuLine);
var
  Key: Char;
  Keys: String40;
begin
  ParseHotkeys(Text, Keys);
  Key := ChooseFromList(Title, Text, HeadingColor, LineColor, HighlightColor, Left, Top, Right,
    Bottom, List, WithExit, Redraw, Choice, Selected);
end;
{ ovl07:1815: retf 8: 8 bytes of parameters; 512 bytes of locals }
{@stub} procedure ovl07_e15; begin end;
{ ovl07:18EB: retf 4: 4 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl07_e16; begin end;
{ ovl07:1951: retf 2: 2 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl07_e17; begin end;
{ ovl07:19DB: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl07_e19; begin end;
{ ovl07:1A6F: retf 2: 2 bytes of parameters; 30 bytes of locals }
{@stub} procedure ovl07_e18; begin end;
{ ovl07:1CC3: retf 10: 10 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl07_e20; begin end;
{ ovl07:1DF0: retf 6: 6 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl07_e21; begin end;
{ ovl07:1EA6: retf 0: 0 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl07_e22; begin end;
{ ovl07:1FB1: retf 8: 8 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl07_e23; begin end;
{ ovl07:20A9: frame not read }
{@stub} procedure ovl07_fn_20A9; begin end;
{ ovl07:20CC: retf 6: 6 bytes of parameters; 518 bytes of locals }
{@stub} procedure ovl07_e24; begin end;

begin
end.
