# 25 The oracle (Verifier)

**Inputs:** SPEC section 8.2; Exhume's fuzzing and replay design as reference (`docs/dos-decomp-projects/UW1Decomp/docs/BUILDING.md`).

## Build order

1. `machine.py`: Unicorn x86 16-bit, 1 MB conventional memory plus video windows, IVT, MZ loader (PSP at a fixed segment, relocations), single-step and block hooks.
2. `dos.py`, `bios.py`: the interrupt services the game actually calls (log every unimplemented call loudly, never return silently).
3. Overlay manager: nothing to write; the game's own manager runs on INT 3Fh. Verify by watching overlays load from `GAME.OVR`.
4. Timer: virtual time from the instruction count; deliver IRQ0 at 18.2 Hz (or the reprogrammed PIT rate) when interrupts are enabled.
5. `ega.py`: planes, latches, map mask, bit mask, write modes 0 to 2, read modes, palette registers; screenshot to PNG.
6. Input: a script player (`tests/sessions/*.keys`) feeding INT 16h and the keyboard buffer.
7. Tracing: call and return events with arguments (using `re/symbols.toml` signatures), memory watch points, state snapshots per `re/state.toml`.
8. Replacement hook: replace a routine by Python (`oracle.routines.replace`), for experiments and, in Phase 7, for the C translation (branch `track-c-hybrid` has the hybrid library).

## Acceptance checks

- Boots to the title screen; the screenshot matches DOSBox-X's (same mode, same pixels).
- The same key script run twice gives identical traces and state digests.
- Character creation completes from a script.

## Done when

The checks above pass in `make test` and the oracle's capabilities are listed in the whitepaper appendix.
