#!/usr/bin/env python3
"""winscan.py: the shapes of generated code that are unsafe with two data windows (docs/HEAP-STUDY.md, option 1; docs/RISKS.md class 13).

  winscan.py [GEN_DIR]        GEN_DIR is build/gen/vm (the translation of the CoCo build); exit 1 when a rule finds something new

A pointer into a data window is good until the next access to another page. CMOC works a statement out right to left and takes the address of the
left side last (probes/asm/win-order.c), so a scalar read is a value before the next window call and an assignment stores at once. Three shapes remain:

  1. a window address (an array or string field, `&field`) handed to a routine of the game: the callee's own accesses can take the window away. The
     translator copies a string field into a temporary (p2c_expr._arg_pass); what is left in window-escapes.txt must be a runtime routine that only
     moves bytes (FillChar, Move, BlockRead, BlockWrite);
  2. a call with three or more window addresses at once (two windows hold two); the third argument of the picture copies is a value, not an address;
  3. a `with` over a record that is itself in a window (the translator keeps the far pointer of a banked block and maps it again at every field).

The checks read the text of the translation; they do not know a type, so what they list is read, not proved."""
import glob
import os
import re
import sys

KNOWN_VALUE_ARGS = {("ovl12.c", "ShowDebugTrace"), ("ovl16.c", "rtl_Move"), ("ovl32.c", "rtl_Move")}   # a value read as an argument, or code the build replaces (mkgame PATCHES)
RUNTIME = {"FillChar", "Move", "BlockRead", "BlockWrite"}


def calls(text):
    for m in re.finditer(r"\b(\w+)\(", text):
        i, depth, args, cur = m.end(), 1, [], ""
        while i < len(text) and depth:
            ch = text[i]
            if ch in "([":
                depth += 1
            elif ch in ")]":
                depth -= 1
                if depth == 0:
                    break
            if ch == "," and depth == 1:
                args.append(cur)
                cur = ""
            else:
                cur += ch
            i += 1
        args.append(cur)
        yield m.group(1), [a.strip() for a in args]


def main(argv):
    gen = argv[1] if len(argv) > 1 else "build/gen/vm"
    bad = 0
    esc = [l.rstrip() for l in open(os.path.join(gen, "window-escapes.txt"))] if os.path.exists(os.path.join(gen, "window-escapes.txt")) else []
    direct = []
    for l in esc:
        m = re.match(r"(\S+) (\w+)\((\w+)\) <- (.*)", l)
        if m and m.group(2) not in RUNTIME and re.match(r"^(\(void \*\))?&?\(\*FPB\(", m.group(4)) and "rtl_str_assign" not in m.group(4) and "rtl_str_cat_v" not in m.group(4):
            direct.append(l)
    print("1. window addresses handed to a routine of the game: %d sites listed in window-escapes.txt, %d direct (the rest are copies in a temporary or runtime moves)" % (len(esc), len(direct)))
    for l in direct:
        print("   " + l[:200])
    bad += len(direct)
    many = []
    for f in sorted(glob.glob(os.path.join(gen, "ovl*.c")) + glob.glob(os.path.join(gen, "res*.c"))):
        for i, line in enumerate(open(f), 1):
            if line.lstrip().startswith(("/*", "*")):
                continue
            for fn, args in calls(line):
                if fn.startswith(("FP", "PEEKP", "VMV")):
                    continue
                n = sum(1 for a in args if re.match(r"^(\(void \*\))?&?\(\*FP[BD]\(", a) or re.match(r"^&FPB\(", a))
                if n >= 3 and (os.path.basename(f), fn) not in KNOWN_VALUE_ARGS:
                    many.append("%s:%d %s %d addresses" % (os.path.basename(f), i, fn, n))
    print("2. calls with three or more window addresses: %d new" % len(many))
    for x in many:
        print("   " + x)
    bad += len(many)
    withs = [(os.path.basename(f), i) for f in sorted(glob.glob(os.path.join(gen, "ovl*.c")) + glob.glob(os.path.join(gen, "res*.c")))
             for i, line in enumerate(open(f), 1) if "WINDOW-WITH" in line]
    print("3. with statements over a pointer into a window: %d (ovl16 StartingAgeTable[..] is a paged table whose fields are read before the dice are rolled: read, safe)" % len(withs))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
