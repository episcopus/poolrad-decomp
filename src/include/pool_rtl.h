/* pool_rtl.h: Turbo Pascal runtime semantics in C (SPEC 7.4).
 *
 * P3 spike: Move, FillChar and Random only. Strings, sets, files and the heap
 * arrive unit by unit in P4.
 */
#ifndef POOLRAD_RTL_H
#define POOLRAD_RTL_H

#include "types.h"
#include "pool_memory.h"
#include "gen/dseg.h"

/* System_Move core: overlapping-safe copy of count bytes (rep movsb semantics). */
void rtl_move(farptr src, farptr dst, u16 count);

/* System_FillChar core: store value into count bytes (rep stosb semantics). */
void rtl_fillchar(farptr dst, u16 count, u8 value);

/* TP 6.0 generator step: RandSeed := RandSeed * 08088405h + 1 (mod 2^32). */
void rtl_random_step(void);

/* Random(range): step, then hi16(RandSeed) mod range; 0 when range is 0. */
u16 rtl_random_range(u16 range);

/* Randomize from a DOS GetTime read (INT 21h AH=2Ch): seed := DX:CX with
 * DX = sec:hund (high word) and CX = hour:min (low word). */
void rtl_randomize(u8 hour, u8 minute, u8 sec, u8 hund);

#endif /* POOLRAD_RTL_H */
