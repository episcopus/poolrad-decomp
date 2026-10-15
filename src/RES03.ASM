; RES03.ASM: the sound driver of unit res03, the part of the unit that is not Pascal.
;
; The original linked this code with {$L} after the unit's initialisation part (08AE:01D7 to the end of
; the segment, 5,721 bytes). This file is its source, written from the original's bytes: tools/re/asm86.py
; assembles it into an object file that the rebuild (make rebuild) links in the same place, and the rebuilt
; program is byte for byte the original. It is also the specification of the driver for the C translation:
; everything it does is a handful of port writes (below) and a small interpreter, and the oracle's trace of
; those writes (tests/sessions/golden/sound-driver, tools/oracle/soundprobe.py) is the reference to meet.
; Evidence tags: [V] read in the code or confirmed by the oracle's trace, [I] inferred from the code.
;
; THE FRONT END is Pascal (src/RES03.PAS): PlaySound(n) calls SetSpeakerTune(n - 1) or SetTandyTune(n - 1)
; (the device of POOL.CFG line 2), SetSoundOutput(0 or 1), and StartSoundTimer / StopSoundTimer around a
; sound when the driver is not left running. Tune 0 is silence.
;
; THE DEVICES [V]
;   PC speaker   PIT channel 2: a 16-bit period written low then high to port 42h; port 61h bits 0 and 1
;                (timer gate, speaker data) are the gate. Channel 2 is put in mode 3 by the control word
;                0B6h written to port 43h at start.
;   Tandy chip   SN76489 at port 0C0h: a latch byte 1cctdddd (cc channel 0..3, t 0 tone / 1 attenuation,
;                dddd the low four bits) and, for a tone, a second byte 00dddddd with the high six bits.
;   Timer        PIT channel 0 reloaded with 5041 = 65536 / 13 (236.7 Hz, 13 times the BIOS rate) by
;                StartSoundTimer; TimerHandler is INT 08h; every 13th tick it chains to the BIOS handler
;                (SavedVector), so the BIOS clock keeps its 18.2 Hz. StopSoundTimer restores the vector
;                and writes 0FFFFh to channel 0, gates the speaker off and silences the chip (9Fh, 0BFh,
;                0DFh, 0FFh: attenuation 15 on the four channels).
;
; VOICES [V] Four per device (the table has room for eight records of 30h bytes, the stepper runs four).
;   A voice is a 30h byte record, offsets vXxx below. Each tick (TimerHandler -> SpeakerStep / TandyStep ->
;   StepVoice) it adds the pitch and level slopes, adds vibrato from a table, counts the event down and,
;   at zero, runs its stream (RunStream) until the stream waits again.
;   The speaker plays the first voice (0..3) that has a stream and a nonzero level; the Tandy chip plays
;   all four. Output period vOutput = vPitch + vibrato.
;
; THE STREAM LANGUAGE [V] (RunStream reads bytes at vStream; every shipped tune is made of these)
;   0FFh f w     set the word of the current voice at offset f to w. Field 0 is the event duration:
;                 writing it ends the burst (the voice waits w ticks, then the stream goes on); w = 0
;                 there ends the voice (no stream, VoiceTune cleared).
;   0FEh f t     repeat: field f (26h or 28h) is a counter; if it is 0 jump to t (forever), else decrement it and
;                 jump to t unless it became 0.
;   0FDh o       the current voice becomes the record at VoiceBase + o, then it is cleared (as 0FAh).
;   0FAh         clear the current voice's slopes, envelope and vibrato (fields 04h..24h except 0Eh, 14h).
;   0FCh t / 0FBh  call t (one level, ReturnPtr) / return.
;   other        a note event of three bytes: voice<<5 and flags, note (bit 7: last note of the chord),
;                 duration; its pitch comes from NoteTable[note mod 12] >> (note div 12), transposed by
;                 vTranspose. No shipped tune uses it (the dead path is NextNote..NoteLast).
;
; ENVELOPE tables (the Envelope... blocks) are pairs (slope, count): the level slope and for how many ticks;
; a count of 0FFFFh sets the level to the first word instead. VIBRATO tables are signed bytes
; (SineTable 256 entries, SquareTable 32, NoiseTable 512), indexed by vVibPos / 16, scaled by vVibDepth.
;
; FOR THE C BUILD: `python tools/re/asm86.py src/RES03.ASM --binary sound.bin --map` writes the assembled
; bytes with every pointer as an offset into the file (the tune tables, streams, envelopes and note tables are
; plain data) and lists the label offsets; the code below is the algorithm to port, and tests/sessions/golden/
; sound-driver (make sound-golden) is what the port must reproduce, in sequence.
;
; OBJECT FORMAT: one code segment, offsets from the start of this file; the linker places it after the
; unit's own code (at 01D7h in the original) and fixes every label reference. CODESEG is the unit's
; segment: the driver runs with DS = CS and keeps its variables beside its code.

; voice record offsets
vCount      equ 00h             ; ticks left in the current event; the stepper skips a voice at 0
vStream     equ 02h             ; the voice's stream pointer, 0 when it has none
vPitch      equ 04h             ; period before vibrato
vPitchStep  equ 06h             ; added to vPitch every tick (portamento)
vOutput     equ 08h             ; the period sent to the device
vLevel      equ 0Ah             ; level accumulator: speaker gate bits are its low two bits, Tandy attenuation
                                ; its high nibble inverted
vLevelStep  equ 0Ch             ; added to vLevel every tick
vTempo      equ 0Eh             ; multiplies note durations (the note event path)
vField10    equ 10h             ; set to 12 by four streams; no routine reads it [I]
vTranspose  equ 12h             ; added to a note number
vRelease    equ 14h             ; ticks until the release part of the envelope starts, 0 = never
vEnvelope   equ 16h             ; pointer to the envelope table
vEnvPos     equ 18h             ; offset of the next envelope entry
vEnvCount   equ 1Ah             ; ticks left of the current envelope entry
vVibrato    equ 1Ch             ; pointer to the vibrato table
vVibPos     equ 1Eh             ; position in it, in sixteenths of an entry
vVibStep    equ 20h             ; added to vVibPos every tick (0 = no vibrato)
vVibDepth   equ 22h             ; multiplier of the table value
vVibLength  equ 24h             ; vVibPos wraps at this
vLoopA      equ 26h             ; the repeat counters of the stream's 0FEh (a stream may use any field;
vLoopB      equ 28h             ; these two are the ones the shipped tunes use)

OpClear     equ 0FAh            ; stream opcodes
OpReturn    equ 0FBh
OpCall      equ 0FCh
OpVoice     equ 0FDh
OpLoop      equ 0FEh
OpSet       equ 0FFh

        PUBLIC  StartSoundTimer, StopSoundTimer, SetSpeakerTune, SetTandyTune, SetSoundOutput

; ---- variables (initial values as in the original image) ----
; Timer ticks left before the BIOS handler is chained; 13 per BIOS tick [V]
ChainCount:
        db      0Dh

; set while the steppers run: the handler does not nest [V]
InService:
        db      0

; voices left to step in the current pass [V]
VoicesLeft:
        db      0

; bytes per voice record (30h), the multiplier of the note path [V]
VoiceSize:
        db      30h

; Nonzero: ticks until the handler writes a fake "Run-time error 200" message and
; exits with code 255 (the program hung). No routine of this file sets it [I]
WatchdogTicks:
        dw      0

; the message in the BIOS write-string format with the top bit set on every byte (the
; handler masks it with 7Fh before printing): "Run-time  Error 200 at 0BAD:0038" CR LF [V]
WatchdogText:
        db      0D2h, 0F5h, 0EEh, 0ADh, 0F4h, 0E9h, 0EDh, 0E5h, 0A0h, 0A0h, 0C5h, 0F2h, 0F2h, 0EFh, 0F2h, 0A0h
        db      0B2h, 0B0h, 0B9h, 0A0h, 0E1h, 0F4h, 0A0h, 0B0h, 0C2h, 0C1h, 0C4h, 0BAh, 0B0h, 0B0h, 0B3h, 0B8h
        db      8Ah, 8Dh

; the tune number a SetXxxTune call stored, the stepper tests it for 0 [V]
CurrentTune:
        dw      0

; the voice whose stream is running (RunStream saves it for EventEnd) [V]
CurrentVoice:
        dw      0

