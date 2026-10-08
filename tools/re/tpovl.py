#!/usr/bin/env python3
"""tpovl.py: Turbo Pascal (Borland FBOV) overlay manifest for Pool of Radiance.

Reads the UNPACKED main executable (EXEPACK removed) and the overlay file, finds
every overlay stub segment (INT 3Fh header) in the load image, validates that the
stubs tile the overlay file exactly, and writes a JSON manifest.

Layout of a stub segment, as observed in this build (see docs/design/WHITEPAPER.md):
  +00 u8[2]  CD 3F            INT 3Fh (overlay manager trap)
  +02 u16    save_return      runtime field (0 on disk)
  +04 u32    file_offset      offset of this unit's code in the .OVR file
  +08 u16    code_size        bytes of code
  +0A u16    fixup_size       bytes of fixup table that follows the code (u16 offsets)
  +0C u16    entry_count      number of 5-byte entry stubs at +20
  +0E u16    link             meaning unconfirmed (stub chain / list link)
  +10..+1F   runtime fields   zero on disk
  +20        entry[i]         CD 3F, u16 code_offset, u8 0   (5 bytes each)

Usage:
  python3 tools/re/tpovl.py poolrad/start-unpack.exe poolrad/GAME.OVR [-o build/re/overlays.json]
       [--extract build/re/overlays]   # writes ovlNN.bin (code) and ovlNN.fix (fixup offsets)
Exit code 0 when the manifest validates, 1 otherwise.
"""
import argparse, hashlib, json, os, struct, sys


def read_mz(data):
    if data[:2] not in (b"MZ", b"ZM"):
        raise SystemExit("not an MZ executable")
    f = struct.unpack("<14H", data[:28])
    last, pages, nreloc, hdrpara = f[1], f[2], f[3], f[4]
    size = (pages - 1) * 512 + last if last else pages * 512
    hdr = {
        "relocations": nreloc, "header_paragraphs": hdrpara,
        "min_alloc": f[5], "max_alloc": f[6], "ss": f[7], "sp": f[8],
        "ip": f[10], "cs": f[11], "image_bytes": size - hdrpara * 16,
    }
    return hdr, data[hdrpara * 16:size]


def init_chain(image, cs, ip):
    """Far calls at the entry point: Turbo Pascal calls each unit's initialisation in turn."""
    p, calls = cs * 16 + ip, []
    while p + 5 <= len(image) and image[p] == 0x9A:
        off, seg = struct.unpack("<HH", image[p + 1:p + 5])
        calls.append({"segment": seg, "offset": off})
        p += 5
    return calls


