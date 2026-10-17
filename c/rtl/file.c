/* file.c: Pascal files over the host's files, with DOS names.
 *
 * The game names files the DOS way (`C:\POOLRAD\8X8D1.DAX`, `pool.cfg`, `SAVE\RAD.CHA`). The directory that DOS calls
 * \POOLRAD is the data directory the platform names; reads find a file in the save directory first (what the game
 * wrote) and then in the data directory, so a pinned data directory is never changed: a write goes to the save
 * directory, and a file opened for update is copied there on its first write. Names match without regard to case. */
#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <direct.h>
#include <io.h>
#include <windows.h>
#define MKDIR(p) _mkdir(p)
#ifndef S_ISDIR
#define S_ISDIR(m) (((m) & _S_IFMT) == _S_IFDIR)
#endif
#else
#include <dirent.h>
#include <unistd.h>
#define MKDIR(p) mkdir((p), 0777)
#endif

#include "platform.h"

#define MAX_FILES 64
#define IO_NOTFOUND 2
#define IO_NOPATH 3
#define IO_ACCESS 5
#define IO_READ 100
#define IO_WRITE 101
#define IO_NOTOPEN 103
#define IO_NOTINPUT 104
#define IO_NOTOUTPUT 105

typedef struct HostFile {
  FILE *fp;
  char path[1024];       /* the host path currently open */
  char rel[256];         /* the DOS name below \POOLRAD, upper case ("SAVE\RAD.CHA") */
  int in_layer;          /* the open file is in the save directory */
  int can_write;
  int lookahead;         /* text input: one character read ahead, -2 none */
} HostFile;

static HostFile files[MAX_FILES];
static char cwd[256] = "";              /* current directory below \POOLRAD, upper case, no slashes at the ends */
static char deleted[64][256];
static int ndeleted;

#define IORES (*(u16 *)(pool_ds + 0x4426))
#define FILEMODE (*(u8 *)(pool_ds + 0x442C))

static void ioerr(u16 code)
{
  if (IORES == 0) {
    IORES = code;
  }
}

u16 rtl_IOResult(void)
{
  u16 r = IORES;
  IORES = 0;
  return r;
}

/* Lists a host directory: calls cb(name, is_dir, ctx) for each entry until it returns nonzero. */
static int dir_list(const char *path, int (*cb)(const char *name, int is_dir, void *ctx), void *ctx)
{
#ifdef _WIN32
  char pat[1100];
  WIN32_FIND_DATAA fd;
  HANDLE h;
  snprintf(pat, sizeof pat, "%s\\*", path);
  h = FindFirstFileA(pat, &fd);
  if (h == INVALID_HANDLE_VALUE) {
    return 0;
  }
  do {
    if (strcmp(fd.cFileName, ".") && strcmp(fd.cFileName, "..") &&
        cb(fd.cFileName, (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0, ctx)) {
      FindClose(h);
      return 1;
    }
  } while (FindNextFileA(h, &fd));
  FindClose(h);
  return 0;
#else
  DIR *d = opendir(path);
  struct dirent *e;
  if (!d) {
    return 0;
  }
  while ((e = readdir(d)) != NULL) {
    struct stat st;
    char full[1200];
    int isdir = 0;
    if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) {
      continue;
    }
    snprintf(full, sizeof full, "%s/%s", path, e->d_name);
    if (stat(full, &st) == 0) {
      isdir = S_ISDIR(st.st_mode) != 0;
    }
    if (cb(e->d_name, isdir, ctx)) {
      closedir(d);
      return 1;
    }
  }
  closedir(d);
  return 0;
#endif
}

/* ---- names ------------------------------------------------------------------------------------------------ */
/* A DOS name to the form below \POOLRAD: upper case, backslashes, no drive; relative names start at the current
 * directory. Returns 0 when the name is outside \POOLRAD. */
