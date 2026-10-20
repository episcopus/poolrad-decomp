* snd.asm: the hardware layer of the sound driver (step 8.8): the PC speaker's square wave on the CoCo's 6 bit DAC, and the driver's clock.
*
* The GIME timer interrupts (FIRQ) once for every part of a half period of the tone (snd_k of them make a half period when it is longer
* than the timer's 12 bits). Each interrupt counts itself (snd_n: the pump, src/snd/snd_core.c, turns the count into time), toggles the
* DAC (every interrupt in ISR_A, every snd_k-th in ISR_B) and loads a new reload if the main line left one (snd_new_hi/lo: the tone
* changes at an interrupt, so no interval is cut short). It is ~70 cycles; a tone of 1 kHz costs 4 % of the CPU.
*
* WHERE. The interrupt can arrive in either MMU task and with any bank mapped, so its code must be in memory both tasks see and no bank
* moves: the constant page $FE00..$FEEF, which the GIME maps to the same RAM whatever the MMU holds. Its image is assembled here, in the
* engine, with relative branches only (the code runs from $FE00, not from where the linker put it) and snd_install copies it at the
* start (gameboot.c, the engine tests). ISR_A is at $FE00, ISR_B at $FE3B, take at $FE81, setvec at $FE9F (src/snd/snd_core.c has the addresses; the check below stops the assembly if the code moved). The variables are in the shared data
* ($0700..$085F: the 28 bytes after the keyboard's; the event log is at $0860).
*
* The vector: snd_begin points the FIRQ vector ($FFF6 and the stub's operand $FEF5) at one of them and snd_end gives the engine's back.
* The sound uses no memory of the game's and no register it does not save.
        INCLUDE mailbox.inc

        SECTION shared2
        EXPORT  _snd_n
        EXPORT  _snd_thresh
        EXPORT  _snd_state
        EXPORT  _snd_k
        EXPORT  _snd_kcnt
        EXPORT  _snd_dac
        EXPORT  _snd_flip
        EXPORT  _snd_new_hi
        EXPORT  _snd_new_lo
        EXPORT  _tins
        EXPORT  _snd_cn
        EXPORT  _snd_tn
        EXPORT  _snd_tc
_snd_n          RMB     2               interrupts counted since the pump last took them
_snd_thresh     RMB     2               the pump has work when snd_n reaches this (0: the sound is off)
_snd_state      RMB     2               the driver's block in the mapped heap (src/snd/snd.h)
_snd_k          RMB     1               interrupts per toggle (ISR_B)
_snd_kcnt       RMB     1               ... countdown
_snd_dac        RMB     1               the DAC value now
_snd_flip       RMB     1               xor that toggles it (0: silence)
_snd_new_hi     RMB     1               bit 7: a new reload is waiting; bits 3..0 its high nibble
_snd_new_lo     RMB     1               its low byte
_tins           RMB     1               $20 while the timer runs on the fast clock (279 ns), else 0: every write of $FF91 is OR'ed with it
_snd_cn         RMB     2               snd_n at the moment the interrupt loaded a new reload (the interrupt that ended the old interval); 0: none since the pump looked
_snd_tn         RMB     2               what take found in snd_n ...
_snd_tc         RMB     2               ... and in snd_cn
        ENDSECTION

        SECTION code
        EXPORT  _snd_install
        EXPORT  _snd_blob
        EXPORT  _snd_blob_end

* void snd_install(void): copy the interrupt code to $FE00
_snd_install
        ldx     #_snd_blob
        ldy     #$FE00
@c      ldd     ,x++
        std     ,y++
        cmpx    #_snd_blob_end
        blo     @c
        rts

_snd_blob
* ISR_A, at $FE00: one interrupt, one toggle
isr_a   pshs    a
        lda     $FF93                   acknowledge
        inc     >_snd_n+1
        bne     @n1
        inc     >_snd_n
@n1     lda     >_snd_dac
        eora    >_snd_flip
        sta     >_snd_dac
        sta     $FF20
        lda     >_snd_new_hi
        beq     @out
        anda    #$0F
        sta     $FF94                   the reload: the high nibble first, the low byte starts the interval
        lda     >_snd_new_lo
        sta     $FF95
        clr     >_snd_new_hi
        lda     >_snd_n                 the interrupts up to this one ended intervals of the old length: the pump needs to know how many
        sta     >_snd_cn
        lda     >_snd_n+1
        sta     >_snd_cn+1
@out    puls    a
        rti

* ISR_B, at $FE3B: snd_k interrupts per toggle
isr_b   pshs    a
        lda     $FF93
        inc     >_snd_n+1
        bne     @n1
        inc     >_snd_n
@n1     dec     >_snd_kcnt
        bne     @chk
        lda     >_snd_k
        sta     >_snd_kcnt
        lda     >_snd_dac
        eora    >_snd_flip
        sta     >_snd_dac
        sta     $FF20
@chk    lda     >_snd_new_hi
        beq     @out
        anda    #$0F
        sta     $FF94
        lda     >_snd_new_lo
        sta     $FF95
        clr     >_snd_new_hi
        lda     >_snd_n
        sta     >_snd_cn
        lda     >_snd_n+1
        sta     >_snd_cn+1
@out    puls    a
        rti

* void take(void), at $FE81: snd_n and snd_cn move to snd_tn and snd_tc, and are zero, with the FIRQ masked
take    pshs    cc
        orcc    #$40
        ldd     >_snd_n
        std     >_snd_tn
        clr     >_snd_n
        clr     >_snd_n+1
        ldd     >_snd_cn
        std     >_snd_tc
        clr     >_snd_cn
        clr     >_snd_cn+1
        puls    cc,pc

* void setvec(u16 vector), at $FE9F: the FIRQ vector ($FFF6, and the operand of the JMP stub the constant page holds), the interrupt held off for the two stores
setvec  pshs    cc
        orcc    #$40
        ldd     3,s                     (the argument: the saved CC, the return address)
        std     $FFF6
        std     $FEF5
        puls    cc,pc
_snd_blob_end
        FCB     0,0
        IFNE    (isr_b-isr_a)-$3B
        ERROR   ISR_B is not at $FE3B: change SND_ISR_B in src/snd/snd_core.c and the notes
        ENDC
        IFNE    (take-isr_a)-$81
        ERROR   take is not at $FE81: change SND_TAKE in src/snd/snd_core.c and the notes
        ENDC
        IFNE    (setvec-isr_a)-$9F
        ERROR   setvec is not at $FE9F: change SND_SETVEC in src/snd/snd_core.c and the notes
        ENDC
        ENDSECTION
