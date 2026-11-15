#!/usr/bin/env python3
"""func.py: does a speed patch keep the game's behaviour? Plays every session of tests/sessions on the reference
build (the series without speed patches, `build.py --ref`, build/ref) and on the game (build/link), both in Tandy
video and sound, and compares what the game did, not how long it took.

  .venv/bin/python ports/dos/tools/func.py [--session NAME ...] [--jobs N] [--shots]
  make -C ports/dos func [SESSION=name]

Why not the replay of sessions.py: a replay feeds the recorded outside world back read by read, and the timer
interrupts by instruction count. A faster game asks for the time and polls the keyboard a different number of
times while it draws, so a replay of the slow game's recording no longer fits the fast one.

The clock here belongs to the program, not to the instructions it runs:

  virtual time  advances only when the game asks for it or waits: a keyboard poll (INT 16h AH=1) 2 ms, a time
                of day read (INT 21h AH=2Ch, INT 1Ah) 10 ms (the hundredth the game reads), a read of the BIOS tick count 50 us, a blocked
                keyboard read up to the next timer interrupt. Drawing, unpacking, game logic take no time at all.
  timer         the interrupt (the sound driver's 236.7 Hz, the BIOS tick every 13th) is raised when virtual time
                passes its period, and taken right after the call that made it pass (when that call returns,
                at the instruction it returns to), so it lands at the same point of the program in every build.
  keys          the script's keys are released to keyboard reads only, by the script's rules (keys.py: `key`
                when the game is idle, `press` at the next poll, `wait` in virtual time); shots, digests and
                `quit` happen at a poll too. The `wheel` command only holds the script until the game drew the
                wheel question's random number (the builds here never ask it).

So a game that draws faster sees the same times, the same keys at the same polls and the same interrupts at the
same calls, and must do the same things. What is compared, reference against game:

  checkpoints   at every key the game reads and every shot/digest: DGROUP's data (the overlay manager's own
                variables masked), the heap (HeapOrg up to HeapPtr) and the Tandy screen (B800h, 32 KB) with the
                video mode. Words that differ only by the distance a segment moved (a patch that changes the size
                of a resident unit moves DGROUP, the heap and the code segments after it) are the same pointer.
  random        every Random call: kind, range, result and the routine that asked
  files         files opened, and the files written (saved games), with the same pointer rule and the stale stack
                ranges of tools/c/known_differences.toml masked
  sound         every byte written to the Tandy chip with its virtual time (the driver steps on the timer, which
                is the program's clock here), and every call of PlaySound and SetSoundDriverIdle
  end           how the run ended, after how many keys

Exit status 0 when every session agrees. Results in build/func/<build>/<session>.pkl; --shots writes the Tandy
screen at every shot of the scripts as PNG to build/func/<build>/<session>/.
"""
from __future__ import annotations

import argparse
import hashlib
import pickle
import struct
import sys
import time
import tomllib
import zlib
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

PORT = Path(__file__).resolve().parents[1]
ROOT = PORT.parents[1]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools/re"))

import tp_toolchain as tp  # noqa: E402

BUILDS = {"ref": PORT / "build/ref", "game": PORT / "build/link"}
SESSIONS = ROOT / "tests/sessions"
PORT_SESSIONS = PORT / "sessions"          # the port's own scripts (Tandy); a name here wins over tests/sessions
SUITE = PORT_SESSIONS / "suite.txt"
OUT = PORT / "build/func"
OWN_FILES = ("\\POOLRAD\\GAME.OVR",)

POLL_US = 2000             # virtual time of one keyboard poll
CLOCK_US = 10000           # of one time of day read: the game reads hundredths (DOS's clock moves every 55 ms)
TICK_US = 50               # of one read of the BIOS tick count (Crt's Delay calibration)
KEY_PATIENCE = 10_000_000  # virtual us a `key` waits for an idle game before it goes in regardless
TANDY_WINDOW = (0x8000, 0x10000)   # B800:0000..7FFF in the oracle's B0000h text buffer

FLAG_IF = 0x0200


