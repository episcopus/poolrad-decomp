# Step 8.0: toolchain baseline (report)

Date: 2026-10-17. Plan: `docs/coco/PORTING-GUIDE.md` section 9, row 8.0. Evidence tags as in the guide:
**[V]** verified here by running a tool or the emulated machine, **[S]** from a cited source, **[E]** estimate.
Everything below was run from `ports/coco3` with `make` (commands in the last column of the tables).

## Exit criterion

| Criterion | Result |
|---|---|
| Container check: `cmoc --help`, NEWS 0.1.86 to 0.1.100, USim and `writecocofile` present | done, section 1 and 2 |
| Rerun `probes/` on 0.1.100 | done, section 3 (the byte rule is unchanged) |
| lwlink two-file test of resident symbol export (open question Q6) | done, answered yes, section 4 |
| A banked hello world (core plus code banks, far call and return) runs in XRoar and MAME | done: `make test` passes in both, section 5 |

Decisions D1 to D11 were not reopened: this step used the guide's recommendations (CoCo 3 with 512 KB, bare
metal, CMOC). Nothing found here contradicts one; D4 (window size) and D11 (gcc6809) wait for 8.1 and 8.1b.

## 1. The toolchain in the image [V] (`make toolchain`)

`jamieleecho/coco-dev:latest`, **aarch64** (Apple Silicon host): CMOC 0.1.100, LWTOOLS 4.25 (`lwasm`, `lwlink`,
`lwar`), ToolShed (`decb`, `os9`), `writecocofile`, `install-coco-boot-loader`, `zx0`/`dzx0`, MAME 0.287
(CoCo 3 only, SDL dummy video and audio), Python 3.12.

- **No USim.** The image has the USim runtime libraries (`libcmoc-*-usim.a`) but no `usim` simulator binary, so
  the guide's "unit tests in USim" idea (section 8, item 2) is replaced by the emulated machine: a probe or unit
  test is a small program that reports through the mailbox (section 5) and runs in headless MAME in about 2 s.
- The image's `mame` needs the `coco3.zip` romset, not shipped (README, "ROMs").
- Everything else the guide asked for is present: `writecocofile`, `install-coco-boot-loader`, `decb`, `zx0`.

## 2. CMOC 0.1.86 to 0.1.100: what changed that matters [V] (image `NEWS`)

| Version | Change | Consequence for the port |
|---|---|---|
| 0.1.87 | `--initial-s=HEX` (first instruction `LDS #HEX`, checked: it is the first instruction of `program_start`) | usable, but our `boot.asm` sets S itself before CMOC's start code |
| 0.1.87 | `__gcccall`: experimental register calling convention (gcc6809's) | probed in `probes/asm/gcccall.c`, section 3.3 |
| 0.1.87 | the optimizer no longer uses Y unless `-Oy` | Y is free for the engine more often |
| 0.1.87 | `-funsigned-char`, `--lwasm-pragma`, warning for an assignment used as a condition | none |
| 0.1.88 | `#pragma push_calling_convention` / `pop_calling_convention`, `--cpp=` | a header can mark whole groups `__gcccall` |
| 0.1.89 | `switch` accepts 32-bit expressions and case values, fixes for jump tables with `default` | relevant to the ECL interpreter's opcode `switch`, untested |
| 0.1.90 | `-fno-omit-frame-pointer`; optimizer bug in `switch` with `--no-relocate` fixed | none |
| 0.1.91 | optimizations for consecutive pushes, LEAS, array element addresses | smaller code |
| 0.1.94 | better code size with `--no-relocate`; `-Wshadow` equals `-Wlocal-var-hiding` | none |
| 0.1.97 | `switch` supports Duff's device; a statement before the first `case` is a warning, not an error | rule 22 of research 04 (no statement before the first `case`, no Duff's device) is out of date |
| 0.1.98, 0.1.99 | `static_assert`, `-Wno-calling-undeclared-function` and other `-Wno-*`; fixed `removeRepeatedLDX` (0.1.99) | none |
| 0.1.100 | optimizations for always true or false conditions; `strncat`; `-E -o` | none |

Nothing in 0.1.87 to 0.1.100 touches byte arithmetic, `volatile`, sections, banking or 6309 code generation.

## 3. Probes on 0.1.100

### 3.1 Byte arithmetic [V] (`make probe P=byte-arith`, MAME and XRoar identical)

`probes/byte-arith.c` runs on the emulated CoCo 3 (not in USim) and compares each result with standard C and
Turbo Pascal. The earlier 0.1.86 result is unchanged:

