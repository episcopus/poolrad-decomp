"""The oracle (playbook 25, SPEC 8.2): machine, DOS/BIOS services, EGA, key scripts, hooks, and the
three acceptance checks (boots to the title screen and matches DOSBox-X, deterministic runs,
character creation from a script).

Fast tests use tiny hand-assembled programs; the session tests boot the real game (about 15 s each)
and share their runs through module fixtures."""
import hashlib
import json
import struct
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/re"))
sys.path.insert(0, str(ROOT / "tools/oracle"))

from oracle.machine import Machine, Unimplemented, LOAD_SEG, FLAG_CF  # noqa: E402
from oracle.keys import KeyScript, char_key, NAMED, parse_clock  # noqa: E402
from oracle.ega import EGA  # noqa: E402
from oracle.vfs import VFS  # noqa: E402
import records  # noqa: E402

POOL = ROOT / "poolrad"
SESSIONS = ROOT / "tests/sessions"


# --------------------------------------------------------------------------- tiny programs
def make_exe(code: bytes, tmp: Path, name="T.EXE") -> Path:
    """A minimal MZ executable: code at CS:0000 (CS = load segment), stack 100h bytes above it."""
    hdr_paras = 2
    img = code + bytes(0x100)
    size = hdr_paras * 16 + len(img)
    hdr = struct.pack("<2s13H", b"MZ", size % 512, (size + 511) // 512, 0, hdr_paras, 0, 0xFFFF,
                      (len(code) + 15) // 16, 0x100, 0, 0, 0, 28, 0)
    path = tmp / name
    path.write_bytes(hdr.ljust(hdr_paras * 16, b"\0") + img)
    return path


def machine_for(code: bytes, tmp_path: Path, files: dict | None = None, **kw) -> Machine:
    game = tmp_path / "game"
    game.mkdir(exist_ok=True)
    for n, data in (files or {}).items():
        (game / n).write_bytes(data)
    return Machine(make_exe(code, tmp_path), game, **kw)


def test_loader_sets_registers_and_relocates_image(tmp_path):
    # a far pointer in the image with one relocation: seg 0 gets LOAD_SEG added
    code = b"\x90" * 8 + struct.pack("<HH", 0x0100, 0x0000)
    exe = make_exe(code, tmp_path)
    raw = bytearray(exe.read_bytes())
    raw[6:8] = struct.pack("<H", 1)                     # one relocation
    raw[24:26] = struct.pack("<H", 28)                  # table at 28
    raw[28:32] = struct.pack("<HH", 10, 0)              # offset 10, segment 0
    exe.write_bytes(bytes(raw))
    (tmp_path / "game").mkdir()
    m = Machine(exe, tmp_path / "game")
    assert (m.get("cs"), m.get("ip")) == (LOAD_SEG, 0)
    assert m.rw(LOAD_SEG, 10) == (0x0000 + LOAD_SEG) & 0xFFFF
    assert m.rw(LOAD_SEG, 8) == 0x0100                  # unrelocated word untouched


def test_guest_installed_vector_runs_as_original_code(tmp_path):
    # the overlay manager works this way: INT 3Fh goes to a handler the program installed
    code = bytes.fromhex("8CC8 8ED8 BA1400 B86025 CD21 CD60 88D8 B44C CD21".replace(" ", ""))
    code += bytes.fromhex("BB3412 CF")                  # handler at 0014: mov bx,1234h ; iret
    m = machine_for(code, tmp_path)
    assert m.run(10_000) == "exit"
    assert m.exit_code == 0x34 and m.get("bx") == 0x1234


def test_timer_interrupt_runs_at_virtual_18_2_hz(tmp_path):
    # handler counts ticks and sends EOI; 3 x 65535 loop iterations = 196,6xx instructions = 3 ticks
    body = bytes.fromhex("8CC8 8ED8 BA2100 B80825 CD21 BB0300 B9FFFF E2FE 4B 75F8 2EA03F00 B44C CD21".replace(" ", ""))
    handler = bytes.fromhex("2EFE063F00 B020 E620 CF".replace(" ", ""))
    pad = bytes(0x21 - len(body))
    assert len(body) <= 0x21
    code = body + pad + handler
    # fix the counter address: it is placed right after the handler
    counter = len(code)
    code = code.replace(b"\x3F\x00", struct.pack("<H", counter)) + b"\x00"
    m = machine_for(code, tmp_path)
    assert m.run(2_000_000) == "exit"
    assert m.exit_code == 3, "expected 3 timer ticks in ~196k instructions (period 54,925)"


def test_hlt_waits_for_the_next_timer_tick(tmp_path):
    # install an INT 08h handler that sets a flag, then `hlt` until it is set; exit code = flag
    handler, flag = 0x1E, 0x29
    code = (bytes.fromhex("8CC8 8ED8") + b"\xBA" + struct.pack("<H", handler) + bytes.fromhex("B80825 CD21 FB")
            + bytes.fromhex("F4") + b"\x2E\x80\x3E" + struct.pack("<H", flag) + b"\x00" + bytes.fromhex("74F7")
            + b"\x2E\xA0" + struct.pack("<H", flag) + bytes.fromhex("B44C CD21"))
    assert len(code) == handler
    code += b"\x2E\xC6\x06" + struct.pack("<H", flag) + b"\x01" + bytes.fromhex("B020 E620 CF")
    assert len(code) == flag
    code += b"\x00"
    m = machine_for(code, tmp_path)
    assert m.run(500_000) == "exit" and m.exit_code == 1
    assert m.insns < 200_000                              # skipped ahead to the tick instead of spinning


def test_hooked_routine_replaces_original_and_can_decline(tmp_path):
    code = bytes.fromhex("B80100 E80800 88C3 88D8 B44C CD21".replace(" ", ""))   # ax=1; call 0x10; al=bl... exit code=al
    code += bytes(0x10 - len(code))
    code += bytes.fromhex("050A00 C3")                   # routine at 0010: add ax,10 ; ret
    for hooked, expect in ((False, 11), (True, 100)):
        m = machine_for(code, tmp_path)
        if hooked:
            m.hook_routine(LOAD_SEG, 0x10, lambda mach: mach.set("ax", 100), far=False)
        assert m.run(10_000) == "exit"
        assert m.exit_code == expect
    m = machine_for(code, tmp_path)
    m.hook_routine(LOAD_SEG, 0x10, lambda mach: False, far=False)   # declines: original runs
    m.run(10_000)
    assert m.exit_code == 11


def test_unimplemented_dos_function_is_loud(tmp_path):
    code = bytes.fromhex("B4AA CD21 B44C CD21".replace(" ", ""))
    m = machine_for(code, tmp_path)
    with pytest.raises(Unimplemented, match="INT 21h AH=AAh"):
        m.run(10_000)


def test_file_read_comes_from_pinned_directory(tmp_path):
    # open "POOL.CFG" (DS:DX), read 4 bytes to DS:0100, exit with the first byte
    name = b"POOL.CFG\x00"
    code = bytes.fromhex("8CC8 8ED8 BA2800 B8003D CD21 89C3 BA0001 B90400 B43F CD21 A00001 B44C CD21".replace(" ", ""))
    code += bytes(0x28 - len(code)) + name
    m = machine_for(code, tmp_path, files={"POOL.CFG": b"E\r\nP\r\n"})
    assert m.run(10_000) == "exit"
    assert m.exit_code == ord("E")
    assert m.dos.reads == [("\\POOLRAD\\POOL.CFG", 0, 4)]


def test_vfs_writes_never_reach_the_pinned_directory(tmp_path):
    d = tmp_path / "in"
    d.mkdir()
    (d / "A.DAT").write_bytes(b"orig")
    v = VFS(d)
    f = v.open("a.dat", write=True)
    f.data[0:4] = b"XXXX"
    assert (d / "A.DAT").read_bytes() == b"orig"
    assert bytes(v.open("A.DAT", write=False).data) == b"XXXX"      # the run sees its own write
    n = v.open("new.txt", write=True, create=True)
    n.data.extend(b"hi")
    assert not (d / "NEW.TXT").exists() and v.exists("\\POOLRAD\\NEW.TXT")
    assert v.delete("A.DAT") and not v.exists("\\POOLRAD\\A.DAT") and (d / "A.DAT").exists()
    assert [x[0] for x in v.find("*.TXT")] == ["NEW.TXT"]


def _clock_program(spin_iterations: int) -> bytes:
    """spin, then INT 21h AH=2Ch and exit with DH (seconds): mov cx,N ; loop ; mov ah,2Ch ; int 21h ; ..."""
    return (b"\xB9" + struct.pack("<H", spin_iterations) + bytes.fromhex("E2FE B42C CD21 88F0 B44C CD21".replace(" ", "")))


def test_pinned_clock_makes_the_first_time_read_independent_of_timing(tmp_path):
    results = {}
    for spin in (10, 60000):                       # about 60,000 instructions apart
        m = machine_for(_clock_program(spin), tmp_path)
        m.clock_pin = parse_clock("07:08:09.10")
        assert m.run(500_000) == "exit"
        results[spin] = (m.exit_code, m.tod_log[0][1])
    assert results[10] == results[60000] == (9, ((7 * 60 + 8) * 60 + 9) * 100 + 10)
    # unpinned, the same two programs see different clocks: the spin is 0.06 virtual seconds
    seen = []
    for spin in (10, 60000):
        m = machine_for(_clock_program(spin), tmp_path)
        m.run(500_000)
        seen.append(m.tod_log[0][1])
    assert seen[0] != seen[1]


def test_clock_command_parses_and_rejects_bad_values():
    assert parse_clock("12:00:16.58") == 12 * 360000 + 16 * 100 + 58
    assert parse_clock("00:00:01") == 100
    assert KeyScript.parse("clock 01:02:03.04\nkey ENTER").clock == ((1 * 60 + 2) * 60 + 3) * 100 + 4
    with pytest.raises(ValueError):
        parse_clock("25:00:00")
    with pytest.raises(ValueError):
        parse_clock("noon")


# --------------------------------------------------------------------------- EGA
class _Dummy:
    pass


def _ega():
    return EGA(_Dummy())


def test_ega_write_mode_0_with_map_mask_and_set_reset():
    e = _ega()
    e.seq[2] = 0b0101                                 # planes 0 and 2 only
    e._write_byte(5, 0xAA)
    assert [p[5] for p in e.planes] == [0xAA, 0, 0xAA, 0]
    e.gc[1] = 0x0F                                    # enable set/reset on all planes
    e.gc[0] = 0b0011                                  # colour 3
    e.seq[2] = 0x0F
    e._write_byte(6, 0xFF)
    assert [p[6] for p in e.planes] == [0xFF, 0xFF, 0, 0]


def test_ega_latches_and_write_mode_1_copy():
    e = _ega()
    for i, p in enumerate(e.planes):
        p[10] = 0x11 * (i + 1)
    e._read_byte(10)                                  # load latches
    e.gc[5] = 1                                       # write mode 1: latches to memory
    e._write_byte(20, 0x00)
    assert [p[20] for p in e.planes] == [0x11, 0x22, 0x33, 0x44]


def test_ega_bit_mask_and_logical_ops():
    e = _ega()
    for p in e.planes:
        p[1] = 0xF0
    e._read_byte(1)
    e.gc[8] = 0x3C                                    # only bits 5..2 change
    e.gc[3] = 3 << 3                                  # XOR with latch
    e._write_byte(1, 0xFF)
    assert e.planes[0][1] == (0xF0 & ~0x3C) | ((0xFF ^ 0xF0) & 0x3C)


def test_ega_read_mode_1_color_compare():
    e = _ega()
    # pixel bit 7: colour 5 (planes 0 and 2); bit 6: colour 4
    e.planes[0][0], e.planes[1][0], e.planes[2][0], e.planes[3][0] = 0x80, 0x00, 0xC0, 0x00
    e.gc[5] = 0x08
    e.gc[2] = 5
    e.gc[7] = 0x0F
    assert e._read_byte(0) == 0x80


def test_ega_attribute_palette_to_rgb_and_png(tmp_path):
    from oracle.ega import ega_rgb
    assert ega_rgb(0x3F) == (255, 255, 255)
    assert ega_rgb(0x14) == (170, 85, 0)             # brown: the EGA's special-cased colour 6
    assert ega_rgb(0x00) == (0, 0, 0)


# --------------------------------------------------------------------------- key scripts
def test_key_script_parses_all_commands():
    s = KeyScript.parse("# c\nkey ENTER\ntext Hi\npress ESC\nwait 3\nshot a\ndigest d\nwheel\nquit\n")
    kinds = [k for k, _ in s.ops]
    assert kinds == ["key", "key", "key", "press", "wait", "shot", "digest", "wheel", "quit"]
    assert s.ops[0][1] == NAMED["ENTER"] and s.ops[1][1] == char_key("H")
    assert char_key("a") == (0x1E << 8) | ord("a") and char_key("A") == (0x1E << 8) | ord("A")


def test_unknown_script_command_is_rejected():
    with pytest.raises(ValueError):
        KeyScript.parse("frobnicate 3")


# --------------------------------------------------------------------------- the real game
@pytest.fixture(scope="module")
def runs():
    from oracle.run import run_session
    out = {}
    text = (SESSIONS / "boot-title.keys").read_text()
    out["boot"] = run_session(text, max_insns=150_000_000, quiet=True)
    text = (SESSIONS / "create-character.keys").read_text()
    out["create"] = run_session(text, max_insns=400_000_000, quiet=True)
    out["create2"] = run_session(text, max_insns=400_000_000, quiet=True)
    return out


def test_boots_to_the_title_screens_in_ega_mode(runs):
    s = runs["boot"]
    assert s["reason"] == "input-exhausted" and s["mode"] == 0x0D
    assert [c["label"] for c in s["checkpoints"]] == ["ssi-logo", "title", "credits"]
    assert len({c["screen"] for c in s["checkpoints"]}) == 3
    assert s["missing_opens"] == []
    assert "\\POOLRAD\\TITLE.DAX" in s["files_opened"]


def test_overlay_manager_loads_every_unit_from_game_ovr(runs):
    m = runs["boot"]["_machine"]
    from oracle.trace import overlay_stubs
    stubs = overlay_stubs()
    assert len(stubs) == 35
    ovr_reads = [(pos, n) for path, pos, n in m.dos.reads if path.endswith("GAME.OVR")]
    assert ovr_reads
    # every unit's code was read from its own file offset (stub +04h, dword) at least once
    for unit, stub in stubs.items():
        fofs = struct.unpack("<I", m.read(stub, 4, 4))[0]
        assert any(pos == fofs for pos, _ in ovr_reads), unit
    assert m.int_counts[0x3F] > 35                      # the game's own manager ran on INT 3Fh


def test_character_creation_completes_from_a_script(runs):
    s = runs["create"]
    assert s["reason"] == "input-exhausted"
    assert [c["label"] for c in s["checkpoints"]] == ["race-human", "sheet", "head-body-keep", "icon-editor", "main-menu"]
    m = s["_machine"]
    raw = bytes(m.vfs.layer["\\POOLRAD\\SAVE\\RAD.CHA"])
    rec = records.decode_char(raw)
    assert (rec["name"], rec["race"], rec["class"], rec["sex"], rec["age"]) == ("RAD", 7, 2, 0, 19)
    assert (rec["str"], rec["int"], rec["wis"], rec["dex"], rec["con"], rec["cha"]) == (15, 13, 11, 12, 16, 12)
    assert bytes(m.vfs.layer["\\POOLRAD\\SAVE\\CHARLIST.TXT"]) == b"RAD\r\n"
    assert (POOL / "SAVE" / "RAD.CHA").exists() is False   # the pinned directory was not touched


def test_same_script_twice_gives_identical_traces_and_digests(runs):
    a, b = runs["create"], runs["create2"]
    assert a["state_digest"] == b["state_digest"]
    assert a["canonical_digest"] == b["canonical_digest"]
    assert a["read_digests"] == b["read_digests"] and len(a["read_digests"]) == a["key_reads"]
    assert [(c["label"], c["time"], c["digest"]) for c in a["checkpoints"]] == \
           [(c["label"], c["time"], c["digest"]) for c in b["checkpoints"]]
    assert a["insns"] == b["insns"] and a["int_counts"] == b["int_counts"]
    assert a["random_digest"] == b["random_digest"] and a["random_calls"] == b["random_calls"] > 1000


def test_call_trace_names_routines_and_is_repeatable():
    from oracle.run import run_session
    runs_ = [run_session("", max_insns=3_000_000, trace="calls", quiet=True, digests=False)
             for _ in range(2)]
    t0, t1 = (r["_machine"].tracer for r in runs_)
    assert "0AF8:0000" in t0.entered                  # System init: the first routine the entry point calls
    assert t0.names["0AF8:0000"].startswith("res00") or "System" in t0.names["0AF8:0000"]
    assert any("call" in l for l in t0.lines) and any("ret" in l for l in t0.lines)
    assert t0.lines == t1.lines


def test_random_log_follows_the_tp6_generator_exactly(runs):
    """Every logged call is seed' = seed * 08088405h + 1 from the previous one, and Random(range) is
    hi16(seed') mod range, as the System code at 0AF8:120F..1244 and 11C0 does (whitepaper 5.13)."""
    log = runs["boot"]["_machine"].random_log
    assert len(log) > 1000, "the title animation consumes thousands of Random(4) calls"
    assert runs["boot"]["random_seed_writes"], "Randomize writes RandSeed once"
    for prev, cur in zip(log, log[1:]):
        assert cur.seed == (prev.seed * 0x08088405 + 1) & 0xFFFFFFFF
        if cur.kind == "range":
            assert cur.result == ((cur.seed >> 16) % cur.range if cur.range else 0)
    # Randomize: RandSeed := DX:CX of INT 21h AH=2Ch, here the pinned 12:00:16.58 (CH=12, CL=0, DH=16, DL=58)
    writes = runs["boot"]["random_seed_writes"]
    assert [w[2] for w in writes] == [0x0C00, 0x103A]
    assert writes[0][1] == "0AF8:124B" or writes[0][1].startswith("0AF8:12")


def test_random_log_matches_what_random_actually_returns():
    from oracle.run import build_machine
    from oracle.machine import Stop
    m = build_machine(KeyScript.parse("clock 12:00:16.58\nwait 3000\n"))
    returned = []
    m.add_breakpoint(0x0AF8 + LOAD_SEG, 0x11D3, lambda mach: returned.append(mach.get("ax")))   # retf 2 of Random(range)
    m.run(37_000_000, on_chunk=lambda mach: (_ for _ in ()).throw(Stop("enough")) if len(returned) >= 300 else None)
    logged = [c.result for c in m.random_log if c.kind == "range"]
    assert len(returned) >= 300
    assert logged[:len(returned)] == returned[:len(logged)]


def test_pinned_clock_gives_the_same_random_sequence_whatever_the_timing(runs):
    """The control for the whole feature: change the oracle's clock rate (which moves the instruction
    count of every event) and the pinned seed and the first decisions stay identical; unpinned they
    would not (the clock read at Randomize would differ)."""
    from oracle.run import build_machine
    from oracle.machine import Stop
    ref = runs["boot"]["_machine"].random_log[:200]
    m = build_machine(KeyScript.parse("clock 12:00:16.58\nwait 3000\n"), insn_per_sec=1_250_000)
    m.run(60_000_000, on_chunk=lambda mach: (_ for _ in ()).throw(Stop("enough")) if len(mach.random_log) >= 200 else None)
    got = m.random_log[:200]
    assert len(got) == 200
    assert [(c.kind, c.caller, c.range, c.seed, c.result) for c in got] == \
           [(c.kind, c.caller, c.range, c.seed, c.result) for c in ref]
    assert got[0].time != ref[0].time               # it really ran on a different clock


def test_unpinned_seed_follows_the_instruction_clock():
    from oracle.run import build_machine
    from oracle.machine import Stop
    seeds = []
    for ips in (1_000_000, 1_250_000):
        m = build_machine(KeyScript([]), insn_per_sec=ips)
        m.run(25_000_000, on_chunk=lambda mach: (_ for _ in ()).throw(Stop("seeded")) if mach.seed_writes else None)
        seeds.append([w.value for w in m.seed_writes][:2])
    assert seeds[0] != seeds[1] and seeds[0][0] == 0x0C00     # same hour:minute, different seconds


def test_hybrid_hook_python_move_matches_original(runs):
    """Replace System.Move (0AF8:1685) by a Python version (video destinations are declined, so the
    original code handles them) and compare the state at the same logical point: just before the 120th
    call, after four timer ticks. A hooked run executes fewer instructions, so the stop point is a
    call count, not an instruction budget.

    Known limit (whitepaper appendix C): later than this, timer ticks land at slightly different
    program points in a hooked run (the clock counts instructions and a replacement executes none),
    and tick-derived bytes in DGROUP differ. `hook_routine(cost=...)` narrows but does not remove
    that; SPEC 8.4 needs either masks in re/state.toml or a precise-time mode before L3 on hybrids."""
    from oracle.run import build_machine
    from oracle.machine import Stop
    from oracle.state import canonical_digest
    NTH = 120
    entry = (0x0AF8 + LOAD_SEG, 0x1685)

    def stop_at_nth(mach, counter):
        counter[0] += 1
        if counter[0] == NTH:
            raise Stop("nth-move")

    ref_n = [0]
    ref = build_machine(KeyScript([]))
    ref.add_breakpoint(*entry, lambda mach: stop_at_nth(mach, ref_n))
    assert ref.run(30_000_000) == "nth-move"

    m = build_machine(KeyScript([]))
    n = [0]
    handled = []

    def py_move(mach):
        stop_at_nth(mach, n)
        ss, sp = mach.get("ss"), mach.get("sp")
        count = mach.rw(ss, sp + 4)
        dst_off, dst_seg = mach.rw(ss, sp + 6), mach.rw(ss, sp + 8)
        src_off, src_seg = mach.rw(ss, sp + 10), mach.rw(ss, sp + 12)
        if mach.linear(dst_seg, dst_off) + count >= 0xA0000:
            return False                                # video memory: leave it to the original
        mach.write(dst_seg, dst_off, mach.read(src_seg, src_off, count))
        handled.append(count)

    m.hook_routine(*entry, py_move, ret_bytes=10)
    assert m.run(30_000_000) == "nth-move"
    assert len(handled) > 50, "the Python Move should have handled most calls"
    assert canonical_digest(m) == canonical_digest(ref)
    assert m.state_digest(registers=False, include_video=False) == ref.state_digest(registers=False, include_video=False)


def test_screens_equal_dosbox_x_frames_pixel_for_pixel():
    import dosbox_ref  # noqa: E402
    if not dosbox_ref.available():
        pytest.skip("dosbox-x or ffmpeg not installed")
    assert dosbox_ref.main(["--seconds", "30"]) == 0
