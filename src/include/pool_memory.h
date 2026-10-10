/* pool_memory.h: the memory model (SPEC 7.3).
 *
 * Turbo Pascal keeps globals in DGROUP and records on a heap reached by far
 * pointers. The C lift mirrors that:
 *
 *   Globals:  one struct mirroring DGROUP byte for byte
 *             (src/include/gen/dseg.h, generated from re/dseg.toml),
 *             accessed as G.field.
 *   Heap/far: farptr handles (segment:offset as u32), dereferenced with
 *             FP(Type, p), which indexes a 1 MB arena.
 *
 * Both builds use the same macros. In the native build pool_mem_base points
 * at the arena. In the hybrid build the oracle maps its conventional RAM with
 * that buffer (Unicorn mem_map_ptr), so FP() addresses the guest. G is the
 * 64 KB DGROUP image inside the buffer at pool_dgroup_linear (0x1C7C0).
 *
 * The arena is flat. The Turbo Pascal suballocator (GetMem/FreeMem, the
 * src/rtl/heap.c SPEC 7.3 names) is not part of this spike: Move, FillChar
 * and Random do not call it.
 */
#ifndef POOLRAD_MEMORY_H
#define POOLRAD_MEMORY_H

#include "types.h"

typedef u32 farptr;

/* Segment:offset packed as (seg << 16) | off. */
#define POOL_FARPTR(seg, off) ((((u32)(seg)) << 16) | ((u32)(off) & 0xFFFFu))
#define POOL_SEG(p) ((u16)(((p) >> 16) & 0xFFFFu))
#define POOL_OFF(p) ((u16)((p) & 0xFFFFu))
/* 20-bit real-mode address. Offset wrap is the caller's job (rep movsb wraps
 * the 16-bit offset and keeps the segment). */
#define POOL_LINEAR(p) ((((u32)(POOL_SEG(p)) * 16u) + (u32)POOL_OFF(p)) & 0xFFFFFu)

#define POOL_MEM_SIZE ((u32)0x100000u)

/* Oracle DS: LOAD_SEG 0x1000 + DGROUP paragraph 0x0C7C (state.py). */
#define POOL_DGROUP_LINEAR ((u32)0x1C7C0u)

extern u8 *pool_mem_base;
extern u32 pool_mem_size;
extern u32 pool_dgroup_linear;

/* Native build: point at the 1 MB arena. Hybrid build: rebind to guest RAM. */
void pool_mem_init(void);
void pool_hybrid_bind(u8 *base, u32 size);
void pool_hybrid_set_dgroup(u32 linear);

#define FP(Type, p) ((Type *)(pool_mem_base + POOL_LINEAR(p)))

#endif /* POOLRAD_MEMORY_H */
