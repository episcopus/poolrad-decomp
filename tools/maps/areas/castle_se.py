"""The castle, south-east quarter: GEO5 block 5, ECL5 block 5 (tile set 5), with ECL5 block 3 for the east and
south rooms. Read from the area scripts (see tools/maps/README.md for how each statement was checked). See
castle_nw.py for how the four GEO5 maps (3 NW, 4 NE, 5 SE, 6 SW) fit together."""
from mapkit import tag

SPEC = dict(
    name='castle-se',
    title='CASTLE SE',
    subtitle=('Hedge maze, throne room, Cadorna\'s cell, the well', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
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
    glance=('<b>ARRIVE</b> at (4,0), (11,0) or (12,0) from the North-East quarter, or at (0,4), (0,11) or (0,12) from the Castle Yard (south-west quarter). <b>EXITS</b> are those six gaps; the south and east edges are solid. '
            '<b>TWO SETS OF RULES:</b> outside the gate (patrols, the east rooms) until you step onto the <i>inside</i> of the gate (11,7)-(11,8); then the maze rules (hedges, tower, throne, teleport pad) apply '
            'until you step back on the outside (12,7)-(12,8). The NW and NE words apply here too: <b>HARASH</b>, <b>TYRANTHRAXUS</b>, <b>RHODIA</b>.'),
    entries=[
        ('G', 'hint', 'Gate ((11,7)-(11,8) | (12,7)-(12,8)), locked',
         'From (12,7) or (12,8) facing west (or from (11,7), (11,8) facing east): "WHAT IS THE PASSWORD?" GIVE it (<b>RHODIA</b>; a wrong word is free) or FORCE it: alarm, ' + tag('fight', '12 boulders of 2d6') +
         ' on random members, and this gate then answers only with boulders from <i>both</i> sides for good. Robbers of the Temple of Bane (Castle Yard) get boulders at once. Cadorna, if freed (3), '
         'hands you the slip each time. (11,7)-(11,8) is the inside (maze rules), (12,7)-(12,8) the outside (patrol rules).'),
        ('P', 'fight', 'Patrols',
         'No random encounters until an alarm rings (it lasts one game hour; see the NW page). Then 1 step in 21 (1 in 3 searching): outside the gate <b>1 Fighter + 5 Hill Giants</b> (disguise: '
         'HAUGHTY or ABUSIVE + TYRANTHRAXUS, MEEK + HARASH); inside <b>4 Giant Snakes</b> (parley, flee or fight; no loot).'),
        ('1', 'fight', 'Door guards (12,12)-(13,12), (14,12)',
         '(12,12) and (13,12): only if you are not in disguise, two giants "bound out of a doorway": robbers of the Temple of Bane are attacked; otherwise PARLEY: ' + tag('hint', 'HAUGHTY') +
         ' = "tell me the password" (<b>HARASH</b>), any other attitude = "who sent you?" (<b>TYRANTHRAXUS</b>); a wrong word is "dinner!" (2 Hill Giants, no loot, then the door is yours). '
         '(14,12) asks the same even in disguise. Behind it, the room (14,12)-(15,13) has nothing in it.'),
        ('2', 'fight', 'Snakes (14,3)', 'Once: 5 Giant Snakes (parley, flee or fight, no loot) in the room (13,0)-(15,3).'),
        ('3', 'hint', 'Cadorna\'s cell (14,10)  ' + tag('hint', 'QUEST'),
         'Appears only after Lord Urslingen at City Hall sends you to "the traitor Cadorna\'s old quarters" (which follows the evidence from the NE scribes\' office). Cadorna, beaten and chained: RELEASE HIM '
         '("take me with you?" yes: he travels with you and the gate hands you its password), LEAVE HIM (4 presses: "I\'ll raise the alarm", "I know how to get through the main gates", '
         '"<b>left, right, right</b> through the hedge", then the alarm) or KILL HIM (the 2nd press). Once. No loot.'),
        ('4', 'loot', 'Well ((15,10), face north)',
         'Facing north on (15,10): "DO YOU WANT TO DIVE IN?" Pick a diver: Constitution under 12 never reaches the bottom; otherwise a roll of 0-20 at or under Constitution does. ' +
         tag('loot', 'A Long Sword +2 (Flame Tongue)') + ' lies there, once. Coming up, a roll of 0-19 plus the amount your Movement is under 12 (a heavy load), if above Constitution, costs the diver 1d6 (water in the lungs). Repeat as you like.'),
        ('5', 'fight', 'Ceiling (10,14)', 'Once: "the ceiling caves in" as you push the door: 2d6 to one random member.'),
        ('6', 'place', 'Cobwebs (12,14)', '"A deserted building, nothing but very large cobwebs." Text, once.'),
        ('7', 'fight', 'Giants rooms (7,14) and (14,8)',
         'Only before hour 14: 8 Hill Giants "putting on their armor" (surprised: "struggling out of bed"). Once for each of (7,14) and (14,8) (and (2,13) in the NW), no loot. '
         + tag('loot', 'a: SEARCH at (6,15), b: at (15,7)') + ': <b>11 gold</b> each, once.'),
        ('H', 'secret', 'Inside the gate: hedges and teleports',
         'Inside the gate a green hedge wall asks CUT THROUGH?: one random member saves or takes 201 damage (poisonous thorns); the party then steps through, so the maze can be crossed anywhere. '
         'The map edges do not change the rules: walking off one just takes you into the neighbouring quarter (NW, NE, SE and Castle Yard make one square); the outer edges stay in place.'),
        ('T', 'fight', 'Throne room (3,1)  ' + tag('loot', 'LOOT'),
         'Enter from (4,1) through the hidden door; reached by cutting hedges or by landing on the pad (3,4). "Tyranthraxus, Lord of Phlan" on his throne. PARLEY: HAUGHTY or SLY = fight; NICE or MEEK = '
         '"begone... do you leave?" (yes: you go; no: fight); <b>ABUSIVE</b>: the game adds up a party strength score (hit points, armor, fighter and cleric levels): '
         'under 85 he collapses, "I\'m not Tyranthraxus, just let me go"; say yes and you take the treasure unopposed; 85 or more (not confirmed in play) he attacks. Fight: the impostor + 2 Thieves. ' + tag('loot', 'Loot 8 gems + 1 jewelry') + '. Once.'),
        ('W', 'fight', 'Tower (10,11)',
         'Entrance through the hidden door (9,11)|(10,11). Four giants quarrel ("frogs and toads not same thing. Me right?"): <b>NO</b>, then LEAVE = nobody fights; YES or ATTACK = '
         '4 Fire Giants (no loot). Undisguised with the alarm up (or after robbing the Temple of Bane) they attack at once. Once, after a fight.'),
        ('D', 'secret', 'Teleport pad (3,4)',
         '"A sudden disorientation": you land on one of four pads, each equally likely: (12,11) in the NW quarter, (6,10) in the NE, (3,4) here, (9,5) in the Castle Yard. Without cutting hedges the way to (3,1) and (3,4) is '
         'the west door (0,4) (under the outside rules, (3,4) is then the sleeping-giants door and (3,1) the loose-stone search of the NW page).'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Hill Giant', '9', '4', '41', 'Fire Giant', '12', '3', '59'],
              ['Giant Snake', '5', '5', '25', 'Troll', '7', '4', '36'],
              ['Impostor', '8', '10', '40', '6th Lvl Thief', '7', '10', '28'],
              ['6th Lvl Fighter', '6', '2', '45', '', '', '', '']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files; the impostor is listed as "TYRANITHRAXUS" (sic).'),
    boxes=[
        '<b>HOW TO GET IN</b> From the NE quarter the doors at (4,0) and (11,0) lead straight into the maze area under the outside rules (no hedge cutting, no gate); the gate at (12,7)-(12,8) is the formal way. '
        'The throne pocket ((3,1), (3,4), the (4,1)-(4,6) corridor) is entered from the Castle Yard\'s east door at row 4.',
        '<b>NOT CONFIRMED</b> What killing Cadorna changes, and how City Hall reacts. The stairs up to Tyranthraxus\' Tower are on the NW page, not here.',
    ],
)
