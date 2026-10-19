/* rtl_sys.c: what Turbo Pascal's System, Crt and Dos units gave the game, as the CoCo has it (step 8.5c): the random
 * generator, the clock, the keyboard, the program's end, the procedure table, the pseudo stack for locals the game takes the
 * address of, and the files (the volumes come with the engine, 8.5d). */
#include "pool.h"
#include "mailbox.h"

/* ---- stopping ----------------------------------------------------------------------------------------------- */
void eng_halt(void);

void rtl_fatal_code(u8 code, u16 info)
{
    MB_RESULT(30) = code;
    MB_RESULT(29) = info;
    MB_STATUS = MB_FAIL;
    eng_halt();
}

void rtl_Halt(u16 code)
{
    MB_RESULT(28) = code;
    MB_STATUS = code == 0 ? MB_PASS : MB_FAIL;
    eng_halt();
}

/* ---- the clock: the vertical sync, 59.92 Hz ----------------------------------------------------------------- */
u16 frame_count(void);

static u32 frames32(void)
{
    static u16 last;
    static u16 hi;
    u16 now = frame_count();
    if (now < last)
        hi++;
    last = now;
    return ((u32)hi << 16) | now;
}

/* the BIOS tick (18.2 Hz) the game's clock counts: frames * 18.2065 / 59.9227 = frames * 0.30385 */
s32 rtl_ticks(void)
{
    u32 f = frames32();
    return (s32)(((f >> 4) * 19913UL) >> 12);
}

s32 GameClock(void)
{
    return rtl_ticks();
}

void rtl_GetTime(u16 *h, u16 *m, u16 *s, u16 *hund)
{
    u32 f = frames32(), t = (f * 100UL) / 60UL;          /* hundredths since the start */
    *hund = (u16)(t % 100UL);
    t /= 100UL;
    *s = (u16)(t % 60UL);
    t /= 60UL;
    *m = (u16)(t % 60UL);
    *h = (u16)(12 + (t / 60UL) % 12UL);
}

void rtl_Delay(u16 ms)
{
    u32 end = frames32() + ((u32)ms * 60UL + 999UL) / 1000UL;
    while ((s32)(frames32() - end) < 0)
        ;
}

/* ---- the keyboard ------------------------------------------------------------------------------------------- */
u16 kbd_get(void);
static u16 pending;                    /* a key of kbd_get: the character, or 0 and the PC scan code in the high byte */
static u8 pending_scan;                /* ReadKey returns an extended key as 0 and then its scan code */

int rtl_KeyPressed(void)
{
    MB_POLLS++;
    if (pending_scan)
        return 1;
    if (!pending)
        pending = kbd_get();
    return pending != 0;
}

u8 rtl_ReadKey(void)
{
    u8 k;
    if (pending_scan) {
        k = pending_scan;
        pending_scan = 0;
        return k;
    }
    while (!rtl_KeyPressed())
        ;
    k = (u8)pending;
    if (!k)
        pending_scan = (u8)(pending >> 8);
    pending = 0;
    return k;
}

/* ---- random numbers: RandSeed := RandSeed * 08088405h + 1; Random(n) = hi16(RandSeed) mod n (TP 6.0) ---------- */
u32 rand_seed;                         /* the harness sets it (lua/watch.lua) to line the sequences up with the recorded ones */
static u32 random_calls;
u8 wheel_pick;                         /* the last Random(13) with bit 7 set: the code wheel's question (CheckCodeWheel); the harness reads it */

u16 rtl_Random(u16 range)
{
    u16 r;
    random_calls++;
    rand_seed = rand_seed * 0x08088405UL + 1UL;
    r = range == 0 ? 0 : (u16)((u16)(rand_seed >> 16) % range);
    if (range == 13)
        wheel_pick = (u8)(r | 0x80);
    return r;
}

void rtl_Randomize(void)
{
    u16 h, m, s, hund;
    rtl_GetTime(&h, &m, &s, &hund);
    rand_seed = ((((u32)s << 8) | hund) << 16) | (((u32)h << 8) | m);
}

/* ---- procedure pointers: the game stores the ids of its handlers, the table is sorted by id --------------------- */
typedef struct PoolProc { u16 hi, lo; void (*fn)(void); } PoolProc;
extern const PoolProc pool_procs_c[];
extern const u16 pool_procs_c_count;

rtl_proc_t rtl_proc(farptr id)
{
    u16 lo = 0, hi = pool_procs_c_count, mid;
    u16 ih = (u16)(id >> 16), il = (u16)id;
    while (lo < hi) {
        const PoolProc *p;
        mid = (u16)((lo + hi) >> 1);
        p = &pool_procs_c[mid];
        if (p->hi == ih && p->lo == il)
            return p->fn;
        if (p->hi < ih || (p->hi == ih && p->lo < il))
            lo = (u16)(mid + 1);
        else
            hi = mid;
    }
    rtl_fatal_code(0x30, il);
    return 0;
}

/* ---- the pseudo stack: locals whose address the game takes live here, so that the address is a far pointer ----- */
static u8 pstack[256];
static u16 ptop;

u16 rtl_stack_mark(void)
{
    return ptop;
}