def find_stubs(image, ovr_len):
    stubs = []
    for p in range(0, len(image) - 0x20, 16):
        if image[p:p + 2] != b"\xcd\x3f":
            continue
        fo, cs, fx, ne, link = struct.unpack("<IHHHH", image[p + 4:p + 16])
        if fo >= ovr_len or ne == 0 or ne > 255 or cs == 0:
            continue
        if any(image[p + 0x10:p + 0x20]):
            continue  # runtime area must be zero on disk
        ents = []
        ok = True
        for i in range(ne):
            q = p + 0x20 + i * 5
            if image[q:q + 2] != b"\xcd\x3f":
                ok = False
                break
            ents.append({"index": i, "stub_offset": 0x20 + i * 5,
                         "code_offset": struct.unpack("<H", image[q + 2:q + 4])[0]})
        if ok:
            stubs.append({"stub_segment": p // 16, "file_offset": fo, "code_size": cs,
                          "fixup_size": fx, "entry_count": ne, "link": link, "entries": ents})
    return stubs


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("exe")
    ap.add_argument("ovr")
    ap.add_argument("-o", "--output")
    ap.add_argument("--extract")
    a = ap.parse_args()

    exe = open(a.exe, "rb").read()
    ovr = open(a.ovr, "rb").read()
    hdr, image = read_mz(exe)
    errors = []
    if ovr[:4] != b"FBOV":
        errors.append("overlay file does not start with FBOV (got %r)" % ovr[:4])
    ovr_hdr_len = struct.unpack("<I", ovr[4:8])[0]
    if ovr_hdr_len != len(ovr) - 8:
        errors.append("FBOV length field %d != file length - 8 (%d)" % (ovr_hdr_len, len(ovr) - 8))

    stubs = sorted(find_stubs(image, len(ovr)), key=lambda s: s["file_offset"])
    expect = 8
    for i, s in enumerate(stubs):
        s["overlay"] = i
        if s["file_offset"] != expect:
            errors.append("overlay %d starts at %#x, expected %#x" % (i, s["file_offset"], expect))
        code = ovr[s["file_offset"]:s["file_offset"] + s["code_size"]]
        fix = ovr[s["file_offset"] + s["code_size"]:s["file_offset"] + s["code_size"] + s["fixup_size"]]
        if s["fixup_size"] % 2:
            errors.append("overlay %d fixup table has odd size" % i)
        offs = list(struct.unpack("<%dH" % (len(fix) // 2), fix))
        bad = [o for o in offs if o + 2 > s["code_size"]]
        if bad:
            errors.append("overlay %d has fixups outside its code: %s" % (i, bad[:5]))
        bad_ent = [e for e in s["entries"] if e["code_offset"] >= s["code_size"]]
        if bad_ent:
            errors.append("overlay %d has entries outside its code" % i)
        s["fixups"] = offs
        s["code_sha256"] = hashlib.sha256(code).hexdigest()
        expect = s["file_offset"] + s["code_size"] + s["fixup_size"]
        if a.extract:
            os.makedirs(a.extract, exist_ok=True)
            open(os.path.join(a.extract, "ovl%02d.bin" % i), "wb").write(code)
            open(os.path.join(a.extract, "ovl%02d.fix" % i), "w").write(
                "".join("%04x\n" % o for o in offs))
    if expect != len(ovr):
        errors.append("overlays end at %#x but the file is %#x bytes" % (expect, len(ovr)))

    chain = init_chain(image, hdr["cs"], hdr["ip"])
    chain_ovl = sorted(c["segment"] for c in chain if c["offset"] == 0x20)
    stub_segs = sorted(s["stub_segment"] for s in stubs)
    if chain_ovl != stub_segs:
        errors.append("init chain overlay calls %s do not match stubs %s" % (chain_ovl, stub_segs))

    manifest = {
        "schema": "poolrad-tpovl-v1",
        "exe": {"path": a.exe, "sha256": hashlib.sha256(exe).hexdigest(), "mz": hdr},
        "ovr": {"path": a.ovr, "sha256": hashlib.sha256(ovr).hexdigest(), "bytes": len(ovr)},
        "unit_init_calls": len(chain),
        "overlay_unit_init_calls": len(chain_ovl),
        "resident_unit_init_calls": len(chain) - len(chain_ovl),
        "overlay_count": len(stubs),
        "entry_count": sum(s["entry_count"] for s in stubs),
        "overlay_code_bytes": sum(s["code_size"] for s in stubs),
        "init_chain": chain,
        "overlays": stubs,
        "errors": errors,
    }
    out = json.dumps(manifest, indent=1)
    if a.output:
        os.makedirs(os.path.dirname(a.output) or ".", exist_ok=True)
        open(a.output, "w").write(out + "\n")
    else:
        print(out)
    summary = "%d overlays, %d entries, %d code bytes, %d unit inits (%d resident); %s" % (
        manifest["overlay_count"], manifest["entry_count"], manifest["overlay_code_bytes"],
        manifest["unit_init_calls"], manifest["resident_unit_init_calls"],
        "OK" if not errors else "%d ERRORS" % len(errors))
    print(summary, file=sys.stderr)
    for e in errors:
        print("  error: " + e, file=sys.stderr)
    return 0 if not errors else 1


if __name__ == "__main__":
    sys.exit(main())
