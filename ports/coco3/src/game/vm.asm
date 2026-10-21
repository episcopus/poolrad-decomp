* vm.asm: the game's paged data (step 8.5c). Two data windows, slot 6 ($C000) and slot 7 ($E000, usable to $FDFF), show two
* of eight 8 KB pages: the pages of the game's DGROUP above $8000 (ids 0..3, the offsets $8000..$FFFF) and of the banked
* heap (ids 4..11). _vm_pgblk gives the physical block of every id. The window that was used less recently is the one a
* miss takes; the pointer a call returns is good until the next call. The registers of task 1 follow (the engine sees the
* same blocks in its slots 6 and 7), and so do the shadows.
        INCLUDE mailbox.inc

        SECTION code
        EXPORT  _vm_ptr
        EXPORT  _vm_pp
        EXPORT  _vm_bp
        EXPORT  _vm_bpv
        EXPORT  _vm_pkp
        IMPORT  _vm_far
        EXPORT  _vm_w0
        EXPORT  _vm_w1
        EXPORT  _vm_pgblk
        EXPORT  _vm_reset

* void *vm_ptr(u16 v): v is a DGROUP offset in $8000..$FFFF
_vm_ptr
        ldd     2,s
        anda    #$1F
        tfr     d,x                     X = the offset in the page
        lda     2,s
        lsra
        lsra
        lsra
        lsra
        lsra
        suba    #4
        tfr     a,b                     B = page id 0..3
        lbra    vmmap

* void *vm_bp(farptr p): a block of the banked heap, the high word BSEG + page (high byte $20), the low word the offset in the page. The
* fast path of FPB: about 100 cycles with the caller's push; any other farptr (nil, a native or paged address) goes to vm_far.
_vm_bp
        lda     2,s
        cmpa    #$20
        bne     @slow
        ldb     3,s
        addb    #4                      page id 4..11
        ldx     4,s
        lbra    vmmap
@slow   jmp     _vm_far

* void *vm_bpv(const farptr *pp): vm_bp of the farptr that pp points to. The caller gives the address of its variable (two bytes) instead of
* copying the four bytes of the value onto the stack with a library routine (idea 5 of step 8.9c).
_vm_bpv
        ldx     2,s
        lda     ,x
        cmpa    #$20
        bne     @slow
        ldb     1,x
        addb    #4                      page id 4..11
        ldx     2,x
        lbra    vmmap
@slow   ldd     2,x
        pshs    d
        ldd     ,x
        pshs    d
        jsr     _vm_far
        leas    4,s
        rts

* u8 *vm_pkp(farptr p, u16 off): the four bytes at offset `off` of the banked block p names, read WITHOUT taking a data window: a page that
* is in a window is read where it is, any other is mapped into the window that would be the next victim for the length of the read and the
* old block goes back. Returns the address of a native copy (_vm_pk). A pointer field read as the address of another deref (PEEKP) therefore
* adds one mapping to a statement, not two: a struct copy or a call with two addresses needs no more than the two windows.
_vm_pkp
        lda     2,s
        cmpa    #$20
        bne     @pslow
        ldd     4,s
        addd    6,s
        tfr     d,x                     X = the offset in the page
        ldb     3,s
        addb    #4                      B = page id
        cmpb    _vm_w0
        beq     @h0
        cmpb    _vm_w1
        beq     @h1
        ldy     #_vm_pgblk
        lda     b,y                     A = the block the read needs
        tst     _vm_lru
        bne     @v1
        ldb     MMU_SH+2                B = the block window 0 shows
        sta     $FFA6
        leax    $C000,x
        bsr     @rd
        stb     $FFA6
        ldd     #_vm_pk
        rts
@v1     ldb     MMU_SH+3
        sta     $FFA7
        leax    $E000,x
        bsr     @rd
        stb     $FFA7
        ldd     #_vm_pk
        rts
@h0     leax    $C000,x
        bra     @h
@h1     leax    $E000,x
@h      bsr     @rd
        ldd     #_vm_pk
        rts
@rd     ldy     ,x
        sty     _vm_pk
        ldy     2,x
        sty     _vm_pk+2
        rts
@pslow  ldx     4,s
        pshs    x
        ldd     4,s
        pshs    d
        jsr     _vm_far
        leas    4,s
        tfr     d,x
        ldd     6,s
        leax    d,x
        bra     @h

* void *vm_pp(u8 id, u16 off): page id 0..11, offset in the page
_vm_pp
        ldb     3,s
        ldx     4,s

* B = page id, X = offset: returns D = pointer in a window
vmmap   cmpb    _vm_w0
        beq     @w0
        cmpb    _vm_w1
        beq     @w1
        tst     _vm_lru
        bne     @load1
        stb     _vm_w0                  a miss: window 0 takes the page
        ldy     #_vm_pgblk
        lda     b,y
        sta     $FFA6
        sta     $FFAE
        sta     MMU_SH+2
@w0     lda     #1
        sta     _vm_lru                 window 1 is the older one now
        tfr     x,d
        anda    #$1F
        ora     #$C0
        rts
@load1  stb     _vm_w1
        ldy     #_vm_pgblk
        lda     b,y
        sta     $FFA7
        sta     $FFAF
        sta     MMU_SH+3
@w1     clr     _vm_lru                 window 0 is the older one now
        tfr     x,d
        anda    #$1F
        ora     #$E0
        rts

* void vm_reset(void): no page in either window
_vm_reset
        lda     #$FF
        sta     _vm_w0
        sta     _vm_w1
        clr     _vm_lru
        rts

_vm_w0  FCB     $FF                     the page id each window shows (in the code section: the loader may write them before CMOC clears bss)
_vm_w1  FCB     $FF
_vm_lru FCB     0                       0: window 0 is the next victim, 1: window 1
_vm_pk  RMB     4                       the copy vm_pkp returns
_vm_pgblk RMB   16
        ENDSECTION
