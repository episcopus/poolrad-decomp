"""WALLDEF wallsets: every pinned WALLDEF*.DAX."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/re"))
import dax  # noqa: E402
import walldef  # noqa: E402

POOL = ROOT / "poolrad"


def test_all_walldef_blocks():
    n = 0
    for path in sorted(POOL.glob("WALLDEF*.DAX")):
        for b in dax.read_dax(str(path)):
            n += 1
            info = walldef.decode_walldef(dax.unrle(b["data"]))
            assert info["wallset_count"] >= 1
            assert len(info["wallsets"][0]["walls"]) == walldef.WALLS_PER_SET
    assert n == 38


def test_walldef_cli_verify_ok():
    assert walldef.main(["walldef", "verify", str(POOL)]) == 0
