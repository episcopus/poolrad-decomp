# Review: ovl19

decompiler: dec-haiku (most routines), dec-1, dec-5, dec-6, dec-9, dec-15, dec-luna, orch (the `Agent:` trailers of the unit's commits)
reviewer: rev-sonnet
date: 2026-10-13
commit: 05e8e32 (second round; the first round reviewed 592a40d)

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl19` (rerun): 21 matched, 0 differ, 0 stubs; `unit: complete, 11026 bytes of code plus 0 of
paragraph padding cover the original segment`. `make readability UNIT=ovl19` is clean. Packet:
`build/packets/ovl19.md`. No `inline`, `db` or `assembler` in the unit (item 7). The signatures of the
RES12, OVL22 and OVL31 routines the unit calls are all recorded in `re/symbols.toml` (item 9; the two
argument-less ones, `res12_fn_27D9` and `res12_fn_2B88`, have an empty `signature`, which is right for a
parameterless procedure). I checked the quirk addresses (0467, 15BB, 19A1, 19B4, 1D1A, 21EE, 2468, 24EF), the
call sites of `CanGiveUpItem` (1339, 1365, 1443), `ShowCharacterSheet` from `TradeMoney` (219D), the combat
call at 03F5, the `cwde` sites (00CF, 01A1, 04E3, 0B3F) and the record offsets of `TSheetFields`,
`TAbilityBlock`, `TDamageDice` and `TMenuLine` (63 bytes) against the packet: all true. I also read the
name tables from `poolrad/start-unpack.exe` (see the first finding).

Routines: `ShowCharacterSheet` (004A), `ShowCharacterMoney` (050D), `ShowCombatStats` (0608),
`ShowAbilityScore` (0901), `ViewSelectedCharacter` (0AB3), `CanGiveUpItem` (0D70), `RunItemMenu` (0EF8),
`ReadyItem` (14D0), `TradeItem` (1734), `HalveItem` (17ED), `JoinItem` (189D), `UseItem` (1A8A),
`SellItem` (1CEE), `IdentifyItem` (1F52), `TradeMoney` (2156), `ChooseAndDropMoney` (24A7),
`WouldOverloadInventory` (275B), `UpdateSelectedCharacter` (27DF), `CharacterMoneyValueInGold` (28BE),
`ChooseSpellFromList` (299C), the empty `ovl19_init` (2B0D).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [x] must-fix ShowCharacterSheet (ClassNames, AlignmentNames, StatusNames): the sheet indexes three name
  tables whose declared bounds are shorter than the data, and the unit says nothing about it (checklist 3
  and 6). The bytes (DS image, `poolrad/start-unpack.exe`): `ClassNames` (DS:0D38, 27 bytes apart) holds 17
  real names, 0 Cleric .. 7 Monk, then 8 Cleric/Fighter, 9 Cleric/Fighter/Magic-User, 10 Cleric/Ranger,
  11 Cleric/Magic-User, 12 Cleric/Thief, 13 Fighter/Magic-User, 14 Fighter/Thief, 15
  Fighter/Magic-User/Thief, 16 Magic-User/Thief (the table ends exactly where `RaceNames` starts: (0F03 -
  0D38) / 27 = 17); the sheet reads `ClassNames[ClassMask]` at ovl19:01D2 and `ClassMask` is 0..16
  (POOLVARS), yet POOLVARS declares `array[0..7]`. `AlignmentNames` (DS:0F53, 17 apart) has 9 entries, the
  ninth being Chaotic Evil, and `StatusNames` (DS:1047, 13 apart) has 9, the ninth being "Gone"; both are
  declared `[0..7]` and re-describe only eight (`re/dseg.toml` evidence "Lawful Good .. Chaotic Neutral",
  and the sheet reads them at ovl19:0198 and 04DE). The whitepaper (5.4 sheet paragraph) and `dseg.toml`
  call the multi-class names "read past its eight entries **[I]**", which suggests garbage; they are the
  real multi-class names **[V]**. Fix: declare the three arrays with their real bounds (0..16, 0..8, 0..8
  in POOLVARS, an additive shared edit), say in ShowCharacterSheet's comment that `ClassMask` 8..16 are
  the multi-class names, and correct the whitepaper and the `dseg.toml` evidence to [V]. (fixed in ff13b01)
- [x] must-fix ViewSelectedCharacter, RunItemMenu, CanGiveUpItem: the two numbers that decide which words
  the menus offer are left bare (severity definition: "a meaningful number left bare"). (a) The view mode
  `ds49F3` is compared with 1, 2, 3 and 4 as bare numbers in RunItemMenu (ovl19:0FA4, 0FAB, 0FB2, 10EB, 111A)
  and with a bare 5 three times in ViewSelectedCharacter (0ABA, 0BEA, 0D09), while
  RunItemMenu, ReadyItem and UseItem each declare their own local `ViewCombat = 5`. The comment explains
  1 (VisitTemple's shop/temple), 2..4 (Use) and 5 (combat), so the meaning is known: name the modes once
  (a unit-level constant block or `ViewMode...` constants in POOLVARS) and use them everywhere.
  (b) The computer-run test on `B84`: `B84 < $80` is bare in ViewSelectedCharacter (0BC4), RunItemMenu
  (0FFA, 10CD) and `Affects[n] > $7F` in CanGiveUpItem (0DB4) is bare, while ShowCharacterSheet names the same
  `B84` test `ComputerRunThreshold = $7F` and UseItem names a different `$80` `AffectFlag`. Give the
  `B84` bit one unit-level name (POOLVARS says bit 7 marks a computer-run member, ovl10:0675) and the
  scribe bit of the scroll affects its own (`Affects[n] >= $80`, whitepaper 5.22), so the three uses of
  `$80` in this unit are not confused with each other. (fixed in ff13b01)
- [ ] should-fix JoinItem, RunItemMenu, WouldOverloadInventory: more bare limits. The stack ceiling 255
  (JoinItem, ovl19:19F6 and three more times in the source) is the byte limit of `Count`; `Affects[1] < 2` (19B4) says which
  items may be joined and has no name or explanation beyond the QUIRK; the Halve test `ItemCountC7 < 16`
  (RunItemMenu) and `MaximumItemCount = 15` (WouldOverloadInventory) are the same item limit written two
  ways and in two places (name it once, in POOLVARS).
- [ ] should-fix CanGiveUpItem, RunItemMenu, ViewSelectedCharacter, SellItem, UseItem, TradeItem,
  ShowCharacterSheet: window rectangles, colours and prompts are bare in most routines but named in
  IdentifyItem (`MessageLeft..MessageBottom`, `PromptTitleColor` = 13, `PromptWordColor` = 10,
  `PromptHotColor` = 15) and ChooseAndDropMoney. The same message window (1, 21, 38, 22, colour 14) and the
  same yes/no colours (13, 10, 15) appear bare in CanGiveUpItem, RunItemMenu (`'Drop It? '`) and
  ViewSelectedCharacter (`ReadPromptChoice('View:', ..., 13, 10, 15)`), and SellItem names the window but
  not the colours of `AskYesNo`. One shared set of constants would let a port rename them in one place.
  The trailing bare `0, 0, 0, 0` / `0, 0, 1, 0` / `5, row, 0, 1` arguments of `res12_fn_0442` (eleven call
  sites) are the same: nothing in this unit says what its last four bytes mean (it draws or prepares an
  item's line; `LongInt(Character)` is the first argument cast from a pointer). A short comment on one of
  them (the first in ShowCharacterSheet, ovl19:044F) saying what the modes do would serve all eleven.
- [ ] should-fix (shared TCharacter, ReadyItem and others): provisional field names the unit gives a role.
  `ds100` is the number of hands in use (`ds100 + RaceRow[ItemType][1] > MaxHands`, ReadyItem 1569); `PadB0`
  is the character's class bit set tested against the item's class byte (ReadyItem, "Wrong Class", 162A);
  `ItemCountC7` is used as the item count six times (RunItemMenu, WouldOverloadInventory) and
  `Combat^.Pad2` is the flag that offers Use in combat; `B9E` and `ByteA0` are named `Sex` and `Alignment`
  in the unit's private `TSheetFields`, and `Pad112` bytes `Count`, `Sides`, `Bonus` in `TDamageDice`,
  while POOLVARS still calls the first two "meaning not settled" and the last "Pad". The private overlay
  records work and compile to the same code, but a port reads POOLVARS first: put the names in
  `TCharacter` (additive edits to a shared file) and drop the overlays if the code still matches. The
  `ovl09` review already asks for `ds100`, `PadB0` and `RaceRow` (renamed to an item-type table) to be
  renamed; `make rename` will update this unit's source with them.
- [ ] should-fix (globals) `ds49F3`, `ds5D96`, `ds6821`: used in this unit with a settled meaning and still
  `dsXXXX`. `ds49F3` is the view mode (POOLVARS comment: ShowEndingNarrative, VisitTemple, ovl31; used ten
  times here), `ds5D96` is the head of the party list (UpdateSelectedCharacter walks `Next` through it;
  POOLVARS even says "head of the TCodeRec list ovl14 walks", which contradicts `TCharacter.Next: the next
  character of the party list (ds5D96)` in the same file, so one of the two comments is wrong), `ds6821`
  forces the Items window to be redrawn. `ds5D96` needs the evidence reconciled and then a name
  (`PartyHead`?); `ds49F3` is `ViewMode`; `make rename` does it.
- [ ] should-fix unit comment (line 2): "Inventory: the party's carried-item menus and selection/transfer
  routines (whitepaper 5.4; strings at ovl19:0AB3)". "strings at ovl19:0AB3" is the address of
  ViewSelectedCharacter, not of strings, and the comment leaves out half of the unit: the character sheet
  (ShowCharacterSheet and its three helpers), the View command, the item menu and its actions, the money
  Trade and Drop commands and the spell-list chooser. List the main routines, say that the unit is the
  View command (shop V key, Temple, camp, combat) and that RunItemMenu is also called by PlayerTurn
  (ovl08:031A, per the packet).
- [ ] should-fix ShowCharacterSheet: the comment omits the "(NPC)" tag drawn after the name for a
  computer-run member (`B84 > $7F`, ovl19:0092) and the sex/race/age/alignment/class tables' bounds
  (see the must-fix). A `ComputerRunThreshold` named `$7F` for a "> $7F" test is correct but reads
  oddly next to `< $80` elsewhere.
- [ ] should-fix ShowCombatStats: the comment does not say that it first calls `res12_fn_0BB8` (the carried
  weight is recomputed, so Encumbrance is current) and why `Affect: Pointer` is declared (an out parameter
  of `res12_fn_2199` that is never read). "THAC0 (60 minus HitAdjust ...)": POOLVARS also has a `Thac0`
  field at +$2D (the class to-hit value); say that the sheet does not show it, or the next reader will
  think the wrong field was used. "why 60 [I]" has no evidence behind the [I]: say what was observed
  (the `mov ax, 3Ch` at ovl19:06DC).
- [ ] should-fix ViewSelectedCharacter: the comment lists the words but not when each is offered. Items:
  the character carries items (`Items <> nil`); Spells: a memorized spell (`Spells[0..20] > 0`); Trade:
  money, view mode not 5, and `B84 < $80` or `Flag10D = 0` or `Status = 1`; Drop: money. Also say that the
  routine ends with `res12_fn_27D9` (restores the screen? the other callers describe it as the screen
  redraw) and that Done is cleared on entry. The condition under Trade is the same as RunItemMenu's and
  deserves one explanation of why a computer-run active member may not trade.
- [ ] should-fix RunItemMenu: (1) the comment says "UseItem may set it" for Done; outside combat the
  routine clears Done again after UseItem (`if ds49F3 <> ViewCombat then Done := 0`, ovl19:1310..131A), so Done
  survives only in combat; state that. (2) Use is offered only when `Flag10D <> 0`, VarNoCasting is zero
  and the mode fits; the comment gives the mode and the Pad2 test but not `Flag10D`. (3) The routine returns
  at once when the character has no items (`if not (ItemCountC7 > 0) then Exit`, a written-out `= 0`); the
  comment says the menu "is drawn only when the character carries items", which hides the early Exit.
  (4) The loop `Cursor` that calls `res12_fn_0442(..., 0, 0, 1, 0)` over every item does not draw anything
  on screen as far as the call arguments show; the local comment says "the loop that draws the list stands
  on"; say what the call does (builds each item's display name, presumably).
- [ ] should-fix RunItemMenu (Drop): the message is `'Your ' + Selected^.Text + 'will be gone forever'`
  with no space before `will`, while the comment (and the whitepaper, [V]) show "Your <item> will be gone
  forever". Either the item name already ends with a space (then say so, with the evidence, in the
  comment) or the original prints "Your Long Swordwill be gone forever" and that is a QUIRK to mark.
  I could not settle it from the bytes of `res12_fn_0442`, which is not decompiled.
- [ ] should-fix IdentifyItem: the price is paid even when the item has nothing to identify
  (`HiddenNames = 0`, "I can't tell anything new about your <item>"): the money is taken before the
  `HiddenNames` test, ovl19:1FEB..202C against the test at 205F. The whitepaper says "The price is paid either way", but the unit
  comment does not, and it is the kind of behaviour a port must keep although it looks wrong. Mark it
  `QUIRK ovl19:205F` (the `HiddenNames` test) so a porter does not "fix" it.
- [ ] should-fix SellItem: (1) the gold part of the payment is credited to the character even when
  WouldOverload refused the coins (only the platinum is limited by Room), so the character can end above
  his Room; say so (QUIRK or note). (2) `Offer * Item^.Count` is a Word product and can wrap; a port
  using a wider integer would pay differently. (3) The routine names the pointer for the item line
  `SheetCharacter` (ovl19:1D55) while the seller is `SelectedCharacter`; the comment says so, good, but the
  POOLVARS comment for SheetCharacter gives the address as 1D59; make them agree (the call site is 1D59
  for the pointer push, per the packet).
- [ ] should-fix UseItem: `ItemAffectUse := True` is also set around the call of `ovl22_e5` for every use
  (ovl19:1BC2 sets it, 1BE2 clears it); the comment only says the Affects[2] case sets it. Say that the
  flag is true while the spell is cast (POOLVARS says the same) and that the first assignment is only the
  Affects[2] case. `DisplayMode` is passed as `UseListMode = 1` ("meaning not known yet") while
  ViewSelectedCharacter passes 0: say in ChooseSpellFromList that the meaning of the second argument is
  `Purpose unknown:` (what is known: ovl22_e1 receives it with Choice).
- [ ] should-fix WouldOverloadInventory, UpdateSelectedCharacter, ChooseSpellFromList: their comments are
  below the standard of the rest of the unit (checklist 4). WouldOverloadInventory gives no parameter or
  result meaning (Character: the recipient; Item: what is added; True: refuse) and does not say what
  `res12_fn_0BB8` does (it recalculates the carried weight, ovl19:275B..). UpdateSelectedCharacter
  does not say who calls it (eleven callers: the G and O keys of the shop, temple, camp, treasure and
  wilderness menus; the Key parameter is the key those menus read, Home/End or keypad 7/1 per OVL04) nor
  that with a nil party head it stores nil in SelectedCharacter (the final assignment runs on every path). ChooseSpellFromList says what it does with
  `Choice` but not what its result is (the spell byte `ovl22_e1` returns, 0 when `Listed` is 0), what `Listed` is for the callers, or who calls it (ovl13, ovl15, ovl16, this unit).
  `Choice: Word` is tested as `Integer(Choice) < 0` and passed as `$FFFF`; say that Choice is a signed
  index kept in a Word because `ovl22_e1` declares it so.
- [ ] should-fix whitepaper 5.4 (line 487) and the unit table (line 168): ovl19 is described as "partially
  matched"; the unit is complete and reviewed here. Update the status words (playbook 60).
- [ ] note ShowCombatStats: `Move` is a local that shadows `System.Move`, which HalveItem uses; it compiles
  and matches, but a port renaming locals should pick a different name (`MovementRate`).
- [ ] note TradeMoney: the QUIRK for `Finished` (ovl19:2468) is accurate: on the first pass with a nil
  `Chosen` the loop test reads an uninitialised stack byte. A port must choose a defined value; the likely
  intent is that a cancelled list ends the trade (`Finished := True`), which is not what the original does.
- [ ] note ReadyItem, SellItem: `RaceRow[ItemType]` (an item-type table) and the two item kinds `$49` and
  `$1C` (named `ItemKindSlot11` and `ItemKindSlot12` in SellItem, after the body slots 11 and 12 ReadyItem
  checks) are names borrowed from other uses; the evidence is in the comments and the whitepaper, so they
  are accepted here, but they should become real item-kind names when the item table is decoded.
- [ ] note CharacterMoneyValueInGold: parameter is `Who` where every other routine of the unit says
  `Character`; harmless.

## Round 2 (2026-10-13, commit 05e8e32)

Rerun: `make match UNIT=ovl19` says 21 matched, 0 differ, 0 stubs, `unit: complete`; `make readability
UNIT=ovl19` is clean. Both must-fix findings are closed and I checked the fixes, not only the ticks:
- Name tables: POOLVARS now declares `ClassNames` `[0..16]`, `AlignmentNames` `[0..8]` and `StatusNames`
  `[0..8]` (lines 898, 901, 905); the `dseg.toml` evidence for the three says 17, 9 and 9 entries with the
  table end addresses [V]; ShowCharacterSheet's comment says 0..7 are the single classes and 8..16 the
  multi-class names; whitepaper 5.4 (line 634) says the same with [V].
- Bare numbers: a unit-level constant block names the view modes (`ViewModeShop` 1 .. `ViewModeCombat` 5,
  with who sets each and where), `ComputerRunB84` / `ComputerRunThreshold` for the B84 bit 7, `AffectFlag` /
  `AffectThreshold` for Affects[3] bit 7, and `ScribeAffectThreshold` for the scroll's scribe bit; the grep
  for bare `ds49F3 = n`, `< $80` and `> $7F` finds none left in code. The two spellings of each bit test
  are explained and backed by a probe (`tools/re/tp_idioms/ovl19/PB19BIT.PAS`).
The should-fix and note findings of round 1 stay open and do not block.

## Verdict

Passed: the two must-fix findings of round 1 are fixed and verified; the unit matches (complete) and reads
true, and only should-fix and note findings remain open.
