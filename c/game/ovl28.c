#include "game.h"

/* ovl28:0000. Draws the 8x8 sprite Sprite at column Col and row Row. A nil Sprite draws nothing. When
     Direct is set it blits the sprite one column and one row up and left (Col - 1, Row - 1) onto the
     screen buffer DrawBuf through
     DrawPictureItemClipped (mode 0, the flag 1) and steps the display through FlushPictureChanges; otherwise it
     copies it into the staging buffer with ShowPicture. Called by DrawHeadSprite, DrawBodySprite and
     ShowHeadBodySprites inside this unit, and from ovl03, ShowEncounterPicture, ovl18 and ovl25 (the packet's callers). */
void DrawSprite(s16 Col, s16 Row, u8 Direct, farptr Sprite)
{
  POOL_TRACE("DrawSprite");
  if (Sprite != 0) {
    if (Direct != 0) {
      DrawPictureItemClipped((s16)(Col - 1), (s16)(Row - 1), 0, 1, Sprite, DrawBuf);
      FlushPictureChanges();
    } else {
      ShowPicture(Col, Row, Sprite);
    }
  }
}

/* ovl28:0050. Draws the 8x8 sprite Sprite of a bank at column Col and row Row without an offset
     (through DrawSprite, the staging buffer path). Called by ShowHeadBodySprites. */
void DrawHeadSprite(u8 Col, u8 Row, farptr Sprite)
{
  POOL_TRACE("DrawHeadSprite");
  DrawSprite(Col, Row, 0, Sprite);
}

/* ovl28:0070. Draws the 8x8 sprite Sprite at column Col and row Row plus 5 (through DrawSprite, the
     staging buffer path). Called by ShowHeadBodySprites. */
void DrawBodySprite(u8 Col, u8 Row, farptr Sprite)
{
  POOL_TRACE("DrawBodySprite");
  DrawSprite(Col, (s16)(Row + 5), 0, Sprite);
}

/* ovl28:00A2. Loads the sprite pictures of block Bank of the DAX file <Name><TileSet>.dax (for
     example PIC or FINAL, ovl18 passes 'FINAL') into the sprite list List^, unless that file and block
     are already loaded (the name and block of the last load are kept in LastSpriteFile and LastSpriteBank). The test
     compares Name and Bank only, not the TileSet digit, so a TileSet change with the same name and
     block does not reload. It frees the old list first (FreeSpriteList), reads the block (LoadDaxBlock)
     and walks it: a count byte (at most PicBlock1Sprites for PIC block 1), then per sprite 4 bytes into
     the slot, the Height and WidthCols words, and when at least FreeMemoryFloor bytes of heap are free
     (MaxAvail) it allocates the picture (AllocatePicture(Height, WidthCols, 1, Mode, slot)), reads its X
     and Y words (one byte after Y is skipped) and 8 palette bytes, and decodes Row + 1 bytes of pixel
     data (UnpackPicturePixels), Row being the picture's ByteSize (twice the byte size when VideoAdapter is 0)
     minus one. PIC and FINAL pictures are stored as differences: the first picture's data is kept in
     Prev and every later picture's bytes are xored with it before decoding. When bit 0 of Mode is set
     and VideoAdapter is not 0, the picture also goes through RemapPictureColors with the two 16-byte tables
     SpriteRemapFrom and SpriteRemapTo. Frees Prev and the block at the end and calls FlushKeyboard (which does nothing,
     QUIRK 0899:010A).
     QUIRK ovl28:0269: when MaxAvail is below FreeMemoryFloor the jump to the loop end skips not only
     the allocation but also the offset advance past the sprite's X, Y, skipped byte, palette and
     Row + 1 pixel bytes, so every later sprite of the block is read from the middle of the skipped one
     (and every later offset is wrong). List^.Count still becomes the number loaded (Loaded), but the
     slots keep the index I: a skipped slot stays nil below Count and a loaded slot sits above it.
     QUIRK ovl28:046C: the final FreeMem(Prev, Row + 1) frees with the last picture's Row, not the
     first picture's size Prev was allocated with (FreeMem ignores the size, so it is harmless).
     Note ovl28:00D9: FreeSpriteList is passed @List^ (les/push es/push di), the same pointer as List.
     Parameters: Name (the file base name), Bank (the DAX block), Mode (passed on to the allocator and
     the decoder; bit 0 enables RemapPictureColors), List (the sprite list to fill). Side effects: the heap,
     LastSpriteFile, LastSpriteBank. Callers: ovl03:0856, ShowEncounterPicture, ovl18:0006, RedrawView (packet). */
