/* ide.c: the game's storage on a CompactFlash card (or an IDE drive) behind a Cloud-9 SuperIDE or a Glenside interface (step 8.12, docs/PHASE-8.12.md).
 *
 * The same container image as the other media (img.c: one run of 256-byte sectors, addressed by logical sector number), laid out on the card by
 * tools/mkimage.py --ide: the card moves 512 bytes a sector, so TWO of the game's sectors share one, except the saves area, where each sector has
 * a card sector of its own (the other half is zeros): a save is a write of one sector, and a half that is changed needs no read first. The card
 * sector of the image's sector 0 is IDE_LBA_BASE (ide_cfg.h, from the Makefile's IDE_* variables):
 *     lsn <  s0               card sector IDE_LBA_BASE + lsn / 2, the half lsn % 2
 *     s0 <= lsn < s1          IDE_LBA_BASE + s0 / 2 + (lsn - s0), the first half            (s0 = img_save_lsn, s1 = s0 + img_save_sectors, both even)
 *     s1 <= lsn               IDE_LBA_BASE + s0 / 2 + (s1 - s0) + (lsn - s1) / 2, the half lsn % 2
 * Nothing else of the card is ever written, and nothing before the first sector of the image has said PIM2: a card that is not the game's is left as it is.
 *
 * This replaces flop.c and sdc.asm in the engine of the IDE build (tools/mkgame.py with IDE=1): there is no room for all three media in the engine, and the
 * disks and the SDC have no use here. flop_detect, flop_setup and flop_io are the names img.c and vol.c call. No disk is ever asked for. */
#include "eng.h"
#include "ide_cfg.h"

#ifndef ENG_TEST

#define IDE_REG(n) (*(volatile u8 *)(IDE_ADDR + (n)))
#define R_FEAT 1
#define R_STAT 7
#define TXT ((u8 *)0x0400)                   /* the splash's text screen */

#define CMD_READ 0x20
#define CMD_WRITE 0x30
#define CMD_FEATURES 0xEF

u8 medium;                                   /* 0: none, 3: the card */
u8 ide_dev;                                  /* the device byte: $E0 the master, $F0 the slave (LBA mode) */
u8 ide_mode;                                 /* how the data register is read: 0 words (the latch), 1 bytes (8 bit transfers on) */
static u8 diag_status, diag_stage, diag_dev, diag_mode;

u8 ide_cmd(u8 cmd, u8 count, u8 lba_hi, u16 lba_lo);     /* ide_xfer.asm: 0 = started */
u8 ide_in(u8 *dst, u8 n, u8 mode);                       /* the data of a read: mode 0 n sectors, 1 the second half of one, 2 the first half of one */
u8 ide_out(const u8 *src);                               /* the data of a write: 256 bytes and 256 zeros */

static void say_at(u8 row, u8 col, const char *s)
{
    u8 *p = TXT + (u16)row * 32 + col;
    u8 c;
    while ((c = (u8)*s++) != 0)
        *p++ = (u8)(c >= 0x40 ? c - 0x40 : c);
}

static void hex_at(u8 row, u8 col, u8 v)
{
    u8 *p = TXT + (u16)row * 32 + col;
    u8 d = (u8)(v >> 4);
    *p++ = (u8)(d < 10 ? '0' + d : 'A' - 0x40 + d - 10);
    d = (u8)(v & 15);
    *p = (u8)(d < 10 ? '0' + d : 'A' - 0x40 + d - 10);
}

/* the first four bytes of dsk_buf are the image's PIM2 */
static u8 is_image(void)
{
    return dsk_buf[0] == 'P' && dsk_buf[1] == 'I' && dsk_buf[2] == 'M' && dsk_buf[3] == '2';
}

/* the card has not answered, or what it holds is not the game's: nothing can be loaded, so say what was seen and stop (the player has the splash screen up) */
static void give_up(void)
{
    u8 i;
    for (i = 0; i < 8; i++)
        say_at((u8)(7 + i), 0, "                                ");
    say_at(7, 0, "POOL OF RADIANCE: THE IDE CARD");
    if (diag_stage == 0)
        say_at(9, 0, "NO IDE DEVICE ANSWERED");
    else if (diag_stage == 1)
        say_at(9, 0, "THE CARD DID NOT SEND A SECTOR");
    else
        say_at(9, 0, "NO GAME DATA AT THE SET PLACE");
    say_at(11, 0, "STATUS");
    hex_at(11, 7, diag_status);
    say_at(11, 11, "DEVICE");
    hex_at(11, 18, diag_dev);
    say_at(11, 22, "MODE");
    hex_at(11, 27, diag_mode);
    say_at(13, 0, "FIRST BYTES");
    for (i = 0; i < 6; i++)
        hex_at(13, (u8)(12 + 3 * i), dsk_buf[i]);
    for (;;)
        ;
}

