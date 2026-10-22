* kernels.asm: the engine's inner loops (step 8.3e). CMOC passes arguments on the stack, first argument nearest the
* return address, a byte as a word (its low byte at the higher address). Each routine saves U and Y, which CMOC keeps.
* No interrupt is masked: the frame ISR uses no register it does not save.
        INCLUDE mailbox.inc

        SECTION code
        EXPORT  _k_copy
        EXPORT  _k_fill
        EXPORT  _k_fillrect
        EXPORT  _k_put
        EXPORT  _k_blit
        ifndef  ENG_TEST
        EXPORT  _k_tile8
        EXPORT  _k_icon
        endc
        EXPORT  _k_mask
        ifndef  ENG_TEST
        EXPORT  _k_mirror
        endc
        EXPORT  _bp
        EXPORT  _gbuf
        EXPORT  _mbuf
        EXPORT  _db_dirty
        EXPORT  _db_lo
        EXPORT  _db_hi
        IMPORT  _rowa
        IMPORT  _font
        EXPORT  _k_text
        EXPORT  _k_flush
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

* void k_fillrect(u8 *dst, u8 value, u8 n, u8 rows): rows rows of n bytes (a multiple of 4, at most 160) at dst, 160 bytes apart, all in the window that is mapped
* (FillPlaneRect's rectangles: the combat map's 64 byte by 168 row clear and the like took 18 ms through k_fill, a call a row). A row is filled from its end down by PSHU,
* six bytes at a time: a run of 26 PSHU entered at the point that leaves the row's number of groups, then the odd words; the pattern stays in D, X and Y for all rows.
_k_fillrect
        pshs    u,y
        leas    -3,s                    0,s a leftover word  1,s a second one  2,s rows left
        lda     14,s                    n
        clrb
@d      cmpa    #6
        blo     @e
        suba    #6
        incb
        bra     @d
@e      clr     0,s
        clr     1,s
        cmpa    #2
        blo     @n
        inc     0,s
        cmpa    #4
        blo     @n
        inc     1,s
@n      aslb                            B = 2 bytes of code for each group of six
        clra
        std     <FC_X
        ldd     #@runend
        subd    <FC_X
        std     <FC_X                   the entry in the run
        lda     16,s
        sta     2,s
        ldx     9,s
        ldb     14,s
        abx                             (an accumulator offset of an indexed mode is signed: ABX adds B as it is)
        tfr     x,u                     U = the end of the first row
        lda     12,s
        tfr     a,b
        tfr     d,x
        tfr     d,y
@row    stu     <FC_Y
        jmp     [$0087]
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
        pshu    d,x,y
@runend tst     0,s
        beq     @s2
        pshu    d
@s2     tst     1,s
        beq     @nx
        pshu    d
@nx     ldu     <FC_Y
        leau    160,u
        dec     2,s
        lbne    @row
        leas    3,s
        puls    u,y,pc

* void k_flush(void): the dirty rows of DrawBuf to the screen, 8 pixels right and 8 rows down: for each row y with db_dirty[y] set, the bytes db_lo[y] to db_hi[y] go to the
* screen at rowa[y + 8] + db_lo[y] + 4 (db_flush). Window 0 shows DrawBuf's block, window 1 the screen's, each mapped only when it changes; a span that crosses a block border
* of the screen is copied in two parts. Step 8.9e: a flush took 27 ms for 49 rows of 42 bytes, most of it the C loop's work for each row.
_k_flush
        pshs    u,y
        leas    -5,s                    0,s DrawBuf's block in window 0  1,s the screen's in window 1  2,s y  3,s bytes to the border  4,s the rest
        lda     #$FF
        sta     0,s
        sta     1,s
        clr     2,s
        ldu     #_db_dirty
