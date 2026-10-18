/* t_scene.c: step 8.3 exit criterion in one picture. From the .DSK: the title screen of TITLE.DAX, the game's font and
 * the first tile bank of 8X8D1.DAX, drawn together: a DAX picture, text and tiles on the CoCo 3's screen. The parts are
 * checked bit by bit against the original game by t_pic and t_gfx; this one is for the eye (build/run/t_scene-mame.png). */
#include "eng.h"
#include "mailbox.h"

int main(void)
{
    RsFile f;
    Pic bank;
    u8 i;
    mb_check(0, rs_mount(0), 0);
    mb_check(1, rs_open(&f, 0, "TITLE   ", "DAX"), 0);
    gfx_init();
    mb_check(2, gfx_show_title(&f, 2), 0);
    mb_check(3, rs_open(&f, 0, "8X8D1   ", "DAX"), 0);
    mb_check(4, gfx_font_load(&f), 0);
    mb_check(5, pic_load(&bank, &f, 0xCB, 13, 1), 0);
    dsk_motor_off();
    for (i = 0; i < 40; i++)
        gfx_item(&bank, (u8)(i % 45), i, 0);
    gfx_text(8, 22, 0xF, "Pool of Radiance on the CoCo 3");
    gfx_text(8, 23, 0xB, "DAX picture, text and tiles");
    gfx_text(8, 24, 0xE, "read from a .DSK by the engine");
    mb_hold();
    mb_finish();
    return 0;
}
