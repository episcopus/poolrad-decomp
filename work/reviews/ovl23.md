# Review: ovl23

decompiler: dec-11 (Agent trailer of 4cc356f, the redo; earlier drafts by dec-1)
reviewer: rev-4
date: 2026-10-12
commit: 4a6697e

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

`make match UNIT=ovl23` (rerun): `RecalcClassStats` 431 bytes, `AddWisdomBonusSpells` 166,
`ComputeSavingThrows` 212, `ComputeThiefSkills` 309, `ovl23_init` 5; `unit: complete, 1123 bytes of
code plus 0 of paragraph padding cover the original segment`. `make readability UNIT=ovl23` is clean.
Packet: `build/packets/ovl23.md`.

Routines: `RecalcClassStats` (ovl23:0000), `AddWisdomBonusSpells` (ovl23:01AF),
`ComputeSavingThrows` (ovl23:0255), `ComputeThiefSkills` (ovl23:0329), the empty `ovl23_init`
(ovl23:045E).

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [ ] note RecalcClassStats: the `ClassFighter` arm (ovl23:0000) sets `Attacks` from the class 2 level unconditionally, so a character with fighter level 0 also gets `Attacks := 2`; the comment says "a fighter gets Attacks 3 above level 6, else 2" without the zero-level case. The bytes are clear, worth knowing.
- [ ] note RecalcClassStats: `Thac0 := the largest ClassThac0Table[class, level]` is "best (largest)" because the table's values rise with level (level 1 gives 40, level 10 gives 46 to 49 in the image); the record's `Thac0` field is whitepaper 4.2.5's THAC0, so the word is loose but the pick is right.
- [ ] note ComputeSavingThrows: the QUIRK `ovl23:0258` frame is 4 bytes: `Save` and `ClassNo` are `ShortInt` (one byte each) and `Unused` is the other two, while the loop is over the five SavingThrows; the comment matches the bytes.

## What was verified

1. `make match UNIT=ovl23` rerun: complete, all five routines L2. `make readability UNIT=ovl23` is clean.
2. Names true and specific: the four routines and the class constants `ClassCleric` 0, `ClassFighter` 2, `ClassMage` 5, `ClassThief` 6, `LastClass` 7, `LastSpell` $38, `LastSpellLevel` 3, `LastSave` 4, `WorstSave` 20, `LastThiefSkill` 8, `DexSkills` 5, `FighterExtraAttackLevel` 6, `FewAttacks`/`MoreAttacks` 2/3, `FirstSpellLevel` 1, `ClericSpell` 0. Every table is a named `POOLVARS.PAS` global with `re/dseg.toml` evidence (`ClassThac0Table`, `ClericSlotTable`, `MageSlotTable`, `SavingThrowTable`, `ThiefSkillTable`, `ThiefRaceTable`, `ThiefDexTable`, `SpellTable`), and the record fields (`Thac0` +$2D, `Race` +$2E, `KnownSpells` +$33..+$6A, `SavingThrows` +$6D..+$71, `HighestLevel` +$73, `ThiefSkills` +$77..+$7E, `ClassLevels` +$96..+$9D, `Attacks` +$A1, `ClericSlots` +$B2..+$B4, `MageSlots` +$B5..+$B7).
3. Types fit: the loop indices are `ShortInt` (1 byte) and the stored values `Byte`; `SpellTable[Spell].Level` is a signed `ShortInt` used to index `ClericSlots[1..3]`; `ThiefRaceTable`/`ThiefDexTable` are `ShortInt` rows and their sums are stored into the `Byte` skill array.
4. Comments give addresses and meaning; the ones checked hold: `RecalcClassStats`'s Thac0 max, the `HighestLevel` raise, the fighter attacks, the cleric slots plus the wisdom bonus and the `KnownSpells` set-only rule, the mage slots, then `ComputeSavingThrows` and the thief gate; `AddWisdomBonusSpells`'s five thresholds (Wisdom 13/14/15/16/17 with a nonzero slot); `ComputeSavingThrows`'s start at 20 and minimum over the classes with a level; `ComputeThiefSkills`'s base plus signed race plus signed dexterity for the first five, and the "negative race larger than the base gives 0" rule.
5. Callers match the packet: `RecalcClassStats` from ovl12:228C, ovl16:29AE, ovl17:1446 and ovl22:2D39 (the comment's ovl12/ovl16/ovl17/ovl22); `AddWisdomBonusSpells` from ovl16 (three sites) and RecalcClassStats; `ComputeSavingThrows` and `ComputeThiefSkills` from ovl16:0B52 and RecalcClassStats.
6. Quirks kept and marked: `ovl23:0258` (the two unused `ComputeSavingThrows` frame bytes). No `inline`/`db`/`assembler`.
7. Whitepaper 5.6 records what the unit taught (the eight class levels, the four routines, the tables, the AD&D wisdom bonus and thief table, the class indices, and the `T[row, column]` idioms).

## Verdict

Passed. Every name, type and comment is true to the bytes; the three notes are informational (the zero-level fighter arm, the loose "best (largest)", the frame split).
