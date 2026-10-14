# Review: ovl03

decompiler: dec-haiku, dec-deepseek-2, esc-grok, int-loop
reviewer: rev-sonnet
date: 2026-10-14
commit: e052339 (round 1 reviewed 3165044)

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

First review. `make match UNIT=ovl03` says `unit: complete` (55 matched, 1 nested (WriteScanResults in
ScanPartyCommand), 0 differ, 0 stubs, 13581 bytes). `make readability UNIT=ovl03` is clean. `make stubs`
reports every stub header matching `re/symbols.toml`. The packet is `build/packets/ovl03.md`. Every routine
has an entry in whitepaper 5.1 (the ovl03 opcode paragraphs).

Spot checks against the packet disassembly (all hold): `cmp al,38h` at 3135, `call RunCamp` at 33E7, the
`cmp byte ptr [bp+di-4],0FFh` slot loop at 0D7B, the `Kind := 3` store at 175F overwritten at 1769 (RollRangeCommand
QUIRK), `inc word ptr [49EDh]` at 2AA5 (the one-byte commands), the `$FF` test at 024D (RandomCommand QUIRK). The
`$6BA7` and `$6C1B` stat addresses are script addresses, not record offsets: GetCharacterVar (ovl07:0391..0416)
maps `$A5..$AC` to `ThiefSkills[Addr - $A4]` and `$11B` to `Movement`, so the ScanPartyCommand comment is right.
ReadNumber's "0 to 65536" agrees with RES06 (QUIRK 0709:0BBF). The EngineActionCommand word constants add up
(`$AC91 + $7FFF = $12C90` and so on). The `ds4A00` claim (DrawTextRun waits per glyph) is RES06:358.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [x] must-fix DamagePartyCommand (ovl03:2775) / `TrapOneTargetBit`: the name and its comment ("bit 7 picks one target; clear: the number of hits") say the opposite of what the code does when bit 6 is also set. With bit 7 set the code runs three different cases: bit 6 hits the whole party (`WholePartyHit`, every member saves), else operand 5 bit 7 picks the selected character, else one random member. So bit 7 is the saving-throw mode (the targeted trap), not "one target", and the routine comment contradicts itself ("picks one target ... bit 6 hits the whole party"). Rename (for example `TrapSavingThrowBit`) and fix both the constant comment (ovl03 constants, "ECL command 46") and the routine comment. Also say what bit 6 does with bit 7 clear: `MemberNumber` is not rolled and the loop `for I := 1 to Flags` then counts bit 6 into the number of hits (Flags $40 or more means 64 or more hits), which is a QUIRK to mark `QUIRK ovl03:2775`. (fixed in 01ef132)
- [x] must-fix RunAreaStep (ovl03:31B4), RunAreaEventCommand (ovl03:179B), EndCommand (ovl03:0001), NewLineCommand (ovl03:2AEB): constants of this unit that exist are left unused, and the comments point at them. `ViewModeWall = 4` and `ViewModeMap = 3` are used only in RunWilderness; RunAreaStep writes `ds49F3 := 4` once and `ds49F3 := 3` three times and RunAreaEventCommand writes `ds49F3 := 4` / `3`, although the constant's own comment says RunAreaEventCommand sets "the same pair". EndCommand ends with `GlyphRow := $11; GlyphCol := 1` while the comment on `EclTextLeft`/`EclTextTop` says "the one EndCommand (ovl03:0001) also puts it at"; use `EclTextTop`/`EclTextLeft` (ShowTextCommand and ChooseFromListCommand do). NewLineCommand's `GlyphCol := 1` is `EclTextLeft` too. Use the constants. (fixed in 01ef132)
- [x] must-fix RunAreaEventCommand (ovl03:179B), PauseCommand (ovl03:271F), RedrawAreaViewCommand (ovl03:2AA2), NewLineCommand (ovl03:2AEB), ClearPictureWindowCommand (ovl03:2B14): the comments misdescribe `Inc(EclPC)`. RunAreaEventCommand says it "counts its calls in EclPC (purpose unknown)", PauseCommand and RedrawAreaViewCommand say it "counts EclPC up ... and does not move EclPC itself", the last two say "Inc(EclPC) counts the command (see EclPC)", and POOLVARS `EclPC` has no such note. These are one-byte commands with no operands (DecodeOperands is never called; `inc word ptr [49EDh]` at 2AA5 is the first instruction after the prologue), and `Inc(EclPC)` steps the program counter past the opcode so RunScriptFrom (ovl03:3171) reads the next command, exactly as ApproachEncounterCommand (ovl03:0817), ClearEncounterCommand (ovl03:125D) and RunIfCompared say. Nothing is counted, and "does not move EclPC itself" is false. Say so in all five comments and drop the "purpose unknown". (fixed in 01ef132)
- [ ] should-fix EndCommand (ovl03:0001): the comment leaves out its main effect and three writes: `ds442E := 1` (the script run ends: RunScriptFrom's loop test, POOLVARS ds442E), `ds84E0 := 0`, `ds84E2 := 0` and `ds84DE := 0`. Say that it ends the script run.
- [ ] should-fix DispatchCommand (ovl03:2F2D) and LoadAreaGraphics (ovl03:0C74): the opcodes 0 to 3, 8 to 21, 28 to 30, 32 to 36, 38 to 46, 49 to 54 and 56 to 61 are bare case labels (and `SkippedOpcode = $21`, `$37` is bare in LoadAreaGraphics) while OpAdd..OpMul, the OpIf* group, OpAnd, OpOr, OpChooseAddress and OpContinueText are named. The handlers carry the command number in their comment, so the table is recoverable, but a port wants one list of opcodes. At least name the ones the handlers test themselves (`$21` in LoadAreaGraphics, `$11` is already `OpContinueText`).
- [ ] should-fix dsXXXX globals whose meaning this unit and the rest of the source already establish: `ds442E` (script run ended), `ds442F` (a script block started, so RunAreaStep repeats), `ds4431`, `ds84E0` (close-up up), `ds84E3` (3D sprite loaded), `ds84E9` (skip the close-up unless monster pictures), `ds4A00` (RES06:358: per-glyph text delay; its POOLVARS comment mentions only the loader and EndBattle, add DrawTextRun and ShowTextCommand/EncounterActionCommand), `ds84DD` (saved low bit of word 714), `ds6F83` (the encounter icon slot; the constant `FirstEncounterIcon` already names its start), `ds49F3` (the view mode). Rename with `make rename` where the evidence is in POOLVARS.
- [ ] should-fix ds6810 (POOLVARS, used in 24 places here): the POOLVARS comment says only "the shop's item list", while AddLootCommand and ClearEncounterCommand here, OVL05 (ChooseLootItem, ComputeBattleExperience) and OVL13 use it as the loot list, and whitepaper 5.1 calls it both "the item list" and the loot list. ClearEncounterCommand calls it "the item list ds6810", AddLootCommand "the loot list ds6810". Pick one name (the shop's stock list and the loot list are the same list, OVL06 ShopMain shows it) and say so in POOLVARS.
- [ ] should-fix ComputePartyValueCommand (ovl03:12C6): the local `Checksum` is not a checksum (it is the sum over the party of a weighted strength figure, divided by 10 per member), and `ClassLevel5`/`ClassLevel0` carry the index, not the class. POOLVARS `ClassMask` says class 0 is cleric and 5 magic-user; if `ClassLevels` uses the same indexing, call them `ClericLevel`/`MagicUserLevel` (the comment already says "class levels 0 and 5"), else say why not. `Flag11B` is read into `HitPoints` here and the comment says "current hit points (Flag11B)"; POOLVARS tags that [I]. Fine, but rename the field in POOLVARS when the evidence is firm (ovl09 review made the same point).
- [ ] should-fix colours, windows and picture numbers that are bare: `DrawWindow(3, 3, $D, $D, 0, $F, '')` three times (EndCommand, ShowCloseUpCommand) and `..., 0, $A, '')` in RunAreaStep (the close-up box, columns and rows 3 to 13; `CloseUpLastRow = $D` exists), `DrawSprite(3, 3, 1, ...)`, `GlyphCol := 2; GlyphRow := 2` in DamagePartyCommand, `Load24x24Set('BACPAC', 0, 40)` twice, the ICON picture slots 9 to 11 (RunAreaEventCommand), `ShowPagedText(..., 1, ...)` / `0` clear flag, `ReadNumber(Prompt, 10)` (EclTextColor is 10 but is not used; say so or use it), `AskMenu(..., 0, 0)`, `FormatItemLine(..., 0, 0, 0, 0)`, `AreaViewKind` 1 to 4 (the comments say 1 is the 3D wall view and 2 to 4 are map pages; `WallModeMapPage2..4` exist), `PictureShown[0]`/`[1]`. Name the close-up box constants at least.
- [ ] should-fix EncounterActionCommand (ovl03:1EF8): the five `ChoiceKind` values 0 to 4 are bare case labels for five outcome tables, and `Lines`/`Line` loops are explained only through the comment. A one-line meaning per kind table (what a kind 0 script wants: only flee is checked; kind 2: the monsters flee; kinds 3 and 4: a parlay path) in the comment would help; the existing text describes the written words but not why a script picks a kind. `ds84CC` cases 8 and 10 in EngineActionCommand (ovl03:2CCF) are bare too (POOLVARS says "meaning unknown", so a `Purpose unknown:` note there is enough).
- [ ] should-fix LoadAreaGraphics (ovl03:0C74): the comment says command 33 loads the 3D map "when VarForceWallView is set" but the code also requires `Blocks[1]` to be neither `$FF` nor `$7F` (`$7F` is described only for command 55), and `GameVars^[231]`, `GameVars^[232]` and `ds49D6^[713]` stay bare (the comment says "not named yet", acceptable as such; give them `Var...` constants like the others, as VarWord714 has).
- [ ] should-fix RunCamp (ovl03:2DD3): the comment says the script "runs ... (through ovl03:3171, not decompiled yet)"; RunScriptFrom is decompiled, say `RunScriptFrom`. The sentence about callers is split by "Then the area view is drawn again", reorder. `ds557D := False` is stated with no reason (POOLVARS: "who sets it is not shown"); mark that as unexplained in a `QUIRK`-style note or say "Purpose unknown".
- [ ] should-fix ChoosePartyMemberCommand (ovl03:2B33): "SelectPartyMember is the selection the learning notes call SelectPartyMember" says nothing; replace by what SelectPartyMember (RES12) does and what the Mode 0 argument is. The "Who is untyped in RES12.PAS" remark belongs next to the call as a comment on the cast, not the routine header.
- [ ] should-fix DamagePartyCommand (ovl03:2775): "Then PartyDestroyed (PartyDestroyed) is 1 unless a member has Flag10D (combat participation) set" repeats the name; say "PartyDestroyed is set to 1 unless a member has Flag10D set (POOLVARS: combat participation)". Also the "screen 'The END!'" is the window title passed to DrawWindow, not a screen name.
- [ ] should-fix stray comment before RedrawAreaViewCommand (OVL03.PAS line 1867): `{ ovl03:2AA2: retf 0: 0 bytes of parameters; 0 bytes of locals }` is the skeleton's leftover and duplicates the routine comment; delete it.
- [ ] should-fix AddEncounterGroupCommand (ovl03:0450): locals `Who` (the loaded character), `Last`, `Saved`, `Items`, `Affects` are generic; `Who` is the character `LoadCharacter` just loaded and `Template` its copy source. Name them for their roles (`Loaded`, `Tail`, `SavedCharacter`). `if Count <= 0` on a Byte is `= 0`; keep it but say so (the original compares the byte with 0).
- [ ] note ReadNumberCommand (ovl03:0951): "a number from 0 to 65536" is right for ReadNumber; say that 65536 is accepted and becomes 0 (QUIRK 0709:0BBF in RES06).
- [ ] note ScanPartyCommand (ovl03:1435): `Found: ShortInt` and `Stats: array of Byte` are chosen to match; the comment explains the shape. Fine. The QUIRK for the empty party is marked.
- [ ] note AddLootCommand (ovl03:19B0): the treasure Code table (1 to 100 mappings) is written out in full and carries two QUIRKs (the overlapping `91..98`/`86..92` labels in the code and Roll2 48/49 keeping the previous Code in the comment). The latter has no marker in the code at `case Roll2` (ovl03:1BB7); a `{ QUIRK ovl03:1BB7: 48 and 49 leave Code unchanged }` there would help. Local `Unused: array[0..22]` is marked.
- [ ] note FindMemorizedSpellCommand (ovl03:2C03): the four QUIRKs are all marked and explained; the unit is the best-documented example of a bug-compatible routine here.

What was verified: every routine comment starts with its address; every command number named in a comment matches the case arm of DispatchCommand (checked all arms; 31 and 62 up have none, as the comment says); the constants `CodeBias`/`Action*` add up; `VarShopRequest`, `VarTempleRequest`, `VarStepsAhead` and the other GameVars words are used with the offsets the comments give; every `QUIRK` marks a real frame byte or unreachable assignment (the `Unused` locals match the frame sizes in the packet); no `inline`, `db` or `assembler`; the only nested routine (WriteScanResults) is proven by the parent's match; stubs that this unit declares match `re/symbols.toml`.

## Verdict (round 1)

not passed: three must-fix findings (the misleading `TrapOneTargetBit`, the unused named constants, the "counts EclPC" comments); the rest of the unit was well documented.

## Round 2 (rev-sonnet, commit e052339)

`make match UNIT=ovl03` says `unit: complete` (55 matched, 1 nested, 0 differ, 0 stubs, 13581 bytes),
`make readability UNIT=ovl03` is clean, `make stubs` finds every stub header matching `re/symbols.toml`.
I re-read the fix commit 01ef132 against the code and the earlier must-fix findings:

- DamagePartyCommand: `TrapOneTargetBit` is gone; `TrapSavingThrowBit` ($80) is used in the test at ovl03:2775 and the
  constant comment and routine comment now describe the three saving-throw cases (whole party, selected character, one
  random member) and the number-of-hits mode, in line with the code. The bit 6 / bit 5 counting quirk is marked
  `QUIRK ovl03:2775` in the routine comment, inside the `else` branch and in whitepaper 5.1. The `TrapSelectedBit` and
  `TrapBonusMask` constants exist and are used. Closed.
- `ViewModeWall`/`ViewModeMap` are used in RunAreaStep and RunAreaEventCommand, `EclTextTop`/`EclTextLeft` in EndCommand
  and NewLineCommand (grep shows no remaining bare `ds49F3 := 3/4` or `$11`/`1` text cursor writes in those routines).
  Closed.
- The five one-byte command comments (RunAreaEventCommand, PauseCommand, RedrawAreaViewCommand, NewLineCommand,
  ClearPictureWindowCommand) now say that `Inc(EclPC)` steps past the opcode so RunScriptFrom reads the next command;
  no "counts" or "does not move EclPC" text remains, and the stray skeleton comment before RedrawAreaViewCommand is
  deleted. Closed.

The bytes are unchanged by the fix (match still complete). New findings of this round:

- [ ] should-fix RunAreaEventCommand, PauseCommand, RedrawAreaViewCommand, NewLineCommand, ClearPictureWindowCommand: the new
  comments end with "(see EclPC)", but the POOLVARS comment of `EclPC` (line 860) says only "set to $9900 by the loader
  (ovl11:03C0)". The pointer leads nowhere; add to the POOLVARS `EclPC` comment that it is the script program counter,
  that the dispatcher reads the opcode at it and that handlers move it past the command (RunScriptFrom, ovl03:3171), or
  drop "(see EclPC)".
- [ ] note DamagePartyCommand (ovl03:2775): `GlyphCol := 2; GlyphRow := 2` and the `1` clear flag stay bare (already listed in
  round 1); the old finding about "PartyDestroyed (PartyDestroyed)" is fixed in the text, the "window 'The END!'" wording
  is now right.

The open should-fix and note items of round 1 are unchanged and none is a must-fix: they are weak names, bare
colours and window numbers, and thin comments, not wrong ones.

## Verdict

passed: all three round 1 must-fix findings are fixed and verified against the code, no must-fix is open; the should-fix
findings above stay for the decompiler.
