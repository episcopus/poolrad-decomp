unit RES05;
{ The file and text layer (whitepaper 4.1, 5.15): LoadDaxBlock reads one block of a DAX archive
  (OpenDaxFile, the index walk, UnpackRle), OpenGameFile opens a game file and asks for the disk
  while it is missing, FileExists probes a name, MakeDosFileName cleans a name for DOS, and
  WriteCharsAt, WriteTextAt, FillBlocksAt and ShowBottomMessage write text through the BIOS.
  SelectTileSet and RestoreTileSet keep the 8X8D file number.
  Switches: I+ for the unit, with WaitForOverlayDisk, OpenGameFile and FileExists under I- (no
  CheckInOutRes after their Reset, Close and WriteLn, 0802:0246, 02D7, 032A). O+ as in the overlay
  units: WaitForOverlayDisk copies the literal 'game.ovr' into a stack temporary before calling
  FileExists (0802:0218), which the compiler does only under O+ (make match: without it the frame
  is 2 bytes, not 12). }
{$A-,O+,F+,S-,R-,G-,I+}
interface
type
  { A 40-character name: OpenGameFile copies its two name arguments (the file name and its
    extension) with System_StrLCopy limit $28 (0802:028D, 0802:02A4). }
  String40 = string[40];
  { The DAX file name and extension LoadDaxBlock takes: copied with limit $14 (0802:0727). }
  String20 = string[20];
  { A run of bytes addressed by index (UnpackRle); $R- makes the bound only a declaration. }
  TByteArray = array[0..65519] of Byte;
  PByteArray = ^TByteArray;
procedure FreeHeapBlock(var Block: Pointer; Size: Word);
procedure AllocHeapBlock(var Block: Pointer; Size: Word);
procedure WriteCharsAt(Col, Row, Color, Count: Byte; Ch: Char);
procedure WriteTextAt(Col, Row, Color: Byte; Text: string);
procedure FillBlocksAt(Col, Row, Color, Count: Byte);
procedure ShowBottomMessage(Color: Byte; Message: String40);
procedure WaitForOverlayDisk;
function OpenGameFile(FileName: String40; DiskPrompt: String40; NoPrompt: Byte; var GameFile: file): Byte;
function FileExists(FileName: String40): Boolean;
function DeleteAllOccurrences(Text: string; Pattern: string): string;
function MakeDosFileName(Name: string): String40;
procedure UnpackRle(var Source, Dest: Pointer; var PackedSize, UnpackedSize: Word);
function OpenDaxFile(Name: String40; Ext: String40; var HeaderSize: Word;
  var DataFile: file; var IndexFile: file): Boolean;
procedure CloseDaxFile(var DataFile: file; var IndexFile: file);
procedure LoadDaxBlock(Name: String20; Ext: String20; BlockId: Byte; var Size: Word; var Block: Pointer);
procedure SelectTileSet(NewSet: Byte);
procedure RestoreTileSet;
implementation
uses Dos, POOLVARS, RES04;

const
  BiosVideo = $10;           { INT 10h, the BIOS video services }
  BiosSetCursor = 2;         { function 2: set the cursor position (DH row, DL column, BH page) }
  BiosWriteChar = 9;         { function 9: write AL CX times with attribute BL on page BH }
  SolidBlock = #$DB;         { the full block character of the PC character set }
  PromptRow = 24;            { the bottom text row, where ShowBottomMessage shows its message }
  RowWidth = 40;             { text cells in a row (40-column mode) }
  Black = 0;
  Yellow = 14;
  MaxPackedSize = $8CA0;     { the largest packed block LoadDaxBlock accepts (0802:080B) }


{ 0802:0000. Frees a heap block that AllocHeapBlock allocated: the size is rounded up to the heap's
  8-byte granularity the same way. LoadDaxBlock frees its packed buffer with it. }
procedure FreeHeapBlock(var Block: Pointer; Size: Word);
begin
  FreeMem(Block, (Size + 7) and $FFF8);
