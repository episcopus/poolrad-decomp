/* lz4bench.c: the same measurement as zxbench.c for an LZ4 block (the fastest decoders of the family: byte aligned tokens, no bit reading).
 * The sample is made by tools/zxprobe.py makelz4 (lz4 -9 of the host, the frame stripped to its block). r0 sum of the output, r1 its length, r3 the block's length. */
#include "mailbox.h"
#include "../build/run/zx/zxdata.h"

typedef unsigned char u8;
typedef unsigned short u16;

unsigned zx_len, zx_last;
unsigned char zx_tok;
const u8 *zx_src;
const u8 *zx_end;
u8 *zx_dst;

void lz4_unpack(void)
{
    asm {
        pshs    u,y
        ldx     _zx_src
        ldu     _zx_dst
l4tok   lda     ,x+
        sta     _zx_tok
        lsra
        lsra
        lsra
        lsra
        clr     _zx_len
        sta     _zx_len+1
        cmpa    #15
        lbne    l4lit
l4e1    ldb     ,x+
        pshs    b
        ldd     _zx_len
        addb    ,s+
        adca    #0
        std     _zx_len
        ldb     -1,x
        incb
        lbeq    l4e1
l4lit   ldy     _zx_len
        lbeq    l4nolit
l4cl    ldb     ,x+
        stb     ,u+
        leay    -1,y
        bne     l4cl
l4nolit cmpx    _zx_end
        lbhs    l4end
        ldb     ,x+
        lda     ,x+
        std     _zx_last
        lda     _zx_tok
        anda    #15
        clr     _zx_len
        sta     _zx_len+1
        cmpa    #15
        lbne    l4m
l4e2    ldb     ,x+
        pshs    b
        ldd     _zx_len
        addb    ,s+
        adca    #0
        std     _zx_len
        ldb     -1,x
        incb
        lbeq    l4e2
l4m     ldd     _zx_len
        addd    #4
        tfr     d,y
        pshs    x
        tfr     u,d
        subd    _zx_last
        tfr     d,x
l4cm    ldb     ,x+
        stb     ,u+
        leay    -1,y
        bne     l4cm
        puls    x
        lbra    l4tok
l4end   puls    u,y
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
    *(volatile u8 *)0xFFA4 = 0x18;
    *(volatile u8 *)0xFFA5 = 0x19;
    zx_src = zx_comp;
    zx_end = zx_comp + ZX_COMP;
    zx_dst = (u8 *)0x8000;
    lz4_unpack();
    MB_RESULT(0) = sumblk((u8 *)0x8000, ZX_RAW);
    MB_RESULT(1) = ZX_RAW;
    MB_RESULT(3) = ZX_COMP;
    MB_CHECKPOINT = 2;
    for (i = 0; i < 50; i++) {
        zx_src = zx_comp;
        zx_dst = (u8 *)0x8000;
        lz4_unpack();
    }
    MB_CHECKPOINT = 3;
    mb_finish();
    return 0;
}
