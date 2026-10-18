/* mailbox.h: C side of src/engine/mailbox.inc. Plain C, no CMOC-only syntax. */
#ifndef MAILBOX_H
#define MAILBOX_H

/* CMOC ignores `volatile` (and warns), so nothing here uses it: the mailbox is only touched
 * from the main line, never from an interrupt handler. */
#define MB_BASE       0x1000u
#define MB_CHECKPOINT (*(unsigned char *)(MB_BASE + 4))
#define MB_STATUS     (*(unsigned char *)(MB_BASE + 5))
#define MB_FAILS      (*(unsigned int *)(MB_BASE + 6))
#define MB_RESULT(i)  (*(unsigned int *)(MB_BASE + 0x10 + 2 * (i)))

#define MB_RUNNING 0
#define MB_PASS    1
#define MB_FAIL    2

/* Record r[i] = value and compare with the expected value; counts a failure on mismatch. */
void mb_check(unsigned char i, unsigned int value, unsigned int expected);
void mb_halt(void);
/* Mark the run finished (status 1 or 2) and stop. Never returns. */
void mb_finish(void);

/* Write text on the BASIC text screen (32 columns, 16 rows, ASCII upper case and digits). */
void scr_clear(void);
void scr_puts(unsigned char row, unsigned char col, const char *s);
void scr_hex(unsigned char row, unsigned char col, unsigned int v);

#endif