static int dos_rel(const u8 *pname, char *out, size_t cap)
{
  char buf[512];
  int n = pname[0], i, j = 0;
  char *parts[64];
  int np = 0;
  char *tok;
  char acc[512];
  for (i = 0; i < n && j < (int)sizeof buf - 1; i++) {
    char c = (char)pname[1 + i];
    buf[j++] = c == '/' ? '\\' : (char)toupper((unsigned char)c);
  }
  buf[j] = 0;
  i = 0;
  if (j >= 2 && buf[1] == ':') {
    i = 2;
  }
  acc[0] = 0;
  if (buf[i] != '\\') {                  /* relative: start at the current directory */
    strcpy(acc, "\\POOLRAD");
    if (cwd[0]) {
      strcat(acc, "\\");
      strcat(acc, cwd);
    }
    strcat(acc, "\\");
  }
  strcat(acc, buf + i);
  /* resolve . and .. */
  tok = strtok(acc, "\\");
  while (tok) {
    if (strcmp(tok, ".") == 0) {
    } else if (strcmp(tok, "..") == 0) {
      if (np) np--;
    } else if (tok[0]) {
      parts[np++] = tok;
    }
    tok = strtok(NULL, "\\");
  }
  if (np == 0 || strcmp(parts[0], "POOLRAD") != 0) {
    return 0;
  }
  out[0] = 0;
  for (i = 1; i < np; i++) {
    if (i > 1) {
      strncat(out, "\\", cap - strlen(out) - 1);
    }
    strncat(out, parts[i], cap - strlen(out) - 1);
  }
  return 1;
}

typedef struct Match {
  const char *want;
  char found[256];
} Match;

static int match_cb(const char *name, int is_dir, void *ctx)
{
  Match *m = (Match *)ctx;
  const char *a = name, *b = m->want;
  (void)is_dir;
  while (*a && *b && toupper((unsigned char)*a) == toupper((unsigned char)*b)) {
    a++;
    b++;
  }
  if (!*a && !*b) {
    snprintf(m->found, sizeof m->found, "%s", name);
    return 1;
  }
  return 0;
}

/* Find a path below `root` matching `rel` (backslash separated) without regard to case; writes the host path. */
static int find_host(const char *root, const char *rel, char *out, size_t cap)
{
  char cur[1024];
  char tmp[512];
  char *tok;
  strncpy(cur, root, sizeof cur - 1);
  cur[sizeof cur - 1] = 0;
  strncpy(tmp, rel, sizeof tmp - 1);
  tmp[sizeof tmp - 1] = 0;
  tok = strtok(tmp, "\\");
  while (tok) {
    Match m;
    m.want = tok;
    m.found[0] = 0;
    if (!dir_list(cur, match_cb, &m)) {
      return 0;
    }
    strncat(cur, "/", sizeof cur - strlen(cur) - 1);
    strncat(cur, m.found, sizeof cur - strlen(cur) - 1);
    tok = strtok(NULL, "\\");
  }
  strncpy(out, cur, cap - 1);
  out[cap - 1] = 0;
  return 1;
}

static int is_deleted(const char *rel)
{
  int i;
  for (i = 0; i < ndeleted; i++) {
    if (strcmp(deleted[i], rel) == 0) {
      return 1;
    }
  }
  return 0;
}

static void mkdirs(const char *path)
{
  char tmp[1024];
  char *p;
  strncpy(tmp, path, sizeof tmp - 1);
  tmp[sizeof tmp - 1] = 0;
  for (p = tmp + 1; *p; p++) {
    if (*p == '/') {
      *p = 0;
      MKDIR(tmp);
      *p = '/';
    }
  }
}

