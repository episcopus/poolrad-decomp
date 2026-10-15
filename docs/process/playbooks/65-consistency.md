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

## Findings for a reviewer (not settled by evidence)

Two names for one affect number (`InitAffectHandlers` fills the table from the number, so the value is
certain and only the meaning is open):

| Number | Names in the source (unit) |
|---|---|
| $1E | AffectCough (ovl24), AffectKeptB (ovl09) |
| $1F | AffectNausea (ovl12, ovl24, now shared), AffectHelpless (ovl15) |
| $20 | AffectKeptA (ovl09), AffectRemovedAtRaiseDead (ovl04) |
| $32 | AffectHealingBlock (shared), AffectMummyDisease (ovl15) |
| $37 | AffectPoisoned (shared), AffectPoison (ovl04) |
| $3A | AffectHeldFast (ovl12), AffectLostWithForcedAttack (ovl13) |
| $4A | AffectBloodDrainWeak (ovl12), AffectForcedAttack (ovl13) |
| $4B | AffectBloodDrain (ovl12), AffectNoPartingShot1 (ovl13) |

Still defined in more than one unit (layout and key constants, deliberately local until a screen layout
type exists): `MessageLeft/Right/Top/Bottom`, `List*`, `Prompt*`, `MessageColor` and `MessageColour`,
`KeyYes`/`Yes`, `KeyExit`, `Strength17`/`Strength18`.

Not done in this pass:

- **Ownership of globals.** Globals still live in `src/POOLVARS.PAS` because it is also the DGROUP layout
  (playbook 50); moving each to the unit that owns it needs the layout generator to read several units.
- **`tools/re/rtl_ident.py`** (phase 1) still holds the provisional runtime names in its tables; running
  `make map` again would write them over the names of this phase. Update its tables first.
- **Reviewer sign-off per subsystem** (SPEC 10, P6 exit): not started; `make review-pass` records it per unit.
