# Review: ovl20

decompiler: dec-deepseek, haiku-dec, dec-1, dec-15, dec-luna, dec-opus-cc, esc-grok, int-loop (the `Agent:` trailers of the unit's commits; several commits carry none)
reviewer: rev-sonnet
date: 2026-10-14
commit: 717fa1e

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl20` (rerun): 15 matched, 0 differ, 0 stubs; `unit: complete, 3685 bytes of code plus 0 of
paragraph padding cover the original segment`. `make readability UNIT=ovl20` is clean. Packet:
`build/packets/ovl20.md`. No `inline`, `db` or `assembler` in the unit (item 7). The signatures of the
RES06, RES12, OVL22, OVL24 and OVL25 routines the unit calls (`RemoveAffect`, `ovl22_e6..e8`, `HealCharacter`,
`ReadPromptChoice`, `AskYesNo`, `ClearRect`) are recorded in `re/symbols.toml` (item 9). I checked the
addresses quoted in the comments against the packet (0097 `cmp ..., 0xa`, 0118 `les` before the nil test,
037B `inc word es:[di+30h]`, 0877 `inc [6DD8]`, 0B80 times three, 0CA4 `Unused`, 0CE5 `FillChar` of
`ds471E`), the digit radices (`ClockRadix` = 10, 10, 6, 24, 30, 12, 256 at DS:363A) and the roles of the
digits, the `ReadPromptChoice` contract (Escape returns `#0`, extended keys return their scan-code letter with
`ExtKey` 1), and the whitepaper section 5.22.1 against the source: the prose is accurate and the quirks
that are marked (0118, 0B0A, 0BB2, 0C9A, 0CA4) are real.

Routines: `AdvanceAffectDurations` (0000), `CarryRestClock` (02F2), `NormalizeRestTime` (03A3), `ovl20_e1`
(03D5), `SpendRestTime` (047A), `TwoDigitText` (0565), `ShowRestTime` (05F0), `RestTimeMenu` (0721),
`CheckRestHealing` (0871), `ProcessMemorizedSpell` (0925), `ProcessPendingScribedSpell` (09E7),
`AdvanceRestStudies` (0B0A), `AdvanceRestHour` (0BB2), `RunRestPeriod` (0C9A), the empty `ovl20_init` (0E60).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] must-fix ovl20_e1: the routine keeps a placeholder name and says `Purpose unknown:` although its own
  comment (and whitepaper 5.22.1) states the purpose in full: it is the game clock advance. It adds `Amount`
  units to digit `Index` of the seven game-clock words (GameVars 198..204), carries, writes back and spends
  the time on timed affects. Its callers confirm it: the end of every combat round `ovl20_e1(1, 1)`
  (ovl08:0880), movement steps `ovl20_e1(1, 1)` / `(1, 2)` and `ovl20_e1($C, 3)` (twelve hours, ovl14), the
  rest's five-minute step. READABILITY: `Purpose unknown:` is accepted only when the evidence really is
  missing; a comment that says both is self-contradicting. The given reason ("a rename is a cross-unit
  change") is not a reason: `make rename OLD=ovl20_e1 NEW=AdvanceGameClock WHY=...` does exactly that across the
  registry, sources and whitepaper. Rename it (a name such as `AdvanceGameClock`), drop `Purpose unknown:`,
  and say in the unit comment (lines 2-4, which mention only `RunRestPeriod` and `AdvanceAffectDurations`)
  that this routine is the unit's main entry for other units. Also name the bare `$49C6` (line 223 and 230,
  the first game-clock word as a `VarsAt4900` index) as a constant; the comment calls it "49C6h..49CCh" and
  the whitepaper "GameVars words 198..204", so a port cannot tell which numbering is meant.
- [ ] must-fix RunRestPeriod, CheckRestHealing, POOLVARS (ds49FB, ds6DD8, ds6DDA): the interruption test
  uses two game variables as bare numbers, `ds49D6^[$2D2]` (lines 584, 587) and `ds49D6^[$2D3]` (590),
  and the code gives no name or in-source meaning for them. The whitepaper (5.22.1) knows them: `$2D2` is
  the number of rest steps between interruption checks (the counter `ds49FB` is compared with it) and `$2D3`
  is the percentage chance, tested with a 1d100 roll (`RollDice(1, 100) <= word`); `ovl07:0160` clears both.
  Name them as `Var...` constants in the style of `VarPartySize` and say so in the routine comment (which now
  only says "ds49D6 game variables"). The three counters this unit alone gives a role are left as `dsXXXX`
  with stale comments: `ds49FB` ("cleared by the loader" only; here it counts rest steps toward an
  interruption check), `ds6DD8` ("meaning unknown"; here it counts rest steps toward the whole-party heal, 288
  steps = 24 hours, whitepaper 5.22.1) and `ds6DDA` (set to 1 for the whole rest and cleared after; RES12
  uses it to pick the top of the message window, res12:886, so it says "the rest screen is up"; the
  routine comment does not mention the write at all). Rename them with `make rename` (for example
  `RestInterruptCounter`, `RestHealCounter`, `RestWindowActive`; evidence above) or at least correct the
  POOLVARS comments, which now contradict this unit's own comments (checklist 4: `dsXXXX` globals carry what is
  known). `ds471E` (72 bytes reset to 1) is the same table as `TimedAffectFlags` from index 1; say once in
  the code comment which of the two names a port should use.
