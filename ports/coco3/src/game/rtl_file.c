/* rtl_file.c: the game's files on the CoCo (step 8.5). Two kinds, told apart by what the name finds:
 *
 *   saves     the files the game writes (SAVE\RAD.CHA, .ITM, .SPC, CHARLIST.TXT, saved games) live in the save area of the image
 *             (img.c: byte addressed through the engine's SaveRead and SaveWrite). The area starts with a directory: a header
 *             ("PSAV", the first free 256 byte unit) and 127 entries of 16 bytes (name as 8 + 3 characters, start unit, size in
 *             units, size in bytes). A file gets its room when it is created (4 KB, 15 KB for .DAT) and keeps it while it exists;
 *             an erased file's room is free again: a new file takes the smallest run of units no live entry covers (find_room).
 *   volumes   the read only game data (DAX files, ITEMS) the engine reads from the image (engapi.c, DaxLoad and DaxRead).
 *
 * This code is in the runtime bank, which holds no variables: the state of an open file is in the file variable itself (the
 * 16 bytes of UserData, at the same place in a FileRec and a TextRec): position, start, size, room, directory index, kind. */
#include "pool.h"

extern u16 rtl_ioresult;
void SaveRead(u32 off, u8 *dst, u8 n);
void SaveWrite(u32 off, const u8 *src, u8 n);
u16 FileKnown(const u8 *name);
u16 DaxLoad(const u8 *name, u16 id);
void DaxRead(u16 off, u8 *dst, u16 n);

#define U_POS 0
#define U_START 2
#define U_SIZE 4
#define U_CAP 6        /* the room, in 256 byte units */
#define U_IDX 7        /* the directory entry */
#define U_KIND 8       /* 1: a volume file, 2: a save file */
#define U_RW 9         /* 1: opened for writing */
#define DIR_ENTRIES 127
#define DIR_HEAD 16
#define NAME_LEN 11
#define SAVE_UNITS 512u       /* the save area of the image: 512 sectors */

static u16 g16(const u8 *p)
{
    return (u16)(((u16)p[0] << 8) | p[1]);
}

static void p16(u8 *p, u16 v)
{
    p[0] = (u8)(v >> 8);
    p[1] = (u8)v;
}

/* the name of a path as the directory has it: the part after the last \ or :, base padded to 8 and extension to 3 */
static void dosname(const u8 *path, u8 *out)
{
    u16 n = path[0], start = 0, i, k = 0;
    u8 c, dot = 0;
    for (i = 1; i <= n; i++)
        if (path[i] == '\\' || path[i] == ':')
            start = i;
    for (i = 0; i < NAME_LEN; i++)
        out[i] = ' ';
    for (i = start + 1; i <= n; i++) {
        c = path[i];
        if (c >= 'a' && c <= 'z')
            c = (u8)(c - 32);
        if (c == '.') {
            dot = 1;
            k = 8;
            continue;
        }
        if ((!dot && k < 8) || (dot && k < NAME_LEN))
            out[k++] = c;
    }
}

/* the base of a path without directory or extension, for the volumes (Pascal string of at most 8 characters) */
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

static u32 usave(u16 unit)
{
    return (u32)unit << 8;
}

static u16 entry_at(u8 idx)
{
    return (u16)(DIR_HEAD + ((u16)idx << 4));
}

/* the directory entry of a name: its index (the 16 bytes in e), or 0xFF */
static u8 dir_find(const u8 *key, u8 *e)
{
    u8 i;
    for (i = 0; i < DIR_ENTRIES; i++) {
        SaveRead((u32)entry_at(i), e, 16);
        if (e[0] != 0 && memcmp(e, key, NAME_LEN) == 0)
            return i;
    }
    return 0xFF;
}

/* the start of the smallest run of at least cap free units, 0xFFFF when there is none. A unit is free when no live entry's room
 * covers it (the directory takes the first eight): the room of an erased file is free again, and so is a room that an earlier
 * version of this code lost track of (it kept an erased entry's room by writing a new file's entry over it). */
