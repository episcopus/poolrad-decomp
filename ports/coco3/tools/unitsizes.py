#!/usr/bin/env python3
"""unitsizes.py: compile every generated unit with CMOC and tabulate the 6809 sizes (step 8.1).
Runs inside the toolchain. Usage: unitsizes.py REPO_DIR BUILD_DIR [unit ...]

Reads the units from REPO_DIR/c/game (after tools/cmocify.py and tools/mkshim.py have written
BUILD_DIR/game and BUILD_DIR/shim), compiles each with the port's CMOC flags and reads the section
sizes from lwobjdump. The x86 size is code_bytes of REPO_DIR/re/units.toml.
Writes BUILD_DIR/sizes.tsv and prints a table.
"""
import os
import re
import subprocess
import sys
import tomllib

repo, build = sys.argv[1], sys.argv[2]
want = sys.argv[3:]
game = os.path.join(build, "game")

units = tomllib.load(open(os.path.join(repo, "re/units.toml"), "rb"))
x86 = {}
for kind in units.values():
    if isinstance(kind, list):
        for u in kind:
            if "id" in u and "code_bytes" in u:
                x86[u["id"]] = u["code_bytes"]

skip = {"image", "proc_table", "pool", "poolvars"}
names = want or sorted(n[:-2] for n in os.listdir(game) if n.endswith(".c") and n[:-2] not in skip)
rows, failed = [], []
for n in names:
    obj = os.path.join(build, n + ".o")
    if os.path.exists(obj):
        os.unlink(obj)
    p = subprocess.run(
        ["cmoc", "-c", "--void-target", "--no-relocate", "-O2", "-w"] + os.environ.get("CMOC_EXTRA", "").split() + [ "-Ishim", "-I" + os.path.join(build, "shim"),
         "-I" + game, "-o", obj, os.path.join(game, n + ".c")], capture_output=True, text=True)
    if p.returncode != 0 or not os.path.exists(obj):
        out = (p.stdout + p.stderr).splitlines()
        errs = [l for l in out if "error" in l.lower()] or out[-3:] or ["exit %d" % p.returncode]
        failed.append((n, len(errs), errs))
        continue
    dump = subprocess.run(["lwobjdump", obj], capture_output=True, text=True).stdout
    sec, size = None, {}
    for line in dump.splitlines():
        m = re.match(r"SECTION (\S+)", line)
        if m:
            sec = m.group(1)
        m = re.match(r"\s+CODE ([0-9A-Fa-f]+) bytes", line)
        if m and sec:
            size[sec] = size.get(sec, 0) + int(m.group(1), 16)
    rows.append((n, x86.get(n), size.get("code", 0), size.get("rodata", 0), size.get("rwdata", 0),
                 size.get("bss", 0), size.get("initgl", 0)))

tag = os.environ.get("SIZES_TAG", "")
with open(os.path.join(build, "sizes%s.tsv" % tag), "w") as f:
    f.write("unit\tx86_code\tcmoc_code\trodata\trwdata\tbss\tinitgl\n")
    for r in rows:
        f.write("\t".join("" if v is None else str(v) for v in r) + "\n")
print(f"{'unit':8} {'x86':>7} {'cmoc':>7} {'ratio':>6} {'rodata':>7} {'rwdata':>7} {'bss':>5} {'initgl':>7}")
for n, x, c, ro, rw, bss, ig in rows:
    ratio = f"{c / x:.2f}" if x else "-"
    print(f"{n:8} {x if x is not None else '-':>7} {c:>7} {ratio:>6} {ro:>7} {rw:>7} {bss:>5} {ig:>7}")
tx = sum(r[1] or 0 for r in rows)
tc = sum(r[2] for r in rows)
print(f"{'total':8} {tx:>7} {tc:>7} {tc / tx if tx else 0:>6.2f}")
with open(os.path.join(build, "errors.txt"), "w") as f:
    for n, k, errs in failed:
        f.write("\n".join(errs) + "\n")
for n, k, errs in failed:
    print(f"FAILED {n}: {k} errors; first: {errs[0] if errs else '?'}")
