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
    source_note=('Read from the game files: area map GEO5 block 3, event scripts ECL5 blocks 3 and 5,',
                 'monsters MON5CHA, loot ITEM5. Grid: columns A-P, rows 1-16, north is up.'),
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
    glance=('<b>ARRIVE</b> at D16, E16 or L16 from the SW quarter (ECL5 block 6), or at P4, P5, P12 from the NE quarter (ECL5 block 4). '
            '<b>EXITS</b> are those same six door gaps (P12 and its block are reached from the NE quarter); the north and west edges are solid. <b>ONE CASTLE, FOUR MAPS:</b> NW = GEO5/3 (this page), NE = /4, '
            'SE = /5, SW = /6; this script (ECL5/3) runs the NW and SE maps. Nothing roams until an <b>alarm</b> rings (P). '
            'Three words matter: <b>HARASH</b> (today\'s password), <b>TYRANTHRAXUS</b> ("on whose authority"), <b>RHODIA</b> (the gate, 7).'),
    entries=[
        ('P', 'fight', 'Alarm and patrols',
         'No random encounters at all until an alarm starts: a scripted fight, a door slammed on you, running from a fight, a failed bluff. '
         'It then lasts one game hour (until the clock shows the same minute an hour later). While it rings each step meets a patrol with 1 chance in 21 '
         '(1 in 3 when searching; quiet cells halve that, safe cells never): <b>1 Fighter + 5 Hill Giants</b>. In disguise (the clothes the woman gives you in the '
         'SW quarter) they ask "what are you doing here?": ' + tag('hint', 'HAUGHTY or ABUSIVE') + ' = "on whose authority?" (type <b>TYRANTHRAXUS</b>); '
         + tag('hint', 'MEEK') + ' = "today\'s password?" (type <b>HARASH</b>); SLY or NICE = they attack. Success: "you are left alone". Undisguised, or if you robbed the SW '
         'temple, they just attack ("THAT\'S THEM!"). Running from any scripted fight rings the alarm, strips the disguise and pushes you back a cell.'),
        ('1', 'fight', 'The guardroom (F1-G2) and its street door (F3-F5)',
         'F3, F4 and F5 (inside the hidden room E5-F7, door F5|G5) trigger on every step until a fight has happened this visit. Alarm up or no disguise: "the door of the building slams" and the alarm rings. '
         'In disguise: a fighter steps out; parley as above (SLY or NICE: he flees yelling and rings the alarm), failing sends you to STAY AND FIGHT (1 Fighter, then a '
         'patrol rounds the corner) or RUN. <b>F2</b>: "an armed man immediately attacks" (1 Fighter, rings the alarm; the same once-per-visit flag). No loot.'),
        ('2', 'place', 'Hall (H1-K2)', 'Long tables, a hearth, rats picking at garbage. Text only, once.'),
        ('3', 'fight', 'Apartment (A3-B4)',
         'First step on <b>B4</b>: two Hill Giants lumber up. Parley works with <i>any</i> attitude ("OH... OKAY", they leave); fighting gives no loot. Flag shared with N16, O16. '
         + tag('loot', 'a: SEARCH at A3') + ' (S key): a loose stone hides <b>200 gold + a Potion of Speed</b>, one yes/no prompt, once.'),
        ('4', 'place', 'Latrine (A6-B6)', '"The lack of bad smell gives you a general idea of the sanitation." Text only.'),
        ('5', 'fight', 'Dormitory (A7-B9)',
         'A bucket of sand is propped over the door: 1d4 to one member (searching, S key, you spot it and kick it down harmlessly). Sleeping giants: if you surprise them, '
         'SNEAK OUT or ATTACK AS THEY SLEEP; otherwise they charge. <b>4 Fire Giants</b> before hour 14, 2 after. ' + tag('loot', 'Loot 300 gold') +
         '. Once (flag shared with M12).'),
        ('6', 'fight', 'Room C14-C15',
         '<b>C14</b>, only before hour 14: 8 Hill Giants "putting on their armor" or "struggling out of bed" (if you surprise them). Once, no loot. '
         + tag('loot', 'b: SEARCH at C15') + ': <b>11 gold</b>, once.'),
        ('7', 'hint', 'Gate (D8-D9 | E8-E9), locked',
         'Facing east on D8 or D9: "A DEEP VOICE: WHAT IS THE PASSWORD?" GIVE THE PASSWORD (type <b>RHODIA</b>; a wrong word costs nothing) or FORCE THE GATE: alarm, '
         + tag('fight', '12 boulders of 2d6') + ' on random members (about 80 HP in all), and from then on <b>this side of the gate answers only with boulders</b> (flag, permanent). '
         'If you stole from the SW temple, boulders at once. If Cadorna travels with you (SE quarter) he hands you the slip with the gate word. '
         'Beyond, E8-E9 hands you to the maze script (ECL5/5).'),
        ('8', 'fight', 'East block (L10-P16, entered at P12)',
         'Same events as the west: <b>M12</b> is the bucket door of the giants room below it (the dormitory fight and its 300 gold, one shared flag: only one of the two can ever happen), '
         '<b>N16, O16</b> the apartment (two Hill Giants, same flag as B4).'),
        ('M', 'hint', 'Beyond the gate: the maze script (ECL5 block 5)',
         'Stepping on E8 or E9 switches scripts. Walls with id 7 or 9 (green) are hedges: facing one asks CUT THROUGH? and one random member must save or take 201 damage (poisonous thorns). '
         'Roaming packs become 4 Giant Snakes. Cells change meaning: F3-F5 a captured mage (notes: journal entry 30), H1-K2 3 Hill Giants (only SLY, NICE or MEEK plus <b>TYRANTHRAXUS</b> '
         'gets past them), A6-B6 a ruined tower with 8 Trolls, <b>M12</b> a teleport pad; an event-4 cell (B4, N16, O16) facing east is the stairs up (ECL5/7). Stepping on D8 or D9 hands you back to this script. The SE page covers the rest.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Hill Giant', '9', '4', '41', 'Fire Giant', '12', '3', '59'],
              ['6th Lvl Fighter', '6', '2', '45', '', '', '', '']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON5CHA). Group sizes may scale; these are the scripted counts.'),
    boxes=[
        '<b>PASSWORDS</b> <b>HARASH</b> (guards\' "today\'s password"), <b>TYRANTHRAXUS</b> (their "authority"), <b>RHODIA</b> (the gates). Learned from the paper in the NE barracks or on the '
        'barracks floor, the slave freed in the NE kitchen, or Cadorna (SE quarter). The rune tiles on those papers match HARASH and RHODIA in length and letter pattern (inferred; those are the words the script compares with).',
        '<b>CLOCK AND FLAGS</b> The script tests the clock hour against 14 (giants, number of fire giants). Alarm, passwords and quest flags persist; "once per visit" flags reset when you re-enter. '
        'Grey cells (E11, F7, P16) have no way in on foot.',
    ],
)
