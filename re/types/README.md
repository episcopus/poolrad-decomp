# Record and enum types

Notes on the game's records (characters, items, monsters, map cells, ...) as evidence accumulates: one Markdown or TOML file per record family with every field's offset, size, Pascal type and evidence.

The Pascal declarations themselves live in the unit sources in `src/` (record types in the interface of the unit that owns them). `make match` checks them indirectly: every field access compiles to a displacement that must equal the original's. `re/state.toml` `heap_root` entries will name records here once the heap is described by type rather than byte for byte.