; first voice record of the device being stepped [V]
VoiceBase:
        dw      0

; the 12-entry period table of the device being stepped [V]
NoteTable:
        dw      0

; the return address of the stream's one-level subroutine call [V]
ReturnPtr:
        dw      0

; per voice, the tune number that started it; 0 once its stream ended [V]
VoiceTune:
        db      0, 0, 0, 0

; 1: the speaker and the chip sound; PlaySound(0) clears it, PlaySound(1) sets it [V]
OutputOn:
        db      1

; unreferenced: 3,4 / 6,8 / 0Ch,10h / 18h,20h / 30h,40h [V]
UnusedTable:
        db      0, 0, 0, 2, 0, 3, 4, 0, 6, 8, 0, 0Ch, 10h, 0, 18h, 20h
        db      0, 30h, 40h

; stream opcodes 0FAh..0FFh -> handler [V]
OpcodeTable:
        dw      CmdClearVoice
        dw      CmdReturn
        dw      CmdCall
        dw      CmdSelectVoice
        dw      CmdLoop
        dw      CmdSetField

; 8 voice records of 30h bytes per device, all zero at start [V]
SpeakerVoices:
        db      384 dup (0)

; one octave of periods, 1,193,182 / frequency (C = 0x8E84 = 36484 is the lowest) [I]
SpeakerNotes:
        dw      8E84h
        dw      8684h
        dw      7EF7h
        dw      77D7h
        dw      714Fh
        dw      6AC4h
        dw      64C6h
        dw      5F1Eh
        dw      59C7h
        dw      54BDh
        dw      4FFCh
        dw      4B7Eh

; the voice the speaker plays this tick, 0 = none [V]
LoudestVoice:
        dw      0
TandyVoices:
        db      384 dup (0)

; one octave of Tandy periods (the chip takes the value >> 6) [I]
TandyNotes:
        dw      0FFC0h
        dw      0F140h
        dw      0E3C0h
        dw      0D700h
        dw      0CB40h
        dw      0BF80h
        dw      0B4C0h
        dw      0AA80h
        dw      0A100h
        dw      9800h
        dw      8F80h
        dw      8740h

; tune -> four stream pointers (voices 0..3) for the speaker: 21 rows of 4 words, row 0 silent [V]
SpeakerTunes:
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune1_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune2_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune3_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune4_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune5_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune6_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune7_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune8_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune9_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune10_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune11_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune12_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune13_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune14_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune15_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune16_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune17_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune18_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune19_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune0_0
        dw      SpkTune20_0
        dw      0
        dw      0
        dw      0

; the same for the Tandy chip [V]
TandyTunes:
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune1_0
        dw      TanTune1_1
        dw      TanTune1_2
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune2_3
        dw      TanTune3_0
        dw      TanTune3_1
        dw      TanTune3_2
        dw      TanTune0_0
        dw      TanTune4_0
        dw      TanTune0_0
        dw      TanTune4_2
        dw      TanTune4_3
        dw      TanTune5_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune6_2
        dw      TanTune6_3
        dw      TanTune7_0
        dw      TanTune7_1
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune8_3
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune9_3
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune10_2
        dw      TanTune10_3
        dw      TanTune11_0
        dw      TanTune11_1
        dw      TanTune11_2
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune12_2
        dw      TanTune12_3
        dw      TanTune13_0
        dw      TanTune0_0
        dw      TanTune13_2
        dw      TanTune13_3
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune14_2
        dw      TanTune14_3
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune15_2
        dw      TanTune15_3
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune16_2
        dw      TanTune16_3
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune17_2
        dw      TanTune0_0
        dw      TanTune18_0
        dw      TanTune0_0
        dw      TanTune18_2
        dw      TanTune18_3
        dw      TanTune19_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune20_0
        dw      TanTune0_0
        dw      TanTune0_0
        dw      TanTune0_0

; ---- vibrato tables: signed bytes ----
SineTable:
        db      0, 3, 6, 9, 0Ch, 0Fh, 12h, 15h, 18h, 1Bh, 1Eh, 21h, 24h, 27h, 2Ah, 2Dh
        db      30h, 33h, 36h, 39h, 3Bh, 3Eh, 41h, 43h, 46h, 49h, 4Bh, 4Eh, 50h, 52h, 55h, 57h
        db      59h, 5Bh, 5Eh, 60h, 62h, 64h, 66h, 67h, 69h, 6Bh, 6Ch, 6Eh, 70h, 71h, 72h, 74h
        db      75h, 76h, 77h, 78h, 79h, 7Ah, 7Bh, 7Bh, 7Ch, 7Dh, 7Dh, 7Eh, 7Eh, 7Eh, 7Eh, 7Eh
        db      7Eh, 7Eh, 7Eh, 7Eh, 7Eh, 7Eh, 7Dh, 7Dh, 7Ch, 7Bh, 7Bh, 7Ah, 79h, 78h, 77h, 76h
        db      75h, 74h, 72h, 71h, 70h, 6Eh, 6Ch, 6Bh, 69h, 67h, 66h, 64h, 62h, 60h, 5Eh, 5Bh
        db      59h, 57h, 55h, 52h, 50h, 4Eh, 4Bh, 49h, 46h, 43h, 41h, 3Eh, 3Bh, 39h, 36h, 33h
        db      30h, 2Dh, 2Ah, 27h, 24h, 21h, 1Eh, 1Bh, 18h, 15h, 12h, 0Fh, 0Ch, 9, 6, 3
        db      0, 0FDh, 0FAh, 0F7h, 0F4h, 0F1h, 0EEh, 0EBh, 0E8h, 0E5h, 0E2h, 0DFh, 0DCh, 0D9h, 0D6h, 0D3h
        db      0D0h, 0CDh, 0CAh, 0C7h, 0C5h, 0C2h, 0BFh, 0BDh, 0BAh, 0B7h, 0B5h, 0B2h, 0B0h, 0AEh, 0ABh, 0A9h
        db      0A7h, 0A5h, 0A2h, 0A0h, 9Eh, 9Ch, 9Ah, 99h, 97h, 95h, 94h, 92h, 90h, 8Fh, 8Eh, 8Ch
        db      8Bh, 8Ah, 89h, 88h, 87h, 86h, 85h, 85h, 84h, 83h, 83h, 82h, 82h, 82h, 82h, 82h
        db      82h, 82h, 82h, 82h, 82h, 82h, 83h, 83h, 84h, 85h, 85h, 86h, 87h, 88h, 89h, 8Ah
        db      8Bh, 8Ch, 8Eh, 8Fh, 90h, 92h, 94h, 95h, 97h, 99h, 9Ah, 9Ch, 9Eh, 0A0h, 0A2h, 0A5h
        db      0A7h, 0A9h, 0ABh, 0AEh, 0B0h, 0B2h, 0B5h, 0B7h, 0BAh, 0BDh, 0BFh, 0C2h, 0C5h, 0C7h, 0CAh, 0CDh
        db      0D0h, 0D3h, 0D6h, 0D9h, 0DCh, 0DFh, 0E2h, 0E5h, 0E8h, 0EBh, 0EEh, 0F1h, 0F4h, 0F7h, 0FAh, 0FDh
SquareTable:
        db      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
        db      78h, 78h, 78h, 78h, 78h, 78h, 78h, 78h, 78h, 78h, 78h, 78h, 78h, 78h, 78h, 78h

