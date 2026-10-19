#!/usr/bin/env python3
"""explore_path.py: the key sequence that walks the party from the loaded saved game to a cell (a tool for writing sessions).

  .venv/bin/python tools/c/explore_path.py state.json COL ROW [FACING]

state.json is the output of the explorer's `state` command (the walls of the loaded 16x16 map). Prints `key UP` / `key LEFT` / `key RIGHT` lines. Walls: the low nibble of
`ne` is the cell's north wall, the high nibble its east wall; `sw`: low south, high west; 0 is open, 3 a door (passable)."""
import json
import sys
from collections import deque

d = json.load(open(sys.argv[1]))
ne, sw = bytes.fromhex(d["ne"]), bytes.fromhex(d["sw"])
goal = (int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]) if len(sys.argv) > 4 else None)
DX = {0: 0, 2: 1, 4: 0, 6: -1}
DY = {0: -1, 2: 0, 4: 1, 6: 0}


def wall(c, r, f):
    i = r * 16 + c
    return {0: ne[i] & 15, 2: ne[i] >> 4, 4: sw[i] & 15, 6: sw[i] >> 4}[f]


start = (d["col"], d["row"], d["facing"])
prev = {start: None}
q = deque([start])
while q:
    s = q.popleft()
    c, r, f = s
    if (c, r) == goal[:2] and (goal[2] is None or f == goal[2]):
        path = []
        while prev[s]:
            s, k = prev[s]
            path.append(k)
        for k in reversed(path):
            print("key " + k)
        sys.exit(0)
    nxt = [((c, r, (f - 2) % 8), "LEFT"), ((c, r, (f + 2) % 8), "RIGHT")]
    if wall(c, r, f) in (0, 3):
        nc, nr = c + DX[f], r + DY[f]
        if 0 <= nc < 16 and 0 <= nr < 16:
            nxt.append(((nc, nr, f), "UP"))
    for t, k in nxt:
        if t not in prev:
            prev[t] = (s, k)
            q.append(t)
sys.exit("no path")