# ---------------------------------------------------------------------------------------------- the machine
def make_machine_class():
    from unicorn import UC_HOOK_MEM_READ
    from unicorn.x86_const import (UC_X86_REG_EFLAGS as R_FLAGS, UC_X86_REG_CS as R_CS, UC_X86_REG_IP as R_IP,
                                   UC_X86_REG_SS as R_SS, UC_X86_REG_SP as R_SP)
    from oracle.machine import Machine, GuestCrash, OracleError, Stop
    from unicorn import UcError

    class FuncMachine(Machine):
        """The oracle's PC with the program's clock (module docstring)."""

        def now(self) -> int:
            return self.extra

        def deliver_interrupt(self, n: int, clear_if: bool = True) -> None:
            """Machine.deliver_interrupt with the registers read once (the harness spends its time here)."""
            uc = self.uc
            fl = uc.reg_read(R_FLAGS) & 0xFFFF
            cs = uc.reg_read(R_CS)
            ip = uc.reg_read(R_IP)
            ss = uc.reg_read(R_SS)
            sp = (uc.reg_read(R_SP) - 6) & 0xFFFF
            uc.mem_write(ss * 16 + sp, struct.pack("<HHH", ip, cs, fl))   # (no frame crosses 64 KB here)
            uc.reg_write(R_SP, sp)
            uc.reg_write(R_FLAGS, fl & ~(0x0100 | (FLAG_IF if clear_if else 0)))
            off, seg = struct.unpack("<HH", uc.mem_read(n * 4, 4))
            uc.reg_write(R_CS, seg)
            uc.reg_write(R_IP, off)

        def time_of_day(self) -> int:
            self.extra += CLOCK_US
            return super().time_of_day()

        def install_clock(self) -> None:
            self.wait_listeners = []                    # callables(): a poll or a clock read happened (prof.py)
            for n in (0x16, 0x1A, 0x21):
                self.services[n] = self._timed(n, self.services[n])
            lo = 0x46C
            self.uc.hook_add(UC_HOOK_MEM_READ, self._on_tick_read, begin=lo, end=lo + 3)
            # the Tandy screen is B800h of the oracle's text buffer: count its writes like the EGA's, so keys.py's
            # idle rule (no video write between polls) means the same as on the EGA the scripts were written for
            ega = self.ega
            plain = ega._write_byte

            def write_byte(off, v, plain=plain, ega=ega):
                plain(off, v)
                if off >= 0x10000:
                    ega.writes += 1
            ega._write_byte = write_byte

        def _on_tick_read(self, uc, access, addr, size, value, _ud):
            if addr == 0x46C:
                self.extra += TICK_US
                for f in self.wait_listeners:
                    f()
                if not self.irq0_pending and self.extra >= self.next_irq0:
                    # a memory read cannot move CS:IP: stop after this instruction, the run loop takes the interrupt
                    # at the next instruction boundary (the same one in every build)
                    uc.emu_stop()

        def _timed(self, n, fn):
            def service(m):
                ah = m.get("ax") >> 8
                if n == 0x16 and ah in (0x01, 0x11):
                    m.extra += POLL_US
                elif n == 0x1A and ah in (0x00, 0x02):
                    m.extra += CLOCK_US
                if (n == 0x16 and ah in (0x00, 0x01, 0x10, 0x11)) or n == 0x1A or (n == 0x21 and ah == 0x2C):
                    for f in m.wait_listeners:
                        f()
                fn(m)                                   # (INT 21h AH=2Ch charges through time_of_day)
                if not m.irq0_pending and m.extra >= m.next_irq0:
                    m._take_irq0_after_service()
            return service

        def _take_irq0_after_service(self) -> None:
            """Virtual time passed the timer's period during a service: the interrupt comes when the service's
            IRET returns to the program. Do that IRET here (the stub's IRET is skipped: the code hook moved
            CS:IP) and, if the program runs with interrupts on, deliver IRQ 0 at that very instruction."""
            self._raise_irq0()
            self.next_irq0 += self._irq0_period()
            ss, sp = self.get("ss"), self.get("sp")
            flags = self.rw(ss, sp + 4)
            if not (flags & FLAG_IF) or self.irq0_in_service or (self.pic_mask & 1):
                return                                  # the run loop delivers it when it can, stepping
            ip, cs = self.pop(), self.pop()
            self.pop()
            from unicorn.x86_const import UC_X86_REG_EFLAGS
            self.uc.reg_write(UC_X86_REG_EFLAGS, flags)
            self.set("cs", cs)
            self.set("ip", ip)
            self._try_deliver_irq0()
            # CS:IP is the handler's now, so stopping cannot run this service again: the run loop takes over at the
            # handler's first instruction and steps one instruction at a time while a further period is owed
            self.uc.emu_stop()

        def run(self, max_insns: int = 50_000_000, on_chunk=None) -> str:
            uc = self.uc
            limit = self.insns + max_insns
            try:
                while True:
                    if self.exit_code is not None:
                        return "exit"
                    if not self.irq0_pending and self.extra >= self.next_irq0:
                        self._raise_irq0()
                        self.next_irq0 += self._irq0_period()
                    self._try_deliver_irq0()
                    if self.irq0_pending and self.insns - self._pending_since > 2_000_000:
                        raise OracleError("stalled: a timer interrupt pending with interrupts off at %04X:%04X" % (
                            self.get("cs"), self.get("ip")))
                    # while an interrupt waits for IF, step one instruction at a time: it is taken at the first
                    # instruction boundary that allows it, the same in every build
                    chunk = 1 if self.irq0_pending else 50_000
                    chunk = min(chunk, limit - self.insns)
                    if chunk <= 0:
                        return "max-insns"
                    start = self.linear(self.get("cs"), self.get("ip"))
                    uc.emu_start(start, 0xFFFFFFFF, count=chunk)
                    self.insns += chunk
                    # (no HLT rule: the oracle's guesses one from the byte before IP at a chunk boundary, which depends
                    # on where the chunk ended; the game never halts)
                    if on_chunk:
                        on_chunk(self)
            except Stop as s:
                return s.reason
            except UcError as e:
                raise GuestCrash(self.crash_report(str(e))) from e

    return FuncMachine


