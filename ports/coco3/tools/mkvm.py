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
NAT_BASE = 0x0000                                          # DS offsets of the host model
VM_BASE = 0x2000
# --coco: the DS offsets are the CoCo's addresses (a native global at offset o is at address o, a block of the mapped heap
# likewise) and the paged globals live at offsets from $8000 up, which no address of the map is used for.
COCO_NAT_BASE = 0x4E20
COCO_VM_BASE = 0x8000
CONST_END = 0x43DC
# System unit variables and the Input/Output records the runtime reads and writes itself: always native
SYSTEM = [(0x4400, 0x30), (0x84F0, 0x218)]


def parse_plan(path):
    text = Path(path).read_text()
    if tomllib:
        return {c[0] for c in tomllib.loads(text)["native"]["clusters"]}
    return {int(m.group(1), 16) for m in re.finditer(r"^\s*\[(0x[0-9A-Fa-f]+),", text, re.M)}


# Bytes of a typed global that the game also reads as bytes through another global: they stay in the PC's order.
#   StartingAgeTable row 0 (28 bytes) is the index base of the table and lies over the Half-Orc and Human rows of RaceClassChoices
#   (POOLVARS, whitepaper 5.8: the Human row of the class menu is read from there; found when the class list came up empty)
#   ExperienceTable [0,0] and [0,1] (8 bytes) are not experience values: the first real one is [0,2] = 1501 (the cleric's level 2);
#   the bytes are the tail of ConstitutionHitPointTable (indexes 13..18, declared 19 long, stored on into the next storage)
#   SpecialBlocks entry 0 (4 bytes) is never read (OVL29 DrawAreaView tests entries 1..9); its bytes are WallViewIdTable[10..13], found
#   when the ceiling of the 3D view came out red (index 11 read the byte of index 10)
NOSWAP = [("StartingAgeTable", 0, 28), ("ExperienceTable", 0, 8), ("SpecialBlocks", 0, 4)]


def write_image(out, gen, clusters, nat_end, npages):
    """DGROUP.IMG, what the CoCo's loader (src/engine/gameboot.c) reads: "DGI2", the native base and size (big endian words), the
    number of pages, then two run length coded blocks (packed size, raw size, packed bytes): the paged globals (`npages` pages
    of 8,192 bytes) and the native bytes; the initial values from gen/image.c."""
    text = open(gen + "/image.c").read()
    org = int(re.search(r"pool_image_org = (0x[0-9A-Fa-f]+|\d+)", text).group(1), 0)
    body = text[text.index("pool_image[] = {") + 16:text.rindex("};")]
    img = bytearray(int(x, 16) for x in re.findall(r"0x([0-9A-Fa-f]{2})", body))
    # the CoCo is big endian, the image is the PC's: every multi-byte scalar of a typed global is reversed once (globals.txt
    # lists them as offset:width:count); bytes, strings and sets stay
    done = bytearray(len(img))
    nswap = 0
    gl = [l.split() for l in open(gen + "/globals.txt")]
    # The storage of a global is the Raw<addr> / ds<addr> array its declaration lies over (POOLVARS "DS:aaaa..bbbb: storage of X").
    # A typed view may be declared longer than its storage (an index base, a table that reads on into the next one), and a byte
    # view's values must not be reversed by a word view that overlaps them: a value is not swapped when it lies in the real extent
    # (declaration cut to storage) of another global that is read as bytes.
    stores = sorted((int(f[0], 16), int(f[0], 16) + int(f[1])) for f in gl if len(f) >= 3 and re.match(r"(Raw|ds)[0-9A-Fa-f]{4}$", f[2]))
    def storage_end(a):
        for lo, hi in stores:
            if lo <= a < hi:
                return hi
        return None
    storage_spans = [(lo, hi) for lo, hi in stores]
    byteviews = []
    for f in gl:
        if len(f) >= 5 and f[4] == "-" and not re.match(r"(Raw|ds)[0-9A-Fa-f]{4}$", f[2]):
            a = int(f[0], 16)
            e = storage_end(a)
            if e:
                byteviews.append((a, min(a + int(f[1]), e), f[2]))
    nskip = 0
    swapped_items, skipped = set(), []
    for f in gl:
        if len(f) < 5 or f[4] == "-":
            continue
        base = int(f[0], 16)
        for item in f[4].split(","):
            o, w, c = (int(x) for x in item.split(":"))
            for i in range(c):
                at = base + o + i * w
                pos = at - org
                if any(lo < at + w and at < hi and n != f[2] for lo, hi, n in byteviews):
                    nskip += 1
                    skipped.append((at, w))
                    continue
                if any(lo <= at < hi or lo < at + w <= hi for lo, hi in storage_spans if (lo <= at < hi) != (lo < at + w <= hi)):
                    nskip += 1                          # an item across the border of two storage arrays: an index base's overhang
                    skipped.append((at, w))
                    continue
                if any(lo <= at - base < hi for n, lo, hi in NOSWAP if n == f[2]):
                    nskip += 1
                    skipped.append((at, w))
                    continue
                if (at, w) in swapped_items:
                    continue                                # the same value listed by two globals
                if 0 <= pos and pos + w <= len(img) and not any(done[pos:pos + w]):
                    img[pos:pos + w] = img[pos:pos + w][::-1]
                    done[pos:pos + w] = b"\x01" * w
                    nswap += 1
                    swapped_items.add((at, w))
                elif 0 <= pos and pos + w <= len(img):
                    skipped.append((at, w))                 # overlaps a value that was turned round: left alone
    with open(out + "/unswapped.txt", "w") as sf:         # for tools/statecheck.py: the multi-byte values left in the PC's order
        for at, w in skipped:
            sf.write("%04X %d\n" % (at, w))
    print("mkvm: DGROUP.IMG: %d multi-byte values put in the CoCo's byte order (%d lie in the real extent of a byte view: left alone)" % (nswap, nskip))
    img = bytes(img)
    nat = bytearray(nat_end - NAT_BASE)
    pages = [bytearray(PAGE) for _ in range(npages)]
    for lo, hi, names, lg, cls, nw in clusters:
        a, b = max(lo, org), min(hi, org + len(img))
        if a >= b:
            continue
        data = img[a - org:b - org]
        at = nw + (a - lo)
        if cls == "N":
            nat[at - NAT_BASE:at - NAT_BASE + len(data)] = data
        else:
            k, o = divmod(at - VM_BASE, PAGE)
            pages[k][o:o + len(data)] = data
    paged = b"".join(bytes(pg) for pg in pages)
    with open(out + "/DGROUP.IMG", "wb") as f:
        f.write(b"DGI2" + bytes([NAT_BASE >> 8, NAT_BASE & 255, len(nat) >> 8, len(nat) & 255, npages]))
        for raw in (paged, bytes(nat)):                      # the pages first (to consecutive blocks), then the native bytes
            pk = rle_pack(raw)
            f.write(bytes([len(pk) >> 8, len(pk) & 255, len(raw) >> 8, len(raw) & 255]) + pk)