static u16 find_room(u8 cap)
{
    u8 map[SAVE_UNITS / 8], e[16], i;
    u16 u, s, c, run = 0, start = 0, best = 0xFFFF, bestlen = 0xFFFF;
    memset(map, 0, sizeof(map));
    map[0] = 0xFF;
    for (i = 0; i < DIR_ENTRIES; i++) {
        SaveRead((u32)entry_at(i), e, 16);
        if (e[0] == 0)
            continue;
        s = g16(e + 11);
        for (c = e[13]; c != 0 && s < SAVE_UNITS; c--, s++)
            map[s >> 3] |= (u8)(1 << (s & 7));
    }
    for (u = 0; u <= SAVE_UNITS; u++) {
        if (u < SAVE_UNITS && (map[u >> 3] & (1 << (u & 7))) == 0) {
            if (run == 0)
                start = u;
            run++;
        } else {
            if (run >= cap && run < bestlen) {
                best = start;
                bestlen = run;
            }
            run = 0;
        }
    }
    return best;
}

/* a file created: its entry with room for cap units; the 16 bytes in e. The room of a name the directory still has is kept (the
 * file starts empty) when it is big enough. Otherwise the file gets an entry and a room of free units (find_room): the game
 * erases a character's files and writes them again at every save, and rooms that were never given back filled the area (an
 * erase then a rewrite took 5 new units each time, until the 512 were gone: fatal 40 in the middle of a save). */
static u8 dir_create(const u8 *key, u8 cap, u8 *e)
{
    u8 i, h[8], z = 0;
    u16 start, next;
    SaveRead(0UL, h, 8);
    if (memcmp(h, "PSAV", 4) != 0) {                    /* a save area nobody has used */
        memcpy(h, "PSAV", 4);
        h[4] = 0;                                        /* the first free unit (a word): the directory takes the first eight */
        h[5] = 8;
        h[6] = h[7] = 0;
        SaveWrite(0UL, h, 8);
    }
    i = dir_find(key, e);
    if (i != 0xFF) {
        if (e[13] >= cap) {
            p16(e + 14, 0);
            SaveWrite((u32)entry_at(i), e, 16);
            return i;
        }
        SaveWrite((u32)entry_at(i), &z, 1);              /* too small for what is asked now: erased, its room is free */
    }
    for (i = 0; i < DIR_ENTRIES; i++) {                  /* the first free entry */
        SaveRead((u32)entry_at(i), e, 16);
        if (e[0] == 0)
            break;
    }
    if (i == DIR_ENTRIES)
        rtl_fatal_code(0x40, DIR_ENTRIES);               /* 127 files */
    start = find_room(cap);
    if (start == 0xFFFF)
        rtl_fatal_code(0x40, (u16)(0x100 | cap));        /* no run of cap free units (the info is 256 + cap) */
    memcpy(e, key, NAME_LEN);
    p16(e + 11, start);
    e[13] = cap;
    p16(e + 14, 0);
    SaveWrite((u32)entry_at(i), e, 16);
    next = g16(h + 4);
    if (start + cap > next) {                            /* the header's first free unit: behind every room */
        p16(h + 4, (u16)(start + cap));
        SaveWrite(4UL, h + 4, 2);
    }
    return i;
}

/* ---- Assign, Reset, Rewrite, Close, Erase ---------------------------------------------------------------- */
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
    memset(r->UserData, 0, 16);
}

static void open_save(FileRec *r, const u8 *e, u8 idx, u8 rw)
{
    p16(r->UserData + U_POS, 0);
    p16(r->UserData + U_START, g16(e + 11));              /* in 256 byte units: the byte address is a long (usave) */
    memcpy(r->UserData + U_SIZE, e + 14, 2);
    r->UserData[U_CAP] = e[13];
    r->UserData[U_IDX] = idx;
    r->UserData[U_KIND] = 2;
    r->UserData[U_RW] = rw;
    r->Handle = 2;
    r->Mode = rw ? fmOutput : fmInput;
}

