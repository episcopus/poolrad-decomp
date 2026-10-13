unit OVL11;
{ Loader: the game's start-up (whitepaper 3.2.2). The main program runs StartGame once, before
  the title screens and the copy protection (src/POOL.PAS: `StartGame;`). It allocates the game's
  main heap blocks, sets up the screen buffers (through AllocatePicture), fills the three 200-entry
  cell address tables, initialises the screen and game globals, then builds the save game file path
  and reads its data file (OpenGameFile, Reset/Seek/BlockRead/Close) before handing over to
  ovl22_e10 (the character/party loader) and ovl12_e1 (the training and rewards unit). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure StartGame;
implementation
uses POOLVARS, RES03, RES05, RES06, RES07, OVL12, OVL22, OVL25, OVL32, OVL34;

const
  { The loader fills three tables of 200 cells (indices 0..$C7, ovl11:0130..024D). }
  LastCell = $C7;
  { A text row is 40 characters (the 16-bit wide multiply of ds5050, ovl11:018E). }
  CellsPerRow = $28;
  { The two text scanline video segments and the four graphics planes the cell tables address
    (whitepaper 5.11). }
  TextSegOdd = $BA00;
  TextSegEven = $B800;
  Plane1 = $B800;
  Plane2 = $BA00;
  Plane3 = $BC00;
  Plane4 = $BE00;
  { The loader reads one $810-byte block of the game file (ovl11:05D2). }
  LoadBlockSize = $810;

{ ovl11:002D. The start-up loader. Allocates the game's heap blocks (New at ovl11:0034..00A3: the
  game variables at DS:49D2, a second $800-byte word block at DS:49D6, and the $400, $1E00, $588,
  $924 and $400 byte blocks), then the three screen buffers through AllocatePicture (ovl11:00A4,
  00BC, 00D4), clears the fixed buffers, fills the three cell address tables DS:4EC0 (the text
  scanline address, ovl11:0130), DS:5050 (the row offset I*40, ovl11:0186) and DS:51E0 (the plane
  address used with VideoAdapter 2, ovl11:019F), and finally sets the screen and game globals
  (ovl11:0392..0456). The second half (ovl11:0469..0614) is the save game load: it saves the
  current file path, draws 'Loading...Please Wait' (DrawTextAt), loads the 12 sprites of 'COMSPR'
  through LoadPictureSlot, builds the game file name from the InsertDiskPrompts name table plus the character in
  DS:547D (OpenGameFile opens it), reads one $810-byte block (Reset/Seek/BlockRead/Close,
  ovl11:05A9..05E5), restores the path, randomises the seed (System.Randomize, ovl11:0602) and
  calls ovl22_e10 and ovl12_e1.
  Reads and changes: the globals listed in POOLVARS.PAS (their comments name the write).
  Side effects: the heap, the screen (DrawTextAt, LoadPictureSlot, Load8x8Bank) and the disk (the file
  read). The loop counter is the global DS:465C, reused by the three fill loops. }
