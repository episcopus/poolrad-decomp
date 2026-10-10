# 00 Bootstrap

**Inputs:** a fresh clone on macOS (Apple Silicon) or Linux.

## Steps

1. Follow `docs/setup/SETUP-macos.md` (or its Linux notes). The script `tools/setup/setup-macos.sh` is idempotent; run it with `--dry-run` first to see what it will install.
2. Run `make doctor`. Every line must be `ok` or an explicitly optional `skip`. Fix `missing` lines before anything else.
3. Run `make inputs`. All hashes in `poolrad/` must match `re/inputs.toml`. If they do not, stop: the spec targets exactly these bytes.
4. Run `make overlays`. Expect: `35 overlays, 406 entries, 197641 code bytes, 48 unit inits (13 resident); OK`.
5. Run `make unexepack`. Expect a byte match of the unpacker output against `poolrad/start-unpack.exe`.
6. Reference compiler (needed from Phase 1 on for codegen questions, never for the build): put the Turbo Pascal archives in `build/toolchain/dist/` as listed in `docs/setup/SETUP-tp.md`, then `make emu2 tp-pin`. Expect `System unit matches: tp60-1991`. The archives are proprietary: never commit them.

## Done when

`make doctor`, `make inputs`, `make unexepack` and `make overlays` all pass; `make tp-pin` passes once the compiler archives are in place.

## Hand-off

Record the environment versions printed by `make doctor` in `work/status.md` (section "Environment").
