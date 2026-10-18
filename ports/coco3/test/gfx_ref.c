/* gfx_ref.c: the reference for the CoCo engine's text, tile and blit primitives (step 8.3c).
 *
 * It runs the Phase 7 C game's own routines (DrawTextAt, DrawGlyph, Put8x8Symbol, FillPictureRect, FlushPictureChanges,
 * SetPaletteRegister, in the EGA profile the recorded sessions use) on a fixed script and prints one line per
 * checkpoint, `label sha256`, the digest of the 32,000 screen bytes as the CoCo shows them (4 bits a pixel) followed by
 * the 16 palette register values: the format of the 4bpp goldens (c/platform/replay.c record_screen4). The CoCo test
 * src/engtest/t_gfx.c plays the same script on the engine, and tools/engcheck.py compares the two lists.
 *
 *   gfx_ref [--dump PREFIX]       run from the directory holding the game's data files (poolrad/)
 *
 * Build: make gfx-ref (ports/coco3/Makefile). */
#include <stdio.h>
#include <string.h>

#include "game.h"
#include "platform.h"
#include "ega.h"
#include "sha256.h"


static const char *g_dump;

static void checkpoint(const char *label)
{
  static u8 shot[32000];
  u8 pal[16], dg[32];
  char hex[65];
  Sha256 c;
  if (!ega_to_4bpp(shot, pal)) {
    printf("%s text\n", label);
    return;
  }
  if (g_dump) {
    char path[512];
    FILE *f;
    snprintf(path, sizeof path, "%s-%s.scr4", g_dump, label);
    f = fopen(path, "wb");
    if (f) {
      fwrite(shot, 1, sizeof shot, f);
      fwrite(pal, 1, sizeof pal, f);
      fclose(f);
    }
  }
  sha256_init(&c);
  sha256_update(&c, shot, sizeof shot);
  sha256_update(&c, pal, sizeof pal);
  sha256_final(&c, dg);
  sha256_hex(dg, hex);
  printf("%s %s\n", label, hex);
}

int main(int argc, char **argv)
{
  farptr identity;
  int i;
  for (i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--dump") == 0 && i + 1 < argc) g_dump = argv[++i];
  }
  rtl_init();
  pool_init_units();

  /* the parts of StartGame (ovl11) the primitives need */
  GameFont = rtl_getmem(1416);
  AllocatePicture(8, 1, 1, 0, (void *)&TileBuf);
  AllocatePicture(0xA8, 0x15, 1, 0, (void *)&DrawBuf);
  rtl_FillChar((void *)&RowDirtyFlags, 0xA8, 0);
  rtl_FillChar((void *)&RowFirstChangedCol, 0x150, 0);
  rtl_FillChar((void *)&RowFirstChangedOfs, 0x150, 0xFF);
  rtl_FillChar((void *)&RowLastChangedOfs, 0x150, 0);
  for (i = 0; i <= LastScanline; i++) {
    EgaScanlineOffsets[i] = i * BytesPerEgaScanline;
  }
  rtl_FillChar((void *)&TileBanks, 0x14, 0);
  ClipChecksEnabled = 1;
  TileSet = 1;
  LoadGameFont();

  identity = rtl_getmem(8);
  for (i = 0; i < 8; i++) {
    *FPD(u8 *, identity + i) = (u8)((2 * i) << 4 | (2 * i + 1));
  }

  checkpoint("blank");

  /* text: the cooked set (lower case folds to upper), a raw glyph run, a clipped cell */
  DrawTextAt(0, 0, 0xF, S("\020Pool of Radiance"));
  DrawTextAt(2, 3, 0xA, S("\025Loading...Please Wait"));
  DrawTextAt(5, 12, 0xC, S("\020abc xyz 0123: !?"));
  DrawGlyph(10, 20, 0x9, 3, 0x41, 0);
  DrawGlyph(36, 24, 0xE, 4, 0x42, 1);
  DrawGlyph(0, 24, 0x6, 40, 0x20, 1);               /* ClearTextCells' call: the message line */
  DrawTextAt(0, 24, 0x7, S("\011Message 1"));
  checkpoint("text");

  /* tiles straight to the screen (Put8x8Symbol with Direct 0 goes through ShowPicture) */
  Load8x8Bank(0xCB, 0);
  Load8x8Bank(0xCA, 4);
  for (i = 0; i < 8; i++) {
    Put8x8Symbol((s8)(2 + i), 5, (u16)(1 + i), 0, 0);
  }
  Put8x8Symbol(30, 18, 0x100, 0, 0);
  Put8x8Symbol(31, 18, 0x101, 0, 0);
  checkpoint("tiles");

  /* tiles through the staging buffer: masked and opaque, then flushed (the 3D view's path) */
  DrawTextAt(10, 10, 0xE, S("\014text beneath"));
  for (i = 0; i < 8; i++) {
    Put8x8Symbol((s8)i, 3, (u16)(9 + i), 1, 1);       /* masked: colour 13 is transparent */
  }
  Put8x8Symbol(2, 10, 3, 1, 0);                       /* opaque */
  Put8x8Symbol(9, 10, 4, 1, 1);                       /* a gap of untouched buffer between the two */
  FlushPictureChanges();
  checkpoint("flush");

  /* rectangles in the staging buffer, clipped on every side, flushed */
  FillPictureRect(2, 20, 4, 30, 5, identity, DrawBuf);
  FillPictureRect(-1, -3, 3, 10, 7, identity, DrawBuf);
  FillPictureRect(19, 150, 5, 30, 0xB, identity, DrawBuf);
  FlushPictureChanges();
  checkpoint("fill");

  SetPaletteRegister(1, 9);
  SetPaletteRegister(3, 4);
  checkpoint("palette");
  return 0;
}
