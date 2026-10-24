#!/usr/bin/env python3
"""routine_profile.py: which routines each session really runs, and when (step 8.11, code residency).

Runs the sessions in the oracle (the original DOS game, tools/oracle) with call tracing on and keeps, per session:
  * the sequence of routines that run (each call, and each return to the caller) as (instruction count, routine) pairs, runs folded,
  * per routine: calls, instructions spent in the routine itself (exclusive) and with its callees (inclusive).
The names are the original's (re/symbols.toml); tools/codeprof.py maps them to the port's code. Runtime routines
(System_, Crt_, Dos_, Overlay_) are not part of the port's banks and are left out.

  python3 tools/routine_profile.py [session ...]       -> build/profile/<session>.json (.seq.npy beside it)
  python3 tools/routine_profile.py --summary           -> one table over the profiles that exist

Needs the repository's .venv (unicorn): tools/oracle is imported from the repository root."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))

OUT = HERE.parent / "build" / "profile"
SKIP = ("Overlay_", "System_", "Crt_", "Dos_")
# the runtime routines the port keeps in its own bank (src/game/rtl_heap.c, rtl_file.c, rtl_strx.c): they take a slot of the code pool when they run,
# so the profile keeps them (the other runtime routines are in the core or the engine and cost the pool nothing)
RTL = {"System_" + n for n in (
    "Insert StrLong ValLong GetMem FreeMem Assign AssignText Reset ResetText Rewrite RewriteText AppendText Close CloseText Erase Seek FilePos "
    "FileSize Eof Eoln Truncate FlushText BlockRead BlockWrite ReadString ReadChar ReadLn WriteString WriteChar WriteLn").split()}


def profile(session: str) -> dict:
    from oracle import golden, trace
    from oracle.run import run_session
    import array

    OUT.mkdir(parents=True, exist_ok=True)
    prog = OUT / (session + ".progress")                  # "insns done, insns expected, depth of the profile stack, depth of the tracer's"
    beat = [0]
    try:
        total_insns = json.loads((golden.SESSIONS / "golden" / session / "golden.json").read_text())["instructions"]
    except (OSError, KeyError, ValueError):
        total_insns = 0
    names: dict[str, int] = {}
    order: list[str] = []
    seq_id = array.array("H")
    seq_t = array.array("L")
    stats: dict[int, list[int]] = {}      # id -> [calls, exclusive insns, inclusive insns]
    stack: list[list[int]] = []           # [id, entry insns, insns in callees]
    last = [-1]

    class Tracer(trace.Tracer):
        """The oracle's call tracer, but frames that were left without a return (the original unwinds its stack in places) are dropped when
        a later call shows the stack is shallower than the frame was: the shadow stack and its indentation otherwise grow for ever and a
        long session slows down quadratically."""

        def _on_block(self, uc, addr, size, _ud):
            sh = self.shadow
            rid = self.entry_map.get(addr) if sh else None
            if rid is not None and not (sh and addr == sh[-1][0]):
                sp = self.m.get("sp")
                while sh and sh[-1][1] <= sp:
                    sh.pop()
                    self.depth = max(0, self.depth - 1)
                    self.emit("leak")
            super()._on_block(uc, addr, size, _ud)

    def prepare(m):
        tr = Tracer(m, calls=True, out=None)

        def emit(line):
            s = line.lstrip()
            t = m.insns
            if t >= beat[0]:                              # progress for whoever watches: instructions run, of those the golden recorded
                beat[0] = t + 2_000_000
                prog.write_text("%d %d %d %d\n" % (t, total_insns, len(stack), len(tr.shadow)))
            if s.startswith("call "):
                name = s[5:].split("(")[0]
                if name.startswith(SKIP) and name not in RTL:
                    stack.append([-1, t, 0])
                    return
                i = names.get(name)
                if i is None:
                    i = names[name] = len(order)
                    order.append(name)
                stats.setdefault(i, [0, 0, 0])[0] += 1
                stack.append([i, t, 0])
                if i != last[0] or not seq_id:
                    seq_id.append(i)
                    seq_t.append(t & 0xFFFFFFFF)
                last[0] = i
            elif s.startswith("leak"):
                if stack:
                    i, t0, inner = stack.pop()
                    if stack:
                        stack[-1][2] += t - t0
                    if i >= 0:
                        st = stats[i]
                        st[1] += t - t0 - inner
                        st[2] += t - t0
            elif s.startswith("ret "):
                if not stack:
                    return
                i, t0, inner = stack.pop()
                span = t - t0
                if i >= 0:
                    st = stats[i]
                    st[1] += span - inner
                    st[2] += span
                if stack:
                    stack[-1][2] += span
                top = stack[-1][0] if stack else -1       # the routine that runs again: a return is a use of its code too
                if top >= 0 and top != last[0]:
                    seq_id.append(top)
                    seq_t.append(t & 0xFFFFFFFF)
                last[0] = top
        tr.emit = emit

    text = (golden.SESSIONS / (session + ".keys")).read_text()
    summ = run_session(text, max_insns=golden.session_limit(text), quiet=True, prepare=prepare, insn_per_sec=golden.INSN_PER_SEC)
    prog.write_text("%d %d 0 0\n" % (total_insns, total_insns))
    total = int(summ.get("insns") or (seq_t[-1] if seq_t else 0))
    rec = {"session": session, "insns": total, "routines": order,
           "stats": {order[i]: v for i, v in stats.items()}}
    (OUT / (session + ".json")).write_text(json.dumps(rec))
    with open(OUT / (session + ".seq"), "wb") as f:       # id (u16) and time (u32) arrays, little endian, same length
        n = len(seq_id)
        f.write(n.to_bytes(4, "little"))
        if sys.byteorder != "little":
            seq_id.byteswap(); seq_t.byteswap()
        seq_id.tofile(f)
        seq_t.tofile(f)
    return rec


def load(session: str):
    """(record, ids, times) of a stored profile"""
    import array
    rec = json.loads((OUT / (session + ".json")).read_text())
    with open(OUT / (session + ".seq"), "rb") as f:
        n = int.from_bytes(f.read(4), "little")
        ids = array.array("H"); ids.fromfile(f, n)
        ts = array.array("L"); ts.fromfile(f, n)
        if sys.byteorder != "little":
            ids.byteswap(); ts.byteswap()
    return rec, ids, ts


def summary() -> None:
    rows = []
    for p in sorted(OUT.glob("*.json")):
        r = json.loads(p.read_text())
        calls = sum(v[0] for v in r["stats"].values())
        rows.append((r["session"], r["insns"], len(r["stats"]), calls))
    print("%-20s %12s %9s %10s" % ("session", "insns", "routines", "calls"))
    for s, n, k, c in rows:
        print("%-20s %12d %9d %10d" % (s, n, k, c))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("sessions", nargs="*")
    ap.add_argument("--summary", action="store_true")
    a = ap.parse_args(argv)
    if a.summary:
        summary()
        return 0
    sessions = a.sessions or sorted(p.stem for p in (ROOT / "tests/sessions").glob("*.keys") if p.stem != "create-elf-mage")
    for s in sessions:
        rec = profile(s)
        print("%-20s %12d insns %5d routines %9d calls" % (s, rec["insns"], len(rec["stats"]), sum(v[0] for v in rec["stats"].values())), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
