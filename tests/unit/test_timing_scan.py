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


def test_crt_init_spins_on_the_bios_tick_counter_through_a_register(result):
    raw, cls = result
    assert raw["0A40:002E"]["loop_feats"] == ["bios-tick-0040"]       # mov di,6Ch ; cmp al,es:[di] ; je
    assert cls["0A40:002E"]["class"] == "waits" and cls["0A40:002E"]["families"] == ["time"]
    assert sum(1 for v in raw.values() if any(f.startswith("bios-tick") for f in v["feats"])) == 1


def test_int21_ah06_is_output_not_a_key_poll(result):
    raw, _ = result
    assert raw["0AF8:01E7"]["feats"] == []


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


def test_a_register_reloaded_without_an_immediate_is_not_taken_for_the_tick_counter(monkeypatch):
    """2026-10-14: FormatItemLine (00BA:0442) does `mov di,0x43D`, later `les di,[bp+6]`, then reads
    `es:[di+0x31]`; the scanner still added 0x31 to 0x43D and reported the BIOS tick counter (0x46E)."""
    import timing_scan
    sc = timing_scan.Scanner()
    stale = bytes.fromhex("BF3D04" "C47E06" "26807D31B1")        # mov di,0x43D; les di,[bp+6]; cmp es:[di+0x31],0B1h
    fresh = bytes.fromhex("BF3D04" "26807D31B1")                 # mov di,0x43D; cmp es:[di+0x31],0B1h
    for code, expect in ((stale, False), (fresh, True)):
        monkeypatch.setattr(timing_scan, "routine_bytes", lambda r, image, ovl, code=code: (code, 0, "res12"))
        feats = sc.scan({"id": "x"}, None, None)["feats"]
        assert ("bios-tick-0000" in feats) == expect, (code.hex(), feats)
