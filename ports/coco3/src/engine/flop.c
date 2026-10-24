/* flop.c: the game's storage on a set of floppy disks (step 8.10, docs/PHASE-8.10.md).
 *
 * The image of img.c (one run of 256-byte sectors, addressed by logical sector number) is cut into disks by tools/mkimage.py
 * --medium floppy: disk n holds the sectors dbase[n-1] .. dbase[n]-1. Every disk is an RS-DOS disk (tools/decbfs.py) whose first
 * directory entry is the data file POOLDSKn.DAT, in consecutive granules, so sector k of the disk is at granule first + k / 9 and the
 * disk says which one it is by that name; disk 1 also holds POOL.BIN, which LOADM started. Sectors are read and written through
 * DSKCON (disk.asm), and a sector on a disk that no drive holds asks for it on the text screen (the splash's: a CoCo 1 style screen at
 * $0400, which the GIME shows when its CoCo bit is set and which the game never touches).
 *
 * Drives: with two or more, disk 1 (the code, the index, the saves' neighbour) stays in drive 0 and the other disks take turns in
 * the least recently used of the rest; with one drive every change of disk is a swap. The prompt tells how to switch: key 1 or 2. */
#include "eng.h"

#ifndef ENG_TEST

#define MAXD 14
#define SWP_REQ (*(volatile u8 *)0x090C)     /* the disk wanted (1..), 0 = none: the harness' cue to mount it (lua/watch.lua MB_FLOP) */
#define SWP_DRV (*(volatile u8 *)0x090D)     /* in which drive */
#define SWP_ACK (*(volatile u8 *)0x090F)     /* the harness sets it when the disk is there: the same as pressing ENTER */
#define TXT ((u8 *)0x0400)                   /* the splash's text screen */
#define TXT_BLK 0x3E                         /* the prompt's: a spare block ($3E is nobody's, src/engine/gamemap.h) */

u8 medium;                                   /* 0: the development backend (the harness serves the sectors), 1: a set of floppy disks */
static u8 nd, ndrv, stamp;
static u32 dbase[MAXD + 1];                  /* the first sector of each disk, then the total */
static u8 dr_disk[4], dr_gran[4], dr_use[4];  /* what each drive holds (1.., 0 = not known), its data file's first granule, when it was used last */

static void say_at(u8 *base, u8 row, u8 col, const char *s)
{
    u8 *p = base + (u16)row * 32 + col;
    u8 c;
    while ((c = (u8)*s++) != 0)
        *p++ = (u8)(c >= 0x40 ? c - 0x40 : c);
}

#define say(row, col, s) say_at(TXT, row, col, s)

/* 1 when the first seven bytes at b are the name */
static u8 same7(const u8 *b, const char *name)
{
    u8 i;
    for (i = 0; i < 7; i++)
        if (b[i] != (u8)name[i])
            return 0;
    return 1;
}

/* the disk in a drive: its number, 0 when the directory is not that of a disk of the set; remembers the first granule of the data file. The sector is read into
 * b: dsk_buf while the engine starts (the splash is on the text screen), the text screen's memory after (dsk_buf may hold a sector that is being written) */
static u8 ident(u8 drive, u8 *b)
{
    u8 n;
    if (dsk_read_to(drive, 17, 3, b) != 0 || !same7(b, "POOLDSK"))
        return 0;
    n = b[7];
    n = (u8)(n >= 'A' ? n - 'A' + 10 : n - '0');
    if (n == 0 || n > MAXD)
        return 0;
    dr_gran[drive] = b[13];
    return n;
}

/* 1 when the disk in drive 0 is disk 1 of a set: from then on the sectors come from the disks (a second drive with a disk of the set is used too) */
u8 flop_detect(void)
{
    u8 n;
    medium = 0;
    if (dsk_read(0, 17, 3) == 0 && same7(dsk_buf, "POOLSDC")) {  /* the CoCo SDC's single image: its first 630 sectors are a disk with this marker, the game's image follows */
        medium = 2;
        say(6, 2, "STORAGE: COCO SDC      ");
        return 1;
    }
    if (ident(0, dsk_buf) != 1)
        return 0;
    dr_disk[0] = 1;
    for (ndrv = 1; ndrv < 4; ndrv++) {          /* how many drives hold a disk of the set (the player puts disk 2 in the second one); the others are asked for */
        n = ident(ndrv, dsk_buf);
        if (n == 0)
            break;
        dr_disk[ndrv] = n;
    }
    nd = 1;                                   /* until the header says how large disk 1 is: every sector is on it */
    dbase[1] = 0x7FFFFFFFUL;
    medium = 1;
    say(6, 2, "STORAGE: FLOPPY DISKS ");              /* the splash's line (boot.asm's said DEV) */
    return 1;
}

