#include "game.h"

/* 0464:0000: retf 6: one Byte and one LongInt parameter; 6 bytes of locals.
     Returns a bit mask of the eight nibbles of Data (four bytes) that equal Color:
     bit 7 is the high nibble of Data[0], bit 0 the low nibble of Data[3]. */
u8 ColorMatchMask(u8 Color, s32 Data)
{
  POOL_TRACE("ColorMatchMask");
  u8 Result = 0;
  u8 (*CellBytes)[4] = (u8 (*)[4])&Data;
  u8 Sum = 0;
  u8 Target = 0;
  u8 Mask = 0;
  u8 I = 0;
  Sum = 0;
  Target = Color << 4;
  Mask = 0x80;
  {
    if (0 <= 3) {
      I = 0;
      for (;;) {
          if ((((*CellBytes)[I] & 0xF0)) == Target) {
            Sum += Mask;
          }
          Mask = (s16)((u16)Mask >> 1);
          if ((((*CellBytes)[I] & 0xF)) == Color) {
            Sum += Mask;
          }
          Mask = (s16)((u16)Mask >> 1);
        if (I == 3) break;
        I++;
      }
    }
  }
  Result = Sum;
  return Result;
}

/* 0464:007B: retf 6: a palette pointer and a nibble index. Copies the eight
     palette bytes to a local and returns the palette colour for pixel value Index:
     even Index takes the high nibble, odd Index the low nibble of Pal[Index shr 1]. */
u8 PaletteColor(u8 Index, PPalette Source)
{
  POOL_TRACE("PaletteColor");
  u8 Result = 0;
  TPalette Pal = {0};
  memcpy(Pal, (*FPD(TPalette (*), Source)), 8);
  if (Index & 1) {
    Result = (Pal[(s16)((u16)Index >> 1)] & 0xF);
  } else {
    Result = (s16)((u16)((Pal[(s16)((u16)Index >> 1)] & 0xF0)) >> 4);
  }
  return Result;
}

/* 0464:00CF: sets video mode A through INT 10h function 0, the way the game
     changes the mode: the mode that was current (CurrentVideoMode) is kept in
     SavedVideoMode, then CurrentVideoMode becomes A. res08_init sets the mode of the adapter kind: $0D EGA, 9 Tandy, 4
     CGA. Called by
     res08_init and by RestoreVideoMode, so the two calls swap the modes [I]. */
void SetVideoMode(u8 Mode)
{
  POOL_TRACE("SetVideoMode");
  u8 UnusedMode = 0;
  SavedVideoMode = CurrentVideoMode;
  Regs.AH = 0;
  Regs.AL = Mode;
  rtl_Intr(0x10, &Regs);
  CurrentVideoMode = Mode;
}

/* 0464:00FF: SetVideoMode(SavedVideoMode). Because SetVideoMode saves the current mode first, the call swaps the two
     modes: the first
     call goes back to the DOS text mode and leaves the game mode saved, a second call returns to the game mode [I].
     Callers are the
     loaders (ovl28, ovl29, ovl32, ovl34) and res08_init just before an error message, which they show in text mode; the pattern
     RestoreVideoMode, message, key, RestoreVideoMode, QuitGame ends with QuitGame setting the DOS mode. QUIRK [I]: a
     lone call before
     QuitGame would leave the game mode saved (not run in the oracle). */
void RestoreVideoMode(void)
{
  POOL_TRACE("RestoreVideoMode");
  SetVideoMode(SavedVideoMode);
}

/* 0464:0111: loads DAX picture block A of the set Text (with the '.dax'
     extension) into the caller's picture pointer: frees any picture already there,
     copies the header fields into locals, AllocatePicture (B = the pixel-buffer
     flag), stores the X/Y position and palette into the new picture, unpacks the
     pixels through 02A5 (C = the colour key, offset $11 = the pixel data), frees
     the DAX block and flushes the keyboard. Target is untyped so ovl32, ovl34,
     ovl28 and ovl11 can each pass their own pointer variable. */
void LoadPicture(const u8 *Text_in, u8 BlockId, u8 AllocFlags, u8 Color, void *Target)
{
  POOL_TRACE("LoadPicture");
  const u8 *Text = Text_in;
  u16 DaxHeight = 0;
  u16 DaxWidthCols = 0;
  u16 DaxXPos = 0;
  u16 DaxYPos = 0;
  u8 DaxItemCount = 0;
  TPalette DaxPalette = {0};
  u16 Size = 0;
  u16 PixelOfs = 0;
  farptr Block = 0;
  u8 Unused = 0;
  if ((*(farptr (*))Target) != 0) {
    ReleasePicture((void *)Target);
  }
  LoadDaxBlock(Text, S("\004.dax"), BlockId, &Size, &Block);
  if (Size != 0) {
    rtl_Move((void *)&(*FPD(TPicture (*), Block)).Height, (void *)&DaxHeight, 2);
    rtl_Move((void *)&(*FPD(TPicture (*), Block)).WidthCols, (void *)&DaxWidthCols, 2);
    rtl_Move((void *)&(*FPD(TPicture (*), Block)).XPos, (void *)&DaxXPos, 2);
    rtl_Move((void *)&(*FPD(TPicture (*), Block)).YPos, (void *)&DaxYPos, 2);
    rtl_Move((void *)&(*FPD(TPicture (*), Block)).ItemCount, (void *)&DaxItemCount, 1);
    rtl_Move((void *)&(*FPD(TPicture (*), Block)).Palette, (void *)&DaxPalette, 8);
    AllocatePicture(DaxHeight, DaxWidthCols, DaxItemCount, AllocFlags, (void *)Target);
    {
      TPicture *w1 = &(*FPD(TPicture (*), (*(farptr (*))Target)));
        w1->XPos = DaxXPos;
        w1->YPos = DaxYPos;
        memcpy(w1->Palette, DaxPalette, 8);
        PixelOfs = 0x11;
        UnpackPicturePixels(Block, PixelOfs, AllocFlags, Color, (*(farptr (*))Target));
    }
    rtl_freemem(Block, Size);
    FlushKeyboard();
  }
}

/* 0464:02A5: unpacks the pixel data of the DAX block Source (its pixels start at Offset,
     $11) into Data, the picture LoadPicture allocated, one item and one cell (four source
     bytes, eight pixels) at a time. Per VideoAdapter: 0 writes two bytes per cell, the
     palette colour of each pixel in 2-bit form (PixelBitsByColor), and, when the picture has a pixel
     buffer (Pixels, AllocFlags bit 0), the mask of the pixels equal to Color; 1 writes the
     four EGA plane bytes of each cell (a pixel's colour bits select its planes) and the
     mask; 2 copies ByteSize bytes of each item unchanged and builds the mask from them.
     AllocFlags is never read. Called by LoadPicture (0464:0111) and by ovl28 LoadSpriteList.
     QUIRK 0464:02A5: the frame has 17 bytes above Cell that the code never touches. */
