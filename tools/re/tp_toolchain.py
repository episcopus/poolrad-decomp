#!/usr/bin/env python3
"""tp_toolchain.py: pin the Turbo Pascal version that built POOL by byte comparison.

The runtime units (System, Crt, Dos, Overlay) are linked into start-unpack.exe from the
compiler's TURBO.TPL. We compile a probe program with each candidate compiler and align
our unit code against the probe's, classifying every differing byte:

  equal        identical byte
  reloc        segment fixup word (MZ relocation table) on either side
  near-branch  E8/E9 rel16 whose targets correspond under the alignment (routines between
               caller and callee were dropped or added by the smart linker)
  far-target   offset word of a far pointer/call into another runtime unit whose targets
               correspond under that unit's alignment
  code-offset  absolute in-segment code offset whose targets correspond
  data-ref     DGROUP operand that differs by one of the unit's data-layout deltas
               (our DGROUP holds the game's data too, so every variable moved)
  padding      zero bytes after the unit's last routine, up to the paragraph boundary
  ref-only     bytes only in the probe: routines POOL never calls (smart linker dropped them)
  ours-only    bytes only in POOL: a routine the probe does not pull in (extend the probe)
  unexplained  anything else: a real code difference

A candidate matches a unit when ours-only and unexplained are both zero.

Subcommands (all from the repository root):
  install   check build/toolchain/dist/* against tools/re/tp_toolchain.toml, extract
            TPC.EXE and TURBO.TPL into build/toolchain/<ver>/BIN/
  probe     compile tools/re/tp_probe/SINK.PAS with each installed version into
            build/toolchain/probe/<ver>/ (emu2 by default, DOSBox-X with --emu dosbox-x)
  compare   write build/toolchain/compare.md and compare.json; exit 0 when exactly one
            candidate matches the System unit
  all       install, probe, compare
  tpc       compile any Pascal file with the pinned compiler (or --version) into
            build/tpc/<version>/<name>/ with a detailed map; --disasm prints the
            program's code with line numbers. Use it to see how TP 6.0 compiles an
            idiom (playbooks 30 and 70) and for track M (SPEC 4.3).

Needs: Python 3.11+, Info-ZIP `unzip` (PKZIP implode), emu2 (tools/setup/build-emu2.sh)
or DOSBox-X. Nothing is written outside build/.
"""
from __future__ import annotations

import argparse
import collections
import difflib
import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "tools/re/tp_toolchain.toml"
TC = ROOT / "build/toolchain"
DIST = TC / "dist"
PROBE_SRC = ROOT / "tools/re/tp_probe"
EXE = ROOT / "poolrad/start-unpack.exe"
LOAD_SEG = 0x1000  # Ghidra / smoke load segment; image paragraph P is at (LOAD_SEG + P)
DGROUP_PARA = 0x0C7C
UNITS = ("SYSTEM", "CRT", "DOS", "OVERLAY")
TPC_ARGS = ["/B", "/GS", "/GP", "SINK.PAS"]


def sha1(b: bytes) -> str:
    return hashlib.sha1(b).hexdigest()


def manifest() -> dict:
    return tomllib.loads(MANIFEST.read_text())["version"]


def pinned_version() -> str:
    return tomllib.loads(MANIFEST.read_text())["pinned"]


# ---------------------------------------------------------------- install

