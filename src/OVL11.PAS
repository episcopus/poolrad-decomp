unit OVL11;
{ Loader: the game's start-up (whitepaper 3.2.2). The main program runs StartGame once, before
  the title screens and the copy protection (src/POOL.PAS: `StartGame;`). It allocates the game's
  main heap blocks, sets up the screen buffers (through AllocatePicture), fills the three 200-entry
  cell address tables, initialises the screen and game globals, then builds the save game file path
  and reads its data file (OpenGameFile, Reset/Seek/BlockRead/Close) before handing over to
  InitSpellHandlers (which fills the spell cast handler table) and InitAffectHandlers (the training and
  rewards unit). }
{$A-,O+,F+,S-,R-,G-,I-}
interface
procedure StartGame;
implementation
uses POOLVARS, RES03, RES05, RES06, RES07, OVL12, OVL22, OVL25, OVL32, OVL34;

const
  { The loader fills three tables of 200 pixel scanlines (indices 0..$C7, ovl11:0130..024D). }
  LastScanline = $C7;
  { An EGA scanline is 40 bytes (the 16-bit wide multiply of EgaScanlineOffsets, ovl11:018E). }
  BytesPerEgaScanline = $28;
  { The two text scanline video segments and the four Tandy banks the scanline tables address
    (whitepaper 5.11). }
  TextSegOdd = $BA00;
  TextSegEven = $B800;
  TandyBank0 = $B800;
  TandyBank1 = $BA00;
  TandyBank2 = $BC00;
  TandyBank3 = $BE00;
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
  calls InitSpellHandlers and InitAffectHandlers.
  Reads and changes: the globals listed in POOLVARS.PAS (their comments name the write).
  Side effects: the heap, the screen (DrawTextAt, LoadPictureSlot, Load8x8Bank) and the disk (the file
  read). The loop counter is the global DS:465C, reused by the three fill loops. }
