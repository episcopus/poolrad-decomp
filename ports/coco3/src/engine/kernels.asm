* kernels.asm: the engine's inner loops (step 8.3e). CMOC passes arguments on the stack, first argument nearest the
* return address, a byte as a word (its low byte at the higher address). Each routine saves U and Y, which CMOC keeps.
* No interrupt is masked: the frame ISR uses no register it does not save.
        INCLUDE mailbox.inc

        SECTION code
        EXPORT  _k_copy
        EXPORT  _k_fill
        EXPORT  _k_blit
        ifndef  ENG_TEST
        EXPORT  _k_tile8
        endc
        EXPORT  _k_mask
        ifndef  ENG_TEST
        EXPORT  _k_mirror
        endc
        EXPORT  _bp
        EXPORT  _gbuf
        EXPORT  _mbuf
        IMPORT  _db_dirty
        IMPORT  _db_lo
        IMPORT  _db_hi
        EXPORT  _k_glyph8
        ifdef   ENG_TEST
        EXPORT  _k_sum
        endc

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

* void k_fill(u8 *dst, u8 value, u16 n): from the top down, the odd bytes first, then 24 bytes (four PSHUs of D,X,Y), then four
* at a time. FC_Y = the start, FC_D = start + 24, FC_X = start + 4.
_k_fill
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
@out    puls    u,y,pc

* void k_mask(u8 *d, u8 *m, u8 n, u8 key): the colour key of a masked picture becomes its mask (UnpackPicturePixels): for each byte of d the
* mask byte is $F0 for a high nibble equal to the key and $0F for a low one; the byte loses those nibbles. n >= 1.
_k_mask
        pshs    u,y
        ldx     6,s
        ldy     8,s
        ldb     11,s
        stb     <FC_D
        ldb     13,s
        stb     <FC_Y
@l      lda     ,x
        clrb
        pshs    a
        lsra
        lsra
        lsra
        lsra
        cmpa    <FC_Y
        bne     @lo
        ldb     #$F0
@lo     lda     ,s
        anda    #$0F
        cmpa    <FC_Y
        bne     @st
        orb     #$0F
@st     stb     ,y+
        comb
        puls    a
        stb     <FC_Y+1
        anda    <FC_Y+1
        sta     ,x+
        dec     <FC_D
        bne     @l
        puls    u,y,pc

* void k_blit(void): rows of a picture into DrawBuf (step 8.9). The parameters are in `bp` (gfx.c sets them):
*   d     the destination of the first row, DrawBuf's window 0 address with the column included
*   src   the first row of the picture in RAM (gbuf), n bytes a row; msk the same for the mask, 0 = none (opaque)
*   sl    bytes cut off the left of the row (of the mirrored row when mirrored), nb bytes written to each row
*   rows  how many rows; y the DrawBuf row of the first (for the trackers); x0, x1 the first and last byte changed in a row
*   mir   the row is drawn left for right: the bytes in reverse order, the two pixels of each swapped
* A row: dst = (dst & mask) | colour, or dst = colour. The trackers (db_dirty, db_lo, db_hi) follow. Rows are 84 bytes apart.
BP_D    EQU     0
BP_SRC  EQU     2
BP_MSK  EQU     4
BP_N    EQU     6
BP_SL   EQU     7
BP_NB   EQU     8
BP_ROWS EQU     9
BP_Y    EQU     10
BP_X0   EQU     11
BP_X1   EQU     12
BP_MIR  EQU     13
_k_blit
        pshs    u,y
@row    ldx     >_bp+BP_D
        ldy     >_bp+BP_SRC
        ldu     >_bp+BP_MSK
        tst     >_bp+BP_MIR
        bne     @mir
        clra
        ldb     >_bp+BP_SL
        leay    d,y
        ldb     >_bp+BP_NB
        andb    #1
        stb     <FC_D+1                 an odd byte at the end
        ldb     >_bp+BP_NB
        lsrb
        stb     <FC_D                   whole words
        cmpu    #0
        beq     @sopq
        clra
        ldb     >_bp+BP_SL
        leau    d,u
        tst     <FC_D
        beq     @smodd
@sm2    ldd     ,x
        anda    ,u+
        andb    ,u+
        ora     ,y+
        orb     ,y+
        std     ,x++
        dec     <FC_D
        bne     @sm2
@smodd  tst     <FC_D+1
        beq     @done
        lda     ,x
        anda    ,u
        ora     ,y
        sta     ,x
        bra     @done
@sopq   tst     <FC_D
        beq     @soodd
@so2    ldd     ,y++
        std     ,x++
        dec     <FC_D
        bne     @so2
@soodd  tst     <FC_D+1
        beq     @done
        lda     ,y
        sta     ,x
        bra     @done
* mirrored: the source is read backwards from its end less the skip, a pair of nibbles swapped (x16 puts the high nibble in A,
* the low one in B)
@mir    clra
        ldb     >_bp+BP_N
        subb    >_bp+BP_SL
        leay    d,y
        ldb     >_bp+BP_NB
        stb     <FC_D
        cmpu    #0
        beq     @mopq
        ldb     >_bp+BP_N
        subb    >_bp+BP_SL
        clra
        leau    d,u
