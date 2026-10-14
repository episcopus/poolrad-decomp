{ Probe for ovl17_e5's local layout and string-expression codegen (playbook 30).
  Question 1: with a `string` value parameter (copy at [bp-0x100]) and the declared locals
  SaveFile: file; ReadCount: Word; Suffix: string[4]; Status: Byte; DiskPrompt: string[40], which
  offsets do they get? (the original uses 0x180, 0x182, 0x187, 0x1b9, 0x1b8)
  Question 2: which source shape gives `FileName := SaveDir + MakeDosFileName(FileName)` and
  `DiskPrompt := 'Put save disk in ' + SaveDir[1] + ':'` and `OpenGameFile(FileName + Suffix, ...)`. }
{$F+,S-,R-,I-}
program E5Lay;

type
  String40 = string[40];
  PCharacter = ^TCharacter;
  TCharacter = record Pad: array[0..299] of Byte; end;

var
  SaveDir, GameDir: string;
  TileSet: Byte;
  InsertDiskPrompts: array[0..8] of string[29];

function MakeDosFileName(FileName: string): String40; begin end;
function OpenGameFile(FileName: String40; DiskPrompt: String40; NoPrompt: Byte; var GameFile: file): Byte; begin end;

procedure T(FileName: string; Who: PCharacter; SavedGame: Byte; UseSaveDir: Byte);
var
  SaveFile: file;
  ReadCount: Word;
  Suffix: string[4];
  Status: Byte;
  DiskPrompt: string[40];
begin
  if UseSaveDir <> 0 then
  begin
    FileName := SaveDir + MakeDosFileName(FileName);
    DiskPrompt := 'Put save disk in ' + SaveDir[1] + ':';
  end
  else
    DiskPrompt := InsertDiskPrompts[TileSet] + GameDir[1] + ':';
  if SavedGame <> 0 then
    Suffix := '.sav'
  else
    Suffix := '.cha';
  Status := OpenGameFile(FileName + Suffix, DiskPrompt, 0, SaveFile);
  BlockRead(SaveFile, Who^, 285, ReadCount);
  Close(SaveFile);
end;

begin
  T('', nil, 0, 0);
end.
