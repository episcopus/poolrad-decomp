#!/usr/bin/env python3
"""stripbin.py FILE.bin: move the shared data out of the area Disk BASIC uses while LOADM runs (see strip_low_records)."""
import sys
from pathlib import Path


def strip_low_records(path):
    """The shared data lives at $0700..$08FF, where Disk BASIC keeps its buffers (and the file control block of POOL.BIN) until the
    program takes over: LOADM must not write there. The records between $0600 and $1FFF are taken out of the DECB binary and
    put, as one image of $0700..$08FF, at SHARED_IMG ($7C90; it was $7C00 until step 8.9d, which needed the engine's room: the image is 346 bytes and must end before $7E00, where BASIC's stack is while LOADM runs); boot.asm copies it into place (SHARED_IMG in mailbox.inc)."""
    d = path.read_bytes()
    out, img, i, used = bytearray(), bytearray(0x200), 0, 0
    while i < len(d):
        if d[i] != 0:
            out += d[i:]
            break
        ln, ad = (d[i + 1] << 8) | d[i + 2], (d[i + 3] << 8) | d[i + 4]
        if 0x0600 <= ad < 0x2000:
            if ad < 0x0700 or ad + ln > 0x0900:
                raise SystemExit("a record of the engine at $%04X (%d bytes) is in Disk BASIC's buffers, outside $0700..$08FF" % (ad, ln))
            img[ad - 0x0700:ad - 0x0700 + ln] = d[i + 5:i + 5 + ln]
            used = max(used, ad - 0x0700 + ln)
        else:
            out += d[i:i + 5 + ln]
        i += 5 + ln
    exec_rec = bytes(out[-5:])
    body = bytes(out[:-5])
    n = (used + 1) & ~1                                       # the image is its length (a word) and the data up to the last record's end
    blob = bytes([n >> 8, n & 255]) + bytes(img[:n])
    if 0x7C90 + len(blob) > 0x7E00:
        raise SystemExit("the shared data image (%d bytes) does not fit between $7C90 and $7E00" % len(blob))
    path.write_bytes(body + bytes([0, len(blob) >> 8, len(blob) & 255, 0x7C, 0x90]) + blob + exec_rec)


if __name__ == "__main__":
    strip_low_records(Path(sys.argv[1]))
