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
        win_set(0, (u8)(SCREEN_BLK + b));
        k_fill((u8 *)0x8000, value, 0x2000);
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

/* a pointer to screen byte a, with the block holding it mapped into window 0 */
static u8 *scr_at(u16 a)
{
    win_set(0, (u8)(SCREEN_BLK + (HI(a) >> 5)));
    return (u8 *)(0x8000u + (a & 0x1FFFu));
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
/* The picture store: the blocks PIC_SEG_A and PIC_SEG_B read as one linear space of 8 KB blocks. A picture is a
 * run of bytes in it (its items one after the other, then the mask of every item when it has one) that may cross block
 * borders; pic_ptr maps the block a byte is in. Extents are kept in a small table, first fit, so a picture the game
 * releases (ReleasePicture) gives its place back. */
#define PIC_EXTENTS 64
static const u8 run_first[PIC_RUNS] = {0x08, 0x28, 0x33};      /* physical block of the first block of each run */
static const u8 run_n[PIC_RUNS] = {6, 8, 5};                  /* blocks in each run */
#define PIC_NBLK 19                                            /* all runs: linear block indexes 0..18 */
#define PIC_SPACE ((u32)PIC_NBLK * 0x2000UL)
static u32 ext_lin[PIC_EXTENTS];          /* start in the linear space */
static u16 ext_len[PIC_EXTENTS];          /* 0 = free slot */

static u8 pic_phys(u8 idx)                /* linear block index -> physical block */
{
    u8 r;
    for (r = 0; r < PIC_RUNS; r++) {
        if (idx < run_n[r])
            return (u8)(run_first[r] + idx);
        idx = (u8)(idx - run_n[r]);
    }
    return 0;
}

static u8 pic_lin(u8 blk)
{
    u8 r, base = 0;
    for (r = 0; r < PIC_RUNS; r++) {
        if (blk >= run_first[r] && blk < run_first[r] + run_n[r])
            return (u8)(base + blk - run_first[r]);
        base = (u8)(base + run_n[r]);
    }
    return 0;
}

/* the end (linear byte) of the run that holds byte `at` */
static u32 run_end(u32 at)
{
    u8 r;
    u32 end = 0;
    for (r = 0; r < PIC_RUNS; r++) {
        end += (u32)run_n[r] * 0x2000UL;
        if (at < end)
            return end;
    }
    return end;
}

static u8 pic_place(u16 total, u8 *blk, u16 *off)
{
    u8 i, j;
    u32 at = 0;
    if (total > PIC_TOTAL_MAX)
        return 5;
    for (;;) {                             /* candidate: 0, then the end of every extent */
        if (at + total > PIC_SPACE)
            return 6;
        if (at + total > run_end(at)) {    /* a picture does not cross from one run of blocks to the next */
            at = run_end(at);
            continue;
        }
        for (j = 0; j < PIC_EXTENTS; j++)
            if (ext_len[j] && ext_lin[j] < at + total && ext_lin[j] + ext_len[j] > at)
                break;
        if (j == PIC_EXTENTS)
            break;
        at = ext_lin[j] + ext_len[j];      /* retry behind the extent in the way */
    }
    for (i = 0; i < PIC_EXTENTS && ext_len[i]; i++)
        ;
    if (i == PIC_EXTENTS)
        return 6;
    ext_lin[i] = at;
    ext_len[i] = total;
    *blk = pic_phys((u8)(at >> 13));
    *off = (u16)(at & 0x1FFFUL);
    return 0;
}

void pic_free(const Pic *p)
{
    u8 i;
    u32 at = (u32)pic_lin(p->blk) * 0x2000UL + p->off;
    for (i = 0; i < PIC_EXTENTS; i++)
        if (ext_len[i] && ext_lin[i] == at) {
            ext_len[i] = 0;
            return;
        }
}

/* The byte `rel` of the picture's storage: window 0 is mapped on the block that holds it; *room = the bytes from there to
 * the end of that block */
static u8 *pic_ptr(const Pic *p, u16 rel, u16 *room)
{
    u16 lin = (u16)(p->off + rel);        /* below 64 KB: a picture is at most PIC_TOTAL_MAX bytes */
    win_set(0, (u8)(p->blk + (u8)(lin >> 13)));
    *room = (u16)(0x2000u - (lin & 0x1FFFu));
    return (u8 *)(0x8000u + (lin & 0x1FFFu));
}

/* n bytes of the picture from `rel` to dst (RAM below $8000) */
static void pic_rd(const Pic *p, u16 rel, u8 *dst, u16 n)
{
    u16 room, c;
    u8 *src;
    while (n > 0) {
        src = pic_ptr(p, rel, &room);
        c = n < room ? n : room;
        if (c > 255)
            c = 255;
        k_copy(dst, src, (u8)c);
        dst += c;
        rel += c;
        n -= c;
    }
}

#ifndef ENG_TEST                           /* (what only the game uses: the engine tests of 8.3 and 8.4 are built without it, their disks are small) */
/* n bytes from src (RAM below $8000) into the picture at `rel` */
static void pic_wr(const Pic *p, u16 rel, const u8 *src, u16 n)
{
    u16 room, c;
    u8 *d;
    while (n > 0) {
        d = pic_ptr(p, rel, &room);
        c = n < room ? n : room;
        if (c > 255)
            c = 255;
        k_copy(d, src, (u8)c);
        src += c;
        rel += c;
        n -= c;
    }
}

/* Item 0 of a picture and its mask run through 128 byte pieces: what the editor's copy and merge of the icon pictures do
 * (CopyPictureSlot copies the tail and the pixels, MergePictureData ORs the tail and ANDs the pixels: here the colours and
 * the mask, the other way round from the PC's two buffers). op 0: copy, 1: merge (colours OR, mask AND). */
void pic_combine(const Pic *s, const Pic *d, u8 op)
{
    u16 n = s->bytesize < d->bytesize ? s->bytesize : d->bytesize, rel, c, i;
    u8 a[128], b[128];
    for (rel = 0; rel < n; rel = (u16)(rel + c)) {
        c = (u16)(n - rel) < 128 ? (u16)(n - rel) : 128;
        pic_rd(s, rel, a, c);
        if (op) {
            pic_rd(d, rel, b, c);
            for (i = 0; i < c; i++)
                a[i] |= b[i];
        }
        pic_wr(d, rel, a, c);
        if (s->moff && d->moff) {
            pic_rd(s, (u16)(s->moff + rel), a, c);
            if (op) {
                pic_rd(d, (u16)(d->moff + rel), b, c);
                for (i = 0; i < c; i++)
                    a[i] &= b[i];
            }
            pic_wr(d, (u16)(d->moff + rel), a, c);
        }
    }
}

/* UnpackPicturePixels for a piece: n (at most 128) bytes of a block's pixels (4 bits each, two to a byte) at byte rel of item 0.. of
 * the picture; with a mask the pixels equal to `key` become mask nibbles and are cleared (what pic_load_e does for a loaded block) */
void pic_put(const Pic *p, u16 rel, const u8 *src, u8 n, u8 key)
{
    u8 d[128], m[128], i, v;
    if ((u16)(rel + n) > (u16)(p->bytesize * p->items))
        return;
    key &= 15;
    for (i = 0; i < n; i++) {
        v = src[i];
        m[i] = 0;
        if (p->moff) {
            if ((v >> 4) == key)
                m[i] = 0xF0;
            if ((v & 15) == key)
                m[i] = (u8)(m[i] + 0x0F);
            v = (u8)(v & ~m[i]);
        }
        d[i] = v;
    }
    pic_wr(p, rel, d, n);
    if (p->moff)
        pic_wr(p, (u16)(p->moff + rel), m, n);
}
#endif

static void pic_zero(const Pic *p, u16 total)
{
    u16 rel = 0, room, c;
    u8 *d;
    while (rel < total) {
        d = pic_ptr(p, rel, &room);
        c = (u16)(total - rel) < room ? (u16)(total - rel) : room;
        k_fill(d, 0, c);
        rel += c;
    }
}

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
    u8 st, v, k, d[128], m[128];
    u16 size, total, i, n, rel;
    if (e->raw <= 17)
        return 4;
    size = (u16)(e->raw - 17);             /* the pixels of every item */
    total = masked ? (u16)(2 * size) : size;
    if (masked && size > 0x7FFFu)
        return 5;
    st = pic_place(total, &p->blk, &p->off);
    if (st != 0)
        return st;
    p->moff = masked ? size : 0;
    pic_zero(p, total);
    st = dax_unpack(f, e, hdr, 17, p->blk, p->off, 0);
    if (st != 0) {
        pic_free(p);
        return st;
    }
    p->x = p->y = 0;
    p->height = (u8)le16(hdr);
    p->wcols = (u8)le16(hdr + 2);
    p->items = hdr[8];
    p->bytesize = (u16)((u16)p->height * p->wcols * 4u);
    if ((u16)(p->bytesize * p->items) != size) {
        pic_free(p);
        return 7;
    }
    if (masked) {                         /* UnpackPicturePixels, adapter 2: the colour key becomes a mask */
        u16 room;
        u8 *w;
        k = (u8)(key & 15);
        for (rel = 0; rel < size; rel = (u16)(rel + n)) {
            n = (u16)(size - rel) < 128 ? (u16)(size - rel) : 128;
            pic_rd(p, rel, d, n);
            for (i = 0; i < n; i++) {
                v = d[i];
                m[i] = 0;
                if ((v >> 4) == k)
                    m[i] = 0xF0;
                if ((v & 15) == k)
                    m[i] = (u8)(m[i] + 0x0F);
                d[i] = (u8)(v & ~m[i]);
            }
            for (i = 0; i < n;) {          /* back to the pixels and the mask, mind the block border */
                u16 c;
                w = pic_ptr(p, (u16)(rel + i), &room);
                c = (u16)(n - i) < room ? (u16)(n - i) : room;
                k_copy(w, d + i, (u8)c);
                w = pic_ptr(p, (u16)(size + rel + i), &room);
                c = (u16)(n - i) < room ? (u16)(n - i) : room;
                k_copy(w, m + i, (u8)c);
                i = (u16)(i + c);
            }
        }
    }
    return 0;
}