/* the part of the image's header that tells the disks apart: from byte 24, the medium (1), the number of disks, a word of sectors for each */
void flop_setup(const u8 *e)
{
    u8 i;
    nd = e[1];
    if (nd > MAXD)
        nd = MAXD;
    dbase[0] = 0;
    for (i = 0; i < nd; i++)
        dbase[i + 1] = dbase[i] + (u16)(((u16)e[2 + 2 * i] << 8) | e[3 + 2 * i]);
}

/* the prompt: the CoCo's text screen on, in a block of its own (the visible text area of MAME's GIME is taller than the 16 rows of 32: $0400 would show
 * what lies behind it), the palette as the text wants it (the foreground is an odd register, the background the even one before it), a wait for
 * ENTER (or the harness), then the game's screen again */
static u8 prompt(u8 disk, u8 drive, u8 found)
{
    u8 saved[16], i, k = 0, old;
    u16 c;
    u8 *p;
    for (i = 0; i < 16; i++)
        saved[i] = gfx_pal[i];
    old = MMU_W1;
    MMU_W1 = TXT_BLK;
    for (p = WIN1; p < WIN1 + 1024; p++)                       /* (not k_fill: its scratch is the far call trampoline's FC_X, the entry a bank load is for) */
        *p = 0x20;
    say_at(WIN1, 5, 8, "INSERT DISK");
    p = WIN1 + 5 * 32 + 20;
    i = disk;
    if (i >= 10) {
        *p++ = '1';
        i = (u8)(i - 10);
    }
    *p = (u8)('0' + i);
    say_at(WIN1, 7, 6, "IN THE");
    if (ndrv > 1)
        say_at(WIN1, 7, 13, drive == 0 ? "FIRST" : drive == 1 ? "SECOND" : drive == 2 ? "THIRD" : "FOURTH");
    say_at(WIN1, 7, 20, "DRIVE");
    say_at(WIN1, 10, 4, "THEN PRESS ENTER");
    if (found != 0xFF) {                                       /* a second try: what the drives held */
        if (found == 0)
            say_at(WIN1, 12, 4, "NO DISK OF THE GAME THERE");
        else {
            say_at(WIN1, 12, 4, "THAT WAS DISK");
            WIN1[12 * 32 + 18] = (u8)('0' + found % 10);
        }
    }
    say_at(WIN1, 14, 2, "KEY 1 TO 4: HOW MANY DRIVES");
    MMU_W1 = old;
    for (i = 0; i < 16; i++)
        *(u8 *)(0xFFB0 + i) = (u8)(i & 1 ? 0x12 : 0);          /* the text: green on black */
    *(u8 *)0xFF99 = 0;                                         /* 192 lines */
    *(u8 *)0xFF9D = 0xE0;                                      /* the CoCo mode's video start: the 64 KB page $70000 from here (bits 18 to 16), the SAM's F bits in it */
    *(u8 *)0xFF9E = 0;
    *(u8 *)0xFFC8 = 0;                                         /* SAM F1 off, F5 and F6 on: $C000 into the page (F = $C000 / 512 = 96), the text block $3E */
    *(u8 *)0xFFD1 = 0;
    *(u8 *)0xFFD3 = 0;
    *(u8 *)0xFF90 = (u8)(eng_init0 | 0x80);                    /* the CoCo's own screen (the splash's) */
    while (kbd_get() != 0)                                     /* keys typed ahead are the game's, not an answer */
        ;
    SWP_DRV = drive;
    SWP_ACK = 0;
    SWP_REQ = disk;
    for (;;) {
        c = kbd_get();
        if (SWP_ACK != 0 || (u8)c == 13)
            break;
        if ((u8)c >= '1' && (u8)c <= '4') {
            k = (u8)c;
            break;
        }
    }
    SWP_REQ = 0;
    *(u8 *)0xFF90 = eng_init0;
    *(u8 *)0xFFD0 = 0;                                         /* the SAM's F bits as BASIC had them: $0400 */
    *(u8 *)0xFFD2 = 0;
    *(u8 *)0xFFC9 = 0;
    *(u8 *)0xFF99 = 0x3E;
    *(u8 *)0xFF9D = (u8)((SCREEN_BLK * 0x2000UL) >> 11);
    *(u8 *)0xFF9E = 0;
    for (i = 0; i < 16; i++)
        gfx_palette(i, saved[i]);
    return k;
}

