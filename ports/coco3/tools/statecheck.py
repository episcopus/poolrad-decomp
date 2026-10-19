#!/usr/bin/env python3
"""statecheck.py SESSION PREFIX: is the state the game on the CoCo ended the session with the one the original ended with?
Two comparisons, both against the C translation on the host, which the replays proved equal to the original (make c-golden):

  files    what the game wrote (the save area of the image: PREFIX.saves from lua/watch.lua) against what the host's replay wrote
           (poolrad_replay --save). A character record's words are big endian here and little endian there, and its pointers are
           addresses of two different heaps: words are turned round, pointers are not compared.
  dgroup   the data segment at the end of the session, global by global: the host's dump (poolrad_replay --snap) against the
           bytes of the CoCo's native area (PREFIX.core) and paged globals (PREFIX.pages), found through the layout table of the
           build (build/gen/vm/vmlayout.c) and put back in the PC's byte order (the swap lists of globals.txt). Globals that
           cannot be equal (pointers into the heap, the clock, anything the keyboard read touches) are listed in
           data/state_ignore.txt with the reason; every other difference is reported.

Exit 1 unless the files are equal and no unexplained global differs."""
import os
import re
import shutil
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "../../.."))
COCO = os.path.join(HERE, "..")
SIZES = {"u8": 1, "s8": 1, "u16": 2, "s16": 2, "u32": 4, "s32": 4, "farptr": 4}


def struct_fields(h, name):
    """[(offset, width, is_pointer)] of the flat typedef struct `name` in game.h text h"""
    m = re.search(r"typedef struct %s \{\n(.*?)\n\} %s;" % (name, name), h, re.S)
    fields, off = [], 0
    ptr_types = set(re.findall(r"typedef (?:farptr|PMenuLine|PItem|PCharacter|PCombatant) (\w+);", h)) | {"farptr", "PItem", "PCharacter", "PCombatant"}
    for ln in m.group(1).split("\n"):
        mm = re.match(r"\s*(\w+) (\w+)((?:\[\d+\])*);", ln)
        if not mm:
            raise SystemExit("statecheck: cannot read the field %r of %s" % (ln, name))
        t, _, dims = mm.groups()
        n = 1
        for d in re.findall(r"\[(\d+)\]", dims):
            n *= int(d)
        w = SIZES.get(t, 4 if t in ptr_types else None)
        if w is None:
            raise SystemExit("statecheck: type %s of a field of %s" % (t, name))
        for i in range(n):
            fields.append((off, w, t in ptr_types))
            off += w
    return fields, off


def host_state(session, outdir):
    rpl = os.path.join(ROOT, "build/c/replay", session + ".rpl")
    exe = os.path.join(ROOT, "build/cmake/poolrad_replay")
    if not os.path.exists(exe) or not os.path.exists(rpl):
        raise SystemExit("statecheck: build the host first (make host, make c-golden)")
    save = os.path.join(outdir, "save")
    shutil.rmtree(outdir, ignore_errors=True)
    os.makedirs(outdir)
    p = subprocess.run([exe, "--data", os.path.join(ROOT, "poolrad"), "--save", save, "--dump", os.path.join(outdir, "x"),
                        "--snap", os.environ.get("STATE_SNAP") or str(SNAP.get(session, 0)), rpl], capture_output=True, text=True)
    if "ok:" not in p.stdout + p.stderr:
        raise SystemExit("statecheck: the host replay failed:\n" + p.stdout + p.stderr)
    return save, os.path.join(outdir, "x-snap.dgroup")


SNAP = {"create-character": 616000, "walk-explore": 1580000, "camp-save": 1400000, "camp-rest-combat": 3865800, "parley-combat": 7394000,
        "shop-buy": 1547290, "temple-cast": 1413560, "battle-aftermath": 7570950, "combat-spells": 4901940, "temple-heal": 9104300,
        "camp-magic": 1605180, "council-guards": 1033490, "character-menu": 2838740, "character-view": 1724570, "camp-cast": 1367960}                # a read in the last idle stretch of the session (the main menu again)