/* A blank picture of height x wcols cells, items items (the data of AllocatePicture), masked: with room for a mask. */
u8 pic_alloc(Pic *p, u8 height, u8 wcols, u8 items, u8 masked)
{
    u16 size = (u16)((u16)height * wcols * 4u * items), total = masked ? (u16)(2 * size) : size;
    u8 st;
    if (total == 0 || (masked && size > 0x7FFFu))
        return 5;
    st = pic_place(total, &p->blk, &p->off);
    if (st != 0)
        return st;
    p->moff = masked ? size : 0;
    p->x = p->y = 0;
    p->height = height;
    p->wcols = wcols;
    p->items = items;
    p->bytesize = (u16)((u16)height * wcols * 4u);
    pic_zero(p, total);
    return 0;
}

/* RemapPictureColors, 4 bits a pixel: every pixel of item `item` becomes lut[pixel] (the mask stays) */
void pic_remap(const Pic *p, u8 item, const u8 *lut)
{
    u16 rel = (u16)((u16)item * p->bytesize), end = (u16)(rel + p->bytesize), room, c, i;
    u8 *d;
    while (rel < end) {
        d = pic_ptr(p, rel, &room);
        c = (u16)(end - rel) < room ? (u16)(end - rel) : room;
        for (i = 0; i < c; i++)
            d[i] = (u8)((lut[d[i] >> 4] << 4) | lut[d[i] & 15]);
        rel = (u16)(rel + c);
    }
}