/* The path of `rel` in the save directory, creating folders (upper case names, as DOS shows them). */
static void layer_path(const char *rel, char *out, size_t cap, int create_dirs)
{
  char last[256];
  const char *slash = strrchr(rel, '\\');
  char dir[1024];
  snprintf(dir, sizeof dir, "%s", platform_save_dir());
  if (slash) {
    char sub[256];
    size_t n = (size_t)(slash - rel);
    memcpy(sub, rel, n);
    sub[n] = 0;
    {
      char *p;
      for (p = sub; *p; p++) {
        if (*p == '\\') *p = '/';
      }
    }
    strncat(dir, "/", sizeof dir - strlen(dir) - 1);
    strncat(dir, sub, sizeof dir - strlen(dir) - 1);
    snprintf(last, sizeof last, "%s", slash + 1);
  } else {
    snprintf(last, sizeof last, "%s", rel);
  }
  if (create_dirs) {
    char probe[1100];
    snprintf(probe, sizeof probe, "%s/x", dir);
    mkdirs(probe);
  }
  snprintf(out, cap, "%s/%s", dir, last);
}

/* The host path to read `rel` from: the save directory first, then the data directory. */
static int locate(const char *rel, char *out, size_t cap, int *in_layer)
{
  if (is_deleted(rel)) {
    return 0;
  }
  if (find_host(platform_save_dir(), rel, out, cap)) {
    *in_layer = 1;
    return 1;
  }
  if (find_host(platform_data_dir(), rel, out, cap)) {
    *in_layer = 0;
    return 1;
  }
  return 0;
}

/* ---- the file record ---------------------------------------------------------------------------------------- */
static HostFile *host_of(void *f, int need_open)
{
  FileRec *r = (FileRec *)f;
  if (r->Mode == fmClosed || r->Mode == 0) {
    if (need_open) {
      ioerr(IO_NOTOPEN);
    }
    return NULL;
  }
  if (r->Handle >= MAX_FILES || !files[r->Handle].fp) {
    if (need_open) {
      ioerr(IO_NOTOPEN);
    }
    return NULL;
  }
  return &files[r->Handle];
}

static int alloc_slot(void)
{
  int i;
  for (i = 2; i < MAX_FILES; i++) {
    if (!files[i].fp) {
      return i;
    }
  }
  return -1;
}

void rtl_assign(void *f, const u8 *name)
{
  FileRec *r = (FileRec *)f;
  int n = name[0] > 79 ? 79 : name[0];
  r->Handle = 0;
  r->Mode = fmClosed;
  memset(r->Name, 0, sizeof r->Name);
  memcpy(r->Name, name + 1, n);
}

static int open_file(void *f, const char *mode_ro_rw, u16 recsize, u16 fm, int create)
{
  FileRec *r = (FileRec *)f;
  u8 pname[81];
  char rel[256], path[1024];
  int slot, in_layer = 0;
  HostFile *h;
  FILE *fp;
  int n = (int)strlen((char *)r->Name);
  if (n > 79) n = 79;
  pname[0] = (u8)n;
  memcpy(pname + 1, r->Name, n);
  if (n == 0) {                          /* Assign(f, '') is the console */
    ioerr(IO_NOTFOUND);
    return 0;
  }
  if (!dos_rel(pname, rel, sizeof rel)) {
    ioerr(IO_NOPATH);
    return 0;
  }
  slot = alloc_slot();
  if (slot < 0) {
    ioerr(4);
    return 0;
  }
  if (getenv("POOLRAD_TRACE")) {
    fprintf(stderr, "open %s %s\n", rel, create ? "(create)" : "");
  }
  h = &files[slot];
  memset(h, 0, sizeof *h);
  h->lookahead = -2;
  strncpy(h->rel, rel, sizeof h->rel - 1);
  if (create) {
    layer_path(rel, path, sizeof path, 1);
    {
      /* a replaced file keeps the case of the existing name in the layer */
      char existing[1024];
      if (find_host(platform_save_dir(), rel, existing, sizeof existing)) {
        snprintf(path, sizeof path, "%s", existing);
      }
    }
    fp = fopen(path, "w+b");
    in_layer = 1;
    {
      int i;
      for (i = 0; i < ndeleted; i++) {
        if (strcmp(deleted[i], rel) == 0) {
          memmove(deleted[i], deleted[ndeleted - 1], sizeof deleted[0]);
          ndeleted--;
          break;
        }
      }
    }
  } else {
    if (!locate(rel, path, sizeof path, &in_layer)) {
      ioerr(IO_NOTFOUND);
      return 0;
    }
    fp = fopen(path, in_layer && fm != 0 ? "r+b" : "rb");
    if (fp && in_layer && fm == 0) {
      fp = freopen(path, "rb", fp);
    }
  }
  if (!fp) {
    ioerr(create ? IO_ACCESS : IO_NOTFOUND);
    return 0;
  }
  h->fp = fp;
  strncpy(h->path, path, sizeof h->path - 1);
  h->in_layer = in_layer;
  h->can_write = in_layer || create;
  r->Handle = (u16)slot;
  r->RecSize = recsize;
  r->Mode = fmInOut;
  (void)mode_ro_rw;
  return 1;
}

