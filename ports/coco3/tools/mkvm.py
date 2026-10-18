#!/usr/bin/env python3
"""mkvm.py: lay the game's DGROUP out for the CoCo (step 8.5). The Pascal data segment is 34,656 bytes at fixed offsets and
every global is reached as `pool_ds + offset`. The CoCo cannot hold that image next to the code, so the globals go to two
places:

  native   a few hundred bytes to 8 KB that sit in the 64 KB map for good (the engine's choice, placement-vm.toml): a plain
           address, VMN(offset)
  paged    everything else, in 8 KB pages reached through the two data windows (slot 6 and slot 7, whose last 512 bytes
           are I/O: an object must end before offset $1E00 of its page): VMV(address), a call that maps the page and
           returns the pointer. No global straddles that border (the layout inserts gaps), so one mapping serves a
           whole object.

Globals that overlap (an absolute variable, a raw view of the same bytes) form a cluster and move together, so the bytes
keep their relative place. Only clusters some unit names get a place; the rest of DGROUP (the engine's tables of the PC's
video hardware, the unused 20%) is dropped.

  mkvm.py GEN_DIR PLAN.toml OUT_DIR     GEN_DIR from pas2c --profile coco; PLAN from mkplan.py

OUT_DIR gets the units and game.h with `pool_ds + 0xOFF` rewritten to VMN(new) or VMV(new) (the new offsets are offsets in
the DS segment, which the host model keeps; on the CoCo VMN is a fixed address and VMV a page and an offset), and
vmlayout.c: the cluster table for the runtime (initial image, the System unit's variables) and vm_map_ds()."""
import glob
import os
import re
import shutil
import sys
from pathlib import Path

try:
    import tomllib
except ImportError:                                       # Python < 3.11
    tomllib = None

PAGE = 0x2000
USABLE = 0x1E00                                            # data window 1 is slot 7: $E000..$FDFF, the rest of the page is I/O
ENGINE_UNITS = {"res05", "res06", "res07", "res09", "ovl28", "ovl32", "ovl34"}
NAT_BASE = 0x0000                                          # DS offsets of the host model; the CoCo has its own addresses
VM_BASE = 0x2000
CONST_END = 0x43DC
# System unit variables and the Input/Output records the runtime reads and writes itself: always native
SYSTEM = [(0x4400, 0x30), (0x84F0, 0x218)]


def parse_plan(path):
    text = Path(path).read_text()
    if tomllib:
        return {c[0] for c in tomllib.loads(text)["native"]["clusters"]}
    return {int(m.group(1), 16) for m in re.finditer(r"^\s*\[(0x[0-9A-Fa-f]+),", text, re.M)}


