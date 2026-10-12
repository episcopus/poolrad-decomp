"""tools/re/enumerate_routines.py (`make map`) on the real image: forced starts survive, no known
routine is dropped or merged, proven extents are not split again (escalate-ovl11-20261012040038:
System.Randomize at 0AF8:1247 is a leaf with no prologue that the scan merged into
System_RandomStep; the false far-call start ovl11:0435 split StartGame)."""
import re
import sys
import tomllib
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/re"))
import enumerate_routines as er  # noqa: E402
import forced_starts  # noqa: E402

OVERLAYS = ROOT / "build/re/overlays.json"
SYMBOLS = ROOT / "re/symbols.toml"


def run(tmp_path, symbols_text: str) -> dict[str, dict]:
    if not OVERLAYS.exists():
        pytest.skip("no overlay manifest; run make overlays")
    out = tmp_path / "symbols.toml"
    out.write_text(symbols_text)
    assert er.main(["enumerate_routines.py", "--merge", "-o", str(out)]) == 0
    return {r["id"]: r for r in tomllib.loads(out.read_text())["routine"]}


def without_randomize(text: str) -> str:
    """The symbols file before dec-4's hand fix: no 0AF8:1247, RandomStep 69 bytes."""
    blocks = re.split(r"(?=\[\[routine\]\]\n)", text)
    blocks = [b for b in blocks if 'id = "0AF8:1247"' not in b]
    return "".join(b.replace("size = 56\n", "size = 69\n") if 'id = "0AF8:120F"' in b else b for b in blocks)


def test_randomize_is_a_forced_start():
    assert "0AF8:1247" in forced_starts.forced()


def test_map_keeps_randomize_its_own_routine(tmp_path):
    got = run(tmp_path, SYMBOLS.read_text())
    assert got["0AF8:1247"]["name"] == "System_Randomize"
    assert got["0AF8:1247"]["size"] == 13
    assert got["0AF8:120F"]["name"] == "System_RandomStep"
    assert got["0AF8:120F"]["size"] == 56


def test_map_restores_randomize_when_symbols_lack_it(tmp_path):
    got = run(tmp_path, without_randomize(SYMBOLS.read_text()))
    assert got["0AF8:1247"]["size"] == 13
    assert got["0AF8:120F"]["size"] == 56


def test_map_keeps_every_routine_and_field(tmp_path):
    before = {r["id"]: r for r in tomllib.loads(SYMBOLS.read_text())["routine"]}
    got = run(tmp_path, SYMBOLS.read_text())
    assert set(before) <= set(got)
    for rid, r in before.items():
        for key, val in r.items():
            if key != "size":
                assert got[rid].get(key) == val, (rid, key)
        if er.proven(r):
            assert got[rid]["size"] == r["size"], rid


def test_map_does_not_split_a_proven_routine(tmp_path):
    got = run(tmp_path, SYMBOLS.read_text())
    assert "ovl11:0435" not in got
    assert got["ovl11:002D"]["size"] == 1512


def test_probe_finds_randomize():
    """With the pinned compiler's probe build, the far call SINK.PAS makes to Randomize lands on
    0AF8:1247 (tools/re/tp_probe/SINK.PAS calls Randomize)."""
    probe = forced_starts.probe_starts()
    if probe is None:
        pytest.skip("no probe build; run make tp-probe")
    assert "0AF8:1247" in probe
