# Review: ovl04

decompiler: dec-6
reviewer: rev-6
rounds: 1 rev-5 at e3614ee; 2 rev-6 at 8962b79; 3 rev-sonnet at f1c0c8b
date: 2026-10-13
commit: f1c0c8b

Checklist: docs/process/playbooks/70-review.md (every item, every routine).

First review. `make match UNIT=ovl04` reports `unit: complete` (12 routines, 3895 bytes:
AskCastAnyway, ChargeForCure, CureBlindness, CureDisease, CureWounds, RaiseDead,
NeutralizePoison, RemoveCurse, StoneToFlesh, HealMenu, VisitTemple, ovl04_init).
`make readability UNIT=ovl04` is clean. The packet is `build/packets/ovl04.md`.

## Findings

One line per finding: `- [ ] <severity> <routine name>: <what and why, with the address>`.
Severity: must-fix (blocks review-pass), should-fix, note. When the decompiler fixes one, mark it
`- [x]` and add `(fixed in <commit>)`. Do not delete findings.

- [x] must-fix HealMenu (TempleMenuText bound): HealMenu builds ten menu lines (ovl25_e6(10, List) at ovl04:09F2) and fills them with TempleMenuText[I] for I = 1 to 10 (ovl04:0A0C..0A54, I*41+$F1), but POOLVARS declares `TempleMenuText: array[0..9] of string[40]` with the comment "entries 1..9 at DS:011A". Index 10 is read: DS:028B in start-unpack.exe holds length 4 'Exit' (entry 1 at $11A is 'Cure Blindness', entry 9 at $262 'Stone to Flesh', entry 10 at $28B 'Exit'; entry 0 at $F1 is the tail of the previous data). The bound must be [0..10] and the comment must say entries 1..10. Whitepaper 5.19 says "nine names from the string[40] table at DS:011A" and needs the same correction (ten names: the nine services plus Exit). (fixed in 63f6c84)
- [x] should-fix ovl04_init: the empty initialisation at ovl04:0F32 (`55 89 E5 5D CB`) has no comment and no address. Prior reviews accepted the unit only with an init comment carrying the address. (fixed in 63f6c84)
- [x] should-fix OVL04 unit comment: "each a routine here (CureBlindness, CureDisease, CureWounds, NeutralizePoison, RaiseDead, RemoveCurse, StoneToFlesh) that checks the selected character, asks for confirmation when the service is not needed (AskCastAnyway), takes the price (ChargeForCure) and applies the cure through the affect routines of ovl24". CureWounds never asks (no AskCastAnyway, ovl04:0401) and heals through ovl24_e8/e21, not the affect routines; RemoveCurse applies through ovl22_e9 (ovl04:083A), not ovl24. Qualify the summary (most services; CureWounds and RemoveCurse differ). (fixed in 63f6c84)
- [x] should-fix RaiseDead: "(a fighter level counts constitution - 14, another level 2 above 15, else 1)" (ovl04:0510 comment). "another level 2" reads as class index 2, which is the fighter (FighterClass = 2, ovl04:067A). The code gives (con-14) per fighter level, 2 per non-fighter level above con 15 (ovl04:06A9), else 1 per level (ovl04:06CD). Rephrase, e.g. "a non-fighter level counts twice above 15". (fixed in 63f6c84)
- [x] should-fix VisitTemple: `case Key of 'B', 'T': res12_fn_27D9` (ovl04:0F02) handles a 'B' key the routine comment never mentions. The menu prompts ('Heal View Take Pool Share Appraise Exit', ovl04:0D55/0D6A) offer H V T P S A E, and G/O go to ovl19_e10. Say what produces 'B' or mark it unknown with what is known. (fixed in 63f6c84)
- [x] should-fix HealMenu/VisitTemple: `KeyNone = #0` is commented "what the menus return for Escape", but ovl25_e2/e4 are undecompiled stubs with no notes on their return values (re/symbols.toml: auto:near_call/entry only). Cite evidence for Escape yielding #0 or hedge the comment. (fixed in 63f6c84)
- [x] should-fix HealMenu: the comment ends "Frees the lines (ovl25_e7) and redraws the view (res12_fn_27D9)" but the epilogue also clears the text area (res06_fn_0DD3(0, 0, 39, 24)) and reshows the character (res12_fn_0767(SelectedCharacter)), like VisitTemple's loop end does. Name both calls. (fixed in 63f6c84)
- [x] note CureWounds/AskCastAnyway: "ovl24_e8 rolls, ovl24_e21 heals", "res12_fn_17E3 clears the prompt", "ovl25_e5 ... the line reader"-style readings of undecompiled stubs are inferences from the call shapes ((1,8),(2,8)+1,(3,8)+3 fit 1d8/2d8+1/3d8+3; 17E3 takes nothing and follows prompts). Constrained and consistent with the D&D services, but record the inference as such when those units are decompiled. (fixed in 63f6c84)

