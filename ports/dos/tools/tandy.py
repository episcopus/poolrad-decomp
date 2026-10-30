#!/usr/bin/env python3
"""tandy.py: run the port's game on an emulated Tandy 1000 (DOSBox-X, machine=tandy) with Tandy video and sound,
headless, and check it against the original on the same machine.

  .venv/bin/python ports/dos/tools/tandy.py [--seconds 75] [--play]
  make -C ports/dos tandy

POOL.CFG says T (Tandy 16-colour 320x200) and T (Tandy 3-voice sound chip). Three runs, in parallel, each recorded
by DOSBox-X's own capture (lossless ZMBV video) with no window (SDL dummy driver):

  port        build/game/START.EXE, no argument: the title screens, then the character menu
  original    poolrad/start-unpack.exe, no argument: the title screens, then the code wheel question
  sting       the original with STING (its own switch that skips the title screens and the wheel): the menu

No key is typed: the port goes from the titles to the menu by itself, the original stops at the wheel. Checks:

  1. every run shows the Tandy 320x200 mode;
  2. the port's last screen is the original's character menu (the sting run's last screen), pixel for pixel;
  3. the port never shows the original's wheel question (its last screen);
  4. every title screen the original shows, the port shows too, pixel for pixel.

The title screens play no sound, so sound is not checked here: sessions.py compares every write to the Tandy
chip of 18 sessions, and build.py shows the sound driver (res03) is the original's code.

The emulated CPU runs at full host speed (cycles=max): this is a behaviour check, not a timing measurement.
Exit status 0 when every check passes, 77 when DOSBox-X or ffmpeg is missing. Frames: build/tandy/<run>/frames.

--play opens a DOSBox-X window instead (for a person, never for a test): the same Tandy machine running the
port's game at about a Tandy 1000 EX's speed (an 8088 at 7.16 MHz is roughly `cycles=fixed PLAY_CYCLES`; DOSBox
does not model 8088 timing, so this is a feel, not a measurement). Saved games stay in build/play between runs.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

PORT = Path(__file__).resolve().parents[1]
ROOT = PORT.parents[1]
OUT = PORT / "build/tandy"
GAME_FILES = ("ITEMS",)                       # besides every *.DAX of poolrad/
PLAY_CYCLES = 400                             # DOSBox-X cycles for the feel of a 7.16 MHz 8088 (not calibrated)
TANDY_CFG = b"T\r\nT\r\nC:\\POOLRAD\\\r\nC:\\POOLRAD\\SAVE\\\r\nF\r\n"   # video, sound, game path, save path, (as shipped)


def game_dir(c: Path, exe: Path, ovr: Path, keep_saves: bool = False) -> None:
    """C:\\POOLRAD with the pinned game data (symlinks), the program under test and a Tandy POOL.CFG."""
    pool = c / "POOLRAD"
    for p in (pool.iterdir() if pool.exists() else ()):
        if p.is_dir() and not keep_saves:
            shutil.rmtree(p)
        elif not p.is_dir():
            p.unlink()
    (pool / "SAVE").mkdir(parents=True, exist_ok=True)
    for p in sorted((ROOT / "poolrad").iterdir()):
        if p.is_file() and (p.suffix.upper() == ".DAX" or p.name in GAME_FILES):
            os.symlink(p.resolve(), pool / p.name)
    os.symlink(exe.resolve(), pool / "START.EXE")
    os.symlink(ovr.resolve(), pool / "GAME.OVR")
    (pool / "POOL.CFG").write_bytes(TANDY_CFG)


def conf(run: Path, c: Path, args: str, cycles: str) -> str:
    return f"""[dosbox]