; 512 bytes (tune 1 uses it with length 2000h: 512 entries of 16 sixteenths) [V]
NoiseTable:
        db      29h, 23h, 0BEh, 84h, 0E1h, 6Ch, 0D6h, 0AEh, 52h, 90h, 49h, 0F1h, 0F1h, 0BBh, 0E9h, 0EBh
        db      0B3h, 0A6h, 0DBh, 3Ch, 87h, 0Ch, 3Eh, 99h, 24h, 5Eh, 0Dh, 1Ch, 6, 0B7h, 47h, 0DEh
        db      0B3h, 12h, 4Dh, 0C8h, 43h, 0BBh, 8Bh, 0A6h, 1Fh, 3, 5Ah, 7Dh, 9, 38h, 25h, 1Fh
        db      5Dh, 0D4h, 0CBh, 0FCh, 96h, 0F5h, 45h, 3Bh, 13h, 0Dh, 89h, 0Ah, 1Ch, 0DBh, 0AEh, 32h
        db      20h, 9Ah, 50h, 0EEh, 40h, 78h, 36h, 0FDh, 12h, 49h, 32h, 0F6h, 9Eh, 7Dh, 49h, 0DCh
        db      0ADh, 4Fh, 14h, 0F2h, 44h, 40h, 66h, 0D0h, 6Bh, 0C4h, 30h, 0B7h, 32h, 3Bh, 0A1h, 22h
        db      0F6h, 22h, 91h, 9Dh, 0E1h, 8Bh, 1Fh, 0DAh, 0B0h, 0CAh, 99h, 2, 0B9h, 72h, 9Dh, 49h
        db      2Ch, 80h, 7Eh, 0C5h, 99h, 0D5h, 0E9h, 80h, 0B2h, 0EAh, 0C9h, 0CCh, 53h, 0BFh, 67h, 0D6h
        db      0BFh, 14h, 0D6h, 7Eh, 2Dh, 0DCh, 8Eh, 66h, 83h, 0EFh, 57h, 49h, 61h, 0FFh, 69h, 8Fh
        db      61h, 0CDh, 0D1h, 1Eh, 9Dh, 9Ch, 16h, 72h, 72h, 0E6h, 1Dh, 0F0h, 84h, 4Fh, 4Ah, 77h
        db      2, 0D7h, 0E8h, 39h, 2Ch, 53h, 0CBh, 0C9h, 12h, 1Eh, 33h, 74h, 9Eh, 0Ch, 0F4h, 0D5h
        db      0D4h, 9Fh, 0D4h, 0A4h, 59h, 7Eh, 35h, 0CFh, 32h, 22h, 0F4h, 0CCh, 0CFh, 0D3h, 90h, 2Dh
        db      48h, 0D3h, 8Fh, 75h, 0E6h, 0D9h, 1Dh, 2Ah, 0E5h, 0C0h, 0F7h, 2Bh, 78h, 81h, 87h, 44h
        db      0Eh, 5Fh, 50h, 0, 0D4h, 61h, 8Dh, 0BEh, 7Bh, 5, 15h, 7, 3Bh, 33h, 82h, 1Fh
        db      18h, 70h, 92h, 0DAh, 64h, 54h, 0CEh, 0B1h, 85h, 3Eh, 69h, 15h, 0F8h, 46h, 6Ah, 4
        db      96h, 73h, 0Eh, 0D9h, 16h, 2Fh, 67h, 68h, 0D4h, 0F7h, 4Ah, 4Ah, 0D0h, 57h, 68h, 76h
        db      0FAh, 16h, 0BBh, 11h, 0ADh, 0AEh, 24h, 88h, 79h, 0FEh, 52h, 0DBh, 25h, 43h, 0E5h, 3Ch
        db      0F4h, 45h, 0D3h, 0D8h, 28h, 0CEh, 0Bh, 0F5h, 0C5h, 60h, 59h, 3Dh, 97h, 27h, 8Ah, 59h
        db      76h, 2Dh, 0D0h, 0C2h, 0C9h, 0CDh, 68h, 0D4h, 49h, 6Ah, 79h, 25h, 8, 61h, 40h, 14h
        db      0B1h, 3Bh, 6Ah, 0A5h, 11h, 28h, 0C1h, 8Ch, 0D6h, 0A9h, 0Bh, 87h, 97h, 8Ch, 2Fh, 0F1h
        db      15h, 1Dh, 9Ah, 95h, 0C1h, 9Bh, 0E1h, 0C0h, 7Eh, 0E9h, 0A8h, 9Ah, 0A7h, 86h, 0C2h, 0B5h
        db      54h, 0BFh, 9Ah, 0E7h, 0D9h, 23h, 0D1h, 55h, 90h, 38h, 28h, 0D1h, 0D9h, 6Ch, 0A1h, 66h
        db      5Eh, 4Eh, 0E1h, 30h, 9Ch, 0FEh, 0D9h, 71h, 9Fh, 0E2h, 0A5h, 0E2h, 0Ch, 9Bh, 0B4h, 47h
        db      65h, 38h, 2Ah, 46h, 89h, 0A9h, 82h, 79h, 7Ah, 76h, 78h, 0C2h, 63h, 0B1h, 26h, 0DFh
        db      0DAh, 29h, 6Dh, 3Eh, 62h, 0E0h, 96h, 12h, 34h, 0BFh, 39h, 0A6h, 3Fh, 89h, 5Eh, 0F1h
        db      6Dh, 0Eh, 0E3h, 6Ch, 28h, 0A1h, 1Eh, 20h, 1Dh, 0CBh, 0C2h, 3, 3Fh, 41h, 7, 84h
        db      0Fh, 14h, 5, 65h, 1Bh, 28h, 61h, 0C9h, 0C5h, 0E7h, 2Ch, 8Eh, 46h, 36h, 8, 0DCh
        db      0F3h, 0A8h, 8Dh, 0FEh, 0BEh, 0F2h, 0EBh, 71h, 0FFh, 0A0h, 0D0h, 3Bh, 75h, 6, 8Ch, 7Eh
        db      87h, 78h, 73h, 4Dh, 0D0h, 0BEh, 82h, 0BEh, 0DBh, 0C2h, 46h, 41h, 2Bh, 8Ch, 0FAh, 30h
        db      7Fh, 70h, 0F0h, 0A7h, 54h, 86h, 32h, 95h, 0AAh, 5Bh, 68h, 13h, 0Bh, 0E6h, 0FCh, 0F5h
        db      0CAh, 0BEh, 7Dh, 9Fh, 89h, 8Ah, 41h, 1Bh, 0FDh, 0B8h, 4Fh, 68h, 0F6h, 72h, 7Bh, 14h
        db      99h, 0CDh, 0D3h, 0Dh, 0F0h, 44h, 3Ah, 0B4h, 0A6h, 66h, 53h, 33h, 0Bh, 0CBh, 0A1h, 10h
SpkTune10_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      7530h
        db      OpSet, vVibrato
        dw      NoiseTable
        db      OpSet, vVibLength
        dw      2000h
        db      OpSet, vVibDepth
        dw      2710h
        db      OpSet, vVibStep
        dw      10h
        db      OpSet, vCount
        dw      1Ch
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0Ch
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      1004h
        db      OpSet, vVibDepth
        dw      898h
        db      OpSet, vPitchStep
        dw      10h
        db      OpSet, vCount
        dw      12Ch
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune12_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      2710h
        db      OpSet, vVibrato
        dw      NoiseTable
        db      OpSet, vVibLength
        dw      2000h
        db      OpSet, vVibDepth
        dw      2328h
        db      OpSet, vVibStep
        dw      10h
        db      OpSet, vCount
        dw      19h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      2
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      1388h
        db      OpSet, vVibDepth
        dw      0FA0h
        db      OpSet, vPitchStep
        dw      12Ch
        db      OpSet, vCount
        dw      50h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune13_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      0BB8h
        db      OpSet, vVibrato
        dw      NoiseTable
        db      OpSet, vVibLength
        dw      2000h
        db      OpSet, vVibDepth
        dw      44Ch
        db      OpSet, vVibStep
        dw      10h
        db      OpSet, vCount
        dw      2
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      1
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      834h
        db      OpSet, vVibDepth
        dw      1F4h
        db      OpSet, vPitchStep
        dw      0FF9Ch
        db      OpSet, vCount
        dw      1Eh
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune18_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      1F40h
        db      OpSet, vVibrato
        dw      NoiseTable
        db      OpSet, vVibLength
        dw      2000h
        db      OpSet, vVibDepth
        dw      44Ch
        db      OpSet, vVibStep
        dw      10h
        db      OpSet, vCount
        dw      2
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      1
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      17D4h
        db      OpSet, vVibDepth
        dw      1F4h
        db      OpSet, vPitchStep
        dw      0FF9Ch
        db      OpSet, vCount
        dw      50h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune16_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vVibrato
        dw      NoiseTable
        db      OpSet, vVibLength
        dw      2000h
        db      OpSet, vVibDepth
        dw      3E8h
        db      OpSet, vVibStep
        dw      10h
        db      OpSet, vPitchStep
        dw      0FFCEh
        db      OpSet, vLoopA
        dw      4
