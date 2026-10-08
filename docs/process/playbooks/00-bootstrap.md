# 00 Bootstrap

**Inputs:** a fresh clone on macOS (Apple Silicon) or Linux.

## Steps

1. Follow `docs/setup/SETUP-macos.md` (or its Linux notes). The script `tools/setup/setup-macos.sh` is idempotent; run it with `--dry-run` first to see what it will install.
2. Run `make doctor`. Every line must be `ok` or an explicitly optional `skip`. Fix `missing` lines before anything else.
3. Run `make inputs`. All hashes in `poolrad/` must match `re/inputs.toml`. If they do not, stop: the spec targets exactly these bytes.
4. Run `make overlays`. Expect: `35 overlays, 406 entries, 197641 code bytes, 48 unit inits (13 resident); OK`.
5. P0 work still open (check `work/status.md`): reproduce `start-unpack.exe` from `START.EXE` with `tools/re/unexepack.py` (to be written: implement the EXEPACK algorithm, compare the result byte for byte, document any difference in the whitepaper).

## Done when

`make doctor`, `make inputs` and `make overlays` all pass, and the unpack chain is reproducible.

## Hand-off

Record the environment versions printed by `make doctor` in `work/status.md` (section "Environment").
