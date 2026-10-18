/* t_gfx.c: step 8.3c. The engine's text, tiles and blits from the .DSK: the script of test/gfx_ref.c, which the Phase 7
 * C game's own routines (DrawTextAt, Put8x8Symbol, FillPictureRect, FlushPictureChanges ...) play on the EGA profile.
 * The harness hashes the screen and the palette at each checkpoint; tools/engcheck.py compares them with
 * goldens/engine/t_gfx.s4, the reference's output. Put8x8Symbol (ovl34 015D) is written out here: it is game code,
 * built from the engine's picture calls. */
#include "eng.h"
#include "mailbox.h"

static Pic banks[5];
static u8 loaded[5];
static const u16 symbol_base[5] = {1, 46, 116, 186, 256};

static void put_symbol(s8 x, s8 y, u16 sym, u8 direct, u8 attr)
{
    u8 bank;
    if (sym >= 1 && sym <= 0x2D)
        bank = 0;
    else if (sym <= 0x73)
        bank = 1;
    else if (sym <= 0xB9)
        bank = 2;
    else if (sym <= 0xFF)
        bank = 3;
    else
        bank = 4;
    if (!loaded[bank])
        return;
    sym = (u16)(sym - symbol_base[bank]);
    if (direct)
        db_item(&banks[bank], (u8)sym, (u8)x, (u8)y, attr);
    else
        gfx_item(&banks[bank], (u8)sym, (u8)x, (u8)y);
}

static u8 cp;

static void checkpoint(void)
{
    mb_hold();
    cp++;
}

int main(void)
{
    RsFile f;
    u8 i;
    mb_check(0, rs_mount(0), 0);
    mb_check(1, rs_open(&f, 0, "8X8D1   ", "DAX"), 0);
    mb_check(2, gfx_font_load(&f), 0);
    mb_check(3, pic_load(&banks[0], &f, 0xCB, 13, 1), 0);       /* Load8x8Bank($CB, 0): colour 13 is the key */
    loaded[0] = 1;
    mb_check(4, pic_load(&banks[4], &f, 0xCA, 13, 1), 0);       /* Load8x8Bank($CA, 4) */
    loaded[4] = 1;
    dsk_motor_off();
    gfx_init();
    db_init();
    checkpoint();                                               /* blank */

    gfx_text(0, 0, 0xF, "Pool of Radiance");
    gfx_text(2, 3, 0xA, "Loading...Please Wait");
    gfx_text(5, 12, 0xC, "abc xyz 0123: !?");
    gfx_glyph(10, 20, 0x9, 3, 0x41, 0);
    gfx_glyph(36, 24, 0xE, 4, 0x42, 1);
    gfx_glyph(0, 24, 0x6, 40, 0x20, 1);
    gfx_text(0, 24, 0x7, "Message 1");
    checkpoint();                                               /* text */

    for (i = 0; i < 8; i++)
        put_symbol((s8)(2 + i), 5, (u16)(1 + i), 0, 0);
    put_symbol(30, 18, 0x100, 0, 0);
    put_symbol(31, 18, 0x101, 0, 0);
    checkpoint();                                               /* tiles */

    gfx_text(10, 10, 0xE, "text beneath");
    for (i = 0; i < 8; i++)
        put_symbol((s8)i, 3, (u16)(9 + i), 1, 1);
    put_symbol(2, 10, 3, 1, 0);
    put_symbol(9, 10, 4, 1, 1);
    db_flush();
    checkpoint();                                               /* flush */

    db_fill(2, 20, 4, 30, 5);
    db_fill(-1, -3, 3, 10, 7);
    db_fill(19, 150, 5, 30, 0xB);
    db_flush();
    checkpoint();                                               /* fill */

    gfx_pal_reg(1, 9);
    gfx_pal_reg(3, 4);
    checkpoint();                                               /* palette */
    mb_check(5, cp, 6);
    mb_finish();
    return 0;
}
