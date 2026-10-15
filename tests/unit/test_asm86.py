"""The assembler of the sound driver (tools/re/asm86.py) and src/RES03.ASM (playbook 50).

The encodings are the ones TASM chose, which the driver's bytes show; the last test assembles the real
source and compares it with the original's segment, so a change to either side that moves a byte fails."""
import struct
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/re"))
sys.path.insert(0, str(ROOT / "tools/match"))

import asm86  # noqa: E402


def asm(text: str) -> bytes:
    _obj, a = asm86.assemble(text, "T")
    return bytes(a.code)


@pytest.mark.parametrize("line,expected", [
    ("mov bp, sp", "8B EC"),                       # destination in the reg field
    ("mov al, ah", "8A C4"),
    ("sub dx, dx", "2B D2"),
    ("add bl, bl", "02 DB"),
    ("and ax, 7Fh", "25 7F 00"),                   # accumulator form, imm16
    ("cmp ax, 0", "3D 00 00"),
    ("and al, 0FCh", "24 FC"),
    ("add si, 30h", "83 C6 30"),                   # sign-extended imm8
    ("cmp di, 457h", "81 FF 57 04"),
    ("sub bl, 0FAh", "80 EB FA"),
    ("mov word ptr [si + 0Ah], bx", "89 5C 0A"),
    ("mov ax, word ptr [si + 8]", "8B 44 08"),
    ("mov bl, byte ptr [20Dh]", "8A 1E 0D 02"),
    ("mov al, byte ptr [20Dh]", "A0 0D 02"),       # AL/AX with a direct address
    ("mov word ptr cs:[1378h], bx", "2E 89 1E 78 13"),
    ("mov byte ptr [bx + 209h], al", "88 87 09 02"),
    ("mov word ptr [3C5h], 0", "C7 06 C5 03 00 00"),
    ("cmp word ptr [1DBh], 0", "83 3E DB 01 00"),
    ("shr ax, 1", "D1 E8"),
    ("sar ax, cl", "D3 F8"),
    ("inc di", "47"),
    ("inc cl", "FE C1"),
    ("dec word ptr [si]", "FF 0C"),
    ("imul word ptr [si + 22h]", "F7 6C 22"),
    ("mul byte ptr [bx + 1]", "F6 67 01"),
    ("retf 2", "CA 02 00"),
    ("in al, 61h", "E4 61"),
    ("out 0C0h, al", "E6 C0"),
    ("mov es, bx", "8E C3"),
    ("mov word ptr cs:[1378h], es", "2E 8C 06 78 13"),
])
def test_encodings_are_tasms(line, expected):
    assert asm(line) == bytes.fromhex(expected.replace(" ", ""))


def test_branches_choose_short_backward_near_forward_and_short_conditionals():
    src = "top:\n  nop\n  jmp top\n  jne top\n  jmp fwd\n  nop\nfwd:\n  call top\n"
    got = asm(src)
    assert got == bytes([0x90, 0xEB, 0xFD, 0x75, 0xFB, 0xE9, 0x01, 0x00, 0x90, 0xE8, 0xF4, 0xFF])


def test_labels_become_fixups_and_codeseg_a_segment_fixup():
    obj, a = asm86.assemble("start:\n  mov ax, CODESEG\n  mov si, tab\n  mov bx, word ptr [tab + 2]\ntab:\n  dw start, tab\n", "T")
    kinds = [(f.kind, f.offset) for f in a.fixups]
    assert ("seg", 1) in kinds and ("off", 4) in kinds
    assert sum(1 for k, _ in kinds if k == "off") == 4        # si, [tab + 2], and the two words
    assert bytes(a.code[4:6]) == struct.pack("<H", a.labels["tab"])      # the field holds the label's offset


def test_object_file_records_have_valid_checksums():
    obj, _ = asm86.assemble("PUBLIC go\ngo:\n  mov ax, CODESEG\n  retf\n", "T")
    pos, kinds = 0, []
    while pos < len(obj):
        rtype, length = obj[pos], obj[pos + 1] | obj[pos + 2] << 8
        assert sum(obj[pos:pos + 3 + length]) % 256 == 0
        kinds.append(rtype)
        pos += 3 + length
    assert kinds[0] == 0x80 and kinds[-1] == 0x8A and {0x98, 0x90, 0xA0, 0x9C} <= set(kinds)


def test_a_fixup_field_is_never_split_across_two_data_records():
    # 1023 bytes of data, then a word with a fixup: it would straddle the 1024 byte record limit
    src = "x:\n  db 1023 dup (0)\n  dw x\n"
    obj, a = asm86.assemble(src, "T")
    pos = 0
    ledata = []
    while pos < len(obj):
        rtype, length = obj[pos], obj[pos + 1] | obj[pos + 2] << 8
        if rtype == 0xA0:
            ledata.append((struct.unpack_from("<H", obj, pos + 4)[0], length - 4))
        pos += 3 + length
    assert len(ledata) == 2 and ledata[0][1] == 1023            # the word starts the second record


def test_unknown_instruction_is_refused():
    with pytest.raises(asm86.AsmError):
        asm("frobnicate ax")


def test_the_driver_source_assembles_to_the_originals_bytes():
    import match
    source = ROOT / "src/RES03.ASM"
    if not source.exists():
        pytest.skip("no src/RES03.ASM")
    obj, a = asm86.assemble(source.read_text(), "RES03X")
    code = bytearray(a.code)
    base = 0x1D7                                  # where the linker places the object in the unit
    for f in a.fixups:
        v = struct.unpack_from("<H", code, f.offset)[0]
        struct.pack_into("<H", code, f.offset, (v + base) & 0xFFFF if f.kind == "off" else 0x08AE)
    original, _seg = match.Original().segment("res03")
    assert bytes(code) == bytes(original[base:base + len(code)])
    assert len(code) == 5721
    assert {"StartSoundTimer", "StopSoundTimer", "SetSpeakerTune", "SetTandyTune",
            "SetSoundOutput"} <= set(a.publics)