def make_script_class():
    from oracle.keys import KeyScript

    class Script(KeyScript):
        """keys.py's player, with every op at a keyboard poll (never at an emulator chunk boundary, whose place
        in the program depends on the code's length) and `wheel` as a gate only."""

        pending_since = None             # (op index, virtual time) the head `key` began to wait for idle

        def _advance(self, m, at_poll: bool = True):
            while self.i < len(self.ops) and self.ops[self.i][0] == "wheel":
                if getattr(m, "wheel_answer", None) is None:
                    return None
                m.wheel_answer = None
                self.i += 1
            k = super()._advance(m, at_poll)
            if k is None and self.i < len(self.ops) and self.ops[self.i][0] == "key":
                # a screen that animates while it waits for a key is never idle: after KEY_PATIENCE of virtual
                # time the key goes in anyway (the same moment in every build: the clock is the program's)
                if self.pending_since is None or self.pending_since[0] != self.i:
                    self.pending_since = (self.i, m.now())
                elif m.now() - self.pending_since[1] >= KEY_PATIENCE:
                    return self.ops[self.i][1]
            return k

        def service(self, m) -> None:
            pass

    return Script


# ---------------------------------------------------------------------------------------------- one run
def dgroup_and_heap(m, ds: int, masked: tuple[int, int]) -> tuple[bytes, bytes]:
    from oracle import state
    end = min(0x10000, max(0, (m.get("ss") - ds) << 4))
    data = bytearray(m.read(ds, 0, end))
    lo, hi = masked
    data[lo:hi] = bytes(hi - lo)
    return bytes(data), state.heap_bytes(m, ds)


def screen(m) -> bytes:
    ega = m.ega
    lo, hi = TANDY_WINDOW
    return bytes(ega.text_mem[lo:hi]) + struct.pack("<H", ega.mode)


TANDY_RGB = [(0, 0, 0), (0, 0, 170), (0, 170, 0), (0, 170, 170), (170, 0, 0), (170, 0, 170), (170, 85, 0),
             (170, 170, 170), (85, 85, 85), (85, 85, 255), (85, 255, 85), (85, 255, 255), (255, 85, 85),
             (255, 85, 255), (255, 255, 85), (255, 255, 255)]


def tandy_png(m, path: Path) -> None:
    """The 320x200 16-colour Tandy screen (four 8 KB banks, row y in bank y mod 4, two pixels per byte)."""
    from oracle.ega import write_png
    mem = m.ega.text_mem
    out = bytearray(320 * 200 * 3)
    for y in range(200):
        base = TANDY_WINDOW[0] + (y & 3) * 0x2000 + (y >> 2) * 160
        for x in range(160):
            b = mem[base + x]
            for k, c in enumerate((b >> 4, b & 15)):
                o = (y * 320 + 2 * x + k) * 3
                out[o:o + 3] = bytes(TANDY_RGB[c])
    path.parent.mkdir(parents=True, exist_ok=True)
    write_png(path, 320, 200, bytes(out))


