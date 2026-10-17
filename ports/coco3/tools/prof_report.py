#!/usr/bin/env python3
"""prof_report.py: read the profiles of scripts/prof_run.sh and answer the data model questions of
step 8.1c. Usage: prof_report.py REPO [PROF ...]   (default: REPO/build/prof/*.prof)

For every DGROUP global and every heap block class: how many references the game's routines make per
interval (an interval is the work between two keys read by the game), which units make them, and how much
of that the engine (the blitter and text units) could take. Then the cost of each way of splitting
code and data, counted on the same recorded sessions.
"""
import collections
import glob
import re
import statistics
import sys

repo = sys.argv[1]
files = sys.argv[2:] or sorted(glob.glob(repo + "/build/prof/*.prof"))

# ------------------------------------------------------------------ static knowledge
fn_unit = {}                                   # routine name -> unit id
for path in glob.glob(repo + "/c/game/*.c"):
    unit = path.split("/")[-1][:-2]
    if not unit.startswith(("ovl", "res")):
        continue
    text = open(path).read()
    for m in re.finditer(r"^(?:static )?[A-Za-z_][\w ]*?[ *](\w+)\([^;{]*\)\s*\n\{", text, re.M):
        fn_unit[m.group(1)] = unit
# The game waits for a key or a time by polling the clock in a loop (WaitKeyOrTimeout inside
# ReadPromptChoice, the title screen's loop, WaitHundredths). How often it spins depends on the speed
# of the machine, not on the game, so references made while spinning are left out of the load figures.
IDLE_FNS = {"ReadPromptChoice", "WaitKeyOrTimeout", "WaitHundredths", "ShowTitleScreen", "GameClock",
            "TimeInHundredths"}
ENGINE = {"res06", "res07", "res09", "ovl28", "ovl32", "ovl34"}      # pictures, blits, text, 8x8 symbols

glob_at = {}                                   # offset -> (size, name): the largest entry at each offset
for l in open(repo + "/c/game/globals.txt"):
    p = l.split()
    if len(p) >= 3:
        o, s, n = int(p[0], 16), int(p[1]), p[2]
        if o not in glob_at or s > glob_at[o][0]:
            glob_at[o] = (s, n)
starts = sorted(glob_at)


def global_of(off):
    """The named global whose range holds off ((start, size, name)), or an anonymous entry."""
    lo, hi = 0, len(starts)
    while lo < hi:
        mid = (lo + hi) // 2
        if starts[mid] <= off:
            lo = mid + 1
        else:
            hi = mid
    for i in range(lo - 1, max(lo - 6, -1), -1):
        o = starts[i]
        if o <= off < o + glob_at[o][0]:
            return o, glob_at[o][0], glob_at[o][1]
    return off, 1, "ds%04X" % off


# ------------------------------------------------------------------ read the logs
class Session:
    def __init__(self, path):
        self.name = path.split("/")[-1][:-5]
        self.names, self.classes = {}, {}
        self.intervals = []                    # list of dict(E=[], G=[], H=[])
        cur = None
        for line in open(path):
            t = line.split()
            if t[0] == "I":
                cur = {"E": [], "G": [], "H": []}
                self.intervals.append(cur)
            elif t[0] in "EGH":
                cur[t[0]].append((int(t[1]), int(t[2]), int(t[3])))
            elif t[0] == "F":
                self.names[int(t[1])] = t[2].lstrip("_")
            elif t[0] == "C":
                self.classes[int(t[1])] = (int(t[2]), int(t[3]))
                self.cls_live = getattr(self, "cls_live", {})
                self.cls_live[int(t[1])] = (int(t[5]), int(t[6]))          # most live at once, live at the end

    def unit(self, fn_id):
        return fn_unit.get(self.names.get(fn_id, "?"), "?")

    def idle(self, fn_id):
        return self.names.get(fn_id, "?") in IDLE_FNS


sessions = [Session(f) for f in files]
if not sessions:
    sys.exit("no profiles: run scripts/prof_run.sh")


def pct(vals, p):
    v = sorted(vals)
    return v[min(len(v) - 1, int(len(v) * p / 100))] if v else 0


# ------------------------------------------------------------------ overall
print("sessions:", ", ".join(f"{s.name} ({len(s.intervals)} intervals)" for s in sessions))
tot_calls = tot_g = tot_h = 0
for s in sessions:
    for iv in s.intervals:
        tot_calls += sum(n for _, _, n in iv["E"])
        tot_g += sum(n for _, _, n in iv["G"])
        tot_h += sum(n for _, _, n in iv["H"])
