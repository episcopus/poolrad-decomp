#include "game.h"

/* ovl18:0006. Animates the FINAL ending picture at (Col, Row): loads the FINAL<TileSet>
     frames of bank Bank through LoadSpriteList and shows them Cycles times, drawing each frame
     through DrawSprite and waiting that frame's data delay, scaled by (GameSpeed + 3) ticks of
     the GameClock timer, before stepping to the next one, then frees the list. The frame
     cursor is the sprite list's Flag field (the loader sets it to 1); Count is read as a
     byte here (ovl18:00E1 compares it with a byte cmp/jbe although the shared type says
     ShortInt). Called by ShowEndingNarrative. */
void AnimateFinalPicture(u16 Col, u16 Row, u8 Bank, u8 Cycles)
{
  POOL_TRACE("AnimateFinalPicture");
  u16 stack_mark = rtl_stack_mark();
  TSpriteList (*Sprites) = (TSpriteList (*))rtl_stack_alloc(66);
  s32 NowTick = 0;
  s32 StartTick = 0;
  u8 DoneCycles = 0;
  DoneCycles = 0;
  StartTick = GameClock();
  rtl_FillChar((void *)&(*Sprites), 66, 0);
  LoadSpriteList(S("\005FINAL"), Bank, 2, rtl_far(&(*Sprites)));
  DrawPictureItemClipped((u16)(Col - 1), (u16)(Row - 1), 0, 0, (*Sprites).Slots[0].Sprite, DrawBuf);
  FlushPictureChanges();
  do {
    DrawSprite(Col, Row, 1, (*Sprites).Slots[(*Sprites).Flag - 1].Sprite);
    NowTick = GameClock();
    if ((NowTick - StartTick) > (s32)(*Sprites).Slots[(*Sprites).Flag - 1].Data * ((s16)(GameSpeed + 3))) {
      (*Sprites).Flag++;
      if ((*Sprites).Flag > (*Sprites).Count) {
        (*Sprites).Flag = 1;
        DoneCycles++;
      }
      StartTick = NowTick;
    }
  } while (!(DoneCycles == Cycles));
  FreeSpriteList(rtl_far(&(*Sprites)));
L_exit:
  rtl_stack_release(stack_mark);
}

/* ovl18:02A4. The ending narrative (PoolNarrative): it shows the dragon's death and the
     Tyranthraxus and Bane speech as lines of text (DrawTextAt on column 1, rows $11 onwards, colour
     10), loads the FINAL<number> pictures (whose number is Str(TileSet) in DS:4713) through
     LoadPicture and draws them with DrawPictureItemClipped, running the AnimateFinalPicture
     animation between the speech blocks, and restores the view mode DS:49F3 at the end.
     Callers: ovl03:2E10. Gets its picture
     number from DS:4713 and its lines from the code's literal pool. */
void ShowEndingNarrative(void)
{
  POOL_TRACE("ShowEndingNarrative");
  u8 ts1[7];
  rtl_str_int(FinalPictureNumber, 1, TileSet, 0);
  SavedViewMode = ViewMode;
  ViewMode = 7;
  FinalPictureBank = 0;
  ClearRect(1, 0x11, 0x26, 0x16);
  DrawTextAt(1, 0x11, 0xA, S("#Mortally wounded, the dragon roars!"));
  DrawTextAt(1, 0x12, 0xA, S("$The spirit of Tyranthraxus flares up"));
  DrawTextAt(1, 0x13, 0xA, S("\027from the dragon's body."));
  RedrawView();
  LoadPicture(rtl_str_cat(ts1, 2, (const u8 *const[]){S("\005FINAL"), FinalPictureNumber}), 1, 0, 0, (void *)&FinalPictureBank);
  DrawPictureItemClipped(0, 0, 0, 0, FinalPictureBank, DrawBuf);
  AnimateFinalPicture(3, 5, 2, ((s16)(((s16)(10 - GameSpeed)) * 5) / 2));
  LoadPicture(rtl_str_cat(ts1, 2, (const u8 *const[]){S("\005FINAL"), FinalPictureNumber}), 3, 0, 0, (void *)&FinalPictureBank);
  DrawPictureItemClipped(0, 0, 0, 0, FinalPictureBank, DrawBuf);
  if ((*FPD(TGameVars (*), GameVars2))[830] > 1) {
    LoadPicture(rtl_str_cat(ts1, 2, (const u8 *const[]){S("\005FINAL"), FinalPictureNumber}), 4, 0, 0, (void *)&FinalPictureBank);
    DrawPictureItemClipped(0, 0xB, 0, 0, FinalPictureBank, DrawBuf);
  }
  if ((*FPD(TGameVars (*), GameVars2))[830] > 2) {
    LoadPicture(rtl_str_cat(ts1, 2, (const u8 *const[]){S("\005FINAL"), FinalPictureNumber}), 5, 0, 0, (void *)&FinalPictureBank);
    DrawPictureItemClipped(0xD, 9, 0, 0, FinalPictureBank, DrawBuf);
  }
  if ((*FPD(TGameVars (*), GameVars2))[830] > 3) {
    LoadPicture(rtl_str_cat(ts1, 2, (const u8 *const[]){S("\005FINAL"), FinalPictureNumber}), 6, 0, 0, (void *)&FinalPictureBank);
    DrawPictureItemClipped(0, 9, 0, 0, FinalPictureBank, DrawBuf);
  }
  ClearRect(1, 0x11, 0x26, 0x16);
  DrawTextAt(1, 0x11, 0xA, S("#\"Fools, you have but slain the body"));
  DrawTextAt(1, 0x12, 0xA, S("$I possessed.  I cannot be defeated!\""));
  DrawTextAt(1, 0x13, 0xA, S("&With the power of the pool of radiance"));
  DrawTextAt(1, 0x14, 0xA, S("\037which I moved here, to my lair,"));
  DrawTextAt(1, 0x15, 0xA, S("$I will still rule, by possessing one"));
  DrawTextAt(1, 0x16, 0xA, S("\010of you!\""));
  AnimateFinalPicture(3, 1, 7, ((s16)(((s16)(10 - GameSpeed)) * 5) / 2));
  ClearRect(1, 0x11, 0x26, 0x16);
  DrawTextAt(1, 0x11, 0xA, S("&\"No Lord Bane!  I can still rule here!"));
  DrawTextAt(1, 0x12, 0xA, S("'I have not failed.  Do not call me back"));
  DrawTextAt(1, 0x13, 0xA, S("\022through the pool!\""));
  DrawTextAt(1, 0x14, 0xA, S("\010Noooo..."));
  AnimateFinalPicture(3, 1, 8, 1);
  DelayByGameSpeed();
  DelayByGameSpeed();
  DelayByGameSpeed();
  ViewMode = SavedViewMode;
  RedrawView();
}

