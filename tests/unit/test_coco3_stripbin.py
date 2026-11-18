"""The CoCo 3 game's POOL.BIN (ports/coco3/tools/stripbin.py): the engine bytes that would land on a BASIC program's text are staged, so the game starts from a
BASIC program (an AUTOEXEC.BAS) as well as from the prompt. The engine's image must be the same once the stub has run."""
import importlib.util
import struct
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ports/coco3/tools"))
spec = importlib.util.spec_from_file_location("coco3_stripbin", ROOT / "ports/coco3/tools/stripbin.py")
sb = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sb)


def rec(addr, data):
    return bytes([0]) + struct.pack(">HH", len(data), addr) + bytes(data)


def decb(*records, entry=0x2000):
    return b"".join(records) + bytes([0xFF, 0, 0, entry >> 8, entry & 255])


def engine(n=0x4F00):
    """a fake engine: n bytes at $2000 that are all different from the BASIC text sentinel, one record, plus a shared record in Disk BASIC's buffers"""
    return decb(rec(0x2000, bytes((i * 7 + 1) & 255 or 1 for i in range(n))), rec(0x1D80, bytes(range(1, 200))), rec(0x0700, bytes([5] * 16)))


def load(path, text_sentinel=0xA5):
    """LOADM: apply the records over a memory that holds BASIC's program text where it is, return (memory, the EXEC address, the sentinel's range)"""
    d, mem, i = Path(path).read_bytes(), bytearray(65536), 0
    mem[sb.STAGE_LO:sb.STAGE_HI] = bytes([text_sentinel]) * (sb.STAGE_HI - sb.STAGE_LO)
    touched = set()
    while True:
        t, ln, ad = d[i], (d[i + 1] << 8) | d[i + 2], (d[i + 3] << 8) | d[i + 4]
        i += 5
        if t == 0xFF:
            return mem, ad, touched
        mem[ad:ad + ln] = d[i:i + ln]
        touched |= set(range(ad, ad + ln))
        i += ln


def run_stub(mem, pc):
    """the six instructions of the stub, as a 6809 would run them (an unknown opcode fails the test); returns where it jumps to"""
    x = y = 0
    while True:
        op = mem[pc]
        if op == 0x8E:
            x, pc = (mem[pc + 1] << 8) | mem[pc + 2], pc + 3
        elif op == 0x10 and mem[pc + 1] == 0x8E:
            y, pc = (mem[pc + 2] << 8) | mem[pc + 3], pc + 4
        elif op == 0xEC and mem[pc + 1] == 0x81:
            d, x, pc = (mem[x], mem[x + 1]), x + 2, pc + 2
        elif op == 0xED and mem[pc + 1] == 0xA1:
            mem[y], mem[y + 1], y, pc = d[0], d[1], y + 2, pc + 2
        elif op == 0x8C:
            z, pc = (mem[pc + 1] << 8) | mem[pc + 2], pc + 3
            eq = x == z
        elif op == 0x26:
            off = mem[pc + 1] - 256 if mem[pc + 1] > 127 else mem[pc + 1]
            pc = pc + 2 + (off if not eq else 0)
        elif op == 0x7E:
            return (mem[pc + 1] << 8) | mem[pc + 2]
        else:
            pytest.fail("the stub holds an instruction the test does not know: %02X at %04X" % (op, pc))


@pytest.fixture
def built(tmp_path):
    plain, staged = tmp_path / "plain.bin", tmp_path / "game.bin"
    plain.write_bytes(engine())
    staged.write_bytes(engine())
    sb.strip_low_records(plain)                      # the probes' and tests' binaries: no staging
    sb.strip_low_records(staged, splash=True)        # the game's
    return plain, staged


def test_the_window_is_not_loaded_where_basic_keeps_its_program(built):
    _, staged = built
    mem, entry, touched = load(staged)
    assert not touched & set(range(sb.STAGE_LO, sb.STAGE_HI))                    # LOADM writes nothing in the window
    assert mem[sb.STAGE_LO:sb.STAGE_HI] == bytes([0xA5]) * (sb.STAGE_HI - sb.STAGE_LO)
    assert entry == sb.STAGE_AT + (sb.STAGE_HI - sb.STAGE_LO)                      # EXEC runs the stub


def test_the_stub_puts_the_engine_back_and_enters_it(built):
    plain, staged = built
    ref, ref_entry, _ = load(plain)
    mem, entry, _ = load(staged)
    assert run_stub(mem, entry) == ref_entry == 0x2000
    assert mem[0x1000:0x7000] == ref[0x1000:0x7000]
    # the shared data's image ($7C90, copied by boot.asm) and the splash's records are the same as without the staging
    assert mem[0x7C90:0x7E00] == ref[0x7C90:0x7E00]


def test_the_staged_bytes_and_the_stub_stay_clear_of_the_engine(built):
    _, staged = built
    _, _, touched = load(staged)
    plain_touched = load(built[0])[2]
    in_area = {a for a in touched if sb.STAGE_AT <= a < sb.STAGE_AT + (sb.STAGE_HI - sb.STAGE_LO) + 19}
    assert not in_area & plain_touched
    assert len(in_area) == (sb.STAGE_HI - sb.STAGE_LO) + 19


def test_a_record_in_the_staging_area_is_refused(tmp_path):
    p = tmp_path / "bad.bin"
    p.write_bytes(decb(rec(0x2000, bytes([1]) * 0x5100), rec(0x0700, bytes([5] * 16))))        # runs to $7100
    with pytest.raises(SystemExit, match="staging area"):
        sb.strip_low_records(p, splash=True)


def test_an_engine_with_a_hole_in_the_window_is_refused(tmp_path):
    p = tmp_path / "hole.bin"
    p.write_bytes(decb(rec(0x2000, bytes([1]) * 0x400), rec(0x2800, bytes([1]) * 0x100), rec(0x0700, bytes([5] * 16))))
    with pytest.raises(SystemExit, match="staged whole"):
        sb.strip_low_records(p, splash=True)
