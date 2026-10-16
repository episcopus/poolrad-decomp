#include "game.h"

/* ovl34:003B. Loads block BlockId of the file 8x8d<TileSet> into 8x8 bank Bank (0..4) through
     LoadPicture (its first number is the DAX block id, as TITLE 1 and 2 in ovl01 and FINAL 1..6 in
     ovl18 show; LoadWallSet passes its WALLDEF block id). On a failure (the bank pointer stays nil)
     it announces Unable to load 8x8D<set>-<block> on Output, waits for a key and ends the game;
     otherwise it flushes the keyboard. Any other Bank does nothing. Called by LoadWallSet and
     StartGame. */
void Load8x8Bank(u8 BlockId, u8 Bank)
{
  u8 NumSet[2] = {0};
  u8 NumBlock[4] = {0};
  u8 Unused = 0;
  u8 Key = 0;
  u8 t1[256];
  u8 t2[256];
  if ((Bank >= FirstBank && Bank <= LastBank)) {
    rtl_str_int(NumSet, 1, TileSet, 0);
    rtl_str_int(NumBlock, 3, BlockId, 0);
    LoadPicture(rtl_str_cat(t1, 2, (const u8 *const[]){S("\0048x8d"), NumSet}), BlockId, TileLoadB, TileLoadC, (void *)&TileBanks[Bank]);
    if (TileBanks[Bank] == 0) {
      RestoreVideoMode();
      rtl_write_str(&Output, rtl_str_cat(t2, 4, (const u8 *const[]){S("\023Unable to load 8x8D"), NumSet, S("\001-"), NumBlock}), 0), rtl_write_ln(&Output);
      Key = ReadGameKey();
      RestoreVideoMode();
      QuitGame();
    }
    FlushKeyboard();
  }
}

/* ovl34:015D. Draws 8x8 symbol Symbol at (XPos, YPos). Symbols 1..$11E live in banks 0..4
     (ranges 1..$2D, $2E..$73, $74..$B9, $BA..$FF, $100..$11E, based at SymbolBase); 0 and
     $11F..$7FFF are fatal (Bad symbol number in Put8x8Symbol on Output, a key, then the game
     ends). QUIRK ovl34:01C0: symbols above $7FFF skip the check and run on with an unset bank.
     A nil bank pointer draws nothing. Otherwise Symbol is made bank relative and the tile is
     drawn through DrawPictureItem when Direct is nonzero (the 3D view) or copied into the staging
     buffer TileBuf and shown with ShowPicture (window frames). Called by DrawWindowFrame and
     ovl29 (three times): DrawWindowFrame passes Direct 0, the ovl29 calls (the 3D view and the
     overhead wall map) pass 1 (ovl29:010C, 0146, 02FB). */
void Put8x8Symbol(s8 XPos, s8 YPos, u16 Symbol, u8 Direct, u8 Attr)
{
  u8 Bank = 0;
  u8 Key = 0;
  s32 t1;
  t1 = Symbol;
  if ((t1 >= 1 && t1 <= 45)) {
    Bank = 0;
  } else if ((t1 >= 46 && t1 <= 115)) {
    Bank = 1;
  } else if ((t1 >= 116 && t1 <= 185)) {
    Bank = 2;
  } else if ((t1 >= 186 && t1 <= 255)) {
    Bank = 3;
  } else if ((t1 >= 256 && t1 <= 286)) {
    Bank = 4;
  } else if (t1 == 0 || (t1 >= 287 && t1 <= 32767)) {
    RestoreVideoMode();
    rtl_write_str(&Output, S("\"Bad symbol number in Put8x8Symbol."), 0), rtl_write_ln(&Output);
    Key = ReadGameKey();
    QuitGame();
  }
  if (TileBanks[Bank] != 0) {
    Symbol -= SymbolBase[Bank];
    if (Direct != 0) {
      DrawPictureItem(XPos, YPos, (u8)Symbol, Attr, TileBanks[Bank], DrawBuf);
    } else {
      {
        T8x8Bank *w1 = &(*FPD(T8x8Bank (*), TileBanks[Bank]));
          rtl_Move((void *)&w1->Data[(u16)(Symbol * w1->Stride)], (void *)&(*FPD(T8x8Bank (*), TileBuf)).Data[0], w1->Stride);
          ShowPicture(XPos, YPos, TileBuf);
      }
    }
  }
}

/* Initialisation part of unit OVL34. */
void init_OVL34(void)
{
}
