/* vol.c: volumes (step 8.4): one RS-DOS floppy holds one container file POOLVOL.DAT with the blocks of many DAX files
 * (tools/mkvolumes.py documents the layout). Mounting reads the index of the volume once into engine memory (physical
 * blocks 6 and 7, 4 KB a drive); a lookup is then a scan of RAM, no disk access, and gives a DaxEntry that dax_unpack and
 * pic_load_e take as they are. Up to four volumes, one a drive. */
#include "eng.h"

#define IDX_BLK 6                         /* physical blocks 6 and 7: drive d at block 6 + d / 2, offset 4096 * (d & 1) */
#define IDX_MAX 4096

Vol vols[4];

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
    for (d = 0; d < 4; d++)
        if (vols[d].mounted && file_index(&vols[d], name8, &base) != 0xFF)
            return 1;
    return 0;
}

u8 vol_lookup(const char *name8, u8 id, Vol **vp, DaxEntry *e)
{
    u8 d, st, seen = 0;
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
