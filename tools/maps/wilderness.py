#!/usr/bin/env python3
"""wilderness: one-page outdoor maps of Pool of Radiance (US Letter landscape): the overworld the party walks between
New Phlan, Old Phlan and the wilderness, drawn from the game's own terrain tiles.

  uv run --with reportlab --with pillow python tools/maps/wilderness.py           # all four pages
  uv run --with reportlab --with pillow python tools/maps/wilderness.py overworld  # one
  uv run --with reportlab --with pillow python tools/maps/build.py wilderness      # the same through build.py

Pages written to docs/maps/: `overworld.pdf` (the whole map, 44 x 36 blocks), `outdoor-west.pdf`, `outdoor-north-shore.pdf`
and `outdoor-east.pdf` (one strip each: 16 columns, the squares the game's menus use).

Developer notes (not drawn). The overworld is `AreaMap` (DGROUP 0x3648, 36 rows x 44 columns of bytes; file offset
0x10808 of poolrad/start-unpack.exe, the same bytes the game keeps in memory). A byte minus 1 is a picture code: codes
0..127 are pictures of SQRPACI.DAX block 1 (SqrPaciBank1), codes 128..255 are pictures 0..127 of block 2 (SqrPaciBank2);
each picture is 24x24 pixels (one block). The three wilderness scripts see the map as strips of 16 columns:
`MapBaseX` is 0, 13 and 26 for tile sets 6 (west), 7 (North Shore) and 8 (east), so a square (x, y) of a strip is
AreaMap[y][base + x]. The special squares the scripts test (Ruined Castle (11,8), Zhentil (3,32), ...) all hold
the special icon blocks of the map, which is how this mapping was confirmed.

Walking rules are `CheckMapCell` (src/OVL14.PAS): a step onto a byte in `$4E`, `$7E..$80`, `$82..$84`, `$A8..$AC`,
`$AE..$B3`, `$BC`, `$DD..$DE`, `$E1..$E9` or `$F5` does nothing (sea, shore pieces, the pyramid, the city's centre); a
step onto `$66..$6C` or `$72` (17 river squares) prints "The river's stench drives you back." while game word 418
(script address 4AA2) is 0; anything else is a step. The North Shore script sets word 418 to 255 once the pyramid quest flag
(4AB3) reaches 254, and rewrites river squares of the map then (SETTABLE), so the squares drawn as river are the
polluted state in the executable. Routes on the pages are Dijkstra paths over those rules (a small penalty per turn so
they look like a walk) and are drawn from the boat landings the harbor master's menu leads to.
"""
import io
import sys
import heapq
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / 'tools' / 're'))
import dax  # noqa: E402
import pic  # noqa: E402
import mapkit  # noqa: E402
from mapkit import (AMBER, BLUE, BOX, BOXLINE, FONT, FONTB, FONTI, GREEN, INK, MUTED, PURPLE, RED,  # noqa: E402
                    TYPECOL, STANDARD_NOTE, Overflow)

from PIL import Image  # noqa: E402
from reportlab.lib.colors import HexColor, white  # noqa: E402
from reportlab.lib.pagesizes import landscape, letter  # noqa: E402
from reportlab.lib.styles import ParagraphStyle  # noqa: E402
from reportlab.lib.utils import ImageReader  # noqa: E402
from reportlab.pdfbase.pdfmetrics import stringWidth  # noqa: E402
from reportlab.pdfgen import canvas  # noqa: E402
from reportlab.platypus import Paragraph  # noqa: E402

OUT = ROOT / 'docs' / 'maps'
W, H = landscape(letter)
M = 22

ROWS, COLS = 36, 44
BASES = {'west': 0, 'north-shore': 13, 'east': 26}

BLOCKED = set([0x4E] + list(range(0x7E, 0x81)) + list(range(0x82, 0x85)) + list(range(0xA8, 0xAD)) +
              list(range(0xAE, 0xB4)) + [0xBC, 0xDD, 0xDE] + list(range(0xE1, 0xEA)) + [0xF5])
RIVER = set(list(range(0x66, 0x6D)) + [0x72])


# ---------------------------------------------------------------- the map data

def load_map():
    data = (ROOT / 'poolrad' / 'start-unpack.exe').read_bytes()
    off = 0x3648 + 0xD1C0
    return [list(data[off + r * COLS: off + (r + 1) * COLS]) for r in range(ROWS)]


def load_tiles():
    banks = {}
    for blk in dax.read_dax(str(ROOT / 'poolrad' / 'SQRPACI.DAX')):
        meta, _ = pic.parse_picture(dax.unrle(blk['data']))
        banks[blk['id']] = meta
    cache = {}

    def tile(code):
        if code not in cache:
            cache[code] = pic.to_image(banks[1 if code < 128 else 2], code & 0x7F)
        return cache[code]
    return tile


AM = load_map()
_TILE = load_tiles()


