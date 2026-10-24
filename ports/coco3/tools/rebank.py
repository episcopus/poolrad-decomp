#!/usr/bin/env python3
"""rebank.py: choose which routines share a code bank, from what the sessions really run (step 8.11).

Until step 8.10 a bank was a translated unit (or half of one, or a few merged by tools/bankgroup.py): the unit boundaries of the original
overlay layout, which did not know about the CoCo's 16 KB slots and a 4 KB/s floppy. This tool works on routines:

  input   build/profile/code.json   (tools/codeprof.py: every routine of the banked units with its size)
          build/profile/<session>.json and .seq   (tools/routine_profile.py: the routines each session runs, in order, from the oracle)
  model   a pool of N slots (7), LRU, a bank is read whole when a routine of it runs and it is not there; cost = bytes read
  method  a start from greedy clustering (routines that run right after one another share a bank), then simulated annealing on the
          pool simulation itself (tools/poolsim.c, compiled on first use): move or swap routines between banks, keep what lowers the
          bytes read over all sessions; routines no session ran are packed by unit into cold banks; the plain unit layout of the
          last build is simulated for comparison
  output  a report; with --write, data/routine_banks.json = {"banks": {"hotNN": ["Routine", ...], ...}} for tools/mkgame.py

  python3 tools/rebank.py [--slots 7] [--limit 15600] [--write] [--sessions a,b,c]
"""
from __future__ import annotations

import argparse
import collections
import heapq
import ctypes
import json
import math
import multiprocessing
import random
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import routine_profile as rp          # noqa: E402

PROF = ROOT / "build/profile"
# Routines the port runs that the oracle never calls (the original's sound driver is an external object, so its routines are not in the
# symbol map): they run right after the routine that calls them. Found by comparing the entries the port's bank logs show with the profiles
# (step 8.11: BriefWait, 376 calls over the 16 sessions; a layout that left it out filled the pool exactly and thrashed the moment it ran).
FOLLOWERS = {"PlaySound": ["BriefWait"]}
SND_EVERY = 333_000      # instructions of the oracle (1 MHz clock model) between two runs of the sound driver: 3 a second, as in the port's logs


class Model:
    def __init__(self, sessions=None):
        code = json.loads((PROF / "code.json").read_text())
        self.units = code["units"]
        self.groups = []                            # [(unit, name, size, funcs)]
        self.gid = {}
        for u, v in sorted(self.units.items()):
            for g in v["groups"]:
                self.gid[g["name"]] = len(self.groups)
                self.groups.append((u, g["name"], g["size"], g["funcs"]))
        self.bank_of = code["bank_of"]              # routine -> bank of the last build
        # the runtime bank and the sound bank take slots of the pool too (the sound driver runs about three times a second of game time):
        # two groups of their own that annealing never moves
        banks = {b["name"]: b["size"] for b in json.loads((ROOT / "build/game/banks.json").read_text())["banks"]} if (ROOT / "build/game/banks.json").exists() else {}
        self.rtl = self.snd = len(self.groups)            # one bank (tools/mkgame.py RTLSND): both kinds of event use the same group
        self.groups.append(("rtl", "@RTLSND", banks.get("rtlsnd", banks.get("rtl", 9411) + banks.get("snd", 6775)), []))
        self.fixed = {self.rtl}
        self.sessions = sessions or sorted(p.stem for p in PROF.glob("*.json") if p.stem != "code" and (PROF / (p.stem + ".seq")).exists())
        self.seqs = {}                              # session -> list of group ids, runs folded
        self.unmatched = collections.Counter()
        for s in self.sessions:
            rec, ids, ts = rp.load(s)
            names = rec["routines"]
            m = [self.gid.get(n, self.rtl if n in rp.RTL else -1) for n in names]
            for n, g in zip(names, m):
                if g < 0:
                    self.unmatched[n] += 1
            out, last, nxt = [], -2, SND_EVERY
            follow = {self.gid[n]: [self.gid[f] for f in fs if f in self.gid] for n, fs in FOLLOWERS.items() if n in self.gid}
            for i, t in zip(ids, ts):
                while t >= nxt:
                    out.append(self.snd)
                    nxt += SND_EVERY
                    last = -2
                g = m[i]
                if g >= 0 and g != last:
                    out.append(g)
                    last = g
                    for f in follow.get(g, ()):
                        out.append(f)
                        out.append(g)
            self.seqs[s] = out

    @property
    def size(self):
        return [g[2] for g in self.groups]


