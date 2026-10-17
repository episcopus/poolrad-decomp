/* mailbox.c: result mailbox and text screen output for test programs. */
#include "mailbox.h"

#define SCREEN 0x0400u

void mb_check(unsigned char i, unsigned int value, unsigned int expected)
{
    MB_RESULT(i) = value;
    if (value != expected)
        MB_FAILS = MB_FAILS + 1u;
}

/* The harnesses stop here: XRoar traps on this address, MAME polls the status byte. */
void mb_halt(void)
{
    for (;;)
        ;
}

void mb_finish(void)
{
    MB_STATUS = MB_FAILS ? MB_FAIL : MB_PASS;
    /* Border colour: green when every check passed, red otherwise (GIME $FF9A, RGB bits). */
    *(unsigned char *)0xFF9A = MB_FAILS ? 0x24 : 0x12;
    mb_halt();
}

void scr_clear(void)
{
    unsigned char *p = (unsigned char *)SCREEN;
    unsigned int n;
    for (n = 0; n < 512u; n++)
        *p++ = 0x60;            /* VDG text mode: $60 is a blank */
}

void scr_puts(unsigned char row, unsigned char col, const char *s)
{
    unsigned char *p = (unsigned char *)(SCREEN + (unsigned int)row * 32u + col);
    while (*s)
        *p++ = (unsigned char)*s++;
}

void scr_hex(unsigned char row, unsigned char col, unsigned int v)
{
    unsigned char *p = (unsigned char *)(SCREEN + (unsigned int)row * 32u + col);
    signed char n;
    for (n = 12; n >= 0; n -= 4) {
        unsigned char d = (unsigned char)((v >> n) & 15u);
        *p++ = (unsigned char)(d < 10 ? '0' + (unsigned int)d : 'A' + (unsigned int)d - 10);
    }
}
