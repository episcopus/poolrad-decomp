* rle.asm: the DAX run-length decoder, as a resumable state machine so that it can be fed a sector at a time and write
* into whatever window the caller has mapped. The format (tools/re/dax.py unrle): a control byte n < $80 copies the next
* n+1 bytes; n >= $80 repeats the next byte 256-n times.
*
*   struct Rle { u8 *src, *srcend, *dst, *dstend; u8 pad; u8 count; u8 mode; u8 val; }     offsets 0 2 4 6 8 9 10 11
*   mode 0 expect a control byte, 1 inside a literal (count left), 2 expect the run value (count is the run length),
*        3 inside a run (count left, value in val)
*
* u8 k_rle(struct Rle *r): decode until the input is used up (returns 0) or the output is full (returns 1). The caller
* refills whichever ran out and calls again; the state is in the struct.
        SECTION code
        EXPORT  _k_rle

_k_rle
        pshs    u,y
        ldu     6,s                     U = state
        ldx     ,u                      X = src
        ldy     4,u                     Y = dst
        ldb     10,u
        beq     @ctl
        cmpb    #1
        beq     @lit
        cmpb    #2
        beq     @runval
        bra     @run
*
@ctl    cmpx    2,u
        beq     @inend
        lda     ,x+
        bmi     @newrun
        inca                            literal: a+1 bytes (1..128)
        sta     9,u
        lda     #1
        sta     10,u
        bra     @lit
@newrun nega                            run: 256-a bytes (1..128)
        sta     9,u
        lda     #2
        sta     10,u
        bra     @runval
*
@lit    lda     9,u
        beq     @done
@litl   cmpx    2,u
        beq     @inend
        cmpy    6,u
        beq     @outfull
        lda     ,x+
        sta     ,y+
        dec     9,u
        bne     @litl
@done   clr     10,u
        bra     @ctl
*
@runval cmpx    2,u
        beq     @inend
        lda     ,x+
        sta     11,u
        lda     #3
        sta     10,u
@run    lda     9,u
        beq     @done
        lda     11,u
@runl   cmpy    6,u
        beq     @outfull
        sta     ,y+
        dec     9,u
        bne     @runl
        bra     @done
*
@inend  stx     ,u
        sty     4,u
        clrb
        bra     @ret
@outfull stx    ,u
        sty     4,u
        ldb     #1
@ret    clra
        puls    u,y,pc
        ENDSECTION