void rtl_reset(void *f, u16 recsize)
{
  if (open_file(f, "rb", recsize ? recsize : 128, FILEMODE & 3, 0)) {
    ((FileRec *)f)->Mode = fmInOut;
  }
}

void rtl_rewrite(void *f, u16 recsize)
{
  if (open_file(f, "w+b", recsize ? recsize : 128, 2, 1)) {
    ((FileRec *)f)->Mode = fmInOut;
  }
}

void rtl_reset_text(void *f)
{
  if (open_file(f, "rb", 1, 0, 0)) {
    ((FileRec *)f)->Mode = fmInput;
  }
}

void rtl_rewrite_text(void *f)
{
  if (open_file(f, "w+b", 1, 2, 1)) {
    ((FileRec *)f)->Mode = fmOutput;
  }
}

void rtl_append_text(void *f)
{
  if (open_file(f, "r+b", 1, 2, 0)) {
    HostFile *h = host_of(f, 0);
    if (h) {
      fseek(h->fp, 0, SEEK_END);
    }
    ((FileRec *)f)->Mode = fmOutput;
  } else if (IORES == IO_NOTFOUND) {
    IORES = 0;
    rtl_rewrite_text(f);
  }
}

void rtl_close(void *f)
{
  FileRec *r = (FileRec *)f;
  HostFile *h = host_of(f, 0);
  if (!h) {
    IORES = IO_NOTOPEN;                  /* Close on a file that is not open says so, over an earlier error */
  }
  if (h) {
    fclose(h->fp);
    h->fp = NULL;
  }
  r->Mode = fmClosed;
}

void rtl_erase(void *f)
{
  FileRec *r = (FileRec *)f;
  u8 pname[81];
  char rel[256], path[1024];
  int n = (int)strlen((char *)r->Name);
  if (n > 79) n = 79;
  pname[0] = (u8)n;
  memcpy(pname + 1, r->Name, n);
  if (!dos_rel(pname, rel, sizeof rel)) {
    ioerr(IO_NOPATH);
    return;
  }
  if (find_host(platform_save_dir(), rel, path, sizeof path)) {
    remove(path);
  }
  {
    char dp[1024];
    int lay;
    if (find_host(platform_data_dir(), rel, dp, sizeof dp) && !is_deleted(rel) && ndeleted < 64) {
      strncpy(deleted[ndeleted++], rel, 255);
    } else if (!find_host(platform_data_dir(), rel, dp, sizeof dp) && !find_host(platform_save_dir(), rel, dp, sizeof dp)) {
      ioerr(IO_NOTFOUND);
    }
    (void)lay;
  }
}

/* A file from the data directory is copied to the save directory before its first write. */
static int make_writable(HostFile *h)
{
  char dst[1024];
  FILE *out;
  long pos;
  char buf[4096];
  size_t n;
  if (h->in_layer) {
    return 1;
  }
  layer_path(h->rel, dst, sizeof dst, 1);
  pos = ftell(h->fp);
  out = fopen(dst, "wb");
  if (!out) {
    return 0;
  }
  fseek(h->fp, 0, SEEK_SET);
  while ((n = fread(buf, 1, sizeof buf, h->fp)) > 0) {
    fwrite(buf, 1, n, out);
  }
  fclose(out);
  fclose(h->fp);
  h->fp = fopen(dst, "r+b");
  if (!h->fp) {
    return 0;
  }
  fseek(h->fp, pos, SEEK_SET);
  strncpy(h->path, dst, sizeof h->path - 1);
  h->in_layer = 1;
  h->can_write = 1;
  return 1;
}

