#include "game.h"

/* ovl32:0022. Loads the picture set SetName and, when SqrPaciBank1 is not nil, copies one picture's
     bytes into it at Index times the picture's byte size. Index above 127 prints
     "Start range error in Load24x24Set" and leaves through QuitGame. Callers in ovl03 and ovl10
     pass 40, 24 or 5 as Unused; this routine never reads it. */
void Load24x24Set(const u8 *SetName_in, u8 Index, u8 Unused)
{
  POOL_TRACE("Load24x24Set");
  const u8 *SetName = SetName_in;
  farptr Loaded = 0;
  u16 CopyBytes = 0;
  u16 DestOfs = 0;
  if (Index > PicIndexMask) {
    RestoreVideoMode();
    rtl_write_str(&Output, S("!Start range error in Load24x24Set"), 0), rtl_write_ln(&Output);
    QuitGame();
  }
  Loaded = 0;
  LoadPicture(SetName, 1, 0, 0, (void *)&Loaded);
  CopyBytes = (*FPD(TMemPic (*), Loaded)).ItemCount * (*FPD(TMemPic (*), Loaded)).ByteSize;
  DestOfs = Index * (*FPD(TMemPic (*), Loaded)).ByteSize;
  if (SqrPaciBank1 != 0) {
    rtl_Move((void *)&(*FPD(TMemPic (*), Loaded)).Tail, (void *)&(*FPD(TMemPic (*), SqrPaciBank1)).Tail[DestOfs], CopyBytes);
  }
  ReleasePicture((void *)&Loaded);
  FlushKeyboard();
}

/* ovl32:00F1. Draws the picture PicCode at cell (PicCol, PicRow). When PicCode is above
     PicIndexMask, bit 7 is cleared and the source is SqrPaciBank2; otherwise the source is SqrPaciBank1
     and the code is passed whole. Both paths pass NoBlitFlags and the destination DrawBuf to
     DrawPictureItem. Unused is never read (DrawAreaView passes 1, ovl31 passes 0). */
void DrawCellPicture(s8 PicCol, s8 PicRow, u8 PicCode, u8 Unused)
{
  POOL_TRACE("DrawCellPicture");
  if (PicCode > PicIndexMask) {
    DrawPictureItem(PicCol, PicRow, (PicCode & PicIndexMask), NoBlitFlags, SqrPaciBank2, DrawBuf);
  } else {
    DrawPictureItem(PicCol, PicRow, PicCode, NoBlitFlags, SqrPaciBank1, DrawBuf);
  }
}

/* ovl32:014E. Frees both pictures of one slot in PictureSlots, when the pointer is not nil,
     through ReleasePicture (FreeMem, then the pointer is set nil). Slot selects the
     record, stride 8. QUIRK ovl32:0151: UnusedWord is allocated and never read or written. */
void FreePictureSlot(u8 Slot)
{
  POOL_TRACE("FreePictureSlot");
  u16 UnusedWord = 0;
  if (PictureSlots[Slot].FirstPic != 0) {
    ReleasePicture((void *)&PictureSlots[Slot].FirstPic);
  }
  if (PictureSlots[Slot].SecondPic != 0) {
    ReleasePicture((void *)&PictureSlots[Slot].SecondPic);
  }
}

/* ovl32:01C8. Loads picture Block of the set SetName into the first pointer of slot Slot of
     the picture table PictureSlots and picture Block + $80 (its mirrored half) into the second.
     CHEAD and CBODY sets: a name ending in T adds $40 to Block and loses that letter. COMSPR and
     ICON: the name is used as it is, and ICON pictures are recoloured with PictureRemap13To0. Any other set
     takes the file number TileSet as a suffix and both pictures are recoloured with PictureRemap13To8
     (RemapPictureColors, from the identity map PictureRemapFrom). Flushes the keyboard at the end. StartGame
     loads COMSPR pictures 0 to 11 into slots 13 to 24 and picture 25 into slot 25 with it. */
