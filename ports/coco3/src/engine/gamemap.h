/* gamemap.h: the physical memory of the game build (step 8.5c), as the engine and the game core both see it. */
#ifndef GAMEMAP_H
#define GAMEMAP_H
#define GAME_BLK 0x30          /* the core: three blocks, task 0 slots 1..3 */
#define VMBLK_DS 0x10          /* the four pages of paged DGROUP */
#define VMBLK_HEAP 0x14        /* the four pages of the banked heap */
#define BANK_POOL_FIRST 0x18   /* the code banks: two blocks each, 12 of them */
#define BANK_POOL_END 0x30
void game_launch(void);        /* shared memory: leave the engine's task and jump to the game's entry */
#endif
