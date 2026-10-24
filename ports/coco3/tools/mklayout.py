#!/usr/bin/env python3
"""mklayout.py: which entry of the image goes on which floppy disk (step 8.10), from what the sessions read.

The image (tools/mkimage.py) is a run of sectors; the floppy medium cuts it into disks (tools/mkimage.py --layout). The order decides how
often the player swaps: this tool takes the storage traces of the sessions (MB_SECLOG runs on an image without shared blocks, one entry
to a sector range: build/trace/run-traces.sh), the model of that image (mkimage.py --model) and
  * simulates the drives the engine has (src/engine/flop.c): disk 1 stays in drive 0, the others take turns in the least recently used
    of the remaining drives; every disk that no drive holds is a swap (the prompt "INSERT DISK n"),
  * writes a layout: build/floppy/layout.json  {"disks": [{"keys": [[file, id], ...]}, ...], "save": n}
Subcommands:  eval LAYOUT   swaps per session of a layout        naive   the alphabetical layout (what the PC's disks looked like)
              make          the optimised layout (--out)         areas   what a tileset family is made of

Entries that no session reads (82 % of the data bytes) are placed by what the game's files say: the eight tilesets (PICn, 8X8Dn, BODYn,
HEADn, SPRITn, CPICn, WALLDEFn, GEOn, ECLn, MONnCHA, MONnITM, MONnSPC, ITEMn, FINAL5, ...) belong to one area each, and an area is played
for hours on its disk while the rest of the game waits."""
import argparse
import bisect
import collections
import json
import re
import sys
from pathlib import Path

DISK_SECTORS = 612
SAVE_SECTORS = 512
IDX_SECTORS_PAD = 0

AREA_RE = [re.compile(p) for p in (r"^(?:PIC|8X8D|BODY|HEAD|SPRIT|CPIC|WALLDEF|GEO|ECL|ITEM)(\d)$", r"^MON(\d)(?:CHA|ITM|SPC)$")]


def area_of(name):
    """the tileset family a file belongs to (1..8), 0 for what every area uses"""
    for r in AREA_RE:
        m = r.match(name)
        if m:
            return int(m.group(1))
    return 0


class Model:
    """the entries of the image the traces were made on"""

    def __init__(self, path, sizes=None, scheme="none"):
        d = json.loads(Path(path).read_text())
        self.files = d["files"]
        self.data_off = d["data_off"]
        self.pool_bin_sectors = d["pool_bin_sectors"]
        self.ents = d["entries"]
        for i, e in enumerate(self.ents):
            e["i"] = i
            e["area"] = area_of(e["file"])
            e["name"] = "%s/%d" % (e["file"], e["id"])
            e["osize"] = e["size"]                       # the size in the image the traces were made on (what maps a sector to an entry)
            if sizes:                                    # an experiment: the bytes each entry would take stored another way (tools/compexp.py)
                e["size"] = sizes["%s/%d" % (e["file"], e["id"])][scheme]
        self.by_off = sorted(self.ents, key=lambda e: e["off"])
        self.starts = [e["off"] for e in self.by_off]
        self.save_lsn = None

    def entries_at(self, lsn, count):
        lo, hi = lsn * 256, (lsn + count) * 256
        out = []
        i = max(bisect.bisect_right(self.starts, lo) - 1, 0)
        while i < len(self.by_off) and self.by_off[i]["off"] < hi:
            e = self.by_off[i]
            if e["off"] + max(e["osize"], 1) > lo:
                out.append(e["i"])
            i += 1
        return out


def parse_trace(path, model, save_lsn):
    """the events of a run in order: entry numbers, -1 for the save area (reads and writes); the index and the first sectors are
    disk 1's anyway and left out"""
    seq = []
    for line in open(path, errors="replace"):
        if not line.startswith("sec cmd="):
            continue
        m = re.match(r"sec cmd=(\d+) lsn=(\d+) count=(\d+)", line)
        if not m:
            continue
        cmd, lsn, cnt = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if lsn >= save_lsn:
            ev = [-1]
        elif lsn * 256 < model.data_off:
            continue
        else:
            ev = model.entries_at(lsn, cnt)
        for x in ev:
            if not seq or seq[-1] != x:
                seq.append(x)
    return seq