void UnpackPicturePixels(farptr Source, u16 Offset, u8 AllocFlags, u8 Color, farptr Data)
{
  POOL_TRACE("UnpackPicturePixels");
  u8 Unused[17] = {0};
  s32 Cell = 0;
  u8 (*CellBytes)[4] = (u8 (*)[4])&Cell;
  u8 I = 0;
  u16 Col = 0;
  u16 Row = 0;
  u16 OutOfs = 0;
  u16 PixIndex = 0;
  u8 Mask = 0;
  u8 Index = 0;
  u8 Pass = 0;
  u8 Bit = 0;
  u8 Plane = 0;
  u8 Nibble = 0;
  if (Data == 0) {
    return;
  }
  {
    TPicture *w1 = &(*FPD(TPicture (*), Data));
      OutOfs = 0;
      PixIndex = 0;
      switch (VideoAdapter) {
      case 0:
      {
        {
          u8 limit = w1->ItemCount;
          if (1 <= limit) {
            I = 1;
            for (;;) {
                {
                  u16 limit = (u16)(w1->Height - 1);
                  if (0 <= limit) {
                    Row = 0;
                    for (;;) {
                        {
                          u16 limit = (u16)(w1->WidthCols - 1);
                          if (0 <= limit) {
                            Col = 0;
                            for (;;) {
                                rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), Source))[Offset], (void *)&Cell, 4);
                                if (w1->Pixels != 0) {
                                  Mask = ColorMatchMask(Color, Cell);
                                  Bit = 0x80;
                                  {
                                    if (1 <= 2) {
                                      Pass = 1;
                                      for (;;) {
                                          {
                                            if (4 <= 7) {
                                              Index = 4;
                                              for (;;) {
                                                  if (((Bit & Mask)) > 0) {
                                                    (*FPD(TByteArray_RES07 (*), w1->Pixels))[PixIndex] = ((*FPD(TByteArray_RES07 (*), w1->Pixels))[PixIndex] | GlyphPixelMasks[Index]);
                                                  }
                                                  Bit = (s16)((u16)Bit >> 1);
                                                if (Index == 7) break;
                                                Index++;
                                              }
                                            }
                                          }
                                          PixIndex++;
                                        if (Pass == 2) break;
                                        Pass++;
                                      }
                                    }
                                  }
                                }
                                {
                                  if (0 <= 3) {
                                    Index = 0;
                                    for (;;) {
                                        if (Index & 1) {
                                          w1->Data[OutOfs] = (w1->Data[OutOfs] | PixelBitsByColor[PaletteColor(((*CellBytes)[(s16)((u16)Index >> 1)] & 0xF), rtl_far(&w1->Palette))][Index]);
                                        } else {
                                          w1->Data[OutOfs] = (w1->Data[OutOfs] | PixelBitsByColor[PaletteColor((s16)((u16)(((*CellBytes)[(s16)((u16)Index >> 1)] & 0xF0)) >> 4), rtl_far(&w1->Palette))][Index]);
                                        }
                                      if (Index == 3) break;
                                      Index++;
                                    }
                                  }
                                }
                                if (w1->Pixels != 0) {
                                  w1->Data[OutOfs] = (w1->Data[OutOfs] & (u8)~(*FPD(TByteArray_RES07 (*), w1->Pixels))[(u16)(PixIndex - 2)]);
                                }
                                OutOfs++;
                                {
                                  if (4 <= 7) {
                                    Index = 4;
                                    for (;;) {
                                        if (Index & 1) {
                                          w1->Data[OutOfs] = (w1->Data[OutOfs] | PixelBitsByColor[PaletteColor(((*CellBytes)[(s16)((u16)Index >> 1)] & 0xF), rtl_far(&w1->Palette))][(s16)(Index - 4)]);
                                        } else {
                                          w1->Data[OutOfs] = (w1->Data[OutOfs] | PixelBitsByColor[PaletteColor((s16)((u16)(((*CellBytes)[(s16)((u16)Index >> 1)] & 0xF0)) >> 4), rtl_far(&w1->Palette))][(s16)(Index - 4)]);
                                        }
                                      if (Index == 7) break;
                                      Index++;
                                    }
                                  }
                                }
                                if (w1->Pixels != 0) {
                                  w1->Data[OutOfs] = (w1->Data[OutOfs] & (u8)~(*FPD(TByteArray_RES07 (*), w1->Pixels))[(u16)(PixIndex - 1)]);
                                }
                                OutOfs++;
                                Offset += 4;
                              if (Col == limit) break;
                              Col++;
                            }
                          }
                        }
                      if (Row == limit) break;
                      Row++;
                    }
                  }
                }
              if (I == limit) break;
              I++;
            }
          }
        }
        break;
      }
      case 1:
      {
        {
          u8 limit = w1->ItemCount;
          if (1 <= limit) {
            I = 1;
            for (;;) {
                {
                  u16 limit = (u16)(w1->Height - 1);
                  if (0 <= limit) {
                    Row = 0;
                    for (;;) {
                        {
                          u16 limit = (u16)(w1->WidthCols - 1);
                          if (0 <= limit) {
                            Col = 0;
                            for (;;) {
                                rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), Source))[Offset], (void *)&Cell, 4);
                                if (w1->Pixels != 0) {
                                  (*FPD(TByteArray_RES07 (*), w1->Pixels))[PixIndex] = ColorMatchMask(Color, Cell);
                                  PixIndex++;
                                }
                                Bit = 0x80;
                                {
                                  if (0 <= 7) {
                                    Index = 0;
                                    for (;;) {
                                        if (Index & 1) {
                                          Nibble = ((*CellBytes)[(s16)((u16)Index >> 1)] & 0xF);
                                        } else {
                                          Nibble = (s16)((u16)(*CellBytes)[(s16)((u16)Index >> 1)] >> 4);
                                        }
                                        {
                                          if (0 <= 3) {
                                            Plane = 0;
                                            for (;;) {
                                                if (((EgaPlaneBitMasks[Plane] & Nibble)) > 0) {
                                                  w1->Data[(u16)(OutOfs + Plane)] = (w1->Data[(u16)(OutOfs + Plane)] | Bit);
                                                }
                                              if (Plane == 3) break;
                                              Plane++;
                                            }
                                          }
                                        }
                                        Bit = (s16)((u16)Bit >> 1);
                                      if (Index == 7) break;
                                      Index++;
                                    }
                                  }
                                }
                                if (w1->Pixels != 0) {
                                  {
                                    if (0 <= 3) {
                                      Plane = 0;
                                      for (;;) {
                                          w1->Data[(u16)(OutOfs + Plane)] = (w1->Data[(u16)(OutOfs + Plane)] & (u8)~(*FPD(TByteArray_RES07 (*), w1->Pixels))[(u16)(PixIndex - 1)]);
                                        if (Plane == 3) break;
                                        Plane++;
                                      }
                                    }
                                  }
                                }
                                OutOfs += 4;
                                Offset += 4;
                              if (Col == limit) break;
                              Col++;
                            }
                          }
                        }
                      if (Row == limit) break;
                      Row++;
                    }
                  }
                }
              if (I == limit) break;
              I++;
            }
          }
        }
        break;
      }
      case 2:
      {
        {
          u8 limit = w1->ItemCount;
          if (1 <= limit) {
            I = 1;
            for (;;) {
                rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), Source))[Offset], (void *)&w1->Data[OutOfs], w1->ByteSize);
                if (w1->Pixels != 0) {
                  {
                    u16 limit = (u16)((OutOfs + w1->ByteSize) - 1);
                    u16 first = OutOfs;
                    if (first <= limit) {
                      Col = first;
                      for (;;) {
                          if (((s16)((u16)w1->Data[Col] >> 4)) == Color) {
                            (*FPD(TByteArray_RES07 (*), w1->Pixels))[Col] = 0xF0;
                          }
                          if (((w1->Data[Col] & 0xF)) == Color) {
                            (*FPD(TByteArray_RES07 (*), w1->Pixels))[Col] += 0xF;
                          }
                          w1->Data[Col] = (w1->Data[Col] & (u8)~(*FPD(TByteArray_RES07 (*), w1->Pixels))[Col]);
                        if (Col == limit) break;
                        Col++;
                      }
                    }
                  }
                }
                OutOfs += w1->ByteSize;
                Offset += w1->ByteSize;
              if (I == limit) break;
              I++;
            }
          }
        }
        break;
      }
      }
  }
}

/* 0464:08D4: copies picture Source (item PicIndex of it) into Dest at cell column Col and
     pixel row Row * 8, one source row of bytes at a time, and marks the rows it changed in the
     trackers (RowDirtyFlags, RowFirstChangedOfs, RowFirstChangedCol, RowLastChangedOfs). With bit 0 of Flags and a pixel
     buffer in Source,
     the copy is masked: a destination byte keeps the bits its Pixels mask marks and takes the
     source bits. Per VideoAdapter the bytes per cell are 2 (0) or 4 (1 and 2); adapter 1 reads
     one mask byte per four data bytes. Called by DrawCellPicture (ovl32:00F1, flags 0 and
     DrawBuf) and by ovl34 Put8x8Symbol (ovl34:015D). It does no clipping of its own: the
     item must lie inside Dest (RightRoom is a Word and is added as it is). */
