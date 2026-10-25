* ide_xfer.asm: sectors through the registers of an IDE interface (Cloud-9 SuperIDE, Glenside IDE: step 8.12, docs/PHASE-8.12.md), by programmed I/O.
* The registers (SuperIDE manual rev 1.3, section 6; base address $FF50 as shipped, assembled with -DIDE_ADDR=n for another):
*   +0 data   +1 error (read) / features (write)   +2 sector count   +3 LBA 7..0   +4 LBA 15..8   +5 LBA 23..16   +6 device ($E0 master, $F0 slave, LBA mode, bits 27..24)
*   +7 status (read: bit 7 busy, bit 6 ready, bit 3 data request, bit 0 error) / command (write)   +8 the latch: the high byte of a 16 bit word
* The card moves 512 bytes a sector. Two ways to read them (_ide_mode, chosen by ide.c's flop_detect from what the card does):
*   0  words: a read of +0 gives the low byte and latches the high byte, which is read from +8 (the card's own mode after a reset)
*   1  bytes: SET FEATURES $01 (8 bit transfers) was accepted, every read of +0 is the next byte of the sector. A 6309 moves the 256 bytes of a half with ONE
*      TFM (fixed source, 3 cycles a byte); a 6809 reads two bytes into A and B and stores them with one STD (9 cycles a byte)
* A sector is moved in two halves of 256 bytes, which is what the game's sectors are: the image keeps two of them in a card sector (ide.c). Interrupts are masked
* for the length of one half (1 to 2 ms), not of a sector or a command: the card waits for the CPU.
        INCLUDE mailbox.inc
        IFNDEF  IDE_ADDR
IDE_ADDR        EQU     $FF50
        ENDC
D_DATA          EQU     IDE_ADDR
D_FEAT          EQU     IDE_ADDR+1
D_CNT           EQU     IDE_ADDR+2
D_LBA0          EQU     IDE_ADDR+3
D_LBA1          EQU     IDE_ADDR+4
D_LBA2          EQU     IDE_ADDR+5
D_HEAD          EQU     IDE_ADDR+6
D_CMD           EQU     IDE_ADDR+7
D_LATCH         EQU     IDE_ADDR+8

        SECTION code
        IMPORT  _cpu6309
        IMPORT  _ide_dev
        IMPORT  _ide_mode
        EXPORT  _ide_cmd
        EXPORT  _ide_in
        EXPORT  _ide_out

* u8 ide_cmd(u8 cmd, u8 count, u8 lba_hi, u16 lba_lo): selects the device (_ide_dev), waits for it to be ready, loads the registers and starts the command.
* 0 = started; else the status ($80: it never became ready)
_ide_cmd
        pshs    cc,u,y
        IFDEF   IDE_SLOW
        sta     >$FFD8                  (the interface is made to run at 0.89 MHz: make ide IDE_SLOW=1)
        ENDC
        lbsr    ready                   (a command that is finishing)
        bcs     cmdx
        lda     >_ide_dev
        sta     >D_HEAD                 the device
        lbsr    ready
        bcs     cmdx
        ldb     10,s
        stb     >D_CNT
        lda     14,s
        sta     >D_LBA0
        lda     13,s
        sta     >D_LBA1
        lda     12,s
        sta     >D_LBA2
        lda     8,s
        sta     >D_CMD
        clrb
cmdx    clra                            (B is the status when the carry is set)
        IFDEF   IDE_SLOW
        sta     >$FFD9
        ENDC
        puls    cc,u,y,pc

* u8 ide_in(u8 *dst, u8 n, u8 mode): the data of a command that reads. mode 0: n sectors of 512 bytes to dst; 1: one sector, its first 256 bytes dropped, the
* second 256 to dst; 2: one sector, the first 256 to dst, the second dropped. 0 = ok; else the status ($80: no data request in time, bit 0: the card's error)
_ide_in
        pshs    cc,u,y
        IFDEF   IDE_SLOW
        sta     >$FFD8
        ENDC
        leas    -2,s                    ,s = the sectors left, 1,s = the mode (the arguments are two bytes further)
        ldb     12,s
        stb     ,s
        ldb     14,s
        stb     1,s
        ldx     9,s
inl     lbsr    drq
        bcs     inx
        lda     1,s
        bne     in12
        lbsr    getq                    mode 0: both halves to dst
        lbsr    getq
        bra     inn
in12    cmpa    #1
        bne     in2
        lbsr    skipq                   mode 1: the first dropped
        lbsr    getq
        bra     inn
in2     lbsr    getq                    mode 2: the second dropped
        lbsr    skipq
inn     dec     ,s
        bne     inl
        clrb
inx     leas    2,s
        clra
        IFDEF   IDE_SLOW
        sta     >$FFD9
        ENDC
        puls    cc,u,y,pc

* u8 ide_out(const u8 *src): the data of a command that writes one sector: the 256 bytes at src, then 256 zeros; waits for the card to be done. 0 = ok, else the status
_ide_out
        pshs    cc,u,y
        IFDEF   IDE_SLOW
        sta     >$FFD8
        ENDC
        ldx     7,s
        lbsr    drq
        bcs     outx
        lbsr    putq
        lbsr    zeroq
        lbsr    ready                   the card writes the sector
        bcs     outx
        ldb     >D_CMD
        andb    #1                      the error bit
outx    clra
        IFDEF   IDE_SLOW
        sta     >$FFD9
        ENDC
        puls    cc,u,y,pc

* (carry clear) the device is not busy and is ready, (carry set) B = the status that it stayed at: about 2 s. Preserves X
ready   pshs    x
        ldy     #3
rdy1    ldx     #0
rdy2    ldb     >D_CMD
        andb    #$C0
        cmpb    #$40
        beq     rdyok
        leax    -1,x
        bne     rdy2
        leay    -1,y
        bne     rdy1
        ldb     >D_CMD
        orb     #$80                    (a status of 0 would read as success)
        orcc    #1
        puls    x,pc
rdyok   clrb
        andcc   #$FE
        puls    x,pc

* (carry clear) data request, (carry set) B = the status: the error bit, or $80 for a card that stayed busy (about 2 s). Preserves X
drq     pshs    x
        ldy     #3
dq1     ldx     #0
dq2     ldb     >D_CMD
        bmi     dqbsy
        bitb    #1
        bne     dqerr
        bitb    #8
        bne     dqok
dqbsy   leax    -1,x
        bne     dq2
        leay    -1,y
        bne     dq1
        ldb     #$80
dqerr   orcc    #1
        puls    x,pc
dqok    clrb
        andcc   #$FE
        puls    x,pc

* the 256 bytes of a half: X = dst on entry and advanced by 256 on return; the interrupt mask is the caller's again at the end
getq    pshs    cc
        orcc    #$50
        tst     >_ide_mode
        bne     gq8
        ldy     #16                     words: low byte from the data register, high byte from the latch
gq16    lda     >D_DATA
        ldb     >D_LATCH
        std     ,x++
        lda     >D_DATA
        ldb     >D_LATCH
        std     ,x++
        lda     >D_DATA
        ldb     >D_LATCH
        std     ,x++
        lda     >D_DATA
        ldb     >D_LATCH
        std     ,x++
        lda     >D_DATA
        ldb     >D_LATCH
        std     ,x++
        lda     >D_DATA
        ldb     >D_LATCH
        std     ,x++
        lda     >D_DATA
        ldb     >D_LATCH
        std     ,x++
        lda     >D_DATA
        ldb     >D_LATCH
        std     ,x++
        leay    -1,y
        bne     gq16
        puls    cc,pc
gq8     tst     >_cpu6309
        bne     gq8t
        ldy     #16                     bytes on a 6809: two reads of the same register, one 16 bit store
gq8l    lda     >D_DATA
        ldb     >D_DATA
        std     ,x++
        lda     >D_DATA
        ldb     >D_DATA
        std     ,x++
        lda     >D_DATA
        ldb     >D_DATA
        std     ,x++
        lda     >D_DATA
        ldb     >D_DATA
        std     ,x++
        lda     >D_DATA
        ldb     >D_DATA
        std     ,x++
        lda     >D_DATA
        ldb     >D_DATA
        std     ,x++
        lda     >D_DATA
        ldb     >D_DATA
        std     ,x++
        lda     >D_DATA
        ldb     >D_DATA
        std     ,x++
        leay    -1,y
        bne     gq8l
        puls    cc,pc
gq8t    ldy     #D_DATA                 a 6309: LDW #256, TFM Y,X+ (the source is fixed, the destination counts up)
        fcb     $10,$86,$01,$00
        fcb     $11,$3B,$21
        puls    cc,pc

* the 256 bytes of a half, read and dropped
skipq   pshs    cc
        orcc    #$50
        ldy     #16
        tst     >_ide_mode
        bne     sq8
sq16    lda     >D_DATA                 words: both bytes of a word
        ldb     >D_LATCH
        lda     >D_DATA
        ldb     >D_LATCH
        lda     >D_DATA
        ldb     >D_LATCH
        lda     >D_DATA
        ldb     >D_LATCH
        lda     >D_DATA
        ldb     >D_LATCH
        lda     >D_DATA
        ldb     >D_LATCH
        lda     >D_DATA
        ldb     >D_LATCH
        lda     >D_DATA
        ldb     >D_LATCH
        leay    -1,y
        bne     sq16
        puls    cc,pc
sq8     lda     >D_DATA
        lda     >D_DATA
        lda     >D_DATA
        lda     >D_DATA
        lda     >D_DATA
        lda     >D_DATA
        lda     >D_DATA
        lda     >D_DATA
        lda     >D_DATA
        lda     >D_DATA
        lda     >D_DATA
        lda     >D_DATA
        lda     >D_DATA
        lda     >D_DATA
        lda     >D_DATA
        lda     >D_DATA
        leay    -1,y
        bne     sq8
        puls    cc,pc

* the 256 bytes at X to the card (X advanced by 256)
putq    pshs    cc
        orcc    #$50
        ldy     #256
        tst     >_ide_mode
        bne     pq8
pq16    lda     1,x                     words: the high byte to the latch first, then the low byte to the data register (the Glenside order [?]; only used when the
        sta     >D_LATCH                card has refused 8 bit transfers)
        lda     ,x++
        sta     >D_DATA
        leay    -2,y
        bne     pq16
        puls    cc,pc
pq8     lda     ,x+
        sta     >D_DATA
        leay    -1,y
        bne     pq8
        puls    cc,pc

* 256 zero bytes to the card (the unused half of a sector)
zeroq   pshs    cc
        orcc    #$50
        ldy     #256
        clra
        tst     >_ide_mode
        bne     zq8
zq16    sta     >D_LATCH
        sta     >D_DATA
        leay    -2,y
        bne     zq16
        puls    cc,pc
zq8     sta     >D_DATA
        leay    -1,y
        bne     zq8
        puls    cc,pc
        ENDSECTION
