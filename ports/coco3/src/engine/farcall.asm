* farcall.asm: the far-call trampoline, bank loader and bank table.
*
* __farcall is entered by JMP from a resident stub with B = bank id, X = entry address in
* the window; the stack holds the caller's return address, then the arguments, exactly as
* if the caller had called the entry directly. So the callee finds its first argument at
* 2,S as CMOC expects. The return address and the caller's Y and bank id go on a separate
* bank stack (U-addressed, DP variables), never on S. D (the result), U and S are preserved
* on the way back, Y is restored to the caller's value. Not reentrant: no interrupt handler
* may use it.

        INCLUDE mailbox.inc
        INCLUDE banks.inc

        SECTION code

        EXPORT  __farcall
__farcall
        stx     <FC_X                   target entry
        sty     <FC_Y                   caller's Y
        stu     <FC_U                   caller's U
        puls    x                       X = caller's return address
        ldu     <FC_BSPTR
        pshu    x                       bank stack: return address
        ldx     <FC_Y
        pshu    x                       caller's Y
        lda     <FC_CURBANK
        stb     <FC_CURBANK
        pshu    a                       the bank that was mapped
        stu     <FC_BSPTR
        ldu     <FC_U                   caller's U back before the call
        ldx     #banktab-1
        lda     b,x
        sta     MMU_SLOT4               map the callee's bank
        inca
        sta     MMU_SLOT5
        jsr     [FC_X]
        std     <FC_D                   result
        stu     <FC_U                   U as the callee left it (= the caller's)
        ldu     <FC_BSPTR
        pulu    a                       the bank to restore
        sta     <FC_CURBANK
        beq     @nomap                  0: the caller was resident code
        ldx     #banktab-1
        lda     a,x
        sta     MMU_SLOT4
        inca
        sta     MMU_SLOT5
@nomap  pulu    y                       caller's Y
        pulu    x                       caller's return address
        stu     <FC_BSPTR
        ldu     <FC_U
        ldd     <FC_D
        jmp     ,x

* _load_banks: copy the staged bank images into their physical blocks.
        EXPORT  _load_banks
_load_banks
        ldx     #STAGE1
        lda     #BANK1_BLK
        bsr     @copy
        ldx     #STAGE2
        lda     #BANK2_BLK
@copy   sta     MMU_SLOT4
        inca
        sta     MMU_SLOT5
        ldy     #BANK_WINDOW
        ldb     #STAGE_BYTES/32
@loop   ldu     ,x++                    16 words per pass
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        ldu     ,x++
        stu     ,y++
        decb
        bne     @loop
        rts

banktab FCB     BANK1_BLK,BANK2_BLK     index = bank id - 1

        ENDSECTION