end;

{ 0802:0020. Allocates a heap block of Size bytes rounded up to a multiple of 8. LoadDaxBlock
  allocates its packed buffer with it. }
procedure AllocHeapBlock(var Block: Pointer; Size: Word);
begin
  GetMem(Block, (Size + 7) and $FFF8);
end;

{ 0802:0040. Writes Count copies of the character Ch at text cell (Col, Row) through the BIOS
  (INT 10h function 2 sets the cursor, function 9 writes the character with its attribute) on the
  page in TextPage. With VideoAdapter 0 the colour goes through the four-colour table TextColourMap4; with
  VideoAdapter 1 the same two calls are repeated on the page in FillTextPage with the colour as it is. }
procedure WriteCharsAt(Col, Row, Color, Count: Byte; Ch: Char);
begin
  Regs.AH := BiosSetCursor;
  Regs.BH := TextPage;
  Regs.DH := Row;
  Regs.DL := Col;
  Intr(BiosVideo, Regs);
  Regs.AH := BiosWriteChar;
  Regs.AL := Ord(Ch);
  Regs.BH := TextPage;
  if VideoAdapter = 0 then
    Regs.BL := TextColourMap4[Color]
  else
    Regs.BL := Color;
  Regs.CX := Count;
  Intr(BiosVideo, Regs);
  if VideoAdapter = 1 then
  begin
    Regs.AH := BiosSetCursor;
    Regs.BH := FillTextPage;
    Regs.DH := Row;
    Regs.DL := Col;
    Intr(BiosVideo, Regs);
    Regs.AH := BiosWriteChar;
    Regs.AL := Ord(Ch);
    Regs.BH := FillTextPage;
    Regs.BL := Color;
    Regs.CX := Count;
    Intr(BiosVideo, Regs);
  end;
end;

{ 0802:0105. Writes Text from text cell (Col, Row) to the right in Color, one character at a
  time through WriteCharsAt. }
procedure WriteTextAt(Col, Row, Color: Byte; Text: string);
var
  Len, I: Byte;
begin
  Len := Length(Text);
  for I := 1 to Len do
  begin
    WriteCharsAt(Col, Row, Color, 1, Text[I]);
    Inc(Col);
  end;
end;

{ 0802:0175. Fills Count text cells from (Col, Row) to the right with solid blocks in Color
  (character $DB through WriteCharsAt). }
procedure FillBlocksAt(Col, Row, Color, Count: Byte);
begin
  WriteCharsAt(Col, Row, Color, Count, SolidBlock);
end;

{ 0802:0193. Shows Message in Color on the bottom text row, waits for a key (ReadGameKey) and
  clears the row again with black blocks. QUIRK 0802:01D4: the key is stored and never read. }
procedure ShowBottomMessage(Color: Byte; Message: String40);
var
  Key: Char;
begin
  FillBlocksAt(0, PromptRow, Black, RowWidth);
  WriteTextAt(0, PromptRow, Color, Message);
  Key := ReadGameKey;
  FillBlocksAt(0, PromptRow, Black, RowWidth);
end;

