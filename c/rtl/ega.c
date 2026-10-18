/* ega.c: the EGA model (tools/oracle/ega.py, ported). */
#include "ega.h"
#include "platform.h"

Ega ega;

static const u8 default_attr[16] = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x14, 0x07,
                                    0x38, 0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x3F};

static int graphics_mode(u8 m)
{
  return m == 0x0D || m == 0x0E || m == 0x0F || m == 0x10;
}

void ega_set_mode(u8 mode, int clear)
{
  int g;
  mode &= 0x7F;
  ega.mode = mode;
  g = graphics_mode(mode);
  if (clear) {
    memset(ega.planes, 0, sizeof ega.planes);
    memset(ega.text_mem, 0, sizeof ega.text_mem);
    if (mode <= 3) {
      int i;
      for (i = 0; i < 0x4000; i++) {
        ega.text_mem[0x8000 + 2 * i] = 0x20;
        ega.text_mem[0x8000 + 2 * i + 1] = 0x07;
      }
    }
  }
  ega.seq[0] = 0x03; ega.seq[1] = 0x01; ega.seq[2] = 0x0F; ega.seq[3] = 0x00; ega.seq[4] = g ? 0x06 : 0x03;
  memset(ega.gc, 0, sizeof ega.gc);
  ega.gc[6] = g ? 0x05 : 0x0D;
  ega.gc[7] = 0x0F;
  ega.gc[8] = 0xFF;
  memset(ega.crtc, 0, sizeof ega.crtc);
  memset(ega.attr, 0, sizeof ega.attr);
  memcpy(ega.attr, default_attr, 16);
  ega.attr[16] = g ? 0x01 : 0x08;
  ega.attr[18] = 0x0F;
  ega.attr_ff = 0;
  ega.page = 0;
  ega.dirty++;
}

void ega_reset(void)
{
  memset(&ega, 0, sizeof ega);
  ega.misc = 0x23;
  ega.seq[2] = 0x0F;
  ega.gc[8] = 0xFF;
  memcpy(ega.attr, default_attr, 16);
  ega.attr[16] = 0x08;
  ega.attr[18] = 0x0F;
  ega.mode = 0x03;
}

u8 ega_read(u32 off)
{
  u8 *lat = ega.latch;
  if (off >= 0x10000u) {
    return ega.text_mem[off - 0x10000u];
  }
  lat[0] = ega.planes[0][off];
  lat[1] = ega.planes[1][off];
  lat[2] = ega.planes[2][off];
  lat[3] = ega.planes[3][off];
  if (ega.gc[5] & 0x08) {                       /* read mode 1: colour compare */
    u8 cmp = ega.gc[2] & 0x0F, care = ega.gc[7] & 0x0F, res = 0xFF;
    int p;
    for (p = 0; p < 4; p++) {
      if (care & (1 << p)) {
        res &= ((cmp >> p) & 1) ? lat[p] : (u8)~lat[p];
      }
    }
    return res;
  }
  return lat[ega.gc[4] & 3];
}

void ega_write(u32 off, u8 v)
{
  u8 *lat = ega.latch;
  int mode, p;
  u8 mask, bm, func, rot;
  if (off >= 0x10000u) {
    ega.text_mem[off - 0x10000u] = v;
    ega.dirty++;
    return;
  }
  mode = ega.gc[5] & 3;
  mask = ega.seq[2] & 0x0F;
  bm = ega.gc[8];
  func = (ega.gc[3] >> 3) & 3;
  rot = ega.gc[3] & 7;
  if (mode == 1) {
    for (p = 0; p < 4; p++) {
      if (mask & (1 << p)) {
        ega.planes[p][off] = lat[p];
      }
    }
    ega.dirty++;
    return;
  }
  for (p = 0; p < 4; p++) {
    u8 d;
    if (!(mask & (1 << p))) {
      continue;
    }
    if (mode == 0) {
      d = rot ? (u8)((v >> rot) | (v << (8 - rot))) : v;
      if (ega.gc[1] & (1 << p)) {
        d = (ega.gc[0] & (1 << p)) ? 0xFF : 0x00;
      }
    } else if (mode == 2) {
      d = ((v >> p) & 1) ? 0xFF : 0x00;
    } else {                                      /* mode 3 */
      u8 rd = rot ? (u8)((v >> rot) | (v << (8 - rot))) : v;
      u8 bmm = bm & rd;
      u8 alu;
      d = (ega.gc[0] & (1 << p)) ? 0xFF : 0x00;
      alu = func == 0 ? d : (func == 1 ? (d & lat[p]) : (func == 2 ? (d | lat[p]) : (d ^ lat[p])));
      ega.planes[p][off] = (u8)((alu & bmm) | (lat[p] & ~bmm));
      continue;
    }
    if (func == 1) {
      d &= lat[p];
    } else if (func == 2) {
      d |= lat[p];
    } else if (func == 3) {
      d ^= lat[p];
    }
    ega.planes[p][off] = (u8)((d & bm) | (lat[p] & ~bm));
  }
  ega.dirty++;
}

