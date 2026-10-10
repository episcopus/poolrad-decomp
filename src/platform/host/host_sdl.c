/* host_sdl.c: SDL3 implementation of platform.h (SPEC 7.5, 11).
 *
 * P3: every hook and wait, plus the video present call. Sound is logged by
 * doing nothing audible (synthesis is P5). The timer handler runs on the
 * thread that calls into the platform, at the PIT period rounded to the
 * nearest millisecond. The BIOS tick count is kept from the wall clock, so
 * a C handler never chains (platform.h).
 */
#include <stdio.h>

#include <SDL3/SDL.h>

#include "types.h"
#include "platform.h"

#define FB_W 320u
#define FB_H 200u

static SDL_Window *win;
static SDL_Renderer *ren;
static SDL_Texture *tex;
static u32 present_count;

/* Input: SDL events become BIOS key codes (scan in the high byte, ASCII in
 * the low byte) and are queued. Wait blocks on the queue. */
#define KEYQ 64u
static u16 keyq[KEYQ];
static u32 keyq_head;
static u32 keyq_tail;

static u32 tick_base_ms;
static u16 timer_divisor;
static u32 timer_interval_ms;
static u32 timer_next_ms;
static u8 timer_in_handler;
static platform_tick_fn timer_handler;

/* SDL scancode (USB HID usage) to BIOS scan code. 0 means "no BIOS key".
 * Indexed by SDL_Scancode. Letters and the top row are the XT make codes;
 * arrows, home, end and the function keys are the INT 16h values. */
static const u8 bios_scan[232] = {
    [4] = 0x1E, [5] = 0x30, [6] = 0x2E, [7] = 0x20, [8] = 0x12, [9] = 0x21,
    [10] = 0x22, [11] = 0x23, [12] = 0x17, [13] = 0x24, [14] = 0x25, [15] = 0x26,
    [16] = 0x32, [17] = 0x31, [18] = 0x18, [19] = 0x19, [20] = 0x10, [21] = 0x13,
    [22] = 0x1F, [23] = 0x14, [24] = 0x16, [25] = 0x2F, [26] = 0x11, [27] = 0x2D,
    [28] = 0x15, [29] = 0x2C,
    [30] = 0x02, [31] = 0x03, [32] = 0x04, [33] = 0x05, [34] = 0x06,
    [35] = 0x07, [36] = 0x08, [37] = 0x09, [38] = 0x0A, [39] = 0x0B,
    [40] = 0x1C, [41] = 0x01, [42] = 0x0E, [43] = 0x0F, [44] = 0x39,
    [45] = 0x0C, [46] = 0x0D, [47] = 0x1A, [48] = 0x1B, [49] = 0x2B,
    [51] = 0x27, [52] = 0x28, [53] = 0x29, [54] = 0x33, [55] = 0x34, [56] = 0x35,
    [57] = 0x3A,
    [58] = 0x3B, [59] = 0x3C, [60] = 0x3D, [61] = 0x3E, [62] = 0x3F,
    [63] = 0x40, [64] = 0x41, [65] = 0x42, [66] = 0x43, [67] = 0x44,
    [68] = 0x85, [69] = 0x86,
    [73] = 0x52, [74] = 0x47, [75] = 0x49, [76] = 0x53, [77] = 0x4F, [78] = 0x51,
    [79] = 0x4D, [80] = 0x4B, [81] = 0x50, [82] = 0x48,
    [83] = 0x45, [85] = 0x37, [86] = 0x4A, [87] = 0x4E, [88] = 0x1C,
    [89] = 0x4F, [90] = 0x50, [91] = 0x51, [92] = 0x4B, [93] = 0x4C,
    [94] = 0x4D, [95] = 0x47, [96] = 0x48, [97] = 0x49, [98] = 0x52, [99] = 0x53,
    [224] = 0x1D, [225] = 0x2A, [226] = 0x38, [228] = 0x1D, [229] = 0x36, [230] = 0x38,
};

/* Nearest millisecond to 1000 * divisor / 1193182, and at least 1.
 * divisor 0 is the BIOS 65536. 5041 (the sound unit) is 4 ms; 65536 is 55 ms. */
u32 host_pit_interval_ms(u16 divisor)
{
    u32 div_value = divisor == 0u ? 65536u : (u32)divisor;
    u32 ms = (div_value * 1000u + (1193182u / 2u)) / 1193182u;
    return ms == 0u ? 1u : ms;
}

/* BIOS key code for one SDL key. 0 drops the key. */
u16 host_bios_key(u16 scancode, u32 keycode)
{
    u8 scan;
    u8 ascii;
    if (scancode >= 232u) {
        return 0u;
    }
    scan = bios_scan[scancode];
    if (scan == 0u) {
        return 0u;
    }
    ascii = keycode < 128u ? (u8)keycode : 0u;
    return (u16)(((u16)scan << 8) | ascii);
}

int host_self_test(void)
{
    if (host_bios_key(41, 27) != 0x011Bu) {
        printf("host self-test: Escape\n");
        return 1;
    }
    if (host_bios_key(4, (u32)'a') != 0x1E61u) {
        printf("host self-test: A\n");
        return 1;
    }
    if (host_bios_key(82, 0x40000052u) != 0x4800u) {
        printf("host self-test: Up\n");
        return 1;
    }
    if (host_pit_interval_ms(0) != 55u || host_pit_interval_ms(5041) != 4u) {
        printf("host self-test: PIT interval\n");
        return 1;
    }
    printf("host self-test ok\n");
    return 0;
}

static u32 timer_cb_interval(void)
{
    return timer_interval_ms == 0u ? 1u : timer_interval_ms;
}