def main(argv):
    gen, plan, out = argv[1], argv[2], argv[3]
    native_los = parse_plan(plan)
    g = []
    for l in open(gen + "/globals.txt"):
        p = l.split()
        g.append((int(p[0], 16), int(p[1]), p[2]))
    g.sort()
    units = {Path(f).stem: open(f).read() for f in glob.glob(gen + "/*.c")}
    repo = Path(os.environ["REPO"]) if "REPO" in os.environ else Path(__file__).resolve().parents[3]
    extra = "".join(open(f).read() for d in ("c/rtl", "c/platform", "c/driver") for f in glob.glob(str(repo / d / "*.c")))
    logic = "".join(t for u, t in units.items() if u not in ENGINE_UNITS and u not in ("image", "poolvars")) + extra
    eng = "".join(units.get(u, "") for u in ENGINE_UNITS)
    rtl_offs = {int(m.group(1), 16) for m in re.finditer(r"(?:V16|V32|DGS|pool_ds \+)\(?\s*(0x[0-9A-Fa-f]{4})", extra)}
    # clusters over every global (names that overlap one another stand for the same bytes, and the code may reach any of
    # them), kept when some unit or the runtime names one of them
    allg = [(off, size, name) for off, size, name in g] + [(o, sz, "system%04X" % o) for o, sz in SYSTEM]
    allg.sort()
    clusters = []                                           # [lo, hi, names, logic?]
    for off, size, name in allg:
        if clusters and off < clusters[-1][1]:
            clusters[-1][1] = max(clusters[-1][1], off + size)
            clusters[-1][2].append(name)
        else:
            clusters.append([off, off + size, [name], False])
    kept = []
    for c in clusters:
        hit_l = hit_e = False
        for name in c[2]:
            pat = re.compile(r"\b" + re.escape(name) + r"\b")
            hit_l = hit_l or bool(pat.search(logic)) or name.startswith("system")
            hit_e = hit_e or bool(pat.search(eng))
        hit_l = hit_l or any(c[0] <= o < c[1] for o in rtl_offs)
        if hit_l or hit_e:
            c[3] = hit_l
            kept.append(c)
    clusters = kept
    # classes: native (the plan, the System variables), paged
    for c in clusters:
        rtl = any(c[0] <= o < c[1] for o in rtl_offs)             # the host runtime reads it without the accessor
        c.append("N" if (c[0] in native_los or rtl or any(n.startswith("system") for n in c[2])) else "V")
    # A paged aggregate (an array, a record, a string) passed to a routine of the game by reference is a pointer into a
    # window that the callee keeps while it calls other routines, and those remap the window. Such a global is made native.
    gh = open(gen + "/game.h").read()
    kinds = {}
    for m in re.finditer(r"^#define (\w+) (\(.*\))$", gh, re.M):
        body = m.group(2)
        mo = re.search(r"pool_ds \+ (0x[0-9A-Fa-f]+)", body)
        if mo:
            kinds[m.group(1)] = (int(mo.group(1), 16), "array" if "->a)" in body else
                                 "scalar" if re.match(r"\(\*\((?:u8|s8|u16|s16|u32|s32|farptr) ?\*?\)", body) else "record")
    defs = set()
    for u, t in units.items():
        for m in re.finditer(r"^(?:static )?[A-Za-z_][\w ]*?[ *](\w+)\([^;{]*\)\s*\n\{", t, re.M):
            defs.add(m.group(1))
    promoted = []

    def calls(text):
        """(function, [top-level argument texts]) for every call in the text"""
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

    bare = {nm: re.compile(r"^(?:\((?:void|u8|const u8)? ?\*\))?&?\(?" + nm + r"\)?$") for nm, (_, k) in kinds.items() if k != "scalar"}
    for u, t in units.items():
        if u in ENGINE_UNITS or u in ("image", "poolvars"):
            continue
        for fn, args in calls(t):
            if fn.startswith("rtl_") or fn not in defs:
                continue
            for arg in args:
                for nm, rx in bare.items():
                    if rx.match(arg):
                        off = kinds[nm][0]
                        for c in clusters:
                            if c[0] <= off < c[1] and c[4] == "V":
                                c[4] = "N"
                                promoted.append((nm, c[1] - c[0], fn))
    # layout
    nat, vm = NAT_BASE, VM_BASE
    for c in clusters:
        size = c[1] - c[0]
        if c[4] == "N":
            c.append(nat)
            nat += size
        else:
            if size > USABLE:
                raise SystemExit("cluster %s is %d bytes: more than a page" % (c[2][0], size))
            if (vm % PAGE) + size > USABLE:
                vm = (vm // PAGE + 1) * PAGE
            c.append(vm)
            vm += size
    if nat > VM_BASE:
        raise SystemExit("native clusters need %d bytes, the host model leaves %d" % (nat - NAT_BASE, VM_BASE - NAT_BASE))

    def new_off(off):
        for lo, hi, names, lg, cls, nw in clusters:
            if lo <= off < hi:
                return cls, nw + off - lo
        raise KeyError(off)

    os.makedirs(out, exist_ok=True)
    pat = re.compile(r"pool_ds \+ (0x[0-9A-Fa-f]+)\)")
    missing = set()

    def sub(m):
        off = int(m.group(1), 16)
        try:
            cls, nw = new_off(off)
        except KeyError:                                   # a global no unit names: its macro stays, but may not be used
            missing.add(off)
            return "VMU(0x%04X))" % off
        return "%s(0x%04X))" % ("VMN" if cls == "N" else "VMV", nw)

    nrew = 0
    for f in glob.glob(gen + "/*"):
        name = os.path.basename(f)
        dst = os.path.join(out, name)
        if name.endswith((".c", ".h")) and Path(f).stem not in ("image", "poolvars"):
            t = open(f).read()
            t2, n = pat.subn(sub, t)
            nrew += n
            open(dst, "w").write(t2)
        elif os.path.isfile(f):
            shutil.copy(f, dst)
    unused = len(missing)
    with open(out + "/vmlayout.c", "w") as w:
        w.write("/* generated by ports/coco3/tools/mkvm.py: the DGROUP layout of the CoCo. */\n#include \"pool.h\"\n")
        w.write("const u16 vm_nat_size = %d;\nconst u16 vm_paged_end = %d;\n" % (nat - NAT_BASE, vm))
        w.write("const struct VmCluster vm_clusters[] = {\n")
        for lo, hi, names, lg, cls, nw in clusters:
            w.write("  {0x%04X, %d, '%s', %d, 0x%04X}, /* %s */\n" % (lo, hi - lo, cls, 1 if lg else 0, nw, names[0]))
        w.write("};\nconst u16 vm_cluster_count = %d;\n" % len(clusters))
        w.write("u16 vm_map_ds(u16 off)\n{\n  u16 i;\n  for (i = 0; i < vm_cluster_count; i++) {\n"
                "    if (off >= vm_clusters[i].lo && off < (u16)(vm_clusters[i].lo + vm_clusters[i].size)) {\n"
                "      return (u16)(vm_clusters[i].nw + off - vm_clusters[i].lo);\n    }\n  }\n"
                "  rtl_fatal(\"DGROUP offset %04X has no place in the CoCo layout\", off);\n  return 0;\n}\n")
    with open(out + "/vmlayout.h", "w") as w:
        w.write("/* generated by ports/coco3/tools/mkvm.py */\n#define VM_NAT_SIZE %d\n#define VM_PAGED_BASE 0x%04X\n#define VM_PAGED_END 0x%04X\n"
                "#define MAPPED_LO ((u16)((VM_PAGED_END + 0xFFu) & ~0xFFu))\n" % (nat - NAT_BASE, VM_BASE, vm))
    nn = sum(c[1] - c[0] for c in clusters if c[4] == "N")
    nv = sum(c[1] - c[0] for c in clusters if c[4] == "V" and c[3])
    ne = sum(c[1] - c[0] for c in clusters if c[4] == "V" and not c[3])
    if promoted:
        print("mkvm: made native because they are passed by reference to game routines: " +
              ", ".join("%s (%d bytes, to %s)" % p for p in promoted))
    print("mkvm: %d clusters, %d rewrites (%d offsets of globals no unit names: VMU); native %d bytes, paged %d bytes (+%d only the engine units name), paged space ends at %04X"
          % (len(clusters), nrew, unused, nn, nv, ne, vm))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