Stream0AEB:
        db      OpSet, vPitch
        dw      2710h
        db      OpSet, vCount
        dw      4
        db      OpSet, vPitch
        dw      4E20h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      4
        db      OpSet, vLevel
        dw      3
        db      OpSet, vCount
        dw      4
        db      OpLoop, vLoopA
        dw      Stream0AEB
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune17_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vVibrato
        dw      NoiseTable
        db      OpSet, vVibLength
        dw      2000h
        db      OpSet, vVibDepth
        dw      3E8h
        db      OpSet, vVibStep
        dw      10h
        db      OpSet, vPitchStep
        dw      0FFCEh
        db      OpSet, vLoopA
        dw      14h
Stream0B2F:
        db      OpSet, vPitch
        dw      1388h
        db      OpSet, vCount
        dw      1
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      1
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      7530h
        db      OpSet, vCount
        dw      1
        db      OpLoop, vLoopA
        dw      Stream0B2F
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune14_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      2710h
        db      OpSet, vVibrato
        dw      NoiseTable
        db      OpSet, vVibLength
        dw      2000h
        db      OpSet, vVibDepth
        dw      1F4h
        db      OpSet, vVibStep
        dw      10h
        db      OpSet, vPitchStep
        dw      0FFCEh
        db      OpSet, vCount
        dw      1Ch
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune15_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      4E20h
        db      OpSet, vVibrato
        dw      NoiseTable
        db      OpSet, vVibLength
        dw      2000h
        db      OpSet, vVibDepth
        dw      2710h
        db      OpSet, vVibStep
        dw      10h
        db      OpSet, vCount
        dw      5
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      1
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      834h
        db      OpSet, vVibDepth
        dw      898h
        db      OpSet, vPitchStep
        dw      64h
        db      OpSet, vCount
        dw      64h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune8_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      0FA0h
        db      OpSet, vCount
        dw      5
        db      OpSet, vPitch
        dw      3E8h
        db      OpSet, vCount
        dw      4
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune9_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      36B0h
        db      OpSet, vPitchStep
        dw      0C8h
        db      OpSet, vVibrato
        dw      NoiseTable
        db      OpSet, vVibLength
        dw      2000h
        db      OpSet, vVibDepth
        dw      1770h
        db      OpSet, vVibStep
        dw      7Bh
        db      OpSet, vCount
        dw      8
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune7_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      3FB4h
        db      OpSet, vLoopA
        dw      1Eh
Stream0C0F:
        db      OpSet, vPitchStep
        dw      0FE3Ch
        db      OpSet, vCount
        dw      0Ch
        db      OpSet, vPitchStep
        dw      277h
        db      OpSet, vCount
        dw      8
        db      OpLoop, vLoopA
        dw      Stream0C0F
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune2_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vVibrato
        dw      NoiseTable
        db      OpSet, vVibLength
        dw      2000h
        db      OpSet, vVibDepth
        dw      640h
        db      OpSet, vVibStep
        dw      19Bh
        db      OpSet, vPitch
        dw      10CCh
        db      OpSet, vPitchStep
        dw      0Ah
        db      OpSet, vCount
        dw      1Eh
        db      OpSet, vVibDepth
        dw      384h
        db      OpSet, vPitch
        dw      514h
        db      OpSet, vPitchStep
        dw      50h
        db      OpSet, vCount
        dw      5
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune5_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vLoopA
        dw      5
        db      OpSet, vPitch
        dw      1838h
Stream0C6F:
        db      OpSet, vPitchStep
        dw      0
        db      OpSet, vCount
        dw      6
        db      OpSet, vLoopB
        dw      0Ch
Stream0C7B:
        db      OpSet, vPitchStep
        dw      0FC5Eh
        db      OpSet, vCount
        dw      1
        db      OpSet, vPitchStep
        dw      384h
        db      OpSet, vCount
        dw      1
        db      OpLoop, vLoopB
        dw      Stream0C7B
        db      OpLoop, vLoopA
        dw      Stream0C6F
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune3_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      197Bh
        db      OpSet, vLoopA
        dw      0Ah
Stream0CA7:
        db      OpSet, vPitchStep
        dw      0FFD3h
        db      OpSet, vCount
        dw      14h
        db      OpSet, vPitchStep
        dw      1F4h
        db      OpSet, vCount
        dw      1
        db      OpLoop, vLoopA
        dw      Stream0CA7
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune4_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vVibrato
        dw      NoiseTable
        db      OpSet, vVibLength
        dw      2000h
        db      OpSet, vVibDepth
        dw      2710h
        db      OpSet, vVibStep
        dw      10h
        db      OpSet, vPitch
        dw      2EE0h
        db      OpSet, vLoopA
        dw      2Ch
Stream0CDF:
        db      OpSet, vPitchStep
        dw      0F1F0h
        db      OpSet, vCount
        dw      2
        db      OpSet, vPitchStep
        dw      0E88h
        db      OpSet, vCount
        dw      2
        db      OpLoop, vLoopA
        dw      Stream0CDF
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune6_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vVibrato
        dw      NoiseTable
        db      OpSet, vVibLength
        dw      2000h
        db      OpSet, vVibDepth
        dw      0A28h
        db      OpSet, vVibStep
        dw      10h
        db      OpSet, vPitch
        dw      1770h
        db      OpSet, vPitchStep
        dw      0FF60h
        db      OpSet, vCount
        dw      1Eh
        db      OpSet, vPitchStep
        dw      46h
        db      OpSet, vCount
        dw      23h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune0_0:
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune1_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      1388h
        db      OpSet, vVibrato
        dw      SineTable
        db      OpSet, vVibLength
        dw      1000h
        db      OpSet, vVibDepth
        dw      1F4h
        db      OpSet, vVibStep
        dw      4Eh
        db      OpSet, vLoopA
        dw      28h
Stream0D4F:
        db      OpSet, vPitchStep
        dw      0
        db      OpSet, vCount
        dw      2
        db      OpSet, vPitchStep
        dw      0FDADh
        db      OpSet, vCount
        dw      1
        db      OpSet, vPitchStep
        dw      0
        db      OpSet, vCount
        dw      2
        db      OpSet, vPitchStep
        dw      1F4h
        db      OpSet, vCount
        dw      1
        db      OpLoop, vLoopA
        dw      Stream0D4F
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune11_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vVibrato
        dw      SineTable
        db      OpSet, vVibLength
        dw      1000h
        db      OpSet, vVibDepth
        dw      3E8h
        db      OpSet, vVibStep
        dw      100h
        db      OpSet, vPitch
        dw      0CE4h
        db      OpSet, vPitchStep
        dw      0FFECh
        db      OpSet, vCount
        dw      1Eh
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
SpkTune20_0:
        db      OpCall
        dw      Stream0DAA
        db      OpSet, vCount
        dw      0
Stream0DAA:
        db      OpVoice
        dw      30h
        db      OpSet, vTranspose
        dw      0FFE8h
        db      OpSet, vEnvelope
        dw      Stream0E37
        db      OpSet, vVibrato
        dw      SineTable
        db      OpSet, vVibLength
        dw      1000h
        db      OpSet, vVibDepth
        dw      28h
        db      OpSet, vVibStep
        dw      12Ch
        db      OpVoice
        dw      60h
        db      OpSet, vTranspose
        dw      0FFE8h
        db      OpSet, vField10
        dw      5
        db      OpSet, vEnvelope
        dw      Stream0E1F
        db      OpSet, vVibrato
        dw      SineTable
        db      OpSet, vVibLength
        dw      1000h
        db      OpSet, vVibDepth
        dw      14h
        db      OpSet, vVibStep
        dw      78h
        db      OpVoice
        dw      0
        db      OpSet, vTranspose
        dw      0FFE8h
        db      OpSet, vEnvelope
        dw      Stream0E4F
        db      OpSet, vVibrato
        dw      SineTable
        db      OpSet, vVibLength
        dw      1000h
        db      OpSet, vVibDepth
        dw      78h
        db      OpSet, vVibStep
        dw      0E4h
        db      OpVoice
        dw      90h
        db      OpSet, vTranspose
        dw      0FFE8h
        db      OpSet, vEnvelope
        dw      Stream0E67
        db      OpSet, vVibrato
        dw      SineTable
        db      OpSet, vVibLength
        dw      1000h
        db      OpSet, vVibDepth
        dw      78h
        db      OpSet, vVibStep
        dw      0E4h
        db      OpSet, vTempo
        dw      1
        db      OpReturn
