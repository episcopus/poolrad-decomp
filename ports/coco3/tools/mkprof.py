#!/usr/bin/env python3
"""mkprof.py: the profiling copy of the Phase 7 C game (step 8.1c). Usage: mkprof.py REPO OUT_DIR

Writes OUT_DIR/include/pool.h (FPD goes through pool_prof_fpd) and OUT_DIR/game/ (the units
unchanged, game.h with every `pool_ds + 0xNNNN` turned into pool_prof_g(0xNNNN)), so a host build
(scripts/prof_run.sh) can count, per routine, the references to DGROUP and the dereferences of far
pointers into the heap. The game itself is not changed.
"""
import os
import re
import shutil
import sys

repo, out = sys.argv[1], sys.argv[2]
os.makedirs(out + "/include", exist_ok=True)
os.makedirs(out + "/game", exist_ok=True)

pool = open(repo + "/c/include/pool.h").read()
new, n = re.subn(r"#define FPD\(T, p\)[^\n]*",
                 "void *pool_prof_fpd(farptr p);\nvoid *pool_prof_g(u32 off);\n"
                 "#define FPD(T, p) ((T)pool_prof_fpd(p))", pool)
assert n == 1
open(out + "/include/pool.h", "w").write(new)

for name in os.listdir(repo + "/c/game"):
    src = repo + "/c/game/" + name
    if not name.endswith((".c", ".h")):
        continue
    text = open(src).read()
    if name == "game.h":
        text, k = re.subn(r"pool_ds \+ (0x[0-9A-Fa-f]+)", r"pool_prof_g(\1)", text)
        print(f"mkprof: {k} DGROUP references instrumented")
    open(out + "/game/" + name, "w").write(text)
