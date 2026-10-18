/* ega.h: the IBM EGA as the game uses it (graphics modes 0Dh to 10h, write modes 0 to 3, read modes 0 and 1).
 * It is the C counterpart of tools/oracle/ega.py and answers the same way. */
#ifndef POOL_EGA_H
#define POOL_EGA_H

#include "pool.h"

typedef struct Ega {
  u8 planes[4][0x10000];
  u8 latch[4];
  u8 text_mem[0x20000];
  u8 mode;
  u8 seq[5];
  u8 gc[9];
  u8 crtc[25];
  u8 attr[21];
  u8 attr_ff;
  u8 attr_idx;
  u8 seq_idx, gc_idx, crtc_idx;
  u8 misc;
  u8 page;
  u32 dirty;                              /* counts writes since the host last looked */
} Ega;

extern Ega ega;

void ega_reset(void);
void ega_set_mode(u8 mode, int clear);
u8 ega_read(u32 offset);                  /* offset from A000:0000 */
void ega_write(u32 offset, u8 value);
u8 ega_port_read(u16 port);
void ega_port_write(u16 port, u8 value);
/* The picture: size, then RGBA pixels (row by row, 4 bytes each). Returns 0 when the mode is not a picture. */
int ega_size(int *w, int *h);
void ega_render(u32 *rgba);
void ega_palette_rgb(u8 rgb[16][3]);
/* The picture as the CoCo 3 shows it (step 8.2): 320x200, 4 bits a pixel, the high nibble the left pixel, 160 bytes a
 * row (32,000 bytes), the palette as the 16 EGA register values. 0 when the mode is not 0Dh. This is the screen model
 * of the port: its digest at each checkpoint is the 4bpp golden (tests/sessions/golden-4bpp). */
int ega_to_4bpp(u8 out[32000], u8 palette[16]);
void ega_planes_sha256(u8 out[32]);       /* the digest the oracle records as "screen" */

#endif
