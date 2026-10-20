#!/usr/bin/env python3
"""seclog.py: what a run reads from the storage, by kind (step 8.9). Input: the output of a run made with MB_SECLOG=1 (lua/watch.lua prints
every sec_io request) and the image it ran on (build/game/pool.img, "PIM2": tools/mkimage.py). Prints, per kind (code banks, the core, DGROUP,
each DAX file, the save area), the requests, the sectors and the kilobytes; with --rate KBPS also the seconds the medium would need.
Usage: seclog.py RUN.out [IMAGE] [--rate 12.6] [--by-file]"""
import argparse
import collections
import re
import struct
import sys


def load_index(path):
    img = open(path, "rb").read(65536)
    assert img[:4] == b"PIM2"
    nfiles, nent, files_off, ents_off, save_lsn, save_sectors = struct.unpack(">HHIIIH", img[4:22])
    full = open(path, "rb").read()
    files = []
    for i in range(nfiles):
        name, first, cnt = struct.unpack(">8sHH", full[files_off + 12 * i:files_off + 12 * i + 12])
        files.append((name.decode("ascii").strip(), first, cnt))
    ents = []
    for i in range(nent):
        f, ident, off, packed, raw = struct.unpack(">BBIHH", full[ents_off + 10 * i:ents_off + 10 * i + 10])
        ents.append((off, packed, raw, f, ident))
    return files, ents, save_lsn, save_sectors


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("run")
    ap.add_argument("image", nargs="?", default="build/game/pool.img")
    ap.add_argument("--rate", type=float, default=0.0, help="KB/s of the medium")
    ap.add_argument("--by-file", action="store_true")
    a = ap.parse_args()
    files, ents, save_lsn, save_sectors = load_index(a.image)
    bounds = sorted(ents)
    starts = [e[0] for e in bounds]
    import bisect
    tot = collections.Counter()
    req = collections.Counter()
    for line in open(a.run, errors="replace"):
        m = re.match(r"sec cmd=(\d+) lsn=(\d+) count=(\d+)", line)
        if not m:
            continue
        cmd, lsn, cnt = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if cmd != 1:
            continue
        off = lsn * 256
        if lsn >= save_lsn:
            kind = "SAVE"
        elif lsn == 0 or off < (starts[0] if starts else 0):
            kind = "index"
        else:
            i = bisect.bisect_right(starts, off) - 1
            e = bounds[i]
            name = files[e[3]][0]
            kind = name if a.by_file else ("BANK" if name == "BANK" else "DGROUP" if name == "DGROUP" else "CORE" if name == "CORE" else "data (DAX)")
        tot[kind] += cnt
        req[kind] += 1
    allsec = sum(tot.values())
    print("%-12s %8s %8s %8s%s" % ("kind", "requests", "sectors", "KB", "  seconds" if a.rate else ""))
    for k, n in sorted(tot.items(), key=lambda kv: -kv[1]):
        print("%-12s %8d %8d %8.0f%s" % (k, req[k], n, n / 4.0, "  %7.0f" % (n / 4.0 / a.rate) if a.rate else ""))
    print("%-12s %8d %8d %8.0f%s" % ("total", sum(req.values()), allsec, allsec / 4.0, "  %7.0f" % (allsec / 4.0 / a.rate) if a.rate else ""))


if __name__ == "__main__":
    main()
