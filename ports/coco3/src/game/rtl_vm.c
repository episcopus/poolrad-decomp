/* rtl_vm.c: addresses of the game (step 8.5c). A farptr the game holds is DGROUP's segment and an offset (a native global or
 * heap block below $8000: the offset is the address; a paged global from $8000 up), a pointer into a native or window
 * address it took with @ (rtl_far), or a block of the banked heap (a PC style segment:offset above DGROUP's segment).
 * vm_far turns any of them into a pointer, mapping a page when it has to. */
#include "pool.h"

void *vm_pp(u8 id, u16 off);
extern u8 vm_w0, vm_w1;
extern u8 vm_pgblk[8];
void vm_reset(void);

#define BHEAP_LIN0 0x2C7C0UL                   /* where the banked heap starts in the linear address of the PC (HeapOrg of the host model) */

void *vm_unplaced(u16 off)
{
    rtl_fatal_code(0x10, off);
    return 0;
}

void *vm_far(farptr f)
{
    u16 seg = (u16)(f >> 16), off = (u16)f;
    u32 lin, rel;
    if (seg == POOL_DS_SEG) {
        if (off < 0x8000u)
            return (void *)off;
        return vm_ptr(off);
    }
    if (f == 0)
        return (void *)0;                     /* a nil read through: the page at address 0 (the host reads it too) */
    lin = ((u32)seg << 4) + off;
    if (lin < BHEAP_LIN0)
        rtl_fatal_code(0x11, off);
    rel = lin - BHEAP_LIN0;
    if (rel >= 0x8000UL)
        rtl_fatal_code(0x12, off);
    return vm_pp((u8)(4 + (u8)(rel >> 13)), (u16)(rel & 0x1FFFu));
}

/* the address of a variable or a block the game took: a native one stays what it is (the offset is the address), one
 * in a window is the page it shows plus the offset in the window */
farptr rtl_far(const void *p)
{
    u16 a = (u16)p;
    u8 id;
    u32 lin;
    if (a < 0xC000u)
        return POOL_FARPTR(POOL_DS_SEG, a);
    id = a < 0xE000u ? vm_w0 : vm_w1;
    if (id == 0xFF)
        rtl_fatal_code(0x13, a);
    if (id < 4)
        return POOL_FARPTR(POOL_DS_SEG, 0x8000u + ((u16)id << 13) + (a & 0x1FFFu));
    lin = BHEAP_LIN0 + ((u32)(id - 4) << 13) + (a & 0x1FFFu);
    return POOL_FARPTR((u16)(lin >> 4), (u16)(lin & 15u));
}

/* the physical block of every page, from the layout in coco_map.h (the loader may have changed it) */
void vm_init(void)
{
    u8 i;
    for (i = 0; i < 4; i++) {
        vm_pgblk[i] = (u8)(VMBLK_DS + i);
        vm_pgblk[4 + i] = (u8)(VMBLK_HEAP + i);
    }
    vm_reset();
}
