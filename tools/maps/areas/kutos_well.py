"""Kuto's Well, the plaza west of the slums: GEO8 block 29, ECL8 block 29 (tile set 8). Read from the area script
(see tools/maps/README.md for how each statement was checked). The same script also runs GEO8 block 32 below the well."""
from mapkit import tag

SPEC = dict(
    name='kutos-well',
    title="KUTO'S WELL",
    subtitle=('Ruined plaza west of the slums; a bandit hideout below', 'Pool of Radiance (DOS)  |  area map  |  SPOILERS'),
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
    glance=('<b>ARRIVE</b> from the slums by the east doors ((15,4), (15,11); the slums\' west doors lead here). <b>OTHER EDGES</b> west doors (0,4) and (0,11) lead to Podal Plaza, '
            'south doors (4,15) and (11,15) to the Library; the north edge is solid. '
            '<b>THE POINT</b> "Kuto\'s Well, a source of water in all seasons": win the two kobold ambushes (1) to be allowed down; below, the Hidden Catacombs (see the box and its own map page), is the hideout of '
            '<b>Norris the Gray</b>. Killing him: <b>250 gp + 200 pp</b> bonus at City Hall (not confirmed in play), his treasure, and a safe place to rest.'),
    entries=[
        ('1', 'fight', 'The well (7,7) and its ring (6,7), (8,7), (7,6), (7,8)',
         'Facing the well from a ring cell: "Before you lies Kuto\'s Well." Until it is cleared, facing it, stepping on an amber cell, or pressing S on the plaza edge '
         '(S on a ring cell first costs <b>9 arrows of 1d6</b>) springs the ambush: <b>6 Kobolds + 3 Kobold Leaders</b> from the buildings (or "waiting kobolds"), '
         'then a second band the same size climbs out of the well. After the second the plaza is cleared for good. Fleeing drops you at one of (13,12), (2,9), (11,3), (1,1), (13,7), (1,14), (10,13) and the ambush stays armed.'),
        ('1', 'hint', 'Down the well (7,7)', 'Once cleared, step into (7,7): "Rungs are set in the sides of the well wall. Do you want to climb down?" You arrive in the Hidden Catacombs at the same cell, '
         'where you may climb back up at once.'),
        ('R', 'fight', 'Random packs (red hatch)',
         'About 1 step in 11 (3 in 11 when searching): Gnolls, Kobolds or Lizardmen (1 in 3 each), scaled to your party. Parley: "boss\'s orders, we\'ll let you go this time" if it goes well. '
         'After 10 won fights the streets stay quiet. Resting here can be interrupted by the same.'),
        ('4', 'hint', 'Kobold scouts (blue hatch)',
         'Once a visit, about 1 step in 21: "a small band of sickly kobolds picking its way through the rubble" (2 Kobolds + 4 Leaders). PARLAY and let them go for the story: '
         'their king sent them west to test "rumors of a wondrous pool" (the Pool of Radiance); fighting is possible too.'),
        ('2', 'fight', 'Nailed door (7,13)',
         'A Lizardman + 4 Giant Lizards patrol before a door "nailed closed" (once). Facing south at (7,13): "Will you force it open?" YES frees it; the chamber (6,14)-(8,15) lies behind.'),
        ('3', 'loot', 'Woman on a rug (7,14)',
         'Once: a wide-eyed woman: "an evil spirit from an unholy pool guides your enemies, it hides behind a fair countenance, be not deceived" and she is gone. '
         + tag('loot', 'Press S: under the rug, Bracers, Quarter Staff +1, Banded Mail +1') + ' (say YES, once).'),
        ('5', 'place', 'Plaza (ring of cells round the well)', 'About 1 step in 10: "You wander in the plaza near Kuto\'s Well." Flavour only.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Kobold', '0', '7', '3', 'Lizardman', '3', '4', '11'], ['Kobold Leader', '0', '7', '4', 'Giant Lizard', '4', '5', '16'],
              ['Gnoll', '2', '5', '10', 'Norris the Gray', '5', '10', '25']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as listed in the game.'),
    boxes=[
        '<b>BELOW (the Hidden Catacombs)</b> (7,7) well bottom (leave by the open secret door, (7,8) is south). (7,8) "hidden catacombs": 4 arrows of 1d6 once a visit; (4,13), (4,14) and (1,10)-(3,10): a ghostly archer, 1 arrow each. '
        '<b>(5,7), (5,8)</b> need S: each member finds the secret door 1 in 6 (elf or half-elf 2 in 6), until then north-south is barred (every visit). '
        '<b>Norris the Gray</b> waits at (10,3), (1,5) or (5,5) (once): SURRENDER strips every member of all money and items and puts you out above ground (the fight and treasure are gone for good); '
        'FIGHT is Norris + 5 Lizardmen + 9 Kobold Leaders. Win: journal entry 50, a rest-safe hideout and, at <b>(13,1)</b>, '
        + tag('loot', '2300 sp, 92 gp, 20 gems') + '. Camping below while he lives can bring him to you. The game text says the hideout is yours to rest in.',
        '<b>ORDER</b> clear the ambush (1), loot the rug (3, needs the nailed door), go down, find the (5,7)/(5,8) secret door if it bars you, fight Norris at full strength, take (13,1), report to City Hall.',
    ],
)
