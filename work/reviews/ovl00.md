# Review: ovl00

decompiler: dec-1 (Agent trailer of 2012dbb; earlier commits 00d8c6a and 551e46c carry none)
reviewer: rev-4
date: 2026-10-11
commit: 474751c

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl00` (rerun): `HeapErrorHandler` 106 bytes plus 66 pool, `ovl00_init` 18;
`unit: complete, 190 bytes of code plus 0 of paragraph padding cover the original segment`.
`make readability UNIT=ovl00` is clean. Packet: `build/packets/ovl00.md`.

Routines: `HeapErrorHandler` (ovl00:0042), the unit initialisation `ovl00_init` (ovl00:00AC).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

### Resolved in the previous cycle (rev-1, commit dbc6aa9, fixed in 2012dbb)

- [x] must-fix HeapErrorHandler: the QUIRK said the handler never returns because QuitGame halts (ovl00:00A3); that holds only for Size > 0. Size = 0 takes `jbe` at ovl00:004C to ovl00:00A3, which returns with the unassigned result. (fixed in 2012dbb)
- [x] must-fix whitepaper 5.15: same overstatement; now states the Size = 0 early return first. (fixed in 2012dbb)
- [x] should-fix ovl00_init: the initialisation at ovl00:00AC had no comment of its own; the comment is now there. (fixed in 2012dbb)
- [x] should-fix ds557D: POOLVARS named ovl17_e9 as the writer; this unit only reads it (ovl00:0075), and the comment now says so. (fixed in 2012dbb)

### This cycle (rev-4)

- [ ] note HeapErrorHandler: the 40-byte frame (`sub sp,28h`, ovl00:0045) is the `$O+` stack copies of the two `string[40]` constants (`System_StrCopy`, 0AF8:0B0B, at ovl00:005F and ovl00:008E) plus `Quit` (bp-3) and the Integer result (bp-2); no local is missing. Worth knowing when reading the frame, not a defect.

## What was verified

1. `make match UNIT=ovl00` rerun: complete, both routines L2. `make readability UNIT=ovl00` clean.
2. Names true and specific: `HeapErrorHandler(Size: Word): Integer` is the handler the unit installs into the System `HeapError` vector at DS:4414 (ovl00:00AF..00B8 stores 0016:0025, the ovl00 stub segment and this entry, whitepaper 3.6); `ovl00_init` is that install. `Quit` is the repeat gate at bp-3.
3. Types fit: `Size: Word` is proven by `cmp word [bp+6],0; jbe` (unsigned, ovl00:0048); `Quit`/`ds49D0`/`ds557D` are bytes compared with 0 (ovl00:004E, 0069, 0075, 0098); the result is an Integer word at bp-2 (ovl00:00A3). `Yellow = 14` is the `al,0Eh` pushed at ovl00:0052 and ovl00:0081. The two string literals are passed through `String40` (`procedure ShowMessageLine(Color: Byte; Text: String40)`, RES06).
4. Comments give addresses and meaning: the zero-size early return and the unassigned result, the two messages, the `ds49D0` branch, the retry on `ds557D`, `QuitGame` on the non-zero path, and the init comment (ovl00:00AC stores `@HeapErrorHandler`). `re/units.toml` names ovl17 `SaveLoad` [V], so "the save and load unit" is backed; the `ovl17_e9` call is ovl17:1D58 at ovl00:0070.
5. No record type is declared here.
6. Quirk kept and marked: `QUIRK ovl00:004C`, the Size = 0 path returns the unassigned result without calling `QuitGame`.
7. No `inline`, no `db`, no `assembler`.
8. Behaviour claims match whitepaper 5.15 and are tagged [V].
9. Stub signature this unit set is recorded: `procedure ovl17_e9` in `re/symbols.toml` and `src/OVL17.PAS` (ovl00:0070, `retf`, nothing pushed).
10. Whitepaper 5.15 records what the unit taught, and 3.6 the `HeapError` slot at DS:4414.

## Verdict

Passed. Every name, type and comment is true to the bytes and the whitepaper; the one note is frame reading only and does not block.
