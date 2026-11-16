"""The nomad camp on the north shore: GEO7 block 17, ECL7 block 17 (tile set 7). Read from the area script
(see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='nomad-camp',
    title='NOMAD CAMP',
    subtitle=("Hassad Ahwal's tribe, north shore wilderness", 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    geo=('GEO7', 17),
    start=(14, 1),
    exits=[(0, 3, 'N'), (15, 3, 'S'), (8, 0, 'W')],
    hatch_events={1: ('#f3d9d3', '#d89b90'), 4: ('#e3e9ee', '#aab8c2')},
    legend=['arrival', 'exit', 'door', 'hatch:sentry ring (first contact)', 'hatch:outskirts (no first contact)',
            'grey:palisade, no way in'],
    rooms=[
        ('tent', 4, 8, 4.4), ('tent', 6, 5, 4.4), ('tent', 6, 9, 4.4), ('tent', 6, 11, 4.4), ('big tent', 8.5, 7.5, 4.6),
        ('tent', 8, 12, 4.4), ('tent', 10, 5, 4.4), ('tent', 11, 7, 4.4), ('tent', 11, 11, 4.4), ('guest', 12, 9, 4.4, '#9a6b2f', True),
    ],
    markers=[
        ('1', 8, 3, 'hint'), ('3', 9, 9, 'place', dict(dy=-3)), ('2', 12, 10, 'place'), ('4', 7, 13, 'fight'),
    ],
    glance=('<b>ARRIVE</b> at (1,14), facing east, by choosing ENTER at the Nomad Camp on the North Shore map (25,11). '
            '<b>LEAVE</b> by stepping off the north, south or west edge and answering yes, or by fleeing. The camp is open ground: '
            'the only triggers are the <b>sentry ring</b> (red hatch) and the clock. The tribe: chief <b>Hassad Ahwal</b> '
            '(level 6), a shaman, 5 fourth-level guards, about 50 nomads. <b>Befriend them</b> (feast, kobold raid): 3000 gp + 5000 gp + '
            'Two-Handed Sword +2 + a Wand. <b>Or kill them all</b>: 5000 gp. Either way leaving counts for City Hall: 6 gems + 2 jewelry.'),
    entries=[
        ('1', 'hint', 'First contact: the sentry ring',
         'Stepping on any red cell (3,4)-(3,12), (3,4)-(5,4), (6,2)-(7,2), (6,3), (8,1)-(11,1), (4,13)-(6,13), (7,14)-(11,14) before you have accepted hospitality. Clock hour 14 or earlier: '
         'a crowd gathers. Later: half the time you first trip a wire (bells): FLEE / ADVANCE CAUTIOUSLY / ATTACK. '
         'The crowd menu: fight, wait, flee (leaves the camp) or <b>parley</b>. The outskirts (blue) never start first contact.'),
        ('P', 'hint', "The headman's offer (parley at the crowd menu)",
         'Hassad offers a feast tonight (clock hour under 14) or tomorrow. ' + tag('hint', 'YES') + ' accepts. NO: "then you must leave us", leave or '
         + tag('fight', 'refuse and the tribe is hostile') + '. Hostile also follows any attack on them, and killing the guard (below).'),
        ('2', 'place', 'Guest hut (9,12) and the guards',
         'Offered after dark: you are led here and rest (camp menu). While lodged, walking into any other tent door brings a guard: FOLLOW (back to the hut) or '
         + tag('fight', 'ATTACK ("they have slain Samir!") makes the camp hostile') + '.'),
        ('3', 'place', 'Games and the feast (central clearing (9,9))',
         'You are led to the clearing (the next morning if you arrived late in the day): contests, then the night feast. Chief, tongue loosened by drink, gives you <b>journal entry 55</b> '
         '(dangers of the region) and begs you to stay: a large kobold band is near. After a night in the hut, at the next morning (clock hour 0 or 1; '
         'rest through midnight, not confirmed) he asks again: <b>STAY AND FIGHT</b> or LEAVE (wished luck; the raid still comes if you return after 18).'),
        ('4', 'fight', 'Kobold raid (after you agreed, from clock hour 18)',
         'About 1 step in 4, anywhere (in the outskirts the kobolds come alone, no nomad help). Three raids in turn ("kobolds attacking the camp", then kobolds in melee with nomads; nomads fight beside you, '
         'a scaled number of Kobolds). The fourth: a huge horde; the chief asks "finish this together?" <b>DESTROY THE KOBOLDS</b>: Hassad + 2 guards + '
         + tag('fight', '53 Kobolds') + ', loot 3000 gp; then the shaman pays ' + tag('loot', '5000 gp, Two-Handed Sword +2, a Wand') + '. FLEE: the chief charges alone and '
         'pays only ' + tag('loot', '500 gp') + '. No retreat from column 11 eastwards ("nowhere left to retreat").'),
        ('H', 'fight', 'If the tribe turns hostile',
         'Day (before 18): about 1 step in 4 a wave of nomads (scaled to your party), three waves, then the chief rallies the tribe: Hassad, shaman, '
         + tag('fight', '5 fighters + 49 Nomads') + ', loot ' + tag('loot', '5000 gp') + '. Night: kobolds join and the tribe attacks too: shaman, chief, fighters + 49 Kobolds, '
         + tag('loot', '8000 gp') + '. Once the tribe is dead kobold raids still come at night (3000 gp for the horde).'),
        ('L', 'hint', 'Leaving and City Hall',
         'Leave after accepting the feast, or after wiping the tribe out: the quest counts as done. The City Hall clerk then pays '
         + tag('loot', '6 gems + 2 jewelry') + ' ("FIND THE NOMADS AND STOP THEM"). Walking off an edge asks "back into the wilderness?"; fleeing in the west half moves you back '
         'to a fixed cell of your 4x4 block ((4,4) (7,4) (11,4) (4,6) (8,7) (13,6) (4,10) (8,10) (13,9) (4,12) (8,11) (10,11)).'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Where'],
              ['Nomad', '1', '6', '6', 'tribe, 49-50'], ['4th Lvl Fighter', '4', '8', '30', 'guards, 5'],
              ['Hassad (headman)', '6', '2', '45', '1'], ['Shaman', '5', '9', '20', '1'], ['Kobold', '0', '7', '3', 'raids, 53']],
        widths=[84, 20, 20, 24, 0],
        caption='Lvl, AC (descending), HP as stored in the game files. Counts marked scaled depend on party strength.'),
    boxes=[
        '<b>TIME</b> the game reads the clock hour: from 14 on counts as "tomorrow" (dark palette), from 18 it is the kobold hour. That these are evening hours is not confirmed. '
        '<b>NO SECRETS</b> no passwords, traps, locked doors or search spots; wall segments with amber bars are open gaps, thick black walls (palisade) are solid.',
        '<b>NOT CONFIRMED</b> exactly how party strength sets group sizes; how nomad allies are handled in the raid (computer-run, probably); the North Shore symbol that changes at (25,11) after the camp is resolved. '
        'If your party harms its nomad allies the tribe probably turns hostile.',
    ],
)
