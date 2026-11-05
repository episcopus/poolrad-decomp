"""Kuto's Well, the plaza west of the slums: GEO8 block 29, ECL8 block 29 (tile set 8). Read from the area script
(see tools/maps/README.md for how each statement was checked). The same script also runs GEO8 block 32 below the well."""
from mapkit import tag

SPEC = dict(
    name='kutos-well',
    title="KUTO'S WELL",
    subtitle=('Ruined plaza west of the slums; a bandit hideout below', 'Pool of Radiance (DOS)  |  area map  |  SPOILERS'),
    source_note=('Game files: GEO8 block 29 (surface; block 32 = the hideout below), ECL8 block 29, MON8CHA, ITEM8.',
                 'Grid: columns A-P, rows 1-16, north up.'),
    geo=('GEO8', 29),
    start=(4, 15),
    arrivals=[(11, 15)],
    exits=[(4, 15, 'E'), (11, 15, 'E'), (4, 0, 'W'), (11, 0, 'W'), (15, 4, 'S'), (15, 11, 'S')],
    hatch_events={0: ('#f3d9d3', '#d89b90'), 3: ('#f6e3c6', '#d9ae6b'), 20: ('#dce8f3', '#8fb0d1')},
    legend=['arrival', 'exit', 'door', 'hatch:random packs', 'hatch:waiting kobolds (before the well is cleared)', 'hatch:kobold scouts'],
    markers=[
        ('1', 7, 7, 'fight'), ('2', 13, 7, 'fight', dict(dy=3)), ('3', 14, 7, 'loot', dict(dy=-3)),
        ('4', 1, 6, 'hint'), ('4', 0, 2, 'hint'), ('5', 6, 6, 'place'),
    ],
    glance=('<b>ARRIVE</b> from the slums by the east doors (P5, P12; the slums\' west doors lead here). <b>OTHER EDGES</b> west doors A5 and A12 lead to ECL1 block 18 (a Phlan street area), '
            'south doors E16 and L16 to ECL2 block 15 (the Library district); the north edge is solid. '
            '<b>THE POINT</b> "Kuto\'s Well, a source of water in all seasons": win the two kobold ambushes (1) to be allowed down; below (see the box) is the hideout of '
            '<b>Norris the Gray</b>. Killing him: <b>250 gp + 200 pp</b> bonus at City Hall (inferred from the clerk\'s tables), his treasure, and a safe place to rest.'),
    entries=[
        ('1', 'fight', 'The well (H8) and its ring (G8, I8, H7, H9)',
         'Facing the well from a ring cell: "Before you lies Kuto\'s Well." Until it is cleared, facing it, stepping on an amber cell, or pressing S on the plaza edge '
         '(S on a ring cell first costs <b>9 arrows of 1d6</b>) springs the ambush: <b>6 Kobolds + 3 Kobold Leaders</b> from the buildings (or "waiting kobolds"), '
         'then a second band the same size climbs out of the well. After the second the plaza is cleared for good. Fleeing drops you at one of N13, C10, L4, B2, N8, B15, K14 and the ambush stays armed.'),
        ('1', 'hint', 'Down the well (H8)', 'Once cleared, step into H8: "Rungs are set in the sides of the well wall. Do you want to climb down?" You arrive in the hideout (GEO8 block 32) at the same cell, '
         'where you may climb back up at once.'),
        ('R', 'fight', 'Random packs (red hatch)',
         'About 1 step in 11 (3 in 11 when searching): Gnolls, Kobolds or Lizardmen (1 in 3 each), scaled to your party. Parley: "boss\'s orders, we\'ll let you go this time" if it goes well. '
         'After 10 won fights the streets stay quiet. Resting here can be interrupted by the same.'),
        ('4', 'hint', 'Kobold scouts (blue hatch)',
         'Once a visit, about 1 step in 21: "a small band of sickly kobolds picking its way through the rubble" (2 Kobolds + 4 Leaders). PARLAY and let them go for the story: '
         'their king sent them west to test "rumors of a wondrous pool" (the Pool of Radiance); fighting is possible too.'),
        ('2', 'fight', 'Nailed door (H14)',
         'A Lizardman + 4 Giant Lizards patrol before a door "nailed closed" (once). Facing south at H14: "Will you force it open?" YES frees it; the chamber G15-I16 lies behind.'),
        ('3', 'loot', 'Woman on a rug (H15)',
         'Once: a wide-eyed woman: "an evil spirit from an unholy pool guides your enemies, it hides behind a fair countenance, be not deceived" and she is gone. '
         + tag('loot', 'Press S: under the rug, Bracers, Quarter Staff +1, Banded Mail +1') + ' (say YES, once).'),
        ('5', 'place', 'Plaza (ring of cells round the well)', 'About 1 step in 10: "You wander in the plaza near Kuto\'s Well." Flavour only.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Kobold', '0', '7', '3', 'Lizardman', '3', '4', '11'], ['Kobold Leader', '0', '7', '4', 'Giant Lizard', '4', '5', '16'],
              ['Gnoll', '2', '5', '10', 'Norris the Gray', '5', '10', '25']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON8CHA).'),
    boxes=[
        '<b>BELOW (GEO8 block 32, same script)</b> H8 well bottom (leave by the open secret door, H9 is south). H9 "hidden catacombs": 4 arrows of 1d6 once a visit; E14, E15 and B11-D11: a ghostly archer, 1 arrow each. '
        '<b>F8, F9</b> need S: each member finds the secret door 1 in 6 (elf or half-elf 2 in 6), until then north-south is barred (every visit). '
        '<b>Norris the Gray</b> waits at K4, B6 or F6 (once): SURRENDER strips every member of all money and items and puts you out above ground (the fight and treasure are gone for good); '
        'FIGHT is Norris + 5 Lizardmen + 9 Kobold Leaders. Win: journal entry 50, a rest-safe hideout and, at <b>N2</b>, '
        + tag('loot', '2300 sp, 92 gp, 20 gems') + '. Camping below while he lives can bring him to you. The script text says the hideout is yours to rest in.',
        '<b>ORDER</b> clear the ambush (1), loot the rug (3, needs the nailed door), go down, find the F8/F9 secret door if it bars you, fight Norris at full strength, take N2, report to City Hall.',
    ],
)
