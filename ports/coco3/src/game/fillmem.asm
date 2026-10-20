* fillmem.asm: a fast memset for the game core (step 8.9), in place of the CMOC library's byte loop (about 14 cycles a byte; FillChar, the pseudo stack's
* clears and the translated game's array clears are the callers). The same fill as the engine's k_fill (kernels.asm): from the top down, the odd
* bytes first, then 24 bytes by four PSHUs of D,X,Y, then four at a time. PSHU leaves the system stack, and so the interrupts, alone.
* void *fill_mem(void *s, int c, size_t n), memset by another name: the library member that defines memset is linked anyway (CMOC itself needs it). FC_Y = the start, FC_D = start + 24, FC_X = start + 4 (scratch of the direct page).
        INCLUDE mailbox.inc

        SECTION code
        EXPORT  _fill_mem

_fill_mem
        pshs    u,y
        ldx     6,s
        stx     <FC_Y
        ldd     10,s
        leau    d,x                     U = the end
        ldd     <FC_Y
        addd    #4
        std     <FC_X
        addd    #20
        std     <FC_D
        ldb     11,s
        andb    #3
        beq     @quad
        lda     9,s
@rem    sta     ,-u
        decb
        bne     @rem
@quad   lda     9,s
        tfr     a,b
        tfr     d,x
        tfr     d,y
@l24    cmpu    <FC_D
        blo     @l4
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        bra     @l24
@l4     cmpu    <FC_X
        blo     @out
        pshu    d,x
        bra     @l4
@out    ldd     6,s
        puls    u,y,pc
        ENDSECTION
