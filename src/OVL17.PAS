unit OVL17;
{ SaveLoad: the save and load unit (whitepaper 4.4). Its entry points write and read the files of a
  saved game on the save disk: the per-character CHRDAT<slot><n>.SAV/.ITM/.SPC files with their
  character (285 bytes), item (63 bytes) and affect (9 bytes) records. The file names are built
  from SaveDir and the game directory, CreateSaveDir makes the save directory on the save disk, and
  the "Put save disk in <drive>:" prompt shows while that disk is missing. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
uses POOLVARS;
procedure ReadSavedCharacterList(var List: PMenuLine);
procedure RewriteSavedCharacterList(List: PMenuLine);
procedure CreateSaveDir;
procedure MergePictureData(Source, Dest: Pointer);
procedure BuildCharacterIcon(Recolor: Boolean);
procedure ovl17_e4;
procedure ovl17_fn_0818;
procedure ovl17_fn_084A;
procedure ovl17_fn_0865;
procedure ovl17_fn_0AE5;
procedure ovl17_e5;
procedure ovl17_fn_0B48;
procedure ovl17_e6(Kind: Byte; Who: Pointer);
procedure ovl17_fn_0F99;
procedure ovl17_e7;
procedure AddPartyMember(Member: PCharacter);
procedure ovl17_e8;
procedure ovl17_e9;
procedure ovl17_e11;
implementation
uses RES04, RES05, RES06, RES07, OVL23, OVL25, OVL32;

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
  menu line per saved character). Called by ovl16's character menu and by ovl17_e4 (save one
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
  menu (ovl16_fn_306D) and by ovl17_e4. }
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
  by ReadSavedCharacterList, RewriteSavedCharacterList, ovl17_e4, ovl17_e8 and ovl17_e9. }
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
  Sel^.Figure[1..6] through ds3CF5 and applies it to both halves of the icon (res07_fn_1E5C).
  Finally it frees slot 11, restores the tile set and flushes the keyboard. Called by the ovl16
  character menus, by ovl17_e7 and by ovl17_e8. }
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
      res07_fn_1E5C(@MapFrom, @MapTo, 0, 0, ds5E5A[CombatIcon].FirstPic);
      res07_fn_1E5C(@MapFrom, @MapTo, 0, 0, ds5E5A[CombatIcon].SecondPic);
    end;
    FreePictureSlot(11);
    RestoreTileSet;
    FlushKeyboard;
  end;
end;
{ ovl17:069E: frame not read }
{@stub} procedure ovl17_e4; begin end;
{ ovl17:0818: frame not read }
{@stub} procedure ovl17_fn_0818; begin end;
{ ovl17:084A: frame not read }
{@stub} procedure ovl17_fn_084A; begin end;
{ ovl17:0865: retf 8: 8 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl17_fn_0865; begin end;
{ ovl17:0AE5: frame not read }
{@stub} procedure ovl17_fn_0AE5; begin end;
{ ovl17:0AEC: frame not read }
{@stub} procedure ovl17_e5; begin end;
{ ovl17:0B48: retf 12: 12 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl17_fn_0B48; begin end;
{ ovl17:0EC4: frame not read }
{@stub} procedure ovl17_e6(Kind: Byte; Who: Pointer); begin end;
{ ovl17:0F99: retf 6: 6 bytes of parameters; 0 bytes of locals }
{@stub} procedure ovl17_fn_0F99; begin end;
{ ovl17:1262: retf 2: 2 bytes of parameters; 18 bytes of locals }
{@stub} procedure ovl17_e7; begin end;
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
{ ovl17:1602: retf 0: 0 bytes of parameters; 1554 bytes of locals }
{@stub} procedure ovl17_e8; begin end;
{ ovl17:1D58: retf 0: 0 bytes of parameters; 1278 bytes of locals }
{@stub} procedure ovl17_e9; begin end;
{ ovl17:22D5: retf 4: 4 bytes of parameters; 342 bytes of locals }
{@stub} procedure ovl17_e11; begin end;

begin
end.
