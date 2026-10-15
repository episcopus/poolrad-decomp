"""The oracle running the rebuilt program (tools/oracle/layout.py, `golden.py --rebuilt`, playbook 50).

Fast tests: nothing here boots the game. The layout of a rebuild is read from the link map `make rebuild`
leaves in build/rebuild; that test skips when there is none."""
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

from oracle import golden, layout  # noqa: E402
from oracle.vfs import VFS  # noqa: E402


def test_original_layout_is_what_the_hooks_were_written_against():
    lay = layout.original()
    assert lay.is_original and lay.overlay_file is None
    assert (lay.dgroup_para, lay.system_para) == (0x0C7C, 0x0AF8)
    assert (lay.randseed, lay.heap_org, lay.heap_ptr, lay.wheel_table) == (0x4428, 0x4400, 0x4404, 0)
    assert lay.stubs is None and lay.resident_ranges is None      # read from re/units.toml


def test_use_swaps_the_layout_and_returns_the_previous_one():
    mine = layout.Layout(name="probe", dgroup_para=0x0B19)
    prev = layout.use(mine)
    try:
        assert layout.current() is mine
        from oracle.state import dgroup_seg
        from oracle.machine import LOAD_SEG
        assert dgroup_seg() == LOAD_SEG + 0x0B19
    finally:
        layout.use(prev)
    assert layout.current() is prev and layout.current().is_original


def test_trace_locate_prints_the_original_form_for_a_rebuild():
    """A rebuilt unit sits at another paragraph; the caller still prints as the original's `SSSS:OOOO`."""
    from oracle import trace
    from oracle.machine import LOAD_SEG
    mine = layout.Layout(name="probe", stubs={}, resident_ranges=[(0x500 * 16, 0x500 * 16 + 0x100, 0x0464, "res14",
                                                                    0x500 * 16)])
    prev = layout.use(mine)
    try:
        class M:
            def rw(self, seg, off):
                return 0
        got = trace.locate(M(), (LOAD_SEG + 0x500) * 16 + 0x42)
    finally:
        layout.use(prev)
    assert got == "0464:0042"


def test_alias_serves_the_rebuilt_overlay_as_game_ovr(tmp_path):
    game = tmp_path / "game"
    game.mkdir()
    (game / "GAME.OVR").write_bytes(b"original")
    built = tmp_path / "POOL.OVR"
    built.write_bytes(b"rebuilt")
    v = VFS(game)
    f = v.open("C:\\POOLRAD\\GAME.OVR", write=False)
    assert bytes(f.data) == b"original"
    v.alias("GAME.OVR", built)
    f = v.open("C:\\POOLRAD\\game.ovr", write=False)
    assert bytes(f.data) == b"rebuilt"
    assert built.read_bytes() == b"rebuilt"                        # reads never touch the host file


def test_behaviour_difference_ignores_where_the_data_lives():
    class Rec:
        def __init__(self, runs, final):
            self.streams = type("S", (), {"runs": runs})()
            self.final = final

    base = {k: 1 for k in golden.BEHAVIOUR}
    base["checkpoints"] = [{"label": "a", "time": 5, "screen": "x", "random_calls": 3, "canonical": "p"}]
    other = dict(base)
    other["checkpoints"] = [{"label": "a", "time": 5, "screen": "x", "random_calls": 3, "canonical": "q"}]
    r = Rec({"key": [[1, 0, 2]]}, {k: 0 for k in golden.RECORDING_FINAL})
    assert golden.behaviour_differences(base, other, r, r) == []     # state digests are not behaviour
    fresh = Rec({"key": [((1, 2), 0, 2)]}, {k: 0 for k in golden.RECORDING_FINAL})   # a run holds tuples,
    disk = Rec({"key": [[[1, 2], 0, 2]]}, {k: 0 for k in golden.RECORDING_FINAL})    # a recording lists
    assert golden.behaviour_differences(base, base, fresh, disk) == []
    other["checkpoints"] = [dict(other["checkpoints"][0], screen="y")]
    why = golden.behaviour_differences(base, other, r, r)
    assert len(why) == 1 and "screen" in why[0]
    r2 = Rec({"key": [[2, 0, 2]]}, {k: 0 for k in golden.RECORDING_FINAL})
    assert any("outside world" in w for w in golden.behaviour_differences(base, base, r, r2))


def test_rebuilt_layout_comes_from_the_link_map():
    if not (layout.REBUILD_DIR / "POOL.MAP").exists() and not (layout.REBUILD_DIR / "pool.map").exists():
        pytest.skip("no rebuild in build/rebuild (make rebuild)")
    lay = layout.rebuilt()
    assert lay.name == "rebuilt" and lay.exe.name.upper() == "POOL.EXE"
    assert lay.overlay_file.name.upper() == "POOL.OVR"
    assert len(lay.stubs) == 35 and lay.stubs["ovl00"] == 0x0016
    assert lay.randseed != 0x4428 or lay.dgroup_para == 0x0C7C       # the data layout is its own until identical