What was verified (all checked against the bytes): AskCastAnyway and ChargeForCure match
their disassembly call for call (res12_fn_16EC/17E3, ovl25_e5 13,10,15, the Yes=$59
compares, ovl19_e11/ovl21_e10 then ovl21_e12(ds67F4)/ovl21_e11, 'Not enough money.',
'is cured.'); every service price matches its push (1000, 1000, 100/350/600, 1000,
5500=$157C, 3500, 2000); every affect id matches its compare ($21 at ovl04:0262, $20
at ovl04:05B8, $37 at ovl04:05CE, $37/$16/$0F at ovl04:07DB/07F1/0807, $24 at
ovl04:08A0); RaiseDead's Status test (6 at ovl04:0539, 1 at ovl04:0545), Flag11B/Status/Flag10D
writes (+$11B/+$10C/+$10D), constitution Dec (+$14) and HpMax arithmetic (+$32 vs +$B1,
class loop 0..7 over +$96, con>=14 at ovl04:0652, div at ovl04:0701, the <17-or-fighter
rule at ovl04:070B) match the comment; RemoveCurse's item walk (+$C8 list, +$36 Cursed,
+$2A Next) and ds6C95 handoff match; VisitTemple's menu arms (H/V/T/P/S/A/E/G/O at
ovl04:0DAD..0EF2), the pooled-money prompt switch, the priest strings and the
LeaveAnswer = 1 rule match; TCharacter/TItem/TMenuLine field offsets match every use;
all parameterized stub signatures this unit set are recorded in re/symbols.toml and
agree with the other units' stubs (parameterless ovl21_e2/e3/e4, ovl22_e9 and
res12_fn_17E3 correctly record no signature); QUIRK ovl04:0250 marks the cleared
Unread string; no inline code; whitepaper 5.19 covers the unit except the nine/ten
names count.