void *rtl_stack_alloc(u16 size)
{
    void *p = pstack + ptop;
    ptop = (u16)(ptop + ((size + 1u) & 0xFFFEu));
    if (ptop > sizeof pstack)
        rtl_fatal_code(0x31, size);
    memset(p, 0, size);
    return p;
}

void rtl_stack_release(u16 mark)
{
    ptop = mark;
}

/* ---- Move and FillChar ---------------------------------------------------------------------------------------- */
void rtl_Move(const void *src, void *dst, u16 count)
{
    memmove(dst, src, count);
}

void rtl_FillChar(void *dst, u16 count, u8 value)
{
    memset(dst, value, count);
}

/* ---- Intr, files and the console: not yet (the engine brings volumes and files, 8.5d) -------------------------- */
static u16 ioresult;

void rtl_Intr(u8 n, Registers *regs)
{
    (void)n;
    (void)regs;
}

u16 rtl_IOResult(void)
{
    u16 r = ioresult;
    ioresult = 0;
    return r;
}

/* The game's files, the part of them that is read-only data: what the volumes hold (tools/mkvolumes.py), seen as Pascal
 * files. A file is known when a mounted volume has it (its name without directory and extension, 8 characters); ITEMS, which
 * the game reads with BlockRead, is block 0 of the volumes' pseudo file ITEMS, staged by the engine at reset. Files the game
 * writes (saves) are not here yet: Rewrite fails. */
u16 FileKnown(const u8 *name);
u16 DaxLoad(const u8 *name, u16 id);
void DaxRead(u16 off, u8 *dst, u16 n);

/* the Pascal name of a path as a Pascal string of at most 8 characters, without directory and extension */
static void base_name(const u8 *path, u8 *out)
{
    u8 n = path[0], start = 0, end, i, len;
    for (i = 1; i <= n; i++)
        if (path[i] == '\\' || path[i] == ':')
            start = i;
    end = n;
    for (i = (u8)(start + 1); i <= n; i++)
        if (path[i] == '.')
            end = (u8)(i - 1);
    len = (u8)(end - start);
    if (len > 8)
        len = 8;
    out[0] = len;
    for (i = 0; i < len; i++)
        out[1 + i] = path[start + 1 + i];
}

void rtl_assign(void *f, const u8 *name)
{
    FileRec *r = (FileRec *)f;
    u8 n = name[0];
    if (n > 79)
        n = 79;
    r->Name[0] = n;
    memcpy(r->Name + 1, name + 1, n);
    r->Handle = 0;
    r->Mode = fmClosed;
    r->UserData[0] = r->UserData[1] = 0;                 /* the position, in bytes */
}

void rtl_reset(void *f, u16 recsize)
{
    FileRec *r = (FileRec *)f;
    u8 b[10];
    base_name(r->Name, b);
    r->RecSize = recsize;
    if (b[0] == 0 || !FileKnown(b)) {
        ioresult = 2;
        return;
    }
    if (b[0] == 5 && memcmp(b + 1, "ITEMS", 5) == 0)
        DaxLoad(b, 0);                                   /* the contents wait in the engine's stage */
    r->Handle = 1;
    r->Mode = fmInput;
}
void rtl_rewrite(void *f, u16 recsize) { (void)f; (void)recsize; ioresult = 5; }
void rtl_reset_text(void *f) { (void)f; ioresult = 2; }
void rtl_rewrite_text(void *f) { (void)f; ioresult = 5; }
void rtl_close(void *f) { ((FileRec *)f)->Handle = 0; ((FileRec *)f)->Mode = fmClosed; }
void rtl_erase(void *f) { (void)f; }
void rtl_seek(void *f, s32 pos)
{
    FileRec *r = (FileRec *)f;
    u16 p = (u16)(pos * r->RecSize);
    r->UserData[0] = (u8)(p >> 8);
    r->UserData[1] = (u8)p;
}
int rtl_eof(void *f) { (void)f; return 1; }
void rtl_blockread(void *f, void *buf, u16 count, void *result)
{
    FileRec *r = (FileRec *)f;
    u16 pos = (u16)(((u16)r->UserData[0] << 8) | r->UserData[1]), want = (u16)(count * r->RecSize), got = 0, c;
    u8 tmp[128];
    while (got < want) {
        c = (u16)(want - got) < 128 ? (u16)(want - got) : 128;
        DaxRead((u16)(pos + got), tmp, c);
        memcpy((u8 *)buf + got, tmp, c);
        got += c;
    }
    pos += got;
    r->UserData[0] = (u8)(pos >> 8);
    r->UserData[1] = (u8)pos;
    *(u16 *)result = r->RecSize ? (u16)(got / r->RecSize) : got;
}
void rtl_blockwrite(void *f, const void *buf, u16 count, void *result) { (void)f; (void)buf; (void)count; *(u16 *)result = 0; }
void rtl_MkDir(const u8 *dir) { (void)dir; ioresult = 5; }
void rtl_read_ln(void *f) { (void)f; }
void rtl_read_str(void *f, u8 *s, int maxlen) { (void)f; (void)maxlen; s[0] = 0; }
void rtl_write_str(void *f, const u8 *s, int width) { (void)f; (void)s; (void)width; }
void rtl_write_ln(void *f) { (void)f; }