def terrain_image(c0, c1, r0, r1, zoom=2):
    """the terrain of AreaMap columns c0..c1 and rows r0..r1 (inclusive) as one image, `zoom` times its pixels"""
    img = Image.new('RGB', ((c1 - c0 + 1) * 24, (r1 - r0 + 1) * 24))
    for r in range(r0, r1 + 1):
        for c in range(c0, c1 + 1):
            img.paste(_TILE(AM[r][c] - 1), ((c - c0) * 24, (r - r0) * 24))
    if zoom != 1:
        img = img.resize((img.width * zoom, img.height * zoom), Image.NEAREST)
    return img


def walkable(c, r, river_clean=False):
    b = AM[r][c]
    if b in BLOCKED:
        return False
    if b in RIVER and not river_clean:
        return False
    return True


def route(start, goal, river_clean=False, turn=0.6):
    """walkable path between two AreaMap squares (col, row), with a small penalty per turn; list of squares"""
    best = {}
    heap = [(0.0, start, None)]
    came = {}
    while heap:
        cost, cur, d = heapq.heappop(heap)
        if (cur, d) in best:
            continue
        best[(cur, d)] = cost
        if cur == goal:
            path = [cur]
            key = (cur, d)
            while key in came:
                key = came[key]
                path.append(key[0])
            return path[::-1]
        for nd, (dc, dr) in enumerate(((1, 0), (-1, 0), (0, 1), (0, -1))):
            n = (cur[0] + dc, cur[1] + dr)
            if not (0 <= n[0] < COLS and 0 <= n[1] < ROWS) or not walkable(n[0], n[1], river_clean) and n != goal:
                continue
            nc = cost + 1 + (turn if d is not None and nd != d else 0)
            if (n, nd) not in best:
                came.setdefault((n, nd), (cur, d))
                heapq.heappush(heap, (nc, n, nd))
    return None


def words(path):
    """a path as '4 east, then 1 north'"""
    name = {(1, 0): 'east', (-1, 0): 'west', (0, 1): 'south', (0, -1): 'north'}
    runs = []
    for a, b in zip(path, path[1:]):
        d = (b[0] - a[0], b[1] - a[1])
        if runs and runs[-1][0] == d:
            runs[-1][1] += 1
        else:
            runs.append([d, 1])
    return ', then '.join('%d %s' % (n, name[d]) for d, n in runs)


def how_far(a, b):
    """'15 squares north and 1 west': the straight-line offset from square a to square b (the terrain between is visible)"""
    dx, dy = b[0] - a[0], b[1] - a[1]
    parts = []
    if dy:
        parts.append('%d %s' % (abs(dy), 'south' if dy > 0 else 'north'))
    if dx:
        parts.append('%d %s' % (abs(dx), 'east' if dx > 0 else 'west'))
    return ' and '.join(parts)


def strip_path(strip, a, b, **kw):
    """route between two squares given in overworld columns (the numbering the pages print)"""
    return route(a, b, **kw)


# ---------------------------------------------------------------- the pages
# Each strip is a dict; squares are (column, row) in OVERWORLD columns (0..43), the numbering the game shows. The drawing code
# converts them to the strip's own columns (minus its base) only to place them on the picture.

LANDING_W = (20, 29)     # the WEST boat lands on the North Shore (strip square (7,29))
GATE_W, GATE_N, GATE_E = (24, 28), (26, 26), (26, 27)
ROWBOAT, NOMAD, PYRAMID = (19, 14), (25, 11), (19, 16)


