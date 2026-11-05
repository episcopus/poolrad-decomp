"""Stojanow Gate (old Phlan): GEO2 block 9, ECL2 block 9 (tile set 2). Read from the area script
(see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='stojanow-gate',
    title='STOJANOW GATE',
    subtitle=('Old Phlan gatehouse: wall, two towers, bugbear guards', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Read from the game files: area map GEO2 block 9, scripts ECL2 block 9 and ECL3 block 8,',
                 'monsters MON2CHA. Grid: columns A-P, rows 1-16, north is up.'),
    geo=('GEO2', 9),
    start=(15, 4),
    exits=[(15, 4, 'S'), (15, 11, 'S'), (0, 4, 'N'), (0, 11, 'N')],
    hatch_events={3: ('#f3d9d3', '#d89b90'), 5: ('#f6e3c6', '#d9ae6b'), 6: ('#dfd3ee', '#a98bd0')},
    legend=['arrival', 'exit', 'door', 'lock2:locked (Bash/Pick/Knock; gate: Bash/Knock)',
            'hatch:wall (3)', 'hatch:toll (5)', 'hatch:doors (6)', 'grey:no walk-in'],
    rooms=[
        ('WEST TOWER', 8.2, 4.5, 5.6), ('EAST TOWER', 8.2, 10.5, 5.6), ('GATE', 7.5, 7.5, 4.8, '#6b3fa0', True),
        ('OLD TOWN SIDE', 5.0, 1.6, 5.6), ('PLAZA SIDE', 15.0, 1.6, 5.2),
    ],
    markers=[
        ('1', 12, 2, 'hint'), ('1', 12, 4, 'hint'), ('1', 12, 12, 'hint'), ('1', 13, 7, 'hint'),
        ('2', 14, 4, 'hint'), ('2', 14, 11, 'hint'),
        ('3', 10, 3, 'fight'), ('3', 9, 13, 'fight'),
        ('4', 11, 6, 'fight'), ('5', 10, 8, 'fight'), ('6', 8, 7, 'hint'),
        ('7', 7, 4, 'fight'), ('8', 7, 11, 'fight'), ('B', 5, 4, 'fight'), ('B', 5, 11, 'fight'),
        ('9', 7, 8, 'fight'), ('9', 6, 7, 'fight'), ('P', 3, 8, 'fight'),
    ],
    glance=('<b>ARRIVE</b> on the south edge (E16 or L16) from the plaza map (ECL1 block 18), or on the north edge (E1 or L1) from the '
            'old town (ECL5 block 6: smithy, Bane temple, washerwomen). Walk off the same four edge doors to leave. '
            '<b>JOB</b> (City Hall, ECL3 block 8): "secure Stojanow Gate... a small band must slip inside and hold until relieved." '
            'Done when the garrisons and the outside guards are beaten (9): flag [4AB9] = 254 and the clerk\'s reward table row 19 pays <b>10 jewelry</b>. '
            '<b>NO</b> loot or shops: scripted fights, a wagon and an alarm. The grey wall and towers cannot be walked into; only the stairs and gate doors cross them.'),
    entries=[
        ('1', 'hint', 'Viewpoints (C13, E13, M13, H14)',
         'First step on any of them, once ever: "BEFORE YOU IS STOJANOW GATE... BUILT ACROSS THE BEND OF THE RIVER, THUS ISOLATING THE OLD TOWN AND THE CASTLE"; '
         'wall 30 ft, towers 50 ft, bugbears at the entrance. ' + tag('secret', 'SEARCH (S key) facing north') + ' here while the clock hour digit is below 5 and the bugbears live: '
         'a man with a wagon hands something to two bugbears and the gates open (the hint to 2 and 4).'),
        ('2', 'hint', 'Wagon trader (E15, L15)',
         'Once per visit while the clock hour digit is below 14 and you have no wagon: a man drives a wagon of food and equipment north. '
         + tag('hint', 'PARLAY') + ': it costs <b>250 gp</b> (pooled coin; NO gets "take it or leave it"; too poor, he leaves) and he warns that the bugbears hate gate duty and fear '
         'the ettin, so give them no back talk. ' + tag('fight', 'COMBAT') + ': you kill him and take it free. The wagon is only a flag (merchant cover for 4).'),
        ('3', 'fight', 'Wall strip (red hatch)',
         'Until both towers are taken. Warning 1: "STAY AWAY FROM THE WALL." Next step: the bugbears come over and swing: ' + tag('fight', 'ATTACK') + ' (16 Bugbears) or '
         'TAKE THE PUNCH (1d3 to one member, "NOW BEAT IT"); had you stood on a viewpoint (1) in between you get "...THAT INCLUDES THE TOWER" instead. After that every step here is the demand at 5. '
         'Bugbears dead: the strip, toll zone and gate doors shoot "a couple arrows" (2 hits of 1d6) per step while a tower garrison lives.'),
        ('4', 'fight', 'Toll zone (G11, J11, G12-J12)',
         'Without the wagon: as 3. With it, per step: if you were already refused or seen through, or a 1-in-10 to 3-in-10 roll (more after warnings at 3) fails: '
         '"THEY ARE IMPOSTERS!" and the demand at 5. Else a bugbear says "LET\'S HAVE THE 15 GOLD": ' + tag('hint', 'pay 15 gp') + ' and "THE GATE OPENS": you are walked through the passage and stand '
         'at I6 facing north, inside. Refuse or cannot pay: "COME BACK WHEN YOU\'VE LEARNED THE RULES" and the next try is always seen through.'),
        ('5', 'fight', 'Gate doors (H11-I11, violet hatch)',
         'Every step while the outside bugbears live: "THROW DOWN YOUR WEAPONS!" ' + tag('fight', 'ATTACK') + ': 16 Bugbears, alarm rings, they stay dead. '
         'SURRENDER: all your coin and about 1 item in 5 go ("STRIP YOU OF ANYTHING REMOTELY VALUABLE"), then you are set down at E15 or L15. FLEE: same, nothing lost.'),
        ('6', 'hint', 'Gate passage (H7-I10, hard-locked doors)',
         'Going <b>south</b> through the passage is always free, and walking it facing south opens both doors for good (flags 1 and 2). Going north through H10/I10 or H8/I8 needs that, or the '
         'gate taken (9); otherwise: "FROM THE TOP OF THE GATE COMES A VOLLEY OF ROCKS", 16 hits of 1d6 on random members. (The toll walk at 4 skips the doors.)'),
        ('7', 'fight', 'West tower (E6 stair door, guard room E8)',
         'On E6 facing south: "DO YOU WANT TO GO UPSTAIRS?" takes you to E8; E8 facing north comes back down to E6. '
         'Guard room: "TABLES, CHAIRS, AND BEDS... ALL BUT TWO OF THE BEDS ARE 14 FEET LONG!"; "TWO HUMANS AND THREE ETTIN". You overhear a mage: "...BEFORE ASSAULTING PHLAN. I AM EAGER TO BECOME A BARON." COMBAT or PARLAY fights '
         '(alarm rings): <b>5th lvl MU + Aide + 3 Ettins</b>; FLEE goes back down. Win: garrison done for good (flag 4).'),
        ('8', 'fight', 'East tower (L6 stair door, guard room L8)',
         'Same at L6 and L8: "THE LAST GUY WHO GAVE THE BOSS LIP WAS THROWN THROUGH THE TRAPDOOR TO THE MEDUSA!" Fight: <b>Level 6 MU + Aide + 3 Ettins</b>. Win: garrison done (flag 8).'),
        ('B', 'fight', 'Alarm ambush at the tower bases (E6, L6)',
         'Only while the alarm rings: stepping on E6 or L6 sends down each garrison still alive ("MONSTERS THUNDER DOWN THE STEPS", "CHARGING TOWARD YOU FROM THE FAR TOWER"; both if both): '
         'MU + Aide + 3 Ettins each. Winning counts <b>both</b> garrisons slain, even unvisited; if the bugbears still live: "NOW SLAY THE OUTSIDE GUARDS QUICKLY BEFORE THE ENEMY ARRIVES." '
         'Flee: you are sent to E16 of the old-town map (the script does not reset the tile set first: looks unfinished).'),
        ('9', 'fight', 'Taking the gate (H8-I8; H7-I7)',
         'Both garrisons dead, bugbears alive, step on H8 or I8: "BUGBEARS WERE WAITING ON THE OTHER SIDE OF THE GATE", 16 Bugbears; win: "YOU HAVE TAKEN THE GATE! ... 20 HUMAN AND DEMI-HUMAN GUARDS TAKE POSSESSION OF THE GUARD TOWERS." '
         'Both doors open for good, [4AB9] = 254; flee sends you to E16 of the old-town map as in B. Bugbears dead, one garrison alive: on H7 or I7, "A GROUP OF MONSTERS IS WAITING ON THE OTHER SIDE OF THE WALL": <b>2 Level 6 MU + 2 Aides + 6 Ettins</b>; win = gate taken too; flee: set down at E15 or L15.'),
        ('P', 'fight', 'Giant patrol (open ground, rows 1-7) and the disguise',
         'Only while the alarm rings: about 1 step in 21 (1 in 3 when searching; rarer inside the buildings), and a rest here can be interrupted by it too: '
         '<b>6th lvl Fighter + 5 Hill Giants</b>. ' + tag('hint', 'With the old-town disguise') + ' (the washerwomen\'s clothes) you may PARLAY: the leader asks "WHAT ARE YOU DOING HERE?"; '
         'attitude MEEK: "TODAY\'S PASSWORD?" -> <b>HARASH</b>; HAUGHTY or ABUSIVE: "ON WHOSE AUTHORITY?" -> <b>TYRANTHRAXUS</b>; SLY or NICE or a wrong word: fight. Right word: left alone. '
         'Without the disguise: fight or flee. Fleeing rings the alarm and loses the disguise.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Bugbear', '4', '5', '16', 'Hill Giant', '9', '4', '41'], ['Ettin', '10', '3', '50', '6th lvl Fighter', '6', '2', '45'],
              ['5th lvl MU', '5', '9', '20', 'Level 6 MU', '6', '9', '23'], ['Aide', '3', '8', '18', '', '', '', '']],
        widths=[58, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON2CHA).'),
    boxes=[
        '<b>PASSWORDS</b> HARASH (meek), TYRANTHRAXUS (haughty or abusive), to the giant patrol only, and only in the disguise. '
        '<b>PRICES</b> wagon 250 gp, gate toll 15 gp. <b>ALARM</b> starts when you fight a tower garrison or the gate bugbears, or flee a patrol or ambush; "AN ALARM IS SOUNDING" shows on about 1 step in 10; '
        'walking off the south edge ends it (its own timeout reads an untraced scratch variable: looks like a script slip). <b>CAMPING</b> is safe, except on the open ground north (rows 1-7) '
        'while the alarm rings: a 17% check every 5 minutes of rest, then the giant patrol.',
        '<b>STAYS</b> after you leave: tower garrisons dead, bugbears dead, the wagon, the gate taken, the warning level. <b>RESETS</b> each visit: the trader, the guard-room texts, the arrows. '
        '<b>LOOKS LIKE the intended route:</b> wagon (2), toll (4), old-town disguise, both towers (7, 8) or the alarm ambush (B), then H8 (9).',
        '<b>TEXT ONLY</b> every building (rows 1-4 and 10-16): no script, locked doors (red), nothing inside. The outer doors E1, L1, E16, L16 are the map edges.',
    ],
)