void DrawPictureItem(s16 Col, s16 Row, u8 PicIndex, u8 Flags, farptr Source, farptr Dest)
{
  POOL_TRACE("DrawPictureItem");
  s16 LeftCol = 0;
  u16 RightRoom = 0;
  u16 SrcRowBytes = 0;
  u16 ItemOfs = 0;
  u16 DestOfs = 0;
  u16 SrcLastRow = 0;
  u16 SrcRow = 0;
  u16 MaskOfs = 0;
  u8 BytesToNextMask = 0;
  u16 FirstRow = 0;
  u16 LeftBytes = 0;
  u8 HasMask = 0;
  HasMask = (((((Flags & 1)) > 0)) && (((*FPD(TPicture (*), Source)).Pixels != 0)));
  FirstRow = Row * 8;
  DestOfs = FirstRow * (*FPD(TPicture (*), Dest)).WidthCols;
  SrcLastRow = (*FPD(TPicture (*), Source)).Height - 1;
  LeftCol = Col;
  RightRoom = (*FPD(TPicture (*), Dest)).WidthCols - (Col + (*FPD(TPicture (*), Source)).WidthCols);
  switch (VideoAdapter) {
  case AdapterCga:
  case AdapterTandy:
  {
    if (VideoAdapter == AdapterCga) {
      LeftBytes = LeftCol * 2;
      SrcRowBytes = (*FPD(TPicture (*), Source)).WidthCols * 2;
      LeftCol = LeftCol * 2;
      RightRoom = RightRoom * 2;
      ItemOfs = PicIndex * (*FPD(TPicture (*), Source)).ByteSize;
      DestOfs = DestOfs * 2;
    } else {
      LeftBytes = LeftCol * 4;
      SrcRowBytes = (*FPD(TPicture (*), Source)).WidthCols * 4;
      LeftCol = LeftCol * 4;
      RightRoom = RightRoom * 4;
      ItemOfs = PicIndex * (*FPD(TPicture (*), Source)).ByteSize;
      DestOfs = DestOfs * 4;
    }
    if (HasMask) {
      {
        u16 limit = SrcLastRow;
        if (0 <= limit) {
          SrcRow = 0;
          for (;;) {
              RowDirtyFlags[FirstRow] = 1;
              DestOfs += LeftCol;
              if (RowFirstChangedOfs[FirstRow] > DestOfs) {
                RowFirstChangedCol[FirstRow] = LeftBytes;
                RowFirstChangedOfs[FirstRow] = DestOfs;
              }
              {
                s8 limit = SrcRowBytes;
                if (1 <= limit) {
                  SharedLoopIndex = 1;
                  for (;;) {
                      (*FPD(TPicture (*), Dest)).Data[DestOfs] = ((((*FPD(TPicture (*), Dest)).Data[DestOfs] & (*FPD(TByteArray_RES07 (*), (*FPD(TPicture (*), Source)).Pixels))[ItemOfs])) | (*FPD(TPicture (*), Source)).Data[ItemOfs]);
                      ItemOfs++;
                      DestOfs++;
                    if (SharedLoopIndex == limit) break;
                    SharedLoopIndex++;
                  }
                }
              }
              if ((u16)(DestOfs - 1) > RowLastChangedOfs[FirstRow]) {
                RowLastChangedOfs[FirstRow] = DestOfs - 1;
              }
              DestOfs += RightRoom;
              FirstRow++;
            if (SrcRow == limit) break;
            SrcRow++;
          }
        }
      }
    } else {
      {
        u16 limit = SrcLastRow;
        if (0 <= limit) {
          SrcRow = 0;
          for (;;) {
              RowDirtyFlags[FirstRow] = 1;
              DestOfs += LeftCol;
              if (RowFirstChangedOfs[FirstRow] > DestOfs) {
                RowFirstChangedCol[FirstRow] = LeftBytes;
                RowFirstChangedOfs[FirstRow] = DestOfs;
              }
              rtl_Move((void *)&(*FPD(TPicture (*), Source)).Data[ItemOfs], (void *)&(*FPD(TPicture (*), Dest)).Data[DestOfs], SrcRowBytes);
              ItemOfs += SrcRowBytes;
              DestOfs += SrcRowBytes;
              if ((u16)(DestOfs - 1) > RowLastChangedOfs[FirstRow]) {
                RowLastChangedOfs[FirstRow] = DestOfs - 1;
              }
              DestOfs += RightRoom;
              FirstRow++;
            if (SrcRow == limit) break;
            SrcRow++;
          }
        }
      }
    }
    break;
  }
  case AdapterEga:
  {
    LeftBytes = LeftCol;
    SrcRowBytes = (*FPD(TPicture (*), Source)).WidthCols * 4;
    LeftCol = LeftCol * 4;
    RightRoom = RightRoom * 4;
    ItemOfs = PicIndex * (*FPD(TPicture (*), Source)).ByteSize;
    MaskOfs = (u16)((u16)(u16)((u16)ItemOfs >> 1) >> 1);
    BytesToNextMask = 4;
    DestOfs = DestOfs * 4;
    if (HasMask) {
      {
        u16 limit = SrcLastRow;
        if (0 <= limit) {
          SrcRow = 0;
          for (;;) {
              RowDirtyFlags[FirstRow] = 1;
              DestOfs += LeftCol;
              if (RowFirstChangedOfs[FirstRow] > DestOfs) {
                RowFirstChangedCol[FirstRow] = LeftBytes;
                RowFirstChangedOfs[FirstRow] = DestOfs;
              }
              {
                s8 limit = SrcRowBytes;
                if (1 <= limit) {
                  SharedLoopIndex = 1;
                  for (;;) {
                      (*FPD(TPicture (*), Dest)).Data[DestOfs] = ((((*FPD(TPicture (*), Dest)).Data[DestOfs] & (*FPD(TByteArray_RES07 (*), (*FPD(TPicture (*), Source)).Pixels))[MaskOfs])) | (*FPD(TPicture (*), Source)).Data[ItemOfs]);
                      ItemOfs++;
                      BytesToNextMask--;
                      if (BytesToNextMask == 0) {
                        BytesToNextMask = 4;
                        MaskOfs++;
                      }
                      DestOfs++;
                    if (SharedLoopIndex == limit) break;
                    SharedLoopIndex++;
                  }
                }
              }
              if ((u16)(DestOfs - 1) > RowLastChangedOfs[FirstRow]) {
                RowLastChangedOfs[FirstRow] = DestOfs - 1;
              }
              DestOfs += RightRoom;
              FirstRow++;
            if (SrcRow == limit) break;
            SrcRow++;
          }
        }
      }
    } else {
      {
        u16 limit = SrcLastRow;
        if (0 <= limit) {
          SrcRow = 0;
          for (;;) {
              RowDirtyFlags[FirstRow] = 1;
              DestOfs += LeftCol;
              if (RowFirstChangedOfs[FirstRow] > DestOfs) {
                RowFirstChangedCol[FirstRow] = LeftBytes;
                RowFirstChangedOfs[FirstRow] = DestOfs;
              }
              rtl_Move((void *)&(*FPD(TPicture (*), Source)).Data[ItemOfs], (void *)&(*FPD(TPicture (*), Dest)).Data[DestOfs], SrcRowBytes);
              ItemOfs += SrcRowBytes;
              DestOfs += SrcRowBytes;
              if ((u16)(DestOfs - 1) > RowLastChangedOfs[FirstRow]) {
                RowLastChangedOfs[FirstRow] = DestOfs - 1;
              }
              DestOfs += RightRoom;
              FirstRow++;
            if (SrcRow == limit) break;
            SrcRow++;
          }
        }
      }
    }
    break;
  }
  }
}

/* 0464:0D71: retf 16: same frame as DrawPictureItem. Bit 0 of Flags is tested. */
/* 0464:0D71: the clipping version of DrawPictureItem (08D4). Draws item PicIndex of
     Source with its top-left cell at column Col and pixel row Row * 8, cut to Dest on
     all four sides. Bit 0 of Flags masks the picture (Source needs a pixel buffer);
     bit 2 first copies the destination bytes that are about to be overwritten into the
     screen buffer IconBackgroundBuffer (SaveOfs, the same layout as the picture rows). The range
     checks run only while ClipChecksEnabled is nonzero (set by the loader); when it is 0 the
     picture is drawn with no check at all. Per VideoAdapter: 0 and 2 copy bytes (2 or
     4 per cell), 1 copies the four EGA planes and reads one mask byte per four data
     bytes. The change marks go into RowDirtyFlags, RowFirstChangedCol, RowFirstChangedOfs and RowLastChangedOfs per pixel row.
     QUIRK 0464:0D71: SaveOfs starts at the top-cut bytes only (no PicIndex offset), and
     the adapter 1 mask phase is set once per call, so it carries from row to row. */
