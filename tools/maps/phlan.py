"""New Phlan, the starting town: GEO3 block 0, ECL3 block 0 (tile set 3). Read from the area script
(see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='phlan',
    title='NEW PHLAN',
    subtitle=('The starting town: harbor, temples, shops, City Hall', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Read from the game files: area map GEO3 block 0, event script ECL3 block 0,',
                 'monsters MON3CHA. Grid: columns A-P, rows 1-16, north is up.'),
    geo=('GEO3', 0),
    start=(1, 15),
    exits=[(4, 0, 'W')],
    locked_rules={(0, 9), (4, 7), (26, 11)},
    legend=['arrival', 'exit', 'door', 'locked:locked after dark (never break in)', 'grey:sea / not walkable'],
    rooms=[
        ('TRAINING HALL', 2.0, 8.5, 5.2),
    ],
    markers=[
        ('2', 1, 11, 'hint'), ('3', 5, 10, 'place', dict(dy=2)), ('4', 2, 1, 'place'), ('5', 12, 1, 'place', dict(dy=-3)),
        ('6', 1, 7, 'place', dict(dy=3)), ('7', 4, 4, 'place'), ('8', 4, 0, 'hint', dict(dx=4)),
        ('9', 13, 4, 'place', dict(dy=6)), ('9', 13, 6, 'place', dict(dy=6)), ('9', 14, 1, 'place'),
        ('G', 8, 15, 'loot'), ('G', 10, 9, 'loot'), ('G', 10, 12, 'loot'), ('G', 11, 11, 'loot'),
        ('A', 8, 13, 'loot'), ('A', 11, 8, 'loot'), ('A', 12, 11, 'loot'), ('A', 13, 8, 'loot'),
        ('J', 10, 8, 'loot'), ('V', 10, 11, 'loot'), ('V', 13, 10, 'loot'),
        ('T', 8, 10, 'fight'), ('T', 9, 8, 'fight'), ('T', 10, 14, 'fight', dict(dx=12)), ('T', 13, 15, 'fight'),
    ],
    glance=('<b>START:</b> the passenger dock at P2, facing west. On your first visit guide <b>Rolf</b> walks you on a 34-step tour '
            '(Tyr temple, training halls, City Hall, Sune temple, west gate) and then leaves you on your own. '
            '<b>FIRST STOPS:</b> the City Hall clerk (7) for commissions, the Training Hall (6) to level up, an inn (9) to rest. '
            '<b>LEAVING:</b> the west gate (8, A5) leads out to the slums; boats leave from P2.'),
    entries=[
        ('2', 'hint', 'Harbor master (L2) and the boat (P2)',
         'Face north at L2. Passage is 1 platinum for the round trip (one member pays); then board at the dock end, P2. '
         + tag('hint', 'Until Sokal Keep is cleared the only boat out is to Sokal Keep') + '; afterwards boats to the west, east and the bay open too.'),
        ('3', 'place', 'Temple of Tyr (door K6; priests L4, I5, I7)',
         'Healing. Guards bar Bishop Braccio at first: ' + tag('fight', 'FORCE YOUR WAY PAST means a City Watch fight') + ', do not. '
         'Once you have collected the Sokal Keep reward the clerk summons you here: the bishop introduces <b>Dirten</b>, priest of Ilmar, '
         'to cleanse the Temple of Bane across the river (keep its hidden treasure). Dirten joins only if your party has room (under 8).'),
        ('4', 'place', 'Temple of Sune (B2, D2, B4)', 'Priestess Joy of Sune heals for a fee.'),
        ('5', 'place', 'Temple of Tempus (A13, C13)',
         'Heals. If the watch is angry with you the Tempus guards attack instead: 12 clerics + 20 fighters + 20 fighters. Avoid.'),
        ('6', 'place', 'Training Hall (F1-J3; doors G2-G3 and J1)', 'Both doors lead to the training school (separate script): level up, classes split by wing.'),
        ('7', 'place', 'City Hall (E5) and the proclamations (E4, D5, F5)',
         'The clerk pays rewards and hands out commissions: slums, Sokal Keep (reward 250 platinum + 3 jewelry), Podal Plaza and more. '
         'Outside, the proclamations add numbered entries to your journal as you progress. '
         + tag('hint', 'Skullcrusher') + ' (freed in Cadorna Textile House) leaves your party at E4-F5: "I must go to my master now".'),
        ('8', 'hint', 'West gate (A5)',
         'Gateway to the unsettled areas (the slums). Carrying Cadorna\'s treasure, the watch takes it here (and at L3): the reward waits with the clerk.'),
        ('9', 'place', 'Inns (E13-E14, G13-G14, A15-C15)',
         '1 platinum to rest (one member pays): the safe place to heal and memorize. Camping in the open street can bring "the City Watch roust you": '
         + tag('hint', 'answer GO') + ', STAY is a fight.'),
        ('G', 'loot', 'Shops (G, A, J, V on the map)',
         tag('loot', 'G') + ' general store (P9, J11-J12, M11, L12). ' + tag('loot', 'A') + ' arms and armor (N9, I12, L13, I14-J14). '
         + tag('loot', 'J') + ' jeweler (I11). ' + tag('loot', 'V') + ' silver shop (L11, K14). Step into a marked cell and answer yes.'),
        ('T', 'fight', 'Taverns (K9, I10, O11-P11, P13-P15)',
         'Tales (22 different) and a top-spin game, house limit 1000 pp: green 20% pays double, blue 50% returns the stake, red 30% loses it. '
         'About 1 visit in 10 a pickpocket strikes; ' + tag('fight', 'GRAB starts a drunken brawl') + ' (four mobs of 11-13 toughs, scaled to your party) '
         'and then the City Watch charges: STAY is about 38 watchmen, RUN is the answer.'),
        ('!', 'fight', 'Do not provoke the watch',
         'A locked door (red), the bishop\'s guards, a tavern brawl, or a Mad Man in your party all end with the City Watch: '
         '2 level 3 MU, 12 6th-level fighters, 12 aides, 12 nomads. Afterwards shops, temples and inns refuse you until the clerk next pays you a reward. '
         'A <b>Mad Man</b> NPC in the party turns on you about 1 step in 20 here: the priests of Tyr offer to take him in.'),
    ],
    table=dict(
        rows=[['If it comes to a fight', 'No.', 'Lvl', 'AC', 'HP'],
              ['City Watch: Level 3 MU', '2', '3', '9', '9'], ['City Watch: 6th Lvl Fighter', '12', '6', '2', '45'],
              ['City Watch: Aides', '12', '3', '8', '18'], ['City Watch: Nomad', '12', '1', '6', '6'],
              ['Tempus guard: 7th Lvl Cleric', '12', '7', '8', '42'], ['Tempus guard: 4th Lvl Fighter', '20', '4', '8', '30'],
              ['Tempus guard: 8th Lvl Fighter', '20', '8', '6', '87']],
        widths=[132, 24, 24, 24, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON3CHA).'),
    boxes=[
        '<b>HEAL</b> Tyr (L4, I5, I7), Sune (B2, D2, B4), Tempus (A13, C13).  <b>REST</b> any inn, 1 pp, safe.  '
        '<b>TRAIN</b> the Training Hall.  <b>QUESTS</b> the City Hall clerk: finish a commission, report back, collect.',
        '<b>AFTER DARK</b> many doors are locked (red on the map): the script asks "break in?" and yes brings the watch. Answer no and come back by day.',
    ],
)
