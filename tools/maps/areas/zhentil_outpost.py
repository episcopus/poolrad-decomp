"""The Zhentil Outpost: GEO6 block 28, ECL6 block 28 (tile set 6). Read from the area script
(see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='zhentil-outpost',
    title='ZHENTIL OUTPOST',
    subtitle=('Walled garrison in the wilderness: envoys are welcomed, then betrayed', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    geo=('GEO6', 28),
    start=(0, 7),
    exits=[(0, 7, 'N'), (0, 8, 'N')],
    legend=['arrival', 'exit', 'door', 'grey:inside the inner wall (no gate)'],
    rooms=[
        ('QUARTERS', 0.95, 5.5, 4.6), ('CENTRAL KEEP', 10.9, 7.5, 5.6, '#6d6256', True), ('inner wall', 5.1, 7.5, 4.6, '#6d6256'),
    ],
    markers=[
        ('1', 0, 8, 'hint', dict(dx=3)), ('2', 2, 7, 'hint'), ('3', 8, 6, 'place'), ('4', 4, 5, 'place'),
        ('5', 0, 5, 'hint', dict(dx=3, dy=-3)), ('6', 0, 4, 'fight', dict(dx=-2)), ('7', 1, 4, 'fight'),
        ('W', 3, 14, 'secret'), ('W', 7, 1, 'secret'), ('W', 8, 1, 'secret'), ('W', 14, 6, 'secret'),
    ],
    glance=('<b>ARRIVE</b> at the north gate (7,0) facing south. You only get in with City Hall\'s sealed message packet: the game then asks (West Wilderness square (3,32)) '
            '"Are you the diplomatic envoys from New Phlan?" YES / NO (YES: the riders escort you in; without the packet they tell you to leave, and if you stay 12 corporals attack). '
            '<b>EXIT</b> by walking off the north edge at the gate (7,0), (8,0) or by climbing the wall at the four W cells. '
            '<b>THE POINT:</b> it is a trap. After a guided tour and a dinner with the commandant, four guards attack you in your quarters at night; '
            'the alarm goes up and the garrison hunts you until you kill the commandant or leave. There is no treasure here. '
            'Flags reset when you re-land, except the commandant\'s death.'),
    entries=[
        ('1', 'hint', 'Front gate (7,0), (8,0)',
         'First step: "You are being escorted into Zhentil Outpost." and the guided tour (2, 3, 4, 5). Later on the gate cells: if the commandant is dead '
         '"You are near the front gate"; otherwise, once per visit, "The commotion allows you to get to the front gate!" and then a 3 in 4 chance '
         'that 11 guards attack.'),
        ('2', 'hint', 'The tour (guided walk)',
         '(7,0) > (7,2) "a large inner wall around the central keep; this area is busy with men entering and leaving barracks" > (7,5) "you are led toward '
         'the central keep" > (7,7) > (6,8) (3) > (5,4) (4) > (7,2) "one of our fine watch towers... the wall has survived many attacks, including one from a dragon" > (4,2) > (4,0) > (5,0) (5). '
         'The escorts walk you through the inner wall; on foot it has no gate.'),
        ('3', 'place', "Commandant's office / mess (6,8)",
         '"Inside the commandant\'s office. He greets you and you hand him the papers... I hope you will join me for dinner tonight." '
         'Inside the grey area: reachable only by the escorts.'),
        ('4', 'place', 'Barracks (5,4)', '"One of our fine barracks. There are six of these here and each can hold over 100 men." Only text.'),
        ('5', 'hint', 'Your quarters ((5,0), with (4,0))',
         'Stepping on (5,0): "Walk around or relax until dinner?" RELAX: at dusk a guard walks you to dinner (D). Back at (5,0) the game says "It is night": '
         'GO TO SLEEP (one guard hits you for 8d4+8 first) or SLEEP WITH A WATCH (guards burst in about two hours later); either way '
         '4 Aides attack, then 5 Corporals + 6 Aides (win or flee). Win: "an alarm goes off in the distance"; flee: you hide at (3,12) and hear the alarm.'),
        ('D', 'hint', 'Dinner talk (at 3)',
         'Topics (three rounds at most): CITY (new or old Phlan: Bishop Braccio the real power? Tirantikus and Tyranthraxus "are one and the same", a powerful fire demon; '
         'are you having trouble), MAGIC (LIE, or mention the Pool of Radiance: a story, ' + tag('hint', 'journal entry 46') + '), POLITICS (Ulrich Eberhard corrupt?). '
         'Your answers change nothing mechanical; all of them end at the night attack.'),
        ('6', 'fight', 'Guards at the quarters door (4,0)',
         'Before the night and before you have attacked anyone: "Four guards here... you are restricted to your quarters." RETURN (put back at (5,0)), ATTACK, or BRIBE: '
         'the bribe only angers them (GO BACK or ATTACK). Attack: 4 Guards; win: "More guards come running: surrender or attack?" SURRENDER strips every coin and item and tosses you '
         'out; ATTACK: 16 Guards + 4 Corporals, twice. The guards also sound an alarm.'),
        ('7', 'fight', 'Reprisal trigger (4,1)',
         'Once you have attacked the guards (6): stepping on (4,1) brings "a large group of men led by a dwarf": 1 Dwarven Fighter, 10 Aides, 12 Corporals, 25 Guards; '
         'then "led by the commandant": Al-Hyam Dazid, the Commandant, 24 Corporals, 20 Aides. Win: the outpost surrenders or flees; the commandant stays dead '
         '(the patrols and the alarm are over for good). Flee: you run for the gate, 6 guards stop you; escape or be stripped and tossed out.'),
        ('A', 'fight', 'The alarm (every step after it)',
         'From the night fight on, the alarm level is 1 and each step rolls 0 to 14 against the level L: below L, guards come: '
         '5 x L Guards + (L+1) Corporals ("some guards spot you and attack"); L goes up each time; at L = 2 there is only a text; '
         'from L = 7 the dwarf assault (7) comes instead. It stops when the commandant dies, or when you leave (the alarm resets each visit).'),
        ('W', 'secret', 'Climbable wall (14,3), (1,7), (1,8), (6,14)',
         '"The wall is climbable here, will you scale over it?" CLIMB OVER WALL: you leave the outpost and the wilderness remembers it '
         '(the next approach is silent, the one after is hostile).'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Guard', '0', '10', '4', 'Dwarven Fighter', '6', '8', '50'], ['Corporal', '2', '6', '13', 'Al-Hyam Dazid', '7', '9', '22'],
              ['Aides', '3', '8', '18', 'Commandant', '9', '7', '100']],
        widths=[50, 18, 18, 18, 72, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files.'),
    boxes=[
        '<b>WAYS OUT</b> the north gate (7,0), (8,0) and the four wall cells W leave at once; the alarm patrols stop when the commandant dies (7) or when you leave. '
        'There is no loot here.',
        '<b>TEXT ONLY</b> the six barracks and watch towers are only described by the tour; nothing happens in any other room. Note: the outpost is west of New Phlan (City Hall: '
        '"the Zhentil outpost to the west"); "Aides" and "Corporal" are the monster names as stored in the game.',
    ],
)
