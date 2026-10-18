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
        k_fill((u8 *)0xC000, value, 0x2000);
    }
}

static void rowa_init(void);

void gfx_init(void)
{
    rowa_init();
    eng_init0 = 0x4C;              /* GIME: CoCo 3 mode, MMU on, $FE00 constant page (IRQ and FIRQ bits: irq_start) */
    *(u8 *)0xFF90 = eng_init0;
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
    return dax_unpack(f, &e, hdr, 17, SCREEN_BLK, 0, 0);
}

void gfx_pal_reg(u8 reg, u8 color)
{
    gfx_palette(reg, color < 8 ? color : (u8)(color + 8));
}

/* ---- the screen as rows of bytes. Pixel row y starts at byte y * 160 of the four screen blocks; a span can cross
 * from one block to the next (8192 is not a multiple of 160), so the general write (scr_putn) splits it; the fast
 * paths test that a span stays in a block. The source is always in core RAM (below the windows). rowa[y] = y * 160. */
#define HI(x) (*(u8 *)&(x))               /* the high byte of a 16-bit variable (the CPU is big endian) */
static u16 rowa[200];
static u8 gbuf[256];                      /* a picture's rows, copied out of their block in one go */
static u8 mbuf[256];

static void rowa_init(void)
{
    u16 a = 0;
    u8 y;
    for (y = 0; y < 200; y++) {
        rowa[y] = a;
        a += 160;
    }
}

/* a pointer to screen byte a, with the block holding it mapped into slot 6 */
static u8 *scr_at(u16 a)
{
    mmu_set(6, (u8)(SCREEN_BLK + (HI(a) >> 5)));
    return (u8 *)(0xC000u + (a & 0x1FFFu));
}

static void scr_putn(u16 a, const u8 *src, u8 n)
{
    u16 room, c;
    if (a >= 32000u)
        return;
    while (n > 0) {
        room = (u16)(0x2000u - (a & 0x1FFFu));
        c = n < room ? n : room;
        k_copy(scr_at(a), src, (u8)c);
        src += c;
        a += c;
        n = (u8)(n - c);
    }
}

/* ---- text */
static u8 font[1416];                     /* 177 glyphs of 8 rows; a row's top bit is its leftmost pixel */
static u8 font_ok;

u8 gfx_font_load(RsFile *f)
{
    DaxEntry e;
    u8 st = dax_find(f, 201, &e);
    if (st != 0)
        return st;
    return gfx_font_load_e(f, &e);
}

u8 gfx_font_load_e(RsFile *f, const DaxEntry *e)
{
    u8 st;
    if (e->raw > 1416)
        return 4;
    st = dax_unpack(f, e, font, 0, 0xFF, 0, font);
    if (st == 0)
        font_ok = 1;
    return st;
}

void gfx_glyph(u8 col, u8 row, u8 color, u8 count, u8 glyph, u8 textset)
{
    u8 tab[4], buf[4], i, line, b, c, y0;
    const u8 *g;
    u16 idx, a0, a1;
    if (col > 39 || row > 24 || !font_ok)
        return;
    idx = glyph;
    if (textset) {
        if (glyph >= 'a' && glyph <= 'z')
            idx = (u16)(glyph - 32);
        idx = idx & 63;
    }
    if (idx > 176)
        return;                           /* the original reads past the font block here */
    tab[0] = 0;
    tab[1] = color & 15;
    tab[2] = (u8)(color << 4);
    tab[3] = (u8)((color << 4) | (color & 15));
    g = font + idx * 8;
    y0 = (u8)(row * 8);
    for (i = 0; i < count; i++) {
        c = (u8)(col + i);
        if (c > 39)
            break;                        /* the original runs into the next row; no caller does */
        a0 = rowa[y0] + (u8)(c * 4);
        a1 = rowa[y0 + 7] + (u8)(c * 4) + 3;
        if ((HI(a0) >> 5) == (HI(a1) >> 5)) {
            k_glyph8(scr_at(a0), g, tab);  /* the eight rows are in one block */
            continue;
        }
        for (line = 0; line < 8; line++) {
            b = g[line];
            buf[0] = tab[b >> 6];
            buf[1] = tab[(b >> 4) & 3];
            buf[2] = tab[(b >> 2) & 3];
            buf[3] = tab[b & 3];
            scr_putn(rowa[y0 + line] + (u8)(c * 4), buf, 4);
        }
    }
}

