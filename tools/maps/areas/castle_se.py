"""The castle, south-east quarter: GEO5 block 5, ECL5 block 5 (tile set 5), with ECL5 block 3 for the east and
south rooms. Read from the area scripts (see tools/maps/README.md for how each statement was checked). See
castle_nw.py for how the four GEO5 maps (3 NW, 4 NE, 5 SE, 6 SW) fit together."""
from mapkit import tag

SPEC = dict(
    name='castle-se',
    title='CASTLE SE',
    subtitle=('Hedge maze, throne room, Cadorna\'s cell, the well', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Read from the game files: area map GEO5 block 5, event scripts ECL5 blocks 5 and 3,',
                 'monsters MON5CHA, loot ITEM5. Grid: columns A-P, rows 1-16, north is up.'),
    geo=('GEO5', 5),
    start=(0, 12),
    extra_starts=[(0, 4), (0, 11), (4, 0), (11, 0), (12, 0)],
    exits=[(0, 4, 'N'), (0, 11, 'N'), (0, 12, 'N'), (4, 0, 'W'), (11, 0, 'W'), (12, 0, 'W')],
    illusion_ids={4},
    hedge_ids={7, 9},
    legend=['arrival', 'exit', 'search', 'door', 'illusion:hidden door', 'lock2:gate (password)',
            'hedge:hedge wall', 'grey:no way in'],
    rooms=[
        ('THRONE ROOM', 2.2, 1.5, 4.8), ('hedge maze', 9.3, 8.5, 6.5, '#3f7f3a', True), ('tower', 10.0, 10.5, 4.6),
        ('snakes', 1.2, 14.0, 4.6), ('cobwebs', 15.2, 13.5, 4.2),
        ('giants', 14.7, 4.5, 4.4),
    ],
    markers=[
        ('G', 7.5, 11.5, 'hint', dict(dy=1)), ('1', 12, 12.5, 'fight', dict(dy=-9)), ('2', 3, 14, 'fight'), ('3', 10, 14, 'hint'),
        ('4', 10, 15, 'hint', dict(dy=-3)), ('5', 14, 10, 'fight'), ('6', 14, 12, 'place'), ('7', 14, 7, 'fight'), ('7', 8, 14, 'fight', dict(dy=3)),
        ('T', 1, 3, 'fight'), ('W', 11, 10, 'fight'), ('D', 4, 3, 'secret'), ('P', 13, 3, 'fight'),
    ],
    diamonds=[('a', 15, 6, 'loot'), ('b', 7, 15, 'loot')],
    glance=('<b>ARRIVE</b> at E1, L1 or M1 from the NE quarter, or at A5, A12 or A13 from the SW quarter (ECL5 block 6). <b>EXITS</b> are those six gaps; the south and east edges are solid. '
            '<b>TWO SCRIPTS:</b> ECL5/3 (patrols, the east rooms) runs until you step onto the <i>inside</i> of the gate (L8-L9); then the maze script ECL5/5 (hedges, tower, throne, teleport pad) takes over '
            'until you step on the outside (M8-M9). Every fight and word of the NW and NE pages applies here too: <b>HARASH</b>, <b>TYRANTHRAXUS</b>, <b>RHODIA</b>.'),
    entries=[
        ('G', 'hint', 'Gate (L8-L9 | M8-M9), locked',
         'From M8 or M9 facing west (or from L8, L9 facing east): "WHAT IS THE PASSWORD?" GIVE it (<b>RHODIA</b>; a wrong word is free) or FORCE it: alarm, ' + tag('fight', '12 boulders of 2d6') +
         ' on random members, and this gate then answers only with boulders from <i>both</i> sides for good. Robbers of the SW temple get boulders at once. Cadorna, if freed (3), '
         'hands you the slip each time. L8-L9 starts ECL5/5, M8-M9 returns to ECL5/3.'),
        ('P', 'fight', 'Patrols',
         'No random encounters until an alarm rings (it lasts one game hour; see the NW page). Then 1 step in 21 (1 in 3 searching): in ECL5/3 <b>1 Fighter + 5 Hill Giants</b> (disguise: '
         'HAUGHTY or ABUSIVE + TYRANTHRAXUS, MEEK + HARASH); in ECL5/5 <b>4 Giant Snakes</b> (parley, flee or fight; no loot).'),
        ('1', 'fight', 'Door guards (M13-N13, O13)',
         'M13 and N13: only if you are not in disguise, two giants "bound out of a doorway": robbers of the SW temple are attacked; otherwise PARLEY: ' + tag('hint', 'HAUGHTY') +
         ' = "tell me the password" (<b>HARASH</b>), any other attitude = "who sent you?" (<b>TYRANTHRAXUS</b>); a wrong word is "dinner!" (2 Hill Giants, no loot, then the door is yours). '
         'O13 asks the same even in disguise. Behind it, the room O13-P14 has no script.'),
        ('2', 'fight', 'Snakes (O4)', 'Once: 5 Giant Snakes (parley, flee or fight, no loot) in the room N1-P4.'),
        ('3', 'hint', 'Cadorna\'s cell (O11)  ' + tag('hint', 'QUEST'),
         'Appears only after City Hall (ECL5/3 reads a flag ECL3 block 8 sets when Lord Urslingen sends you to "the traitor Cadorna\'s old quarters"; that follows the evidence from the NE scribes\' office). Cadorna, beaten and chained: RELEASE HIM '
         '("take me with you?" yes: he travels with you and the gate hands you its password), LEAVE HIM (4 presses: "I\'ll raise the alarm", "I know how to get through the main gates", '
         '"<b>left, right, right</b> through the hedge", then the alarm) or KILL HIM (the 2nd press). Once. No loot.'),
        ('4', 'loot', 'Well (P11, face north)',
         'Facing north on P11: "DO YOU WANT TO DIVE IN?" Pick a diver: Constitution under 12 never reaches the bottom; otherwise a roll of 0-20 at or under Constitution does. ' +
         tag('loot', 'A Long Sword +2 (Flame Tongue)') + ' lies there, once. Coming up, a roll of 0-19 plus the amount your Movement is under 12 (a heavy load), if above Constitution, costs the diver 1d6 (water in the lungs). Repeat as you like.'),
        ('5', 'fight', 'Ceiling (K15)', 'Once: "the ceiling caves in" as you push the door: 2d6 to one random member.'),
        ('6', 'place', 'Cobwebs (M15)', '"A deserted building, nothing but very large cobwebs." Text, once.'),
        ('7', 'fight', 'Giants rooms (H15 and O9)',
         'Only before hour 14: 8 Hill Giants "putting on their armor" (surprised: "struggling out of bed"). Once for each of H15 and O9 (and C14 in the NW), no loot. '
         + tag('loot', 'a: SEARCH at G16, b: at P8') + ': <b>11 gold</b> each, once.'),
        ('H', 'secret', 'Maze script: hedges and teleports',
         'In ECL5/5 a wall with id 7 or 9 (green) asks CUT THROUGH?: one random member saves or takes 201 damage (poisonous thorns); the party then steps through, so the maze can be crossed anywhere. '
         'The map edges do not change scripts: walking off one just loads the neighbouring quarter (GEO5 3 NW, 4 NE, 5 SE, 6 SW as one square); the outer edges stay in place.'),
        ('T', 'fight', 'Throne room (D2)  ' + tag('loot', 'LOOT'),
         'Enter from E2 through the hidden door; reached by cutting hedges or by landing on the pad D5. "Tyranthraxus, Lord of Phlan" on his throne. PARLEY: HAUGHTY or SLY = fight; NICE or MEEK = '
         '"begone... do you leave?" (yes: you go; no: fight); <b>ABUSIVE</b>: the script adds up a party strength score (hit points, armor, fighter and cleric levels; PARTYVAL): '
         'under 85 he collapses, "I\'m not Tyranthraxus, just let me go"; say yes and you take the treasure unopposed; 85 or more (as read) he attacks. Fight: the impostor + 2 Thieves. ' + tag('loot', 'Loot 8 gems + 1 jewelry') + '. Once.'),
        ('W', 'fight', 'Tower (K12)',
         'Entrance through the hidden door J12|K12. Four giants quarrel ("frogs and toads not same thing. Me right?"): <b>NO</b>, then LEAVE = nobody fights; YES or ATTACK = '
         '4 Fire Giants (no loot). Undisguised with the alarm up (or after robbing the SW temple) they attack at once. Once, after a fight.'),
        ('D', 'secret', 'Teleport pad (D5)',
         '"A sudden disorientation": you land on one of four pads, each equally likely: M12 in the NW quarter, G11 in the NE, D5 here, J6 in the SW. Without cutting hedges the way to D2 and D5 is '
         'the west door A5 (under ECL5/3, D5 is then the sleeping-giants door and D2 the loose-stone search of the NW page).'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Hill Giant', '9', '4', '41', 'Fire Giant', '12', '3', '59'],
              ['Giant Snake', '5', '5', '25', 'Troll', '7', '4', '36'],
              ['Impostor', '8', '10', '40', '6th Lvl Thief', '7', '10', '28'],
              ['6th Lvl Fighter', '6', '2', '45', '', '', '', '']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON5CHA); the impostor is the record "TYRANITHRAXUS".'),
    boxes=[
        '<b>HOW TO GET IN</b> From the NE quarter the doors at E1 and L1 lead straight into the maze under ECL5/3 (no hedge rules, no gate); the gate at M8-M9 is the formal way. '
        'The throne pocket (D2, D5, the E2-E7 corridor) is entered from the SW quarter\'s east door at row 5.',
        '<b>NOT TRACED</b> The City Hall flags behind Cadorna\'s cell (and what flag 4ABF, set when you kill him, is for); the stairs up to ECL5/7 (event 4 facing east) are not on this map.',
    ],
)
