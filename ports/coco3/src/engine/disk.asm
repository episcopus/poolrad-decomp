* disk.asm: DSKCON through Disk BASIC's ROM, called from the all-RAM world of the engine (research 03 4.3).
* The engine runs in all-RAM mode with its own windows in slots 4..7. Disk BASIC lives in ROM above $8000, so for the
* length of one sector read this routine switches the machine back to BASIC's view: ROM mode, slots 4..7 on the
* blocks BASIC had ($3C..$3F; in ROM mode they show the Color, Extended and Disk BASIC images and the I/O page),
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
        EXPORT  _dsk_motor_off
        EXPORT  _dsk_buf

* u8 dsk_read(u8 drive, u8 track, u8 sector): reads one 256-byte sector into dsk_buf; returns DCSTA (0 = ok)
_dsk_read
        pshs    u,y
        orcc    #$50
        lda     #2                      DSKCON op 2: read sector
        sta     DC_OPC
        lda     7,s                     drive
        sta     DC_DRV
        lda     9,s                     track
        sta     DC_TRK
        lda     11,s                    sector
        sta     DC_SEC
        ldd     #_dsk_buf
        std     DC_BUF
        clr     DC_STA
        ldd     #$3C3D                  BASIC's blocks for slots 4 and 5
        sta     $FFA4
        stb     $FFA5
        ldd     #$3E3F
        sta     $FFA6
        stb     $FFA7
        sta     $FFDE                   ROM mode
        sta     $FFD8                   0.89 MHz
        jsr     [DSKCON_VEC]
        sta     $FFD9                   1.79 MHz
        sta     $FFDF                   all-RAM mode
        lda     MMU_SH
        sta     $FFA4
        lda     MMU_SH+1
        sta     $FFA5
        lda     MMU_SH+2
        sta     $FFA6
        lda     MMU_SH+3
        sta     $FFA7
        ldb     DC_STA
        clra
        puls    u,y,pc

* void dsk_motor_off(void): IRQ is off, so Disk BASIC's motor timeout never runs
_dsk_motor_off
        clr     $FF40
        clr     DRGRAM
        rts

_dsk_buf
        RMB     256
        ENDSECTION
