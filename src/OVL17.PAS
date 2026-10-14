unit OVL17;
{ SaveLoad: the save and load unit (whitepaper 4.4). Its entry points write and read the files of a
  saved game on the save disk: the per-character CHRDAT<slot><n>.SAV/.ITM/.SPC files with their
  character (285 bytes), item (63 bytes) and affect (9 bytes) records. The file names are built
  from SaveDir and the game directory, CreateSaveDir makes the save directory on the save disk, and
  the "Put save disk in <drive>:" prompt shows while that disk is missing. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
type
  String8 = string[8];   { the short save-file base name SaveCharacter takes }
  ScriptName = string[40];  { a value string parameter carrying a file name (SaveAndExit) }
procedure ReadSavedCharacterList(var List: PMenuLine);
procedure RewriteSavedCharacterList(List: PMenuLine);
procedure CreateSaveDir;
procedure MergePictureData(Source, Dest: Pointer);
procedure BuildCharacterIcon(Recolor: Boolean);
procedure SaveCharacter(Who: PCharacter; Name: String8);
procedure LoadCharacterFile(FileName: string; Who: PCharacter; SavedGame: Byte; UseSaveDir: Byte);
procedure LoadMonster(Kind: Byte; Who: Pointer);
procedure AddMonsterToParty(Kind: Byte);
procedure AddPartyMember(Member: PCharacter);
procedure LoadGame;
procedure SaveGame;
procedure SaveAndExit(AreaScript: ScriptName);
implementation
uses RES04, RES05, RES06, RES07, OVL18, OVL23, OVL24, OVL25, OVL29, OVL32;

type
  { An in-memory picture as ovl32 loads it: the same layout as ovl32's private TMemPic, with the
    byte size (the word at +$11), the pointer to the packed pixel bytes (+$13) and the copied tail
    (+$17) that the picture operations index. Declared here because ovl17 needs it too. }
  PMemPic = ^TMemPic;
  TMemPic = record
    Head: array[0..$10] of Byte;  { +0..+$10: the picture header (height, width, item count) }
    ByteSize: Word;               { +$11: bytes per tile }
    Pixels: ^Byte;                { +$13: the packed pixel bytes }
    Tail: array[0..20000] of Byte;  { +$17: the tile bytes, indexed by a byte times ByteSize }
  end;
  { The monster picture-bank tables a loaded monster's appearance is picked from: a view of the
    ds08C5-region byte table (POOLVARS, whose ds08C5[Figure[0]] is the CHEAD/CBODY suffix) with the
    head bank table at +2 and the four body bank tables at +$12, +$1C, +$26 and +$30. AddMonsterToParty
    indexes each by Who^.B9E * its stride plus a RollDice. The first two bytes are the suffix
    table's. }
  { Each table is indexed [Who^.B9E, a RollDice], one row per B9E (the 16/10-byte extents keep the
    next table at its own offset; a 2-D access is what makes the compiler index by the row stride,
    as ThiefDexTable[Dexterity, Skill] does in ovl23). }
  TMonsterBanks = record
    Suffix01: array[0..1] of Byte;       { +0..+1: the CHEAD/CBODY suffix table's first bytes }
    Head: array[0..1, 0..7] of Byte;     { +2: head banks, [B9E, RollDice(1, 8)] }
    BodyClass0: array[0..1, 0..4] of Byte;  { +$12: body banks for class 0 }
    BodyOther: array[0..1, 0..4] of Byte;   { +$1C: body banks for the other classes }
    BodyClass5: array[0..1, 0..4] of Byte;  { +$26: body banks for class 5 }
    BodyClass6: array[0..1, 0..4] of Byte;  { +$30: body banks for class 6 }
  end;

var
  MonsterBanks: TMonsterBanks absolute ds08C5;  { the ds08C5 picture-bank tables; see TMonsterBanks }

const
  Yellow = $0E;        { EGA text colour of the disk prompt (the message colour OVL00 also uses) }
  IoSuccess = 0;       { IOResult of a MkDir that created the directory }
  IoDirExists = 5;     { IOResult of a MkDir when the directory is already there (DOS access denied) }
  { A menu line as the save and load lists allocate it: the Text, Flag29 and Next fields of
    TMenuLine (46 bytes), not the whole item record. ovl25's NewMenuList and FreeMenuList use the
    same size. }
  MenuLineBytes = $2E;

{ ovl17:0010. Reads the save disk's charlist.txt (SaveDir + 'charlist.txt') and builds List as the
  menu list of the saved characters: one 46-byte menu line per line of that file, in file order.
  A name a party member (the ds5D96 list) already carries is prefixed '* ', so the menu shows who
  is already in the party. Does nothing (List stays nil) when the file is missing. Reads SaveDir
  and the party list; writes List; side effects: the disk prompt (CreateSaveDir) and the heap (one
  menu line per saved character). Called by ovl16's character menu and by SaveCharacter (save one
  character). }
procedure ReadSavedCharacterList(var List: PMenuLine);
var
  SavedLine: PMenuLine;         { the menu line built for the line just read }
  Last: PMenuLine;              { the last line appended, the list's tail }
  Who: PCharacter;              { walks the party list ds5D96 }
  Names: Text;                  { the opened charlist.txt }
begin
  List := nil;
  CreateSaveDir;
  if not FileExists(SaveDir + 'charlist.txt') then Exit;
  Assign(Names, SaveDir + 'charlist.txt');
  Reset(Names);
  while not Eof(Names) do
  begin
    GetMem(SavedLine, MenuLineBytes);
    FillChar(SavedLine^, MenuLineBytes, 0);
    if List = nil then
    begin
      List := SavedLine;
      Last := List;
    end
    else
    begin
      Last^.Next := SavedLine;
      Last := Last^.Next;
    end;
    ReadLn(Names, Last^.Text);
    Who := PCharacter(ds5D96);
    while (Who <> nil) and (Who^.Name <> Last^.Text) do
      Who := Who^.Next;
    if Who <> nil then
      Last^.Text := '* ' + Last^.Text;
  end;
  Close(Names);
end;
{ ovl17:01B8. Rewrites the save disk's charlist.txt from List, the saved-character menu list that
  ReadSavedCharacterList built (and the add-character menu then edited): makes the save directory
  (CreateSaveDir), then opens charlist.txt for rewriting and shows "Put save disk in <drive>:" and
  tries again while the open fails (IOResult non-zero). Writes one line per list entry whose text
  does not start with '*' (the party members are skipped, so they leave the available-character
  file), then closes it. Reads SaveDir and List; writes charlist.txt. Called by the ovl16 add-character
  menu (ovl16_fn_306D) and by SaveCharacter. }
procedure RewriteSavedCharacterList(List: PMenuLine);
var
  Line: PMenuLine;              { walks the list }
  Names: Text;                  { the rewritten charlist.txt }
  ErrCode: Word;                { IOResult of the Rewrite }
begin
  CreateSaveDir;
  repeat
    Assign(Names, SaveDir + 'charlist.txt');
    Rewrite(Names);
    ErrCode := IOResult;
    if ErrCode <> 0 then
      ShowMessageLine(Yellow, 'Put save disk in ' + SaveDir[1] + ':');
  until ErrCode = 0;
  Line := List;
  while Line <> nil do
  begin
    if Line^.Text[1] <> '*' then
      WriteLn(Names, Line^.Text);
    Line := Line^.Next;
  end;
  Close(Names);
end;
{ ovl17:02AE. Makes sure the save directory exists on the save disk: MkDir of SaveDir without its
  trailing backslash, and while that fails with anything but success or "already there" it shows
  "Put save disk in <drive>:" (the drive letter SaveDir starts with) and tries again. Reads SaveDir,
  creates the directory on the save disk as a side effect. Called before the save files are touched
  by ReadSavedCharacterList, RewriteSavedCharacterList, SaveCharacter, LoadGame and SaveGame. }
procedure CreateSaveDir;
var
  ErrCode: Word;
begin
  repeat
    MkDir(Copy(SaveDir, 1, Length(SaveDir) - 1));
    ErrCode := IOResult;
    if (ErrCode <> IoSuccess) and (ErrCode <> IoDirExists) then
      ShowMessageLine(Yellow, 'Put save disk in ' + SaveDir[1] + ':');
  until (ErrCode = IoSuccess) or (ErrCode = IoDirExists);
end;
{ ovl17:032F. Combines two in-memory pictures, Dest and Source: ORs the tail bytes (the tile ids) of
  Source into Dest and ANDs its pixel bytes into Dest, so Source masks Dest. On the EGA adapter
  (VideoAdapter 1) the tail is ORed over Source^.ByteSize bytes and only the first
  ds5E5A[11].FirstPic^.ByteSize div 4 pixel bytes are ANDed; on the other two adapters (0 and 2)
  both run over Source^.ByteSize bytes. Called by BuildCharacterIcon for each mirrored half of the character
  head and body pictures (slot 11 holds the reference picture). No heap or file effect. }
procedure MergePictureData(Source, Dest: Pointer);
var
  Count: Word;                  { the pixel byte count of the EGA path, minus one }
  I: Word;                      { the byte index, 0 based }
begin
  case VideoAdapter of
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
        Count := PMemPic(ds5E5A[11].FirstPic)^.ByteSize div 4 - 1;
        for I := 0 to Count do
          PByteArray(PMemPic(Dest)^.Pixels)^[I] :=
            PByteArray(PMemPic(Dest)^.Pixels)^[I] and PByteArray(PMemPic(Source)^.Pixels)^[I];
      end;
  end;
end;
{ ovl17:0482. Builds the selected character's (SelectedCharacter) combat icon picture. It selects
  8X8D tile set 3, loads the character's CHEAD picture (block Sel^.CHeadBlock, the set name given
  the suffix ds08C5[Sel^.Figure[0]]) into picture slot 11 and its CBODY picture (block
  Sel^.CBodyBlock) into the character's icon slot (ds5E5A[Sel^.CombatIcon]), then merges the CHEAD
  halves into the CBODY halves (MergePictureData: OR the tile bytes, AND the pixels), so the head
  masks the body. When Recolor is set it also builds a 16-entry colour map from the six nibble pairs
  Sel^.Figure[1..6] through ds3CF5 and applies it to both halves of the icon (RemapPictureColours).
  Finally it frees slot 11, restores the tile set and flushes the keyboard. Called by the ovl16
  character menus, by AddMonsterToParty and by LoadGame. }
procedure BuildCharacterIcon(Recolor: Boolean);
var
  UnusedBytes: array[0..2] of Byte;  { QUIRK ovl17:0482: three frame bytes the original reserves and never reads or writes }
  MapFrom: array[0..15] of Byte;  { the icon's source colours (the identity map) }
  MapTo: array[0..15] of Byte;    { the destination colour of each source colour }
  I: Byte;                      { loop index }
  UnusedByte: Byte;             { QUIRK ovl17:0482: a frame byte the original reserves and never reads or writes }
begin
  SelectTileSet(3);
  with SelectedCharacter^ do
  begin
    LoadPictureSlot('CHEAD' + ds08C5[Figure[0]], CHeadBlock, 11);
    LoadPictureSlot('CBODY' + ds08C5[Figure[0]], CBodyBlock, CombatIcon);
    MergePictureData(ds5E5A[11].FirstPic, ds5E5A[CombatIcon].FirstPic);
    MergePictureData(ds5E5A[11].SecondPic, ds5E5A[CombatIcon].SecondPic);
    if Recolor then
    begin
      for I := 0 to 15 do
      begin
        MapFrom[I] := I;
        MapTo[I] := I;
      end;
      for I := 1 to 6 do
      begin
        MapTo[ds3CF5[I]] := Figure[I] and $0F;
        MapTo[ds3CF5[I] + 8] := (Figure[I] and $F0) shr 4;
      end;
      RemapPictureColours(@MapFrom, @MapTo, 0, 0, ds5E5A[CombatIcon].FirstPic);
      RemapPictureColours(@MapFrom, @MapTo, 0, 0, ds5E5A[CombatIcon].SecondPic);
    end;
    FreePictureSlot(11);
    RestoreTileSet;
    FlushKeyboard;
  end;
end;
{ ovl17:069E. Saves the character Who to the save disk. With an empty Name it adds Who's name to the
  saved-character file charlist.txt (ReadSavedCharacterList, a new 46-byte line at the tail,
  RewriteSavedCharacterList, FreeMenuList) and writes to SaveDir + a DOS-cleaned Who^.Name + '.cha';
  with a Name it makes the save directory and writes to SaveDir + Name + '.sav'. It rewrites the
  file (prompting for the save disk while the open fails), BlockWrites the 285-byte character,
  closes it, and (after erasing any old file) writes the 63-byte items of Who^.Items to '.itm' and
  the 9-byte affects of Who^.Affects to '.spc'. Called by RunCharacterMenu, ovl16_fn_1EA3 and SaveGame. }
procedure SaveCharacter(Who: PCharacter; Name: String8);
var
  SaveFile: file;                      { the file written }
  FileName: string[40];         { the file name without its extension }
  Suffix: string[4];            { the file extension: '.sav' or '.cha' }
  Unused: Word;                 { QUIRK ovl17:069E: two frame bytes the original reserves and never reads or writes }
  Item: PItem;                  { walks Who^.Items }
  Affect: PAffect;              { walks Who^.Affects }
  List: PMenuLine;              { the saved-character list ReadSavedCharacterList built }
  Walk: PMenuLine;              { walks List to its last line }
  Last: PMenuLine;              { the new line added for Who }
  ErrCode: Word;                { IOResult of the file rewrite }
begin
  if Name = '' then
  begin
    ReadSavedCharacterList(List);
    Walk := List;
    if Walk <> nil then
      while Walk^.Next <> nil do
        Walk := Walk^.Next;
    GetMem(Last, MenuLineBytes);
    FillChar(Last^, MenuLineBytes, 0);
    Last^.Text := Who^.Name;
    if Walk <> nil then
      Walk^.Next := Last
    else
      List := Last;
    RewriteSavedCharacterList(List);
    FreeMenuList(List);
    Suffix := '.cha';
    FileName := SaveDir + MakeDosFileName(DeleteAllOccurrences(Who^.Name, '.'));
  end
  else
  begin
    CreateSaveDir;
    Suffix := '.sav';
    FileName := SaveDir + Name;
  end;
  repeat
    Assign(SaveFile, FileName + Suffix);
    Rewrite(SaveFile, 1);
    ErrCode := IOResult;
    if ErrCode <> 0 then
      ShowMessageLine(Yellow, 'Put save disk in ' + SaveDir[1] + ':');
  until ErrCode = 0;
  BlockWrite(SaveFile, Who^, 285);
  Close(SaveFile);
  if FileExists(FileName + '.itm') then
  begin
    Assign(SaveFile, FileName + '.itm');
    Erase(SaveFile);
  end;
  if Who^.Items <> nil then
  begin
    Assign(SaveFile, FileName + '.itm');
    Rewrite(SaveFile, 1);
    Item := Who^.Items;
    while Item <> nil do
    begin
      BlockWrite(SaveFile, Item^, 63);
      Item := Item^.Next;
    end;
    Close(SaveFile);
  end;
  if FileExists(FileName + '.spc') then
  begin
    Assign(SaveFile, FileName + '.spc');
    Erase(SaveFile);
  end;
  if Who^.Affects <> nil then
  begin
    Assign(SaveFile, FileName + '.spc');
    Rewrite(SaveFile, 1);
    Affect := Who^.Affects;
    while Affect <> nil do
    begin
      BlockWrite(SaveFile, Affect^, 9);
      Affect := Affect^.Next;
    end;
    Close(SaveFile);
  end;
end;
{ ovl17:0AEC. Loads one character and its item and affect lists from a file. The file lives on the
  save disk (UseSaveDir: FileName is SaveDir + the DOS-cleaned name, and the prompt names SaveDir's
  drive) or on the game disk (the prompt is InsertDiskPrompts[TileSet] + GameDir's drive). SavedGame
  picks the character suffix: '.sav' for a saved game, '.cha' for an available character. It opens
  FileName + Suffix through OpenGameFile and BlockReads the 285-byte character into Who^, then clears
  Who's list links (Next, Items, Affects, Combat), and, when FileName.itm / FileName.spc exist, reads
  the 63-byte item and 9-byte affect lists, each into a GetMem chain that runs to end of file. Reads
  SaveDir, GameDir, TileSet and InsertDiskPrompts; writes SaveFile, Who^ and the heap; then flushes the
  keyboard. The read counterpart of SaveCharacter. Called by ovl16_fn_306D and LoadGame. }
procedure LoadCharacterFile(FileName: string; Who: PCharacter; SavedGame: Byte; UseSaveDir: Byte);
var
  SaveFile: file;               { the character, item and affect files }
  ReadCount: Word;              { the record count BlockRead reports }
  Suffix: string[4];            { '.sav' or '.cha' }
  Item: PItem;                  { walks Who^.Items while the items are read }
  Affect: PAffect;              { walks Who^.Affects while the affects are read }
  DiskPrompt: string[40];       { the "Put save disk in X:" prompt OpenGameFile shows }
  Status: Byte;                 { the OpenGameFile result (kept, never read) }
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
  Who^.Next := nil;
  Who^.Items := nil;
  Who^.Affects := nil;
  Who^.Combat := nil;
  if FileExists(FileName + '.itm') then
  begin
    GetMem(Who^.Items, 63);
    Item := Who^.Items;
    Status := OpenGameFile(FileName + '.itm', DiskPrompt, 0, SaveFile);
    repeat
      BlockRead(SaveFile, Item^, 63, ReadCount);
      Item^.Next := nil;
      if not Eof(SaveFile) then
      begin
        GetMem(Item^.Next, 63);
        Item := Item^.Next;
      end;
    until Eof(SaveFile);
    Close(SaveFile);
  end;
  if FileExists(FileName + '.spc') then
  begin
    GetMem(Who^.Affects, 9);
    Affect := Who^.Affects;
    Status := OpenGameFile(FileName + '.spc', DiskPrompt, 0, SaveFile);
    repeat
      BlockRead(SaveFile, Affect^, 9, ReadCount);
      Affect^.Next := nil;
      if not Eof(SaveFile) then
      begin
        GetMem(Affect^.Next, 9);
        Affect := Affect^.Next;
      end;
    until Eof(SaveFile);
    Close(SaveFile);
  end;
  FlushKeyboard;
end;
{ ovl17:0EC4. Loads one monster character and its affect and item lists from the MON<TileSet>*.DAX
  archives. CharSet is Str(TileSet). It loads MON<set>CHA.DAX block Kind into a buffer and, when the
  block is missing, shows 'Unable to load monster' and quits; otherwise it Moves the 285-byte record
  into Who^, clears the character's list links (Items, Affects, Next, Combat) and builds its figure
  descriptor: Figure[0] is 1 for the races 1/3/5 and 2 for 2/4/6/7, Figure[1..3] and Figure[5..6] are
  two random nibble pairs from RollDice(1, 6), and Figure[4] is $C4. Then it loads MON<set>SPC.DAX
  and MON<set>ITM.DAX block Kind and copies their 9-byte affect and 63-byte item records out of the
  buffer (the offset advances to the block size) into GetMem chains. Sets ds557C while the lists are
  read and flushes the keyboard. Called by ovl07 LoadCharacter and AddMonsterToParty. }
procedure LoadMonster(Kind: Byte; Who: Pointer);
var
  Size: Word;                   { the unpacked size of the loaded DAX block }
  Block: Pointer;               { the DAX buffer LoadDaxBlock allocates }
  Offset: Word;                 { the byte offset into Block while a list is copied }
  Item: PItem;                  { walks the item chain while it is built }
  Affect: PAffect;              { walks the affect chain while it is built }
  CharSet: string[1];           { Str(TileSet): the monster set number in the file name }
  I: Byte;                      { the Figure index one random nibble pair is written to }
  Roll: Byte;                   { RollDice(1, 6) for one nibble pair }
begin
  Str(TileSet, CharSet);
  LoadDaxBlock('MON' + CharSet + 'CHA', '.dax', Kind, Size, Block);
  if Size = 0 then
  begin
    ShowMessageLine(15, 'Unable to load monster');
    QuitGame;
  end;
  Move(Block^, Who^, 285);
  with PCharacter(Who)^ do
  begin
    Items := nil;
    Affects := nil;
    Next := nil;
    Combat := nil;
    case Race of
      1, 3, 5: Figure[0] := 1;
      2, 4, 6, 7: Figure[0] := 2;
    end;
    for I := 1 to 3 do
    begin
      Roll := RollDice(1, 6);
      Figure[I] := Roll + ((Roll + 8) shl 4);
    end;
    Figure[4] := $C4;
    for I := 5 to 6 do
    begin
      Roll := RollDice(1, 6);
      Figure[I] := Roll + ((Roll + 8) shl 4);
    end;
  end;
  FreeMem(Block, Size);
  ds557C := 1;
  LoadDaxBlock('MON' + CharSet + 'SPC', '.dax', Kind, Size, Block);
  if Size <> 0 then
  begin
    Offset := 0;
    GetMem(PCharacter(Who)^.Affects, 9);
    Affect := PCharacter(Who)^.Affects;
    repeat
      Move(PByteArray(Block)^[Offset], Affect^, 9);
      Affect^.Next := nil;
      Inc(Offset, 9);
      if Offset < Size then
      begin
        GetMem(Affect^.Next, 9);
        Affect := Affect^.Next;
      end;
    until Offset >= Size;
    FreeMem(Block, Size);
  end;
  LoadDaxBlock('MON' + CharSet + 'ITM', '.dax', Kind, Size, Block);
  if Size <> 0 then
  begin
    Offset := 0;
    GetMem(PCharacter(Who)^.Items, 63);
    Item := PCharacter(Who)^.Items;
    repeat
      Move(PByteArray(Block)^[Offset], Item^, 63);
      Item^.Next := nil;
      Inc(Offset, 63);
      if Offset < Size then
      begin
        GetMem(Item^.Next, 63);
        Item := Item^.Next;
      end;
    until Offset >= Size;
    FreeMem(Block, Size);
  end;
  ds557C := 0;
  FlushKeyboard;
end;
{ ovl17:1262. Adds a monster of kind Kind to the party. If the party already holds eight members
  (ds49D6^[PartySize] > 7) it does nothing. Otherwise it allocates a 285-byte character and has
  LoadMonster fill it, gives it a random byte at +$AB (Random(256)), collects the classes with a
  positive level (Who^.ClassLevels[0..6]) into Pick[] (Pick[1] = 2 when none qualifies), rolls one of
  them (RollDice(1, Count)) and picks the monster's body picture bank from the ds08C5-region
  MonsterBanks tables by the roll and Who^.B9E (the body table of class 0, 5, 6 or the default), and
  its head bank from the head table the same way. Then AddPartyMember adds it and
  BuildCharacterIcon(True) rebuilds the combat icon. Called by ovl03_fn_2B7E. }
procedure AddMonsterToParty(Kind: Byte);
const
  PartySize = 830;              { party member count, a word of the ds49D6 game variable block }
  LastClass = 6;                { the highest ClassLevels index the class scan tests }
var
  Unused: Pointer;              { QUIRK ovl17:1262: a spare far pointer the original never reads or writes }
  Who: PCharacter;              { the monster record being built }
  Count: Byte;                  { the classes found, then the RollDice(1, Count) pick }
  I: ShortInt;                  { walks the classes 0..LastClass }
  { QUIRK ovl17:1262: four bytes, but the scan writes up to Pick[LastClass + 1] (7): the original
    writes past the array into Count, I and Who for a monster with more than four classes. }
  Pick: array[1..4] of Byte;    { the classes with a positive level, 1-based }
begin
  if ds49D6^[PartySize] > 7 then Exit;
  GetMem(Who, 285);
  LoadMonster(Kind, Who);
  with Who^ do
  begin
    BAB := Random(256);
    Count := 0;
    for I := 0 to LastClass do
      if ClassLevels[I] > 0 then
      begin
        Inc(Count);
        Pick[Count] := I;
      end;
    if Count = 0 then
    begin
      Count := 1;
      Pick[Count] := 2;
    end;
    Count := RollDice(1, Count);
    case Pick[Count] of
      0: BodyBank := MonsterBanks.BodyClass0[B9E, RollDice(1, 5)];
      5: BodyBank := MonsterBanks.BodyClass5[B9E, RollDice(1, 5)];
      6: BodyBank := MonsterBanks.BodyClass6[B9E, RollDice(1, 5)];
      else BodyBank := MonsterBanks.BodyOther[B9E, RollDice(1, 5)];
    end;
    HeadBank := MonsterBanks.Head[B9E, RollDice(1, 8)];
  end;
  AddPartyMember(Who);
  BuildCharacterIcon(True);
end;
{ ovl17:1446. Adds one character to the party list (ds5D96) and gives it a combat map icon. Member
  points to the TCharacter to add: its Next is left nil. When the list is empty it becomes the head
  and SelectedCharacter; otherwise it is linked at the tail. Then every icon number 0..7 a member
  already holds is marked Used[], and SelectedCharacter (set to Member) gets the lowest number no one
  holds. Finally the party size word is counted up and the character's class statistics are
  recalculated. Reads the party list and SelectedCharacter; side effects: the party list,
  SelectedCharacter^.CombatIcon, ds49D6^[VarPartySize], and whatever RecalcClassStats writes. }
procedure AddPartyMember(Member: PCharacter);
const
  FirstIcon = 0;                { lowest combat map icon number a party member can hold }
  IconCount = 8;                { the icon numbers run 0..IconCount-1 (the free-icon loop bound) }
  VarPartySize = 830;           { party member count, a word of the ds49D6 game variable block }
var
  Who: PCharacter;              { walks the party list }
  Used: array[FirstIcon..IconCount - 1] of Boolean;  { icon numbers already held by a member }
begin
  Member^.CombatIcon := $FF;    { no icon until one is picked below (QUIRK ovl17:1446) }
  if PCharacter(ds5D96) = nil then
  begin
    ds5D96 := LongInt(Member);
    SelectedCharacter := Member;
  end
  else
  begin
    Who := PCharacter(ds5D96);
    while Who^.Next <> nil do
      Who := Who^.Next;
    Who^.Next := Member;
  end;
  FillChar(Used, SizeOf(Used), 0);
  Who := PCharacter(ds5D96);
  while Who <> nil do
  begin
    if Who^.CombatIcon in [FirstIcon..IconCount - 1] then
      Used[Who^.CombatIcon] := True;
    Who := Who^.Next;
  end;
  SelectedCharacter := Member;
  with SelectedCharacter^ do
  begin
    CombatIcon := FirstIcon;
    while (CombatIcon < IconCount) and Used[CombatIcon] do
      Inc(CombatIcon);
  end;
  Inc(ds49D6^[VarPartySize]);
  RecalcClassStats(Member);
end;
{ ovl17:1602. Loads a saved game from the save disk. It scans the letters A..J for
  SaveDir + 'savgam<letter>.dat', collects the found ones into the 'Load Which Game: ' prompt
  (ReadPromptChoice, Escape cancels) and prompts again until the player picks a slot whose file
  exists. Then it opens the slot through OpenGameFile and reads the game state back: TileSet, the
  three word blocks (GameVars, ds49D6, ds49DA), the ECL code, the party map bytes, AreaViewKind, the
  view mode, and the party list (a member count and the 8 'CHRDAT<slot><n>' names). It restores
  GameSpeed and the picture flags, loads every named member through LoadCharacterFile and
  AddPartyMember, erases the members' old standalone .cha/.itm/.spc files, rebuilds every member's
  combat icon (BuildCharacterIcon(True)), then restores the view: TileSet from $6E12, and either the
  3D view (AreaViewKind < 2: Load3DMap(GameVars^[VarGeoBlock]) and the three wall sets through
  LoadWallSet, the ds6AAEWords pairs whose block id is not negative) or, for a map view
  (AreaViewKind > 1), LoadPictureSlot('ICON', 0, 11), which loads ICON block 0 into picture slot 11,
  the scratch slot BuildCharacterIcon freed (the map view's party marker pictures are slots 9..11,
  ovl26 DrawPartyMarker). It animates the doors when the river gate is set, and flushes the
  keyboard. Reads the save files, SaveDir and the party list; writes the game state,
  ds5D96, SelectedCharacter and the party list. Called by RunCharacterMenu. }
procedure LoadGame;
var
  MemberFiles: array[1..8] of string[40];  { the 'CHRDAT<slot><n>' names read from the save }
  SaveFile: file;               { the 'savgam<slot>.dat' save file and the erased member files }
  I: Byte;                      { the member loops and the wall-set loop }
  Who: PCharacter;              { the loaded member, then the walker of the party list ds5D96 }
  FileName: string[40];         { a member file's base name (its DOS-cleaned name) }
  ReadCount: Word;              { the BlockRead record count }
  MemberCount: Byte;            { the party member count read from the save }
  Status: Byte;                 { the OpenGameFile result (kept, never read) }
  Slot: Char;                   { the scanned slot letter and the chosen one (#0 cancels) }
  ExtKey: Byte;                 { ReadPromptChoice's extended-key flag (not used) }
  GameList: string[20];         { the letters of the slots that exist, e.g. 'A C F ' }
begin
  CreateSaveDir;
  GameList := '';
  for Slot := 'A' to 'J' do
    if FileExists(SaveDir + 'savgam' + Slot + '.dat') then
      GameList := GameList + Slot + ' ';
  if GameList = '' then Exit;
  repeat
    Slot := ReadPromptChoice('Load Which Game: ', GameList, 13, 10, 15, 0, 0, ExtKey);
  until ((Slot in ['A'..'J']) and FileExists(SaveDir + 'savgam' + Slot + '.dat')) or (Slot = #0);
  if Slot = #0 then Exit;
  Status := OpenGameFile(SaveDir + 'savgam' + Slot + '.dat',
    'Put save disk in ' + SaveDir, 1, SaveFile);
  ClearPromptLine;
  DrawTextAt(0, $18, $A, 'Loading...Please Wait');
  BlockRead(SaveFile, TileSet, 1, ReadCount);
  BlockRead(SaveFile, GameVars^, $800, ReadCount);
  BlockRead(SaveFile, ds49D6^, $800, ReadCount);
  BlockRead(SaveFile, ds49DA^, $400, ReadCount);
  BlockRead(SaveFile, EclCode^, $1E00, ReadCount);
  BlockRead(SaveFile, PartyMapColumn, 5, ReadCount);
  BlockRead(SaveFile, AreaViewKind, 1, ReadCount);
  BlockRead(SaveFile, ds49F3, 1, ReadCount);
  BlockRead(SaveFile, MemberCount, 1, ReadCount);
  BlockRead(SaveFile, MemberFiles, $148, ReadCount);
  Close(SaveFile);
  ShowMonsterPics := VarsAt4900^[$49FF] shr 1;
  ShowPortraits := VarsAt4900^[$49FF] and 1;
  GameSpeed := VarsAt4900^[$49FC];
  VarsAt6B00^[$6E3E] := 0;
  for I := 1 to MemberCount do
  begin
    FileName := MakeDosFileName(DeleteAllOccurrences(MemberFiles[I], '.'));
    if FileExists(SaveDir + FileName + '.sav') then
    begin
      GetMem(Who, 285);
      LoadCharacterFile(FileName, Who, 1, 1);
      AddPartyMember(Who);
      CreateSaveDir;
    end;
  end;
  Who := PCharacter(ds5D96);
  while Who <> nil do
  begin
    FileName := SaveDir + MakeDosFileName(DeleteAllOccurrences(Who^.Name, '.'));
    if FileExists(FileName + '.cha') then
    begin
      Assign(SaveFile, FileName + '.cha');
      Erase(SaveFile);
      if FileExists(FileName + '.itm') then
      begin
        Assign(SaveFile, FileName + '.itm');
        Erase(SaveFile);
      end;
      if FileExists(FileName + '.spc') then
      begin
        Assign(SaveFile, FileName + '.spc');
        Erase(SaveFile);
      end;
    end;
    Who := Who^.Next;
  end;
  SelectedCharacter := PCharacter(ds5D96);
  while SelectedCharacter <> nil do
  begin
    BuildCharacterIcon(True);
    SelectedCharacter := SelectedCharacter^.Next;
  end;
  SelectedCharacter := PCharacter(ds5D96);
  TileSet := VarsAt6B00^[$6E12];
  if AreaViewKind < 2 then
    Load3DMap(GameVars^[VarGeoBlock]);
  if AreaViewKind > 1 then
    LoadPictureSlot('ICON', 0, 11)
  else
    for I := 1 to 3 do
    begin
      ds6AAEWords[I].A := VarsAt4900^[$4AF9 + I];
      ds6AAEWords[I].B := VarsAt4900^[$4AFC + I];
      if Integer(ds6AAEWords[I].A) >= 0 then
        LoadWallSet(ds6AAEWords[I].A, ds6AAEWords[I].B);
    end;
  if GameVars^[VarRiverGate] <> 0 then
    AnimateAreaDoors(0);
  FlushKeyboard;
  ClearPromptLine;
end;
{ ovl17:1D58. Saves the current game to the save disk. It prompts 'Save Which Game: ' for a slot
  letter A..J (Escape cancels), makes the save directory and opens SaveDir + 'savgam<letter>.dat'
  (showing the disk prompt while the open fails), then writes the whole game state: the three loaded
  wall-set slots (block id and slot) into the ECL variable words at $4AF9 + I and $4AFC + I,
  GameSpeed and the picture flags, TileSet, the three word blocks
  (GameVars, ds49D6, ds49DA), the ECL code, the party map bytes, AreaViewKind and the view mode. Then
  it writes the party list to the slot: a one-byte member count and the 8 'CHRDAT<letter><n>' names,
  and finally saves each member with SaveCharacter and erases the member's old standalone .cha/.itm/
  .spc files. Ends with the heap retry gate ds557D := 1 and clears the prompt line. Reads the slot
  key, SaveDir, the game state and the party list ds5D96; writes the save files and ds557D. Called by
  the heap error handler, MakeCamp, the character menu and SaveAndExit (SaveAndExit). }
procedure SaveGame;
var
  MemberFiles: array[1..8] of string[40];  { the 'CHRDAT<slot><n>' name written per party member }
  SaveFile: file;               { the 'savgam<slot>.dat' save file }
  Count: Byte;                  { party member count; also the small game-block loop index }
  Walk: PCharacter;             { walks the party list ds5D96 }
  NumText: string[1];           { Str(Count) }
  FileName: string[40];         { the member's standalone file name (SaveDir + its DOS name) }
  ExtKey: Byte;                 { ReadPromptChoice's extended-key flag (not used) }
  Key: Char;                    { the slot letter or #0 }
  ErrCode: Word;                { IOResult of the save-file rewrite }
begin
  repeat
    Key := ReadPromptChoice('Save Which Game: ', 'A B C D E F G H I J', 13, 10, 15, 0,
      Ord(ds49F3 = 2), ExtKey);
  until Key in [#0, 'A'..'J'];
  if Key = #0 then Exit;
  CreateSaveDir;
  repeat
    Assign(SaveFile, SaveDir + 'savgam' + Key + '.dat');
    Rewrite(SaveFile, 1);
    ErrCode := IOResult;
    if ErrCode <> 0 then
      ShowMessageLine(Yellow, 'Put save disk in ' + SaveDir[1] + ':');
  until ErrCode = 0;
  ClearPromptLine;
  DrawTextAt(0, $18, $A, 'Saving...Please Wait');
  for Count := 1 to 3 do
  begin
    VarsAt4900^[$4AF9 + Count] := ds6AAEWords[Count].A;
    VarsAt4900^[$4AFC + Count] := ds6AAEWords[Count].B;
  end;
  VarsAt4900^[$49FC] := GameSpeed;
  VarsAt4900^[$49FF] := ShowMonsterPics * 2 + ShowPortraits;
  VarsAt6B00^[$6E12] := TileSet;
  BlockWrite(SaveFile, TileSet, 1);
  BlockWrite(SaveFile, GameVars^, $800);
  BlockWrite(SaveFile, ds49D6^, $800);
  BlockWrite(SaveFile, ds49DA^, $400);
  BlockWrite(SaveFile, EclCode^, $1E00);
  BlockWrite(SaveFile, PartyMapColumn, 5);
  BlockWrite(SaveFile, AreaViewKind, 1);
  BlockWrite(SaveFile, ds49F3, 1);
  Count := 0;
  Walk := PCharacter(ds5D96);
  while Walk <> nil do
  begin
    Inc(Count);
    Str(Count, NumText);
    MemberFiles[Count] := 'CHRDAT' + Key + NumText;
    Walk := Walk^.Next;
  end;
  BlockWrite(SaveFile, Count, 1);
  BlockWrite(SaveFile, MemberFiles, $148);
  Close(SaveFile);
  Walk := PCharacter(ds5D96);
  Count := 0;
  while Walk <> nil do
  begin
    Inc(Count);
    Str(Count, NumText);
    SaveCharacter(Walk, 'CHRDAT' + Key + NumText);
    FileName := SaveDir + MakeDosFileName(DeleteAllOccurrences(Walk^.Name, '.'));
    if FileExists(FileName + '.cha') then
    begin
      Assign(SaveFile, FileName + '.cha');
      Erase(SaveFile);
    end;
    if FileExists(FileName + '.itm') then
    begin
      Assign(SaveFile, FileName + '.itm');
      Erase(SaveFile);
    end;
    if FileExists(FileName + '.spc') then
    begin
      Assign(SaveFile, FileName + '.spc');
      Erase(SaveFile);
    end;
    Walk := Walk^.Next;
  end;
  ds557D := True;
  ClearPromptLine;
end;
{ ovl17:22D5. Called by ovl03:0BD1 with the current area's ECL file name (GameDir + 'ECL' +
  Str(TileSet) + '.dax') just before an area transition. When that file exists (a normal area) it
  returns at once; otherwise it shows the 'Save and exit  Insert disk #N' line (N = TileSet)
  through ReadPromptChoice and, when the player presses its hotkey S, steps the party one cell
  back in its facing (wrapping the 16x16 area map), restores the tile set, saves the game
  (SaveGame) and quits. Reads AreaScript, TileSet, PartyMapColumn, PartyMapRow and PartyFacing;
  writes ExtKey and, on S, the party's map cell. Side effects: the prompt line, the save disk
  and the game exit. }
procedure SaveAndExit(AreaScript: ScriptName);
var
  Prompt: String40;             { the 'Save and exit  Insert disk #N' line }
  NumText: string[1];           { Str(TileSet) }
  Key: Char;                    { the key ReadPromptChoice returned }
  ExtKey: Byte;                 { nonzero when an extended key was pressed }
begin
  if FileExists(AreaScript) then Exit;
  Str(TileSet, NumText);
  Prompt := 'Save and exit  Insert disk #' + NumText;
  Key := ReadPromptChoice('', Prompt, 13, 10, 15, 0, 0, ExtKey);
  if (ExtKey = 0) and (Key = 'S') then
  begin
    Dec(PartyMapColumn, DirStepX[PartyFacing]);
    if PartyMapColumn < 0 then
      PartyMapColumn := $F;
    if PartyMapColumn > $F then
      PartyMapColumn := 0;
    Dec(PartyMapRow, DirStepY[PartyFacing]);
    if PartyMapRow < 0 then
      PartyMapRow := $F;
    if PartyMapRow > $F then
      PartyMapRow := 0;
    RestoreTileSet;
    SaveGame;
    QuitGame;
  end;
end;

begin
end.
