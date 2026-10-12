# Review: res08

decompiler: dec-2 (Agent trailer of bd9a3f4; the unit was re-applied in dfca441)
reviewer: rev-4
date: 2026-10-11
commit: fdfc118

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

Routines: `res08_init` (042B:00A4), the whole unit (its initialisation part).

`make match UNIT=res08` (rerun): `res08_init` 748 bytes plus 164 pool; `unit: complete, 912 bytes of
code plus 0 of paragraph padding cover the original segment`. `make readability UNIT=res08` is clean.
Packet: `build/packets/res08.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] must-fix res08_init: the two self-assigning copies are QUIRKs and the source does not mark them. `ReadLn(CfgText, GameDir)` is followed by `GameDir := GameDir`, a `System_StrLCopy` with the same source and destination (`lea di,[$547C]` twice, limit $FF) at 042B:032D; `SaveDir` has the same at 042B:0358. Whitepaper 2.3 calls them "a self-assigning `S := S` QUIRK" and 2.2 cites `042B:032D`/`042B:0358`. A reader takes them for a bug. Mark each `QUIRK 042B:032D:` and `QUIRK 042B:0358:` (or comment why they are kept).
- [ ] should-fix res08_init: the heap is cut twice but the comment names only one. The `T` branch cuts it at 042B:01CF and the unconditional cut at 042B:02E2 (after the sound line) runs for every mode, so `T` cuts twice. The routine comment says "T: 2 with a smaller heap" and does not mention the second cut; a port that dropped it would be wrong.
- [ ] note res08_init/spec: the unit directive is `{$A-,O+,F+,S-,R-,G-,I-}` while res08 is a resident unit (`042B`). This is real: `OvrInit('GAME.OVR')` at 042B:00AF copies the literal to a stack temporary with `System_StrCopy` before the call, the `$O+` form, while the `Assign`/`WriteLn` literals in the same routine are pushed directly. Whitepaper 2.2 records it `[V]` ("`$O+` is not overlay-units-only"). AGENTS.md ("overlay units add O+") and SPEC 3 item 6 still say overlay-only, so the source is right and the spec text needs the human's decision. Escalated.
- [ ] note res08_init: `GameDir` is DS:547C, the same slot the ovl11 source calls `ds547C` (StartGame saves, empties and restores it). `POOLVARS.PAS` and `re/dseg.toml` name it `GameDir`; ovl11's `ds547C` is the stale name. Cross-unit naming, Phase 6 (ovl11 is blocked on the matcher issue anyway).
- [ ] note res08_init: `HeapWords` is `array[0..1] of Word absolute HeapEnd`; `match.py --all` (in `make check`) cannot resolve it ("global HEAPWORDS has no original offset") while `make match UNIT=res08` can. The approved `absolute`-alias tool fix (task/tools-alias) covers this; the single-unit match and readability here pass.

## What was verified

1. `make match UNIT=res08` rerun: complete, `res08_init` L2. `make readability UNIT=res08` is clean.
2. Names true and specific: `CfgProbe`/`CfgProbeResult` (the untyped existence probe), `CfgText`/`CfgChar` (the text file and the choice just read), `GameDir`/`SaveDir` (POOL.CFG lines 3 and 4), `NewHeapEnd`, `HeapWords`, `ds84F0`, `ds43DC` (overlay result), `ds49D1` (the F flag), `ds4A1A`/`ds4A1B`/`ds4A1D` are all named for what they hold and carry `POOLVARS.PAS` comments with the write address. `VideoAdapter` and `SoundMode` are the shared globals.
3. Types fit: `VideoAdapter`/`SoundMode`/`ds4A1A`/`ds4A1B`/`ds4A1D`/`ds49D1`/`ds84F0` are `Byte`, `CfgChar` is `Char`, `GameDir`/`SaveDir` are `string`, `NewHeapEnd` is `Pointer`, `CfgProbe` is `File`, `CfgText` is `Text`, `ds43DC` is `Word`, `HeapWords` is `array[0..1] of Word absolute HeapEnd` (`HeapWords[0]`/`[1]` are the offset and segment words the disasm reads at `[$4408]`/`[$440A]`).
4. Comments give addresses and meaning: the res05 call, `OvrInit('GAME.OVR')`, the probe loop with `'Please insert startup disk.'` and `ReadGameKey`, the `DS:84F0` clear, the `POOL.CFG` open and `Unable to find POOL.CFG`, the three video arms (`E`: 1 and `$0D`; `T`: 2 and the heap cut; else 0 with `res07_fn_00CF(4)`), the `$18800` overlay buffer and the `Not enough memory to run game.  You need N more bytes.` message, the overlay-error halt, the three sound arms (`T`: 0, `P`: 1, else 2), `res03_fn_017B`, the two directory reads and the F flag.
5. The `CfgText`/`CfgProbeResult`/`SavedVideoMode` overlap is documented in `POOLVARS.PAS` as time-shared DGROUP; the disasm writes `IOResult` to `[$49CD]` (inside the `CfgText` slot) and the video mode to `[$4A02]`/`[$4A1C]`, which the comments explain.
6. Quirks: the two self-assignments are not marked in the source (the must-fix); the heap double cut is the should-fix. No `inline`/`db`/`assembler`.
7. Side effects stated: files, screen, heap, sound, halt. `OvrGetBuf`/`OvrSetBuf`/`OvrInit` come from the `Overlay` unit.
8. The caller: `res08_init` runs from the main program's initialisation chain (POOL.PAS); the packet finds no direct caller because it is an init entry. Whitepaper 2.3 and 2.2 describe it `[V]`.
9. No stub signature is owed: the unit declares no procedure and sets no signature in another unit.
10. Whitepaper 2.3 records what the unit taught (the five POOL.CFG lines, the probe, the video/sound arms, the self-assigning QUIRK, the overlay buffer, the heap cut); 2.2 records the `$O+` fact.

## Verdict

Not passed. One must-fix: the two self-assigning `S := S` copies at 042B:032D and 042B:0358 are QUIRKs and the source leaves them unmarked.
