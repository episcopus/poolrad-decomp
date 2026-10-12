# Readability: what "readable" means for this source

The Pascal in `src/` is the starting point of every port (the C translation, then the CoCo 3) and the most exact description of the game there is. A routine that matches but is called `ovl12_fn_2233(A, B, C)`, reads `ds5372` and compares with `19` proves the bytes and explains nothing; whoever ports it has to decompile it a second time. So readability is part of decompiling, not a later phase: **a routine is done when it matches and reads well**, and a unit is done when it is complete, readable and reviewed.

Names and comments never change the code: `make match` proves a renamed, commented routine exactly as before. There is no reason to postpone them.

## When

- **The decompiler** makes every routine readable before committing it (playbook 30, step 3): it names the routine, its parameters, its locals and the globals it uses as far as the evidence goes, comments it, and replaces magic numbers by named constants. `make check` refuses a unit with a decompiled routine that breaks a checkable rule (below), so nothing reaches `main` unnamed or uncommented.
- **The reviewer** judges what no tool can (playbook 70): whether each name and comment is true, specific and backed by evidence.
- **Phase 6** then only harmonises names across units (the same thing called the same everywhere) once the whole game is known; it is not where naming happens.

## Names

| What | Style | Examples |
|---|---|---|
| Routine | PascalCase, a verb phrase saying what it does; functions say what they return; Boolean functions read as a question | `ShowMessageLine`, `ReadGameKey`, `IsPartyDead` |
| Global | PascalCase noun naming what it holds | `SoundMode`, `DebugMode`, `SavedVideoMode` |
| Parameter, local | PascalCase, its role in this routine | `Message`, `Size`, `FirstText`; `I`, `J`, `K`, `N` only as loop counters |
| Constant | PascalCase; the meaning, not the value | `KeyCtrlS = #19`, `Yellow = 14`, `VideoSetMode = $00` |
| Type | PascalCase, `T` prefix for records and enumerations | `TCharacter`, `String40` |
| Unit | the file and unit name stay the id (`RES04`, `OVL12`); its real name goes in its header comment and `re/units.toml` | |

- **A name is a claim and needs evidence**: an address, a string, a caller, behaviour observed in the oracle. The evidence goes in the routine's comment, in `re/symbols.toml` notes (`make rename` records it) or in the whitepaper.
- **Name what is known, not more.** `ShowsTextOnRow24` is better than a guess like `ShowCombatLog`. When nothing is known yet, keep the provisional name and say `Purpose unknown:` in the routine's comment with what is known (callers, globals, strings); the reviewer accepts that when the evidence really is missing.
- **Renaming a routine or a global** goes through `make rename OLD=<name> NEW=<Name> WHY="<evidence>"`: the matcher finds routines by their name in `re/symbols.toml` and globals by theirs in `re/dseg.toml`, so the tool changes the registry, every source file and the whitepaper together and logs it in `re/renames.toml`. A merge that brings back an old name is fixed with `make rename APPLY=1`. Parameters, locals, constants and types live in one unit's source: rename them in the editor.
- **Types say what values are**: `Boolean` for flags, `Char` for keys, a record type instead of offsets into a byte array once the structure is known, `string[N]` with the length the code uses. Keep whatever compiles to the same code (`make match` decides).

## Comments

- **Unit:** right after `unit X;`, what the unit is for, its main routines, and the whitepaper section.
- **Routine:** right above its header: its address (`{ 0899:0059. ...`), what it does in game terms, what its parameters and result mean, the globals it reads or changes, its side effects (screen, files, sound), and anything surprising.
- **Inside a routine:** only where the code is not obvious: why, not what (`{ the overlay may move: the compiler copies the string }`, not `{ copy the string }`).
- **Quirks:** every behaviour a port must keep although it looks wrong is marked `QUIRK <address>:` with what happens (dead code after `Exit`, unassigned results, off-by-ones). Never fixed.
- **Globals** still named `dsXXXX`: their declaration in `src/POOLVARS.PAS` carries a comment with what is known.

## What the tool checks (`make readability UNIT=<id>`, part of `make check`)

For every decompiled routine of the unit, and for the unit:

| Rule | Checks |
|---|---|
| R1 | The unit comment exists and is not the skeleton's (8 words or more) |
| R2 | The routine has a real name, or its comment says `Purpose unknown:` |
| R3 | The routine has a comment right above it, 8 words or more, with its address |
| R4 | No parameter or local is a single letter (except `I`, `J`, `K`, `N`) or a placeholder (`Tmp`, `Value1`, ...) |
| R5 | Every `dsXXXX` global the routine uses has a comment on its declaration in `POOLVARS.PAS` |

## What the reviewer judges (playbook 70)

1. Every name is true (the code does what the name says) and specific (says which thing, not just "data" or "handle").
2. Every name beyond the obvious has evidence; `Purpose unknown:` is used only when evidence is really missing.
3. The comments are accurate, say what the code means in game terms, and cover parameters, result, globals and side effects.
4. Magic numbers that mean something (keys, colours, limits, interrupt functions, offsets into records) are named constants or record fields.
5. Types fit the values (Boolean, Char, records, enumerations where they compile the same).
6. Quirks are marked `QUIRK <address>:`.
7. Names agree with the rest of the source and the whitepaper (the same thing has one name).

A wrong name or comment is a must-fix finding. A vague or weakly backed one is should-fix.
