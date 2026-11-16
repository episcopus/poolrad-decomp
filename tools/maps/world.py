#!/usr/bin/env python3
"""world: one-page player route guide of Pool of Radiance, US Letter landscape: how the 29 area maps connect and
what the game asks you to answer to get from one to the next.

  uv run --with reportlab python tools/maps/world.py [out.pdf]     # default docs/maps/world-map.pdf
  uv run --with reportlab python tools/maps/build.py world         # the same, through build.py (make maps does it too)

The page itself uses only player wording (world squares are printed in overworld columns: a North Shore square (x,y) of the
scripts below prints as (x+13,y), an East one as (x+26,y); the table here keeps the scripts' own numbers) (place names, the words of the game's menus, world-map squares). The links
come from the area scripts and are documented here for developers: every script leaves through `NEWECL` (opcode 32;
`python3 tools/maps/ecldis.py ECL<n> <block>` prints them). The operand is the next script block and `[6E12]` the tile
set it is loaded from; the script first stores the arrival cell (`[C04B]` column, `[C04C]` row, `[C04D]` facing) or,
for a wilderness, the world square (`[49C3]` column, `[49C4]` row). Edge exits pick the target from the direction faced
(`ONGOTO [C04D]` or a `GETTABLE` on it). The tables that were read:

  ECL3/0   New Phlan:      harbor master menu SOKAL/EAST/WEST/BAY/NONE (`[4AC4]` 0..3 -> ECL4/21, ECL8/27 at (9,29),
                           ECL7/26 at (7,29), ECL7/26 at (13,27)); west gate -> ECL2/20; City Hall ECL3/8, Training Hall ECL3/11
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
  ECL7/26  North Shore:    menus at (12..13,26) CITY/GRAVEYARD/LEAVE, (13,27) NORTH/SOUTH/BOAT/LEAVE,
                           (11,28) NORTH/SOUTH/LEAVE, (6,14) YES/NO, (6,16) ENTER/GO BACK, (12,11) ENTER/LEAVE,
                           (7,29) TAKE BOAT/STAY; x=2 -> ECL6/25, x=15 -> ECL8/27
  ECL6/25  West:           squares (10,9) ENTER CAVE/IGNORE CAVE, (12,31) ENTER/LEAVE, (3,32) YES/NO
  ECL8/27  East:           squares (11,8) ENTER/LEAVE, (6,15) LARGE/SMALL/EXIT, (9,29) TAKE BOAT/STAY

Kovel Mansion's south gates lead to the Orc Mansion and the Temple of Bane lies west of it: from the game's own
Adventurer's Journal (the script picks the map from `[49C5]`, whose writer is not read).

The page is a schematic: only the drawn lines are connections, positions are not to scale. Thumbnails are the real
16x16 plans (the cells the party can reach, walls and doors) from the same GEO blocks as the area pages.
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import geoq  # noqa: E402,F401  (mapkit imports it too)
import mapkit  # noqa: E402
from mapkit import (AMBER, BLUE, BOXLINE, FONT, FONTB, FONTI, GRASS, GREEN, INK, MUTED, PARCH,  # noqa: E402
                    PURPLE, RED, WALL, reachable)

from reportlab.lib.colors import HexColor, white  # noqa: E402
from reportlab.lib.pagesizes import landscape, letter  # noqa: E402
from reportlab.pdfbase.pdfmetrics import stringWidth  # noqa: E402
from reportlab.pdfgen import canvas  # noqa: E402

OUT = HERE.parents[1] / 'docs' / 'maps' / 'world-map.pdf'

W, H = landscape(letter)
M = 22
NODE_W, NODE_H = 72, 52
NODEFILL = HexColor('#fbf7ea')
PANEL = HexColor('#f1e9d3')
STRIP = HexColor('#e6edd8')
STRIPLINE = HexColor('#9fb27e')
CARDFILL = HexColor('#f7fbef')
HARBOR = HexColor('#e3edf5')
GREENDK = HexColor('#2f7d3a')
BLUEDK = HexColor('#1f5fa8')

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
    def __init__(self, key, name, caption, spec, cx, top, w=NODE_W, h=NODE_H, thumb=32, style='area'):
        self.key, self.name, self.caption, self.spec = key, name, caption, spec
        self.cx, self.top, self.w, self.h, self.thumb, self.style = cx, top, w, h, thumb, style

    @property
    def left(self):
        return self.cx - self.w / 2

    @property
    def right(self):
        return self.cx + self.w / 2

    @property
    def bottom(self):
        return self.top - self.h

    @property
    def mid(self):  # height of the thumbnail's middle, where side links attach
        return self.top - 3 - self.thumb / 2

    def L(self):
        return (self.left, self.mid)

    def R(self):
        return (self.right, self.mid)

    def T(self):
        return (self.cx, self.top)

    def B(self):
        return (self.cx, self.bottom)


BODY_TOP = H - M - 34  # 556
FOOT = 52              # bottom of the panels

# old city: five columns, five rows (north up as far as the districts join)
TX = [228 + 86 * i for i in range(5)]
TOP_BOTTOM = 252       # bottom of the old city panel


def trow(r):
    return 540 - 58 * r


# North Shore: six cards, then the places they lead to
HX = [226 + 70 * i for i in range(6)]
HW = 66                # width of a place box under a card
CARD_TOP, CARD_H = 231, 44
KID1, KID2 = 168, 108  # tops of the two rows of places
KID_H = 50

NODES = {}


def add(key, name, caption, spec, cx, top, **kw):
    NODES[key] = Node(key, name, caption, spec, cx, top, **kw)


# --- Old Phlan and New Phlan
add('nw', 'Castle North-West', 'castle quarter', 'castle-nw', TX[0], trow(0))
add('ne', 'Castle North-East', 'castle quarter', 'castle-ne', TX[1], trow(0))
add('yard', 'Castle Yard', 'castle quarter, entrance', 'valjevo-castle-yard', TX[0], trow(1))
add('se', 'Castle South-East', 'castle maze quarter', 'castle-se', TX[1], trow(1))
add('tower', "Tyranthraxus' Tower", 'up the castle stairs', 'tyranthraxus-tower', TX[2], trow(1))
add('gate', 'Stojanow Gate', 'gate to the castle', 'stojanow-gate', TX[0], trow(2))
add('cat', 'Hidden Catacombs', 'under the well', 'hidden-catacombs', TX[2], trow(2))
add('plaza', 'Podal Plaza', 'old city', 'podal-plaza', TX[0], trow(3))
add('kuto', "Kuto's Well", 'old city', 'kutos-well', TX[1], trow(3))
add('slums', 'The Slums', 'old city', 'slums', TX[2], trow(3))
add('phlan', 'New Phlan', 'start town', 'phlan', TX[3], trow(3))
add('sokal', 'Sokal Keep', 'first quest, by boat', 'sokal-keep', TX[4], trow(3))
add('textile', 'Cadorna Textile House', 'old city', 'cadorna-textile-house', TX[0], trow(4))
add('library', 'Library', 'old city', 'library', TX[1], trow(4))

# --- North Shore places (row 1 under the cards, row 2 below those)
add('grave', 'Valhingen Graveyard', 'undead quest', 'valhingen-graveyard', HX[1], KID1, w=HW, h=KID_H, thumb=28)
add('kovel', 'Kovel Mansion', 'thieves quest', 'kovel-mansion', HX[2], KID1, w=HW, h=KID_H, thumb=28)
add('bane', 'Temple of Bane', 'temple quest', 'temple-of-bane', HX[3], KID1, w=HW, h=KID_H, thumb=28)
add('pyr1', 'Pyramid', 'maze level', 'pyramid-1', HX[4], KID1, w=HW, h=KID_H, thumb=28)
add('nomad', 'Nomad Camp', 'tribal camp', 'nomad-camp', HX[5], KID1, w=HW, h=KID_H, thumb=28)
add('orc', 'Orc Mansion', 'east of the temple', 'orc-mansion', HX[3], KID2, w=HW, h=KID_H, thumb=28)
add('pyr2', "Yarash's Lab", 'deeper in the pyramid', 'pyramid-2', HX[4], KID2, w=HW, h=KID_H, thumb=28)
add('grove', "Lizard men's grove", 'random find', 'north-shore', HX[5], KID2, w=HW, h=KID_H, thumb=28, style='random')

# --- West wilderness (mountains)
WCX, ECX = 112, 690
WY = [470, 372, 272, 172]
add('dio', "Diogenes' Cave", 'text scenes only', None, WCX, WY[0], style='script')
add('bucc', 'Buccaneer Base', 'slaver fort', 'buccaneer-base', WCX, WY[1])
add('zhent', 'Zhentil Outpost', 'trap', 'zhentil-outpost', WCX, WY[2])
add('wcave', 'Small dark cave', 'random find', 'wilderness-cave', WCX, WY[3], style='random')

# --- East wilderness
EY = [470, 384, 262, 172]
add('ruin', 'Ruined Castle', 'lizard men quest', 'ruined-castle', ECX, EY[0])
add('lizard', 'Lizard Man Tunnels', 'under the ruins', 'lizardman-tunnels', ECX, EY[1])
add('kobold', 'Kobold Caves', 'kobold quest', 'kobold-caves', ECX, EY[2])
add('ecave', 'Small dark cave', 'random find', 'east-wilderness', ECX, EY[3], style='random')

# the two interiors that are only menus, drawn as chips above New Phlan
CHIPS = [('CITY HALL', 'menu screen, no map'), ('TRAINING HALL', 'menu screen, no map')]
CHIP_TOP = [trow(2) - 2, trow(2) - 23]


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
    size = max(1.8, min(3.4, short / 4.0))  # the links between rows are only a few points long
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


def answer_line(c, x, y, word, rest, size=5.0, wcolor=BLUEDK, maxw=None):
    """one line "WORD: rest" with the word the player answers in bold colour"""
    c.setFont(FONTB, size)
    c.setFillColor(wcolor)
    c.drawString(x, y, word)
    ww = stringWidth(word, FONTB, size)
    c.setFont(FONT, size)
    c.setFillColor(INK)
    c.drawString(x + ww + 2, y, rest)


def thumbnail(c, spec, x, y, size):
    """the area's 16x16 plan at (x, y) bottom left: reachable cells, solid walls dark, doors light"""
    cells = geoq.load(*spec['geo'])
    wrap_ = spec.get('wrap', False)
    reach = reachable(cells, tuple(spec['start']), wrap_)
    for extra in list(spec.get('arrivals', ())) + list(spec.get('extra_starts', ())):
        reach |= reachable(cells, tuple(extra), wrap_)
    for r0, c0, r1, c1 in spec.get('grey_rects', ()):
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
    c.roundRect(x, y, n.w, n.h, 3, fill=1, stroke=1)
    c.setDash()
    tx, ty = n.cx - n.thumb / 2, n.top - 3 - n.thumb
    if n.spec:
        thumbnail(c, specs[n.spec], tx, ty, n.thumb)
    else:  # no plan: the area is a menu scene
        c.setFillColor(HexColor('#e9e4d8'))
        c.setStrokeColor(MUTED)
        c.setDash(1.5, 1.5)
        c.rect(tx, ty, n.thumb, n.thumb, fill=1, stroke=1)
        c.setDash()
        c.setFillColor(MUTED)
        c.setFont(FONTI, 5.2)
        c.drawCentredString(n.cx, ty + n.thumb / 2 + 1, 'menu scene')
        c.drawCentredString(n.cx, ty + n.thumb / 2 - 6, 'no map')
    size = 6.3
    while stringWidth(n.name, FONTB, size) > n.w - 4 and size > 4.6:
        size -= 0.2
    c.setFillColor(INK)
    c.setFont(FONTB, size)
    c.drawCentredString(n.cx, y + 10.5, n.name)
    csize = 5.0
    while stringWidth(n.caption, FONT, csize) > n.w - 4 and csize > 4.2:
        csize -= 0.2
    c.setFillColor(MUTED)
    c.setFont(FONT, csize)
    c.drawCentredString(n.cx, y + 3.8, n.caption)
    if n.spec:  # the page of this area, when the PDFs sit next to this one
        c.linkURL(n.spec + '.pdf', (x, y, x + n.w, y + n.h), relative=1)


