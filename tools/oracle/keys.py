"""keys.py: the input script player (`tests/sessions/*.keys`, SPEC 8.5, playbook 25 step 6).

Script format, one command per line, `#` starts a comment:

    key ENTER            a named key (ENTER ESC SPACE TAB BKSP UP DOWN LEFT RIGHT HOME END PGUP PGDN INS DEL F1..F10,
                         single characters, or a raw 0xSSAA scan/ASCII word). Released when the game is idle
                         waiting for input (below), like a person who types after the prompt appeared.
    text Hello there     types the characters (ASCII), each released like `key`
    press ESC            like `key`, but released at the very next poll, idle or not (skipping an animation)
    wait 18              hold the next key back for 18 BIOS ticks (about one second of virtual time)
    shot title           screenshot named `title`: taken as soon as the preceding ops are done and the game has
                         asked for input again (when it follows a key), or at the chunk boundary
    digest label         record a state digest checkpoint, timed like `shot`
    wheel                types the answer to the copy-protection question the game last asked
                         (protection.py), followed by ENTER
    quit                 stop the run, timed like `shot`

Idle means: the game is blocked in a keyboard read, or it has polled the keyboard `IDLE_POLLS` times in a
row with an empty buffer and without writing to video memory in between. The game flushes the keyboard
before most prompts, so a key typed ahead of the prompt would be eaten; gating on idle prevents that.
Keys reach the program only when it asks (INT 16h or INT 21h char input), so a run depends on the
program and the script alone and never on host timing.
"""
from __future__ import annotations

NAMED = {
    "ESC": 0x011B, "ENTER": 0x1C0D, "RETURN": 0x1C0D, "SPACE": 0x3920, "TAB": 0x0F09, "BKSP": 0x0E08,
    "UP": 0x4800, "DOWN": 0x5000, "LEFT": 0x4B00, "RIGHT": 0x4D00, "HOME": 0x4700, "END": 0x4F00,
    "PGUP": 0x4900, "PGDN": 0x5100, "INS": 0x5200, "DEL": 0x5300,
}
for _i in range(10):
    NAMED["F%d" % (_i + 1)] = (0x3B + _i) << 8

_ROW_SCAN = {}
for _row, _start in (("1234567890-=", 0x02), ("qwertyuiop[]", 0x10), ("asdfghjkl;'`", 0x1E), ("\\zxcvbnm,./", 0x2B)):
    for _i, _c in enumerate(_row):
        _ROW_SCAN[_c] = _start + _i


def char_key(c: str) -> int:
    lo = c.lower()
    if lo in _ROW_SCAN:
        return (_ROW_SCAN[lo] << 8) | ord(c)
    if c == " ":
        return 0x3920
    if c == "\n":
        return 0x1C0D
    return ord(c)


IDLE_POLLS = 4


def key_value(tok: str) -> int:
    t = tok.upper()
    if t in NAMED:
        return NAMED[t]
    if t.startswith("0X"):
        return int(t, 16)
    if len(tok) == 1:
        return char_key(tok)
    raise ValueError("unknown key %r" % tok)


class KeyScript:
    def __init__(self, ops):
        self.ops = list(ops)
        self.i = 0
        self.wait_until = None          # virtual time when the head `wait` expires
        self.fired: list = []           # (op, virtual time) log of non-key ops, for tests
        self.on_op = None               # callback(op, machine) for shot / digest / quit
        self.after_key = False          # a key was just delivered: capture ops wait for the game's next poll

    @classmethod
    def parse(cls, text: str) -> "KeyScript":
        ops = []
        for n, raw in enumerate(text.splitlines(), 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            cmd, _, arg = line.partition(" ")
            cmd = cmd.lower()
            arg = arg.strip()
            if cmd == "key":
                ops.append(("key", key_value(arg)))
            elif cmd == "press":
                ops.append(("press", key_value(arg)))
            elif cmd == "text":
                ops.extend(("key", char_key(c)) for c in arg)
            elif cmd == "wait":
                ops.append(("wait", int(arg)))
            elif cmd in ("shot", "digest"):
                ops.append((cmd, arg or "%s%d" % (cmd, n)))
            elif cmd == "quit":
                ops.append(("quit", ""))
            elif cmd == "wheel":
                ops.append(("wheel", ""))
            else:
                raise ValueError("line %d: unknown command %r" % (n, cmd))
        return cls(ops)

    @classmethod
    def from_file(cls, path) -> "KeyScript":
        from pathlib import Path
        return cls.parse(Path(path).read_text())

    # --- player ---------------------------------------------------------------------
    def _advance(self, m, at_poll: bool = True) -> int | None:
        if at_poll:
            self.after_key = False
        while self.i < len(self.ops):
            kind, arg = self.ops[self.i]
            if kind == "press":
                return arg
            if kind == "key":
                if not m.bios.idle(IDLE_POLLS):
                    return None
                return arg
            if kind == "wheel":
                word = getattr(m, "wheel_answer", None)
                if word is None:
                    return None             # not asked yet: no key is available (title screens just run on)
                m.wheel_answer = None
                self.fired.append(("wheel", word, m.now()))
                self.ops[self.i:self.i + 1] = [("key", char_key(c)) for c in word] + [("key", NAMED["ENTER"])]
                continue
            if kind == "wait":
                if self.wait_until is None:
                    self.wait_until = m.now() + arg * 65536 * m.insn_per_sec // 1_193_182
                if m.now() < self.wait_until:
                    return None
                self.wait_until = None
            else:
                if self.after_key:
                    return None             # let the game react to the key before capturing
                self.fired.append((kind, arg, m.now()))
                if self.on_op:
                    self.on_op((kind, arg), m)
            self.i += 1
        return None

    def service(self, m) -> None:
        """Called by the run loop at every chunk boundary: executes time-based ops (wait, shot, ...)
        even while the game is not polling the keyboard (loading screens)."""
        self._advance(m, at_poll=False)

    def peek(self, m):
        return self._advance(m)

    def take(self, m):
        k = self._advance(m)
        if k is not None:
            self.i += 1
            self.after_key = True
            m.bios.note_key_released()
        return k

    def exhausted(self, m) -> bool:
        self._advance(m)
        return self.i >= len(self.ops)
