"""The east wilderness script and its random "small dark cave": GEO8 block 27, ECL8 block 27 (tile set 8).
The wilderness itself is the world map (script coordinates, not a 16x16 plan); the plan drawn is the cave. Read from the
area script (see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='east-wilderness',
    title='EAST WILDERNESS',
    subtitle=('East boat from Phlan; plan = the random "small, dark cave"', 'Pool of Radiance (DOS)  |  area map  |  SPOILERS'),
    source_note=('Game files: GEO8 block 27 (the cave), ECL8 block 27 (wilderness + cave), MON8CHA.',
                 'Grid: columns A-P, rows 1-16, north up. World coordinates below are script (col, row), from 0.'),
    geo=('GEO8', 27),
    start=(15, 6),
    arrivals=[(3, 0), (15, 12), (0, 11)],
    hatch_events={10: ('#f3d9d3', '#d89b90'), 15: ('#f6e3c6', '#d9ae6b'), 11: ('#f3d9d3', '#d89b90'), 16: ('#f6e3c6', '#d9ae6b')},
    legend=['arrival', 'door', 'hatch:gnolls 1 in 8 (SE)', 'hatch:mad kobolds 1 in 8 (NE)', 'grey:walls / not reachable'],
    rooms=[('NW CAVE', 0.35, 1.5, 5.0), ('NE CAVE', 0.35, 14.0, 5.0), ('SW CAVE', 8.35, 4.6, 5.0), ('SE CAVE', 8.35, 14.0, 5.0)],
    markers=[
        ('2', 2, 0, 'loot'), ('3', 3, 6, 'fight'), ('3', 5, 6, 'fight'), ('4', 1, 4, 'fight'), ('1', 2, 2, 'place'),
        ('5', 12, 5, 'fight'), ('6', 9, 7, 'place'), ('7', 9, 0, 'fight', dict(dy=3)), ('8', 11, 2, 'loot'), ('9', 15, 1, 'fight', dict(dx=-2)),
        ('13', 14, 9, 'fight'), ('14', 7, 14, 'fight'), ('12', 10, 15, 'place'),
    ],
    glance=('<b>GETTING HERE</b> Phlan harbor master, boat EAST (1 pp round trip): you land at world (9, 29), where the boat waits to take you back to Phlan. '
            'At column 2, on some terrain, the script hands you to the ECL7 block 26 zone. <b>LANDMARKS</b> (stepping on them offers entry): '
            'ruined castle (11, 8) to the ruined castle page; two caves (6, 15), large and small, to the kobold caves page. '
            '<b>RANDOM</b> 1 step in 20 meets a pack; 1 in 21 of those is a "small, dark cave" (this plan). '
            'The cave is four sealed 8x8 quarters; you enter one of the four S cells at random and leave by the same S cell.'),
    entries=[
        ('B', 'place', 'Boat (9, 29)', '"A boat docked here will return you to the civilized section of Phlan." TAKE BOAT lands you at Phlan\'s east pier (P2).'),
        ('C', 'place', 'Ruined castle (11, 8)', '"A ruined castle surrounded by quicksand. An old worn drawbridge is the only safe way across." ENTER goes to the ruined castle.'),
        ('K', 'fight', 'Two caves (6, 15)',
         'First visit: kobolds are seen slipping into the small cave. LARGE (to the kobold caves at K16, no random fights there until the wyvern is dead), SMALL (hidden, at G16) or EXIT. '
         'While the kobold king lives, stepping on the six cells around the caves ((6,14) (7,14) (5,15) (7,15) (6,16) (7,16)) starts '
         + tag('fight', '25 Kobolds + 5 Kobold Leaders') + ' (once per visit).'),
        ('R', 'fight', 'Random packs (1 step in 20)',
         'By d20: Kobolds 4, Gnolls 3, Lizard men 3, Giant Lizards 2, Hippogriffs 2, Wyvern 1, Trolls 2, Phase Spiders 1, Minotaurs 2 (in 20), sized from your party strength. '
         'Choices: flee, fight, parley (not with Giant Lizards, Hippogriffs, Wyverns, Phase Spiders). Parley: attitude + d30 + modifiers: 120+ they wander off, 100-119 they let you pass, less they attack. '
         'Resting in the open can be interrupted by the same encounter.'),
        ('D', 'place', 'Small, dark cave (this plan)',
         '"Will you enter?" Then you are put at A4 (NW), G16 (SW), M16 (SE) or L1 (NE) at random. Each quarter has its own fights; in every cell marked S, '
         '"You find a passageway going out": LEAVE returns you to the wilderness. Fleeing a fight returns you to your entry cell. Flags reset on each entry.'),
        ('2', 'loot', 'NW quarter (entry A4): wyvern lair',
         tag('loot', 'A3: wyvern\'s treasure') + ': 5000 cp, 6000 sp, 2000 ep, 1000 gp, 3 gems, 3 jewelry and 1 treasure roll (take it with no fight). '
         '3 (G3, G4, G6) and 4 (E2): a Wyvern each (L9, AC3, HP42), once each. 1 (C3): half-eaten halfling, nothing.'),
        ('5', 'fight', 'SW quarter (entry G16): lizard den',
         '5 (F13): 4 Giant Lizards. 7 (A10): 4 Giant Lizards + 2 Minotaurs (L7, AC6, HP33). 9 (B16): 2 Giant Lizards guard the chamber. 6 (H10): human bones. '
         + tag('loot', '8 (C12): 6000 cp, 4000 sp, 3000 ep and 1 treasure roll') + '.'),
        ('13', 'fight', 'SE quarter (entry M16): gnolls and trolls',
         '13 (J15) and 14 (O8): 12 Gnolls + 4 Trolls (L7, AC4, HP36), once for both. Hatched cells: 1 in 8 per step a pack of 4 to 34 Gnolls. 12 (P11): remains of elves.'),
        ('K', 'fight', 'NE quarter (entry L1): mad kobolds',
         'Only hatched cells: 1 in 8 per step a pack of 10 to 50 Kobolds (3 Kobold Leaders too from 40). No treasure.'),
        ('W', 'hint', 'West edge', 'At column 2 (on terrain codes 6 and 7, and 5 except row 31) the script hands you to ECL7 block 26, arriving at column 14: the zone the Phlan WEST and BAY boats land in.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Kobold', '0', '7', '3', 'Hippogriff', '4', '5', '18'], ['Kobold Leader', '0', '7', '4', 'Wyvern', '9', '3', '42'],
              ['Gnoll', '2', '5', '10', 'Phase Spider', '6', '7', '35'], ['Lizardman', '3', '4', '11', 'Troll', '7', '4', '36'],
              ['Giant Lizard', '4', '5', '16', 'Minotaur', '7', '6', '33']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON8CHA).'),
    boxes=[
        '<b>NOT TRACED</b> the terrain codes that block walking (a table of impassable map codes and the north and east edge tests), the exact encounter size formula, '
        'and the world-map picture of the landmarks. Everything on this page is read from the script and the cave map; the wilderness itself has no 16x16 plan in the files.',
    ],
)
