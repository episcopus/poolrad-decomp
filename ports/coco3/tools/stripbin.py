#!/usr/bin/env python3
"""stripbin.py FILE.bin: move the shared data out of the area Disk BASIC uses while LOADM runs (see strip_low_records); the game's
build (mkgame.py) adds the splash screen and the progress bar of LOADM to the file (splash=True)."""
import sys
from pathlib import Path


def strip_low_records(path, splash=False):
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
        if 0x0600 <= ad < 0x0A00:
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
    tail = bytes([0, len(blob) >> 8, len(blob) & 255, 0x7C, 0x90]) + blob + exec_rec
    if splash:
        body = splash_records() + progress_records(body)
    path.write_bytes(body + tail)


SPL = 0x0400                    # the splash screen: BASIC's own 32 by 16 text screen, drawn by the first record of the file (boot.asm)
SPL_BAR = SPL + 10 * 32 + 2     # the 28 cells of the progress bar
BAR_CELLS_LOADM = 14            # the first half of the bar is LOADM's (records of this file), the second half the engine's (boot.asm)


def vdg(text):
    """ASCII capitals, digits and punctuation as the inverse video codes of the VDG's text screen (green on black)."""
    return bytes((ord(c) - 0x40) if ord(c) >= 0x40 else ord(c) for c in text)


def record(addr, data):
    return bytes([0, len(data) >> 8, len(data) & 255, addr >> 8, addr & 255]) + bytes(data)


def splash_records():
    """What LOADM shows while it loads (step 8.9i): the first record writes the splash screen over BASIC's text screen (nothing else of
    the program lands there since the shared code moved to $1D80; before, LOADM showed the code as garbage)."""
    scr = bytearray(b" " * 512)

    def put(row, col, text):
        scr[row * 32 + col:row * 32 + col + len(text)] = vdg(text)
    put(1, 1, "POOL OF RADIANCE  COCO 3 PORT")
    put(9, 2, "LOADING...")
    put(10, 1, "[")
    put(10, 30, "]")
    return record(SPL, scr)


def progress_records(body):
    """The largest record of the program (the engine at $2000) cut in BAR_CELLS_LOADM pieces, a cell of the bar after each: the bar moves
    while LOADM loads. The other records stay as they are, after it."""
    recs, i = [], 0
    while i < len(body):
        ln = (body[i + 1] << 8) | body[i + 2]
        recs.append((i, ln, (body[i + 3] << 8) | body[i + 4]))
        i += 5 + ln
    big = max(recs, key=lambda r: r[1])
    i, ln, ad = big
    data, out = body[i + 5:i + 5 + ln], bytearray()
    n = BAR_CELLS_LOADM
    for k in range(n):
        a, b = len(data) * k // n, len(data) * (k + 1) // n
        out += record(ad + a, data[a:b]) + record(SPL_BAR + k, bytes([0xDF]))      # semigraphics: a cyan block
    for r in recs:
        if r != big:
            out += body[r[0]:r[0] + 5 + r[1]]
    return bytes(out)


if __name__ == "__main__":
    strip_low_records(Path(sys.argv[1]))
