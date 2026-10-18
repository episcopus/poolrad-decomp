* mmu.asm: the engine's MMU windows. Slots 0 to 3 ($0000..$7FFF) are never changed after boot; slots 4 to 7
* are the windows (code bank, data, pictures, the screen), shadowed in MMU_SH because the GIME registers can be
* read back only in their low 6 bits and DSKCON needs the original BASIC blocks in them for the length of a call.
        INCLUDE mailbox.inc

        SECTION code
        EXPORT  _mmu_set
        EXPORT  _mmu_get

* void mmu_set(u8 slot, u8 block)    slot 4..7
_mmu_set
        ldb     3,s                     slot
        lda     5,s                     block
        andb    #3                      0..3 (slot - 4)
        ldx     #MMU_SH
        sta     b,x
        ldx     #$FFA4
        sta     b,x
        rts

* u8 mmu_get(u8 slot)
_mmu_get
        ldb     3,s
        andb    #3
        ldx     #MMU_SH
        ldb     b,x
        clra
        rts
        ENDSECTION
