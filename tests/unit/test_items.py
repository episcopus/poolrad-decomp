"""ITEMS type table."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/re"))
import items  # noqa: E402

POOL = ROOT / "poolrad"


def test_items_roundtrip():
    raw = (POOL / "ITEMS").read_bytes()
    info = items.decode_items(raw)
    assert info["count"] == 128
    assert items.encode_items(info) == raw


def test_items_cli_verify_ok():
    assert items.main(["items", "verify", str(POOL)]) == 0