Stream0E1F:
        db      3, 0, 0FFh, 0FFh, 0, 0, 0, 0, 0, 0, 0FFh, 0FFh, 0, 0, 0, 0
        db      0, 0, 0FFh, 0FFh, 0, 0, 0, 0
Stream0E37:
        db      3, 0, 0FFh, 0FFh, 0, 0, 10h, 0, 0, 0, 0FFh, 0FFh, 0, 0, 0, 0
        db      0, 0, 1Eh, 0, 0, 0, 0, 0
Stream0E4F:
        db      3, 0, 0FFh, 0FFh, 0, 0, 8, 0, 0, 0, 0FFh, 0FFh, 0, 0, 0, 0
        db      0, 0, 1Eh, 0, 0, 0, 0, 0
Stream0E67:
        db      3, 0, 0FFh, 0FFh, 0, 0, 14h, 0, 0, 0, 0FFh, 0FFh, 0, 0, 0, 0
        db      0, 0, 1Eh, 0, 0, 0, 0, 0
SpkTune19_0:
        db      OpSet, vLevel
        dw      3
        db      OpSet, vPitch
        dw      0FA0h
        db      OpSet, vPitchStep
        dw      14h
        db      OpSet, vCount
        dw      10h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune10_2:
        db      OpSet, vPitch
        dw      0BB8h
        db      OpSet, vCount
        dw      1Ch
        db      OpSet, vPitch
        dw      3E80h
        db      OpSet, vPitchStep
        dw      0FFE7h
        db      OpSet, vCount
        dw      190h
        db      OpSet, vCount
        dw      0
TanTune10_3:
        db      OpSet, vPitch
        dw      1C0h
        db      OpSet, vLevel
        dw      0EA60h
        db      OpSet, vCount
        dw      1Ch
        db      OpSet, vLevel
        dw      0C350h
        db      OpSet, vLevelStep
        dw      0FF9Ch
        db      OpSet, vCount
        dw      190h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune12_2:
        db      OpSet, vPitch
        dw      0BB8h
        db      OpSet, vCount
        dw      12h
        db      OpSet, vPitch
        dw      3E80h
        db      OpSet, vPitchStep
        dw      0FFE7h
        db      OpSet, vCount
        dw      64h
        db      OpSet, vCount
        dw      0
TanTune12_3:
        db      OpSet, vPitch
        dw      1C0h
        db      OpSet, vLevel
        dw      0EA60h
        db      OpSet, vCount
        dw      12h
        db      OpSet, vLevel
        dw      0C350h
        db      OpSet, vLevelStep
        dw      0FF9Ch
        db      OpSet, vCount
        dw      64h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune13_2:
        db      OpSet, vPitch
        dw      2328h
        db      OpSet, vPitchStep
        dw      0FFE7h
        db      OpSet, vCount
        dw      19h
        db      OpSet, vCount
        dw      0
TanTune13_3:
        db      OpSet, vPitch
        dw      1C0h
        db      OpSet, vLevel
        dw      0D6D8h
        db      OpSet, vLevelStep
        dw      0FF9Ch
        db      OpSet, vCount
        dw      19h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune13_0:
        db      OpSet, vPitch
        dw      0FA0h
        db      OpSet, vLevel
        dw      9C40h
        db      OpSet, vLevelStep
        dw      0FF9Ch
        db      OpSet, vPitchStep
        dw      0FF9Ch
        db      OpSet, vCount
        dw      19h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune18_2:
        db      OpSet, vPitch
        dw      2710h
        db      OpSet, vPitchStep
        dw      0FFE7h
        db      OpSet, vCount
        dw      37h
        db      OpSet, vCount
        dw      0
TanTune18_3:
        db      OpSet, vPitch
        dw      1C0h
        db      OpSet, vLevel
        dw      0EA60h
        db      OpSet, vLevelStep
        dw      0FF9Ch
        db      OpSet, vCount
        dw      37h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune18_0:
        db      OpSet, vPitch
        dw      1B58h
        db      OpReturn
        db      0Ah, 28h, 0A0h, 0FFh, 0Ch, 9Ch, 0FFh, 0FFh, 6, 9Ch, 0FFh, 0FFh, 0, 37h, 0, 0FFh
        db      0Ah, 0, 0, 0FFh, 0, 0, 0
TanTune16_2:
        db      OpSet, vPitch
        dw      1F40h
        db      OpSet, vCount
        dw      28h
        db      OpSet, vCount
        dw      0
TanTune16_3:
        db      OpSet, vPitch
        dw      1C0h
        db      OpSet, vLoopA
        dw      4
Stream0FA3:
        db      OpSet, vLevel
        dw      0D6D8h
        db      OpSet, vCount
        dw      5
        db      OpSet, vLevel
        dw      1
        db      OpSet, vCount
        dw      5
        db      OpLoop, vLoopA
        dw      Stream0FA3
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune17_2:
        db      OpSet, vLoopA
        dw      14h
Stream0FC3:
        db      OpSet, vPitch
        dw      1770h
        db      OpSet, vLevel
        dw      0C350h
        db      OpSet, vCount
        dw      1
        db      OpSet, vPitch
        dw      1388h
        db      OpSet, vLevel
        dw      1
        db      OpSet, vCount
        dw      1
        db      OpSet, vPitch
        dw      7530h
        db      OpSet, vLevel
        dw      0C350h
        db      OpSet, vCount
        dw      1
        db      OpLoop, vLoopA
        dw      Stream0FC3
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune14_2:
        db      OpSet, vPitch
        dw      0FA0h
        db      OpSet, vCount
        dw      1Ch
        db      OpSet, vCount
        dw      0
TanTune14_3:
        db      OpSet, vPitch
        dw      1C0h
        db      OpSet, vLevel
        dw      0C350h
        db      OpSet, vCount
        dw      1Ch
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune15_2:
        db      OpSet, vPitch
        dw      2710h
        db      OpSet, vCount
        dw      5
        db      OpSet, vPitch
        dw      0FA0h
        db      OpSet, vPitchStep
        dw      64h
        db      OpSet, vCount
        dw      64h
        db      OpSet, vCount
        dw      0
TanTune15_3:
        db      OpSet, vPitch
        dw      1C0h
        db      OpSet, vLevel
        dw      0EA60h
        db      OpSet, vCount
        dw      5
        db      OpSet, vLevel
        dw      0C350h
        db      OpSet, vLevelStep
        dw      0FF9Ch
        db      OpSet, vCount
        dw      64h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune8_3:
        db      OpSet, vPitch
        dw      100h
        db      OpSet, vLevel
        dw      7530h
        db      OpSet, vLevelStep
        dw      3E8h
        db      OpSet, vCount
        dw      14h
        db      OpSet, vLevelStep
        dw      0FC18h
        db      OpSet, vCount
        dw      28h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune9_3:
        db      OpSet, vPitch
        dw      180h
        db      OpSet, vLevel
        dw      0EA60h
        db      OpSet, vLevelStep
        dw      0F254h
        db      OpSet, vCount
        dw      10h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune7_1:
        db      OpSet, vCount
        dw      4
TanTune7_0:
        db      OpSet, vLevel
        dw      0EA60h
        db      OpSet, vLevelStep
        dw      0FF9Ch
        db      OpSet, vPitch
        dw      0FDE8h
        db      OpSet, vLoopA
        dw      1Eh
Stream1097:
        db      OpSet, vPitchStep
        dw      0FD8Ah
        db      OpSet, vCount
        dw      0Ch
        db      OpSet, vPitchStep
        dw      276h
        db      OpSet, vCount
        dw      8
        db      OpLoop, vLoopA
        dw      Stream1097
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune6_2:
        db      OpSet, vPitch
        dw      7D0h
        db      OpSet, vPitchStep
        dw      5Ah
        db      OpSet, vCount
        dw      14h
        db      OpSet, vCount
        dw      0
TanTune6_3:
        db      OpSet, vPitch
        dw      1C0h
        db      OpSet, vLevel
        dw      0EA60h
        db      OpSet, vLevelStep
        dw      0F830h
        db      OpSet, vCount
        dw      14h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune5_0:
        db      OpSet, vPitch
        dw      9C2h
        db      OpSet, vLevel
        dw      7530h
        db      OpSet, vLoopA
        dw      0Ch
