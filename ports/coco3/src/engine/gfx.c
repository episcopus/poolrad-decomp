/* gfx.c: the GIME screen of the port: 320x200, 16 colours, 4 bits a pixel (high nibble the left pixel), 160 bytes a row,
 * 32,000 bytes in physical blocks 0..3 (guide 2.1, research 02). The EGA palette register values the game uses are mapped
 * to the GIME's: GIME bits R1 G1 B1 R0 G0 B0 = EGA bits 2 1 0 5 4 3, that is ((e & 7) << 3) | (e >> 3). */
#include "eng.h"
#include "mailbox.h"

u8 gfx_pal[16];

static const u8 default_ega[16] = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07,
                                   0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F};

void gfx_palette(u8 reg, u8 ega)
{
    gfx_pal[reg & 15] = ega;
    ((u8 *)MB_BASE)[0x50 + (reg & 15)] = ega;           /* the harness reads the palette from the mailbox */
    *(u8 *)(0xFFB0 + (reg & 15)) = (u8)(((ega & 7) << 3) | ((ega >> 3) & 7));
}

void gfx_default_palette(void)
{
    u8 i;
    for (i = 0; i < 16; i++)
        gfx_palette(i, default_ega[i]);
}

void gfx_clear(u8 value)
{
    u8 b;
    for (b = 0; b < 4; b++) {
        mmu_set(6, (u8)(SCREEN_BLK + b));
        memset((void *)0xC000, value, 0x2000);
    }
}

void gfx_init(void)
{
    *(u8 *)0xFF90 = 0x4C;          /* GIME: CoCo 3 mode, MMU on, $FE00 constant page */
    *(u8 *)0xFF98 = 0x80;          /* graphics */
    *(u8 *)0xFF99 = 0x3E;          /* 200 lines, 160 bytes a row, 16 colours */
    *(u8 *)0xFF9A = 0;             /* border */
    *(u8 *)0xFF9C = 0;
    *(u8 *)0xFF9F = 0;
    *(u8 *)0xFF9D = (u8)((SCREEN_BLK * 0x2000UL) >> 11);    /* the screen start in 8-byte units: physical address / 8 */
    *(u8 *)0xFF9E = 0;
    gfx_clear(0);
    gfx_default_palette();
}

/* A DAX block holding a picture record of 320x200: 17 bytes of header, then 32,000 bytes of pixels that go straight
 * into the screen blocks. */
u8 gfx_show_title(RsFile *f, u8 block)
{
    DaxEntry e;
    u8 hdr[17];
    u8 st = dax_find(f, block, &e);
    if (st != 0)
        return st;
    return dax_unpack(f, &e, hdr, 17, SCREEN_BLK, 0);
}
