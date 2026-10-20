/* rtl_vm.c: addresses of the game (step 8.5c). A farptr the game holds is DGROUP's segment and an offset (a native global or
 * heap block below $8000: the offset is the address; a paged global from $8000 up), a pointer into a native or window
 * address it took with @ (rtl_far), or a block of the banked heap (BSEG + the page in the high word, the offset in the page in the low one).
 * vm_far turns any of them into a pointer, mapping a page when it has to; vm_bp (vm.asm) does the banked ones fast. */
#include "pool.h"

void *vm_pp(u8 id, u16 off);
extern u8 vm_w0, vm_w1;
extern u8 vm_pgblk[16];
void vm_reset(void);


void *vm_unplaced(u16 off)
{
    rtl_fatal_code(0x10, off);
    return 0;
}

void *vm_far(farptr f)
{
    u16 seg = (u16)(f >> 16), off = (u16)f;
    if (seg == POOL_DS_SEG) {
        if (off < 0x8000u)
            return (void *)off;
        return vm_ptr(off);
    }
    if (f == 0)
        return (void *)0;                     /* a nil read through: the page at address 0 (the host reads it too) */
    if ((seg >> 8) == (BSEG >> 8) && (u16)(seg - BSEG) < NBPAGES)
        return vm_pp((u8)(4 + (seg - BSEG)), off);
    rtl_fatal_code(0x11, off);
    return (void *)0;
}

/* the address of a variable or a block the game took: a native one stays what it is (the offset is the address), one
 * in a window is the page it shows plus the offset in the window */
farptr rtl_far(const void *p)
{
    u16 a = (u16)p;
    u8 id;
    if (a < 0xC000u)
        return POOL_FARPTR(POOL_DS_SEG, a);
    id = a < 0xE000u ? vm_w0 : vm_w1;
    if (id == 0xFF)
        rtl_fatal_code(0x13, a);
    if (id < 4)
        return POOL_FARPTR(POOL_DS_SEG, 0x8000u + ((u16)id << 13) + (a & 0x1FFFu));
    return POOL_FARPTR((u16)(BSEG + (id - 4)), (u16)(a & 0x1FFFu));
}

/* the physical block of every page, from the layout in coco_map.h (the loader may have changed it) */
void vm_init(void)
{
    u8 i;
    for (i = 0; i < 4; i++) {
        vm_pgblk[i] = (u8)(VMBLK_DS + i);
        vm_pgblk[4 + i] = (u8)(VMBLK_HEAP + i);
        vm_pgblk[8 + i] = (u8)(VMBLK_HEAP2 + i);
    }
    vm_reset();
}
