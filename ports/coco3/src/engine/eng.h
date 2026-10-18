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

#endif