void DrawPictureItemClipped(s16 Col, s16 Row, u8 PicIndex, u8 Flags, farptr Source, farptr Dest)
{
  POOL_TRACE("DrawPictureItemClipped");
  u16 LeftCut = 0;
  u16 RightCut = 0;
  u16 LeftCol = 0;
  u16 RightRoom = 0;
  u16 LeftMaskCut = 0;
  u16 RightMaskCut = 0;
  u16 VisibleBytes = 0;
  u16 SrcOfs = 0;
  u16 DestOfs = 0;
  u16 SaveOfs = 0;
  u16 SrcLastRow = 0;
  u16 SrcRow = 0;
  u16 MaskOfs = 0;
  u8 BytesToNextMask = 0;
  u16 FirstRow = 0;
  u16 LeftBytes = 0;
  u8 HasMask = 0;
  u8 SaveBackground = 0;
  if (((Source == 0)) || ((Dest == 0))) {
    return;
  }
  HasMask = (((((Flags & 1)) > 0)) && (((*FPD(TPicture (*), Source)).Pixels != 0)));
  SaveBackground = (((Flags & 4)) > 0);
  if (ClipChecksEnabled != 0) {
    if (Col < 0) {
      LeftCut = rtl_abs(Col);
      if (LeftCut > (*FPD(TPicture (*), Source)).WidthCols) {
        return;
      }
      LeftCol = 0;
    } else {
      LeftCut = 0;
      LeftCol = Col;
      if (LeftCol > (*FPD(TPicture (*), Dest)).WidthCols) {
        return;
      }
    }
    if (Col + (*FPD(TPicture (*), Source)).WidthCols > (*FPD(TPicture (*), Dest)).WidthCols) {
      RightCut = (Col + (*FPD(TPicture (*), Source)).WidthCols) - (*FPD(TPicture (*), Dest)).WidthCols;
      if (RightCut > (*FPD(TPicture (*), Source)).WidthCols) {
        return;
      }
      RightRoom = 0;
    } else {
      RightCut = 0;
      RightRoom = (*FPD(TPicture (*), Dest)).WidthCols - (Col + (*FPD(TPicture (*), Source)).WidthCols);
      if (RightRoom > (*FPD(TPicture (*), Dest)).WidthCols) {
        return;
      }
    }
    if (Row < 0) {
      SrcOfs = (rtl_abs(Row) * (*FPD(TPicture (*), Source)).WidthCols) * 8;
      DestOfs = 0;
      FirstRow = 0;
      SrcLastRow = ((*FPD(TPicture (*), Source)).Height - 1) - (rtl_abs(Row) * 8);
      if ((((u16)((*FPD(TPicture (*), Source)).ByteSize - 1) < SrcOfs)) || ((SrcLastRow > (u16)((*FPD(TPicture (*), Source)).Height - 1)))) {
        return;
      }
    } else {
      SrcOfs = 0;
      FirstRow = Row * 8;
      DestOfs = FirstRow * (*FPD(TPicture (*), Dest)).WidthCols;
      /* the original stores the default here and again in the else below (0464:0F3F, 0F95) */
      SrcLastRow = (*FPD(TPicture (*), Source)).Height - 1;
      if ((Row * 8) + (*FPD(TPicture (*), Source)).Height > (*FPD(TPicture (*), Dest)).Height) {
        SrcLastRow = ((*FPD(TPicture (*), Dest)).Height - 1) - (Row * 8);
      } else {
        SrcLastRow = (*FPD(TPicture (*), Source)).Height - 1;
      }
      if (((((u16)((*FPD(TPicture (*), Source)).ByteSize - 1) < SrcOfs)) || (((u16)((*FPD(TPicture (*), Dest)).ByteSize - 1) < DestOfs))) || ((SrcLastRow > (u16)((*FPD(TPicture (*), Source)).Height - 1)))) {
        return;
      }
    }
  } else {
    LeftCut = 0;
    RightCut = 0;
    SrcOfs = 0;
    FirstRow = Row * 8;
    DestOfs = FirstRow * (*FPD(TPicture (*), Dest)).WidthCols;
    SrcLastRow = (*FPD(TPicture (*), Source)).Height - 1;
    LeftCol = Col;
    RightRoom = (*FPD(TPicture (*), Dest)).WidthCols - (Col + (*FPD(TPicture (*), Source)).WidthCols);
  }
  switch (VideoAdapter) {
  case AdapterCga:
  case AdapterTandy:
  {
    if (VideoAdapter == AdapterCga) {
      LeftBytes = LeftCol * 2;
      VisibleBytes = ((u16)(((*FPD(TPicture (*), Source)).WidthCols - LeftCut) - RightCut)) * 2;
      LeftCut = LeftCut * 2;
      RightCut = RightCut * 2;
      LeftCol = LeftCol * 2;
      RightRoom = RightRoom * 2;
      SrcOfs = SrcOfs * 2;
      SaveOfs = SrcOfs;
      SrcOfs = SrcOfs + (PicIndex * (*FPD(TPicture (*), Source)).ByteSize);
      DestOfs = DestOfs * 2;
    } else {
      LeftBytes = LeftCol * 4;
      VisibleBytes = ((u16)(((*FPD(TPicture (*), Source)).WidthCols - LeftCut) - RightCut)) * 4;
      LeftCut = LeftCut * 4;
      RightCut = RightCut * 4;
      LeftCol = LeftCol * 4;
      RightRoom = RightRoom * 4;
      SrcOfs = SrcOfs * 4;
      SaveOfs = SrcOfs;
      SrcOfs = SrcOfs + (PicIndex * (*FPD(TPicture (*), Source)).ByteSize);
      DestOfs = DestOfs * 4;
    }
    {
      u16 limit = SrcLastRow;
      if (0 <= limit) {
        SrcRow = 0;
        for (;;) {
            RowDirtyFlags[FirstRow] = 1;
            SrcOfs += LeftCut;
            SaveOfs += LeftCut;
            DestOfs += LeftCol;
            if (RowFirstChangedOfs[FirstRow] > DestOfs) {
              RowFirstChangedCol[FirstRow] = LeftBytes;
              RowFirstChangedOfs[FirstRow] = DestOfs;
            }
            if (SaveBackground) {
              rtl_Move((void *)&(*FPD(TPicture (*), Dest)).Data[DestOfs], (void *)&(*FPD(TPicture (*), IconBackgroundBuffer)).Data[SaveOfs], VisibleBytes);
            }
            SaveOfs += VisibleBytes;
            if (HasMask) {
              {
                s8 limit = VisibleBytes;
                if (1 <= limit) {
                  SharedLoopIndex = 1;
                  for (;;) {
                      (*FPD(TPicture (*), Dest)).Data[DestOfs] = ((((*FPD(TPicture (*), Dest)).Data[DestOfs] & (*FPD(TByteArray_RES07 (*), (*FPD(TPicture (*), Source)).Pixels))[SrcOfs])) | (*FPD(TPicture (*), Source)).Data[SrcOfs]);
                      SrcOfs++;
                      DestOfs++;
                    if (SharedLoopIndex == limit) break;
                    SharedLoopIndex++;
                  }
                }
              }
            } else {
              rtl_Move((void *)&(*FPD(TPicture (*), Source)).Data[SrcOfs], (void *)&(*FPD(TPicture (*), Dest)).Data[DestOfs], VisibleBytes);
              SrcOfs += VisibleBytes;
              DestOfs += VisibleBytes;
            }
            if ((u16)(DestOfs - 1) > RowLastChangedOfs[FirstRow]) {
              RowLastChangedOfs[FirstRow] = DestOfs - 1;
            }
            SrcOfs += RightCut;
            SaveOfs += RightCut;
            DestOfs += RightRoom;
            FirstRow++;
          if (SrcRow == limit) break;
          SrcRow++;
        }
      }
    }
    break;
  }
  case AdapterEga:
  {
    LeftBytes = LeftCol;
    VisibleBytes = ((u16)(((*FPD(TPicture (*), Source)).WidthCols - LeftCut) - RightCut)) * 4;
    LeftCut = LeftCut * 4;
    RightCut = RightCut * 4;
    LeftCol = LeftCol * 4;
    RightRoom = RightRoom * 4;
    SrcOfs = SrcOfs * 4;
    SaveOfs = SrcOfs;
    SrcOfs = SrcOfs + (PicIndex * (*FPD(TPicture (*), Source)).ByteSize);
    /* two shifts by 1: the original does not compile shr 2 this way (res07-shift-two-forms) */
    MaskOfs = (u16)((u16)(u16)((u16)SrcOfs >> 1) >> 1);
    LeftMaskCut = (u16)((u16)(u16)((u16)LeftCut >> 1) >> 1);
    RightMaskCut = (u16)((u16)(u16)((u16)RightCut >> 1) >> 1);
    BytesToNextMask = 4;
    DestOfs = DestOfs * 4;
    {
      u16 limit = SrcLastRow;
      if (0 <= limit) {
        SrcRow = 0;
        for (;;) {
            RowDirtyFlags[FirstRow] = 1;
            SrcOfs += LeftCut;
            MaskOfs += LeftMaskCut;
            SaveOfs += LeftCut;
            DestOfs += LeftCol;
            if (RowFirstChangedOfs[FirstRow] > DestOfs) {
              RowFirstChangedCol[FirstRow] = LeftBytes;
              RowFirstChangedOfs[FirstRow] = DestOfs;
            }
            if (SaveBackground) {
              rtl_Move((void *)&(*FPD(TPicture (*), Dest)).Data[DestOfs], (void *)&(*FPD(TPicture (*), IconBackgroundBuffer)).Data[SaveOfs], VisibleBytes);
            }
            SaveOfs += VisibleBytes;
            if (HasMask) {
              {
                s8 limit = VisibleBytes;
                if (1 <= limit) {
                  SharedLoopIndex = 1;
                  for (;;) {
                      (*FPD(TPicture (*), Dest)).Data[DestOfs] = ((((*FPD(TPicture (*), Dest)).Data[DestOfs] & (*FPD(TByteArray_RES07 (*), (*FPD(TPicture (*), Source)).Pixels))[MaskOfs])) | (*FPD(TPicture (*), Source)).Data[SrcOfs]);
                      SrcOfs++;
                      BytesToNextMask--;
                      if (BytesToNextMask == 0) {
                        BytesToNextMask = 4;
                        MaskOfs++;
                      }
                      DestOfs++;
                    if (SharedLoopIndex == limit) break;
                    SharedLoopIndex++;
                  }
                }
              }
            } else {
              rtl_Move((void *)&(*FPD(TPicture (*), Source)).Data[SrcOfs], (void *)&(*FPD(TPicture (*), Dest)).Data[DestOfs], VisibleBytes);
              SrcOfs += VisibleBytes;
              DestOfs += VisibleBytes;
            }
            if ((u16)(DestOfs - 1) > RowLastChangedOfs[FirstRow]) {
              RowLastChangedOfs[FirstRow] = DestOfs - 1;
            }
            SrcOfs += RightCut;
            MaskOfs += RightMaskCut;
            SaveOfs += RightCut;
            DestOfs += RightRoom;
            FirstRow++;
          if (SrcRow == limit) break;
          SrcRow++;
        }
      }
    }
    break;
  }
  }
}

/* 0464:1484: reverses the eight bits of X: bit 0 becomes bit 7, bit 1 bit 6,
     and so on. The byte-sized mirror used to flip an 8-pixel byte of a picture. */
u8 MirrorByte(u8 Value)
{
  POOL_TRACE("MirrorByte");
  u8 Result = 0;
  u8 Mirrored = 0;
  Mirrored = Value << 7;
  Mirrored += (s16)(((Value & 0x2)) << 5);
  Mirrored += (s16)(((Value & 0x4)) << 3);
  Mirrored += (s16)(((Value & 0x8)) << 1);
  Mirrored += (s16)((u16)((Value & 0x10)) >> 1);
  Mirrored += (s16)((u16)((Value & 0x20)) >> 3);
  Mirrored += (s16)((u16)((Value & 0x40)) >> 5);
  Mirrored += (s16)((u16)((Value & 0x80)) >> 7);
  Result = Mirrored;
  return Result;
}

/* 0464:1509: reverses the order of the eight 2-bit groups of X: the group in
     bits 1..0 moves to bits 15..14, and so on. The word-sized mirror used to flip
     a 16-bit unit of a picture row (15C7 applies it to every word of a row). The
     masks come from GlyphPixelMasks (DS:25E5), which holds them in the opposite
     order, so the statements run from element 7 down to 0. */
u16 MirrorWord(u16 Value)
{
  POOL_TRACE("MirrorWord");
  u16 Result = 0;
  u16 Mirrored = 0;
  Mirrored = ((Value & GlyphPixelMasks[7])) << 14;
  Mirrored += (u16)(((Value & GlyphPixelMasks[6])) << 10);
  Mirrored += (u16)(((Value & GlyphPixelMasks[5])) << 6);
  Mirrored += (u16)(((Value & GlyphPixelMasks[4])) << 2);
  Mirrored += (u16)((u16)((Value & GlyphPixelMasks[3])) >> 2);
  Mirrored += (u16)((u16)((Value & GlyphPixelMasks[2])) >> 6);
  Mirrored += (u16)((u16)((Value & GlyphPixelMasks[1])) >> 10);
  Mirrored += (u16)((u16)((Value & GlyphPixelMasks[0])) >> 14);
  Result = Mirrored;
  return Result;
}

/* 0464:1596: swaps the two nibbles of Value: the low nibble becomes the high one. On VideoAdapter 2 a byte holds two
     4-bit pixels, so this
     mirrors a pair of pixels (MirrorPicture); the companion of MirrorByte (1484) and MirrorWord (1509). */
