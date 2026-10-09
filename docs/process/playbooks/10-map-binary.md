# 10 Map the binary (Mapper)

**Inputs:** a passing bootstrap; Ghidra 12.1.x with PyGhidra; `re/` files.

## Steps

1. **Import.** `make ghidra` (tool to build in this phase: `tools/ghidra/import_tp.py`). It must:
   - load `poolrad/start-unpack.exe` with the x86 16-bit Real Mode language at a fixed load segment (use `1000h` so addresses stay readable);
   - create one overlay memory block per overlay unit from `build/re/overlays/ovlNN.bin`, apply the overlay's fixups (segment values relative to the load segment), and label each entry `ovlNN_eM` at its code offset;
   - mark each stub entry (`CD 3F xx xx 00`) as a thunk to its overlay entry so cross references resolve;
   - apply everything in `re/` (names, signatures, types, comments).
2. **Units.** Fill `re/units.toml`: for each of the 48 units its kind (resident or overlay), code range, init routine, provisional name (`resNN` / `ovlNN`) and, once evidence allows, its real role. The init chain order (manifest `init_chain`) is the unit order of the original `uses` clause.
3. **Runtime.** Identify the Turbo Pascal runtime units (System at segment `0AF8` is certain; others such as Crt, Dos and Overlay by their behaviour). Name every runtime routine used by game code (string helpers, set helpers, Write/WriteLn, file I/O, heap, Random, range-check and stack-check helpers). These become `src/rtl` functions. Record the evidence (byte patterns, interrupts used).
4. **Version.** Bound the Turbo Pascal version: `FBOV` overlay header, runtime copyright "1983,91", RTL routine shapes. If the user supplies Turbo Pascal 6.0 or 7.0, compile a small program and compare the System unit's code bytes. Write the result in the whitepaper (section 2) with its confidence.
5. **Calling convention samples.** On 5 or more routines, confirm parameter order, who pops arguments, how VAR parameters, string results and nested procedure static links are passed. Write the rules into the whitepaper (section 3.3) with the addresses as evidence.
6. **Routines.** Every routine gets an entry in `re/symbols.toml` with `id` (`ovlNN:XXXX` or `seg:XXXX`), `unit`, `addr`, `size`, and a provisional name. Use: referenced strings, called runtime routines, interrupts, data files opened, and prior-art leads (coab names for the same engine family, the user's earlier IDA names in `poolrad/START.*`). Tag every name's source in `notes`.
7. **Globals.** Start `re/dseg.toml` (DGROUP at paragraph `0C7C` in the load image): offset, size, type, name, evidence. Unknown ranges stay unnamed.
8. **Export.** `tools/ghidra/export.py` writes any names you set interactively back into `re/`; commit `re/` only, never the Ghidra project.

## Done when

`make p1-check` exits 0. That encodes SPEC section 10 Phase 1: Ghidra rebuildable, 48 units with ranges, routines listed with sizes, RTL named, TP version bounded, DGROUP started, CC samples written, initial names from strings/prior art, agent lock/packet/status tools present.

## Tooling

| Command | Role |
|---|---|
| `make map` | ranges + enumerate + `name_units` + `rtl_ident` + status |
| `make ghidra` | `map` then `tools/ghidra/import_tp.py` (needs `GHIDRA_INSTALL_DIR`) |
| `make p1-check` | verify Phase 1 exit criteria |
| `tools/ghidra/export.py` | write interactive Ghidra names back to `re/symbols.toml` |

## Hand-off

Update `work/queue.toml` with the unit order (SPEC 9.4) and the whitepaper sections 2 and 3.