print(f"routine calls {tot_calls:,}; DGROUP references {tot_g:,}; far pointer dereferences {tot_h:,}")
idle_g = sum(n for s in sessions for iv in s.intervals for f, _, n in iv["G"] if s.idle(f))
idle_h = sum(n for s in sessions for iv in s.intervals for f, _, n in iv["H"] if s.idle(f))
print(f"made while waiting for a key or a time (left out below): {idle_g:,} DGROUP references, {idle_h:,} dereferences")

# ------------------------------------------------------------------ globals
by_glob = collections.defaultdict(lambda: [0, collections.Counter()])      # key -> [count, Counter(unit)]
iv_total = []                                                              # per interval: references to DGROUP
for s in sessions:
    for iv in s.intervals:
        iv_total.append(sum(n for f, _, n in iv["G"] if not s.idle(f)))
        for fn, off, n in iv["G"]:
            if s.idle(fn):
                continue
            o, size, name = global_of(off)
            e = by_glob[(o, size, name)]
            e[0] += n
            e[1][s.unit(fn)] += n
n_iv = len(iv_total)


def eng_share(counter):
    t = sum(counter.values())
    return 100.0 * sum(c for u, c in counter.items() if u in ENGINE) / t if t else 0.0


print("\nDGROUP globals by references (count over all sessions, per interval = per key):")
print(f"{'global':26} {'off':>5} {'bytes':>6} {'refs':>11} {'/key':>9} {'units':>5} {'engine%':>7}  main units")
const_end = 0x43DC
seen = 0
for (o, size, name), (cnt, units) in sorted(by_glob.items(), key=lambda kv: -kv[1][0]):
    if seen >= 40:
        break
    seen += 1
    kind = "const" if o < const_end else "var"
    top = ",".join(u for u, _ in units.most_common(4))
    print(f"{name:26} {o:5X} {size:6d} {cnt:11,d} {cnt / n_iv:9,.0f} {len(units):5d} {eng_share(units):6.0f}%  {top} [{kind}]")

# how the references split between the constants image and the variables, and by who
const_refs = sum(c for (o, s, n), (c, u) in by_glob.items() if o < const_end)
var_refs = sum(c for (o, s, n), (c, u) in by_glob.items() if o >= const_end)
print(f"\nreferences to the constants image {const_refs:,} ({100 * const_refs / (const_refs + var_refs):.0f}%), to variables {var_refs:,}")
touched = {k for k, v in by_glob.items() if v[0] > 0}
vbytes = sum(k[1] for k in touched if k[0] >= const_end)
print(f"variables referenced at least once: {len([k for k in touched if k[0] >= const_end])} of {len([o for o in glob_at if o >= const_end])} named, {vbytes:,} bytes")

# ------------------------------------------------------------------ heap classes
cls_total = collections.defaultdict(lambda: [0, collections.Counter(), 0])  # (size, allocator) -> [count, units, blocks]
special = {0: "unknown or nil", 1: "DGROUP via far pointer", 2: "video memory"}
for s in sessions:
    for iv in s.intervals:
        for fn, c, n in iv["H"]:
            if s.idle(fn):
                continue
            if c in special:
                key = (0, special[c])
            else:
                size, a = s.classes.get(c, (0, 0))
                key = (size, s.names.get(a, "?").lstrip("_"))
            e = cls_total[key]
            e[0] += n
            e[1][s.unit(fn)] += n
print("\nHeap block classes (size, allocating routine) by far pointer dereferences:")
print(f"{'class':36} {'bytes':>6} {'derefs':>11} {'/key':>9} {'units':>5} {'engine%':>7}  main units")
rows = sorted(cls_total.items(), key=lambda kv: -kv[1][0])
for (size, alloc), (cnt, units, _) in rows[:30]:
    top = ",".join(u for u, _ in units.most_common(4))
    print(f"{alloc[:36]:36} {size:6d} {cnt:11,d} {cnt / n_iv:9,.0f} {len(units):5d} {eng_share(units):6.0f}%  {top}")

# ------------------------------------------------------------------ per interval load
gh = []
for s in sessions:
    for iv in s.intervals:
        gh.append(sum(n for f, _, n in iv["G"] if not s.idle(f)) + sum(n for f, _, n in iv["H"] if not s.idle(f)))
