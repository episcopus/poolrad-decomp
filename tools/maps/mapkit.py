#!/usr/bin/env python3
"""mapkit: draws a one-page annotated area map (US Letter landscape) from a spec.

The map itself (walls, doors, events) is read from the game's GEO#.DAX block by geoq.py; the
text, markers and room labels come from the spec of the area (sokal_keep.py, phlan.py, ...).
Needs reportlab (not a project dependency): `uv run --with reportlab python tools/maps/build.py`.

Spec keys (all optional unless marked):
  name*, title*, subtitle (two lines), source_note (two lines, optional: the standard player wording is used when absent), geo*=(file, block),
  start*=(row, col)   the cell the party arrives in (reachability is computed from it),
  exits               list of (row, col, side) edges drawn with a green arrow,
  hatch_events        {event id: fill hex} cells shaded for a roaming encounter,
  illusion_ids        wall ids that are walls yet passable: drawn as an illusionary wall,
  grey_rects          [(row0, col0, row1, col1)] unused map space drawn grey even when it is reachable,
  illusion_edges      [(row, col, side)] single door edges drawn as an illusionary / secret wall (either side's cell),
  extra_starts        [(row, col)] more cells the reachability shading starts from (teleport destinations),
  arrivals            [(row, col)] further arrival cells: drawn like the start and also seed the reachability shading,
  wrap                true when the party wraps around the map edge (reachability then wraps too),
  hedge_ids           wall ids drawn as green hedge walls (legend word 'hedge:<text>'),
  locked_rules        {(event, wall id)}: a door the script locks when you stand on that event cell facing it (red),
  rooms               [(text, row, col, size, color hex or None, bold)],
  markers             [(text, row, col, kind, {dx, dy, rad})], kind in fight/hint/loot/secret/place
  diamonds            [(text, row, col, kind, {dx, dy})]   search spots
  legend              extra legend words: 'door', 'illusion' (or 'illusion:<text>'), 'hatch:<text>', 'grey', 'search', 'arrival', 'exit' (or 'exit:<text>')
  glance*             html text of the box at the top of the right column
  entries*            [(chip text, kind, title, html body)]
  table               {'rows': [[...]], 'widths': [...], 'caption': text}
  boxes               [html, ...] stacked boxes under the map
"""
import collections
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import geoq  # noqa: E402

from reportlab.lib.colors import HexColor, white
from reportlab.lib.pagesizes import landscape, letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.pdfmetrics import registerFontFamily, stringWidth
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas
from reportlab.platypus import Paragraph, Table, TableStyle

_F = '/System/Library/Fonts/Supplemental/'
_FONTS = [('Arial', 'Arial.ttf'), ('Arial-Bold', 'Arial Bold.ttf'), ('Arial-Italic', 'Arial Italic.ttf'),
          ('Arial-BoldItalic', 'Arial Bold Italic.ttf')]
try:
    for _n, _f in _FONTS:
        pdfmetrics.registerFont(TTFont(_n, _F + _f))
    registerFontFamily('Arial', normal='Arial', bold='Arial-Bold', italic='Arial-Italic', boldItalic='Arial-BoldItalic')
    FONT, FONTB, FONTI = 'Arial', 'Arial-Bold', 'Arial-Italic'
except Exception:  # not on macOS: the built-in Helvetica (not embedded)
    FONT, FONTB, FONTI = 'Helvetica', 'Helvetica-Bold', 'Helvetica-Oblique'

N = 16
D = {'N': (-1, 0), 'E': (0, 1), 'S': (1, 0), 'W': (0, -1)}

INK = HexColor('#2b2118')
WALL = HexColor('#3a2c22')
PARCH = HexColor('#f6efdc')
GRASS = HexColor('#e3ecd3')
GREY = HexColor('#d9d6cf')
RED = HexColor('#b3261e')
BLUE = HexColor('#1f5fa8')
AMBER = HexColor('#b7791f')
PURPLE = HexColor('#6b3fa0')
GREEN = HexColor('#2f7d3a')
MUTED = HexColor('#6d6256')
BOX = HexColor('#efe6cf')
BOXLINE = HexColor('#b9aa86')
TYPECOL = {'fight': RED, 'hint': BLUE, 'loot': AMBER, 'secret': PURPLE, 'place': HexColor('#4a5560')}
TYPEHEX = {'fight': '#b3261e', 'hint': '#1f5fa8', 'loot': '#b7791f', 'secret': '#6b3fa0', 'place': '#4a5560'}