def north_shore():
    to_gate = strip_path('north-shore', LANDING_W, GATE_W)
    to_north = strip_path('north-shore', LANDING_W, GATE_N)
    return dict(
        name='outdoor-north-shore', strip='north-shore', rows=(0, 33),
        title='NORTH SHORE',
        subtitle=('Outdoor map around Old Phlan: the boat landings, the old city\'s gates', 'Pool of Radiance (SSI, DOS)  |  outdoor map  |  SPOILERS'),
        markers=[('1', LANDING_W, 'hint'), ('2', GATE_W, 'place'), ('3', GATE_N, 'place'), ('4', GATE_E, 'place'),
                 ('5', ROWBOAT, 'place'), ('6', PYRAMID, 'secret'), ('7', NOMAD, 'place')],
        extra=[((25, 26), 'place')],
        routes=[(to_gate, '#1f5fa8', 2.0)],
        edges=[('W', 'to the West Wilderness'), ('E', 'to the East Wilderness')],
        labels=[('SEA', 22, 31.6, 7.0), ('river', 21.5, 23.3, 5.2), ('mountains', 17.5, 3, 6.6), ('lake', 19.0, 15.0, 5.0)],
        glance=('<b>THE BIG PICTURE</b> You are on the north shore of the bay, across the water from New Phlan. <b>Old Phlan</b> is the ruined city at the mouth of the river '
                '(squares around (25,27)). Its streets are <b>not</b> on this map: you enter them from three gates, and the game asks which way to go '
                '(see 2, 3 and 4). <b>Boats from New Phlan:</b> WEST lands at <b>1</b>, BAY lands at <b>4</b>. Both boats wait to take you back '
                '(TAKE BOAT). <b>One step in 20</b> brings a random encounter; about 1 in 21 of those finds the lizard men\'s grove (its plan is on the North Shore area page).'),
        entries=[
            ('1', 'hint', 'WEST boat landing (20,29)',
             'You land on the south shore, <b>west</b> of the river mouth. TAKE BOAT returns to New Phlan, STAY lets you walk. '
             + '<b>To the west gate (2):</b> walk %s (the blue line).' % words(to_gate)),
            ('2', 'place', 'Old Phlan, west gate (24,28)',
             'Asks "which entrance?": <b>NORTH</b> = Podal Plaza, <b>SOUTH</b> = Cadorna Textile House, LEAVE. Podal Plaza is the way on to Stojanow Gate and the castle, '
             'and east to Kuto\'s Well and the Slums.'),
            ('3', 'place', 'Old Phlan, north gate (26,26) and (25,26)',
             'Asks "northern city gates or the graveyard?": <b>CITY</b> = Kovel Mansion, <b>GRAVEYARD</b> = Valhingen Graveyard, LEAVE. It is one square north of the east gate (4); from the WEST landing walk %s.' % words(to_north)),
            ('4', 'place', 'Old Phlan, east gate (26,27): the BAY landing',
             '<b>NORTH</b> = Kovel Mansion, <b>SOUTH</b> = Temple of Bane (its east side leads on to the Orc Mansion), <b>BOAT</b> = back to New Phlan, LEAVE.'),
            ('5', 'place', 'Rowboat in the reeds (19,14)',
             'YES rows you to the pyramid; at <b>6</b> answer ENTER (GO BACK returns you to the rowboat). The pyramid squares themselves cannot be walked onto. '
             'It lies %s of the WEST landing (the forest and the river valley are in between; go round the river squares).' % how_far(LANDING_W, ROWBOAT)),
            ('6', 'secret', 'Pyramid (19,16)',
             'The maze level, then Yarash\'s Lab. Ending the pollution there clears the river (see the river note). Reached only from the rowboat.'),
            ('7', 'place', 'Nomad Camp (25,11)',
             'ENTER or LEAVE. It lies %s of the WEST landing, or %s of the east gate (4).' % (how_far(LANDING_W, NOMAD), how_far(GATE_E, NOMAD))),
        ],
        boxes=[
            '<b>WALKING</b> Every step is one square; you cannot walk on the sea, the shore pieces, the pyramid or the city\'s middle (shaded). '
            '<b>RIVER</b> (yellow hatch, 17 squares on the whole map): "The river\'s stench drives you back" until the pollution in Yarash\'s Lab is ended; '
            'the river then runs clean and can be crossed.',
            '<b>EDGES</b> The map is continuous with its neighbours: walk west past column 15 and you are on the West Wilderness map (its column 14); walk east past column 28 and you are on the East Wilderness map (its column 29).',
            '<b>COMMON TRIPS FROM NEW PHLAN</b><br/>'
            '<b>Podal Plaza by boat:</b> harbor master WEST; if the landing (1) asks TAKE BOAT or STAY, answer STAY; walk %s to the west gate (2); answer NORTH. '
            '<b>On foot instead:</b> New Phlan\'s west gate leads to the Slums, then Kuto\'s Well, then west to Podal Plaza.<br/>'
            '<b>Cadorna Textile House:</b> the same, but answer SOUTH at the west gate.<br/>'
            '<b>Kovel Mansion:</b> harbor master BAY; at the east gate (4) answer NORTH. <b>Temple of Bane:</b> BAY, then SOUTH. '
            '<b>Valhingen Graveyard:</b> BAY, answer LEAVE, step one square north, answer GRAVEYARD.<br/>'
            '<b>Castle:</b> via Podal Plaza, then north through Stojanow Gate. <b>Nomad Camp, Pyramid:</b> see 7 and 5.' % words(to_gate),
        ],
    )


