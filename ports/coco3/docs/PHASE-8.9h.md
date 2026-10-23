# Step 8.9h: the 6309's native mode

Date: 2026-10-23. Follows `docs/PHASE-8.9g.md`; the measurements and the reasons are in `docs/RESEARCH-6309.md` (branch `research/6309`). Built on the branch `perf/native6309`. Tags: **[V]** measured by running it in MAME (the `coco3` 6809 machine and the `coco3h` HD6309 machine), **[E]** estimate.

## 1. What it does

One image for both CPUs. `boot.asm`, after the image of the shared data is copied, tests for a 6309 and switches it to native mode:

```
        ldy     #0
        fcb     $1F,$62          TFR W,Y: Y = W on a 6309 (W is 0 after a reset), $FFFF on a 6809 (no W)
        cmpy    #$FFFF
        beq     @is6809
        fcb     $11,$3D,$01      LDMD #1: native mode
        lda     #1
        sta     >_cpu6309        (a byte of shared2, $0701: 1 on a 6309 in native mode, else 0)
```

On a 6809 nothing changes (the same bytes of work as before, one byte more of shared data). A 6309 runs the same code in fewer cycles (one less for most inherent, direct and extended instructions, the calls, the pushes; indexed instructions are the same). Interrupts push two bytes more (E and F; our handlers only `RTI`), FIRQ keeps the 6809 frame.

**Disk BASIC's ROM.** `dsk_read` calls DSKCON in the Disk BASIC ROM, whose NMI handler (the end of every sector transfer) throws away a 6809 interrupt frame of 12 bytes: in native mode the frame is 14 bytes and the machine crashes (`t_disk` hung on the 6309 machine; found by the engine tests, **not** by `make step-check`, because MAME's game runs serve the disk image from the harness and never call the ROM). `disk.asm` now leaves native mode (`LDMD #0`) for the length of the ROM call and goes back (`LDMD #1`) when it returns, only when `_cpu6309` is set. Any other call of ROM code from the engine would need the same.

## 2. Verified [V]

| | 6809 machine (`coco3`) | 6309 machine (`coco3h`) |
|---|---|---|
| `make step-check` (16 sessions, 15 states with 0 DGROUP places open, party records, save area) | pass, busy 1,848 s (as before) | pass, busy **1,692 s (-8.4 %)** |
| engine tests `t_disk` to `t_task` (11 tests in MAME; XRoar is a 6809) | pass | pass |
| `_cpu6309` read from the RAM dump | 0 | 1 |

`t_vol2` stops at the build of its test disk in this worktree (the disk is full: environment, as before this step), so the volume tests do not run here. The same image on both machines: `build/game/pool.img` is not rebuilt between them.

Gains per session (busy seconds, 6809 to 6309 native, from the research runs): -7 to -9 % in every menu and fight session, -13 % a step in the 3D view, -14 % over the scroll script (`docs/RESEARCH-6309.md` has the table).

## 3. Not covered, to check before a release [E]

* **A real 6809 and a real 6309.** The detection is the reference's (`TFR W,Y`); MAME's 6809 and 6309 agree with it, no hardware was tried. If W held `$FFFF` on a 6309 it would stay in compatible mode (safe).
* **Loops that count cycles run about 8 % shorter** in native mode. `disk.asm`'s half second wait for the motor (nested counted loops, around 0.4 s instead of 0.45 s) is the one that matters; the game's delays count frames.
* **The real disk path under native mode** is tested only through the engine tests on MAME's emulated controller; the DSKCON call runs in compatible mode, so the ROM sees what it always saw.
* The shared data grew by one byte: the 28 bytes of room before the event log at `$0860` are 27 now; the engine ends at `$7C7F` of `$7C90` (17 bytes left, 37 before).

## 4. Next [E]

`TFM` copy kernels (about 2 to 4 % more, scroll -10 %): the engine has no room for a second set of kernels, so the 6309 versions (shorter than the 6809 ones) would be copied over them at start-up from a bank when `_cpu6309` is 1. `docs/research-6309-tfm-kernels.patch` (branch `research/6309`) is the kernel change.

## 5. Tools

`MB_MACHINE=coco3h make step-check LABEL=...` (and `make eng-tests`, `scripts/game_run.sh`) run on MAME's 6309 machine; `roms/coco3h/` needs copies of `coco3.rom` and `disk11.rom` (README, ROMs).