def rle_pack(raw):
    """the DAX run length code (src/engine/rle.asm): n < $80 copies n+1 bytes, n >= $80 repeats the next byte 256-n times"""
    out, i, lit = bytearray(), 0, bytearray()
    def flush():
        while lit:
            c = lit[:128]
            del lit[:128]
            out.append(len(c) - 1)
            out.extend(c)
    while i < len(raw):
        j = i
        while j < len(raw) and raw[j] == raw[i] and j - i < 128:
            j += 1
        if j - i >= 3:
            flush()
            out.append(256 - (j - i))
            out.append(raw[i])
            i = j
        else:
            lit.append(raw[i])
            i += 1
    flush()
    return bytes(out)


def main(argv):
    global NAT_BASE, VM_BASE
    coco = "--coco" in argv
    argv = [a for a in argv if a != "--coco"]
    if coco:
        NAT_BASE, VM_BASE = COCO_NAT_BASE, COCO_VM_BASE
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
    # layout: the native clusters one after the other, the paged ones first-fit decreasing into pages
    nat = NAT_BASE
    pages = []                                               # bytes used in each page
    for c in clusters:
        if c[4] == "N":
            c.append(nat)
            nat += c[1] - c[0]
        else:
            c.append(None)
    for c in sorted((c for c in clusters if c[4] == "V"), key=lambda c: -(c[1] - c[0])):
        size = c[1] - c[0]
        if size > USABLE:
            raise SystemExit("cluster %s is %d bytes: more than a page" % (c[2][0], size))
        for k, used in enumerate(pages):
            if used + size <= USABLE:
                break
        else:
            pages.append(0)
            k = len(pages) - 1
        c[5] = VM_BASE + k * PAGE + pages[k]
        pages[k] += size
    vm = VM_BASE + len(pages) * PAGE if pages else VM_BASE
    if nat > VM_BASE:
        raise SystemExit("native clusters need %d bytes, the layout leaves %d" % (nat - NAT_BASE, VM_BASE - NAT_BASE))
    if vm > 0x10000:
        raise SystemExit("the paged globals end at %X: past the 64 KB of offsets" % vm)

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
        if coco:
            w.write("/* generated by ports/coco3/tools/mkvm.py --coco: a DS offset below $8000 is a CoCo address */\n"
                    "#define VM_NAT_BASE 0x%04X\n#define VM_NAT_SIZE %d\n#define VM_PAGED_BASE 0x%04X\n#define VM_PAGED_END 0x%04X\n"
                    "#define MAPPED_LO 0x%04X\n#define MAPPED_HI 0x8000\n" % (NAT_BASE, nat - NAT_BASE, VM_BASE, vm, (nat + 7) & ~7))
        else:
            w.write("/* generated by ports/coco3/tools/mkvm.py */\n#define VM_NAT_SIZE %d\n#define VM_PAGED_BASE 0x%04X\n#define VM_PAGED_END 0x%04X\n"
                    "#define MAPPED_LO ((u16)((VM_PAGED_END + 0xFFu) & ~0xFFu))\n" % (nat - NAT_BASE, VM_BASE, vm))
    if coco:
        write_image(out, gen, clusters, nat, len(pages))
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
