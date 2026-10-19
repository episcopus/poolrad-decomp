#!/usr/bin/env python3
"""baseline_table.py: the verdicts of a `make baseline` as a Markdown table (docs/PHASE-8.7b.md section 3).

  python3 tools/baseline_table.py [session ...]

Per session: the labelled golden screens the CoCo showed in order (gamecheck.py), the unlabelled ones, the end of the run (a fatal code of the program, from the mailbox
the run left), and the state check (statecheck.py: DGROUP and the files against the host's at the same read). The screens of a camp are not compared bit for bit
(the portrait animates with the clock): their verdict is the state."""
import glob
import os
import re
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
COCO = os.path.abspath(os.path.join(HERE, ".."))
os.chdir(COCO)


def run(*a):
    return subprocess.run(a, capture_output=True, text=True).stdout


def fatal(session):
    f = "build/run/game-%s.mbx" % session
    if not os.path.exists(f):
        return "no run"
    d = open(f, "rb").read()
    status = d[5] if len(d) > 5 else 0
    if status == 2:
        r30 = struct.unpack(">H", d[0x10 + 30 * 2:0x10 + 30 * 2 + 2])[0]
        r29 = struct.unpack(">H", d[0x10 + 29 * 2:0x10 + 29 * 2 + 2])[0]
        return "fatal 0x%02X (%d)" % (r30, r29)
    return ""


def main():
    names = sys.argv[1:] or sorted(os.path.basename(p)[:-5] for p in glob.glob("../../tests/sessions/*.keys") if "create-elf-mage" not in p)
    print("| session | labelled screens | unlabelled | state (DGROUP places) | party records | the run ended |")
    print("|---|---|---|---|---|---|")
    for s in names:
        g = run("python3", "-I", "tools/gamecheck.py", s, "build/run/game-" + s).strip().split("\n")[-1]
        m = re.search(r"(\d+) of (\d+) labelled golden screens shown in order, (\d+) of (\d+) unlabelled", g)
        lab = "%s of %s" % (m.group(1), m.group(2)) if m else "?"
        unl = "%s of %s" % (m.group(3), m.group(4)) if m else "?"
        st = run("python3", "-I", "tools/statecheck.py", s, "build/run/game-" + s)
        m = re.search(r"dgroup: (\d+) places equal, (\d+) differ for a reason.*?, (\d+) differ and are open", st)
        stt = "%s equal, %s explained, %s open" % m.groups() if m else ("no state check" if "no state comparison" in st else "?")
        m = re.search(r"party: (\d+) records, (\d+) differ", st)
        pty = "%s, %s differ" % m.groups() if m else ""
        print("| `%s` | %s | %s | %s | %s | %s |" % (s, lab, unl, stt, pty, fatal(s)))


if __name__ == "__main__":
    main()