def session_file(name: str) -> Path:
    own = PORT_SESSIONS / (name + ".keys")
    return own if own.exists() else SESSIONS / (name + ".keys")


def suite() -> list[str]:
    """The sessions of sessions/suite.txt (one name per line, `#` comments)."""
    return [l.split("#", 1)[0].strip() for l in SUITE.read_text().splitlines() if l.split("#", 1)[0].strip()]


def setup(build: str, session: str, video: bytes = b"T"):
    """The machine for one session on one build: Tandy video and sound, the program's clock, the script, the
    wheel watcher and the random log. Returns (machine, script, publics of the link map, its segments, DGROUP)."""
    from oracle import layout, state
    from oracle.protection import install_wheel_solver
    from oracle.rng import install_random_log

    link = BUILDS[build]
    layout.use(layout.rebuilt(link))
    segs, pubs = tp.read_map(tp.ci(link, "POOL.MAP"))
    Machine = make_machine_class()
    Script = make_script_class()
    lay = layout.current()
    script = Script.parse(session_file(session).read_text())
    m = Machine(lay.exe, ROOT / "poolrad", strict=True)
    m.vfs.alias("GAME.OVR", lay.overlay_file)
    for f in sorted((PORT_SESSIONS / "saves").glob("*")):   # the port's saved games (bane-battle: slot F)
        m.vfs.alias("SAVE\\" + f.name, f)
    lines = (ROOT / "poolrad/POOL.CFG").read_bytes().split(b"\r\n")
    lines[0], lines[1] = video, b"T"                      # Tandy video, Tandy sound: the target machine
    m.vfs.layer["\\POOLRAD\\POOL.CFG"] = bytearray(b"\r\n".join(lines))
    m.keys = script
    m.clock_pin = script.clock
    m.install_clock()
    install_wheel_solver(m)
    install_random_log(m)
    return m, script, pubs, segs, state.dgroup_seg()


def run_one(build: str, session: str, shots: bool = False, max_insns: int = 3_000_000_000) -> dict:
    """Play one session on one build; returns (and pickles) what func.py compares."""
    from oracle.machine import LOAD_SEG, Stop

    m, script, pubs, _segs, ds = setup(build, session)
    masked = (pubs["OVRRESULT"][1], pubs["HEAPORG"][1])

    sound_calls = []
    for name in ("PlaySound", "SetSoundDriverIdle"):
        seg, off = pubs[name.upper()]
        m.add_breakpoint(LOAD_SEG + seg, off,
                         lambda mm, name=name: sound_calls.append((name, mm.rw(mm.get("ss"), mm.get("sp") + 4))))

    checkpoints = []
    last = [None, None]

    def checkpoint(label):
        data, heap = dgroup_and_heap(m, ds, masked)
        scr = screen(m)
        cp = {"label": label, "keys": m.bios.key_reads, "random": len(m.random_log), "time": m.now(),
              "screen": hashlib.sha256(scr).hexdigest(), "data_sha": hashlib.sha256(data).hexdigest(),
              "heap_sha": hashlib.sha256(heap).hexdigest()}
        # the bytes themselves, so a difference can be judged (pointer rule) and shown; repeated states once
        cp["data"] = None if cp["data_sha"] == last[0] else zlib.compress(data, 1)
        cp["heap"] = None if cp["heap_sha"] == last[1] else zlib.compress(heap, 1)
        last[0], last[1] = cp["data_sha"], cp["heap_sha"]
        checkpoints.append(cp)

    def on_key(mach, k):
        checkpoint("key %d (%04X)" % (mach.bios.key_reads, k))
    m.on_key_read = on_key

    shot_dir = OUT / build / session

    def on_op(op, mach):
        kind, arg = op
        if kind in ("shot", "digest"):
            checkpoint("%s %s" % (kind, arg))
            if shots and kind == "shot":
                tandy_png(mach, shot_dir / (arg + ".png"))
        if kind == "quit":
            raise Stop("quit")
    script.on_op = on_op

    t0 = time.time()
    err = None
    try:
        reason = m.run(max_insns)
    except Exception as e:                         # a crash is a result too: the other build may not crash
        reason, err = "error", "%s: %s" % (type(e).__name__, e)
    checkpoint("end")
    if shots:
        tandy_png(m, shot_dir / "end.png")
    written = {name: bytes(data) for name, data in m.vfs.layer.items() if name not in OWN_FILES}
    result = {
        "build": build, "session": session, "reason": reason, "error": err, "seconds": round(time.time() - t0, 1),
        "insns": m.insns, "virtual_time": m.now(), "keys": m.bios.key_reads,
        "segments": {k: v for k, v in _segs.items()} if isinstance(_segs, dict) else _segs,
        "dgroup": ds, "checkpoints": checkpoints,
        "random": [(c.kind, c.range, c.result, routine_of(c.caller)) for c in m.random_log],
        "opened": [p for (op, p, _x) in m.vfs.log if op == "open"],
        "written": written, "tandy": list(m.tandy_log), "sound_calls": sound_calls,
    }
    out = OUT / build / (session + ".pkl")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(pickle.dumps(result))
    return result