Stream10E7:
        db      OpSet, vPitchStep
        dw      0FFF7h
        db      OpSet, vCount
        dw      0Ch
        db      OpSet, vPitchStep
        dw      9
        db      OpSet, vCount
        dw      8
        db      OpLoop, vLoopA
        dw      Stream10E7
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune3_2:
        db      OpSet, vCount
        dw      14h
TanTune3_1:
        db      OpSet, vCount
        dw      14h
TanTune3_0:
        db      OpSet, vPitch
        dw      98E3h
        db      OpSet, vLevel
        dw      0EA60h
        db      OpSet, vLevelStep
        dw      0FF38h
        db      OpSet, vPitchStep
        dw      0FF4Eh
        db      OpSet, vCount
        dw      0C8h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune4_0:
        db      OpSet, vLevel
        dw      2710h
        db      OpSet, vLevelStep
        dw      1F4h
        db      OpSet, vPitch
        dw      0FA00h
        db      OpSet, vPitchStep
        dw      0FF10h
        db      OpSet, vCount
        dw      50h
        db      OpSet, vLevelStep
        dw      0
        db      OpSet, vLoopA
        dw      2Ch
Stream1143:
        db      OpSet, vPitchStep
        dw      0FB50h
        db      OpSet, vCount
        dw      2
        db      OpSet, vPitchStep
        dw      4D8h
        db      OpSet, vCount
        dw      2
        db      OpLoop, vLoopA
        dw      Stream1143
        db      OpSet, vLevelStep
        dw      0FE61h
        db      OpSet, vPitchStep
        dw      3Ch
        db      OpSet, vCount
        dw      78h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune4_2:
        db      OpSet, vPitch
        dw      1130h
        db      OpSet, vPitchStep
        dw      0Bh
        db      OpSet, vCount
        dw      0BCh
        db      OpSet, vPitchStep
        dw      0FFF5h
        db      OpSet, vCount
        dw      0BCh
        db      OpSet, vCount
        dw      0
TanTune4_3:
        db      OpSet, vPitch
        dw      1C0h
        db      OpSet, vLevel
        dw      61A8h
        db      OpSet, vLevelStep
        dw      9Fh
        db      OpSet, vCount
        dw      0BCh
        db      OpSet, vLevelStep
        dw      0FF61h
        db      OpSet, vCount
        dw      0BCh
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune2_3:
        db      OpSet, vLevelStep
        dw      960h
        db      OpSet, vPitch
        dw      100h
        db      OpSet, vCount
        dw      19h
        db      OpSet, vLevelStep
        dw      0F6A0h
        db      OpSet, vCount
        dw      19h
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune0_0:
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune1_0:
        db      OpSet, vLevel
        dw      0EA60h
        db      OpSet, vLevelStep
        dw      0FF15h
        db      OpSet, vPitch
        dw      1FE0h
        db      OpSet, vLoopA
        dw      6
Stream11D7:
        db      OpSet, vPitchStep
        dw      1Eh
        db      OpSet, vCount
        dw      10h
        db      OpSet, vPitchStep
        dw      0FFE2h
        db      OpSet, vCount
        dw      10h
        db      OpLoop, vLoopA
        dw      Stream11D7
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune1_1:
        db      OpSet, vLevel
        dw      0C350h
        db      OpSet, vLevelStep
        dw      0FF38h
        db      OpSet, vPitch
        dw      4010h
        db      OpSet, vLoopA
        dw      0Ah
Stream1203:
        db      OpSet, vPitchStep
        dw      42h
        db      OpSet, vCount
        dw      8
        db      OpSet, vPitchStep
        dw      0FFBEh
        db      OpSet, vCount
        dw      8
        db      OpLoop, vLoopA
        dw      Stream1203
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune1_2:
        db      OpSet, vLevel
        dw      0FDE8h
        db      OpSet, vLevelStep
        dw      0FED4h
        db      OpSet, vPitch
        dw      36B0h
        db      OpSet, vLoopA
        dw      8
Stream122F:
        db      OpSet, vPitchStep
        dw      52h
        db      OpSet, vCount
        dw      0Ch
        db      OpSet, vPitchStep
        dw      0FFB2h
        db      OpSet, vCount
        dw      0Ch
        db      OpLoop, vLoopA
        dw      Stream122F
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune11_0:
        db      OpSet, vLevel
        dw      0EA60h
        db      OpSet, vLevelStep
        dw      0FB50h
        db      OpSet, vPitch
        dw      34D0h
        db      OpSet, vCount
        dw      1Eh
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune11_1:
        db      OpSet, vLevel
        dw      0EA60h
        db      OpSet, vLevelStep
        dw      0FB50h
        db      OpSet, vPitch
        dw      8020h
        db      OpSet, vCount
        dw      1Eh
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune11_2:
        db      OpSet, vLevel
        dw      0EA60h
        db      OpSet, vLevelStep
        dw      0FB50h
        db      OpSet, vPitch
        dw      1770h
        db      OpSet, vCount
        dw      0Ah
        db      OpSet, vLevel
        dw      0
        db      OpSet, vCount
        dw      0
TanTune20_0:
        db      OpCall
        dw      Stream129A
        db      OpSet, vCount
        dw      0
Stream129A:
        db      OpVoice
        dw      30h
        db      OpSet, vField10
        dw      0Ch
        db      OpSet, vTranspose
        dw      0FFD3h
        db      OpSet, vEnvelope
        dw      Envelope131C
        db      OpSet, vVibrato
        dw      SineTable
        db      OpSet, vVibLength
        dw      1000h
        db      OpSet, vVibDepth
        dw      28h
        db      OpSet, vVibStep
        dw      12Ch
        db      OpVoice
        dw      60h
        db      OpSet, vField10
        dw      7
        db      OpSet, vTranspose
        dw      0FFD3h
        db      OpSet, vEnvelope
        dw      Envelope12FC
        db      OpSet, vVibrato
        dw      SineTable
        db      OpSet, vVibLength
        dw      1000h
        db      OpSet, vVibDepth
        dw      16h
        db      OpSet, vVibStep
        dw      78h
        db      OpVoice
        dw      0
        db      OpSet, vField10
        dw      7
        db      OpSet, vTranspose
        dw      0FFD3h
        db      OpSet, vEnvelope
        dw      Envelope133C
        db      OpSet, vVibrato
        dw      SquareTable
        db      OpSet, vVibLength
        dw      200h
        db      OpSet, vVibDepth
        dw      0C8h
        db      OpSet, vVibStep
        dw      10h
        db      OpSet, vTempo
        dw      6
        db      OpReturn
Envelope12FC:
        dw      0C350h
        dw      0FFFFh
        dw      9C4h
        dw      4
        dw      0F830h
        dw      6
        dw      0
        dw      0
        dw      0BB80h
        dw      0FFFFh
        dw      0E0C0h
        dw      6
        dw      0
        dw      0FFFFh
        dw      0
        dw      0
Envelope131C:
        dw      9C40h
        dw      0FFFFh
        dw      9C4h
        dw      8
        dw      0F448h
        dw      5
        dw      0
        dw      0
        dw      0AFC8h
        dw      0FFFFh
        dw      0F060h
        dw      0Bh
        dw      0
        dw      0FFFFh
        dw      0
        dw      0
Envelope133C:
        dw      0DEA8h
        dw      0FFFFh
        dw      0FA24h
        dw      6
        dw      0
        dw      0
        dw      0
        dw      0
        dw      0BB80h
        dw      0FFFFh
        dw      0E0C0h
        dw      6
        dw      0
        dw      0FFFFh
        dw      0
        dw      0
TanTune19_0:
        dw      4FFh
        dw      1F40h
        dw      0AFFh
        dw      7530h
        dw      6FFh
        dw      14h
        dw      0CFFh
        dw      0FF9Ch
        dw      0FFh
        dw      10h
        dw      0AFFh
        dw      0
        dw      0FFh
        dw      0

; the BIOS INT 08h vector StartSoundTimer replaced (offset, then segment) [V]
SavedVector:
        dd      0

