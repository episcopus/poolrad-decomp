# Step 8.13: quality of life (no code wheel, the port's credits line, BASIC for DOS, a loading screen that says how)

Date: 2026-10-25. The port's first changes that are DEVIATIONS from the PC original on purpose. They are on by default; `make QOL=0 game` (`POOL_QOL=0`) builds the faithful game. Tags: **[V]** seen on the emulated CoCo.

## 1. What changed

| Change | Where | How |
|---|---|---|
| No code wheel (the copy protection) | `pool_main` | `tools/qol.py drop_wheel` takes the call of `CheckCodeWheel` out of `pool.c`; the overlay's bank is never loaded for it. The title and the credits go straight to the training hall menu **[V]** |
| Credits: `COCO 3 PORT:` (light green) `UNOFFICIAL - V1.0` and `FROM PC V1.3` (light cyan) replace the line `VERSION 1.3` | `ShowCredits` (ovl01) | a patch in `tools/qol.py` (`PATCHES` of `tools/mkgame.py`). The whole line is 43 cells and the text area has 36, so it takes two rows (6 and 7), and the first programming block moves one row down into the blank row that separated it from the graphic arts block **[V]** |
| `RETURN TO BASIC` for the prompts that name DOS | ovl15 (camp menu Quit, Drop with one member left), ovl16 (training hall Exit) | the three literals; the training hall's menu entry reads `Exit to BASIC` (initial data, patched in `tools/mkvm.py` before the image is coded; it keeps the hotkey E, which `Return` would take from `Remove Character from Party`) **[V]** |
| Loading screen: the CPU's mode on its own line, the storage's kind and details | `boot.asm`, `tools/stripbin.py`, `tools/mkimage.py`, `src/engine/ide.c` | rows 4 to 6 the machine (`COCO 3, 512K RAM: OK`, `CPU: 6309 (HITACHI)`, `MODE: NATIVE`; a 6809 has no mode line), rows 8 and 9 the storage, `LOADING...` on row 11, the bar on row 12 |

The storage lines are not engine code (the engine of the floppy and SDC builds has 37 bytes left): `stripbin.with_storage` writes them into the splash record at the start of `POOL.BIN` when `mkimage.py` packs it, so LOADM shows them from its first record. `STORAGE: FLOPPY DISKS` / `35 TRACKS, 12 DISKS`; `STORAGE: COCO SDC` / `ONE IMAGE FILE ON THE CARD`; `STORAGE: IDE, COMPACTFLASH` and, once the card has answered (the one thing only the run knows), `MASTER, 8 BIT TRANSFERS` (or `SLAVE,` and `16 BIT TRANSFERS`) from `ide.c`. The harness' storage (tests, `make play`) has no storage lines.

## 2. The version

`ports/coco3/VERSION` (now `1.0`) is the one place; `tools/qol.py` puts it on the credits screen when the game is built.

## 3. Tests: the goldens are the PC's screens

The sessions (`tests/sessions`) type the wheel's answer and their goldens show the PC's credits and menu, so a game with these changes cannot match them. The Makefile builds the faithful game (`QOL=0`) for every target that plays a session (`QOL_OFF_GOALS`: `first-light`, `combat`, `exploration`, `baseline`, `game-run`, `game-view`, `game-wav`, `game-state`, `stress`, `perf-*`, `floppy-run`, `floppy-check`, `ide-run`, `ide-check`, `sdc-run`, `io-budget`) and the changed game for the rest (`game`, `play`, `floppy`, `sdc`, `ide`, `dist`...). `make game-run S=boot-title QOL=1` plays a session on the changed game (the credits screen then differs from its golden, as it should).

* **[V]** `make first-light` on the faithful build: `boot-title` 3 of 3 labelled screens equal, `create-character` 4 of 4 labelled and 16 of 23 unlabelled equal, DGROUP 0 open differences (the comparison with the host's party records needs `make host` once, as before).
* **[V]** the changed build: the credits, the menu entry, the `RETURN TO BASIC  YES NO` prompt, the splash of the floppy set (6809 and 6309) and of the IDE card (master, 8 bit) in MAME.

## 4. Not done

* The camp menu's `Quit` prompt and the Drop prompt (one member left) were not played; they are the same patch as the training hall's prompt, which was.
* The SDC file was built (`make sdc`, its `POOL.BIN` carries the storage lines) but not run in MAME; the floppy set and the IDE card were.
