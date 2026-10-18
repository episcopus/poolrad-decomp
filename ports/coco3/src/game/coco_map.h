/* coco_map.h: where the game's memory is in the 64 KB map of the CoCo 3 (task 0). Step 8.5c; the numbers are fixed here so
 * that the generated code can name addresses as constants.
 *
 *   $0E00..$1FFF  stack, direct page variables, the mailbox (shared by both tasks)
 *   $2000..       the game core: code and read only data, then bss
 *   NATVARS       the globals the layout keeps native (VM_NAT_SIZE bytes)
 *   HEAPM_BASE    the mapped heap
 *   $8000..$BFFF  the code window (a bank)
 *   $C000, $E000  the two data windows
 */
#ifndef COCO_MAP_H
#define COCO_MAP_H
#include "vmlayout.h"
#define NATVARS 0x5800u
#define HEAPM_BASE (NATVARS + VM_NAT_SIZE)
#define HEAPM_END 0x8000u
#endif
