/* img.c: the game's storage (step 8.5, decision D13 of the porting guide): ONE container image of 256-byte sectors, addressed by
 * logical sector number, behind a two-call interface:
 *
 *     sec_io(cmd, lsn, count, block, offset)   read (1) or write (2) `count` sectors between the image and physical RAM
 *
 * The development backend (below) is a doorbell at $0960 in slot 0 (the mailbox' neighbour, below the stack area): the engine fills a request block and writes the command byte last; the
 * test harness (lua/watch.lua, a write tap on the doorbell) does the transfer at once and leaves the status in the block. The
 * real backends (DriveWire, SDC command mode, floppy through DSKCON with swap prompts) will implement sec_io; nothing above it
 * changes. The image is laid out by tools/mkimage.py ("PIM2"): a header, a table of files, a table of entries (file, id, byte
 * offset, packed size, raw size: the same entries as the volumes of 8.4) and the blocks; the byte offset of an entry is from
 * the start of the image, so dax_unpack and the picture loader read from it through rs_read exactly as from a floppy file. */
#include "eng.h"

#define REQ ((u8 *)0x0960)                 /* the request block: [0] doorbell/command, [1] status, [2..4] lsn, [5..6] count, [7] block, [8..9] offset */
#define SCRATCH ((u8 *)0x0600)             /* one sector in slot 0 (both tasks see it; BASIC no longer needs it once the engine runs) */
#define SCRATCH_BLK 0x38
#define SCRATCH_OFF 0x0600

u8 sec_io(u8 cmd, u32 lsn, u16 count, u8 blk, u16 off)
{
    u8 *r = REQ;
    r[1] = 0xFF;
    r[2] = (u8)(lsn >> 16);
    r[3] = (u8)(lsn >> 8);
    r[4] = (u8)lsn;
    r[5] = (u8)(count >> 8);
    r[6] = (u8)count;
    r[7] = blk;
    r[8] = (u8)(off >> 8);
    r[9] = (u8)off;
    r[0] = cmd;                             /* the doorbell: the transfer is done when this store has been made */
    return r[1];
}

static u32 cached = 0xFFFFFFFFUL;           /* the sector in SCRATCH */

/* n bytes of the image from byte `offset` into RAM (below $8000 or in slot 0); 0 = ok */
u8 img_read(u32 offset, u8 *dst, u16 n)
{
    u16 o, c;
    u32 lsn;
    while (n > 0) {
        lsn = offset >> 8;
        if (lsn != cached) {
            if (sec_io(SEC_READ, lsn, 1, SCRATCH_BLK, SCRATCH_OFF) != 0) {
                cached = 0xFFFFFFFFUL;
                return 1;
            }
            cached = lsn;
        }
        o = (u16)(offset & 255);
        c = (u16)(256 - o);
        if (c > n)
            c = n;
        if (c > 128) {
            k_copy(dst, SCRATCH + o, 128);
            k_copy(dst + 128, SCRATCH + o + 128, (u8)(c - 128));
        } else {
            k_copy(dst, SCRATCH + o, (u8)c);
        }
        dst += c;
        offset += c;
        n -= c;
    }
    return 0;
}

/* nbytes (at most 64 KB) of the image from byte `offset` (a multiple of 256) into physical blocks first_blk, +1, ... */
u8 img_read_blocks(u32 offset, u16 nbytes, u8 first_blk)
{
    u32 lsn = offset >> 8;
    u16 sectors = (u16)((nbytes + 255u) >> 8), room, c;
    u16 off = 0;
    u8 blk = first_blk;
    while (sectors > 0) {
        room = (u16)((0x2000u - off) >> 8);
        c = sectors < room ? sectors : room;
        if (sec_io(SEC_READ, lsn, c, blk, off) != 0)
            return 1;
        lsn += c;
        sectors = (u16)(sectors - c);
        off = (u16)(off + (c << 8));
        if (off >= 0x2000u) {
            off = 0;
            blk++;
        }
    }
    cached = 0xFFFFFFFFUL;                 /* (the harness may have written SCRATCH's block; the cache is only a guess) */
    return 0;
}

/* nbytes of physical blocks from first_blk into the image at byte `offset` (a multiple of 256) */
u8 img_write_blocks(u32 offset, u16 nbytes, u8 first_blk)
{
    u32 lsn = offset >> 8;
    u16 sectors = (u16)((nbytes + 255u) >> 8), room, c;
    u16 off = 0;
    u8 blk = first_blk;
    while (sectors > 0) {
        room = (u16)((0x2000u - off) >> 8);
        c = sectors < room ? sectors : room;
        if (sec_io(SEC_WRITE, lsn, c, blk, off) != 0)
            return 1;
        lsn += c;
        sectors = (u16)(sectors - c);
        off = (u16)(off + (c << 8));
        if (off >= 0x2000u) {
            off = 0;
            blk++;
        }
    }
    cached = 0xFFFFFFFFUL;
    return 0;
}

/* n bytes (at most 128) from src (RAM below $8000 or in slot 0) into the image at byte `offset`: a sector is read first when
 * it is only changed in part, then written back; 0 = ok */
u8 img_write(u32 offset, const u8 *src, u16 n)
{
    u16 o, c;
    u32 lsn;
    while (n > 0) {
        lsn = offset >> 8;
        o = (u16)(offset & 255);
        c = (u16)(256 - o);
        if (c > n)
            c = n;
        if (c < 256 && lsn != cached) {
            if (sec_io(SEC_READ, lsn, 1, SCRATCH_BLK, SCRATCH_OFF) != 0) {
                cached = 0xFFFFFFFFUL;
                return 1;
            }
        }
        k_copy(SCRATCH + o, src, (u8)c);
        cached = 0xFFFFFFFFUL;
        if (sec_io(SEC_WRITE, lsn, 1, SCRATCH_BLK, SCRATCH_OFF) != 0)
            return 1;
        cached = lsn;
        src += c;
        offset += c;
        n -= c;
    }
    return 0;
}
