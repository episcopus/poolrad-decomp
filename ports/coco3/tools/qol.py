#!/usr/bin/env python3
"""qol.py: the quality of life changes of the CoCo 3 port (docs/PHASE-8.13.md): DEVIATIONS from the PC original, on by default.

  * no code wheel (the copy protection: ovl02 CheckCodeWheel is never called)
  * the credits screen names the port and its version where the PC's version line was (ovl01 ShowCredits)
  * the ways out of the game say BASIC, not DOS (ovl15, ovl16 prompts; the training hall's menu entry, in the initial data: tools/mkvm.py calls patch_image)

POOL_QOL=0 in the environment (make QOL=0) builds the faithful game: the session goldens (tests/sessions, goldens/4bpp) are the PC's screens and
type the wheel's answer, so every target that plays a session builds that one (the Makefile's QOL_OFF_GOALS).

  qol.py version              the port's version (ports/coco3/VERSION)"""
import os
import sys
from pathlib import Path

ENABLED = os.environ.get("POOL_QOL", "1") != "0"
PC_VERSION = "1.3"                  # the PC original's version, as its credits screen printed it


def version():
    return (Path(__file__).resolve().parent.parent / "VERSION").read_text().strip()


def pas_s(text):
    """a Pascal string literal as the translation writes it: S("\\ooo" + text), the length in octal"""
    assert len(text) < 256 and '"' not in text and "\\" not in text
    return 'S("\\%03o%s")' % (len(text), text)


def credits_lines():
    """The credits screen's block of lines 34 to 43 of ovl01.c (the PC's version line, then the first programming block) as it is here: the port's
    line replaces the version line, in two rows (the 40 column screen has 36 cells of text: the whole line is 43), and the programming block, which
    follows, moves one row down into the empty row that separated it from the next block. COCO 3 PORT: is light green like the other labels of this
    block ("game created by:"), what follows light cyan like the names."""
    v = version()
    return [
        (2, 6, "LightGreen_OVL01", "coco 3 port:"),
        (15, 6, "LightCyan_OVL01", "unofficial - v%s" % v),
        (15, 7, "LightCyan_OVL01", "from pc v%s" % PC_VERSION),
        (2, 8, "Yellow_OVL01", "programming:"),
        (0x14, 8, "Yellow_OVL01", "original"),
        (2, 9, "LightCyan_OVL01", "scot bayless"),
        (0x14, 9, "Yellow_OVL01", "programming:"),
        (2, 0xA, "LightCyan_OVL01", "brad myers"),
        (0x14, 0xA, "LightCyan_OVL01", "keith brors"),
        (2, 0xB, "LightCyan_OVL01", "russ brown"),
        (0x14, 0xB, "LightCyan_OVL01", "brad myers"),
        (2, 0xC, "LightCyan_OVL01", "ted greer"),
    ]


# the translation's text of what is replaced (ovl01.c, ShowCredits), exactly
CREDITS_OLD = (
    '  DrawTextAt(0xE, 6, LightCyan_OVL01, S("\\013version 1.3"));\n'
    '  DrawTextAt(2, 7, Yellow_OVL01, S("\\014programming:"));\n'
    '  DrawTextAt(0x14, 7, Yellow_OVL01, S("\\010original"));\n'
    '  DrawTextAt(2, 8, LightCyan_OVL01, S("\\014scot bayless"));\n'
    '  DrawTextAt(0x14, 8, Yellow_OVL01, S("\\014programming:"));\n'
    '  DrawTextAt(2, 9, LightCyan_OVL01, S("\\012brad myers"));\n'
    '  DrawTextAt(0x14, 9, LightCyan_OVL01, S("\\013keith brors"));\n'
    '  DrawTextAt(2, 0xA, LightCyan_OVL01, S("\\012russ brown"));\n'
    '  DrawTextAt(0x14, 0xA, LightCyan_OVL01, S("\\012brad myers"));\n'
    '  DrawTextAt(2, 0xB, LightCyan_OVL01, S("\\011ted greer"));\n')


def credits_new():
    return "".join("  DrawTextAt(0x%X, 0x%X, %s, %s);\n" % (c, r, col, pas_s(t)) for c, r, col, t in credits_lines())


# the prompts that name DOS, by unit: the PC's text and ours (the length byte is part of the literal). ovl15: the camp menu's Quit and the Drop command
# with one member left; ovl16: the training hall's Exit
BASIC_PROMPTS = {"ovl15": [("Quit TO DOS ", "Return to BASIC "), ("quit TO DOS: ", "Return to BASIC: ")],
                 "ovl16": [("Quit to DOS ", "Return to BASIC ")]}


def patches():
    """{unit: [patch, ...]} in the form of tools/mkgame.py PATCHES; empty when POOL_QOL=0"""
    if not ENABLED:
        return {}
    out = {"ovl01": [("all", CREDITS_OLD, credits_new())]}
    for u, prompts in BASIC_PROMPTS.items():
        out[u] = [("all", pas_s(a), pas_s(b)) for a, b in prompts]
    return out


def drop_wheel(pool_c):
    """pool.c without the call of the code wheel (the check lives in overlay 2: the call would load its bank for nothing)"""
    if not ENABLED:
        return pool_c
    call = "    CheckCodeWheel();\n"
    if pool_c.count(call) != 1:
        raise SystemExit("qol: the call of CheckCodeWheel is not in pool_main once")
    return pool_c.replace(call, "")


MENU_OLD, MENU_NEW = "Exit to DOS", "Exit to BASIC"       # the training hall's last menu entry (E is its hotkey: 'Return' would take R, Remove Character from Party's)


def patch_image(data):
    """the DGROUP initial image (the PC's data segment, before it is coded for the CoCo: tools/mkvm.py write_image) with the menu entry changed; the entry is a
    string[40] in a record of 42 bytes whose unused bytes are zero, so the new text fits where the old one was"""
    if not ENABLED:
        return data
    old = bytes([len(MENU_OLD)]) + MENU_OLD.encode()
    i = data.find(old)
    if i < 0 or data.find(old, i + 1) >= 0:
        raise SystemExit("qol: %r is not in the DGROUP image once" % MENU_OLD)
    new = bytes([len(MENU_NEW)]) + MENU_NEW.encode()
    if any(data[i + len(old):i + len(new)]):
        raise SystemExit("qol: the bytes after %r are not free" % MENU_OLD)
    return data[:i] + new + data[i + len(new):]


if __name__ == "__main__":
    if sys.argv[1:] == ["version"]:
        print(version())
    else:
        raise SystemExit(__doc__)
