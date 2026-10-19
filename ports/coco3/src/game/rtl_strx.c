/* rtl_strx.c: the string routines that are seldom called (Insert, Str of integers, Val), in the runtime bank: it keeps the core small.
 * No variables here (the bank holds none). Literal arguments are copied by the caller (tools/mkgame.py copy_cross_literals). */
#include "pool.h"

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

/* Str(v:width, s): the decimal text of a LongInt, right aligned in width characters. The division by ten is done on the four bytes
 * with 16 bit arithmetic: CMOC's unsigned long modulo returns 0 for a dividend below 10 (found in the clock of the location line:
 * "11:08" came out as "11:" and two junk characters), and memset with a count of 0 is not trusted either. */
void rtl_str_int(u8 *s, int maxlen, s32 v, int width)
{
    char buf[12];
    u8 b[4], nz, j;
    u16 cur;
    int n = 0, pad, total, i;
    u32 u = v < 0 ? (u32)(-v) : (u32)v;
    b[0] = (u8)(u >> 24);
    b[1] = (u8)(u >> 16);
    b[2] = (u8)(u >> 8);
    b[3] = (u8)u;
    do {
        cur = 0;
        nz = 0;
        for (j = 0; j < 4; j++) {
            cur = (u16)((cur << 8) | b[j]);
            b[j] = (u8)(cur / 10u);
            cur = (u16)(cur % 10u);
            nz |= b[j];
        }
        buf[n++] = (char)('0' + (u8)cur);
    } while (nz != 0);
    if (v < 0)
        buf[n++] = '-';
    pad = width > n ? width - n : 0;
    total = n + pad;
    if (total > maxlen)
        total = maxlen;
    for (i = 0; i < pad && i < total; i++)
        s[1 + i] = ' ';
    for (i = 0; pad + i < total; i++)
        s[1 + pad + i] = (u8)buf[n - 1 - i];
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

