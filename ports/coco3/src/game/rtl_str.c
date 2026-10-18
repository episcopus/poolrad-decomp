/* rtl_str.c: Turbo Pascal strings and sets for the CoCo (step 8.5c): the same behaviour as c/rtl/core.c, which the
 * recorded sessions check. A string is its length byte and up to 255 characters; the pointers are native or into a window. */
#include "pool.h"

u8 *rtl_str_assign(u8 *dst, int maxlen, const u8 *src)
{
    u8 n = src[0];
    if (dst == src) {
        if (n > maxlen)
            dst[0] = (u8)maxlen;
        return dst;
    }
    if (n > maxlen)
        n = (u8)maxlen;
    memmove(dst + 1, src + 1, n);
    dst[0] = n;
    return dst;
}

u8 *rtl_str_cat_v(u8 *dst, int n, ...)
{
    u8 tmp[256];
    const u8 *parts[16];
    va_list ap;
    int i, len = 0, l;
    va_start(ap, n);
    for (i = 0; i < n && i < 16; i++)
        parts[i] = va_arg(ap, const u8 *);
    va_end(ap);
    for (i = 0; i < n && i < 16; i++) {
        l = parts[i][0];
        if (len + l > 255)
            l = 255 - len;
        memcpy(tmp + 1 + len, parts[i] + 1, l);
        len += l;
    }
    tmp[0] = (u8)len;
    memcpy(dst, tmp, len + 1);
    return dst;
}

u8 *rtl_str_char(u8 *dst, u8 c)
{
    dst[0] = 1;
    dst[1] = c;
    return dst;
}

int rtl_str_cmp(const u8 *a, const u8 *b)
{
    int la = a[0], lb = b[0], n = la < lb ? la : lb, i;
    for (i = 1; i <= n; i++) {
        if (a[i] != b[i])
            return a[i] < b[i] ? -1 : 1;
    }
    return la == lb ? 0 : (la < lb ? -1 : 1);
}

u8 *rtl_str_copy(u8 *dst, const u8 *s, int idx, int cnt)
{
    int len = s[0];
    u8 tmp[256];
    if (idx < 1)
        idx = 1;
    if (cnt < 0 || idx > len)
        cnt = 0;
    else if (idx + cnt - 1 > len)
        cnt = len - idx + 1;
    if (cnt > 0)
        memcpy(tmp + 1, s + idx, cnt);
    tmp[0] = (u8)cnt;
    memcpy(dst, tmp, cnt + 1);
    return dst;
}

u8 rtl_str_pos(const u8 *sub, const u8 *s)
{
    int ls = sub[0], l = s[0], i;
    if (ls == 0)
        return 0;
    for (i = 1; i + ls - 1 <= l; i++) {
        if (memcmp(s + i, sub + 1, ls) == 0)
            return (u8)i;
    }
    return 0;
}

void rtl_str_delete(u8 *s, int idx, int cnt)
{
    int len = s[0];
    if (idx < 1 || idx > len || cnt <= 0)
        return;
    if (idx + cnt - 1 > len)
        cnt = len - idx + 1;
    memmove(s + idx, s + idx + cnt, len - (idx + cnt - 1));
    s[0] = (u8)(len - cnt);
}

void rtl_str_insert(const u8 *src, u8 *s, int maxlen, int idx)
{
    u8 tmp[512];
    int ls = src[0], len = s[0], n;
    if (idx < 1)
        idx = 1;
    if (idx > len + 1)
        idx = len + 1;
    memcpy(tmp + 1, s + 1, idx - 1);
    memcpy(tmp + idx, src + 1, ls);
    memcpy(tmp + idx + ls, s + idx, len - idx + 1);
    n = len + ls;
    if (n > maxlen)
        n = maxlen;
    memcpy(s + 1, tmp + 1, n);
    s[0] = (u8)n;
}

/* Str(v:width, s): the decimal text of a LongInt, right aligned in width characters */
void rtl_str_int(u8 *s, int maxlen, s32 v, int width)
{
    char buf[12];
    int n = 0, pad, total;
    u32 u = v < 0 ? (u32)(-v) : (u32)v;
    do {
        buf[n++] = (char)('0' + (u8)(u % 10UL));
        u /= 10UL;
    } while (u != 0);
    if (v < 0)
        buf[n++] = '-';
    pad = width > n ? width - n : 0;
    total = n + pad;
    if (total > maxlen)
        total = maxlen;
    memset(s + 1, ' ', pad < total ? pad : total);
    {
        int i;
        for (i = 0; pad + i < total; i++)
            s[1 + pad + i] = (u8)buf[n - 1 - i];
    }
    s[0] = (u8)total;
}

