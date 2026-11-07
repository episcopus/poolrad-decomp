#!/usr/bin/env python3
"""world: one-page "world map" of Pool of Radiance, US Letter landscape: how the 29 area maps connect.

  uv run --with reportlab python tools/maps/world.py [out.pdf]     # default docs/maps/world-map.pdf
  uv run --with reportlab python tools/maps/build.py world         # the same, through build.py (make maps does it too)

The links come from the area scripts, not from the pictures: every area script leaves through `NEWECL`
(opcode 32; `python3 tools/maps/ecldis.py ECL<n> <block>` prints them). The operand is the next script block and
`[6E12]` the tile set it is loaded from; the script first stores the arrival cell (`[C04B]` column, `[C04C]` row,
`[C04D]` facing) or, for a wilderness, the world square (`[49C3]` column, `[49C4]` row). Edge exits pick the target
from the direction faced (`ONGOTO [C04D]` or a `GETTABLE` on it). The tables that were read:

  ECL1/18  Podal Plaza:    N gate -> ECL2/9, E -> ECL8/29, S -> ECL4/2, W -> ECL7/26 at (11,28)
  ECL2/9   Stojanow Gate:  north edge -> ECL5/6 (castle yard), south edge -> ECL1/18
  ECL2/15  Library:        facing N -> ECL8/29, facing W -> ECL4/2
  ECL2/20  Slums:          east -> ECL3/0 (Phlan), west -> ECL8/29
  ECL4/2   Textile House:  N -> ECL1/18, E -> ECL2/15, W -> ECL7/26 at (11,28)
  ECL8/29  Kuto's Well:    E -> ECL2/20, S -> ECL2/15, W -> ECL1/18 (table AFC7/AFCA)
  ECL5/6   castle yard:    facing S -> ECL2/9, any other edge -> ECL5/3
  ECL5/3   NW and SE:      N or E -> ECL5/4, S or W -> ECL5/6 (table 9AA6); ECL5/4 returns to ECL5/3
  ECL1/24  Bane and Orc:   Orc map north -> ECL3/14, Orc map east -> ECL7/26; the two maps swap inside the script
  ECL3/14  Kovel Mansion:  north and east edges -> ECL7/26 at (13,26) / (13,27), south edge -> ECL1/24
  ECL3/0   New Phlan:      west gate -> ECL2/20, boats -> ECL4/21, ECL7/26 at (7,29) and (13,27), ECL8/27 at (9,29)
  ECL7/26  North Shore:    world squares (12,11) (12..13,26) (13,27) (11,28) (6,14) (6,16) (7,29); x=2 -> ECL6/25, x=15 -> ECL8/27
  ECL6/25  West:           squares (10,9) (12,31) (3,32) (table ADD6/ADF5/ADDE/ADFD); east edge -> ECL7/26
  ECL8/27  East:           squares (11,8) (6,15) (9,29) (table ABA6/ABB4/ABAB/ABB9); west edge -> ECL7/26

The page is a schematic: only the drawn lines are connections, positions are not to scale. Thumbnails are the real
16x16 plans (the cells the party can reach, walls and doors) from the same GEO blocks as the area pages.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import geoq  # noqa: E402,F401  (mapkit imports it too)
import mapkit  # noqa: E402
from mapkit import (AMBER, BLUE, BOX, BOXLINE, FONT, FONTB, FONTI, GRASS, GREEN, GREY, INK, MUTED, PARCH,  # noqa: E402
                    PURPLE, RED, WALL, reachable)

from reportlab.lib.colors import HexColor, white  # noqa: E402
from reportlab.lib.pagesizes import landscape, letter  # noqa: E402
from reportlab.pdfbase.pdfmetrics import stringWidth  # noqa: E402
from reportlab.pdfgen import canvas  # noqa: E402

OUT = HERE.parents[1] / 'docs' / 'maps' / 'world-map.pdf'

W, H = landscape(letter)
M = 22
NODE_W, NODE_H, THUMB = 72, 52, 32
NODEFILL = HexColor('#fbf7ea')
PANEL = HexColor('#f1e9d3')
STRIP = HexColor('#e6edd8')
STRIPLINE = HexColor('#9fb27e')
WATER = HexColor('#dde8ef')
GREENDK = HexColor('#2f7d3a')

# link kinds: colour, dash, line width
KINDS = {
    'walk': (INK, None, 1.1),
    'world': (GREEN, None, 1.2),
    'boat': (BLUE, (3, 2), 1.4),
    'vert': (PURPLE, (2, 1.5), 1.2),
    'random': (AMBER, (1.5, 2), 1.2),
}


# ---------------------------------------------------------------- nodes

class Node:
    def __init__(self, key, name, src, spec=None, cx=0, top=0, style='area', note=None):
        self.key, self.name, self.src, self.spec = key, name, src, spec
        self.cx, self.top, self.style, self.note = cx, top, style, note

    @property
    def left(self):
        return self.cx - NODE_W / 2

    @property
    def right(self):
        return self.cx + NODE_W / 2

    @property
    def bottom(self):
        return self.top - NODE_H

    @property
    def mid(self):  # height of the thumbnail's middle, where side links attach
        return self.top - 3 - THUMB / 2

    def L(self):
        return (self.left, self.mid)

    def R(self):
        return (self.right, self.mid)

    def T(self):
        return (self.cx, self.top)

    def B(self):
        return (self.cx, self.bottom)


# top zone: Old Phlan and New Phlan, five columns, five rows (north up, as the districts join)
TX = [222 + 86 * i for i in range(5)]


def trow(r):
    return 540 - 58 * r


# hub zone: the North Shore world map and what hangs off it, six columns
HX = [218 + 72 * i for i in range(6)]
HROW1, HROW2 = 194, 136

# side strips: the west and east wilderness, one column of nodes
WCX, ECX = 110, 702

NODES = {}


def add(key, name, src, spec, cx, top, **kw):
    NODES[key] = Node(key, name, src, spec, cx, top, **kw)


# --- Old Phlan: the castle, the gate, the plaza, the districts around it
add('nw', 'Castle NW', 'ECL5/3', 'castle-nw', TX[0], trow(0))
add('ne', 'Castle NE', 'ECL5/4', 'castle-ne', TX[1], trow(0))
add('yard', 'Valjevo Castle Yard', 'ECL5/6', 'valjevo-castle-yard', TX[0], trow(1))
add('se', 'Castle SE (maze)', 'ECL5/3, 5/5', 'castle-se', TX[1], trow(1))
add('tower', "Tyranthraxus' Tower", 'ECL5/7', 'tyranthraxus-tower', TX[2], trow(1))
add('gate', 'Stojanow Gate', 'ECL2/9', 'stojanow-gate', TX[0], trow(2))
add('cat', 'Hidden Catacombs', 'ECL8/29', 'hidden-catacombs', TX[2], trow(2))
add('plaza', 'Podal Plaza', 'ECL1/18', 'podal-plaza', TX[0], trow(3))
add('kuto', "Kuto's Well", 'ECL8/29', 'kutos-well', TX[1], trow(3))
add('slums', 'The Slums', 'ECL2/20', 'slums', TX[2], trow(3))
add('phlan', 'New Phlan', 'ECL3/0', 'phlan', TX[3], trow(3))
add('sokal', 'Sokal Keep', 'ECL4/21', 'sokal-keep', TX[4], trow(3))
add('textile', 'Cadorna Textile House', 'ECL4/2', 'cadorna-textile-house', TX[0], trow(4))
add('library', 'Library', 'ECL2/15', 'library', TX[1], trow(4))

# --- the North Shore hub and its children
add('nomad', 'Nomad Camp', 'ECL7/17', 'nomad-camp', HX[0], HROW1)
add('pyr1', 'Pyramid: maze', 'ECL7/22', 'pyramid-1', HX[1], HROW1)
add('grave', 'Valhingen Graveyard', 'ECL4/10', 'valhingen-graveyard', HX[2], HROW1)
add('bane', 'Temple of Bane', 'ECL1/24', 'temple-of-bane', HX[3], HROW1)
add('orc', 'Orc Mansion', 'ECL1/24', 'orc-mansion', HX[4], HROW1)
add('kovel', 'Kovel Mansion', 'ECL3/14', 'kovel-mansion', HX[5], HROW1)
add('pyr2', "Yarash's Lab", 'ECL7/23', 'pyramid-2', HX[1], HROW2)
add('grove', "Lizard men's grove", 'GEO7/26', 'north-shore', HX[0], HROW2, style='random')

# --- the west wilderness (tile set 6)
WY = [472, 372, 272, 172]
add('dio', "Diogenes' Cave", 'ECL6/19', None, WCX, WY[0], style='script')
add('bucc', 'Buccaneer Base', 'ECL6/1', 'buccaneer-base', WCX, WY[1])
add('zhent', 'Zhentil Outpost', 'ECL6/28', 'zhentil-outpost', WCX, WY[2])
add('wcave', 'Small dark cave', 'GEO6/25', 'wilderness-cave', WCX, WY[3], style='random')

# --- the east wilderness (tile set 8)
EY = [472, 380, 272, 172]
add('ruin', 'Ruined Castle', 'ECL8/16', 'ruined-castle', ECX, EY[0])
add('lizard', 'Lizard Man Tunnels', 'ECL8/16 (GEO8/30)', 'lizardman-tunnels', ECX, EY[1])
add('kobold', 'Kobold Caves', 'ECL8/13', 'kobold-caves', ECX, EY[2])
add('ecave', 'Small dark cave', 'GEO8/27', 'east-wilderness', ECX, EY[3], style='random')

# --- the two interiors that are only menus, drawn as chips above New Phlan
CHIPS = {
    'hall': ('CITY HALL', 'ECL3/8', 0),
    'train': ('TRAINING HALL', 'ECL3/11', 1),
}
CHIP_TOP = [trow(2) - 2, trow(2) - 23]  # City Hall above Training Hall, both above New Phlan


# ---------------------------------------------------------------- drawing helpers

def arrowhead(c, x, y, dx, dy, color, size=3.4):
    """filled triangle at (x, y) pointing along (dx, dy)"""
    n = (dx * dx + dy * dy) ** 0.5 or 1
    dx, dy = dx / n, dy / n
    px, py = -dy, dx
    p = c.beginPath()
    p.moveTo(x, y)
    p.lineTo(x - dx * size * 1.5 + px * size * 0.7, y - dy * size * 1.5 + py * size * 0.7)
    p.lineTo(x - dx * size * 1.5 - px * size * 0.7, y - dy * size * 1.5 - py * size * 0.7)
    p.close()
    c.setFillColor(color)
    c.setStrokeColor(color)
    c.setDash()
    c.drawPath(p, stroke=0, fill=1)


def link(c, kind, pts, ends='both'):
    """polyline in the style of `kind`; arrowheads at the ends ('both', 'end', 'start' or 'none')"""
    color, dash, w = KINDS[kind]
    c.setStrokeColor(color)
    c.setLineWidth(w)
    c.setDash(*dash) if dash else c.setDash()
    p = c.beginPath()
    p.moveTo(*pts[0])
    for q in pts[1:]:
        p.lineTo(*q)
    c.drawPath(p, stroke=1, fill=0)
    c.setDash()
    short = min(((pts[i + 1][0] - pts[i][0]) ** 2 + (pts[i + 1][1] - pts[i][1]) ** 2) ** 0.5 for i in range(len(pts) - 1))
    size = max(1.8, min(3.4, short / 4.0))  # the vertical links between rows are only 6 pt long
    if ends in ('both', 'end'):
        arrowhead(c, pts[-1][0], pts[-1][1], pts[-1][0] - pts[-2][0], pts[-1][1] - pts[-2][1], color, size)
    if ends in ('both', 'start'):
        arrowhead(c, pts[0][0], pts[0][1], pts[0][0] - pts[1][0], pts[0][1] - pts[1][1], color, size)


def pill(c, x, y, text, color=MUTED, size=5.4, font=None, back=PANEL, rot=0):
    """small centred label with a background so it stays readable over a line"""
    font = font or FONT
    tw = stringWidth(text, font, size)
    c.saveState()
    c.translate(x, y)
    if rot:
        c.rotate(rot)
    c.setFillColor(back)
    c.rect(-tw / 2 - 1.5, -size * 0.35 - 1, tw + 3, size + 1.2, fill=1, stroke=0)
    c.setFillColor(color)
    c.setFont(font, size)
    c.drawCentredString(0, -size * 0.3, text)
    c.restoreState()


def wrap(text, font, size, width):
    words, lines, cur = text.split(), [], ''
    for w_ in words:
        t = (cur + ' ' + w_).strip()
        if stringWidth(t, font, size) <= width:
            cur = t
        else:
            lines.append(cur)
            cur = w_
    if cur:
        lines.append(cur)
    return lines


def textbox(c, x, top, width, text, size=6.0, color=INK, lead=None, font=None):
    """left-aligned wrapped text from `top` downwards; returns the y below the last line"""
    font = font or FONT
    lead = lead or size * 1.22
    y = top
    for para in text.split('\n'):
        for ln in wrap(para, font, size, width):
            y -= lead
            c.setFont(font, size)
            c.setFillColor(color)
            c.drawString(x, y, ln)
    return y


def thumbnail(c, spec, x, y, size):
    """the area's 16x16 plan at (x, y) bottom left: reachable cells, solid walls dark, doors light"""
    cells = geoq.load(*spec['geo'])
    wrap_ = spec.get('wrap', False)
    start = tuple(spec['start'])
    reach = reachable(cells, start, wrap_)
    for extra in list(spec.get('arrivals', ())) + list(spec.get('extra_starts', ())):
        reach |= reachable(cells, tuple(extra), wrap_)
    for rect in spec.get('grey_rects', ()):
        r0, c0, r1, c1 = rect
        reach = {q for q in reach if not (r0 <= q[0] <= r1 and c0 <= q[1] <= c1)}
    s = size / 16.0
    c.setFillColor(HexColor('#e4e0d6'))
    c.rect(x, y, size, size, fill=1, stroke=0)
    for (r, col), cell in cells.items():
        if (r, col) not in reach:
            continue
        c.setFillColor(PARCH if cell['interior'] else GRASS)
        c.rect(x + col * s, y + size - (r + 1) * s, s + 0.15, s + 0.15, fill=1, stroke=0)
    for (r, col), cell in cells.items():
        if (r, col) not in reach:
            continue
        x0, y0 = x + col * s, y + size - r * s  # top left of the cell
        for d, (ax, ay, bx, by) in (('N', (0, 0, s, 0)), ('S', (0, -s, s, -s)), ('W', (0, 0, 0, -s)), ('E', (s, 0, s, -s))):
            if cell[d] == 0:
                continue
            door = cell['d' + d] != 0
            c.setStrokeColor(HexColor('#a8683a') if door else WALL)
            c.setLineWidth(0.3 if door else 0.55)
            c.line(x0 + ax, y0 + ay, x0 + bx, y0 + by)
    c.setStrokeColor(HexColor('#b9aa86'))
    c.setLineWidth(0.4)
    c.rect(x, y, size, size, fill=0, stroke=1)