machine=tandy
memsize=640
captures={run / "cap"}
[cpu]
core=normal
cputype=8086
cycles={cycles}
[render]
aspect=false
scaler=none
[sdl]
output=surface
[speaker]
tandy=on
[autoexec]
mount c "{c}"
c:
cd \\poolrad
dx-capture /v start.exe {args}
exit
"""


def record(name: str, exe: Path, ovr: Path, args: str, seconds: int) -> Path:
    run = OUT / name
    if run.exists():
        shutil.rmtree(run)
    (run / "cap").mkdir(parents=True)
    game_dir(run / "c", exe, ovr)
    cf = run / "dosbox.conf"
    cf.write_text(conf(run, run / "c", args, "max"))
    env = dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy")
    subprocess.run(["dosbox-x", "-conf", str(cf), "-nopromptfolder", "-nogui", "-fastlaunch", "-silent",
                    "-time-limit", str(seconds)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   check=False)
    return run


def play() -> int:
    """The port's game in a DOSBox-X window on the Tandy machine, at about the 1000 EX's speed."""
    run = PORT / "build/play"
    game_dir(run / "c", PORT / "build/game/START.EXE", PORT / "build/game/GAME.OVR", keep_saves=True)
    cf = run / "dosbox.conf"
    cf.write_text(conf(run, run / "c", "", "fixed %d" % PLAY_CYCLES).replace("dx-capture /v start.exe ", "start.exe")
                  .replace("\nexit\n", "\n").replace("aspect=false", "aspect=true")
                  .replace("scaler=none", "scaler=normal3x"))
    return subprocess.run(["dosbox-x", "-conf", str(cf), "-nopromptfolder", "-fastlaunch"], check=False).returncode


def frames(run: Path) -> list[Path]:
    """Every distinct screen of the run's video, in order (ffmpeg's frames, consecutive duplicates dropped)."""
    avis = sorted((run / "cap").glob("*.avi"), key=lambda p: p.stat().st_size)
    if not avis:
        raise RuntimeError("%s: DOSBox-X wrote no video capture" % run.name)
    d = run / "frames"
    if d.exists():
        shutil.rmtree(d)
    d.mkdir()
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(avis[-1]), "-vf", "fps=4",
                    str(d / "f%05d.png")], check=True)
    out, last = [], None
    for f in sorted(d.glob("*.png")):
        b = pixels(f)
        if b != last:
            out.append(f)
            last = b
    return out


def pixels(p: Path) -> tuple:
    from PIL import Image
    im = Image.open(p).convert("RGB")
    return im.size, im.tobytes()


def available() -> bool:
    return shutil.which("dosbox-x") is not None and shutil.which("ffmpeg") is not None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--seconds", type=int, default=75, help="wall-clock time each run gets (the titles take about 45)")
    ap.add_argument("--play", action="store_true", help="open a DOSBox-X window to play the port's game")
    a = ap.parse_args(argv)
    if a.play:
        if not (PORT / "build/game/START.EXE").exists():
            print("tandy: no port build (make -C ports/dos game)")
            return 1
        return play()
    if not available():
        print("tandy: dosbox-x and ffmpeg are required (brew install dosbox-x ffmpeg)")
        return 77
    port_exe, port_ovr = PORT / "build/game/START.EXE", PORT / "build/game/GAME.OVR"
    if not port_exe.exists():
        print("tandy: no port build (make -C ports/dos game)")
        return 1
    orig_exe, orig_ovr = ROOT / "poolrad/start-unpack.exe", ROOT / "poolrad/GAME.OVR"
    runs = {"port": (port_exe, port_ovr, ""), "original": (orig_exe, orig_ovr, ""),
            "sting": (orig_exe, orig_ovr, "STING")}
    print("tandy: three DOSBox-X runs (machine=tandy, Tandy video and sound), %d s each, in parallel ..." % a.seconds,
          flush=True)
    with ThreadPoolExecutor(len(runs)) as ex:
        done = {n: ex.submit(record, n, *r, a.seconds) for n, r in runs.items()}
        dirs = {n: f.result() for n, f in done.items()}
    shots = {n: frames(d) for n, d in dirs.items()}
    px = {n: [pixels(f) for f in fs] for n, fs in shots.items()}
    ok = True

    def check(cond: bool, text: str) -> None:
        nonlocal ok
        ok &= cond
        print("  %-4s %s" % ("ok" if cond else "FAIL", text))

    for n in runs:
        last = px[n][-1][0] if px[n] else None
        check(last == (320, 200), "%s: last screen is %s (Tandy 320x200: %s)" % (
            n, "x".join(map(str, last)) if last else "none", "yes" if last == (320, 200) else "no"))
    menu, wheel = px["sting"][-1], px["original"][-1]
    check(px["port"][-1] == menu, "port's last screen is the original's character menu (%s, %s)" % (
        shots["port"][-1].relative_to(ROOT), shots["sting"][-1].relative_to(ROOT)))
    check(menu != wheel and wheel not in px["port"], "port never shows the original's wheel question (%s)" %
          shots["original"][-1].relative_to(ROOT))
    port_set = set(px["port"])
    titles = [(f, p) for f, p in zip(shots["original"][:-1], px["original"][:-1]) if p[0] == (320, 200)]
    missing = [f for f, p in titles if p not in port_set]
    check(bool(titles) and not missing, "port shows all %d title screens of the original pixel for pixel%s" % (
        len(titles), "" if not missing else " (missing: %s)" % ", ".join(f.name for f in missing[:5])))
    print("tandy: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