def west():
    return dict(
        name='outdoor-west', strip='west', rows=(0, 33),
        title='WEST WILDERNESS',
        subtitle=('Outdoor map of the mountains and plains in the far west', 'Pool of Radiance (SSI, DOS)  |  outdoor map  |  SPOILERS'),
        markers=[('1', (10, 9), 'hint'), ('2', (12, 31), 'fight'), ('3', (3, 32), 'fight')],
        extra=[((10, 8), 'hint'), ((11, 8), 'hint'), ((9, 9), 'hint'), ((11, 9), 'hint'), ((9, 10), 'hint'), ((10, 10), 'hint'),
               ((8, 24), 'fight'),
               ((12, 30), 'loot'), ((13, 30), 'loot'), ((11, 31), 'loot'), ((13, 31), 'loot'), ((12, 32), 'loot'), ((13, 32), 'loot'),
               ((2, 31), 'secret'), ((3, 31), 'secret'), ((2, 32), 'secret'), ((4, 32), 'secret'), ((2, 33), 'secret'), ((3, 33), 'secret')],
        routes=[],
        edges=[('E', 'to the North Shore')],
        labels=[('SEA', 7, 33.0, 7.0), ('mountains', 5.5, 5.5, 8.0)],
        glance=('<b>THE BIG PICTURE</b> Mountains in the north-west, plains and forest below. You arrive from the North Shore at column 14 on the row you left it. '
                '<b>Three places, each asks one question.</b> The squares around them (coloured) trigger a scripted event once. '
                '<b>One step in 20</b> brings a random encounter; about 1 in 21 of those finds a small dark cave (its plan is on the Small Dark Cave page).'),
        entries=[
            ('1', 'hint', "Diogenes' Cave (10,9)",
             'Asks about the large cave: <b>ENTER CAVE</b> or IGNORE CAVE. Text scenes only: the silver dragon, his quest and the silver bottle. '
             'The coloured squares around it show the dragon flying down behind a mountain (once).'),
            ('2', 'fight', 'Buccaneer Base (12,31)',
             'Asks: <b>ENTER</b> or LEAVE. Offered only while the City Hall quest for the heir of House Bivant is open and the boy is not yet saved. '
             'The squares around it (amber) show slavers riding toward the base.'),
            ('3', 'fight', 'Zhentil Outpost (3,32)',
             'Horsemen ask "are you the diplomatic envoys from New Phlan?": <b>YES</b> or NO. YES works only with City Hall\'s sealed message packet; it is a trap. '
             'The squares around it (purple) have armed guards riding by.'),
            ('!', 'fight', 'Anhkhegs (8,24)',
             'Two anhkhegs burst out of the ground when you step here (a fight, once per visit).'),
        ],
        boxes=[
            '<b>GETTING HERE</b> From the North Shore walk west past column 15: you land at column 14 of this map. '
            'Walking east past column 15 of this map leads back to the North Shore (its column 16).',
            '<b>WALKING</b> Every step is one square; the shaded squares (sea) cannot be walked on. The thin rivers drawn here can be crossed: only the 17 "stench" river squares of the North Shore block you.',
        ],
    )


def east():
    landing, castle, caves = (35, 29), (37, 8), (32, 15)
    to_kobold = strip_path('east', landing, caves)
    to_castle = strip_path('east', landing, castle)
    return dict(
        name='outdoor-east', strip='east', rows=(0, 33),
        title='EAST WILDERNESS',
        subtitle=('Outdoor map of the east: Ruined Castle and Kobold Caves', 'Pool of Radiance (SSI, DOS)  |  outdoor map  |  SPOILERS'),
        markers=[('1', castle, 'place'), ('2', caves, 'fight'), ('3', landing, 'hint')],
        extra=[((27, 6), 'place'), ((28, 7), 'place'), ((32, 14), 'fight'), ((33, 14), 'fight'), ((31, 15), 'fight'), ((33, 15), 'fight'),
               ((32, 16), 'fight'), ((33, 16), 'fight')],
        routes=[(to_kobold, '#b3261e', 1.4), (to_castle, '#1f5fa8', 1.4)],
        edges=[('W', 'to the North Shore')],
        labels=[('SEA', 35, 31.8, 7.0), ('badlands', 34, 5, 7.0)],
        glance=('<b>THE BIG PICTURE</b> Rough dark hills and valleys in the east. The <b>EAST</b> boat from New Phlan lands at <b>3</b> on the south coast; the boat waits there. '
                '<b>One step in 20</b> brings a random encounter; about 1 in 21 of those finds a small dark cave (its plan is on the East Wilderness page).'),
        entries=[
            ('1', 'place', 'Ruined Castle (37,8)',
             'Asks: <b>ENTER</b> or LEAVE ("ruined castle surrounded by quicksand, an old worn drawbridge is the only safe way across"). The same prompt appears at (27,6) and (28,7). '
             'From the landing: %s (the blue line).' % words(to_castle)),
            ('2', 'fight', 'Kobold Caves (32,15)',
             'Two caves: <b>LARGE</b> (the obvious one), <b>SMALL</b> (hidden) or EXIT. The squares around them (red) hold a kobold ambush of about 30, once per visit and only until the kobold business is settled (not confirmed in play). '
             'From the landing: %s (the red line).' % words(to_kobold)),
            ('3', 'hint', 'EAST boat landing (35,29)',
             'TAKE BOAT returns you to New Phlan; STAY lets you walk.'),
        ],
        boxes=[
            '<b>GETTING HERE</b> By the EAST boat from New Phlan, or from the North Shore: walk east past column 28 and you arrive at column 29 of this map. '
            'Walking west past column 28 returns you to the North Shore (its column 27).',
            '<b>WALKING</b> Every step is one square; the shaded squares (sea) cannot be walked on. The thin rivers drawn here can be crossed: only the 17 "stench" river squares of the North Shore block you.',
        ],
    )


# ---------------------------------------------------------------- drawing

KIND_HEX = {'hint': '#1f5fa8', 'place': '#4a5560', 'fight': '#b3261e', 'loot': '#b7791f', 'secret': '#6b3fa0'}