void gfx_text(u8 col, u8 row, u8 color, const char *s)
{
    if (col > 39 || row > 39)
        return;
    while (*s) {
        gfx_glyph(col, row, color, 1, (u8)*s, 1);
        s++;
        col++;
    }
}

/* ---- pictures */
static u8 pic_blk = PIC_FIRST_BLK;
static u16 pic_off;

static u16 le16(const u8 *p)
{
    return (u16)(p[0] | ((u16)p[1] << 8));
}

u8 pic_load(Pic *p, RsFile *f, u8 id, u8 key, u8 masked)
{
    DaxEntry e;
    u8 st = dax_find(f, id, &e);
    if (st != 0)
        return st;
    return pic_load_e(p, f, &e, key, masked);
}

u8 pic_load_e(Pic *p, RsFile *f, const DaxEntry *e, u8 key, u8 masked)
{
    u8 hdr[17];
    u8 st, *d, *m, v, k;
    u16 size, total, i;
    if (e->raw <= 17)
        return 4;
    size = (u16)(e->raw - 17);             /* the pixels of every item */
    total = masked ? (u16)(2 * size) : size;
    if (total > PIC_MAX)
        return 5;
    if (pic_off + total > PIC_MAX) {
        pic_blk++;
        pic_off = 0;
    }
    if (pic_blk > PIC_LAST_BLK)
        return 6;
    p->blk = pic_blk;
    p->off = pic_off;
    p->moff = masked ? (u16)(pic_off + size) : 0;
    mmu_set(6, pic_blk);
    k_fill((u8 *)(0xC000u + pic_off), 0, total);
    st = dax_unpack(f, e, hdr, 17, pic_blk, pic_off, 0);
    if (st != 0)
        return st;
    p->height = (u8)le16(hdr);
    p->wcols = (u8)le16(hdr + 2);
    p->items = hdr[8];
    p->bytesize = (u16)((u16)p->height * p->wcols * 4u);
    if ((u16)(p->bytesize * p->items) != size)
        return 7;
    pic_off = (u16)(pic_off + total);
    if (masked) {                         /* UnpackPicturePixels, adapter 2: the colour key becomes a mask */
        mmu_set(6, p->blk);
        d = (u8 *)(0xC000u + p->off);
        m = (u8 *)(0xC000u + p->moff);
        k = (u8)(key & 15);
        for (i = 0; i < size; i++) {
            v = d[i];
            if ((v >> 4) == k)
                m[i] = 0xF0;
            if ((v & 15) == k)
                m[i] = (u8)(m[i] + 0x0F);
            d[i] = (u8)(v & ~m[i]);
        }
    }
    return 0;
}

/* How many rows of n bytes fit gbuf, at most h of them. */
static u8 rows_in_buf(u8 h, u8 n)
{
    u8 fit = (u8)(255 / n);
    return h < fit ? h : fit;
}

void gfx_item(const Pic *p, u8 item, u8 col, u8 row)
{
    u8 n = (u8)(p->wcols * 4), h = p->height, take, r, y = (u8)(row * 8);
    u16 so = (u16)(p->off + (u16)item * p->bytesize);
    u16 a = rowa[y] + (u8)(col * 4);
    const u8 *src;
    while (h > 0 && y < 200) {
        take = rows_in_buf(h, n);
        mmu_set(6, p->blk);
        k_copy(gbuf, (u8 *)(0xC000u + so), (u8)(take * n));
        src = gbuf;
        for (r = 0; r < take && y < 200; r++) {
            if ((a & 0x1FFFu) + n <= 0x2000u)
                k_copy(scr_at(a), src, n);
            else
                scr_putn(a, src, n);
            src += n;
            a += 160;
            y++;
        }
        so += (u16)take * n;
        h -= take;
    }
}

/* ---- DrawBuf: 168 rows of 84 bytes; rows 0..96 in block 4, 97..167 in block 5 (a row never crosses a block). The
 * trackers hold, for each row, the first and last changed byte of the row (the original's flat offsets, made row
 * relative: the order within a row is the same). */
#define DB_BLK 4
#define DB_SPLIT 97
#define DB_ROWBYTES 84
static u8 db_dirty[DB_ROWS], db_lo[DB_ROWS], db_hi[DB_ROWS];

