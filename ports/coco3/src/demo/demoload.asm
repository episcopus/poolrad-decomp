* demoload.asm: the demo's bank loader: copies the bank images that LOADM staged below $6000 into their blocks (the game's
* loader reads the banks from disk, step 8.5).
        INCLUDE mailbox.inc
        INCLUDE banks.inc

        SECTION code
        IMPORT  _banktab
* _load_banks: copy the staged bank images into their physical blocks.
        EXPORT  _load_banks
_load_banks
        lda     #BANK1_BLK
        sta     _banktab
        lda     #BANK2_BLK
        sta     _banktab+1
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



        ENDSECTION
