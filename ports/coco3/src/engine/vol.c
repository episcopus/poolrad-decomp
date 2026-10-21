/* vol.c: volumes (step 8.4): one RS-DOS floppy holds one container file POOLVOL.DAT with the blocks of many DAX files
 * (tools/mkvolumes.py documents the layout). Mounting reads the index of the volume once into engine memory (physical
 * blocks 6 and 7, 4 KB a drive); a lookup is then a scan of RAM, no disk access, and gives a DaxEntry that dax_unpack and
 * pic_load_e take as they are. Up to four volumes, one a drive. */
#include "eng.h"

#define IDX_BLK 6                         /* physical blocks 6 and 7: drive d at block 6 + d / 2, offset 4096 * (d & 1) */
#define IDX_MAX 4096

Vol vols[4];
#ifndef ENG_TEST                            /* (the engine tests of 8.3 and 8.4 are built without the image and what only the game uses: their disks are small) */
Vol img_vol;
u32 img_save_lsn;
u16 img_save_sectors;
#define ENT_AT 0x600                      /* the entry table of the image in blocks 6 and 7 (one 16 KB run at $8000 through windows 0 and 1), behind the table of files */
#define ENT_END 0x4000

/* The image (tools/mkimage.py, "PIM2"): header { "PIM2", u16 nfiles, u16 nent, u32 files_off, u32 ents_off, u32 save_lsn, u16
 * save_sectors }, the table of files (name8, u16 first entry, u16 count; kept in physical block 6) and the table of entries
 * (the 10 byte entries of the volumes), which follows it in blocks 6 and 7: read once at mount, so that a lookup is a scan of RAM (it used to read
 * the entries from the image a chunk at a time: two requests of the medium for every bank loaded, step 8.9c). */
u8 img_mount(void)
{
    u8 h[24];
    u16 n;
    u32 files_off, ents_off;
    img_vol.mounted = 0;
    img_vol.drive = IMG_DRIVE;
    img_vol.f.drive = IMG_DRIVE;
    if (img_read(0, h, 24) != 0)
        return 1;
    if (h[0] != 'P' || h[1] != 'I' || h[2] != 'M' || h[3] != '2')
        return 2;
    img_vol.nfiles = (u8)(((u16)h[4] << 8) | h[5]);
    img_vol.nent = (u16)(((u16)h[6] << 8) | h[7]);
    files_off = ((u32)h[8] << 24) | ((u32)h[9] << 16) | ((u32)h[10] << 8) | h[11];
    ents_off = ((u32)h[12] << 24) | ((u32)h[13] << 16) | ((u32)h[14] << 8) | h[15];
    img_save_lsn = ((u32)h[16] << 24) | ((u32)h[17] << 16) | ((u32)h[18] << 8) | h[19];
    img_save_sectors = (u16)(((u16)h[20] << 8) | h[21]);
    n = (u16)((u16)img_vol.nfiles * 12u);       /* (CMOC multiplies two bytes in 8 bits) */
    if (n > ENT_AT || (u16)(ENT_AT + (u16)img_vol.nent * 10u) > ENT_END)
        return 3;
    if (img_read_blocks(files_off, n, 6) != 0)
        return 4;
    if (img_read_blocks_at(ents_off, (u16)((u16)img_vol.nent * 10u), 6, ENT_AT) != 0)
        return 5;
    img_vol.mounted = 1;
    return 0;
}

/* a file of the image: its first entry and count, 0xFF when there is none */
static u8 img_file(const char *name8, u16 *first, u16 *count)
{
    u8 i, j, *t;
    win_set(0, 6);
    for (i = 0; i < img_vol.nfiles; i++) {
        t = (u8 *)0x8000u + (u16)i * 12;
        for (j = 0; j < 8; j++)
            if (t[j] != (u8)name8[j])
                break;
        if (j == 8) {
            *first = (u16)(((u16)t[8] << 8) | t[9]);
            *count = (u16)(((u16)t[10] << 8) | t[11]);
            return i;
        }
    }
    return 0xFF;
}

static u8 img_find(const char *name8, u8 id, DaxEntry *e)
{
    u16 first, count, k;
    const u8 *p;
    if (img_file(name8, &first, &count) == 0xFF)
        return 1;
    win_set(0, 6);
    win_set(1, 7);
    p = (const u8 *)0x8000u + ENT_AT + (u16)(first * 10u);
    for (k = 0; k < count; k++, p += 10)
        if (p[1] == id) {
            e->offset = ((u32)p[2] << 24) | ((u32)p[3] << 16) | ((u32)p[4] << 8) | p[5];
            e->packed = (u16)(((u16)p[6] << 8) | p[7]);
            e->raw = (u16)(((u16)p[8] << 8) | p[9]);
            return 0;
        }
    return 2;
}