def header(c, title, subtitle, tsize=25):
    c.setFillColor(INK)
    c.setFont(FONTB, tsize)
    c.drawString(M, H - M - 20, title)
    tw = stringWidth(title, FONTB, tsize)
    c.setFont(FONT, 9)
    c.setFillColor(MUTED)
    c.drawString(M + tw + 14, H - M - 8, subtitle[0])
    c.drawString(M + tw + 14, H - M - 20, subtitle[1])
    c.setFont(FONTI, 6.6)
    c.drawRightString(W - M, H - M - 8, STANDARD_NOTE[0])
    c.drawRightString(W - M, H - M - 17, 'Squares are (column,row) as on the Overworld page, from 0, top left.')
    c.setStrokeColor(INK)
    c.setLineWidth(1.2)
    c.line(M, H - M - 28, W - M, H - M - 28)


def halo_text(c, x, y, text, size, color=INK, font=None, centre=True):
    font = font or FONTB
    c.setFont(font, size)
    tw = stringWidth(text, font, size)
    x0 = x - tw / 2 if centre else x
    c.setFillColor(white)
    for dx, dy in ((-0.5, 0), (0.5, 0), (0, -0.5), (0, 0.5), (-0.5, -0.5), (0.5, 0.5), (-0.5, 0.5), (0.5, -0.5)):
        c.drawString(x0 + dx, y + dy, text)
    c.setFillColor(color)
    c.drawString(x0, y, text)


def marker(c, num, x, y, kind, rad=5.4):
    c.setFillColor(white)
    c.circle(x, y, rad + 1.2, fill=1, stroke=0)
    c.setFillColor(TYPECOL[kind])
    c.circle(x, y, rad, fill=1, stroke=0)
    c.setFillColor(white)
    c.setFont(FONTB, 6.4 if len(num) == 1 else 5.6)
    c.drawCentredString(x, y - 2.2, num)


def draw_overlays(c, cx, cy, cell, c0, c1, r0, r1, base):
    """shade the squares that cannot be walked on, hatch the river squares"""
    for r in range(r0, r1 + 1):
        for col in range(c0, c1 + 1):
            b = AM[r][col]
            x, y = cx(col - base), cy(r)
            if b in RIVER:
                c.setStrokeColor(HexColor('#ffe600'))
                c.setLineWidth(0.9)
                p = c.beginPath()
                p.rect(x, y - cell, cell, cell)
                c.saveState()
                c.clipPath(p, stroke=0, fill=0)
                for k in range(-1, 4):
                    c.line(x + k * cell / 2.5, y - cell, x + k * cell / 2.5 + cell, y)
                c.restoreState()
                c.setStrokeColor(HexColor('#b8a200'))
                c.setLineWidth(0.5)
                c.rect(x, y - cell, cell, cell, fill=0, stroke=1)
            elif b in BLOCKED and b != 0x4E:
                c.setFillColor(HexColor('#000000'))
                c.setFillAlpha(0.28)
                c.rect(x, y - cell, cell, cell, fill=1, stroke=0)
                c.setFillAlpha(1)