void LoadSpriteList(const u8 *Name_in, u8 Bank, u8 Mode, PSpriteList List)
{
  POOL_TRACE("LoadSpriteList");
  const u8 *Name = Name_in;
  u16 Size = 0;
  farptr Block = 0;
  u16 Offset = 0;
  u8 I = 0;
  u16 Height = 0;
  u16 WidthCols = 0;
  u8 Digit[2] = {0};
  PByteArray_RES07 Prev = 0;
  u16 J = 0;
  u16 Row = 0;
  u8 IsPicOrFinal = 0;
  u8 PrevAllocated = 0;
  u8 Loaded = 0;
  u8 t1[10];
  if (((rtl_str_cmp(Name, LastSpriteFile) == 0)) && ((Bank == LastSpriteBank))) {
    return;
  }
  FreeSpriteList(rtl_far(&(*FPD(TSpriteList (*), List))));
  rtl_str_assign(LastSpriteFile, 8, Name);
  LastSpriteBank = Bank;
  IsPicOrFinal = (((rtl_str_cmp(Name, S("\003PIC")) == 0)) || ((rtl_str_cmp(Name, S("\005FINAL")) == 0)));
  rtl_str_int(Digit, 1, TileSet, 0);
  LoadDaxBlock(rtl_str_cat(t1, 2, (const u8 *const[]){Name, Digit}), S("\004.dax"), Bank, &Size, &Block);
  if (Size == 0) {
    return;
  }
  Offset = 0;
  PrevAllocated = 0;
  {
    TSpriteList *w1 = &(*FPD(TSpriteList (*), List));
      w1->Count = (*FPD(TByteArray_RES07 (*), Block))[Offset];
      if ((((rtl_str_cmp(Name, S("\003PIC")) == 0)) && ((Bank == 1))) && ((w1->Count > PicBlock1Sprites))) {
        w1->Count = PicBlock1Sprites;
      }
      Offset++;
      w1->Flag = 1;
      Loaded = 0;
      {
        u8 limit = w1->Count;
        if (1 <= limit) {
          I = 1;
          for (;;) {
              rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), Block))[Offset], (void *)&w1->Slots[I - 1].Data, 4);
              Offset += 4;
              rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), Block))[Offset], (void *)&Height, 2);
              Offset += 2;
              rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), Block))[Offset], (void *)&WidthCols, 2);
              Offset += 2;
              if (rtl_MaxAvail() >= FreeMemoryFloor) {
                Loaded++;
                AllocatePicture(Height, WidthCols, 1, Mode, (void *)&w1->Slots[I - 1].Sprite);
                {
                  TSpritePicture *w2 = &(*FPD(TSpritePicture (*), w1->Slots[I - 1].Sprite));
                    rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), Block))[Offset], (void *)&w2->X, 2);
                    Offset += 2;
                    rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), Block))[Offset], (void *)&w2->Y, 2);
                    Offset += 3;
                    rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), Block))[Offset], (void *)&w2->Palette, 8);
                    Offset += 8;
                }
                if (VideoAdapter == AdapterCga) {
                  Row = ((*FPD(TSpritePicture (*), w1->Slots[I - 1].Sprite)).ByteSize * 2) - 1;
                } else {
                  Row = (*FPD(TSpritePicture (*), w1->Slots[I - 1].Sprite)).ByteSize - 1;
                }
                if (IsPicOrFinal) {
                  if (I == 1) {
                    Prev = rtl_getmem((u16)(Row + 1));
                    rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), Block))[Offset], (void *)&(*FPD(TByteArray_RES07 (*), Prev)), (u16)(Row + 1));
                    PrevAllocated = 1;
                  } else {
                    {
                      u16 limit = (u16)(Offset + Row);
                      u16 first = Offset;
                      if (first <= limit) {
                        J = first;
                        for (;;) {
                            (*FPD(TByteArray_RES07 (*), Block))[J] = ((*FPD(TByteArray_RES07 (*), Block))[J] ^ (*FPD(TByteArray_RES07 (*), Prev))[(u16)(J - Offset)]);
                          if (J == limit) break;
                          J++;
                        }
                      }
                    }
                  }
                }
                UnpackPicturePixels(Block, Offset, Mode, 0, w1->Slots[I - 1].Sprite);
                if (((((Mode & 1)) > 0)) && ((VideoAdapter != AdapterCga))) {
                  RemapPictureColors(rtl_far(&SpriteRemapFrom), rtl_far(&SpriteRemapTo), 0, 0, w1->Slots[I - 1].Sprite);
                }
                Offset += (u16)(Row + 1);
              }
            if (I == limit) break;
            I++;
          }
        }
      }
      w1->Count = Loaded;
  }
  if (IsPicOrFinal && PrevAllocated) {
    rtl_freemem(Prev, (u16)(Row + 1));
  }
  rtl_freemem(Block, Size);
  FlushKeyboard();
}

