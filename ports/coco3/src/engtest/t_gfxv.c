/* t_gfxv.c: step 8.4. t_gfx again, with the font and the tile banks read through the BASE volume on drive 1 (vol_find, then
 * gfx_font_load_e and pic_load_e) instead of 8X8D1.DAX: the same six screens must come out. */
#define FROM_VOLUME 1
#include "t_gfx.c"
