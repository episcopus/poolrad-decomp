# 20 Data formats (Mapper / Verifier)

**Inputs:** a format to decode (DAX container, a DAX block type such as GEO, ECL, PIC, SPRIT, WALLDEF, MON*CHA, ITEMS, save files).

## Steps

1. Read what is already known: whitepaper section 4 and leads in prior art (OpenGoldBox `docs/graphics-format.md`, `docs/sound-format.md`, `docs/SCRIPTS.md`, `docs/MAPS.md`; coab `Classes/DaxFiles`). Treat them as hypotheses.
2. Find the routine(s) in our binary that read the format (follow the file name string to its open call). The code is the authority.
3. Write a Python decoder in `tools/re/` with a CLI that dumps the format to JSON or PNG for inspection.
4. Write a test that runs the decoder over **every** pinned file of that kind and checks invariants (sizes, counts, round trip where the game writes the format).
5. Write the C loader only when its routines are being lifted (playbook 30); reuse the Python decoder as its test oracle.
6. Document the format in the whitepaper with [V] tags pointing at the routine address and the test.

## Done when

The decoder handles 100 percent of the pinned files, the test is in `make test`, and the whitepaper describes the format.
