#!/usr/bin/env python3
"""Shared MZ / load-image helpers for Pool of Radiance RE tools."""
from __future__ import annotations

import json
import struct
from pathlib import Path

LOAD_SEG = 0x1000  # PSP at 0FF0; image at 1000:0000 (same as tools/oracle/smoke.py)
DGROUP_PARA = 0x0C7C


def read_mz(path: str | Path) -> tuple[dict, bytes]:
    data = Path(path).read_bytes()
    if data[:2] not in (b"MZ", b"ZM"):
        raise ValueError("%s: not an MZ executable" % path)
    last, pages, nreloc, hdrpara = struct.unpack_from("<HHHH", data, 2)
    size = pages * 512 if last in (0, 512) else (pages - 1) * 512 + last
    min_alloc, max_alloc, ss, sp, checksum, ip, cs = struct.unpack_from("<HHHHHHH", data, 10)
    reloc_off = struct.unpack_from("<H", data, 0x18)[0]
    hdr = {
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
    return hdr, data[hdrpara * 16 : size]


def load_overlays_json(path: str | Path = "build/re/overlays.json") -> dict:
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError("%s missing; run `make overlays` first" % p)
    return json.loads(p.read_text())


def para_to_linear(para: int, offset: int = 0) -> int:
    return para * 16 + offset


def fmt_addr(para: int, offset: int) -> str:
    return "%04X:%04X" % (para & 0xFFFF, offset & 0xFFFF)


def parse_addr(s: str) -> tuple[int, int]:
    a, b = s.split(":")
    return int(a, 16), int(b, 16)
