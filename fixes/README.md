# fixes/: bugs of the original, fixed for every port

`src/` is the original program: `make match` and `make rebuild` prove it byte for byte, so a bug of SSI's code stays in
it. A fix lives here instead, as a unified diff against `src/` (paths `a/<FILE>`, `b/<FILE>`), named in `series`. Every
port applies the series to a copy of `src/` (`apply.py`) and builds from the copy:

| Port | Where | Without the fixes |
|---|---|---|
| DOS (`ports/dos`) | `tools/build.py` applies them before the port's own `patches/series` | `make FAITHFUL=1` (no patch at all) |
| C translation (`c/game`, the SDL host) | `tools/c/pas2c.py` translates the fixed copy | `pas2c.py --faithful` |
| CoCo 3 (`ports/coco3`) | the same translator, `scripts/game_build.sh` | `make QOL=0` (the PC's game, which the goldens are) |

A fix changes the game only where the original goes wrong, so the recorded sessions of `tests/sessions` still play
the same on a fixed build (the DOS port's `make sessions`, `make c-golden`). Where the original's mistake is on screen
in a recording, the fixed build shows something else at that checkpoint: `expected.toml` lists each such checkpoint
with its fix, and `make c-golden` requires the screen to differ there and DGROUP and the heap to stay the original's
(`poolrad_replay --expect`). Any other difference still fails, and so does an entry whose screen no longer differs. Each patch's comments say what the original
did, how it was found and reproduced, and what the fix changes.

| Fix | Bug |
|---|---|
| `quick-combat-hang.patch` | A computer-run (Quick) character whose readied weapon is missile-only (darts) hangs the game when an enemy stands next to it and the target it remembers is out of reach: `AiTurn` (ovl09) asks `UseBestItem` for a melee weapon and gives the pass back to `QuickTurn`; darts carry `FlagSlotItem` without `FlagAttack` (ITEMS row 9), so `UseBestItem` picks them again as its melee choice, nothing changes, and `QuickTurn` calls `AiTurn` forever (the character panel redrawn, no key read). Seen on a real Tandy 1000 EX (2026-11-01); reproduced in the oracle. Now `AiTurn` attacks its target with the darts when they are still readied, and `QuickTurn` ends the turn (`EndOrGuardTurn`) after 50 `AiTurn` passes, where a normal turn takes one or two. |
| `stale-location-line.patch` | After a script moves the party to another map (the boat from New Phlan, walking from the Slums through the gate) the location line under the roster (position, facing, time) still shows the old map's values until the first turn or step: `RunAreaStep` (ovl03) draws the new area but not the line, and `HandleWildernessKeys` (ovl14) draws it only after a key. Reported from play (2026-11-11), reproduced on the C translation (saved game A, turn to face east, step into New Phlan: the line says `15,4 E` at (0,4)). Now `RunAreaStep` draws the line together with the area, as ECL command 45 already does. |

To write one: `python3 fixes/apply.py /tmp/stage` (the current fixes applied), copy the file you change, edit it, and
`diff -u --label a/X.PAS --label b/X.PAS before after > fixes/name.patch`; add the name to `series`.
