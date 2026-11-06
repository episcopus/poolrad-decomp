"""The old library of Phlan: GEO2 block 15, ECL2 block 15 (tile set 2). Read from the area script
(see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='library',
    title='LIBRARY',
    subtitle=('Old stacks, a basilisk, a spectre that guards the books', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Read from the game files: area map GEO2 block 15, scripts ECL2 block 15 and ECL3 block 8,',
                 'monsters MON2CHA, loot ITEM2. Grid: (column,row) from 0, top left, north up.'),
    geo=('GEO2', 15),
    start=(0, 4),
    exits=[(0, 4, 'N'), (0, 11, 'N'), (4, 0, 'W'), (11, 0, 'W')],
    hatch_events={1: ('#d3e6c0', '#8fb27a')},
    legend=['arrival', 'exit', 'search', 'door', 'lock2:locked (Bash/Pick/Knock; front doors: Bash/Knock)',
            'hatch:garden slime (G)', 'grey:pillar'],
    rooms=[
        ('PHILOSOPHY', 8.0, 13, 4.8), ('MATHEMATICS', 8.0, 3, 4.6), ('HISTORY', 4.0, 11, 5.0), ('RHETORIC', 4.0, 5, 5.0),
        ('GARDEN', 10.9, 4, 4.6), ('(pond)', 11.35, 4, 4.2),
    ],
    markers=[
        ('1', 6, 13, 'hint'), ('2', 6, 3, 'hint'), ('3', 2, 11, 'hint'), ('4', 2, 5, 'fight'),
        ('X', 2, 8, 'fight'), ('X', 13, 9, 'fight'), ('G', 12, 6, 'fight'),
        ('8', 12, 11, 'hint'), ('9', 10, 12, 'fight'),
    ],
    diamonds=[('5', 11, 8, 'loot'), ('6', 13, 13, 'loot'), ('7', 9, 10, 'loot'), ('7', 10, 8, 'loot', dict(dx=-3, dy=4)), ('7', 13, 10, 'loot')],
    glance=('<b>ARRIVE</b> outside the library building (2,2)-(14,13): on the north edge ((4,0) or (11,0), from the hub map ECL8 block 29) or the west edge ((0,4) or (0,11), from ECL4 block 2); '
            'the same four edge doors lead out. <b>GET IN</b> by the north double door (8,1)-(8,2) (hard lock: Bash or Knock) or the south door (9,14)-(9,13) (hard lock from outside, free from inside). '
            '<b>REWARD</b> (City Hall, ECL3 block 8): "a reward for clearing the library", <b>250 gp + 200 pp</b>, once the basilisk (4) <u>and</u> the spectre (X) are dead. '
            '<b>SAFE</b>: no random fights, and camping is never interrupted. Looks like Mendor\'s library (the Sokal Keep ghost speaks of it); this script never names it.'),
    entries=[
        ('G', 'fight', 'Garden ((2,9)-(6,13), green hatch)',
         'Once a garden: "WEED FILLED. THE PLEASANT POND HAS BECOME A SWAMP." A small maze of low walls and doors round the pond. Each step in it: 7 in 26 to meet <b>green slime</b>, at most 7 times '
         'in the whole game (the counter [4A32] never resets). Mostly you spot it and walk round; sometimes you step in: 1d4 to one member ("A GOOD DEAL OF DAMAGE"). Door in from the hall at (6,9)-(7,9).'),
        ('1', 'hint', 'Philosophy stacks (12,6)-(14,8)',
         'Sign "PHILOSOPHY." (once per visit). ' + tag('secret', 'SEARCH (S key)') + ': each search about 1 in 4 finds a book, "DO YOU TAKE IT?": <b>Fyerdetha\'s Discourses on Power</b> (journal entry 7), '
         '<b>Urgund\'s description of darkness</b> (entry 19; his imprisonment in the lower realms) or one of five titled books (MEDITATIONS; THE HARMONY OF THE ROCK; STROM\'S DISCUSSIONS OF POETICS; '
         'CHRONICLES OF ARRAM; DISCOURSE ON THE NATURE OF WRITING: flags only, no item in the script). Never offered twice; else "VERY BORING".'),
        ('2', 'hint', 'Mathematics stacks (2,6)-(4,8)', 'Sign "MATHEMATICS." Searching gives "ESSAYS ON GEOMETRY... NOTHING USEFUL." Nothing here.'),
        ('3', 'hint', 'History stacks (10,2)-(12,4)',
         'Sign "HISTORY." ' + tag('secret', 'SEARCH') + ': about 1 search in 6 finds a book (DO YOU TAKE IT?): <b>Lex Geographica</b>, an atlas by Tomarus with an old map of Phlan (entry 37), '
         '<b>the History of the North</b> (entry 8) or <b>the Grand Historian\'s records of the arts of war</b> (entry 21). Else "FILLED WITH MYTH".'),
        ('4', 'fight', 'Rhetoric stacks (4,2)-(6,4): the basilisk',
         'Sign "RHETORIC." Walking in (no search needed) while it lives: <b>a Basilisk</b>, "A DULL BROWN REPTILIAN MONSTER" (it may hiss at you, ambush you at once, or not notice you). '
         'Fight, or FLEE (to (5,5)). Loot: ' + tag('loot', 'Clerical Scroll (2 spells), Cloak of Displacement +2, Potion of Healing, Potion of Giant Strength') + '. Searching here: murder-trial speeches, nothing.'),
        ('X', 'fight', 'The spectre ((8,2) facing north, (9,13) facing south)',
         'Turn to leave by either front door after you took <b>any</b> journal book from the stacks (1, 3): "A SPECTRE SUDDENLY APPEARS... \'THIEF! I DEFENDED THESE BOOKS IN LIFE AND I WILL DEFEND THEM IN DEATH!\'" '
         '1 Spectre. Kill it and it is gone for good; flee and you land at (5,5) and it stays. No loot. The jar and the Manual (5, 6) do not count as books, so with no book it never comes (and the reward needs it dead).'),
        ('5', 'loot', 'Ruined room with a desk (8,11)',
         '"A RUINED ROOM... HUMAN BONES LIE SCATTERED ABOUT A DESK." ' + tag('loot', 'SEARCH') + ' after that: "A JAR UNDER THE FLOORBOARDS": <b>3 Potions of Extra Healing</b> (once ever).'),
        ('6', 'loot', 'Buried book (13,13)', tag('loot', 'SEARCH') + ': "BURIED AMID ALL THE TRASH YOU SEE A BOOK": a <b>Manual of Bodily Health</b> (a training manual), DO YOU TAKE IT? Once ever.'),
        ('7', 'loot', 'Illuminators\' carrels (10,9), (8,10), (10,13)',
         'Each says "ALL THEIR EQUIPMENT HAS DECAYED" once per visit. ' + tag('loot', 'SEARCH') + ' in each: 1 chance in 2 per search of a box of gold foil: <b>3 Sheets of Gold</b> (once each, ever).'),
        ('8', 'hint', 'Mad man (11,12)',
         'Until he leaves or joins: a fighter "COWERING IN THE CORNER", "MERCY!... DIE! DIE YOU SLIME FROM THE PIT!" COMBAT, or PARLAY ABUSIVE, fights him (<b>Mad Man</b>, level 1). '
         'PARLAY NICE: "DO YOU TAKE PITY AND INVITE HIM?", then "DO YOU INSIST?": he <b>joins as an NPC</b> (if your party has room). Other attitudes: rants ("THE EVIL ONE IN THE CASTLE OF FLOWERS -- HE IS COMING!", "DON\'T GO ON THE HILL!", "HE IS NOT HUMAN"). IGNORE: he slips away for good. FLEE: set down at (9,9).'),
        ('9', 'fight', 'Storeroom and kobolds (12,10)',
         '"A STOREROOM FULL OF SUPPLIES TOO OLD TO BE USEFUL", and five Kobolds at a table plead for mercy. PARLAY: spare them and they sketch the area: <b>journal entry 10</b>. '
         'Fight them (5 Kobolds, level 0) for the same entry. FLEE: set down at (9,11). Once ever.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Basilisk', '7', '4', '31', 'Mad Man', '1', '4', '7'], ['Spectre', '8', '2', '38', 'Kobold', '0', '7', '3']],
        widths=[50, 18, 18, 18, 50, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON2CHA).'),
    boxes=[
        '<b>JOURNAL ENTRIES</b> 7 and 19 (Philosophy), 37, 8 and 21 (History), 10 (kobolds); each also sets a [4AAx] flag. <b>LOCKS</b> red cross: Bash, Pick or Knock; the front doors are hard locks (no Pick). '
        '<b>STAYS</b> done: books taken, jar, Manual, foil boxes, basilisk, spectre, kobolds, mad man, the slime count. <b>RESETS</b> each visit: sign and room texts.',
        '<b>LOOKS LIKE the order:</b> open the north door; basilisk (4); search the stacks (1, 3) for books; (8,11), (13,13), the carrels; kobolds and the mad man; then leave by a front door to meet the spectre; clerk for the reward.',
        '<b>TEXT ONLY</b> small cells (3,2)-(3,4), (13,2)-(13,4), (5,6)-(7,6), (9,6)-(11,6) ("A BENCH AND A SMALL DESK"); frescoes (8,2)-(8,4) ("A FEELING OF PEACE"); writing hall (9,10)-(10,10) and (9,13) ("ROWS OF WRITING TABLES"); chambers (7,7), (9,7); study (12,12) ("A SHATTERED RUIN"); storeroom aside from the kobolds.',
    ],
)
