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
    tail = bytes([0, len(blob) >> 8, len(blob) & 255, 0x7C, 0x90]) + blob
    if splash:
        body = splash_records() + progress_records(body)
        body, tail_stage, exec_rec = stage_program_text(body, exec_rec)
        tail += tail_stage
    path.write_bytes(body + tail + exec_rec)


# Disk BASIC keeps the text of the BASIC program at $2601 (TXTTAB, read from a MAME dump of the machine). A player who starts the game from a program (an
# AUTOEXEC.BAS, a menu, HDB-DOS or the SDC's autostart) has that program running while LOADM loads the engine: a record that lands on the program text
# ends in `?SN ERROR` when BASIC goes on to the :EXEC after the LOADM. So the record bytes of the window below are not loaded where they belong: they are
# loaded at STAGE_AT (BSS of the engine, which no record touches) as the last records of the file, and the file's EXEC address is a stub that copies them into
# place and jumps to the engine's own entry. 768 bytes (three sectors) hold a program of a few lines, which is what a launcher is. The engine's image is the
# same byte for byte once the stub has run (tests/unit/test_coco3_stripbin.py).
STAGE_LO, STAGE_HI = 0x2500, 0x2800     # the window of the engine that is staged: BASIC's program text ($2601 and on) is inside it
STAGE_AT = 0x7000                       # where its bytes are loaded; the stub follows them at STAGE_AT + STAGE_HI - STAGE_LO


def stage_program_text(body, exec_rec):
    """Take the bytes of [STAGE_LO, STAGE_HI) out of the records of `body` (their other bytes stay in the same order, each cut in two where the window
    crosses it) and return (the body, the records that load them at STAGE_AT and hold the stub, the new EXEC record)."""
    n = STAGE_HI - STAGE_LO
    win, have = bytearray(n), [False] * n
    out, i = bytearray(), 0
    while i < len(body):
        ln, ad = (body[i + 1] << 8) | body[i + 2], (body[i + 3] << 8) | body[i + 4]
        data = body[i + 5:i + 5 + ln]
        lo, hi = max(ad, STAGE_LO), min(ad + ln, STAGE_HI)
        if lo >= hi:
            out += body[i:i + 5 + ln]
        else:
            win[lo - STAGE_LO:hi - STAGE_LO] = data[lo - ad:hi - ad]
            have[lo - STAGE_LO:hi - STAGE_LO] = [True] * (hi - lo)
            if lo > ad:
                out += record(ad, data[:lo - ad])
            if hi < ad + ln:
                out += record(hi, data[hi - ad:])
        i += 5 + ln
    if not all(have):
        raise SystemExit("stripbin: the engine has no bytes at $%04X to $%04X, which must be staged whole" % (STAGE_LO, STAGE_HI))
    stub_at, entry = STAGE_AT + n, (exec_rec[3] << 8) | exec_rec[4]
    # every record must stay clear of the staging area and the stub (the ends of the load image are checked by the builds)
    i = 0
    while i < len(out):
        ln, ad = (out[i + 1] << 8) | out[i + 2], (out[i + 3] << 8) | out[i + 4]
        if ad < stub_at + 19 and ad + ln > STAGE_AT:
            raise SystemExit("stripbin: a record at $%04X (%d bytes) is in the staging area $%04X to $%04X" % (ad, ln, STAGE_AT, stub_at + 19))
        i += 5 + ln
    stub = bytes([0x8E, STAGE_AT >> 8, STAGE_AT & 255,                 # ldx  #STAGE_AT
                  0x10, 0x8E, STAGE_LO >> 8, STAGE_LO & 255,          # ldy  #STAGE_LO
                  0xEC, 0x81, 0xED, 0xA1,                             # loop: ldd ,x++ ; std ,y++
                  0x8C, stub_at >> 8, stub_at & 255,                  # cmpx #stub_at
                  0x26, 0xF7,                                         # bne  loop
                  0x7E, entry >> 8, entry & 255])                     # jmp  the engine's entry
    return (bytes(out), record(STAGE_AT, win) + record(stub_at, stub),
            bytes([0xFF, 0, 0, stub_at >> 8, stub_at & 255]))


SPL = 0x0400                    # the splash screen: BASIC's own 32 by 16 text screen, drawn by the first record of the file (boot.asm)
SPL_BAR = SPL + 12 * 32 + 2     # the 28 cells of the progress bar (row 12: rows 4 to 6 are the machine's (boot.asm), rows 8 and 9 the storage's)
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
    put(11, 2, "LOADING...")
    put(12, 1, "[")
    put(12, 30, "]")
    return record(SPL, scr)


STORAGE_ROW = 8                 # the splash's rows 8 and 9: what the game's storage is and how (rows 4 to 6 are the machine's, boot.asm)


def with_storage(pool_bin, line1, line2=""):
    """POOL.BIN (the game's, with the splash: strip_low_records(splash=True)) with two lines about its storage in the splash record, for the medium it is packed
    for (tools/mkimage.py: the floppy set, the SDC file, the IDE card): LOADM shows them, the engine needs no code or text for them. The IDE driver adds what it
    only knows when it runs (the device and the transfer width: src/engine/ide.c)."""
    d = bytearray(pool_bin)
    if bytes(d[:5]) != bytes([0, 2, 0, SPL >> 8, SPL & 255]):
        raise SystemExit("stripbin: the first record of POOL.BIN is not the splash screen")
    for row, text in ((STORAGE_ROW, line1), (STORAGE_ROW + 1, line2)):
        if len(text) > 30:
            raise SystemExit("stripbin: %r does not fit the splash's row" % text)
        at = 5 + row * 32 + 2
        d[at:at + 30] = vdg(text.ljust(30))
    return bytes(d)


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
