/* core.c: the resident part of the banked hello world (step 8.0).
 * Calls entries in two code banks that both live at logical $8000 and checks the results. */
#include "mailbox.h"

/* Far entries: resident stubs in farstubs.asm. */
extern unsigned int bank1_whoami(void);
extern unsigned int bank1_add(unsigned int a, unsigned int b);
extern unsigned int bank1_chain(unsigned int x);
extern unsigned int bank2_whoami(void);
extern unsigned int bank2_mul(unsigned int a, unsigned int b);
extern unsigned int bank2_bytes(unsigned char a, unsigned char b);

/* Resident routines the banks call back (bank1_chain uses core_double). */
unsigned int core_double(unsigned int x)
{
    return x * 2u;
}

/* A 16-bit multiply in resident code: pulls CMOC's MUL16 helper into the core, which the
 * banks then share (they are linked without any CMOC library). */
unsigned int core_mul(unsigned int a, unsigned int b)
{
    return a * b;
}

/* The same signature as bank1_add, resident: the baseline of the call-cost measurement. */
unsigned int core_add(unsigned int a, unsigned int b)
{
    return a + b;
}

#define BENCH_CALLS 1000u

/* Engine state in the direct page (engine/mailbox.inc). */
#define FC_CURBANK (*(unsigned char *)0x80)
#define FC_BSPTR   (*(unsigned int *)0x81)
#define MMU_SLOT4  (*(unsigned char *)0xFFA4)
#define MMU_SLOT5  (*(unsigned char *)0xFFA5)

int main(void)
{
    unsigned int i, sum = 0;

    *(unsigned char *)0xFF91 = 0;                  /* the game's task: the banks are mapped in task 0 (boot starts in the engine's) */
    *(unsigned char *)0x1009 = 0;
    scr_clear();
    scr_puts(0, 0, "POOL OF RADIANCE COCO3");
    scr_puts(1, 0, "8.0 BANKED HELLO WORLD");

    mb_check(0, bank1_whoami(), 0xB1B1u);          /* same logical entry address ...   */
    mb_check(1, bank2_whoami(), 0xB2B2u);          /* ... different bank, other code   */
    mb_check(2, bank1_add(1000, 234), 1234u);
    mb_check(3, bank1_chain(21), 421u);            /* bank1 -> core -> bank2 -> bank1 */
    mb_check(4, bank2_mul(300, 7), 2100u);         /* MUL16 from the core              */
    mb_check(5, core_mul(123, 45), 5535u);
    mb_check(6, bank2_bytes(200, 100), 44u);       /* CMOC byte rule holds in a bank   */
    mb_check(7, FC_BSPTR, 0x2000u);                /* bank stack balanced              */
    mb_check(8, FC_CURBANK, 0u);                   /* back in resident code            */
    mb_check(9, MMU_SLOT4 & 0x3F, 0x0Eu);          /* window left on the last callee   */
    mb_check(10, MMU_SLOT5 & 0x3F, 0x0Fu);
    MB_CHECKPOINT = 1;

    /* Call cost: 1000 far calls, then 1000 resident calls of the same shape. The harness
     * timestamps the checkpoints (lua/mailbox.lua writes them to <prefix>.cp). */
    MB_CHECKPOINT = 2;
    for (i = 0; i < BENCH_CALLS; i++)
        sum += bank1_add(i, 2);
    MB_CHECKPOINT = 3;
    for (i = 0; i < BENCH_CALLS; i++)
        sum += core_add(i, 2);
    MB_CHECKPOINT = 4;
    mb_check(11, sum, 19960u);                     /* 2 * (sum 0..999 + 2000) mod 65536 */

    scr_puts(3, 0, "ADD 1000+234 = ");
    scr_hex(3, 15, MB_RESULT(2));
    scr_puts(4, 0, "CHAIN 21     = ");
    scr_hex(4, 15, MB_RESULT(3));
    scr_puts(5, 0, MB_FAILS ? "FAIL" : "PASS");
    mb_finish();
    return 0;
}