def simulate(model, assign, sizes, slots, policy="lru"):
    """assign: group id -> bank id. Returns {session: (loads, bytes)} for a pool of `slots` banks."""
    res = {}
    for s, seq in model.seqs.items():
        pool = collections.OrderedDict()
        loads = nbytes = 0
        last = -1
        for g in seq:
            b = assign[g]
            if b == last:
                continue
            last = b
            if b in pool:
                pool.move_to_end(b)
                continue
            loads += 1
            nbytes += sizes[b]
            if len(pool) >= slots:
                pool.popitem(last=False)
            pool[b] = True
        res[s] = (loads, nbytes)
    return res


def transitions(model):
    """weight of the pair (i, j) = how often one runs right after the other, each session counting the same (the mean of the sessions, as the budget does)"""
    T = collections.defaultdict(float)
    for s, seq in model.seqs.items():
        if len(seq) < 2:
            continue
        w = 1000.0 / len(seq)
        for a, b in zip(seq, seq[1:]):
            if a != b and a not in model.fixed and b not in model.fixed:
                T[(a, b) if a < b else (b, a)] += w
    return T


def cluster(model, limit, T):
    n = len(model.groups)
    size = model.size
    members = {i: [i] for i in range(n)}
    csize = {i: size[i] for i in range(n)}
    adj = collections.defaultdict(dict)             # cluster -> {cluster: weight}
    for (a, b), w in T.items():
        adj[a][b] = adj[a].get(b, 0) + w
        adj[b][a] = adj[b].get(a, 0) + w
    heap = [(-w / (csize[a] + csize[b]) ** 0.5, a, b) for a, d in adj.items() for b, w in d.items() if a < b]
    heapq.heapify(heap)
    alive = set(range(n))
    while heap:
        _, a, b = heapq.heappop(heap)
        if a not in alive or b not in alive or b not in adj[a]:
            continue
        if csize[a] + csize[b] > limit:
            continue
        # merge b into a
        for c, w in adj[b].items():
            if c == a:
                continue
            adj[a][c] = adj[a].get(c, 0) + w
            adj[c][a] = adj[c].get(a, 0) + w
            del adj[c][b]
        del adj[a][b]
        del adj[b]
        members[a] += members.pop(b)
        csize[a] += csize.pop(b)
        alive.discard(b)
        for c, w in adj[a].items():
            x, y = (a, c) if a < c else (c, a)
            heapq.heappush(heap, (-w / (csize[a] + csize[c]) ** 0.5, x, y))
    return [members[c] for c in sorted(alive)]


def pack(model, clusters, limit):
    """clusters that ran (hot) stay as they are, but small ones are first-fit merged by the weight between them; the groups no session ran
    are dealt into cold banks, a unit at a time in the original's order"""
    ran = set()
    for seq in model.seqs.values():
        ran.update(seq)
    hot = [c for c in clusters if any(g in ran for g in c)]
    cold_groups = [g for c in clusters for g in c if g not in ran]
    # a cluster of hot groups may carry never-run groups along (merged through a single weight); keep them, they cost only space
    banks = [sorted(c) for c in hot]
    # the cold groups, by unit then address order, into banks of the same unit where they fit, else first fit
    cold_groups.sort()
    size = model.size
    free = [limit - sum(size[g] for g in b) for b in banks]
    out = [list(b) for b in banks]
    cold_banks, cfree = [], []
    cur, used, cur_unit = [], 0, None
    for g in cold_groups:
        u = model.groups[g][0]
        if cur and (used + size[g] > limit or u != cur_unit and used > limit * 0.6):
            cold_banks.append(cur)
            cfree.append(limit - used)
            cur, used = [], 0
        cur.append(g)
        used += size[g]
        cur_unit = u
    if cur:
        cold_banks.append(cur)
        cfree.append(limit - used)
    return out, cold_banks


