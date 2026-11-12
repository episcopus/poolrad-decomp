"""The castle, north-west quarter: GEO5 block 3, ECL5 block 3 (tile set 5). Read from the area scripts
(see tools/maps/README.md for how each statement was checked). The scripts call the place "the castle"
(ECL5 block 7, ECL3 block 8: "an assault on the castle"; ECL3 block 14 hands out journal maps "NW CASTLE" and
"NE CASTLE"). The four GEO5 blocks 3, 4, 5, 6 are the NW, NE, SE and SW quarters of one walled city: their
edge door gaps line up and the edge tables of ECL5 blocks 3, 5 and 6 send you across them."""
from mapkit import tag

SPEC = dict(
    name='castle-nw',
    title='CASTLE NW',
    subtitle=("Tyranthraxus' walled city quarter, held by giants", 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    geo=('GEO5', 3),
    start=(15, 3),
    extra_starts=[(15, 4), (15, 11), (3, 15), (4, 15), (11, 15)],
    exits=[(15, 3, 'S'), (15, 4, 'S'), (15, 11, 'S'), (3, 15, 'E'), (4, 15, 'E'), (11, 15, 'E')],
    illusion_ids={4},
    hedge_ids={7, 9},
    legend=['arrival', 'exit', 'search', 'door', 'illusion:hidden door', 'lock2:gate (password)',
            'hedge:hedge wall', 'grey:no way in'],
    rooms=[
        ('hall', 0.5, 8.5, 6.0), ('(armed man)', 0.5, 5.5, 4.2), ('apartment', 2.0, 1.0, 4.4), ('latrine', 5.0, 1.0, 4.4),
        ('sleeping giants', 7.7, 0.5, 4.0), ('hedge maze', 8.0, 8.0, 6.5, '#3f7f3a', True),
        ('giants room', 13.0, 14.5, 4.6), ('east block', 11.0, 13.0, 4.6),
    ],
    markers=[
        ('1', 2, 5, 'fight', dict(dy=-5)), ('2', 1, 9, 'place', dict(dy=-4)), ('3', 3, 1, 'fight'), ('4', 5, 0, 'place'),
        ('5', 8, 1, 'fight', dict(dy=-4)), ('6', 13, 2, 'fight'), ('7', 7.5, 4, 'hint', dict(dx=-11.5)), ('P', 3, 10, 'fight'),
        ('8', 11, 12, 'fight', dict(dy=-5)),
    ],
    diamonds=[('a', 2, 0, 'loot'), ('b', 14, 2, 'loot')],
    glance=('<b>ARRIVE</b> at (3,15), (4,15) or (11,15) from the Castle Yard (south-west quarter), or at (15,3), (15,4), (15,11) from the North-East quarter. '
            '<b>EXITS</b> are those same six door gaps; the north and west edges are solid. <b>ONE CASTLE, FOUR MAPS:</b> North-West (this page), North-East, '
            'South-East (the maze) and the Castle Yard. Inside the gate (7) the maze rules apply: hedges, tower, throne (M). Nothing roams until an <b>alarm</b> rings (P). '
            'Three words matter: <b>HARASH</b> (today\'s password), <b>TYRANTHRAXUS</b> ("on whose authority"), <b>RHODIA</b> (the gate, 7).'),
    entries=[
        ('P', 'fight', 'Alarm and patrols',
         'No random encounters at all until an alarm starts: a set-piece fight, a door slammed on you, running from a fight, a failed bluff. '
         'It then lasts one game hour (until the clock shows the same minute an hour later). While it rings each step meets a patrol with 1 chance in 21 '
         '(1 in 3 when searching; quiet cells halve that, safe cells never): <b>1 Fighter + 5 Hill Giants</b>. In disguise (the clothes the woman gives you in the '
         'Castle Yard laundry) they ask "what are you doing here?": ' + tag('hint', 'HAUGHTY or ABUSIVE') + ' = "on whose authority?" (type <b>TYRANTHRAXUS</b>); '
         + tag('hint', 'MEEK') + ' = "today\'s password?" (type <b>HARASH</b>); SLY or NICE = they attack. Success: "you are left alone". Undisguised, or if you robbed the Temple of Bane '
         'in the Castle Yard, they just attack ("THAT\'S THEM!"). Running from any set-piece fight rings the alarm, strips the disguise and pushes you back a cell.'),
        ('1', 'fight', 'The guardroom (5,0)-(6,1) and its street door (5,2)-(5,4)',
         '(5,2), (5,3) and (5,4) (inside the hidden room (4,4)-(5,6), door (5,4)|(6,4)) trigger on every step until a fight has happened this visit. Alarm up or no disguise: "the door of the building slams" and the alarm rings. '
         'In disguise: a fighter steps out; parley as above (SLY or NICE: he flees yelling and rings the alarm), failing sends you to STAY AND FIGHT (1 Fighter, then a '
         'patrol rounds the corner) or RUN. <b>(5,1)</b>: "an armed man immediately attacks" (1 Fighter, rings the alarm; the same once-per-visit trigger). No loot.'),
        ('2', 'place', 'Hall (7,0)-(10,1)', 'Long tables, a hearth, rats picking at garbage. Text only, once.'),
        ('3', 'fight', 'Apartment (0,2)-(1,3)',
         'First step on <b>(1,3)</b>: two Hill Giants lumber up. Parley works with <i>any</i> attitude ("OH... OKAY", they leave); fighting gives no loot. Shared with (13,15), (14,15). '
         + tag('loot', 'a: SEARCH at (0,2)') + ' (S key): a loose stone hides <b>200 gold + a Potion of Speed</b>, one yes/no prompt, once.'),
        ('4', 'place', 'Latrine (0,5)-(1,5)', '"The lack of bad smell gives you a general idea of the sanitation." Text only.'),
        ('5', 'fight', 'Dormitory (0,6)-(1,8)',
         'A bucket of sand is propped over the door: 1d4 to one member (searching, S key, you spot it and kick it down harmlessly). Sleeping giants: if you surprise them, '
         'SNEAK OUT or ATTACK AS THEY SLEEP; otherwise they charge. <b>4 Fire Giants</b> before hour 14, 2 after. ' + tag('loot', 'Loot 300 gold') +
         '. Once (shared with (12,11)).'),
        ('6', 'fight', 'Room (2,13)-(2,14)',
         '<b>(2,13)</b>, only before hour 14: 8 Hill Giants "putting on their armor" or "struggling out of bed" (if you surprise them). Once, no loot. '
         + tag('loot', 'b: SEARCH at (2,14)') + ': <b>11 gold</b>, once.'),
        ('7', 'hint', 'Gate ((3,7)-(3,8) | (4,7)-(4,8)), locked',
         'Facing east on (3,7) or (3,8): "A DEEP VOICE: WHAT IS THE PASSWORD?" GIVE THE PASSWORD (type <b>RHODIA</b>; a wrong word costs nothing) or FORCE THE GATE: alarm, '
         + tag('fight', '12 boulders of 2d6') + ' on random members (about 80 HP in all), and from then on <b>this side of the gate answers only with boulders</b> (permanent). '
         'If you stole from the Temple of Bane, boulders at once. If Cadorna travels with you (South-East quarter) he hands you the slip with the gate word. '
         'Beyond, (4,7)-(4,8) puts you inside: the maze rules apply (see M).'),
        ('8', 'fight', 'East block ((11,9)-(15,15), entered at (15,11))',
         'Same events as the west: <b>(12,11)</b> is the bucket door of the giants room below it (the dormitory fight and its 300 gold: only one of the two can ever happen), '
         '<b>(13,15), (14,15)</b> the apartment (two Hill Giants, shared with (1,3)).'),
        ('M', 'hint', 'Beyond the gate: the maze rules',
         'Stepping on (4,7) or (4,8) takes you inside the maze. Green hedge walls: facing one asks CUT THROUGH? and one random member must save or take 201 damage (poisonous thorns). '
         'Roaming packs become 4 Giant Snakes. Squares change meaning: (5,2)-(5,4) a captured mage (notes: journal entry 30), (7,0)-(10,1) 3 Hill Giants (only SLY, NICE or MEEK plus <b>TYRANTHRAXUS</b> '
         'gets past them), (0,5)-(1,5) a ruined tower with 8 Trolls, <b>(12,11)</b> a teleport pad; facing east on (1,3), (13,15) or (14,15) is the stairs up to Tyranthraxus\' Tower. Stepping on (3,7) or (3,8) takes you back outside, where the normal rules return. The South-East page covers the rest.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Hill Giant', '9', '4', '41', 'Fire Giant', '12', '3', '59'],
              ['6th Lvl Fighter', '6', '2', '45', '', '', '', '']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files. Group sizes may scale; these are the set-fight counts.'),
    boxes=[
        '<b>PASSWORDS</b> <b>HARASH</b> (guards\' "today\'s password"), <b>TYRANTHRAXUS</b> (their "authority"), <b>RHODIA</b> (the gates). Learned from the paper in the North-East barracks or on the '
        'barracks floor, the slave freed in the North-East kitchen, or Cadorna (South-East quarter). The runes on those papers match HARASH and RHODIA in length and letter pattern (inferred, not confirmed in play).',
        '<b>CLOCK AND PROGRESS</b> The game checks the clock against hour 14 (giants, number of fire giants). Alarm, passwords and quest progress persist; "once per visit" events reset when you re-enter. '
        'Grey cells (4,10), (5,6), (15,15) have no way in on foot.',
    ],
)
