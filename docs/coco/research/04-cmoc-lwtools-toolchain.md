# 04: The C toolchain (CMOC 0.1.100, LWTOOLS 4.25, ToolShed) for the Pool of Radiance CoCo 3 port

## Key takeaways for the Pool of Radiance port

1. CMOC is a usable but non-standard C compiler. The single most dangerous difference for our mechanically translated C: **a binary `+ - * / %` on two byte-sized operands (including an 8-bit constant) yields a byte in CMOC, not an int.** `uint8_t row; row * 40` is computed in 8 bits. Every such expression must get an explicit widening cast, and `-Wgives-byte` finds them (src: CMOC 0.1.86 manual "Binary operations on bytes"; `ExpressionTypeSetter.cpp` `setBinOpTypeDescForDiffSizedOperands`, https://github.com/stahta01/cmoc).
2. `int` is 16 bits, `long` is 32 bits, `char` is signed, `double` is an alias of `float`. Turbo Pascal Integer/Word/Byte/ShortInt/LongInt map 1:1 onto `int16_t/uint16_t/uint8_t/int8_t/int32_t` (CMOC's `<coco.h>` defines these typedefs). There is no `stdint.h`, `stdbool.h`, `string.h` or `stdio.h`: we ship our own shim headers.
3. 32-bit `long` arithmetic is done by library calls through pointers (`addDWordDWord` etc.), and `long`/`float`/struct return values go through a hidden pointer. It is roughly an order of magnitude more expensive than 16-bit code. Keep LongInt to where Pascal needs it.
4. Floating point exists only via Color Basic ROM routines (5-byte MS format, ROM must be mapped) or `--mc6839` (adds the 8 KB Motorola MC6839 ROM image, 4-byte format). Neither reproduces Turbo Pascal's 6-byte Real bit for bit. Replace the few Real routines with integer or fixed-point code validated against the PC version.
5. CMOC has **no banking, far calls, overlays or per-function section placement.** It emits everything into fixed section names (`code`, `rodata`, `rwdata`, `bss`, `initgl`). Overlays are built the way Space Bandits / DynoSprite does it: link each overlay separately at the MMU window address, against symbols extracted from the resident link, and call through hand-written assembly trampolines. This is proven in a shipping CMOC game (src: https://github.com/jamieleecho/space-bandits).
6. CMOC code is about 1.3x larger and 2x slower than gcc6809 on a published kernel benchmark (CMOC 0.1.98 vs gcc6809 4.3.6) (src: https://vectrex.substack.com/p/cmoc-vs-vbcc-vs-gcc6809). That is acceptable for game logic, not for pixel loops; those stay in LWASM assembly.
7. Build with `--no-relocate` (JSR instead of LBSR, constant pointer tables emitted as FDB in rodata instead of run-time init code), `-O2`, and evaluate `-fomit-frame-pointer`. Do not use `cmoc`'s one-line link for the final image: drive `lwlink` with our own script.
8. Verdict: **stay on CMOC + LWTOOLS** (maintained, in the container, used by real CoCo 3 projects). Keep the C portable enough that hot modules could later be tried with gcc6809 or vbcc. No usable Pascal compiler for the 6809 accepts Turbo Pascal 6.0; TRSE's "Turbo Rascal" is a different language.

Source note: the CMOC home page and HTML manual on sarrazip.com refuse automated fetches (robots), and the perso.b2b2c.ca mirror serves an old 0.1.44 manual. The detailed facts below come from the **0.1.86 source tree and manual** (2024-03-10) in the GitHub mirror https://github.com/stahta01/cmoc (cloned and read, not executed). The container ships 0.1.100 (src: https://github.com/jamieleecho/coco-dev Dockerfile). 0.1.98 was released 2026-06-06 (src: https://vectrex.substack.com/p/cmoc-vs-vbcc-vs-gcc6809). I could not obtain release notes for 0.1.87 to 0.1.100; options seen in newer real builds (`--initial-s=`, `-Wno-assign-in-condition`) prove changes exist (src: https://github.com/FujiNetWIFI/fujinet-config Makefile). **First task for a later agent: run `cmoc --help` and read `/usr/local/share/doc/cmoc*` or the NEWS file inside the container to diff against this document.**

---

## 1. Versions in the container

| Tool | Version | Where it comes from |
|---|---|---|
| CMOC | 0.1.100 | `curl http://sarrazip.com/dev/cmoc-0.1.100.tar.gz`, built with g++ (src: coco-dev Dockerfile) |
| LWTOOLS (lwasm, lwlink, lwar, lwobjdump) | 4.25 (2026-07-18) | lwtools.ca release tarball (src: Dockerfile; https://www.lwtools.ca/) |
| ToolShed (decb, os9, etc.) | 2.6.1 | github.com/nitros9project/toolshed tag v2.6.1 |
| MAME | 0.287, headless, coco3 driver only | built in image, ROMs not included |
| Others | ZX0, salvador, BasTo6809 5.50, coco-tools 0.28 (Python), milliluk-tools, nitros9 `defs` in `/usr/local/share/lwasm`, java_grinder, naken_asm | (src: https://github.com/jamieleecho/coco-dev README and Dockerfile) |

The wrapper script `coco-dev/coco-dev` runs `jamieleecho/coco-dev:0.88` with the home directory mounted (src: coco-dev repo, `coco-dev` script line 10). The image does not contain XRoar.

LWTOOLS 4.20 to 4.25 notes: 4.23 fixed "a stack corruption bug in the object file output format" and added `0b` binary constants; 4.22 added STDIN source and offset/length for `INCLUDEBIN`; 4.25 added `<<` and `>>` operators to lwasm. 4.19 changed the lwlink `raw` target to emit no bytes for BSS sections and added `raw2` for the old behaviour (src: https://www.lwtools.ca/).

---

## 2. Language support and limits

### 2.1 Feature table (CMOC 0.1.86 manual "C Language Features", cross-checked against the compiler's own test suite)

| Feature | Status | Notes / source |
|---|---|---|
| `char` 8, `short`/`int` 16, `long` 32 bits, signed/unsigned | Supported | manual "Supported C and C99 features" |
| `long long` (64-bit) | No | manual "Unsupported" |
| `char` signedness | **signed** | manual "Calling convention": "An argument of type `char`, which is signed, is promoted to `int`" |
| `float` | Single precision, only with Basic ROM (CoCo DECB, DragonDOS) or `--mc6839` | manual "Floating-point arithmetic" |
| `double` | Accepted, alias of `float`, warning issued | manual |
| Pointers, pointer to pointer, pointer to array | Supported (pointer-to-array bugs fixed 0.1.84) | NEWS 0.1.84 |
| Structs, unions, nested structs, anonymous structs | Supported; **must be declared at global scope** | manual |
| Struct assignment and init from another struct | Supported (calls `memcpy`) | manual; "Avoiding CMOC's default C library" |
| Struct/union pass and return by value | Supported since 0.1.40; return via hidden pointer | manual |
| `*ptr` struct as r-value | Manual lists as unsupported, but `struct S local = *ptr;` is in the 0.1.86 test suite | `test-program-output.pl` line 4717. Prefer `memcpy` or plain field access |
| Bit-fields | **Accepted syntax only**: each field occupies a full char/int/long | manual; NEWS 0.1.56 |
| `const` | Supported since 0.1.50; const-correctness problems are warnings | manual |
| `volatile` | Accepted, **ignored**, warning | manual. Optimizer treats loads from absolute constant addresses as volatile (NEWS 0.1.5x "storeLoad") |
| `register` | Accepted, ignored | manual |
| `inline`, `restrict`, `_Bool`, `_Static_assert` | Not keywords | lexer.ll keyword list |
| Designated initializers, compound literals | Not in the grammar [inferred from parser.yy; verify] | parser.yy |
| Enumerations | Supported, **global scope only**; an enum with an enumerator list cannot appear in a parameter or return type; values are `int` (16-bit) | manual "Enumerations"; error "non-global enum not supported" |
| Typedefs | Global only; redefining a typedef is an error | manual |
| Function pointers | Type-safe; struct members can be function pointers; arrays of function pointers work in 0.1.86 tests despite the manual still listing them as unsupported | manual; `test-program-output.pl` lines 5677, 9171 to 9240 |
| Variadic functions | Supported with `<stdarg.h>`; at least one named parameter | manual |
| K&R definitions, local prototypes (0.1.85) | Supported | manual |
| C99 mixed declarations, `for (int i...)` | Supported | manual |
| `static` locals | Supported since 0.1.76, constant initializer | manual |
| `switch` | Jump table or if-else chain (cost based, `--switch=ifelse|jump`); **no `long`/float switch; no `continue` inside switch; no statement before first `case`; no Duff's device** | manual; error list in `test-bad-programs.pl` |
| `goto`, labels | Supported | manual |
| `setjmp/longjmp` | `<setjmp.h>` since 0.1.82 | NEWS |
| Zero-length arrays | No | manual |
| Array size limit | 1 to 32767 bytes; constant expressions are evaluated in 16-bit signed int, so write `256U * 192U / 8U` | manual "Array sizes" |
| Inline asm | `asm { ... }` blocks, `asm("ins", "args")` one-liners, `asm` functions with no frame, `__norts__`, global-scope `asm {}` since 0.1.84 | manual; FujiNet `text_gime.c` uses `asm("orcc", "#$50")` |
| `interrupt` functions | End with RTI; may not take parameters; may not be called directly | manual; error list |
| 6309 instructions | Accepted in inline asm (lwasm default); **CMOC never generates 6309 code** | manual "Hitachi 6309 instructions" |

### 2.2 Semantic gotchas that matter for translated Pascal

1. **Byte arithmetic stays byte.** CMOC: "Binary operations on bytes give a byte under CMOC, whereas they give an integer under Standard C." The result type is the larger operand size, where an 8-bit constant counts as a byte (src: manual; `setBinOpTypeDescForDiffSizedOperands` in ExpressionTypeSetter.cpp). So `uint8_t a=200, b=100; uint16_t s = a + b;` gives 44, and `row * 40`, `x + 100`, `hp - dmg` (all bytes) wrap at 8 bits. Turbo Pascal (like C) widens to Integer. `-Wgives-byte` warns, except when either operand has a cast (src: manual, NEWS 0.1.86).
2. **Signedness of `+ - * /` is that of the left operand** (src: manual "Signedness of integers"; same function, `!left->isUnsignedOrPositiveConst()`). `uint16_t u; int16_t s; s / u` divides signed. Use `-Wsign-compare` and explicit casts on every mixed-sign expression.
3. Integer constants are `int`: `0xFFFF` alone is fine, but arithmetic on constants that exceeds 32767 overflows at compile time; use `U` and `L` suffixes.
4. Global integer-only array initializers are emitted as FCB/FDB and **not re-initialized if the program re-runs** (src: manual "Execution of global array initializers"). Irrelevant for a game that boots once, relevant for a test harness that re-enters `main`.
5. With default (relocatable) code generation, any global initializer that contains an address (string pointer tables, function pointer tables, pointers to arrays) is filled in at run time by code in section `initgl`, costing code bytes per element, and such data cannot be in `rodata`. With `--no-relocate`, array names and function addresses are emitted as `FDB` constants (src: `Declaration::emitArrayAddress`, `TypeDesc::canMemberGoInReadOnlySection` in the 0.1.86 source).
6. A `const` array (`const uint8_t t[] = {...}`) goes to `rodata`; `const char *p` does **not** (the pointer is writable) (src: manual "Compiling a ROM image for a cartridge").
7. Calling an undeclared function is a warning (assumed to return int) since 0.1.85 (src: NEWS). Use `-Werror` to catch it.
8. Assigning `long` to `int` warns since 0.1.86 (src: NEWS).
9. The preprocessor is the host `cpp`. In inline asm, `#define PIA0 0xFF00` then `stb PIA0+2` expands to `stb 0xFF00 +2` and the `+2` is read as a comment; write `2+PIA0` (src: manual "Preprocessor identifiers in inline assembly"). Avoid `//` comments on `#define` lines (src: manual).

### 2.3 Standard library (`<cmoc.h>` and friends)

Declared in 0.1.86 `cmoc.h` (src: https://github.com/stahta01/cmoc/blob/master/src/stdlib/cmoc.h): `printf, sprintf, vprintf, vsprintf, putstr, putchar, strcmp, stricmp, strncmp, memcmp, memicmp, memchr, memichr, memcpy, memmove, memset, memset16, strlen, strcpy, strcat, strncpy, strchr, strrchr, strstr, strlwr, strupr, strspn, strcspn, strtok, strpbrk, isspace, isalpha, isalnum, isdigit, tolower, toupper, atoui, atoi, atol, atoul, strtol, strtoul, itoa10, utoa10, ltoa10, ultoa10, dwtoa, abs, labs, sqrt16, sqrt32, divmod16, divmod8, divdwb, divdww, mulwb, mulww, zerodw, adddww, subdww, cmpdww, exit, srand, rand, sbrk, sbrkmax, set_null_ptr_handler, set_stack_overflow_handler, setConsoleOutHook, delay, readword, readline, qsort, bsearch`, float helpers `strtof, atoff, ftoa, logf, log2f, enable_printf_float, setMC6839Trap`. `size_t` is `unsigned`, `ssize_t` exists (0.1.86), `offsetof` is a macro, `NULL` is `((void *)0)`.

Other headers: `<assert.h>`, `<coco.h>` (CoCo helpers, `byte/word/dword` and `uint8_t..int32_t` typedefs, `BOOL`, `TRUE/FALSE`), `<disk.h>` (DECB file access through the Disk Basic ROM's DSKCON), `<dskcon-standalone.h>` (floppy sector read/write **without** Disk Basic, needs its own NMI service routine), `<setjmp.h>`, `<stdarg.h>`, Vectrex headers (src: manual "Provided header files"; stdlib directory).

Missing: `stdio.h` (no FILE, fopen), `stdlib.h` (no malloc/free; only `sbrk`), `string.h` as a separate header, `stdint.h`, `stdbool.h`, `ctype.h`, `limits.h`, `math.h`. `printf` writes through a `CHROUT` pointer initialised from `$A002` (Color Basic PUTCHR) at startup; `setConsoleOutHook` redirects it (src: manual; crt.asm `INILIB`).

The library is linked as `libcmoc-crt-<target>.a` (always, it holds the compiler's helper routines) plus `libcmoc-std-<target>.a` and float libraries unless `-nodefaultlibs` (src: main.cpp `invokeLinker`). Struct assignment calls `memcpy`, so `-nodefaultlibs` requires our own `memcpy` (src: manual).

### 2.4 Floating point

`float` is a struct `_Float` internally. With the default backend the operations call Color Basic routines (`$B4F4` GIVABF, `$BACC` multiply, `$BD12` string to float, FPA0 at `$004F`, FPA1 at `$005C`) (src: `src/float/float.inc`). Consequences for us: the Extended Color Basic ROM code must be mapped where CMOC expects it and its direct-page work area must be intact; the routines are **not reentrant** ("an interrupt service routine ... must not do float operations if the main program is making use of them") (src: manual). `--mc6839` (experimental, 0.1.86) instead links the whole 8 KB MC6839 ROM image (`Float09.bin`), uses a 32-bit format (about 7 significant digits instead of 9), requires `enable_printf_float()` for `%f`, and supports a trap function (src: manual, NEWS 0.1.86). `sinf/cosf/tanf/atanf/logf/expf/sqrtf/...` exist only with Extended Color Basic (src: NEWS 0.1.77).

Turbo Pascal's Real is a 6-byte software float (39-bit mantissa). No CMOC option matches it. For a deterministic port, implement the handful of Real operations PoR actually uses either as integer/fixed-point code proven equal on all inputs the game produces, or as a small emulation of TP's 6-byte Real arithmetic in C/asm [recommendation].

### 2.5 32-bit arithmetic cost

`long` is represented as struct `_Long`/`_ULong` (src: doc/cmoc-implementation.markdown). Operations are calls to helpers that receive operand **addresses**, e.g. `addDWordDWord`: "pushed addresses: left dword, right dword. X => destination dword", which itself does `pshs u,y`, two loads of pointers, `ldd/addd/std` twice, `puls y,u,pc` (src: `src/stdlib/addDWordDWord.asm`). Add the caller's `leax`/`pshs` setup and a 32-bit add costs on the order of 60 to 90 cycles versus about 14 for 16-bit [estimate from the listed instructions and MC6809E timings]. Multiplication (`mulDWordDWord`), division (`divDWordDWord`, bit-serial), shifts (`leftShiftDWord`, loop per bit) are much worse. `long` and `float` return values are written through a hidden first parameter (src: manual "Calling convention").

16-bit helpers: `MUL16` uses three MUL instructions (about 60 cycles with the push/pop) and `DIV16` is a 16-iteration shift-subtract loop (several hundred cycles) (src: `MUL16.asm`, `DIV16.asm`). CMOC inlines MUL for 8x8 and shifts for some constant multiplies and divides, and has special cases for unsigned byte division by 3 and 7 (src: NEWS 0.1.81; `BinaryOpExpr.cpp` around line 1200 to 1300).

---

## 3. Code generation

### 3.1 Calling convention (0.1.86 manual "Calling convention", verbatim facts)

- Arguments pushed on the hardware stack S in reverse order; **caller pops**.
- `char` promoted to `int`, `unsigned char` to `unsigned int`; a 1-byte struct gets a padding byte (for `va_arg`).
- Return value in **B** (byte) or **D** (16-bit). Struct, long, float, double: stored at an address passed as a hidden first parameter.
- CMOC functions preserve **U, Y, S and DP**; they may modify **A, B, X, CC**. Y must be preserved on all targets for portability (it is the data pointer under OS-9), but "the compiler's low-level optimizer may emit code that uses Y when targeting a platform other than OS-9" (it saves it).
- DP is never used or modified by CMOC-generated code.
- Frame: `PSHS U / LEAU ,S` on entry and `LEAS ,U / PULS U,PC` on exit when the function has parameters or locals (an `interrupt` function ends with `PULS U` / `RTI`). First parameter is at `4,U` (`FIRST_FUNC_PARAM_FRAME_DISPLACEMENT = 2 + 2`, Declaration.h); locals are at negative offsets from U, allocated with `LEAS -n,S`.
- Undocumented in the manual but present in 0.1.86: the `_CMOC_fpir_` function qualifier ("first parameter in register"): the first parameter arrives in **B** if 8-bit or **X** if 16-bit and is spilled to the frame on entry; not allowed when the first parameter is a struct or larger than 2 bytes (src: lexer.ll line 232; FunctionDef.cpp lines 511 to 520 and 681 to 700; `TranslationUnit::getFirstParameterRegister`). Usable for asm-called C entry points; check it still exists in 0.1.100.

Calling-sequence cost for `f(a, b)` with two int locals: `LDD b,U / PSHS D / LDD a,U / PSHS D / LBSR f / LEAS 4,S` plus callee `PSHS U / LEAU ,S ... LEAS ,U / PULS U,PC`. With MC6809E timings (LBSR 9, PSHS/PULS 5 + 1 per byte, RTS 5, `n,R` 8-bit offset +1) (src: MC6809E datasheet, colorcomputerarchive.com Datasheets) this is roughly 50 to 60 cycles of overhead per call before any work [estimate]. Small functions called in loops are expensive: inline them by hand or with macros.

### 3.2 How data is addressed

- Locals and parameters: `n,U` (5-bit offsets are +1 cycle, 8-bit +1 cycle and +1 byte, 16-bit +4 cycles and +2 bytes) (src: MC6809E datasheet). Keep frames small so offsets stay within -128..127.
- Globals and literals: always `name,PCR` on non-OS-9 targets (src: `TranslationUnit::getDataIndexRegister` returns `",PCR"`). A 16-bit PC-relative offset costs +5 cycles and +2 bytes, so `LDD global,PCR` is 10 cycles / 4 bytes against 6 cycles / 3 bytes for extended addressing (src: MC6809E datasheet). `--no-relocate` only rewrites `LEAX foo,PCR` to `LDX #foo` and turns LBSR into JSR (JSR extended is 8 cycles vs LBSR 9) (src: `ASMText::removePCRIfRelocatabilityNotSupported`, FunctionCallExpr.cpp line 1019, NEWS 0.1.78). Hot globals therefore belong in assembly (direct page) or are copied to a local or accessed through a pointer held in X.
- Expression evaluation: r-value in D/B, l-value address in X; an assignment `foo = bar` is "evaluate bar in D, PSHS B,A, evaluate address of foo in X, PULS A,B, STD ,X" before peephole cleanup (src: doc/cmoc-implementation.markdown). CMOC does no register allocation across statements; values go back to the frame.

### 3.3 Optimizer

- `-O0`: no peephole optimizer. `-O1`: peephole without Jamie Cho's 2016 optimizations. `-O2` (default): all (src: manual "Disabling some optimizations"). In 0.1.86 there are 20 level-1 and 66 level-2 peephole rules applied iteratively (up to 300 passes) on the assembly text (src: `ASMText::level1OptimFuncs`, `level2OptimFuncs`, `peepholeOptimize` in ASMText.cpp).
- `-fomit-frame-pointer` (0.1.82+, "use with caution") removes the U frame for functions that do not need one; it does not act on functions containing inline asm (src: NEWS 0.1.82, 0.1.84 and 0.1.86 fixes). In the substack benchmark it shrank memops from 54 to 40 bytes (src: https://vectrex.substack.com/p/cmoc-vs-vbcc-vs-gcc6809, quoted in 01-cpu-6809-6309.md).
- Peephole improvements continue: 0.1.98 is 8.9% smaller and up to 33% faster than 0.1.67 on the same kernels (src: substack addendum).

### 3.4 Benchmarks

Roger Boesch's comparison (Vectrex freestanding kernels, cycle-accurate simulator; CMOC 0.1.67 and 0.1.98 `-O2` without `-fomit-frame-pointer`, vbcc `vbcchc12` `-O=255`, gcc6809 4.3.6 dftools `-O2`) (src: https://vectrex.substack.com/p/cmoc-vs-vbcc-vs-gcc6809):

| Metric | CMOC 0.1.67 | CMOC 0.1.98 | vbcc | gcc6809 |
|---|---|---|---|---|
| Kernel code size, 11 kernels (bytes) | 1333 | 1214 | 1188 | 948 |
| Size ratio vs gcc6809 | 1.41 | 1.28 | 1.25 | 1.00 |
| Speed ratio (cycles) vs gcc6809, 10 kernels | 2.43 | 1.99 | 1.64 | 1.00 |
| Pong whole program (bytes) | 1092 | n/a | 874 | 789 |

Per kernel cycles for CMOC 0.1.98: objmove 3741 (gcc 1509), collide 15945 (7644), isort 11536 (6553), checksum 8593 (3657), bcdscore 536 (342). CMOC won only `fixmul` (gcc6809 could not link `__mulsi3`). An older informal test found a CMOC prime sieve ran at about half the speed of gcc6809, attributing part of it to stack-only parameter passing (src: https://www.aslak.net/index.php/2018/03/07/exploring-c-compilers-for-the-6809/).

Versus hand assembly: I found no rigorous public benchmark. Practitioners keep hot paths in assembly: Space Bandits' guide says "Prefer assembly for hot paths. C (via CMOC) is acceptable for object logic" (src: https://github.com/jamieleecho/space-bandits CLAUDE.md). A claim of "3 to 5x" for asm over C appears on docs.retrogamecoders.com/c/cmoc/ but that page also wrongly says CMOC has no float and uses a software stack, so treat it as unreliable. Working estimate: CMOC is 2x to 4x slower than careful hand assembly on byte loops [estimate].

### 3.5 Writing C that CMOC compiles well

| Do | Why (source) |
|---|---|
| Use `uint8_t` loop counters and indices when the range fits; use `unsigned` over signed | "more efficient code for unsigned arithmetic" (manual) |
| Pre-increment `++i` | "typically generates one instruction less" (manual) |
| Walk arrays with a pointer (`*p++`) instead of `a[i]` with 16-bit `i` | avoids index multiply/add per access; CMOC has a small optimization for element size < 256 with 16-bit index (NEWS 0.1.85) but pointer walking is still cheaper [estimate] |
| Avoid `long` in loops and comparisons | helper calls via pointers (section 2.5) |
| Avoid division and modulo by non-constants; use shifts/masks for powers of two | `DIV16` is bit-serial |
| Make read-only tables global `const` arrays, not locals | locals are initialised by run-time stores (manual "Array initializers") |
| Use `static` locals for large buffers | stack frames with 16-bit offsets cost +4 cycles per access; large frames risk stack overflow |
| Cache a hot global in a local inside a loop | globals are `,PCR` 16-bit (10 cycles per LDD) |
| Pass a pointer to a struct, never a struct by value; avoid struct return | by-value copies through `memcpy`/push helpers (`pushStruct.asm`) |
| Keep functions with many small calls flat; macro-inline tiny accessors | ~50 cycle call overhead |
| Prefer `switch` over long if-chains on dense small values | jump table (`jumpTableSwitch.asm`), `--switch=jump` to force |
| Read the `.s` and `.lst` (`-i` / `--intdir`) for every hot function | the generated asm is annotated with C source lines (aslak.net) |

---

## 4. Memory layout control

### 4.1 Options and pragmas

| Option | Meaning (0.1.86 `--help` text and manual) |
|---|---|
| `--org=X` | First code address (hex). Default `$2800` for CoCo Disk Basic; `$2600` with `--dos`; `$000D` OS-9; `$0000` Vectrex/FLEX |
| `--data=X` | Put writable globals (`rwdata`, `bss`) at X instead of after the code |
| `--limit=X` | Fail if `program_end` exceeds X (0.1.86 also deletes the output when it fails) |
| `--stack-space=N` | Bytes reserved for the stack (default 1024 on CoCo); only affects `sbrk()` and `--check-stack`; must be given when compiling the file with `main()` |
| `--raw`, `--srec` | Output format override (lwlink `--format=raw` / `srec`) |
| `--no-relocate` | Code may assume its link address (JSR, FDB pointer tables) |
| `--coco` (= `--decb`, `--coco3`, `--coco-basic`), `--dos`, `--dragon`, `--os9`, `--flex`, `--thommo`, `--thomto`, `--vectrex`, `--usim`, `--void-target` | Target platform. `--coco3` is only a synonym of `--coco` (main.cpp line 828). `--void-target` is "a target that has no I/O system known to CMOC" (SREC output by default) |
| `--mc6839` | MC6839 float ROM image |
| `--check-null`, `--check-stack` | Debug run-time checks (about 9% code size for null checks) |
| `-i` / `--intermediate`, `--intdir=D` | Keep `.s`, `.lst`, `.map`, `.link` |
| `-S`, `-c`, `-E`, `--deps`, `--deps-only`, `-MT/-MD/-MP/-MF` | Usual compile stages and make dependencies |
| `-nodefaultlibs`, `-L`, `-l` | Libraries (`-l` after the objects) |
| `--lwasm=`, `--lwlink=` | Path to the tools; can point at wrapper scripts (Space Bandits does this) |
| Warnings | `-Wsign-compare`, `-Wgives-byte`, `-Wshadow`, `-Wlocal-var-hiding`, `-Wfor-condition-sizes`, `-Werror`, and `-Wno-*` variants |
| Newer than 0.1.86 (seen in use) | `--initial-s=HEX` ("only takes effect when compiling main()", resets S at start), `-Wno-assign-in-condition` (src: fujinet-config Makefile). [Details unverified] |

Pragmas `#pragma org`, `data`, `limit`, `stack_space` work only when compiling a single C file straight to an executable, not with `-c` (src: manual "Specifying code and data addresses").

### 4.2 Sections and the generated link script

Every C file goes into these LWASM sections; assembly modules must follow the same convention (src: manual "Assembly language modules"):

| Section | Contents |
|---|---|
| `start` | `program_start` (only in the file with `main`) |
| `code` | functions |
| `constructors`, `destructors` (+ `_start`/`_end`) | library hooks run before/after `main` |
| `initgl` (+ `initgl_start`, `initgl_end`) | run-time initialisation code for globals; must not end with RTS |
| `rodata` | string literals, `const` globals, long/float literals |
| `rwdata` | writable globals with static initialisers |
| `bss` (flag `bss`) | uninitialised globals, `RMB` only |
| `program_end` | defines the end label |

CMOC writes this lwlink script for non-OS-9 targets (src: `createLinkScript` in main.cpp):

```
define basesympat s_%s
define lensympat l_%s
section start load <org>
section code
section constructors_start
section constructors
section constructors_end
section destructors_start
section destructors
section destructors_end
section initgl_start
section initgl
section initgl_end
section rodata
section rwdata [load <data>]
section bss,bss
section program_end
entry program_start
```

and calls `lwlink --format=decb --output=... --script=x.link --map=x.map -L<floatlibdir> -lcmoc-crt-ecb [-lcmoc-std-ecb ...]` (src: main.cpp `invokeLinker`). It runs lwasm as `lwasm -fobj --pragma=forwardrefmax -D<TARGET> --output=x.o [--list=x.lst] x.s` and **does not pass `--6809`**, so inline 6309 opcodes are silently accepted (src: Parameters.cpp line 569). Assemble our own `.asm` modules with `--6809` or `PRAGMA 6809`.

There is no `#pragma section` or attribute to move a function to another section (src: Pragma.cpp supports only `org`, `limit`, `data`, `stack_space`, Vectrex pragmas). To place C code elsewhere you must (a) link that object separately at another `--org`, or (b) compile with `-S`, rewrite `SECTION code` to another name with a script, assemble with lwasm, and link with your own script. Space Bandits does (b)-style post-processing (section 5.3).

### 4.3 Startup code

`program_start` does `LDD #-stackspace`, `LBSR INILIB`, `LBSR _main`, pushes the return value and `LBSR _exit` (src: TranslationUnit.cpp lines 1100 to 1145). `INILIB` (crt.asm): clears `bss` byte by byte, saves `INISTK` = caller's S for `exit()`, sets `end_of_sbrk_mem` and `program_break` (`sbrk` region from `program_end` to S minus stack space), sets null/stack handlers, loads `CHROUT` from `$A002` on CoCo, calls `INITGL` (global initialisers) and then the `constructors`. **It does not set S** (0.1.86): the program runs on whatever stack LOADM/EXEC left, near the top of Basic's RAM. `exit()` restores S from `INISTK` and returns to the caller (Basic) with the status in D (src: manual "Value returned by main()").

What the `--coco` target assumes: loaded by `LOADM` into Basic's RAM (default `$2800` leaves `$2600` to `$27FF` for Basic), Color Basic present for `printf` (`$A002`), `sbrk` memory up to about `$7F00`, Extended Basic for float, Disk Basic for `<disk.h>`, Basic's 60 Hz IRQ running (`delay()` on CoCo busy-waits until Basic's `TIMER` variable reaches the target, so it hangs if Basic's IRQ handler is not running) (src: `src/stdlib/delay.asm`) (src: manual sections "sbrk", "printf", "Origin address").

### 4.4 Taking over the machine (no ROM)

CMOC-generated code itself never touches ROM. Only library pieces do: `printf/putchar/putstr` (through `CHROUT`), float (Basic ROM), `<disk.h>`, `<coco.h>` helpers that call Basic, `sbrk` (assumes the Basic layout), `delay`. A takeover program:

1. Is loaded by a small DECB loader (`.bin` via LOADM) or boots from track 34 (`--dos` plus `install-coco-boot-loader`, src: manual "Compiling a program executable by the DOS command").
2. In the first lines of `main` (or in an asm `start` module linked first), masks interrupts, sets S to resident RAM, programs the GIME (`$FF90` and friends, see 02-gime-video-memory-io-sound.md), maps its own blocks, installs its vectors, then never returns (do not call `exit()`).
3. Uses `setConsoleOutHook` or simply avoids `printf`; uses only the string/memory functions, which are pure code.
4. Avoids float (or uses `--mc6839`).
5. Reads the disk with its own driver or `dskcon-standalone.h`, which reads/writes floppy sectors without Disk Basic but requires installing its NMI service routine and calling `dskcon_irqService()` from the IRQ handler (src: `src/stdlib/dskcon-standalone.h`).

FujiNet config's CoCo 3 backend is a concrete CMOC example of GIME takeover from C: it masks interrupts with `asm("pshs","cc"); asm("orcc","#$50")`, copies a task-1 MMU map to `$FFA8`, flips `$FF91` to task 1 to draw into a `$8000` window, writes `$FF90 = $4C` ("CoCo 3 mode, MMU on, $FExx constant"), `$FF98 = $80`, `$FF99 = $1E` (320x192x16) (src: https://github.com/FujiNetWIFI/fujinet-config `src/coco/text_gime.c`).

### 4.5 Interrupt service routines

`interrupt void isr(void) { ... }` ends in `PULS U / RTI` instead of RTS; such a function cannot have parameters or be called (src: manual; error list). The manual's hook example reads the vector address from `$FFF8` and writes a `JMP` (`$7E`) plus the ISR address there, between `disableInterrupts()` / `enableInterrupts()` from `<coco.h>`; FIRQ vector is `$FFF6` (src: manual "Interrupt Service Routines"). On the CoCo 3 these vectors point into the `$FEF0` to `$FEFF` secondary vector page (see 02-gime file).

IRQ is safe for a C ISR because the 6809 stacks all registers (E=1, RTI 15 cycles). **FIRQ stacks only PC and CC (RTI 6 cycles)** (src: MC6809E datasheet), and a CMOC function clobbers A, B, X and CC. A C function used as a FIRQ handler therefore needs an asm wrapper that saves D and X (and Y if any called code might use it): `FIRQ: PSHS D,X,Y / LBSR _firqBody / PULS D,X,Y / RTI` with `firqBody` an ordinary (non-`interrupt`) function. For the 236.7 Hz sound tick, write the whole FIRQ handler in asm. Never use float in any ISR (src: manual).

---

## 5. Separate compilation, libraries, multiple binaries and banking

### 5.1 Modular builds and libraries

```
cmoc -c --no-relocate -O2 combat.c          # -> combat.o (LWOBJ16)
cmoc -c blit.asm                           # CMOC runs lwasm -fobj on .asm/.s too
lwar -c libpor.a a.o b.o c.o               # library; only referenced members are linked with -lpor
cmoc -o por.bin --org=2000 --data=6000 main.o libpor.a -lcmoc-std-ecb ...
```

Each `.o` is indivisible; put rarely used functions in their own files if a library is meant to be selective (src: manual "Creating libraries"). External name clashes are link errors since 0.1.83 (src: NEWS). C names get a leading underscore in asm (`foo` is `_foo`) (src: manual).

### 5.2 Driving lwlink yourself

lwlink options: `--format=decb|raw|raw2|srec|ihex|os9`, `-o`, `--script=FILE`, `--section-base=SECT=BASE` (ignored when a script is given), `--map=FILE`, `-l`, `-L`. Script directives: `section NAME [load] ADDR`, `section NAME high ADDR` (ends just below ADDR), `section NAME` (follows previous), `*`, `*,bss`, `*,!bss`, `sectopt NAME padafter ...`, `define basesympat`/`lensympat`, `entry sym`, `pad size`. **DECB output: every `load` starts a new block and "It is legal for sections to overlap ... the linker assumes the loader will sort everything out." Raw output: only one `load` for non-BSS sections, and it must be first.** Sections flagged `constant` (or named `_constants`) hold absolute symbols the linker does not relocate (src: https://www.lwtools.ca/manual/manual.pdf). Object files contain per-section exported symbols, incomplete references and code (src: same, "LWOBJ16").

Practical consequences:

- A single lwlink run can emit one DECB `.bin` with several blocks at fixed addresses (e.g. resident code at `$2000`, an initial overlay at `$C000`), each block being one `load` line. A tiny host script can split DECB blocks into per-bank files.
- For bank images, prefer one lwlink run per bank with `--format=raw` (or `raw2` if BSS bytes must be present) and a `section code load <window>` script.
- To let an overlay link call resident functions and use resident globals and CMOC helpers, generate an assembly file from the resident `.map` that exports every resident symbol as an absolute value in a constant section, and put its object first on the overlay link line [design proposal; mechanism per lwtools manual, not tested here]. DynoSprite does the equivalent by `INCLUDE`-ing a generated `dynosprite-symbols.asm` built by `scripts/symbol-extract.py` from the pass-1 listing (src: https://github.com/jamieleecho/dynosprite makefile steps 4 to 7).

### 5.3 Real projects that bank or overlay with CMOC (cloned and read)

**Space Bandits (Jamie Cho, CoCo 3, 512 KB, DynoSprite engine, C objects and levels)** (src: https://github.com/jamieleecho/space-bandits). This is the reference CMOC banking design:

- Engine in assembly (DynoSprite). Memory map: `$2000` to `$3FFF` main code and globals with DP at `$2000`, `$4000` to `$5FFF` level/object code or graphics aperture, `$6000` to `$BFFF` graphics window, `$C000` to `$DFFF` sprite erase data, `$E000` to `$FFFF` vectors and secondary code; 8 KB pages swapped through the GIME (src: CLAUDE.md "Memory Map"; doc/AddressMap.txt in dynosprite).
- Each object group and level is one C file, compiled by `scripts/cmoc-wrapper.py`: `cmoc -S --intermediate --raw -O2 file.c`, then the `.s` is edited: the last line is dropped, a `SECTION define_the_object` is appended containing `#define _ObjectInit _<Name>Init` style aliases and the contents of `engine/c-object-entry.asm` (or `c-level-entry.asm`), the result is run through `cpp`, assembled with `lwasm -fobj --pragma=forwardrefmax -I engine -I build/asm`, then linked by `cmoc --intermediate --org=0x0 (objects) or --org=0x6000 (levels) --lwlink=../../tools/cmoc-link` (src: scripts/cmoc-wrapper.py).
- `tools/cmoc-link` is a shell wrapper that deletes the last line of CMOC's generated `.link` script, appends `section define_the_object` and `entry program_start`, replaces `--format=decb` with `--format=raw2`, and calls the real lwlink (src: tools/cmoc-link). This is how they inject an extra section and get a raw page image out of CMOC's link step.
- The C entry glue (`engine/c-object-entry.asm`) is called by the asm engine. It saves the engine stack (`sts DynoStackPointer,pcr`), switches to a C stack (`lds #$8000`), `pshs u,y,x`, runs CMOC's `INITGL` once per load (`tst LibraryInit,pcr`), calls `_ObjectInit` / `_ObjectUpdate` / `_ObjectReactivate`, restores registers and S, and inspects B (the C return value) to request a level change. It exports a descriptor table with `fdb Object_Init, Object_Reactivate, Object_Update` (src: engine/c-object-entry.asm). Note the build option `OBJPAGEGUARD`: "num bytes to reserve at top of each object code page" (src: makefile help).
- C code calls engine routines through `static asm` wrappers in `engine/dynosprite.h`, e.g. `static asm void PlaySound(byte val) { asm { ldd 2,s / pshs u / jsr Sound_Play / puls u } }`, and the engine's globals are reached by fixed-address pointers (`#define DynospriteDirectPageGlobalsPtr ((DynospriteDirectPageGlobals *)0x2000)`).
- Object code is position-independent ("Object handling assembly code must be position-independent, because it can be loaded in different locations depending on the level", c-object-entry.asm header). Calls to the engine use absolute JSR because engine addresses are known at assembly time.
- They replaced float with a `FixedPoint` C module (game/shared/FixedPoint.c) and moved music code to a "tertiary page" at `$4000` "swapped in via `$FFA2` on demand" with page-swapping stubs in the always-mapped secondary page (src: CLAUDE.md "Music System").

**DynoSprite (Richard Goedeken, asm, upstream of the above)** (src: https://github.com/richard42/dynosprite): two-pass engine build (`--define=PASS=1` listing for symbol extraction, then `PASS=2` with generated directories), overlays assembled `lwasm -r` (raw) against `dynosprite-symbols.asm`, and `scripts/binsectionmover.py LOADER.BIN 0e00-1fff 4000 e000-ffff 6000` rewrites DECB block addresses so LOADM puts blocks destined for `$0E00`/`$E000` into a staging area, to be moved after the engine takes over the MMU (src: makefile step 14).

**FujiNet config for CoCo (CMOC, 2026)** (src: https://github.com/FujiNetWIFI/fujinet-config): no MMU code banking. The program is split into three separate CMOC executables (WIFI, MAIN, FILES, plus CoCo 3 variants built with `-DCOCO3`), each linked `--org=2600 --limit=7BF8` from explicit object lists, chained with a `runm()` that pokes `RUNM"name"` into Basic's command buffer and jumps to `$AE75`, handing state over in a `struct entry_data` at a fixed address above `$7BF8`. Compiled with `--initial-s=7F00` because "RUNM keeps the caller's stack, so every app resets S". Disk built with `decb dskini`, `decb copy -b -2`. This is the "multiple binaries from one project" pattern; too slow for PoR's frequent overlay switches but a valid model for separating, for example, character creation from the main game.

**CoCoFun / Splinter (Jamie Cho)** (src: https://github.com/jamieleecho/CoCoFun): a flat CoCo 3 CMOC game, `cmoc -O2 -c` per file, linked `--org=0x2800 --limit=0x7fff`, disk via `decb dskini/copy/attr -2 -b`; no banking. Useful as a minimal Makefile template.

**gcc6809 far calls (FreeWPC, for comparison)** (src: https://github.com/bcd/freewpc `include/env.h`, `cpu/m6809/farcall.s`): gcc6809 supports `__attribute__((far("page")))` on prototypes; calls go through `__far_call_handler`, which reads the target offset and page inline after the call, saves the current bank, writes the bank register, `jsr [__far_call_address]`, restores the bank; "Overhead is about 70 cycles as compared to a normal function call, plus 3 extra bytes on the stack." CMOC has no equivalent; we reproduce the trampoline by hand.

Searches of the CoCo forums, CoCopedia and mailing-list archives turned up no other public CMOC project with general MMU code banking [gap; not exhaustive].

### 5.4 Far-call trampoline compatible with CMOC's stack convention [design proposal]

Problem: CMOC callees find their first argument at `2,S` on entry (then `4,U`). A trampoline that pushes the saved MMU state on S before `JSR` would shift every argument. Solution: keep the bank state on a separate small "bank stack" in resident RAM:

```
; Resident stub generated per overlay entry point, e.g. combat_run():
_combat_run    LDX   #_ovl_combat_run      ; real address inside the window
               LDB   #OVL_COMBAT           ; overlay id -> MMU block(s)
               JMP   farcall
; farcall: caller's return address is at 0,S, args at 2,S
farcall        PULS  Y                     ; Y = caller return address (Y saved below)
               ...push Y, current window block(s) and caller's Y onto bankstack
               ...map overlay B into window slot(s): STB $FFA6 (+ shadow)
               JSR   ,X                    ; callee sees args at 2,S as usual
               ...pop window block(s), restore mapping and shadows
               ...pop caller's Y and return address (keep D intact: return value)
               JMP   ,X or PSHS X/RTS
```

Rules: preserve D (B/D return value) and U on the way out, preserve Y for CMOC, keep interrupts able to run at any point (the MMU write is atomic per slot; mask interrupts only if an ISR also changes the same slot). Cost about 60 to 90 cycles [estimate, comparable to FreeWPC's 70]. Function pointers stored in game tables must point to resident stubs, never into a window. Do not use `_CMOC_fpir_` on far-called functions unless the trampoline preserves B and X.

---

## 6. LWASM features useful to the port

From the LWTOOLS manual (src: https://www.lwtools.ca/manual/manual.pdf) unless noted:

- CPU: 6309 instructions accepted by default (`-3/--6309`); `-9/--6809` or `PRAGMA 6809` rejects them. `6809conv`/`6309conv` add convenience mnemonics.
- Output formats: `--format=obj` (LWOBJ16 for lwlink), `decb` (`-b`, LOADM format, multiple blocks), `raw` (`-r`, ORG only sets addresses), `os9`, `hex`, `srec`, `ihex`, `basic` (a BASIC POKE loader).
- Listings and symbols: `--list[=file]`, `--symbols`, `--symbols-nolocals`, `--map=FILE`, `--symbol-dump[=file]` (writes the global symbol table as assembly source: directly usable to export resident addresses to overlay builds).
- Defines and includes: `-D SYM[=VAL]`, `-I path`, `INCLUDE`, `INCLUDEBIN file[,start[,length]]`.
- Sections: `SECTION name[,bss|constant|!bss|!constant]` ... `ENDSECTION`; `EXPORT`, `IMPORT`/`EXTERN`, `EXTDEP`. ORG is not allowed inside sections in object mode.
- Macros: `name MACRO [NOEXPAND]` ... `ENDM`, parameters `\1` to `\9`, `{n}`, `\*`.
- Structures: `name STRUCT` ... `ENDSTRUCT`, field references `name.field`, `sizeof{name}`. Use them to mirror C struct layouts used by asm (keep them in sync with a generated header, or generate both from one description).
- Conditionals: `IF/IFEQ/IFNE/IFGT/IFGE/IFLT/IFLE`, `IFDEF`, `IFNDEF`, `IFPRAGMA`, `ELSE`, `ENDC`.
- Local labels: any symbol containing `@` or `?`, or `$` unless `nodollarlocal`; scope ends at a blank line, include file or macro. CMOC's manual recommends `@label` in inline asm and warns that `$` locals break OS-9 portability.
- Useful pragmas: `autobranchlength` (pick short/long branches), `operandsizewarning`, `forwardrefmax` (default since 4.14, required by CMOC), `cescapes`, `undefextern`, `export` (export all), `newsource` (spaces in operands, `;` before comments).
- Data: `FCB, FDB, FQB, FCC, FCN, FCS, RMB, RMD, RMQ, ZMB, FILL, ALIGN`; `SETDP` is advisory only (sets assembler assumption, not the register).

Mixing asm modules with CMOC C (src: CMOC manual "Assembly language modules", "Merging a binary file", "Importing symbols"):

```
        SECTION code
_blit8x8 EXPORT                 ; C: void blit8x8(uint8_t *dst, const uint8_t *src);
_blit8x8
        PSHS  U,Y               ; must preserve U and Y
        LDU   6,S               ; dst  (2 bytes return + 4 bytes pushed)
        LDY   8,S               ; src
        ...
        PULS  U,Y,PC
        ENDSECTION

        SECTION rodata
_font   EXPORT
_font   INCLUDEBIN font.bin     ; C: extern const uint8_t font[];
        ENDSECTION
```

- C-callable asm: names start with `_`, `EXPORT` them, arguments on S starting at `2,S`, bytes promoted to words (big-endian: the byte value is at the higher address, `3,S` for the first char argument), return in B or D, preserve U, Y, S, DP, free to trash A, B, X, CC.
- Asm calling C: `IMPORT _func`, push arguments right to left as words, `LBSR`/`JSR _func`, then `LEAS n,S`. Save X yourself if needed.
- Inline asm: refer to C variables with `:name` (`:v[4]` indexes elements, `:obj.field` since 0.1.79), labels in column 1, no change to U or Y.
- `asm` functions (`asm int f(int m, int n) { asm { ldd 2,s / addd 4,s } }`) have no frame and get an automatic RTS unless `__norts__`.
- Global-scope `asm { }` (0.1.84+) emits verbatim text just before the next C function.
- Data blobs: `INCLUDEBIN` in a `rodata` section with exported start/end labels.

---

## 7. ToolShed and disk images

`decb` (Disk BASIC images) commands in ToolShed 2.6.1 (src: help texts in https://github.com/nitros9project/toolshed `decb/*.c`): `dskini` (`-3`/`-4`/`-8` = 35/40/80 tracks, `-h<num>` HDB-DOS drives), `copy` (`-0..-3` file type, 2 = machine language; `-a`/`-b` ASCII or binary; `-t` BASIC token translation; `-l` EOL translation; `-r` overwrite; `-c` concatenate ML segments), `dir`, `list`, `attr`, `kill`, `rename`, `free`, `fstat`, `dsave`, `hdbconv`, `binbust` ("Strip DECB binary pre-, inner-, and post- ambles"). Executive option `-g<num>` sets FAT granule count (68 for 35 tracks, 78 for 40, 156 for 80). Typical:

```
decb dskini POR.DSK
decb copy -2 -b por.bin POR.DSK,POR.BIN
decb copy -2 -b ovl01.raw POR.DSK,OVL01.BIN     # raw page images as binary files
decb copy -0 -t loader.bas POR.DSK,LOADER.BAS
decb dir POR.DSK
```

`os9` commands: `format` (`-t` tracks, `-ds`, `-dd`, `-l` logical sectors for hard drive images, `-n` name), `copy`, `attr`, `makdir`, `dir`, `del`, `gen` (`-b=bootfile`, `-t=trackfile`), `ident`, `modbust`, `padrom`, `dsave`, `dump`. CMOC also ships `writecocofile` (copy a `.bin` into a 35-track image, `-r` read, `-d` list) and `install-coco-boot-loader` (track 34 boot loader for `--dos`) (src: CMOC manual).

---

## 8. Alternatives and when to leave CMOC

| Option | Status | Fit for PoR |
|---|---|---|
| **CMOC 0.1.100** | Actively maintained (0.1.98 in June 2026), in the container, C89 plus useful C99, LWTOOLS based, real CoCo 3 users | **Chosen.** Weakest code of the three C compilers, no banking support |
| **gcc6809** (GCC 4.3.x patches; GitLab `dfffffff/gcc6809`, branch `dftools`) | 2008-era GCC, "hard to build", native `cc1` crashes on Apple Silicon for two-argument functions, prebuilt x86_64 works; prebuilt libgcc lacked `__mulsi3`; register argument passing; `far` attribute banking (FreeWPC) (src: substack; aslak.net; https://gitlab.com/dfffffff/gcc6809; worldofdragon thread https://archive.worldofdragon.org/phpBB3/viewtopic.php?p=13232 notes 64-bit build problems fixed in 2015 and an lwasm `d,s` bug fixed in 4.11) | Best code (about 2x faster, 0.78x size). Not in our container. Consider only for a few hot C modules after profiling, keeping CMOC's calling convention at the boundary or writing glue |
| **vbcc** 6809/6309/68hc12 backend (Volker Barthelmann) | "second alpha release"; newer `vbcc6809_20260125.zip` with Vectrex target mentioned by the author; licence "free for non commercial use" with no explicit licence for generated code (src: http://www.compilers.de/vbcc.html; substack comments) | Middle quality (1.64x gcc cycles). Alpha, licensing unclear, no CoCo target. Plan C only |
| **LLVM** | No public 6809 backend found. Boisy Pitre's BASIC09 LLVM frontend (2026) mentions separate "MC6809 backend" work, not published; his `DrPitre/llvm-project` fork has no M6809 target directory (src: https://www.phoronix.com/news/BASIC09-LLVM-Front-End; https://github.com/drpitre/basic09c README; checked fork tree) | Not available |
| **Pascal for 6809** | Period products: OS-9 Pascal (Microware; P-code interpreter plus a native code translator "four to ten times faster", PascalS virtual memory) (src: https://www.cocopedia.com/wiki/OS-9), DEFT Pascal Workbench (DECB), Color Pascal (Colorware), Quick Pascal, TSC FLEX Pascal (manuals listed at https://colorcomputerarchive.com/repo/Documents/Manuals/Programming/) | None accept Turbo Pascal 6.0 (units, overlays, inline, `absolute`, objects); all run on the CoCo, not as cross compilers. Not usable |
| **TRSE / Turbo Rascal** | Modern Pascal-like cross compiler with a 6809 code generator and CoCo 3 project templates (src: https://github.com/leuat/TRSE tree: `codegen_6809.cpp`, `Publish/project_templates/coco3_clean`) | Different language; would mean re-porting from Pascal source by hand. Not suitable for a 48,000-line verified translation |
| **Basic09** | OS-9 I-code compiler plus interpreter (RunB) (src: cocopedia OS-9) | Requires OS-9, interpreted; no |
| Hand assembly everything | Possible, used by DynoSprite | Too large (about 200 KB of logic); use only for hot paths |

Verdict: CMOC + LWTOOLS for all C, LWASM for hot paths and all machine-level glue (trampolines, ISRs, blitters, loaders). Leave CMOC for a module only if profiling in MAME/XRoar shows a logic hot spot that cannot be fixed by restructuring the C or by rewriting that function in assembly; rewriting in asm is preferred over adding gcc6809 to the build.

---

## 9. CMOC rules for the Pool of Radiance port

Later agents adapting the generated C must follow these rules.

1. **Widen byte arithmetic explicitly.** Any `+ - * / %` whose operands are both 8-bit (variables, fields or constants 0 to 255) and whose result can exceed the byte range or is used as a 16-bit value must cast one operand: `(uint16_t)row * 40u`, `(int16_t)hp + bonus`. Build with `-Wgives-byte` and treat each warning as a bug until proven harmless.
2. **Make signedness explicit** on every mixed signed/unsigned `+ - * / % < <= > >=`. CMOC uses the left operand's signedness. Build with `-Wsign-compare`. Mirror Turbo Pascal semantics (TP widens Integer/Word mixes to LongInt) with explicit `(int32_t)` casts where the decomp's C already does so.
3. **Provide shim headers**: `stdint.h` (from `<coco.h>`-style typedefs: `uint8_t` unsigned char, `uint16_t` unsigned int, `uint32_t` unsigned long, signed variants), `stdbool.h` (`typedef uint8_t bool`), `string.h`/`stddef.h`/`stdlib.h` that include `<cmoc.h>`. No `_Bool`, `inline`, `restrict`, `_Static_assert`: map `inline` to nothing or `static`, and implement static asserts with a negative-size array typedef at global scope.
4. **Hoist every struct, union, enum and typedef to file scope.** No local struct/enum/typedef definitions, no enum-with-list in parameter or return types (declare `enum X {...};` globally, then use `enum X` or `int16_t`).
5. **No designated initializers or compound literals**; write positional initializers with every field in order (CMOC zero-fills missing trailing fields since 0.1.78, but warn-free code lists them).
6. **Bit-fields cost full storage.** Replace Pascal packed sets/bit records with explicit `uint8_t` masks and shifts, keeping the exact on-disk byte layout of character (285-byte) and item (63-byte) records.
7. **Never rely on `long` being cheap.** Use `int32_t` only where the Pascal type was LongInt and the value can exceed 16 bits (experience, money, file offsets). Do not put `long` in loop counters, array indices or `switch` (unsupported).
8. **No float in game code.** Replace each Pascal Real routine with integer or fixed-point code and compare results against the PC version over the full input range. Never link the Basic-ROM float library in the takeover build.
9. **Pass structs by pointer.** No struct parameters or struct return values in game code; a function that "returns a record" takes an output pointer. Struct assignment is allowed (it calls `memcpy`) but avoid it in hot loops.
10. **Globals live in a few dedicated files** (`globals_*.c`) linked into the resident image. Overlay modules define no writable globals or `static` data of their own (only `const` tables, which go into the overlay's `rodata`). This mirrors Turbo Pascal, where overlay units' variables live in DGROUP.
11. **Build everything with `--no-relocate -O2`**, plus `-Werror` once warnings are clean. Evaluate `-fomit-frame-pointer` per module with the test suite before enabling it globally.
12. **Function pointers must point to resident code.** Dispatch tables (ECL opcodes, menu actions, spell effects) hold addresses of resident functions or resident far-call stubs, never of code inside an MMU window.
13. **Calls into another overlay go through generated stubs** (section 5.4). No overlay calls another overlay's function directly, and no overlay keeps a pointer into another overlay's code or rodata after returning.
14. **Do not use `printf`, `sprintf`, `sbrk`, `delay`, `readline`, `<disk.h>` or `<coco.h>` helpers in the takeover build.** Use our own text output, timer and disk modules. String/memory functions from `<cmoc.h>` are fine (pure code).
15. **Set S ourselves.** The first code of the game must load S into resident, always-mapped RAM with room for the deepest call chain plus interrupt frames (12 bytes per IRQ). Never call `exit()` or return from `main()` in the game build.
16. **Large locals become `static`** (or globals). Keep each function's frame under 128 bytes so `n,U` uses 8-bit offsets; no local arrays over about 64 bytes.
17. **Hot globals are accessed through a local copy or a pointer** inside loops; the hottest few move to an asm-owned direct page block declared in asm and imported in C. CMOC never changes DP, so DP belongs to assembly.
18. **Prefer `uint8_t` counters, `++i`, pointer walking (`*p++`) and `unsigned` types**; avoid `/` and `%` by non-constants and non-powers of two in hot code.
19. **Interrupt handlers:** the 60 Hz IRQ may be a C `interrupt void` function (no parameters, no float, no far calls, short); FIRQ handlers are written in assembly (only PC and CC are stacked). All ISRs live in resident memory and keep their own MMU state shadow.
20. **Inline asm hygiene:** prefix C variables with `:`, labels in column 1 with `@` locals, never modify U or Y (save/restore Y if a sequence needs it), write `2+PIA0` instead of `PIA0+2` with macros, and assemble standalone `.asm` files with `--6809` (or `PRAGMA 6809`) so no 6309 opcode slips into the baseline build.
21. **Asm entry points follow CMOC's convention** unless marked otherwise: args on S at `2,S` upward as 16-bit words (a byte argument is in the low byte, the higher address), result in B/D, preserve U/Y/S/DP. Register-argument asm routines are only called through `asm` wrapper functions or inline asm.
22. **Switch statements:** no `continue` inside a `switch` body (restructure the loop), no statements before the first `case`, no Duff's device, no `long` selector. Dense opcode switches (ECL VM) become jump tables automatically; check the `.s`.
23. **Array sizes and constant expressions** that exceed 32767 must use `U`/`L` suffixes; no array over 32767 bytes (split, or put large buffers in MMU blocks managed by asm).
24. **Every module is compiled with `-i --intdir=build/int`**, and reviewers read the `.s` of any function in a per-frame or per-tile path. Keep the `.map` files: overlay sizes and the resident symbol export are generated from them.
25. **Check CMOC version-specific facts in the container** (`cmoc --version`, `--help`, NEWS) before relying on undocumented features such as `_CMOC_fpir_` or `--initial-s`.

---

## Implications and recommendations for the port

1. **Build architecture.** Use a Makefile that calls `cmoc -c` for C, `lwasm -fobj --6809` for asm, and **lwlink directly with our own scripts** for the final images (one resident image plus one raw image per overlay window page). Use `cmoc`'s own link step only for quick experiments. Generate the resident symbol export (from `lwasm --symbol-dump` or the lwlink `.map`) as an absolute-symbol object for overlay links; link overlays with `-nodefaultlibs` and resolve CMOC helpers (`MUL16`, `DIV16`, `addDWordDWord`, `memcpy`, ...) to the copies in the resident image, so each overlay does not carry its own helpers [design; verify lwlink resolution order with a two-file test early].
2. **Map Turbo Pascal's overlay manager onto the MMU.** Each TP overlay unit (largest 17.5 KB of x86) becomes one overlay link at a fixed window (8 KB or 16 KB, two consecutive MMU slots). The memory layout decision belongs with the GIME/memory research (02 file), but the toolchain constraint is: one fixed origin per overlay link, no cross-overlay pointers, all entry points through resident stubs. Measure real CMOC sizes for the three largest overlays first; if any exceeds the window, split it along procedure boundaries.
3. **Run a CMOC compatibility pass on the existing C before any memory-model work**: shim headers, hoisting local types, removing designated initializers, `-Wgives-byte -Wsign-compare -Werror`, and running the existing unit tests under the CMOC build on USim (`--usim`) or MAME. The `--usim` target lets CMOC-compiled logic run headlessly on the host for differential tests against the PC build [CMOC ships USim 0.91 in its source tree; check whether the container installs the simulator].
4. **Keep a portable C core.** Avoid CMOC-only syntax outside a few platform files (`interrupt`, `asm`, `_CMOC_fpir_`), so the logic still builds with gcc/clang on the host for testing and could be tried with gcc6809 if a hot module needs it.
5. **Assembly owns**: startup/takeover, MMU and trampolines, ISRs (IRQ timer and FIRQ sound), disk driver, DAX RLE decode, all blitters, glyph expansion, frame-delta XOR, line drawing inner loop, memory fill/copy, and the direct page.
6. **Plan for performance measurement** from the first playable build: MAME/XRoar cycle counting around combat AI, pathfinding and ECL interpretation, since CMOC logic will run at roughly PC-8088 speed or slower.

## Open questions

1. What changed between CMOC 0.1.86 and 0.1.100 (options such as `--initial-s`, `-Wno-assign-in-condition`; any section, banking, register-parameter or 6309 features; whether `_CMOC_fpir_` remains)? Read NEWS in the container.
2. Does lwlink resolve an import against an absolute symbol in a `constant` section of an earlier object before searching libraries, so overlays can share resident helpers? Needs a two-file experiment.
3. How large is CMOC output relative to the x86 for real PoR modules (estimate 0.9x to 1.5x in 01-cpu-6809-6309.md)? Compile the largest overlay as soon as the C is CMOC-clean.
4. Which Turbo Pascal Real operations does PoR actually execute, and with what inputs (to choose integer replacement vs TP Real emulation)?
5. Does a `while (flag == 0) {}` loop on a global set by an ISR always reload the global in CMOC 0.1.100 (no `volatile` support)? Inspect the `.s`; until confirmed, read ISR-shared flags through inline asm or an asm accessor.
6. Is `--initial-s` usable to place S at boot for the takeover image, or must the asm start module do it?
7. Does the container install USim (`usim`) and `writecocofile`/`install-coco-boot-loader`?

## Sources

- https://github.com/stahta01/cmoc : Git mirror of CMOC source; read at 0.1.86 (manual `doc/cmoc-manual.markdown`, `doc/cmoc-implementation.markdown`, NEWS, `src/*.cpp`, `src/stdlib`, `src/float`). Primary source for language, ABI, link script, startup and optimizer facts.
- http://perso.b2b2c.ca/~sarrazip/dev/cmoc-manual.html : official manual mirror (serves an old 0.1.44 edition); used to confirm calling convention and options.
- http://perso.b2b2c.ca/~sarrazip/dev/cmoc.html and http://gvlsywt.cluster051.hosting.ovh.net/dev/cmoc.html : CMOC home page mirrors (stale version listings 0.1.89/0.1.90).
- https://github.com/jamieleecho/coco-dev : Dockerfile and README for the coco-dev image (CMOC 0.1.100, LWTOOLS 4.25, ToolShed 2.6.1, MAME 0.287, tool list, image tag 0.88).
- https://www.lwtools.ca/ : LWTOOLS release notes up to 4.25, raw2 note.
- https://www.lwtools.ca/manual/manual.pdf : LWASM/LWLINK/LWAR manual: formats, directives, pragmas, link scripts, constant sections, object format.
- https://vectrex.substack.com/p/cmoc-vs-vbcc-vs-gcc6809 : CMOC vs vbcc vs gcc6809 benchmark, CMOC 0.1.98 release date, vbcc and gcc6809 status.
- https://www.aslak.net/index.php/2018/03/07/exploring-c-compilers-for-the-6809/ : early CMOC vs gcc6809 experience (speed, PIC, libgcc problems).
- https://archive.worldofdragon.org/phpBB3/viewtopic.php?p=13232 : gcc6809 build history and lwasm bug note.
- https://gitlab.com/dfffffff/gcc6809 : gcc6809 repository (metadata only).
- http://www.compilers.de/vbcc.html : vbcc 6809/6309/68hc12 alpha status.
- https://github.com/jamieleecho/space-bandits : CMOC + DynoSprite CoCo 3 game; cmoc-wrapper.py, tools/cmoc-link, engine/c-object-entry.asm, dynosprite.h, CLAUDE.md memory map. Reference banking design.
- https://github.com/jamieleecho/dynosprite and https://github.com/richard42/dynosprite : DynoSprite engine, address map, two-pass build, binsectionmover.
- https://github.com/FujiNetWIFI/fujinet-config : CMOC CoCo/CoCo 3 multi-binary build, `--initial-s`, GIME takeover code in C.
- https://github.com/jamieleecho/CoCoFun : flat CMOC CoCo 3 games (Splinter Makefile).
- https://github.com/jamieleecho/cmoc_os9 : OS-9 C library for CMOC (context only).
- https://github.com/bcd/freewpc : gcc6809 `far` attribute and far-call trampoline (`cpu/m6809/farcall.s`).
- https://github.com/nitros9project/toolshed : ToolShed v2.6.1 decb/os9 command help texts.
- https://colorcomputerarchive.com/repo/Documents/Datasheets/MC6809E%20HMOS%208%20Bit%20Microprocessor%20(Motorola)%20(OCR).pdf : 6809 cycle counts and indexed-mode extras.
- https://colorcomputerarchive.com/repo/Documents/Manuals/Programming/ : list of period Pascal/C/Basic09 manuals for the CoCo.
- https://www.cocopedia.com/wiki/OS-9 : OS-9 Pascal (P-code plus native translator), Basic09, OS-9 C.
- https://www.phoronix.com/news/BASIC09-LLVM-Front-End, https://discourse.llvm.org/t/rfc-adding-basic09-frontend-tool-to-llvm/91141, https://github.com/drpitre/basic09c : LLVM BASIC09 frontend; evidence that no public LLVM 6809 backend exists.
- https://github.com/leuat/TRSE : Turbo Rascal (TRSE) 6809 code generator and CoCo 3 templates.
- https://docs.retrogamecoders.com/c/cmoc/ : CMOC tutorial page; contains factual errors, cited only as an unreliable claim.
- https://8bitnews.io/article/6809-cross-compiler : brief CMOC news item (context only).
