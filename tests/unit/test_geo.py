"""GEO map blocks: every pinned GEO*.DAX (playbook 20, whitepaper 4.2)."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/re"))
import dax  # noqa: E402
import geo  # noqa: E402

POOL = ROOT / "poolrad"


def test_all_geo_blocks_decode():
    files = sorted(POOL.glob("GEO*.DAX"))
    assert len(files) == 8
    n = 0
    for path in files:
        for b in dax.read_dax(str(path)):
            n += 1
            m = geo.decode_geo(dax.unrle(b["data"]))
            assert m["width"] == 16 and m["height"] == 16
            assert m["payload_bytes"] == 1024
            assert len(m["cells"]) == 16 and all(len(r) == 16 for r in m["cells"])
    assert n == 29


def test_geo_cli_verify_ok():
    assert geo.main(["geo", "verify", str(POOL)]) == 0


def test_load3dmap_size_constant():
    """ovl29:10C7 compares the loaded block size to 0x402."""
    for path in POOL.glob("GEO*.DAX"):
        for b in dax.read_dax(str(path)):
            assert b["raw"] == geo.GEO_SIZE
