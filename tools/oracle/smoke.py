#!/usr/bin/env python3
"""smoke.py: first proof that Unicorn runs the original Pool of Radiance code in 16-bit real mode.

Loads the unpacked START.EXE like DOS would (PSP + relocations), starts at CS:IP and runs
until the program makes its first N DOS/BIOS interrupt calls, printing each one. Interrupts are
answered with minimal stubs. This is NOT the oracle (SPEC 8.2); it only de-risks Phase 2.

  .venv/bin/python tools/oracle/smoke.py poolrad/start-unpack.exe [--ints 25]
"""
import argparse, struct, sys
from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INTR, UcError
from unicorn.x86_const import *

PSP_SEG = 0x0FF0          # PSP at 0FF0:0000, load image at 1000:0000
LOAD_SEG = PSP_SEG + 0x10


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("exe")
    ap.add_argument("--ints", type=int, default=25)
    a = ap.parse_args()
    d = open(a.exe, "rb").read()
    f = struct.unpack("<14H", d[:28])
    last, pages, nrel, hdrp, minalloc, _maxa, ss, sp, _cs, ip, cs, reloff = f[1:13]
    size = (pages - 1) * 512 + last if last else pages * 512
    image = bytearray(d[hdrp * 16:size])
    for i in range(nrel):
        off, seg = struct.unpack("<HH", d[reloff + 4 * i:reloff + 4 * i + 4])
        p = seg * 16 + off
        image[p:p + 2] = struct.pack("<H", (struct.unpack("<H", image[p:p + 2])[0] + LOAD_SEG) & 0xFFFF)

    mu = Uc(UC_ARCH_X86, UC_MODE_16)
    mu.mem_map(0, 0x110000)
    psp = bytearray(256)
    psp[0:2] = b"\xcd\x20"
    psp[2:4] = struct.pack("<H", 0xA000)          # top of memory paragraph
    psp[0x80] = 0; psp[0x81] = 0x0D               # empty command tail
    mu.mem_write(PSP_SEG * 16, bytes(psp))
    mu.mem_write(LOAD_SEG * 16, bytes(image))
    # IVT: every vector points at an IRET in high memory, so interrupts can be intercepted
    mu.mem_write(0xF0000, b"\xcf")
    mu.mem_write(0, struct.pack("<HH", 0x0000, 0xF000) * 256)

    for r, v in ((UC_X86_REG_CS, cs + LOAD_SEG), (UC_X86_REG_IP, ip), (UC_X86_REG_SS, ss + LOAD_SEG),
                 (UC_X86_REG_SP, sp), (UC_X86_REG_DS, PSP_SEG), (UC_X86_REG_ES, PSP_SEG)):
        mu.reg_write(r, v)

    seen = []
    def on_int(uc, intno, _):
        ah = uc.reg_read(UC_X86_REG_AX) >> 8
        csv, ipv = uc.reg_read(UC_X86_REG_CS), uc.reg_read(UC_X86_REG_IP)
        seen.append((intno, ah))
        print("INT %02Xh AH=%02Xh at %04X:%04X (load-relative seg %04X)" % (intno, ah, csv, ipv, (csv - LOAD_SEG) & 0xFFFF))
        if intno == 0x21 and ah == 0x30:            # DOS version: 3.30
            uc.reg_write(UC_X86_REG_AX, 0x1E03)
        elif intno == 0x21 and ah == 0x35:          # get vector -> ES:BX
            al = uc.reg_read(UC_X86_REG_AX) & 0xFF
            o, s = struct.unpack("<HH", uc.mem_read(al * 4, 4))
            uc.reg_write(UC_X86_REG_ES, s); uc.reg_write(UC_X86_REG_BX, o)
        elif intno == 0x21 and ah == 0x25:          # set vector from DS:DX
            al = uc.reg_read(UC_X86_REG_AX) & 0xFF
            uc.mem_write(al * 4, struct.pack("<HH", uc.reg_read(UC_X86_REG_DX), uc.reg_read(UC_X86_REG_DS)))
        if len(seen) >= a.ints:
            uc.emu_stop()

    mu.hook_add(UC_HOOK_INTR, on_int)
    try:
        mu.emu_start(((cs + LOAD_SEG) << 4) + ip, 0, count=5_000_000)
    except UcError as e:
        print("stopped:", e)
    print("%d interrupt calls observed; CS:IP now %04X:%04X" % (
        len(seen), mu.reg_read(UC_X86_REG_CS), mu.reg_read(UC_X86_REG_IP)))
    return 0 if seen else 1


if __name__ == "__main__":
    sys.exit(main())