@y      lda     ,u
        lbeq    @skip
        ldb     168,u
        clra
        tfr     d,y                     Y = lo
        lda     336,u
        suba    168,u
        inca
        sta     <FC_Y                   n
        ldb     2,s
        clra
        addd    #8
        aslb
        rola
        ldx     #_rowa
        ldd     d,x                     rowa[y + 8]
        leay    d,y
        leay    4,y                     Y = the screen address of the span
        tfr     y,d
        lsra
        lsra
        lsra
        lsra
        lsra                            A = the screen block (SCREEN_BLK is 0)
        cmpa    1,s
        beq     @w1
        sta     1,s
        sta     $FFAD
@w1     tfr     y,d
        anda    #$1F
        addd    #$A000
        tfr     d,x                     X = the destination in window 1
        ldb     2,s
        cmpb    #97
        blo     @b4
        subb    #97
        lda     #5
        bra     @mp
@b4     lda     #4
@mp     cmpa    0,s
        beq     @w0
        sta     0,s
        sta     $FFAC
@w0     lda     #84
        mul
        addd    #$8000
        tfr     d,y
        ldb     168,u
        leay    b,y                     Y = the span in DrawBuf (lo < 128)
        tfr     x,d
        addb    <FC_Y
        adca    #0
        cmpd    #$C001
        blo     @one
        pshs    x
        ldd     #$C000
        subd    ,s++                    D = the bytes that fit the screen block
        stb     3,s
        ldb     <FC_Y
        subb    3,s
        stb     4,s
        ldb     3,s
        bsr     @cpy
        lda     1,s
        inca
        sta     1,s
        sta     $FFAD
        ldx     #$A000
        ldb     4,s
        bsr     @cpy
        bra     @skip
@one    ldb     <FC_Y
        bsr     @cpy
@skip   leau    1,u
        inc     2,s
        lda     2,s
        cmpa    #168
        lblo    @y
        leas    5,s
        puls    u,y,pc
* B bytes (1 to 160) from Y to X
@cpy    stb     <FC_D+1
        lsrb
        beq     @odd
        stb     <FC_D
@wl     ldd     ,y++
        std     ,x++
        dec     <FC_D
        bne     @wl
@odd    lda     <FC_D+1
        anda    #1
        beq     @cx
        lda     ,y+
        sta     ,x+
@cx     rts

