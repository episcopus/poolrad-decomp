# Review: ovl20

decompiler: dec-1, dec-15, dec-deepseek, dec-luna, dec-opus-cc, esc-grok, haiku-dec, int-loop
reviewer: rev-sonnet
date: 2026-10-14
commit: 636844a

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

Checked: `make match UNIT=ovl20` (unit: complete, 15 matched, 0 differ), `make readability UNIT=ovl20`
(clean), the packet, the whitepaper section 5.22.1, `re/symbols.toml` signatures (the ovl22_e6, e7, e8
stub signatures this unit relies on are recorded) and the POOLVARS comments of the globals it uses.
No `inline`, `db` or `assembler` anywhere; the unused frame bytes and the unused local are marked QUIRK.

## Findings

- [ ] must-fix RestCounterBytes, RestCounterInitial (constants): the names say "rest counter", but the
  only uses are `FillChar(ds471E, RestCounterBytes, RestCounterInitial)` at ovl20:0000 (outside camp) and
  ovl20:0CE5 (start of RunRestPeriod). ds471E is the TimedAffectFlags array (72 flags, one per member),
  and the call marks every member as due (value 1). Nothing there is a counter. The comments ("bytes
  reset at ovl20:0CE5", "initial value stored by that FillChar") do not say what the bytes are either.
  Rename to what they are (for example TimedAffectFlagCount = $48 and TimedAffectDue = 1) and say so in
  the comment. (A port reading the constants would look for a rest counter that does not exist.)
- [ ] must-fix RestFirstColumn (constant): the comment says "the column where the days field starts", but
  ShowRestTime draws the days at Col + 1 = 12 (whitepaper 5.22.1 says column 12), then the colon at 14,
  the hours at 15, the colon at 17 and the minutes at 18. 11 is the column before the days field, so the
  comment is wrong. Fix the comment (or fold the +1 into the constant) so the layout can be read off.
- [ ] should-fix ShowRestTime: the comment says days and hours are drawn "with a colon between them", but
  the loop draws a colon after each of days and hours, so the line is `dd:hh:mm` (days at column 12, hours
  at 15, minutes at 18). Say the format and the three columns.
- [ ] should-fix RunRestPeriod: the routine comment never says it first runs the Rest menu
  (`EndRest := Ord(RestTimeMenu = 0)`, ovl20:0CF3..) and rests only when the menu returns 1, nor that it
  loops until the four low digits of RestTime are zero. It says "changes ds471E" without saying that the
  FillChar marks every member's timed affects due (TimedAffectFlags), and that it zeroes
  RestStudyCountdowns first. The whitepaper has all of this; the source comment should too.
- [ ] should-fix RunRestPeriod, ovl20 (the unit): `FillChar(ds471E, ...)` is written through the alias
  ds471E in RunRestPeriod and AdvanceAffectDurations although POOLVARS says to prefer TimedAffectFlags and
  the whitepaper says a port should use it (the alias is "only the name ovl20's rest code uses"). Writing
  `FillChar(TimedAffectFlags[1], ...)` would be the readable form if it compiles the same; if not, keep it
  and say so at the call site (the comment in AdvanceAffectDurations does).
- [ ] should-fix ProcessPendingScribedSpell: the scroll test is `Affects[SpellIndex] > PendingSpellFlag`
  ($80, so byte $80 itself does not count) whereas ProcessMemorizedSpell tests `> SpellNumberMask` ($7F, so
  $80 counts). The comments say "bit 7 set" for both. A pending spell byte of exactly $80 (spell number 0)
  is probably unreachable, but the difference is a behaviour a port must keep: mark it `QUIRK ovl20:...`
  with the address of the compare, and say that the constant is used as a threshold here, not as a bit.
- [ ] should-fix ProcessPendingScribedSpell: "calls ovl22_e7 to consume it" is a guess about a stub
  (ovl22_e7 is undecompiled). Whitepaper 5.20/5.22 only say a used scroll goes through ovl22_e7. Say
  "calls ovl22_e7 (undecompiled; the scroll's use-up step) [I]" or similar.
- [ ] should-fix AdvanceRestHour: the parameter `State` is vague. It is the caller's RestCycleCounter,
  the count of five-minute steps towards RestStepsPerHour (12). Rename (for example StepsThisHour) and
  update the registry signature. Also say why `Handled := 1` is stored before the calls: it makes both
  helpers only peek at the next pending spell's level, not complete it.
- [ ] should-fix AdvanceAffectDurations, SpendRestTime, AdvanceGameClock: the parameter `Index` is the
  clock digit (MinutesDigit..), not an array index of anything the reader can see. `Digit` or
  `ClockDigit` says what it is (registry signatures to be updated by `make rename`-style edit).
- [ ] should-fix (clock digit 0): ClockRadix and RestTime have seven digits, 0..6, but only 1..6 are named
  (MinutesDigit..). Digit 0 has radix 10 and carries into the minutes (CarryRestClock loops 0..6) yet no
  comment says what it is or that no caller uses it as an Index (the callers pass 1; AdvanceAffectDurations
  stops scaling at digit 1). Note it in the unit comment or at the constants. POOLVARS lists six names
  for the seven radices (10, 10, 6, 24, 30, 12, 256).
- [ ] should-fix AdvanceGameClock: `for Digit := 0 to 6` uses a bare 6 (twice) although TopClockDigit = 6
  is the same value in the same unit. Use the constant (if it compiles the same).
- [ ] should-fix RestTimeMenu: `ReadPromptChoice(..., 1, 0, ExtendedKey)` passes two bare flags
  (ExtKeys on, Animate off, per OVL25's signature and whitepaper 5.22.1) and the case labels 'Y', 'H', 'M',
  'I', 'D' are bare characters while KeyEnter, KeyRest, KeyExit and the Scan constants are named. Name
  them (KeyDays, KeyHours, KeyMinutes, KeyInc, KeyDec) or add a comment mapping each to its menu word.
- [ ] should-fix types: AffectAtTail, HasTimedAffect, Handled, EndRest (and the RunRestPeriod result) are
  Byte flags that are only ever 0 or 1. Boolean would say it (Healed in CheckRestHealing already is
  one); keep Byte where it is needed to match, but then say so in the declaration comment. Handled is a
  `var Byte` in two public signatures and its meaning (1 = "peek only, nothing completes") is explained
  only in the routine comments.
- [ ] should-fix globals ds5D96, ds49F3, ds49D6: used 9, 2 and 8 times for the party list, the view mode
  and the second game word block, and still `dsXXXX`. ds5D96's POOLVARS comment says "head of the TCodeRec
  list ovl14 walks", while this unit (and whitepaper 5.22 Alter, "the list is ds5D96 linked by Next, +$104")
  uses it as the head of the party's TCharacter list. Names and comment should say party list. (Shared
  file, so it needs a coordinated `make rename`; see the note below.)
- [ ] note AdvanceRestStudies: RunRestPeriod zeroes every RestStudyCountdowns byte and the first
  `Dec` of a Byte 0 gives $FF, so a member's first countdown is 255 steps unless AdvanceRestHour sets it
  earlier. That wrap is probably intended by the original, but it is a port-relevant fact not stated
  anywhere; one sentence would do.
- [ ] note TCharacter.Affects: declared `Pointer`, but this unit (and RemoveAffect) uses it as a PAffect
  list head. Not this unit's file; a `PAffect` type would save the implicit conversions.
- [ ] note POOLVARS TCharacter.Age comment refers to `CarryClock`; the routine is CarryRestClock.
  A stale name from before a rename.
- [ ] note NormalizeRestTime: the days clamp sits inside the `Months > 0` branch; the comment ("keeps the
  days at MaxRestDays or less") is true in effect because CarryRestClock first reduces the days below 30,
  but it is worth one clause saying why the clamp is only reached after months were turned into days.

## Verdict

not passed: two must-fix findings (the misleading RestCounterBytes/RestCounterInitial constants and the
wrong RestFirstColumn comment); everything else is should-fix or note. The matching, quirk marks,
signature records and whitepaper section 5.22.1 are in order.
