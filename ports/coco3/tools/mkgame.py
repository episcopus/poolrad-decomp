#!/usr/bin/env python3
"""mkgame.py: build the game of the CoCo port from the laid-out C of mkvm.py (step 8.5c). Runs in the toolchain.

  mkgame.py GEN_DIR OUT_DIR      GEN_DIR from scripts/vm_host.sh (build/gen-vm), OUT_DIR for objects, stubs and images

What it does:
  1. compiles every unit of the game with CMOC (-fomit-frame-pointer);
  2. a unit whose code and constants do not fit a 16 KB bank is split at routine borders and its parts compiled again
     (the routines of the generated C are top level and not static, nested helpers stay with the routine that uses them);
  3. assigns the units to banks and the small resident ones to the core;
  4. writes the far stubs (the resident entry for every routine of a bank that another bank or the core calls), the entry
     table at the head of every bank, and the bank table.
The core and the banks are linked by the Makefile rules that follow (build/game/Makefile.inc), because they need the core's map."""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

BANK_BYTES = 0x4000                      # slots 4 and 5
BANK_LIMIT = BANK_BYTES - 0x180          # room for the entry table (3 bytes an entry) and a margin
CORE_UNITS = ["pool", "res02", "res04", "res10", "res11"]   # resident
SKIP_UNITS = {"image", "poolvars", "vmlayout"}
RTL_BANK = ("rtl_str", "rtl_heap")                     # the runtime that has no variables lives in a bank of its own (the core is small)
# Replaced by the engine (step 8.5d): whole units, and routines of units that stay. The engine provides them under the same
# names; until a routine is written a stub stops the program and says which one was asked for.
ENGINE_UNITS = ["res05", "res07", "ovl28", "res08"]
CORE_ROUTINES = {"res06": ["GameClock"]}                  # cut out of the unit, written in src/game (the core)
ENGINE_ROUTINES = {
    "res06": ["SetEgaFillRegisters", "SetActivePage", "SetPageSegment", "FillPlaneRect", "LoadGameFont", "DrawGlyph"],   # GameClock: rtl_sys.c
    "ovl34": ["Put8x8Symbol"],
    "ovl32": ["Load24x24Set", "DrawCellPicture", "DrawIcon"],
}
CMOC = ["cmoc", "-c", "--void-target", "--no-relocate", "-O2", "-fomit-frame-pointer", "-w"]


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def compile_c(src, obj, incs):
    p = run(CMOC + ["-I" + i for i in incs] + ["-o", obj, src])
    if p.returncode != 0 or not os.path.exists(obj):
        errs = [l for l in (p.stdout + p.stderr).splitlines() if "error" in l.lower()] or (p.stdout + p.stderr).splitlines()[-3:]
        raise SystemExit("cmoc failed on %s: %s" % (src, "; ".join(errs[:3])))


def objinfo(obj):
    """-> dict(code=, rodata=, exports=set, imports=set, funcs={name: size}, order=[name])"""
    out = run(["lwobjdump", obj]).stdout
    sec, mode = None, None
    code = rodata = 0
    exports, imports, funcs, order = set(), set(), {}, []
    for line in out.splitlines():
        m = re.match(r"SECTION (\S+)", line)
        if m:
            sec, mode = m.group(1), None
            continue
        s = line.strip()
        if s == "Exported symbols":
            mode = "e"
            continue
        if s == "Local symbols:":
            mode = "l"
            continue
        if s == "Incomplete references":
            mode = "i"
            continue
        m = re.match(r"CODE ([0-9A-Fa-f]+) bytes", s)
        if m:
            n = int(m.group(1), 16)
            if sec == "code":
                code += n
            elif sec == "rodata":
                rodata += n
            elif sec in ("rwdata", "bss", "initgl") and n:
                raise SystemExit("%s has %d bytes in section %s: banks hold code and constants only" % (obj, n, sec))
            continue
        if mode == "e":
            m = re.match(r"(\S+)=", s)
            if m:
                exports.add(m.group(1))
        elif mode == "i":
            for m in re.finditer(r"ES=([^\s)]+)", s):
                imports.add(m.group(1))
        elif mode == "l" and sec == "code":
            m = re.match(r"funcsize_(\S+)=([0-9A-Fa-f]+)", s)
            if m:
                funcs[m.group(1)] = int(m.group(2), 16)
    return {"code": code, "rodata": rodata, "exports": exports, "imports": imports - exports, "funcs": funcs}


