"""Stojanow Gate (old Phlan): GEO2 block 9, ECL2 block 9 (tile set 2). Read from the area script
(see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='stojanow-gate',
    title='STOJANOW GATE',
    subtitle=('Old Phlan gatehouse: wall, two towers, bugbear guards', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
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
    glance=('<b>ARRIVE</b> on the south edge (4,15) or (11,15) from Podal Plaza, or on the north edge (4,0) or (11,0) from the '
            'Castle Yard (smithy, Bane temple, washerwomen). Walk off the same four edge doors to leave. '
            '<b>JOB</b> (City Hall): "secure Stojanow Gate... a small band must slip inside and hold until relieved." '
            'Done when the garrisons and the outside guards are beaten (9): the City Hall clerk pays <b>10 jewelry</b>. '
            '<b>NO</b> loot or shops: set-piece fights, a wagon and an alarm. The grey wall and towers cannot be walked into; only the stairs and gate doors cross them.'),
    entries=[
        ('1', 'hint', 'Viewpoints (2,12), (4,12), (12,12), (7,13)',
         'First step on any of them, once ever: "BEFORE YOU IS STOJANOW GATE... BUILT ACROSS THE BEND OF THE RIVER, THUS ISOLATING THE OLD TOWN AND THE CASTLE"; '
         'wall 30 ft, towers 50 ft, bugbears at the entrance. ' + tag('secret', 'SEARCH (S key) facing north') + ' here while the game clock\'s hour is below 5 and the bugbears live: '
         'a man with a wagon hands something to two bugbears and the gates open (the hint to 2 and 4).'),
        ('2', 'hint', 'Wagon trader (4,14), (11,14)',
         'Once per visit while the game clock\'s hour is below 14 and you have no wagon: a man drives a wagon of food and equipment north. '
         + tag('hint', 'PARLAY') + ': it costs <b>250 gp</b> (pooled coin; NO gets "take it or leave it"; too poor, he leaves) and he warns that the bugbears hate gate duty and fear '
         'the ettin, so give them no back talk. ' + tag('fight', 'COMBAT') + ': you kill him and take it free. The wagon is just your merchant cover for 4.'),
        ('3', 'fight', 'Wall strip (red hatch)',
         'Until both towers are taken. Warning 1: "STAY AWAY FROM THE WALL." Next step: the bugbears come over and swing: ' + tag('fight', 'ATTACK') + ' (16 Bugbears) or '
         'TAKE THE PUNCH (1d3 to one member, "NOW BEAT IT"); had you stood on a viewpoint (1) in between you get "...THAT INCLUDES THE TOWER" instead. After that every step here is the demand at 5. '
         'Bugbears dead: the strip, toll zone and gate doors shoot "a couple arrows" (2 hits of 1d6) per step while a tower garrison lives.'),
        ('4', 'fight', 'Toll zone (6,10), (9,10), (6,11)-(9,11)',
         'Without the wagon: as 3. With it, per step: if you were already refused or seen through, or a 1-in-10 to 3-in-10 roll (more after warnings at 3) fails: '
         '"THEY ARE IMPOSTERS!" and the demand at 5. Else a bugbear says "LET\'S HAVE THE 15 GOLD": ' + tag('hint', 'pay 15 gp') + ' and "THE GATE OPENS": you are walked through the passage and stand '
         'at (8,5) facing north, inside. Refuse or cannot pay: "COME BACK WHEN YOU\'VE LEARNED THE RULES" and the next try is always seen through.'),
        ('5', 'fight', 'Gate doors ((7,10)-(8,10), violet hatch)',
         'Every step while the outside bugbears live: "THROW DOWN YOUR WEAPONS!" ' + tag('fight', 'ATTACK') + ': 16 Bugbears, alarm rings, they stay dead. '
         'SURRENDER: all your coin and about 1 item in 5 go ("STRIP YOU OF ANYTHING REMOTELY VALUABLE"), then you are set down at (4,14) or (11,14). FLEE: same, nothing lost.'),
        ('6', 'hint', 'Gate passage ((7,6)-(8,9), hard-locked doors)',
         'Going <b>south</b> through the passage is always free, and walking it facing south opens both doors for good. Going north through (7,9)/(8,9) or (7,7)/(8,7) needs that, or the '
         'gate taken (9); otherwise: "FROM THE TOP OF THE GATE COMES A VOLLEY OF ROCKS", 16 hits of 1d6 on random members. (The toll walk at 4 skips the doors.)'),
        ('7', 'fight', 'West tower ((4,5) stair door, guard room (4,7))',
         'On (4,5) facing south: "DO YOU WANT TO GO UPSTAIRS?" takes you to (4,7); (4,7) facing north comes back down to (4,5). '
         'Guard room: "TABLES, CHAIRS, AND BEDS... ALL BUT TWO OF THE BEDS ARE 14 FEET LONG!"; "TWO HUMANS AND THREE ETTIN". You overhear a mage: "...BEFORE ASSAULTING PHLAN. I AM EAGER TO BECOME A BARON." COMBAT or PARLAY fights '
         '(alarm rings): <b>5th lvl MU + Aide + 3 Ettins</b>; FLEE goes back down. Win: garrison done for good.'),
        ('8', 'fight', 'East tower ((11,5) stair door, guard room (11,7))',
         'Same at (11,5) and (11,7): "THE LAST GUY WHO GAVE THE BOSS LIP WAS THROWN THROUGH THE TRAPDOOR TO THE MEDUSA!" Fight: <b>Level 6 MU + Aide + 3 Ettins</b>. Win: garrison done.'),
        ('B', 'fight', 'Alarm ambush at the tower bases (4,5), (11,5)',
         'Only while the alarm rings: stepping on (4,5) or (11,5) sends down each garrison still alive ("MONSTERS THUNDER DOWN THE STEPS", "CHARGING TOWARD YOU FROM THE FAR TOWER"; both if both): '
         'MU + Aide + 3 Ettins each. Winning counts <b>both</b> garrisons slain, even unvisited; if the bugbears still live: "NOW SLAY THE OUTSIDE GUARDS QUICKLY BEFORE THE ENEMY ARRIVES." '
         'Flee: you are sent to (4,15) of the Castle Yard map (looks like a glitch: the map graphics are not reloaded).'),
        ('9', 'fight', 'Taking the gate (7,7)-(8,7); (7,6)-(8,6)',
         'Both garrisons dead, bugbears alive, step on (7,7) or (8,7): "BUGBEARS WERE WAITING ON THE OTHER SIDE OF THE GATE", 16 Bugbears; win: "YOU HAVE TAKEN THE GATE! ... 20 HUMAN AND DEMI-HUMAN GUARDS TAKE POSSESSION OF THE GUARD TOWERS." '
         'Both doors open for good and the gate counts as taken; flee sends you to (4,15) of the Castle Yard map as in B. Bugbears dead, one garrison alive: on (7,6) or (8,6), "A GROUP OF MONSTERS IS WAITING ON THE OTHER SIDE OF THE WALL": <b>2 Level 6 MU + 2 Aides + 6 Ettins</b>; win = gate taken too; flee: set down at (4,14) or (11,14).'),
        ('P', 'fight', 'Giant patrol (open ground, rows 0-6) and the disguise',
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
        caption='Lvl, AC (descending), HP as listed in the game.'),
    boxes=[
        '<b>PASSWORDS</b> HARASH (meek), TYRANTHRAXUS (haughty or abusive), to the giant patrol only, and only in the disguise. '
        '<b>PRICES</b> wagon 250 gp, gate toll 15 gp. <b>ALARM</b> starts when you fight a tower garrison or the gate bugbears, or flee a patrol or ambush; "AN ALARM IS SOUNDING" shows on about 1 step in 10; '
        'walking off the south edge ends it (its own timeout looks broken). <b>CAMPING</b> is safe, except on the open ground north (rows 0-6) '
        'while the alarm rings: a 17% check every 5 minutes of rest, then the giant patrol.',
        '<b>STAYS</b> after you leave: tower garrisons dead, bugbears dead, the wagon, the gate taken, the warning level. <b>RESETS</b> each visit: the trader, the guard-room texts, the arrows. '
        '<b>LOOKS LIKE the intended route:</b> wagon (2), toll (4), old-town disguise, both towers (7, 8) or the alarm ambush (B), then (7,7) (9).',
        '<b>TEXT ONLY</b> every building (rows 0-3 and 9-15): locked doors (red), nothing inside. The outer doors (4,0), (11,0), (4,15), (11,15) are the map edges.',
    ],
)