/* the start of row y of DrawBuf, with its block mapped into slot 6 */
static u8 *db_ptr(u8 y)
{
    if (y < DB_SPLIT) {
        mmu_set(6, DB_BLK);
        return (u8 *)(0xC000u + (u16)y * DB_ROWBYTES);
    }
    mmu_set(6, DB_BLK + 1);
    return (u8 *)(0xC000u + (u16)(y - DB_SPLIT) * DB_ROWBYTES);
}

static void db_clear_trackers(void)
{
    u8 r;
    for (r = 0; r < DB_ROWS; r++) {
        db_dirty[r] = 0;
        db_lo[r] = 0xFF;
        db_hi[r] = 0;
    }
}

void db_init(void)
{
    mmu_set(6, DB_BLK);
    k_fill((u8 *)0xC000, 0, 0x2000);
    mmu_set(6, DB_BLK + 1);
    k_fill((u8 *)0xC000, 0, 0x2000);
    db_clear_trackers();
}

void db_item(const Pic *p, u8 item, u8 col, u8 row, u8 flags)
{
    u8 n = (u8)(p->wcols * 4), h = p->height, x0 = (u8)(col * 4), x1 = (u8)(x0 + n - 1);
    u8 y = (u8)(row * 8), take, r;
    u8 masked = (flags & 1) && p->moff != 0;
    u16 so = (u16)(p->off + (u16)item * p->bytesize);
    u16 mo = (u16)(p->moff + (u16)item * p->bytesize);
    u8 *d;
    const u8 *src, *mk;
    if ((u16)x0 + n > DB_ROWBYTES || (u16)row * 8 + h > DB_ROWS)
        return;
    while (h > 0) {
        take = rows_in_buf(h, n);
        mmu_set(6, p->blk);
        k_copy(gbuf, (u8 *)(0xC000u + so), (u8)(take * n));
        if (masked)
            k_copy(mbuf, (u8 *)(0xC000u + mo), (u8)(take * n));
        src = gbuf;
        mk = mbuf;
        for (r = 0; r < take; r++) {
            d = db_ptr(y) + x0;
            if (masked)
                k_mcopy(d, mk, src, n);
            else
                k_copy(d, src, n);
            db_dirty[y] = 1;
            if (x0 < db_lo[y])
                db_lo[y] = x0;
            if (x1 > db_hi[y])
                db_hi[y] = x1;
            src += n;
            mk += n;
            y++;
        }
        so += (u16)take * n;
        mo += (u16)take * n;
        h -= take;
    }
}

void db_fill(s16 col, s16 row, u16 w, u16 h, u8 color)
{
    u16 clip_left = 0, right_over = 0, start = col, count, last;
    u8 r, y, bytes, x0, v = (u8)(color * 17);
    if (col < 0) {
        clip_left = (u16)(-col);
        start = 0;
    }
    if ((s16)(col + w) > DB_COLS)
        right_over = (u16)(col + w - DB_COLS);
    if (row < 0) {
        if (h < (u16)(-row))
            return;
        y = 0;
        last = (u16)(h + row);            /* the original's bound is h - |row| and its loop includes it */
    } else {
        y = (u8)row;
        last = (row + h > DB_ROWS) ? (u16)(DB_ROWS - 1 - row) : (u16)(h - 1);
    }
    if (w <= clip_left + right_over || row >= DB_ROWS)
        return;
    count = (u16)((w - clip_left - right_over) * 4);
    x0 = (u8)(start * 4);
    bytes = (u8)count;
    for (r = 0; r <= last && y < DB_ROWS; r++, y++) {
        k_fill(db_ptr(y) + x0, v, bytes);
        db_dirty[y] = 1;
        if (x0 < db_lo[y])
            db_lo[y] = x0;
        if ((u8)(x0 + bytes - 1) > db_hi[y])
            db_hi[y] = (u8)(x0 + bytes - 1);
    }
}

void db_flush(void)
{
    u8 y, n, lo;
    u16 a;
    for (y = 0; y < DB_ROWS; y++) {
        if (!db_dirty[y])
            continue;
        lo = db_lo[y];
        n = (u8)(db_hi[y] - lo + 1);
        k_copy(gbuf, db_ptr(y) + lo, n);
        a = rowa[y + 8] + (u8)(lo + 4);
        if ((a & 0x1FFFu) + n <= 0x2000u)
            k_copy(scr_at(a), gbuf, n);
        else
            scr_putn(a, gbuf, n);
    }
    db_clear_trackers();
}
