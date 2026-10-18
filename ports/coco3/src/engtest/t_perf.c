/* t_perf.c: step 8.3e. What the engine's drawing costs, measured with the 60 Hz frame clock (one frame is about
 * 29,870 cycles at 1.79 MHz). Each result word is the number of frames a fixed number of operations took; the
 * operation counts are in the comments, and docs/PHASE-8.3.md turns them into cycles an operation. Nothing is checked
 * except that the program finishes; the drawing itself is checked by t_gfx. */
#include "eng.h"
#include "mailbox.h"

static Pic bank;

#define MEASURE(slot, n, stmt)                                  \
    do {                                                        \
        u16 i_, t_;                                             \
        wait_edge();                                            \
        t_ = frame_count();                                     \
        for (i_ = 0; i_ < (n); i_++) {                          \
            stmt;                                               \
        }                                                       \
        MB_RESULT(slot) = (u16)(frame_count() - t_);            \
    } while (0)

static void wait_edge(void)
{
    u16 t = frame_count();
    while (frame_count() == t)
        ;
}

int main(void)
{
    RsFile f;
    u16 k;
    mb_check(24, rs_mount(0), 0);
    mb_check(25, rs_open(&f, 0, "8X8D1   ", "DAX"), 0);
    mb_check(26, gfx_font_load(&f), 0);
    mb_check(27, pic_load(&bank, &f, 0xCB, 13, 1), 0);
    dsk_motor_off();
    gfx_init();
    db_init();
    irq_start();
    MB_RESULT(0) = 0;
    MEASURE(0, 1000, gfx_glyph((u8)(i_ % 40), 10, 0xF, 1, 'A', 1));              /* 1000 glyphs */
    MEASURE(1, 1000, gfx_item(&bank, (u8)(i_ % 40), (u8)(i_ % 40), 5));          /* 1000 tiles to the screen */
    MEASURE(2, 1000, db_item(&bank, (u8)(i_ % 40), (u8)(i_ % 20), 5, 0));        /* 1000 opaque tiles into DrawBuf */
    MEASURE(3, 1000, db_item(&bank, (u8)(i_ % 40), (u8)(i_ % 20), 5, 1));        /* 1000 masked tiles into DrawBuf */
    MEASURE(4, 20, db_flush());                                                   /* 20 flushes of the 8 pixel rows above */
    MEASURE(5, 20, { db_fill(0, 0, DB_COLS, DB_ROWS, 3); db_flush(); });          /* 20 full-window fills and flushes */
    MEASURE(6, 50, gfx_clear(0));                                                 /* 50 screen clears */
    for (k = 0; k < 8; k++)
        MB_RESULT(8 + k) = (u16)(k * 0);
    irq_stop();
    mb_finish();
    return 0;
}
