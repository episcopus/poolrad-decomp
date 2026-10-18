# Step 8.2: the CoCo profile of the translator, the placement model and the 4bpp goldens (report)

Date: 2026-10-17. Plan: `docs/coco/PORTING-GUIDE.md` section 9, row 8.2, with D12 confirmed as the hybrid of
`PHASE-8.1c.md`. Tags: **[V]** verified here by running a tool or the game, **[E]** estimate.
Reproduce with `make coco-host`, `make place-host`, `make golden4` and `make sizes` (all from `ports/coco3`; the host
targets need `make c-golden` once in the repository root).

## Exit criterion

| Criterion | Result |
|---|---|
| a CoCo profile of `pas2c` | done: `tools/c/pas2c.py --profile coco` writes C that CMOC 0.1.100 compiles for all 46 units with no hand fix (section 1) |
| a host build with the CoCo memory model | done for the hybrid placement: mapped 16-bit heap, banked accessor with two data windows, engine blocks as before (section 3) |
| a host build with a 4bpp screen model | done: `ega_to_4bpp`, the screen as the CoCo shows it, digested at every checkpoint (section 4) |
| all seven sessions play on the host with the new model | **done** for both the coco profile (full game state compared byte for byte, as in Phase 7) and the placement model (screens, reads, Random calls and files compared) |
| 4bpp screen goldens recorded | **done**: 971 checkpoints in `goldens/4bpp`, equal on the PC profile, the coco profile and the placement model |

What is **not** done, on purpose (section 6): pointer fields and records keep the PC's 4-byte layout, so the
save-file format is untouched; the picture, blit and text units are still the Phase 7 translation (EGA planes) behind the
4bpp view, not the native engine (that is 8.3); the accessor cost is counted, not timed.

## 1. The coco profile of the translator [V]

`pas2c --profile coco` (generator changes, `tools/c/p2c_coco.py` for the text of the result). The PC profile's output is
unchanged: `make coco-host` checks it against `c/game` byte for byte first.

**In the generator (the Pascal types are known):**

| Change | Why |
|---|---|
| the left operand of every `+ - *`, `div`, `mod`, `shl`, unary minus and comparison is cast to the class Turbo Pascal gives the operation (`(s16)a + b`, `(s32)w + i`) | CMOC computes two byte-sized operands in 8 bits and takes the left operand's signedness (8.0 probe); under standard C the casts do nothing |
| variant records are named unions with member paths (`x.u.a1.Field`) | CMOC has no anonymous unions |
| string concatenation is `rtl_str_cat_v(dst, n, a, b)` | no compound literals |
| aggregates are cleared with `memset` after the declarations | CMOC rejects `= {0}` for arrays of records |

**In the text pass:** parenthesised declarators; pointers to arrays as pointers to one-array wrapper structs (168
wrappers); `x -= y` written out and signed byte stores of negative constants as unsigned (the two CMOC 0.1.100 code
generation bugs of 8.1); 32-bit and negative enumerators as `#define`s; comma statements split; `POOL_VIDEO` and `POOL_CAP`
for the EGA window and the 65,520-byte array bound (valid C for the host, 16-bit for CMOC); `#pragma pack` hidden from CMOC.
The counts are printed by the translator (`coco profile: {...}`).

**Proof.** The coco profile's output is built on the host and every session replayed with the full state of the game
(DGROUP, heap, screen) compared at every checkpoint, exactly as the PC profile: **all seven pass**. So the casts, wrappers,
named unions and `memset` zeroing change nothing the game computes. CMOC compiles the same text: `make sizes`.

**What the casts cost [V].** Correct width semantics add code that 8.1's text-patched C did not have: all 46 units come to
**258,179 bytes** (8.1: 245,986, which silently computed byte arithmetic in 8 bits wherever a constant was involved):

| | x86 | CMOC -O2 | CMOC -O2 `-fomit-frame-pointer` | CMOC with the placement |
|---|---:|---:|---:|---:|
| overlays (35), code | 197,641 | 219,273 (1.11) | 213,232 (1.08) | 221,406 |
| all 46 units, code | 235,705 | 258,179 (1.10) | 252,042 (1.07) | 260,363 |
| overlay constants | | 11,532 | | |

