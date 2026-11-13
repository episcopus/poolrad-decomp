#!/usr/bin/env python3
"""port.py: the DOS port's patches for the listening pass's picks (README.md, "Toward the port").

  python3 ports/dos/sound/port.py           writes ports/dos/patches/tandy-sound.patch and tandy-strike.patch

picks.json is the pass the page exported: for each game sound, "designed" (the script of designs.py), "fixed" (the
original's tune with the noise fix) or "now" (the original's tune as it is; the noise fix still applies, it is the
driver's). Two patches come out, both against src/:

tandy-sound.patch (res03, the driver, src/RES03.ASM):
  - the noise fix: TandyStep writes the noise control (0E0h | x) only when its low three bits change, where the
    original wrote it every tick and every write reset the chip's shift register (the 237 Hz buzz, the silent
    Fireball). LastNoise is forgotten by SetTandyTune, so each tune writes its first noise control.
  - a script player: SetTandyTune looks the tune up in DesignTunes; a tune with a script plays it instead of its
    voices, one frame every second timer tick (118.3 Hz, the tick of designs.py). A script is frames:
        n (1..7Fh) and n bytes     write the bytes to port C0h in this frame
        80h + m - 1                this frame and the m - 1 after it write nothing (m = 1..126)
        0FEh                       the end: the chip quiet, every frame, until the next tune
    The voices of a designed tune are still loaded but not stepped; OutputOn off quiets the chip as before.
tandy-strike.patch (ovl13): the game silences the missile's strike at once (SetSoundDriverIdle(10) right after
  PlaySound(SoundAttackArrives), src/OVL13.PAS:1497). When the strike is designed, the Tandy chip gets the time
  its script needs first (WaitHundredths, the wait PlaySound gives an idle sound); the speaker is not waited for.
"""
from __future__ import annotations

import difflib
import json
import math
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PATCHES = ROOT / "ports/dos/patches"
sys.path.insert(0, str(HERE))

import designs  # noqa: E402

STRIKE = 12                      # SoundAttackArrives


def frames(writes) -> dict[int, list[int]]:
    out: dict[int, list[int]] = {}
    for t, b in writes:
        out.setdefault(int(round(t * designs.TICK)), []).append(b)
    return out


def encode(writes) -> bytes:
    fr = frames(writes)
    out, empty = bytearray(), 0
    for i in range(max(fr) + 1):
        b = fr.get(i)
        if not b:
            empty += 1
            continue
        while empty:
            m = min(empty, 126)
            out.append(0x80 + m - 1)
            empty -= m
        assert len(b) < 0x80
        out.append(len(b))
        out += bytes(b)
    out.append(0xFE)
    return bytes(out)


def decode(script: bytes) -> list[tuple[int, int]]:
    """(frame, byte) of a script, the player's reading: the check of port captures (check.py)."""
    out, i, f = [], 0, 0
    while script[i] != 0xFE:
        h = script[i]
        i += 1
        if h >= 0x80:
            f += h - 0x7F
            continue
        out += [(f, b) for b in script[i:i + h]]
        i += h
        f += 1
    return out


def picks() -> dict[int, str]:
    data = json.loads((HERE / "picks.json").read_text())
    return {int(k): v["pick"] for k, v in data["sounds"].items()}


def designed() -> dict[int, bytes]:
    """Sound -> script, for the sounds picked as designed."""
    return {s: encode(designs.DESIGNS[s].script().writes()) for s, p in sorted(picks().items()) if p == "designed"}


def replace(text: str, old: str, new: str) -> str:
    if text.count(old) != 1:
        raise SystemExit("port.py: src/RES03.ASM changed: %r is not there exactly once" % old.splitlines()[0])
    return text.replace(old, new)