void rtl_seek(void *f, s32 pos)
{
  FileRec *r = (FileRec *)f;
  HostFile *h = IORES ? NULL : host_of(f, 1);       /* an unread IOResult makes file operations do nothing */
  if (h) {
    fseek(h->fp, (long)pos * (long)r->RecSize, SEEK_SET);
  }
}

void rtl_truncate(void *f)
{
  HostFile *h = host_of(f, 1);
  if (h && make_writable(h)) {
    long pos = ftell(h->fp);
    fflush(h->fp);
#ifdef _WIN32
    _chsize(_fileno(h->fp), pos);
#else
    if (ftruncate(fileno(h->fp), pos) != 0) {
      ioerr(IO_WRITE);
    }
#endif
  }
}

void rtl_flush(void *f)
{
  HostFile *h = host_of(f, 1);
  if (h) {
    fflush(h->fp);
  }
}

s32 rtl_filepos(void *f)
{
  FileRec *r = (FileRec *)f;
  HostFile *h = host_of(f, 1);
  return h ? (s32)(ftell(h->fp) / (long)(r->RecSize ? r->RecSize : 1)) : 0;
}

s32 rtl_filesize(void *f)
{
  FileRec *r = (FileRec *)f;
  HostFile *h = host_of(f, 1);
  long cur, end;
  if (!h) {
    return 0;
  }
  cur = ftell(h->fp);
  fseek(h->fp, 0, SEEK_END);
  end = ftell(h->fp);
  fseek(h->fp, cur, SEEK_SET);
  return (s32)(end / (long)(r->RecSize ? r->RecSize : 1));
}

int rtl_eof(void *f)
{
  FileRec *r = (FileRec *)f;
  HostFile *h = host_of(f, 0);
  int c;
  if (!h) {
    return 1;
  }
  if (r->Mode == fmInput && h->lookahead != -2) {
    return h->lookahead == -1 || h->lookahead == 26;
  }
  c = fgetc(h->fp);
  if (c == EOF) {
    return 1;
  }
  ungetc(c, h->fp);
  return r->Mode == fmInput && c == 26;
}

void rtl_blockread(void *f, void *buf, u16 count, void *result)
{
  FileRec *r = (FileRec *)f;
  HostFile *h = IORES ? NULL : host_of(f, 1);
  size_t want = (size_t)count * r->RecSize, got;
  extern void rtl_store(void *dst, const void *src, u32 count);
  u8 tmp[4096];
  u8 *dst = (u8 *)buf;
  size_t total = 0;
  if (!h) {
    return;
  }
  while (total < want) {
    size_t chunk = want - total > sizeof tmp ? sizeof tmp : want - total;
    got = fread(tmp, 1, chunk, h->fp);
    if (got == 0) {
      break;
    }
    rtl_store(dst + total, tmp, (u32)got);
    total += got;
    if (got < chunk) {
      break;
    }
  }
  if (getenv("POOLRAD_TRACE")) {
    fprintf(stderr, "  blockread %s rec=%u want=%u got=%u pos=%ld\n", h->rel, r->RecSize, (unsigned)want, (unsigned)total, ftell(h->fp));
  }
  if (result) {
    u16 n = (u16)(total / (r->RecSize ? r->RecSize : 1));
    memcpy(result, &n, 2);
    if (total % (r->RecSize ? r->RecSize : 1)) {
      /* a partial record is not counted; the file position stays after it, as DOS leaves it */
    }
  } else if (total < want) {
    ioerr(IO_READ);
  }
}