def routine_of(caller) -> str:
    """The routine part of a caller as rng.py names it ('ovl06:0A31+1C' -> 'ovl06:0A31'): a patch may move code
    inside a routine, never the routine a random decision belongs to."""
    s = str(caller)
    return s.split("+", 1)[0]


# ---------------------------------------------------------------------------------------------- comparing
def seg_deltas(ref: dict, game: dict) -> set[int]:
    """How far each segment moved between the builds (code segments of units, and DGROUP with everything above
    it, the stack, the overlay buffer and the heap), as 16-bit differences; 0 is not a move."""
    out = {(game["dgroup"] - ref["dgroup"]) & 0xFFFF}
    rs, gs = ref["segments"], game["segments"]
    if isinstance(rs, dict):
        for k in rs.keys() & gs.keys():
            a, b = rs[k], gs[k]
            out.add(((b[0] >> 4) - (a[0] >> 4)) & 0xFFFF)     # (start byte, size, class) of the link map
    out.discard(0)
    return out


def differences(a: bytes, b: bytes, deltas: set[int], limit: int = 8) -> list[str]:
    """Where two byte strings differ, apart from words that differ by a segment move (a relocated pointer)."""
    out = []
    if len(a) != len(b):
        out.append("length %d, game %d" % (len(a), len(b)))
    n = min(len(a), len(b))
    i = 0
    while i < n and len(out) < limit:
        if a[i] == b[i]:
            i += 1
            continue
        j = i
        while j < n and a[j] != b[j]:
            j += 1
        ok = False
        if deltas and j - i <= 2:
            for w in (i - 1, i):                     # the segment word of a far pointer that covers [i, j)
                if 0 <= w and w + 2 <= n and w <= i and j <= w + 2:
                    wa, wb = struct.unpack_from("<H", a, w)[0], struct.unpack_from("<H", b, w)[0]
                    if (wb - wa) & 0xFFFF in deltas:
                        ok = True
        if not ok:
            out.append("%04X: %s / %s" % (i, a[i:j][:8].hex(), b[i:j][:8].hex()))
        i = j
    return out


def unpack_states(cps: list[dict]):
    data = heap = b""
    for cp in cps:
        if cp["data"] is not None:
            data = zlib.decompress(cp["data"])
        if cp["heap"] is not None:
            heap = zlib.decompress(cp["heap"])
        yield cp, data, heap


def known_differences() -> dict[str, list[tuple[int, int]]]:
    d = tomllib.loads((ROOT / "tools/c/known_differences.toml").read_text())
    return {f["name"]: [tuple(r) for r in f["ranges"]] for f in d.get("file", [])}