/* Val: optional sign, then decimal digits or $hex; code is 0 or the 1-based position of the first bad character */
void rtl_str_val(const u8 *s, void *v, int size, int is_signed, void *code)
{
    int len = s[0], i = 1, neg = 0, base = 10, ndig = 0;
    u32 acc = 0, lim;
    s16 err = 0;
    while (i <= len && s[i] == ' ')
        i++;
    if (i <= len && (s[i] == '-' || s[i] == '+')) {
        neg = s[i] == '-';
        i++;
    }
    if (i <= len && (s[i] == '$' || s[i] == 'x' || s[i] == 'X')) {
        base = 16;
        i++;
    }
    for (; i <= len; i++) {
        int c = s[i], d;
        if (c >= '0' && c <= '9')
            d = c - '0';
        else if (base == 16 && c >= 'a' && c <= 'f')
            d = c - 'a' + 10;
        else if (base == 16 && c >= 'A' && c <= 'F')
            d = c - 'A' + 10;
        else
            break;
        if (acc > (0xFFFFFFFFUL - d) / base)
            err = (s16)i;
        acc = acc * base + d;
        ndig++;
    }
    if (i <= len)
        err = (s16)i;
    else if (ndig == 0)
        err = (s16)(len + 1);
    if (err == 0) {
        if (size == 4)
            lim = is_signed ? (neg ? 0x80000000UL : 0x7FFFFFFFUL) : (neg ? 0UL : 0xFFFFFFFFUL);
        else
            lim = is_signed ? (neg ? (1UL << (size * 8 - 1)) : (1UL << (size * 8 - 1)) - 1UL) : (neg ? 0UL : (1UL << (size * 8)) - 1UL);
        if (acc > lim)
            err = (s16)i;
    }
    if (err == 0) {
        s32 r = neg ? -(s32)acc : (s32)acc;
        if (size == 1) {
            u8 b = (u8)r;
            memcpy(v, &b, 1);
        } else if (size == 2) {
            u16 w = (u16)r;
            memcpy(v, &w, 2);
        } else {
            memcpy(v, &r, 4);
        }
    }
    memcpy(code, &err, 2);
}

u8 rtl_upcase(u8 c)
{
    return (c >= 'a' && c <= 'z') ? (u8)(c - 32) : c;
}

u8 rtl_lowercase(u8 c)
{
    return (c >= 'A' && c <= 'Z') ? (u8)(c + 32) : c;
}

/* ParamStr: the CoCo has no command line */
u8 *rtl_paramstr(u8 *dst, int n)
{
    if (n == 0) {
        memcpy(dst + 1, "POOL.EXE", 8);
        dst[0] = 8;
    } else {
        dst[0] = 0;
    }
    return dst;
}

u16 rtl_ParamCount(void)
{
    return 0;
}

void rtl_set_clear(u8 *s, int n) { memset(s, 0, n); }
void rtl_set_add(u8 *s, int v) { s[(v >> 3) & 31] |= (u8)(1u << (v & 7)); }
void rtl_set_range(u8 *s, int lo, int hi) { int i; for (i = lo; i <= hi; i++) rtl_set_add(s, i); }
int rtl_set_in_at(const u8 *s, int first, int n, int v)
{
    int b = (v >> 3) - first;
    return v >= 0 && b >= 0 && b < n && ((s[b] >> (v & 7)) & 1);
}
int rtl_set_in(const u8 *s, int v) { return v >= 0 && v < 256 && ((s[v >> 3] >> (v & 7)) & 1); }
u8 *rtl_set_union(u8 *d, const u8 *a, const u8 *b, int n) { int i; for (i = 0; i < n; i++) d[i] = a[i] | b[i]; return d; }
u8 *rtl_set_diff(u8 *d, const u8 *a, const u8 *b, int n) { int i; for (i = 0; i < n; i++) d[i] = a[i] & (u8)~b[i]; return d; }
u8 *rtl_set_inter(u8 *d, const u8 *a, const u8 *b, int n) { int i; for (i = 0; i < n; i++) d[i] = a[i] & b[i]; return d; }
int rtl_set_eq(const u8 *a, const u8 *b, int n) { return memcmp(a, b, n) == 0; }
int rtl_set_le(const u8 *a, const u8 *b, int n) { int i; for (i = 0; i < n; i++) if (a[i] & ~b[i]) return 0; return 1; }
int rtl_set_ge(const u8 *a, const u8 *b, int n) { return rtl_set_le(b, a, n); }