def draw_strip(spec, out):
    strip = spec['strip']
    base = BASES[strip]
    r0, r1 = spec['rows']
    nrows = r1 - r0 + 1
    c = canvas.Canvas(str(out), pagesize=(W, H))
    c.setTitle('%s - outdoor map (Pool of Radiance)' % spec['title'].title())
    c.setAuthor('Claude')
    c.setSubject('Pool of Radiance (DOS) outdoor map: %s' % spec['title'])
    header(c, spec['title'], spec['subtitle'], 22 if len(spec['title']) > 12 else 25)

    top = H - M - 46
    bottom = M + 70
    cell = (top - bottom) / nrows
    MAPX = M + 16
    mapw = cell * 16

    def cx(col):
        return MAPX + col * cell

    def cy(row):
        return top - (row - r0) * cell

    # the data is in overworld columns; the picture of this strip starts at `base`
    markers = [(n_, (col - base, row), k) for n_, (col, row), k in spec['markers']]
    extra = [((col - base, row), k) for (col, row), k in spec.get('extra', [])]
    routes = [([(col - base, row) for col, row in path] if path else None, colr, wd) for path, colr, wd in spec.get('routes', [])]
    labels = [(t, col - base, row, sz) for t, col, row, sz in spec.get('labels', [])]
    img = terrain_image(base, base + 15, r0, r1)
    c.drawImage(ImageReader(img), MAPX, top - nrows * cell, mapw, nrows * cell)
    draw_overlays(c, cx, cy, cell, base, base + 15, r0, r1, base)

    # grid and axes
    c.setStrokeColor(white)
    c.setLineWidth(0.15)
    c.setStrokeAlpha(0.35)
    for i in range(17):
        c.line(cx(i), top, cx(i), top - nrows * cell)
    for r in range(r0, r1 + 2):
        c.line(MAPX, cy(r), MAPX + mapw, cy(r))
    c.setStrokeAlpha(1)
    c.setFont(FONT, 5.6)
    c.setFillColor(MUTED)
    for i in range(16):
        c.drawCentredString(cx(i) + cell / 2, top + 3, str(base + i))
        c.drawCentredString(cx(i) + cell / 2, top - nrows * cell - 7, str(base + i))
    for r in range(r0, r1 + 1):
        c.drawRightString(MAPX - 3, cy(r) - cell / 2 - 2, str(r))
        c.drawString(MAPX + mapw + 3, cy(r) - cell / 2 - 2, str(r))
    c.setStrokeColor(INK)
    c.setLineWidth(0.9)
    c.rect(MAPX, top - nrows * cell, mapw, nrows * cell, fill=0, stroke=1)

    # coloured event squares
    for (col, row), kind in extra:
        c.setStrokeColor(HexColor(KIND_HEX[kind]))
        c.setLineWidth(1.3)
        c.rect(cx(col) + 0.8, cy(row) - cell + 0.8, cell - 1.6, cell - 1.6, fill=0, stroke=1)

    # routes
    for path, color, width in routes:
        if not path:
            continue
        c.setStrokeColor(white)
        c.setLineWidth(width + 1.6)
        c.setLineCap(1)
        pts = [(cx(a) + cell / 2, cy(b) - cell / 2) for a, b in path]
        p = c.beginPath()
        p.moveTo(*pts[0])
        for q in pts[1:]:
            p.lineTo(*q)
        c.drawPath(p, stroke=1, fill=0)
        c.setStrokeColor(HexColor(color))
        c.setLineWidth(width)
        c.setDash(3, 2)
        c.drawPath(p, stroke=1, fill=0)
        c.setDash()

    # terrain labels
    for text, col, row, size in labels:
        halo_text(c, cx(col) + cell / 2, cy(row) - cell / 2, text, size, HexColor('#1b1b1b'), FONTI)

    # side edges: where the strip joins its neighbours
    for side, text in spec.get('edges', []):
        c.setFillColor(GREEN)
        c.setStrokeColor(GREEN)
        c.setLineWidth(1.6)
        ymid = top - nrows * cell / 2
        if side == 'W':
            x = MAPX - 12
            c.line(x, ymid, x + 8, ymid)
            p = c.beginPath()
            p.moveTo(x - 4, ymid)
            p.lineTo(x + 3, ymid + 3.4)
            p.lineTo(x + 3, ymid - 3.4)
            p.close()
            c.drawPath(p, fill=1, stroke=0)
        else:
            x = MAPX + mapw + 14
            c.line(x - 8, ymid, x, ymid)
            p = c.beginPath()
            p.moveTo(x + 4, ymid)
            p.lineTo(x - 3, ymid + 3.4)
            p.lineTo(x - 3, ymid - 3.4)
            p.close()
            c.drawPath(p, fill=1, stroke=0)

    # numbered markers
    for num, (col, row), kind in markers:
        marker(c, num, cx(col) + cell / 2, cy(row) - cell / 2, kind)

    # legend under the map
    ly = bottom - 18
    lx = MAPX + 22
    c.setFont(FONTB, 6.6)
    c.setFillColor(INK)
    c.drawString(MAPX, ly, 'KEY')
    c.setFont(FONT, 6.6)
    items = [('river', 'river square: blocked until the river is clean'), ('dark', 'cannot walk (sea, shore, solid)'),
             ('route', 'route from the boat landing'), ('edge', 'edge of the map: leads on to the next one')]
    for kind, text in items:
        if kind == 'route' and not spec.get('routes'):
            continue
        if kind == 'river' and strip != 'north-shore':
            continue
        if kind == 'edge' and not spec.get('edges'):
            continue
        if kind == 'river':
            c.setFillColor(HexColor('#fff7a8'))
            c.setStrokeColor(HexColor('#b8a200'))
            c.rect(lx, ly - 1.2, 8, 8, fill=1, stroke=1)
        elif kind == 'dark':
            c.setFillColor(HexColor('#555555'))
            c.rect(lx, ly - 1.2, 8, 8, fill=1, stroke=0)
        elif kind == 'route':
            c.setStrokeColor(HexColor('#1f5fa8'))
            c.setLineWidth(1.6)
            c.setDash(3, 2)
            c.line(lx, ly + 2.8, lx + 8, ly + 2.8)
            c.setDash()
        else:
            c.setFillColor(GREEN)
            c.rect(lx, ly - 1.2, 8, 8, fill=1, stroke=0)
        c.setFillColor(INK)
        c.setFont(FONT, 6.6)
        c.drawString(lx + 11, ly, text)
        ly -= 10  # one entry per line: the legend stays under the map, the right column keeps the space

    # right column: glance, entries, boxes
    return finish_text(c, spec, MAPX + mapw + 30, top + 14, bottom)


