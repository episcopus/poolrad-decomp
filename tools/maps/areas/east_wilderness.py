"""The east wilderness script and its random "small dark cave": GEO8 block 27, ECL8 block 27 (tile set 8).
The wilderness itself is the world map (script coordinates, not a 16x16 plan); the plan drawn is the cave. Read from the
area script (see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='east-wilderness',
    title='EAST WILDERNESS',
    subtitle=('East boat from New Phlan; the plan drawn is a random "small dark cave"', 'Pool of Radiance (DOS)  |  area map  |  SPOILERS'),
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
    glance=('<b>THE PLAN</b> The East Wilderness is an overland map; the plan drawn here is only a random "small dark cave" you can stumble into on it. '
            'World squares are (column, row) as on the Overworld page. <b>GETTING HERE</b> New Phlan harbor master, boat EAST (1 pp round trip): you land at square (35, 29), where the boat waits to take you back to New Phlan. '
            'Walking west past column 28 leads back to the North Shore map. <b>The terrain and routes are on the East Wilderness outdoor map page.</b> <b>LANDMARKS</b> (stepping on them offers entry): '
            'Ruined Castle (37, 8), see the Ruined Castle page; two caves (32, 15), large and small, see the Kobold Caves page. '
            '<b>RANDOM</b> 1 step in 20 meets a pack; 1 in 21 of those is a "small, dark cave" (this plan). '
            'The cave is four sealed 8x8 quarters; you enter one of the four S cells at random and leave by the same S cell.'),
    entries=[
        ('B', 'place', 'Boat (35, 29)', '"A boat docked here will return you to the civilized section of Phlan." TAKE BOAT lands you at New Phlan\'s east pier (15,1).'),
        ('C', 'place', 'Ruined Castle (37, 8)', '"A ruined castle surrounded by quicksand. An old worn drawbridge is the only safe way across." ENTER goes to the Ruined Castle.'),
        ('K', 'fight', 'Two caves (32, 15)',
         'First visit: kobolds are seen slipping into the small cave. LARGE (to the Kobold Caves at (10,15), no random fights there until the wyvern is dead), SMALL (hidden, at (6,15) inside) or EXIT. '
         'While the kobold king lives, stepping on the six squares around the caves ((32,14) (33,14) (31,15) (33,15) (32,16) (33,16)) starts '
         + tag('fight', '25 Kobolds + 5 Kobold Leaders') + ' (once per visit).'),
        ('R', 'fight', 'Random packs (1 step in 20)',
         'By d20: Kobolds 4, Gnolls 3, Lizard men 3, Giant Lizards 2, Hippogriffs 2, Wyvern 1, Trolls 2, Phase Spiders 1, Minotaurs 2 (in 20), sized from your party strength. '
         'Choices: flee, fight, parley (not with Giant Lizards, Hippogriffs, Wyverns, Phase Spiders). Parley: attitude + d30 + modifiers: 120+ they wander off, 100-119 they let you pass, less they attack. '
         'Resting in the open can be interrupted by the same encounter.'),
        ('D', 'place', 'Small, dark cave (this plan)',
         '"Will you enter?" Then you are put at (0,3) (NW), (6,15) (SW), (12,15) (SE) or (11,0) (NE) at random. Each quarter has its own fights; in every cell marked S, '
         '"You find a passageway going out": LEAVE returns you to the wilderness. Fleeing a fight returns you to your entry cell. Everything resets each time you enter.'),
        ('2', 'loot', 'NW quarter (entry (0,3)): wyvern lair',
         tag('loot', '(0,2): wyvern\'s treasure') + ': 5000 cp, 6000 sp, 2000 ep, 1000 gp, 3 gems, 3 jewelry and 1 treasure roll (take it with no fight). '
         '3 (6,2), (6,3), (6,5) and 4 (4,1): a Wyvern each ((11,8), AC3, HP42), once each. 1 (2,2): half-eaten halfling, nothing.'),
        ('5', 'fight', 'SW quarter (entry (6,15)): lizard den',
         '5 (5,12): 4 Giant Lizards. 7 (0,9): 4 Giant Lizards + 2 Minotaurs ((11,6), AC6, HP33). 9 (1,15): 2 Giant Lizards guard the chamber. 6 (7,9): human bones. '
         + tag('loot', '8 (2,11): 6000 cp, 4000 sp, 3000 ep and 1 treasure roll') + '.'),
        ('13', 'fight', 'SE quarter (entry (12,15)): gnolls and trolls',
         '13 (9,14) and 14 (14,7): 12 Gnolls + 4 Trolls ((11,6), AC4, HP36), once for both. Hatched cells: 1 in 8 per step a pack of 4 to 34 Gnolls. 12 (15,10): remains of elves.'),
        ('K', 'fight', 'NE quarter (entry (11,0)): mad kobolds',
         'Only hatched cells: 1 in 8 per step a pack of 10 to 50 Kobolds (3 Kobold Leaders too from 40). No treasure.'),
        ('W', 'hint', 'West edge', 'Walking west past column 28 (on some kinds of terrain) takes you to the North Shore map, arriving at column 27: the map the New Phlan WEST and BAY boats land on.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Kobold', '0', '7', '3', 'Hippogriff', '4', '5', '18'], ['Kobold Leader', '0', '7', '4', 'Wyvern', '9', '3', '42'],
              ['Gnoll', '2', '5', '10', 'Phase Spider', '6', '7', '35'], ['Lizardman', '3', '4', '11', 'Troll', '7', '4', '36'],
              ['Giant Lizard', '4', '5', '16', 'Minotaur', '7', '6', '33']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as listed in the game.'),
    boxes=[
        '<b>NOT CONFIRMED</b> which kinds of terrain block walking, the exact size of random packs, and a map picture of the landmarks. '
        'The wilderness itself has no floor plan to draw; only the random cave has.',
    ],
)