u8 SwapNibbles(u8 Value)
{
  POOL_TRACE("SwapNibbles");
  u8 Result = 0;
  u8 Swapped = 0;
  Swapped = Value << 4;
  Swapped += (s16)((u16)((Value & 0xF0)) >> 4);
  Result = Swapped;
  return Result;
}

/* 0464:15C7: copies the picture Source into Dest mirrored: the palette is copied
     as is, then the pixel data of every row is reversed (each 16-bit unit through
     MirrorWord for adapter 0, each byte through MirrorByte in 4-byte groups for
     adapter 1, each byte through SwapNibbles for adapter 2). The pixel buffer at
     +$13 is mirrored too when it is not nil: word by word in mode 0, byte by byte
     within the row in mode 1, and in place in mode 2. Called by ovl32 DrawIcon
     (icon sets above 3) and res12. */
void MirrorPicture(farptr Source, farptr Dest)
{
  POOL_TRACE("MirrorPicture");
  u16 DestOfs = 0;
  u16 SrcLastOfs = 0;
  u16 RowOfs = 0;
  u16 RowBytes = 0;
  u16 Col = 0;
  u16 Row = 0;
  u8 I = 0;
  u16 PixelWord = 0;
  if (((Source == 0)) || ((Dest == 0))) {
    return;
  }
  {
    TPicture *w1 = &(*FPD(TPicture (*), Source));
      rtl_Move((void *)&w1->Palette, (void *)&(*FPD(TPicture (*), Dest)).Palette, 8);
      switch (VideoAdapter) {
      case AdapterCga:
      {
        RowBytes = w1->WidthCols * 2;
        SrcLastOfs = RowBytes - 2;
        DestOfs = 0;
        {
          u16 limit = w1->Height;
          if (1 <= limit) {
            Row = 1;
            for (;;) {
                RowOfs = DestOfs;
                {
                  u16 limit = (u16)(w1->WidthCols - 1);
                  if (0 <= limit) {
                    Col = 0;
                    for (;;) {
                        rtl_Move((void *)&w1->Data[(u16)((SrcLastOfs - DestOfs) + RowOfs)], (void *)&PixelWord, 2);
                        PixelWord = MirrorWord(PixelWord);
                        rtl_Move((void *)&PixelWord, (void *)&(*FPD(TPicture (*), Dest)).Data[DestOfs], 2);
                        if (w1->Pixels != 0) {
                          rtl_Move((void *)&(*FPD(TByteArray_RES07 (*), w1->Pixels))[(u16)((SrcLastOfs - DestOfs) + RowOfs)], (void *)&PixelWord, 2);
                          PixelWord = MirrorWord(PixelWord);
                          rtl_Move((void *)&PixelWord, (void *)&(*FPD(TByteArray_RES07 (*), (*FPD(TPicture (*), Dest)).Pixels))[DestOfs], 2);
                        }
                        DestOfs += 2;
                      if (Col == limit) break;
                      Col++;
                    }
                  }
                }
                SrcLastOfs += RowBytes;
              if (Row == limit) break;
              Row++;
            }
          }
        }
        break;
      }
      case AdapterEga:
      {
        RowBytes = w1->WidthCols * 4;
        SrcLastOfs = RowBytes - 4;
        DestOfs = 0;
        {
          u16 limit = w1->Height;
          if (1 <= limit) {
            Row = 1;
            for (;;) {
                RowOfs = DestOfs;
                {
                  u16 limit = w1->WidthCols;
                  if (1 <= limit) {
                    Col = 1;
                    for (;;) {
                        {
                          if (0 <= 3) {
                            I = 0;
                            for (;;) {
                                (*FPD(TPicture (*), Dest)).Data[(u16)(DestOfs + I)] = MirrorByte(w1->Data[(u16)(((SrcLastOfs - DestOfs) + RowOfs) + I)]);
                              if (I == 3) break;
                              I++;
                            }
                          }
                        }
                        DestOfs += 4;
                      if (Col == limit) break;
                      Col++;
                    }
                  }
                }
                SrcLastOfs += RowBytes;
              if (Row == limit) break;
              Row++;
            }
          }
        }
        if (w1->Pixels != 0) {
          SrcLastOfs = 0;
          {
            u16 limit = w1->Height;
            if (1 <= limit) {
              Row = 1;
              for (;;) {
                  {
                    u16 limit = (u16)(w1->WidthCols - 1);
                    if (0 <= limit) {
                      Col = 0;
                      for (;;) {
                          (*FPD(TByteArray_RES07 (*), (*FPD(TPicture (*), Dest)).Pixels))[(u16)(((SrcLastOfs + w1->WidthCols) - Col) - 1)] = MirrorByte((*FPD(TByteArray_RES07 (*), w1->Pixels))[(u16)(SrcLastOfs + Col)]);
                        if (Col == limit) break;
                        Col++;
                      }
                    }
                  }
                  SrcLastOfs += w1->WidthCols;
                if (Row == limit) break;
                Row++;
              }
            }
          }
        }
        break;
      }
      case AdapterTandy:
      {
        RowBytes = w1->WidthCols * 4;
        SrcLastOfs = RowBytes - 1;
        DestOfs = 0;
        {
          u16 limit = w1->Height;
          if (1 <= limit) {
            Row = 1;
            for (;;) {
                RowOfs = DestOfs;
                {
                  u16 limit = RowBytes;
                  if (1 <= limit) {
                    Col = 1;
                    for (;;) {
                        (*FPD(TPicture (*), Dest)).Data[DestOfs] = SwapNibbles(w1->Data[(u16)((SrcLastOfs - DestOfs) + RowOfs)]);
                        if (w1->Pixels != 0) {
                          (*FPD(TByteArray_RES07 (*), (*FPD(TPicture (*), Dest)).Pixels))[DestOfs] = SwapNibbles((*FPD(TByteArray_RES07 (*), w1->Pixels))[(u16)((SrcLastOfs - DestOfs) + RowOfs)]);
                        }
                        DestOfs++;
                      if (Col == limit) break;
                      Col++;
                    }
                  }
                }
                SrcLastOfs += RowBytes;
              if (Row == limit) break;
              Row++;
            }
          }
        }
        break;
      }
      }
  }
}

/* 0464:1951: shows a picture at (PicCol, PicRow) by copying its packed pixel data
     straight to the video hardware, one branch per video adapter. PicRow * 8 is the
     first pixel row, and PicCol the first cell column. Adapter 0 moves a
     WidthCols*2-byte row per screen row to the segment CgaScanlineSegments[Row] at column
     PicCol*2; adapter 1 writes, per row and per cell column, the four plane bytes of
     the source cell (the plane-interleaved layout, 4 bytes per cell, one byte per
     EGA plane: each byte holds eight pixels of that plane, written through the map
     mask EgaPlaneBitMasks[Plane] on port 3C5 to Mem[EgaPage0Segment:EgaScanlineOffsets[Row] + Col]);
     adapter 2 is the adapter-0 move with four bytes per column and the TandyScanlineSegments
     segment table. Called by ShowTitleScreen, ovl28 DrawSprite and ovl34 Put8x8Symbol. */
void ShowPicture(s16 PicCol, s16 PicRow, farptr Buf)
{
  POOL_TRACE("ShowPicture");
  s16 Col = 0;
  s16 Row = 0;
  u16 FirstCol = 0;
  u16 FirstRow = 0;
  u16 LastCol = 0;
  u16 LastRow = 0;
  u16 RowBytes = 0;
  u16 SourceOfs = 0;
  u8 Plane = 0;
  if (Buf == 0) {
    return;
  }
  {
    TPicture *w1 = &(*FPD(TPicture (*), Buf));
      switch (VideoAdapter) {
      case AdapterCga:
      {
        RowBytes = w1->WidthCols * 2;
        SourceOfs = 0;
        FirstRow = PicRow * 8;
        LastRow = (FirstRow + w1->Height) - 1;
        FirstCol = PicCol * 2;
        {
          s16 limit = LastRow;
          s16 first = FirstRow;
          if (first <= limit) {
            Row = first;
            for (;;) {
                rtl_Move((void *)&(*FPD(TPicture (*), Buf)).Data[SourceOfs], rtl_mem_ptr(CgaScanlineSegments[Row], FirstCol), RowBytes);
                SourceOfs += RowBytes;
              if (Row == limit) break;
              Row++;
            }
          }
        }
        break;
      }
      case AdapterEga:
      {
        SourceOfs = 0;
        FirstRow = PicRow * 8;
        LastRow = (FirstRow + w1->Height) - 1;
        FirstCol = PicCol;
        LastCol = (FirstCol + w1->WidthCols) - 1;
        rtl_outp(SeqIndex, SeqMapMask);
        {
          s16 limit = LastRow;
          s16 first = FirstRow;
          if (first <= limit) {
            Row = first;
            for (;;) {
                {
                  s16 limit = LastCol;
                  s16 first = FirstCol;
                  if (first <= limit) {
                    Col = first;
                    for (;;) {
                        {
                          if (0 <= 3) {
                            Plane = 0;
                            for (;;) {
                                rtl_outp(SeqData, EgaPlaneBitMasks[Plane]);
                                rtl_poke8(EgaPage0Segment, EgaScanlineOffsets[Row] + Col, (*FPD(TPicture (*), Buf)).Data[SourceOfs]);
                                SourceOfs++;
                              if (Plane == 3) break;
                              Plane++;
                            }
                          }
                        }
                      if (Col == limit) break;
                      Col++;
                    }
                  }
                }
              if (Row == limit) break;
              Row++;
            }
          }
        }
        rtl_outp(SeqData, MapMaskAll);
        break;
      }
      case AdapterTandy:
      {
        RowBytes = w1->WidthCols * 4;
        SourceOfs = 0;
        FirstRow = PicRow * 8;
        LastRow = (FirstRow + w1->Height) - 1;
        FirstCol = PicCol * 4;
        {
          s16 limit = LastRow;
          s16 first = FirstRow;
          if (first <= limit) {
            Row = first;
            for (;;) {
                rtl_Move((void *)&(*FPD(TPicture (*), Buf)).Data[SourceOfs], rtl_mem_ptr(TandyScanlineSegments[Row], FirstCol), RowBytes);
                SourceOfs += RowBytes;
              if (Row == limit) break;
              Row++;
            }
          }
        }
        break;
      }
      }
  }
}

