"""The tunnels below the lizard men's ruins: GEO8 block 30, run by the script ECL8 block 16 (tile set 8).
Read from the area script (see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='lizardman-tunnels',
    title='LIZARD MAN TUNNELS',
    subtitle=('Flooded tunnels under the Ruined Castle', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    geo=('GEO8', 30),
    start=(1, 13),
    arrivals=[(4, 10), (5, 4), (7, 1), (8, 10), (10, 7), (15, 4)],
    legend=['arrival', 'door', 'grey:water (pools) and rock'],
    markers=[
        ('24', 2, 2, 'loot'), ('25', 8, 3, 'loot', dict(dy=-1)), ('26', 13, 5, 'loot'), ('27', 15, 11, 'loot'), ('28', 12, 13, 'loot'),
        ('29', 5, 8, 'loot'), ('30', 2, 10, 'loot'), ('31', 7, 6, 'loot'), ('31', 8, 5, 'loot'), ('31', 8, 7, 'loot'), ('31', 9, 6, 'loot'),
        ('32', 10, 3, 'loot'), ('33', 14, 7, 'loot'), ('34', 6, 9, 'loot'),
    ],
    glance=('<b>ARRIVE</b> by one of seven tunnel mouths (green S) from the Ruined Castle grounds map: search rubble or swamp (S key) on the cells in the table, '
            'or take the old stairs (9,8) (no search needed). <b>EXIT</b> by standing on a mouth, facing its opening wall, and answering YES to "DO YOU GO UP?". '
            'Three separate regions: the main tunnels (102 cells, four mouths: (13,1), (4,5), (7,10), (10,8)), the west pocket ((1,7) and (4,15) are connected, 13 cells) and the '
            'east pocket ((10,4) with the pool (8,5), 4 cells). <b>THE POINT:</b> 11 flooded pools; each hides a purse and some hide a magic item, but the lizard men may ambush you at the water. '
            'Numbers on the map match the entries on the right (17 to 23 are the mouths, 24 to 34 the pools).'),
    entries=[
        ('S', 'place', 'Going down (from the Ruined Castle grounds)',
         'Surface cell to tunnel mouth: (3,7) to (1,7), (10,4) to (13,1), (5,12) to (4,15), (6,6) to (4,5), (9,6) to (10,4), (7,9) to (7,10), (9,8) to (10,8). On the surface it says "Searching through the rubble '
         '(or swamp) you find a hidden tunnel leading down. Do you take it?" (needs search mode); (9,8) "an old and partially blocked set of stairs leading down into the dark" '
         '(no search). On arrival: "You are no longer going down. Suddenly you hear a noise. There are giant lizards charging!" '
         + tag('fight', 'up to 10 Giant Lizards') + ' if at least 2 are left to charge.'),
        ('17', 'place', 'Tunnel mouths (13,1), (10,4), (4,5), (1,7), (4,15), (7,10), (10,8)',
         'Stand on the mouth facing the wall that is drawn as an opening (the table says which way) and the game asks "The tunnel begins to slope up. Do you go up?" '
         '((10,8): "You find a set of stairs leading up"). YES puts you on the surface cell of the table.'),
        ('24', 'loot', 'Pools (24 to 34)',
         'Stepping on a pool cell asks "You are in front of a deep pool of water. Do you wish to dive in and search it?" '
         + tag('loot', 'Treasure per pool: 1000 sp, 1000 gp, 1 gem') + ' (taken once only; saved games remember it). '
         'Item too: ' + tag('loot', 'Shield +2') + ' at 27 (11,15), 28 (13,12) and 34 (9,6); ' + tag('loot', 'Long Sword +1') + ' at 29 (8,5). '
         'Pools that share a treasure count as one: 25 and 32 (3,8), (3,10), 26 and 33 (5,13), (7,14), 29 and 34 (8,5), (9,6). '
         'So there are 8 treasures: (2,2), (3,8) or (3,10), (5,13) or (7,14), (11,15), (13,12), (8,5) or (9,6), (10,2) and the plus-shaped pool (6,8) (four approach cells (6,7), (5,8), (7,8), (6,9)).'),
        ('A', 'fight', 'Lizard men at the water',
         'Before the prompt, while at least 3 lizard men are still alive, ' + tag('fight', 'up to 5 Lizard Men') + ' '
         '"slither out of the water and throw javelins": one 1d6 hit per man. The first time ever they dive back at once. Later, if you are not surprised, you choose: '
         'let them go, or "before they can return to the water you engage them; they fight fanatically" (a fight; killed men do not come back). '
         'If they escaped, diving in is a trap ("lizard men... damage: 5 hits of 2d2, then 5 hits of 1d8, you get out before they finish you off") and finds nothing. '
         'With no ambush, or after you beat them, the dive searches the pool.'),
        ('X', 'hint', 'Not confirmed in play',
         'How many lizard men are alive when you first arrive, the retreat cells used when you flee a pool fight, and the exact surprise odds. '
         'No random fights and no other events in these tunnels: every other cell is empty.'),
    ],
    table=dict(
        rows=[['Mouth', 'No.', 'Face', 'Goes up to', 'Mouth', 'No.', 'Face', 'Goes up to'],
              ['(13,1)', '17', 'north', '(10,4)', '(1,7)', '20', 'north', '(3,7)'],
              ['(10,4)', '18', 'east', '(9,6)', '(4,15)', '21', 'south', '(5,12)'],
              ['(4,5)', '19', 'north', '(6,6)', '(7,10)', '22', 'west', '(7,9)'],
              ['(10,8)', '23', 'north', '(9,8)', '', '', '', '']],
        widths=[26, 28, 34, 56, 28, 28, 34, 0],
        caption='Face: the way you must look. "Goes up to": the cell on the Ruined Castle grounds map you land on.'),
    boxes=[
        '<b>MONSTERS</b> Lizardman (11,2), AC4, HP11. Giant Lizard (11,3), AC5, HP16. <b>DAMAGE</b> javelins 1d6 each; the dive trap 5 x 2d2 then 5 x 1d8.',
        '<b>NOT CONFIRMED</b> The wall openings drawn at the tunnel mouths and the grey squares inside the rock (taken to be water) are read from the map layout, not seen in play.',
    ],
)
