/* crt.c: Crt, Dos and Overlay as the game uses them, the video BIOS, and the start up of the runtime. */
#include <stdio.h>
#include <stdlib.h>

#include "ega.h"
#include "platform.h"

extern const u32 pool_image_org;
extern const u32 pool_image_size;
extern const u8 pool_image[];
void file_init(void);

#define V16(off) (*(u16 *)(pool_ds + (off)))
#define V32(off) (*(u32 *)(pool_ds + (off)))

/* ---- Crt ------------------------------------------------------------------------------------------------- */
static u8 pending_scan;                /* ReadKey returns an extended key as 0 and then its scan code */
static u8 has_pending;

int rtl_KeyPressed(void)
{
  if (has_pending) {
    return 1;
  }
  return platform_key_peek() != 0;
}

#ifdef POOL_PROFILE
void pool_prof_key(void);
#endif

u8 rtl_ReadKey(void)
{
  u16 k;
  if (has_pending) {
    has_pending = 0;
    return pending_scan;
  }
#ifdef POOL_PROFILE
  pool_prof_key();                      /* a key is consumed: ports/coco3/prof closes its interval here */
#endif
  k = platform_key_wait();
  if ((k & 0xFF) == 0) {
    pending_scan = (u8)(k >> 8);
    has_pending = 1;
    return 0;
  }
  return (u8)k;
}

void rtl_Delay(u16 ms)
{
  platform_delay_ms(ms);
}

void rtl_Sound(u16 hz)
{
  if (hz) {
    platform_speaker_set((u16)(1193181u / hz), 3);
  }
}

void rtl_NoSound(void)
{
  platform_speaker_off();
}

void rtl_ClrScr(void) {}
void rtl_GotoXY(u8 x, u8 y) { (void)x; (void)y; }

/* ---- Dos --------------------------------------------------------------------------------------------------- */
void rtl_GetTime(u16 *h, u16 *m, u16 *s, u16 *hund)
{
  u8 a, b, c, d;
  platform_get_time(&a, &b, &c, &d);
  *h = a;
  *m = b;
  *s = c;
  *hund = d;
}

void rtl_GetDate(u16 *y, u16 *m, u16 *d, u16 *dow)
{
  u8 mo, da, dw;
  platform_get_date(y, &mo, &da, &dw);
  *m = mo;
  *d = da;
  *dow = dw;
}

void rtl_MsDos(Registers *regs)
{
  regs->Flags &= (u16)~1u;
}

/* The video BIOS: the calls the game makes (mode, page, palette). */
void rtl_Intr(u8 n, Registers *r)
{
  r->Flags = 0x0202;                    /* what the BIOS returns: interrupts enabled, carry clear */
  if (n != 0x10) {
    return;
  }
  switch (r->AH) {
  case 0x00:
    ega_set_mode(r->AL & 0x7F, !(r->AL & 0x80));
    platform_video_changed();
    break;
  case 0x05:
    ega.page = r->AL & 7;
    break;
  case 0x0F:
    r->AL = ega.mode;
    r->AH = (u8)(ega.mode <= 1 || ega.mode == 0x0D ? 40 : 80);
    r->BH = ega.page;
    break;
  case 0x10:
    switch (r->AL) {
    case 0x00:
      if ((r->BL & 0x0F) < 16) ega.attr[r->BL & 0x0F] = r->BH & 0x3F;
      platform_video_changed();
      break;
    case 0x01:
      ega.attr[17] = r->BH & 0x3F;
      break;
    case 0x02: {
      u8 *p = pool_arena + (((u32)r->ES << 4) + r->DX);
      int i;
      for (i = 0; i < 16; i++) ega.attr[i] = p[i] & 0x3F;
      ega.attr[17] = p[16];
      platform_video_changed();
      break;
    }
    case 0x07:
      r->BH = ega.attr[r->BL & 0x0F];
      break;
    default:
      break;
    }
    break;
  case 0x1A:
    r->AX = 0;
    break;
  default:
    break;
  }
}

/* ---- Overlay: the code is linked into the program, only the buffer's bookkeeping remains -------------------------- */
#define OVR_HEAP_SIZE V16(0x43EE)
#define OVR_HEAP_ORG V16(0x43F4)
#define OVR_HEAP_PTR V16(0x43F6)
#define OVR_HEAP_END V16(0x43F8)
#define OVR_RESULT V16(0x43DC)
#define HEAP_ORG V32(0x4400)
#define HEAP_PTR V32(0x4404)
#define HEAP_END V32(0x4408)
#define FREE_LIST V32(0x440C)

void rtl_OvrInit(const u8 *name)
{
  (void)name;
  OVR_RESULT = 0;
  OVR_HEAP_SIZE = 0x0467;
  OVR_HEAP_ORG = (u16)(HEAP_ORG >> 16);
  OVR_HEAP_PTR = OVR_HEAP_ORG;
  OVR_HEAP_END = (u16)(OVR_HEAP_ORG + OVR_HEAP_SIZE);
  HEAP_ORG = HEAP_PTR = POOL_FARPTR(OVR_HEAP_END, 0);
  FREE_LIST = HEAP_ORG;
}

void rtl_OvrInitEMS(void) { OVR_RESULT = -5 & 0xFFFF; }

s32 rtl_OvrGetBuf(void)
{
  return (s32)OVR_HEAP_SIZE * 16;
}

void rtl_OvrSetBuf(s32 size)
{
  u32 para = (u32)(size >> 4);
  OVR_RESULT = 0;
  OVR_HEAP_SIZE = (u16)para;
  OVR_HEAP_END = (u16)(OVR_HEAP_ORG + para);
  HEAP_ORG = HEAP_PTR = POOL_FARPTR(OVR_HEAP_END, 0);
  FREE_LIST = HEAP_ORG;
}

void rtl_OvrClearBuf(void) {}
void rtl_OvrSetRetry(s32 size) { (void)size; }
s32 rtl_OvrGetRetry(void) { return 0; }

/* ---- start up and exit --------------------------------------------------------------------------------------------- */
void rtl_Halt(u16 code)
{
  platform_quit(code);
}

void rtl_init(void)
{
  memset(pool_arena, 0, sizeof pool_arena);
  memcpy(pool_ds + pool_image_org, pool_image, pool_image_size);
  ega_reset();
  file_init();
  /* the heap: the program ends at paragraph 28F2; DOS gives the rest of conventional memory (the game lowers
   * HeapEnd by 400h paragraphs itself) */
  HEAP_ORG = POOL_FARPTR(0x28F2, 0);
  HEAP_PTR = HEAP_ORG;
  HEAP_END = POOL_FARPTR(0xA000, 0);
  FREE_LIST = HEAP_ORG;
  *(u8 *)(pool_ds + 0x84F6) = 7;        /* TextAttr */
  V16(0x84F4) = 3;                      /* LastMode */
  V16(0x84F8) = 0;                      /* WindMin */
  V16(0x84FA) = 0x184F;                 /* WindMax */
  *(u8 *)(pool_ds + 0x84F0) = 1;        /* CheckBreak */
  *(u8 *)(pool_ds + 0x442C) = 2;        /* FileMode */
  V16(0x4422) = 0x0FF0;                 /* PrefixSeg */
}
