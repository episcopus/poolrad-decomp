# Review: ovl11

decompiler: dec-4 (Agent trailer of a864d03; 195afb6, 6e3314e document and probe it)
reviewer: rev-4
date: 2026-10-11
commit: d6165f3

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

Routines: `StartGame` (ovl11:002D), the empty `ovl11_init` (ovl11:0615).

## Blocker: `make match UNIT=ovl11` does not pass, and the cause is the runtime map, not this unit

`make match UNIT=ovl11` (rerun) stops at the first difference:

```
DIFF  StartGame  ovl11:002D  call into SYSTEM+0B0B: no POOL routine corresponds
      (runtime routine POOL never uses: wrong library call?)
```

The instruction is ours at ovl11:0602: `lcall 0133:0B0B`; the original has `lcall 0AF8:1247`
(`System_Randomize`). The source is right: OVL11.PAS calls `Randomize` (line 162), the original
calls `Randomize` (0AF8:1247), and our fresh System routine at 0133:0B0B is the compiler's
Randomize body (`B4 2C CD 21 89 0E 3E 00 89 16 40 00 CB`), the same as POOL's `0AF8:1247`
(`B4 2C CD 21 89 0E 28 44 89 16 2A 44 CB`) apart from the two RandSeed DS operands.

`tp_toolchain.runtime_names` fails to map that fresh entry. `runtime_entries` (after commit
588597a, "resolve runtime call targets by routine entry") scores the hand-added POOL entry
`0AF8:1247` (13 bytes) and finds only 6 bytes present in the fresh System, so its `2 * here >
end - e` test rejects it. The four DS-operand bytes (`28 44`, `2A 44`) fall in a non-same-length
diff region and do not count as present. The POOL entry overlaps nothing now (`0AF8:120F` is 56
bytes, ending at 0AF8:1247).

To prove the unit is otherwise clean I re-ran the comparison in a scratch script with the single
missing mapping injected (`tp.runtime_names` patched, no tool or source file changed):

```
StartGame matched
ovl11_init matched
unit: complete, 1562 bytes of code plus 0 of paragraph padding cover the original segment
```