/* Reset: a save file if the directory has it, else a volume file */
static void open_read(FileRec *r)
{
    u8 key[NAME_LEN], e[16], b[10], idx;
    dosname(r->Name, key);
    idx = dir_find(key, e);
    if (idx != 0xFF) {
        open_save(r, e, idx, 0);
        return;
    }
    base_name(r->Name, b);
    if (b[0] == 0 || !FileKnown(b)) {
        rtl_ioresult = 2;
        return;
    }
    memset(r->UserData, 0, 16);
    if (b[0] == 5 && memcmp(b + 1, "ITEMS", 5) == 0)
        p16(r->UserData + U_SIZE, DaxLoad(b, 0));        /* the contents wait in the engine's stage */
    r->UserData[U_KIND] = 1;
    r->Handle = 1;
    r->Mode = fmInput;
}

void rtl_reset(void *f, u16 recsize)
{
    FileRec *r = (FileRec *)f;
    r->RecSize = recsize;
    open_read(r);
}

void rtl_reset_text(void *f)
{
    TextRec *t = (TextRec *)f;
    t->BufSize = 128;
    open_read((FileRec *)f);
}

static void open_write(FileRec *r)
{
    u8 key[NAME_LEN], e[16], idx, cap;
    dosname(r->Name, key);
    cap = 16;                                            /* the room of a new file, in 256 byte units, by what it is */
    if (key[8] == 'D' && key[9] == 'A' && key[10] == 'T')
        cap = 60;                                        /* a saved game: 13 KB */
    else if (key[8] == 'T' && key[9] == 'X' && key[10] == 'T')
        cap = 12;                                        /* the list of characters */
    else if (key[8] == 'I' && key[9] == 'T')
        cap = 5;                                         /* the items of a character: 63 bytes each */
    else if (key[8] == 'S' && key[9] == 'P')
        cap = 3;                                         /* the affects: 9 bytes each */
    else if (key[8] == 'S' || key[8] == 'C')
        cap = 2;                                         /* the character record: 285 bytes */
    idx = dir_create(key, cap, e);
    open_save(r, e, idx, 1);
}

void rtl_rewrite(void *f, u16 recsize)
{
    ((FileRec *)f)->RecSize = recsize;
    open_write((FileRec *)f);
}

void rtl_rewrite_text(void *f)
{
    ((TextRec *)f)->BufSize = 128;
    open_write((FileRec *)f);
}

/* Append: the end of the file, or a new file */
void rtl_append_text(void *f)
{
    FileRec *r = (FileRec *)f;
    u8 key[NAME_LEN], e[16], idx;
    ((TextRec *)f)->BufSize = 128;
    dosname(r->Name, key);
    idx = dir_find(key, e);
    if (idx == 0xFF) {
        open_write(r);
        return;
    }
    open_save(r, e, idx, 1);
    memcpy(r->UserData + U_POS, r->UserData + U_SIZE, 2);
}

void rtl_close(void *f)
{
    FileRec *r = (FileRec *)f;
    r->Handle = 0;
    r->Mode = fmClosed;
}

void rtl_erase(void *f)
{
    FileRec *r = (FileRec *)f;
    u8 key[NAME_LEN], e[16], idx, z = 0;
    dosname(r->Name, key);
    idx = dir_find(key, e);
    if (idx != 0xFF)
        SaveWrite((u32)entry_at(idx), &z, 1);
    else
        rtl_ioresult = 2;
}

void rtl_MkDir(const u8 *dir)
{
    (void)dir;                                           /* the save area is the directory */
}

