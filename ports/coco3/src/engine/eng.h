/* eng.h: the engine of the CoCo 3 port (step 8.3). Plain C for CMOC; the kernels are in kernels.asm, disk.asm, mmu.asm.
 * Physical memory is in 8 KB blocks ($00..$3F on 512 KB); the CPU sees eight 8 KB slots (mmu.asm). */
#ifndef ENG_H
#define ENG_H

typedef unsigned char u8;
typedef signed char s8;
typedef unsigned int u16;
typedef int s16;
typedef unsigned long u32;

/* ---- mmu.asm: slots 4 to 7 are the engine's windows; 0 to 3 are fixed (BASIC low RAM, core). */
void mmu_set(u8 slot, u8 block);          /* map physical block into slot 4..7 (shadowed, restored after disk calls) */
u8 mmu_get(u8 slot);

/* ---- disk.asm (DSKCON through Disk BASIC's ROM) and rsdos.c (a read-only RS-DOS file system). */
extern u8 dsk_buf[256];
u8 dsk_read(u8 drive, u8 track, u8 sector);   /* 0 = ok; else Disk BASIC's status byte */
u8 dsk_read_to(u8 drive, u8 track, u8 sector, u8 *buf);   /* the same, into buf (below $8000) instead of dsk_buf */
void dsk_motor_off(void);

typedef struct RsFile {
    u8 drive;
    u8 gran0;                             /* first granule */
    u16 last_bytes;                       /* bytes used in the last sector */
    u16 sectors;                          /* sectors in the chain */
} RsFile;

u8 rs_mount(u8 drive);                    /* read the FAT; 0 = ok */
u8 rs_open(RsFile *f, u8 drive, const char *name8, const char *ext3);   /* 0 = ok, 1 = not found, else disk status */
u8 rs_read(RsFile *f, u32 offset, u8 *dst, u16 n);                       /* 0 = ok */

/* ---- rle.asm and dax.c */
typedef struct Rle {
    u8 *src, *srcend, *dst, *dstend;
    u8 pad, count, mode, val;
} Rle;
u8 k_rle(Rle *r);

typedef struct DaxEntry {
    u32 offset;                           /* of the packed data, from the start of the file */
    u16 raw, packed;
} DaxEntry;
u8 dax_find(RsFile *f, u8 id, DaxEntry *e);
u8 dax_unpack(RsFile *f, const DaxEntry *e, u8 *hdr, u8 hdr_n, u8 first_blk, u16 first_off, u8 *ram_dst);

/* ---- vol.c: volumes. One RS-DOS floppy holds POOLVOL.DAT, the container of tools/mkvolumes.py with the blocks of many
 * DAX files and their index; up to four are mounted at once, one a drive. */
typedef struct Vol {
    u8 drive, num, nfiles, mounted;
    u16 nent;
    RsFile f;
} Vol;
extern Vol vols[4];
u8 vol_mount(Vol *v, u8 drive);           /* 0 = ok, 1 = no valid POOLVOL.DAT, else the disk status; reads the index into RAM */
u8 vol_find(const Vol *v, const char *name8, u8 id, DaxEntry *e);   /* name8: 8 characters, space padded, e.g. "ECL2    "; 0 = found, 1 = file not on this volume, 2 = no such block */
u8 vol_entry(const Vol *v, u16 i, u8 *file, u8 *id, DaxEntry *e);   /* the i-th index entry, 1 past the end */
u8 vol_lookup(const char *name8, u8 id, Vol **vp, DaxEntry *e);     /* over every mounted volume; 1 = on none of them, 2 = a volume has the file but not the block */

/* ---- kernels.asm: the inner loops. Nothing here maps a window; the pointers must be valid when called. */
void k_copy(u8 *dst, const u8 *src, u8 n);                      /* n = 0 copies nothing */
void k_fill(u8 *dst, u8 value, u16 n);
void k_mcopy(u8 *dst, const u8 *mask, const u8 *src, u8 n);     /* dst = (dst & mask) | src, n >= 1 */
void k_glyph8(u8 *scr, const u8 *glyph, const u8 *tab);         /* 8 font rows to rows 160 bytes apart */
u16 k_sum(const u8 *p, u16 n);                                  /* the sum of the bytes, modulo 65536 */

