"""Static timing scan (tools/re/timing_scan.py): which routines wait on time or input.

Fast: Capstone over the pinned bytes. Needs the extracted overlays (`make overlays`)."""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/re"))

if not list((ROOT / "build/re/overlays").glob("ovl*.bin")):
    pytest.skip("run `make overlays` first", allow_module_level=True)

import timing_scan as ts  # noqa: E402


@pytest.fixture(scope="module")
def result():
    sc = ts.Scanner()
    image, ovl = ts.load_bytes()
    raw = {r["id"]: sc.scan(r, image, ovl) for r in sc.routines}
    return raw, ts.classify(raw)


def test_crt_keyboard_routines_are_found_by_their_int16_calls(result):
    raw, _ = result
    assert "kbd-int16" in raw["0A40:02FD"]["feats"]          # Crt KeyPressed
    assert "kbd-int16" in raw["0A40:030F"]["feats"]          # Crt ReadKey


def test_a_loop_around_a_key_read_is_a_wait(result):
    _, cls = result
    r = cls["0A40:0143"]
    assert r["class"] == "waits" and r["families"] == ["input"] and r["loop_feats"] == ["kbd-int16"]


def test_far_calls_are_followed_into_resident_units_and_through_overlay_stubs(result):
    raw, cls = result
    assert "0A40:02FD" in raw["0899:0059"]["calls"]          # resident far call (capstone lcall)
    assert cls["0899:0059"]["class"] == "waits" and cls["0899:0059"]["waits_via_calls"]
    assert any(c.startswith("ovl") for rid, v in raw.items() if rid.startswith("0") for c in v["calls"]), \
        "a resident routine calls an overlay entry through its stub"
    assert cls["ovl25:03BD"]["class"] == "waits" and "input" in cls["ovl25:03BD"]["families"]   # the menu loop


def test_plain_computation_is_not_flagged(result):
    _, cls = result
    assert cls["0AF8:1685"]["class"] == "none"               # System.Move
    counts = {k: sum(1 for r in cls.values() if r["class"] == k) for k in ("waits", "uses", "none")}
    assert counts["none"] > counts["waits"] + counts["uses"], "most routines are plain computation"
