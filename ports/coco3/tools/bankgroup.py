#!/usr/bin/env python3
"""bankgroup.py: which code banks to put together (step 8.9).

A bank is a unit of the translated game (or a part of a split one); the pool holds six of them, replaced in turn, and a miss reads the
whole bank from the medium. Banks that are used together should share one 16 KB bank: one load brings both and they cannot push each
other out. This tool takes the bank logs of the sessions (MB_BANKLOG, lua/watch.lua) and merges banks greedily, always the pair whose
merge saves the most bytes loaded over all the sessions, while the merged bank fits the 16 KB window.

Usage: bankgroup.py LOG-or-glob... [--slots 6] [--policy fifo|lru] [--limit 16000] [--write FILE]
Prints the groups, the loads and the bytes before and after, per session. --write FILE saves the groups as JSON (mkgame BANK_GROUPS).
"""
import argparse
import collections
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bankpool_sim as bs

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def loads_fifo(refs, n):
    """list of banks loaded, in order"""
    pool, nxt, out = [0] * n, 0, []
    where = set()
    for b in refs:
        if b in where:
            continue
        free = [i for i in range(n) if pool[i] == 0]
        k = free[0] if free else nxt
        if pool[k]:
            where.discard(pool[k])
        pool[k] = b
        where.add(b)
        nxt = (k + 1) % n
        out.append(b)
    return out


def loads_clock(refs, n):
    """second chance, as the far call trampoline could do it with one spare bit in banktab: a hit sets the bank's bit; the loader
    passes over (and clears) banks whose bit is set, starting after the last victim"""
    pool, ref, hand, out = [0] * n, {}, 0, []
    where = set()
    for b in refs:
        if b in where:
            ref[b] = True
            continue
        free = [i for i in range(n) if pool[i] == 0]
        if free:
            k = free[0]
        else:
            k = hand
            while ref.get(pool[k]):
                ref[pool[k]] = False
                k = (k + 1) % n
        if pool[k]:
            where.discard(pool[k])
        pool[k] = b
        where.add(b)
        ref[b] = True
        hand = (k + 1) % n
        out.append(b)
    return out


def loads_stamp8(refs, n):
    """LRU as a trampoline with an 8 bit counter could do it: every transition in refs stamps the bank with a counter that wraps at 256;
    the loader evicts the bank with the largest (counter - stamp) mod 256"""
    pool, stamp, tick, out = [], {}, 0, []
    for b in refs:
        tick = (tick + 1) & 255
        if b not in pool:
            out.append(b)
            if len(pool) == n:
                pool.remove(max(pool, key=lambda x: (tick - stamp[x]) & 255))
            pool.append(b)
        stamp[b] = tick
    return out


def loads_lru(refs, n):
    pool, out = [], []
    for b in refs:
        if b in pool:
            pool.remove(b)
        else:
            out.append(b)
            if len(pool) == n:
                pool.pop(0)
        pool.append(b)
    return out


def loads_blocks(refs, cap, blocks_of, policy):
    """a pool of `cap` 8 KB blocks; a bank takes blocks_of[b] of them (contiguity ignored); the oldest (fifo) or least recently used goes first"""
    pool, used, out = [], 0, []                  # pool: oldest first
    for b in refs:
        if b in pool:
            if policy == "lru":
                pool.remove(b)
                pool.append(b)
            continue
        need = blocks_of[b]
        while used + need > cap and pool:
            used -= blocks_of[pool.pop(0)]
        pool.append(b)
        used += need
        out.append(b)
    return out


