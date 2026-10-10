#!/usr/bin/env python3
"""dosbox_ref.py: compare the oracle's screens with DOSBox-X's (playbook 25 acceptance check 1).

DOSBox-X runs the unpacked executable headless (SDL dummy video driver) under its own `dx-capture`,
which records the emulated video to a lossless ZMBV AVI at the program's native resolution. ffmpeg
decodes the AVI to PNG frames; each screenshot the oracle took in `tests/sessions/boot-title.keys` must
equal one DOSBox-X frame in every pixel (same mode, same pixels).

Everything is written under build/dosbox (ignored by git). Game files are symlinked, never copied.

  .venv/bin/python tools/oracle/dosbox_ref.py [--seconds 30] [--skip-record]

Exit codes: 0 all screens match, 1 a screen has no matching frame, 77 DOSBox-X or ffmpeg is missing.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build/dosbox"
SCREENS = ("ssi-logo", "title", "credits")


def prepare_mount() -> Path:
    c = BUILD / "c"
    pool = c / "POOLRAD"
    if pool.exists():
        shutil.rmtree(c)
    pool.mkdir(parents=True)
    src = ROOT / "poolrad"
    for p in sorted(src.iterdir()):
        if p.is_file() and p.suffix.upper() in (".DAX", ".OVR") or p.name in ("ITEMS", "POOL.CFG"):
            os.symlink(p.resolve(), pool / p.name)
    os.symlink((src / "start-unpack.exe").resolve(), pool / "GAMEX.EXE")
    (pool / "SAVE").mkdir()
    return c


def record(seconds: int) -> Path:
    c = prepare_mount()
    cap = BUILD / "cap"
    if cap.exists():
        shutil.rmtree(cap)
    cap.mkdir(parents=True)
    conf = BUILD / "poolrad.conf"
    conf.write_text(f"""[dosbox]
captures={cap}
machine=ega
[cpu]
cycles=max
[render]
aspect=false
scaler=none
[sdl]
output=surface
[autoexec]
mount c {c}
c:
cd poolrad
dx-capture /v gamex.exe
exit
""")
    env = dict(os.environ, SDL_VIDEODRIVER="dummy")
    subprocess.run(["dosbox-x", "-conf", str(conf), "-nopromptfolder", "-nogui", "-fastlaunch", "-silent",
                    "-time-limit", str(seconds)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   check=False)
    avis = sorted(cap.glob("*.avi"), key=lambda p: p.stat().st_size)
    if not avis:
        raise RuntimeError("DOSBox-X produced no capture")
    return avis[-1]                       # the game run; a tiny first file is the shell prompt


def extract(avi: Path, fps: int = 4) -> Path:
    frames = BUILD / "frames"
    if frames.exists():
        shutil.rmtree(frames)
    frames.mkdir(parents=True)
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(avi), "-vf", f"fps={fps}",
                    str(frames / "f%04d.png")], check=True)
    return frames


def oracle_screens(out: Path) -> dict[str, Path]:
    from oracle.run import run_session
    text = (ROOT / "tests/sessions/boot-title.keys").read_text()
    run_session(text, max_insns=120_000_000, out_dir=out, quiet=True, digests=False)
    return {n: out / "shots" / (n + ".png") for n in SCREENS}


def rgb_bytes(path: Path) -> tuple[tuple[int, int], bytes]:
    from PIL import Image
    im = Image.open(path).convert("RGB")
    return im.size, im.tobytes()


def compare(shots: dict[str, Path], frames: Path) -> dict[str, str | None]:
    ref = {}
    for f in sorted(frames.glob("*.png")):
        size, data = rgb_bytes(f)
        ref.setdefault((size, data), f.name)
    result = {}
    for name, p in shots.items():
        size, data = rgb_bytes(p)
        result[name] = ref.get((size, data))
    return result


def available() -> bool:
    return shutil.which("dosbox-x") is not None and shutil.which("ffmpeg") is not None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--seconds", type=int, default=30, help="DOSBox-X wall-clock time limit")
    ap.add_argument("--skip-record", action="store_true", help="reuse build/dosbox/frames")
    a = ap.parse_args(argv)
    if not available():
        print("dosbox-x and ffmpeg are required (brew install dosbox-x ffmpeg)", file=sys.stderr)
        return 77
    BUILD.mkdir(parents=True, exist_ok=True)
    frames = BUILD / "frames"
    if not a.skip_record:
        frames = extract(record(a.seconds))
    shots = oracle_screens(BUILD / "oracle")
    res = compare(shots, frames)
    ok = True
    for name, f in res.items():
        print("%-10s %s" % (name, ("identical to DOSBox-X %s" % f) if f else "NO MATCHING DOSBOX-X FRAME"))
        ok &= f is not None
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