Three units now exceed the 16 KB window with their constants: `ovl16` (23,125), `ovl03` (16,819) and `ovl13` (16,577);
`-fomit-frame-pointer` brings `ovl03` just under (16,325). So D4 stays at a 16 KB window with **three splits**
(`ovl16` into two or three parts, `ovl03` and `ovl13` by a few routines). A saving is available where the result of an
operation is stored into a byte (8-bit arithmetic then gives the same low byte): not taken yet, about 2 to 4% [E].

## 2. Bugs and surprises found by running it [V]

- **`ovl25:115` indexes `ReadPromptChoice_TWordSpan[-1]`** (an original quirk: the Pascal reads a word before an array). The
  PC host build tolerates it at `-O3`; the placement build crashes at `-O3` in `RunCombat` and passes at `-O2`, `-O1` and
  with UBSan (bounds off). The placement script builds at `-O2`. 8.3 must either reproduce the quirk (a guard word) or fix it.
- **The profile build of `parley-combat` diverges only with `-finstrument-functions`** (8.1c): the same family of
  reads of stack garbage. Not found yet.
- **`TCharacter.Affects` is an untyped `Pointer` field** that the game uses as a `PAffect` list: the allocation
  `GetMem(Who^.Affects, 9)` had no pointee type. `placement.toml` has a `[pointer_fields]` override. It is the only one the
  sessions hit; the translator reports every engine-class dereference by game logic (below) so more can be found.
- **A mapped-class pointer can be nil or point at a local** (`Item^.Next` read when the list is empty; `WalkLine(@Map)`).
  Both are valid native addresses on the CoCo (page zero, the stack), so `pool_fpm` accepts them and counts them (46 nil
  reads in `parley-combat`, 8,941 into the stack).
- **Saved records contain heap pointers** (`TCharacter` +127 Affects, +200 Items, +204 SlotItems, +260 Next, +264 Combat;
  `TMenuLine` +42 Next; `TAffect` +5 Next). With a different heap the bytes differ although the game did the same. The
  replay files of the placement model mask them (`export_replay.py --pointer-masks`, 6 sessions, about a minute each). The
  CoCo save format (D7) should not write them at all.

## 3. The placement model on the host [V] (`make place-host`)

`pas2c --profile coco --placement ports/coco3/placement.toml`: each pointer type is one of

| Class | Dereference | Allocation | Here |
|---|---|---|---|
| mapped | `FPM(T, p)`: a 16-bit address in the 64 KB map | `rtl_getmem_m`: a mapped heap in the DGROUP segment, offsets `$8800` to `$FDFF` (30,208 bytes) | `TCharacter`, `TAffect`, `TMenuLine`, `TCombatant`, `TCombatNode`, `TLineState`, `TReturnEntry`, `TCombatMap`, `TMapRows`, `TWallTiles`, `TWallSets`, `TGeoCellBlock`, `TBlock400`, `TScoredCharacter`, the character views `TSheetFields`, `TAbilityBlock`, `TDamageDice`, `TResistView` |
| banked | `FPB(T, p)`: the block is mapped into the data window first | the PC heap | `TGameVars`, `TEclCode`, `TMemPic`, `TPictureHeader`, the two script word views |
| engine | `FPD` (as before) | the PC heap | pictures, fonts, 8x8 banks, sprites, DAX buffers, raw byte views |

The host runtime (`c/rtl/heap.c`, `-DPOOL_PLACEMENT`): `pool_fpm` **fails the run if a mapped-class pointer is not a 16-bit
address of the mapped segment** (or nil, or a local); `pool_bank_map` models two 8 KB windows with least-recently-used
replacement and counts maps and misses; the PC heap starts above the 64 KB segment (`HeapOrg` 2C7C) so the mapped heap
fits. A static check (`tools/placement_check.py`): of 257 statements that use banked data, 11 use two different banked
pointers and **none uses three**, so two windows always suffice.

**Results.** All seven sessions play: the reads in order, the **screen at every checkpoint, the Random calls and the files
written (heap pointer fields masked) equal the original's**, and the 4bpp screens equal `goldens/4bpp`:

