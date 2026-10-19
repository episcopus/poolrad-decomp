/* coco_map.h: where the game's memory is in the 64 KB map of the CoCo 3 (task 0) and in physical memory. Step 8.5c.
 *
 *   $0900..$1FFF  mailbox, stack, direct page variables, the mailbox (shared by both tasks)
 *   $2000..$51FF the game core: code and read only data, then bss (build/game/core.map says where it ends)
 *   HEAPDATA      the tables of the runtime bank's heap ($4C80..$4E12)
 *   VM_NAT_BASE   $4E20: the globals the layout keeps native, then the mapped heap up to $7FFF
 *   $8000..$BFFF  the code window (a bank)
 *   $C000, $E000  the two data windows (vm.asm)
 * DGROUP offsets are the same numbers: below $8000 they are addresses, from $8000 on the paged globals (four pages).
 */
#ifndef COCO_MAP_H
#define COCO_MAP_H
#include "vmlayout.h"
#define HEAPDATA 0x4C80u       /* the heap's tables (struct HeapData of rtl_heap.c, 403 bytes): the runtime bank has no variables */
#define VMBLK_DS 0x10          /* physical blocks of the four pages of paged DGROUP (the engine's pictures start at $08: moved later) */
#define VMBLK_HEAP 0x14        /* and of the four pages of the banked heap */
#endif