@mm     lda     ,-y
        ldb     #16
        mul
        pshs    a
        orb     ,s+
        stb     <FC_Y
        lda     ,-u
        ldb     #16
        mul
        pshs    a
        orb     ,s+
        lda     ,x
        pshs    b
        anda    ,s+
        ora     <FC_Y
        sta     ,x+
        dec     <FC_D
        bne     @mm
        bra     @done
@mopq   lda     ,-y
        ldb     #16
        mul
        pshs    a
        orb     ,s+
        stb     ,x+
        dec     <FC_D
        bne     @mopq
@done   clra
        ldb     >_bp+BP_Y
        ldx     #_db_dirty
        abx
        lda     #1
        sta     ,x
        ldx     #_db_lo
        abx
        lda     >_bp+BP_X0
        cmpa    ,x
        bhs     @nolo
        sta     ,x
@nolo   ldx     #_db_hi
        ldb     >_bp+BP_Y
        abx
        lda     >_bp+BP_X1
        cmpa    ,x
        bls     @nohi
        sta     ,x
@nohi   ldd     >_bp+BP_D
        addd    #84
        std     >_bp+BP_D
        clra
        ldb     >_bp+BP_N
        std     <FC_D
        ldd     >_bp+BP_SRC
        addd    <FC_D
        std     >_bp+BP_SRC
        ldd     >_bp+BP_MSK
        beq     @nomsk
        addd    <FC_D
        std     >_bp+BP_MSK
@nomsk  inc     >_bp+BP_Y
        dec     >_bp+BP_ROWS
        lbne    @row
        puls    u,y,pc

        ifndef  ENG_TEST
* void k_tile8(u8 yb, u8 x0, const u8 *src, const u8 *msk, u8 y): an 8x8 item (eight rows of four bytes) into DrawBuf, the common case of k_blit without the per row
* set up: yb the first row's number in the DrawBuf block that window 0 shows (rows 84 bytes apart), x0 the column byte, src and msk (0 = opaque) the item's 32 bytes where
* they are (the picture's block in window 1), y the DrawBuf row of the first for the trackers, which follow as k_blit's do (db_dirty, db_lo, db_hi).
* Step 8.9d: the 3D view draws about 200 of them a step.
_k_tile8
        pshs    u,y
        lda     7,s
        ldb     #84
        mul
        addd    #$8000
        tfr     d,x
        ldb     9,s
        abx
        ldy     10,s
        ldu     12,s
        lda     #8
        sta     <FC_D
        cmpu    #0
        beq     @opq
@m      ldd     ,x
        anda    ,u+
        andb    ,u+
        ora     ,y+
        orb     ,y+
        std     ,x
        ldd     2,x
        anda    ,u+
        andb    ,u+
        ora     ,y+
        orb     ,y+
        std     2,x
        leax    84,x
        dec     <FC_D
        bne     @m
        bra     @trk
@opq    ldd     ,y++
        std     ,x
        ldd     ,y++
        std     2,x
        leax    84,x
        dec     <FC_D
        bne     @opq
@trk    ldb     15,s
        ldx     #_db_dirty
        abx
        lda     #1
        sta     ,x
        sta     1,x
        sta     2,x
        sta     3,x
        sta     4,x
        sta     5,x
        sta     6,x
        sta     7,x
        ldb     15,s
        ldx     #_db_lo
        abx
        lda     9,s
        ldb     #8
@lo     cmpa    ,x
        bhs     @nl
        sta     ,x
@nl     leax    1,x
        decb
        bne     @lo
        ldb     15,s
        ldx     #_db_hi
        abx
        lda     9,s
        adda    #3
        ldb     #8
@hi     cmpa    ,x
        bls     @nh
        sta     ,x
@nh     leax    1,x
        decb
        bne     @hi
        puls    u,y,pc
        endc

        ifndef  ENG_TEST                (the engine tests do not mirror)
* void k_mirror(u8 *b, u8 n): the row of n bytes reversed, the two pixels of each byte swapped
_k_mirror
        pshs    u,y
        ldx     6,s
        clra
        ldb     9,s
        leay    d,x
        leay    -1,y                    Y = the last byte
@l      pshs    y
        cmpx    ,s++
        bhs     @mid
        lda     ,x
        bsr     @swap
        pshs    a                       the first byte, swapped
        lda     ,y
        bsr     @swap
        sta     ,x+                     first := the last, swapped
        puls    a
        sta     ,y                      last := the first, swapped
        leay    -1,y
        bra     @l
@mid    bne     @out                    (X = Y: the middle byte of an odd row)
        lda     ,x
        bsr     @swap
        sta     ,x
@out    puls    u,y,pc
@swap   ldb     #16
        mul
        pshs    a
        orb     ,s+
        tfr     b,a
        rts
        endc

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

        ifdef   ENG_TEST                (the tests sum what they read)
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
        endc
        ENDSECTION

        SECTION bss
_bp     RMB     14                      the parameters of k_blit
        ENDSECTION

* The two staging buffers of the picture routines (gfx.c: a picture's rows copied out of their block, and its mask). They are at $7E00 and $7F00, above the
* image of the shared data ($7C90..$7DEA) and below the constant page: the loader's own stack is there while LOADM runs, but nothing is after it, and the engine's
* address space below $7C90 is full (step 8.9e, which needed the room for faster icon draws).
        SECTION hibss,bss
_gbuf   RMB     256
_mbuf   RMB     256
        ENDSECTION