print(f"\nreferences per interval (DGROUP + far pointers): median {statistics.median(gh):,.0f}, p90 {pct(gh, 90):,}, max {max(gh):,}")

# ------------------------------------------------------------------ calls between units under three assignments
def far_calls(assign):
    out = []
    for s in sessions:
        for iv in s.intervals:
            n = 0
            for a, b, c in iv["E"]:
                ua, ub = s.unit(a), s.unit(b)
                if s.idle(a) or s.idle(b):
                    continue
                if ua != "?" and ub != "?" and assign(ua) != assign(ub):
                    n += c
            out.append(n)
    return out


overlay = lambda u: u if u.startswith("ovl") else "RES"
allbank = lambda u: u
res_only = lambda u: "RES" if u in ENGINE else u
for label, f in (("overlay = bank, resident units pinned", overlay),
                 ("every unit its own bank (resident too)", allbank),
                 ("overlay = bank, blitter and text units pinned, other resident units banked", lambda u: "PIN" if u in ENGINE else u)):
    v = far_calls(f)
    print(f"far calls per interval, {label}: median {statistics.median(v):,.0f}, p90 {pct(v, 90):,}, max {max(v):,}, "
          f"total {sum(v):,}  (x 176 cycles: median {statistics.median(v) * 176:,.0f}, max {max(v) * 176:,})")



# ------------------------------------------------------------------ what the C code (not the engine) sees
ACCESS_CYCLES = 50          # [E] one reference to banked data through an accessor (map, load, call overhead)
ENGINE_PLUS = ENGINE | {"res05"}                 # res05 is the DAX loader: asm in the port
cvis_g = collections.defaultdict(lambda: [0, collections.Counter()])   # global -> [refs, Counter(unit)] from C-code routines
for s in sessions:
    for iv in s.intervals:
        for fn, off, n in iv["G"]:
            u = s.unit(fn)
            if s.idle(fn) or u in ENGINE_PLUS or u == "?":
                continue
            e = cvis_g[global_of(off)]
            e[0] += n
            e[1][u] += n
print("\n--- what the C code (not the engine units %s) references" % ",".join(sorted(ENGINE_PLUS)))
cov = {k: bytearray(0x8760) for k in ("const1", "constN", "var1", "varN")}
nconst = nvar = 0
for (o, size, name), (cnt, units) in cvis_g.items():
    kind = ("const" if o < const_end else "var") + ("1" if len(units) == 1 else "N")
    nconst += o < const_end
    nvar += o >= const_end
    cov[kind][o:o + size] = b"\x01" * size
# bytes counted once: a byte used by several entries counts for the "several units" class if any says so
for kind in ("const", "var"):
    only1 = sum(1 for i in range(0x8760) if cov[kind + "1"][i] and not cov[kind + "N"][i])
    several = sum(cov[kind + "N"])
    print(f"DGROUP {kind}{'ants' if kind == 'const' else 'iables'} referenced by C code: "
          f"{(nconst if kind == 'const' else nvar)} entries, {only1 + several:,} bytes "
          f"({only1:,} used by one unit only, {several:,} by several)")

cvis_h = collections.defaultdict(lambda: [0, collections.Counter(), 0])   # (size, alloc) -> [derefs, units, max bytes live]
for s in sessions:
    for iv in s.intervals:
        for fn, c, n in iv["H"]:
            u = s.unit(fn)
            if c < 3 or s.idle(fn) or u in ENGINE_PLUS or u == "?":
                continue
            size, a = s.classes.get(c, (0, 0))
            e = cvis_h[(size, s.names.get(a, "?").lstrip("_"))]
            e[0] += n
            e[1][u] += n
for s in sessions:
    for c, (maxlive, live) in getattr(s, "cls_live", {}).items():
        size, a = s.classes[c]
        key = (size, s.names.get(a, "?").lstrip("_"))
        if key in cvis_h:
            cvis_h[key][2] = max(cvis_h[key][2], maxlive * size)
print(f"\nheap classes dereferenced by C code (largest live bytes seen in any session):")
print(f"{'class':36} {'bytes':>6} {'live max':>9} {'derefs':>11} {'/key':>8}  units")
hb = 0
for (size, alloc), (cnt, units, live) in sorted(cvis_h.items(), key=lambda kv: -kv[1][2]):
    if live >= 500 or cnt / n_iv > 50:
        print(f"{alloc[:36]:36} {size:6d} {live:9,d} {cnt:11,d} {cnt / n_iv:8,.0f}  {','.join(u for u, _ in units.most_common(5))}")
    hb += live
