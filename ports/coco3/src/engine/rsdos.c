/* rsdos.c: a read-only RS-DOS (Disk BASIC) file system over DSKCON (research 03 1.2).
 * 35 tracks, 18 sectors of 256 bytes, the FAT in sector 2 and the directory in sectors 3..11 of track 17, files in
 * chains of 9-sector granules (two to a track, the directory track skipped). The chain is followed on every read;
 * the last sector read is cached so that a header read as nine-byte entries costs one DSKCON call per sector. */
#include "eng.h"

#ifndef ENG_TEST
u8 rs_read(RsFile *f, u32 offset, u8 *dst, u16 n)      /* the game has no files of its own: everything is read from the image (the engine has no room for more) */
{
    return img_read(offset, dst, n);
}
#else
static u8 fat[4][68];                     /* the FAT of each mounted drive */
static u8 cache_drive = 0xFF, cache_track, cache_sector;

static u8 read_sector(u8 drive, u8 track, u8 sector)
{
    u8 st;
    if (drive == cache_drive && track == cache_track && sector == cache_sector)
        return 0;
    st = dsk_read(drive, track, sector);
    if (st != 0) {
        cache_drive = 0xFF;
        return st;
    }
    cache_drive = drive;
    cache_track = track;
    cache_sector = sector;
    return 0;
}

u8 rs_mount(u8 drive)
{
    u8 st = read_sector(drive, 17, 2);
    u8 i;
    if (st != 0)
        return st;
    for (i = 0; i < 68; i++)
        fat[drive & 3][i] = dsk_buf[i];
    return 0;
}

/* granule g, sector number s within it (0..8) -> track and sector */
static void locate(u8 g, u8 s, u8 *track, u8 *sector)
{
    u8 t = g >> 1;
    if (t >= 17)
        t++;
    *track = t;
    *sector = (u8)((u16)((g & 1) ? 10 : 1) + s);
}

u8 rs_open(RsFile *f, u8 drive, const char *name8, const char *ext3)
{
    u8 sec, e, i, st;
    const u8 *ft = fat[drive & 3];
    for (sec = 3; sec <= 11; sec++) {
        st = read_sector(drive, 17, sec);
        if (st != 0)
            return st;
        for (e = 0; e < 8; e++) {
            const u8 *d = dsk_buf + (u8)(e * 32);
            u8 same = 1;
            if (d[0] == 0xFF)
                return 1;                      /* the end of the directory */
            if (d[0] == 0)
                continue;                      /* deleted */
            for (i = 0; i < 8 && same; i++)
                if (d[i] != (u8)name8[i])
                    same = 0;
            for (i = 0; i < 3 && same; i++)
                if (d[8 + i] != (u8)ext3[i])
                    same = 0;
            if (same) {
                u8 g = d[13];
                u16 n = 0;
                f->drive = drive;
                f->gran0 = g;
                f->last_bytes = (u16)(((u16)d[14] << 8) | d[15]);
                while (!(ft[g] & 0x80)) {       /* count the sectors of the chain */
                    n += 9;
                    g = ft[g];
                }
                n += (u16)(ft[g] & 0x1F);
                f->sectors = n;
                return 0;
            }
        }
    }
    return 1;
}

u8 rs_read(RsFile *f, u32 offset, u8 *dst, u16 n)
{
#ifndef ENG_TEST
    if (f->drive == IMG_DRIVE)
        return img_read(offset, dst, n);
#endif
    u16 idx = (u16)(offset >> 8);
    u16 skip = (u16)(offset & 255);
    const u8 *ft = fat[f->drive & 3];
    u8 g, track, sector, st;
    u16 gi, chunk;
    while (n > 0) {
        g = f->gran0;
        gi = idx / 9;
        while (gi-- > 0) {
            if (ft[g] & 0x80)
                return 2;                       /* read past the end */
            g = ft[g];
        }
        locate(g, (u8)(idx % 9), &track, &sector);
        chunk = (u16)(256 - skip);
        if (chunk > n)
            chunk = n;
        if (chunk == 256 && !(f->drive == cache_drive && track == cache_track && sector == cache_sector)) {
            st = dsk_read_to(f->drive, track, sector, dst);     /* a whole sector, straight to the caller */
            if (st != 0)
                return st;
        } else {
            st = read_sector(f->drive, track, sector);
            if (st != 0)
                return st;
            if (chunk == 256) {
                k_copy(dst, dsk_buf, 128);
                k_copy(dst + 128, dsk_buf + 128, 128);
            } else {
                k_copy(dst, dsk_buf + skip, (u8)chunk);
            }
        }
        dst += chunk;
        n -= chunk;
        skip = 0;
        idx++;
    }
    return 0;
}
#endif
