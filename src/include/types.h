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
typedef unsigned int u32;
typedef signed int s32;

#define POOL_STATIC_ASSERT(cond, msg) typedef u8 pool_static_assert_##msg[(cond) ? 1 : -1]

#endif /* POOLRAD_TYPES_H */