/* ---- positions -------------------------------------------------------------------------------------------- */
void rtl_seek(void *f, s32 pos)
{
    FileRec *r = (FileRec *)f;
    p16(r->UserData + U_POS, (u16)((u16)pos * r->RecSize));
}

s32 rtl_filepos(void *f)
{
    FileRec *r = (FileRec *)f;
    u16 rs = r->RecSize ? r->RecSize : 1;
    return (s32)(g16(r->UserData + U_POS) / rs);
}

s32 rtl_filesize(void *f)
{
    FileRec *r = (FileRec *)f;
    u16 rs = r->RecSize ? r->RecSize : 1;
    return (s32)(g16(r->UserData + U_SIZE) / rs);
}

int rtl_eof(void *f)
{
    FileRec *r = (FileRec *)f;
    if (r->UserData[U_KIND] != 2)
        return 1;
    return g16(r->UserData + U_POS) >= g16(r->UserData + U_SIZE);
}

void rtl_truncate(void *f)
{
    FileRec *r = (FileRec *)f;
    u16 pos = g16(r->UserData + U_POS);
    p16(r->UserData + U_SIZE, pos);
    SaveWrite((u32)entry_at(r->UserData[U_IDX]) + 14, r->UserData + U_SIZE, 2);
}

void rtl_flush(void *f)
{
    (void)f;
}

/* ---- bytes ------------------------------------------------------------------------------------------------- */
/* up to n bytes at the position into buf; the number read */
static u16 rd(FileRec *r, u8 *buf, u16 n)
{
    u16 pos = g16(r->UserData + U_POS), size = g16(r->UserData + U_SIZE), start = g16(r->UserData + U_START), got = 0, c;
    u8 tmp[64];

    if (pos >= size)
        return 0;
    if (n > (u16)(size - pos))
        n = (u16)(size - pos);
    while (got < n) {
        c = (u16)(n - got) < 64 ? (u16)(n - got) : 64;
        SaveRead(usave(start) + pos + got, tmp, (u8)c);
        memcpy(buf + got, tmp, c);
        got = (u16)(got + c);
    }
    p16(r->UserData + U_POS, (u16)(pos + got));
    return got;
}

/* n bytes at the position, growing the file; the room is the end */
static void wr(FileRec *r, const u8 *buf, u16 n)
{
    u16 pos = g16(r->UserData + U_POS), size = g16(r->UserData + U_SIZE), start = g16(r->UserData + U_START), done = 0, c;
    u16 room = (u16)((u16)r->UserData[U_CAP] << 8);
    u8 tmp[64];
    if (r->UserData[U_KIND] != 2 || !r->UserData[U_RW]) {
        rtl_ioresult = 105;
        return;
    }
    if ((u32)pos + n > room)
        rtl_fatal_code(0x42, pos);
    while (done < n) {
        c = (u16)(n - done) < 64 ? (u16)(n - done) : 64;
        memcpy(tmp, buf + done, c);
        SaveWrite(usave(start) + pos + done, tmp, (u8)c);
        done = (u16)(done + c);
    }
    pos = (u16)(pos + n);
    p16(r->UserData + U_POS, pos);
    if (pos > size) {
        p16(r->UserData + U_SIZE, pos);
        SaveWrite((u32)entry_at(r->UserData[U_IDX]) + 14, r->UserData + U_SIZE, 2);
    }
}

void rtl_blockread(void *f, void *buf, u16 count, void *result)
{
    FileRec *r = (FileRec *)f;
    u16 want = (u16)(count * r->RecSize), got = 0, c;
    u8 tmp[128];
    if (r->UserData[U_KIND] == 2) {
        got = rd(r, (u8 *)buf, want);
    } else {
        u16 pos = g16(r->UserData + U_POS), size = g16(r->UserData + U_SIZE);
        if (pos >= size)
            want = 0;
        else if (want > (u16)(size - pos))
            want = (u16)(size - pos);                    /* the file ends: the rest of the buffer stays as it was */
        while (got < want) {
            c = (u16)(want - got) < 128 ? (u16)(want - got) : 128;
            DaxRead((u16)(pos + got), tmp, c);
            memcpy((u8 *)buf + got, tmp, c);
            got = (u16)(got + c);
        }
        p16(r->UserData + U_POS, (u16)(pos + got));
    }
    *(u16 *)result = r->RecSize ? (u16)(got / r->RecSize) : got;
}

