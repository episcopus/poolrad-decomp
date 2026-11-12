"""The castle, north-east quarter: GEO5 block 4, ECL5 block 4 (tile set 5). Read from the area script
(see tools/maps/README.md for how each statement was checked). See castle_nw.py for how the four GEO5 maps
(3 NW, 4 NE, 5 SE, 6 SW) fit together: the edge door gaps of this map match those of its neighbours."""
from mapkit import tag

SPEC = dict(
    name='castle-ne',
    title='CASTLE NE',
    subtitle=('Barracks, kitchen, records and scribes of the giants', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    geo=('GEO5', 4),
    start=(3, 0),
    extra_starts=[(4, 0), (11, 0), (15, 4), (15, 11), (15, 12)],
    exits=[(3, 0, 'W'), (4, 0, 'W'), (11, 0, 'W'), (15, 4, 'S'), (15, 11, 'S'), (15, 12, 'S')],
    illusion_ids={4},
    hedge_ids={7, 9},
    legend=['arrival', 'exit', 'search', 'door', 'illusion:hidden door', 'lock2:armory door (Bash or Knock)',
            'hedge:hedge wall', 'grey:no way in'],
    rooms=[
        ('barracks', 0.5, 9.5, 5.6), ('(armed man)', 0.5, 5.5, 4.2), ('ARMORY', 2.1, 14.5, 4.8), ('KITCHEN', 7.0, 14.5, 4.8),
        ('RECORDS', 10.0, 14.5, 4.8), ('SCRIBES', 12.4, 14.5, 4.8, '#7a6d5c', True), ('hedge maze', 8.5, 6.0, 6.5, '#3f7f3a', True),
    ],
    markers=[
        ('1', 2.5, 5, 'fight'), ('2', 1, 5, 'fight', dict(dy=-5)), ('3', 1, 9, 'fight', dict(dy=-4)), ('4', 3, 14.5, 'loot', dict(dy=-1)),
        ('5', 6, 14.5, 'hint', dict(dy=2)), ('6', 9, 14.5, 'hint'), ('7', 14, 14.5, 'fight', dict(dy=-1)), ('P', 3, 2, 'fight'),
    ],
    diamonds=[('a', 0, 8, 'loot'), ('b', 15, 14.5, 'loot', dict(dy=-1))],
    glance=('<b>ARRIVE</b> at (0,3), (0,4) or (0,11) from the North-West quarter, or at (4,15), (11,15) or (12,15) from the South-East quarter (the maze). <b>EXITS</b> are those six door gaps '
            '(west to the North-West quarter, south to the South-East quarter); the north and east edges are solid. '
            'It is where you learn the guards\' password <b>HARASH</b> and the gate word <b>RHODIA</b> (3, 5) and where City Hall\'s case against '
            '<b>Cadorna</b> is found (7). Nothing roams until an <b>alarm</b> rings (P).'),
    entries=[
        ('P', 'fight', 'Alarm and patrols',
         'As in the North-West quarter: no random encounters until an alarm starts (a fight, a slammed door, running away); it lasts one game hour; then 1 step in 21 '
         '(1 in 3 searching) meets <b>1 Fighter + 5 Hill Giants</b> (quiet cells halve that, safe cells never). In disguise: ' + tag('hint', 'HAUGHTY or ABUSIVE') +
         ' = "on whose authority?" (<b>TYRANTHRAXUS</b>), ' + tag('hint', 'MEEK') + ' = "today\'s password?" (<b>HARASH</b>), SLY or NICE = they attack. '
         'Undisguised or after robbing the Temple of Bane in the Castle Yard: they attack at once; the disguise is dropped if you robbed it.'),
        ('1', 'fight', 'Street door (5,2)-(5,3)  ' + tag('fight', 'FIGHT'),
         'It happens every time until the fight has been fought once, ever. Alarm up or no disguise: the door slams, the alarm rings, then <b>4 Fire Giants</b> charge out '
         '(fight or flee). In disguise a fighter steps out and parleys (SLY or NICE: he flees yelling, alarm, giants); a failed bluff gives STAY AND FIGHT: '
         '<b>1 Fighter + 4 Fire Giants</b> at once, then a patrol rounds the corner. No loot.'),
        ('2', 'fight', 'Guardroom (5,1)', '"An armed man immediately attacks": 1 Fighter, alarm. Once, and shared with 1 (fight here and the street door is quiet).'),
        ('3', 'fight', 'Barracks (9,1)  ' + tag('hint', 'PASSWORDS'),
         '"A pigsty": 4 Fire Giants, until you have the papers or they are dead. ADVANCE to PARLEY: ' + tag('hint', 'HAUGHTY or SLY') + ' and they hand over "the paper with the passwords" '
         '(free: <b>HARASH</b> and the gate word <b>RHODIA</b>); NICE or MEEK: "get lost, wimp" (STAY = fight, or LEAVE); ABUSIVE = fight. Undisguised with the alarm up they attack. No loot.'),
        ('a', 'loot', 'Barracks floor (8,0)', tag('loot', 'SEARCH') + ' (S key) once the four giants are dead and you lack the papers: "a piece of paper": the same two passwords.'),
        ('4', 'loot', 'Armory (14,2)-(15,3)', 'Locked (Bash or Knock; it cannot be picked). Safe room. ' + tag('loot', 'Take anything:') +
         ' 58 plain items (shield, plate to leather armor, bows, crossbows, swords, axes, polearms, ammunition); the prompt repeats until you say no.'),
        ('5', 'hint', 'Kitchen (14,5)-(15,7)',
         'Slaves and a gnoll overseer. <b>KILL THE OVERSEER AND FREE THE SLAVES</b> (no combat): a slave gives you the paper with the <b>gate password</b> and says '
         '"the maze is deadly" (once for good). TALK: a threat, then boiling oil (2d6, one member) on every repeat. GO BACK OUTSIDE: you are pushed back (alarm if undisguised).'),
        ('6', 'hint', 'Records (14,9)-(15,10)',
         'READ THE RECORDS: one session shows three pieces in a row: the Red Wizards of Thay are allied to Tyranthraxus; his plan to conquer "all lands south of the Moonsea"; '
         'then "clear the area first". Each page read risks an interruption: alarm up, 1 in 2 a patrol; before hour 18, 3 in 20 a scribe walks in (RUN, or AMBUSH him, no alarm; '
         'if he sees you first he flees and the alarm rings).'),
        ('7', 'fight', 'Scribes\' office (14,12)-(15,15), (13,14)-(13,15)  ' + tag('hint', 'EVIDENCE'),
         'Hour 18 or later, or the alarm up: empty. Otherwise 6 scribes and 2 officers (2 Envoys). Disguised parley as in P; any other outcome is a fight (alarm 1 in 5). '
         'Once the officers are dead: ' + tag('loot', 'b: SEARCH') + ' the office (S key): each step 1 in 10 each of "hard evidence that Cadorna has been using you and seeks the Pool for himself" '
         '(the proof City Hall is waiting for), a Raven Clan report, and Tyranthraxus\' "flaming aura" note.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Hill Giant', '9', '4', '41', 'Fire Giant', '12', '3', '59'],
              ['6th Lvl Fighter', '6', '2', '45', 'Envoy', '6', '2', '45']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files. Counts are the set-fight ones.'),
    boxes=[
        '<b>PASSWORDS</b> Barracks (3) or its floor paper (a) give both rune papers; the kitchen slave (5) only the gate word. They match HARASH and RHODIA in length and letter pattern (inferred, not confirmed in play). '
        'Cadorna (South-East quarter) also hands over the gate slip once freed.',
        '<b>GREY</b> (7,5) and the 4x4 block (0,12)-(3,15) have no way in on foot and no events. <b>BEWARE</b> Permanent progress (the street fight, passwords, records read, evidence) stays for the whole game; "once per visit" events reset when you re-enter. '
        'Once you are inside the maze (past the gate in the NW or SE quarter) the same squares mean something else: (5,2)-(5,3) a mage, (9,1) three Hill Giants, (8,0) stairs up when facing east; '
        '<b>(6,10)</b> is a teleport pad there but here runs the kitchen scene.',
    ],
)
