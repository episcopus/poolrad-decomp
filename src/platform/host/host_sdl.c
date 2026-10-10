/* host_sdl.c: SDL3 implementation of platform.h (SPEC 7.5, 11).
 *
 * P3 spike: every hook and wait plus the video present call. Sound is logged,
 * not synthesised (audible synthesis is P5). The timer handler runs on an SDL
 * timer at the programmed rate; the BIOS tick count is kept here, so a C
 * handler never chains (platform.h).
 */
#include <SDL3/SDL.h>

#include "types.h"
#include "platform.h"

#define FB_W 320u
#define FB_H 200u

static SDL_Window *win;
static SDL_Renderer *ren;
static SDL_Texture *tex;
static u32 present_count;

/* Input: SDL events are translated to BIOS key codes (scan << 8 | ascii) and
 * queued; wait blocks on the queue. */
#define KEYQ 64u
static u16 keyq[KEYQ];
static u32 keyq_head;
static u32 keyq_tail;

static u32 tick_base_ms;
static u32 tick_count;
static u16 timer_divisor;
static platform_tick_fn timer_handler;
static SDL_TimerID timer_id = 0;

static u32 timer_cb(void *ud, SDL_TimerID id, u32 interval)
{
    (void)ud;
    (void)id;
    (void)interval;
    if (timer_handler != 0) {
        timer_handler();
    }
    return interval;
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

static void pump(void)
{
    SDL_Event ev;
    while (SDL_PollEvent(&ev)) {
        if (ev.type == SDL_EVENT_QUIT) {
            if (((keyq_tail + 1u) % KEYQ) != keyq_head) {
                keyq[keyq_tail] = 0x011Bu;
                keyq_tail = (keyq_tail + 1u) % KEYQ;
            }
        } else if (ev.type == SDL_EVENT_KEY_DOWN && !ev.key.repeat) {
            u16 code = (u16)(((u32)ev.key.scancode << 8) | (ev.key.key & 0xFFu));
            if (((keyq_tail + 1u) % KEYQ) != keyq_head) {
                keyq[keyq_tail] = code;
                keyq_tail = (keyq_tail + 1u) % KEYQ;
            }
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
    host_init();
    {
        u32 ms = (u32)SDL_GetTicks() - tick_base_ms;
        /* 18.2065 ticks per second. */
        return tick_count + (ms * 199u) / 10925u;
    }
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
    SDL_Delay((u32)ms);
}

void platform_get_time(u8 *hour, u8 *min, u8 *sec, u8 *hund)
{
    u32 ticks = platform_ticks();
    u32 hund_total = (ticks * 100u) / 18u;
    *hour = (u8)((hund_total / 360000u) % 24u);
    *min = (u8)((hund_total / 6000u) % 60u);
    *sec = (u8)((hund_total / 100u) % 60u);
    *hund = (u8)(hund_total % 100u);
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
    return (u8)(platform_ticks() & 0xFFu);
}

void platform_timer_set(u16 divisor, platform_tick_fn handler)
{
    u32 div_value = divisor == 0u ? 65536u : (u32)divisor;
    u32 interval_ms;
    host_init();
    platform_timer_reset();
    timer_divisor = divisor;
    timer_handler = handler;
    /* 1193182 / divisor periods per second. */
    interval_ms = 1193182u / div_value;
    if (interval_ms == 0u) {
        interval_ms = 1u;
    }
    timer_id = SDL_AddTimer(interval_ms, timer_cb, 0);
}

void platform_timer_reset(void)
{
    if (timer_id != 0) {
        SDL_RemoveTimer(timer_id);
        timer_id = 0;
    }
    timer_handler = 0;
    timer_divisor = 0u;
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