class CSim:
    """tools/poolsim.c through ctypes: the same pool as simulate(), about 100 times faster"""

    def __init__(self, model, slots, weights=None):
        lib = PROF / "libpoolsim.so"
        src = HERE / "poolsim.c"
        if not lib.exists() or lib.stat().st_mtime < src.stat().st_mtime:
            subprocess.run(["cc", "-O2", "-shared", "-fPIC", "-o", str(lib), str(src)], check=True)
        self.lib = ctypes.CDLL(str(lib))
        self.lib.pool_sim.restype = ctypes.c_double
        self.names = list(model.seqs)
        flat, off = [], [0]
        for s in self.names:
            flat += model.seqs[s]
            off.append(len(flat))
        self.n = len(self.names)
        self.off = (ctypes.c_int32 * len(off))(*off)
        self.seq = (ctypes.c_int32 * len(flat))(*flat)
        self.slots = slots
        self.w = (ctypes.c_double * self.n)(*(weights or [1.0] * self.n))
        self.bytes = (ctypes.c_int64 * self.n)()
        self.loads = (ctypes.c_int32 * self.n)()

    def run(self, assign, bsize):
        a = (ctypes.c_int32 * len(assign))(*assign)
        b = (ctypes.c_int32 * len(bsize))(*bsize)
        return self.lib.pool_sim(self.n, self.off, self.seq, a, b, self.slots, self.w, self.bytes, self.loads)

    def per_session(self):
        return {s: (self.loads[i], self.bytes[i]) for i, s in enumerate(self.names)}


OVERHEAD = 900            # a bank is read with its constants (0.4 to 1.6 KB measured) and its entry table


def anneal(args):
    model, slots, start, cap, iters, seed, weights, nb = args
    rnd = random.Random(seed)
    sim = CSim(model, slots, weights)
    size = model.size
    ng = len(size)
    assign = list(start)
    used = [0] * nb
    for g, b in enumerate(assign):
        if b >= 0:
            used[b] += size[g]
    for g in model.fixed:
        used[assign[g]] -= OVERHEAD                     # these two are read whole at their real size, which bs() must not add to
    hot = sorted({g for seq in model.seqs.values() for g in seq} - model.fixed)
    bs = lambda: [u + OVERHEAD if u else 0 for u in used]
    cost = sim.run(assign, bs())
    best, best_assign = cost, list(assign)
    t0 = cost * 0.003
    for it in range(iters):
        T = t0 * (1 - it / iters) ** 3 + 1e-9
        g = rnd.choice(hot)
        a = assign[g]
        if rnd.random() < 0.5:
            b = rnd.randrange(nb)
            if b == a or used[b] + size[g] > cap:
                continue
            assign[g] = b
            used[a] -= size[g]
            used[b] += size[g]
            new = sim.run(assign, bs())
            if new <= cost or rnd.random() < math.exp((cost - new) / T):
                cost = new
            else:
                assign[g] = a
                used[a] += size[g]
                used[b] -= size[g]
        else:
            h = rnd.choice(hot)
            b = assign[h]
            if b == a or used[a] - size[g] + size[h] > cap or used[b] - size[h] + size[g] > cap:
                continue
            assign[g], assign[h] = b, a
            used[a] += size[h] - size[g]
            used[b] += size[g] - size[h]
            new = sim.run(assign, bs())
            if new <= cost or rnd.random() < math.exp((cost - new) / T):
                cost = new
            else:
                assign[g], assign[h] = a, b
                used[a] -= size[h] - size[g]
                used[b] -= size[g] - size[h]
        if cost < best:
            best, best_assign = cost, list(assign)
    return best, best_assign


