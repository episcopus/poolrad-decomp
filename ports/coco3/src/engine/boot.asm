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
        EXPORT  _eng_init0

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
        sta     >_eng_init0
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
*       task 1, the engine's address space: slots 0..3 as task 0, 4 and 5 its own windows, 6 and 7 as the game's data
*       windows (mmu_set keeps both tasks equal there). Programs start in task 1 (the engine tests are the engine); the
*       game leaves it (eng_leave) and enters it only for the length of an engine call.
        ldd     #$3839
        std     $FFA8
        ldd     #$3A3B
        std     $FFAA
        ldd     #$3C3D
        std     $FFAC
        ldd     #$3E3F
        std     $FFAE
        lda     #1
        sta     FC_TASK
        sta     $FF91
        lbsr    _load_banks             copy staged bank images into their physical blocks
        lbra    program_start


* void mb_hold(void): the test harness looks at the screen. Maps the screen blocks (physical $00..$03) into slots 2..5
* ($4000..$BFFF), counts a checkpoint, waits for the harness to set MB_ACK (MAME's Lua script does; without a harness
* it gives up after about a second) and maps the slots back. It lives in slot 1 (this section) so that it keeps running
* while the slots it is called from are away; the registers of slots 2 to 5 (of the current task) come back as they were.
        EXPORT  _mb_hold
_mb_hold
        pshs    u,y
        ldy     #$FFA2                  the registers of slots 2..5 of the task the CPU is in
        tst     FC_TASK
        beq     @t0
        ldy     #$FFAA
@t0     ldd     ,y                      what they hold now (the low 6 bits read back)
        pshs    d
        ldd     2,y
        pshs    d
        clr     MB_ACK
        lda     #0
        sta     ,y
        inca
        sta     1,y
        inca
        sta     2,y
        inca
        sta     3,y
        inc     MB_CHECKPOINT
        ldx     #0
@wait   tst     MB_ACK
        bne     @go
        leax    -1,x
        bne     @wait
@go     clr     MB_ACK
        puls    d
        std     2,y
        puls    d
        std     ,y
        puls    u,y,pc

        ENDSECTION

        SECTION bss
_eng_init0      RMB     1               the value last written to GIME $FF90 (a write only register), for irq_start and gfx_init
        ENDSECTION