/* an object of the image by name and id: 0 = found, 1 = no such file, 2 = no such block */
u8 img_entry(const char *name8, u8 id, DaxEntry *e)
{
    return img_find(name8, id, e);
}
#endif

static u8 *idx_ptr(u8 drive)
{
    win_set(0, (u8)(IDX_BLK + (drive >> 1)));
    return (u8 *)(0x8000u + ((drive & 1) ? 0x1000u : 0));
}

static u32 be32(const u8 *p)
{
    return ((u32)p[0] << 24) | ((u32)p[1] << 16) | ((u32)p[2] << 8) | p[3];
}

static u16 be16(const u8 *p)
{
    return (u16)(((u16)p[0] << 8) | p[1]);
}

u8 vol_mount(Vol *v, u8 drive)
{
    u8 hdr[256], st, *d;
    u16 pos, idx_len;
    v->mounted = 0;
    v->drive = drive;
    st = rs_mount(drive);
    if (st != 0)
        return st;
    st = rs_open(&v->f, drive, "POOLVOL ", "DAT");
    if (st != 0)
        return st == 1 ? 1 : st;
    st = rs_read(&v->f, 0, hdr, 256);
    if (st != 0)
        return st;
    if (hdr[0] != 'P' || hdr[1] != 'V' || hdr[2] != 'O' || hdr[3] != 'L' || hdr[4] != 1)
        return 1;
    idx_len = be16(hdr + 10);
    if (idx_len > IDX_MAX || idx_len == 0)
        return 1;
    v->num = hdr[5];
    v->nent = be16(hdr + 6);
    v->nfiles = (u8)be16(hdr + 8);
    for (pos = 0; pos < idx_len; pos = (u16)(pos + 256)) {
        if (pos > 0) {
            st = rs_read(&v->f, pos, hdr, 256);
            if (st != 0)
                return st;
        }
        d = idx_ptr(drive);
        k_copy(d + pos, hdr, 128);
        k_copy(d + pos + 128, hdr + 128, 128);
    }
    v->mounted = 1;
    return 0;
}

/* The index of file name8 on this volume, or 0xFF. Leaves the index window mapped. */
static u8 file_index(const Vol *v, const char *name8, u8 *base)
{
    u8 i, j, *names = idx_ptr(v->drive) + 16;
    for (i = 0; i < v->nfiles; i++) {
        for (j = 0; j < 8; j++)
            if (names[(u16)i * 8 + j] != (u8)name8[j])
                break;
        if (j == 8) {
            *base = 0;
            return i;
        }
    }
    return 0xFF;
}

static void entry_at(const Vol *v, u16 i, u8 *file, u8 *id, DaxEntry *e)
{
    const u8 *p = idx_ptr(v->drive) + 16 + (u16)v->nfiles * 8 + i * 10;
    *file = p[0];
    *id = p[1];
    e->offset = be32(p + 2);
    e->packed = be16(p + 6);
    e->raw = be16(p + 8);
}

u8 vol_find(const Vol *v, const char *name8, u8 id, DaxEntry *e)
{
    u8 base, fi = file_index(v, name8, &base), f, b;
    u16 i;
    const u8 *p;
    if (fi == 0xFF)
        return 1;
    p = idx_ptr(v->drive) + 16 + (u16)v->nfiles * 8;      /* the window stays mapped for the scan */
    for (i = 0; i < v->nent; i++, p += 10) {
        if (p[0] == fi && p[1] == id) {
            entry_at(v, i, &f, &b, e);
            return 0;
        }
    }
    return 2;
}

u8 vol_entry(const Vol *v, u16 i, u8 *file, u8 *id, DaxEntry *e)
{
    if (i >= v->nent)
        return 1;
    entry_at(v, i, file, id, e);
    return 0;
}

/* 1 when a mounted volume holds the file at all */
u8 vol_has(const char *name8)
{
    u8 d, base;
    u16 a, b;
#ifndef ENG_TEST
    if (img_vol.mounted && img_file(name8, &a, &b) != 0xFF)
        return 1;
#endif
    for (d = 0; d < 4; d++)
        if (vols[d].mounted && file_index(&vols[d], name8, &base) != 0xFF)
            return 1;
    return 0;
}

u8 vol_lookup(const char *name8, u8 id, Vol **vp, DaxEntry *e)
{
    u8 d, st, seen = 0;
#ifndef ENG_TEST
    if (img_vol.mounted) {
        st = img_find(name8, id, e);
        if (st == 0) {
            *vp = &img_vol;
            return 0;
        }
        if (st == 2)
            seen = 2;
    }
#endif
    for (d = 0; d < 4; d++) {
        if (!vols[d].mounted)
            continue;
        st = vol_find(&vols[d], name8, id, e);
        if (st == 0) {
            *vp = &vols[d];
            return 0;
        }
        if (st == 2)
            seen = 2;
    }
    return seen ? 2 : 1;
}
