/* t_pic.c: step 8.3b. The two full-screen pictures of TITLE.DAX shown on the CoCo's 320x200x16 screen: the harness
 * hashes the screen and the palette at each checkpoint and compares them with the recorded screens of the original game
 * (goldens/4bpp/boot-title.s4: "ssi-logo" and "title"). */
#include "eng.h"
#include "mailbox.h"

int main(void)
{
    RsFile f;
    mb_check(0, rs_mount(0), 0);
    mb_check(1, rs_open(&f, 0, "TITLE   ", "DAX"), 0);
    gfx_init();
    mb_check(2, gfx_show_title(&f, 1), 0);            /* the SSI logo: golden "ssi-logo" */
    mb_hold();
    mb_check(3, gfx_show_title(&f, 2), 0);            /* the title: golden "title" */
    dsk_motor_off();
    mb_hold();
    mb_finish();
    return 0;
}
