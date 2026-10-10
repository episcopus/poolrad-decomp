"""SAVE/ directory: SAVGAMA + CHRDAT records."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/re"))
import save  # noqa: E402

POOL = ROOT / "poolrad"


def test_save_verify_ok():
    assert save.main(["save", "verify", str(POOL / "SAVE")]) == 0


def test_savgama_size():
    assert (POOL / "SAVE/SAVGAMA.DAT").stat().st_size == save.SAVGAMA_SIZE