/* the first sector of the image through the card, into dsk_buf: 0 = it is there */
static u8 try_header(void)
{
    u8 st;
    dsk_buf[0] = 0;
    st = ide_cmd(CMD_READ, 1, (u8)(IDE_LBA_BASE >> 16), (u16)IDE_LBA_BASE);
    diag_stage = 1;
    if (st == 0)
        st = ide_in(dsk_buf, 1, 2);
    diag_status = st;
    diag_dev = ide_dev;
    diag_mode = ide_mode;
    if (st != 0)
        return st;
    diag_stage = 2;
    return is_image() ? 0 : 0xFE;
}

/* SET FEATURES: 1 enables the 8 bit transfers, $81 goes back to words. The card may refuse (the error bit): the header read that follows says what it does
 * (the next command waits until this one is done) */
static void features(u8 f)
{
    IDE_REG(R_FEAT) = f;
    ide_cmd(CMD_FEATURES, 0, 0, 0);
}

/* 1 when a card with the game on it is there; sets medium, the device and the way to read the data register */
u8 flop_detect(void)
{
    u8 d, st;
    medium = 0;
    diag_stage = 0;
    for (d = 0; d < 2; d++) {
        ide_dev = d == 0 ? 0xE0 : 0xF0;
        IDE_REG(6) = ide_dev;                 /* a device that is not there leaves the bus as it was ($FF) or lets it float to 0 */
        st = IDE_REG(R_STAT);
        if (st == 0xFF || st == 0x00)
            continue;
        if (diag_stage == 0)
            diag_stage = 1;
        ide_mode = 1;                         /* bytes first: the fast way, and the one that needs no latch */
        features(1);
        if (try_header() == 0) {
            medium = 3;
            return 1;
        }
        features(0x81);
        ide_mode = 0;
        if (try_header() == 0) {
            medium = 3;
            return 1;
        }
    }
    give_up();
    return 0;
}

/* (nothing of the floppy medium's header: img.c calls this for a header that has one) */
void flop_setup(const u8 *e)
{
    (void)e;
}

/* sectors between the image and physical RAM, through the card: reads anywhere, writes in the saves area only; see the layout at the top */
u8 flop_io(u8 cmd, u32 lsn, u16 count, u8 blk, u16 off)
{
    u8 *p, old = 0, w = 0, st = 0, tries, m, ns;
    u32 s0 = img_save_lsn, s1 = s0 + img_save_sectors, lba;
    u16 n;
    if (blk >= 0x38 && blk <= 0x3B) {
        p = (u8 *)(((u16)(blk - 0x38) << 13) + off);        /* slots 0..3: the same in both tasks */
    } else {
        old = MMU_W1;
        MMU_W1 = blk;
        w = 1;
        p = WIN1 + off;
    }
    while (count > 0 && st == 0) {
        if (lsn >= s0 && lsn < s1) {                        /* the saves: a card sector each, the first half */
            lba = IDE_LBA_BASE + (s0 >> 1) + (lsn - s0);
            n = 1;
            m = 2;
            ns = 1;
        } else if (cmd != SEC_READ) {
            st = 0xFD;                                      /* (the packed part of the image is never written) */
            break;
        } else {
            lba = lsn < s0 ? (lsn >> 1) : (s0 >> 1) + (s1 - s0) + ((lsn - s1) >> 1);
            lba += IDE_LBA_BASE;
            if (lsn & 1) {                                  /* the second half of a card sector */
                n = 1;
                m = 1;
                ns = 1;
            } else if (count >= 2) {                        /* whole card sectors: as many as there are pairs, in one command, not across s0 */
                n = (u16)(count & ~1u);
                if (lsn < s0 && lsn + n > s0)
                    n = (u16)(s0 - lsn);
                if (n > 64)
                    n = 64;
                m = 0;
                ns = (u8)(n >> 1);
            } else {                                        /* the first half of the last card sector */
                n = 1;
                m = 2;
                ns = 1;
            }
        }
        for (tries = 0; tries < 3; tries++) {
            if (cmd == SEC_READ) {
                st = ide_cmd(CMD_READ, ns, (u8)(lba >> 16), (u16)lba);
                if (st == 0)
                    st = ide_in(p, m == 0 ? ns : 1, m);
            } else {
                st = ide_cmd(CMD_WRITE, 1, (u8)(lba >> 16), (u16)lba);
                if (st == 0)
                    st = ide_out(p);
            }
            if (st == 0)
                break;
        }
        p += (u16)(n << 8);
        lsn += n;
        count = (u16)(count - n);
    }
    if (w)
        MMU_W1 = old;
    return st != 0;
}
#endif
