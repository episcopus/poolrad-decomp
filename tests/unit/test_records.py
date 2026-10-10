"""Character / item / affect records: MON* and SAVE (playbook 20)."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/re"))
import dax  # noqa: E402
import records  # noqa: E402

POOL = ROOT / "poolrad"


def test_records_cli_verify_ok():
    assert records.main(["records", "verify", str(POOL)]) == 0


def test_all_mon_cha_are_285():
    n = 0
    for path in sorted(POOL.glob("MON*CHA.DAX")):
        for b in dax.read_dax(str(path)):
            n += 1
            raw = dax.unrle(b["data"])
            assert len(raw) == records.CHAR_SIZE
            rec = records.decode_char(raw)
            assert rec["name"]
            assert records.encode_char(rec) == raw
    assert n == 172


def test_save_char_matches_layout():
    raw = (POOL / "SAVE/CHRDATA1.SAV").read_bytes()
    rec = records.decode_char(raw)
    assert "THRENDER" in rec["name"].upper() or len(rec["name"]) > 0
    assert records.encode_char(rec) == raw


def test_item_blob_roundtrip():
    raw = (POOL / "SAVE/CHRDATA1.ITM").read_bytes()
    items = records.decode_item_blob(raw)
    assert items
    assert records.encode_item_blob(items) == raw
