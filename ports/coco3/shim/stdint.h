/* stdint.h shim for CMOC (no <stdint.h> in its library). 16-bit int, 32-bit long. */
#ifndef SHIM_STDINT_H
#define SHIM_STDINT_H
typedef unsigned char uint8_t;
typedef signed char int8_t;
typedef unsigned int uint16_t;
typedef int int16_t;
typedef unsigned long uint32_t;
typedef long int32_t;
#endif
