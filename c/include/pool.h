/* pool.h: the runtime interface of the C translation of Pool of Radiance (SPEC 7.4).
 *
 * The game was written in Turbo Pascal 6.0 for a 16-bit real-mode PC. The translation keeps the PC's memory
 * as it was: one flat 1 MB arena addressed by segment:offset far pointers (`farptr`), the program's data
 * segment (DGROUP) at its original paragraph, the Turbo Pascal heap above it and the EGA video memory at
 * A000:0000. Game globals are macros into DGROUP (game.h), so a byte-for-byte comparison with the original's
 * data segment stays possible. Everything the game asks of the outside world goes through platform.h.
 */
#ifndef POOL_H
#define POOL_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

typedef uint8_t u8;
typedef int8_t s8;
typedef uint16_t u16;
typedef int16_t s16;
typedef uint32_t u32;
typedef int32_t s32;

typedef u32 farptr;                      /* segment in the high word, offset in the low word */

#define POOL_ARENA_SIZE 0x110000u        /* 1 MB plus the 64 KB high memory area (segment:offset can pass 1 MB) */
#define POOL_DS_SEG 0x1C7Cu              /* DGROUP: load paragraph 1000h + 0C7Ch, as the oracle runs the original */
#define POOL_DS_LINEAR (POOL_DS_SEG * 16u)
#define POOL_VIDEO_LO 0xA0000u           /* the EGA window: A000:0000 to AFFF:000F */
#define POOL_VIDEO_HI 0xB0000u

extern u8 pool_arena[POOL_ARENA_SIZE];
#define pool_ds (pool_arena + POOL_DS_LINEAR)

#define POOL_FARPTR(seg, off) ((((u32)(u16)(seg)) << 16) | (u32)(u16)(off))
#define POOL_LINEAR(p) ((((u32)(p) >> 16) << 4) + ((u32)(p) & 0xFFFFu))
#define FPD(T, p) ((T)(pool_arena + POOL_LINEAR(p)))

#define S(x) ((const u8 *)(x))

/* Helpers of the CoCo profile of the translator (tools/c/pas2c.py --profile coco, step 8.2). They do nothing
 * for the PC profile; the CoCo build (CMOC) defines its own versions. */
#ifndef POOL_VIDEO
#define POOL_VIDEO(off) (pool_arena + (off))     /* EGA window addresses, 20 bit: the CoCo has no EGA planes */
#endif
#ifndef POOL_CAP
#define POOL_CAP(n) (n)                          /* an array bound: CMOC arrays stop at 32767 elements */
#endif


/* Every translated routine announces itself, so a run can be compared call by call with the original's
 * (tools/c/call_trace.py); empty unless built with -DPOOL_TRACE_CALLS (cmake -DPOOLRAD_TRACE=ON). */
#ifdef POOL_TRACE_CALLS
void pool_trace(const char *name);
#define POOL_TRACE(n) pool_trace(n)
#else
#define POOL_TRACE(n) ((void)0)
#endif           /* a Pascal string literal: length byte first */

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

typedef struct Registers {
  union {
    struct { u16 AX, BX, CX, DX, BP, SI, DI, DS, ES, Flags; };
    struct { u8 AL, AH, BL, BH, CL, CH, DL, DH; };
  };
} Registers;

/* ---- core ------------------------------------------------------------------------------------------- */
void rtl_init(void);                     /* arena, DGROUP image, System variables, units' data */
farptr rtl_far(const void *p);           /* a host pointer into the arena as a far pointer */
void *rtl_mem_ptr(u16 seg, u16 off);
void (*rtl_proc(farptr id))(void);
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
u8 *rtl_str_cat(u8 *dst, int n, const u8 *const parts[]);
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