# the page's source line: player wording, no file or script names (a spec may still override it)
STANDARD_NOTE = ('Read from the original game data: the area map, its events and monsters.',
                 'Grid: (column,row) from 0, top left, north up.')


def lab(r, c):
    """grid label of a cell in the game's coordinates: (column,row), both from 0, row 0 at the top"""
    return '(%d,%d)' % (c, r)


def tag(kind, text):
    return '<font color="%s"><b>%s</b></font>' % (TYPEHEX[kind], text)


def reachable(cells, start, wrap=False):
    def can(r, c, d):
        x = cells[(r, c)]
        return x[d] == 0 or x['d' + d] != 0
    seen = {start}
    q = collections.deque([start])
    while q:
        r, c = q.popleft()
        for d, (dr, dc) in D.items():
            if not can(r, c, d):
                continue
            rr, cc = r + dr, c + dc
            if wrap:  # the party wraps around the map edge (spec key 'wrap')
                rr, cc = rr % N, cc % N
            if 0 <= rr < N and 0 <= cc < N and (rr, cc) not in seen:
                seen.add((rr, cc))
                q.append((rr, cc))
    return seen


class Overflow(Exception):
    pass


def render(spec, out, fs):
    """draw the page with body font size fs; raises Overflow when the right column or boxes do not fit"""
    cells = geoq.load(*spec['geo'])
    REACH = reachable(cells, tuple(spec['start']), spec.get('wrap', False))
    for _s in spec.get('arrivals', ()):  # further arrival cells, drawn like the start (spec key 'arrivals')
        REACH |= reachable(cells, tuple(_s), spec.get('wrap', False))
    for extra in spec.get('extra_starts', ()):  # more seeds (teleport destinations) for the reachability shading
        REACH |= reachable(cells, tuple(extra))
    W, H = landscape(letter)
    c = canvas.Canvas(out, pagesize=(W, H))
    c.setTitle('%s - annotated map (Pool of Radiance)' % spec['title'].title())
    c.setAuthor('Claude')
    c.setSubject('Pool of Radiance (DOS) area map: %s' % spec['title'])
    M = 22
    CELL = 24.0
    MAPW = CELL * N
    MAPX = M + 14
    MAPTOP = H - M - 46
    MAPY = MAPTOP - MAPW

    def cx(col):
        return MAPX + col * CELL

    def cy(row):
        return MAPTOP - row * CELL

    # header
    c.setFillColor(INK)
    tsize = 25 if len(spec['title']) <= 12 else (21 if len(spec['title']) <= 16 else 16)
    c.setFont(FONTB, tsize)
    c.drawString(M, H - M - 20, spec['title'])
    tw = stringWidth(spec['title'], FONTB, tsize)
    c.setFont(FONT, 9)
    c.setFillColor(MUTED)
    sub = spec.get('subtitle', ('', ''))
    c.drawString(M + tw + 14, H - M - 8, sub[0])
    c.drawString(M + tw + 14, H - M - 20, sub[1])
    c.setFont(FONTI, 6.6)
    note = spec.get('source_note', STANDARD_NOTE)
    c.drawRightString(W - M, H - M - 8, note[0])
    c.drawRightString(W - M, H - M - 17, note[1])
    left = M + tw + 14 + max(stringWidth(sub[0], FONT, 9), stringWidth(sub[1], FONT, 9))
    for ln in note:  # the right-aligned source note must not run into the subtitle
        if W - M - stringWidth(ln, FONTI, 6.6) < left + 6:
            print('  warning: %s: source note overlaps the subtitle: %s' % (spec['name'], ln[:50]))
    c.setStrokeColor(INK)
    c.setLineWidth(1.2)
    c.line(M, H - M - 28, W - M, H - M - 28)

    # cells
    hatch = spec.get('hatch_events', {})
    for (r, col), x in cells.items():
        if (r, col) not in REACH or any(a <= r <= b and cc0 <= col <= cc1 for a, cc0, b, cc1 in spec.get('grey_rects', ())):
            fill = GREY  # spec key 'grey_rects': [(row0, col0, row1, col1)] unused map space forced grey
        elif x['interior']:
            fill = PARCH
        else:
            fill = GRASS
        c.setFillColor(fill)
        c.setStrokeColor(HexColor('#cfc8b6'))
        c.setLineWidth(0.25)
        c.rect(cx(col), cy(r + 1), CELL, CELL, fill=1, stroke=1)
    for ev, tint in hatch.items():
        for (r, col), x in cells.items():
            if x['ev'] != ev or (r, col) not in REACH:
                continue
            c.setFillColor(HexColor(tint[0]))
            c.rect(cx(col), cy(r + 1), CELL, CELL, fill=1, stroke=0)
            p = c.beginPath()
            p.rect(cx(col), cy(r + 1), CELL, CELL)
            c.saveState()
            c.clipPath(p, stroke=0, fill=0)
            c.setStrokeColor(HexColor(tint[1]))
            c.setLineWidth(0.35)
            for k in range(-2, 7):
                x0 = cx(col) + k * 6
                c.line(x0, cy(r + 1), x0 + CELL, cy(r + 1) + CELL)
            c.restoreState()
            c.setStrokeColor(HexColor('#cfc8b6'))
            c.setLineWidth(0.25)
            c.rect(cx(col), cy(r + 1), CELL, CELL, fill=0, stroke=1)

    # walls and doors
    illusion_ids = set(spec.get('illusion_ids', ()))
    locked_rules = set(spec.get('locked_rules', ()))
    hedge_ids = set(spec.get('hedge_ids', ()))
    edges = []

    def side(r, col, d):
        x = cells[(r, col)]
        return x[d], x['d' + d]

    def add_edge(r, col, d, other):
        a_id, a_k = side(r, col, d)
        b_id, b_k = (0, 0)
        if other is not None:
            opp = {'N': 'S', 'S': 'N', 'E': 'W', 'W': 'E'}[d]
            b_id, b_k = side(other[0], other[1], opp)
        if a_id == 0 and b_id == 0:
            return
        door = (a_id and a_k) or (b_id and b_k)
        if door and not ((r, col) in REACH and (other is None or other in REACH)):
            door = False
        hard = bool(door) and max((k for i, k in ((a_id, a_k), (b_id, b_k)) if i), default=0) >= 2
        locked = False
        if door and locked_rules:
            if (cells[(r, col)]['ev'], a_id) in locked_rules:
                locked = True
            if other is not None and (cells[other]['ev'], b_id) in locked_rules:
                locked = True
        ill = False
        if door and other is not None and illusion_ids:
            ids = {i for i, k in ((a_id, a_k), (b_id, b_k)) if i and k}
            if ids and ids <= illusion_ids:
                ill = True
        if door and spec.get('illusion_edges'):  # [(row, col, side)]: single edges drawn as secret / illusionary walls
            _opp = {'N': 'S', 'S': 'N', 'E': 'W', 'W': 'E'}[d]
            _mine = (r, col, d)
            _theirs = (other[0], other[1], _opp) if other is not None else None
            if any(tuple(e) in (_mine, _theirs) for e in spec['illusion_edges']):
                ill = True
        if d == 'N':
            seg = (cx(col), cy(r), cx(col + 1), cy(r))
        elif d == 'S':
            seg = (cx(col), cy(r + 1), cx(col + 1), cy(r + 1))
        elif d == 'W':
            seg = (cx(col), cy(r), cx(col), cy(r + 1))
        else:
            seg = (cx(col + 1), cy(r), cx(col + 1), cy(r + 1))
        wallkind = 'wall'
        if hedge_ids and not door:  # a plain wall whose ids are all hedge ids (spec key 'hedge_ids')
            hids = {i for i in (a_id, b_id) if i}
            if hids and hids <= hedge_ids:
                wallkind = 'hedge'
        edges.append(('ill' if ill else ('lock2' if hard else ('lock' if locked else ('door' if door else wallkind))),) + seg)

    for r in range(N):
        for col in range(N):
            add_edge(r, col, 'N', (r - 1, col) if r > 0 else None)
            add_edge(r, col, 'W', (r, col - 1) if col > 0 else None)
            if r == N - 1:
                add_edge(r, col, 'S', None)
            if col == N - 1:
                add_edge(r, col, 'E', None)
    c.setLineCap(1)
    for kind, x0, y0, x1, y1 in edges:
        if kind == 'wall':
            c.setLineWidth(1.7)
            c.setStrokeColor(WALL)
            c.line(x0, y0, x1, y1)
        elif kind == 'hedge':  # spec key 'hedge_ids': a green wall
            c.setLineWidth(1.7)
            c.setStrokeColor(HexColor('#3f7f3a'))
            c.line(x0, y0, x1, y1)
    for kind, x0, y0, x1, y1 in edges:
        if kind == 'door':
            dx, dy = x1 - x0, y1 - y0
            L = (dx * dx + dy * dy) ** 0.5
            ux, uy = dx / L, dy / L
            g0, g1 = 0.2 * L, 0.8 * L
            c.setStrokeColor(WALL)
            c.setLineWidth(1.7)
            c.line(x0, y0, x0 + ux * g0, y0 + uy * g0)
            c.line(x0 + ux * g1, y0 + uy * g1, x1, y1)
            c.setStrokeColor(AMBER)
            c.setLineWidth(2.6)
            c.line(x0 + ux * (g0 + 1.5), y0 + uy * (g0 + 1.5), x0 + ux * (g1 - 1.5), y0 + uy * (g1 - 1.5))
        elif kind in ('lock', 'lock2'):
            dx, dy = x1 - x0, y1 - y0
            L = (dx * dx + dy * dy) ** 0.5
            ux, uy = dx / L, dy / L
            g0, g1 = 0.2 * L, 0.8 * L
            c.setStrokeColor(WALL)
            c.setLineWidth(1.7)
            c.line(x0, y0, x0 + ux * g0, y0 + uy * g0)
            c.line(x0 + ux * g1, y0 + uy * g1, x1, y1)
            c.setStrokeColor(RED if kind == 'lock' else HexColor('#c2410c'))
            c.setLineWidth(2.6)
            c.line(x0 + ux * (g0 + 1.5), y0 + uy * (g0 + 1.5), x0 + ux * (g1 - 1.5), y0 + uy * (g1 - 1.5))
            if kind == 'lock2':  # a cross-bar: a lock you must bash, pick or knock
                mx, my = (x0 + x1) / 2, (y0 + y1) / 2
                c.setStrokeColor(white)
                c.setLineWidth(0.9)
                c.line(mx - uy * 3, my + ux * 3, mx + uy * 3, my - ux * 3)
        elif kind == 'ill':
            c.setStrokeColor(PURPLE)
            c.setLineWidth(2.2)
            c.setDash(3, 2)
            c.line(x0, y0, x1, y1)
            c.setDash()

    # axes
    c.setFillColor(MUTED)
    c.setFont(FONT, 6.4)
    for k in range(N):
        c.drawCentredString(cx(k + 0.5), MAPTOP + 3, str(k))
        c.drawCentredString(cx(k + 0.5), MAPY - 8, str(k))
        c.drawRightString(MAPX - 3, cy(k + 0.5) - 2.2, str(k))
        c.drawString(MAPX + MAPW + 3, cy(k + 0.5) - 2.2, str(k))

    # room labels
    for item in spec.get('rooms', []):
        txt, r, col = item[0], item[1], item[2]
        size = item[3] if len(item) > 3 else 5.4
        color = HexColor(item[4]) if len(item) > 4 and item[4] else HexColor('#7a6d5c')
        bold = item[5] if len(item) > 5 else False
        c.setFillColor(color)
        c.setFont(FONTB if bold else FONT, size)
        c.drawCentredString(cx(col + 0.5), cy(r + 0.5) - size / 3, txt)

    def marker(txt, r, col, kind, dx=0.0, dy=0.0, rad=7.0):
        x, y = cx(col + 0.5) + dx, cy(r + 0.5) + dy
        c.setFillColor(TYPECOL[kind])
        c.setStrokeColor(white)
        c.setLineWidth(1.2)
        c.circle(x, y, rad, fill=1, stroke=1)
        c.setFillColor(white)
        c.setFont(FONTB, 7.6 if len(txt) < 2 else 6.4)
        c.drawCentredString(x, y - 2.6, txt)

    def diamond(txt, r, col, kind, dx=0.0, dy=0.0, s=6.0):
        x, y = cx(col + 0.5) + dx, cy(r + 0.5) + dy
        c.setFillColor(TYPECOL[kind])
        c.setStrokeColor(white)
        c.setLineWidth(1.0)
        p = c.beginPath()
        p.moveTo(x, y + s)
        p.lineTo(x + s, y)
        p.lineTo(x, y - s)
        p.lineTo(x - s, y)
        p.close()
        c.drawPath(p, fill=1, stroke=1)
        c.setFillColor(white)
        c.setFont(FONTB, 6.4)
        c.drawCentredString(x, y - 2.2, txt)

    sr, sc = spec['start']
    sx, sy = cx(sc + 0.5), cy(sr + 0.5)
    c.setFillColor(GREEN)
    c.setStrokeColor(white)
    c.setLineWidth(1.2)
    c.rect(sx - 7, sy - 7, 14, 14, fill=1, stroke=1)
    c.setFillColor(white)
    c.setFont(FONTB, 7.4)
    c.drawCentredString(sx, sy - 2.6, 'S')
    for (er_, ec_) in spec.get('arrivals', ()):
        c.setFillColor(GREEN)
        c.setStrokeColor(white)
        c.setLineWidth(1.2)
        c.rect(cx(ec_ + 0.5) - 7, cy(er_ + 0.5) - 7, 14, 14, fill=1, stroke=1)
        c.setFillColor(white)
        c.setFont(FONTB, 7.4)
        c.drawCentredString(cx(ec_ + 0.5), cy(er_ + 0.5) - 2.6, 'S')
    for (er, ec, es) in spec.get('exits', []):
        # arrow on the outside of the edge, pointing away from the map
        ex = cx(ec + 0.5) if es in 'NS' else (cx(ec) if es == 'W' else cx(ec + 1))
        ey = cy(er + 0.5) if es in 'EW' else (cy(er) if es == 'N' else cy(er + 1))
        vx, vy = {'N': (0, 1), 'S': (0, -1), 'E': (1, 0), 'W': (-1, 0)}[es]
        c.setStrokeColor(GREEN)
        c.setFillColor(GREEN)
        c.setLineWidth(1.6)
        c.line(ex - vx * 5, ey - vy * 5, ex + vx * 4, ey + vy * 4)
        p = c.beginPath()
        tipx, tipy = ex + vx * 10, ey + vy * 10
        px, py = -vy * 4, vx * 4
        p.moveTo(ex + vx * 3 + px, ey + vy * 3 + py)
        p.lineTo(ex + vx * 3 - px, ey + vy * 3 - py)
        p.lineTo(tipx, tipy)
        p.close()
        c.drawPath(p, fill=1, stroke=0)
    for m in spec.get('markers', []):
        kw = m[4] if len(m) > 4 else {}
        marker(m[0], m[1], m[2], m[3], **kw)
    for m in spec.get('diamonds', []):
        kw = m[4] if len(m) > 4 else {}
        diamond(m[0], m[1], m[2], m[3], **kw)

    # legend
    ly = MAPY - 22
    c.setFont(FONTB, 6.6)
    c.setFillColor(INK)
    c.drawString(MAPX, ly, 'KEY')

    def lgap(word, x):
        return x + 11 + stringWidth(word, FONT, 6.6) + 9

    x = MAPX + 22
    row1 = [('fight', 'combat'), ('hint', 'story / hint'), ('loot', 'treasure'), ('secret', 'secret'), ('place', 'place')]
    used_kinds = {m[3] for m in spec.get('markers', [])} | {m[3] for m in spec.get('diamonds', [])}
    for k, t in row1:
        if k not in used_kinds:
            continue
        c.setFillColor(TYPECOL[k])
        c.circle(x + 4, ly + 2.4, 4, fill=1, stroke=0)
        c.setFillColor(INK)
        c.setFont(FONT, 6.6)
        c.drawString(x + 11, ly, t)
        x = lgap(t, x)
    want = set(spec.get('legend', []))
    c.setFont(FONT, 6.6)
    if 'arrival' in want:
        c.setFillColor(GREEN)
        c.rect(x, ly - 1.2, 7, 7, fill=1, stroke=0)
        c.setFillColor(INK)
        c.drawString(x + 11, ly, 'arrival')
        x = lgap('arrival', x)
    etext = 'exit'
    for w in want:
        if w.startswith('exit:'):  # the arrow with the area's own words (for example 'passage wraps to the far edge')
            etext = w[5:]
            want = want | {'exit'}
    if 'exit' in want:
        c.setStrokeColor(GREEN)
        c.setFillColor(GREEN)
        c.setLineWidth(1.6)
        c.line(x + 4, ly + 7, x + 4, ly + 1)
        pp = c.beginPath()
        pp.moveTo(x, ly + 2)
        pp.lineTo(x + 8, ly + 2)
        pp.lineTo(x + 4, ly - 3)
        pp.close()
        c.drawPath(pp, fill=1, stroke=0)
        c.setFillColor(INK)
        c.drawString(x + 11, ly, etext)
        x = lgap(etext, x)
    if 'search' in want:
        c.setFillColor(AMBER)
        p = c.beginPath()
        p.moveTo(x + 4, ly + 7)
        p.lineTo(x + 8, ly + 2.5)
        p.lineTo(x + 4, ly - 2)
        p.lineTo(x, ly + 2.5)
        p.close()
        c.drawPath(p, fill=1, stroke=0)
        c.setFillColor(INK)
        c.drawString(x + 11, ly, 'search spot (S key)')
        x = lgap('search spot (S key)', x)
    ly2 = ly - 12
    x = MAPX + 22
    if 'door' in want:
        c.setStrokeColor(AMBER)
        c.setLineWidth(2.6)
        c.line(x, ly2 + 2.4, x + 12, ly2 + 2.4)
        c.setFillColor(INK)
        c.setFont(FONT, 6.6)
        c.drawString(x + 16, ly2, 'door')
        x += 16 + stringWidth('door', FONT, 6.6) + 10
    itext = 'illusionary wall' if 'illusion' in want else None
    for w in sorted(want):
        if w.startswith('illusion:'):  # same dashed line with the area's own words (for example 'secret door')
            itext = w[9:]
    if itext:
        c.setStrokeColor(PURPLE)
        c.setLineWidth(2.2)
        c.setDash(3, 2)
        c.line(x, ly2 + 2.4, x + 12, ly2 + 2.4)
        c.setDash()
        c.setFillColor(INK)
        c.setFont(FONT, 6.6)
        c.drawString(x + 16, ly2, itext)
        x += 16 + stringWidth(itext, FONT, 6.6) + 10
    for w in sorted(want):
        if w.startswith('lock2:'):
            text = w[6:]
            c.setStrokeColor(HexColor('#c2410c'))
            c.setLineWidth(2.6)
            c.line(x, ly2 + 2.4, x + 12, ly2 + 2.4)
            c.setStrokeColor(white)
            c.setLineWidth(0.9)
            c.line(x + 6, ly2 + 0.2, x + 6, ly2 + 4.6)
            c.setFillColor(INK)
            c.setFont(FONT, 6.6)
            c.drawString(x + 16, ly2, text)
            x += 16 + stringWidth(text, FONT, 6.6) + 10
    for w in sorted(want):
        if w.startswith('locked:'):
            text = w[7:]
            c.setStrokeColor(RED)
            c.setLineWidth(2.6)
            c.line(x, ly2 + 2.4, x + 12, ly2 + 2.4)
            c.setFillColor(INK)
            c.setFont(FONT, 6.6)
            c.drawString(x + 16, ly2, text)
            x += 16 + stringWidth(text, FONT, 6.6) + 10
    hl = [w for w in spec.get('legend', []) if w.startswith('hatch:')]
    for w in hl:
        if True:
            text = w[6:]
            tint = list(hatch.values())[hl.index(w)]
            c.setFillColor(HexColor(tint[0]))
            c.setStrokeColor(HexColor(tint[1]))
            c.setLineWidth(0.8)
            c.rect(x, ly2 - 1, 12, 8, fill=1, stroke=1)
            c.setFillColor(INK)
            c.setFont(FONT, 6.6)
            c.drawString(x + 16, ly2, text)
            x += 16 + stringWidth(text, FONT, 6.6) + 10
    for w in sorted(want):
        if w.startswith('hedge:'):  # legend sample of the hedge wall colour
            text = w[6:]
            c.setStrokeColor(HexColor('#3f7f3a'))
            c.setLineWidth(2.2)
            c.line(x, ly2 + 2.4, x + 12, ly2 + 2.4)
            c.setFillColor(INK)
            c.setFont(FONT, 6.6)
            c.drawString(x + 16, ly2, text)
            x += 16 + stringWidth(text, FONT, 6.6) + 10
    greys = [w for w in want if w == 'grey' or w.startswith('grey:')]
    if greys:
        gtext = greys[0][5:] if ':' in greys[0] else 'no way in'
        c.setFillColor(GREY)
        c.setStrokeColor(HexColor('#b8b2a4'))
        c.rect(x, ly2 - 1, 12, 8, fill=1, stroke=1)
        c.setFillColor(INK)
        c.setFont(FONT, 6.6)
        c.drawString(x + 16, ly2, gtext)

    # text
    base = ParagraphStyle('base', fontName=FONT, fontSize=fs, leading=fs * 1.19, textColor=INK)
    small = ParagraphStyle('small', parent=base, fontSize=fs, leading=fs * 1.2)
    RX = MAPX + MAPW + 28
    RW = W - M - RX
    y = MAPTOP + 14
    gp = Paragraph(spec['glance'], base)
    gw, gh = gp.wrap(RW - 10, 1000)
    c.setFillColor(BOX)
    c.setStrokeColor(BOXLINE)
    c.setLineWidth(0.6)
    c.roundRect(RX, y - gh - 7, RW, gh + 8, 3, fill=1, stroke=1)
    gp.drawOn(c, RX + 5, y - gh - 3)
    y = y - gh - 14
    for num, kind, title, body in spec['entries']:
        txt = '<b>%s</b><br/>%s' % (title, body) if title else body
        pp = Paragraph(txt, base)
        pw, ph = pp.wrap(RW - 16, 1000)
        c.setFillColor(TYPECOL[kind])
        c.circle(RX + 5, y - 6.2, 5.4, fill=1, stroke=0)
        c.setFillColor(white)
        c.setFont(FONTB, 6.2 if len(num) > 1 else 6.8)
        c.drawCentredString(RX + 5, y - 8.4, num)
        pp.drawOn(c, RX + 14, y - ph)
        y -= ph + 2.3
    floor = M
    tb = spec.get('table')
    if tb:
        cellst = ParagraphStyle('cell', parent=base, fontSize=fs - 0.4, leading=(fs - 0.4) * 1.14)
        rows = [[Paragraph(('<b>%s</b>' % t) if i == 0 else t, cellst) for t in r] for i, r in enumerate(tb['rows'])]
        widths = list(tb['widths'])
        widths[-1] = RW - sum(widths[:-1])
        t = Table(rows, colWidths=widths, rowHeights=[fs + 2.2] * len(rows))
        t.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), HexColor('#e6dcc0')),
            ('GRID', (0, 0), (-1, -1), 0.3, BOXLINE),
            ('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
            ('LEFTPADDING', (0, 0), (-1, -1), 2.5), ('RIGHTPADDING', (0, 0), (-1, -1), 2),
            ('TOPPADDING', (0, 0), (-1, -1), 0.4), ('BOTTOMPADDING', (0, 0), (-1, -1), 0.6)]))
        tw_, th_ = t.wrap(RW, 1000)
        ty = y - 2 - th_
        t.drawOn(c, RX, ty)
        c.setFillColor(MUTED)
        c.setFont(FONTI, 5.6)
        c.drawString(RX, ty - 7, tb.get('caption', ''))
        y = ty - 9
    if y < floor:
        raise Overflow('right column ends at %.1f' % y)

    # boxes under the map
    bw = MAPW + 14
    paras = []
    for txt in spec.get('boxes', []):
        p = Paragraph(txt, small)
        w_, h_ = p.wrap(bw - 10, 1000)
        paras.append((p, h_))
    tot = sum(h for _, h in paras) + 8 * len(paras)
    top_limit = MAPY - 38  # legend row 2 sits at MAPY-34
    if M + tot > top_limit:
        raise Overflow('boxes need %.1f, have %.1f' % (tot, top_limit - M))
    c.setFillColor(BOX)
    c.setStrokeColor(BOXLINE)
    c.setLineWidth(0.6)
    c.roundRect(MAPX - 14, M, bw, tot, 3, fill=1, stroke=1)
    yy = M + tot - 5
    for i, (p, h_) in enumerate(paras):
        p.drawOn(c, MAPX - 14 + 5, yy - h_)
        yy -= h_ + 4
        if i < len(paras) - 1:
            c.setStrokeColor(BOXLINE)
            c.setLineWidth(0.4)
            c.line(MAPX - 14 + 5, yy, MAPX - 14 + bw - 5, yy)
            yy -= 4
    c.showPage()
    c.save()
    return y


def build(spec, out):
    """render at the largest body font size that fits; returns the size used"""
    last = None
    for fs in (7.0, 6.8, 6.6, 6.4, 6.2, 6.0, 5.8, 5.6):
        try:
            render(spec, out, fs)
            return fs
        except Overflow as e:
            last = e
    raise RuntimeError('%s does not fit even at 5.6 pt: %s' % (spec['name'], last))
