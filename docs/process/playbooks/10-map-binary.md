# 10 Map the binary (Mapper)

**Inputs:** a passing bootstrap; Ghidra 12.1.x with PyGhidra; `re/` files.

## Steps

1. **Import.** `make ghidra` (tool to build in this phase: `tools/ghidra/import_tp.py`). It must:
   - load `poolrad/start-unpack.exe` with the x86 16-bit Real Mode language at a fixed load segment (use `1000h` so addresses stay readable);
   - create one overlay memory block per overlay unit from `build/re/overlays/ovlNN.bin`, apply the overlay's fixups (segment values relative to the load segment), and label each entry `ovlNN_eM` at its code offset;
   - mark each stub entry (`CD 3F xx xx 00`) as a thunk to its overlay entry so cross references resolve;
   - apply everything in `re/` (names, signatures, types, comments).
2. **Units.** Fill `re/units.toml`: for each of the 48 init-chain units its kind (resident or overlay), code range, init routine, provisional name (`resNN` / `ovlNN`) and, once evidence allows, its real role. The init chain order (manifest `init_chain`) is the unit order of the original `uses` clause. Units without an initialisation part make no init call and must be found another way: the Borland Dos (`res13`, `0A32`) and Overlay (`res14`, `0AA2`) units were found by byte comparison (step 4) and carry `init = ""`. Add any game unit found the same way with the next free `resNN` id.
3. **Runtime.** The Turbo Pascal runtime units are System `0AF8`, Crt `0A40`, Dos `0A32` and Overlay `0AA2`, all byte-matched to TP 6.0 (`make tp-compare`, whitepaper 2.2); `tools/re/rtl_ident.py` applies this on every `make map`. Name every runtime routine used by game code (string helpers, set helpers, Write/WriteLn, file I/O, heap, Random, range-check and stack-check helpers). They are linked from `TURBO.TPL`, never decompiled; names matter because packets and `make match` reports use them. Record the evidence (byte patterns, interrupts used). Fastest naming route: write a few lines of Pascal that call the routine you suspect, run `make tpc SRC=that.pas DISASM=1`, and read which POOL routine each runtime call maps to (the tool aligns the fresh runtime with ours and prints `name (POOL seg:off)`).
4. **Version.** Done: **Turbo Pascal 6.0, June 1991 release** (whitepaper 2.2, SPEC section 2). To re-prove it on a new machine: put the archives in `build/toolchain/dist/` (`docs/setup/SETUP-tp.md`), then `make emu2 tp-pin`. Expect `System unit matches: tp60-1991` with zero unexplained bytes in System, Crt, Dos and Overlay. If `tp-compare` ever reports `ours-only` bytes, a POOL runtime routine is missing from `tools/re/tp_probe/SINK.PAS`: extend the probe, never the classifier.
5. **Calling convention samples.** On 5 or more routines, confirm parameter order, who pops arguments, how VAR parameters, string results and nested procedure static links are passed. Write the rules into the whitepaper (section 3.3) with the addresses as evidence.
6. **Routines.** Every routine gets an entry in `re/symbols.toml` with `id` (`ovlNN:XXXX` or `seg:XXXX`), `unit`, `addr`, `size`, and a provisional name. Sizes are gaps between starts until a routine matches: `make match WRITE=1` then writes the compiler's boundaries (sizes, bogus entries removed, missing routines added), so no mapper session is needed for boundaries after Phase 1. Use: referenced strings, called runtime routines, interrupts, data files opened, and prior-art leads (coab names for the same engine family, the user's earlier IDA names in `poolrad/START.*`). Tag every name's source in `notes`.
7. **Globals.** Start `re/dseg.toml` (DGROUP at paragraph `0C7C` in the load image): offset, size, type, name, evidence. Unknown ranges stay unnamed.
8. **Export.** `tools/ghidra/export.py` writes any names you set interactively back into `re/`; commit `re/` only, never the Ghidra project.

## Done when

`make p1-check` exits 0. That encodes SPEC section 10 Phase 1: Ghidra rebuildable, 48 init-chain units plus the runtime units without init with ranges, routines listed with sizes, RTL named, TP version pinned, DGROUP started, CC samples written, initial names from strings/prior art, agent lock/packet/status tools present.

## Tooling

| Command | Role |
|---|---|
| `make map` | ranges + forced starts + enumerate + `name_units` + `rtl_ident` + status; keeps every routine and field already in `re/symbols.toml` |
| `tools/re/forced_starts.py` | starts the scan cannot find (leaf runtime routines with no prologue): probe far-call targets confirmed by `runtime_entries`, `rtl_ident` hand tables, manual entries of `re/forced_starts.toml` with evidence |
| `make ghidra` | `map` then `tools/ghidra/import_tp.py` (needs `GHIDRA_INSTALL_DIR`) |
| `make p1-check` | verify Phase 1 exit criteria |
| `tools/ghidra/export.py` | write interactive Ghidra names back to `re/symbols.toml` |

## Hand-off

Update `work/queue.toml` with the unit order (SPEC 9.4) and the whitepaper sections 2 and 3.