def draw_chip(c, label, caption, cx, top):
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
    c.drawCentredString(cx, top - 13.5, caption)


def panel(c, x, y, w, h, fill, line, r=5):
    c.setFillColor(fill)
    c.setStrokeColor(line)
    c.setLineWidth(0.8)
    c.roundRect(x, y, w, h, r, fill=1, stroke=1)


def header_bar(c, x, y, w, h, title, sub):
    c.setFillColor(GREENDK)
    c.setStrokeColor(GREENDK)
    c.roundRect(x, y, w, h, 3, fill=1, stroke=1)
    c.setFillColor(white)
    c.setFont(FONTB, 8)
    c.drawString(x + 6, y + h - 8.5, title)
    c.setFont(FONT, 5.6)
    c.drawString(x + 6, y + 4.2, sub)


def card(c, cx, top, w, h, title, coord, answers):
    """a decision card: a square of the North Shore map, the question it asks and what each answer does"""
    c.setFillColor(CARDFILL)
    c.setStrokeColor(GREENDK)
    c.setLineWidth(0.9)
    c.roundRect(cx - w / 2, top - h, w, h, 3, fill=1, stroke=1)
    c.setFillColor(GREENDK)
    c.setFont(FONTB, 5.6)
    c.drawString(cx - w / 2 + 3, top - 7.5, title)
    c.setFillColor(MUTED)
    c.setFont(FONT, 4.8)
    c.drawRightString(cx + w / 2 - 3, top - 7.5, coord)
    y = top - 15
    for word, rest in answers:
        answer_line(c, cx - w / 2 + 3, y, word, rest, size=4.8)
        y -= 6.6