def initial(model, cap):
    """first-fit decreasing of the greedy clusters (heaviest in the sessions first) into banks of at most `cap` bytes"""
    T = transitions(model)
    clusters = cluster(model, cap, T)
    ran = {g for seq in model.seqs.values() for g in seq} - model.fixed
    size = model.size
    hot = [[g for g in c if g in ran] for c in clusters]
    hot = [c for c in hot if c]
    hot.sort(key=lambda c: -sum(size[g] for g in c))
    banks, used = [], []
    for c in hot:
        sz = sum(size[g] for g in c)
        for k in range(len(banks)):
            if used[k] + sz <= cap:
                banks[k] += c
                used[k] += sz
                break
        else:
            banks.append(list(c))
            used.append(sz)
    assign = [-1] * len(size)
    for k, b in enumerate(banks):
        for g in b:
            assign[g] = k
    return assign, len(banks)


def cold_banks(model, assign, nhot, cap, skip=()):
    """the groups no session ran, a unit at a time in the original's order, into banks of the same unit where they fit"""
    size = model.size
    rest = [g for g in range(len(size)) if assign[g] < 0 and g not in skip]
    k, used, unit = nhot, 0, None
    for g in rest:
        u = model.groups[g][0]
        if used and (used + size[g] > cap or (u != unit and used > cap * 0.6)):
            k += 1
            used = 0
        assign[g] = k
        used += size[g]
        unit = u
    return k + 1 if rest else nhot


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--slots", type=int, default=6, help="slots the layout is made for; the pool has one more, as a margin for banks the profiles do not show")
    ap.add_argument("--limit", type=int, default=15000, help="bytes of code in a bank (the rest of the 16000: constants, the entry table)")
    ap.add_argument("--iters", type=int, default=6000, help="annealing steps per chain")
    ap.add_argument("--chains", type=int, default=12)
    ap.add_argument("--spare", type=int, default=4, help="empty banks the annealing may fill")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--sessions")
    ap.add_argument("--holdout", help="train on the other sessions and report this one with the banks they chose (how well the layout serves a play it was not made from)")
    ap.add_argument("--show", action="store_true", help="list the hot banks and their routines")
    a = ap.parse_args(argv)
    model = Model(a.sessions.split(",") if a.sessions else None)
    held = None
    if a.holdout:
        held = Model([a.holdout])
        model = Model([x for x in model.seqs if x != a.holdout])
    G = model.groups
    size = model.size
    print("%d routines in %d units, %d bytes; %d sessions; %d names of the profiles are not banked code (%s ...)" % (
        len(G), len(model.units), sum(size), len(model.seqs), len(model.unmatched), ", ".join(n for n, _ in model.unmatched.most_common(5))))
    # the plain unit layout of the last build
    names = sorted(set(model.bank_of.values()) - {None})
    bid = {n: i for i, n in enumerate(names)}
    base = [bid.get(model.bank_of.get(g[1]), len(names)) for g in G]
    base[model.rtl] = len(names) + 1
    bsz = collections.Counter()
    for g, b in zip(G, base):
        bsz[b] += g[2]
    sizes0 = [bsz.get(i, 0) + OVERHEAD for i in range(len(names) + 2)]
    for g in model.fixed:
        sizes0[base[g]] -= OVERHEAD
    sim = CSim(model, a.slots + 1)                  # the old layout in the pool as it is: one slot more than the layout is made for
    sim.run(base, sizes0)
    r0 = sim.per_session()
    weights = [1.0 / math.sqrt(max(1, r0[s][1])) for s in sim.names]
    assign, nhot = initial(model, a.limit)
    nhot += a.spare
    assign[model.rtl] = nhot
    used = collections.Counter()
    for g in range(len(size)):
        if assign[g] >= 0:
            used[assign[g]] += size[g]
    sim = CSim(model, a.slots, weights)
    sim.run(assign, [used.get(i, 0) + (OVERHEAD if i < nhot else 0) for i in range(nhot + 1)])
    print("start: %d hot banks, %d KB read by the sessions on average" % (nhot, sum(v[1] for v in sim.per_session().values()) // len(model.seqs) // 1024))
    starts = [(model, a.slots, list(assign), a.limit, a.iters, 1000 + k, weights, nhot + 1) for k in range(a.chains)]
    with multiprocessing.Pool(min(a.chains, multiprocessing.cpu_count())) as pool:
        results = pool.map(anneal, starts)
    results.sort(key=lambda r: r[0])
    print("chains: " + " ".join("%.1f" % r[0] for r in results))
    best = results[0][1]
    final = [best[g] if assign[g] >= 0 else -1 for g in range(len(size))]
    ids = sorted({b for g, b in enumerate(final) if b >= 0 and g not in model.fixed})
    renum = {b: i for i, b in enumerate(ids)}
    final = [renum[b] if b >= 0 and g not in model.fixed else -1 for g, b in enumerate(final)]
    nhot = len(ids)
    nb = cold_banks(model, final, nhot, a.limit, model.fixed)
    final[model.rtl] = nb
    used = collections.Counter()
    for g in range(len(size)):
        used[final[g]] += size[g]
    sizes1 = [used.get(i, 0) + OVERHEAD for i in range(nb)] + [size[model.rtl]]
    sim2 = CSim(model, a.slots)
    sim2.run(final, sizes1)
    r1 = sim2.per_session()
    sim3 = CSim(model, a.slots + 1)
    sim3.run(final, sizes1)
    r2 = sim3.per_session()
    print("%d hot banks (%d bytes), %d cold banks (%d bytes)" % (nhot, sum(sizes1[:nhot]), nb - nhot, sum(sizes1[nhot:])))
    if held:
        sh = CSim(held, a.slots + 1)
        sh.run(base, sizes0)
        h0 = sh.per_session()[a.holdout]
        sh.run(final, sizes1)
        h1 = sh.per_session()[a.holdout]
        print("HOLDOUT %-18s old banks %4d loads %6d KB | new banks %4d loads %6d KB" % (a.holdout, h0[0], h0[1] // 1024, h1[0], h1[1] // 1024))
        return 0
    print("%-18s %14s | %14s | %14s" % ("session", "old, %d slots" % (a.slots + 1), "new, %d slots" % a.slots, "new, %d slots" % (a.slots + 1)))
    t0 = t1 = t2 = 0
    for s in model.seqs:
        print("%-18s %5d %8d | %5d %8d | %5d %8d" % (s, r0[s][0], r0[s][1] // 1024, r1[s][0], r1[s][1] // 1024, r2[s][0], r2[s][1] // 1024))
        t0 += r0[s][1]
        t1 += r1[s][1]
        t2 += r2[s][1]
    k = len(model.seqs)
    print("%-18s %5s %8d | %5s %8d | %5s %8d   (mean KB per session)" % ("average", "", t0 // k // 1024, "", t1 // k // 1024, "", t2 // k // 1024))
    if a.show:
        for i in range(nhot):
            mem = [g for g in range(len(size)) if final[g] == i]
            print("hot%02d %6d bytes: %s" % (i, used[i], " ".join(G[g][1] for g in sorted(mem, key=lambda g: -size[g])[:10])))
    if a.write:
        out = {"slots": a.slots, "limit": a.limit,
               "banks": {("hot%02d" % i if i < nhot else "cold%02d" % (i - nhot)): [G[g][1] for g in range(len(size)) if final[g] == i] for i in range(nb)}}
        (ROOT / "data/routine_banks.json").write_text(json.dumps(out, indent=0))
        print("wrote data/routine_banks.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
