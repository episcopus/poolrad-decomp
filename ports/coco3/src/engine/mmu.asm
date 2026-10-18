* mmu.asm: the engine's MMU windows. Slots 0 to 3 ($0000..$7FFF) are never changed after boot; slots 4 to 7
* are the windows (code bank, data, pictures, the screen), shadowed in MMU_SH because the GIME registers can be
* read back only in their low 6 bits and DSKCON needs the original BASIC blocks in them for the length of a call.
        INCLUDE mailbox.inc

        SECTION code
        EXPORT  _mmu_set
        EXPORT  _mmu_get
        EXPORT  _win_set
        EXPORT  _eng_enter
        EXPORT  _eng_leave

* void mmu_set(u8 slot, u8 block)    slot 4..7 of task 0 (the game); slots 6 and 7 of task 1 follow (the engine sees what
* the game has mapped there, so a pointer into a data window stays valid inside an engine call)
_mmu_set
        ldb     3,s                     slot
        lda     5,s                     block
        andb    #3                      0..3 (slot - 4)
        ldx     #MMU_SH
        sta     b,x
        ldx     #$FFA4
        sta     b,x
        cmpb    #2
        blo     @out
        ldx     #$FFAC
        sta     b,x                     task 1 slot 6 and 7
@out    rts

* void win_set(u8 w, u8 block)       the engine's window w (0: logical $8000, 1: $A000), slots 4 and 5 of task 1
_win_set
        ldb     3,s
        lda     5,s
        andb    #1
        ldx     #$FFAC
        sta     b,x
        rts

* void eng_enter(void): the CPU enters the engine's address space (task 1); eng_leave goes back. Neither disturbs D.
_eng_enter
        pshs    a
        lda     #1
        sta     FC_TASK
        sta     $FF91
        puls    a,pc
_eng_leave
        pshs    a
        clr     FC_TASK
        clr     $FF91
        puls    a,pc

* u8 mmu_get(u8 slot)
_mmu_get
        ldb     3,s
        andb    #3
        ldx     #MMU_SH
        ldb     b,x
        clra
        rts
        ENDSECTION
