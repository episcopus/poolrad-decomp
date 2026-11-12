/* snrender.c: render a Tandy chip (SN76489) or PC speaker log to a 44.1 kHz mono WAV (README.md).
 *
 *   snrender T|S SECONDS OUT.wav [GAIN] < log      (GAIN: the sample value of a full-scale channel, 8000)
 *
 * The log is text, one event a line, times in seconds:
 *   T: "t byte"            a byte written to port C0h
 *   S: "t divisor on"      PIT channel 2's divisor and the speaker gate (port 61h bits 0 and 1 both set)
 *
 * The chip is the Tandy 1000's as the Eye of the Beholder study models it (eob-decomp ports/dos/sound/render.cpp):
 * 3.579545 MHz, tone counters stepped at clock / 16, a period of 0 counted as 1024, a 15-bit noise register with
 * taps on bits 0 and 4, reset by every write of the noise register, 2 dB a volume step, a 12 kHz output filter
 * and a 20 Hz high-pass. The speaker is a square wave at 1,193,182 / divisor while the gate is on, through the
 * same filters. Every Tandy clip is rendered at the same scale, so the levels of two clips compare as the chip
 * plays them.
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define OUT_RATE 44100
#define CLOCK 3579545.0
#define PIT 1193182.0

typedef struct { double t; int a, b; } Ev;

static Ev *ev;
static size_t nev, cap;

static void put16(FILE *f, int v) { fputc(v & 255, f); fputc((v >> 8) & 255, f); }
static void put32(FILE *f, long v) { put16(f, v & 0xFFFF); put16(f, (v >> 16) & 0xFFFF); }

static double gain = 8000.0;

static void wav(const char *path, const float *x, size_t n)
{
    FILE *f = fopen(path, "wb");
    if (!f) { perror(path); exit(1); }
    fwrite("RIFF", 1, 4, f); put32(f, 36 + n * 2); fwrite("WAVEfmt ", 1, 8, f);
    put32(f, 16); put16(f, 1); put16(f, 1); put32(f, OUT_RATE); put32(f, OUT_RATE * 2); put16(f, 2); put16(f, 16);
    fwrite("data", 1, 4, f); put32(f, n * 2);
    for (size_t i = 0; i < n; i++) {
        double v = x[i] * gain;
        if (v > 32767) v = 32767;
        if (v < -32768) v = -32768;
        put16(f, (int)lrint(v));
    }
    fclose(f);
}

/* the chip */
static int period[3] = {0x400, 0x400, 0x400}, count[4] = {1, 1, 1, 1}, out[4] = {1, 1, 1, 1};
static int vol[4] = {15, 15, 15, 15}, noise = 0, latch = 0;
static unsigned lfsr = 0x4000;
static double amp[16];

static void sn_write(int b)
{
    int ch;
    if (b & 0x80) latch = (b >> 4) & 7;
    ch = latch >> 1;
    if (latch & 1) vol[ch] = b & 15;
    else if (ch < 3) {
        if (b & 0x80) period[ch] = (period[ch] & 0x3F0) | (b & 15);
        else period[ch] = (period[ch] & 15) | ((b & 0x3F) << 4);
    } else { noise = b & 7; lfsr = 0x4000; }
}

static void shift(void)
{
    unsigned bit = (noise & 4) ? ((lfsr ^ (lfsr >> 4)) & 1) : (lfsr & 1);
    lfsr = (lfsr >> 1) | (bit << 14);
}

static double sn_step(void)
{
    int t2_rise = 0, c, r;
    double s = 0;
    for (c = 0; c < 3; c++)
        if (--count[c] <= 0) {
            count[c] = period[c] ? period[c] : 0x400;
            out[c] = -out[c];
            if (c == 2 && out[c] > 0) t2_rise = 1;
        }
    r = noise & 3;
    if (r == 3) { if (t2_rise) shift(); }
    else if (--count[3] <= 0) {
        count[3] = 0x10 << r;
        out[3] = -out[3];
        if (out[3] > 0) shift();
    }
    for (c = 0; c < 3; c++) s += (period[c] <= 1 ? 1 : out[c]) * amp[vol[c]];
    s += ((lfsr & 1) ? 1 : -1) * amp[vol[3]];
    return s;
}

int main(int argc, char **argv)
{
    char line[256];
    double len, lp = 0, hpx = 0, hpy = 0, lp_a, hp_r, pos = 0, rate;
    size_t m, i, k = 0;
    float *res;
    int speaker, v;
    if (argc != 4 && argc != 5) { fprintf(stderr, "usage: snrender T|S SECONDS OUT.wav [GAIN] < log\n"); return 2; }
    if (argc == 5) gain = atof(argv[4]);
    speaker = argv[1][0] == 'S';
    len = atof(argv[2]);
    for (v = 0; v < 15; v++) amp[v] = pow(10.0, -2.0 * v / 20.0);
    amp[15] = 0;
    while (fgets(line, sizeof line, stdin)) {
        Ev e = {0, 0, 0};
        if (sscanf(line, "%lf %d %d", &e.t, &e.a, &e.b) < 2) continue;
        if (nev == cap) { cap = cap ? cap * 2 : 4096; ev = realloc(ev, cap * sizeof *ev); }
        ev[nev++] = e;
    }
    m = (size_t)(len * OUT_RATE);
    res = calloc(m ? m : 1, sizeof *res);
    lp_a = 1.0 - exp(-2 * M_PI * 12000.0 / OUT_RATE);
    hp_r = exp(-2 * M_PI * 20.0 / OUT_RATE);
    rate = speaker ? PIT : CLOCK / 16.0;
    {
        int div = 0, on = 0, sout = 1;
        double phase = 0;
        for (i = 0; i < m; i++) {
            double end = (i + 1) * rate / OUT_RATE, acc = 0, x, y;
            int n = 0;
            while (pos < end) {
                double t = pos / rate;
                while (k < nev && ev[k].t <= t) {
                    if (speaker) { div = ev[k].a; on = ev[k].b; }
                    else sn_write(ev[k].a);
                    k++;
                }
                if (speaker) {
                    /* PIT mode 3: a square wave, half the divisor high, half low; 0 counts as 65536 */
                    double d = div ? div : 65536;
                    phase += 1;
                    if (phase >= d / 2) { phase -= d / 2; sout = -sout; }
                    acc += on ? sout * 0.5 : 0;
                } else acc += sn_step();
                n++;
                pos += 1;
            }
            x = n ? acc / n : 0;
            lp += lp_a * (x - lp);
            y = lp - hpx + hp_r * hpy;
            hpx = lp;
            hpy = y;
            res[i] = (float)y;
        }
    }
    wav(argv[3], res, m);
    return 0;
}
