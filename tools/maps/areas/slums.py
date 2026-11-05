"""The slums west of New Phlan: GEO2 block 20, ECL2 block 20 (tile set 2). Read from the area script
(see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='slums',
    title='THE SLUMS',
    subtitle=('Monster-crawling streets west of New Phlan', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Read from the game files: area map GEO2 block 20, event script ECL2 block 20,',
                 'monsters MON2CHA, loot ITEM2. Grid: columns A-P, rows 1-16, north is up.'),
    geo=('GEO2', 20),
    start=(4, 15),
    exits=[(4, 15, 'E'), (4, 0, 'W'), (11, 0, 'W')],
    hatch_events={0: ('#f3d9d3', '#d89b90'), 18: ('#f6e3c6', '#d9ae6b')},
    legend=['arrival', 'exit', 'search', 'door', 'lock2:locked door (Bash / Pick / Knock)',
            'hatch:street encounters', 'hatch:Rope Guild encounters'],
    rooms=[
        ('HEMP MARKET', 9.1, 2, 5.0), ('OLD ROPE GUILD', 11.4, 10.5, 6.5, '#9a6b2f', True),
        ('(dirty room)', 4.3, 5.5, 4.4), ('(storage)', 1.0, 3, 4.2),
    ],
    markers=[
        ('1', 0.5, 12.5, 'fight'), ('2', 0.5, 9.5, 'fight'), ('3', 0.5, 7.5, 'fight'),
        ('4', 9.5, 12, 'hint'), ('5', 2, 5.5, 'loot', dict(dy=-3)), ('7', 8, 2, 'hint', dict(dy=-6)),
        ('8', 5, 3, 'hint'), ('9', 3, 2.5, 'fight'), ('10', 2.5, 0, 'fight', dict(dx=2)), ('12', 0, 0, 'loot'),
        ('13', 6, 0, 'fight'), ('14', 5, 1, 'fight'), ('15', 10.5, 3, 'fight'), ('16', 10, 4.5, 'loot', dict(dy=5)),
        ('19', 12, 15, 'hint'), ('20', 14, 0, 'fight'), ('P', 5, 8, 'fight'), ('R', 14, 4, 'fight'),
    ],
    diamonds=[('a', 2, 5, 'loot', dict(dx=4, dy=5)), ('b', 3, 0, 'loot', dict(dx=3)), ('c', 10, 5, 'loot', dict(dx=3, dy=-5))],
    glance=('<b>ARRIVE</b> at P5 from Phlan\'s west gate. <b>EXITS:</b> the east edge (P5) returns to Phlan; the two west doors (A5, A12) lead on to '
            'Kuto\'s Well. <b>CLEARING:</b> every won fight, scripted or random, counts; at 25 the slums are cleared, the streets go quiet and the '
            'City Hall clerk pays <b>250 gold + 50 platinum + 1 jewelry</b>. Orange doors are locked. '
            'Group sizes scale with your party; the figures below are the scripted ones.'),
    entries=[
        ('P', 'fight', 'Street encounters (red hatch)',
         'Each step on street ground: about 1 chance in 14 of a pack of kobolds, goblins or orcs with 3-4 leaders (a bugbear too if you are strong). '
         'Searching (S key) makes it about 1 in 3. Parley: your attitude plus a d30 decides: low, they attack; middling, they demand payment; '
         'higher, they tell you to leave; top, a tip ("stay away from the Textile House, the undead are going crazy up there"). '
         'ABUSIVE scores highest. ' + tag('fight', 'PAY') + ' costs half of everyone\'s money and may cost items; SURRENDER takes all of it. '
         'After about 15 street fights the streets stay quiet.'),
        ('R', 'fight', 'Old Rope Guild (orange hatch, rows 12-16)',
         '"Most who venture into its twisty halls never return." Same random packs, about 1 step in 5 (more when searching).'),
        ('1', 'fight', 'Orcs arguing over papers (L1-N2)', '4 Orcs.'),
        ('2', 'fight', 'Goblin school (J1-K2)', 'A goblin drills his young: 8 Goblin Guards + 1 Goblin Leader.'),
        ('3', 'fight', 'Feeding kobolds (H1-I2)', '15 Kobolds + 1 Kobold Leader.'),
        ('4', 'hint', "Ohlo's study (L10-N11)", tag('hint', 'Commission:') + ' be NICE or MEEK (HAUGHTY and ABUSIVE make him attack: 36 foes, 25 of them hobgoblins). '
         'He wants a potion from a booth in the Rope Guild: say <b>OHLO</b> there (19), bring it back, GIVE it: '
         + tag('loot', '150 platinum + 1 jewelry + a treasure roll') + '. Return empty handed and he dismisses you.'),
        ('5', 'loot', 'Stable (F3-G3)', 'Dirty stable. ' + tag('loot', 'a: SEARCH') + ': a long leather bag, 100 gp, 2 gems, Short Bow +1, 20 Arrows +1.'),
        ('7', 'hint', 'Old hemp market (B8-D10)',
         'Overheard rumors, one per visit: the gang works from the catacombs by the well; the Temple over the river is run by a hot-shot orc; '
         + tag('secret', '"a secret treasure room in the NW corner"') + ' (12).'),
        ('8', 'hint', 'Fortune teller (D6)',
         'Pay a few coppers for a fortune (flavor). ' + tag('fight', 'Do not ATTACK her') + ': the gods note it and every encounter chance rises sharply.'),
        ('9', 'fight', 'Orc lair (C4-D4)', '"How dare you break into our home?" 24 Orcs (4 of them leaders).'),
        ('10', 'fight', 'Hobgoblins and their gold (A3-A4)', '5 Hobgoblins. ' + tag('loot', 'b: SEARCH') + ' afterwards: 500 gp, 50 pp, Short Bow +1, Ring +1.'),
        ('12', 'secret', 'Treasure room (A1)',
         'Walk in from B1. Reach it through the locked door north of C2 (Bash, Pick or Knock). '
         + tag('loot', '1000 electrum, 92 gp, 50 pp, 4 gems, 2 jewelry, Short Bow +1, 20 Arrows +1') + ', taken automatically.'),
        ('13', 'fight', 'Guards (A6-A8)', '30 Orcs + 4 Orc Leaders.'),
        ('14', 'fight', 'Monster leaders (B6)', '1 Ogre, 2 Gnolls, 2 Hobgoblin Leaders.'),
        ('15', 'fight', 'Alerted guards (D11-D12)', '12 Goblin Guards + 21 Goblin Leaders.'),
        ('16', 'loot', 'Large empty room (E10-F12)',
         tag('loot', 'c: SEARCH') + ' (S key): a loose floorboard hides a chest: 200 pp, 2 gems, a magic-user scroll (1 spell), Shield +1.'),
        ('19', 'hint', 'Booth (P13)', 'The shopkeeper has "nothing to sell". SPEAK and type OHLO: he fetches the potion. ATTACK brings 15 Hobgoblins + 4 Leaders.'),
        ('20', 'fight', 'Grain tossers (A15)', 'Monsters throwing a sack of grain: 2 Ogres + 4 Trolls. Loot: 30 gp, 50 pp, 1 jewelry, 3 treasure rolls.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Kobold', '0', '7', '3', 'Hobgoblin', '2', '5', '6'], ['Kobold Leader', '0', '7', '4', 'Gnoll', '2', '5', '10'],
              ['Goblin Guard', '0', '7', '4', 'Bugbear', '4', '5', '16'], ['Goblin Leader', '0', '5', '7', 'Ogre', '5', '5', '21'],
              ['Orc', '1', '6', '5', 'Troll', '7', '4', '36'], ['Orc Leader', '1', '5', '8', 'Level 3 MU', '3', '9', '9']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON2CHA).'),
    boxes=[
        '<b>PASSWORD</b> <b>OHLO</b> at the booth (19). <b>LOCKS</b> B bash, P pick (thieves), K knock (spell). '
        '<b>SEARCH SPOTS</b> a stable bag (5), b hobgoblin gold (10, after the fight), c floorboard chest (16): press S to search.',
        '<b>ORDER</b> Ohlo (4) first for the commission; kill the scripted packs one by one (each counts toward 25); loot a, b, c; '
        'rumor 7 and the locked door lead to the NW treasure room (12); then the booth (19) and back to Ohlo; report to City Hall.',
        '<b>TEXT ONLY</b> dirty room F4-G5, storage room D2, "just north of the Rope Guild entry" G11. Other unmarked rooms (NW, centre) have no script.',
    ],
)