def driver(src: str, scripts: dict[int, bytes]) -> str:
    t = src
    t = replace(t, """TandyStep:
        mov bx, word ptr [CurrentTune]
        cmp bx, 0
        je TandyQuiet
""", """TandyStep:
        mov bx, word ptr [CurrentTune]
        cmp bx, 0
        jne TandyTune                       ; port: TandyQuiet is out of a short jump's reach now
        jmp TandyQuiet
TandyTune:
        cmp word ptr [ScriptPtr], 0         ; port: a designed tune plays its script, not its voices
        je TandyVoicesStep
        jmp ScriptStep
TandyVoicesStep:
""")
    t = replace(t, """        xor al, dl
        out 0C0h, al
        cmp dl, 0E0h
        je L1546
        mov al, ah
        out 0C0h, al
L1546:
""", """        xor al, dl
        cmp dl, 0E0h
        je TandyNoise
        out 0C0h, al
        mov al, ah
        out 0C0h, al
        jmp short L1546

; port: the noise control only when it changes (every write of it resets the chip's shift register)
TandyNoise:
        mov ah, al
        and ah, 7
        cmp ah, byte ptr [LastNoise]
        je L1546
        mov byte ptr [LastNoise], ah
        out 0C0h, al
L1546:
""")
    t = replace(t, """        mov al, 0FFh
        out 0C0h, al
        ret

; StepVoice:""", """        mov al, 0FFh
        out 0C0h, al
        ret

; port: ScriptStep, a frame of the current tune's script every second tick (ports/dos/sound/port.py). Uses ax and
; si only (the handler saves ax, bx, dx, ds, si).
ScriptStep:
        cmp byte ptr [OutputOn], 0
        je TandyQuiet
        mov al, byte ptr [ScriptPhase]
        xor byte ptr [ScriptPhase], 1
        cmp al, 0
        jne ScriptDone
        cmp byte ptr [ScriptWait], 0
        je ScriptFrame
        dec byte ptr [ScriptWait]
        ret
ScriptFrame:
        mov si, word ptr [ScriptPtr]
        mov al, byte ptr [si]
        cmp al, 0FEh
        je TandyQuiet
        inc si
        cmp al, 80h
        jb ScriptWrites
        sub al, 80h
        mov byte ptr [ScriptWait], al
        mov word ptr [ScriptPtr], si
        ret
ScriptWrites:
        mov ah, al
ScriptOut:
        mov al, byte ptr [si]
        inc si
        out 0C0h, al
        dec ah
        jne ScriptOut
        mov word ptr [ScriptPtr], si
ScriptDone:
        ret

; StepVoice:""")
    t = replace(t, """        mov byte ptr [InService], 1
        mov byte ptr [VoicesLeft], 4
        mov di, TandyVoices
""", """        mov byte ptr [InService], 1
        mov bx, word ptr [CurrentTune]      ; port: the tune's script (0: none), from its first frame
        add bx, bx
        mov ax, word ptr [bx + DesignTunes]
        mov word ptr [ScriptPtr], ax
        mov byte ptr [ScriptPhase], 0
        mov byte ptr [ScriptWait], 0
        mov byte ptr [LastNoise], 0FFh
        mov byte ptr [VoicesLeft], 4
        mov di, TandyVoices
""")
    lines = ["", "; ---- the port's sound data (ports/dos/sound/port.py, from designs.py and picks.json) ----",
             "; the script of the tune playing, 0 for the voices [port]", "ScriptPtr:", "        dw      0",
             "; 0 on the ticks that play a frame, 1 on the others", "ScriptPhase:", "        db      0",
             "; frames left to skip", "ScriptWait:", "        db      0",
             "; the low three bits of the last noise control written, 0FFh none since the tune started",
             "LastNoise:", "        db      0FFh",
             "; per tune 0..20 (PlaySound n plays tune n - 1), its script or 0", "DesignTunes:"]
    for tune in range(21):
        s = tune + 1
        lines.append("        dw      %s" % ("Design%02d" % s if s in scripts else "0"))
    for s, data in scripts.items():
        d = designs.DESIGNS[s]
        lines += ["", "; PlaySound(%d), %s: %s (%d bytes)" % (s, d.name, d.what, len(data)), "Design%02d:" % s]
        for i in range(0, len(data), 16):
            lines.append("        db      " + ", ".join("%03Xh" % b for b in data[i:i + 16]))
    return t.rstrip("\n") + "\n" + "\n".join(lines) + "\n"


def strike_wait() -> int:
    """Hundredths for the designed strike's script to sound out."""
    w = designs.DESIGNS[STRIKE].script().writes()
    return math.ceil(max(t for t, b in w) * 100)


def strike(src: str) -> str:
    old = """  PlaySound(SoundAttackArrives);
  SetSoundDriverIdle(SoundIdleDefault);
"""
    new = """  PlaySound(SoundAttackArrives);
  if SoundMode = 0 then
    WaitHundredths(%d);   { port: the designed strike sounds on the Tandy chip before the driver goes idle }
  SetSoundDriverIdle(SoundIdleDefault);
""" % strike_wait()
    if src.count(old) != 1:
        raise SystemExit("port.py: src/OVL13.PAS changed: the strike's PlaySound is not there exactly once")
    return src.replace(old, new)


def diff(name: str, a: str, b: str) -> str:
    return "".join(difflib.unified_diff(a.splitlines(True), b.splitlines(True), "a/" + name, "b/" + name))


def main() -> int:
    scripts = designed()
    src = (ROOT / "src/RES03.ASM").read_text()
    (PATCHES / "tandy-sound.patch").write_text(diff("RES03.ASM", src, driver(src, scripts)))
    p = picks()
    out = ["tandy-sound.patch: %d scripts, %d bytes (%s)" % (
        len(scripts), sum(len(s) for s in scripts.values()), ", ".join("%d" % s for s in scripts))]
    if p.get(STRIKE) == "designed":
        ovl = (ROOT / "src/OVL13.PAS").read_text()
        (PATCHES / "tandy-strike.patch").write_text(diff("OVL13.PAS", ovl, strike(ovl)))
        out.append("tandy-strike.patch: WaitHundredths(%d) after the strike" % strike_wait())
    elif (PATCHES / "tandy-strike.patch").exists():
        (PATCHES / "tandy-strike.patch").unlink()
        out.append("tandy-strike.patch removed (the strike is not designed): take it out of patches/series")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
