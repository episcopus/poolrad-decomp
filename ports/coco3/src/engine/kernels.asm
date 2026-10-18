* kernels.asm: the engine's inner loops (step 8.3e). CMOC passes arguments on the stack, first argument nearest the
* return address, a byte as a word (its low byte at the higher address). Each routine saves U and Y, which CMOC keeps.
* No interrupt is masked: the frame ISR uses no register it does not save.
        INCLUDE mailbox.inc

        SECTION code
        EXPORT  _k_copy
        EXPORT  _k_fill
        EXPORT  _k_mcopy
        EXPORT  _k_glyph8
        EXPORT  _k_sum
        EXPORT  _k_sum

* void k_copy(u8 *dst, const u8 *src, u8 n): n bytes, eight at a time
_k_copy
        pshs    u,y
        ldx     6,s
        ldy     8,s
        ldb     11,s
        lsrb
        lsrb
        lsrb
        beq     @tail
        stb     <FC_D                   (LDD below uses B)
@l8     ldd     ,y++
        std     ,x++
        ldd     ,y++
        std     ,x++
        ldd     ,y++
        std     ,x++
        ldd     ,y++
        std     ,x++
        dec     <FC_D
        bne     @l8
@tail   ldb     11,s
        andb    #7
        beq     @out
@l1     lda     ,y+
        sta     ,x+
        decb
        bne     @l1
@out    puls    u,y,pc

* void k_fill(u8 *dst, u8 value, u16 n): four bytes a PSHU, from the top down
_k_fill
        pshs    u,y
        ldx     6,s
        ldd     10,s
        leau    d,x                     U = the end
        ldb     11,s
        andb    #3
        beq     @quad
        lda     9,s
@rem    sta     ,-u
        decb
        bne     @rem
@quad   ldd     10,s
        lsra
        rorb
        lsra
        rorb
        tfr     d,y                     n / 4 pushes
        cmpy    #0
        beq     @out
        lda     9,s
        tfr     a,b
        tfr     d,x
@l4     pshu    a,b,x
        leay    -1,y
        bne     @l4
@out    puls    u,y,pc

* void k_mcopy(u8 *dst, const u8 *mask, const u8 *src, u8 n): dst = (dst & mask) | src
_k_mcopy
        pshs    u,y
        ldx     6,s
        ldy     8,s
        ldu     10,s
        ldb     13,s
@l      lda     ,x
        anda    ,y+
        ora     ,u+
        sta     ,x+
        decb
        bne     @l
        puls    u,y,pc

* void k_glyph8(u8 *scr, const u8 *glyph, const u8 *tab): eight font rows to eight screen rows 160 bytes apart; each
* row byte is four two-pixel codes, tab[code] the two colour nibbles
_k_glyph8
        pshs    u,y
        ldx     6,s
        ldy     8,s
        ldu     10,s
        lda     #8
        sta     <FC_D+1
@row    lda     ,y+
        sta     <FC_D
        lsra
        lsra
        lsra
        lsra
        lsra
        lsra
        ldb     a,u
        stb     ,x
        lda     <FC_D
        lsra
        lsra
        lsra
        lsra
        anda    #3
        ldb     a,u
        stb     1,x
        lda     <FC_D
        lsra
        lsra
        anda    #3
        ldb     a,u
        stb     2,x
        lda     <FC_D
        anda    #3
        ldb     a,u
        stb     3,x
        leax    160,x
        dec     <FC_D+1
        bne     @row
        puls    u,y,pc

* u16 k_sum(const u8 *p, u16 n): the sum of n bytes, modulo 65536
_k_sum
        pshs    u,y
        ldx     6,s
        ldy     8,s
        clra
        clrb
        std     <FC_Y
        cmpy    #0
        beq     @out
@l      ldb     ,x+
        clra
        addd    <FC_Y
        std     <FC_Y
        leay    -1,y
        bne     @l
@out    ldd     <FC_Y
        puls    u,y,pc
        ENDSECTION
