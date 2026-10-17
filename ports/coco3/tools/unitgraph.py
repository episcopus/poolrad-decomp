#!/usr/bin/env python3
"""unitgraph.py: function sizes and cross-unit calls of the CMOC-compiled game (step 8.1).
Runs inside the toolchain (needs lwobjdump). Usage: unitgraph.py BUILD_DIR REPO_DIR

  functions: the size of every routine, from the funcsize_ symbols CMOC leaves in each object
  edges:     for every routine, which routines of OTHER units it names (static call sites in the
             generated C; a procedure pointer is one more name), so the number of far-call stubs
             and call sites a unit assignment would need can be counted.
"""
import collections
import os
import re
import subprocess
import sys

build, repo = sys.argv[1], sys.argv[2]
game = os.path.join(build, "game")
units = sorted(n[:-2] for n in os.listdir(game)
               if n.endswith(".c") and n[:-2] not in ("image", "proc_table", "pool", "poolvars"))

# 1. function sizes, in the order they sit in the object
size = {}       # unit -> [(function, bytes)]
for u in units:
    obj = os.path.join(build, u + ".o")
    if not os.path.exists(obj):
        continue
    out = subprocess.run(["lwobjdump", obj], capture_output=True, text=True).stdout
    fs = [(m.group(1), int(m.group(2), 16)) for m in re.finditer(r"^\s+funcsize_(\w+)=([0-9A-Fa-f]+)$", out, re.M)]
    size[u] = fs

allfn = [(b, f, u) for u, fs in size.items() for f, b in fs]
allfn.sort(reverse=True)
print("largest routines (bytes):", ", ".join(f"{f} {b} ({u})" for b, f, u in allfn[:12]))
n = len(allfn)
over = lambda t: sum(1 for b, _, _ in allfn if b > t)
print(f"routines: {n}; over 1 KB: {over(1024)}; over 2 KB: {over(2048)}; over 4 KB: {over(4096)}; over 8 KB: {over(8192)}")
tot = sum(b for b, _, _ in allfn)
print(f"sum of routine sizes {tot}")

# 2. the split of an oversize unit into contiguous parts that fit a window
def split(unit, limit):
    parts, cur, cur_n = [], 0, 0
    for f, b in size[unit]:
        if cur and cur + b > limit:
            parts.append((cur, cur_n))
            cur, cur_n = 0, 0
        cur += b
        cur_n += 1
    parts.append((cur, cur_n))
    return parts
for u in ("ovl16",):
    for lim in (16384 - 1024, 16384 - 4096, 12288):
        ps = split(u, lim)
        print(f"{u} in parts of at most {lim}: {len(ps)} parts " + ", ".join(f"{b}B/{k} routines" for b, k in ps))

# 3. cross-unit edges from the generated C
defs = {}       # function -> unit
src = {}
for u in units:
    text = open(os.path.join(repo, "c/game", u + ".c")).read()
    src[u] = text
    for m in re.finditer(r"^(?:static )?[A-Za-z_][\w ]*?[ *](\w+)\([^;{]*\)\s*\n\{", text, re.M):
        defs[m.group(1)] = u
edges = collections.Counter()
callees = collections.defaultdict(set)      # unit -> functions of other units it calls
for u, text in src.items():
    for name, owner in defs.items():
        pass
names = re.compile(r"\b(" + "|".join(sorted(map(re.escape, defs), key=len, reverse=True)) + r")\b")
for u, text in src.items():
    body = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    for m in names.finditer(body):
        f = m.group(1)
        owner = defs[f]
        if owner != u:
            edges[(u, owner)] += 1
            callees[owner].add(f)
res = lambda u: u.startswith("res")
cross = sum(edges.values())
to_res = sum(c for (a, b), c in edges.items() if res(b))
ov_ov = sum(c for (a, b), c in edges.items() if not res(a) and not res(b))
print(f"static references from one unit to a routine of another unit: {cross} "
      f"(to resident units {to_res}, overlay to overlay {ov_ov})")
stubs = sum(len(v) for k, v in callees.items() if not res(k))
print(f"routines of overlay units named from other units (far stubs needed if each overlay is a bank): {stubs}")
print("overlay-to-overlay pairs with the most references:")
for (a, b), c in sorted(((k, v) for k, v in edges.items() if not res(k[0]) and not res(k[1])),
                        key=lambda kv: -kv[1])[:10]:
    print(f"  {a} -> {b}: {c}")
print("overlay units most referenced from other overlays:")
inb = collections.Counter()
for (a, b), c in edges.items():
    if not res(a) and not res(b):
        inb[b] += c
for b, c in inb.most_common(6):
    print(f"  {b}: {c}")