void rtl_blockwrite(void *f, const void *buf, u16 count, void *result)
{
  FileRec *r = (FileRec *)f;
  HostFile *h = IORES ? NULL : host_of(f, 1);
  size_t want = (size_t)count * r->RecSize, put;
  if (!h) {
    return;
  }
  if (!make_writable(h)) {
    ioerr(IO_ACCESS);
    return;
  }
  put = fwrite(buf, 1, want, h->fp);
  if (result) {
    u16 n = (u16)(put / (r->RecSize ? r->RecSize : 1));
    memcpy(result, &n, 2);
  } else if (put < want) {
    ioerr(IO_WRITE);
  }
}

void rtl_file_read(void *f, void *rec)
{
  rtl_blockread(f, rec, 1, NULL);
}

void rtl_file_write(void *f, const void *rec)
{
  rtl_blockwrite(f, rec, 1, NULL);
}

void rtl_MkDir(const u8 *dir)
{
  char rel[256], path[1024];
  if (!dos_rel(dir, rel, sizeof rel)) {
    ioerr(IO_NOPATH);
    return;
  }
  layer_path(rel, path, sizeof path, 1);
  if (MKDIR(path) != 0 && errno != EEXIST) {
    ioerr(IO_ACCESS);
  }
}

void rtl_RmDir(const u8 *dir)
{
  (void)dir;
}

void rtl_ChDir(const u8 *dir)
{
  char rel[256];
  if (!dos_rel(dir, rel, sizeof rel)) {
    ioerr(IO_NOPATH);
    return;
  }
  strncpy(cwd, rel, sizeof cwd - 1);
}

/* ---- text -------------------------------------------------------------------------------------------------- */
static void console_write(const char *s, size_t n)
{
  fwrite(s, 1, n, stderr);
}

static void out_bytes(void *f, const char *s, size_t n)
{
  FileRec *r = (FileRec *)f;
  if (r->Mode == fmOutput && r->Handle == 1) {
    console_write(s, n);
    return;
  }
  if (r->Mode != fmOutput) {
    ioerr(IO_NOTOUTPUT);
    return;
  }
  {
    HostFile *h = host_of(f, 1);
    if (h && make_writable(h)) {
      fwrite(s, 1, n, h->fp);
    }
  }
}

void rtl_write_str(void *f, const u8 *s, int width)
{
  int pad = width > s[0] ? width - s[0] : 0;
  while (pad-- > 0) out_bytes(f, " ", 1);
  out_bytes(f, (const char *)s + 1, s[0]);
}

void rtl_write_char(void *f, u8 c, int width)
{
  int pad = width > 1 ? width - 1 : 0;
  while (pad-- > 0) out_bytes(f, " ", 1);
  out_bytes(f, (const char *)&c, 1);
}

void rtl_write_int(void *f, s32 v, int width)
{
  char buf[32];
  int n = snprintf(buf, sizeof buf, "%*ld", width, (long)v);
  out_bytes(f, buf, (size_t)n);
}

void rtl_write_real(void *f, double v, int width, int dec)
{
  char buf[64];
  int n = dec >= 0 ? snprintf(buf, sizeof buf, "%*.*f", width, dec, v) : snprintf(buf, sizeof buf, "%*.10E", width > 0 ? width : 17, v);
  out_bytes(f, buf, (size_t)n);
}

void rtl_write_bool(void *f, int v, int width)
{
  const char *s = v ? "TRUE" : "FALSE";
  char buf[32];
  int n = snprintf(buf, sizeof buf, "%*s", width, s);
  out_bytes(f, buf, (size_t)n);
}

void rtl_write_ln(void *f)
{
  out_bytes(f, "\r\n", 2);
}

static int in_peek(void *f)
{
  HostFile *h = host_of(f, 1);
  if (!h) {
    return -1;
  }
  if (h->lookahead == -2) {
    h->lookahead = fgetc(h->fp);
  }
  return h->lookahead;
}

static int in_get(void *f)
{
  int c = in_peek(f);
  HostFile *h = host_of(f, 0);
  if (h) {
    h->lookahead = -2;
  }
  return c;
}