u8 ega_port_read(u16 port)
{
  switch (port) {
  case 0x3DA:
  case 0x3BA:
    ega.attr_ff = 0;
    return platform_retrace_status();
  case 0x3C0: return ega.attr_idx;
  case 0x3C1: return ega.attr_idx < 21 ? ega.attr[ega.attr_idx] : 0;
  case 0x3C2: return 0x70;
  case 0x3C4: return ega.seq_idx;
  case 0x3C5: return ega.seq_idx < 5 ? ega.seq[ega.seq_idx] : 0;
  case 0x3CC: return ega.misc;
  case 0x3CE: return ega.gc_idx;
  case 0x3CF: return ega.gc_idx < 9 ? ega.gc[ega.gc_idx] : 0;
  case 0x3D4: case 0x3B4: return ega.crtc_idx;
  case 0x3D5: case 0x3B5: return ega.crtc_idx < 25 ? ega.crtc[ega.crtc_idx] : 0;
  default: return 0xFF;
  }
}

void ega_port_write(u16 port, u8 val)
{
  switch (port) {
  case 0x3C0:
    if (!ega.attr_ff) {
      ega.attr_idx = val & 0x1F;
    } else if ((ega.attr_idx & 0x1F) < 21) {
      ega.attr[ega.attr_idx & 0x1F] = val;
      ega.dirty++;
    }
    ega.attr_ff = !ega.attr_ff;
    break;
  case 0x3C2: ega.misc = val; break;
  case 0x3C4: ega.seq_idx = val & 7; break;
  case 0x3C5: if (ega.seq_idx < 5) ega.seq[ega.seq_idx] = val; break;
  case 0x3CE: ega.gc_idx = val & 0x0F; break;
  case 0x3CF: if (ega.gc_idx < 9) ega.gc[ega.gc_idx] = val; break;
  case 0x3D4: case 0x3B4: ega.crtc_idx = val & 0x1F; break;
  case 0x3D5: case 0x3B5:
    if (ega.crtc_idx < 25) {
      ega.crtc[ega.crtc_idx] = val;
      if (ega.crtc_idx == 0x0C || ega.crtc_idx == 0x0D) {
        ega.dirty++;
      }
    }
    break;
  default:
    break;                                        /* VGA DAC and CGA ports: accepted, not modelled */
  }
}

/* ---- the picture ---------------------------------------------------------------------------------------- */
static void rgb6(u8 v, u8 out[3])
{
  out[0] = (u8)((((v >> 2) & 1) << 1 | ((v >> 5) & 1)) * 85);
  out[1] = (u8)((((v >> 1) & 1) << 1 | ((v >> 4) & 1)) * 85);
  out[2] = (u8)(((v & 1) << 1 | ((v >> 3) & 1)) * 85);
}

void ega_palette_rgb(u8 rgb[16][3])
{
  int i;
  for (i = 0; i < 16; i++) {
    rgb6(ega.attr[i] & 0x3F, rgb[i]);
  }
}

int ega_size(int *w, int *h)
{
  switch (ega.mode) {
  case 0x0D: *w = 320; *h = 200; return 1;
  case 0x0E: *w = 640; *h = 200; return 1;
  case 0x0F: case 0x10: *w = 640; *h = 350; return 1;
  default: return 0;
  }
}

void ega_render(u32 *rgba)
{
  int w, h, y, xb, bit, bpl;
  u8 pal[16][3];
  u32 start;
  if (!ega_size(&w, &h)) {
    return;
  }
  bpl = w / 8;
  ega_palette_rgb(pal);
  start = ((u32)ega.crtc[0x0C] << 8) | ega.crtc[0x0D];
  for (y = 0; y < h; y++) {
    u32 base = (start + (u32)y * (u32)bpl) & 0xFFFF;
    for (xb = 0; xb < bpl; xb++) {
      u32 a = (base + (u32)xb) & 0xFFFF;
      u8 b0 = ega.planes[0][a], b1 = ega.planes[1][a], b2 = ega.planes[2][a], b3 = ega.planes[3][a];
      for (bit = 7; bit >= 0; bit--) {
        int c = ((b0 >> bit) & 1) | (((b1 >> bit) & 1) << 1) | (((b2 >> bit) & 1) << 2) | (((b3 >> bit) & 1) << 3);
        *rgba++ = 0xFF000000u | ((u32)pal[c][2] << 16) | ((u32)pal[c][1] << 8) | pal[c][0];
      }
    }
  }
}

int ega_to_4bpp(u8 out[32000], u8 palette[16])
{
  int y, xb, bit, i;
  u32 start;
  if (ega.mode != 0x0D) {
    return 0;
  }
  start = ((u32)ega.crtc[0x0C] << 8) | ega.crtc[0x0D];
  for (i = 0; i < 16; i++) {
    palette[i] = ega.attr[i] & 0x3F;
  }
  for (y = 0; y < 200; y++) {
    u32 base = (start + (u32)y * 40u) & 0xFFFF;
    u8 *row = out + y * 160;
    for (xb = 0; xb < 40; xb++) {
      u32 a = (base + (u32)xb) & 0xFFFF;
      u8 b0 = ega.planes[0][a], b1 = ega.planes[1][a], b2 = ega.planes[2][a], b3 = ega.planes[3][a];
      for (bit = 7; bit >= 0; bit -= 2) {            /* two pixels a byte: the left one in the high nibble */
        int l = ((b0 >> bit) & 1) | (((b1 >> bit) & 1) << 1) | (((b2 >> bit) & 1) << 2) | (((b3 >> bit) & 1) << 3);
        int r = ((b0 >> (bit - 1)) & 1) | (((b1 >> (bit - 1)) & 1) << 1) | (((b2 >> (bit - 1)) & 1) << 2) | (((b3 >> (bit - 1)) & 1) << 3);
        row[xb * 4 + (7 - bit) / 2] = (u8)((l << 4) | r);
      }
    }
  }
  return 1;
}