/* ovl28:048F. Frees the sprite list Rec^: it frees the picture of every used slot (through
     ReleasePicture), then zeroes the whole SizeOf(TSpriteList)-byte record, clears the picture name
     DS:6B0A and sets the current bank DS:6B1C to NoBank. Called by ovl10, ovl14, ovl18 and
     LoadSpriteList. */
void FreeSpriteList(PSpriteList Rec)
{
  POOL_TRACE("FreeSpriteList");
  {
    TSpriteList *w1 = &(*FPD(TSpriteList (*), Rec));
      {
        s8 limit = w1->Count;
        if (1 <= limit) {
          SharedLoopIndex = 1;
          for (;;) {
              ReleasePicture((void *)&w1->Slots[SharedLoopIndex - 1].Sprite);
            if (SharedLoopIndex == limit) break;
            SharedLoopIndex++;
          }
        }
      }
  }
  rtl_FillChar((void *)&(*FPD(TSpriteList (*), Rec)), 66, 0);
  rtl_str_assign(LastSpriteFile, 8, S("\000"));
  LastSpriteBank = NoBank;
}

/* ovl28:04F9. Shows the HEAD/BODY picture window of the character screen: when the character record
     DS:5D92 has both a HEAD and a BODY picture bank it draws the window (columns 28..38, rows 1..11)
     and loads and shows the HEAD and BODY sprites of those banks. Does nothing when either bank is 0.
     QUIRK ovl28:056C, ovl28:0593: the two Str() calls into V1 and V2 are computed and never read
     (a port may drop them). Called by ovl16:33E7 and ovl19:031E. */
void ShowHeadBodyWindow(void)
{
  POOL_TRACE("ShowHeadBodyWindow");
  u8 V1[4] = {0};
  u8 V2[4] = {0};
  if ((((*FPD(TCharacter (*), SelectedCharacter)).HeadBank == 0)) || (((*FPD(TCharacter (*), SelectedCharacter)).BodyBank == 0))) {
    return;
  }
  DrawWindow(0x1C, 1, 0x26, 0xB, 0, 0, S("\000"));
  {
    TCharacter *w1 = &(*FPD(TCharacter (*), SelectedCharacter));
      rtl_str_int(V1, 3, HeadPictureNumbers[w1->HeadBank], 0);
      rtl_str_int(V2, 3, BodyPictureNumbers[w1->BodyBank], 0);
      LoadHeadBodySprites(HeadPictureNumbers[w1->HeadBank], BodyPictureNumbers[w1->BodyBank]);
  }
  ShowHeadBodySprites(0x1C, 1, 1);
}