def finish_text(c, spec, RX, ytop, floor, fs_list=(7.2, 7.0, 6.8, 6.6, 6.4, 6.2, 6.0, 5.8)):
    RW = W - M - RX
    last = None
    for fs in fs_list:
        base = ParagraphStyle('base', fontName=FONT, fontSize=fs, leading=fs * 1.2, textColor=INK)
        items = []
        gp = Paragraph(spec['glance'], base)
        gw, gh = gp.wrap(RW - 10, 1000)
        items.append(('glance', gp, gh))
        total = gh + 14
        ents = []
        for num, kind, title, body in spec['entries']:
            pp = Paragraph('<b>%s</b><br/>%s' % (title, body), base)
            pw, ph = pp.wrap(RW - 16, 1000)
            ents.append((num, kind, pp, ph))
            total += ph + 2.6
        boxes = []
        for txt in spec.get('boxes', []):
            p = Paragraph(txt, base)
            pw, ph = p.wrap(RW - 10, 1000)
            boxes.append((p, ph))
        total += sum(h for _, h in boxes) + 8 * len(boxes) + 8
        if ytop - total >= M + 2:
            break
        last = total
    else:
        raise Overflow('%s: right column needs %.0f, has %.0f' % (spec['name'], last, ytop - M))
    y = ytop
    c.setFillColor(BOX)
    c.setStrokeColor(BOXLINE)
    c.setLineWidth(0.6)
    c.roundRect(RX, y - gh - 7, RW, gh + 8, 3, fill=1, stroke=1)
    gp.drawOn(c, RX + 5, y - gh - 3)
    y = y - gh - 14
    for num, kind, pp, ph in ents:
        c.setFillColor(TYPECOL[kind])
        c.circle(RX + 5, y - 6.2, 5.4, fill=1, stroke=0)
        c.setFillColor(white)
        c.setFont(FONTB, 6.8)
        c.drawCentredString(RX + 5, y - 8.4, num)
        pp.drawOn(c, RX + 14, y - ph)
        y -= ph + 2.6
    y -= 4
    for p, ph in boxes:
        c.setFillColor(BOX)
        c.setStrokeColor(BOXLINE)
        c.roundRect(RX, y - ph - 6, RW, ph + 8, 3, fill=1, stroke=1)
        p.drawOn(c, RX + 5, y - ph - 2)
        y -= ph + 12
    inset(c, spec, RX, RW, y)
    c.showPage()
    c.save()
    return fs


# ---------------------------------------------------------------- the overview

def overview(out):
    c = canvas.Canvas(str(out), pagesize=(W, H))
    c.setTitle('Overworld - outdoor map (Pool of Radiance)')
    c.setAuthor('Claude')
    c.setSubject('Pool of Radiance (DOS): the whole outdoor map')
    header(c, 'OVERWORLD', ('The whole outdoor map: three maps side by side, the sea routes and every place', 'Pool of Radiance (SSI, DOS)  |  outdoor map  |  SPOILERS'))
    top = H - M - 56
    cell = 13.2
    MAPX = M + 16
    mapw, maph = cell * COLS, cell * ROWS

    def cx(col):
        return MAPX + col * cell

    def cy(row):
        return top - row * cell

    c.drawImage(ImageReader(terrain_image(0, COLS - 1, 0, ROWS - 1)), MAPX, top - maph, mapw, maph)
    draw_overlays(c, cx, cy, cell, 0, COLS - 1, 0, ROWS - 1, 0)
    # the three maps as bands over the top
    bands = [('WEST WILDERNESS', 0, 15, '#2f7d3a'), ('NORTH SHORE', 13, 28, '#1f5fa8'), ('EAST WILDERNESS', 26, 41, '#b7791f')]
    for k, (name, a, b, col) in enumerate(bands):
        yb = top + 7 + (k % 2) * 0
        c.setStrokeColor(HexColor(col))
        c.setLineWidth(2.0)
        c.line(cx(a) + 1, top + 4 + (k % 2) * 8, cx(b + 1) - 1, top + 4 + (k % 2) * 8)
        c.setFillColor(HexColor(col))
        c.setFont(FONTB, 6.2)
        c.drawCentredString((cx(a) + cx(b + 1)) / 2, top + 7 + (k % 2) * 8, name)
    c.setFont(FONT, 5.4)
    c.setFillColor(MUTED)
    for col in range(COLS):
        if col % 2 == 0:
            c.drawCentredString(cx(col) + cell / 2, top - maph - 7, str(col))
    for r in range(ROWS):
        if r % 2 == 0:
            c.drawRightString(MAPX - 3, cy(r) - cell / 2 - 2, str(r))
    c.setStrokeColor(INK)
    c.setLineWidth(0.9)
    c.rect(MAPX, top - maph, mapw, maph, fill=0, stroke=1)
    # strip boundaries, as faint vertical lines
    c.setStrokeColor(white)
    c.setLineWidth(0.5)
    c.setDash(2, 2)
    for col in (13, 26):
        c.line(cx(col), top, cx(col), top - maph)
    c.setDash()
    # places (AreaMap column, row), label, offset
    places = [  # (AreaMap column, row, label, kind, side of the dot the label goes: r, l or b)
        (BASES['west'] + 10, 9, "Diogenes' Cave", 'hint', 'r'),
        (BASES['west'] + 12, 31, 'Buccaneer Base', 'fight', 'r'),
        (BASES['west'] + 3, 32, 'Zhentil Outpost', 'fight', 'r'),
        (13 + 12, 11, 'Nomad Camp', 'place', 'r'),
        (13 + 6, 14, 'rowboat', 'place', 'l'),
        (13 + 6, 16, 'Pyramid', 'secret', 'l'),
        (13 + 12, 27, 'Old Phlan', 'place', 'r'),
        (13 + 7, 29, 'WEST landing', 'hint', 'l'),
        (26 + 11, 8, 'Ruined Castle', 'place', 'r'),
        (26 + 6, 15, 'Kobold Caves', 'fight', 'l'),
        (26 + 9, 29, 'EAST landing', 'hint', 'l'),
    ]
    for col, row, label, kind, side in places:
        x, y = cx(col) + cell / 2, cy(row) - cell / 2
        c.setFillColor(white)
        c.circle(x, y, 3.2, fill=1, stroke=0)
        c.setFillColor(TYPECOL[kind])
        c.circle(x, y, 2.4, fill=1, stroke=0)
        tw = stringWidth(label, FONTB, 5.8)
        halo_text(c, x + 6 if side == 'r' else x - 6 - tw, y - 2, label, 5.8, INK, centre=False)
    # the sea routes
    c.setStrokeColor(HexColor('#ffffff'))
    # right column: how to read
    RX = MAPX + mapw + 14
    RW = W - M - RX
    base = ParagraphStyle('b', fontName=FONT, fontSize=6.4, leading=7.7, textColor=INK)
    txt = ('<b>HOW THE MAPS FIT</b> The game shows the outdoors as three maps of 16 columns side by side. Walk off the west or east side of one and the next '
           'takes over. The strip pages (West, North Shore, East) print the same column numbers as the edges of this map.<br/><br/>'
           '<b>BOATS</b> The New Phlan harbor master sells SOKAL, WEST, BAY and EAST. WEST and BAY land on the North Shore, EAST on the East Wilderness.<br/><br/>'
           '<b>WALKING</b> Shaded squares (sea, shore) cannot be walked on. River squares (yellow) block you until the pyramid\'s pollution is ended.')
    p = Paragraph(txt, base)
    pw, ph = p.wrap(RW, 1000)
    c.setFillColor(BOX)
    c.setStrokeColor(BOXLINE)
    c.roundRect(RX - 4, top - ph - 8, RW + 6, ph + 12, 3, fill=1, stroke=1)
    p.drawOn(c, RX, top - ph - 3)
    c.showPage()
    c.save()


