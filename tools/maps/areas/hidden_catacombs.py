"""The hidden catacombs under Kuto's Well: GEO8 block 32, run by the script ECL8 block 29 (tile set 8).
Read from the area script (see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='hidden-catacombs',
    title='HIDDEN CATACOMBS',
    subtitle=("Norris the Gray's bandit lair under Kuto's Well (ECL8/29)", 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Read from the game files: area map GEO8 block 32, run by the script of ECL8 block 29,',
                 'monsters MON8CHA, loot ITEM8. Grid: columns A-P, rows 1-16, north is up.'),
    geo=('GEO8', 32),
    start=(7, 7),
    locked_rules={(6, 6), (7, 6)},
    legend=['arrival', 'door', 'locked:secret door (found by searching)', 'grey:solid rock'],
    markers=[
        ('9', 8, 7, 'fight'), ('6', 8, 5, 'secret'), ('7', 7, 5, 'secret'),
        ('10', 13, 4, 'fight'), ('10', 14, 4, 'fight'), ('11', 10, 1, 'fight'), ('11', 10, 2, 'fight'), ('11', 10, 3, 'fight'),
        ('12', 3, 10, 'fight'), ('12', 5, 1, 'fight'), ('12', 5, 5, 'fight'), ('13', 1, 13, 'loot'),
    ],
    glance=("<b>ARRIVE</b> at H8, the bottom of Kuto's Well: from the surface map (ECL8/29) the well asks \"Rungs are set in the sides of the well wall. Do you want to climb down?\" "
            "once you have beaten the two kobold ambushes there on your first visit (6 Kobolds + 3 Kobold Leaders each). <b>EXIT</b> the same way: on H8 the script asks "
            "\"Just above the waterline, a secret door has been left ajar... Do you want to climb up the rungs?\". "
            "<b>THE POINT:</b> Norris the Gray and his band wait for you wherever you go (the first of the cells 12). Beat them for journal entry 50, "
            "the City Hall bonus and a treasure room; surrender and you lose everything. No random fights underground. "
            "Flags marked once per visit reset when you leave Kuto's Well. Numbers on the map are the script's event ids."),
    entries=[
        ('16', 'place', 'Well bottom (H8)',
         'The only way in and out. Climbing up costs nothing: "You make the long, arduous climb up the well." Saying NO to the climb leaves you here; the door south (H9) opens the catacombs.'),
        ('9', 'fight', 'Torch-lit room (H9)',
         '"You pass into hidden catacombs. This large room is dimly lit by sputtering torches... curtains hung to cover doorways." While Norris lives, once per visit: '
         '"A volley of arrows tears into the group": ' + tag('fight', '4 hits of 1d6') + ' on random members. (Doorways with the curtains are the amber doors.)'),
        ('10', 'fight', 'Arrow traps (E14, E15)',
         'While Norris lives, once per visit: "A dimly seen figure fires an arrow into the party. The figure fades away." ' + tag('fight', '1 hit of 1d6') + '.'),
        ('11', 'fight', 'Arrow trap (B11, C11, D11)', 'The same trap with its own once-per-visit flag.'),
        ('6', 'secret', 'Secret door (F9, north wall)',
         'The step is blocked until found: standing on F9 or F8 (7) takes a search. Each member rolls once per look: a bonus of 1 for elves and half-elves '
         '(a race table, inferred) plus 1 in search mode (S key), found if the bonus beats a d6 minus 1. So non-elves need the S key (1 in 6 each); '
         'an elf searching has 2 in 6. "You find a secret door in the north wall" (from F8: south wall). Found for this visit only. It is only a short cut: the map stays connected without it.'),
        ('12', 'fight', "Norris the Gray's ambush (K4, B6, F6)",
         '"You are surrounded by the bandit band of the infamous Norris the Gray. \'You dare to invade my halls?\' Surrender or die!" '
         'The first of the three cells you step on triggers it: ' + tag('fight', 'Norris the Gray + 5 Lizardmen + 9 Kobold Leaders') + '. '
         'Resting underground (camp interrupted) brings the same ambush while he lives. SURRENDER: stripped of all money and items, blindfolded and released above ground; '
         'Norris is then marked done for good (never again) but you get no hideout. FIGHT and lose or flee: back on the surface, nothing lost. '
         'FIGHT and win: journal entry 50 ("a curious message"), "You have defeated the dreaded bandit gang and rid Phlan of a great evil", '
         '"possession of a hideout in which you may rest undisturbed", and City Hall pays a bonus (not traced).'),
        ('13', 'loot', "Bandit treasure (N2)",
         'After a win: "You have found the bandit\'s treasure. Do you take it?" ' + tag('loot', '2300 sp, 92 gp, 20 gems') + '. Only in the visit in which you beat Norris (a visit flag); taken once.'),
        ('X', 'hint', 'No script (F12, F13, F14)',
         'Cells with event ids 14, 8 and 15 are in the map but the script has no handler for them: they do nothing.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Norris the Gray', '5', '10', '25', 'Kobold Leader', '0', '7', '4'], ['Lizardman', '3', '4', '11', '', '', '', '']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON8CHA).'),
    boxes=[
        '<b>ORDER</b> Beat the kobolds at the well, climb down (H8), go south through H9 (arrows once), find Norris; if you win, take the treasure N2 in the same visit.',
        '<b>EVIDENCE</b> The map is loaded when the script reaches LOADGFX 32 (the climb down). Event ids 6, 7, 9 to 13 and 16 are read by its search entry (id 0 gives no random fight underground), '
        'ids 6 and 7 by its step entry (the secret door). Inferences: the amber doors with wall id 10 are the curtains; the green cells are the cells without the interior bit.',
    ],
)
