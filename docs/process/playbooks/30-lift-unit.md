# 30 Decompile a unit to Pascal (Decompiler)

**Inputs:** a unit id from `make next` or the orchestrator; the unit unlocked; the compiler installed (`make tp-pin`).

## Steps

1. `make lock UNIT=<id>`; create a worktree: `git worktree add ../poolrad-<id> -b unit/<id>`.
2. `make packet UNIT=<id>`; read it (annotated disassembly, frames, callers, the bytes after each return), then the whitepaper sections about the subsystem.
3. Create `src/<ID>.PAS` if it does not exist: the unit header and directives (below), every routine of the unit declared in the interface in address order, and a `{@stub}` body for each. Keep this order: Turbo Pascal lays routines out in source order, which makes the whole-unit check possible at the end.
4. For each routine, leaves first (callees before callers):
   1. Read the frame: `retf n` gives the parameter bytes, `sub sp, n` the locals, `[bp+6]` upward are the parameters (last declared first), `[bp-1]` downward the function result and locals in declaration order.
   2. Write the Pascal in place of the stub. For a callee that is not decompiled, give its stub the signature its callers' pushes show (same unit: edit the stub here; another unit: add or fix the `{@stub}` declaration in that unit's file) and record it in `re/symbols.toml` `signature`. For a new global, add `dsXXXX` to `src/POOLVARS.PAS` (or name it in `re/dseg.toml` with evidence).
   3. `make match UNIT=<id> FN=<name>`. On a difference, the tool shows both instructions and the reason: fix the Pascal, not the tool. When the compiler's choice is unclear, probe it (rules of thumb). Maximum 5 attempts, then write a `blocked` note in `re/symbols.toml` and continue.
   4. `make match UNIT=<id> WRITE=1` records L2; commit: `<unit>: decompile <name> (<id>) [L2]`.
5. When no stub of the unit is left, `make match UNIT=<id>` also checks that routines, pools, the initialisation part and the padding cover the original segment exactly (`unit: complete`). The original has an initialisation part if `re/units.toml` lists an `init` (an empty one is `begin end.` at the end of the file).
6. Apply what `WRITE=1` reports about `re/symbols.toml` boundaries through the mapper (playbook 10), or note them for the orchestrator.
7. Request review (playbook 70) from a fresh agent session; update the design doc (playbook 60); `make unlock UNIT=<id>`; hand the branch to the orchestrator for merge.

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

## Idioms found so far (TP 6.0, proven by `make match`)

| Code | Pascal |
|---|---|
| Strings and sets used by a routine sit in the code segment right before it (the packet shows them as bytes after the previous routine's return) | string literals, `in [0, 1]` set constants (32 bytes) |
| `push cs; call near` | a call to a routine of the same unit (`$F+`: every routine is far) |
| `jmp` to the epilogue as the first instruction | `Exit;` followed by code the original kept (res04_fn_0104) |
| `mov al,[bp-k]; mov [bp-1],al; mov al,[bp-1]` at the end | function result assigned from a local (`F := Key;`) |
| `cmp byte [x],0; mov al,0; jne +1; inc ax; mov [x],al` | `x := not x` for a Boolean |
| In an overlay unit: `push <len>`, then a stack temporary and the code-segment literal passed to `0AF8:0B0B` before a call | a string constant passed to a routine under `$O+` (the compiler copies it to the stack, since the overlay may move) |
| A value `string[N]` parameter copied by `0AF8:0B25` with max N in the prologue | parameter declared with that type (`Text: String40`) |
| Locals not word-aligned (an odd-sized string at `[bp-29h]`) | `$A-` (every POOL unit) |
| `mov ax, <off>; mov dx, <stub seg>` stored into a pointer | `P := @Routine` of an overlay routine: the address of its stub entry |
| `0AF8:16BC` with `(temp, n)` | `ParamStr(n)` |
| `0AF8:0C10` after two string addresses | string comparison (`=`, `<>`, ...) |
| `0AF8:0DC0` after a byte and a set address | `x in [...]` |
| `0A40:030F`, `0A40:02FD` | `ReadKey`, `KeyPressed` |
| `0A32:000B` after `push 10h` and a `Registers` address | `Intr($10, Regs)` |

## Done when

Every routine of the unit at L2, `make match UNIT=<id>` says `unit: complete`, `make check` green, review passed, whitepaper updated.