/* the drive that holds disk d (0 based) after this call, asking for it when no drive does. After ENTER every drive is looked at (the player may have
 * used another than the one asked for); what the asked one held is said on the next prompt */
static u8 drive_for(u8 d)
{
    u8 want = (u8)(d + 1), v, i, k, found = 0xFF, dd, lim;
    for (v = 0; v < ndrv; v++)
        if (dr_disk[v] == want) {
            dr_use[v] = ++stamp;
            return v;
        }
    for (;;) {
        v = 0;
        if (ndrv > 1 && want != 1) {
            v = 1;
            for (i = 2; i < ndrv; i++)
                if (dr_use[i] < dr_use[v])
                    v = i;
        }
        dr_disk[v] = 0;
        k = prompt(want, v, found);
        if (k != 0) {                                 /* a key 1 to 4: the player has that many drives */
            ndrv = (u8)(k - '0');
            continue;
        }
        for (i = 0; i < 2 && ident(v, TXT) == 0; i++)    /* the drive that was asked for gets a few tries: a disk that was just put in is not read at once */
            ;
        lim = found == 0xFF ? ndrv : 4;               /* the first ENTER looks at the drives there are; if that was not it, at all four */
        for (i = 0; i < lim; i++) {
            dd = (u8)(v + i);
            if (dd >= lim)
                dd = (u8)(dd - lim);
            k = ident(dd, TXT);
            dr_disk[dd] = k;                          /* what the drive holds now */
            if (dd == v)
                found = k;
            if (k == want) {
                if (dd >= ndrv)
                    ndrv = (u8)(dd + 1);
                dr_use[dd] = ++stamp;
                return dd;
            }
        }
    }
}

/* a sector between dsk_buf and physical block blk at off */
static void move(u8 to_buf, u8 blk, u16 off)
{
    u8 *p, w = 0, old = 0;
    if (blk >= 0x38 && blk <= 0x3B) {
        p = (u8 *)(((u16)(blk - 0x38) << 13) + off);        /* slots 0..3: the same in both tasks */
    } else {
        old = MMU_W1;
        MMU_W1 = blk;
        w = 1;
        p = WIN1 + off;
    }
    if (p != dsk_buf) {
        if (to_buf) {
            k_copy(dsk_buf, p, 128);
            k_copy(dsk_buf + 128, p + 128, 128);
        } else {
            k_copy(p, dsk_buf, 128);
            k_copy(p + 128, dsk_buf + 128, 128);
        }
    }
    if (w)
        MMU_W1 = old;
}

#define SDC_BASE 630L                          /* the image starts behind the 35 track disk that holds POOL.BIN (tools/mkimage.py --sdc) */
u8 sdc_xfer(u8 cmd, u8 lsn_hi, u16 lsn_lo);     /* sdc.asm: one sector between the card and dsk_buf; 0 = ok */

/* sectors between the image and physical RAM: on the disks (medium 1, with the prompts for the ones no drive holds) or through the CoCo SDC's command mode (2) */
u8 flop_io(u8 cmd, u32 lsn, u16 count, u8 blk, u16 off)
{
    u8 d, dr = 0, track = 0, sec = 0, st, tries;
    u16 k, g;
    u32 card;
    while (count > 0) {
        if (medium == 1) {
            d = 0;
            while (d + 1 < nd && lsn >= dbase[d + 1])
                d++;
            k = (u16)(lsn - dbase[d]);
            dr = drive_for(d);
            g = (u16)(dr_gran[dr] + k / 9);
            track = (u8)(g >> 1);
            if (track >= 17)
                track++;
            sec = (u8)((g & 1 ? 10 : 1) + k % 9);
        }
        if (cmd != SEC_READ)
            move(1, blk, off);
        card = lsn + SDC_BASE;
        for (tries = 0; tries < 3; tries++) {
            if (medium == 2)
                st = sdc_xfer(cmd == SEC_READ ? 0x80 : 0xA0, (u8)(card >> 16), (u16)card);
            else
                st = cmd == SEC_READ ? dsk_read(dr, track, sec) : dsk_write(dr, track, sec);
            if (st == 0)
                break;
        }
        if (st != 0)
            return 1;
        if (cmd == SEC_READ)
            move(0, blk, off);
        lsn++;
        count--;
        off = (u16)(off + 256);
    }
    return 0;
}
#endif
