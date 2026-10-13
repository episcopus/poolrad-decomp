unit OVL17;
{ SaveLoad: the save and load unit (whitepaper 4.4). Its entry points write and read the files of a
  saved game on the save disk: the per-character CHRDAT<slot><n>.SAV/.ITM/.SPC files with their
  character (285 bytes), item (63 bytes) and affect (9 bytes) records. The file names are built
  from SaveDir and the game directory, CreateSaveDir makes the save directory on the save disk, and
  the "Put save disk in <drive>:" prompt shows while that disk is missing. }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure ovl17_e1;
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
procedure ovl17_e10;
procedure ovl17_e8;
procedure ovl17_e9;
procedure ovl17_e11;
implementation
uses POOLVARS, RES06;

const
  Yellow = $0E;        { EGA text colour of the disk prompt (the message colour OVL00 also uses) }
  IoSuccess = 0;       { IOResult of a MkDir that created the directory }
  IoDirExists = 5;     { IOResult of a MkDir when the directory is already there (DOS access denied) }

{ ovl17:0010: retf 4: 4 bytes of parameters; 524 bytes of locals }
{@stub} procedure ovl17_e1; begin end;
{ ovl17:01B8: retf 4: 4 bytes of parameters; 774 bytes of locals }
{@stub} procedure ovl17_e2; begin end;
{ ovl17:02AE. Makes sure the save directory exists on the save disk: MkDir of SaveDir without its
  trailing backslash, and while that fails with anything but success or "already there" it shows
  "Put save disk in <drive>:" (the drive letter SaveDir starts with) and tries again. Reads SaveDir,
  creates the directory on the save disk as a side effect. Called before the save files are touched
  by ovl17_e1, ovl17_e2, ovl17_e4, ovl17_e8 and ovl17_e9. }
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
{ ovl17:1446: retf 4: 4 bytes of parameters; 16 bytes of locals }
{@stub} procedure ovl17_e10; begin end;
{ ovl17:1602: retf 0: 0 bytes of parameters; 1554 bytes of locals }
{@stub} procedure ovl17_e8; begin end;
{ ovl17:1D58: retf 0: 0 bytes of parameters; 1278 bytes of locals }
{@stub} procedure ovl17_e9; begin end;
{ ovl17:22D5: retf 4: 4 bytes of parameters; 342 bytes of locals }
{@stub} procedure ovl17_e11; begin end;

begin
end.
