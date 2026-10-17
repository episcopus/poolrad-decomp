#!/usr/bin/env python3
"""oracle_files.py: the files a session writes on the original (the oracle's save layer), written to a folder, to
compare byte for byte with what the C translation wrote.  oracle_files.py SESSION OUTDIR"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from oracle import golden  # noqa: E402

session, out = sys.argv[1], Path(sys.argv[2])
s, rec = golden.run_once(session)
m = s["_machine"]
out.mkdir(parents=True, exist_ok=True)
for path, data in m.vfs.layer.items():
    (out / path.replace("\\", "_").strip("_")).write_bytes(bytes(data))
print(len(m.vfs.layer), "files")