def save_files(prefix):
    img = open(os.path.join(COCO, "build/game/pool.img"), "rb").read()
    save_lsn = struct.unpack(">L", img[16:20])[0]
    nsec = struct.unpack(">H", img[20:22])[0]
    area = bytearray(img[save_lsn * 256:(save_lsn + nsec) * 256])
    sv = prefix + ".saves"
    if os.path.exists(sv):
        d = open(sv, "rb").read()
        for i in range(0, len(d), 260):
            lsn = struct.unpack(">L", d[i:i + 4])[0]
            if save_lsn <= lsn < save_lsn + nsec:
                area[(lsn - save_lsn) * 256:(lsn - save_lsn + 1) * 256] = d[i + 4:i + 260]
    files = {}
    if area[0:4] == b"PSAV":
        for i in range(127):
            e = area[16 + 16 * i:32 + 16 * i]
            if e[0]:
                name = e[:8].decode("ascii").strip() + "." + e[8:11].decode("ascii").strip()
                start, size = struct.unpack(">H", e[11:13])[0] * 256, struct.unpack(">H", e[14:16])[0]
                files[name] = bytes(area[start:start + size])
    return files


def check_files(prefix, hostsave):
    """The files the session wrote against the host's. The game writes them in the PC's byte order (BlockWrite turns the words round
    before and after, tools/c p2c_builtin.py), so they are compared byte for byte except the pointers of a record (addresses of two
    different heaps)."""
    h = open(os.path.join(ROOT, "c/game/game.h")).read()
    kinds = {}
    for ext, t in ((".SAV", "TCharacter"), (".CHA", "TCharacter"), (".ITM", "TMenuLine"), (".SPC", "TAffect")):
        kinds[ext] = struct_fields(h, t)
    ours = save_files(prefix)
    bad = 0
    ref = {}
    for dp, _, fs in os.walk(hostsave):
        for f in fs:
            ref[f.upper()] = open(os.path.join(dp, f), "rb").read()
    shipped = {}
    sd = os.path.join(ROOT, "poolrad/SAVE")
    if os.path.isdir(sd):
        for f in os.listdir(sd):
            shipped[f.upper()] = open(os.path.join(sd, f), "rb").read()
    for name in sorted(set(ours) | set(ref)):
        a, b = ours.get(name), ref.get(name)
        if a is not None and a == shipped.get(name) and (b is None or b == a):
            continue                                        # a file of the shipped game the session did not change
        if a is None or b is None:
            print("  file %-12s %s" % (name, "missing on the CoCo" if a is None else "not written by the original"))
            bad += 1
            continue
        ext = os.path.splitext(name)[1]
        if ext in kinds and len(a) == len(b):
            fields, size = kinds[ext]
            diff = []
            for r in range(0, len(a) - size + 1, size):
                for off, w, isptr in fields:
                    if not isptr and a[r + off:r + off + w] != b[r + off:r + off + w]:
                        diff.append(r + off)
            ok = not diff
            print("  file %-12s %4d bytes, %d record(s): %s" % (name, len(a), len(a) // size, "equal (pointers left out)" if ok else "differs at %s" % diff[:6]))
        else:
            ok = a == b
            print("  file %-12s %d bytes: %s" % (name, len(a), "equal" if ok else "DIFFERS (%d against %d bytes)" % (len(a), len(b))))
        bad += not ok
    return bad


def load_ignore():
    ign = {}
    p = os.path.join(COCO, "data/state_ignore.txt")
    if os.path.exists(p):
        for ln in open(p):
            ln = ln.strip()
            if ln and not ln.startswith("#"):
                n, _, why = ln.partition(" ")
                ign[n] = why.strip()
    return ign


def check_dgroup(prefix, dump):
    pc = open(dump, "rb").read()
    core = open(prefix + ".core", "rb").read()          # logical $2000.. of the CoCo
    pages = open(prefix + ".pages", "rb").read()        # the four pages of paged DGROUP
    gen = os.path.join(COCO, "build/gen/vm")
    clusters = []
    for m in re.finditer(r"\{0x([0-9A-F]+), (\d+), '(\w)', \d+, 0x([0-9A-F]+)\}", open(gen + "/vmlayout.c").read()):
        clusters.append((int(m.group(1), 16), int(m.group(2)), m.group(3), int(m.group(4), 16)))
    clusters.sort()

    def coco_bytes(off, n):
        for lo, sz, cls, new in clusters:
            if lo <= off and off + n <= lo + sz:
                a = new + off - lo
                if cls == "N":
                    return core[a - 0x2000:a - 0x2000 + n]
                page, o = (a >> 13) - 4, a & 0x1FFF
                return pages[page * 0x2000 + o:page * 0x2000 + o + n]
        return None
    left = set()                                             # the values mkvm.py left in the PC's order
    for ln in open(gen + "/unswapped.txt"):
        a, w = ln.split()
        left.add((int(a, 16), int(w)))
    ign = load_ignore()
    rows = []                                                # (offset, size, name, swap spec)
    for ln in open(gen + "/globals.txt"):
        f = ln.split()
        if len(f) >= 5:
            rows.append((int(f[0], 16), int(f[1]), f[2], f[4]))
    isstore = lambda n: re.match(r"(Raw|ds)[0-9A-Fa-f]{4}$", n) is not None
    stores = [(o, s, n) for o, s, n, _ in rows if isstore(n)]
    # what is compared: the storage arrays of the initialised data (a typed view of them may be declared longer than its
    # storage, so the views are not compared one by one), and every global that lies in no such array
    units = list(stores)
    for o, s, n, _ in rows:
        if not isstore(n) and not any(so <= o and o + s <= so + ss for so, ss, _ in stores):
            units.append((o, s, n))
    spec = {}
    for o, s, n, sw in rows:
        if sw != "-":
            for item in sw.split(","):
                io, w, c = (int(x) for x in item.split(":"))
                for i in range(c):
                    spec[(o + io + i * w, w)] = True
    equal, unplaced, diffs, ignored, open_ = 0, 0, [], 0, 0
    seen = set()
    for off, size, name in sorted(units):
        if (off, size) in seen:
            continue
        seen.add((off, size))
        b = coco_bytes(off, size)
        if b is None:
            unplaced += 1
            continue
        b = bytearray(b)
        for (at, w) in spec:                                 # a value counts when it is the PC's either way round: the
            if off <= at and at + w <= off + size:           # words written at run time are big endian, bytes written over
                x = bytes(b[at - off:at + w - off])           # a word view stay as they are (the layout's aliases, mkvm.py)
                if x[::-1] == pc[at:at + w] and (at, w) not in left:
                    b[at - off:at - off + w] = x[::-1]
        if bytes(b) == pc[off:off + size]:
            equal += 1
        elif name in ign and not ign[name].startswith("OPEN:"):
            ignored += 1
        elif name in ign:
            open_ += 1
            diffs.append((off, size, name + "  (" + ign[name] + ")"))
        else:
            where = [i for i in range(size) if b[i] != pc[off + i]]
            if os.environ.get("STATE_SHOW"):                        # debugging: the bytes on both sides
                print("    %s host %s" % (name, pc[off:off + 64].hex()))
                print("    %s coco %s" % (name, bytes(b[:64]).hex()))
            diffs.append((off, size, "%s  (differs at +%s%s)" % (name, ",".join("%X" % i for i in where[:12]), "..." if len(where) > 12 else "")))
    print("  dgroup: %d places equal, %d differ for a reason in data/state_ignore.txt (representation, platform), %d differ and are open or unexplained, %d not on the CoCo (the engine's)" % (
        equal, ignored, len(diffs), unplaced))
    for off, size, name in diffs:
        print("    DS:%04X %4d %s" % (off, size, name))
    return len(diffs)


def check_party(session, prefix):
    """The party list: the records of the characters (and, in a fight, the monsters) the party list holds, one by one: every one byte field and every
    word (put in the PC's order) of the CoCo's records against the host's, at the same read (poolrad_replay POOL_PARTYHEX). The records live in the
    heap, which the dgroup check does not see; a combat that goes another way shows here first (step 8.7b: hit points of the party)."""
    exe = os.path.join(ROOT, "build/cmake/poolrad_replay")
    rpl = os.path.join(ROOT, "build/c/replay", session + ".rpl")
    env = dict(os.environ, POOL_PARTYHEX="1", POOL_PARTYLOG=os.environ.get("STATE_SNAP") or str(SNAP.get(session, 0)))
    p = subprocess.run([exe, "--data", os.path.join(ROOT, "poolrad"), "--save", os.path.join(COCO, "build/run/host-" + session + "-party"), rpl],
                       capture_output=True, text=True, env=env)
    host = [bytes.fromhex(l.strip()[4:]) for l in p.stderr.split("\n") if l.startswith("hex:")]
    if not host:
        print("  party: the host printed no records (build the host first)")
        return 1
    h = open(os.path.join(ROOT, "c/game/game.h")).read()
    fields, size = struct_fields(h, "TCharacter")
    core = open(prefix + ".core", "rb").read()
    gen = os.path.join(COCO, "build/gen/vm")
    clusters = [(int(m.group(1), 16), int(m.group(2)), m.group(3), int(m.group(4), 16))
                for m in re.finditer(r"\{0x([0-9A-F]+), (\d+), '(\w)', \d+, 0x([0-9A-F]+)\}", open(gen + "/vmlayout.c").read())]
    head = None
    for ln in open(gen + "/globals.txt"):
        f = ln.split()
        if len(f) >= 3 and f[2] == "PartyListHead":
            head = int(f[0], 16)
    a = next(new + head - lo for lo, sz, c, new in clusters if lo <= head < lo + sz and c == "N")
    ptr = struct.unpack(">I", core[a - 0x2000:a - 0x2000 + 4])[0] & 0xFFFF
    coco = []
    while ptr and len(coco) < 30:
        r = core[ptr - 0x2000:ptr - 0x2000 + 0x120]
        coco.append(r)
        nxt = struct.unpack(">I", r[0x104:0x108])[0]
        ptr = nxt & 0xFFFF if nxt else 0
    bad = 0
    if len(coco) != len(host):
        print("  party: %d records on the CoCo, %d on the host" % (len(coco), len(host)))
        bad += 1
    names = []
    for k, (c, hh) in enumerate(zip(coco, host)):
        diffs = []
        for off, w, isptr in fields:
            if isptr or off + w > 0x120:
                continue
            cv, hv = c[off:off + w], hh[off:off + w]
            if cv[::-1] != hv if w > 1 else cv != hv:
                diffs.append("+%03X" % off)
        nm = hh[1:1 + hh[0]].decode("latin1")
        if diffs:
            bad += 1
            print("  party %2d %-16s differs at %s" % (k, nm, " ".join(diffs[:12])))
        names.append(nm)
    print("  party: %d records, %d differ" % (len(host), bad))
    return 1 if bad else 0


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    session, prefix = sys.argv[1], sys.argv[2]
    if session not in SNAP:
        print("%s: no state comparison for this session (it ends on a screen the clock decides)" % session)
        return 0
    hostsave, dump = host_state(session, os.path.join(COCO, "build/run/host-" + session))
    print("%s: state" % session)
    bad = check_files(prefix, hostsave)
    bad += check_dgroup(prefix, dump)
    bad += check_party(session, prefix)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
