/* sha256.c: SHA-256 (public domain algorithm). */
#include "sha256.h"

static const u32 K[64] = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

#define ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

static void block(Sha256 *c, const u8 *p)
{
  u32 w[64], a, b, cc, d, e, f, g, h, t1, t2;
  int i;
  for (i = 0; i < 16; i++) {
    w[i] = ((u32)p[4 * i] << 24) | ((u32)p[4 * i + 1] << 16) | ((u32)p[4 * i + 2] << 8) | p[4 * i + 3];
  }
  for (i = 16; i < 64; i++) {
    u32 s0 = ROR(w[i - 15], 7) ^ ROR(w[i - 15], 18) ^ (w[i - 15] >> 3);
    u32 s1 = ROR(w[i - 2], 17) ^ ROR(w[i - 2], 19) ^ (w[i - 2] >> 10);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }
  a = c->state[0]; b = c->state[1]; cc = c->state[2]; d = c->state[3];
  e = c->state[4]; f = c->state[5]; g = c->state[6]; h = c->state[7];
  for (i = 0; i < 64; i++) {
    t1 = h + (ROR(e, 6) ^ ROR(e, 11) ^ ROR(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i];
    t2 = (ROR(a, 2) ^ ROR(a, 13) ^ ROR(a, 22)) + ((a & b) ^ (a & cc) ^ (b & cc));
    h = g; g = f; f = e; e = d + t1; d = cc; cc = b; b = a; a = t1 + t2;
  }
  c->state[0] += a; c->state[1] += b; c->state[2] += cc; c->state[3] += d;
  c->state[4] += e; c->state[5] += f; c->state[6] += g; c->state[7] += h;
}

void sha256_init(Sha256 *c)
{
  static const u32 iv[8] = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  memcpy(c->state, iv, sizeof iv);
  c->count_lo = c->count_hi = c->buflen = 0;
}

void sha256_update(Sha256 *c, const void *data, size_t len)
{
  const u8 *p = (const u8 *)data;
  u32 old = c->count_lo;
  c->count_lo += (u32)len;
  if (c->count_lo < old) c->count_hi++;
  c->count_hi += (u32)((uint64_t)len >> 32);
  while (len > 0) {
    size_t n = 64 - c->buflen;
    if (n > len) n = len;
    memcpy(c->buf + c->buflen, p, n);
    c->buflen += (u32)n;
    p += n;
    len -= n;
    if (c->buflen == 64) {
      block(c, c->buf);
      c->buflen = 0;
    }
  }
}

void sha256_final(Sha256 *c, u8 out[32])
{
  u32 lo = c->count_lo, hi = c->count_hi;
  u8 pad[72];
  size_t padlen = (c->buflen < 56) ? 56 - c->buflen : 120 - c->buflen;
  {
    uint64_t bits = ((((uint64_t)hi) << 32) | lo) * 8u;
    int i;
    memset(pad, 0, sizeof pad);
    pad[0] = 0x80;
    for (i = 0; i < 8; i++) {
      pad[padlen + i] = (u8)(bits >> (56 - 8 * i));
    }
    sha256_update(c, pad, padlen + 8);
  }
  {
    int i;
    for (i = 0; i < 8; i++) {
      out[4 * i] = (u8)(c->state[i] >> 24);
      out[4 * i + 1] = (u8)(c->state[i] >> 16);
      out[4 * i + 2] = (u8)(c->state[i] >> 8);
      out[4 * i + 3] = (u8)c->state[i];
    }
  }
}

void sha256_hex(const u8 d[32], char out[65])
{
  static const char hex[] = "0123456789abcdef";
  int i;
  for (i = 0; i < 32; i++) {
    out[2 * i] = hex[d[i] >> 4];
    out[2 * i + 1] = hex[d[i] & 15];
  }
  out[64] = 0;
}
