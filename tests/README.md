# tests/

| Directory | Contents | Phase |
|---|---|---|
| `unit/` | C and Python unit tests (runtime helpers, data codecs over all pinned files) | P2 to P3 |
| `fuzz/` | per-routine differential test specs (input generators, recorded cases) | P3 |
| `sessions/` | input scripts (`*.keys`) and `golden/<name>/` digests and screenshots made from the original in the oracle | P2 |

Goldens hold digests and our own screenshots; never copies of game files.