| Expression (operands `unsigned char` unless noted) | Standard C and Pascal | CMOC 0.1.100 | `-Wgives-byte` warns? |
|---|---:|---:|---|
| `row * 40`, row = 10 | 400 | **144** | no |
| `a + b`, 200 + 100 | 300 | **44** | yes |
| `k - 10`, k = 7, stored in an `int` | -3 | **253** | no |
| `u - v`, 7 - 10 | -3 | **253** | yes |
| `a + 100`, a = 200 | 300 | **44** | no |
| `(a + b) >> 1` | 150 | **22** | yes |
| `sa / ub`, `sa` = -8 (int), `ub` = 2 (unsigned char) | 32764 | **65532** (-4, left operand's signedness) | no |
| `(long)w1 + w2` (Words) | 70000 | 70000 | n/a |
| `(unsigned char)(a << 1)` | 144 | 144 | n/a |
| `(unsigned int)row * 40`, `(unsigned int)a + b`, `(int)k - 10` | 400, 300, -3 | 400, 300, -3 | n/a |

So the rule stands: a binary operation on two byte-sized operands (an 8-bit constant counts) is computed in 8 bits,
the signedness of `/` follows the left operand, and one explicit cast fixes it. **New: `-Wgives-byte` still misses
every case where one operand is a constant (`row * 40`, `k - 10`, `a + 100`)**, so the warning cannot be the safety
net: the translator's CoCo profile (guide 6.2) must emit the cast itself.

### 3.2 `volatile` and polling (open question Q7) [V] (`make asm-probe P=volatile-poll`)

`volatile` is **rejected with a warning** ("the `volatile' keyword is not supported"), but the generated loops
reload the global on every pass: `while (ticks == 0)` compiles to `LDB _ticks / BEQ`, `while (bigticks < 100)` to
`LDD _bigticks / CMPD #$64 / BLO`, and two consecutive reads of the same global both stay. A loop on a *local copy*
of a global does not reload it (obviously). So a polling loop on an interrupt-set global works as written at
`-O2` (0.1.100, these shapes); keep such polls in a few asm accessors anyway, because the optimizer's behaviour is
not a language guarantee. The port's headers do not use `volatile` (no warnings).

### 3.3 `_CMOC_fpir_`, `__gcccall`, `--initial-s` [V] (`make asm-probe P=fpir-initial-s`, `P=gcccall`)

- `_CMOC_fpir_` still exists in 0.1.100: first parameter in X (16 bit) or B (8 bit), spilled to the frame at entry.
- `__gcccall`: first byte-sized argument in B, first word-sized argument in X, further arguments on the stack; a
  16-bit result comes back in **X**, not D. The callee still spills register arguments to a frame, so the saving is
  small, and the far-call stub would have to preserve B and X and treat X as the result. Not adopted; revisit in
  8.1b with the gcc6809 comparison.
- `--initial-s=1F80` emits `LDS #$1F80` as the first instruction of `program_start`.

## 4. Q6: sharing the resident code with a bank, answered yes [V]

An object assembled from `SECTION name,constant` containing `SYM EQU $xxxx` and `EXPORT SYM` defines absolute symbols
that `lwlink` resolves for references in any other object, with no library involved (two-file test in `build/exp`,
then the demo). `tools/symexport.py` writes such a file from the core's linker map, restricted to the symbols a bank
object references and does not define, and **fails if the core lacks one**. CMOC emits calls to helpers such as
`MUL16` as PC-relative expressions (`( ES=MUL16 ... IS=code OP=TIMES ... )` in `lwobjdump`), which lwlink resolves
across the 64 KB address space, so a bank at `$8000` reaches `MUL16` at `$20DD` with a plain `LBSR`. A bank linked
without `-l` libraries carries none of CMOC's helpers: `bank2_mul` (`a * b`) runs through the core's `MUL16` and gives
2100 for 300 * 7.

Not yet answered: which CMOC helpers the translated game needs (all of them should be linked into the core
whole; today only referenced library members are, so the demo calls `a * b` once in the core to pull in `MUL16`).

## 5. The banked hello world [V] (`make test`, `make bench`)

What it is (`src/engine`, `src/demo`): a resident **core** (`boot.asm` takeover, `farcall.asm` trampoline and bank
loader, CMOC runtime, `core.c`) at `$2000`, and two **code banks** that both link at `$8000` (MMU slots 4 and 5, 16 KB
window) and live in physical blocks `$0C/$0D` and `$0E/$0F`. LOADM puts the core at `$2000` and the two bank images
at staging addresses `$4000` and `$5000`; `_load_banks` copies them into the physical blocks through the window. Each
bank starts with a table of 3-byte `JMP`s, so the resident stubs know every entry address without knowing the bank's
symbols (`FARSTUB name,bank,index`).

What the test checks (all pass, identically in MAME 0.287 and XRoar 1.12.1):

| Check | Result |
|---|---|
| the same logical entry (`$8000`) in two banks runs different code | `bank1_whoami` = `$B1B1`, `bank2_whoami` = `$B2B2` |
| far call with two arguments and a result | `bank1_add(1000, 234)` = 1234 |
| bank 1 calls resident code, which far-calls bank 2, which returns into bank 1 | `bank1_chain(21)` = 421 (nested call, window remapped on the way back) |
| a bank uses CMOC helpers from the core | `bank2_mul(300, 7)` = 2100 |
| the byte rule holds inside a bank | `bank2_bytes(200, 100)` = 44 |
| bank stack balanced, no bank mapped in resident code, MMU read-back | `$2000`, 0, slots 4 and 5 = `$0E`, `$0F` |
| 1000 far calls and 1000 resident calls give the expected sum | 19960 |

**Far-call cost, measured [V] (`make bench`, MAME, 1.79 MHz):** 287 cycles per far call against 111 for the same
call made directly; **the trampoline costs 176 cycles (about 98 us)**. A hand count of the code gives about the
same. The guide's estimate of 60 to 90 cycles [E] was optimistic by 2 to 3 times. Not a problem for turn based
game logic (a keypress that makes 100 far calls spends 10 ms), but the optimisation room is known: the bank stack
frame goes through memory scratch words because U, Y and X all carry live values; a remap is skipped when the
caller's bank is already mapped; a stub for a hot entry can map the window itself. Do this in 8.9 from a profile.

Sizes [V]: core 1,485 bytes with the CMOC runtime pieces it pulls in (`program_end` = `$25CD`), of which the trampoline,
loader and bank table are 174 bytes and the stubs 48; the banks are 55 and 45 bytes. `tools/maplimit.py` keeps the
core below the staging area, `tools/bankcheck.py` fails a bank that has writable data, global initialisers or does not
fit the window.

### Things learned while building it

- **The mailbox cannot be trusted before the program starts.** `$0100` is BASIC's hook area; the Lua script
  and `mbdump.py` require the magic `PRAD` before they read a status.
- **XRoar's `-trap-snap file.ram` writes the 512 KB in physical address order** [V] (answers 08, open question 2):
  the mailbox at logical `$0100` (block `$38`) is at file offset `$70100`. `-ui null -ao null` runs it headless
  (no `xvfb` needed); `xroar -vo help` did not return (it never printed, killed after two minutes), do not use it. `-run` on a `.bin` loads and execs without a disk.
- **MAME**: `-video soft` is needed for `screen:snapshot` to work; the Lua script as a `-autoboot_script` can post
  the LOADM command and poll logical memory; the whole run takes about 2 s of wall time (28x real time). Emulated time
  reads back in Lua, which is how `make bench` measures cycles. The ALSA warning is harmless.
- **Video after takeover.** Switching `$FF90` to CoCo 3 mode left the screen garbled because BASIC's video registers
  were set for CoCo-compatible mode; the engine keeps `$FF90` bit 7 (compatible video) until it programs 320x200x16 in 8.3.
- The `ldx`/`ldb`/`jmp` stub shape works because a CMOC callee finds its first argument at `2,S`; the trampoline pulls the
  caller's return address and keeps it on its own bank stack, so S looks exactly like a direct call.

## 6. Answers to the guide's open questions

| Q | Answer |
|---|---|
| 2 (CMOC 0.1.86 to 0.1.100) | section 2; the byte rule holds; `_CMOC_fpir_` and `--initial-s` exist; `__gcccall` is new |
| 6 (lwlink resolves a bank's imports against absolute core symbols) | yes, section 4 |
| 7 (polling loop on an ISR-set global without `volatile`) | reloaded every pass in the shapes tested, section 3.2 |
| 08 open: layout of XRoar `.ram` | physical order, section 5 |
| 08 open: is there a `null` UI in XRoar | yes, `-ui null` |
| 08 open: does MAME's Lua read logical memory and the screenshot work headless | yes (`-video soft`), section 5 |

Still open and not touched by this step: Q1, Q3 to Q5, Q8 to Q15 (DSKCON at 1.79 MHz, real CMOC unit sizes, DGROUP
and heap peak, GMC, GIME revisions, gcc6809, OCR of the scans). 8.1 takes Q3 and Q4.

## 7. What the next step needs from this one

- `make probe`, `make asm-probe`, `make test` are the loop for every later CMOC question; add a probe before
  relying on a CMOC behaviour (the guide's convention).
- 8.1 compiles the five largest overlay units and one resident unit with CMOC as they are. The shim headers and the
  translator profile (8.2) do not exist yet, so expect that step to start from the shims in `src/engine`-style
  headers and to report sizes of *CMOC-clean* code, not of a finished port.
- The staging copy in `_load_banks` is demo scaffolding; the real loader (8.3) reads bank files from disk straight
  into the physical blocks.
