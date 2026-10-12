"""re/symbols.toml keeps its shape: a merge or a hand edit must not drop a routine's fields.

Ten ovl31 entries once lost c_name, level and justification in a merge, so `make match WRITE=1` could not
record their L2 and the status undercounted the unit; nothing failed. Every routine entry carries the
fields below (`review` is optional: only reviewed routines have it)."""
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FIELDS = ("id", "unit", "addr", "size", "name", "c_name", "signature", "level", "justification", "notes",
          "evidence")


def test_every_routine_entry_has_every_field():
    routines = tomllib.loads((ROOT / "re/symbols.toml").read_text())["routine"]
    broken = ["%s: %s" % (r.get("id", "?"), ", ".join(f for f in FIELDS if f not in r))
              for r in routines if any(f not in r for f in FIELDS)]
    assert not broken, "routine entries missing fields (restore them; never drop fields in a merge):\n" + \
        "\n".join(broken)


def test_routine_ids_are_unique():
    ids = [r["id"] for r in tomllib.loads((ROOT / "re/symbols.toml").read_text())["routine"]]
    assert len(ids) == len(set(ids))