/* 0464:1B52: presents the changed regions the blitters marked in RowDirtyFlags (the
     per-row changed flag) and the tracker arrays, one branch per video adapter. Per
     changed row the staging buffer DrawBuf holds the changed bytes at
     Data[RowFirstChangedOfs[Row] .. RowLastChangedOfs[Row]]: RowFirstChangedOfs is the first (lowest) changed byte
     offset, a minimum that starts at $FFFF, and RowLastChangedOfs the last (highest), which
     starts at 0. RowFirstChangedCol[Row] is the screen-side byte column of that first changed
     byte (LeftCol * 2 on adapter 0, LeftCol * 1 on adapter 1, LeftCol * 4 on
     adapter 2). Adapter 0 moves each changed span to the segment CgaScanlineSegments[Row+8] at
     column RowFirstChangedCol[Row]+2; adapter 1 writes the four EGA planes byte by byte through
     port 3C5 (stride 4 in the source) into the off-screen page EgaPage1Segment, then copies
     EgaPage1Segment onto the visible page EgaPage0Segment in GC write mode 1 (GC register 5 := 1,
     restored to 0); adapter 2 moves the spans to the TandyScanlineSegments segments at column
     RowFirstChangedCol[Row]+4. Finally the trackers are reset. Called after every sprite or
     picture blit. */
void FlushPictureChanges(void)
{
  POOL_TRACE("FlushPictureChanges");
  u16 Row = 0;
  u16 SrcOfs = 0;
  u16 DestOfs = 0;
  u16 BaseOfs = 0;
  u16 Unused = 0;
  switch (VideoAdapter) {
  case AdapterCga:
  {
    {
      if (0 <= 0xA7) {
        Row = 0;
        for (;;) {
            if (RowDirtyFlags[Row] != 0) {
              rtl_Move((void *)&(*FPD(TPicture (*), DrawBuf)).Data[RowFirstChangedOfs[Row]], rtl_mem_ptr(CgaScanlineSegments[(u16)(Row + 8)], (u16)(RowFirstChangedCol[Row] + 2)), (u16)((RowLastChangedOfs[Row] - RowFirstChangedOfs[Row]) + 1));
            }
          if (Row == 0xA7) break;
          Row++;
        }
      }
    }
    break;
  }
  case AdapterEga:
  {
    rtl_outp(SeqIndex, SeqMapMask);
    {
      if (0 <= 0xA7) {
        Row = 0;
        for (;;) {
            if (RowDirtyFlags[Row] != 0) {
              BaseOfs = (EgaScanlineOffsets[(u16)(Row + 8)] + RowFirstChangedCol[Row]) + 1;
              rtl_outp(SeqData, EgaPlaneBitMasks[0]);
              SrcOfs = RowFirstChangedOfs[Row];
              DestOfs = BaseOfs;
              do {
                rtl_poke8(EgaPage1Segment, DestOfs, (*FPD(TPicture (*), DrawBuf)).Data[SrcOfs]);
                SrcOfs += 4;
                DestOfs++;
              } while (!(SrcOfs > RowLastChangedOfs[Row]));
              rtl_outp(SeqData, EgaPlaneBitMasks[1]);
              SrcOfs = RowFirstChangedOfs[Row] + 1;
              DestOfs = BaseOfs;
              do {
                rtl_poke8(EgaPage1Segment, DestOfs, (*FPD(TPicture (*), DrawBuf)).Data[SrcOfs]);
                SrcOfs += 4;
                DestOfs++;
              } while (!(SrcOfs > RowLastChangedOfs[Row]));
              rtl_outp(SeqData, EgaPlaneBitMasks[2]);
              SrcOfs = RowFirstChangedOfs[Row] + 2;
              DestOfs = BaseOfs;
              do {
                rtl_poke8(EgaPage1Segment, DestOfs, (*FPD(TPicture (*), DrawBuf)).Data[SrcOfs]);
                SrcOfs += 4;
                DestOfs++;
              } while (!(SrcOfs > RowLastChangedOfs[Row]));
              rtl_outp(SeqData, EgaPlaneBitMasks[3]);
              SrcOfs = RowFirstChangedOfs[Row] + 3;
              DestOfs = BaseOfs;
              do {
                rtl_poke8(EgaPage1Segment, DestOfs, (*FPD(TPicture (*), DrawBuf)).Data[SrcOfs]);
                SrcOfs += 4;
                DestOfs++;
              } while (!(SrcOfs > RowLastChangedOfs[Row]));
            }
          if (Row == 0xA7) break;
          Row++;
        }
      }
    }
    rtl_outp(SeqData, MapMaskAll);
    DestOfs = EgaScanlineOffsets[8] + 1;
    rtl_outp(GcIndex, GcMode);
    rtl_outp(GcData, WriteMode1);
    {
      if (0 <= 0xA7) {
        Row = 0;
        for (;;) {
            if (RowDirtyFlags[Row] != 0) {
              rtl_Move(rtl_mem_ptr(EgaPage1Segment, (u16)(DestOfs + RowFirstChangedCol[Row])), rtl_mem_ptr(EgaPage0Segment, (u16)(DestOfs + RowFirstChangedCol[Row])), (u16)((u16)((u16)(u16)((u16)((u16)(RowLastChangedOfs[Row] - RowFirstChangedOfs[Row])) >> 1) >> 1) + 1));
            }
            DestOfs += 0x28;
          if (Row == 0xA7) break;
          Row++;
        }
      }
    }
    rtl_outp(GcData, WriteMode0);
    break;
  }
  case AdapterTandy:
  {
    {
      if (0 <= 0xA7) {
        Row = 0;
        for (;;) {
            if (RowDirtyFlags[Row] != 0) {
              rtl_Move((void *)&(*FPD(TPicture (*), DrawBuf)).Data[RowFirstChangedOfs[Row]], rtl_mem_ptr(TandyScanlineSegments[(u16)(Row + 8)], (u16)(RowFirstChangedCol[Row] + 4)), (u16)((RowLastChangedOfs[Row] - RowFirstChangedOfs[Row]) + 1));
            }
          if (Row == 0xA7) break;
          Row++;
        }
      }
    }
    break;
  }
  }
  rtl_FillChar((void *)&RowDirtyFlags, 0xA8, 0);
  rtl_FillChar((void *)&RowFirstChangedOfs, 0x150, 0xFF);
  rtl_FillChar((void *)&RowLastChangedOfs, 0x150, 0);
}

/* 0464:1E5C: recolours item FirstItem of picture Pic (item 0 when FirstItem is
     negative). For every colour index I whose FromMap and ToMap entries differ, each pixel
     whose palette colour is FromMap[I] becomes ToMap[I]. The changes go to a scratch copy
     of Pic (AllocatePicture) that is copied back at the end: because of the QUIRK at 1F51
     the colour loop and the copy back run over exactly one item, item FirstItem, never the
     items from FirstItem on. The scratch copy of a negative FirstItem holds ItemCount items
     but only item 0 is used. FirstItem is an item index (the byte offset of an item is
     FirstItem * ByteSize). Flicker (nonzero) makes each change random: adapters 0 and 2
     change each matching pixel with chance 1 in 4, adapter 1 changes a random subset of the
     matching pixels of each cell. Adapter 0 compares 2-bit pixel pairs (PixelBitsByColor,
     GlyphPixelMasks), adapter 1 the four EGA planes (EgaPlaneBitMasks), adapter 2 the two
     nibbles of each byte. Called by LoadPictureSlot (ovl32), LoadSpriteList (ovl28),
     AnimateAreaDoors (ovl18, the door frame index) and ovl16, ovl17 (the others 0).
     QUIRK 0464:1F51: the header inside the colour loop tests FirstItem again; the header
     before the loop has already set it to 0, so Items is 1 for every colour: a negative
     FirstItem recolours and copies back item 0 only. */
