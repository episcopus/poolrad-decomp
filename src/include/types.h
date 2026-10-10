/* types.h: the project's width types (SPEC 7.2).
 *
 * Engine code (src/game, src/rtl) uses only these for game data, never bare
 * int/long. No floating point, no 64-bit integers.
 */
#ifndef POOLRAD_TYPES_H
#define POOLRAD_TYPES_H

typedef unsigned char u8;
typedef signed char s8;
typedef unsigned short u16;
typedef signed short s16;

/* 32-bit on a 16-bit int (Open Watcom, CMOC: long is 32) and on LP64 hosts
 * (int is 32; long would be 64). The lint skips this file; the asserts below
 * are what fail a wrong choice. */
#if defined(__LP64__) || defined(_WIN64)
typedef unsigned int u32;
typedef signed int s32;
#else
typedef unsigned long u32;
typedef signed long s32;
#endif

#define POOL_STATIC_ASSERT(cond, msg) typedef u8 pool_static_assert_##msg[(cond) ? 1 : -1]

POOL_STATIC_ASSERT(sizeof(u8) == 1, u8_width);
POOL_STATIC_ASSERT(sizeof(s8) == 1, s8_width);
POOL_STATIC_ASSERT(sizeof(u16) == 2, u16_width);
POOL_STATIC_ASSERT(sizeof(s16) == 2, s16_width);
POOL_STATIC_ASSERT(sizeof(u32) == 4, u32_width);
POOL_STATIC_ASSERT(sizeof(s32) == 4, s32_width);

#endif /* POOLRAD_TYPES_H */
