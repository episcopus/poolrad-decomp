# 65 Consistency (Phase 6)

**Inputs:** a tree where `make check` passes (every routine L2, `make rebuild` IDENTICAL);
`docs/process/READABILITY.md`; `re/renames.toml` (every rename so far with its evidence).

**Goal:** the same thing has one name everywhere, every symbol of the program has a real name where the
evidence allows one, and a shared value is defined once. Names and comments never change the code, so this
phase is checked by the tools that already exist: `make match` (all units), `make rebuild` (IDENTICAL),
`make readability`, `make check`.

## What phase 6 covers

| Kind | Rule | Tool |
|---|---|---|
| Routine | no routine keeps a map name (`resNN_fn_XXXX`, `ovlNN_eN`, `System_rtl_XXXX`); an initialisation part is `<unit>_init` | `make rename OLD= NEW= WHY=` |
| Global | every `dsXXXX` that code reads or writes has a real name; a `dsXXXX` left in `POOLVARS.PAS` is a storage cell of the DGROUP layout (a named view is declared over it) or an object nothing reads | `make rename` |
| Alias | one object has one name: `ExperienceTable` (not also `ds409B` and `ClassXpTable`), `ItemTable`, `OvrResult`, `CheckBreak` are used directly | edit the unit, then `make dgroup` and `make match` |
| Shared value | a constant that two or more units define lives once in the `const` block of `src/POOLVARS.PAS` headed "Constants shared by several units"; units drop their copies | by hand, then `make match` |
| Runtime library | the Turbo Pascal runtime units (res00, res01, res13, res14) carry TP names, tagged **[I]** (read from the disassembly, `make packet UNIT=res00`); they are library, never decompiled | `make rename` |

## Procedure

1. List what is left unnamed: routines with a map name (`grep -c '_fn_\|_rtl_\|_MemOp_' re/symbols.toml`
   names), `dsXXXX` used outside `POOLVARS.PAS` (`grep -rE '\bds[0-9A-F]{4}\b' src/*.PAS`).
2. For a global, read every use (the context of each caller) and the comments of its declaration; the name
   must say what the value is for in the game, with the address that shows it in the evidence. A value that
   is written and never read gets a name that says so (`UnreadWord6AB2`), not a guess.
3. Rename with `make rename`. Run `make dgroup` (the layout generator must still report 0 problems; Turbo
   Pascal lines are limited to 127 characters, so wrap comment lines that a longer name pushed over),
   `make match`, `make rebuild`.
4. For shared values: find names defined in more than one unit (the same name with the same value, or two
   names for one value), check the value against the table the game keeps (`StatusNames`, `ClassNames`,
   `RaceNames`, ...), define it once in `POOLVARS.PAS`, delete the local copies, and replace synonyms. A
   name whose value contradicts the table is a wrong name, not a synonym (phase 6 found `StatusDead = 1` in
   ovl04 and ovl05: status 1 is Animated, 6 is Dead, 8 is Gone).
5. A conflict that evidence cannot settle (two names for one affect number, a value used in two meanings) is
   written down in the findings below, not guessed.
6. `make check`, commit one kind of change at a time (`p6: <what> [L2]`).

## Done when

`make check` passes; no routine of `re/symbols.toml` has a map name; every `dsXXXX` a routine reads has a real
name or is a storage cell; no constant name is defined in two units with two values; the findings below
are empty or each has an owner. The reviewer signs each subsystem off (`make review-pass`).

## Hand-off

`make handoff` with a `CHANGELOG=` row naming the kinds of change (renames, merges of aliases, shared
constants), as for any unit; `make integrate` merges it. The evidence of every rename is in
`re/renames.toml`; the findings stay in this playbook.

## Done in the first pass (2026-10-15)

- The 204 globals the code reads by offset named from the evidence in their comments; `ds409B`, `ClassXpTable`, `ds5582`, `ds43DC`, `ds84F0` merged into `ExperienceTable`,
  `ItemTable`, `OvrResult` and `CheckBreak`; seven never-read index base bytes named.