def inset(c, spec, RX, RW, ytop):
    """a small picture of the whole overworld with this page's map outlined, in the free space of the right column"""
    avail = ytop - M - 16
    scale = min(6.4, avail / ROWS, RW / COLS)
    if scale < 2.6:
        return
    iw, ih = scale * COLS, scale * ROWS
    x0, y0 = RX, M + 2
    c.drawImage(ImageReader(terrain_image(0, COLS - 1, 0, ROWS - 1, zoom=1)), x0, y0, iw, ih)
    c.setStrokeColor(INK)
    c.setLineWidth(0.6)
    c.rect(x0, y0, iw, ih, fill=0, stroke=1)
    base = BASES[spec['strip']]
    r0, r1 = spec['rows']
    c.setStrokeColor(HexColor('#ffe600'))
    c.setLineWidth(1.6)
    c.rect(x0 + base * scale, y0 + ih - (r1 + 1) * scale, 16 * scale, (r1 - r0 + 1) * scale, fill=0, stroke=1)
    for num, (col, row), kind in spec['markers']:
        halo = TYPECOL[kind]
        c.setFillColor(white)
        c.circle(x0 + (col + 0.5) * scale, y0 + ih - (row + 0.5) * scale, 1.9, fill=1, stroke=0)
        c.setFillColor(halo)
        c.circle(x0 + (col + 0.5) * scale, y0 + ih - (row + 0.5) * scale, 1.3, fill=1, stroke=0)
    c.setFont(FONTB, 6.2)
    c.setFillColor(INK)
    c.drawString(x0 + iw + 8, y0 + ih - 8, 'WHERE THIS IS')
    c.setFont(FONT, 6.2)
    c.setFillColor(MUTED)
    textbox_lines = ['The whole outdoor map; the yellow frame', 'is the map on this page. The game shows', 'the outdoors as three maps side by side',
                     '(West, North Shore, East).']
    for i, ln in enumerate(textbox_lines):
        c.drawString(x0 + iw + 8, y0 + ih - 18 - i * 8, ln)


# ---------------------------------------------------------------- build

PAGES = {'overworld': None, 'outdoor-west': west, 'outdoor-north-shore': north_shore, 'outdoor-east': east}


def build(names=None):
    OUT.mkdir(parents=True, exist_ok=True)
    done = []
    for name in names or list(PAGES):
        out = OUT / (name + '.pdf')
        if name == 'overworld':
            overview(out)
            print('%s: %s' % (name, out.relative_to(ROOT)))
        else:
            fs = draw_strip(PAGES[name](), out)
            print('%s: %s (body %.1f pt)' % (name, out.relative_to(ROOT), fs))
        done.append(out)
    return done


if __name__ == '__main__':
    args = sys.argv[1:]
    bad = [a for a in args if a not in PAGES]
    if bad:
        sys.exit('no such page %s (have: %s)' % (bad, ', '.join(PAGES)))
    build(args or None)
