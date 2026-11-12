"""Valjevo Castle, the yard north of Stojanow Gate: GEO5 block 6, ECL5 block 6 (tile set 5). Read from the area
script (see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='valjevo-castle-yard',
    title='VALJEVO CASTLE',
    subtitle=('The castle yard (south-west): giants, Bane temple, smithy', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    geo=('GEO5', 6),
    start=(15, 4),
    extra_starts=[(0, 4), (0, 11), (4, 15), (11, 15)],
    exits=[(15, 4, 'S'), (15, 11, 'S'), (0, 3, 'N'), (0, 4, 'N'), (0, 11, 'N'), (4, 15, 'E'), (11, 15, 'E'), (12, 15, 'E')],
    hatch_events={0: ('#f3d9d3', '#d89b90')},
    legend=['arrival', 'exit', 'door', 'hatch:patrol ground (alarm only; half as likely in the maze and bare rooms)'],
    rooms=[
        ('TEMPLE OF BANE', 1, 0.9, 4.8, '#9a3f2f', True), ('altar', 0, 0, 4.2), ('SMOKE-', 5.0, 0.5, 3.8), ('HOUSE', 5.5, 0.5, 3.8), ('(empty)', 9.5, 0.5, 4.4),
        ('COAL', 12.5, 0.5, 4.2), ('SMITHY', 15, 1.5, 6, '#9a6b2f', True), ('(empty)', 14.8, 6.5, 4.6), ('(empty)', 14.8, 9.5, 4.2),
        ('LAUNDRY', 14.9, 13.5, 6, '#2f6d9a', True), ('MAZE (entered from the NW quarter only)', 8.7, 8.5, 6, '#7a6d5c', True),
    ],
    markers=[
        ('1', 14, 12, 'hint'), ('2', 14, 0, 'fight', dict(dx=3)), ('3', 2, 1, 'fight', dict(dx=-3)), ('4', 0, 1, 'loot', dict(dx=8)),
        ('5', 6, 0, 'place', dict(dy=-6)), ('5', 13, 1, 'place', dict(dy=2)), ('5', 5, 9, 'place'), ('6', 10, 6, 'place'),
        ('P', 7, 3, 'fight'),
    ],
    glance=('<b>ARRIVE</b> at (4,15) from Stojanow Gate, facing north. <b>EXITS</b> (green arrows; the direction you face when you walk off the edge decides): '
            'facing south (the gates (4,15), (11,15)) goes back to Stojanow Gate; any other edge (north gates (3,0), (4,0), (11,0), east gates (15,4), (15,11), (15,12)) goes on into '
            'the North-West quarter, which leads north/east to the North-East quarter and south/west back here. <b>NOTHING ROAMS</b> until an alarm rings. The giants are best passed in disguise '
            '(laundry, 1) or by luck; the smithy fight (2) and the Bane temple (3) are the only set fights. Orange doors are plain doors; nothing here is locked.'),
    entries=[
        ('P', 'fight', 'Alarm and patrols (hatched ground)',
         'An alarm starts when a fight here is not won outright (fleeing counts as not winning), when you flee a patrol, or 1 time in 5 '
         'when you kill the laundry women. It lasts about one game hour and each new trigger restarts it; Stojanow Gate raises the same alarm. '
         'While it rings, each step on hatched ground risks a patrol: <b>1 in 21</b> on street cells, <b>1 in 3</b> if you SEARCH that step; half as likely on the light hatch '
         '(maze, bare buildings); never inside the temple (0,0)-(2,3), smokehouse (0,5)-(1,6) or coal stores (0,12)-(1,13), (9,5). "AN ALARM IS SOUNDING" is printed about 1 step in 10 and on every search step. '
         'A patrol is <b>a 6th-level fighter + 5 hill giants</b>. Stolen from the Bane altar (4)? They attack on sight, FIGHT or FLEE only. No disguise: same. '
         + tag('hint', 'In the laundry disguise') + ': WAIT or ADVANCE until PARLAY, then your attitude: <b>MEEK</b> is asked the password: <b>HARASH</b>; '
         '<b>HAUGHTY</b> or <b>ABUSIVE</b> is asked on whose authority: <b>TYRANTHRAXUS</b>; SLY or NICE: they attack. A wrong word: they attack. Fleeing rings the alarm and puts you back a step. '
         'Resting: camping is safe while quiet; with the alarm on, outside the patrol-free buildings, an interrupted camp is a patrol (inferred).'),
        ('1', 'hint', 'Laundry ((12,13), door at (11,13)), once per game',
         'Women wash clothes. A half-orc woman asks what you want: your attitude: ABUSIVE makes them plead and offer clothes; any other has them offer them. '
         + tag('hint', 'YES to the disguise') + ' gives you the disguise the patrols test for (the printed replies look swapped; what counts is whether you end up disguised). Then '
         'TIE THEM UP (safe), KILL THEM (no fight is run; 1 in 5 the screams are heard: alarm, disguise lost) or LEAVE (HAUGHTY loses the disguise, ABUSIVE rings the alarm). '
         'The disguise is lost for good when you take the offering box or the swords (4, 5) and when a fight is not won.'),
        ('2', 'fight', 'Smithy ((0,14)-(3,15); door at (3,14)), only while the clock hour is 14 or less',
         '"The smith (a human) and three fire giants" at work. PARLAY: HAUGHTY gets "no more orders, get authorization" (no fight); NICE or MEEK get small talk; SLY or ABUSIVE: '
         '"you don\'t belong here" and a fight. COMBAT attacks with surprise. Fight: <b>smith (4th-lvl fighter) + 3 fire giants</b>, 20 gp. Then (or at once after the hour passes) '
         + tag('loot', 'the weapon and armour pile') + ' (yes/no): the whole pile, <b>58 ordinary weapons, arrows and armours</b>, nothing magical.'),
        ('3', 'fight', 'Temple of Bane ((1,2), door at (2,2)), until the priest is dealt with',
         'A barracks turned temple. A priest and two acolytes: MENU: <b>ACCEPT BLESSING</b>: every member who is not evil (only LE, NE, CE are spared) "doubles up in agony", '
         '2d10+2, no save; if anyone was hurt the priest unmasks you (next). <b>LEAVE</b> does the same: "You aren\'t worshippers!", a fireball (15 to everyone, 15 more unless the save works) '
         'and the fight. <b>KILL THEM</b>: fight at once. TALK: flavor (Tyranthraxus founded it). All-evil parties are blessed harmlessly, repeatedly. '
         'Fight: <b>Level 5 cleric + 2 first-level clerics</b>; no loot.'),
        ('4', 'loot', 'Altar ((1,0), far end of the temple)',
         tag('fight', 'Offering box') + ': 37 silver, then "something immense and evil staring down": <b>2d10+2 to everyone</b>, no save; you now count as blasphemers. '
         + tag('loot', 'Crossed swords behind the altar') + ': <b>2 Long Swords +3</b> (no curse). Taking either drops the disguise and makes the messenger in Tyranthraxus\' Tower attack.'),
        ('5', 'place', 'Text-only rooms: smokehouse ((0,6), door south), coal stores ((1,13), door east; (9,5) in the maze)',
         'One block of flavor text each, once per game. Inside the maze there are no set events apart from the patrols.'),
        ('6', 'place', 'Walled block and maze (4,0)-(15,11)',
         'No door connects it to the yard. Its gates ((4,0), (11,0) north; (15,4), (15,11) east) are where you arrive from the North-West quarter (walking off a map edge seems to place you on the opposite edge: not confirmed in play). '
         'The two halves of the maze are separate. The bare buildings (0,8)-(1,10), (5,14)-(8,15), (9,14)-(10,15) have nothing in them.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Hill Giant', '9', '4', '41', 'Level 5 Cleric', '5', '10', '29'], ['Fire Giant', '12', '3', '59', '1st Lvl Cleric', '1', '10', '8'],
              ['6th Lvl Fighter', '6', '2', '45', '4th Lvl Fighter', '4', '8', '30']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files; gear may change AC.'),
    boxes=[
        '<b>PASSWORDS</b> <b>HARASH</b> (MEEK) and <b>TYRANTHRAXUS</b> (HAUGHTY or ABUSIVE) to a patrol, only in the laundry disguise and before stealing from the altar. '
        '<b>NEVER RESET</b> (once per game): laundry, smith, pile, priest, altar and every text-only room; the alarm. Nothing here resets when you re-enter.',
        '<b>SUGGESTED ORDER</b> Laundry disguise (1), then the temple (3) with an all-evil party or a plan to fight; the smithy (2) early in the day; take the swords (4) last, '
        'since they end the disguise; leave by (3,0) or (15,12) for the castle proper, or by (4,15)/(11,15) for Stojanow Gate.',
    ],
)
