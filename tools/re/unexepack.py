#!/usr/bin/env python3
"""unexepack.py: unpack a Microsoft EXEPACK-compressed DOS MZ executable.

Pool of Radiance ships START.EXE EXEPACK-compressed. Analysis uses the unpacked
image poolrad/start-unpack.exe. This tool reproduces that image from START.EXE.

Format notes (18-byte EXEPACK header with skip_len, as in this build):
  CS:0   EXEPACK header (real_ip/cs, mem_start, exepack_size, real_sp/ss,
         dest_len, skip_len, signature "RB")
  CS:IP  decompression stub, ending with "Packed file is corrupt"
  then   packed relocation table (16 segment buckets, segment = i*0x1000)
  before CS:0: compressed load image (RLE, decoded backwards)

Usage:
  python3 tools/re/unexepack.py poolrad/START.EXE -o build/re/start-unpack.exe
  python3 tools/re/unexepack.py poolrad/START.EXE --check poolrad/start-unpack.exe

Exit 0 on success (and on --check when the output matches byte for byte).
"""
from __future__ import annotations

import argparse
import hashlib
import struct
import sys

ERR_MSG = b"Packed file is corrupt"
RB = 0x4252


def mz_declared_size(data: bytes) -> int:
    last, pages = struct.unpack_from("<HH", data, 2)
    if last in (0, 512):
        return pages * 512
    return (pages - 1) * 512 + last


def parse_mz(data: bytes) -> dict:
    if data[:2] not in (b"MZ", b"ZM"):
        raise ValueError("not an MZ executable")
    last, pages, nreloc, hdrpara = struct.unpack_from("<HHHH", data, 2)
    min_alloc, max_alloc, ss, sp, checksum, ip, cs = struct.unpack_from("<HHHHHHH", data, 10)
    reloc_off = struct.unpack_from("<H", data, 0x18)[0]
    size = mz_declared_size(data)
    return {
        "last": last,
        "pages": pages,
        "nreloc": nreloc,
        "hdrpara": hdrpara,
        "min_alloc": min_alloc,
        "max_alloc": max_alloc,
        "ss": ss,
        "sp": sp,
        "checksum": checksum,
        "ip": ip,
        "cs": cs,
        "reloc_off": reloc_off,
        "size": size,
    }


def parse_exepack_header(blob: bytes) -> dict:
    """blob is the first `ip` bytes at CS:0 (header length equals the MZ IP field)."""
    if len(blob) == 0x12:
        fields = struct.unpack("<9H", blob)
        real_ip, real_cs, mem_start, exepack_size, real_sp, real_ss, dest_len, skip_len, sig = fields
    elif len(blob) == 0x10:
        fields = struct.unpack("<8H", blob)
        real_ip, real_cs, mem_start, exepack_size, real_sp, real_ss, dest_len, sig = fields
        skip_len = 1
    elif len(blob) == 0x14:
        fields = struct.unpack("<10H", blob)
        real_ip, real_cs, mem_start, exepack_size, _unused, real_sp, real_ss, dest_len, skip_len, sig = fields
    else:
        raise ValueError("unsupported EXEPACK header length %d (MZ IP)" % len(blob))
    if sig != RB:
        raise ValueError("EXEPACK signature is %04X, expected 4252 ('RB')" % sig)
    if skip_len == 0 or dest_len < skip_len:
        raise ValueError("invalid dest_len/skip_len (%d/%d)" % (dest_len, skip_len))
    return {
        "real_ip": real_ip,
        "real_cs": real_cs,
        "mem_start": mem_start,
        "exepack_size": exepack_size,
        "real_sp": real_sp,
        "real_ss": real_ss,
        "dest_len": dest_len,
        "skip_len": skip_len,
    }


