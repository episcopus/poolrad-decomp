"""The old Kovel mansion (thieves' hideout): GEO3 block 14, ECL3 block 14 (tile set 3). Read from the area script
(see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='kovel-mansion',
    title='KOVEL MANSION',
    subtitle=('The thieves\' hideout: traps, caskets, ambushes', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Read from the game files: area map GEO3 block 14, scripts ECL3 blocks 14 and 8,',
                 'monsters MON3CHA, loot ITEM3. Grid: (column,row) from 0, top left, north up.'),
    geo=('GEO3', 14),
    start=(0, 4),
    exits=[(0, 4, 'N'), (0, 11, 'N'), (4, 15, 'E'), (11, 15, 'E'), (15, 4, 'S'), (15, 11, 'S')],
    hatch_events={1: ('#f3d9d3', '#d89b90'), 2: ('#f3d9d3', '#d89b90')},
    legend=['arrival', 'exit', 'door', 'lock2:locked (Bash/Pick/Knock)', 'hatch:thief ambush rooms (2)'],
    rooms=[('ANNEX', 10.5, 1.5, 5.0)],
    markers=[
        ('1', 1, 9, 'place', dict(dx=12, dy=-5)),
        ('T', 10, 11, 'secret'), ('T', 11, 13, 'secret'), ('T', 13, 12, 'secret'), ('T', 11, 3, 'secret'),
        ('T', 12, 4, 'secret'), ('T', 6, 5, 'secret'), ('T', 3, 4, 'secret'),
        ('3', 9, 10, 'loot'), ('4', 10, 14, 'loot'), ('5', 14, 14, 'loot'), ('6', 13, 3, 'loot'), ('7', 7, 6, 'loot'),
        ('8', 4, 3, 'fight'), ('9', 5, 6, 'fight'), ('A', 13, 8, 'fight'), ('A', 14, 7, 'fight'), ('J', 12, 10, 'fight'),
        ('F', 14, 8, 'hint'), ('F', 14, 5, 'hint'), ('F', 5, 4, 'hint'),
    ],
    glance=('<b>ARRIVE</b> in the grounds: south edge ((4,15), (11,15), from ECL1 block 24) or north and east edges ((4,0), (11,0), (15,4), (15,11), from the wilderness map ECL7 block 26); '
            'walk off those doors to leave (nothing on the west). <b>GET IN</b> by the double front door on the north face, (9,1)-(9,2) and (10,1)-(10,2) (locked). '
            'The west annex (1,7)-(2,13) has three outer doors, no way into the house and no script. '
            '<b>JOB</b> (City Hall): "a large group of thieves operates out of the old Kovel mansion": kill <b>21 thieves</b> (a running tally, see below) and the clerk pays <b>80 pp + 3 gems</b>. '
            '<b>TAKE</b> 1500 sp, 1800 gp, 35 gems, 1 jewelry and many items (tapestries, scrolls, +1 arms, a Leather Armor +4). '
            '<b>DANGER</b> traps, ambushes, and no safe camping until the guild is broken.'),
    entries=[
        ('1', 'place', 'Front doors ((9,2), (10,2), north face)', 'Locked (red cross). Inside, rooms open with plain locks and doors. All events below are on the cells shown.'),
        ('2', 'fight', 'Thief ambush rooms (red hatch)',
         'Cells (7,3) (8,3) (13,6) (12,7) (4,9) (6,9) (6,11) (10,11) (11,11) (12,11) (5,12) (12,12) (5,13) (event 1) and (11,2) (5,3) (6,3) (12,3) (4,6) (3,8) (4,8) (8,12) (event 2): while the guild stands and under 21 are dead, '
         '"A THIEF WITH A SWORD COMES OUT OF NOWHERE" (never twice in a row from the same event number, per visit). 3 times in 10 he <b>backstabs</b> a member (2d8, 3d8 after 12 kills) and vanishes; '
         'else you hold him: ATTACK (one thief: <b>1st lvl</b>, a <b>6th lvl</b> after 18 kills) or LET HIM GO. Each kill adds 1 to the tally. Fleeing sets you back a step.'),
        ('T', 'secret', 'Trap rooms (11,10), (13,11), (12,13), (3,11), (4,12), (5,6), (4,3)',
         'Once per trap per visit (traps re-arm when you re-land). The party may notice it: "YOUR PARTY DETECTS A TRAP!" (a roll against the best thief skill in the party) or "YOUR MAGIC DETECTS A TRAP!" '
         '(always: looks like a Find Traps effect). Noticed: AVOID (harmless, it stays armed) or DISARM (a roll against that skill; failing sets it off). Unnoticed it fires: '
         '"A SCYTHING BLADE DROPS ACROSS THE DOORWAY" (11,10), (12,13), (3,11), (4,12), (4,3) 1d6 to one member; (13,11): "THE CRACKING OF GLASS... A POISONOUS GAS" 1d3 (save); (5,6): "A NET LACED WITH SHARP BLADES" 1d6 (save).'),
        ('3', 'loot', 'Loot pile (10,9)', '"VARIOUS LOOT... NICK NACKS FROM TARNISHED BRONZE CANDLESTICKS": ' + tag('loot', 'Electrum Decanter, Silver Scarab, Incense, Silver Mirror, Leather Armor +4, Short Sword +2') + ', no trap, once.'),
        ('4', 'loot', 'Three cabinets (14,10)',
         'A, B, C, each locked (see Locks). ' + tag('loot', 'A') + ': files = journal entries 23 and 14. ' + tag('loot', 'B') + ': "FIFTEEN SACKS FILLED WITH SILVER": <b>1500 sp</b>. '
         + tag('loot', 'C') + ': trapped (a needle, 1d8) then "EIGHTEEN SACKS FILLED WITH GOLD": <b>1800 gp</b>. A and B have no trap check.'),
        ('5', 'loot', 'Rugs and tapestries (14,14)', 'No trap: ' + tag('loot', '2 Fine Tapestries and 26 Huge Tapestries') + ' (sellable goods), once.'),
        ('6', 'loot', 'Wooden cabinet (3,13)',
         'Trap check ("A CLOUD OF POISONOUS YELLOW GAS", 2d6 to each member, save), lock, then ' + tag('loot', '4 Magic User Scrolls (3 spells), 2 Clerical Scrolls (3 spells), Scale Armor, Stone Statuette') + '.'),
        ('7', 'loot', 'Table of four caskets (6,7)',
         'Each: trap check, lock, then ' + tag('loot', 'A 12 gems') + ' (needle 1d4), ' + tag('loot', 'B gold chains and pendants: 1 jewelry') + ' (dart 1d3), ' + tag('loot', 'C 3 gems') + ' (powder 1d6 to all, save), '
         + tag('loot', 'D "TINY PEARLS": 20 gems') + ' (12 darts of 1d4). A trap that fires still lets you loot; AVOID leaves the casket shut.'),
        ('8', 'fight', 'Weapons and shields (3,4)',
         'TAKE SOME springs the trap unless searched first (SEARCH: trap check): "AN AWFUL SMELLING CLOUD OF GAS... STUNS THE PARTY": <b>5 thieves</b> jump out (the mix turns 6th lvl as the tally rises, fewer near the end). '
         'Once 18 are dead the gas is "HARMLESS". Gear: ' + tag('loot', 'Broad Sword -2 (cursed), Chain Mail +1, Shield +2, Short Sword +1, Scimitar +1, Morning Star +1, Hammer +1, 2 Daggers +1') + '. Once.'),
        ('9', 'fight', 'The chase (6,5)',
         'Once per visit: two thieves attack and flee east: "WILL YOU CHASE THEM?" The party is walked (9,5), (9,8); then SOUTH, EAST or DON\'T FOLLOW. '
         '<b>EAST</b> (11,8), (11,7), (13,7), (13,5): you catch "THE GUILD MASTER" (a plain thief): ATTACK him, or RELEASE ("SUCKERS": nothing changes). <b>SOUTH</b> ((8,8) to (8,13)): into the ambush hall A.'),
        ('A', 'fight', 'Ambush hall (8,13), (7,14)', 'Once per visit: "AMBUSHED BY SOME THIEVES": <b>15 1st lvl + 3 6th lvl thieves</b>. Win: +15 on the tally. Flee: back a step.'),
        ('J', 'fight', 'Jail (10,12)',
         'Once ever: "TEN YOUNG THUGS BEATING AN OLDER THIEF TO DEATH": 10 1st lvl thieves attack (not counted). Win: he dies saying "THE BOSS HAS ALLIES EVERYWHERE": <b>journal entry 48</b>. '
         'Fleeing also uses the room up. Afterwards: "A JAIL CELL. IT IS EMPTY."'),
        ('F', 'hint', 'Papers and maps (8,14), (5,14), (4,5)',
         'Once ever each, no fight: (8,14) "IMPORTANT LOOKING FILES": entries 38 and 51. (5,14) a slate with a maze marked "NW CASTLE": entry 41. (4,5) a crude map "NE CASTLE": entry 29.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP'], ['1st lvl Thief', '1', '10', '4'], ['6th lvl Thief', '7', '10', '28']],
        widths=[70, 22, 22, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON3CHA).'),
    boxes=[
        '<b>LOCKS</b> (cabinets, caskets): PICK by the chosen member\'s thief skill, one try per lock ever (a failure is permanent); BREAK always works; CAST KNOCK spends a memorized Knock. '
        '<b>TALLY</b> [4A45]: +1 per ambush kill, +5 weapons room, +1 guild master, +15 hall A; at 21 the quest flag [4AB2] = 254, the ambush rooms stop and camping turns safe.',
        '<b>CAMPING</b> before that: a check at every 5 minutes of rest, 99%: "THREE THIEVES WITH SLINGS" hit 3 times for 1d4+1 and run. '
        '<b>STAYS</b> done: all loot, jail, papers, the tally. <b>RESETS</b> each visit: traps, the chase, hall A, the chain rule of the ambush rooms.',
        '<b>LOOKS LIKE the order:</b> front door; loot and papers first (3, 4, 5, F); ambush rooms and the weapons room to build the tally; hall A (A) is the big fight; the clerk for the reward.',
        '<b>TEXT ONLY</b> every other cell, including the whole west annex (1,7)-(2,13).',
    ],
)
