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
procedure ovl07_e2;
procedure ovl07_e1;
procedure ovl07_e3;
procedure LoadEcl;
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
procedure ovl07_e12;
procedure ovl07_fn_1153;
procedure ovl07_fn_12FB;
procedure ovl07_fn_156D;
function ovl07_e13(Title: String40; Text: string; A, B, C, D, E: Byte): Byte;
procedure ovl07_e14;
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
uses OVL28, OVL29;

const
  { The blocks of the script's address space (MemRegion). }
  RegionGameVars = 0;
  RegionWords6B00 = 1;
  RegionWords9700 = 2;
  RegionCode = 3;
  RegionSpecial = 4;

{ ovl07:0000: retf 2: 2 bytes of parameters; 8 bytes of locals }
{@stub} procedure ovl07_e2; begin end;
{ ovl07:0136: retf 2: 2 bytes of parameters; 10 bytes of locals }
{@stub} procedure ovl07_e1; begin end;
{ ovl07:01B6: retf 0: 0 bytes of parameters; 4 bytes of locals }
{@stub} procedure ovl07_e3; begin end;
{ ovl07:0341: retf 2: 2 bytes of parameters; 274 bytes of locals }
{@stub} procedure LoadEcl; begin end;
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
{ ovl07:0F53: retf 6: 6 bytes of parameters; 260 bytes of locals }
{@stub} procedure ovl07_e12; begin end;
{ ovl07:1153: retf 4: 4 bytes of parameters; 520 bytes of locals }
{@stub} procedure ovl07_fn_1153; begin end;
{ ovl07:12FB: frame not read }
{@stub} procedure ovl07_fn_12FB; begin end;
{ ovl07:156D: retf 8: 8 bytes of parameters; 514 bytes of locals }
{@stub} procedure ovl07_fn_156D; begin end;
{ ovl07:1684: retf 18; a string[40], a string and five bytes; returns a byte (the Temple tests it for 1). }
{@stub} function ovl07_e13(Title: String40; Text: string; A, B, C, D, E: Byte): Byte; begin end;
{ ovl07:1788: retf 40: 40 bytes of parameters; 340 bytes of locals }
{@stub} procedure ovl07_e14; begin end;
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