def decompress_exepack(buf: bytearray, dst: int, src: int) -> None:
    """In-place EXEPACK RLE. dst/src are one-past-the-end indices into buf."""
    while src > 0 and buf[src - 1] == 0xFF:
        src -= 1
    while True:
        if src < 3:
            raise ValueError("truncated EXEPACK command")
        src -= 1
        command = buf[src]
        src -= 1
        length = (buf[src] << 8)
        src -= 1
        length += buf[src]
        op = command & 0xFE
        if op == 0xB0:
            if src < 1:
                raise ValueError("truncated EXEPACK fill")
            src -= 1
            fill = buf[src]
            if dst < length:
                raise ValueError("EXEPACK fill overruns destination")
            for _ in range(length):
                dst -= 1
                buf[dst] = fill
        elif op == 0xB2:
            if src < length or dst < length:
                raise ValueError("EXEPACK copy overruns buffer")
            for _ in range(length):
                src -= 1
                dst -= 1
                buf[dst] = buf[src]
        else:
            raise ValueError("unknown EXEPACK command %02X" % command)
        if command & 1:
            break


def unpack_reloc_table(data: bytes, off: int) -> tuple[list[tuple[int, int]], int]:
    """Return (relocs, end_offset) for the 16-bucket packed relocation table."""
    relocs: list[tuple[int, int]] = []
    for bucket in range(16):
        if off + 2 > len(data):
            raise ValueError("packed reloc table truncated at bucket %d" % bucket)
        n = struct.unpack_from("<H", data, off)[0]
        off += 2
        if off + 2 * n > len(data):
            raise ValueError("packed reloc entries truncated at bucket %d" % bucket)
        seg = bucket * 0x1000
        for _ in range(n):
            ofs = struct.unpack_from("<H", data, off)[0]
            off += 2
            relocs.append((seg, ofs))
    return relocs, off


def exe_checksum(data: bytes) -> int:
    """Ones-complement sum of all 16-bit words, with e_csum treated as zero."""
    buf = bytearray(data)
    if len(buf) & 1:
        buf.append(0)
    struct.pack_into("<H", buf, 0x12, 0)
    total = 0
    for i in range(0, len(buf), 2):
        total = (total + struct.unpack_from("<H", buf, i)[0]) & 0xFFFF
    return (~total) & 0xFFFF


def craft_exe(image: bytes, relocs: list[tuple[int, int]], eh: dict, max_alloc: int, min_alloc: int) -> bytes:
    """Build an MZ EXE. Header is padded to a multiple of 512 bytes (matches the pinned golden)."""
    reloc_off = 0x1C
    reloc_blob = b"".join(struct.pack("<HH", off, seg) for seg, off in relocs)
    raw_hdr = reloc_off + len(reloc_blob)
    hdr_size = (raw_hdr + 511) // 512 * 512
    hdrpara = hdr_size // 16
    total = hdr_size + len(image)
    pages = (total + 511) // 512
    last = total % 512  # 0 means a full final page; MZ encodes that as 0
    out = bytearray(total)
    struct.pack_into(
        "<2sHHHHHHHHHHHHH",
        out,
        0,
        b"MZ",
        last,
        pages,
        len(relocs),
        hdrpara,
        min_alloc & 0xFFFF,
        max_alloc & 0xFFFF,
        eh["real_ss"],
        eh["real_sp"],
        0,  # checksum filled below
        eh["real_ip"],
        eh["real_cs"],
        reloc_off,
        0,  # overlay number
    )
    out[reloc_off : reloc_off + len(reloc_blob)] = reloc_blob
    out[hdr_size:] = image
    struct.pack_into("<H", out, 0x12, exe_checksum(out))
    return bytes(out)