void rtl_read_char(void *f, u8 *c)
{
  int ch = in_get(f);
  *c = ch < 0 ? 26 : (u8)ch;
}

void rtl_read_str(void *f, u8 *s, int maxlen)
{
  int n = 0, ch;
  while ((ch = in_peek(f)) >= 0 && ch != '\r' && ch != '\n' && ch != 26) {
    in_get(f);
    if (n < maxlen) {
      s[1 + n++] = (u8)ch;
    }
  }
  s[0] = (u8)n;
}

void rtl_read_int(void *f, void *v, int size, int is_signed)
{
  u8 tmp[32];
  int n = 0, ch;
  s16 code;
  while ((ch = in_peek(f)) == ' ' || ch == '\t') in_get(f);
  while ((ch = in_peek(f)) >= 0 && ch != ' ' && ch != '\r' && ch != '\n' && ch != 26 && n < 30) {
    in_get(f);
    tmp[1 + n++] = (u8)ch;
  }
  tmp[0] = (u8)n;
  rtl_str_val(tmp, v, size, is_signed, &code);
  if (code) {
    ioerr(106);
  }
}

void rtl_read_real(void *f, double *v)
{
  (void)f;
  *v = 0;
}

void rtl_read_ln(void *f)
{
  int ch;
  while ((ch = in_get(f)) >= 0 && ch != '\n' && ch != 26) {
  }
}

int rtl_eoln(void *f)
{
  int c = in_peek(f);
  return c < 0 || c == '\r' || c == '\n' || c == 26;
}

/* ---- start up ---------------------------------------------------------------------------------------------- */
void file_init(void)
{
  TextRec *in = (TextRec *)(pool_ds + 0x8508), *out = (TextRec *)(pool_ds + 0x8608);
  memset(files, 0, sizeof files);
  in->Handle = 0;
  in->Mode = fmInput;
  out->Handle = 1;
  out->Mode = fmOutput;
  cwd[0] = 0;
  ndeleted = 0;
}

/* The pinned data file a DOS name (\POOLRAD\X) stands for, or 0. */
int rtl_data_file(const char *dos_name, char *out, size_t cap)
{
  const char *rel = dos_name;
  if (strncmp(rel, "\\POOLRAD\\", 9) == 0) {
    rel += 9;
  }
  return find_host(platform_data_dir(), rel, out, cap);
}

/* The files written during the run (below the save directory) and their DOS names, for the replay's checks. */
int rtl_written_files(void (*cb)(const char *dos_name, const char *host_path, void *ctx), void *ctx);

typedef struct WalkCtx {
  const char *host;
  const char *dos;
  void (*cb)(const char *, const char *, void *);
  void *ctx;
  int n;
} WalkCtx;

static int walk(const char *host, const char *dos, void (*cb)(const char *, const char *, void *), void *ctx);

static int walk_cb(const char *name, int is_dir, void *c)
{
  WalkCtx *w = (WalkCtx *)c;
  char hp[1200], dp[600];
  size_t i;
  snprintf(hp, sizeof hp, "%s/%s", w->host, name);
  snprintf(dp, sizeof dp, "%s\\%s", w->dos, name);
  for (i = 0; dp[i]; i++) {
    dp[i] = (char)toupper((unsigned char)dp[i]);
  }
  if (is_dir) {
    w->n += walk(hp, dp, w->cb, w->ctx);
  } else {
    w->cb(dp, hp, w->ctx);
    w->n++;
  }
  return 0;
}

static int walk(const char *host, const char *dos, void (*cb)(const char *, const char *, void *), void *ctx)
{
  WalkCtx w;
  w.host = host;
  w.dos = dos;
  w.cb = cb;
  w.ctx = ctx;
  w.n = 0;
  dir_list(host, walk_cb, &w);
  return w.n;
}

int rtl_written_files(void (*cb)(const char *, const char *, void *), void *ctx)
{
  return walk(platform_save_dir(), "\\POOLRAD", cb, ctx);
}
