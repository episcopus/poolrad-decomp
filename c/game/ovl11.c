#include "game.h"

/* ovl11:002D. The start-up loader. Allocates the game's heap blocks (New at ovl11:0034..00A3: the
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
     read). The loop counter is the global DS:465C, reused by the three fill loops. */
void StartGame(void)
{
  POOL_TRACE("StartGame");
  u8 ts1[2];
  u8 ts2[32];
  GameVars = rtl_getmem(2048);
  GameVars2 = rtl_getmem(2048);
  GameVars3 = rtl_getmem(1024);
  EclCode = rtl_getmem(7680);
  GameFont = rtl_getmem(1416);
  WallTiles = rtl_getmem(2340);
  GeoBlock = rtl_getmem(1024);
  AllocatePicture(8, 1, 1, 0, (void *)&TileBuf);
  AllocatePicture(0xA8, 0x15, 1, 0, (void *)&DrawBuf);
  AllocatePicture(0x18, 3, 1, 0, (void *)&IconBackgroundBuffer);
  rtl_FillChar((void *)&RowDirtyFlags, 0xA8, 0);
  rtl_FillChar((void *)&RowFirstChangedCol, 0x150, 0);
  rtl_FillChar((void *)&RowFirstChangedOfs, 0x150, 0xFF);
  rtl_FillChar((void *)&RowLastChangedOfs, 0x150, 0);
  {
    if (0 <= LastScanline) {
      LoaderLoopIndex = 0;
      for (;;) {
          if (LoaderLoopIndex & 1) {
            CgaScanlineSegments[LoaderLoopIndex] = TextSegOdd + (((LoaderLoopIndex / 2)) * 5);
          } else {
            CgaScanlineSegments[LoaderLoopIndex] = TextSegEven + (((LoaderLoopIndex / 2)) * 5);
          }
          EgaScanlineOffsets[LoaderLoopIndex] = LoaderLoopIndex * BytesPerEgaScanline;
          switch ((LoaderLoopIndex % 4)) {
          case 0:
          {
            TandyScanlineSegments[LoaderLoopIndex] = (((LoaderLoopIndex / 4)) * 0xA) + TandyBank0;
            break;
          }
          case 1:
          {
            TandyScanlineSegments[LoaderLoopIndex] = (((LoaderLoopIndex / 4)) * 0xA) + TandyBank1;
            break;
          }
          case 2:
          {
            TandyScanlineSegments[LoaderLoopIndex] = (((LoaderLoopIndex / 4)) * 0xA) + TandyBank2;
            break;
          }
          case 3:
          {
            TandyScanlineSegments[LoaderLoopIndex] = (((LoaderLoopIndex / 4)) * 0xA) + TandyBank3;
            break;
          }
          }
        if (LoaderLoopIndex == LastScanline) break;
        LoaderLoopIndex++;
      }
    }
  }
  rtl_FillChar((void *)&TileBanks, 0x14, 0);
  rtl_FillChar((void *)&SqrPaciBank1, 8, 0);
  rtl_FillChar((void *)&(*FPD(TGameVars (*), GameVars)), 0x800, 0);
  rtl_FillChar((void *)&(*FPD(TGameVars (*), GameVars2)), 0x800, 0);
  rtl_FillChar((void *)&(*FPD(TBlock400 (*), GameVars3)), 0x400, 0);
  rtl_FillChar((void *)&(*FPD(TEclCode (*), EclCode)), 0x1E00, 0);
  rtl_FillChar((void *)&PictureSlots, 0xD0, 0);
  {
    if (1 <= 2) {
      LoaderLoopIndex = 1;
      for (;;) {
          LoadSlots[LoaderLoopIndex].Kind = 0xFF;
          LoadSlots[LoaderLoopIndex].Addr = 0;
        if (LoaderLoopIndex == 2) break;
        LoaderLoopIndex++;
      }
    }
  }
  rtl_FillChar((void *)&PictureAnimation, 0x42, 0);
  PooledItems = 0;
  rtl_FillChar((void *)&PartyMapColumn, 5, 0);
  PartyMapColumn = 0xF;
  PartyMapRow = 1;
  PartyFacing = 6;
  rtl_FillChar((void *)&DoorMenuFlags, 3, 1);
  UnreadWord6AB2 = 0;
  UnreadWord6AB4 = 1;
  {
    if (2 <= 3) {
      LoaderLoopIndex = 2;
      for (;;) {
          WallSetSlotPairs[LoaderLoopIndex].A = 0xFFFF;
          WallSetSlotPairs[LoaderLoopIndex].B = 0xFFFF;
        if (LoaderLoopIndex == 3) break;
        LoaderLoopIndex++;
      }
    }
  }
  ShowPortraits = 1;
  ShowMonsterPics = 1;
  DebugMode = 0;
  DelayPerGlyph = 1;
  SkipAreaScriptLoad = 0;
  RestInterruptCounter = 0;
  PartyListHead = 0;
  SelectedCharacter = 0;
  EclPC = 0x9900;
  GameSpeed = 1;
  SuppressContinuePrompt = 0;
  TileSet = 1;
  SavedTileSet = 1;
  UnreadWord547A = 1;
  UnreadWord5378 = 1;
  WallMapMode = 0;
  PreviousAreaViewKind = 1;
  AreaViewKind = 1;
  (*FPD(TGameVars (*), GameVars2))[830] = 0;
  MarkerFrame = 0;
  ListMenuTop = 1;
  DuelMode = 0;
  RestWindowActive = 0;
  SavedSearchMode = 0;
  GlyphRunInBox = 0;
  GlyphRunPending = 0;
  CloseUpShown = 0;
  PartyDestroyed = 0;
  ClipChecksEnabled = 1;
  Sprite3DLoaded = 0;
  OpenNoPrompt = 0;
  rtl_str_assign(LastSpriteFile, 8, S("\000"));
  LastSpriteBank = 0xFF;
  HeapErrorStop = 0;
  SpecialViewCode1 = 0xE8;
  SpecialViewCode2 = 0xDB;
  SkipCloseUpIfNoPics = 0;
  SoundDriverIdle = 0;
  SetSoundDriverIdle(100);
  /* A string assignment to a string[40] truncates to 40 (the compiler uses System_StrLCopy); this
     saves the current path DS:547C into DS:4661. */
  rtl_str_assign(GameDirBackup, 40, GameDir);
  rtl_str_assign(GameDir, 255, S("\000"));
  LoadGameFont();
  ClearPromptLine();
  DrawTextAt(0, 0x18, 0xA, S("\025Loading...Please Wait"));
  Load8x8Bank(0xCA, 4);
  Load8x8Bank(0xCB, 0);
  LoadPicture(S("\007sqrpaci"), 1, 0, 0, (void *)&SqrPaciBank1);
  LoadPicture(S("\007sqrpaci"), 2, 0, 0, (void *)&SqrPaciBank2);
  {
    if (0 <= 0xB) {
      LoaderLoopIndex = 0;
      for (;;) {
          LoadPictureSlot(S("\006COMSPR"), LoaderLoopIndex, (s16)(LoaderLoopIndex + 0xD));
        if (LoaderLoopIndex == 0xB) break;
        LoaderLoopIndex++;
      }
    }
  }
  LoadPictureSlot(S("\006COMSPR"), 0x19, 0x19);
  LoaderOpenResult = OpenGameFile(S("\005ITEMS"), rtl_str_cat(ts2, 3, (const u8 *const[]){InsertDiskPrompts[TileSet], rtl_str_char(ts1, (u8)DiskDriveLetter), S("\001:")}), 0, (void *)&LoaderFile);
  rtl_reset(&LoaderFile, 1);
  rtl_seek(&LoaderFile, 2);
  rtl_blockread(&LoaderFile, (void *)&ItemTable, LoadBlockSize, &LoaderReadCount);
  rtl_close(&LoaderFile);
  /* restore the path saved above */
  rtl_str_assign(GameDir, 255, GameDirBackup);
  ClearPromptLine();
  rtl_Randomize();
  InitSpellHandlers();
  InitAffectHandlers();
}

/* Initialisation part of unit OVL11. */
void init_OVL11(void)
{
  POOL_TRACE("init");
  /* ovl11:0615. The unit's initialisation part is empty: the compiler emits only `55 89 E5 5D CB`
     (push bp; mov bp, sp; pop bp; retf, the frame with no body), so the loader unit runs no code when
     the program starts; its work happens only when the main program calls StartGame. */
}
