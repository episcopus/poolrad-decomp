#!/usr/bin/env python3
"""Build the one-page area maps into docs/maps/.

  uv run --with reportlab python tools/maps/build.py            # every map
  uv run --with reportlab python tools/maps/build.py sokal-keep # one map

Reads poolrad/*.DAX (pinned originals); writes docs/maps/<name>.pdf."""
import importlib
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
OUT = HERE.parents[1] / 'docs' / 'maps'
MODULES = {'sokal-keep': 'sokal_keep', 'phlan': 'phlan', 'slums': 'slums'}


def main(argv):
    names = argv[1:] or list(MODULES)
    OUT.mkdir(parents=True, exist_ok=True)
    import mapkit
    for n in names:
        spec = importlib.import_module(MODULES[n]).SPEC
        out = OUT / (spec['name'] + '.pdf')
        fs = mapkit.build(spec, str(out))
        print('%s: %s (body %.1f pt)' % (n, out.relative_to(HERE.parents[1]), fs))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
