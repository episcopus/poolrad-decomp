* disk.asm: DSKCON through Disk BASIC's ROM, called from the all-RAM world of the engine (research 03 4.3).
* The engine runs in all-RAM mode with its own windows in slots 4..7. Disk BASIC lives in ROM above $8000, so for the
* length of one sector read this routine switches the machine back to BASIC's view: ROM mode, slots 4..7 (of the
* task the CPU is in, the engine's) on the blocks BASIC had ($3C..$3F; in ROM mode they show the Color, Extended and
* Disk BASIC images and the I/O page),
* 0.89 MHz (DynoSprite does the same for every controller), then restores the engine's windows and 1.79 MHz.
* Slots 0..3 are the same in both views ($38..$3B), so the code, the stack and the sector buffer stay where they are.
* Disk BASIC's RAM ($0000..$0DFF: the RAM vectors at $0100, its NMI hook at $0109, disk variables from $0600) must be
* untouched: the NMI that ends each sector transfer goes through it. Interrupts stay masked.
        INCLUDE mailbox.inc

DSKCON_VEC      EQU     $C004
DC_OPC          EQU     $EA
DC_DRV          EQU     $EB
DC_TRK          EQU     $EC
DC_SEC          EQU     $ED
DC_BUF          EQU     $EE
DC_STA          EQU     $F0
DRGRAM          EQU     $0986           Disk BASIC's copy of the DSKREG latch

        SECTION code
        EXPORT  _dsk_read
        EXPORT  _dsk_read_to
        EXPORT  _dsk_motor_off
        EXPORT  _dsk_buf

* u8 dsk_read(u8 drive, u8 track, u8 sector): reads one 256-byte sector into dsk_buf; returns DCSTA (0 = ok)
_dsk_read
        pshs    cc,u,y                  the caller's interrupt mask comes back at the end
        ldd     #_dsk_buf
        bra     dsk_go
* u8 dsk_read_to(u8 drive, u8 track, u8 sector, u8 *buf): the same into buf, which must be below $8000
_dsk_read_to
        pshs    cc,u,y
        ldd     13,s
dsk_go  orcc    #$50
        std     DC_BUF
        lda     #2                      DSKCON op 2: read sector
        sta     DC_OPC
        lda     8,s                     drive
        sta     DC_DRV
        lda     10,s                    track
        sta     DC_TRK
        lda     12,s                    sector
        sta     DC_SEC
        clr     DC_STA
        ldx     #$FFA4                  the registers of slots 4..7 of the task the CPU is in: DSKCON needs BASIC's blocks there
        tst     FC_TASK
        beq     @t0
        ldx     #$FFAC
@t0     ldy     ,x                      what they hold now, to put back
        ldu     2,x
        pshs    y,u
        ldd     #$3C3D                  BASIC's blocks for slots 4 and 5
        sta     ,x
        stb     1,x
        ldd     #$3E3F
        sta     2,x
        stb     3,x
        sta     $FFDE                   ROM mode
        sta     $FFD8                   0.89 MHz
        jsr     [DSKCON_VEC]
        sta     $FFD9                   1.79 MHz
        sta     $FFDF                   all-RAM mode
        ldx     #$FFA4
        tst     FC_TASK
        beq     @t0b
        ldx     #$FFAC
@t0b    puls    y,u
        sty     ,x
        stu     2,x
        ldb     DC_STA
        clra
        puls    cc,u,y,pc

* void dsk_motor_off(void): IRQ is off, so Disk BASIC's motor timeout never runs
_dsk_motor_off
        clr     $FF40
        clr     DRGRAM
        rts

_dsk_buf
        RMB     256
        ENDSECTION