print(f"total live bytes in classes the C code dereferences: {hb:,}")

# greedy: keep the most-referenced data per byte in the 64 KB map, bank the rest
items = []         # (bytes, refs, label, kind)
for (o, size, name), (cnt, units) in cvis_g.items():
    if o >= const_end:
        items.append((size, cnt, name, "var"))
for (size, alloc), (cnt, units, live) in cvis_h.items():
    items.append((max(live, size), cnt, f"{alloc}/{size}", "heap"))
var_union = sum(1 for i in range(0x8760) if (cov["var1"][i] or cov["varN"][i]))
print(f"\nC-visible writable data: {var_union:,} bytes of DGROUP variables + {hb:,} bytes of heap = {var_union + hb:,} bytes, "
      f"{sum(i[1] for i in items):,} references (entries overlap, so the budget table below is approximate)")
per_iv_refs = collections.defaultdict(lambda: collections.Counter())      # item label -> per-interval refs
label_of = {}
for s in sessions:
    for k, iv in enumerate(s.intervals):
        for fn, off, n in iv["G"]:
            u = s.unit(fn)
            if s.idle(fn) or u in ENGINE_PLUS or u == "?" or off < const_end:
                continue
            per_iv_refs[(s.name, k)][global_of(off)[2]] += n
        for fn, c, n in iv["H"]:
            u = s.unit(fn)
            if c < 3 or s.idle(fn) or u in ENGINE_PLUS or u == "?":
                continue
            size, a = s.classes.get(c, (0, 0))
            per_iv_refs[(s.name, k)][f"{s.names.get(a, '?').lstrip('_')}/{size}"] += n
print("budget in the 64 KB map -> references per key that land in banked data (the rest stays mapped):")
for budget in (8192, 16384, 22528, 24576, 32768, 40960):
    kept, used = set(), 0
    for size, refs, label, kind in sorted(items, key=lambda i: -i[1] / max(i[0], 1)):
        if used + size <= budget:
            kept.add(label)
            used += size
    banked = [sum(c for l, c in d.items() if l not in kept) for d in per_iv_refs.values()]
    print(f"  keep {budget // 1024:2d} KB mapped: banked refs per key median {statistics.median(banked):>8,.0f}  "
          f"p90 {pct(banked, 90):>9,}  max {max(banked):>10,}  (x {ACCESS_CYCLES} cycles: p90 {pct(banked, 90) * ACCESS_CYCLES:,}, max {max(banked) * ACCESS_CYCLES:,})")
nonengine_refs = [sum(d.values()) for d in per_iv_refs.values()]
print(f"all C-visible references per key: median {statistics.median(nonengine_refs):,.0f}, p90 {pct(nonengine_refs, 90):,}, max {max(nonengine_refs):,}")

kept, used = [], 0
rest = []
for size, refs, label, kind in sorted(items, key=lambda i: -i[1] / max(i[0], 1)):
    if used + size <= 24576:
        kept.append((size, refs, label, kind))
        used += size
    else:
        rest.append((size, refs, label, kind))
print(f"\nkept mapped at 24 KB ({used:,} bytes, {sum(r for _, r, _, _ in kept):,} references), by references:")
for size, refs, label, kind in sorted(kept, key=lambda i: -i[1])[:14]:
    print(f"  {label[:34]:34} {size:6,d} bytes {refs:9,d} refs ({refs / n_iv:6,.0f}/key) [{kind}]")
print(f"banked ({sum(s for s, _, _, _ in rest):,} bytes, {sum(r for _, r, _, _ in rest):,} references), largest:")
for size, refs, label, kind in sorted(rest, key=lambda i: -i[0])[:12]:
    print(f"  {label[:34]:34} {size:6,d} bytes {refs:9,d} refs ({refs / n_iv:6,.0f}/key) [{kind}]")

eng = cc = 0
for s in sessions:
    for iv in s.intervals:
        for fn, _, n in iv["G"] + iv["H"]:
            if s.idle(fn):
                continue
            if s.unit(fn) in ENGINE_PLUS:
                eng += n
            else:
                cc += n
print(f"\nreferences while not waiting: engine units {eng:,} ({100 * eng / (eng + cc):.1f}%), C game logic {cc:,} ({100 * cc / (eng + cc):.1f}%)")
