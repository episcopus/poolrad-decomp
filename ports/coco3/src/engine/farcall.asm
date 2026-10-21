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
        ifdef   GAME
        IMPORT  __engcall
        IMPORT  _banktab
        endc

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
@retry  ldx     #_banktab-1
        lda     b,x
        beq     @missing                the bank is not in memory: the loader has to bring it
        bsr     fcstamp                 used now: the loader evicts the bank used longest ago (step 8.9)
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
@remap  ldx     #_banktab-1
        lda     a,x
        beq     @reload                 the caller's bank was taken for another while the callee ran: bring it back
        bsr     fcstamp
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
@reload
        ifdef   GAME
*       a bank on the bank stack can be evicted (a chain of calls can nest more banks than the pool holds): the loader brings it
*       back before the return goes on. U is the bank stack pointer of the pulls above, the result is in FC_D
        lda     <FC_CURBANK
        tfr     a,b
        clra
        ldx     <FC_D                   the callee's result: the loader's kernels use FC_D and FC_Y as scratch
        pshs    u,y,x,d
        clrb
        jsr     __engcall
        leas    2,s
        puls    x,y,u
        stx     <FC_D
        lda     <FC_CURBANK
        bra     @remap
        else
        lda     #3
        sta     MB_STATUS
        orcc    #$50
@stop2  bra     @stop2
        endc
@missing
        ifdef   GAME
*       the game: the engine loads the bank (api_bankload, routine 0) and the call is tried again
        clra
        pshs    u,y,d                   the bank id, the argument of api_bankload (a word on the stack, as C passes it)
        clrb
        jsr     __engcall               B = 0: routine 0
        leas    2,s
        puls    y,u
        ldb     <FC_CURBANK
        lbra    @retry
        else
        stb     MB_BASE+$3E             which bank: the harness reads it (result word 31)
        lda     #2
        sta     MB_STATUS               finished, failed
        orcc    #$50
@stop   bra     @stop
        endc

* A = the first block of a bank in the pool: stamp it with the tick. Keeps A, takes B and X. (The test builds keep their banks outside
* the pool and stamp nothing.)
fcstamp
        ifdef   GAME
        pshs    a
        inc     <FC_TICK
        tfr     a,b
        cmpb    #$30
        blo     @low
        subb    #$18                    the seventh slot's blocks ($3C) are stamped as $24, a block the pool does not use
@low    ldx     #FC_STAMP-BANK_POOL_FIRST
        abx
        lda     <FC_TICK
        sta     ,x
        puls    a
        endc
        rts

        ifndef  GAME
        SECTION code
        EXPORT  _banktab
_banktab RMB    64                      index = bank id - 1: the first of the two blocks of the bank, 0 = not in memory
*                                       (in the code section, not bss: the loader fills it before CMOC clears bss)
        ENDSECTION
        endc
