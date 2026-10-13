"""A routine address in another unit (escalate-ovl08-20261012113252).

`ds6B84 := @ovl22_e4` compiles to `mov ax, ofs; mov dx, seg` (probe build/probe-ptr). The offset
moves by the padding procedure in every unit, so it used to be read as an offset of the unit being
matched. The segment word, a relocation, selects the unit.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/match"))

import match  # noqa: E402


class _Orig:
    units = {"ovl08": {}, "ovl22": {}, "ovl13": {}}

    def id_of_name(self, name):
        return {
            "ENDCOMBAT": "ovl08:0000",
            "OVL22_E4": "ovl22:0A91",
            "OVL13_E14": "ovl13:20C3",
        }.get(name.upper())

    def code_address(self, uid, value):
        if uid == "ovl22" and value == 0x34:
            return "ovl22:0A91"
        if uid == "ovl13" and value == 0x66:
            return "ovl13:20C3"
        if uid == "ovl08" and value == 0:
            return "ovl08:0000"
        return None


def _build(img, relocs, pubs):
    segs = {
        "OVL08": (0x100, 0x80, "CODE"),
        "OVL22": (0x220, 0x80, "CODE"),
        "OVL13": (0x680, 0x80, "CODE"),
    }
    return match.Build(bytes(img), relocs, segs, pubs)


def _pair(img, relocs, pubs_a, pubs_b):
    cmp = match.Comparer.__new__(match.Comparer)
    cmp.a = _build(img, relocs, pubs_a)
    cmp.b = _build(b"", set(), pubs_b)
    cmp.orig = _Orig()
    cmp.unit = "ovl08"
    cmp.seg = "OVL08"
    return cmp


def test_an_offset_shared_with_this_unit_names_the_other_units_routine():
    """EndCombat and ovl22_e4 are both at offset 0; the original word is ovl22's stub offset 0x34."""
    img = bytearray(0x200)
    img[0x100:0x106] = bytes.fromhex("b80000ba2200")
    pubs_a = {"ENDCOMBAT": (0x10, 0x0000), "OVL22_E4": (0x22, 0x0000)}
    pubs_b = {"ENDCOMBAT": (0x10, 0x0005), "OVL22_E4": (0x22, 0x0005)}
    cmp = _pair(img, {0x104}, pubs_a, pubs_b)
    ok, why = cmp.immediate(0, 5, 0x34, match.Region("EndCombat", 0, 0, 0x10), 0, 1)
    assert ok, why


def test_the_same_offset_is_rejected_when_the_original_names_another_routine():
    img = bytearray(0x200)
    img[0x100:0x106] = bytes.fromhex("b80000ba2200")
    pubs_a = {"ENDCOMBAT": (0x10, 0x0000), "OVL22_E4": (0x22, 0x0000)}
    pubs_b = {"ENDCOMBAT": (0x10, 0x0005), "OVL22_E4": (0x22, 0x0005)}
    cmp = _pair(img, {0x104}, pubs_a, pubs_b)
    ok, why = cmp.immediate(0, 5, 0x66, match.Region("EndCombat", 0, 0, 0x10), 0, 1)
    assert not ok and "OVL22_E4" in why


def test_a_same_unit_routine_address_still_matches():
    img = bytearray(0x200)
    pubs_a = {"ENDCOMBAT": (0x10, 0x0000), "OVL22_E4": (0x22, 0x0010)}
    pubs_b = {"ENDCOMBAT": (0x10, 0x0005), "OVL22_E4": (0x22, 0x0015)}
    cmp = _pair(img, set(), pubs_a, pubs_b)
    ok, why = cmp.immediate(0, 5, 0, match.Region("EndCombat", 0, 0, 0x10), 0, 1)
    assert ok, why


def test_a_shifted_pool_literal_is_not_a_routine_address():
    img = bytearray(0x200)
    pubs_a = {"ENDCOMBAT": (0x10, 0x0000)}
    pubs_b = {"ENDCOMBAT": (0x10, 0x0005)}
    cmp = _pair(img, set(), pubs_a, pubs_b)
    ra = match.Region("EndCombat", 0x30, 0, 0x40)
    ok, why = cmp.immediate(0x20, 0x25, 0x00, ra, 0x10, 1)
    assert ok, why
    ok, why = cmp.immediate(0x20, 0x25, 0x01, ra, 0x10, 1)
    assert not ok and "literal" in why
