"""DAX container and RLE: every pinned .DAX file (playbook 20, whitepaper 4.1)."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/re"))
import dax  # noqa: E402

POOL = ROOT / "poolrad"


def test_all_dax_files_verify():
    files = sorted(POOL.glob("*.DAX"))
    assert len(files) == 113
    blocks = 0
    for path in files:
        for b in dax.read_dax(str(path)):
            blocks += 1
            assert len(dax.unrle(b["data"])) == b["raw"], (path.name, b["id"])
    assert blocks == 1245


def test_dax_cli_verify_ok():
    assert dax.main(["dax", "verify", str(POOL)]) == 0
