/* gamemap.h: the physical memory of the game build (step 8.5c), as the engine and the game core both see it. */
#ifndef GAMEMAP_H
#define GAMEMAP_H
#define GAME_BLK 0x30          /* the core: three blocks, task 0 slots 1..3 */
#define VMBLK_DS 0x10          /* the four pages of paged DGROUP */
#define VMBLK_HEAP 0x14        /* the first four pages of the banked heap */
#define VMBLK_HEAP2 0x24       /* the next four */
#define NBPAGES 8
#define BANK_POOL_FIRST 0x18   /* the code banks: two blocks each, 12 of them */
#define BANK_POOL_END 0x24    /* six banks; $24..$27 are banked heap pages and $28..$2F pictures */
#define BANK_SLOT7 0x3C        /* the seventh: $3C and $3D, which DSKCON leaves alone (src/engtest/t_hide.c; $3E is a spare block, $3F stays reserved) */
void game_launch(void);        /* shared memory: leave the engine's task and jump to the game's entry */
#endif