def draw_node(c, n, specs):
    x, y = n.left, n.bottom
    dashed = n.style in ('random', 'script')
    c.setFillColor(NODEFILL)
    c.setStrokeColor(AMBER if n.style == 'random' else (MUTED if n.style == 'script' else BOXLINE))
    c.setLineWidth(0.9 if dashed else 0.7)
    c.setDash(2, 1.5) if dashed else c.setDash()
    c.roundRect(x, y, NODE_W, NODE_H, 3, fill=1, stroke=1)
    c.setDash()
    tx, ty = n.cx - THUMB / 2, n.top - 3 - THUMB
    if n.spec:
        thumbnail(c, specs[n.spec], tx, ty, THUMB)
    else:  # no plan: the area is a menu scene
        c.setFillColor(HexColor('#e9e4d8'))
        c.setStrokeColor(MUTED)
        c.setDash(1.5, 1.5)
        c.rect(tx, ty, THUMB, THUMB, fill=1, stroke=1)
        c.setDash()
        c.setFillColor(MUTED)
        c.setFont(FONTI, 5.2)
        c.drawCentredString(n.cx, ty + THUMB / 2 + 1, 'menu scene')
        c.drawCentredString(n.cx, ty + THUMB / 2 - 6, 'no map')
    # label
    size = 6.3
    while stringWidth(n.name, FONTB, size) > NODE_W - 4 and size > 4.8:
        size -= 0.2
    c.setFillColor(INK)
    c.setFont(FONTB, size)
    c.drawCentredString(n.cx, y + 10.5, n.name)
    c.setFillColor(MUTED)
    c.setFont(FONT, 5.0)
    c.drawCentredString(n.cx, y + 3.8, n.src + (', random find' if n.style == 'random' else ''))
    if n.spec:  # the page of this area, when the PDFs sit next to this one
        c.linkURL(n.spec + '.pdf', (x, y, x + NODE_W, y + NODE_H), relative=1)


