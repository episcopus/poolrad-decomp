# 30 Decompile a unit to Pascal (Decompiler)

**Inputs:** a name for yourself (`AGENT`, unique among the agents running, for example `dec-2`); the compiler installed in the main checkout (`make tp-pin`).

## Steps

1. **Claim.** From the main checkout: `make claim AGENT=<you>` (or `UNIT=<id>` when the human assigned one). It locks the next unit: first a unit whose review failed (fix its must-fix findings, below), else the next unit of `work/queue.toml` that is neither locked nor complete. It creates the worktree `../poolrad-worktrees/<id>` on branch `unit/<id>` and links the compiler into it. `cd` there; do everything else in that worktree.
2. **Read.** `make packet UNIT=<id>`; read `build/packets/<id>.md` (annotated disassembly, frames, callers, the bytes after each return), the unit's skeleton `src/<ID>.PAS`, and the whitepaper sections about the subsystem.
3. **Decompile, routine by routine, leaves first** (callees before callers):
   1. Read the frame: `retf n` gives the parameter bytes, `sub sp, n` the locals; `[bp+6]` upward are the parameters (the last declared is nearest), `[bp-1]` downward the function result and the locals in declaration order.
   2. Replace the routine's `{@stub}` line (and its interface declaration, if the signature changes) by the Pascal. For a callee that is still a stub, give it the signature its callers' pushes show, in whichever unit's file it lives, and record it in `re/symbols.toml` `signature` (the full header, `procedure name(...)` or `function name(...): T`). For a new global, add `dsXXXX: <type>;` to `src/POOLVARS.PAS` in offset order (or a name in `re/dseg.toml` with evidence).
   3. `make match UNIT=<id> FN=<name>`. On a difference the tool shows both instructions and the reason: fix the Pascal, never the tool. When the compiler's choice is unclear, probe it (rules of thumb). Maximum 5 attempts, then write a `blocked` note in `re/symbols.toml` `notes` and go on.
   4. **Make it readable** before committing (`docs/process/READABILITY.md`): name the routine (`make rename OLD=<provisional> NEW=<Name> WHY="<evidence>"`), its parameters and locals; name the globals it uses (`make rename OLD=dsXXXX NEW=<Name> WHY=...`) or comment their declaration in `POOLVARS.PAS` with what is known; replace meaningful numbers by named constants; write the routine's comment (address, what it does in game terms, parameters, result, globals, side effects) and mark quirks `QUIRK <address>:`. `make match` again (names never change the code), then `make readability UNIT=<id>` until clean. When the purpose is really unknown, keep the provisional name and say `Purpose unknown:` with what is known.
   5. `make match UNIT=<id> WRITE=1` records L2; commit: `<unit>: decompile <name> (<id>) [L2]` with the trailer line `Agent: <you>` (`git commit -m "..." --trailer "Agent: <you>"`).
4. **The unit.** Write the unit's comment (what it is for, its main routines, the whitepaper section) once its purpose is clear, and look over the names across the unit: the same thing gets one name.
5. **The initialisation part.** If the file has `{@stub-init}`, decompile it like a routine (it runs once at start-up) and remove the marker. When no stub is left, `make match UNIT=<id>` also checks that routines, pools, the initialisation part and the padding cover the original segment exactly: `unit: complete`.
6. **Before handing over:** `make check` green in your worktree (all units still match and pass `make readability`, the rebuild links, goldens hold). If you merged `main` into your branch, `make rename APPLY=1` first. Keep the boundary notes `WRITE=1` printed for your hand-off note (a mapper fixes `re/symbols.toml` sizes). Update the whitepaper (playbook 60) for what the unit taught; do not edit `docs/design/CHANGELOG.md` (your row goes in the hand-off).
7. **Hand over:** commit everything on `unit/<id>`, then `make handoff AGENT=<you> UNIT=<id> STATE=complete|partial|blocked NOTE="<what is done, what is blocked and why, boundary notes for the mapper>" CHANGELOG="<whitepaper sections> | <what changed> | <evidence, e.g. make match UNIT=<id>>"`. Do not merge, do not unlock, do not commit `work/status.md` or `CHANGELOG.md`: the orchestrator merges, adds the row, regenerates the status and releases the lock. Then claim the next unit.

