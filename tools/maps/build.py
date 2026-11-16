#!/usr/bin/env python3
"""Build the one-page area maps into docs/maps/.

  uv run --with reportlab python tools/maps/build.py            # every area in tools/maps/areas/
  uv run --with reportlab python tools/maps/build.py slums      # one, by its SPEC name
  uv run --with reportlab python tools/maps/build.py world      # only the world map (world.py), docs/maps/world-map.pdf
  uv run --with reportlab --with pillow python tools/maps/build.py wilderness   # the four outdoor maps (wilderness.py)

Each tools/maps/areas/<file>.py defines SPEC (see mapkit.py). Reads poolrad/*.DAX (pinned originals);
writes docs/maps/<SPEC name>.pdf."""
import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
OUT = HERE.parents[1] / 'docs' / 'maps'


def specs():
    found = {}
    for f in sorted((HERE / 'areas').glob('*.py')):
        if f.name.startswith('_'):
            continue
        mod = importlib.util.spec_from_file_location('areas_' + f.stem, f)
        m = importlib.util.module_from_spec(mod)
        mod.loader.exec_module(m)
        found[m.SPEC['name']] = m.SPEC
    return found


def main(argv):
    import mapkit
    import world
    import wilderness
    allspecs = specs()
    names = argv[1:] or list(allspecs) + ['world'] + list(wilderness.PAGES)
    OUT.mkdir(parents=True, exist_ok=True)
    for n in names:
        if n == 'world':  # the one-page world map: how the areas connect (tools/maps/world.py)
            print('world: %s' % Path(world.build(OUT / 'world-map.pdf')).relative_to(HERE.parents[1]))
            continue
        if n == 'wilderness' or n in wilderness.PAGES:  # the outdoor maps (tools/maps/wilderness.py): all four, or one
            wilderness.build(None if n == 'wilderness' else [n])
            continue
        if n not in allspecs:
            print('no area named %s (have: %s)' % (n, ', '.join(allspecs)))
            return 2
        out = OUT / (n + '.pdf')
        fs = mapkit.build(allspecs[n], str(out))
        print('%s: %s (body %.1f pt)' % (n, out.relative_to(HERE.parents[1]), fs))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