def draw_chip(c, label, src, cx, top):
    w, h = 66, 17
    c.setFillColor(NODEFILL)
    c.setStrokeColor(MUTED)
    c.setLineWidth(0.8)
    c.setDash(2, 1.5)
    c.roundRect(cx - w / 2, top - h, w, h, 3, fill=1, stroke=1)
    c.setDash()
    c.setFillColor(INK)
    c.setFont(FONTB, 5.6)
    c.drawCentredString(cx, top - 7, label)
    c.setFillColor(MUTED)
    c.setFont(FONT, 4.8)
    c.drawCentredString(cx, top - 13.5, src + ', menu scene')


def panel(c, x, y, w, h, fill, line, r=5, dash=None):
    c.setFillColor(fill)
    c.setStrokeColor(line)
    c.setLineWidth(0.8)
    c.setDash(*dash) if dash else c.setDash()
    c.roundRect(x, y, w, h, r, fill=1, stroke=1)
    c.setDash()


def header_bar(c, x, y, w, h, title, sub):
    """green bar of a wilderness world map; (x, y) bottom left"""
    c.setFillColor(GREENDK)
    c.setStrokeColor(GREENDK)
    c.roundRect(x, y, w, h, 3, fill=1, stroke=1)
    c.setFillColor(white)
    c.setFont(FONTB, 8)
    c.drawString(x + 6, y + h - 8.5, title)
    c.setFont(FONT, 5.6)
    c.drawString(x + 6, y + 4.2, sub)