**Escalate** anything you cannot settle from evidence and that is not yours to change: a matcher result you believe is wrong, a spec rule in the way, a contradiction with another unit's claims, a decision AGENTS.md rule 6 reserves for the human. `make handoff AGENT=<you> UNIT=<id or general> STATE=escalate NOTE="<the question, the evidence, what you recommend>"`; it needs no commit, the orchestrator takes it to the human. Carry on with other routines meanwhile.

A complete unit is reviewed by another agent after the merge (playbook 70). If the review has must-fix findings, `make claim` gives the unit back to the next decompiler before any new unit: fix each finding, mark it `- [x] ... (fixed in <commit>)` in `work/reviews/<id>.md`, `make check`, hand over again (`STATE=complete`). The unit then returns to the review queue.

## Unit header

```pascal
unit OVL05;
{ TreasureShare: what the unit does, with evidence (whitepaper section). }
{$A-,O+,F+,S-,R-,G-,I-}        { resident units: {$A-,F+,S-,R-,G-,I-}; res05 has I+ }
interface
procedure ovl05_e1;
...
implementation
uses POOLVARS, RES04, ...;
```

## Rules of thumb

- **Probe, do not guess.** `make tpc SRC=<scratch>/GUESS.PAS DISASM=1` compiles a guess with POOL's compiler and names every runtime call by the POOL routine it reaches. Keep scratch Pascal out of `src/`; worthwhile probes go to `tools/re/tp_idioms/`.
- **The runtime library is a call.** A `lcall 0AF8:xxxx` (System), `0A40:xxxx` (Crt), `0A32:xxxx` (Dos) in the packet is a standard routine or a compiler helper; the packet names it when `re/symbols.toml` does. Find the Pascal construct that produces that call with a probe.
- **Ghidra's decompiler output is a hint**, not the answer: it mis-types Pascal strings, sets and nested-procedure frames.
- **Keep original quirks** (dead code after `Exit`, unassigned function results, off-by-ones): the compiler demands them; comment them as `QUIRK:` with the address.
- **Hand-written assembly** (no Pascal frame shape, `in`/`out`, odd register use) becomes a Turbo Pascal `assembler` routine with real instructions (never `db` bytes), marked as such in its header comment.
- **A routine the map got wrong** (two routines in one entry, a literal pool counted as code, a routine missing): write what the compiler shows; name a missing routine `<unit>_fn_<offset>` (the matcher accepts it) and note it for the mapper.

## Idioms found so far (TP 6.0, proven by `make match`)

| Code | Pascal |
|---|---|
| Strings and sets used by a routine sit in the code segment right before it (the packet shows them as bytes after the previous routine's return) | string literals, `in [0, 1]` set constants (32 bytes) |
| `push cs; call near` | a call to a routine of the same unit (`$F+`: every routine is far) |
| `jmp` to the epilogue as the first instruction | `Exit;` followed by code the original kept (res04_fn_0104) |
| `mov al,[bp-k]; mov [bp-1],al; mov al,[bp-1]` at the end | function result assigned from a local (`F := Key;`) |
| `cmp byte [x],0; mov al,0; jne +1; inc ax; mov [x],al` | `x := not x` for a Boolean |
| In an overlay unit: a stack temporary filled from a code-segment literal by `0AF8:0B0B` before a call | a string constant passed to a routine under `$O+` (the compiler copies it, since the overlay may move) |
| A value `string[N]` parameter copied by `0AF8:0B25` with max N in the prologue | parameter declared with that type (`Text: String40`) |
| Locals not word-aligned (an odd-sized string at `[bp-29h]`) | `$A-` (every POOL unit) |
| `mov ax, <off>; mov dx, <stub seg>` stored into a pointer | `P := @Routine` of an overlay routine: the address of its stub entry |
| `0AF8:16BC` with `(temp, n)` | `ParamStr(n)` |
| `0AF8:0C10` after two string addresses | string comparison (`=`, `<>`, ...) |
| `0AF8:0DC0` after a byte and a set address | `x in [...]` |
| `0A40:030F`, `0A40:02FD` | `ReadKey`, `KeyPressed` |
| `0A32:000B` after `push 10h` and a `Registers` address | `Intr($10, Regs)` |

## Done when

Every routine of the unit at L2 and readable (`make readability UNIT=<id>` clean, names and comments as `docs/process/READABILITY.md` asks), `make match UNIT=<id>` says `unit: complete`, `make check` green, the branch handed to the orchestrator. The unit is *done* after its review passes (playbook 70).
