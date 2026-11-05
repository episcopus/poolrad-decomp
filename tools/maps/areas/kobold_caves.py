"""The kobold caves east of Phlan: GEO8 block 13, ECL8 block 13 (tile set 8). Read from the area script
(see tools/maps/README.md for how each statement was checked). Entered from the wilderness script ECL8 block 27."""
from mapkit import tag

SPEC = dict(
    name='kobold-caves',
    title='KOBOLD CAVES',
    subtitle=('Warren of the ancient kobold king', 'Pool of Radiance (DOS)  |  area map  |  SPOILERS'),
    source_note=('Game files: GEO8 block 13, ECL8 block 13, MON8CHA, ITEM8.',
                 'Grid: columns A-P, rows 1-16, north up. Title is descriptive.'),
    geo=('GEO8', 13),
    start=(15, 10),
    arrivals=[(15, 6)],
    exits=[(15, 6, 'S'), (15, 10, 'S')],
    illusion_ids={1, 2, 10},
    legend=['arrival', 'exit', 'door', 'illusion:walkable wall (secret door / ballista port)',
            'lock2:locked door (Bash / Pick / Knock)', 'grey:not reachable'],
    markers=[
        ('1', 13, 6, 'fight'), ('2', 11, 6, 'hint'), ('3', 12, 8, 'fight'), ('4', 9, 10, 'fight'), ('5', 9, 11, 'fight'),
        ('6', 9, 12, 'hint'), ('16', 9, 13, 'fight'), ('17', 8, 14.5, 'fight'), ('26', 6, 14, 'loot'),
        ('18', 3, 15, 'hint'), ('9', 3, 5, 'fight'), ('10', 1, 5, 'secret'), ('20', 0, 7, 'fight'), ('20', 2, 7, 'fight'),
        ('11', 1, 10, 'hint'), ('27', 1, 13, 'loot'), ('12', 0, 12, 'loot'), ('14', 3, 1, 'hint'), ('15', 0, 0, 'place'),
        ('13', 3, 2.5, 'hint'),
    ],
    glance=('<b>ARRIVE</b> from the wilderness (ECL8 block 27): the <b>large cave</b> puts you at K16, the hidden <b>small cave</b> at G16 '
            '(its north door is locked: Bash, Pick or Knock). <b>LEAVE</b> by stepping back onto G16 or K16 and answering YES. '
            '<b>QUEST</b> (City Hall commission "kobolds being recruited by the enemy"): break the king in three stages (9, 20, 11); the clerk pays '
            '<b>25 gems</b> and the hoard (27) holds the rest. Fights of the throne room come back to back without a rest. '
            'Random fights: none from the large cave until the wyvern is dead; from the small cave they start at once.'),
    entries=[
        ('P', 'fight', 'Roaming kobolds (all plain cave cells)',
         'Chance per step 1 in 61 (1 in 21 when searching) until the first throne fight is won; 1 in 161 (1 in 121) after. Pack: 15 Kobolds + 3 Kobold Leaders. '
         'Resting can be interrupted by kobolds throwing rocks. Fleeing a scripted fight drops you at A13, G13, B15, J12, H11 or G12 (random).'),
        ('1', 'fight', 'Pit trap (G14)', 'Press S: each member rolls a skill byte (looks like find traps) against d100. Unfound: the selected member falls in a pool and loses 20% of money and items. Once a visit.'),
        ('2', 'hint', 'Mine tailings (G12)', 'Press S: a kobold\'s crude drawing, journal entry 42 (the paragraph is in the printed journal).'),
        ('3', 'fight', 'White flag kobold (I13)',
         '"We will pay for a truce." AGREE then FOLLOW: he guides you around the traps (J13, J12, H12, H10, K10, L10, M10) to the slope (16). '
         'REFUSE or KILL IT: the roof collapses (2d6 to the whole party, a saving throw applies) and 20 Kobolds attack. Walking back in later (if you followed) is a plain deadfall trap.'),
        ('4', 'fight', 'Net trap (K10) and spike trap (L10)',
         'K10: unfound, a net and 20 Kobolds; L10: spikes, 2d4 to one member (save). Detect with S (roll as in 1); the escorts in 3 and 6 skip them.'),
        ('6', 'hint', 'Drunken kobold (M10)',
         'Only while the king is untouched and you came by the large cave. SLIP PAST, WAKE IT (offers an escort to "the king": you end at H6, then walk on) '
         'or KILL IT (random fights then start). A boulder wall east of M10 is walkable.'),
        ('16', 'fight', 'Rubble slope (N10)',
         'East from M10 you tumble down and the noise wakes the <b>Wyvern</b> (17) unless it is dead. Facing any other way: "go up?" YES also wakes it, NO sends you back to the cave mouth. Once per visit.'),
        ('17', 'fight', 'Wyvern lair (O9-P9, nest O7)',
         '1 Wyvern (L9, AC3, HP42), once. After it, ' + tag('loot', 'nest O7: 1000 sp, 500 ep, 1000 gp, 2 gems, 2 jewelry, 2 treasure rolls') + '.'),
        ('18', 'hint', 'Crippled kobold (P4)', 'Press S: it croaks for water. GIVE IT WATER: its tale is journal entry 20; then let it leave or kill it. Once only.'),
        ('9', 'fight', 'Throne room (E4-G4)',
         'Three fights in a row. (1) 4 Trolls, 35 Kobolds, 11 Leaders. (2) "use the secret weapons": ballista, 7 bolts of 2d6, then 5 boars (kind 120), 45 Kobolds, 8 Leaders. '
         '(3) the two Envoys (L6, AC2, HP45): 2 Envoys, 2 Trolls, 2 boars, 8 Kobolds. Then "the king has escaped". Fleeing offers SURRENDER (prison: see 14, 15) or FIGHT. '
         'The ballista ports D5, D6, H4-J4 and the north side of E3, G3 are barred until this scene has started.'),
        ('10', 'secret', 'Secret door (F2, face north)',
         'Press S facing north: each member finds it 1 in 6 (elf or half-elf 2 in 6). The wall is walkable either way (map data).'),
        ('20', 'fight', "King's quarters (H1, H3)", 'After the Envoys: 3 Trolls, 3 boars, 20 Kobolds, 4 Leaders.'),
        ('11', 'hint', 'Spiked pit (K2)', 'After the guards: the king falls into his own pit and dies. ' + tag('hint', 'City Hall will pay (25 gems)') + '.'),
        ('27', 'loot', 'Kobold hoard (N2)', 'After the king: ' + tag('loot', '50000 cp, 6 gems, 2 jewelry') + ' and curios (2 MU scrolls +1, boots, saddles, brooch, tapestries, mirror, brazier, rugs, bone chains).'),
        ('12', 'loot', 'Brass bottle (M1)',
         'Press S. PULL IT OUT frees the Efreeti Samir Ahwahl (L10, AC2, HP55). Answer NO to "are you vampires?" and he sulks back: you keep the <b>Efreeti Bottle</b> '
         '("summon me only when a vampire is near"). YES or ATTACK is a fight with no prize. Once only.'),
        ('14', 'hint', 'Princess Fatima (B4)',
         'Once only. She joins (L4, AC10, HP33) if your party has fewer than 8; else she leaves. ATTACK her is a fight. Journal entry 16. She will not leave the caves with you ("I shall go my own way now" at G16 or K16). '
         'If you SURRENDER to the king before meeting her she helps you in a 10-kobold fight at B3.'),
        ('15', 'place', 'Prison cell (A1)',
         'Surrender to the king after meeting Fatima and you wake here with <b>every</b> member stripped of all money and items (25% of both is nabbed on the way). The cell door is open; leave by A2.'),
        ('13', 'hint', 'Barracks (C4-D4)', 'A crude map: journal entry 28.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Kobold', '0', '7', '3', 'Envoy', '6', '2', '45'], ['Kobold Leader', '0', '7', '4', 'Wyvern', '9', '3', '42'],
              ['Troll', '7', '4', '36', 'Efreeti', '10', '2', '55'], ['Boar (kind 120)', '4', '7', '18', 'Fatima', '4', '10', '33']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON8CHA).'),
    boxes=[
        '<b>ORDER</b> large cave (no random fights): drunk kobold (6) escort or the slope; kill the Wyvern (17) and take the nest; the throne room fights (9); '
        'guards (20); the pit (11); the hoard (27). Meet Fatima (14) first for an ally. '
        '<b>LOCKS</b> G15-G16 (small cave), J2-K2 (into the pit), J8-K8 (living areas): Bash, Pick or Knock. <b>TEXT ONLY</b> voices (F6, H6), living areas (K8), rats (F9), tables (D8, F8), ruined ballista (E2, G2, H4, I4, J4, D5, D6).',
    ],
)
