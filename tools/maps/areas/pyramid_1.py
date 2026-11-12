"""The sorcerer's pyramid, maze level: GEO7 block 22, ECL7 block 22 (tile set 7). Read from the area script
(see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='pyramid-1',
    title='PYRAMID: MAZE LEVEL',
    subtitle=("The pyramid on the north shore (first level)", 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    geo=('GEO7', 22),
    start=(0, 15),
    # every cell a teleport of this level or the next one can drop you on (so the maze is not shaded as unreachable)
    extra_starts=[(11, 5), (10, 1), (14, 8), (8, 9), (0, 0), (3, 1), (6, 8), (1, 11), (7, 15), (8, 15), (15, 12)],
    exits=[(0, 15, 'N'), (15, 15, 'S'), (15, 13, 'S')],
    illusion_ids=[4],
    hatch_events={0: ('#f4e6d6', '#d9b88f')},
    legend=['arrival', 'exit', 'search', 'door', 'illusion:secret door (search to find)', 'hatch:random fights (1 step in 21)',
            'grey:sealed, no way in'],
    rooms=[],
    markers=[
        ('1', 15, 15, 'hint'), ('2', 15, 13, 'hint', dict(dy=3)), ('3', 7, 14, 'secret'), ('4', 8, 14, 'secret'),
        ('4', 9, 14, 'secret'), ('4', 1, 6, 'secret'),
    ],
    diamonds=[('j', 4, 13, 'hint')],
    glance=('<b>ARRIVE</b> at (15,0) facing south, after ENTER at the pyramid (North Shore map square (6,16)), a rowboat trip from the reeds (6,14). '
            'The east corridor (column 15) is safe; the maze west of it is shut by <b>secret doors</b> and reached by <b>teleports</b>. '
            '<b>LEAVE</b> by the secret doors at the north wall of (15,0) or the south wall of (15,15), or through the priest\'s hole at (13,15). '
            '<b>DEEPER</b>: the rock room (14,7) and the flash cell (6,1) lead to Yarash\'s Lab (next page). No treasure and no locked door on this level; '
            'the maze is only random fights and the way on.'),
    entries=[
        ('1', 'hint', 'Secret exits ((15,0) north, (15,15) south)',
         'Both walls are secret doors: stand on the cell and search (S key); each party member has about 1 chance in 6 per step (2 in 6 with S, plus 1 in 6 for an elf '
         'or half-elf). "A SECRET DOOR IS FOUND ... IN FRONT OF YOU" and the way out to the North Shore map opens for good. Until then walking into them is blocked.'),
        ('2', 'hint', 'The priest (13,15)',
         '"YOU SEE A HUMAN PRIEST" (2nd Lvl Cleric). Parley: HAUGHTY, SLY or ABUSIVE and he only blesses you ("peace brother"). '
         + tag('hint', 'Be NICE or MEEK') + ': 1 try in 3 he confesses he has chiseled almost through the south wall: say YES and you break through, '
         'he leaves by the hole, and from then on (13,15) offers "go through it?" (out to the North Shore map). Attack and he is just a level 2 cleric. Flee puts you at (12,15).'),
        ('3', 'secret', 'Rock room ((14,7), door from (15,7))',
         'Rocks on the flagstones. Step in: a flash throws you to the next level (4,15) the first time, to (5,11) here the second, and so on. '
         'Search (S) first and you feel "a strange tingle near a bare area"; then you get GO BACK (to (15,7)) / MOVE ON / THROW A ROCK '
         '(it vanishes with a flash and flips which way the next flash goes, without moving you). One switch is shared with the three rock rooms of the next level.'),
        ('4', 'secret', 'Flash cells: (14,8), (14,9), (6,1)',
         '"As you move through the room there is a flash." ' + tag('secret', '(14,8)') + ' sends you to (5,11), ' + tag('secret', '(14,9)') + ' to (0,0), ' + tag('secret', '(6,1)')
         + ' to Yarash\'s level (0,12). (14,8) has a door from (15,8); (14,9) and (6,1) are reached from inside the maze.'),
        ('j', 'hint', 'Corpse (13,4)',
         'A man stripped of weapons and gear. Search (S key): <b>the Journal of Tyrmor</b>, journal entry 26 (once per visit).'),
        ('R', 'fight', 'Random fights (hatch)',
         'Walking: 1 step in 21 (1 in 3 with S) except in column 15. The north half (rows 0-7) and the south half (rows 8-15) each have 6 groups, each fought once '
         '(then it stays gone); a fled fight puts you on a random cell of the same half (north (0,0) (1,3) (8,6) (11,1); south (5,11) (1,10) (8,14) (9,8)). '
         + tag('hint', 'Friendly-looking groups') + ' ("they smile at you", "SAVED!") are not: their parley button just starts the fight.'),
    ],
    table=dict(
        rows=[['Half', 'Group (3 each, stirges 20)', 'Lvl', 'AC', 'HP', 'Mood'],
              ['N', 'Stirges (20)', '2', '8', '5', 'swoop'], ['N', 'Driders', '7', '3', '36', 'hungry'],
              ['N', 'Minotaurs', '7', '6', '33', 'hungry'], ['N', 'Elves (rec. DIANE)', '5', '9', '20', 'friendly look'],
              ['N', 'Kobolds', '0', '7', '3', 'hungry'], ['N', '7th Lvl Fighters', '7', '8', '50', 'friendly look'],
              ['S', '6th Lvl Fighters', '6', '2', '45', 'friendly look'], ['S', 'Displacer Beasts', '6', '2', '30', 'hungry'],
              ['S', '7th Lvl Dwarf Fighters', '7', '4', '50', 'friendly look'], ['S', 'Lizardmen', '3', '4', '11', 'hungry'],
              ['S', 'Driders', '7', '3', '36', 'hungry'], ['S', '7th Lvl Thieves', '7', '10', '28', 'friendly look']],
        widths=[22, 108, 18, 18, 20, 0],
        caption='Lvl, AC (descending), HP as stored in the game files.'),
    boxes=[
        '<b>SECRET DOORS</b> (cell: wall) (15,0) N, (15,15) S (both exits); (1,12) S = (1,13) N; (4,10) E = (5,10) W; (12,8) E (opens from the (12,8) side only); (11,9) E = (12,9) W; (13,14) E = (14,14) W; hole (13,15) S. '
        'Each is found from either of its cells; found doors stay found. <b>TEXT</b> the doors between corridor pockets are plain doors (amber).',
        '<b>NOT CONFIRMED</b> group sizes of the fights (none carries loot); (2,6)-(4,7) and (5,14) are walled pockets with no door and no way in '
        '(they look unused). That the pyramid is Yarash\'s base and its pollution the Stojonow river\'s: see the next page.',
    ],
)