| Session | Mapped heap peak (of 30,208) | Mapped dereferences | Window misses |
|---|---:|---:|---:|
| boot-title | 4,392 | 1 | 1 |
| create-character | 5,160 | 1,243 | 4 |
| create-elf-mage | 5,176 | 1,404 | 7 |
| walk-explore | 7,144 | 15,395 | 4 |
| camp-save | 7,144 | 8,656 | 4 |
| camp-rest-combat | 10,808 | 16,966 | 13 |
| parley-combat | 10,808 | 85,604 | 111 |

Two things this settles. **The mapped class needs at most 10.8 KB live** in these sessions, against the 22 KB the 8.1c
budget allowed for hot data: the placement chose its classes conservatively and there is room to map more (the ECL buffer
and game-variable blocks, now banked, are 11.8 KB; mapping them as well would still fit). **A window miss is rare** (111 misses in
7 million maps in the longest session; the map count is dominated by the idle key-wait loop), so the
accessor's cost is its call overhead, not map switching.

**Engine-class blocks the game logic dereferences anyway** (`placement-report.txt`, 27 static sites): `TPicture` in `res12`
(9), raw `TByteArray` views in `ovl17` (8), `res12` (4), `ovl07` (1), `ovl03` (1) and `u8` in `ovl16` (4). Each needs an
engine call (a picture's width and height, a block copy) or a class: that is the list for the engine API of 8.3.

**Code size with the placement [V]:** mapped dereferences are free (a cast), banked ones add a call: 260,363 bytes against
258,179 (+2,184, +0.8%).

## 4. The 4bpp screen model and goldens [V] (`make golden4`)

`ega_to_4bpp` (c/rtl/ega.c): the screen as the GIME shows 320x200x16: two pixels a byte, the left pixel in the high nibble,
160 bytes a row, 32,000 bytes, with the 16 EGA palette register values. `poolrad_replay --screens4 FILE` writes the SHA-256
of the 32,000 bytes followed by the 16 palette bytes at every checkpoint (and, with `--dump`, the raw `.scr4`);
`tools/scr4png.py` shows one. The digests are in `goldens/4bpp/<session>.s4`: **971 checkpoints**, recorded from the PC
profile host build (whose screens equal the original's at every checkpoint) and equal on the coco profile and the placement
model. A native CoCo engine (8.3) must reproduce them: the MAME script dumps the screen at the same checkpoints, a Python
step hashes it the same way. Palette values map to the GIME by `((e & 7) << 3) | (e >> 3)` (guide 2.1).

## 5. Answers to the guide's decisions and questions

| | Answer |
|---|---|
| D5 (how to produce CoCo C) | decided in practice: extend `pas2c` with a profile; the PC profile's output is untouched and checked on every `make coco-host` |
| D12 (data model) | the hybrid works on the host as specified: classes by pointee type, a placement table, mapped pointers are 16-bit addresses, two banked windows are enough. Remaining: layout (section 6) |
| Q5 (pointers in saved files) | all heap pointers in saved records are listed (section 2). `LoadCharacterFile` clears four of them (`Next`, `Items`, `Affects`, `Combat`) right after the read and rebuilds the lists; `SlotItems` (13 pointers) is rebuilt by the game when the items are readied (not verified that nothing reads the stale values) |
| open from 8.1c | a nil or local-address mapped pointer is valid; `Affects` needs an override |

## 6. What is left, and what step 8.3 takes over

1. **Layout.** The 4-byte pointer storage of the PC is kept, so records, files and DGROUP offsets are unchanged; mapped
   pointers are 16-bit values in 32-bit fields. Compacting them (a `TCharacter` of 273 bytes instead of 285) is a decision
   with D7 (save format) and costs the full-state comparison; do it together with the save-file work.
2. **The engine.** The seven picture, blit and text units run as the Phase 7 translation on EGA planes and are viewed as
   4bpp at the checkpoints. 8.3 replaces them with the native engine and the 4bpp goldens judge it. The 52-call API of 8.1c
   section 2 plus the 27 sites above are its specification.
3. **The CMOC build.** The 46 units compile; nothing has run on a 6809 yet. 8.3 brings the engine core, the loader and a
   mapped-heap and banked-window implementation in assembly; `farptr` becomes a 16-bit type for the mapped class only then.
4. **The three over-size units** (`ovl03`, `ovl13`, `ovl16`) need a split table for the bank build (8.3 or 8.4).
5. **The `ovl25:115` out-of-bounds read** (section 2).
