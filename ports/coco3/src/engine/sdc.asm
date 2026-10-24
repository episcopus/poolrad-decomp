* sdc.asm: one sector through the CoCo SDC's command mode (step 8.10b), the card's own logical sector interface, which Disk BASIC's
* DSKCON does not reach for images above the floppy sizes. The registers (NitrOS-9's defs/cocosdc.d, the CoCo SDC User Guide):
*   $FF40 control latch: $43 turns command mode on, 0 off      $FF48 command (write) / status (read: bit 0 busy, bit 1 ready, bit 7 failed)
*   $FF49 the sector number's bits 23..16, $FF4A:$FF4B bits 15..0 (and, in the transfer, the two data registers: a word read or written at
*   $FF4A moves two bytes)    command $80 + drive reads a sector, $A0 + drive writes one
* The sector is between the card and dsk_buf; interrupts stay masked for the length of the call (about 1 ms of transfer).
        INCLUDE mailbox.inc
        SECTION code
        IMPORT  _dsk_buf
        EXPORT  _sdc_xfer

* u8 sdc_xfer(u8 cmd, u8 lsn_hi, u16 lsn_lo): 0 = ok, else the status ($81: it never came ready)
_sdc_xfer
        pshs    cc,u,y
        orcc    #$50
        ldy     #$FF4A
        lda     #$43
        sta     $FF40                   command mode on
        bsr     idle                    (a card still busy with the last command)
        bcs     out
        ldb     10,s
        stb     -1,y                    sector bits 23..16
        ldx     11,s
        stx     ,y                      bits 15..0
        lda     8,s
        sta     $FF48                   the command
        bsr     ready                   data is ready (or the command failed)
        bcs     out
        ldx     #_dsk_buf
        lda     8,s
        bita    #$20
        bne     wr
        ldb     #128
rl      ldu     ,y                      two bytes at a time
        stu     ,x++
        decb
        bne     rl
        bra     fin
wr      ldb     #128
wl      ldu     ,x++
        stu     ,y
        decb
        bne     wl
fin     bsr     idle                    the card is done
out     tfr     cc,a                    (CLR clears the carry: the verdict is kept in A)
        clr     $FF40                   command mode off
        anda    #1
        beq     ok
        clra                            failed: B is the status
        puls    cc,u,y,pc
ok      clra
        clrb
        puls    cc,u,y,pc

* not busy: carry clear; failed or timed out: carry set, B = the status
idle    ldx     #0
il      ldb     $FF48
        bmi     bad
        lsrb
        bcc     good
        leax    -1,x
        bne     il
        ldb     #$81
bad     orcc    #1
        rts
good    clrb
        andcc   #$FE
        rts

* ready for the transfer: carry clear; failed, finished without data or timed out: carry set, B = the status
ready   ldx     #0
rl2     ldb     $FF48
        bmi     bad
        bitb    #2
        bne     good
        bitb    #1
        beq     nodata
        leax    -1,x
        bne     rl2
        ldb     #$81
        bra     bad
nodata  ldb     #$82
        bra     bad
        ENDSECTION