def fat12_read(img: bytes, name: str) -> bytes:
    """Read one file from the root directory of a FAT12 floppy image."""
    u16 = lambda o: struct.unpack_from("<H", img, o)[0]
    bps, spc, rsv, nfats, nroot, spf = u16(11), img[13], u16(14), img[16], u16(17), u16(22)
    fat, root = rsv * bps, (rsv + nfats * spf) * bps
    data = root + nroot * 32
    for i in range(nroot):
        e = img[root + 32 * i: root + 32 * i + 32]
        if e[0] in (0, 0xE5) or e[11] & 0x18:
            continue
        base, ext = e[0:8].decode("ascii").rstrip(), e[8:11].decode("ascii").rstrip()
        if (base + ("." + ext if ext else "")).upper() != name.upper():
            continue
        out = bytearray()
        clus = struct.unpack_from("<H", e, 26)[0]
        size = struct.unpack_from("<I", e, 28)[0]
        while 2 <= clus < 0xFF8:
            off = data + (clus - 2) * spc * bps
            out += img[off: off + spc * bps]
            v = u16(fat + clus * 3 // 2)
            clus = (v >> 4) if clus & 1 else (v & 0xFFF)
        return bytes(out[:size])
    raise SystemExit("%s: not found in FAT12 image" % name)


def unzip_member(archive: Path, member: str) -> bytes:
    """Extract one member with Info-ZIP unzip (handles PKZIP 1.x implode and SFX stubs)."""
    if not shutil.which("unzip"):
        raise SystemExit("install: Info-ZIP `unzip` not found")
    r = subprocess.run(["unzip", "-p", str(archive), member], capture_output=True)
    if r.returncode != 0 or not r.stdout:
        raise SystemExit("install: unzip -p %s %s failed: %s" % (archive, member, r.stderr.decode()[:200]))
    return r.stdout


def cmd_install(args) -> int:
    ok = True
    for ver, spec in manifest().items():
        if args.versions and ver not in args.versions:
            continue
        missing = []
        for d in spec["dist"]:
            p = DIST / d["path"]
            if not p.exists():
                (None if d.get("optional") else missing.append(d))
                continue
            got = sha1(p.read_bytes())
            if got != d["sha1"]:
                print("FAIL %-10s %s sha1 %s, expected %s" % (ver, d["path"], got, d["sha1"]))
                ok = False
        if missing:
            print("skip %-10s missing %s (see docs/setup/SETUP-tp.md)" % (ver, ", ".join(m["path"] for m in missing)))
            continue
        kind, src, inner = spec["extract"]["container"].split(":", 2)
        srcb = (DIST / src).read_bytes()
        cont = fat12_read(srcb, inner) if kind == "fat12" else None
        with tempfile.TemporaryDirectory() as tmp:
            if kind == "zip":
                cont = unzip_member(DIST / src, inner)
            if sha1(cont) != spec["extract"]["sha1_container"]:
                print("FAIL %-10s container %s sha1 %s" % (ver, inner, sha1(cont)))
                ok = False
                continue
            cpath = Path(tmp) / "container.zip"
            cpath.write_bytes(cont)
            out = TC / ver / "BIN"
            out.mkdir(parents=True, exist_ok=True)
            for name, f in spec["files"].items():
                b = unzip_member(cpath, f["member"])
                if len(b) != f["bytes"] or sha1(b) != f["sha1"]:
                    print("FAIL %-10s %s sha1 %s (%d bytes)" % (ver, name, sha1(b), len(b)))
                    ok = False
                    continue
                (out / name).write_bytes(b)
        print("ok   %-10s %s" % (ver, out.relative_to(ROOT)))
    return 0 if ok else 1


# ---------------------------------------------------------------- probe

def find_emulator(choice: str | None) -> tuple[str, str]:
    if choice in (None, "emu2"):
        for c in (os.environ.get("EMU2"), str(ROOT / "tools/vendor/emu2/emu2"), shutil.which("emu2")):
            if c and Path(c).exists():
                return "emu2", c
        if choice == "emu2":
            raise SystemExit("probe: emu2 not found; run tools/setup/build-emu2.sh")
    for c in (os.environ.get("DOSBOX_X"), shutil.which("dosbox-x"),
              "/Applications/dosbox-x.app/Contents/MacOS/dosbox-x"):
        if c and Path(c).exists():
            return "dosbox-x", c
    raise SystemExit("probe: no DOS emulator (emu2 or dosbox-x) found")


def ci(d: Path, name: str) -> Path | None:
    """Case-insensitive lookup (emu2 writes lower-case names, DOSBox-X upper-case)."""
    return next((p for p in d.iterdir() if p.name.upper() == name), None) if d.is_dir() else None


def run_tpc(kind: str, emu: str, w: Path, tpc_args: list[str]) -> str:
    """Run TPC.EXE in directory w under emu2 or DOSBox-X; return the compiler log.
    Outputs of an earlier run are removed first, so a failed compile cannot pass on a
    stale log or EXE (the two emulators also differ in name case, which would leave
    both spellings side by side)."""
    for p in w.iterdir():
        if p.name.upper() != "TPC.EXE" and p.suffix.upper() in (".LOG", ".EXE", ".MAP", ".OVR", ".TPU"):
            p.unlink()
    if kind == "emu2":
        r = subprocess.run([emu, "TPC.EXE", *tpc_args], cwd=w, capture_output=True)
        (w / "TPC.LOG").write_bytes(r.stdout + r.stderr)
    else:  # DOSBox-X, headless batch run
        cmd = " ".join(["TPC.EXE", *tpc_args]) + " > TPC.LOG"
        subprocess.run([emu, "-silent", "-nogui", "-nomenu", "-exit",
                        "-c", 'mount c "%s"' % w, "-c", "c:", "-c", cmd, "-c", "exit"],
                       capture_output=True)
    log = ci(w, "TPC.LOG")
    return log.read_bytes().decode("latin-1").replace("\r", "\n") if log else ""


def compiled_ok(log: str) -> bool:
    """True when the compiler log ends in its success summary and reports no error.
    The elapsed-time field is optional: emu2 gives `66 lines, 4384 bytes code, ...`,
    DOSBox-X gives `167 lines, 0.2 seconds, 17552 bytes code, ...`."""
    return bool(re.search(r"\d+ lines, (?:[\d.]+ seconds, )?\d+ bytes code", log)) and "Error" not in log


def cmd_tpc(args) -> int:
    """Compile one Pascal source with a pinned compiler; sibling .PAS/.INC/.OBJ files
    are copied too so units and includes resolve."""
    ver = args.version or pinned_version()
    bin_dir = TC / ver / "BIN"
    if not (bin_dir / "TPC.EXE").exists():
        raise SystemExit("tpc: %s not installed; run `make tp-install` (docs/setup/SETUP-tp.md)" % ver)
    src = Path(args.src).resolve()
    stem = src.stem.upper()
    if not src.exists() or len(stem) > 8 or src.suffix.upper() != ".PAS":
        raise SystemExit("tpc: need an existing 8.3 .PAS file, got %s" % args.src)
    kind, emu = find_emulator(args.emu)
    w = ROOT / "build/tpc" / ver / stem
    w.mkdir(parents=True, exist_ok=True)
    for f in ("TPC.EXE", "TURBO.TPL"):
        shutil.copy(bin_dir / f, w / f)
    for f in src.parent.iterdir():
        if f.suffix.upper() in (".PAS", ".INC", ".OBJ") and len(f.stem) <= 8:
            shutil.copy(f, w / f.name.upper())
    log = run_tpc(kind, emu, w, ["/B", "/GD", *args.opts, stem + ".PAS"])
    exe, mapf = ci(w, stem + ".EXE"), ci(w, stem + ".MAP")
    ok = exe is not None and compiled_ok(log)
    print("\n".join(l for l in log.splitlines() if l.strip() and not re.fullmatch(r"\S+\(\d+\)", l.strip())))
    if not ok:
        return 1
    print("tpc: %s -> %s, %s" % (ver, exe.relative_to(ROOT), mapf.relative_to(ROOT)))
    if args.disasm:
        disasm_program(exe, mapf)
    return 0


def disasm_program(exe: Path, mapf: Path) -> None:
    """Disassemble the program's own code segment (the first CODE segment in the map),
    marking source lines from the map's line-number table."""
    try:
        from capstone import Cs, CS_ARCH_X86, CS_MODE_16
    except ImportError:
        print("tpc: --disasm needs capstone (uv sync)")
        return
    img, _ = read_mz(exe)
    segs, _ = read_map(mapf)
    code = [(v[0], v[1], k) for k, v in segs.items() if v[2] == "CODE"]
    start, length, name = min(code)
    seg = start >> 4
    lines = {}
    for m in re.finditer(r"(\d+) ([0-9A-F]{4}):([0-9A-F]{4})", mapf.read_text(errors="replace")):
        if int(m.group(2), 16) == seg:
            lines.setdefault(int(m.group(3), 16), []).append(m.group(1))
    print("; %s code segment %04X, %d bytes (instructions from each source line; other bytes are data)"
          % (name, seg, length))
    md = Cs(CS_ARCH_X86, CS_MODE_16)
    code_bytes = img[start:start + length]
    rtl = runtime_names(img, segs)
    marks = sorted(lines) + [length]

    def db(a: int, b: int) -> None:
        for k in range(a, b, 16):
            print("%04X:%04X  db %s" % (seg, k, code_bytes[k:min(k + 16, b)].hex(" ")))

    db(0, marks[0])
    for a, b in zip(marks, marks[1:]):
        print("; line %s" % ", ".join(lines[a]))
        pos = a
        for i in md.disasm(code_bytes[a:b], a):
            note = ""
            m = re.fullmatch(r"0x([0-9a-f]+), 0x([0-9a-f]+)", i.op_str) if i.mnemonic == "lcall" else None
            if m and (int(m.group(1), 16), int(m.group(2), 16)) in rtl:
                note = "  ; " + rtl[(int(m.group(1), 16), int(m.group(2), 16))]
            print("%04X:%04X  %-14s %s %s%s" % (seg, i.address, i.bytes.hex(), i.mnemonic, i.op_str, note))
            pos = i.address + i.size
            if i.mnemonic in ("ret", "retf"):
                break
        db(pos, b)


def runtime_names(img: bytes, segs: dict) -> dict[tuple[int, int], str]:
    """Map far-call targets in a freshly compiled program's runtime units to the same
    routine in POOL, with its name from re/symbols.toml. Every key is the entry of a POOL
    runtime routine found in the fresh unit (`runtime_entries`), never an offset that only
    happens to sit at the same place in the byte alignment."""
    out: dict[tuple[int, int], str] = {}
    try:
        ours_img, _ = read_mz(EXE)
        units = tomllib.loads((ROOT / "re/units.toml").read_text())["resident"]
        sym = tomllib.loads((ROOT / "re/symbols.toml").read_text()).get("routine", [])
    except (OSError, tomllib.TOMLDecodeError, KeyError):
        return out
    names = {r["id"]: r["name"] for r in sym}
    for u in units:
        uname = u.get("name", "").upper()
        if uname not in UNITS or uname not in segs:
            continue
        a = int(u["code_start"].split(":")[0], 16)
        b = int(u["code_end"].split(":")[0], 16)
        rs, rl, _ = segs[uname]
        entries = sorted(int(rid[5:], 16) for rid in names if rid.startswith("%04X:" % a))
        for rv, uv in runtime_entries(ours_img[a * 16:b * 16], img[rs:rs + rl], entries).items():
            rid = "%04X:%04X" % (a, uv)
            out[(rs >> 4, rv)] = "%s (POOL %s)" % (names[rid], rid)
    return out


def runtime_entries(U: bytes, R: bytes, entries: list[int]) -> dict[int, int]:
    """Find POOL's runtime routines (entries: offsets in U, POOL's unit) in a fresh build
    of the same unit (R); return {offset in R: entry in U}, one to one.

    A plain byte alignment (`align_unit`) cannot be read at a routine entry: when the smart
    linker dropped routines from R, a short common prefix (TP's `mov bx,sp`) glues onto the
    preceding equal block and lands on the entry of a dropped neighbour (Move resolved as
    Assign). So each routine is placed by its whole body instead: every aligned byte of the
    routine votes for where its entry lies in R. A routine is found only when
      - most of its bytes are present in R: aligned, or in a same-length difference (link-time
        address fields), not in a region R lacks (a routine the linker dropped), and
      - the aligned bytes agree: a strict majority of them votes for one entry.
    An offset of R claimed by two routines resolves to neither."""
    regs = regions(U, R)
    pos, present = {}, set()
    for tag, i1, i2, j1, j2 in regs:
        if tag == "equal":
            for k in range(i2 - i1):
                pos[i1 + k] = j1 + k
        if tag == "equal" or i2 - i1 == j2 - j1:
            present.update(range(i1, i2))
    found: dict[int, list[int]] = collections.defaultdict(list)
    for e, end in zip(entries, entries[1:] + [len(U)]):
        votes = collections.Counter(pos[x] - (x - e) for x in range(e, end) if x in pos)
        if not votes:
            continue
        (t, c), = votes.most_common(1)
        here = sum(1 for x in range(e, end) if x in present)
        if 2 * c > sum(votes.values()) and 2 * here > end - e and 0 <= t < len(R):
            found[t].append(e)
    return {t: es[0] for t, es in found.items() if len(es) == 1}


def cmd_probe(args) -> int:
    kind, emu = find_emulator(args.emu)
    rc = 0
    for ver in manifest():
        if args.versions and ver not in args.versions:
            continue
        bin_dir = TC / ver / "BIN"
        if not (bin_dir / "TPC.EXE").exists():
            print("skip %-10s not installed" % ver)
            continue
        w = TC / "probe" / ver
        w.mkdir(parents=True, exist_ok=True)
        for f in ("TPC.EXE", "TURBO.TPL"):
            shutil.copy(bin_dir / f, w / f)
        for f in PROBE_SRC.glob("*.PAS"):
            shutil.copy(f, w / f.name)
        log = run_tpc(kind, emu, w, TPC_ARGS)
        exe = ci(w, "SINK.EXE")
        ok = exe is not None and compiled_ok(log)
        if not ok:
            print("FAIL %-10s compile failed:\n%s" % (ver, log[-600:]))
            rc = 1
            continue
        banner = next((l.strip() for l in log.splitlines() if "Turbo Pascal" in l), "?")
        ovr = ci(w, "SINK.OVR")
        ovr = ovr.read_bytes()[:4] if ovr else b""
        print("ok   %-10s %s; SINK.EXE %d bytes; overlay signature %r" % (ver, banner, exe.stat().st_size, ovr))
    return rc


# ---------------------------------------------------------------- compare

def read_mz(path: Path) -> tuple[bytes, set[int]]:
    d = path.read_bytes()
    last, pages, nrel, hdrp = struct.unpack_from("<HHHH", d, 2)
    size = pages * 512 if last in (0, 512) else (pages - 1) * 512 + last
    ro = struct.unpack_from("<H", d, 0x18)[0]
    rel = set()
    for i in range(nrel):
        o, s = struct.unpack_from("<HH", d, ro + 4 * i)
        rel.add(s * 16 + o)
    return d[hdrp * 16: size], rel


def read_map(path: Path) -> tuple[dict, dict]:
    segs, pubs = {}, {}
    for line in path.read_text(errors="replace").splitlines():
        m = re.match(r"\s*([0-9A-F]{5})H ([0-9A-F]{5})H ([0-9A-F]{5})H (\S+)\s+(\S+)", line)
        if m:
            segs[m.group(4).upper()] = (int(m.group(1), 16), int(m.group(3), 16), m.group(5))
            continue
        m = re.match(r"\s*([0-9A-F]{4}):([0-9A-F]{4})\s+(\S+)", line)
        if m:
            pubs[m.group(3).upper()] = (int(m.group(1), 16), int(m.group(2), 16))
    return segs, pubs


def locate(ours: bytes, ref: bytes, k: int = 10) -> tuple[int, int] | None:
    """Paragraph range of the densest cluster of ref k-mers inside our image."""
    ks = {ref[i:i + k] for i in range(len(ref) - k)}
    hits = [i >> 4 for i in range(len(ours) - k) if ours[i:i + k] in ks]
    clusters: list[list[int]] = []
    for p in sorted(set(hits)):
        if clusters and p - clusters[-1][1] <= 8:
            clusters[-1][1] = p
        else:
            clusters.append([p, p])
    if not clusters:
        return None
    cnt = collections.Counter(hits)
    best = max(clusters, key=lambda c: sum(cnt[p] for p in range(c[0], c[1] + 1)))
    return best[0], best[1]


def word(b: bytes, o: int) -> int | None:
    return b[o] | (b[o + 1] << 8) if 0 <= o and o + 1 < len(b) else None


class Side:
    def __init__(self, img: bytes, rel: set[int], ranges: dict[str, tuple[int, int]]):
        self.img, self.rel, self.ranges = img, rel, ranges  # ranges: unit -> (start byte, length)

    def unit_of_para(self, para: int) -> str | None:
        for u, (s, l) in self.ranges.items():
            if s <= para * 16 < s + l:
                return u
        return None


def regions(U: bytes, R: bytes) -> list[tuple]:
    ops = difflib.SequenceMatcher(None, U, R, autojunk=False).get_opcodes()
    out, cur = [], None
    for idx, (tag, i1, i2, j1, j2) in enumerate(ops):
        small = tag == "equal" and (i2 - i1) < 4 and 0 < idx < len(ops) - 1
        if tag == "equal" and not small:
            if cur:
                out.append(("diff", *cur))
                cur = None
            out.append(("equal", i1, i2, j1, j2))
        elif cur:
            cur[1], cur[3] = i2, j2
        else:
            cur = [i1, i2, j1, j2]
    if cur:
        out.append(("diff", *cur))
    return out


def align_unit(U: bytes, R: bytes) -> tuple[list, dict]:
    regs = regions(U, R)
    m = {}
    for r in regs:
        if r[0] == "equal":
            for k in range(r[2] - r[1]):
                m[r[1] + k] = r[3] + k
    return regs, m


def classify(unit, ours: Side, ref: Side, maps: dict) -> dict:
    us, ul = ours.ranges[unit]
    rs, rl = ref.ranges[unit]
    U, R = ours.img[us:us + ul], ref.img[rs:rs + rl]
    urel = {x - us for x in ours.rel if us <= x < us + ul}
    rrel = {x - rs for x in ref.rel if rs <= x < rs + rl}
    regs, m = maps[unit]
    pairs: dict[int, collections.Counter] = collections.defaultdict(collections.Counter)

    def explain(w: int, jw: int, deltas):
        uv, rv = word(U, w), word(R, jw)
        if uv is None or rv is None:
            return None
        if w in urel or jw in rrel:
            return "reloc"
        if w > 0 and jw > 0 and U[w - 1] in (0xE8, 0xE9) and R[jw - 1] == U[w - 1] \
                and m.get((w + 2 + uv) & 0xFFFF) == (jw + 2 + rv) & 0xFFFF:
            return "near-branch"
        if (w + 2) in urel and (jw + 2) in rrel:  # far pointer: offset then segment fixup
            tu = ours.unit_of_para(word(U, w + 2) or 0)
            tr = ref.unit_of_para(word(R, jw + 2) or 0)
            if tu and tu == tr and tu in maps and maps[tu][1].get(uv) == rv:
                return "far-target"
        if m.get(uv) == rv and uv != rv:
            return "code-offset"
        if deltas is None:
            return ("delta", (uv - rv) & 0xFFFF)
        if (uv - rv) & 0xFFFF in deltas:
            pairs[rv][uv] += 1
            return "data-ref"
        return None

    def same_len(i1, i2, j1, cls, unexpl, deltas):
        k = i1
        while k < i2:
            jk = j1 + k - i1
            if U[k] == R[jk]:
                cls["equal"] += 1
                k += 1
                continue
            got = None
            for w in (k, k - 1):
                e = explain(w, j1 + w - i1, deltas)
                if e and not isinstance(e, tuple):
                    got = (w, e)
                    break
            if got:
                w, e = got
                n = min(w + 2, i2) - k
                cls[e] += n
                k += n
            else:
                cls["unexplained"] += 1
                unexpl.append((k, jk))
                k += 1

    # pass 1: data-layout deltas from words where both bytes differ
    hist = collections.Counter()
    for r in regs:
        if r[0] == "diff" and r[2] - r[1] == r[4] - r[3]:
            for k in range(r[1], r[2] - 1):
                jk = r[3] + k - r[1]
                if U[k] != R[jk] and U[k + 1] != R[jk + 1]:
                    e = explain(k, jk, None)
                    if isinstance(e, tuple):
                        hist[e[1]] += 1
    deltas = {d for d, c in hist.items() if c >= 3}

    cls, unexpl, ours_only = collections.Counter(), [], []
    if regs and regs[-1][0] == "diff" and regs[-1][2] == len(U):
        tag, i1, i2, j1, j2 = regs[-1]
        z = 0
        while z < 15 and i2 - z > i1 and U[i2 - z - 1] == 0:
            z += 1
        if z:  # zero padding up to the next paragraph after the unit's last routine
            cls["padding"] += z
            regs = regs[:-1] + [(tag, i1, i2 - z, j1, j2)]
    for tag, i1, i2, j1, j2 in regs:
        if tag == "equal":
            cls["equal"] += i2 - i1
            continue
        n, L = i2 - i1, j2 - j1
        if n == 0:
            cls["ref-only"] += L
            continue
        if n == L:
            same_len(i1, i2, j1, cls, unexpl, deltas)
            continue
        if n > L and i2 == len(U) and not any(U[i1 + L:i2]) and n - L < 16:
            same_len(i1, i1 + L, j1, cls, unexpl, deltas)  # trailing paragraph padding
            cls["padding"] += n - L
            continue
        # unequal lengths: one side has extra routine(s); try every split point
        best = None
        short = min(n, L)
        for s in range(short + 1):
            c2, u2 = collections.Counter(), []
            same_len(i1, i1 + s, j1, c2, u2, deltas)
            t = short - s
            same_len(i2 - t, i2, j2 - t, c2, u2, deltas)
            if best is None or len(u2) < len(best[1]):
                best = (c2, u2, s)
            if not u2:
                break
        c2, u2, s = best
        cls.update(c2)
        unexpl.extend(u2)
        if L > n:
            cls["ref-only"] += L - n
        else:
            cls["ours-only"] += n - L
            ours_only.append((i1 + s, n - L))
    total = len(U)
    return {
        "unit": unit, "ours_bytes": total, "ref_bytes": len(R), "classes": dict(cls),
        "deltas": sorted(deltas), "unexplained": unexpl[:50], "unexplained_count": len(unexpl),
        "ours_only": ours_only, "pairs": {rv: c.most_common(1)[0][0] for rv, c in pairs.items()},
        "match": cls["unexplained"] == 0 and cls["ours-only"] == 0,
    }


def score(c: dict) -> int:
    k = c["classes"]
    return k.get("unexplained", 0) + k.get("ours-only", 0)


def unit_ranges(ours: Side, ref: Side, starts: dict[str, int]) -> dict[str, tuple[int, int]]:
    order = sorted(starts.items(), key=lambda kv: kv[1])
    out = {}
    for i, (u, p) in enumerate(order):
        end = order[i + 1][1] if i + 1 < len(order) else DGROUP_PARA
        out[u] = (p * 16, (end - p) * 16)
    return out


def classify_all(ours_img, ours_rel, ref: Side, starts) -> dict:
    ours = Side(ours_img, ours_rel, unit_ranges(None, ref, starts))
    maps = {u: align_unit(ours_img[s:s + l], ref.img[ref.ranges[u][0]:sum(ref.ranges[u])])
            for u, (s, l) in ours.ranges.items()}
    return ours, {u: classify(u, ours, ref, maps) for u in ours.ranges}


def locate_units(ours_img, ours_rel, ref: Side) -> tuple[dict[str, int], int]:
    """Our start paragraph per runtime unit: densest k-mer cluster, then the start in
    [p-3, p] that leaves the fewest unexplained bytes (code segments start on paragraphs)."""
    starts = {}
    for u in UNITS:
        loc = locate(ours_img, ref.img[ref.ranges[u][0]:sum(ref.ranges[u])])
        if loc:
            starts[u] = loc[0]
    for u in sorted(starts, key=lambda x: starts[x]):
        best = None
        for cand in range(starts[u] - 3, starts[u] + 1):
            trial = dict(starts, **{u: cand})
            if sorted(trial.values()) != sorted(set(trial.values())):
                continue
            _, res = classify_all(ours_img, ours_rel, ref, trial)
            sc = score(res[u])
            prev = [v for k, v in res.items() if k != u and trial[k] < cand]
            sc += sum(score(v) for v in prev)
            if best is None or sc <= best[0]:
                best = (sc, cand)
        starts[u] = best[1]
    _, res = classify_all(ours_img, ours_rel, ref, starts)
    return starts, sum(score(v) for v in res.values())


def fmt_addr(img_off: int) -> str:
    return "%04X:%04X" % (img_off >> 4, img_off & 15)


def cmd_compare(args) -> int:
    ours_img, ours_rel = read_mz(EXE)
    refs = {}
    for ver in manifest():
        w = TC / "probe" / ver
        exe, mapf, ovrf = ci(w, "SINK.EXE"), ci(w, "SINK.MAP"), ci(w, "SINK.OVR")
        if not (exe and mapf):
            continue
        rimg, rrel = read_mz(exe)
        segs, pubs = read_map(mapf)
        refs[ver] = (Side(rimg, rrel, {u: (segs[u][0], segs[u][1]) for u in UNITS}), segs, pubs, exe, ovrf)
    if not refs:
        print("compare: no probe builds; run `make tp-probe`")
        return 2
    # One set of our unit ranges for every candidate: per unit, take the start found
    # with the candidate that explains that unit best.
    located = {v: locate_units(ours_img, ours_rel, r[0]) for v, r in refs.items()}
    starts = {}
    for u in UNITS:
        opts = []
        for v, (st, _) in located.items():
            if u in st:
                _, res = classify_all(ours_img, ours_rel, refs[v][0], st)
                opts.append((score(res[u]), st[u]))
        if opts:
            starts[u] = min(opts)[1]
    try:  # cross-check against re/units.toml (runtime units, WHITEPAPER 2.2)
        table = {u["name"].upper(): int(u["code_start"].split(":")[0], 16)
                 for u in tomllib.loads((ROOT / "re/units.toml").read_text())["resident"]}
        for u, p in starts.items():
            if table.get(u) != p:
                print("WARN %s located at %04X but re/units.toml says %s" % (u, p, "%04X" % table[u] if u in table else "nothing"))
    except (OSError, tomllib.TOMLDecodeError, KeyError):
        pass
    results = {}
    for ver, (ref, segs, pubs, exe, ovrf) in refs.items():
        ours, units = classify_all(ours_img, ours_rel, ref, starts)
        data_seg = segs["DATA"][0] >> 4
        sysvars = {name: units["SYSTEM"]["pairs"][off] for name, (seg, off) in pubs.items()
                   if seg == data_seg and off in units["SYSTEM"]["pairs"]}
        ovr = ovrf.read_bytes()[:4].decode("latin-1") if ovrf else "?"
        results[ver] = {"ranges": {u: [fmt_addr(s), fmt_addr(s + l)] for u, (s, l) in ours.ranges.items()},
                        "units": units, "system_vars": sysvars, "ovr_signature": ovr,
                        "probe_sha1": sha1(exe.read_bytes())}
    sys_match = [v for v, r in results.items() if r["units"]["SYSTEM"]["match"]]
    write_report(results, sys_match)
    for v, r in results.items():
        line = []
        for u in UNITS:
            if u not in r["units"]:
                continue
            x = r["units"][u]
            c = x["classes"]
            line.append("%s %s (unexpl %d, ours-only %d)" % (u, "MATCH" if x["match"] else "differs",
                                                            c.get("unexplained", 0), c.get("ours-only", 0)))
        print("%-10s %s" % (v, "; ".join(line)))
    print("System unit matches: %s" % (", ".join(sys_match) or "none"))
    print("report: build/toolchain/compare.md")
    return 0 if len(sys_match) == 1 else 1


def write_report(results: dict, sys_match: list[str]) -> None:
    TC.mkdir(parents=True, exist_ok=True)
    (TC / "compare.json").write_text(json.dumps(results, indent=1, default=str))
    L = ["# Turbo Pascal runtime comparison", "",
         "Generated by `tools/re/tp_toolchain.py compare` against `poolrad/start-unpack.exe` "
         "(addresses are load-image paragraphs; add 1000h for Ghidra/smoke).", "",
         "System unit matches: **%s**" % (", ".join(sys_match) or "none"), ""]
    cols = ["equal", "reloc", "near-branch", "far-target", "code-offset", "data-ref", "padding",
            "ref-only", "ours-only", "unexplained"]
    for v, r in results.items():
        L += ["## %s" % v, "", "Probe SINK.EXE sha1 `%s`; SINK.OVR signature `%s`." % (r["probe_sha1"], r["ovr_signature"]), "",
              "| unit | our range | bytes | " + " | ".join(cols) + " | verdict |",
              "|---|---|---:|" + "---:|" * len(cols) + "---|"]
        for u, x in r["units"].items():
            c = x["classes"]
            L.append("| %s | %s..%s | %d | %s | %s |" % (u, *r["ranges"][u], x["ours_bytes"],
                     " | ".join(str(c.get(k, 0)) for k in cols), "MATCH" if x["match"] else "differs"))
        L.append("")
        for u, x in r["units"].items():
            if x["unexplained_count"] or x["ours_only"]:
                s = int(r["ranges"][u][0].split(":")[0], 16) * 16
                L.append("- %s: first unexplained bytes at %s; ours-only blocks %s" % (
                    u, ", ".join(fmt_addr(s + k) for k, _ in x["unexplained"][:8]) or "none",
                    ", ".join("%s+%d" % (fmt_addr(s + a), n) for a, n in x["ours_only"]) or "none"))
        if r["system_vars"]:
            L += ["", "System variables observed in our DGROUP (operand pairs at aligned sites):", ""]
            L.append(", ".join("%s=DS:%04X" % (k, v) for k, v in sorted(r["system_vars"].items(), key=lambda kv: kv[1])))
        L.append("")
    (TC / "compare.md").write_text("\n".join(L) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("cmd", choices=["install", "probe", "compare", "all", "tpc"])
    ap.add_argument("src", nargs="?", help="tpc: the .PAS file to compile")
    ap.add_argument("--version", help="tpc: manifest version (default: the pinned one)")
    ap.add_argument("--opts", nargs="*", default=[], help="tpc: extra TPC options, e.g. /$R+")
    ap.add_argument("--disasm", action="store_true", help="tpc: disassemble the program segment")
    ap.add_argument("--emu", choices=["emu2", "dosbox-x"], help="DOS emulator for `probe` (default: emu2, else DOSBox-X)")
    ap.add_argument("--versions", nargs="*", help="limit to these manifest versions")
    a = ap.parse_args()
    if a.cmd == "install":
        return cmd_install(a)
    if a.cmd == "probe":
        return cmd_probe(a)
    if a.cmd == "compare":
        return cmd_compare(a)
    if a.cmd == "tpc":
        if not a.src:
            ap.error("tpc needs a source file")
        return cmd_tpc(a)
    return cmd_install(a) or cmd_probe(a) or cmd_compare(a)


if __name__ == "__main__":
    sys.exit(main())