# ---------------------------------------------------------------- the page

def render(specs, out):
    c = canvas.Canvas(str(out), pagesize=(W, H))
    c.setTitle('World map - how the area maps connect (Pool of Radiance)')
    c.setAuthor('Claude')
    c.setSubject('Pool of Radiance (DOS): how the 29 area maps connect')
    n = NODES

    # header
    c.setFillColor(INK)
    c.setFont(FONTB, 25)
    c.drawString(M, H - M - 20, 'WORLD MAP')
    tw = stringWidth('WORLD MAP', FONTB, 25)
    c.setFont(FONT, 9)
    c.setFillColor(MUTED)
    c.drawString(M + tw + 14, H - M - 8, 'How the 29 area maps connect: New Phlan, the old city, the three wilderness strips')
    c.drawString(M + tw + 14, H - M - 20, 'Pool of Radiance (SSI, DOS)  |  world map  |  SPOILERS')
    c.setFont(FONTI, 6.6)
    c.drawRightString(W - M, H - M - 8, 'Links read from the area scripts (NEWECL exits and exit tables, ECL1 to ECL8).')
    c.drawRightString(W - M, H - M - 17, 'Schematic, not to scale. (col,row) are world-map squares counted from 0, top left.')
    c.setStrokeColor(INK)
    c.setLineWidth(1.2)
    c.line(M, H - M - 28, W - M, H - M - 28)

    BODY_TOP = H - M - 34  # 556
    MX0, MX1 = 174, 618  # middle column
    WX0, WX1 = M, 160
    EX0, EX1 = 632, W - M

    # ---- panels
    panel(c, MX0, 250, MX1 - MX0, BODY_TOP - 250, PANEL, BOXLINE)  # old + new Phlan
    c.setFillColor(INK)
    c.setFont(FONTB, 7)
    c.drawString(MX0 + 6, BODY_TOP - 9, 'OLD PHLAN AND NEW PHLAN')
    c.setFont(FONT, 5.8)
    c.setFillColor(MUTED)
    c.drawString(MX0 + 6 + stringWidth('OLD PHLAN AND NEW PHLAN', FONTB, 7) + 6, BODY_TOP - 9,
                 '16x16 district maps joined edge to edge: walk off a gate and you arrive at the matching gate of the next map')
    panel(c, MX0, 76, MX1 - MX0, 242 - 76, STRIP, STRIPLINE)  # north shore world map
    panel(c, WX0, 66, WX1 - WX0, BODY_TOP - 66, STRIP, STRIPLINE)
    panel(c, EX0, 66, EX1 - EX0, BODY_TOP - 66, STRIP, STRIPLINE)

    # strips' headers
    HB_Y, HB_H = 216, 20  # north shore bar
    header_bar(c, MX0 + 6, HB_Y, MX1 - MX0 - 12, HB_H, 'NORTH SHORE WORLD MAP (ECL7/26)',
               'the overworld around the old city and the sea routes; each square below asks ENTER, CITY, BOAT and so on')
    header_bar(c, WX0 + 5, BODY_TOP - 31, WX1 - WX0 - 10, 26, 'WEST WILDERNESS', 'world map ECL6/25 (tile set 6): mountains')
    header_bar(c, EX0 + 5, BODY_TOP - 31, EX1 - EX0 - 10, 26, 'EAST WILDERNESS', 'world map ECL8/27 (tile set 8)')
    c.setFillColor(INK)
    y = textbox(c, WX0 + 7, BODY_TOP - 36, WX1 - WX0 - 14,
                'Reached by walking off the west side of the North Shore map (x = 2); you land at column 14. The east edge leads back to column 3.',
                size=5.8, color=MUTED)
    y = textbox(c, EX0 + 7, BODY_TOP - 36, EX1 - EX0 - 14,
                'Reached by the east boat from New Phlan (square (9,29)) or off the east side of the North Shore map (x = 15), landing at column 3. Its west edge (column 2) leads back.',
                size=5.8, color=MUTED)

    # ---- nodes
    for k, node in n.items():
        draw_node(c, node, specs)
    for k, (label, src, i) in CHIPS.items():
        draw_chip(c, label, src, TX[3], CHIP_TOP[i])

    # ---- links inside the old city (walk off an edge)
    walk = [('nw', 'R', 'ne', 'L'), ('nw', 'B', 'yard', 'T'), ('ne', 'B', 'se', 'T'), ('yard', 'R', 'se', 'L'),
            ('yard', 'B', 'gate', 'T'), ('gate', 'B', 'plaza', 'T'), ('plaza', 'R', 'kuto', 'L'),
            ('kuto', 'R', 'slums', 'L'), ('slums', 'R', 'phlan', 'L'), ('plaza', 'B', 'textile', 'T'),
            ('textile', 'R', 'library', 'L'), ('kuto', 'B', 'library', 'T')]
    for a, sa, b, sb in walk:
        link(c, 'walk', [getattr(n[a], sa)(), getattr(n[b], sb)()])
    # vertical transitions: the well and the castle stairs
    kx, ky = n['kuto'].T()
    cat = n['cat']
    link(c, 'vert', [(kx, ky), (kx, cat.mid), (cat.left, cat.mid)])
    link(c, 'vert', [n['se'].R(), n['tower'].L()])
    pill(c, (n['se'].right + n['tower'].left) / 2, n['se'].mid + 5, 'stairs', PURPLE)
    pill(c, (kx + cat.left) / 2 + 2, cat.mid + 6, 'down the well', PURPLE)
    # Phlan satellites
    ph = n['phlan']
    link(c, 'walk', [(ph.cx, CHIP_TOP[1] - 17), (ph.cx, ph.top)], ends='none')
    link(c, 'walk', [(ph.cx, CHIP_TOP[0] - 17), (ph.cx, CHIP_TOP[1])], ends='none')
    # boat to Sokal Keep
    link(c, 'boat', [ph.R(), n['sokal'].L()])
    pill(c, (ph.right + n['sokal'].left) / 2, ph.mid + 5, 'boat', BLUE)
    # old city west gates up to the north shore bar
    gx = MX0 + 5
    bar_y = HB_Y + HB_H
    link(c, 'world', [n['plaza'].L(), (gx, n['plaza'].mid), (gx, HB_Y + 14), (MX0 + 11, HB_Y + 14)], ends='end')
    link(c, 'world', [n['textile'].L(), (gx, n['textile'].mid)], ends='none')
    pill(c, gx, (n['plaza'].mid + n['textile'].mid) / 2, 'west gate (11,28)', GREENDK, size=4.8, rot=90)
    # boats: New Phlan down to the north shore bar, and east
    bx = ph.cx
    ymid = trow(3) - NODE_H - 4
    link(c, 'boat', [(bx, ph.bottom), (bx, bar_y)], ends='both')
    pill(c, bx + 4, trow(4) - 22, 'west and bay boats', BLUE, size=5.0, rot=90)
    link(c, 'boat', [(bx, ymid), (EX0, ymid)], ends='end')
    pill(c, (bx + EX0) / 2 + 20, ymid, 'east boat', BLUE, size=5.0)

    # ---- the hub bar and its children
    hub_y = HB_Y
    hub_links = [('nomad', '(12,11) ENTER'), ('pyr1', 'rowboat (6,14), ENTER (6,16)'), ('grave', '(12-13,26) GRAVEYARD'),
                 ('kovel', '(12..13,26) CITY, (13,27) NORTH'), ('orc', 'via its east gaps'), ('bane', '(13,27) SOUTH')]
    for k, label in hub_links:
        node = n[k]
        link(c, 'world', [(node.cx, hub_y), (node.cx, node.top)])
    for k, label, dy, size in (('nomad', '(12,11)', 0, 5.2), ('pyr1', '(6,14), (6,16)', 0, 5.2), ('grave', '(12-13,26)', 0, 5.2),
                               ('kovel', '(13,26) (13,27)', 0, 5.0), ('orc', 'E gaps to (13,27)', 0, 4.8), ('bane', '(13,27) SOUTH', 0, 5.0)):
        node = n[k]
        pill(c, node.cx, (hub_y + node.top) / 2, label, GREENDK, size=size, back=STRIP)
    # the three sibling links of the Bane group
    link(c, 'walk', [n['bane'].R(), n['orc'].L()])  # the Temple of Bane lies west of the Orc Mansion
    link(c, 'walk', [n['orc'].R(), n['kovel'].L()])  # the Orc Mansion lies south of Kovel Mansion
    link(c, 'vert', [n['pyr1'].B(), n['pyr2'].T()])
    pill(c, n['pyr1'].cx, (n['pyr1'].bottom + n['pyr2'].top) / 2, 'maze to lab', PURPLE, size=5.0, back=STRIP)
    # the grove: a random find, reached from the left corridor
    gcx = MX0 + 3
    link(c, 'random', [(gcx, HB_Y), (gcx, n['grove'].mid), (n['grove'].left, n['grove'].mid)], ends='end')

    nb = n['bane'].left
    textbox(c, nb, HROW2 - 2, 3 * 72 - 8, 'ONE SCRIPT, TWO MAPS', size=6.6, color=INK, font=FONTB)
    textbox(c, nb, HROW2 - 13, 3 * 72 - 8,
            "Temple of Bane and Orc Mansion are two maps of the script ECL1/24: walk east off the temple to reach the mansion, "
            "west off the mansion to come back. Kovel Mansion's south gaps lead into the Orc Mansion, which lies south of it "
            "(the Adventurer's Journal; the script picks the map from [49C5], not traced).",
            size=5.5, color=MUTED)

    # ---- the west and east wilderness: a spine with a tick to each place
    def spine(cx_spine, nodes_, labels):
        """a vertical line from under the intro text with a tick to each place on the strip"""
        c.setStrokeColor(GREENDK)
        c.setLineWidth(1.0)
        c.line(cx_spine, SPINE_TOP, cx_spine, n[nodes_[-1]].mid)
        for k, lab in zip(nodes_, labels):
            node = n[k]
            kind_ = 'random' if node.style == 'random' else 'world'
            link(c, kind_, [(cx_spine, node.mid), (node.left, node.mid)], ends='end')
            pill(c, (cx_spine + node.left) / 2, node.mid + 6, lab, GREENDK if kind_ == 'world' else AMBER, size=5.0, back=STRIP)

    SPINE_TOP = 480
    spine(WX0 + 10, ['dio', 'bucc', 'zhent', 'wcave'], ['(10,9)', '(12,31)', '(3,32)', 'random'])
    spine(EX0 + 10, ['ruin', 'kobold', 'ecave'], ['(11,8)', '(6,15)', 'random'])
    link(c, 'vert', [n['ruin'].B(), n['lizard'].T()])
    pill(c, n['ruin'].cx, (n['ruin'].bottom + n['lizard'].top) / 2, 'tunnel mouths, stairs', PURPLE, size=5.0, back=STRIP)

    # notes under the west nodes
    notes_w = {
        'dio': "ENTER CAVE at (10,9). Text only: the silver dragon's quest and the bottle.",
        'bucc': 'Offered only while the City Hall quest for the heir is open and the boy is not yet saved. Leave by the north edge.',
        'zhent': "Only with the City Hall sealed message packet; it is a trap. Leave by the north gate.",
        'wcave': 'Roughly 1 step in 420 finds it; leave where you came in.',
    }
    for k, t in notes_w.items():
        textbox(c, WX0 + 18, n[k].bottom - 1, WX1 - WX0 - 24, t, size=5.4, color=MUTED)
    notes_e = {
        'ruin': 'ENTER at (11,8): "will you enter the ruined castle?"',
        'lizard': 'Reached from the ruins: search rubble and swamp for the mouths, or take the old stairs (9,8). Leave a mouth with YES.',
        'kobold': 'Two caves at (6,15): LARGE or SMALL (hidden). Leave by the same cell.',
        'ecave': 'Roughly 1 step in 420; leave by the cell you entered.',
    }
    for k, t in notes_e.items():
        textbox(c, EX0 + 18, n[k].bottom - 1, EX1 - EX0 - 24, t, size=5.4, color=MUTED)

    # strips to strips
    link(c, 'world', [(WX1, HB_Y + 6), (MX0 + 6, HB_Y + 6)])
    link(c, 'world', [(MX1 - 6, HB_Y + 6), (EX0, HB_Y + 6)])
    pill(c, (WX1 + MX0) / 2 + 3, HB_Y + 13, 'x = 2', GREENDK, size=4.8, back=PANEL)
    pill(c, (MX1 + EX0) / 2 - 3, HB_Y + 13, 'x = 15', GREENDK, size=4.8, back=PANEL)

    # ---- notes in the free cells of the old city
    nx0 = n['tower'].left
    textbox(c, nx0, trow(0) + 1, 86 * 3 - 14, 'HOW THE CITY IS JOINED', size=6.6, color=INK, font=FONTB)
    textbox(c, nx0, trow(0) - 10, 86 * 3 - 14,
            'Every district is a script area. Its exit gaps send you on by the direction you face when you walk off the edge, '
            'to the matching edge of the next map. Arrows are two-way unless a note says otherwise.\n'
            'Stojanow Gate: its north edge goes to the castle yard, its south edge to Podal Plaza. '
            'The castle is four maps: the yard (SW) joins NW, NW joins NE, NE joins SE, SE joins the yard.',
            size=5.7, color=MUTED)
    tx0 = n['tower'].right + 10
    textbox(c, tx0, trow(1) + 1, 86 * 2 - 14, "TYRANTHRAXUS' TOWER", size=6.6, color=INK, font=FONTB)
    textbox(c, tx0, trow(1) - 10, 86 * 2 - 14,
            'The stairs lead up from the castle maze. Killing Tyranthraxus plays the ending, then drops you in New Phlan (one way).',
            size=5.7, color=MUTED)
    bx0 = n['phlan'].cx + 12
    textbox(c, bx0, trow(4) + 1, MX1 - bx0 - 8, 'BOATS FROM NEW PHLAN', size=6.6, color=INK, font=FONTB)
    textbox(c, bx0, trow(4) - 10, MX1 - bx0 - 8,
            "Sokal Keep first (the only boat until the keep is cleared). Then west and bay, to North Shore (7,29) and (13,27), "
            "and east, to (9,29). Each is a round trip.",
            size=5.5, color=MUTED)

    # ---- the legend
    ly = 56
    c.setFont(FONTB, 6.4)
    c.setFillColor(INK)
    c.drawString(M, ly, 'LINKS')
    x = M + 30
    for kind, text in (('walk', 'walk off an edge to the next map'), ('world', 'ENTER prompt on a world-map square'),
                       ('boat', 'boat'), ('vert', 'stairs, well, tunnel, inner level'), ('random', 'random find')):
        color, dash, w = KINDS[kind]
        c.setStrokeColor(color)
        c.setLineWidth(w + 0.2)
        c.setDash(*dash) if dash else c.setDash()
        c.line(x, ly + 2, x + 22, ly + 2)
        c.setDash()
        c.setFont(FONT, 6.2)
        c.setFillColor(INK)
        c.drawString(x + 26, ly, text)
        x += 30 + stringWidth(text, FONT, 6.2) + 10
    ly2 = 44
    c.setFont(FONTB, 6.4)
    c.drawString(M, ly2, 'BOXES')
    thumbs_x = M + 34
    c.setFont(FONT, 6.2)
    c.setFillColor(INK)
    c.drawString(thumbs_x, ly2, 'the plan is the real 16x16 map: green outdoor, cream indoor, dark walls, brown doors. '
                                'Dashed amber: a random encounter area. Dashed grey: a menu scene with no map. Click a box to open its page.')
    c.setFont(FONTI, 6.0)
    c.setFillColor(MUTED)
    c.drawString(M, 31, "Coordinates are the game's own: (col,row) from 0, row 0 at the top. The wilderness squares are the script's "
                        "world-map squares of each strip, not the 16x16 grids.")
    c.drawString(M, 22, 'Made by tools/maps/world.py from the pinned game files (poolrad/*.DAX); not part of the decompilation proof.')
    c.showPage()
    c.save()


def build(out=OUT):
    import build as _b  # the area specs, for the thumbnails
    specs = _b.specs()
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    render(specs, out)
    return out


if __name__ == '__main__':
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else OUT
    print('world-map: %s' % build(target))