void LoadPictureSlot(const u8 *SetName_in, u8 Block, u8 Slot)
{
  POOL_TRACE("LoadPictureSlot");
  u8 SetName[256];
  rtl_str_assign(SetName, 255, SetName_in);
  u8 Suffix[2] = {0};
  u8 UnusedByte = 0;
  u8 t1[256];
  u8 t2[256];
  u8 t3[256];
  u8 t4[256];
  u8 t5[256];
  u8 t6[256];
  u8 t7[256];
  u8 t8[256];
  u8 t9[256];
  if (((rtl_str_cmp(rtl_str_copy(t1, SetName, 1, 5), S("\005CHEAD")) == 0)) || ((rtl_str_cmp(rtl_str_copy(t2, SetName, 1, 5), S("\005CBODY")) == 0))) {
    if (rtl_upcase(SetName[SetName[0]]) == 'T') {
      Block += AltPictures;
    }
    rtl_str_assign(SetName, 255, rtl_str_copy(t3, SetName, 1, (s16)(SetName[0] - 1)));
    rtl_str_assign(Suffix, 1, S("\000"));
    LoadPicture(rtl_str_cat(t4, 2, (const u8 *const[]){SetName, Suffix}), Block, 1, 0, (void *)&PictureSlots[Slot].FirstPic);
    LoadPicture(rtl_str_cat(t5, 2, (const u8 *const[]){SetName, Suffix}), (s16)(Block + MirrorPictures), 1, 0, (void *)&PictureSlots[Slot].SecondPic);
  } else if (((rtl_str_cmp(SetName, S("\006COMSPR")) == 0)) || ((rtl_str_cmp(SetName, S("\004ICON")) == 0))) {
    rtl_str_assign(Suffix, 1, S("\000"));
    LoadPicture(rtl_str_cat(t6, 2, (const u8 *const[]){SetName, Suffix}), Block, 1, 0, (void *)&PictureSlots[Slot].FirstPic);
    LoadPicture(rtl_str_cat(t7, 2, (const u8 *const[]){SetName, Suffix}), (s16)(Block + MirrorPictures), 1, 0, (void *)&PictureSlots[Slot].SecondPic);
    if (rtl_str_cmp(SetName, S("\004ICON")) == 0) {
      RemapPictureColors(rtl_far(&PictureRemapFrom), rtl_far(&PictureRemap13To0), 0, 0, PictureSlots[Slot].FirstPic);
      RemapPictureColors(rtl_far(&PictureRemapFrom), rtl_far(&PictureRemap13To0), 0, 0, PictureSlots[Slot].SecondPic);
    }
  } else {
    rtl_str_int(Suffix, 1, TileSet, 0);
    LoadPicture(rtl_str_cat(t8, 2, (const u8 *const[]){SetName, Suffix}), Block, 1, 0, (void *)&PictureSlots[Slot].FirstPic);
    RemapPictureColors(rtl_far(&PictureRemapFrom), rtl_far(&PictureRemap13To8), 0, 0, PictureSlots[Slot].FirstPic);
    LoadPicture(rtl_str_cat(t9, 2, (const u8 *const[]){SetName, Suffix}), (s16)(Block + MirrorPictures), 1, 0, (void *)&PictureSlots[Slot].SecondPic);
    RemapPictureColors(rtl_far(&PictureRemapFrom), rtl_far(&PictureRemap13To8), 0, 0, PictureSlots[Slot].SecondPic);
  }
  FlushKeyboard();
}

/* ovl32:04FC. Draws the picture PicIndex, mirror half Mirror, from the table at PictureSlots.
     Nothing happens when that pointer is nil. Otherwise a picture of the same height and
     width is allocated, the bytes are copied (MirrorPicture when IconSet is above
     IconSetCopyLimit, otherwise Move of the tail and the pixels), and DrawPictureItemClipped draws
     it at the cell times CellStep. The copy is then freed. DrawPartyMarker passes the
     marker cell, the icon set PartyFacing, and the walk frame split into half and picture. */
void DrawIcon(s8 CellCol, s8 CellRow, u8 IconSet, u8 Mirror, u8 PicIndex)
{
  POOL_TRACE("DrawIcon");
  farptr Dest = 0;
  if (PictureSlots[PicIndex].Pics[Mirror] != 0) {
    {
      TMemPic *w1 = &(*FPD(TMemPic (*), PictureSlots[PicIndex].Pics[Mirror]));
        AllocatePicture(w1->Height, w1->WidthCols, OneItem, AllocatePixels, (void *)&Dest);
        if (IconSet > IconSetCopyLimit) {
          MirrorPicture(PictureSlots[PicIndex].Pics[Mirror], Dest);
        } else {
          rtl_Move((void *)&w1->Tail, (void *)&(*FPD(TMemPic (*), Dest)).Tail, w1->ByteSize);
          if (VideoAdapter == AdapterEga) {
            rtl_Move((void *)&(*FPD(u8 (*), w1->Pixels)), (void *)&(*FPD(u8 (*), (*FPD(TMemPic (*), Dest)).Pixels)), (u16)((u16)(u16)((u16)w1->ByteSize >> 1) >> 1));
          } else {
            rtl_Move((void *)&(*FPD(u8 (*), w1->Pixels)), (void *)&(*FPD(u8 (*), (*FPD(TMemPic (*), Dest)).Pixels)), w1->ByteSize);
          }
        }
    }
    DrawPictureItemClipped((s16)(CellCol * CellStep), (s16)(CellRow * CellStep), NoPicIndex, BlitFlagBit, Dest, DrawBuf);
    ReleasePicture((void *)&Dest);
  }
}

/* Initialisation part of unit OVL32. */
void init_OVL32(void)
{
  POOL_TRACE("init");
}