def collapse(seq):
    out, last = [], None
    for b in seq:
        if b != last:
            out.append(b)
        last = b
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("logs", nargs="+")
    ap.add_argument("--slots", type=int, default=6)
    ap.add_argument("--policy", default="fifo", choices=["fifo", "lru", "clock", "stamp8"])
    ap.add_argument("--limit", type=int, default=16000)
    ap.add_argument("--blocks", type=int, default=0, help="a pool of this many 8 KB blocks, a bank of up to --small bytes takes one (default: banks of two blocks, --slots of them)")
    ap.add_argument("--small", type=int, default=8000)
    ap.add_argument("--banks", default=os.path.join(ROOT, "build", "game", "banks.json"))
    ap.add_argument("--write")
    ap.add_argument("--max-merges", type=int, default=60)
    a = ap.parse_args()

    banks = {b["id"]: b for b in json.load(open(a.banks))["banks"]}
    sizes = {i: b["size"] + 3 * len(b["entries"]) for i, b in banks.items()}
    sim = {"fifo": loads_fifo, "lru": loads_lru, "clock": loads_clock, "stamp8": loads_stamp8}[a.policy]
    if a.blocks:
        sim = lambda seq, n: loads_blocks(seq, a.blocks, gblocks, a.policy)
    traces = {}
    seen = set()
    for f in sorted(x for pat in a.logs for x in (glob.glob(pat) or [pat])):
        refs = bs.refs_of(f)
        key = hash(tuple(refs))
        if key in seen:
            continue
        seen.add(key)
        traces[os.path.basename(f)] = refs

    group_of = {i: i for i in banks}                    # bank -> representative
    members = {i: [i] for i in banks}
    gsize = dict(sizes)

    def cost(mapping):
        """(loads, bytes) over all traces for a bank -> group mapping"""
        nl = nb = 0
        for refs in traces.values():
            seq = collapse([mapping[b] for b in refs])
            ld = sim(seq, a.slots)
            nl += len(ld)
            nb += sum(gsize_of[g] for g in ld)
        return nl, nb

    gsize_of = gsize
    gblocks = collections.defaultdict(lambda: 2)
    def refresh_blocks():
        for g, sz in gsize.items():
            gblocks[g] = 1 if sz <= a.small else 2
    refresh_blocks()
    base = cost(group_of)
    print("before: %d loads, %d KB loaded over %d sessions" % (base[0], base[1] // 1024, len(traces)))
    cur = base
    for step in range(a.max_merges):
        adj = collections.Counter()
        for refs in traces.values():
            seq = collapse([group_of[b] for b in refs])
            for x, y in zip(seq, seq[1:]):
                adj[(min(x, y), max(x, y))] += 1
        cands = [p for p, _ in adj.most_common(60) if gsize[p[0]] + gsize[p[1]] <= a.limit]
        best = None
        for x, y in cands:
            m = dict(group_of)
            for b in members[y]:
                m[b] = x
            old_x, old_y = gsize[x], gsize.get(y)
            gsize[x] = old_x + old_y
            refresh_blocks()
            c = cost(m)
            gsize[x] = old_x
            refresh_blocks()
            if best is None or c[1] < best[0][1]:
                best = (c, x, y, m)
        if best is None or best[0][1] >= cur[1]:
            break
        (c, x, y, m) = best
        gsize[x] += gsize[y]
        members[x] += members[y]
        del members[y], gsize[y]
        refresh_blocks()
        group_of = m
        cur = c
        print("merge %-24s + %-24s -> %5d loads, %6d KB (%d bytes)" % (
            "+".join(banks[b]["name"] for b in members[x][:-len(members.get(y, [])) or None]) if False else banks[x]["name"],
            banks[y]["name"], c[0], c[1] // 1024, gsize[x]))
    groups = [[banks[b]["name"] for b in ms] for ms in members.values() if len(ms) > 1]
    print("\nafter: %d loads, %d KB loaded" % cur if False else "\nafter: %d loads, %d KB loaded (before %d, %d KB)" % (cur[0], cur[1] // 1024, base[0], base[1] // 1024))
    for g in groups:
        print("  group:", " ".join(g), "(%d bytes)" % sum(sizes[i] for i, b in banks.items() if b["name"] in g))
    if a.write:
        json.dump(groups, open(a.write, "w"), indent=1)


if __name__ == "__main__":
    main()
