/* t_task.c: step 8.5a. The engine's own address space (MMU task 1). The game, task 0, keeps slots 6 and 7 as its data
 * windows; the engine, task 1, has the same slots 0 to 3, 6 and 7 but its own slots 4 and 5 (windows 0 and 1). A call
 * into the engine (eng_enter ... eng_leave) switches task, uses the windows freely, and switches back; a pointer the
 * caller holds into slot 6 stays valid across the call, and the game's code window (task 0 slot 4) is untouched. */
#include "eng.h"
#include "mailbox.h"

/* what an engine call does: sum 16 bytes of the caller's window, write the engine's window 0 (block $21) */
static u16 engine_call(const u8 *caller_data)
{
    u16 sum = 0;
    u8 i;
    eng_enter();
    win_set(0, 0x21);
    win_set(1, 0x22);
    for (i = 0; i < 16; i++)
        sum = (u16)(sum + caller_data[i]);
    for (i = 0; i < 16; i++) {
        WIN0[i] = (u8)(0x80 + i);
        WIN1[i] = (u8)(0x90 + i);
    }
    eng_leave();
    return sum;
}

int main(void)
{
    u8 *w6 = (u8 *)0xC000;
    u8 *w4 = (u8 *)0x8000;
    u8 i, ok;
    eng_leave();                                      /* the game's task */
    mmu_set(4, 0x30);                                 /* the game's code window, a bank of its own */
    w4[0] = 0x5A;
    mmu_set(6, 0x20);
    for (i = 0; i < 16; i++)
        w6[i] = (u8)(0x40 + i);
    mb_check(0, engine_call(w6), 16 * 0x40 + 120);    /* the engine read the game's window */
    ok = (w4[0] == 0x5A);                             /* task 0 slot 4 is still its own bank */
    mb_check(1, ok, 1);
    mmu_set(4, 0x21);                                 /* now look at the engine's window 0 through the game's slot 4 */
    ok = 1;
    for (i = 0; i < 16; i++)
        if (w4[i] != (u8)(0x80 + i))
            ok = 0;
    mb_check(2, ok, 1);
    mmu_set(4, 0x22);
    ok = 1;
    for (i = 0; i < 16; i++)
        if (w4[i] != (u8)(0x90 + i))
            ok = 0;
    mb_check(3, ok, 1);
    ok = 1;                                           /* and the game's window is what the game wrote */
    for (i = 0; i < 16; i++)
        if (w6[i] != (u8)(0x40 + i))
            ok = 0;
    mb_check(4, ok, 1);
    mb_finish();
    return 0;
}
