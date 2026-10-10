/* res00_system.h: the Turbo Pascal System unit interface (res00). */
#ifndef POOLRAD_RES00_SYSTEM_H
#define POOLRAD_RES00_SYSTEM_H

#include "types.h"
#include "pool_memory.h"

void System_Move(farptr src, farptr dst, u16 count);
void System_FillChar(farptr dst, u16 count, u8 value);
u16 System_Random(u16 range);

#endif /* POOLRAD_RES00_SYSTEM_H */
