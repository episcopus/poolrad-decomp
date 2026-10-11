# src: the Pascal source

Turbo Pascal 6.0 (June 1991), compiled by the pinned compiler (`make tp-pin`) and proven routine by routine against the original's machine code with `make match` (SPEC sections 7 and 8.3, playbook 30).

| File | Holds |
|---|---|
| `RESNN.PAS`, `OVLNN.PAS` | one original unit each, named after its id in `re/units.toml`; routines in address order, all declared in the interface |
| `POOLVARS.PAS` | globals whose owning unit is not known yet (`dsXXXX` = DS offset, or a name from `re/dseg.toml`) |

Conventions:

- Directives: `{$A-,F+,S-,R-,G-,I-}`, overlay units `{$A-,O+,F+,S-,R-,G-,I-}`, res05 `I+`.
- A routine not decompiled yet but called by one that is: `{@stub}` at the start of its header line, the right signature, an empty body.
- Top-level routine headers start in column 1; nested routines are indented.
- No raw machine code. Original quirks are kept and marked `QUIRK:`.

The runtime units (System, Crt, Dos, Overlay) are the compiler's own and are never here.
