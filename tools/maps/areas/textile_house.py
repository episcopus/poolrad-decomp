"""Cadorna Textile House (a hobgoblin-held compound south of Podol Plaza, Old Phlan): GEO4 block 2,
ECL4 block 2 (tile set 4). Read from the area script (see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='cadorna-textile-house',
    title='CADORNA TEXTILE HOUSE',
    subtitle=('Hobgoblin compound south of Podol Plaza', 'Pool of Radiance (DOS)  |  area map  |  SPOILERS'),
    source_note=('GEO4 block 2, ECL4 block 2, MON4CHA, ITEM4.', 'Grid: (column,row) from 0, top left, north up.'),
    geo=('GEO4', 2),
    start=(4, 0),
    exits=[(4, 0, 'W'), (11, 0, 'W'), (4, 15, 'E'), (11, 15, 'E'), (0, 4, 'N'), (0, 11, 'N')],
    hatch_events={22: ('#f3d9d3', '#d89b90')},
    legend=['arrival', 'exit', 'door', 'lock2:locked door (Bash / Pick / Knock)', 'hatch:hobgoblin yard (P)'],
    rooms=[
        ('COURTYARD', 10.5, 7.5, 5.2, '#8a3b30', True),
        ('barracks', 8.55, 5, 4.6), ('barracks', 8.55, 7, 4.6),
        ('TEMPLE', 12, 2.5, 4.6), ('stench', 14.5, 5, 4.2), ('stench', 14.5, 7, 4.2),
        ('kitchen', 11.5, 10, 4.4),
    ],
    markers=[
        ('1', 3, 1, 'secret', dict(dx=-1, dy=-4)),
        ('2', 10, 8, 'fight'), ('2', 10, 4, 'fight'), ('2', 13, 8, 'fight'),
        ('3', 9, 5, 'fight', dict(dy=-3)), ('3', 9, 7, 'fight', dict(dy=-3)),
        ('4', 8, 2, 'fight'), ('5', 11, 3, 'fight', dict(dy=-4)), ('6', 14, 3, 'fight', dict(dy=-4)),
        ('7', 15, 2, 'hint'), ('8', 14, 12, 'fight', dict(dx=5, dy=5)), ('9', 14, 11, 'secret', dict(dx=12, dy=-6, rad=5.8)),
        ('K', 9, 9, 'hint', dict(dy=3)),
    ],
    diamonds=[('d', 3, 3, 'loot'), ('d', 6, 3, 'loot'), ('d', 6, 7, 'loot'), ('d', 6, 10, 'loot'),
              ('d', 8, 1, 'loot'), ('d', 8, 15, 'loot'), ('d', 13, 0, 'loot')],
    glance=('<b>ARRIVE</b> at (0,4) facing west from the city\'s west entrance (south route). <b>LEAVE:</b> west gates (0,4) and (0,11) (back to the overland map), '
            'north gates (4,0) and (11,0) (Podol Plaza), east gates (15,4) and (15,11) (an overgrown garden and old library), and a hidden gate at (15,3) (east). '
            '<b>QUEST:</b> City Hall\'s Councilman Cadorna wants his family treasure from "the western building of the textile complex"; his servant never came back. '
            '<b>REWARD:</b> the City Hall clerk pays <b>250 gold + 200 platinum</b> once the house is cleared (see CLEARING below). '
            '<b>NO</b> shops and no search-only treasure; the only trap is the well\'s fall. Everything else is a fight or a line of text; the yard is hobgoblin land until the chief dies.'),
    entries=[
        ('P', 'fight', 'Random encounters ' + tag('fight', 'FIGHT') + '  (red hatch = hobgoblin yard)',
         'Each step on an ordinary cell has a 1 in 31 chance of a pack (1 in 6 when searching with the S key). Hatched yard: <b>always</b> 8 Hobgoblins + 1 Leader until the chief (8) is dead. '
         'Elsewhere the pack depends on (fights so far + a roll of 0 to 10): 0-3: 8 Poisonous Frogs; 4-7: 3 Large + 1 Huge Scorpion; 8-12: 1 Wight + 5 Ghouls; '
         '13-17: 1 Wight + 10 Skeletons + 8 Zombies; 18+: 8 Hobgoblins + 1 Leader. At most <b>9</b> while the chief lives; once he is dead the <b>10th</b> roll is no fight but marks the house cleared. '
         'Fleeing drops you at (4,2) or (12,2).'),
        ('1', 'secret', 'The well (1,3)  ' + tag('secret', 'THIEVES\' GUILD'),
         '"THIEVES ONLY." CLIMB DOWN, pick a character: a roll of 0-99 below that character\'s thief skill meets <b>Restal</b> the old thief; otherwise "a long fall" '
         '(one protective effect, looks like feather fall, means 8 arrows of 1d6; anyone else takes 15d6 no save stops) and a laughing thief lifts you out. '
         'He talks only after City Hall told you of the treasure. <b>No box yet</b>: blindfolded, you are led to (6,11) facing north, courtyard (2) counted as won. '
         '<b>Box taken unopened</b>: "duplicate the seal" for <b>200 pp, 4 gems, 2 jewelry + the same 5 items as the box (8)</b>, and you still hand the box over.'),
        ('2', 'fight', 'Courtyard (4,10), (8,10), (8,13)  ' + tag('fight', 'FIGHT'),
         '"A weedy, garbage strewn courtyard. A drum begins to beat": <b>12 Hobgoblins + 2 Leaders</b> on the first step on any of the three cells. '
         'Won: the drum fades, the temple (5) opens. Fled: "chased out into the streets" (4,2) or (12,2), it returns.'),
        ('3', 'fight', 'Barracks (5,9), (7,9)  ' + tag('fight', 'FIGHT'),
         '<b>14 Hobgoblins + 3 Leaders</b>; fleeing lands you at (4,11), (8,8), (4,14) or (12,13). Once beaten: gone for good.'),
        ('4', 'fight', 'Tapestry room (2,8)', '<b>10 Hobgoblins + 2 Leaders</b>, back each time you re-land.'),
        ('5', 'fight', 'Grishnak\'s temple (3,11), (2,12)  ' + tag('fight', 'BOSS') + '  ' + tag('loot', 'LOOT'),
         'Only after the courtyard (or the guild route). <b>Grishnak + 3 Leaders + 12 Hobgoblins</b>. '
         + tag('loot', '100 cp, 20 sp, 30 ep, 40 gp, 8 pp, a Brass Key') + ', 2 magic-user scrolls, Scale Armor, Stone Statuette, Quarter Staff, a Potion, a cursed Necklace (-5). (2,13) (south) is blood-smeared, text only.'),
        ('6', 'fight', 'Graffiti room (2,14), (3,14)', 'Behind locked doors. <b>12 Hobgoblins + 2 Leaders</b>, once.'),
        ('7', 'hint', 'Prisoner ((2,15), behind a locked door)  ' + tag('hint', 'SKULLCRUSHER'),
         'A chained muscular man (journal entry 47). FREE needs the <b>Brass Key</b> (picking and breaking fail). Then PARLAY with any attitude but ABUSIVE: '
         '"I\'m Lord Cadorna\'s servant": <b>Skullcrusher (level 4, AC 10, HP 39) joins you</b> (free slot needed) and mentions "a secret door to the southeast". '
         'ABUSIVE or ATTACK: he fights you; ATTACK while chained: he dies.'),
        ('8', 'fight', 'Hobgoblin chief (12,14)  ' + tag('fight', 'BOSS') + '  ' + tag('loot', 'IRON BOX'),
         'Reach it through 9. <b>Ogre chief + 18 Hobgoblins + 4 Leaders</b>; his death ends the yard ambushes. The <b>iron box</b> (Cadorna\'s seal): '
         '<b>TAKE IT UNOPENED</b> (the city watch confiscates it later, the clerk pays <b>20 gems</b>) or <b>OPEN IT</b> (Cadorna is angry, no gems): '
         + tag('loot', '450 cp, 20 sp, 400 pp, 8 gems, 4 jewelry, Gauntlets of Ogre Power, Gold Banded Wand, Jewel Studded Bowl, Jewelled Dragon Statuette, a Ring') + '. Asked once only.'),
        ('9', 'secret', 'Secret door (east wall of (11,14))',
         'Drawn as a door here, but in the game a wall (id 4, like the outer wall); the hint is Skullcrusher\'s, who says it when he is with you. Another hidden gate: the east edge at (15,3).'),
        ('K', 'hint', 'Dead hobgoblin (9,9)', '"SKULLCRUSHER WAS HERE" in blood (a dark object is seen from (11,9)). SEARCH and DESTROY find nothing.'),
        ('d', 'loot', 'Diary page (3,3), (3,6), (7,6), (10,6), (1,8), (15,8), (0,13)', 'Any one of these cells gives the same page, journal entry 11 (once a visit). (3,6) is behind a locked door.'),
    ],
    table=dict(
        rows=[['Monster', 'No.', 'Lvl', 'AC', 'HP', 'Where'],
              ['Hobgoblin / Leader', '9-22', '2', '5', '6', 'yard, 2-6, 8'], ['Ogre (chief)', '1', '5', '5', '21', '8'],
              ['Grishnak', '1', '6', '5', '24', '5'], ['Skullcrusher', '1', '4', '10', '39', '7 (if hostile)'],
              ['Poisonous Frog', '8', '1', '8', '4', 'street'], ['Large / Huge Scorpion', '3+1', '3/5', '5/4', '10/20', 'street'],
              ['Wight / Ghoul', '1 / 5', '5/2', '5/6', '23/10', 'street'], ['Skeleton / Zombie', '10 / 8', '1/2', '7/8', '5/10', 'street']],
        widths=[84, 28, 22, 22, 28, 0],
        caption='Lvl, AC (descending), HP as stored in the game files. Group sizes here are fixed, not scaled to the party.'),
    boxes=[
        '<b>CLEARING</b>  Kill the chief (8), then walk on: the 10th random roll marks the house cleared and the City Hall clerk pays <b>250 gp + 200 pp</b>. '
        '<b>STAYS</b> done: courtyard, barracks, graffiti room, Grishnak, prisoner, chief and box choice, the fight count. '
        '<b>RESETS</b> on re-landing: tapestry room, diary page, text rooms, Restal\'s offers.',
        '<b>ORDER</b>  Take Cadorna\'s commission at City Hall. Courtyard (2) or the well (1), then the temple (5) for the Brass Key, free Skullcrusher (7), '
        'barracks and tapestry rooms, chief (8) via 9. <b>TEXT ONLY</b>: stench rooms (5,14) and (7,14), (3,9), (5,15) (baby hobgoblins), kitchen (9,12)-(11,11), fire (10,12), (6,14) carving. '
        '<b>LOCKED</b> (orange, 11): they gate the graffiti room and prisoner, the west strip (0,8)-(1,15) (from (1,10)-(2,10); diary cells (1,8), (0,13)), the east strip (12,11)-(15,11), and single closets (3,6).',
    ],
)
