#!/usr/bin/env python3
"""bankpool_sim.py: how many code bank loads a run costs under other pool sizes and replacement policies (step 8.9).

Input: OUT.banklog of a run made with MB_BANKLOG=t0-t1 (lua/watch.lua): one byte per write of FC_CURBANK, i.e. the bank id
each far call enters and each return goes back to (0 = resident code, which needs nothing). The pool today is 6 banks, replaced in
turn (src/engine/api.c); `fifo 6` must give the load count the run itself reported (r9 of the mailbox dump).
Usage: bankpool_sim.py RUN.banklog [--sizes 6,8,10,12] [--bytes build/game/banks.json]
"""
import argparse
import collections
import json
import os


def events_of(path):
    """[(bank, entry)]: every write of FC_CURBANK, with the entry of the call when the write belongs to one (a restore on return has entry None)."""
    data = open(path, "rb").read()
    out, entry, hi = [], None, 0
    for i in range(0, len(data) - 1, 2):
        kind, v = data[i], data[i + 1]
        if kind == 1:
            hi = v
        elif kind == 2:
            entry = hi * 256 + v
        else:
            out.append((v, entry))
            entry = None
    return out


def refs_of(path):
    refs, last = [], None
    for b, _ in events_of(path):
        if b and b != last:
            refs.append(b)
        last = b
    return refs


def fifo(refs, n):
    pool, nxt, loads = [0] * n, 0, 0
    for b in refs:
        if b in pool:
            continue
        free = [i for i in range(n) if pool[i] == 0]
        k = free[0] if free else nxt
        pool[k] = b
        nxt = (k + 1) % n
        loads += 1
    return loads


def lru(refs, n):
    pool, loads = [], 0                       # most recent last
    for b in refs:
        if b in pool:
            pool.remove(b)
        else:
            loads += 1
            if len(pool) == n:
                pool.pop(0)
        pool.append(b)
    return loads


def opt(refs, n):
    """Belady: evict the bank used furthest ahead. The best any policy can do with n slots."""
    nxt = collections.defaultdict(list)
    for i, b in enumerate(refs):
        nxt[b].append(i)
    pos = collections.defaultdict(int)
    pool, loads = set(), 0
    for i, b in enumerate(refs):
        pos[b] += 1
        if b in pool:
            continue
        loads += 1
        if len(pool) == n:
            def next_use(x):
                p = pos[x]
                return nxt[x][p] if p < len(nxt[x]) else 1 << 60
            pool.remove(max(pool, key=next_use))
        pool.add(b)
    return loads


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("log")
    ap.add_argument("--sizes", default="4,6,8,10,12,16")
    ap.add_argument("--banks", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "game", "banks.json"))
    a = ap.parse_args()
    refs = refs_of(a.log)
    banks = {b["id"]: b for b in json.load(open(a.banks))["banks"]}
    cnt = collections.Counter(refs)
    print("%d bank transitions, %d distinct banks" % (len(refs), len(cnt)))
    print("most used banks:", ", ".join("%s %d" % (banks.get(b, {"name": "?%d" % b})["name"], c) for b, c in cnt.most_common(12)))
    print("%-6s %8s %8s %8s" % ("slots", "fifo", "lru", "opt"))
    for n in [int(x) for x in a.sizes.split(",")]:
        print("%-6d %8d %8d %8d" % (n, fifo(refs, n), lru(refs, n), opt(refs, n)))


if __name__ == "__main__":
    main()
