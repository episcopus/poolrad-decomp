* boot.asm: entry point of every CoCo 3 build in this port. LOADM/EXEC (or XRoar -run)
* jumps here with Disk BASIC still in charge; this code takes the machine over:
* interrupts off, PIA interrupt sources off, all-RAM mode, 1.79 MHz, GIME in CoCo 3
* mode with the MMU on, stack and engine variables set, mailbox cleared.
* It then falls into CMOC's program_start (INILIB, main). Assemble with --6809.

        INCLUDE mailbox.inc

        SECTION boot
        EXPORT  boot
        IMPORT  program_start
        IMPORT  _load_banks

boot
        orcc    #$50                    mask IRQ and FIRQ
        clra
        tfr     a,dp                    DP = 0
        lda     $FF01                   PIA0 CA1 (HSYNC) interrupt off
        anda    #$FE
        sta     $FF01
        lda     $FF03                   PIA0 CB1 (VSYNC, 60 Hz) interrupt off
        anda    #$FE
        sta     $FF03
        lda     $FF21                   PIA1 CA1 off
        anda    #$FE
        sta     $FF21
        lda     $FF23                   PIA1 CB1 (cartridge FIRQ) off
        anda    #$FE
        sta     $FF23
        lda     $FF00                   clear pending PIA flags
        lda     $FF02
        lda     $FF20
        lda     $FF22
        lda     $FF92                   acknowledge GIME interrupts
        lda     $FF93
        clr     $FF92                   GIME interrupt sources off
        clr     $FF93
        sta     $FFDF                   SAM: all-RAM mode (the value written is ignored)
        sta     $FFD9                   SAM: 1.79 MHz
        lda     #$CC                    GIME: CoCo-compatible video (BASIC's text screen stays
*                                       valid for the demo), MMU on, $FE00 constant page
        sta     $FF90
        clr     $FF91                   MMU task 0
        lds     #SYSSTK_TOP
        ldx     #MB_BASE                clear the mailbox
        ldb     #MB_SIZE
@clr    clr     ,x+
        decb
        bne     @clr
        ldd     #$5052                  "PR"
        std     MB_MAGIC
        ldd     #$4144                  "AD"
        std     MB_MAGIC+2
        clr     FC_CURBANK
        ldd     #BANKSTK_TOP
        std     FC_BSPTR
        lbsr    _load_banks             copy staged bank images into their physical blocks
        lbra    program_start


* void mb_hold(void): the test harness looks at the screen. Maps the screen blocks (physical $00..$03) into slots 2..5
* ($4000..$BFFF), counts a checkpoint, waits for the harness to set MB_ACK (MAME's Lua script does; without a harness
* it gives up after about a second) and maps the slots back. It lives in slot 1 (this section) so that it keeps running
* while the slots it is called from are away; slots 2 and 3 return to BASIC's blocks, 4 and 5 to the shadow.
        EXPORT  _mb_hold
_mb_hold
        pshs    u,y
        clr     MB_ACK
        lda     #0
        sta     $FFA2
        inca
        sta     $FFA3
        inca
        sta     $FFA4
        inca
        sta     $FFA5
        inc     MB_CHECKPOINT
        ldx     #0
@wait   tst     MB_ACK
        bne     @go
        leax    -1,x
        bne     @wait
@go     clr     MB_ACK
        lda     #$3A
        sta     $FFA2
        inca
        sta     $FFA3
        lda     MMU_SH
        sta     $FFA4
        lda     MMU_SH+1
        sta     $FFA5
        puls    u,y,pc

        ENDSECTION