{ 0802:0212. Waits until the overlay file game.ovr can be opened: while it cannot, writes
  "Please insert overlay disk." and waits for a key. res08's initialisation calls it. }
{$I-}
procedure WaitForOverlayDisk;
var
  Key: Char;
  Found: Boolean;
begin
  repeat
    Found := FileExists('game.ovr');
    if not Found then
    begin
      WriteLn('Please insert overlay disk.');
      Key := ReadGameKey;
    end;
  until Found;
end;

{ 0802:025D. Opens the file FileName for reading with records of one byte. While it does not
  exist and NoPrompt is 0, shows DiskPrompt (colour 14) and waits for a key, then tries again.
  Returns 1 when the file was found and GameFile is open, 0 otherwise. }
function OpenGameFile(FileName: String40; DiskPrompt: String40; NoPrompt: Byte; var GameFile: file): Byte;
var
  Found: Boolean;
begin
  repeat
    Found := FileExists(FileName);
    if not Found and (NoPrompt = 0) then ShowBottomMessage(Yellow, DiskPrompt);
  until Found or (NoPrompt <> 0);
  if Found then
  begin
    Assign(GameFile, FileName);
    Reset(GameFile, 1);
  end;
  OpenGameFile := Ord(Found);
end;

{ 0802:02EB. Tells whether FileName names a file that can be opened: opens and closes it with
  I/O checks off, keeps IOResult in FileProbeResult, and returns True when that is 0 and the name is not
  empty. }
function FileExists(FileName: String40): Boolean;
var
  Probe: file;
begin
  Assign(Probe, FileName);
  Reset(Probe);
  Close(Probe);
  FileProbeResult := IOResult;
  FileExists := (FileProbeResult = 0) and (Length(FileName) <> 0);
end;
{$I+}

{ 0802:0356. Returns Text with each occurrence of Pattern deleted. QUIRK 0802:03A2: the last
  start position is computed once, before any deletion, so the loop runs past the shortened text,
  and a match that a deletion moves under the current position is not seen. }
function DeleteAllOccurrences(Text: string; Pattern: string): string;
var
  LastStart, PatternLen, I: Byte;
begin
  PatternLen := Length(Pattern);
  LastStart := Length(Text) - PatternLen + 1;
  for I := 1 to LastStart do
    if Copy(Text, I, PatternLen) = Pattern then Delete(Text, I, PatternLen);
  DeleteAllOccurrences := Text;
end;

{ 0802:0425. Turns Name into a DOS file name: deletes each of the ten characters of
  BadNameChars (space . * , ? / \ : ; |), keeps the first 8 characters and makes them upper case. }
function MakeDosFileName(Name: string): String40;
var
  I: Byte;
begin
  for I := 1 to 10 do Name := DeleteAllOccurrences(Name, BadNameChars[I]);
  Name := Copy(Name, 1, 8);
  for I := 1 to Length(Name) do Name[I] := UpCase(Name[I]);
  MakeDosFileName := Name;
end;

{ 0802:050F. Unpacks the run-length coded block Source^ (PackedSize bytes) into Dest^. A
  code byte 0..$7E is followed by code + 1 literal bytes; a code -127..-1 is followed by one byte
  that is repeated -code times (whitepaper 4.1). UnpackedSize is not read. QUIRK 0802:0574: the
  codes $7F and -128 ($80) match neither arm and InPos does not move, so the loop never ends; the
  1,245 blocks of the shipped DAX files contain neither code (a scan with tools/re/dax.py). }
procedure UnpackRle(var Source, Dest: Pointer; var PackedSize, UnpackedSize: Word);
var
  InPos, OutPos: Word;
  Code: ShortInt;
begin
  InPos := 0;
  OutPos := 0;
  repeat
    Code := ShortInt(PByteArray(Source)^[InPos]);
    case Code of
      0..$7E:
        begin
          Move(PByteArray(Source)^[InPos + 1], PByteArray(Dest)^[OutPos], Code + 1);
          Inc(InPos, Code + 2);
          Inc(OutPos, Code + 1);
        end;
      -$7F..-1:
        begin
          Code := -Code;
          FillChar(PByteArray(Dest)^[OutPos], Code, PByteArray(Source)^[InPos + 1]);
          Inc(InPos, 2);
          Inc(OutPos, Code);
        end;
    end;
  until InPos >= PackedSize;
end;

{ 0802:05CD. Opens the DAX file Name + Ext twice: as DataFile through OpenGameFile (prompting
  with the disk name InsertDiskPrompts[TileSet], the drive letter DiskDriveLetter and a colon; OpenNoPrompt is the NoPrompt
  flag) and as IndexFile. Reads the header size word from IndexFile into HeaderSize, adds 2 for
  the word itself and seeks DataFile there. Returns False when the file was not found. }
function OpenDaxFile(Name: String40; Ext: String40; var HeaderSize: Word;
  var DataFile: file; var IndexFile: file): Boolean;
var
  Got: Word;
begin
  if OpenGameFile(Name + Ext, InsertDiskPrompts[TileSet] + Chr(DiskDriveLetter) + ':', OpenNoPrompt, DataFile) <> 0 then
  begin
    Assign(IndexFile, Name + Ext);
    Reset(IndexFile, 1);
    BlockRead(IndexFile, HeaderSize, 2, Got);
    Inc(HeaderSize, 2);
    Seek(DataFile, HeaderSize);
    OpenDaxFile := True;
  end
  else
    OpenDaxFile := False;
end;

{ 0802:06E7. Closes the data file and the index file of a DAX file that OpenDaxFile
  opened, with I/O checks (LoadDaxBlock). }
procedure CloseDaxFile(var DataFile: file; var IndexFile: file);
begin
  Close(DataFile);
  Close(IndexFile);
end;

{ 0802:0716. Loads block BlockId of the DAX file Name + Ext (in the directory GameDir) into a new
  heap block Block of Size bytes (whitepaper 4.1). Walks the index (id byte, offset longint, unpacked
  size word, packed size word per entry) until the id matches or the index ends, reads the packed
  bytes into the buffer PackedBuf and unpacks them (UnpackRle). A packed size above
  MaxPackedSize shows "tempsize <n>" and quits. When the file or the block is missing, Size is 0
  and Block is nil. }
procedure LoadDaxBlock(Name: String20; Ext: String20; BlockId: Byte; var Size: Word; var Block: Pointer);
var
  PackedSize: Word;
  Offset: LongInt;
  Id: Byte;
  Got: Word;
  DataFile, IndexFile: file;
  HeaderSize: Word;
  UnusedByte: Byte;       { QUIRK 0802:0719: one byte of the frame (bp-$136) is never used }
  SizeText: string[6];
begin
  if not OpenDaxFile(GameDir + Name, Ext, HeaderSize, DataFile, IndexFile) then
  begin
    Size := 0;
    Block := nil;
    Exit;
  end;
  repeat
    BlockRead(IndexFile, Id, 1, Got);
    BlockRead(IndexFile, Offset, 4, Got);
    BlockRead(IndexFile, Size, 2, Got);
    BlockRead(IndexFile, PackedSize, 2, Got);
    if PackedSize > MaxPackedSize then
    begin
      Str(PackedSize, SizeText);
      ShowBottomMessage(Yellow, 'tempsize ' + SizeText);
      QuitGame;
    end;
  until (Id = BlockId) or (HeaderSize <= FilePos(IndexFile));
  if Id <> BlockId then
  begin
    Size := 0;
    Block := nil;
    CloseDaxFile(DataFile, IndexFile);
  end
  else
  begin
    AllocHeapBlock(PackedBuf, PackedSize);
    GetMem(Block, Size);
    Seek(DataFile, HeaderSize + Offset);
    BlockRead(DataFile, PackedBuf^, PackedSize, Got);
    CloseDaxFile(DataFile, IndexFile);
    UnpackRle(PackedBuf, Block, PackedSize, Size);
    FreeHeapBlock(PackedBuf, PackedSize);
  end;
end;

{ 0802:094A. Saves TileSet in SavedTileSet, then makes NewSet the current 8X8D file number.
  RestoreTileSet copies SavedTileSet back. ovl07 and ovl17 call this. }
procedure SelectTileSet(NewSet: Byte);
begin
  SavedTileSet := TileSet;
  TileSet := NewSet;
end;

{ 0802:095D. Puts back the TileSet that SelectTileSet saved in SavedTileSet. ovl17 calls this. }
procedure RestoreTileSet;
begin
  TileSet := SavedTileSet;
end;

begin
end.