/* FillPlaneRect (res06): the cells (8 pixels wide, 8 rows high) l..r, t..b solid in one colour */
void gfx_fill_cells(u8 l, u8 t, u8 r, u8 b, u8 color)
{
    u8 y, y1, v = (u8)(color * 17);
    u16 n;
    if (l > r || t > b || l > 39 || t > 24)
        return;
    if (r > 39)
        r = 39;
    if (b > 24)
        b = 24;
    n = (u16)(r - l + 1) * 4u;
    y1 = (u8)(b * 8 + 7);
    for (y = (u8)(t * 8); y <= y1; y++) {
        u16 a = (u16)(rowa[y] + (u8)(l * 4)), rem = n, room, c;
        while (rem > 0) {                 /* a row may cross into the next block */
            room = (u16)(0x2000u - (a & 0x1FFFu));
            c = rem < room ? rem : room;
            k_fill(scr_at(a), v, c);
            a += c;
            rem -= c;
        }
    }
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
    u16 so = (u16)((u16)item * p->bytesize);
    u16 a = rowa[y] + (u8)(col * 4);
    const u8 *src;
    while (h > 0 && y < 200) {
        take = rows_in_buf(h, n);
        pic_rd(p, so, gbuf, (u16)(take * n));
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

/* the start of row y of DrawBuf, with its block mapped into window 0 */
static u8 *db_ptr(u8 y)
{
    if (y < DB_SPLIT) {
        win_set(0, DB_BLK);
        return (u8 *)(0x8000u + (u16)y * DB_ROWBYTES);
    }
    win_set(0, DB_BLK + 1);
    return (u8 *)(0x8000u + (u16)(y - DB_SPLIT) * DB_ROWBYTES);
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
    win_set(0, DB_BLK);
    k_fill((u8 *)0x8000, 0, 0x2000);
    win_set(0, DB_BLK + 1);
    k_fill((u8 *)0x8000, 0, 0x2000);
    db_clear_trackers();
}

void db_item(const Pic *p, u8 item, u8 col, u8 row, u8 flags)
{
    u8 n = (u8)(p->wcols * 4), h = p->height, x0 = (u8)(col * 4), x1 = (u8)(x0 + n - 1);
    u8 y = (u8)(row * 8), take, r;
    u8 masked = (flags & 1) && p->moff != 0;
    u16 so = (u16)((u16)item * p->bytesize);
    u16 mo = (u16)(p->moff + (u16)item * p->bytesize);
    u8 *d;
    const u8 *src, *mk;
    if ((u16)x0 + n > DB_ROWBYTES || (u16)row * 8 + h > DB_ROWS)
        return;
    while (h > 0) {
        take = rows_in_buf(h, n);
        pic_rd(p, so, gbuf, (u16)(take * n));
        if (masked)
            pic_rd(p, mo, mbuf, (u16)(take * n));
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

#ifndef ENG_TEST
/* a row of n bytes mirrored: the bytes in reverse order, the two pixels of each swapped */
static void mirror_row(u8 *b, u8 n)
{
    u8 i, j, t;
    for (i = 0, j = (u8)(n - 1); i < j; i++, j--) {
        t = b[i];
        b[i] = (u8)((b[j] << 4) | (b[j] >> 4));
        b[j] = (u8)((t << 4) | (t >> 4));
    }
    if (i == j)
        b[i] = (u8)((b[i] << 4) | (b[i] >> 4));
}

/* DrawPictureItemClipped (res07 0464:0D71): item `item` with its top-left cell at cell column col and pixel row row * 8, cut to
 * DrawBuf on all four sides. flags bit 0: masked; mirror: the picture drawn left for right (DrawIcon with MirrorPicture's copy).
 * (Bit 2, the saving of the background under the picture, is not here.) */
void db_item_clip(const Pic *p, u8 item, s16 col, s16 row, u8 flags, u8 mirror)
{
    s16 x0 = (s16)(col * 4), y0 = (s16)(row * 8), sl, nb, y, r;
    u8 n = (u8)(p->wcols * 4), x1, ux0, uy;
    u8 masked = (flags & 1) && p->moff != 0;
    u16 so = (u16)((u16)item * p->bytesize);
    u16 mo = (u16)(p->moff + so);
    u8 *d;
    sl = x0 < 0 ? (s16)-x0 : 0;
    nb = (s16)(n - sl);
    if (x0 + n > DB_ROWBYTES)
        nb = (s16)(nb - (x0 + n - DB_ROWBYTES));
    if (nb <= 0)
        return;
    x0 = (s16)(x0 + sl);
    x1 = (u8)(x0 + nb - 1);
    ux0 = (u8)x0;                          /* (CMOC: compare bytes with bytes) */
    for (r = 0; r < p->height; r++) {
        y = (s16)(y0 + r);
        if (y < 0 || y >= DB_ROWS)
            continue;
        pic_rd(p, (u16)(so + (u16)r * n), gbuf, n);
        if (mirror)
            mirror_row(gbuf, n);
        if (masked) {
            pic_rd(p, (u16)(mo + (u16)r * n), mbuf, n);
            if (mirror)
                mirror_row(mbuf, n);
        }
        uy = (u8)y;
        d = db_ptr(uy) + ux0;                 /* (after the reads: they move window 0 to the picture's block) */
        if (masked)
            k_mcopy(d, mbuf + sl, gbuf + sl, (u8)nb);
        else
            k_copy(d, gbuf + sl, (u8)nb);
        db_dirty[uy] = 1;
        if (ux0 < db_lo[uy])
            db_lo[uy] = ux0;
        if (x1 > db_hi[uy])
            db_hi[uy] = x1;
    }
}
#endif
