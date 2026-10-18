* irq.asm: the engine's interrupts: the 60 Hz frame clock, the keyboard scan that rides on it, and a fast tick.
*
*   IRQ   PIA0's CB1, the video's vertical sync (60 Hz NTSC), the CoCo's classic frame interrupt: counts the frame and
*         scans the keyboard matrix. Reading $FF02 acknowledges it. (The GIME's own vertical border interrupt,
*         $FF92 bit 3, is not used; it was not tried once the vectors were right.)
*   FIRQ  the GIME timer ($FF93 bit 5): counts a tick every reload + 2 units of 63.695 us (tick_start; XRoar: reload 64
*         gives 237.9 Hz, MAME about 1% slower). The game's sound driver will hang off it (the original's 237 Hz).
* The vectors: see irq_start. Both handlers use extended addressing only, so they do not depend on DP, and leave every
* register as they found it (IRQ's RTI restores everything; FIRQ saves D). dsk_read masks interrupts on entry and gives
* the caller's mask back; DSKCON itself lets the frame interrupt through between sectors, so the clock keeps time
* through a disk read (t_irq: 330 frames counted over 5.5 s of reading).
* Keyboard: PIA0 ($FF00 rows in, $FF02 columns out) scanned once a frame; a key counts when two consecutive scans agree
* (debounce), its code goes to a 16-entry queue (kbd_get).
* All of it, code, tables and variables, is in the section `shared` ($1060..$13FF, below the mailbox's neighbour): the
* frame interrupt can arrive in either MMU task, and both see slot 0 the same.
        INCLUDE mailbox.inc

        SECTION shared
        EXPORT  _irq_start
        EXPORT  _irq_stop
        EXPORT  _frame_count
        EXPORT  _tick_start
        EXPORT  _tick_stop
        EXPORT  _tick_count
        EXPORT  _kbd_get
        EXPORT  _kbd_mods
        EXPORT  _game_launch
        IMPORT  _eng_init0

* void irq_start(void): vectors, GIME sources on, interrupts unmasked
_irq_start
        orcc    #$50
        ldd     #irq_isr
        std     $FFF8                   the vectors where the CPU fetches them with all RAM mapped (RAM at the top of
        std     $FEF8                   the last block) and, as Disk BASIC's ROM has them, through the stubs in the
        ldd     #firq_isr               constant page: $FEF7 (IRQ) and $FEF4 (FIRQ) hold three bytes, here a JMP
        std     $FFF6
        std     $FEF5
        lda     #$7E
        sta     $FEF7
        sta     $FEF4
        clra
        clrb
        std     >frames
        std     >ticks
        lda     $FF92                   acknowledge anything pending
        lda     $FF93
        lda     $FF02                   clear the vertical sync flag
        lda     $FF03
        ora     #$01
        sta     $FF03                   PIA0 CB1 (vertical sync, 60 Hz) interrupt on
        lda     >_eng_init0
        ora     #$30                    GIME: IRQ and FIRQ enabled
        sta     >_eng_init0
        sta     $FF90
        andcc   #$AF
        rts

* void irq_stop(void)
_irq_stop
        orcc    #$50
        lda     $FF03
        anda    #$FE
        sta     $FF03
        clr     $FF92
        clr     $FF93
        lda     >_eng_init0
        anda    #$CF
        sta     >_eng_init0
        sta     $FF90
        rts

* u16 frame_count(void): frames counted since irq_start (wraps at 65536)
_frame_count
        ldd     >frames
        rts

* void tick_start(u16 reload): FIRQ every reload * 63.695 us (reload 1..4095)
_tick_start
        ldd     2,s
        sta     $FF94                   high nibble first, the low byte starts the timer
        stb     $FF95
        lda     #$20
        sta     $FF93
        rts

_tick_stop
        clr     $FF93
        rts

* u16 tick_count(void)
_tick_count
        ldd     >ticks
        rts

* u8 kbd_get(void): the next key code from the queue, 0 when there is none
_kbd_get
        ldb     >kq_head
        cmpb    >kq_tail
        beq     @none
        ldx     #kq
        abx
        lda     ,x
        incb
        andb    #15
        stb     >kq_head
        tfr     a,b
        clra
        rts
@none   clra
        clrb
        rts

* u8 kbd_mods(void): bit 0 shift, bit 1 control, bit 2 alt, as held now
_kbd_mods
        clrb
        lda     >kheld+7
        bita    #$40
        beq     @c
        orb     #1
@c      lda     >kheld+4
        bita    #$40
        beq     @a
        orb     #2
@a      lda     >kheld+3
        bita    #$40
        beq     @e
        orb     #4
@e      clra
        rts

* void game_launch(void): the engine hands the machine to the game. It is here, in memory both tasks see, because the next
* instruction after the switch is fetched from the game's slot 1, not the engine's.
_game_launch
        orcc    #$50
        clr     FC_TASK
        clr     $FF91
        lds     #SYSSTK_TOP
        jmp     $2000

irq_isr
        lda     $FF03                   bit 7: the vertical sync flag
        bpl     @out
        lda     $FF02                   reading the data register clears it
        ldx     >frames
        leax    1,x
        stx     >frames
        bsr     kbd_tick
@out    rti

firq_isr
        pshs    d
        lda     $FF93                   acknowledge
        ldd     >ticks
        addd    #1
        std     >ticks
        puls    d
        rti

* One keyboard scan. kcur = this scan (a set bit: a pressed row), kprev = the last one, kheld = keys that have counted,
* knew = keys that counted for the first time now.
kbd_tick
        ldx     #kcur
        ldb     #$FE                    column 0 low
@col    stb     $FF02
        lda     $FF00
        coma                            a pressed key reads 0
        anda    #$7F
        sta     ,x+
        orcc    #1
        rolb                            next column
        cmpx    #kcur+8
        bne     @col
        lda     #$FF
        sta     $FF02
*       stable = cur & prev; new = stable & ~held; held = stable; prev = cur
        ldx     #0
@st     lda     kcur,x
        ldb     kprev,x
        sta     kprev,x
        andb    kcur,x
        lda     kheld,x
        coma
        stb     >kstab
        anda    >kstab
        sta     knew,x
        stb     kheld,x
        leax    1,x
        cmpx    #8
        bne     @st
*       a code for every new key
        ldx     #0
@em     lda     knew,x
        beq     @nx
        ldy     #0
@rw     lsra
        bcc     @nr
        pshs    a,x,y
        tfr     x,d
        stb     >kcol
        tfr     y,d
        lslb
        lslb
        lslb
        addb    >kcol                   key number = row * 8 + column
        ldx     #ktab
        lda     >kheld+7
        bita    #$40                    shift held?
        beq     @un
        ldx     #ktabs
@un     abx
        lda     ,x
        beq     @no
        ldx     #kq
        ldb     >kq_tail
        abx
        sta     ,x
        incb
        andb    #15
        cmpb    >kq_head
        beq     @no                     queue full: the key is lost
        stb     >kq_tail
@no     puls    a,x,y
@nr     leay    1,y
        tsta
        bne     @rw
@nx     leax    1,x
        cmpx    #8
        bne     @em
        rts

        ENDSECTION

        SECTION shared
frames          RMB     2
ticks           RMB     2
kcur            RMB     8
kprev           RMB     8
kheld           RMB     8
knew            RMB     8
kstab           RMB     1
kcol            RMB     1
kq_head         RMB     1
kq_tail         RMB     1
kq              RMB     16
        ENDSECTION

        SECTION shared
* key number = row * 8 + column: row = the PIA0 data bit that reads low, column = the strobed bit of $FF02
ktab    FCC     "@ABCDEFG"
        FCC     "HIJKLMNO"
        FCC     "PQRSTUVW"
        FCB     88,89,90,$81,$82,$83,$84,$20
        FCC     "01234567"
        FCC     "89:;,-./"
        FCB     13,$8C,27,0,0,$91,$92,0
ktabs   FCB     64,97,98,99,100,101,102,103
        FCC     "hijklmno"
        FCC     "pqrstuvw"
        FCB     120,121,122,$81,$82,$83,$84,$20
        FCB     0,33,34,35,36,37,38,39
        FCB     40,41,42,43,60,61,62,63
        FCB     13,$8C,27,0,0,$91,$92,0
        ENDSECTION