So the unit matches once the runtime call is mapped; the fix belongs in the matcher/toolchain,
not in OVL11.PAS. Escalated (`make handoff STATE=escalate`). No review-pass could be recorded.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] note StartGame/`re/symbols.toml` runtime map: the blocker above (runtime map misses the fresh `System_Randomize`, so the `Randomize` at ovl11:0602 cannot be resolved). Not a defect of this unit; escalated to the orchestrator.
- [ ] should-fix `TPresenceSlot` in POOLVARS.PAS: the fields of the 4-byte element at DS:6AAE are named `A` and `B`, placeholders, and the record comment says only "one 4-byte element of the table the loader fills (ovl11:0369..0390)". `StartGame` sets `ds6AAEWords[2].A/B := $FFFF` (ovl11:035E..0390). Their meaning is not shown by this unit, so the comment should say `Purpose unknown:` and the fields should not read as names (for example `UnknownA`/`UnknownB`), as `ds6AAEWords` already does for the table as a whole.
- [ ] note StartGame: the loop counter is the global `ds465C` (DS:465C), reused by all five loops (ovl11:0130, 02CA, 035E, 0502 and the 0353 fills). The routine comment says so; a `QUIRK` mark is not needed (the original does it), but it is the reason the three tables live at the exact DS offsets.
- [ ] should-fix POOLVARS.PAS `ds6F68`/`ds6F69`: their comments name `ovl11_fn_0435` as the writer ("set with ds84E5 := 1 by ovl07_e3 ... and ovl11_fn_0435 ($DB)"), but `ovl11:0435` is not a routine: it is inside `StartGame` (the phantom this unit's commit corrected, `re/symbols.toml` notes on `StartGame`). The writer is `StartGame` (`ds6F69 := $E8; ds6F68 := $DB`, ovl11:0435..0442). Whitepaper 5.2.1 line 506 still says `ovl11_fn_0435` too.
- [ ] should-fix OVL11 unit comment: it cites "(whitepaper 5.2.1, 5.12)". The loader's own whitepaper entry is 3.2.2 (the heading "The start-up loader StartGame", added in 6e3314e); 5.2.1 is only where the special view codes it sets are described and 5.12 is the copy protection that follows. Cite 3.2.2.
- [ ] note `ovl11_init` (ovl11:0615) is commented (empty `55 89 E5 5D CB` plus 4 bytes of padding), unlike `res04_init`/`ovl00_init`. Good.

## What was verified (source beside the packet)

1. `make readability UNIT=ovl11` is clean. The name and comments were checked against `build/packets/ovl11.md`.
2. Names true and specific: `StartGame` is the start-up loader `src/POOL.PAS` runs first. The three cell tables are `ds4EC0` (cell text scanline address), `ds5050` (per-cell row offset) and `ds51E0` (cell graphics plane address); the heap blocks are `TBlock400`/`TBlock588`/`TBlock924`/`TBlock1E00`. Every `dsXXXX` global the routine uses has a `POOLVARS.PAS` comment with the write address.
3. The heap: seven `New` of $800, $800, $400, $1E00, $588, $924 and $400 bytes at ovl11:0034..00A0, matching the routine comment and the `TBlock...` types.
4. The tables: the loop runs `ds465C := 0..$C7` (ovl11:0245 `cmp ...,$C7`); even cells take `$B800 + (i div 2)*5`, odd `$BA00 + (i div 2)*5` (ovl11:013B..0182); `ds5050[i] := i*40` (ovl11:018B..019B); `ds51E0[i] := (i div 4)*$A + $B800/$BA00/$BC00/$BE00` by `i mod 4` (ovl11:019F..0241). `LastCell`, `CellsPerRow`, `TextSegOdd/Even` and `Plane1..4` name the constants.
5. The `FillChar` clears and the global initialisations (ovl11:024F..0456) match the source line by line; the loop counter is the documented global `ds465C`.
6. The save-load half matches: the path save `ds4661 := ds547C` (StrLCopy $FF at ovl11:05EA), `ds547C := ''` and `ovl25_e3`; `res06_fn_0626(0,$18,$A,'Loading...Please Wait')`; the 12 `COMSPR` sprites (ovl32_e4, ovl11:050D..052E) plus (`$19,$19`); the `'ITEMS'` file `ds2614[ds5376] + Chr(ds547D) + ':'` (ovl11:055E..0594); `res05_fn_025D`, `Reset`, `Seek(2)`, `BlockRead` of `LoadBlockSize = $810` into `ds5582`, `Close`; the path restore; `Randomize`; `ovl22_e10`; `ovl12_e1`.
7. Types fit: `ds465C`, `ds4660`, `ds547D` are `Byte`; `ds4661` is `string[40]` (the assignment truncates through StrLCopy, documented); `ds468C` is `file`; the tables are `array[0..$C7] of Word`; `ds6AAEWords` is `array[0..3] of TPresenceSlot`; `ds6AFB` is `array[0..2] of TLoadSlot`.
8. Quirks: none beyond the global loop counter, which is documented. The false `ovl11:0435` boundary from the far-call heuristic is explained in the `re/symbols.toml` notes (the call at ovl11:060C goes to ovl12's stub entry `0041:0025`).
9. No `inline`, no `db`, no `assembler`.
10. Whitepaper 3.2.2 and 5.12 record the loader (start-up, the heap blocks, the cell tables, the save-load), tagged [V].

## Verdict

Not passed, and not as a code finding: the unit's source is correct and complete, but `make match` cannot prove the `Randomize` call until the runtime map gains the fresh `System_Randomize` entry. Escalated for the matcher/toolchain fix; the two findings above are should-fix/note.