/* ovl18:06B3. Animates the doors of the area view (Flag 1) or clears them (flag 0): it draws the
     doors of the two block-code tables DS:0900 and DS:090B through RemapPictureColors (bit 7 of a code
     selects the second SQRPACI bank SqrPaciBank2, otherwise SqrPaciBank1), stepping the area view through
     DS:094D/DS:095F and stepping the display, then clears the doors. Called by ovl03:31B4 and
     ovl17:1602. */
void AnimateAreaDoors(u8 Flag)
{
  POOL_TRACE("AnimateAreaDoors");
  u8 DoorCol = 0;
  u8 DoorRow = 0;
  if (Flag != 0) {
    DrawAreaView(0x11, 0xF);
    FlushPictureChanges();
    {
      if (0 <= 8) {
        DoorRow = 0;
        for (;;) {
            {
              if (0 <= 0xA) {
                DoorCol = 0;
                for (;;) {
                    if (DoorBlockCodesFirst[DoorCol] > 0x7F) {
                      RemapPictureColors(rtl_far(&DoorRemapFrom), rtl_far(&DoorRemapToFirst), (DoorBlockCodesFirst[DoorCol] & 0x7F), 1, SqrPaciBank2);
                    } else {
                      RemapPictureColors(rtl_far(&DoorRemapFrom), rtl_far(&DoorRemapToFirst), DoorBlockCodesFirst[DoorCol], 1, SqrPaciBank1);
                    }
                  if (DoorCol == 0xA) break;
                  DoorCol++;
                }
              }
            }
            {
              if (0 <= 0x11) {
                DoorCol = 0;
                for (;;) {
                    if (DoorBlockCodesSecond[DoorCol] > 0x7F) {
                      RemapPictureColors(rtl_far(&DoorRemapFrom), rtl_far(&DoorRemapToSecond), (DoorBlockCodesSecond[DoorCol] & 0x7F), 1, SqrPaciBank2);
                    } else {
                      RemapPictureColors(rtl_far(&DoorRemapFrom), rtl_far(&DoorRemapToSecond), DoorBlockCodesSecond[DoorCol], 1, SqrPaciBank1);
                    }
                  if (DoorCol == 0x11) break;
                  DoorCol++;
                }
              }
            }
            DrawAreaView(DoorViewColumns[DoorRow], DoorViewRows[DoorRow]);
            FlushPictureChanges();
          if (DoorRow == 8) break;
          DoorRow++;
        }
      }
    }
  }
  {
    if (0 <= 0xA) {
      DoorCol = 0;
      for (;;) {
          if (DoorBlockCodesFirst[DoorCol] > 0x7F) {
            RemapPictureColors(rtl_far(&DoorRemapFrom), rtl_far(&DoorRemapToFirst), (DoorBlockCodesFirst[DoorCol] & 0x7F), 0, SqrPaciBank2);
          } else {
            RemapPictureColors(rtl_far(&DoorRemapFrom), rtl_far(&DoorRemapToFirst), DoorBlockCodesFirst[DoorCol], 0, SqrPaciBank1);
          }
        if (DoorCol == 0xA) break;
        DoorCol++;
      }
    }
  }
  {
    if (0 <= 0x11) {
      DoorCol = 0;
      for (;;) {
          if (DoorBlockCodesSecond[DoorCol] > 0x7F) {
            RemapPictureColors(rtl_far(&DoorRemapFrom), rtl_far(&DoorRemapToSecond), (DoorBlockCodesSecond[DoorCol] & 0x7F), 0, SqrPaciBank2);
          } else {
            RemapPictureColors(rtl_far(&DoorRemapFrom), rtl_far(&DoorRemapToSecond), DoorBlockCodesSecond[DoorCol], 0, SqrPaciBank1);
          }
        if (DoorCol == 0x11) break;
        DoorCol++;
      }
    }
  }
  if (Flag != 0) {
    DrawAreaView(0x17, 0x19);
    FlushPictureChanges();
    DelayByGameSpeed();
    DelayByGameSpeed();
  }
}

/* Initialisation part of unit OVL18. */
void init_OVL18(void)
{
  POOL_TRACE("init");
}
