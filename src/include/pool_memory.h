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
 * at the arena. In the hybrid build the oracle harness binds a mirror buffer
 * (tools/oracle/hybrid.py) and syncs the bytes each replaced routine touches;
 * the C code itself is identical. Direct mapping of Unicorn memory is P4 work.
 */
#ifndef POOLRAD_MEMORY_H
#define POOLRAD_MEMORY_H

#include "types.h"

typedef u32 farptr;

/* Segment:offset packed as (seg << 16) | off. */
#define POOL_FARPTR(seg, off) ((((u32)(seg)) << 16) | ((u32)(off) & 0xFFFFu))
#define POOL_SEG(p) ((u16)(((p) >> 16) & 0xFFFFu))
#define POOL_OFF(p) ((u16)((p) & 0xFFFFu))
#define POOL_LINEAR(p) ((u32)(POOL_SEG(p)) * 16u + (u32)POOL_OFF(p))

#define POOL_MEM_SIZE ((u32)0x100000u)

extern u8 *pool_mem_base;
extern u32 pool_mem_size;

/* Native build: point at the 1 MB arena. Hybrid build: rebind per call. */
void pool_mem_init(void);
void pool_hybrid_bind(u8 *base, u32 size);

#define FP(Type, p) ((Type *)(pool_mem_base + POOL_LINEAR(p)))

#endif /* POOLRAD_MEMORY_H */
