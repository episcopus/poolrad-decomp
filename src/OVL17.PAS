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
procedure ovl17_e2;
procedure CreateSaveDir;
procedure ovl17_fn_032F;
procedure ovl17_e3;
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
uses RES05, RES06, OVL23, OVL25;

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
{ ovl17:01B8: retf 4: 4 bytes of parameters; 774 bytes of locals }
{@stub} procedure ovl17_e2; begin end;
{ ovl17:02AE. Makes sure the save directory exists on the save disk: MkDir of SaveDir without its
  trailing backslash, and while that fails with anything but success or "already there" it shows
  "Put save disk in <drive>:" (the drive letter SaveDir starts with) and tries again. Reads SaveDir,
  creates the directory on the save disk as a side effect. Called before the save files are touched
  by ReadSavedCharacterList, ovl17_e2, ovl17_e4, ovl17_e8 and ovl17_e9. }
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
{ ovl17:032F: retf 8: 8 bytes of parameters; 6 bytes of locals }
{@stub} procedure ovl17_fn_032F; begin end;
{ ovl17:0482: retf 2: 2 bytes of parameters; 554 bytes of locals }
{@stub} procedure ovl17_e3; begin end;
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
