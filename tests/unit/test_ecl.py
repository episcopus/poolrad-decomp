"""ECL script blocks: every pinned ECL*.DAX (playbook 20, whitepaper 4.2)."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/re"))
import dax  # noqa: E402
import ecl  # noqa: E402

POOL = ROOT / "poolrad"


def test_all_ecl_blocks_decode():
    files = sorted(POOL.glob("ECL*.DAX"))
    assert len(files) == 8
    n = 0
    for path in files:
        for b in dax.read_dax(str(path)):
            n += 1
            info = ecl.decode_ecl(dax.unrle(b["data"]))
            assert info["header_u16"] == ecl.ECL_HDR_WORD
            assert 0 < info["payload_bytes"] <= ecl.ECL_BUF_MAX
            assert set(info["entries"]) == {
                "vm_run_1",
                "search_location",
                "pre_camp_check",
                "camp_interrupted",
                "initial_entry",
            }
    assert n == 29


def test_ecl_cli_verify_ok():
    assert ecl.main(["ecl", "verify", str(POOL)]) == 0


def test_ecl_loader_buffer_cap():
    """ovl07:0341 GetMem(0x1E00); copy size-2 into that buffer."""
    for path in POOL.glob("ECL*.DAX"):
        for b in dax.read_dax(str(path)):
            assert 2 <= b["raw"] <= ecl.ECL_BUF_MAX + 2