Round 2 (rev-6, at 8962b79): the round-1 fixes in 63f6c84 are verified (TempleMenuText is `array[0..10]`, whitepaper 5.19 says ten names with `Exit` at `DS:028B`, the init comment, the unit comment's exceptions, the RaiseDead wording, the 'B' key, the KeyNone hedge and the HealMenu epilogue). `make match UNIT=ovl04`: unit complete, 12 matched; `make readability UNIT=ovl04`: clean. New findings:

- [x] must-fix VisitTemple: the comment says Exit with money in the pool "leaves only on that menu's first choice", but the menu is `'~Yes ~No'` and `ovl07_e13` returns the 0-based position of the pressed key in its hotkey list: it searches the list at `[bp-0x153]` from 1 (ovl07:173E..1763) and returns that position minus 1 (`dec ax` at ovl07:1775), or $FF when the key is not there (ovl07:177B); Enter returns 0 only when its fourth byte argument is nonzero (ovl07:172A, the Temple passes 0). So `LeaveAnswer = 1` (ovl04 test, `Done := True`) is the second choice, No: the party leaves when it answers No to "Do you want to go back and retrieve your money?", and Yes keeps it in the Temple. Whitepaper 5.19 ("leaves only when that returns 1") is accurate; the source comment is not. Say "leaves on No (ovl07_e13 returns 1, the second hotkey)", and name the constant (for example `AnswerNo = 1`). (fixed in cd780a5)
- [x] should-fix OVL04 unit comment: "HealMenu lists the ten cleric services" (line 3): the ten lines are nine services and Exit (TempleMenuText entries 1..10, Exit at `DS:028B`; HealMenu's own Choice 9 is Exit). Say nine services plus Exit. (fixed in cd780a5)
- [x] should-fix VisitTemple/HealMenu: `MenuFlag` (the `var Flag` result of `ovl25_e2`/`ovl25_e4`) is not explained: Heal and Pool run only when it is 0 (`'H': if MenuFlag = 0`, `'P': if MenuFlag = 0`), and View receives it (`ovl19_e5(MenuFlag)`), but neither the routine comment nor the local says so. `ovl07_e13` treats a nonzero flag as "pass the key to `ovl19_e10`" (ovl07:16EF..16FB), which suggests the flag marks a key the menu did not take as a choice [I]. At least mention the gate in VisitTemple's comment and give the local a comment with what is known. (fixed in cd780a5)
- [x] should-fix VisitTemple: the comment says it "clears the pooled money DS:67F4 on entry" but leaves out the other entry writes: `ds49F3 := 1` (the view mode, whitepaper 5.19 says so) and `ds6DC0 := 0` (ovl04:0D37), and the first `res12_fn_27D9`/`res12_fn_0767` redraw. List the globals it changes. (fixed in cd780a5)
- [x] note (outside the unit, escalated): whitepaper 5.4 (ovl06, line 576) says `BuyItems` pays "first from the party's pool (`ovl19_e11`) and then from its money (`ovl21_e12` on `DS:67F4`)", the opposite of 5.19 and of this unit: `ovl21_e10`, the writer paired with `ovl19_e11`, stores into `DS:5D92^` +$88..+$90 (the selected character, whitepaper line 580), and `DS:67F4` is the pool the Temple clears on entry. ovl04's reading (character's money, then the pool) is the consistent one. (escalation resolved by the orchestrator, 0906962)

Round 3 (rev-sonnet, at f1c0c8b): `make match UNIT=ovl04` says `unit: complete` (12 matched, 0 differ), `make readability UNIT=ovl04` is clean. Since round 2 the source changed only by the name substitution that came with merging ovl07, ovl21, ovl24 and ovl25 (cd780a5 fixed round 2, then the merges renamed the stubs); no code changed. The round-2 fixes still hold. I re-read every routine against the packet disassembly (`ChargeForCure` 0177 and 01C8 truncations, the Raise Dead constitution loop, the menu arms) and against the now-decompiled callees. The substitution left false text behind, and the callees now give evidence that settles three comments that were hedged:

- [ ] must-fix OVL04 unit comment: "add or remove the affect through RemoveAffect/e5" and "heals through RollDice/e21" are leftovers of the mechanical rename of `ovl24_e2/e5` and `ovl24_e8/e21`. The unit calls no `e5` and no `e21`: it removes affects with RemoveAffect (ovl24_e2) only, rolls with RollDice (ovl24_e8) and heals with HealCharacter (ovl24_e21). Write "removes the affect through RemoveAffect" and "heals through RollDice and HealCharacter".
- [ ] must-fix KeyNone: the comment says "ReadPromptChoice/e4 are still stubs, so this comes from the callers (...), not from the callee's own bytes". That is false now: `ReadPromptChoice` (ovl25:03BD) and `ChooseFromList` (ovl25:0D9A) are decompiled in `src/OVL25.PAS` (unit state draft, so cite it as a draft, not L2) and say "Escape returns #0" and "Escape, E and #0 return #0 with Selected nil". That also explains HealMenu's hotkey: the `E` of `'Heal Exit'` returns #0 and ends the menu. Replace the comment with that evidence.
- [ ] should-fix HealMenu `MenuFlag`: the comment calls it "the var Flag of ChooseFromList". The parameter is `Redraw` (ovl25:0D9A: the page is redrawn on entry only when Redraw is nonzero; it is cleared by the callee). So `MenuFlag := 1` asks for a redraw on entry and the value is never read back. Rename to `RedrawList` (or keep the name and say so).
- [ ] should-fix VisitTemple `MenuFlag`: the comment guesses ("when the menu did not take it [I]"). `ReadPromptChoice`'s last parameter is `var ExtKey` (ovl25:03BD): 1 when an extended key or keypad digit was returned (the Temple passes ExtKeys = 1), as its scan code letter (`KeypadScanLetters` 'OPQK MGHI', whitepaper 5.8). So `'H'` and `'P'` from an arrow key (scan letters Up = H, Down = P) must not run Heal or Pool, and `'G'` and `'O'` (Home and End, or keypad 7 and 1), which neither menu text has, reach ovl19_e10 as scan letters. Rename the local `ExtKey`, update the comment and the "what produces 'B' is unknown" sentence (a scan letter too, not a typed 'B'; say which key if it can be told, else keep the hedge with this evidence). Whitepaper 5.4 (ovl06) has the same gap for G and O.
- [ ] should-fix RaiseDead and StoneToFlesh `Flag10D`/`Flag11B`: the comments say both "become 1" and nothing more, and whitepaper 5.19 says "meaning open". POOLVARS and 5.20 already know more: `Flag11B` is the current hit points [I] (HealCharacter adds to it up to HpMax; unconscious characters with it become okay, 5.20) and `Flag10D` is read as "took part in the battle, gets experience". Say in the routine comments that a raised or restored character stands with 1 hit point [I], and drop "meaning open" from 5.19.
- [ ] should-fix CureWounds, RaiseDead, StoneToFlesh: frame-only locals are not marked like `Unused: string`. `Healed` in CureWounds is assigned from HealCharacter and never read (ovl04:0401 case arms); `Affect: Pointer` is declared and unused in RaiseDead and StoneToFlesh (the frame size needs it). Say so in a QUIRK or a local comment.
- [ ] should-fix `AffectPoison2` ($16), `AffectPoison3` ($0F), `AffectDeath` ($20): the evidence is only that Neutralize Poison and Raise Dead remove them together with $37; nothing says $16 and $0F are poisons or $20 is a death affect. Other units name neighbours differently: ovl09 has `AffectKeptA` = $20, ovl24 `AffectNausea` = $1F (the first `DiseaseAffects` entry) and `AffectHealingBlock` = $32 (ovl15 `AffectMummyDisease`), ovl15 `AffectPoisoned` = $37 and `AffectCauseDisease` = $2C. Either use neutral names (`AffectRemovedWithPoison1`) with a "Purpose unknown" note, or cite what shows the meaning; list the cross-unit names for Phase 6.
- [ ] should-fix the prompt-line and window numbers are bare: 13, 10, 15 (title, word, hotkey colours; `13, 15, 10` in ChargeForCure), $A, $11, $26, $16, $F, the `2, 4, $26, $F` list rectangle and `ClearRect(0, 24, 39, 24)`. ovl08 (`MenuColors`) and ovl15 (prompt colours) name theirs. Name the three prompt colours, the text-window rectangle ($11..$16 rows, 1..$26 columns) and the list rectangle.
- [ ] should-fix whitepaper 5.19: say `MoneyInPool` (`DS:6DC0`) instead of the bare address (named in re/dseg.toml), and add that the Raise Dead constitution test uses the constitution after the decrement and that a bonus of 0 leaves the loss undivided (`if Bonus > 0`, ovl04:0701).
- [ ] note RaiseDead: the routine comment does not say that the constitution thresholds (14, 15, 17) apply after the decrement; the code order shows it (`dec` at ovl04:060E before the test at 0652). Worth one clause when the comment is next touched.

Everything else checked out: prices, affect ids, status values, the quirks at ovl04:0177, 01C8, 0250 and the `AnswerNo` rule, the `TreasureLeft` menu switch, the signatures recorded in re/symbols.toml, no raw machine code.

## Verdict

Not passed. TempleMenuText is declared and commented as entries 1..9, but HealMenu reads indices 1..10 and DS:028B holds 'Exit'.

Round 2 (rev-6, at 8962b79): not passed. One must-fix: VisitTemple's comment says the party leaves on the first choice of the retrieve-your-money question; `ovl07_e13` returns the 0-based hotkey position, so 1 is No (ovl07:1775).

Round 3 (rev-sonnet, at f1c0c8b): not passed. Two must-fix: the unit comment still says `RemoveAffect/e5` and `RollDice/e21` (rename leftovers for routines the unit never calls), and the `KeyNone` comment says `ReadPromptChoice/e4` are still stubs although `ReadPromptChoice` and `ChooseFromList` are decompiled in OVL25.PAS and give the evidence.