procedure StartGame;
begin
  New(GameVars);
  New(ds49D6);
  New(ds49DA);
  New(EclCode);
  New(GameFont);
  New(WallTiles);
  New(ds6A5C);
  AllocatePicture(8, 1, 1, 0, TileBuf);
  AllocatePicture($A8, $15, 1, 0, DrawBuf);
  AllocatePicture($18, 3, 1, 0, ds4A24);
  FillChar(ds4A28, $A8, 0);
  FillChar(ds4AD0, $150, 0);
  FillChar(ds4C20, $150, $FF);
  FillChar(ds4D70, $150, 0);
  for ds465C := 0 to LastCell do
  begin
    if Odd(ds465C) then
      ds4EC0[ds465C] := TextSegOdd + (ds465C div 2) * 5
    else
      ds4EC0[ds465C] := TextSegEven + (ds465C div 2) * 5;
    ds5050[ds465C] := ds465C * CellsPerRow;
    case ds465C mod 4 of
      0: ds51E0[ds465C] := (ds465C div 4) * $A + Plane1;
      1: ds51E0[ds465C] := (ds465C div 4) * $A + Plane2;
      2: ds51E0[ds465C] := (ds465C div 4) * $A + Plane3;
      3: ds51E0[ds465C] := (ds465C div 4) * $A + Plane4;
    end;
  end;
  FillChar(TileBanks, $14, 0);
  FillChar(ds5E52, 8, 0);
  FillChar(GameVars^, $800, 0);
  FillChar(ds49D6^, $800, 0);
  FillChar(ds49DA^, $400, 0);
  FillChar(EclCode^, $1E00, 0);
  FillChar(ds5E5A, $D0, 0);
  for ds465C := 1 to 2 do
  begin
    ds6AFB[ds465C].Kind := $FF;
    ds6AFB[ds465C].Addr := nil;
  end;
  FillChar(PictureAnimation, $42, 0);
  ds6810 := nil;
  FillChar(ds6AAD, 5, 0);
  ds6AAD := $F;
  ds6AAE := 1;
  ds6AAF := 6;
  FillChar(ds6DDE, 3, 1);
  ds6AB2 := 0;
  ds6AB4 := 1;
  for ds465C := 2 to 3 do
  begin
    ds6AAEWords[ds465C].A := $FFFF;
    ds6AAEWords[ds465C].B := $FFFF;
  end;
  ShowPortraits := 1;
  ShowMonsterPics := 1;
  DebugMode := False;
  ds4A00 := 1;
  ds49F8 := 0;
  ds49FB := 0;
  ds5D96 := 0;
  SelectedCharacter := nil;
  EclPC := $9900;
  GameSpeed := 1;
  ds49F4 := 0;
  TileSet := 1;
  ds5377 := 1;
  ds547A := 1;
  ds5378 := 1;
  WallMapMode := 0;
  ds49F9 := 1;
  AreaViewKind := 1;
  ds49D6^[830] := 0;
  MarkerFrame := 0;
  ListMenuTop := 1;
  DuelMode := 0;
  ds6DDA := 0;
  ds84DD := 0;
  ds84DE := 0;
  ds84DF := 0;
  ds84E0 := 0;
  PartyDestroyed := 0;
  ds5370 := 1;
  ds84E3 := 0;
  ds557C := 0;
  ds6B0A := '';
  ds6B1C := $FF;
  ds557D := False;
  ds6F69 := $E8;
  ds6F68 := $DB;
  ds84E9 := 0;
  SoundDriverIdle := 0;
  SetSoundDriverIdle(100);
  { A string assignment to a string[40] truncates to 40 (the compiler uses System_StrLCopy); this
    saves the current path DS:547C into DS:4661. }
  ds4661 := GameDir;
  GameDir := '';
  LoadGameFont;
  ClearPromptLine;
  DrawTextAt(0, $18, $A, 'Loading...Please Wait');
  Load8x8Bank($CA, 4);
  Load8x8Bank($CB, 0);
  LoadPicture('sqrpaci', 1, 0, 0, ds5E52);
  LoadPicture('sqrpaci', 2, 0, 0, ds5E56);
  for ds465C := 0 to $B do
    LoadPictureSlot('COMSPR', ds465C, ds465C + $D);
  LoadPictureSlot('COMSPR', $19, $19);
  ds4660 := OpenGameFile('ITEMS', InsertDiskPrompts[TileSet] + Chr(ds547D) + ':', 0, ds468C);
  Reset(ds468C, 1);
  Seek(ds468C, 2);
  BlockRead(ds468C, ds5582, LoadBlockSize, ds5E1E);
  Close(ds468C);
  { restore the path saved above }
  GameDir := ds4661;
  ClearPromptLine;
  Randomize;
  ovl22_e10;
  ovl12_e1;
end;

{ ovl11:0615. The unit's initialisation part is empty: the compiler emits only `55 89 E5 5D CB`
  (push bp; mov bp, sp; pop bp; retf, the frame with no body), so the loader unit runs no code when
  the program starts; its work happens only when the main program calls StartGame. }
begin
end.