- [ ] must-fix CarryRestClock: a missing quirk mark. The top digit (6, radix 256) is never reduced, so
  once `Clock[6] >= 256` every later call ages every party member by another year, and the call is made for
  every step of `ovl20_e1` and for `NormalizeRestTime`. The comment records "the radix is kept [I]" but not
  that this repeats, and it is not marked `QUIRK ovl20:037B:` (the `inc word es:[di+30h]`). Mark it with the
  address (checklist 6) and state the consequence (the aging repeats at every carry call while the year digit
  stays at or above 256; whether the game can reach that is not proven, so say so). The bare `6` (loop bound
  and `Digit <> 6`, lines 178 and 180) should name the top digit (`TopClockDigit`).
- [ ] must-fix NormalizeRestTime, SpendRestTime, ShowRestTime, RestTimeMenu, RunRestPeriod: meaningful numbers
  left bare, although the unit shows the habit of naming them (`RestMinuteStep`, `RestHoursField`, ...) and
  then does not use them. The `RestTime` digits are indexed by raw numbers everywhere: `RestTime[1]` minutes,
  `[2]` tens of minutes, `[3]` hours, `[4]` days, `[5]` months (lines 201 to 361, 561). Name the digits once
  (`MinutesDigit` .. `MonthsDigit`; `RestHoursField` and `RestDaysField` exist but only for the menu's
  `Selected`). Further bare values: the day cap `99` (lines 205 and 206; "keeps the days at 99" is in the
  comment only), the clock size `14` of `FillChar(RestTime, 14, 0)` (253, the byte size of `TRestClock`;
  `SizeOf(RestTime)` is the same value and says why), the lender limit `5` (the months digit, lines 249 and
  251), the five minutes of the rest step in `SpendRestTime(5, 1)`, `ovl20_e1(5, 1)` (573, 580), which are
  `RestMinuteStep` (declared but used only in the menu), the `10 *` of the minutes in `ShowRestTime` (300;
  radix of the tens digit, `ClockRadix[1]`), the screen arguments `ClearRect(1, $11, $26, $16)` (556, 604;
  the rest window, whose row 17 is `RestRow`), the colours of `AskYesNo('Stop Resting? ', 13, 10, 15)` (566:
  `RestTitleColour`, `RestWordColour`, `RestHotColour` are declared and used in `RestTimeMenu`, so use them),
  `DrawTextAt(..., 'Rest Time:')` uses `RestTextColour` but the message colour 10 at line 386 is again
  `RestTextColour` while the same message window uses `RestMessageColour` 15 at 594, say which is right, and
  `HealCharacter(Who, 1, 0)` (382; one hit point, flag 0, see the next finding). The extended-key arms of
  `RestTimeMenu` (`'H'`, `'P'`, `'K'`, `'M'`, lines 324 to 332) are scan codes (up, down, left, right) written as
  letters, and `'X'` is an invented "ignore" key; the comment never says which arm is which key, so a reader
  sees `'M'` mean both "minutes" (line 346) and "right arrow" (332). Name them (`ScanUp`, `ScanDown`,
  `ScanLeft`, `ScanRight`) and say what `'X'` is for.
- [ ] should-fix CheckRestHealing: the comment says it "calls HealCharacter for every party member" but
  not that the amount is one hit point per member, per 288 steps (a day), with Flag 0 (HealCharacter then
  skips members with affect $32, per its own comment, ovl24:175D). That is the whole game effect of the
  routine and a port needs it. The message "The Whole Party Is Healed" is printed even when nobody was
  healed (the redraw alone is conditional on `Healed`); worth a one-line QUIRK/note. Also `ShowRestTime(0)`
  is called before the text only to redraw the line over the roster; say so.
- [ ] should-fix ProcessPendingScribedSpell: the comment says a pending scroll spell is "bit 7 set", but the
  test is `Affects[n] > $80` (line 441, `PendingSpellFlag`), i.e. $80 itself is not pending, while
  `ProcessMemorizedSpell` uses `Spells[n] > $7F` (line 406; the same set minus the value $80). Spell
  number 0 does not exist so the difference is likely harmless, but it is a visible inconsistency of
  the original and belongs in a `QUIRK ovl20:09E7:` line, and the comment should say "above $80" for the scroll.