static void timer_pump(void)
{
    u32 now;
    u32 n;
    if (timer_handler == 0 || timer_in_handler) {
        return;
    }
    now = (u32)SDL_GetTicks();
    n = 0u;
    timer_in_handler = 1u;
    while ((s32)(now - timer_next_ms) >= 0 && n < 8u) {
        timer_handler();
        timer_next_ms += timer_cb_interval();
        n++;
    }
    if (n == 8u) {
        timer_next_ms = now + timer_cb_interval();
    }
    timer_in_handler = 0u;
}

static void host_init(void)
{
    if (win != 0) {
        return;
    }
    SDL_Init(SDL_INIT_VIDEO);
    win = SDL_CreateWindow("Pool of Radiance (P3 spike)", 960, 600, 0);
    ren = SDL_CreateRenderer(win, 0);
    tex = SDL_CreateTexture(ren, SDL_PIXELFORMAT_RGB24, SDL_TEXTUREACCESS_STREAMING, FB_W, FB_H);
    tick_base_ms = (u32)SDL_GetTicks();
}

static void enqueue(u16 code)
{
    if (code == 0u) {
        return;
    }
    if (((keyq_tail + 1u) % KEYQ) != keyq_head) {
        keyq[keyq_tail] = code;
        keyq_tail = (keyq_tail + 1u) % KEYQ;
    }
}

static void pump(void)
{
    SDL_Event ev;
    timer_pump();
    while (SDL_PollEvent(&ev)) {
        if (ev.type == SDL_EVENT_QUIT) {
            enqueue(0x011Bu);
        } else if (ev.type == SDL_EVENT_KEY_DOWN && !ev.key.repeat) {
            enqueue(host_bios_key((u16)ev.key.scancode, (u32)ev.key.key));
        }
    }
}

u16 platform_key_peek(void)
{
    host_init();
    pump();
    if (keyq_head == keyq_tail) {
        return 0u;
    }
    return keyq[keyq_head];
}

u16 platform_key_wait(void)
{
    host_init();
    while (keyq_head == keyq_tail) {
        SDL_WaitEventTimeout(0, 10);
        pump();
    }
    {
        u16 code = keyq[keyq_head];
        keyq_head = (keyq_head + 1u) % KEYQ;
        return code;
    }
}

u32 platform_ticks(void)
{
    u32 ms;
    host_init();
    timer_pump();
    ms = (u32)SDL_GetTicks() - tick_base_ms;
    /* 1193182/65536 ticks per second. */
    return (u32)(((unsigned long long)ms * 1193182ull) / 65536000ull);
}

u32 platform_tick_wait(u32 last)
{
    u32 now = platform_ticks();
    while (now == last) {
        SDL_Delay(1);
        now = platform_ticks();
    }
    return now;
}

void platform_delay_ms(u16 ms)
{
    u32 end;
    host_init();
    end = (u32)SDL_GetTicks() + (u32)ms;
    while ((s32)((u32)SDL_GetTicks() - end) < 0) {
        timer_pump();
        SDL_Delay(1);
    }
    timer_pump();
}

void platform_get_time(u8 *hour, u8 *min, u8 *sec, u8 *hund)
{
    u32 ticks = platform_ticks();
    unsigned long long hund_total = ((unsigned long long)ticks * 6553600ull) / 1193182ull;
    *hour = (u8)((hund_total / 360000ull) % 24ull);
    *min = (u8)((hund_total / 6000ull) % 60ull);
    *sec = (u8)((hund_total / 100ull) % 60ull);
    *hund = (u8)(hund_total % 100ull);
}

void platform_get_date(u16 *year, u8 *month, u8 *day, u8 *dow)
{
    /* Fixed reference date while saves do not need the real one (P5). */
    *year = 1991u;
    *month = 6u;
    *day = 11u;
    *dow = 2u;
}

u8 platform_entropy(void)
{
    /* Live stand-in for IN AL,40h: the low byte of a fast free-running counter.
     * A replay returns the recorded byte instead of calling this. */
    return (u8)SDL_GetPerformanceCounter();
}

void platform_timer_set(u16 divisor, platform_tick_fn handler)
{
    host_init();
    platform_timer_reset();
    timer_divisor = divisor;
    timer_handler = handler;
    timer_interval_ms = host_pit_interval_ms(divisor);
    timer_next_ms = (u32)SDL_GetTicks() + timer_interval_ms;
}

void platform_timer_reset(void)
{
    timer_handler = 0;
    timer_divisor = 0u;
    timer_interval_ms = 0u;
}

void platform_speaker_set(u16 divisor, u8 port61_low2)
{
    (void)divisor;
    (void)port61_low2;
}

void platform_speaker_off(void)
{
}

void platform_tandy_write(u8 value)
{
    (void)value;
}

void platform_present_frame(const u8 *fb_320x200, const u8 palette[16][3])
{
    u8 *pixels;
    int pitch;
    u32 x, y;
    host_init();
    timer_pump();
    if (!SDL_LockTexture(tex, 0, (void **)&pixels, &pitch)) {
        return;
    }
    for (y = 0u; y < FB_H; y++) {
        for (x = 0u; x < FB_W; x++) {
            u8 idx = fb_320x200[y * FB_W + x] & 15u;
            pixels[y * (u32)pitch + x * 3u] = palette[idx][0];
            pixels[y * (u32)pitch + x * 3u + 1u] = palette[idx][1];
            pixels[y * (u32)pitch + x * 3u + 2u] = palette[idx][2];
        }
    }
    SDL_UnlockTexture(tex);
    SDL_RenderTexture(ren, tex, 0, 0);
    SDL_RenderPresent(ren);
    present_count++;
}
