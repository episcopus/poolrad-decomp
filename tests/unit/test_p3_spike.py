"""P3 spike: the C lift loads and behaves (fast, no emulator boot).

Covers what `make test` must prove in seconds; the emulator-backed proofs
(isolated differential fuzz, full-session hybrid replays) live in
`make fuzz` and `make sessions`:

  * the DGROUP mirror is up to date and RandSeed sits at DS:4428;
  * the hybrid library exposes the three spike routines and the C Move,
    FillChar and Random agree with the TP 6.0 semantics on fixed vectors
    (the randomised differential proof against the original bytes is
    tools/fuzz/fuzz.py);
  * the portability lint passes.
"""
import ctypes
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import pytest  # noqa: E402

LIB = None


def lib():
    global LIB
    if LIB is None:
        for name in ("libpoolrad_hybrid.dylib", "libpoolrad_hybrid.so"):
            p = ROOT / "build/host" / name
            if p.exists():
                LIB = ctypes.CDLL(str(p))
                break
        assert LIB is not None, "hybrid library not built (run `make hybrid`)"
        LIB.pool_hybrid_bind.argtypes = [ctypes.c_char_p, ctypes.c_uint32]
        LIB.pool_hybrid_bind.restype = None
        LIB.pool_g_ptr.argtypes = []
        LIB.pool_g_ptr.restype = ctypes.c_void_p
        LIB.hybrid_System_Move.argtypes = [ctypes.c_uint32, ctypes.c_uint32, ctypes.c_uint16]
        LIB.hybrid_System_Move.restype = None
        LIB.hybrid_System_FillChar.argtypes = [ctypes.c_uint32, ctypes.c_uint16, ctypes.c_uint8]
        LIB.hybrid_System_FillChar.restype = None
        LIB.hybrid_System_Random.argtypes = [ctypes.c_uint16]
        LIB.hybrid_System_Random.restype = ctypes.c_uint16
    return LIB


@pytest.fixture(scope="module")
def mem():
    l = lib()
    mirror = ctypes.create_string_buffer(0x100000)
    l.pool_hybrid_bind(mirror, 0x100000)
    return l, mirror


def seed_of(lib):
    return ctypes.c_uint32.from_address(lib.pool_g_ptr() + 0x4428)


def test_dseg_mirror_up_to_date():
    import subprocess
    py = str(ROOT / ".venv/bin/python")
    r = subprocess.run([py, "tools/re/gen_dseg.py", "--check"], cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stderr


def test_randseed_offset():
    text = (ROOT / "src/include/gen/dseg.h").read_text()
    assert "RandSeed) == 0x4428" in text


def test_move_forward(mem):
    lib, mirror = mem
    mirror[0x1000:0x1010] = bytes(range(16))
    lib.hybrid_System_Move(0x1000, 0x2000, 16)
    assert bytes(mirror[0x2000:0x2010]) == bytes(range(16))


def test_move_overlap_uses_offsets_only(mem):
    # dst offset below src offset: forward, destructive like rep movsb.
    lib, mirror = mem
    mirror[0x3000:0x3020] = bytes(range(32))
    lib.hybrid_System_Move(0x3000, 0x2FF0, 32)
    assert bytes(mirror[0x2FF0:0x3010]) == bytes(range(32))


def test_move_zero_count(mem):
    lib, mirror = mem
    mirror[0x4000:0x4004] = b"\xAA\xBB\xCC\xDD"
    lib.hybrid_System_Move(0x4000, 0x5000, 0)
    assert bytes(mirror[0x5000:0x5004]) == b"\x00\x00\x00\x00"


def test_fillchar(mem):
    lib, mirror = mem
    lib.hybrid_System_FillChar(0x6000, 64, 0x41)
    assert bytes(mirror[0x6000:0x6040]) == bytes(0x41 for _ in range(64))
    lib.hybrid_System_FillChar(0x6000, 0, 0xFF)
    assert bytes(mirror[0x6000:0x6001]) == b"\x41"


def test_random_sequence(mem):
    # TP 6.0 vectors: seed' = seed * 08088405h + 1; result = hi16 mod range.
    lib, _mirror = mem
    seed_of(lib).value = 0
    assert lib.hybrid_System_Random(100) == (1 >> 16) % 100 == 0
    assert seed_of(lib).value == 1
    seed_of(lib).value = 0x12345678
    want_seed = (0x12345678 * 0x08088405 + 1) & 0xFFFFFFFF
    assert lib.hybrid_System_Random(1000) == (want_seed >> 16) % 1000
    assert seed_of(lib).value == want_seed


def test_random_zero_range_steps_seed(mem):
    # Proven on the original (fuzz 0AF8:11C0): range 0 still steps the seed.
    lib, _mirror = mem
    seed_of(lib).value = 0xABCDEF01
    assert lib.hybrid_System_Random(0) == 0
    assert seed_of(lib).value == (0xABCDEF01 * 0x08088405 + 1) & 0xFFFFFFFF


def test_portability_lint():
    import subprocess
    py = str(ROOT / ".venv/bin/python")
    r = subprocess.run([py, "tools/lint/portability.py"], cwd=ROOT, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