/* ovl28:05D9. Loads the HEAD and the BODY 8x8 sprite bank for the picture number TileSet: for each
     bank that is asked for (not NoBank) and not already loaded (DS:6B00, DS:6B05) it loads the picture
     through LoadPicture from the file HEAD<number> or BODY<number> into DS:6B01 or DS:6B06, then
     records the loaded number. Calls FlushKeyboard at the end, which does nothing (QUIRK 0899:010A).
     Called by ShowHeadBody, ShowHeadBodyWindow and RedrawView. */
void LoadHeadBodySprites(u8 HeadBank, u8 BodyBank)
{
  POOL_TRACE("LoadHeadBodySprites");
  u8 Num[2] = {0};
  u8 t1[6];
  u8 t2[6];
  rtl_str_int(Num, 1, TileSet, 0);
  if (HeadBank != NoBank) {
    if (((HeadBankIndex == NoBank)) || ((HeadBankIndex != HeadBank))) {
      LoadPicture(rtl_str_cat(t1, 2, (const u8 *const[]){S("\004HEAD"), Num}), HeadBank, 0, 0, (void *)&HeadSpriteBank);
      HeadBankIndex = HeadBank;
    }
  }
  if (BodyBank != NoBank) {
    if (((BodyBankIndex == NoBank)) || ((BodyBankIndex != BodyBank))) {
      LoadPicture(rtl_str_cat(t2, 2, (const u8 *const[]){S("\004BODY"), Num}), BodyBank, 0, 0, (void *)&BodySpriteBank);
      BodyBankIndex = BodyBank;
    }
  }
  FlushKeyboard();
}

/* ovl28:0697. Shows the HEAD/BODY sprites of the character screen at column Col and row Row. Both
     arms draw through the staging buffer (DrawHeadSprite and DrawBodySprite pass Direct 0 to
     DrawSprite): when WithBody is not 0 it draws the HEAD sprite DS:6B01 and the BODY sprite DS:6B06
     (5 rows lower), otherwise only the HEAD sprite. WithBody is not a Direct flag; every path goes
     through ShowPicture. Called by ShowHeadBody, RedrawView and ShowHeadBodyWindow. */
void ShowHeadBodySprites(u8 Col, u8 Row, u8 WithBody)
{
  POOL_TRACE("ShowHeadBodySprites");
  if (WithBody != 0) {
    DrawHeadSprite(Col, Row, HeadSpriteBank);
    DrawBodySprite(Col, Row, BodySpriteBank);
  } else {
    DrawSprite(Col, Row, 0, HeadSpriteBank);
  }
}

/* ovl28:0708. Copies the sprite list Rec^ into a local record and shows slot Slot (only 1..3 are
     legal; another slot restores the saved video mode with RestoreVideoMode, which calls
     SetVideoMode(SavedVideoMode) so the range message is readable, then ends the game with
     'Illegal range in Show3DSprite.'): the sprite is drawn at its base column and row plus 2 (X + 3 -
     1, Y + 3 - 1) through DrawPictureItemClipped onto the screen buffer DrawBuf and the display is stepped.
     A nil slot leaves early. Called by ShowEncounterPicture. */
void Show3DSprite(u8 Slot, PSpriteList Rec)
{
  POOL_TRACE("Show3DSprite");
  TSpriteList List = {0};
  List = (*FPD(TSpriteList (*), Rec));
  if (((Slot < 1)) || ((Slot > Last3DSpriteSlot))) {
    RestoreVideoMode();
    rtl_write_str(&Output, S("\036Illegal range in Show3DSprite."), 0), rtl_write_ln(&Output);
    QuitGame();
  }
  if (List.Slots[Slot - 1].Sprite != 0) {
    {
      TSpritePicture *w1 = &(*FPD(TSpritePicture (*), List.Slots[Slot - 1].Sprite));
        DrawPictureItemClipped((u16)((w1->X + 3) - 1), (u16)((w1->Y + 3) - 1), 0, 1, List.Slots[Slot - 1].Sprite, DrawBuf);
    }
  } else {
    return;
  }
  FlushPictureChanges();
}

/* Initialisation part of unit OVL28. */
void init_OVL28(void)
{
  POOL_TRACE("init");
}