# ---------------------------------------------------------------------------- splitting
def parse_items(text):
    """The top level items of a generated unit: ('pre', text) for everything before the first routine, then
    ('fn', name, static, text), ('other', text) for frame structs and the like. Comments stay with what follows."""
    lines = text.split("\n")
    items, cur, i = [], [], 0
    pending = []                                            # comment or blank lines waiting for an item
    n = len(lines)
    while i < n:
        ln = lines[i]
        if ln.startswith("/*") and "*/" not in ln:         # a block comment
            j = i
            while "*/" not in lines[j]:
                j += 1
            pending += lines[i:j + 1]
            i = j + 1
            continue
        if ln.startswith("/*") or ln.strip() == "":
            pending.append(ln)
            i += 1
            continue
        m = re.match(r"^(static )?[A-Za-z_][\w ]*?[ *](\w+)\([^;{]*\)\s*$", ln)
        if m and i + 1 < n and lines[i + 1] == "{":
            j = i + 1
            while lines[j] != "}":
                j += 1
            items.append(("fn", m.group(2), bool(m.group(1)), "\n".join(pending + lines[i:j + 1])))
            pending = []
            i = j + 1
            continue
        # anything else at column 0: a directive, a typedef, a struct up to its closing line, a declaration
        j = i
        if re.match(r"^(struct|union|typedef struct|typedef union|enum)\b.*\{\s*$", ln) or ln.rstrip().endswith("{"):
            while not re.match(r"^\}.*;\s*$", lines[j]):
                j += 1
        items.append(("other", "\n".join(pending + lines[i:j + 1])))
        pending = []
        i = j + 1
    if pending:
        items.append(("other", "\n".join(pending)))
    return items


def routine_names(text):
    return [it[1] for it in parse_items(text) if it[0] == "fn" and not it[2]]


def strip_routines(text, names):
    """The unit text without the named routines (and the static helpers that precede them)."""
    items = parse_items(text)
    keep, pend = [], []
    for it in items:
        if it[0] == "fn":
            pend.append(it)
            if not it[2]:
                if it[1] not in names:
                    keep.extend(pend)
                pend = []
        else:
            keep.append(it)
    keep.extend(pend)
    return "\n".join(it[1] if it[0] == "other" else it[3] for it in keep) + "\n"


def split_unit(name, text, funcs, parts_wanted):
    """-> [text of part 1, ...]: the non-routine items go to every part, the routines are dealt out in order so that
    each part gets about the same size; static helpers stay with the routine after them."""
    items = parse_items(text)
    shared = [it[1] for it in items if it[0] == "other"]
    groups, cur = [], []
    for it in items:
        if it[0] != "fn":
            continue
        cur.append(it)
        if not it[2]:                                       # a non-static routine closes the group
            groups.append(cur)
            cur = []
    if cur:
        groups.append(cur)
    sizes = [sum(funcs.get(it[1], 0) for it in g) for g in groups]
    total = sum(sizes)
    target = total / parts_wanted
    parts, acc, part = [], 0, []
    for g, sz in zip(groups, sizes):
        if part and acc + sz > target * 1.02 and len(parts) < parts_wanted - 1:
            parts.append(part)
            part, acc = [], 0
        part.append(g)
        acc += sz
    parts.append(part)
    head = "\n".join(shared)
    return [head + "\n" + "\n".join(it[3] for g in p for it in g) + "\n" for p in parts]


