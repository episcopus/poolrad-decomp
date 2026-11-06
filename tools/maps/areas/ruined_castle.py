"""The ruined castle in the quicksand: GEO8 block 16, ECL8 block 16 (tile set 8). Read from the area script
(see tools/maps/README.md for how each statement was checked). Entered from the wilderness script ECL8 block 27."""
from mapkit import tag

SPEC = dict(
    name='ruined-castle',
    title='RUINED CASTLE',
    subtitle=('Lizard men ruins in the quicksand', 'Pool of Radiance (DOS)  |  area map  |  SPOILERS'),
    source_note=('Game files: GEO8 block 16 (surface; block 30 = tunnels below), ECL8 block 16, MON8CHA, ITEM8.',
                 'Grid: (column,row) from 0, top left, north up. Title is descriptive ("ruined castle" is the wilderness text).'),
    geo=('GEO8', 16),
    start=(14, 8),
    exits=[(15, 8, 'S')],
    legend=['arrival', 'exit', 'search', 'door', 'grey:moat / outside the ruins'],
    markers=[
        ('1', 3, 4, 'fight', dict(dy=-4)), ('2', 6.5, 4, 'fight'), ('2', 9.5, 2, 'fight'), ('3', 7, 8, 'fight', dict(dy=-5)),
        ('g', 8, 9, 'secret'), ('M', 4, 15, 'place'), ('M', 0, 6, 'place'), ('M', 15, 1, 'place'),
        ('M', 14, 0, 'place'),
    ],
    diamonds=[
        ('a', 7, 3, 'secret'), ('b', 4, 10, 'secret'), ('c', 12, 5, 'secret'),
        ('d', 6, 6, 'secret'), ('e', 6, 9, 'secret'), ('f', 9, 7, 'secret'), ('T', 8, 3, 'loot', dict(dy=-2)),
    ],
    glance=('<b>ARRIVE</b> from the wilderness (ECL8 block 27, castle at world column 11, row 8: "Will you enter?") at (8,14) facing north: '
            '"You sense an anti-magic shell around you" (the script does not say more; spells may fail here). <b>LEAVE</b> south over the bridge at (8,15). '
            '<b>QUEST</b> (City Hall: "a tribe of lizardmen is preparing to join the enemy"): paid <b>50 gp, 15 gems, 5 jewelry</b> once you win the duel for the old lizardman (Q) '
            'or have killed 40 or more lizardmen when you leave. Everything here is scripted and once only; there are no random fights. '
            '<b>Take the (3,8) treasure (T) before the old lizardman scene</b>: winning it marks all flags done, T included.'),
    entries=[
        ('Q', 'hint', 'The old lizardman (first ruin you enter: 1, 2 or 3)',
         'Only if you freed the shackled lizardmen in the pumping room (ECL7 block 23, which sets the flag this script tests). He appears instead of that ruin\'s ambush. '
         'Pick PARLAY (attack and he dies, then the ambush hits; leaving also loses the quest). He asks for the tribal friend-word: <b>SAVIOR</b> (6 letters; a wrong word makes him vanish). '
         'It was probably told to you by the freed lizardmen (journal entry 35 there; inferred). He then tells his story (journal entry 31): the rebel Drythh '
         'challenges him; "Will you champion me?" YES, pick a member: duel against Drythh ((11,3), AC3, HP18) with that one character. '
         + tag('loot', 'Win: the lizardmen withdraw, the quest is paid by City Hall, every ambush below is cancelled') + '. Lose, or answer NO: Drythh + 12 Lizardmen attack the party.'),
        ('1', 'fight', 'Fallen-roof building (4,3)', 'First entry: roof down, rubble. Ambush: 2 Lizardmen + 1 Giant Lizard (a ranger may spot them first; any answer but flee fights).'),
        ('2', 'fight', 'L-shaped building (4,6)-(4,7), (2,9)-(2,10)', 'Roof partly intact. Ambush: 3 Giant Lizards from behind a mound of rubble.'),
        ('3', 'fight', 'Central keep (6,6)-(9,9)',
         'Rubble-choked. A volley of javelins first (1d6 per lizardman), then up to <b>20 Lizardmen + 4 Giant Lizards</b>: the most dangerous scripted fight here. '
         'Counts are capped by how many are left (the script tracks 50 lizardmen and 10 giant lizards killed; fewer than 2 left: no ambush).'),
        ('a', 'secret', 'Hidden tunnels (S key): (3,7) swamp, (10,4) swamp, (5,12) rubble, and in the keep (6,6), (9,6), (7,9)',
         '"Searching through the swamp you find a hidden tunnel leading down. Do you take it?" It leads to the tunnels (GEO8 block 30, see below). '
         'Going down marks every ruin ambush done; at the bottom up to 10 Giant Lizards charge (if at least 2 are left). ' + tag('secret', 'g (9,8)') + ' is an old blocked stair down, no search needed.'),
        ('T', 'loot', 'Treasure (3,8)', 'Press S: "You find some treasure!" Take it: ' + tag('loot', '1000 gp, 1 gem, 1 jewelry') + '. Once only.'),
        ('M', 'place', 'Moat edge cells (5,0)-(7,0), (9,0), (11,0), (0,2), (0,6)-(0,7), (0,14), (1,15)-(2,15), (11,15), (13,15), (15,4)',
         'You can step onto them, not on: "A moat filled with sludge and thorns... the mud would surely drag you down to your death." Nothing to find.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP'], ['Lizardman', '3', '4', '11'], ['Giant Lizard', '4', '5', '16'], ['Drythh', '4', '3', '18']],
        widths=[70, 22, 22, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON8CHA).'),
    boxes=[
        '<b>DOWN</b> (cell, then GEO8 block 30 arrival cell and facing): (3,7) (1,7) S; (10,4) (13,1) S; (5,12) (4,15) N; (6,6) (4,5) S; (9,6) (10,4) W; (7,9) (7,10) E; (9,8) (10,8) S. '
        '<b>UP</b> (block 30 events 17 to 23 "the tunnel slopes up, do you go up?", 23 is a stair): (10,4), (9,6), (6,6), (3,7), (5,12), (7,9), (9,8). '
        '<b>POOLS</b> (block 30 events 24 to 34): 5 Lizardmen throw javelins (5 hits of 1d6 or so); beat them, then dive: 1000 sp, 1000 gp, 1 gem, '
        'sometimes a Shield +2 or Long Sword +1, once per pool (some pools share a flag). Diving without beating them costs HP and finds nothing.',
        '<b>ORDER</b> take T first; then the old lizardman (Q) in whichever ruin you enter first; skip the keep ambush by winning the duel; leave over the bridge (8,15).',
    ],
)