# ---------------------------------------------------------------- the page

def render(specs, out):
    c = canvas.Canvas(str(out), pagesize=(W, H))
    c.setTitle('World map: how to get there (Pool of Radiance)')
    c.setAuthor('Claude')
    c.setSubject('Pool of Radiance (DOS): how the 29 area maps connect, with the answers the game asks for')
    n = NODES

    # header
    c.setFillColor(INK)
    c.setFont(FONTB, 25)
    c.drawString(M, H - M - 20, 'WORLD MAP')
    tw = stringWidth('WORLD MAP', FONTB, 25)
    c.setFont(FONT, 9)
    c.setFillColor(MUTED)
    c.drawString(M + tw + 14, H - M - 8, 'How to get there: every route out of New Phlan, with the words the game asks you to answer')
    c.drawString(M + tw + 14, H - M - 20, 'Pool of Radiance (SSI, DOS)  |  world map  |  SPOILERS')
    c.setFont(FONTI, 6.6)
    c.drawRightString(W - M, H - M - 8, 'Schematic, not to scale. Only the drawn lines are connections.')
    c.drawRightString(W - M, H - M - 17, '(col,row) are squares of the outdoor maps, counted from 0, top left.')
    c.setStrokeColor(INK)
    c.setLineWidth(1.2)
    c.line(M, H - M - 28, W - M, H - M - 28)

    MX0, MX1 = 174, 618
    WX0, WX1 = M, 160
    EX0, EX1 = 632, W - M

    # ---- panels
    panel(c, MX0, TOP_BOTTOM, MX1 - MX0, BODY_TOP - TOP_BOTTOM, PANEL, BOXLINE)
    c.setFillColor(INK)
    c.setFont(FONTB, 7)
    c.drawString(MX0 + 6, BODY_TOP - 9, 'OLD PHLAN AND NEW PHLAN')
    c.setFont(FONT, 5.8)
    c.setFillColor(MUTED)
    c.drawString(MX0 + 6 + stringWidth('OLD PHLAN AND NEW PHLAN', FONTB, 7) + 6, BODY_TOP - 9,
                 'each box is a map; walk off a gate and you arrive at the matching gate of the next one')
    HUB_TOP = TOP_BOTTOM - 8  # 244
    panel(c, MX0, FOOT, MX1 - MX0, HUB_TOP - FOOT, STRIP, STRIPLINE)
    panel(c, WX0, FOOT, WX1 - WX0, BODY_TOP - FOOT, STRIP, STRIPLINE)
    panel(c, EX0, FOOT, EX1 - EX0, BODY_TOP - FOOT, STRIP, STRIPLINE)
    c.setFillColor(GREENDK)
    c.setFont(FONTB, 7)
    c.drawString(MX0 + 14, HUB_TOP - 9, 'NORTH SHORE')
    c.setFont(FONT, 5.8)
    c.setFillColor(MUTED)
    c.drawString(MX0 + 14 + stringWidth('NORTH SHORE', FONTB, 7) + 6, HUB_TOP - 9,
                 'the outdoor map around Old Phlan')

    header_bar(c, WX0 + 5, BODY_TOP - 31, WX1 - WX0 - 10, 26, 'WEST WILDERNESS', 'outdoor map: mountains')
    header_bar(c, EX0 + 5, BODY_TOP - 31, EX1 - EX0 - 10, 26, 'EAST WILDERNESS', 'outdoor map')
    textbox(c, WX0 + 7, BODY_TOP - 36, WX1 - WX0 - 14,
            'Reached by walking west past column 15 of the North Shore map: you land at column 14. '
            'Walk east off its east edge to come back.', size=5.8, color=MUTED)
    textbox(c, EX0 + 7, BODY_TOP - 36, EX1 - EX0 - 14,
            'Reached by the EAST boat from New Phlan, or by walking east off the North Shore map '
            '(past column 28). Walk west past column 28 to come back.', size=5.8, color=MUTED)

    # ---- nodes
    for node in n.values():
        draw_node(c, node, specs)
    for (label, caption), top in zip(CHIPS, CHIP_TOP):
        draw_chip(c, label, caption, TX[3], top)

    # ---- links inside the old city (walk off a gate)
    walk = [('nw', 'R', 'ne', 'L'), ('nw', 'B', 'yard', 'T'), ('ne', 'B', 'se', 'T'), ('yard', 'R', 'se', 'L'),
            ('yard', 'B', 'gate', 'T'), ('gate', 'B', 'plaza', 'T'), ('plaza', 'R', 'kuto', 'L'),
            ('kuto', 'R', 'slums', 'L'), ('slums', 'R', 'phlan', 'L'), ('plaza', 'B', 'textile', 'T'),
            ('textile', 'R', 'library', 'L'), ('kuto', 'B', 'library', 'T')]
    for a, sa, b, sb in walk:
        link(c, 'walk', [getattr(n[a], sa)(), getattr(n[b], sb)()])
    pill(c, (n['slums'].right + n['phlan'].left) / 2, n['slums'].mid + 6, 'west gate', MUTED, size=4.6)
    kx, ky = n['kuto'].T()
    cat = n['cat']
    link(c, 'vert', [(kx, ky), (kx, cat.mid), (cat.left, cat.mid)])
    pill(c, (kx + cat.left) / 2 + 2, cat.mid + 6, 'climb down the well', PURPLE)
    link(c, 'vert', [n['se'].R(), n['tower'].L()])
    pill(c, (n['se'].right + n['tower'].left) / 2, n['se'].mid + 6, 'stairs', PURPLE)
    ph = n['phlan']
    link(c, 'walk', [(ph.cx, CHIP_TOP[1] - 17), (ph.cx, ph.top)], ends='none')
    link(c, 'walk', [(ph.cx, CHIP_TOP[0] - 17), (ph.cx, CHIP_TOP[1])], ends='none')

    # ---- boats from New Phlan: the harbor master's answers on the lines
    link(c, 'boat', [ph.R(), n['sokal'].L()])
    pill(c, (ph.right + n['sokal'].left) / 2, ph.mid + 6, 'SOKAL', BLUEDK, size=5.2, font=FONTB)
    y_bay, y_west, y_east = 300, 286, 293
    cards_top = CARD_TOP
    xs = HX  # card centres
    link(c, 'boat', [(ph.cx - 18, ph.bottom), (ph.cx - 18, y_bay), (xs[2], y_bay), (xs[2], cards_top)])
    pill(c, (ph.cx - 18 + xs[2]) / 2, y_bay, 'BAY', BLUEDK, size=5.4, font=FONTB)
    link(c, 'boat', [(ph.cx + 6, ph.bottom), (ph.cx + 6, y_west), (xs[3], y_west), (xs[3], cards_top)])
    pill(c, (ph.cx + 6 + xs[3]) / 2 + 4, y_west, 'WEST', BLUEDK, size=5.4, font=FONTB)
    link(c, 'boat', [(ph.cx + 24, ph.bottom), (ph.cx + 24, y_east), (EX0 + 8, y_east)], ends='both')
    pill(c, ph.cx + 60, y_east, 'EAST', BLUEDK, size=5.4, font=FONTB)

    # ---- harbor master box and notes in the free cells of the old city
    hx0, hx1 = n['tower'].left, MX1 - 8
    hy_top = trow(0) + 1
    panel(c, hx0, hy_top - 56, hx1 - hx0, 56, HARBOR, HexColor('#9db8cf'), r=3)
    c.setFillColor(BLUEDK)
    c.setFont(FONTB, 6.6)
    c.drawString(hx0 + 5, hy_top - 9, 'THE HARBOR MASTER')
    c.setFont(FONT, 5.4)
    c.setFillColor(INK)
    c.drawString(hx0 + 5 + stringWidth('THE HARBOR MASTER', FONTB, 6.6) + 5, hy_top - 9,
                 'at (11,1) in New Phlan: face north. 1 platinum, round trip.')
    c.setFillColor(INK)
    c.setFont(FONT, 5.4)
    c.drawString(hx0 + 5, hy_top - 17, '"What passage can I sell you?" Then walk to the end of the pier (15,1) to board.')
    rows = [('SOKAL', 'Sokal Keep. The only one offered until Sokal Keep is cleared.'),
            ('WEST', 'North Shore: landing (20,29); walk 1 north, 4 east to the west gate.'),
            ('BAY', "North Shore: Old Phlan's east gate (26,27): Kovel Mansion, Temple of Bane."),
            ('EAST', 'East Wilderness: boat landing (35,29).')]
    yy = hy_top - 26
    for word, rest in rows:
        answer_line(c, hx0 + 5, yy, word, rest, size=5.4)
        yy -= 7.4
    nx0 = n['tower'].right + 10
    textbox(c, nx0, trow(1) + 1, MX1 - nx0 - 8, 'DOWN IN THE CITY', size=6.6, color=INK, font=FONTB)
    textbox(c, nx0, trow(1) - 10, MX1 - nx0 - 8,
            "Old Phlan's districts are separate maps: each gate leads to the next. Killing Tyranthraxus in his "
            'tower ends the game and returns you to New Phlan.', size=5.5, color=MUTED)

    # ---- the cards: squares of the North Shore map
    CW = 68
    cardinfo = [
        ('WEST GATE', '(24,28)', [('NORTH', 'Podal Plaza'), ('SOUTH', 'Textile House'), ('LEAVE', 'stay outside')]),
        ('NORTH GATE', '(25-26,26)', [('CITY', 'Kovel Mansion'), ('GRAVEYARD', 'Valhingen'), ('LEAVE', 'stay outside')]),
        ('EAST GATE', '(26,27)', [('NORTH', 'Kovel Mansion'), ('SOUTH', 'Temple of Bane'), ('BOAT', 'New Phlan')]),
        ('BOAT LANDING', '(20,29)', [('TAKE BOAT', 'New Phlan'), ('STAY', 'stay ashore'), ('WALK', '1 N, 4 E: west gate')]),
        ('ROWBOAT', '(19,14)', [('YES', 'row to the pyramid'), ('then at (19,16)', ''), ('ENTER', 'the pyramid')]),
        ('NOMAD CAMP', '(25,11)', [('ENTER', 'the camp'), ('LEAVE', 'walk on')]),
    ]
    for cx, (title, coord, ans) in zip(HX, cardinfo):
        card(c, cx, CARD_TOP, CW, CARD_H, title, coord, ans)
    cb = CARD_TOP - CARD_H
    ymid = cb - 8

    # west gate: out to the two districts it leads to
    t0 = HX[0] - CW / 2
    plaza, textile = n['plaza'], n['textile']
    ytab = CARD_TOP - CARD_H / 2
    link(c, 'world', [plaza.L(), (182, plaza.mid), (182, ytab - 8), (t0, ytab - 8)], ends='both')
    link(c, 'world', [textile.L(), (187, textile.mid), (187, ytab + 8), (t0, ytab + 8)], ends='both')

    # north gate: graveyard straight down, Kovel Mansion one step right
    g, k, b_, o = n['grave'], n['kovel'], n['bane'], n['orc']
    link(c, 'world', [(HX[1] - 8, cb), (HX[1] - 8, g.top)])
    link(c, 'world', [(HX[1] + 26, cb), (HX[1] + 26, ymid), (k.cx - 18, ymid), (k.cx - 18, k.top)])
    # east gate: Kovel Mansion straight down, the Temple of Bane one step right
    link(c, 'world', [(HX[2] + 4, cb), (k.cx + 4, k.top)])
    link(c, 'world', [(HX[2] + 28, cb), (HX[2] + 28, ymid), (b_.cx - 8, ymid), (b_.cx - 8, b_.top)])
    # pyramid and nomad camp straight down
    link(c, 'world', [(HX[4], cb), (HX[4], n['pyr1'].top)])
    link(c, 'world', [(HX[5], cb), (HX[5], n['nomad'].top)])
    # the Orc Mansion: south of Kovel Mansion, east of the Temple of Bane (journal)
    link(c, 'walk', [(b_.cx, b_.bottom), (b_.cx, o.top)])
    ym2 = (k.bottom + o.top) / 2
    link(c, 'walk', [(k.cx, k.bottom), (k.cx, ym2), (o.cx - 14, ym2), (o.cx - 14, o.top)])
    link(c, 'vert', [n['pyr1'].B(), n['pyr2'].T()])

    # how to read, under the west gate card
    textbox(c, HX[0] - CW / 2 + 2, KID1 + 2, CW + 2, 'HOW TO READ', size=5.8, color=GREENDK, font=FONTB)
    textbox(c, HX[0] - CW / 2 + 2, KID1 - 8, CW - 2,
            'Each green card is a square of the North Shore map. The capital words are the answers the game '
            'offers; the place after them is where you end up.\nThe Orc Mansion is south of Kovel Mansion and '
            'the Temple of Bane is west of the Orc Mansion.\nBoats cost 1 platinum, round trip. The terrain between squares is on the outdoor map pages.',
            size=4.9, color=MUTED)

    # ---- the west and east wilderness: a spine with a tick to each place
    def spine(x_spine, nodes_, labels, side):
        c.setStrokeColor(GREENDK)
        c.setLineWidth(1.0)
        c.line(x_spine, 480, x_spine, n[nodes_[-1]].mid)
        for k_, lab in zip(nodes_, labels):
            node = n[k_]
            kind_ = 'random' if node.style == 'random' else 'world'
            end = node.left if side == 'W' else node.right
            link(c, kind_, [(x_spine, node.mid), (end, node.mid)], ends='end')
            pill(c, (x_spine + end) / 2, node.mid + 6, lab, GREENDK if kind_ == 'world' else AMBER, size=5.0, back=STRIP)

    spine(WX0 + 10, ['dio', 'bucc', 'zhent', 'wcave'], ['(10,9)', '(12,31)', '(3,32)', 'random'], 'W')
    spine(EX1 - 10, ['ruin', 'kobold', 'ecave'], ['(37,8)', '(32,15)', 'random'], 'E')
    link(c, 'vert', [n['ruin'].B(), n['lizard'].T()])

    def note(x, node, words, text, width):
        yy_ = node.bottom - 1
        c.setFont(FONTB, 5.4)
        c.setFillColor(BLUEDK)
        c.drawString(x, yy_ - 6.6, words)
        textbox(c, x, yy_ - 6.6 + 6.6 - 6.6, width, '', size=5.4)
        textbox(c, x, yy_ - 6.6, width, text, size=5.4, color=MUTED)

    def note2(x, node, words, text, width):
        """a line of answer words in bold colour, then a grey explanation under it"""
        c.setFont(FONTB, 5.4)
        c.setFillColor(BLUEDK)
        c.drawString(x, node.bottom - 7, words)
        textbox(c, x, node.bottom - 7, width, text, size=5.4, color=MUTED)

    note2(WX0 + 18, n['dio'], 'ENTER CAVE or IGNORE CAVE',
          "Text only: the silver dragon's quest and the bottle.", WX1 - WX0 - 24)
    note2(WX0 + 18, n['bucc'], 'ENTER or LEAVE',
          'Offered only while the City Hall quest for the heir is open and the boy is not yet saved.', WX1 - WX0 - 24)
    note2(WX0 + 18, n['zhent'], 'YES or NO ("diplomatic envoys?")',
          'You need the sealed message packet from City Hall; it is a trap. Walk out by the north gate.', WX1 - WX0 - 24)
    note2(WX0 + 18, n['wcave'], 'ENTER or LEAVE',
          'About 1 step in 420 finds it; leave where you came in.', WX1 - WX0 - 24)
    note2(EX0 + 8, n['ruin'], 'ENTER or LEAVE', '', EX1 - EX0 - 36)
    note2(EX0 + 8, n['lizard'], 'search rubble and swamp',
          'Search rubble and swamp in the ruins, or take the old stairs (9,8).',
          EX1 - EX0 - 36)
    note2(EX0 + 8, n['kobold'], 'LARGE, SMALL or EXIT', 'Two caves at (32,15): the small one is hidden. Leave by the same cell.',
          EX1 - EX0 - 36)
    note2(EX0 + 8, n['ecave'], 'ENTER or LEAVE', 'About 1 step in 420; leave by the cell you entered.', EX1 - EX0 - 36)

    # east boat landing card inside the east wilderness
    lc_top = y_east + 13
    c.setFillColor(CARDFILL)
    c.setStrokeColor(GREENDK)
    c.setLineWidth(0.9)
    c.roundRect(EX0 + 8, lc_top - 26, 104, 26, 3, fill=1, stroke=1)
    c.setFillColor(GREENDK)
    c.setFont(FONTB, 5.6)
    c.drawString(EX0 + 11, lc_top - 7.5, 'BOAT LANDING')
    c.setFillColor(MUTED)
    c.setFont(FONT, 4.8)
    c.drawRightString(EX0 + 109, lc_top - 7.5, '(35,29)')
    answer_line(c, EX0 + 11, lc_top - 15, 'TAKE BOAT', 'New Phlan', size=4.8)
    answer_line(c, EX0 + 11, lc_top - 21.6, 'STAY', 'stay ashore', size=4.8)

    # the strips are joined to the North Shore along their side edges
    link(c, 'world', [(WX1, HUB_TOP - 8), (MX0, HUB_TOP - 8)])
    link(c, 'world', [(MX1 - 1, HUB_TOP - 8), (EX0, HUB_TOP - 8)])
    pill(c, (WX1 + MX0) / 2, HUB_TOP - 14, 'west edge', GREENDK, size=4.6, back=PANEL)
    pill(c, (MX1 + EX0) / 2, HUB_TOP - 14, 'east edge', GREENDK, size=4.6, back=PANEL)

    # ---- the legend
    ly = 40
    c.setFont(FONTB, 6.4)
    c.setFillColor(INK)
    c.drawString(M, ly, 'LINKS')
    x = M + 30
    for kind, text in (('walk', 'walk off a gate to the next map'), ('world', 'answer the question on a map square'),
                       ('boat', 'boat (1 platinum, round trip)'), ('vert', 'stairs, well, rowing, searching'),
                       ('random', 'random find')):
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
    c.setFont(FONTB, 6.4)
    c.drawString(M, 30, 'BOXES')
    c.setFont(FONT, 6.2)
    c.drawString(M + 34, 30, 'the plan is the real 16x16 map: green outdoors, cream indoors, dark walls, brown doors. '
                             'Dashed amber: a random find. Dashed grey: a menu screen with no map. Click a box to open its page.')
    c.setFont(FONTI, 6.0)
    c.setFillColor(MUTED)
    c.drawString(M, 20, "Coordinates are the game's own: (col,row) from 0, row 0 at the top. Made by tools/maps/world.py from the "
                        "original game data.")
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
