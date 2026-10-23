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
        EXPORT  _cpu6309
        EXPORT  _spl_cnt
        EXPORT  _spl_pos

boot
        orcc    #$50                    mask IRQ and FIRQ
        ifndef  ENG_TEST
*       Step 8.9i: is this a CoCo 3 with 512 KB? With BASIC's own map still in place (the screen shows what LOADM left in the text screen,
*       which the splash then replaces), the MMU's slot 4 ($8000, RAM in the all-RAM mode) is pointed at four blocks 128 KB apart and a byte
*       written to each: on a CoCo 1 or 2 (no MMU) every block is the same byte, on a CoCo 3 with 128 KB the blocks repeat every 16. If they
*       are not four, BASIC's map and screen are put back, a message is printed through BASIC's own output routine, and boot returns to BASIC.
        sta     $FFDF                   all-RAM mode (the value written is ignored)
        ldx     #t_512
        ldb     #4
        lbsr    probe
        lbne    fail
        ldb     #$3C
        stb     $FFA4                   BASIC's block for slot 4 again
        ldy     #l_mem                  the splash is on the screen already (LOADM drew it: tools/stripbin.py): what has been checked
        lbsr    txt
        endc
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
        ldx     #$0700                  clear the shared data ($0700..$08FF: not in POOL.BIN, where Disk BASIC's own buffers are
@sh     clr     ,x+                     until LOADM is done), then copy their image from SHARED_IMG
        cmpx    #$0900
        bne     @sh
        ldx     #SHARED_IMG
        ldy     #$0700
        ldd     ,x++                    the length of the image in bytes (even), then its data
        leau    d,y
        pshs    u                       the end of the copy
@cp     ldd     ,x++
        std     ,y++
        cmpy    ,s
        bne     @cp
        leas    2,s
        lda     #$CC
        sta     >_eng_init0             (the shadow of $FF90: after the copy, the image holds zero)
*       A Hitachi 6309 runs in native mode (step 8.9h): the same instruction set in fewer cycles (the inherent, direct and extended
*       instructions, the calls and the pushes one cycle less each; 7 to 9 % of the busy time of every session, 13 % of a step in the 3D view),
*       two bytes more of stack for an interrupt (E and F; the handlers only RTI), the FIRQ frame as before. The test is the reference's:
*       TFR W,Y gives Y = W on a 6309 (W is 0 after a reset) and $FFFF on a 6809, which has no W; a 6309 whose W held $FFFF would stay in
*       the compatible mode, which is safe. _cpu6309 says which it was (for the 6309 kernels to come).
        ldy     #0
        fcb     $1F,$62                 TFR W,Y
        cmpy    #$FFFF
        beq     @is6809
        fcb     $11,$3D,$01             LDMD #1: native mode (NM = 1; FM stays 0)
        lda     #1
        sta     >_cpu6309
@is6809
        ifndef  ENG_TEST
        lbsr    spl_cpu                 the lines for the CPU, the storage and the progress bar
        endc
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
        lbsr    _load_banks             copy staged bank images into their physical blocks (task 0's windows)
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
        lbra    program_start

        ifndef  ENG_TEST
SPL             EQU     $0400           the splash screen: BASIC's own 32 by 16 text screen (tools/stripbin.py draws it while LOADM loads)
SPL_BAR         EQU     SPL+10*32+2     the 28 cells of the progress bar
SPL_STEP        EQU     10              sectors read for one more cell of the bar's second half (14 cells): the engine reads 148 sectors until the game's first screen

* probe: X -> pairs (block, byte), B pairs. Each block is mapped into slot 4 and its byte written at $8000, then every block is
* read back; Z is set when every one holds its own byte.
probe   pshs    b,x
        ldy     #$8000
        ldb     ,s
        ldx     1,s
@w      lda     ,x+
        sta     $FFA4
        lda     ,x+
        sta     ,y
        decb
        bne     @w
        ldb     ,s
        ldx     1,s
@r      lda     ,x+
        sta     $FFA4
        lda     ,x+
        cmpa    ,y
        bne     @x
        decb
        bne     @r
@x      puls    b,x,pc

t_512   fcb     $00,$21,$10,$41,$20,$61,$30,$81     four blocks 128 KB apart: a 512 KB machine has all of them

fail    ldb     #$3C
        stb     $FFA4
        sta     $FFDE                   ROM mode: BASIC again
        clr     <$6F                    the device is the screen
        ldx     #$0400                  clear the text screen (green blanks) and put BASIC's cursor ($88) at its top
        lda     #$60
@k      sta     ,x+
        cmpx    #$0600
        bne     @k
        ldx     #$0400
        stx     <$88
        ldx     #m_msg
@l      lda     ,x+
        beq     @d
        jsr     [$A002]
        bra     @l
@d      lda     #13
        jsr     [$A002]
        andcc   #$AF
        rts

m_msg   fcc     "POOL OF RADIANCE NEEDS A COCO 3 WITH 512K RAM"
        fcb     0

* txt: Y -> a list of (screen address, text ending with 0) and a word 0 at its end; the text goes to the screen as inverse video codes
txt     ldx     ,y++
        beq     @e
@c      lda     ,y+
        beq     txt
        cmpa    #$40
        blo     @s
        suba    #$40
@s      sta     ,x+
        bra     @c
@e      rts

spl_cpu ldy     #l_6809
        tst     >_cpu6309
        beq     @p
        ldy     #l_6309
@p      bsr     txt
        ldy     #l_dev
        bsr     txt
        lda     #14                     the first 14 cells of the bar were LOADM's (records of the file); the engine's reads are the other 14
        sta     >_spl_pos
        rts

* void splash_adv(void): a sector has been read: one more cell of the bar every SPL_STEP sectors
        EXPORT  _splash_adv
_splash_adv
        ldb     >_spl_pos
        bmi     @x                      $FF: the splash is gone
        inc     >_spl_cnt
        lda     >_spl_cnt
        cmpa    #SPL_STEP
        blo     @x
        clr     >_spl_cnt
        cmpb    #28
        bhs     @x
        ldx     #SPL_BAR
        abx
        lda     #$DF                    a cyan block (semigraphics colour 5)
        sta     ,x
        inc     >_spl_pos
@x      rts

* void splash_off(void): the game has its own screen
        EXPORT  _splash_off
_splash_off
        lda     #$FF
        sta     >_spl_pos
        rts

l_mem   fdb     SPL+4*32+2
        fcc     "COCO 3, 512K RAM: OK"
        fcb     0
        fdb     0
l_6809  fdb     SPL+5*32+2
        fcc     "CPU: 6809 (STOCK)"
        fcb     0
        fdb     0
l_6309  fdb     SPL+5*32+2
        fcc     "CPU: 6309 (HITACHI), NATIVE"
        fcb     0
        fdb     0
l_dev   fdb     SPL+6*32+2
        fcc     "STORAGE: DEV (MAME)"
        fcb     0
        fdb     0
        endc


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

        SECTION shared2
_eng_init0      RMB     1               the value last written to GIME $FF90 (a write only register), for irq_start and gfx_init
_spl_cnt       RMB     1               the sectors since the last cell of the progress bar
_spl_pos        RMB     1               the cells of the bar drawn; $FF once the splash is gone (gfx_init)
_cpu6309        RMB     1               1 when the CPU is a 6309 and boot put it in native mode, else 0 (set after the image of the shared data is copied)
        ENDSECTION