void RemapPictureColors(farptr FromMap, farptr ToMap, s16 FirstItem, u8 Flicker, farptr Pic)
{
  POOL_TRACE("RemapPictureColors");
  TColorMap FromMapCopy = {0};
  TColorMap ToMapCopy = {0};
  u16 PicOfs = 0;
  u16 ScratchOfs = 0;
  u8 Items = 0;
  u16 ColByte = 0;
  u16 PixelRow = 0;
  u8 Mask = 0;
  u8 PlaneMask[4] = {0};
  u8 Plane = 0;
  u8 Unused = 0;
  u8 Quad = 0;
  u16 RowBytes = 0;
  u8 FromHigh = 0;
  u8 ToHigh = 0;
  u8 Color = 0;
  farptr Scratch = 0;
  memcpy(FromMapCopy, (*FPD(TColorMap (*), FromMap)), 16);
  memcpy(ToMapCopy, (*FPD(TColorMap (*), ToMap)), 16);
  if (Pic == 0) {
    return;
  }
  {
    TPicture *w1 = &(*FPD(TPicture (*), Pic));
      if (FirstItem < 0) {
        FirstItem = 0;
        Items = w1->ItemCount;
      } else {
        Items = 1;
      }
      PicOfs = FirstItem * w1->ByteSize;
      ScratchOfs = 0;
  }
  AllocatePicture((*FPD(TPicture (*), Pic)).Height, (*FPD(TPicture (*), Pic)).WidthCols, Items, 0, (void *)&Scratch);
  memcpy((*FPD(TPicture (*), Scratch)).Palette, (*FPD(TPicture (*), Pic)).Palette, 8);
  rtl_Move((void *)&(*FPD(TPicture (*), Pic)).Data[PicOfs], (void *)&(*FPD(TPicture (*), Scratch)).Data[ScratchOfs], (u16)((*FPD(TPicture (*), Scratch)).ItemCount * (*FPD(TPicture (*), Scratch)).ByteSize));
  {
    if (0 <= 15) {
      Color = 0;
      for (;;) {
          {
            TPicture *w2 = &(*FPD(TPicture (*), Pic));
              if (FirstItem < 0) {
                FirstItem = 0;
                Items = w2->ItemCount;
              } else {
                Items = 1;
              }
              PicOfs = FirstItem * w2->ByteSize;
              ScratchOfs = 0;
          }
          if (FromMapCopy[Color] != ToMapCopy[Color]) {
            {
              TPicture *w3 = &(*FPD(TPicture (*), Scratch));
                switch (VideoAdapter) {
                case 0:
                {
                  RowBytes = w3->WidthCols * 2;
                  {
                    s8 limit = (s16)((Items + FirstItem) - 1);
                    s8 first = FirstItem;
                    if (first <= limit) {
                      SharedLoopIndex = first;
                      for (;;) {
                          {
                            u16 limit = w3->Height;
                            if (1 <= limit) {
                              PixelRow = 1;
                              for (;;) {
                                  {
                                    u16 limit = RowBytes;
                                    if (1 <= limit) {
                                      ColByte = 1;
                                      for (;;) {
                                          {
                                            if (0 <= 3) {
                                              Quad = 0;
                                              for (;;) {
                                                  if ((((*FPD(TPicture (*), Pic)).Data[PicOfs] & GlyphPixelMasks[(s16)(Quad + 4)])) == PixelBitsByColor[PaletteColor(FromMapCopy[Color], rtl_far(&w3->Palette))][Quad]) {
                                                    if (((Flicker == 0)) || ((((Flicker != 0)) && ((rtl_Random(4) == 0))))) {
                                                      /* QUIRK 0464:2375: the redundant
                                                         second test is the original's */
                                                      w3->Data[ScratchOfs] = (((w3->Data[ScratchOfs] & (u16)~GlyphPixelMasks[(s16)(Quad + 4)])) | PixelBitsByColor[PaletteColor(ToMapCopy[Color], rtl_far(&w3->Palette))][Quad]);
                                                    }
                                                  }
                                                if (Quad == 3) break;
                                                Quad++;
                                              }
                                            }
                                          }
                                          PicOfs++;
                                          ScratchOfs++;
                                        if (ColByte == limit) break;
                                        ColByte++;
                                      }
                                    }
                                  }
                                if (PixelRow == limit) break;
                                PixelRow++;
                              }
                            }
                          }
                        if (SharedLoopIndex == limit) break;
                        SharedLoopIndex++;
                      }
                    }
                  }
                  break;
                }
                case 1:
                {
                  {
                    if (0 <= 3) {
                      Plane = 0;
                      for (;;) {
                          if (((FromMapCopy[Color] & EgaPlaneBitMasks[Plane])) > 0) {
                            PlaneMask[Plane] = 0;
                          } else {
                            PlaneMask[Plane] = 0xFF;
                          }
                        if (Plane == 3) break;
                        Plane++;
                      }
                    }
                  }
                  {
                    s8 limit = (s16)((Items + FirstItem) - 1);
                    s8 first = FirstItem;
                    if (first <= limit) {
                      SharedLoopIndex = first;
                      for (;;) {
                          {
                            u16 limit = w3->Height;
                            if (1 <= limit) {
                              PixelRow = 1;
                              for (;;) {
                                  {
                                    u16 limit = w3->WidthCols;
                                    if (1 <= limit) {
                                      ColByte = 1;
                                      for (;;) {
                                          if (Flicker != 0) {
                                            Mask = (rtl_Random(256) & rtl_Random(256));
                                          } else {
                                            Mask = 0xFF;
                                          }
                                          {
                                            if (0 <= 3) {
                                              Plane = 0;
                                              for (;;) {
                                                  Mask = ((((*FPD(TPicture (*), Pic)).Data[(u16)(PicOfs + Plane)] ^ PlaneMask[Plane])) & Mask);
                                                if (Plane == 3) break;
                                                Plane++;
                                              }
                                            }
                                          }
                                          {
                                            if (0 <= 3) {
                                              Plane = 0;
                                              for (;;) {
                                                  if (((ToMapCopy[Color] & EgaPlaneBitMasks[Plane])) > 0) {
                                                    w3->Data[(u16)(ScratchOfs + Plane)] = (w3->Data[(u16)(ScratchOfs + Plane)] | Mask);
                                                  } else {
                                                    w3->Data[(u16)(ScratchOfs + Plane)] = (w3->Data[(u16)(ScratchOfs + Plane)] & (u8)~Mask);
                                                  }
                                                if (Plane == 3) break;
                                                Plane++;
                                              }
                                            }
                                          }
                                          PicOfs += 4;
                                          ScratchOfs += 4;
                                        if (ColByte == limit) break;
                                        ColByte++;
                                      }
                                    }
                                  }
                                if (PixelRow == limit) break;
                                PixelRow++;
                              }
                            }
                          }
                        if (SharedLoopIndex == limit) break;
                        SharedLoopIndex++;
                      }
                    }
                  }
                  break;
                }
                case 2:
                {
                  RowBytes = w3->WidthCols * 4;
                  FromHigh = FromMapCopy[Color] << 4;
                  ToHigh = ToMapCopy[Color] << 4;
                  {
                    s8 limit = (s16)((Items + FirstItem) - 1);
                    s8 first = FirstItem;
                    if (first <= limit) {
                      SharedLoopIndex = first;
                      for (;;) {
                          {
                            u16 limit = w3->Height;
                            if (1 <= limit) {
                              PixelRow = 1;
                              for (;;) {
                                  {
                                    u16 limit = RowBytes;
                                    if (1 <= limit) {
                                      ColByte = 1;
                                      for (;;) {
                                          if ((((*FPD(TPicture (*), Pic)).Data[PicOfs] & 0xF0)) == FromHigh) {
                                            if (((Flicker == 0)) || ((((Flicker != 0)) && ((rtl_Random(4) == 0))))) {
                                              w3->Data[ScratchOfs] = (((w3->Data[ScratchOfs] & 0xF)) | ToHigh);
                                            }
                                          }
                                          if ((((*FPD(TPicture (*), Pic)).Data[PicOfs] & 0xF)) == FromMapCopy[Color]) {
                                            if (((Flicker == 0)) || ((((Flicker != 0)) && ((rtl_Random(4) == 0))))) {
                                              w3->Data[ScratchOfs] = (((w3->Data[ScratchOfs] & 0xF0)) | ToMapCopy[Color]);
                                            }
                                          }
                                          PicOfs++;
                                          ScratchOfs++;
                                        if (ColByte == limit) break;
                                        ColByte++;
                                      }
                                    }
                                  }
                                if (PixelRow == limit) break;
                                PixelRow++;
                              }
                            }
                          }
                        if (SharedLoopIndex == limit) break;
                        SharedLoopIndex++;
                      }
                    }
                  }
                  break;
                }
                }
            }
          }
        if (Color == 15) break;
        Color++;
      }
    }
  }
  {
    TPicture *w4 = &(*FPD(TPicture (*), Pic));
      rtl_Move((void *)&(*FPD(TPicture (*), Scratch)).Data[0], (void *)&w4->Data[FirstItem * w4->ByteSize], (u16)(Items * w4->ByteSize));
  }
  ReleasePicture((void *)&Scratch);
}

/* 0464:248E: allocates a picture record of Height * WidthCols * 2 bytes per
     item (times 2 again when the video adapter is not 0, the EGA planar case) times
     ItemCount, plus $17 header bytes, zeroes it, stores the header fields and, when
     bit 0 of AllocFlags is set, a second block for the pixel buffer (a quarter of
     the size for VideoAdapter 1). Pic is untyped so ovl11 can pass its sprite
     banks and ovl28 its list pointers. */
void AllocatePicture(u16 Height, u16 WidthCols, u8 ItemCount, u8 AllocFlags, void *Pic)
{
  POOL_TRACE("AllocatePicture");
  u16 ItemBytes = 0;
  u16 BlockBytes = 0;
  ItemBytes = (Height * WidthCols) * 2;
  if (VideoAdapter != AdapterCga) {
    ItemBytes = ItemBytes << 1;
  }
  BlockBytes = ItemCount * ItemBytes;
  (*(farptr (*))Pic) = rtl_getmem((u16)(BlockBytes + 0x17));
  rtl_FillChar((void *)&(*FPD(TPicture (*), (*(farptr (*))Pic))), (u16)(BlockBytes + 0x17), 0);
  (*FPD(TPicture (*), (*(farptr (*))Pic))).Height = Height;
  (*FPD(TPicture (*), (*(farptr (*))Pic))).WidthCols = WidthCols;
  (*FPD(TPicture (*), (*(farptr (*))Pic))).ByteSize = ItemBytes;
  (*FPD(TPicture (*), (*(farptr (*))Pic))).ItemCount = ItemCount;
  if ((AllocFlags & 1) > 0) {
    if (VideoAdapter == AdapterEga) {
      (*FPD(TPicture (*), (*(farptr (*))Pic))).Pixels = rtl_getmem((u16)((u16)(u16)((u16)BlockBytes >> 1) >> 1));
      rtl_FillChar((void *)&(*FPD(TByteArray_RES07 (*), (*FPD(TPicture (*), (*(farptr (*))Pic))).Pixels)), (u16)((u16)(u16)((u16)BlockBytes >> 1) >> 1), 0);
    } else {
      (*FPD(TPicture (*), (*(farptr (*))Pic))).Pixels = rtl_getmem(BlockBytes);
      rtl_FillChar((void *)&(*FPD(TByteArray_RES07 (*), (*FPD(TPicture (*), (*(farptr (*))Pic))).Pixels)), BlockBytes, 0);
    }
  }
}

