#!/usr/bin/env python3
"""explore_crawl.py: walk off the edges of the city maps, breadth first, and write down where each way leads (an atlas for choosing sessions).

  .venv/bin/python tools/c/explore_crawl.py [--max-maps 40] [--watch Name,Name]

Starts from the shipped saved game A. In each 16x16 map it finds a way to every border cell that is open to the outside, leaves through it on
poolrad_explore (the C translation, about a second a try) and reads the map it arrives in (the explorer's `state` command). It writes
build/explore/atlas.json (maps with their planes, the key script that reaches each, the exits seen, the area view kind and the routines of
--watch that were entered on the way). Not a test."""
import argparse
import json
import os
import re
import subprocess
from collections import deque

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
EXE = os.path.join(ROOT, "build/cmake-trace/poolrad_explore")
PREFIX = ["clock 12:00:16.58", "wheel", "wait 20", "key L", "wait 20", "key A", "wait 300"]
DX = {0: 0, 2: 1, 4: 0, 6: -1}
DY = {0: -1, 2: 0, 4: 1, 6: 0}


def run(lines, watch=""):
    path = os.path.join(ROOT, "build/explore/crawl.keys")
    open(path, "w").write("\n".join(lines) + "\n")
    p = subprocess.run([EXE, "--data", os.path.join(ROOT, "poolrad"), "--save", os.path.join(ROOT, "build/explore/crawl-save"), "--script", path,
                        "--out", os.path.join(ROOT, "build/explore/crawl"), "--max-polls", "9000000"], capture_output=True, text=True,
                       env=dict(os.environ, EXPLORE_WATCH=watch), timeout=120)
    hits = re.findall(r"^HIT (\w+) col (-?\d+) row (-?\d+) facing (\d+)", p.stderr, re.M)
    try:
        st = json.load(open(os.path.join(ROOT, "build/explore/crawl-end.json")))
    except Exception:
        st = None
    return st, hits


def wall(d, c, r, f):
    ne, sw = bytes.fromhex(d["ne"]), bytes.fromhex(d["sw"])
    i = r * 16 + c
    return {0: ne[i] & 15, 2: ne[i] >> 4, 4: sw[i] & 15, 6: sw[i] >> 4}[f]


def path_in(d, start, goal):
    prev = {start: None}
    q = deque([start])
    while q:
        s = q.popleft()
        c, r, f = s
        if (c, r, f) == goal:
            keys = []
            while prev[s]:
                s, k = prev[s]
                keys.append(k)
            return list(reversed(keys))
        nxt = [((c, r, (f - 2) % 8), "LEFT"), ((c, r, (f + 2) % 8), "RIGHT")]
        if wall(d, c, r, f) in (0, 3):
            nc, nr = c + DX[f], r + DY[f]
            if 0 <= nc < 16 and 0 <= nr < 16:
                nxt.append(((nc, nr, f), "UP"))
        for t, k in nxt:
            if t not in prev:
                prev[t] = (s, k)
                q.append(t)
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-maps", type=int, default=40)
    ap.add_argument("--watch", default="ShopMain,VisitTemple,RunCombat,TrainCharacter,DrawAreaView,EndBattle")
    a = ap.parse_args()
    st, _ = run(PREFIX + ["state end", "quit"])
    atlas = {}
    queue = deque()

    def add(st, script, via):
        key = "%d" % st["geoblock"] if st["areaview"] == 1 else "view%d" % st["areaview"]
        if key in atlas:
            return False
        atlas[key] = {"geoblock": st["geoblock"], "areaview": st["areaview"], "entry": [st["col"], st["row"], st["facing"]], "script": script, "via": via,
                      "ne": st["ne"], "sw": st["sw"], "events": st["events"], "cells": st["cells"], "exits": {}, "hits": []}
        queue.append(key)
        return True

    add(st, [], "start")
    while queue and len(atlas) < a.max_maps:
        key = queue.popleft()
        m = atlas[key]
        if m["areaview"] != 1:
            continue
        d = {"ne": m["ne"], "sw": m["sw"]}
        entry = tuple(m["entry"])
        for edge, cells in (("N", [(c, 0, 0) for c in range(16)]), ("S", [(c, 15, 4) for c in range(16)]),
                            ("W", [(0, r, 6) for r in range(16)]), ("E", [(15, r, 2) for r in range(16)])):
            for c, r, f in cells:
                if wall(d, c, r, f) not in (0, 3):
                    continue
                p = path_in(d, entry, (c, r, f))
                if p is None:
                    continue
                script = PREFIX + m["script"] + sum((["press " + k, "wait 2"] for k in p), []) + ["press UP", "wait 40", "state end", "quit"]
                st, hits = run(script, a.watch)
                if not st:
                    continue
                m["exits"]["%s%d,%d" % (edge, c, r)] = {"to": st["geoblock"], "areaview": st["areaview"], "at": [st["col"], st["row"], st["facing"]]}
                m["hits"] += [list(h) for h in hits]
                if add(st, m["script"] + sum((["press " + k, "wait 2"] for k in p), []) + ["press UP", "wait 40"], "%s via %s %d,%d" % (key, edge, c, r)):
                    print("map %s: new map %s (%s) through %s %d,%d, %d maps" % (key, st["geoblock"], "area view %d" % st["areaview"], edge, c, r, len(atlas)), flush=True)
                break                      # one way out per edge is enough to find the neighbours
    json.dump(atlas, open(os.path.join(ROOT, "build/explore/atlas.json"), "w"))
    for k, m in atlas.items():
        print(k, "entry", m["entry"], "via", m["via"], "exits", {e: v["to"] for e, v in m["exits"].items()})


if __name__ == "__main__":
    main()
