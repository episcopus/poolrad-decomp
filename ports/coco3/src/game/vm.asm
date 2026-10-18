* vm.asm: the game's paged data (step 8.5c). Two data windows, slot 6 ($C000) and slot 7 ($E000, usable to $FDFF), show two
* of eight 8 KB pages: the pages of the game's DGROUP above $8000 (ids 0..3, the offsets $8000..$FFFF) and of the banked
* heap (ids 4..7). _vm_pgblk gives the physical block of every id. The window that was used less recently is the one a
* miss takes; the pointer a call returns is good until the next call. The registers of task 1 follow (the engine sees the
* same blocks in its slots 6 and 7), and so do the shadows.
        INCLUDE mailbox.inc

        SECTION code
        EXPORT  _vm_ptr
        EXPORT  _vm_pp
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
        bra     vmmap

* void *vm_pp(u8 id, u16 off): page id 0..7, offset in the page
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
_vm_pgblk RMB   8
        ENDSECTION