/* 0464:2595: frees a picture: the pixel buffer at +$13 when it is not nil (a
     quarter of the size for VideoAdapter 1) and the picture block itself
     (ItemCount * ByteSize + $17 bytes), then stores nil in the caller's variable.
     Pic is untyped so ovl28 can pass its typed sprite banks. */
void ReleasePicture(void *Pic)
{
  POOL_TRACE("ReleasePicture");
  u16 Size = 0;
  if ((*(farptr (*))Pic) != 0) {
    {
      TPicture *w1 = &(*FPD(TPicture (*), (*(farptr (*))Pic)));
        Size = w1->ItemCount * w1->ByteSize;
        if (w1->Pixels != 0) {
          if (VideoAdapter == AdapterEga) {
            rtl_freemem(w1->Pixels, (u16)((u16)(u16)((u16)Size >> 1) >> 1));
          } else {
            rtl_freemem(w1->Pixels, Size);
          }
        }
        rtl_freemem((*(farptr (*))Pic), (u16)(Size + 0x17));
        (*(farptr (*))Pic) = 0;
    }
  }
}

/* 0464:2632: fills a rectangle of picture Target with palette colour Color (Palette is
     the 8-byte PPalette). Width and FirstCol are in cells of 8 pixels (2, 4 or 1x4 bytes per
     cell), but FirstRow and Height are PIXEL rows: the loop runs once per pixel row, from
     row FirstRow for Height rows, with no * 8. FirstCol and FirstRow may be negative: the
     rectangle is clipped at the picture's left, top, right and bottom edges. VideoAdapter 0
     writes two bytes per cell (PixelsByColor2Bit[PaletteColor(Color)]), 2 writes four bytes per cell
     (PixelsByColor4Bit[Color]) and 1 writes one byte per EGA plane through the plane mask of Color
     (EgaPlaneBitMasks). Every row it touches is marked in RowDirtyFlags and in the trackers RowFirstChangedOfs,
     RowFirstChangedCol and RowLastChangedOfs for FlushPictureChanges. Called by DrawWallDescriptors (ovl29:0174,
     four times, FirstCol = 2, the wall descriptors' pixel rows and the WallDescriptor1..WallDescriptor4
     colours) and by DrawIconCell (ovl16:34DF).
     QUIRK 0464:2707: a rectangle that starts above row 0 is drawn one row too far: the row
     bound is Height - |FirstRow| and the loop includes it. */
void FillPictureRect(s16 FirstCol, s16 FirstRow, u16 Width, u16 Height, u8 Color, farptr Palette, farptr Target)
{
  POOL_TRACE("FillPictureRect");
  TPalette (*Pal) = (TPalette (*))rtl_stack_alloc(8);
  u16 ClipLeft = 0;
  u16 RightOver = 0;
  u16 StartCol = 0;
  u16 RightRoom = 0;
  u16 Count = 0;
  u16 LastRow = 0;
  u16 DestOfs = 0;
  u16 Row = 0;
  u8 Mask[4] = {0};
  u16 TrackRow = 0;
  u16 StartBytes = 0;
  u8 PlaneIndex = 0;
  u16 stack_mark = rtl_stack_mark();
  memcpy((*Pal), (*FPD(TPalette (*), Palette)), 8);
  if (Target == 0) {
    goto L_exit;
  }
  if (FirstCol < 0) {
    ClipLeft = rtl_abs(FirstCol);
    StartCol = 0;
  } else {
    ClipLeft = 0;
    StartCol = FirstCol;
  }
  if (FirstCol + Width > (*FPD(TPicture (*), Target)).WidthCols) {
    RightOver = (FirstCol + Width) - (*FPD(TPicture (*), Target)).WidthCols;
    RightRoom = 0;
  } else {
    RightOver = 0;
    RightRoom = (*FPD(TPicture (*), Target)).WidthCols - (FirstCol + Width);
  }
  if (FirstRow < 0) {
    DestOfs = 0;
    TrackRow = 0;
    LastRow = Height - rtl_abs(FirstRow);
  } else {
    TrackRow = FirstRow;
    DestOfs = TrackRow * (*FPD(TPicture (*), Target)).WidthCols;
    LastRow = Height - 1;
    if (FirstRow + Height > (*FPD(TPicture (*), Target)).Height) {
      LastRow = ((*FPD(TPicture (*), Target)).Height - 1) - FirstRow;
    } else {
      LastRow = Height - 1;
    }
  }
  switch (VideoAdapter) {
  case AdapterCga:
  case AdapterTandy:
  {
    if (VideoAdapter == AdapterCga) {
      StartBytes = StartCol * 2;
      Count = ((u16)((Width - ClipLeft) - RightOver)) * 2;
      StartCol = StartCol * 2;
      RightRoom = RightRoom * 2;
      DestOfs = DestOfs * 2;
    } else {
      Count = ((u16)((Width - ClipLeft) - RightOver)) * 4;
      StartCol = StartCol * 4;
      RightRoom = RightRoom * 4;
      DestOfs = DestOfs * 4;
      StartBytes = StartCol;
    }
    {
      u16 limit = LastRow;
      if (0 <= limit) {
        Row = 0;
        for (;;) {
            RowDirtyFlags[TrackRow] = 1;
            DestOfs += StartCol;
            if (RowFirstChangedOfs[TrackRow] > DestOfs) {
              RowFirstChangedCol[TrackRow] = StartBytes;
              RowFirstChangedOfs[TrackRow] = DestOfs;
            }
            if (VideoAdapter == AdapterCga) {
              rtl_FillChar((void *)&(*FPD(TPicture (*), Target)).Data[DestOfs], Count, PixelsByColor2Bit[PaletteColor(Color, rtl_far(&(*Pal)))]);
            } else {
              rtl_FillChar((void *)&(*FPD(TPicture (*), Target)).Data[DestOfs], Count, PixelsByColor4Bit[Color]);
            }
            DestOfs += Count;
            if ((u16)(DestOfs - 1) > RowLastChangedOfs[TrackRow]) {
              RowLastChangedOfs[TrackRow] = DestOfs - 1;
            }
            DestOfs += RightRoom;
            TrackRow++;
          if (Row == limit) break;
          Row++;
        }
      }
    }
    break;
  }
  case AdapterEga:
  {
    StartBytes = StartCol;
    Count = (Width - ClipLeft) - RightOver;
    StartCol = StartCol * 4;
    RightRoom = RightRoom * 4;
    DestOfs = DestOfs * 4;
    rtl_FillChar((void *)&Mask, 4, 0);
    {
      if (0 <= 3) {
        PlaneIndex = 0;
        for (;;) {
            if (((EgaPlaneBitMasks[PlaneIndex] & Color)) > 0) {
              Mask[PlaneIndex] = 0xFF;
            }
          if (PlaneIndex == 3) break;
          PlaneIndex++;
        }
      }
    }
    {
      u16 limit = LastRow;
      if (0 <= limit) {
        Row = 0;
        for (;;) {
            RowDirtyFlags[TrackRow] = 1;
            DestOfs += StartCol;
            if (RowFirstChangedOfs[TrackRow] > DestOfs) {
              RowFirstChangedCol[TrackRow] = StartBytes;
              RowFirstChangedOfs[TrackRow] = DestOfs;
            }
            {
              s8 limit = Count;
              if (1 <= limit) {
                SharedLoopIndex = 1;
                for (;;) {
                    rtl_Move((void *)&Mask, (void *)&(*FPD(TPicture (*), Target)).Data[DestOfs], 4);
                    DestOfs += 4;
                  if (SharedLoopIndex == limit) break;
                  SharedLoopIndex++;
                }
              }
            }
            if ((u16)(DestOfs - 1) > RowLastChangedOfs[TrackRow]) {
              RowLastChangedOfs[TrackRow] = DestOfs - 1;
            }
            DestOfs += RightRoom;
            TrackRow++;
          if (Row == limit) break;
          Row++;
        }
      }
    }
    break;
  }
  }
L_exit:
  rtl_stack_release(stack_mark);
}

/* 0464:2A0D: sets one EGA palette register through INT 10h function $10
     (AL=0): Register is the palette register and Color the colour value, mapped from
     the 0..15 palette range to the hardware's 0..7 and 16..23. Called by SwapPaletteColors0And8 (0, 8) and (8, 0),
     RestorePaletteColors0And8
     (0, 0) and (8, 8) (ovl31) and by ShowTitleScreen, which cycles (1, 9), (1, $B) and (1, $F) (ovl01:122..132). Why
     8..15 map to 16..23 is [H]: bit 4
     is the intensity bit of the RGBI monitor palette. */
void SetPaletteRegister(u8 Register, u8 Color)
{
  POOL_TRACE("SetPaletteRegister");
  Regs.AH = 0x10;
  Regs.AL = 0;
  if (Color < 8) {
    Regs.BH = Color;
  } else {
    Regs.BH = Color + 8;
  }
  Regs.BL = Register;
  rtl_Intr(0x10, &Regs);
}

/* Initialisation part of unit RES07. */
void init_RES07(void)
{
  POOL_TRACE("init");
}