; ---- code ----
; StartSoundTimer: save INT 08h, install TimerHandler, set the speaker channel to mode 3 and the
; timer to 5041. Far, no arguments. [V]
StartSoundTimer:
        push ds
        push es
        mov ax, CODESEG
        mov ds, ax
        mov ax, 3508h
        int 21h
        mov word ptr cs:[SavedVector], bx
        mov word ptr cs:[SavedVector+2], es
        push ds
        mov dx, CODESEG
        mov ds, dx
        mov dx, TimerHandler
        mov ax, 2508h
        int 21h
        pop ds
        mov al, 0B6h
        out 43h, al
        mov ax, 5041
        out 40h, al
        mov al, ah
        out 40h, al
        pop es
        pop ds
        retf

; StopSoundTimer: restore INT 08h, timer back to 0FFFFh, speaker gate off, Tandy chip silent. [V]
StopSoundTimer:
        push ds
        mov ax, CODESEG
        mov ds, ax
        push ds
        mov dx, word ptr cs:[SavedVector]
        mov ax, word ptr cs:[SavedVector+2]
        mov ds, ax
        mov ax, 2508h
        int 21h
        pop ds
        mov ax, 0FFFFh
        out 40h, al
        mov al, ah
        out 40h, al
        in al, 61h
        and al, 0FCh
        out 61h, al
        mov al, 9Fh
        out 0C0h, al
        mov al, 0BFh
        out 0C0h, al
        mov al, 0DFh
        out 0C0h, al
        mov al, 0FFh
        out 0C0h, al
        pop ds
        retf

; TimerHandler (INT 08h): the watchdog, then the voices, then chain to BIOS every 13th tick. [V]
TimerHandler:
        sti
        push ax
        push bx
        push dx
        push ds
        push si
        mov ax, CODESEG
        mov ds, ax
        cmp word ptr [WatchdogTicks], 0
        je ServiceVoices
        dec word ptr [WatchdogTicks]
        jne ServiceVoices
        mov ah, 0Fh
        int 10h
        mov ah, 0
        int 10h
        mov bl, 7
        mov ah, 7Fh
        mov cx, 21h
        mov bx, CODESEG
        mov es, bx
        mov bx, WatchdogText
L1419:
        mov al, byte ptr es:[bx]
        and al, ah
        mov byte ptr es:[bx], al
        inc bx
        loop L1419
        mov bl, 7
        mov ah, 13h
        mov al, 1
        mov bh, 0
        mov cx, 21h
        xor dx, dx
        mov bp, CODESEG
        mov es, bp
        mov bp, WatchdogText
        int 10h
        mov ah, 4Ch
        mov al, 0FFh
        int 21h

; step both devices unless the handler is already running
ServiceVoices:
        cmp byte ptr [InService], 0
        jne CountChain
        mov byte ptr [InService], 1
        call SpeakerStep
        call TandyStep
        mov byte ptr [InService], 0

; every 13th tick jump to the BIOS handler (it sends the EOI), the others send it here
CountChain:
        dec byte ptr [ChainCount]
        jne AckIrq
        mov byte ptr [ChainCount], 0Dh
        pop si
        pop ds
        pop dx
        pop bx
        pop ax
        jmp dword ptr cs:[SavedVector]
AckIrq:
        mov al, 20h
        out 20h, al
        pop si
        pop ds
        pop dx
        pop bx
        pop ax
        iret

; SpeakerStep: step the four speaker voices, then program PIT channel 2 with the period of the
; first voice that has a nonzero level and set the gate bits from its level. [V]
SpeakerStep:
        mov bx, word ptr [CurrentTune]
        cmp bx, 0
        je SpeakerGate
        mov word ptr [LoudestVoice], 0
        mov byte ptr [VoicesLeft], 4
        mov si, SpeakerNotes
        mov word ptr [NoteTable], si
        mov si, SpeakerVoices
        mov word ptr [VoiceBase], si
L1499:
        cmp word ptr [si], 0
        je L14B7
        call StepVoice
        cmp word ptr [LoudestVoice], 0
        jne L14B7
        cmp word ptr [si + vLevel], 0
        je L14B7
        cmp word ptr [si], 0
        je L14B7
        mov word ptr [LoudestVoice], si
L14B7:
        add si, 30h
        dec byte ptr [VoicesLeft]
        jne L1499
        mov bl, byte ptr [OutputOn]
        cmp bl, 0
        je SpeakerGate
        mov bx, word ptr [LoudestVoice]
        cmp bx, 0
        je SpeakerGate
        mov si, bx
        mov ax, word ptr [si + vOutput]
        out 42h, al
        mov al, ah
        out 42h, al
        mov bx, word ptr [si + vLevel]
        and bl, 3

; gate: port 61h bits 0..1 := bl (0 turns the speaker off)
SpeakerGate:
        in al, 61h
        and al, 0FCh
        or al, bl
        out 61h, al
        ret

; TandyStep: step the four Tandy voices, then write per channel the tone (period >> 6) and the
; attenuation (inverted high nibble of the level). Silence when no tune or output is off. [V]
TandyStep:
        mov bx, word ptr [CurrentTune]
        cmp bx, 0
        je TandyQuiet
        mov byte ptr [VoicesLeft], 4
        mov si, TandyNotes
        mov word ptr [NoteTable], si
        mov si, TandyVoices
        mov word ptr [VoiceBase], si
L1508:
        cmp word ptr [si], 0
        je L1510
        call StepVoice
L1510:
        add si, 30h
        dec byte ptr [VoicesLeft]
        jne L1508
        mov al, byte ptr [OutputOn]
        cmp al, 0
        je TandyQuiet
        mov byte ptr [VoicesLeft], 4
        mov si, TandyVoices
        mov dl, 80h
L152A:
        mov ax, word ptr [si + vOutput]
        shr ax, 1
        shr ax, 1
        shr al, 1
        shr al, 1
        shr al, 1
        shr al, 1
        xor al, dl
        out 0C0h, al
        cmp dl, 0E0h
        je L1546
        mov al, ah
        out 0C0h, al
L1546:
        mov ax, 0FFFFh
        sub ax, word ptr [si + vLevel]
        shr ah, 1
        shr ah, 1
        shr ah, 1
        shr ah, 1
        mov al, ah
        xor al, dl
        add al, 10h
        out 0C0h, al
        add dl, 20h
        add si, 30h
        dec byte ptr [VoicesLeft]
        jne L152A
        ret

; attenuation 15 on all four channels
TandyQuiet:
        mov al, 9Fh
        out 0C0h, al
        mov al, 0BFh
        out 0C0h, al
        mov al, 0DFh
        out 0C0h, al
        mov al, 0FFh
        out 0C0h, al
        ret

; StepVoice: one tick of the voice at si: level and pitch slopes, vibrato, output period, release delay,
; event countdown (RunStream at zero), envelope. [V]
StepVoice:
        push cx
        push di
        mov ax, word ptr [si + vLevelStep]
        add word ptr [si + vLevel], ax
        mov ax, word ptr [si + vPitchStep]
        add word ptr [si + vPitch], ax
        sub dx, dx
        mov ax, word ptr [si + vVibPos]
        add ax, word ptr [si + vVibStep]
        je L15AD
        cmp ax, word ptr [si + vVibLength]
        jb L159A
        sub ax, word ptr [si + vVibLength]
L159A:
        mov word ptr [si + vVibPos], ax
        mov cl, 4
        sar ax, cl
        add ax, word ptr [si + vVibrato]
        mov di, ax
        mov ah, byte ptr [di]
        mov al, 0
        imul word ptr [si + vVibDepth]
L15AD:
        add dx, word ptr [si + vPitch]
        mov word ptr [si + vOutput], dx
        cmp word ptr [si + vRelease], 0
        je CountDuration
        dec word ptr [si + vRelease]
        jne CountDuration
        mov word ptr [si + vEnvPos], 10h
        mov word ptr [si + vEnvCount], 1
CountDuration:
        dec word ptr [si]
        jne EnvelopeCheck
        call RunStream
EnvelopeCheck:
        cmp word ptr [si + vEnvCount], 0
        je StepDone
        dec word ptr [si + vEnvCount]
        jne StepDone
EnvelopeNext:
        mov bx, word ptr [si + vEnvelope]
        add bx, word ptr [si + vEnvPos]
        cmp word ptr [bx + 2], -1
        jne EnvelopeSlope
        mov ax, word ptr [bx]
        mov word ptr [si + vLevel], ax
        cmp ax, 0
        jne L15F3
        mov word ptr [si + vLevelStep], ax