def simulate(disks_seq, ndrv=2, start=(1,)):
    """swaps of a run: disks_seq the disk number (0 = disk 1, the boot disk) of every access in order. Disk 0 stays in drive 0 when
    there are two drives or more. Returns the number of prompts."""
    drives = [0] + [None] * (ndrv - 1) if ndrv > 1 else [None]
    use = [0] * ndrv
    swaps = 0
    t = 0
    for d in disks_seq:
        t += 1
        if d in drives:
            use[drives.index(d)] = t
            continue
        swaps += 1
        if ndrv == 1:
            v = 0
        elif d == 0:
            v = 0
        else:
            v = min(range(1, ndrv), key=lambda i: use[i])
        drives[v] = d
        use[v] = t
    return swaps


def bytes_of(model, idxs):
    """the bytes a disk takes for these entries in this order (mkimage's rules: a raw object starts on a sector, a block with the content of an earlier one on the disk is stored once)"""
    n = 0
    seen = set()
    for i in idxs:
        e = model.ents[i]
        if e["kind"] == 1 and n % 256:
            n += 256 - n % 256
        if e["key"] is not None:
            if e["key"] in seen:
                continue
            seen.add(e["key"])
        n += e["size"]
    return n


def disk_capacity(model, d):
    cap = DISK_SECTORS - (model.pool_bin_sectors if d == 0 else 0)
    return cap * 256


# -------------------------------------------------------------------------------------------------- layouts

def mandatory(model):
    return [e["i"] for e in model.ents if e["file"] in ("CORE", "DGROUP")]


def naive_layout(model):
    """the order of the image (alphabetical by file), the boot objects first, disks filled one after the other, the saves on a disk of their own"""
    boot = mandatory(model)
    rest = [e["i"] for e in model.ents if e["i"] not in set(boot)]
    disks = [list(boot)]
    for i in rest:
        d = disks[-1]
        d.append(i)
        used = bytes_of(model, d) + (model.data_off if len(disks) == 1 else 0)
        if used > disk_capacity(model, len(disks) - 1):
            d.pop()
            disks.append([i])
    return disks


def to_layout(model, disks, save_disk):
    return {"disks": [{"keys": [[model.ents[i]["file"], model.ents[i]["id"]] for i in d]} for d in disks], "save": save_disk}


def disk_map(disks):
    m = {}
    for di, d in enumerate(disks):
        for i in d:
            m[i] = di
    return m


def score(model, runs, disks, save_disk, ndrv=2):
    """swaps of every run for the layout: {name: swaps}"""
    m = disk_map(disks)
    out = {}
    for name, seq in runs.items():
        out[name] = simulate([save_disk if x < 0 else m[x] for x in seq], ndrv)
    return out


def load_runs(model, tracedir, save_lsn):
    runs = {}
    for p in sorted(Path(tracedir).glob("*.out")):
        seq = parse_trace(p, model, save_lsn)
        if seq:
            runs[p.stem] = seq
    return runs


# -------------------------------------------------------------------------------------------------- the optimiser

class Packing:
    """entries on disks, with the bytes each disk takes (a block with the content of one already on the disk costs nothing)"""

    def __init__(self, model, ndisks, save_disk):
        self.model = model
        self.n = ndisks
        self.save_disk = save_disk
        self.disk = {}                                   # entry -> disk
        self.used = [0] * ndisks
        self.kc = [collections.Counter() for _ in range(ndisks)]
        self.cap = [disk_capacity(model, d) for d in range(ndisks)]
        self.cap[0] -= model.data_off
        self.cap[save_disk] -= SAVE_SECTORS * 256

    def cost(self, i):
        e = self.model.ents[i]
        return e["size"] + (255 if e["kind"] == 1 else 0)

    def room(self, d, i):
        e = self.model.ents[i]
        if e["key"] is not None and self.kc[d][e["key"]] > 0:
            return self.cap[d] - self.used[d]
        return self.cap[d] - self.used[d] - self.cost(i)

    def add(self, i, d):
        e = self.model.ents[i]
        if e["key"] is None or self.kc[d][e["key"]] == 0:
            self.used[d] += self.cost(i)
        if e["key"] is not None:
            self.kc[d][e["key"]] += 1
        self.disk[i] = d

    def remove(self, i):
        d = self.disk.pop(i)
        e = self.model.ents[i]
        if e["key"] is not None:
            self.kc[d][e["key"]] -= 1
        if e["key"] is None or self.kc[d][e["key"]] == 0:
            self.used[d] -= self.cost(i)
        return d

    def fits(self, i, d):
        return self.room(d, i) >= 0