- All 1024 routines named: 17 game routines that still had entry names, the sound driver's 15 and the
  runtime units (res00 System, res01 Crt, res13 Dos, res14 Overlay; evidence **[I]**).
- About 225 constant definitions that repeated across units moved into one shared block (status, side,
  class, race, view mode, direction, game variable, affect protocol, tile, size, spell limit constants);
  the names that contradicted `StatusNames` are fixed; `Green` (10) is `LightGreen`, as in Crt.

## Findings (review of the first pass, 2026-10-15)

Affect numbers named twice were settled by the review of 2026-10-15 from the game's own text
(`DisplaySpellEffects` in ovl15 and the `AffectId` byte of `SpellTable`): $1E `AffectCough`, $1F
`AffectHelpless`, $20 `AffectAnimateDead`, $32 `AffectMummyDisease`, $37 `AffectPoisoned`, $3A
`AffectHeldFast`, $4A `AffectForcedAttack` (its handler is ovl13 `ForcedAttack`, it never drains), $4B
`AffectBloodDrain`; all are in the shared block now. $6F is `AffectPoisonImmunity` and $7D `AffectUndeadImmunity`
(the handlers cancel the charm, ends-turn, paralysis and poison hooks; the carriers are named in ovl12). `AffectEndsTurn` ($35, Sleep's AffectId) and `AffectParalysis` ($34, Hold Person's; also given
by fear) keep their effect names.

Spelling: every identifier says `Color` (about 40 names said `Colour`; `Green` is `LightGreen`). Screen and
prompt constants that two or more units defined (`BottomRow`, `ScreenCols`, `KeyYes`, `KeyNo`, `KeyExit`,
`AnswerNo`, `AcceptExtendedKeys`, `ClearTextBeforeMessage`, `NoChoice`, `Strength17`) are in the shared block;
`PromptRow` is `BottomRow`, `Yes`/`No` are `KeyYes`/`KeyNo` and `Strength18` is `ExceptionalStrength`.

Still defined per unit on purpose, because the values differ by screen: the window rectangles and colours
`Message*`, `List*`, `Prompt*Color`, `NameRow`, `LastClass` (7, but 6 in ovl17's scan).

Not done in this pass:

- **Ownership of globals.** Globals still live in `src/POOLVARS.PAS` because it is also the DGROUP layout
  (playbook 50); moving each to the unit that owns it needs the layout generator to read several units.
- **Reviewer sign-off per subsystem** (SPEC 10, P6 exit): done for ovl03, ovl12, ovl16, res07 and res12 on
  2026-10-16 (independent read-only reviews, must-fix findings applied; each `work/reviews/<unit>.md` has a
  "Phase 6 sign-off" section). ovl12 M12 (bare numbers) was finished the same day (shared `Align*`, `Creature*`,
  `HalfOnSave`, `TurnUndeadIndex` in POOLVARS). The `ClassMask` field of TCharacter became `ClassCombo` (an index 0..16; the item and `ClassBits` masks keep
  their names) and res12's flag parameters and locals are Boolean now. Open: the should-fix lists of the reviews
  (`Thac0`, `B84`, `HpB1`, `Flag10D`, `Guarding`, `TileGate`, `SortEntries` as the ScanTargets result list), and the
  Byte flags that travel through many units (the results of `EndCombatTurn` and `GuardTurn` and the `Done` var
  parameters of ovl08, ovl09, ovl19 and others), which a translator should read as Boolean. The other units have not had a
  phase 6 review. `make review-pass` is not rerun: it would restamp the round 2 pass.
- **A lesson of the review:** a name is only as good as the evidence of its first use. The reviews found
  names that two units read differently (`ResistValue` was the armour class, `Flag11B` the hit points,
  `SoundHitMessage` the affect sound), comments that a later rename made false and constants copied into
  a unit after the shared block existed; scan for those three after every consistency pass.