* void k_put(u8 *dst, const u8 *src, u8 n, u8 rows): rows rows of n bytes (a multiple of 4) from src (n bytes a row, one after the other) to dst (160 bytes a row, the screen's),
* both in the windows that are mapped. gfx_item's copy of a picture item to the screen: it staged the item through a 256 byte buffer and called k_copy for every row.
* Step 8.9f: a menu draws three thousand 8x8 items (the windows' frames) in a screen.
_k_put
        pshs    u,y
        ldx     6,s
        ldy     8,s
        ldb     11,s
        cmpb    #4
        bne     @gen
        lda     13,s
        sta     <FC_D
@t      ldd     ,y++
        std     ,x
        ldd     ,y++
        std     2,x
        leax    160,x
        dec     <FC_D
        bne     @t
        puls    u,y,pc
@gen    lda     #160
        stb     <FC_Y+1
        suba    <FC_Y+1
        sta     <FC_Y                   the step from the end of one row to the start of the next
        lsrb
        stb     <FC_X                   words a row
        lda     13,s
        sta     <FC_D
@row    ldb     <FC_X
        stb     <FC_D+1
@w      ldd     ,y++
        std     ,x++
        dec     <FC_D+1
        bne     @w
        ldb     <FC_Y
        abx
        dec     <FC_D
        bne     @row
        puls    u,y,pc

* u8 k_text(u8 col, u8 row, u8 color, u8 count, u8 glyph, u8 textset): count copies of a glyph on the text row, from cell col (cut at column 39): the font's eight rows of the glyph
* become eight rows of four bytes each. Windows 0 and 1 show the screen block of the cell and the next one, so that a glyph whose rows cross a block border is drawn as any other.
* A byte of the font is two nibbles, each of which gives two bytes of the screen (a pixel pair each): the 16 entries of that table for the last colour are kept (_ttab, _tkey) and made
* again when the colour changes; a glyph of eight zero bytes (a space) is eight rows of zeros. Step 8.9f: a menu draws 8,000 single glyphs a screen; this is 2 to 5 times faster than the
* version with a table of four entries and a call of the kernel for each cell. Returns 0.
_k_text
        pshs    u,y
        leas    -10,s                   0 blank  1 cells  2..5 the colour table of four  6,7 the font rows  8,9 the cell
        ldb     25,s
        tst     27,s
        beq     @ni
        cmpb    #$61
        blo     @m
        cmpb    #$7A
        bhi     @m
        subb    #32
@m      andb    #63
@ni     cmpb    #176
        lbhi    @out
        clra
        aslb
        rola
        aslb
        rola
        aslb
        rola
        addd    #_font
        tfr     d,y                     Y = the glyph's eight font bytes
        lda     #40
        suba    17,s
        lbls    @out
        cmpa    23,s
        blo     @nn
        lda     23,s
@nn     sta     1,s                     the cells: count, or what is left of the row
        lbeq    @out
        ldd     ,y
        ora     2,y
        orb     3,y
        ora     4,y
        orb     5,y
        ora     6,y
        orb     7,y
        sta     0,s
        orb     0,s
        stb     0,s                     0 when all eight rows are zero
        beq     @addr
        ldb     21,s
        andb    #15
        cmpb    _tkey
        beq     @addr
        stb     _tkey
        clr     2,s
        stb     3,s
        aslb
        aslb
        aslb
        aslb
        stb     4,s
        orb     3,s
        stb     5,s
        sty     6,s                     (the font pointer, while Y is the table builder's)
        ldx     #_ttab
        clr     <FC_Y
@hl     clr     <FC_Y+1
@ll     leau    2,s
        ldb     <FC_Y
        lda     b,u
        ldb     <FC_Y+1
        ldb     b,u
        std     ,x++
        inc     <FC_Y+1
        ldb     <FC_Y+1
        cmpb    #4
        blo     @ll
        inc     <FC_Y
        ldb     <FC_Y
        cmpb    #4
        blo     @hl
        ldy     6,s
@addr   ldb     19,s
        aslb
        aslb
        aslb
        clra
        aslb
        rola
        ldx     #_rowa
        ldd     d,x
        tfr     d,x
        ldb     17,s
        clra
        aslb
        rola
        aslb
        rola
        leax    d,x                     X = the screen address of the first cell's first row
        tfr     x,d
        lsra
        lsra
        lsra
        lsra
        lsra
        sta     $FFAC
        inca
        sta     $FFAD                   window 1 shows the next block
        tfr     x,d
        anda    #$1F
        addd    #$8000
        tfr     d,x                     X = its address in the windows
        sty     6,s                     the font rows, for every cell
        ldu     #_ttab
@cell   stx     8,s
        tst     0,s
        bne     @px
        ldd     #0
        ldb     #8
        stb     <FC_D+1
        clrb
@br     std     ,x
        std     2,x
        leax    160,x
        dec     <FC_D+1
        bne     @br
        bra     @nx
@px     ldy     6,s
        lda     #8
        sta     <FC_D+1
@row    lda     ,y+
        tfr     a,b
        anda    #$F0
        lsra
        lsra
        lsra
        andb    #$0F
        aslb
        stb     <FC_D
        ldd     a,u
        std     ,x
        ldb     <FC_D
        ldd     b,u
        std     2,x
        leax    160,x
        dec     <FC_D+1
        bne     @row
@nx     ldx     8,s
        leax    4,x
        dec     1,s
        bne     @cell
@out    clrb
        clra
        leas    10,s
        puls    u,y,pc

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

* void k_icon(u8 yb, u8 x0, const u8 *src, const u8 *msk, u8 y, u8 mirror): a 3 cell by 24 row item (12 bytes a row) into DrawBuf, k_tile8's case for the icons of the
* combat map: yb the first row in the block that window 0 shows, x0 the column byte, src and msk (0 = opaque) the item's 288 bytes where they are, y the DrawBuf row of
* the first for the trackers, mirror 1 = drawn left for right (the bytes of a row in reverse order, the two pixels of each swapped, as k_blit's mirrored loop does).
* Step 8.9e: the combat map draws two to four thousand of them in a big fight, each took 10 to 25 ms through k_blit and the staging buffers.
_k_icon
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
        lda     #24
        sta     <FC_D
        tst     17,s
        bne     @mir
        cmpu    #0
        beq     @opq
@m      ldd     ,x
        anda    ,u+
        andb    ,u+
        ora     ,y+
        orb     ,y+
        std     ,x++
        ldd     ,x
        anda    ,u+
        andb    ,u+
        ora     ,y+
        orb     ,y+
        std     ,x++
        ldd     ,x
        anda    ,u+
        andb    ,u+
        ora     ,y+
        orb     ,y+
        std     ,x++
        ldd     ,x
        anda    ,u+
        andb    ,u+
        ora     ,y+
        orb     ,y+
        std     ,x++
        ldd     ,x
        anda    ,u+
        andb    ,u+
        ora     ,y+
        orb     ,y+
        std     ,x++
        ldd     ,x
        anda    ,u+
        andb    ,u+
        ora     ,y+
        orb     ,y+
        std     ,x++
        leax    72,x
        dec     <FC_D
        bne     @m
        bra     @trk
@opq    ldd     ,y++
        std     ,x++
        ldd     ,y++
        std     ,x++
        ldd     ,y++
        std     ,x++
        ldd     ,y++
        std     ,x++
        ldd     ,y++
        std     ,x++
        ldd     ,y++
        std     ,x++
        leax    72,x
        dec     <FC_D
        bne     @opq
        bra     @trk
@mir    leay    12,y                    the row's end: the bytes are read backwards
        cmpu    #0
        beq     @mopq
        leau    12,u
@mrow   ldb     #12
        stb     <FC_D+1
@mb     lda     ,-y
        ldb     #16
        mul
        sta     <FC_Y+1
        orb     <FC_Y+1
        stb     <FC_Y                   the colour byte, its pixels swapped
        lda     ,-u
        ldb     #16
        mul
        sta     <FC_Y+1
        orb     <FC_Y+1                 B = the mask byte, swapped
        stb     <FC_Y+1
        lda     ,x
        anda    <FC_Y+1
        ora     <FC_Y
        sta     ,x+
        dec     <FC_D+1
        bne     @mb
        leax    72,x
        leay    24,y
        leau    24,u
        dec     <FC_D
        bne     @mrow
        bra     @trk
@mopq   ldb     #12
        stb     <FC_D+1
@mob    lda     ,-y
        ldb     #16
        mul
        sta     <FC_Y+1
        orb     <FC_Y+1
        stb     ,x+
        dec     <FC_D+1
        bne     @mob
        leax    72,x
        leay    24,y
        dec     <FC_D
        bne     @mopq
@trk    ldb     15,s
        ldx     #_db_dirty
        abx
        lda     #1
        ldb     #24
@dr     sta     ,x+
        decb
        bne     @dr
        ldb     15,s
        ldx     #_db_lo
        abx
        lda     9,s
        ldb     #24
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
        adda    #11
        ldb     #24
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
_tkey   RMB     1                       the colour (0 to 15) that _ttab is the table of
_ttab   RMB     32                      for each nibble of a font byte, the two screen bytes it makes
* the trackers of DrawBuf: a row has been drawn on, the first and the last byte of it that changed (they are in one block so that k_flush finds them at fixed distances)
_db_dirty RMB   168
_db_lo  RMB     168
_db_hi  RMB     168
        ENDSECTION

* The two staging buffers of the picture routines (gfx.c: a picture's rows copied out of their block, and its mask). They are at $7E00 and $7F00, above the
* image of the shared data ($7C90..$7DEA) and below the constant page: the loader's own stack is there while LOADM runs, but nothing is after it, and the engine's
* address space below $7C90 is full (step 8.9e, which needed the room for faster icon draws).
        SECTION hibss,bss
_gbuf   RMB     256
_mbuf   RMB     256
        ENDSECTION
