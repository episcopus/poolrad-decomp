/* pool.h: the runtime interface of the generated game on the CoCo 3 (step 8.5c; CMOC). Same names as c/include/pool.h, the PC
 * host's: the generated C is the same text. What differs is where an address leads:
 *
 *   farptr   32 bits as on the PC (segment:offset), because the records of the game and the files keep that layout; the
 *            segment is the game's DGROUP segment for everything the layout of ports/coco3/tools/mkvm.py places
 *   VMN(o)   a global kept in native memory: a fixed address of the 64 KB map
 *   VMV(o)   a paged global: the 8 KB page of o is mapped into a data window (asm: vm.asm), the pointer returned is good
 *            until the next VMV/FPB
 *   FPM(T,p) a block of the mapped class: native memory
 *   FPB(T,p) a block of the banked class (or any far address the game holds): through vm_far
 *   FPD      the same as FPB: game logic must not hold a pointer to what only the engine owns (a picture), and vm_far
 *            stops the program when it is given one
 */
#ifndef POOL_H
#define POOL_H

#include <cmoc.h>
#include "coco_map.h"

typedef unsigned char u8;
typedef signed char s8;
typedef unsigned int u16;
typedef int s16;
typedef unsigned long u32;
typedef long s32;

typedef u32 farptr;                      /* segment in the high word, offset in the low word */

#define POOL_DS_SEG 0x1C7Cu              /* DGROUP's segment, as the original runs it: the high word of every game address */
#define POOL_FARPTR(seg, off) ((((u32)(u16)(seg)) << 16) | (u32)(u16)(off))
#define POOL_LINEAR(p) ((((u32)(p) >> 16) << 4) + ((u32)(p) & 0xFFFFu))

#define S(x) ((const u8 *)(x))

#define POOL_VIDEO(off) ((u8 *)(u16)(off))        /* the EGA window is not there: the engine owns the screen */
#define POOL_CAP(n) 32767                          /* CMOC arrays stop at 32767 elements */

/* the layout of DGROUP (mkvm.py --coco: a DS offset below $8000 is a CoCo address, the paged globals are above) */
void *vm_ptr(u16 v);                     /* the page of DGROUP offset v (>= $8000) into a data window; the pointer is good until the next call */
void *vm_far(farptr p);                  /* any address the game holds: native, paged or in the banked heap */
void *vm_unplaced(u16 off);
void vm_init(void);
farptr rtl_far(const void *p);           /* an address the game took (a native one or one in a window) as a far pointer */
void rtl_fatal_code(u8 code, u16 info);  /* stop the program: result words 30 and 29 of the mailbox say why */
#define VMN(o) ((void *)(o))
#define VMV(o) vm_ptr(o)
#define VMU(o) vm_unplaced(o)
#define FPD(T, p) ((T)vm_far(p))
#define FPB(T, p) ((T)vm_far(p))
#define FPM(T, p) ((T)((u16)(p) | 0))        /* the | 0: CMOC 0.1.100 crashes on a bare cast here */
farptr rtl_getmem_m(u16 size);           /* a block of the mapped heap */

/* Every translated routine announces itself on the host (a trace); not here. */
#define POOL_TRACE(n) ((void)0)

/* ---- files (sizes as Turbo Pascal's FileRec and TextRec) ---------------------------------------------- */
enum { fmClosed = 0xD7B0, fmInput = 0xD7B1, fmOutput = 0xD7B2, fmInOut = 0xD7B3 };

typedef struct FileRec {
  u16 Handle;                            /* index in the runtime's table of host files */
  u16 Mode;
  u16 RecSize;
  u8 Private_[26];
  u8 UserData[16];
  u8 Name[80];
} FileRec;

typedef struct TextRec {
  u16 Handle;
  u16 Mode;
  u16 BufSize;
  u16 Private_;
  u16 BufPos;
  u16 BufEnd;
  u8 Reserved[20];
  u8 UserData[16];
  u8 Name[80];
  u8 Buffer[128];
} TextRec;

typedef struct Registers { u16 AX, BX, CX, DX, BP, SI, DI, DS, ES, Flags; u8 AL, AH, BL, BH, CL, CH, DL, DH; } Registers;   /* CMOC has no anonymous unions: the byte halves are not the word's */

/* ---- core ------------------------------------------------------------------------------------------- */
void rtl_init(void);                     /* arena, DGROUP image, System variables, units' data */
farptr rtl_far(const void *p);           /* a host pointer into the arena as a far pointer */
typedef void (*rtl_proc_t)(void);
rtl_proc_t rtl_proc(farptr id);
void rtl_Halt(u16 code);
void rtl_fatal(const char *fmt, ...);

u8 rtl_peek8(u16 seg, u16 off);
u16 rtl_peek16(u16 seg, u16 off);
void rtl_poke8(u16 seg, u16 off, u8 v);
void rtl_poke16(u16 seg, u16 off, u16 v);
u8 rtl_inp(u16 port);
u16 rtl_inpw(u16 port);
void rtl_outp(u16 port, u8 v);
void rtl_outpw(u16 port, u16 v);

u16 rtl_stack_mark(void);                /* the local variables whose address is taken (@) */
void *rtl_stack_alloc(u16 size);
void rtl_stack_release(u16 mark);

void rtl_Move(const void *src, void *dst, u16 count);
void rtl_store(void *dst, const void *src, u32 count);   /* bytes into memory that may be video */
void rtl_FillChar(void *dst, u16 count, u8 value);
u16 rtl_Random(u16 range);
void rtl_Randomize(void);