def runs_cost(runs, weights, dm, save_disk, ndrv):
    t = 0.0
    for name, seq in runs.items():
        t += weights.get(name, 1.0) * simulate([save_disk if x < 0 else dm[x] for x in seq], ndrv)
    return t


def area_runs(model):
    """a visit of each area as a run: its entries in file order (what a player of that area asks of the disks, apart from the code)"""
    out = {}
    for a in range(1, 9):
        out["area%d" % a] = [e["i"] for e in model.ents if e["area"] == a]
    return out


def optimise(model, runs, ndrv=2, iters=60000, area_weight=0.15, seed=1, verbose=True, drive_mix=((2, 1.0), (1, 0.2), (3, 0.2)), extra=1):
    """simulated annealing over the disk of every entry that a run reads; the entries nobody reads keep their area together and give way
    when a disk is full. The cost of a layout is the swaps of every run for the drive counts of `drive_mix` (weighted), the area runs at
    area_weight."""
    import math
    import random
    rng = random.Random(seed)
    mset = mandatory_set(model)
    seen = collections.Counter()
    for r in runs.values():
        for x in set(r):
            if x >= 0:
                seen[x] += 1
    kinds = {}
    for e in model.ents:
        kinds[e["key"] if e["key"] else e["i"]] = e["size"]
    cap = DISK_SECTORS * 256
    ndisks = int(sum(kinds.values()) // cap) + 2 + extra
    sd = ndisks - 1
    pk = Packing(model, ndisks, sd)
    order = mandatory(model)
    hot = sorted(seen, key=lambda i: (-seen[i], model.ents[i]["area"], i))
    order += [i for i in hot if i not in mset]
    keyfirst = {}                                          # the cold entries by the content they share (a block the eight tileset files all hold is stored once on a disk), then by area
    for e in model.ents:
        if e["key"] is not None:
            keyfirst.setdefault(e["key"], (e["area"], e["file"], e["id"]))
    order += [e["i"] for e in sorted(model.ents, key=lambda e: (keyfirst[e["key"]] if e["key"] is not None else (e["area"], e["file"], e["id"]), e["file"], e["id"])) if e["i"] not in seen and e["i"] not in mset]
    d = 0
    for i in order:
        while d < ndisks - 2 and not pk.fits(i, d):
            d += 1
        if not pk.fits(i, d):
            raise SystemExit("mklayout: the entries do not fit on %d disks" % (ndisks - 1))
        pk.add(i, d)
    allruns = dict(runs)
    arun = area_runs(model)
    allruns.update(arun)
    weight = {k: (area_weight if k in arun else 1.0) for k in allruns}
    which = collections.defaultdict(list)                 # entry -> the runs that read it
    for k, r in allruns.items():
        for x in set(r):
            if x >= 0:
                which[x].append(k)

    def run_cost(k, dm):
        seq = [sd if x < 0 else dm[x] for x in allruns[k]]
        if k in arun:
            return weight[k] * simulate(seq, 2)
        return weight[k] * sum(w * simulate(seq, n) for n, w in drive_mix)

    costs = {k: run_cost(k, pk.disk) for k in allruns}
    total = sum(costs.values())
    start = total
    movable = [i for i in seen if i not in mset]
    cold_by_disk = collections.defaultdict(set)
    for i, dd in pk.disk.items():
        if i not in seen and i not in mset:
            cold_by_disk[dd].add(i)
    t0, t1 = 3.0, 0.05
    best, best_disk = total, dict(pk.disk)
    for it in range(iters):
        temp = t0 * (t1 / t0) ** (it / iters)
        i = rng.choice(movable)
        d0 = pk.disk[i]
        d = rng.randrange(ndisks - 1) if rng.random() < 0.97 else sd
        if d == d0 or (d == sd and False):
            continue
        evicted = None
        if not pk.fits(i, d):
            need = -pk.room(d, i)
            cands = [j for j in cold_by_disk[d] if pk.cost(j) >= need]
            if not cands:
                continue
            j = min(cands, key=pk.cost)
            spare = max((x for x in range(ndisks) if x != d), key=lambda x: pk.cap[x] - pk.used[x])
            if not pk.fits(j, spare):
                continue
            evicted = (j, spare)
            pk.remove(j)
            pk.add(j, spare)
        pk.remove(i)
        pk.add(i, d)
        touched = which[i]
        new = {k: run_cost(k, pk.disk) for k in touched}
        delta = sum(new[k] - costs[k] for k in touched)
        if delta <= 0 or rng.random() < math.exp(-delta / temp):
            costs.update(new)
            total += delta
            if evicted:
                cold_by_disk[d].discard(evicted[0])
                cold_by_disk[evicted[1]].add(evicted[0])
            if total < best - 1e-9:
                best, best_disk = total, dict(pk.disk)
        else:
            pk.remove(i)
            pk.add(i, d0)
            if evicted:
                pk.remove(evicted[0])
                pk.add(evicted[0], d)
        if verbose and it % 10000 == 0:
            print("optimise: %6d  T %.2f  cost %.1f  best %.1f" % (it, temp, total, best))
    if verbose:
        print("optimise: %.1f -> %.1f" % (start, best))
    dsk = collections.defaultdict(list)
    for i in order:
        dsk[best_disk[i]].append(i)
    keep = [x for x in range(ndisks) if dsk[x] or x == sd]
    disks = [dsk[x] for x in keep]
    return disks, len(disks) - 1


_mand = {}


def mandatory_set(model):
    if id(model) not in _mand:
        _mand[id(model)] = set(mandatory(model))
    return _mand[id(model)]


def save_runs(model, runs, path):
    """the runs as entry names (data/floppy_runs.json): the profile a layout is made from, which does not depend on where the entries lie in an image"""
    out = {k: ["SAVE" if x < 0 else model.ents[x]["name"] for x in v] for k, v in runs.items()}
    Path(path).write_text(json.dumps({"about": "storage accesses of the sessions by entry (file/id), in order: tools/mklayout.py profile", "runs": out}, separators=(",", ":")))


def load_runs_json(model, path):
    by = {e["name"]: e["i"] for e in model.ents}
    runs, missing = {}, set()
    for k, v in json.loads(Path(path).read_text())["runs"].items():
        seq = []
        for n in v:
            if n == "SAVE":
                seq.append(-1)
            elif n in by:
                seq.append(by[n])
            else:
                missing.add(n)
        runs[k] = seq
    if missing:
        print("mklayout: %d entries of %s are not in this image (ignored)" % (len(missing), path), file=sys.stderr)
    return runs


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["naive", "eval", "make", "areas", "stats", "xval", "profile", "cost"])
    ap.add_argument("--runs", default="data/floppy_runs.json", help="the profile (entry names in the order the sessions read them); the traces of --traces when it does not exist")
    ap.add_argument("--sizes", help="compexp.py's sizes: the entries take those bytes (an experiment)")
    ap.add_argument("--scheme", default="none", help="which of the sizes: none, zx0 (the stored bytes through ZX0), zx0raw (the unpacked block through ZX0)")
    ap.add_argument("layout", nargs="?")
    ap.add_argument("--model", default="build/trace/model.json")
    ap.add_argument("--traces", default="build/trace/runs")
    ap.add_argument("--drives", type=int, default=2)
    ap.add_argument("--extra", type=int, default=2, help="disks beyond the least the data needs")
    ap.add_argument("--iters", type=int, default=60000)
    ap.add_argument("--out", default="build/floppy/layout.json")
    a = ap.parse_args()
    model = Model(a.model, json.loads(Path(a.sizes).read_text()) if a.sizes else None, a.scheme)
    meta = json.loads(Path(a.model).read_text())
    save_lsn = (max(e["off"] + e["size"] for e in model.ents) + 255) // 256
    if a.cmd != "profile" and Path(a.runs).exists():
        runs = load_runs_json(model, a.runs)
    else:
        runs = load_runs(model, a.traces, save_lsn)
    if a.cmd == "profile":
        save_runs(model, runs, a.runs)
        print("mklayout: %d runs written to %s" % (len(runs), a.runs))
        return
    if a.cmd == "stats":
        touched = set(x for s in runs.values() for x in s if x >= 0)
        tot = sum(e["size"] for e in model.ents)
        seen = sum(model.ents[i]["size"] for i in touched)
        print("%d runs, %d accesses; %d of %d entries touched, %d of %d bytes" % (len(runs), sum(len(s) for s in runs.values()), len(touched), len(model.ents), seen, tot))
        for n, s in runs.items():
            print("  %-20s %5d accesses %4d entries" % (n, len(s), len(set(s))))
    elif a.cmd in ("naive", "eval"):
        if a.cmd == "naive":
            disks = naive_layout(model)
            save_disk = len(disks)
            disks.append([])
        else:
            lay = json.loads(Path(a.layout).read_text())
            idx = {(e["file"], e["id"]): e["i"] for e in model.ents}
            disks = [[idx[tuple(k)] for k in d["keys"]] for d in lay["disks"]]
            save_disk = lay["save"]
        for nd in range(1, 5):
            sc = score(model, runs, disks, save_disk, nd)
            print("drives %d: %d swaps over %d runs (worst %s %d)" % (nd, sum(sc.values()), len(sc), max(sc, key=sc.get), max(sc.values())))
        print("%d disks:" % len(disks), " ".join("%d%%" % (100 * bytes_of(model, d) // disk_capacity(model, i)) for i, d in enumerate(disks)))
        if a.cmd == "naive":
            Path(a.out).parent.mkdir(parents=True, exist_ok=True)
            Path(a.out).write_text(json.dumps(to_layout(model, disks, save_disk)))
    elif a.cmd == "make":
        disks, save_disk = optimise(model, runs, a.drives, iters=a.iters, extra=a.extra)
        Path(a.out).parent.mkdir(parents=True, exist_ok=True)
        Path(a.out).write_text(json.dumps(to_layout(model, disks, save_disk)))
        for nd in range(1, 5):
            sc = score(model, runs, disks, save_disk, nd)
            print("drives %d: %d swaps over %d runs (worst %s %d)" % (nd, sum(sc.values()), len(sc), max(sc, key=sc.get), max(sc.values())))
        print("%d disks:" % len(disks), " ".join("%d%%" % (100 * bytes_of(model, d) // disk_capacity(model, i)) for i, d in enumerate(disks)))
    elif a.cmd == "xval":                    # leave one run out: optimise on the others, count the swaps of the one (what the layout does for a session it never saw)
        tot_in, tot_out = 0, 0
        for name in sorted(runs):
            rest = {k: v for k, v in runs.items() if k != name}
            disks, sd = optimise(model, rest, a.drives, iters=a.iters, extra=a.extra, verbose=False)
            out = score(model, {name: runs[name]}, disks, sd, 2)[name]
            ins = sum(score(model, rest, disks, sd, 2).values()) / max(1, len(rest))
            print("%-20s held out: %4d swaps (the others: %.0f on average); %d disks" % (name, out, ins, len(disks)))
            tot_in += ins
            tot_out += out
        print("held out: %.0f swaps a run on average; trained on: %.0f" % (tot_out / len(runs), tot_in / len(runs)))
    elif a.cmd == "cost":                    # what the reads of the sessions would cost on each medium under each way of storing the entries
        sz = json.loads(Path(a.sizes).read_text())
        # (cycles an output byte of the decoders on the 6809: the original's RLE about 22 [E, research 03], ZX0 68.3 and LZ4 31.6 measured in 8.9b)
        rows = [("as now (RLE of the original, banks raw)", "none", lambda e: 22 if e["kind"] == 0 else 0),
                ("ZX0 of those bytes (then the RLE)", "zx0", lambda e: 68.3 + (22 if e["kind"] == 0 else 0)),
                ("ZX0 of the unpacked block", "zx0raw", lambda e: 68.3)]
        media = [("floppy 12.6 KB/s", 12600), ("DriveWire 11 KB/s", 11000), ("SDC command mode 100 KB/s [E]", 100000)]
        nrun = len(runs)
        print("per session on average, %d sessions: seconds of reading + decoding (the swaps are the player's, not counted)" % nrun)
        print("%-42s %9s %9s  %s" % ("", "read KB", "decoded KB", "   ".join("%-26s" % m[0] for m in media)))
        for label, sch, cyc in rows:
            rd = sum(sz[model.ents[x]["name"]][sch] for r in runs.values() for x in r if x >= 0) / nrun
            dec = sum(sz[model.ents[x]["name"]]["raw"] for r in runs.values() for x in r if x >= 0) / nrun
            cy = sum(sz[model.ents[x]["name"]]["raw"] * cyc(model.ents[x]) for r in runs.values() for x in r if x >= 0) / nrun
            print("%-42s %9.0f %9.0f  %s" % (label, rd / 1024, dec / 1024, "   ".join("%-26s" % ("%.0f s" % (rd / m[1] + cy / 1789773)) for m in media)))
    elif a.cmd == "areas":
        by = collections.defaultdict(int)
        for e in model.ents:
            by[e["area"]] += e["size"]
        for k in sorted(by):
            print("area %d: %d bytes" % (k, by[k]))


if __name__ == "__main__":
    main()