def unexepack(data: bytes) -> tuple[bytes, dict]:
    mz = parse_mz(data)
    data = data[: mz["size"]]
    if len(data) < mz["size"]:
        raise ValueError("file shorter than MZ declared size")
    hdr_bytes = mz["hdrpara"] * 16
    cs0 = hdr_bytes + mz["cs"] * 16
    if cs0 + mz["ip"] > len(data):
        raise ValueError("EXEPACK header past end of file")
    eh = parse_exepack_header(data[cs0 : cs0 + mz["ip"]])
    if cs0 + eh["exepack_size"] > len(data):
        raise ValueError("exepack_size extends past end of file")

    skip = eh["skip_len"]
    comp_size = 16 * (mz["cs"] - skip + 1)
    uncomp_size = 16 * (eh["dest_len"] - skip + 1)
    if comp_size <= 0 or hdr_bytes + comp_size > cs0:
        raise ValueError("compressed size inconsistent with CS")

    msg_at = data.find(ERR_MSG, cs0)
    if msg_at < 0:
        raise ValueError("EXEPACK error string not found")
    relocs, reloc_end = unpack_reloc_table(data, msg_at + len(ERR_MSG))
    if reloc_end != cs0 + eh["exepack_size"]:
        raise ValueError(
            "packed reloc table ends at %d, EXEPACK block ends at %d"
            % (reloc_end, cs0 + eh["exepack_size"])
        )

    buf = bytearray(data[hdr_bytes : hdr_bytes + comp_size])
    if len(buf) < uncomp_size:
        buf.extend(b"\x00" * (uncomp_size - len(buf)))
    decompress_exepack(buf, uncomp_size, comp_size)
    image = bytes(buf[:uncomp_size])

    # min_alloc keeps (load_image_paragraphs + min_alloc) constant across pack/unpack
    load_paras = (mz["size"] - hdr_bytes + 15) // 16
    min_alloc = (load_paras + mz["min_alloc"] - eh["dest_len"]) & 0xFFFF

    out = craft_exe(image, relocs, eh, mz["max_alloc"], min_alloc)
    info = {
        "exepack": eh,
        "nreloc": len(relocs),
        "image_bytes": len(image),
        "hdrpara": struct.unpack_from("<H", out, 8)[0],
        "min_alloc": min_alloc,
        "sha256": hashlib.sha256(out).hexdigest(),
    }
    return out, info


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Unpack a Microsoft EXEPACK DOS executable")
    ap.add_argument("packed", help="path to EXEPACK-compressed MZ EXE (e.g. poolrad/START.EXE)")
    ap.add_argument("-o", "--output", help="write unpacked EXE here")
    ap.add_argument(
        "--check",
        metavar="GOLDEN",
        help="compare unpacked bytes to GOLDEN (byte for byte); do not require -o",
    )
    args = ap.parse_args(argv[1:])

    data = open(args.packed, "rb").read()
    try:
        out, info = unexepack(data)
    except ValueError as e:
        print("unexepack: %s" % e, file=sys.stderr)
        return 1

    eh = info["exepack"]
    print(
        "unexepack: %d relocs, %d image bytes, hdrpara=%d, "
        "entry %04X:%04X, ss:sp %04X:%04X, sha256=%s"
        % (
            info["nreloc"],
            info["image_bytes"],
            info["hdrpara"],
            eh["real_cs"],
            eh["real_ip"],
            eh["real_ss"],
            eh["real_sp"],
            info["sha256"],
        )
    )

    if args.output:
        open(args.output, "wb").write(out)
        print("wrote %s (%d bytes)" % (args.output, len(out)))

    if args.check:
        golden = open(args.check, "rb").read()
        if golden == out:
            print("check: OK, matches %s" % args.check)
            return 0
        print(
            "check: MISMATCH vs %s (got %d bytes, golden %d bytes)"
            % (args.check, len(out), len(golden)),
            file=sys.stderr,
        )
        n = min(len(out), len(golden))
        for i in range(n):
            if out[i] != golden[i]:
                print(
                    "check: first diff at offset %d (0x%X): got %02X golden %02X"
                    % (i, i, out[i], golden[i]),
                    file=sys.stderr,
                )
                break
        else:
            print("check: common prefix identical; lengths differ", file=sys.stderr)
        return 1

    if not args.output:
        print("unexepack: pass -o FILE to write, or --check GOLDEN to verify", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
