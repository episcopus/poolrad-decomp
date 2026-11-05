"""The tunnels below the lizard men's ruins: GEO8 block 30, run by the script ECL8 block 16 (tile set 8).
Read from the area script (see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='lizardman-tunnels',
    title='LIZARD MAN TUNNELS',
    subtitle=('Flooded tunnels under the ruined keep (ECL8/16)', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Read from the game files: area map GEO8 block 30, run by the script of ECL8 block 16,',
                 'monsters MON8CHA, loot ITEM8. Grid: columns A-P, rows 1-16, north is up.'),
    geo=('GEO8', 30),
    start=(1, 13),
    arrivals=[(4, 10), (5, 4), (7, 1), (8, 10), (10, 7), (15, 4)],
    legend=['arrival', 'door', 'grey:water (pools) and rock'],
    markers=[
        ('24', 2, 2, 'loot'), ('25', 8, 3, 'loot', dict(dy=-1)), ('26', 13, 5, 'loot'), ('27', 15, 11, 'loot'), ('28', 12, 13, 'loot'),
        ('29', 5, 8, 'loot'), ('30', 2, 10, 'loot'), ('31', 7, 6, 'loot'), ('31', 8, 5, 'loot'), ('31', 8, 7, 'loot'), ('31', 9, 6, 'loot'),
        ('32', 10, 3, 'loot'), ('33', 14, 7, 'loot'), ('34', 6, 9, 'loot'),
    ],
    glance=('<b>ARRIVE</b> by one of seven tunnel mouths (green S) from the ruins on the surface map (ECL8/16): search rubble or swamp (S key) on the cells in the table, '
            'or take the old stairs J9 (no search needed). <b>EXIT</b> by standing on a mouth, facing its opening wall, and answering YES to "DO YOU GO UP?". '
            'Three separate regions: the main tunnels (102 cells, four mouths: N2, E6, H11, K9), the west pocket (B8 and E16 are connected, 13 cells) and the '
            'east pocket (K5 with the pool I6, 4 cells). <b>THE POINT:</b> 11 flooded pools; each hides a purse and some hide a magic item, but the lizard men may ambush you at the water. '
            'Numbers on the map are the script\'s event ids (17 to 23 are the mouths, 24 to 34 the pools).'),
    entries=[
        ('S', 'place', 'Going down (from ECL8/16)',
         'Surface cell to tunnel mouth: D8 to B8, K5 to N2, F13 to E16, G7 to E6, J7 to K5, H10 to H11, J9 to K9. On the surface it says "Searching through the rubble '
         '(or swamp) you find a hidden tunnel leading down. Do you take it?" (needs search mode); J9 "an old and partially blocked set of stairs leading down into the dark" '
         '(no search). On arrival: "You are no longer going down. Suddenly you hear a noise. There are giant lizards charging!" '
         + tag('fight', 'up to 10 Giant Lizards') + ' when the script\'s lizard counters allow (it needs at least 2; the counters are set outside this script: not traced).'),
        ('17', 'place', 'Tunnel mouths (N2, K5, E6, B8, E16, H11, K9)',
         'Stand on the mouth facing the wall that is drawn as an opening (the table says which way) and the script asks "The tunnel begins to slope up. Do you go up?" '
         '(K9: "You find a set of stairs leading up"). YES puts you on the surface cell of the table.'),
        ('24', 'loot', 'Pools (24 to 34)',
         'Stepping on a pool cell asks "You are in front of a deep pool of water. Do you wish to dive in and search it?" '
         + tag('loot', 'Treasure per pool: 1000 sp, 1000 gp, 1 gem') + ' (taken once ever; the script keeps the flag in a saved game word). '
         'Item too: ' + tag('loot', 'Shield +2') + ' at 27 (L16), 28 (N13) and 34 (J7); ' + tag('loot', 'Long Sword +1') + ' at 29 (I6). '
         'Pools that share a flag count as one treasure: 25 and 32 (D9, D11), 26 and 33 (F14, H15), 29 and 34 (I6, J7). '
         'So there are 8 treasures: C3, D9 or D11, F14 or H15, L16, N13, I6 or J7, K3 and the plus-shaped pool G9 (four approach cells G8, F9, H9, G10).'),
        ('A', 'fight', 'Lizard men at the water',
         'Before the prompt, if the lizard-man counter (set outside this script) is at least 53, ' + tag('fight', 'min(5, counter - 50) Lizard Men') + ' (at least 3) '
         '"slither out of the water and throw javelins": one 1d6 hit per man. The first time ever they dive back at once. Later, if you are not surprised, you choose: '
         'let them go, or "before they can return to the water you engage them; they fight fanatically" (a fight; killed men come off the counter). '
         'If they escaped, diving in is a trap ("lizard men... damage: 5 hits of 2d2, then 5 hits of 1d8, you get out before they finish you off") and finds nothing. '
         'With no ambush, or after you beat them, the dive searches the pool.'),
        ('X', 'hint', 'Not traced',
         'What the lizard counters start at (set outside the script), the retreat cells used when you flee a pool fight, and the exact surprise odds. '
         'No random fights and no other events in these tunnels: every other cell is empty.'),
    ],
    table=dict(
        rows=[['Mouth', 'Event', 'Face', 'Goes up to', 'Mouth', 'Event', 'Face', 'Goes up to'],
              ['N2', '17', 'north', 'K5', 'B8', '20', 'north', 'D8'],
              ['K5', '18', 'east', 'J7', 'E16', '21', 'south', 'F13'],
              ['E6', '19', 'north', 'G7', 'H11', '22', 'west', 'H10'],
              ['K9', '23', 'north', 'J9', '', '', '', '']],
        widths=[26, 28, 34, 56, 28, 28, 34, 0],
        caption='Face: the way you must look. "Goes up to": the cell on GEO8 block 16 you land on.'),
    boxes=[
        '<b>MONSTERS</b> (MON8CHA) Lizardman L3, AC4, HP11. Giant Lizard L4, AC5, HP16. <b>DAMAGE</b> javelins 1d6 each; the dive trap 5 x 2d2 then 5 x 1d8.',
        '<b>EVIDENCE</b> The map is loaded by the script of block 16 (LOADGFX 30 at the hidden-tunnel code). Events 17 to 23 are read by its step entry (cell + facing table), 24 to 34 by its search entry. '
        'Inferences: the opening walls are wall id 9 (and id 3 at K9); the grey squares inside the rock are water (wall id 11 cells).',
    ],
)