def compare(ref: dict, game: dict) -> list[str]:
    diffs = []
    deltas = seg_deltas(ref, game)
    if ref["error"] or game["error"]:
        if ref["error"] != game["error"]:
            diffs.append("error: reference %s, game %s" % (ref["error"], game["error"]))
    if ref["reason"] != game["reason"]:
        diffs.append("end: reference %s, game %s" % (ref["reason"], game["reason"]))
    rc, gc = ref["checkpoints"], game["checkpoints"]
    if len(rc) != len(gc):
        diffs.append("checkpoints: reference %d, game %d" % (len(rc), len(gc)))
    for (a, ad, ah), (b, bd, bh) in zip(unpack_states(rc), unpack_states(gc)):
        what = []
        if a["label"] != b["label"]:
            what.append("label %r / %r" % (a["label"], b["label"]))
        if a["random"] != b["random"]:
            what.append("random calls %d / %d" % (a["random"], b["random"]))
        if a["time"] != b["time"]:
            what.append("virtual time %d / %d" % (a["time"], b["time"]))
        if a["screen"] != b["screen"]:
            what.append("screen")
        if a["data_sha"] != b["data_sha"]:
            d = differences(ad, bd, deltas)
            if d:
                what.append("DGROUP " + "; ".join(d))
        if a["heap_sha"] != b["heap_sha"]:
            d = differences(ah, bh, deltas)
            if d:
                what.append("heap " + "; ".join(d))
        if what:
            diffs.append("checkpoint %r: %s" % (a["label"], ", ".join(what)))
            break                                   # the first one is the one to look at
    if ref["random"] != game["random"]:
        n = next((i for i, (x, y) in enumerate(zip(ref["random"], game["random"])) if x != y),
                 min(len(ref["random"]), len(game["random"])))
        diffs.append("random: first difference at call %d: %s / %s (calls %d / %d)" % (
            n, ref["random"][n] if n < len(ref["random"]) else "-", game["random"][n] if n < len(game["random"]) else "-",
            len(ref["random"]), len(game["random"])))
    if ref["opened"] != game["opened"]:
        diffs.append("files opened differ")
    known = known_differences()
    if ref["written"].keys() != game["written"].keys():
        diffs.append("files written: %s / %s" % (sorted(ref["written"]), sorted(game["written"])))
    for name in sorted(ref["written"].keys() & game["written"].keys()):
        a, b = bytearray(ref["written"][name]), bytearray(game["written"][name])
        for lo, hi in known.get(name, ()):
            a[lo:hi] = bytes(max(0, min(hi, len(a)) - lo))
            b[lo:hi] = bytes(max(0, min(hi, len(b)) - lo))
        d = differences(bytes(a), bytes(b), deltas)
        if d:
            diffs.append("file %s: %s" % (name, "; ".join(d)))
    if ref["sound_calls"] != game["sound_calls"]:
        diffs.append("sound calls: %d / %d" % (len(ref["sound_calls"]), len(game["sound_calls"])))
    if ref["tandy"] != game["tandy"]:
        n = next((i for i, (x, y) in enumerate(zip(ref["tandy"], game["tandy"])) if x != y),
                 min(len(ref["tandy"]), len(game["tandy"])))
        diffs.append("Tandy sound writes: first difference at write %d (writes %d / %d)" % (
            n, len(ref["tandy"]), len(game["tandy"])))
    return diffs


def summary_line(r: dict) -> str:
    return "%s after %d keys, %d checkpoints, %d random calls, %d sound writes, %.1f virtual s, %d M instructions" % (
        r["reason"], r["keys"], len(r["checkpoints"]), len(r["random"]), len(r["tandy"]),
        r["virtual_time"] / 1e6, r["insns"] // 1_000_000)


def _job(args):
    build, session, shots = args
    r = run_one(build, session, shots)
    return build, session, r["seconds"]


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--session", action="append", help="session name (default: every tests/sessions/*.keys)")
    ap.add_argument("--jobs", type=int, default=6)
    ap.add_argument("--shots", action="store_true", help="PNG of the Tandy screen at every shot")
    ap.add_argument("--build", choices=sorted(BUILDS), action="append", help="run only these builds (no comparison)")
    ap.add_argument("--compare-only", action="store_true", help="compare the results already in build/func")
    a = ap.parse_args(argv)
    sessions = a.session or suite()
    builds = a.build or sorted(BUILDS)
    for b in builds:
        if tp.ci(BUILDS[b], "POOL.MAP") is None:
            print("func: no %s build in %s (make game, and build.py --ref)" % (b, BUILDS[b].relative_to(ROOT)))
            return 1
    if not a.compare_only:
        jobs = [(b, s, a.shots) for s in sessions for b in builds]
        with ProcessPoolExecutor(max_workers=a.jobs) as ex:
            for build, session, secs in ex.map(_job, jobs):
                print("  ran %-4s %-18s %6.0f s" % (build, session, secs), flush=True)
    if a.build and len(a.build) == 1:
        return 0
    bad = 0
    for s in sessions:
        ref = pickle.loads((OUT / "ref" / (s + ".pkl")).read_bytes())
        game = pickle.loads((OUT / "game" / (s + ".pkl")).read_bytes())
        d = compare(ref, game)
        print("[%s] %s: %s" % (s, "DIFFERS" if d else "ok", summary_line(game)))
        for line in d:
            print("    " + line)
        bad += bool(d)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