L15F3:
        add word ptr [si + vEnvPos], 4
        jmp EnvelopeNext
EnvelopeSlope:
        mov ax, word ptr [bx]
        mov word ptr [si + vLevelStep], ax
        mov ax, word ptr [bx + 2]
        mov word ptr [si + vEnvCount], ax
        add word ptr [si + vEnvPos], 4
StepDone:
        pop di
        pop cx
        ret

; RunStream: execute the voice's stream from vStream until it waits (field 0 written) [V]
RunStream:
        mov di, word ptr [si + vStream]
        cmp di, 0
        jne L1614
        ret
L1614:
        mov word ptr [CurrentVoice], si

; fetch: bytes below 0FAh are note events, 0FAh..0FFh index OpcodeTable
NextCommand:
        mov bl, byte ptr [di]
        inc di
        cmp bl, 0FAh
        jae Command
        jmp Note
Command:
        sub bh, bh
        sub bl, 0FAh
        add bl, bl
        jmp word ptr [bx + OpcodeTable]

; 0FEh f t: repeat (see the header)
CmdLoop:
        mov bl, byte ptr [di]
        inc di
        mov bh, 0
        mov ax, word ptr [di]
        add di, 2
        cmp word ptr [bx + si], 0
        je LoopTaken
        dec word ptr [bx + si]
        je NextCommand
LoopTaken:
        mov di, ax
        jmp NextCommand

; 0FDh o: select the voice record VoiceBase + o, then clear it
CmdSelectVoice:
        mov si, word ptr [di]
        add di, 2
        add si, word ptr [VoiceBase]

; 0FAh: clear the slopes, envelope and vibrato fields of the selected voice
CmdClearVoice:
        sub bx, bx
        mov word ptr [si + vPitch], bx
        mov word ptr [si + vPitchStep], bx
        mov word ptr [si + vOutput], bx
        mov word ptr [si + vLevel], bx
        mov word ptr [si + vLevelStep], bx
        mov word ptr [si + vField10], bx
        mov word ptr [si + vTranspose], bx
        mov word ptr [si + vEnvelope], bx
        mov word ptr [si + vEnvPos], bx
        mov word ptr [si + vEnvCount], bx
        mov word ptr [si + vVibrato], bx
        mov word ptr [si + vVibPos], bx
        mov word ptr [si + vVibStep], bx
        mov word ptr [si + vVibDepth], bx
        mov word ptr [si + vVibLength], bx
        jmp NextCommand

; 0FFh f w: store w in field f; field 0 ends the burst
CmdSetField:
        mov bl, byte ptr [di]
        inc di
        mov bh, 0
        mov ax, word ptr [di]
        inc di
        inc di
        mov word ptr [bx + si], ax
        cmp bl, 0
        jne NextCommand

; save the stream pointer in the stepping voice; a voice whose count is 0 is finished
EventEnd:
        mov si, word ptr [CurrentVoice]
        cmp word ptr [si], 0
        jne SaveStream
        mov bl, 4
        sub bl, byte ptr [VoicesLeft]
        sub bh, bh
        mov byte ptr [bx + VoiceTune], 0
        mov di, 0
SaveStream:
        mov word ptr [si + vStream], di
        ret

; 0FBh: return from the one-level call
CmdReturn:
        mov di, word ptr [ReturnPtr]
        jmp near NextCommand

; 0FCh t: call
CmdCall:
        mov ax, word ptr [di]
        add di, 2
        mov word ptr [ReturnPtr], di
        mov di, ax
        jmp near NextCommand

; the note event path (never reached by a shipped tune)
NextNote:
        mov bl, byte ptr [di]
        inc di
Note:
        push di
        mov al, bl
        mov cl, 5
        shr al, cl
        mov cl, al
        mul byte ptr [VoiceSize]
        add ax, word ptr [VoiceBase]
        mov di, ax
        pop bx
        push bx
        mov ax, word ptr [si + vTempo]
        cmp al, 1
        ja L16E7
        xor ah, ah
        mov al, byte ptr [bx + 1]
        jmp short L16EA
L16E7:
        mul byte ptr [bx + 1]
L16EA:
        mov word ptr [si], ax
        mov al, byte ptr [bx]
        and ax, 7Fh
        cmp ax, 7Fh
        je NoteDone
        cmp cl, 0
        ja NoteDone
        mov cx, word ptr [si]
        mov word ptr [di], cx
        mov word ptr [di + vRelease], cx
        add ax, word ptr [di + vTranspose]
        mov word ptr [di + vEnvPos], 0
        mov word ptr [di + vEnvCount], 1
        mov cx, 0FFh
L1712:
        inc cl
        sub ax, 0Ch
        jae L1712
        add ax, 0Ch
        mov bx, ax
        add bx, bx
        cmp di, TandyVoices+90h
        jne L1726
L1726:
        add bx, word ptr [NoteTable]
        mov ax, word ptr [bx]
        shr ax, cl
        mov word ptr [di + vPitch], ax
        mov word ptr [di + vOutput], ax
NoteDone:
        pop di
        mov al, byte ptr [di]
        inc di
        inc di
        and al, 80h
        jne NoteLast
        jmp NextNote
NoteLast:
        jmp near EventEnd

; SetSpeakerTune(Tune: Word): far, retf 2. Load the four streams of the row Tune of SpeakerTunes into
; cleared voice records (count 1: they start on the next tick) and make Tune current. [V]
SetSpeakerTune:
        push bp
        mov bp, sp
        push ax
        push bx
        push di
        push si
        push ds
        mov si, CODESEG
        mov ds, si
        mov si, word ptr [bp + 6]
        mov word ptr [CurrentTune], si
        add si, si
        add si, si
        add si, si
        mov byte ptr [InService], 1
        mov byte ptr [VoicesLeft], 4
        mov di, SpeakerVoices
SpkLoadVoice:
        mov ax, word ptr [si + SpeakerTunes]
        cmp ax, 0
        je SpkNextVoice
        mov bx, 2Eh
L1775:
        mov word ptr [bx + di], 0
        sub bx, 2
        jge L1775
        mov word ptr [di + vStream], ax
        mov bl, 4
        sub bl, byte ptr [VoicesLeft]
        sub bh, bh
        mov ax, word ptr [CurrentTune]
        mov byte ptr [bx + VoiceTune], al
        mov word ptr [di], 1
SpkNextVoice:
        add di, 30h
        add si, 2
        dec byte ptr [VoicesLeft]
        jne SpkLoadVoice
        mov byte ptr [InService], 0
        pop ds
        pop si
        pop di
        pop bx
        pop ax
        pop bp
        retf 2

; SetTandyTune(Tune: Word): the same for the Tandy chip. [V]
SetTandyTune:
        push bp
        mov bp, sp
        push ax
        push bx
        push di
        push si
        push ds
        mov si, CODESEG
        mov ds, si
        mov si, word ptr [bp + 6]
        mov word ptr [CurrentTune], si
        add si, si
        add si, si
        add si, si
        mov byte ptr [InService], 1
        mov byte ptr [VoicesLeft], 4
        mov di, TandyVoices
TanLoadVoice:
        mov ax, word ptr [si + TandyTunes]
        cmp ax, 0
        je TanNextVoice
        mov bx, 2Eh
L17E1:
        mov word ptr [bx + di], 0
        sub bx, 2
        jge L17E1
        mov word ptr [di + vStream], ax
        mov bl, 4
        sub bl, byte ptr [VoicesLeft]
        sub bh, bh
        mov ax, word ptr [CurrentTune]
        mov byte ptr [bx + VoiceTune], al
        mov word ptr [di], 1
TanNextVoice:
        add di, 30h
        add si, 2
        dec byte ptr [VoicesLeft]
        jne TanLoadVoice
        mov byte ptr [InService], 0
        pop ds
        pop si
        pop di
        pop bx
        pop ax
        pop bp
        retf 2

; SetSoundOutput(Enabled: Word): far, retf 2. OutputOn := the low byte. [V]
SetSoundOutput:
        push bp
        mov bp, sp
        push ax
        push ds
        mov ax, CODESEG
        mov ds, ax
        mov ax, word ptr [bp + 6]
        mov byte ptr [OutputOn], al
        pop ds
        pop ax
        pop bp
        retf 2