/* ---- numbers -------------------------------------------------------------------------------------- */
#define rtl_abs(x) ((s32)((x) < 0 ? -(s32)(x) : (s32)(x)))
#define rtl_fabs(x) ((x) < 0 ? -(x) : (x))
#define rtl_swap(x) ((u16)((((u16)(x)) << 8) | (((u16)(x)) >> 8)))
s32 rtl_trunc(double x);
s32 rtl_round(double x);

/* ---- strings (length byte first) -------------------------------------------------------------------- */
u8 *rtl_str_assign(u8 *dst, int maxlen, const u8 *src);
u8 *rtl_str_cat(u8 *dst, int n, ...);
u8 *rtl_str_cat_v(u8 *dst, int n, ...);          /* the same with the parts as arguments (CoCo profile: no compound literals) */
u8 *rtl_str_char(u8 *dst, u8 c);
int rtl_str_cmp(const u8 *a, const u8 *b);
u8 *rtl_str_copy(u8 *dst, const u8 *s, int idx, int cnt);
u8 rtl_str_pos(const u8 *sub, const u8 *s);
void rtl_str_delete(u8 *s, int idx, int cnt);
void rtl_str_insert(const u8 *src, u8 *s, int maxlen, int idx);
void rtl_str_int(u8 *s, int maxlen, s32 v, int width);
void rtl_str_real(u8 *s, int maxlen, double v, int width, int dec);
void rtl_str_val(const u8 *s, void *v, int size, int is_signed, void *code);
u8 rtl_upcase(u8 c);
u8 rtl_lowercase(u8 c);
u8 *rtl_paramstr(u8 *dst, int n);
void rtl_set_args(int n, const char *const *args);        /* the game's ParamStr(1..n) */
u16 rtl_ParamCount(void);

/* ---- sets (32 bytes, bit n of byte n/8) ----------------------------------------------------------------- */
void rtl_set_clear(u8 *s, int n);
void rtl_set_add(u8 *s, int v);
void rtl_set_range(u8 *s, int lo, int hi);
int rtl_set_in(const u8 *s, int v);
int rtl_set_in_at(const u8 *s, int first_byte, int nbytes, int v);   /* a set stored from the byte of its lowest member */
u8 *rtl_set_union(u8 *d, const u8 *a, const u8 *b, int n);
u8 *rtl_set_diff(u8 *d, const u8 *a, const u8 *b, int n);
u8 *rtl_set_inter(u8 *d, const u8 *a, const u8 *b, int n);
int rtl_set_eq(const u8 *a, const u8 *b, int n);
int rtl_set_le(const u8 *a, const u8 *b, int n);
int rtl_set_ge(const u8 *a, const u8 *b, int n);

/* ---- heap -------------------------------------------------------------------------------------------- */
farptr rtl_getmem(u16 size);
void rtl_freemem(farptr p, u16 size);
s32 rtl_MemAvail(void);
s32 rtl_MaxAvail(void);

/* ---- files and text --------------------------------------------------------------------------------- */
void rtl_assign(void *f, const u8 *name);
void rtl_reset(void *f, u16 recsize);
void rtl_rewrite(void *f, u16 recsize);
void rtl_reset_text(void *f);
void rtl_rewrite_text(void *f);
void rtl_append_text(void *f);
void rtl_close(void *f);
void rtl_erase(void *f);
void rtl_seek(void *f, s32 pos);
void rtl_truncate(void *f);
void rtl_flush(void *f);
int rtl_eof(void *f);
int rtl_eoln(void *f);
s32 rtl_filepos(void *f);
s32 rtl_filesize(void *f);
void rtl_blockread(void *f, void *buf, u16 count, void *result);
void rtl_blockwrite(void *f, const void *buf, u16 count, void *result);
void rtl_file_read(void *f, void *rec);
void rtl_file_write(void *f, const void *rec);
u16 rtl_IOResult(void);
void rtl_MkDir(const u8 *dir);
void rtl_RmDir(const u8 *dir);
void rtl_ChDir(const u8 *dir);
void rtl_write_str(void *f, const u8 *s, int width);
void rtl_write_char(void *f, u8 c, int width);
void rtl_write_int(void *f, s32 v, int width);
void rtl_write_real(void *f, double v, int width, int dec);
void rtl_write_bool(void *f, int v, int width);
void rtl_write_ln(void *f);
void rtl_read_char(void *f, u8 *c);
void rtl_read_str(void *f, u8 *s, int maxlen);
void rtl_read_int(void *f, void *v, int size, int is_signed);
void rtl_read_real(void *f, double *v);
void rtl_read_ln(void *f);

/* ---- Crt, Dos, Overlay -------------------------------------------------------------------------------- */
int rtl_KeyPressed(void);
u8 rtl_ReadKey(void);
void rtl_Delay(u16 ms);
void rtl_Sound(u16 hz);
void rtl_NoSound(void);
void rtl_ClrScr(void);
void rtl_GotoXY(u8 x, u8 y);
void rtl_Intr(u8 n, Registers *regs);
void rtl_MsDos(Registers *regs);
void rtl_GetTime(u16 *h, u16 *m, u16 *s, u16 *hund);
void rtl_GetDate(u16 *y, u16 *m, u16 *d, u16 *dow);
void rtl_OvrInit(const u8 *name);
void rtl_OvrInitEMS(void);
void rtl_OvrSetBuf(s32 size);
s32 rtl_OvrGetBuf(void);
void rtl_OvrClearBuf(void);
void rtl_OvrSetRetry(s32 size);
s32 rtl_OvrGetRetry(void);

/* ---- hand-written units ---------------------------------------------------------------------------------- */
void pool_init_units(void);
void pool_main(void);

#endif