procedure StartGame;
begin
  New(GameVars);
  New(GameVars2);
  New(GameVars3);
  New(EclCode);
  New(GameFont);
  New(WallTiles);
  New(GeoBlock);
  AllocatePicture(8, 1, 1, 0, TileBuf);
  AllocatePicture($A8, $15, 1, 0, DrawBuf);
  AllocatePicture($18, 3, 1, 0, IconBackgroundBuffer);
  FillChar(RowDirtyFlags, $A8, 0);
  FillChar(RowFirstChangedCol, $150, 0);
  FillChar(RowFirstChangedOfs, $150, $FF);
  FillChar(RowLastChangedOfs, $150, 0);
  for LoaderLoopIndex := 0 to LastScanline do
  begin
    if Odd(LoaderLoopIndex) then
      CgaScanlineSegments[LoaderLoopIndex] := TextSegOdd + (LoaderLoopIndex div 2) * 5
    else
      CgaScanlineSegments[LoaderLoopIndex] := TextSegEven + (LoaderLoopIndex div 2) * 5;
    EgaScanlineOffsets[LoaderLoopIndex] := LoaderLoopIndex * BytesPerEgaScanline;
    case LoaderLoopIndex mod 4 of
      0: TandyScanlineSegments[LoaderLoopIndex] := (LoaderLoopIndex div 4) * $A + TandyBank0;
      1: TandyScanlineSegments[LoaderLoopIndex] := (LoaderLoopIndex div 4) * $A + TandyBank1;
      2: TandyScanlineSegments[LoaderLoopIndex] := (LoaderLoopIndex div 4) * $A + TandyBank2;
      3: TandyScanlineSegments[LoaderLoopIndex] := (LoaderLoopIndex div 4) * $A + TandyBank3;
    end;
  end;
  FillChar(TileBanks, $14, 0);
  FillChar(SqrPaciBank1, 8, 0);
  FillChar(GameVars^, $800, 0);
  FillChar(GameVars2^, $800, 0);
  FillChar(GameVars3^, $400, 0);
  FillChar(EclCode^, $1E00, 0);
  FillChar(PictureSlots, $D0, 0);
  for LoaderLoopIndex := 1 to 2 do
  begin
    LoadSlots[LoaderLoopIndex].Kind := $FF;
    LoadSlots[LoaderLoopIndex].Addr := nil;
  end;
  FillChar(PictureAnimation, $42, 0);
  PooledItems := nil;
  FillChar(PartyMapColumn, 5, 0);
  PartyMapColumn := $F;
  PartyMapRow := 1;
  PartyFacing := 6;
  FillChar(DoorMenuFlags, 3, 1);
  UnreadWord6AB2 := 0;
  UnreadWord6AB4 := 1;
  for LoaderLoopIndex := 2 to 3 do
  begin
    WallSetSlotPairs[LoaderLoopIndex].A := $FFFF;
    WallSetSlotPairs[LoaderLoopIndex].B := $FFFF;
  end;
  ShowPortraits := 1;
  ShowMonsterPics := 1;
  DebugMode := False;
  DelayPerGlyph := 1;
  SkipAreaScriptLoad := 0;
  RestInterruptCounter := 0;
  PartyListHead := 0;
  SelectedCharacter := nil;
  EclPC := $9900;
  GameSpeed := 1;
  SuppressContinuePrompt := 0;
  TileSet := 1;
  SavedTileSet := 1;
  UnreadWord547A := 1;
  UnreadWord5378 := 1;
  WallMapMode := 0;
  PreviousAreaViewKind := 1;
  AreaViewKind := 1;
  GameVars2^[830] := 0;
  MarkerFrame := 0;
  ListMenuTop := 1;
  DuelMode := 0;
  RestWindowActive := 0;
  SavedSearchMode := 0;
  GlyphRunInBox := 0;
  GlyphRunPending := 0;
  CloseUpShown := 0;
  PartyDestroyed := 0;
  ClipChecksEnabled := 1;
  Sprite3DLoaded := 0;
  OpenNoPrompt := 0;
  LastSpriteFile := '';
  LastSpriteBank := $FF;
  HeapErrorStop := False;
  SpecialViewCode1 := $E8;
  SpecialViewCode2 := $DB;
  SkipCloseUpIfNoPics := 0;
  SoundDriverIdle := 0;
  SetSoundDriverIdle(100);
  { A string assignment to a string[40] truncates to 40 (the compiler uses System_StrLCopy); this
    saves the current path DS:547C into DS:4661. }
  GameDirBackup := GameDir;
  GameDir := '';
  LoadGameFont;
  ClearPromptLine;
  DrawTextAt(0, $18, $A, 'Loading...Please Wait');
  Load8x8Bank($CA, 4);
  Load8x8Bank($CB, 0);
  LoadPicture('sqrpaci', 1, 0, 0, SqrPaciBank1);
  LoadPicture('sqrpaci', 2, 0, 0, SqrPaciBank2);
  for LoaderLoopIndex := 0 to $B do
    LoadPictureSlot('COMSPR', LoaderLoopIndex, LoaderLoopIndex + $D);
  LoadPictureSlot('COMSPR', $19, $19);
  LoaderOpenResult := OpenGameFile('ITEMS', InsertDiskPrompts[TileSet] + Chr(DiskDriveLetter) + ':', 0, LoaderFile);
  Reset(LoaderFile, 1);
  Seek(LoaderFile, 2);
  BlockRead(LoaderFile, ItemTable, LoadBlockSize, LoaderReadCount);
  Close(LoaderFile);
  { restore the path saved above }
  GameDir := GameDirBackup;
  ClearPromptLine;
  Randomize;
  InitSpellHandlers;
  InitAffectHandlers;
end;

{ ovl11:0615. The unit's initialisation part is empty: the compiler emits only `55 89 E5 5D CB`
  (push bp; mov bp, sp; pop bp; retf, the frame with no body), so the loader unit runs no code when
  the program starts; its work happens only when the main program calls StartGame. }
begin
end.
