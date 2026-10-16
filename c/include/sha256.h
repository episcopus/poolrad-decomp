/* sha256.h: SHA-256 (public domain algorithm), for the digests the replay compares with the oracle's. */
#ifndef POOL_SHA256_H
#define POOL_SHA256_H

#include "pool.h"

typedef struct Sha256 {
  u32 state[8];
  u32 count_lo, count_hi;
  u8 buf[64];
  u32 buflen;
} Sha256;

void sha256_init(Sha256 *c);
void sha256_update(Sha256 *c, const void *data, size_t len);
void sha256_final(Sha256 *c, u8 out[32]);
void sha256_hex(const u8 digest[32], char out[65]);

#endif
