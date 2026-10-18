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
        ldx     #_banktab-1
        lda     b,x
        beq     @missing                the bank is not in memory: the loader has to bring it
        sta     MMU_SLOT4               map the callee's bank
        sta     MMU_SH
        inca
        sta     MMU_SLOT5
        sta     MMU_SH+1
        jsr     [FC_X]
        std     <FC_D                   result
        stu     <FC_U                   U as the callee left it (= the caller's)
        ldu     <FC_BSPTR
        pulu    a                       the bank to restore
        sta     <FC_CURBANK
        beq     @nomap                  0: the caller was resident code
        ldx     #_banktab-1
        lda     a,x
        sta     MMU_SLOT4
        sta     MMU_SH
        inca
        sta     MMU_SLOT5
        sta     MMU_SH+1
@nomap  pulu    y                       caller's Y
        pulu    x                       caller's return address
        stu     <FC_BSPTR
        ldu     <FC_U
        ldd     <FC_D
        jmp     ,x
@missing
        stb     MB_BASE+$3E             which bank: the harness reads it (result word 31)
        lda     #2
        sta     MB_STATUS               finished, failed
        orcc    #$50
@stop   bra     @stop

        SECTION code
        EXPORT  _banktab
_banktab RMB    64                      index = bank id - 1: the first of the two blocks of the bank, 0 = not in memory
*                                       (in the code section, not bss: the loader fills it before CMOC clears bss)
        ENDSECTION