void rtl_blockwrite(void *f, const void *buf, u16 count, void *result)
{
    FileRec *r = (FileRec *)f;
    u16 n = (u16)(count * r->RecSize);
    wr(r, (const u8 *)buf, n);
    *(u16 *)result = count;
}

void rtl_file_read(void *f, void *rec)
{
    FileRec *r = (FileRec *)f;
    rd(r, (u8 *)rec, r->RecSize);
}

void rtl_file_write(void *f, const void *rec)
{
    FileRec *r = (FileRec *)f;
    wr(r, (const u8 *)rec, r->RecSize);
}

/* ---- text ------------------------------------------------------------------------------------------------- */
static int tpeek(FileRec *r)
{
    u16 pos = g16(r->UserData + U_POS);
    u8 c;
    if (r->UserData[U_KIND] != 2 || pos >= g16(r->UserData + U_SIZE))
        return -1;
    SaveRead(usave(g16(r->UserData + U_START)) + pos, &c, 1);
    return c;
}

static int tget(FileRec *r)
{
    int c = tpeek(r);
    if (c >= 0)
        p16(r->UserData + U_POS, (u16)(g16(r->UserData + U_POS) + 1));
    return c;
}

int rtl_eoln(void *f)
{
    int c = tpeek((FileRec *)f);
    return c < 0 || c == '\r' || c == '\n' || c == 26;
}

void rtl_read_str(void *f, u8 *s, int maxlen)
{
    FileRec *r = (FileRec *)f;
    u8 n = 0;
    int c;
    while ((c = tpeek(r)) >= 0 && c != '\r' && c != '\n' && c != 26) {
        tget(r);
        if (n < maxlen)
            s[1 + n++] = (u8)c;
    }
    s[0] = n;
}

void rtl_read_char(void *f, u8 *c)
{
    int v = tget((FileRec *)f);
    *c = v < 0 ? 26 : (u8)v;
}

void rtl_read_ln(void *f)
{
    int c;
    while ((c = tget((FileRec *)f)) >= 0 && c != '\n' && c != 26)
        ;
}

/* The console (the game's Output when it stops with a message): the harness reads it at $0970, 80 bytes, a line end is a bar */
#define CON ((u8 *)0x0970)
static void con_put(const u8 *s, u8 n)
{
    u8 i, k = 0;
    while (k < 78 && CON[k])
        k++;
    for (i = 0; i < n && k < 78; i++)
        CON[k++] = s[i];
    CON[k] = 0;
}

void rtl_write_str(void *f, const u8 *s, int width)
{
    FileRec *r = (FileRec *)f;
    if (r->UserData[U_KIND] == 0) {
        con_put(s + 1, s[0]);
        return;
    }
    static const u8 sp = ' ';
    int i;
    for (i = s[0]; i < width; i++)
        wr(r, &sp, 1);
    wr(r, s + 1, s[0]);
}

void rtl_write_char(void *f, u8 c, int width)
{
    FileRec *r = (FileRec *)f;
    static const u8 sp = ' ';
    int i;
    for (i = 1; i < width; i++)
        wr(r, &sp, 1);
    wr(r, &c, 1);
}

void rtl_write_ln(void *f)
{
    static const u8 crlf[2] = {13, 10};
    if (((FileRec *)f)->UserData[U_KIND] == 0) {
        con_put((const u8 *)"|", 1);
        return;
    }
    wr((FileRec *)f, crlf, 2);
}
