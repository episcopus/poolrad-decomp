/* zxbench.c: how fast does a ZX0 decoder run on the 6809? (step 8.9b) The sample is a block of the game compressed by the real compressor (tools in the
 * coco-dev image: zx0), embedded as zxdata.h (made by tools/zxprobe.py). The decoder is written here in assembly from the format (the reference decoder in C is
 * build/run/zx/dzx0.py and agrees with zx0's own dzx0): the output goes into two MMU blocks mapped contiguously at $8000, as a code bank would.
 * It decodes once for the check, then 50 times between checkpoints 2 and 3 (their emulated times are in the .cp file: tools/zxprobe.py reads them).
 * r0 the sum of the output (std ZX_SUM)  r1 the length of the output (std ZX_RAW)  r3 the compressed length */
#include "mailbox.h"
#include "../build/run/zx/zxdata.h"

typedef unsigned char u8;
typedef unsigned short u16;

unsigned zx_len, zx_last;
unsigned char zx_bk;
const u8 *zx_src;
u8 *zx_dst;

void zx_unpack(void)
{
    asm {
        pshs    u,y
        ldx     _zx_src
        ldu     _zx_dst
        ldd     #1
        std     _zx_last
        lda     #$80
zx_lit  jsr     zx_gamma
        ldy     _zx_len
zx_cl   ldb     ,x+
        stb     ,u+
        leay    -1,y
        bne     zx_cl
        asla
        bne     zx_b1
        lda     ,x+
        rola
zx_b1   bcs     zx_new
        jsr     zx_gamma
zx_rep  pshs    x,a
        tfr     u,d
        subd    _zx_last
        tfr     d,x
        ldy     _zx_len
zx_cr   ldb     ,x+
        stb     ,u+
        leay    -1,y
        bne     zx_cr
        puls    x,a
        asla
        bne     zx_b2
        lda     ,x+
        rola
zx_b2   bcc     zx_lit
zx_new  jsr     zx_gammai
        ldb     _zx_len+1
        bne     zx_nz
        ldb     _zx_len
        cmpb    #1
        lbeq    zx_end
zx_nz   pshs    a
        ldd     _zx_len
        aslb
        rola
        aslb
        rola
        aslb
        rola
        aslb
        rola
        aslb
        rola
        aslb
        rola
        aslb
        rola
        std     _zx_last
        lda     ,x+
        sta     _zx_bk
        lsra
        sta     _zx_len
        ldd     _zx_last
        subb    _zx_len
        sbca    #0
        std     _zx_last
        puls    a
        ldb     #1
        stb     _zx_len+1
        clr     _zx_len
        ldb     _zx_bk
        lsrb
        jsr     zx_gcont
        inc     _zx_len+1
        bne     zx_rep
        inc     _zx_len
        bra     zx_rep
zx_gamma
        ldb     #1
        stb     _zx_len+1
        clr     _zx_len
zx_g1   asla
        bne     zx_g2
        lda     ,x+
        rola
zx_g2   bcs     zx_gd
        asla
        bne     zx_g3
        lda     ,x+
        rola
zx_g3   rol     _zx_len+1
        rol     _zx_len
        bra     zx_g1
zx_gd   rts
zx_gcont
        bcs     zx_gd
        asla
        bne     zx_g4
        lda     ,x+
        rola
zx_g4   rol     _zx_len+1
        rol     _zx_len
        bra     zx_g1
zx_gammai
        ldb     #1
        stb     _zx_len+1
        clr     _zx_len
zx_i1   asla
        bne     zx_i2
        lda     ,x+
        rola
zx_i2   bcs     zx_gd
        asla
        bne     zx_i3
        lda     ,x+
        rola
zx_i3   bcs     zx_i4
        orcc    #1
        bra     zx_i5
zx_i4   andcc   #$FE
zx_i5   rol     _zx_len+1
        rol     _zx_len
        bra     zx_i1
zx_end
        puls    u,y
        }
}

static u16 sumblk(const u8 *p, u16 n)
{
    u16 s = 0;
    while (n--)
        s += *p++;
    return s;
}

int main(void)
{
    u8 i;
    *(volatile u8 *)0xFFA4 = 0x18;          /* blocks $18, $19 at $8000..$BFFF */
    *(volatile u8 *)0xFFA5 = 0x19;
    zx_src = zx_comp; zx_dst = (u8 *)0x8000; zx_unpack();
    MB_RESULT(0) = sumblk((u8 *)0x8000, ZX_RAW);
    MB_RESULT(1) = ZX_RAW;
    MB_RESULT(3) = ZX_COMP;
    MB_CHECKPOINT = 2;
    for (i = 0; i < 50; i++) {
        zx_src = zx_comp;
        zx_dst = (u8 *)0x8000;
        zx_unpack();
    }
    MB_CHECKPOINT = 3;
    mb_finish();
    return 0;
}
