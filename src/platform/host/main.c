/* main.c: P3 spike host program (SPEC 11).
 *
 * Proves the SDL3 platform builds and runs: draws sixteen EGA colour bars
 * through platform_present_frame, exercises the time hooks, and exits.
 * Playing the game is P5; this binary only grows into it.
 */
#include <stdio.h>

#include "types.h"
#include "platform.h"
#include "pool_rtl.h"

static const u8 ega_palette[16][3] = {
    {0x00, 0x00, 0x00}, {0x00, 0x00, 0xAA}, {0x00, 0xAA, 0x00}, {0x00, 0xAA, 0xAA},
    {0xAA, 0x00, 0x00}, {0xAA, 0x00, 0xAA}, {0xAA, 0x55, 0x00}, {0xAA, 0xAA, 0xAA},
    {0x55, 0x55, 0x55}, {0x55, 0x55, 0xFF}, {0x55, 0xFF, 0x55}, {0x55, 0xFF, 0xFF},
    {0xFF, 0x55, 0x55}, {0xFF, 0x55, 0xFF}, {0xFF, 0xFF, 0x55}, {0xFF, 0xFF, 0xFF},
};

static u8 fb[320u * 200u];

int main(int argc, char **argv)
{
    u32 x, y;
    u32 t0, t1;
    u8 hour, min, sec, hund;
    (void)argc;
    (void)argv;
    pool_mem_init();
    for (y = 0u; y < 200u; y++) {
        for (x = 0u; x < 320u; x++) {
            fb[y * 320u + x] = (u8)((x * 16u) / 320u);
        }
    }
    platform_present_frame(fb, ega_palette);
    t0 = platform_ticks();
    platform_delay_ms(200);
    t1 = platform_tick_wait(t0);
    platform_get_time(&hour, &min, &sec, &hund);
    printf("poolrad P3 spike: ticks %u -> %u, time %02u:%02u:%02u.%02u\n",
        t0, t1, hour, min, sec, hund);
    if (platform_key_peek() != 0u) {
        printf("key: %04x\n", platform_key_peek());
    }
    return 0;
}