def main(argv):
    gen, out = Path(argv[1]).resolve(), Path(argv[2])
    inc = out / "inc"
    obj = out / "obj"
    for d in (inc, obj, out / "src"):
        d.mkdir(parents=True, exist_ok=True)
    here = Path(__file__).resolve().parent.parent
    for f in ("game.h", "vmlayout.h"):
        (inc / f).write_text((gen / f).read_text())
    for f in ("pool.h", "coco_map.h"):
        (inc / f).write_text((here / "src/game" / f).read_text())
    incs = [str(here / "shim"), str(inc), str(gen)]
    # the table of procedure ids: CMOC cannot initialise from a 32-bit constant, so the id is two words
    gh = (gen / "game.h").read_text()
    ids = {m.group(1): int(m.group(2), 16) for m in re.finditer(r"^#define PROC_(\w+) (0x[0-9A-Fa-f]+)UL", gh, re.M)}
    pt = (gen / "proc_table.c").read_text()
    order = [m.group(1) for m in re.finditer(r"\{PROC_(\w+), \(void \(\*\)\(void\)\)(\w+)\}", pt)]
    fns = dict(re.findall(r"\{PROC_(\w+), \(void \(\*\)\(void\)\)(\w+)\}", pt))
    rows = sorted((ids[k], fns[k]) for k in fns)
    with open(out / "src/proc_table.asm", "w") as w:
        w.write("* generated by tools/mkgame.py: the table of procedure ids (the PC's far addresses of the routines the game stores in\n"
                "* its handler tables), sorted by id; rtl_proc looks an id up. Entry: high word, low word, the routine (its far stub).\n")
        w.write("        SECTION rodata\n        EXPORT  _pool_procs_c\n        EXPORT  _pool_procs_c_count\n")
        for i, f in rows:
            w.write("        IMPORT  _%s\n" % f)
        w.write("_pool_procs_c\n")
        for i, f in rows:
            w.write("        FDB     $%04X,$%04X,_%s\n" % (i >> 16, i & 0xFFFF, f))
        w.write("_pool_procs_c_count FDB %d\n        ENDSECTION\n" % len(rows))
    units = sorted(p.stem for p in gen.glob("*.c") if p.stem not in SKIP_UNITS and p.stem != "proc_table"
                   and p.stem not in ENGINE_UNITS)
    info = {}
    banks = []                                              # {name, objs[], units[]}
    engine_api = []                                         # routines the engine provides, in the order of the units
    for u in ENGINE_UNITS:
        engine_api += [n for n in routine_names((gen / (u + ".c")).read_text()) if not n.startswith("init_")]
    for u, names in ENGINE_ROUTINES.items():
        engine_api += names
    core = []
    for u in units:
        src = gen / (u + ".c")
        if u in ENGINE_ROUTINES or u in CORE_ROUTINES:      # the routines the engine or the core take over are cut out of the unit
            src = out / "src" / (u + ".c")
            src.write_text(strip_routines((gen / (u + ".c")).read_text(), set(ENGINE_ROUTINES.get(u, [])) | set(CORE_ROUTINES.get(u, []))))
        o = obj / (u + ".o")
        compile_c(str(src), str(o), incs)
        inf = objinfo(str(o))
        size = inf["code"] + inf["rodata"]
        if u in CORE_UNITS:
            core.append(u)
            info[u] = inf
            continue
        if size <= BANK_LIMIT:
            banks.append({"name": u, "objs": [str(o)], "size": size, "units": [u]})
            info[u] = inf
            continue
        n = -(-size // BANK_LIMIT)
        while True:
            texts = split_unit(u, src.read_text(), inf["funcs"], n)
            names = ["%s_%d" % (u, k + 1) for k in range(len(texts))]
            objs, infs = [], []
            for nm, t in zip(names, texts):
                (out / "src" / (nm + ".c")).write_text(t)
                o2 = obj / (nm + ".o")
                compile_c(str(out / "src" / (nm + ".c")), str(o2), incs)
                objs.append(str(o2))
                infs.append(objinfo(str(o2)))
            if all(i["code"] + i["rodata"] <= BANK_LIMIT for i in infs) or n >= 6:
                break
            n += 1
        for nm, o2, i2 in zip(names, objs, infs):
            banks.append({"name": nm, "objs": [o2], "size": i2["code"] + i2["rodata"], "units": [u]})
            info[nm] = i2
        print("split %s (%d bytes) into %d parts: %s" % (u, size, len(names), ", ".join(str(i["code"] + i["rodata"]) for i in infs)))
    # the runtime bank
    robjs = []
    rincs = [str(here / "shim"), str(inc), str(here / "src/engine")]
    for stem in RTL_BANK:
        o2 = obj / (stem + ".o")
        compile_c(str(here / "src/game" / (stem + ".c")), str(o2), rincs)
        robjs.append(str(o2))
    rinfo = {"code": 0, "rodata": 0, "exports": set(), "imports": set(), "funcs": {}}
    for o2 in robjs:
        i2 = objinfo(o2)
        rinfo["code"] += i2["code"]
        rinfo["rodata"] += i2["rodata"]
        rinfo["exports"] |= i2["exports"]
        rinfo["imports"] |= i2["imports"]
    rinfo["imports"] -= rinfo["exports"]
    banks.append({"name": "rtl", "objs": robjs, "size": rinfo["code"] + rinfo["rodata"], "units": ["rtl"]})
    info["rtl"] = rinfo
    p2 = run(["lwasm", "--6809", "-fobj", "-o", str(obj / "proc_table.o"), str(out / "src/proc_table.asm")])
    if p2.returncode:
        raise SystemExit("lwasm failed on proc_table.asm: " + p2.stderr[:300])
    info["proc_table"] = objinfo(str(obj / "proc_table.o"))
    core.append("proc_table")
    # who defines what
    defined = {}
    for b in banks:
        for nm in (b["name"],):
            for sym in info[nm]["exports"]:
                defined[sym] = ("bank", b["name"])
    for u in core:
        for sym in info[u]["exports"]:
            defined[sym] = ("core", u)
    # the routines of a bank that anybody outside it names
    entries = {b["name"]: [] for b in banks}
    seen = {}
    for who, inf in info.items():
        for sym in inf["imports"]:
            d = defined.get(sym)
            if d and d[0] == "bank" and d[1] != who:
                if sym not in seen:
                    seen[sym] = d[1]
                    entries[d[1]].append(sym)
    for k in entries:
        entries[k].sort()
    ids = {b["name"]: i + 1 for i, b in enumerate(banks)}
    asm = lambda src, o: run(["lwasm", "--6809", "-fobj", "-I" + str(here / "src/engine"), "-o", str(o), str(src)])
    # the resident stub of every far entry, the entry table at the head of every bank
    with open(out / "src/farstubs.asm", "w") as w:
        w.write("* generated by tools/mkgame.py: the resident stubs of the far entries\n        INCLUDE banks.inc\n        SECTION code\n        IMPORT  __farcall\n")
        for b in banks:
            for i, sym in enumerate(entries[b["name"]]):
                w.write("        FARSTUB %s,%d,%d\n" % (sym[1:], ids[b["name"]], i))
        w.write("        ENDSECTION\n")
    for b in banks:
        with open(out / "src" / (b["name"] + "_entries.asm"), "w") as w:
            w.write("* generated by tools/mkgame.py: the JMP table at the head of bank %d (%s)\n        SECTION entries\n" % (ids[b["name"]], b["name"]))
            for sym in entries[b["name"]]:
                w.write("        IMPORT  %s\n" % sym)
            for sym in entries[b["name"]]:
                w.write("        jmp     %s\n" % sym)
            w.write("        ENDSECTION\n")
    # the routines the engine provides: a stub that stops the program and says which one was asked for, until it is written
    with open(out / "src/engine_stubs.asm", "w") as w:
        w.write("* generated by tools/mkgame.py: the engine's routines, not written yet\n        INCLUDE mailbox.inc\n        SECTION code\n")
        for sym in engine_api:
            w.write("        EXPORT  _%s\n" % sym)
        for i, sym in enumerate(engine_api):
            w.write("_%s ldd     #%d\n        lbra    __unimpl\n" % (sym, i + 1))
        w.write("__unimpl std     MB_BASE+$3C\n        lda     #2\n        sta     MB_STATUS\n        orcc    #$50\n@stop   bra     @stop\n        ENDSECTION\n")
    (out / "engine_names.txt").write_text("\n".join("%d %s" % (i + 1, n) for i, n in enumerate(engine_api)) + "\n")
    # the init parts of the replaced units do nothing here (the engine sets itself up); res08's is written by hand
    with open(out / "src/init_stubs.asm", "w") as w:
        w.write("* generated by tools/mkgame.py: the initialisation parts of the units the engine replaced\n        SECTION code\n")
        for u in ENGINE_UNITS:
            if u != "res08":                                # the init of res08 is src/game/platform.c
                w.write("        EXPORT  _init_%s\n_init_%s rts\n" % (u.upper(), u.upper()))
        w.write("        ENDSECTION\n")
    # helpers of CMOC's library that banks use: pulled into the core, which the banks then call by address
    stubbed = {"_" + n for n in engine_api} | {sym for v in entries.values() for sym in v}
    lib = set()
    for who, inf in info.items():
        for sym in inf["imports"]:
            if sym not in defined and sym not in stubbed and not sym.startswith("_init_"):
                lib.add(sym)
    lib = sorted(lib - {"_main"})
    with open(out / "src/libpull.asm", "w") as w:
        w.write("* generated by tools/mkgame.py: the library helpers the banks need, referenced so that the core carries them\n        SECTION code\n")
        for sym in lib:
            w.write("        IMPORT  %s\n" % sym)
        w.write("libpull\n")
        for sym in lib:
            w.write("        FDB     %s\n" % sym)
        w.write("        ENDSECTION\n")
    objs_asm = []
    for nm in ("farstubs", "engine_stubs", "init_stubs", "libpull"):
        r = asm(out / "src" / (nm + ".asm"), obj / (nm + ".o"))
        if r.returncode:
            raise SystemExit("lwasm %s: %s" % (nm, r.stderr[:400]))
    for b in banks:
        r = asm(out / "src" / (b["name"] + "_entries.asm"), obj / (b["name"] + "_entries.o"))
        if r.returncode:
            raise SystemExit("lwasm %s: %s" % (b["name"], r.stderr[:400]))
    (out / "banks.json").write_text(json.dumps({
        "banks": [{"name": b["name"], "id": ids[b["name"]], "objs": b["objs"], "entries": entries[b["name"]], "size": b["size"]} for b in banks],
        "core": core, "engine_api": engine_api}, indent=1))
    tot = sum(b["size"] for b in banks)
    print("%d banks (%d bytes), core units %s; %d far entries; %d engine routines" %
          (len(banks), tot, " ".join(core), sum(len(v) for v in entries.values()), len(engine_api)))
    for b in banks:
        print("  %2d %-10s %6d bytes  %3d entries" % (ids[b["name"]], b["name"], b["size"], len(entries[b["name"]])))
    if "--link" in argv:
        return link_all(out, here, banks, ids, info, core, entries)
    return 0


def link_all(out, here, banks, ids, info, core, entries):
    """core.bin and the bank images. The core's undefined symbols that are not written yet become stubs that stop the program
    (build/game/missing.txt lists them: that list is the work left)."""
    obj, src = out / "obj", out / "src"
    eobj = here / "build/obj"                                # the engine objects the Makefile builds
    base = [eobj / n for n in ("boot.o", "mailbox.o", "mmu.o", "farcall.o", "nobanks.o", "irq.o")]
    (obj / "rtl").mkdir(exist_ok=True)
    for stale in (obj / "rtl").glob("*.o"):
        stale.unlink()
    incs = [str(here / "shim"), str(out / "inc"), str(here / "src/engine")]
    for c in sorted((here / "src/game").glob("*.c")):          # the runtime and the platform layer of the CoCo
        if c.stem in RTL_BANK:
            continue                                            # in the runtime bank (below)
        compile_c(str(c), str(obj / "rtl" / (c.stem + ".o")), incs)
    for a in sorted((here / "src/game").glob("*.asm")):
        r = run(["lwasm", "--6809", "-fobj", "-I" + str(here / "src/engine"), "-o", str(obj / "rtl" / (a.stem + ".o")), str(a)])
        if r.returncode:
            raise SystemExit("lwasm %s: %s" % (a, r.stderr[:400]))
    rtl = sorted((obj / "rtl").glob("*.o"))
    libs = ["-L/usr/local/share/cmoc/lib", "-lcmoc-crt-void", "-lcmoc-std-void"]
    cobjs = [str(o) for o in base] + [str(obj / (n + ".o")) for n in ("farstubs", "engine_stubs", "init_stubs", "libpull")] + \
            [str(obj / (u + ".o")) for u in core] + [str(o) for o in rtl]
    missing = []
    for attempt in range(4):
        extra = []
        if missing:
            with open(src / "missing.asm", "w") as w:
                w.write("* generated by tools/mkgame.py: symbols nothing defines yet\n        INCLUDE mailbox.inc\n        SECTION code\n")
                for i, sym in enumerate(missing):
                    w.write("        EXPORT  %s\n%s ldd     #%d\n        lbra    __missing\n" % (sym, sym, 0x100 + i))
                w.write("__missing std   MB_BASE+$3C\n        lda     #2\n        sta     MB_STATUS\n        orcc    #$50\n@stop   bra     @stop\n        ENDSECTION\n")
            r = run(["lwasm", "--6809", "-fobj", "-I" + str(here / "src/engine"), "-o", str(obj / "missing.o"), str(src / "missing.asm")])
            if r.returncode:
                raise SystemExit("lwasm missing: " + r.stderr[:400])
            extra = [str(obj / "missing.o")]
            (out / "missing.txt").write_text("\n".join("%d %s" % (0x100 + i, m) for i, m in enumerate(missing)) + "\n")
        r = run(["lwlink", "--format=decb", "--script=" + str(here / "src/engine/core.link"), "--map=" + str(out / "core.map"),
                 "-o", str(out / "core.bin")] + cobjs + extra + libs)
        if r.returncode == 0:
            break
        und = sorted(set(re.findall(r"External symbol (\S+) not found", r.stderr + r.stdout)))
        if not und:
            raise SystemExit("lwlink core: " + (r.stderr + r.stdout)[:800])
        missing = sorted(set(missing) | set(und))
    else:
        raise SystemExit("lwlink core: still failing: " + (r.stderr + r.stdout)[:800])
    top = max((int(m.group(2), 16) + int(m.group(3), 16) for m in
               re.finditer(r"^Section: (\S+) \((.*?)\) load at ([0-9A-Fa-f]+), length ([0-9A-Fa-f]+)", (out / "core.map").read_text(), re.M)
               if False), default=0)
    sec = [(m.group(1), int(m.group(3), 16), int(m.group(4), 16)) for m in
           re.finditer(r"^Section: (\S+) \((.*?)\) load at ([0-9A-Fa-f]+), length ([0-9A-Fa-f]+)", (out / "core.map").read_text(), re.M)]
    end = max(a + n for _, a, n in sec)
    print("core: ends at $%04X (%d bytes from $2000); %d symbols still missing" % (end, end - 0x2000, len(missing)))
    if end > 0x5200:
        raise SystemExit("the core ends at $%04X, past the heap tables at $5200 (src/game/coco_map.h)" % end)
    for m in missing:
        print("   missing", m)
    # the banks
    sym = here / "tools/symexport.py"
    for b in banks:
        n = b["name"]
        objs = [str(obj / (n + "_entries.o"))] + b["objs"]
        r = run(["python3", str(sym), str(out / "core.map"), str(src / (n + "_syms.asm"))] + objs)
        if r.returncode:
            raise SystemExit("symexport %s: %s" % (n, r.stderr[:600]))
        r = run(["lwasm", "--6809", "-fobj", "-o", str(obj / (n + "_syms.o")), str(src / (n + "_syms.asm"))])
        if r.returncode:
            raise SystemExit("lwasm syms %s: %s" % (n, r.stderr[:300]))
        r = run(["lwlink", "--format=raw", "--script=" + str(here / "src/engine/bank.link"), "--map=" + str(out / (n + ".map")),
                 "-o", str(out / (n + ".raw"))] + objs + [str(obj / (n + "_syms.o"))])
        if r.returncode:
            raise SystemExit("lwlink bank %s: %s" % (n, (r.stderr + r.stdout)[:600]))
        r = run(["python3", str(here / "tools/bankcheck.py"), str(out / (n + ".map"))])
        if r.returncode:
            raise SystemExit(r.stderr or r.stdout)
    print("%d banks linked" % len(banks))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
