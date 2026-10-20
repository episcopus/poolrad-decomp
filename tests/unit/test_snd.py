"""The CoCo 3's sound driver (step 8.8, ports/coco3/src/snd): the generated driver is what its generator writes from the host driver, and the
driver with the backend and a model of the GIME timer plays the PC speaker half of the oracle's sound golden (probes/snd_ref.c, tools/snd_check.py)."""
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
COCO = ROOT / "ports/coco3"


def test_driver_is_what_the_generator_writes():
    r = subprocess.run([sys.executable, "-I", str(COCO / "tools/mksnd.py"), "--check"], capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr


@pytest.mark.skipif(not shutil.which("clang"), reason="needs clang for the host model")
def test_host_model_plays_the_golden_speaker_events():
    r = subprocess.run(["bash", str(COCO / "tools/snd_check.sh")], cwd=COCO, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
