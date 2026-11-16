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
    geo=('GEO1', 31),
    start=(4, 0),
    exits=[(4, 0, 'W'), (11, 0, 'W'), (4, 15, 'E'), (11, 15, 'E'), (0, 4, 'N'), (0, 11, 'N')],
    legend=['arrival', 'exit', 'door'],
    markers=[
        ('1', 5, 6, 'loot'), ('1', 7, 6, 'loot'), ('2', 5, 7, 'loot'), ('2', 6, 9, 'loot'), ('3', 6, 11, 'loot'),
        ('4', 5, 14, 'loot'), ('4', 6, 13, 'loot'), ('A', 9.5, 10, 'fight'), ('6', 8, 6, 'fight'), ('7', 8, 14, 'hint'),
        ('8', 11, 8, 'place'), ('9', 12, 8, 'fight'), ('10', 14, 10, 'fight'), ('11', 14, 6, 'place'), ('12', 15, 5, 'hint'),
    ],
    glance=('<b>ARRIVE</b> on (0,4) or (0,11) facing east (walking east off the Temple of Bane map\'s (15,4) or (15,11)), or by Kovel Mansion\'s south gates (this mansion lies south of it). <b>EXITS:</b> west (0,4), (0,11) back to the Temple of Bane; north (4,0), (11,0) to Kovel Mansion; '
            'east (15,4), (15,11) out to the east gate of Old Phlan on the North Shore map (square (26,27)); the south gaps (4,15), (11,15) lead nowhere (not confirmed in play). This map and the Temple of Bane share their quest progress. '
            'No passwords, no locked doors. <b>Quirk:</b> a room\'s text and treasure check run only when the last room you triggered was a <i>different</i> one, '
            'so switch search mode on (S key) <i>before</i> the step that enters the room; to retry, enter another numbered room first.'),
    entries=[
        ('P', 'fight', 'Every cell without a number: random encounters',
         'Same as the temple map: 3 in 60 per step (10 in 60 searching), 4 in 10 a black-hand patrol of 4 Orcs (never forced: FLEE or PARLEY ends it; '
         'a kill drops 6 Leather Holy Symbols), else orcs, goblins, hobgoblins, ogres. They stop once Mace is dead <i>and</i> the ambush (A) is won.'),
        ('A', 'fight', 'Orc ambush, once ((10,5) (10,6) (11,6) (12,6); (14,5) (13,6); (10,9) (10,10))',
         'First step on any of these cells: "a large group of foul orcs, they snarl and attack": <b>10 Orcs</b>, <b>20</b> if you have already met a black-hand patrol (beaten, fled or '
         'parleyed: remembered for good). Holding a Bane holy symbol only changes the text ("surprised that you are here"): every choice, even FLEE, ends in the same fight. Win and it is done for good.'),
        ('1', 'loot', 'Rubble room (6,5), (6,7)', 'Searching: "in the rubble you spot a beautiful tapestry, will you take it?" ' + tag('loot', 'a Tapestry (250 gp)') + '.'),
        ('2', 'loot', 'Ruined dining room (7,5), (9,6)',
         'Searching: under a broken table, a crushed skeleton with jewelry: ' + tag('loot', '3 pieces of jewelry') + '.'),
        ('3', 'loot', 'Great hall ((10,5) (10,6) (11,6) (12,6))',
         '"Orc trash and crude black hands on the walls." Each active member rolls to find a <b>trap door</b> on entering: 1 in 6 each when searching (elves, half-elves 2 in 6), '
         'only elves and half-elves 1 in 6 when not (as far as we can tell). OPEN: ' + tag('loot', 'a Ring +3, a Potion, a Clerical scroll') + '.'),
        ('4', 'loot', 'Room of the orcs\' victims (14,5), (13,6)',
         'Searching, among the dead bodies: ' + tag('loot', '3 pieces of jewelry') + '.'),
        ('6', 'fight', 'Orcs and an ogre (6,8)', '"Six orcs led by a large ogre lunge forward": 6 Orcs + 1 Ogre, once. Win: a piece of paper, journal entry 53.'),
        ('7', 'hint', 'Goblin slaves (14,8)',
         'Cowering goblins ask not to be killed: KILL THEM (nothing more) or ' + tag('hint', 'LET THEM GO: "to enter the temple you need a holy symbol of Bane."')),
        ('8', 'place', 'Outside the mansion (8,11)', '"You stand outside a large mansion. On the walls are crude black hand prints." The door south leads to 9.'),
        ('9', 'fight', 'Filthy room (8,12)', '"Eight orc guards attack you immediately": 6 Orcs + 2 Orc Leaders, once.'),
        ('10', 'fight', 'Room of hay beds (10,14), (9,15)',
         'SEARCH THE BEDS: 8 Orcs burst in (once), then "nothing but lice and hair". Nothing is hidden here.'),
        ('11', 'place', 'Cell (6,14), (6,15)', '"A room that has been converted into a cell." Text only.'),
        ('12', 'hint', 'Scratched message (5,15)',
         'A damaged wall text: "NORTH WALL.  RI  T FRONT GLAS . SE". Nothing in the game seems to use it; it looks like a leftover hint.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Orc', '1', '6', '5', 'Goblin Guard', '0', '7', '4'], ['Orc Leader', '1', '5', '8', 'Hobgoblin', '2', '5', '6'],
              ['Ogre', '5', '5', '21', 'Ogre Leader', '7', '3', '32']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as the game stores them.'),
    boxes=[
        '<b>PASSWORDS</b> none. <b>LOCKS</b> none. <b>SEARCH (S key on before the step)</b> rubble room 1, dining room 2, great hall 3 (trap door), victims\' room 4. '
        '<b>ONCE ONLY</b> every treasure, the ambush A, the fights at 6, 9, 10 and the slaves 7 happen once (kept between visits).',
        '<b>ORDER</b> Take the ambush (A) at full strength, then the rooms; search 1-4 in search mode; the slaves (7) tell you what the temple gate wants. '
        'Holy symbols come from the black-hand patrols or the Podal Plaza recruiter. Mace and the Temple of Bane are one map west.',
    ],
)