/* ---- irq.asm: the 60 Hz frame clock (GIME vertical border IRQ), a fast tick (GIME timer FIRQ) and the keyboard. */
extern u8 eng_init0;                      /* the value last written to GIME $FF90 */
void irq_start(void);                     /* interrupts on; dsk_read keeps them masked while a sector is read */
void irq_stop(void);
u16 frame_count(void);                    /* frames since irq_start, wraps */
void tick_start(u16 reload);              /* FIRQ every reload * 63.695 us (1..4095) */
void tick_stop(void);
u16 tick_count(void);
u8 kbd_get(void);                         /* next key code, 0 = none: ASCII, ENTER 13, BREAK 27, arrows $81..$84 (up, down, left, right), CLEAR $8C, F1 $91, F2 $92 */
u8 kbd_mods(void);                        /* bit 0 shift, bit 1 control, bit 2 alt */

/* ---- gfx.c: the 320x200x16 screen (physical blocks 0..3), the palette, pictures */
#define SCREEN_BLK 0
#define GFX_ROWBYTES 160
extern u8 gfx_pal[16];                    /* EGA register values last set (also copied to the mailbox for the harness) */
void gfx_init(void);
void gfx_palette(u8 reg, u8 ega);
void gfx_default_palette(void);
void gfx_clear(u8 value);                 /* both pixels of every byte */
u8 gfx_show_title(RsFile *f, u8 block);   /* a full-screen picture record into the screen */
void gfx_pal_reg(u8 reg, u8 color);       /* SetPaletteRegister (res07 0464:2A0D): the game's colour 0..15 into the register */

/* Text (res06): the 8x8 font of DAX block 201 of 8X8D1, 40x25 cells of 8x8 pixels, colour a 4-bit pixel value. */
u8 gfx_font_load(RsFile *f);              /* LoadGameFont; the file is the open 8X8D1.DAX; 0 = ok */
u8 gfx_font_load_e(RsFile *f, const DaxEntry *e);   /* the same from the entry a volume gave (block 201 of 8X8D1) */
void gfx_glyph(u8 col, u8 row, u8 color, u8 count, u8 glyph, u8 textset);   /* DrawGlyph; textset: fold to the 64-glyph set */
void gfx_text(u8 col, u8 row, u8 color, const char *s);                      /* DrawTextAt */

/* Pictures (res07): kept in physical blocks from PIC_FIRST_BLK up (a picture never crosses a block), items of
 * height x wcols cells packed 4 bits a pixel, wcols * 4 bytes a row, optionally with a mask picture of the same layout
 * (a mask byte keeps the bits of the destination where the picture's colour key was). */
#define PIC_FIRST_BLK 8
#define PIC_LAST_BLK 0x37
#define PIC_MAX 0x2000                    /* bytes of one picture with its mask: it fits one block */
typedef struct Pic {
    u8 blk;                               /* physical block of the data (window slot 6) */
    u16 off;                              /* of item 0 in the block */
    u16 moff;                             /* of the mask of item 0; 0 = no mask */
    u16 bytesize;                         /* bytes of one item: height * wcols * 4 */
    u8 height, wcols, items;
} Pic;
u8 pic_load(Pic *p, RsFile *f, u8 id, u8 key, u8 masked);   /* LoadPicture + UnpackPicturePixels; 0 = ok */
u8 pic_load_e(Pic *p, RsFile *f, const DaxEntry *e, u8 key, u8 masked);   /* the same from a DaxEntry (a volume's index) */
void gfx_item(const Pic *p, u8 item, u8 col, u8 row);       /* ShowPicture: one item to the screen at cell col, pixel row 8*row */

/* The staging buffer DrawBuf (168 rows of 21 cells, blocks 4 and 5): blits mark what they change, the flush copies the
 * changed span of each row to the screen, 8 pixels right and 8 rows down (res07 DrawPictureItem, FillPictureRect,
 * FlushPictureChanges). Unlike the original the blits refuse what does not fit instead of writing past the buffer. */
#define DB_ROWS 168
#define DB_COLS 21
void db_init(void);                       /* AllocatePicture + the trackers cleared */
void db_item(const Pic *p, u8 item, u8 col, u8 row, u8 flags);               /* DrawPictureItem (flags bit 0: masked) */
void db_fill(s16 col, s16 row, u16 w, u16 h, u8 color);                      /* FillPictureRect (col, w in cells; row, h in pixel rows) */
void db_flush(void);                      /* FlushPictureChanges */

#endif