- [ ] should-fix AdvanceRestStudies, AdvanceRestHour, RunRestPeriod: behaviour a port must keep and the
  comments do not say. (a) `RunRestPeriod` zeros every `RestStudyCountdowns` entry and `AdvanceRestStudies`
  then does `Dec` on a Byte at the first step, so each member's counter wraps 0 to 255 and the "reaches zero"
  test fires only after 255 more steps (21 hours of rest) unless `AdvanceRestHour` sets it first; this is
  a wraparound quirk (`Dec(RestStudyCountdowns[PartyIndex])`, ovl20:0B0A), not marked.
  (b) `AdvanceRestHour` passes `Handled := 1` (line 516) so the helpers only look up the next level and
  complete nothing; `AdvanceRestStudies` passes 0 so they complete a spell. That is the central difference
  of the two callers and the comments describe both in terms of "reads the next pending level" without
  saying why `Handled` is preset. (c) `ShortInt(Who^.RestHours) > 0` (511) means a `RestHours` above 127 is
  treated as not positive; the comment says "when positive". (d) `RestStepsPerSpellLevel = 3` is three
  five-minute steps, so 15 minutes per spell level, which is the figure `StudyRestMinutes` (ovl15:0000)
  uses (whitepaper 5.22); say so. (e) the parameter `State` of `AdvanceRestHour` and the caller's
  `RestCycleCounter` are vague: it is the count of five-minute steps in the current hour
  (`StepsThisHour`).
- [ ] should-fix ShowRestTime, TwoDigitText: `Selected = 0` (every call but the menu's) highlights nothing
  because `Colors[0]` is the unused digit 0; the comment does not say this. `Col + 1 + 1 + 1` (297) is an
  expression kept for the match; one word saying so (or the constant `ColonOffset`) would stop a port
  "simplifying" the wrong thing. The `TwoDigitText` comment still names a local `S` and "the compiler's
  string temporary"; the local is `Digits`. A number above 99 is cut to its first two digits
  (`Copy(Digits, 1, 2)`), which the comment states but does not call out as the reason the days cap is 99.
- [ ] should-fix RestTimeMenu: the comment ends with "Matched from the expert's diagnosis
  (case-e3e08f09)", which is project process, not game behaviour, and belongs in the commit or in
  `re/symbols.toml` notes; keep the 07D5/083D flow note, drop the case id. The comment says "Escape" ends
  the menu; it does (`ReadPromptChoice` returns `#0`) but 'E' (Exit) and Escape differ from a port's view
  only in the letter, and the `until` set `[#0, 'E', 'R']` should be named (`KeyEscape`, `KeyExit`,
  `KeyRest`) like the other keys.
- [ ] should-fix OVL20 (VarPartySize): `VarPartySize = 830` is declared again in this unit; the same constant
  is declared separately in OVL05, OVL10, OVL16 and OVL17, and OVL11 and OVL18 use the bare `830`. Put it
  once in POOLVARS next to the other `Var...` constants (an additive shared edit). Also `FirstPartyIndex =
  1` and `TimedAffectFlags` indexing from 1 is explained once at the declaration; good.
- [ ] note AdvanceAffectDurations: the comment and the whitepaper say "smallest units" for the result of the
  scaling; it is the digit-1 unit (minutes), because the loop stops at digit 1 (`while UnitIndex > 1`) and
  never multiplies by `ClockRadix[0]`. Say "minutes" once; the units of an affect `Duration` follow from it.
  `ScaledAmount` is a Word, so a large `Amount` at a high digit wraps (for example 255 years); not reachable
  in practice, no action.
- [ ] note whitepaper 5.22.1: it says `ovl20_e1` is "called from OVL03, OVL08, OVL14, OVL15 and RunRestPeriod";
  the sources decompiled so far show OVL08, OVL14 and `RunRestPeriod` only (OVL03 and OVL15 are not
  decompiled at the call sites, or the claim is from the registry's callers). Mark it [I] until a call is
  seen, or cite the caller address. The unit's `ClockRadix` comment in POOLVARS names six digits for seven
  values; digit 0 (radix 10, ten of them make a minute, so a combat round: ovl08:0880 passes `(1, 1)`, not 0)
  is unnamed; say "digit 0 unused by the game as far as seen".
- [ ] note ProcessMemorizedSpell: `ovl22_e8(Who, 'has memorized', Spell)` and `ovl22_e7` are still
  placeholder names of OVL22; not this unit's finding, but the unit comments call them by those names
  and the readability would improve at once when OVL22's decompiler names them (they print "<name> has
  memorized <spell>" and consume a scroll spell).

## Verdict

Not passed: the unit matches and the prose is mostly accurate, but the placeholder/`Purpose unknown:` name
`ovl20_e1`, the unnamed interruption variables and counters, the unmarked repeating-age quirk of
`CarryRestClock` and the bare clock-digit, limit and key numbers are must-fix; the should-fix items are
worth doing in the same pass.
