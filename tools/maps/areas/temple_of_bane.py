"""Temple of Bane: GEO1 block 24, ECL1 block 24 (tile set 1). The same script also runs the orc mansion map
(GEO1 block 31, areas/orc_mansion.py): its init entry loads map 24 or 31 by the area number in [49C5]. Read from the
area script (see tools/maps/README.md for how each statement was checked). The title is the City Hall clerk's
("the Temple of Bane", ECL3 block 8) and the in-script texts."""
from mapkit import tag

SPEC = dict(
    name='temple-of-bane',
    title='TEMPLE OF BANE',
    subtitle=('Orc-held temple across the river', 'Pool of Radiance (SSI, DOS)  |  annotated map  |  SPOILERS'),
    source_note=('Game files: GEO1 block 24, script ECL1 block 24, MON1CHA, ITEM1;',
                 'quest text ECL3 blocks 0, 8. Grid: columns A-P, rows 1-16, north is up.'),
    geo=('GEO1', 24),
    start=(4, 15),
    exits=[(4, 15, 'E'), (11, 15, 'E')],
    hatch_events={0: ('#f3d9d3', '#d89b90')},
    legend=['arrival', 'exit', 'search', 'door', 'hatch:outside the temple: random encounters'],
    rooms=[('NAVE', 7.5, 7.5, 9.0, '#7a6d5c', True), ('(no encounters inside)', 8.6, 7.5, 5.0)],
    markers=[
        ('1', 7.5, 2, 'fight'), ('2', 7.5, 3, 'place'), ('3', 7.5, 14, 'fight'), ('P', 1.5, 9, 'fight'),
    ],
    diamonds=[('a', 5, 5, 'loot'), ('b', 12, 9, 'loot'), ('c', 9, 12, 'loot')],
    glance=('<b>ARRIVE</b> on P5 facing west (the south entrance of the city\'s east edge, ECL7 block 26); from the east gaps of ECL3 block 14 you land on A5 or A12. '
            '<b>EXITS:</b> only the two east gaps (P5, P12), which lead into the orc mansion map (A5, A12 there); the way back to the city is through it. '
            '<b>QUEST:</b> Bishop Braccio sends you with Dirten, priest of Ilmater, to retake the temple "desecrated to Bane"; the City Hall clerk says you may keep '
            'all you found in it. Kill <b>High Priest Mace</b> and his horde (M). No passwords, no locked doors. The same script runs the mansion map, so flags are shared.'),
    entries=[
        ('P', 'fight', 'Outside the temple (red hatch, event 0)',
         'Each step: 3 in 60 (10 in 60 when searching, S key) meets a pack, unless Mace is dead <i>and</i> the mansion ambush is won. '
         '4 in 10 a <b>black-hand patrol</b> (below), 2 in 10 other orcs, 2 in 10 goblins, 1 in 10 hobgoblins, 1 in 10 ogres; size scales with your party; surprise is rolled. '
         'PARLEY: attitude (ABUSIVE 60; HAUGHTY, SLY, NICE 30; MEEK 5) + d30 + your charisma bonus + pack bonus (goblins 20, orcs and hobgoblins 10, ogres 0): '
         '140+ they run away, 75-139 they tell you to keep out and leave, less they attack. Camping: "suddenly attacked by orcs" (10 Orcs); the camp odds drop only after '
         'Mace is dead and the mansion ambush is won.'),
        ('O', 'fight', 'The black-hand patrol',
         'Four Orcs "whose shields bear a black hand on a red field". Never forced: FLEE or PARLEY (any attitude; threats work too) end it peacefully; so does beating it. Any of the three marks you as '
         '"let through" (the gate guards step aside; the mansion ambush grows from 10 to 20 Orcs). COMBAT: ' + tag('loot', 'victory brings 6 Leather Holy Symbols of Bane') +
         ' (item type 74), the pass the gate guards check for.'),
        ('1', 'fight', 'Temple doors and guards (C8-C9)',
         'First step here, Mace alive: "an old blind decrepit orc stands outside with eight orc guards". If you have met a patrol (flag): "as you approach they move, allowing you entrance". '
         'Else LET HIM TOUCH YOU: with a holy symbol "Welcome to the Temple of Bane"; without: "Guards, in the name of Bane, kill these unbelievers!" '
         'BACK OFF first (then LET HIM CHECK, BACK OFF AGAIN = attack, ATTACK). The fight is 8 Orcs, no loot; win it and you may enter.'),
        ('2', 'place', 'Inside the nave (D8-D9 and the cross-shaped hall)',
         'Stepping on D8 or D9 marks you "inside"; coming back out onto C8 or C9 while Mace lives triggers his horde (M). The nave has no script and no random encounters. '
         'Grey cells are pillars.'),
        ('3', 'fight', 'Altar (O8-O9)',
         '"An altar smeared with blood and covered with crude black hand prints": DESTROY ALTAR or LEAVE IT. With Mace alive: "the temple doors fly open and a screaming horde of orcs led by a half-orc cleric attack" (M). '
         'With Mace dead: "the uneasy feeling leaves you". Once per visit.'),
        ('M', 'fight', 'High Priest Mace and his horde',
         '5 Orc Leaders + <b>MACE</b> (the half-orc cleric, level 5) + 50 Orcs = 56. Triggered once, three ways: (1) leaving by the front doors after entering, '
         '("kill the unbelieving toads"); (2) destroying the altar (3); (3) opening the <b>third trapdoor</b> (a, b, c), "scum who would steal from our temple". '
         'Fleeing puts you back on your previous cell. Win: a paper on Mace\'s body (journal entry 25); if Dirten is in the party he thanks you "for helping us regain our temple" '
         'and stays.'),
        ('T', 'loot', 'Trapdoors in the nave (search spots, S key only)',
         'Each step in search mode every active member rolls: 1 in 6, elves and half-elves 2 in 6 (race field, inferred), to find it. OPEN TRAPDOOR gives '
         + tag('loot', 'a F6: a Magic User scroll and 2 Clerical scrolls; b J13: a Woods Holy Symbol, a 7 Gold Statuette lot, Dust, a Wand, 3 Potions; c M10: 8 weapons, all +1') +
         ' (short sword, spear, scimitar, morning star, mace, hammer, dagger, hand axe).'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Goblin Guard', '0', '7', '4', 'Hobgoblin', '2', '5', '6'], ['Goblin Leader', '0', '5', '7', 'Ogre', '5', '5', '21'],
              ['Orc', '1', '6', '5', 'Ogre Leader', '7', '3', '32'], ['Orc Leader', '1', '5', '8', 'MACE', '5', '10', '25']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON1CHA).'),
    boxes=[
        '<b>PASSWORDS</b> none. <b>LOCKS</b> none. <b>SEARCH SPOTS</b> a F6, b J13, c M10 (press S before stepping on them). '
        '<b>FLAGS</b> kept between visits: the gate-guard pass, which trapdoors you opened, Mace dead; things like "inside" reset when you re-land.',
        '<b>ORDER</b> Get a Bane holy symbol first (kill a black-hand patrol outside, or the recruiter in Podal Plaza) or fight the 8 gate guards; '
        'take Dirten in; kill Mace on your terms (altar) before opening the third trapdoor, then search a, b, c at leisure; '
        'only the orc mansion (next map east) has the hay beds, cell and the rest of the orcs.',
    ],
)
