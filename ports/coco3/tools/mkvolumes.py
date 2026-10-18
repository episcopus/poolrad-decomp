#!/usr/bin/env python3
"""mkvolumes.py: the data pipeline of the CoCo port (step 8.4). Turns the original game folder into volumes: one RS-DOS
floppy image each, holding one container file POOLVOL.DAT with every block of the DAX files assigned to it.

  mkvolumes.py DATA_DIR OUT_DIR [--policy data/volumes.json] [--verify]

Writes OUT_DIR/vol<N>.dsk, vol<N>.bin (the container), manifest.json, volmap.h (file name -> volume, for the engine) and
expect<N>.h (the sums the engine tests compare). The result is a pure function of the input files and the policy.
--verify rebuilds into a scratch directory (the bytes must be identical), reads every image back with the independent
reader of rsdos.py and compares every block with tools/re/dax.py's decode of the original; ITEMS (not a DAX) is block 0
of the pseudo file ITEMS. The packed bytes of a block are the original's, untouched (the engine's RLE decoder reads them).

Container (big endian, the CoCo's order):
  0   "PVOL"  4 bytes
  4   version 1, volume number          2 bytes
  6   entry count N, file name count F  2 words
  10  index length in bytes (a multiple of 256, what the engine reads at mount)  1 word
  12  4 bytes of zero
  16  F names of 8 characters (upper case, space padded, no extension)
      N entries of 10 bytes: file index, block id, offset of the packed bytes (long, from the start of the container),
      packed size (word), unpacked size (word)
  the packed blocks, back to back, from the end of the index."""
import fnmatch
import glob
import hashlib
import json
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "../../../tools/re"))
import dax  # noqa: E402
import rsdos  # noqa: E402

VOLFILE = ("POOLVOL", "DAT")


def rle_literal(data):
    """a valid stream of the game's RLE (codes 0..127 copy code+1 bytes) that only copies"""
    out = bytearray()
    for i in range(0, len(data), 128):
        c = data[i:i + 128]
        out += bytes([len(c) - 1]) + c
    return bytes(out)


def load_sources(data_dir):
    """-> {NAME: [(id, packed, raw)]} for every DAX file and ITEMS"""
    src = {}
    for path in sorted(glob.glob(os.path.join(data_dir, "*.DAX"))):
        name = os.path.basename(path)[:-4].upper()
        src[name] = [(b["id"], b["data"], b["raw"]) for b in dax.read_dax(path)]
    raw = open(os.path.join(data_dir, "ITEMS"), "rb").read()
    src["ITEMS"] = [(0, rle_literal(raw), len(raw))]
    return src


def assign(policy, names):
    where = {}
    for v in policy["volumes"]:
        for pat in v["files"]:
            hit = [n for n in names if fnmatch.fnmatchcase(n, pat)]
            if not hit:
                raise SystemExit("policy: pattern %s of volume %d matches no file" % (pat, v["num"]))
            for n in hit:
                if n in where:
                    raise SystemExit("policy: %s is in volumes %d and %d" % (n, where[n], v["num"]))
                where[n] = v["num"]
    missing = [n for n in names if n not in where]
    if missing and not policy.get("partial"):
        raise SystemExit("policy: not in any volume: " + " ".join(missing))
    return where


