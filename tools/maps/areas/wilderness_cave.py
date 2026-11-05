"""The small dark cave in the mountain wilderness: GEO6 block 25, wilderness script ECL6 block 25 (tile set 6).
Read from the area script (see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='wilderness-cave',
    title='SMALL DARK CAVE',
    subtitle=('A random cave in the mountain wilderness: four separate lairs', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Read from the game files: cave map GEO6 block 25, wilderness script ECL6 block 25,',
                 'monsters MON6CHA, loot ITEM6. Grid: columns A-P, rows 1-16, north is up.'),
    geo=('GEO6', 25),
    start=(3, 15),
    arrivals=[(2, 0), (9, 0), (15, 11)],
    wrap=True,
    exits=[(2, 0, 'W'), (2, 15, 'E'), (3, 0, 'W'), (3, 15, 'E')],
    legend=['arrival', 'exit:wraps to the far edge'],
    rooms=[
        ('BOAR LAIR', 6.0, 2.5, 6.0, '#7a2b24', True), ('AHNKHEG LAIR', 3.0, 12.5, 6.0, '#7a2b24', True),
        ('THRI-KREEN LAIR', 12.0, 3.0, 6.0, '#7a2b24', True), ('GIANT SNAKE LAIR', 12.0, 12.0, 6.0, '#7a2b24', True),
    ],
    markers=[
        ('1', 0, 0, 'fight', dict(dx=5, dy=-4)), ('2', 2, 5, 'fight'), ('3', 4, 0, 'fight', dict(dx=5)),
        ('4', 0, 11, 'hint'), ('4', 2, 13, 'hint'), ('5', 3, 9, 'hint'), ('5', 6, 15, 'hint', dict(dy=5)),
        ('6', 1, 4, 'loot'), ('7', 3, 6, 'fight'),
        ('8', 11, 9, 'hint'), ('8', 7, 14, 'hint'), ('9', 14, 13, 'fight'), ('10', 14, 15, 'fight'),
        ('11', 7, 5, 'fight'), ('12', 11, 6, 'fight'), ('13', 8, 2, 'loot'),
    ],
    glance=('<b>ARRIVE</b> in one of the four green S cells; the script picks one at random (1 in 4 each: P4, A3, A10 or L16), and each is a '
            'separate lair with its own fights. The passages wrap around the map edge: P4 and A3 open onto rows 3 and 4 of the far edge. '
            '<b>HOW YOU GET HERE:</b> a step in the wilderness around it has a 1 in 20 chance of an encounter roll, and 1 in 21 of those '
            '(never after a camp interruption) finds it: "YOU HAVE FOUND A SMALL DARK CAVE. WILL YOU ENTER?", about 1 step in 420. '
            '<b>EXIT:</b> the arrival cell: "YOU HAVE FOUND A PASSAGE WHICH LEADS OUTSIDE" (LEAVE CAVE / STAY IN). '
            '<b>RESETS:</b> the fights are flags for this visit only: leaving and coming back refills the lairs. No random fights inside. '
            'Numbers on the map are the script\'s event ids.'),
    entries=[
        ('1', 'fight', 'Wild boars (A1)', '"Out of the shadows, two large wild boars charge." 2 Wild Boars.'),
        ('2', 'fight', 'Sow and young (F3)',
         '"A large, wild boar sow feeding her young... she growls a warning to stay away." APPROACH or LEAVE. If you approach she attacks: '
         '1 Wild Boar. The script marks the fight done in a scratch word, never in the visit flag, so it comes back each time you step on F3.'),
        ('3', 'fight', 'End of the passage (A5)', '"At the end of the passageway are three large wild boars." 3 Wild Boars.'),
        ('4', 'hint', 'Dwarf remains (L1, N3)', '"The dissolving remains of a dwarf, covered in acid": the ahnkheg warning.'),
        ('5', 'hint', 'Churned ground (J4, P7)', '"The ground here is soft and freshly churned."'),
        ('7', 'fight', 'Ahnkheg (G4)', '"From the south, a large ahnkheg lunges out and attacks." 1 Ahnkheg.'),
        ('6', 'loot', 'Victims\' remains (E2)',
         '"Admist the debris is some treasure." ' + tag('loot', '5000 cp, 2000 sp, 500 ep, 1 gem') + ', paid with no fight. Once per visit.'),
        ('8', 'hint', 'Shed snake skin (J12, O8)', '"A large, shedded snake skin."'),
        ('9', 'fight', 'Giant snake (N15)', '"A gigantic snake lies in front of you. It rears and attacks." 1 Giant Snake.'),
        ('10', 'fight', 'Snake from above (P15)', '"A giant snake falls on top of the party." 1 Giant Snake; the script sets the surprise word to 1 ("you are surprised").'),
        ('11', 'fight', 'Thri-kreen block (F8)',
         '"Two thri-kreen block the passage with their bodies." LEAVE (you are put back where you were) or ATTACK: 2 Thri-kreen.'),
        ('12', 'fight', 'Warriors (G12)', '"Before you are three thri-kreen warriors. They attack immediately." 3 Thri-kreen.'),
        ('13', 'loot', 'Chest room (C9)',
         '"Four thri-kreen warriors; on the floor is a chest." 4 Thri-kreen, then ' + tag('loot', '2000 sp, 1000 gp, 3 gems, 1 jewelry, 1 random treasure roll') + '.'),
        ('W', 'hint', 'The wilderness above (ECL6 block 25)',
         'Overland (column,row) spots from the same script: <b>(10,9)</b> dragon cave, with six sighting cells around it; <b>(8,24)</b> two ahnkhegs once per visit; '
         '<b>(3,32)</b> Zhentil Outpost ("diplomatic envoys from New Phlan?"; YES only if City Hall gave you the message packet, else the riders tell you to leave and, if you stay: '
         '12 corporals); <b>(12,31)</b> Buccaneer Base (only while the "rescue the heir of Bivant" quest is open). '
         'Random packs per roll of 20: boars 3, tigers 3, thri-kreen 2, centaurs 2 (peaceful), soldiers 2, quicklings 2, giant snakes 2, mantis, '
         'ahnkheg, thieves 1 each, and 1 that jumps to the Buccaneer Base prompt (looks like a script slip: the slot calls the base handler).'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Wild Boar', '4', '7', '18', 'Tiger', '6', '6', '38'], ['Ahnkheg', '8', '2', '40', 'Giant Mantis', '10', '3', '55'],
              ['Giant Snake', '5', '5', '25', 'Centaur', '4', '5', '20'], ['Thri-kreen', '7', '5', '33', 'Corporal', '2', '6', '13']],
        widths=[58, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON6CHA). Wilderness-only monsters on the right.'),
    boxes=[
        '<b>LAIRS</b> P4 (31 cells): boars 1, 2, 3. A3 (63 cells): ahnkheg 4, 5, 6, 7. A10 (62 cells): thri-kreen 11, 12, 13. L16 (56 cells): giant snakes 8, 9, 10. '
        'About 44 cells are closed pockets nobody can reach (grey).',
        '<b>NOT TRACED</b> the dragon cave itself (ECL6 block 19) and the Buccaneer Base (ECL6 block 1) are other areas. The overland map is not a 16x16 plan, '
        'so only the script\'s coordinates are given. Group sizes in random packs scale with party strength.',
    ],
)
