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

        ENDSECTION
