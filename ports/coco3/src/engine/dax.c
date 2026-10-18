/* dax.c: DAX containers (whitepaper 4.1) read from the disk through rsdos.c, and their blocks unpacked straight into
 * the engine's memory. A DAX file is a header of little-endian words and 9-byte entries (id u8, offset u32, raw u16,
 * packed u16; offsets from the end of the header) followed by RLE-packed blocks. The CoCo is big endian: every
 * multi-byte field goes through le16/le32 here. */
#include "eng.h"

static u16 le16(const u8 *p)
{
    return (u16)(p[0] | ((u16)p[1] << 8));
}

/* Find block id of the open file: its place in the file and its sizes. 0 = found, 1 = no such block, else disk status. */
u8 dax_find(RsFile *f, u8 id, DaxEntry *e)
{
    u8 h[2], ent[9];
    u16 hs, i;
    u8 st = rs_read(f, 0, h, 2);
    if (st != 0)
        return st;
    hs = le16(h);
    for (i = 0; i < hs; i += 9) {
        st = rs_read(f, (u32)2 + i, ent, 9);
        if (st != 0)
            return st;
        if (ent[0] == id) {
            e->offset = (u32)2 + hs + ((u32)le16(ent + 1) | ((u32)le16(ent + 3) << 16));
            e->raw = le16(ent + 5);
            e->packed = le16(ent + 7);
            return 0;
        }
    }
    return 1;
}

/* Unpack block e. The first hdr_n bytes of the result go to hdr (RAM); the rest goes either to ram_dst (RAM; first_blk
 * is 0xFF) or into physical blocks first_blk, first_blk+1 ... through window 0 (8 KB each), starting first_off
 * bytes into the first block. */
u8 dax_unpack(RsFile *f, const DaxEntry *e, u8 *hdr, u8 hdr_n, u8 first_blk, u16 first_off, u8 *ram_dst)
{
    Rle r;
    u8 buf[256];
    u32 off = e->offset;
    u16 left = e->packed;
    u8 phase = hdr_n ? 0 : 1;
    u8 blk = first_blk;
    u8 st, rs;
    u16 got;

    r.mode = 0;
    r.count = 0;
    if (phase == 0) {
        r.dst = hdr;
        r.dstend = hdr + hdr_n;
    } else if (first_blk == 0xFF) {
        r.dst = ram_dst;
        r.dstend = ram_dst + e->raw;
    } else {
        win_set(0, blk);
        r.dst = (u8 *)(0x8000u + first_off);
        r.dstend = (u8 *)0xA000;
    }
    while (left > 0) {
        u16 n = left > 256 ? 256 : left;
        st = rs_read(f, off, buf, n);
        if (st != 0)
            return st;
        off += n;
        left -= n;
        r.src = buf;
        r.srcend = buf + n;
        do {
            rs = k_rle(&r);
            if (rs == 1) {                       /* the output is full */
                if (phase == 0) {
                    phase = 1;
                    if (first_blk == 0xFF) {
                        r.dst = ram_dst;
                        r.dstend = ram_dst + e->raw - hdr_n;
                    } else {
                        win_set(0, blk);
                        r.dst = (u8 *)(0x8000u + first_off);
                        r.dstend = (u8 *)0xA000;
                    }
                } else if (first_blk != 0xFF) {
                    blk++;
                    win_set(0, blk);
                    r.dst = (u8 *)0x8000;
                    r.dstend = (u8 *)0xA000;
                } else {
                    return 3;                    /* more output than the block says */
                }
            }
        } while (rs == 1);
    }
    if (phase == 0)
        return 4;                                /* the block ended inside the header */
    if (first_blk == 0xFF)
        got = (u16)((u16)(r.dst - ram_dst) + hdr_n);
    else
        got = (u16)((u16)(blk - first_blk) * 0x2000u + (u16)((u16)r.dst - 0x8000u) - first_off + hdr_n);
    return got == e->raw ? 0 : 4;               /* fewer bytes than the index says */
}