def build_container(num, files, src):
    """files: sorted names -> (container bytes, entries [(fileidx, id, offset, packed, raw, sum16)])"""
    nent = sum(len(src[n]) for n in files)
    idx_len = 16 + 8 * len(files) + 10 * nent
    idx_len = -(-idx_len // 256) * 256
    entries, body = [], bytearray()
    for fi, n in enumerate(files):
        for bid, packed, raw in src[n]:
            entries.append((fi, bid, idx_len + len(body), len(packed), raw))
            body += packed
    return idx_len, entries, bytes(body)


def pack(num, files, src):
    idx_len, entries, body = build_container(num, files, src)
    h = bytearray(b"PVOL" + bytes([1, num]) + struct.pack(">HHH", len(entries), len(files), idx_len) + bytes(4))
    for n in files:
        h += n.ljust(8).encode("ascii")
    for fi, bid, off, packed, raw in entries:
        h += struct.pack(">BBLHH", fi, bid, off, packed, raw)
    h += bytes(idx_len - len(h))
    return bytes(h) + body, entries


def sums(files, src):
    out = []
    for n in files:
        for bid, packed, raw in src[n]:
            out.append(sum(dax.unrle(packed)) & 0xFFFF)
    return out


def build(data_dir, policy, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    src = load_sources(data_dir)
    where = assign(policy, sorted(src))
    manifest = {"capacity": policy["capacity"], "volumes": []}
    volmap = []
    for v in policy["volumes"]:
        num = v["num"]
        files = sorted(n for n in src if where.get(n) == num)
        cont, entries = pack(num, files, src)
        if len(cont) > policy["capacity"]:
            raise SystemExit("volume %d (%s) is %d bytes, %d over the capacity of %d" % (num, v["name"], len(cont), len(cont) - policy["capacity"], policy["capacity"]))
        img = rsdos.make_image([(VOLFILE[0], VOLFILE[1], cont)])
        open("%s/vol%d.bin" % (out_dir, num), "wb").write(cont)
        open("%s/vol%d.dsk" % (out_dir, num), "wb").write(img)
        sm = sums(files, src)
        with open("%s/expect%d.h" % (out_dir, num), "w") as f:
            f.write("/* generated by tools/mkvolumes.py: the sums of the unpacked blocks of volume %d, in index order */\n" % num)
            f.write("#define EXPECT_N_%d %d\n" % (num, len(entries)))
            f.write("static const unsigned int expect_sum_%d[EXPECT_N_%d] = {%s};\n" % (num, num, ",".join(str(s) for s in sm)))
            f.write("static const unsigned int expect_raw_%d[EXPECT_N_%d] = {%s};\n" % (num, num, ",".join(str(e[4]) for e in entries)))
        for n in files:
            volmap.append((n, num))
        manifest["volumes"].append({
            "num": num, "name": v["name"], "prompt": v["prompt"], "files": files, "blocks": len(entries),
            "container_bytes": len(cont), "free_bytes": policy["capacity"] - len(cont),
            "sha256": hashlib.sha256(img).hexdigest(),
            "entries": [{"file": files[e[0]], "id": e[1], "offset": e[2], "packed": e[3], "raw": e[4], "sum16": s}
                        for e, s in zip(entries, sm)],
        })
    with open(out_dir + "/expectmulti.h", "w") as f:       # the facts t_vol3 checks across three mounted volumes
        f.write("/* generated by tools/mkvolumes.py: the first block of three files on three volumes */\n")
        for name in ("ECL2", "TITLE", "COMSPR"):
            vol = next(v for v in manifest["volumes"] if name in v["files"])
            e = next(e for e in vol["entries"] if e["file"] == name)
            f.write("#define EXPECT_%s_ID %d\n#define EXPECT_%s_SUM %d\n#define EXPECT_%s_RAW %d\n" % (name, e["id"], name, e["sum16"], name, e["raw"]))
    volmap.sort()
    with open(out_dir + "/volmap.h", "w") as f:
        f.write("/* generated by tools/mkvolumes.py: which volume holds each file (names of 8 characters, space padded) */\n")
        f.write("#define VOLMAP_N %d\n" % len(volmap))
        f.write("static const char volmap_name[] = \"%s\";\n" % "".join(n.ljust(8) for n, _ in volmap))
        f.write("static const unsigned char volmap_vol[VOLMAP_N] = {%s};\n" % ",".join(str(v) for _, v in volmap))
        f.write("static const char *const volmap_prompt[] = {%s};\n" % ",".join('"%s"' % v["prompt"] for v in policy["volumes"]))
    with open(out_dir + "/manifest.json", "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
        f.write("\n")
    return manifest


def verify(data_dir, policy, out_dir):
    import tempfile
    bad = 0
    with tempfile.TemporaryDirectory() as tmp:
        build(data_dir, policy, tmp)
        for fn in sorted(os.listdir(out_dir)):
            if fn.startswith(("vol", "expect", "manifest")) or fn == "volmap.h":
                if open(os.path.join(out_dir, fn), "rb").read() != open(os.path.join(tmp, fn), "rb").read():
                    print("not reproducible: " + fn)
                    bad += 1
    src = load_sources(data_dir)
    nblocks = nbytes = 0
    seen = set()
    for v in policy["volumes"]:
        num = v["num"]
        img = open("%s/vol%d.dsk" % (out_dir, num), "rb").read()
        files = rsdos.read_files(img)
        cont = files.get(("POOLVOL ", "DAT"))
        if cont is None or cont != open("%s/vol%d.bin" % (out_dir, num), "rb").read():
            print("volume %d: the file read back from the image differs from the container" % num)
            bad += 1
            continue
        if cont[:4] != b"PVOL" or cont[4] != 1 or cont[5] != num:
            print("volume %d: bad header" % num)
            bad += 1
            continue
        n, nf, il = struct.unpack(">HHH", cont[6:12])
        names = [cont[16 + 8 * i:24 + 8 * i].decode("ascii").strip() for i in range(nf)]
        for i in range(n):
            fi, bid, off, packed, raw = struct.unpack(">BBLHH", cont[16 + 8 * nf + 10 * i:26 + 8 * nf + 10 * i])
            name = names[fi]
            ref = [b for b in src[name] if b[0] == bid]
            if len(ref) != 1:
                print("%s block %d: not in the original" % (name, bid))
                bad += 1
                continue
            _, rpacked, rraw = ref[0]
            blk = cont[off:off + packed]
            if blk != rpacked or raw != rraw or len(dax.unrle(blk)) != raw:
                print("%s block %d: differs from the original" % (name, bid))
                bad += 1
            seen.add((name, bid))
            nblocks += 1
            nbytes += raw
    total = sum(len(b) for b in src.values())
    if len(seen) != total or nblocks != total:
        print("%d blocks in the original, %d on the volumes" % (total, len(seen)))
        bad += 1
    print("mkvolumes: %d volumes, %d blocks (%d bytes unpacked) read back from the images: %s" % (
        len(policy["volumes"]), nblocks, nbytes, "OK" if not bad else "%d problems" % bad))
    return bad


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    policy_path = os.path.join(HERE, "../data/volumes.json")
    if "--policy" in argv:
        policy_path = argv[argv.index("--policy") + 1]
        args.remove(policy_path)
    if len(args) != 2:
        print(__doc__)
        return 2
    policy = json.load(open(policy_path))
    m = build(args[0], policy, args[1])
    for v in m["volumes"]:
        print("vol%d %-7s %3d files %4d blocks %7d bytes (%6d free)  %s" % (
            v["num"], v["name"], len(v["files"]), v["blocks"], v["container_bytes"], v["free_bytes"], v["sha256"][:12]))
    if "--verify" in argv:
        return 1 if verify(args[0], policy, args[1]) else 0
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
