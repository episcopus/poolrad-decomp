"""Orc mansion: GEO1 block 31, run by ECL1 block 24 (tile set 1), the same script as the Temple of Bane map
(areas/temple_of_bane.py): the script's init entry loads map 24 or 31 by the area number in [49C5] and the
step entry switches between them (LOADGFX 31 / 24) without a new script. Block 31 has no ECL block of its own
in ECL1. Read from the area script (see tools/maps/README.md). The script names no place; "orc mansion" is
the neutral description of its texts ("a large mansion, crude black hand prints")."""
from mapkit import tag

SPEC = dict(
    name='orc-mansion',
    title='ORC MANSION',
    subtitle=('Black-hand orcs\' mansion, east of the Temple of Bane', 'Pool of Radiance (SSI, DOS)  |  annotated map  |  SPOILERS'),
    source_note=('Game files: GEO1 block 31, script ECL1 block 24 (shared with the temple map),',
                 'MON1CHA, ITEM1. Grid: columns A-P, rows 1-16, north is up.'),
    geo=('GEO1', 31),
    start=(4, 0),
    exits=[(4, 0, 'W'), (11, 0, 'W'), (4, 15, 'E'), (11, 15, 'E'), (0, 4, 'N'), (0, 11, 'N')],
    legend=['arrival', 'exit', 'door'],
    markers=[
        ('1', 5, 6, 'loot'), ('1', 7, 6, 'loot'), ('2', 5, 7, 'loot'), ('2', 6, 9, 'loot'), ('3', 6, 11, 'loot'),
        ('4', 5, 14, 'loot'), ('4', 6, 13, 'loot'), ('A', 9.5, 10, 'fight'), ('6', 8, 6, 'fight'), ('7', 8, 14, 'hint'),
        ('8', 11, 8, 'place'), ('9', 12, 8, 'fight'), ('10', 14, 10, 'fight'), ('11', 14, 6, 'place'), ('12', 15, 5, 'hint'),
    ],
    glance=('<b>ARRIVE</b> on A5 or A12 facing east (walking east off the temple map\'s P5 or P12). <b>EXITS:</b> west A5, A12 back to the temple map; north E1, L1 to ECL3 block 14; '
            'east P5, P12 to ECL7 block 26 (the city\'s east edge); the south gaps E16, L16 have no target in the script. Same script as the Temple of Bane, so flags are shared. '
            'No passwords, no locked doors. <b>Quirk:</b> a room\'s text and treasure check run only when the last room you triggered was a <i>different</i> one, '
            'so switch search mode on (S key) <i>before</i> the step that enters the room; to retry, enter another numbered room first.'),
    entries=[
        ('P', 'fight', 'Every cell without a number: random encounters',
         'Same as the temple map: 3 in 60 per step (10 in 60 searching), 4 in 10 a black-hand patrol of 4 Orcs (never forced: FLEE or PARLEY ends it; '
         'a kill drops 6 Leather Holy Symbols), else orcs, goblins, hobgoblins, ogres. They stop once Mace is dead <i>and</i> the ambush (A) is won.'),
        ('A', 'fight', 'Orc ambush, once (K6 K7 L7 M7; O6 N7; K10 K11)',
         'First step on a cell of event 3, 4 or 5: "a large group of foul orcs, they snarl and attack": <b>10 Orcs</b>, <b>20</b> if you have already met a black-hand patrol (beaten, fled or '
         'parleyed: flag set for good). Holding a Bane holy symbol only changes the text ("surprised that you are here"): every choice, even FLEE, ends in the same fight. Win and the flag is set for good.'),
        ('1', 'loot', 'Rubble room (G6, G8)', 'Searching: "in the rubble you spot a beautiful tapestry, will you take it?" ' + tag('loot', 'a Tapestry (250 gp)') + '.'),
        ('2', 'loot', 'Ruined dining room (H6, J7)',
         'Searching: under a broken table, a crushed skeleton with jewelry: ' + tag('loot', '3 pieces of jewelry') + '.'),
        ('3', 'loot', 'Great hall (K6 K7 L7 M7)',
         '"Orc trash and crude black hands on the walls." Each active member rolls to find a <b>trap door</b> on entering: 1 in 6 each when searching (elves, half-elves 2 in 6), '
         'only elves and half-elves 1 in 6 when not (race field, inferred). OPEN: ' + tag('loot', 'a Ring +3, a Potion, a Clerical scroll') + '.'),
        ('4', 'loot', 'Room of the orcs\' victims (O6, N7)',
         'Searching, among the dead bodies: ' + tag('loot', '3 pieces of jewelry') + '.'),
        ('6', 'fight', 'Orcs and an ogre (G9)', '"Six orcs led by a large ogre lunge forward": 6 Orcs + 1 Ogre, once. Win: a piece of paper, journal entry 53.'),
        ('7', 'hint', 'Goblin slaves (O9)',
         'Cowering goblins ask not to be killed: KILL THEM (nothing more) or ' + tag('hint', 'LET THEM GO: "to enter the temple you need a holy symbol of Bane."')),
        ('8', 'place', 'Outside the mansion (I12)', '"You stand outside a large mansion. On the walls are crude black hand prints." The door south leads to 9.'),
        ('9', 'fight', 'Filthy room (I13)', '"Eight orc guards attack you immediately": 6 Orcs + 2 Orc Leaders, once.'),
        ('10', 'fight', 'Room of hay beds (K15, J16)',
         'SEARCH THE BEDS: 8 Orcs burst in (once), then "nothing but lice and hair". Nothing is hidden here.'),
        ('11', 'place', 'Cell (G15, G16)', '"A room that has been converted into a cell." Text only.'),
        ('12', 'hint', 'Scratched message (F16)',
         'A damaged wall text: "NORTH WALL.  RI  T FRONT GLAS . SE". Nothing in the script reads it; it looks like a leftover hint (inference).'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Orc', '1', '6', '5', 'Goblin Guard', '0', '7', '4'], ['Orc Leader', '1', '5', '8', 'Hobgoblin', '2', '5', '6'],
              ['Ogre', '5', '5', '21', 'Ogre Leader', '7', '3', '32']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON1CHA).'),
    boxes=[
        '<b>PASSWORDS</b> none. <b>LOCKS</b> none. <b>SEARCH (S key on before the step)</b> rubble room 1, dining room 2, great hall 3 (trap door), victims\' room 4. '
        '<b>ONCE ONLY</b> every treasure, the ambush A, the fights at 6, 9, 10 and the slaves 7 happen once (flags kept between visits).',
        '<b>ORDER</b> Take the ambush (A) at full strength, then the rooms; search 1-4 in search mode; the slaves (7) tell you what the temple gate wants. '
        'Holy symbols come from the black-hand patrols or the Podal Plaza recruiter. Mace and the temple are one map west.',
    ],
)
