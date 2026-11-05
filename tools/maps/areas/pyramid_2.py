"""The sorcerer's pyramid, Yarash's laboratory level: GEO7 block 23, ECL7 block 23 (tile set 7). Read from the area
script (see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='pyramid-2',
    title='YARASH\'S LAB',
    subtitle=("Pyramid on the north shore, laboratory level", 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Read from the game files: area map GEO7 block 23, event script ECL7 block 23,',
                 'monsters MON7CHA, loot ITEM7. Grid: columns A-P, rows 1-16, north is up.'),
    geo=('GEO7', 23),
    start=(15, 4),
    # every cell a teleport (of this level or the maze level) can put you on
    extra_starts=[(12, 0), (0, 0), (4, 0), (8, 3), (13, 3), (9, 4), (0, 6), (0, 7), (3, 11), (3, 12), (13, 14), (12, 15), (3, 0),
                  (12, 14), (3, 13)],
    illusion_ids=[4],
    legend=['arrival', 'search', 'door', 'illusion:secret door (search to find)', 'lock2:locked door (Bash / Pick / Knock)',
            'grey:solid / no way in'],
    rooms=[('LAB', 11, 1, 5.0), ('STORE', 10, 4.5, 4.6), ('STORE', 1, 9, 4.6), ('STORE', 14, 14, 4.6), ('VATS', 11, 14, 5.0)],
    markers=[
        ('1', 1, 1, 'hint', dict(dy=-4)), ('2', 1, 2, 'place', dict(dy=-4)), ('3', 1, 4, 'fight', dict(dy=-3)), ('4', 1, 6, 'loot', dict(dy=3)),
        ('5', 0, 5, 'hint'), ('6', 0, 6, 'secret'),
        ('7', 10, 1, 'place'), ('8', 13, 3, 'fight'), ('9', 13, 9, 'place'), ('10', 10, 14, 'fight'), ('11', 4, 5, 'fight'),
        ('f', 0, 7, 'secret'), ('f', 9, 4, 'secret'), ('f', 13, 14, 'secret'), ('f', 8, 15, 'secret'),
        ('R', 2, 0, 'secret'), ('R', 3, 12, 'secret'), ('R', 12, 15, 'secret'),
    ],
    diamonds=[('$', 11, 5, 'loot'), ('$', 2, 8, 'loot'), ('$', 15, 14, 'loot'), ('n', 12, 2, 'hint')],
    glance=('<b>ARRIVE</b> at E16 (facing north) from the maze level\'s rock room, or at A13 from its flash cell. Everything here is joined by '
            '<b>secret doors</b> and <b>teleports</b>; the <b>dial</b> (F1) decides where the G1 teleporter sends you. This is the laboratory of the mage '
            '<b>Yarash</b> (E2), who mutates lizard men with black pollution. <b>End the pollution</b> by killing Yarash or wrecking the fountain chamber (C2): '
            'City Hall pays <b>250 platinum + 15 jewelry</b> ("clearing of the Stojonow river"). Three storerooms ($) hold 1200 sp + 400 gp + 3 treasure rolls each. '
            '<b>Danger:</b> a wrong password at B2 (201 damage to every member, no save).'),
    entries=[
        ('1', 'hint', 'Password sign (B2, facing east)',
         'A sign over the door: "DON\'T FORGET THE PASSWORD", six dwarvish runes (the same three twice). Type <b>NOKNOK</b> (the two three-rune halves match, inferred). '
         + tag('fight', 'Any other word') + ': a hidden door bursts open and a monster tears you apart: 201 damage to every member, no saving throw (once). The right word does nothing '
         'and the sign asks again each time.'),
        ('2', 'place', 'Fountain chamber (C2, facing east)',
         'Black pollution pumped through pipes. MOVE QUICKLY AWAY, or DESTROY THE EQUIPMENT (10 pieces). Each piece has 1 chance in 10 to start the pipes whining; from then on '
         'each further round raises the pressure and you must leave within two more rounds or it explodes: ' + tag('fight', '3d10 to every member, no save') + '. '
         'Wrecking it (or fleeing in time) ends the pollution: quest flag [4AB3].'),
        ('3', 'fight', 'Yarash and his guards (E2)',
         'Doors: S from E3, or west from D2 (locked, Bash / Pick / Knock). "I need more specimens as controls": no parley. <b>Yarash</b> (level 9) + '
         + tag('fight', '6 Mutant Liz-men') + ' (level 4). No treasure; killing him ends the pollution (as 2). Flee: thrown to A1.'),
        ('4', 'loot', 'Yarash\'s desk (G2)',
         'Search (S) once: journal entries <b>33</b> (the Boss: join or die), <b>49</b> (unsent reply), <b>27</b> (bounty for a real sahuagin), <b>56</b> (danger in the NW mountains), <b>40</b> (kobolds and hobgoblins).'),
        ('5', 'hint', 'The dial (F1)',
         'Four colors: BLUE, COPPER, SILVER, GOLD (stays set; BLUE at the start, inferred). ' + tag('secret', '6') + ' G1 flashes you away by the setting: <b>BLUE</b> back to the maze level (P9 there), '
         '<b>COPPER</b> to E10, <b>SILVER</b> to H1, <b>GOLD</b> to O14 (each the door of a storeroom).'),
        ('f', 'secret', 'Flash cells (f)',
         'E10, H1, O14 throw you back to G1. P9 throws you to D14, into the lizard men (8). The cell you land on does not fire again until you step on it afresh (inferred).'),
        ('R', 'secret', 'Rock rooms (A3, M4, P13)',
         'Same switch as the maze level (S shows the tingle; GO BACK / MOVE ON / THROW A ROCK). A flash alternates: A3 to A1 or N4; M4 to A5 or O13; '
         'P13 to L4 or back to the maze level (P8). GO BACK steps you out (A4, N4, O13).'),
        ('$', 'loot', 'Storerooms (E10-F12, H1-J3, N15-P16)',
         '"A vast collection of magical junk." Search (S) once in each: ' + tag('loot', '1200 silver, 400 gold, 3 treasure-table rolls') + '. Enter only through the dial.'),
        ('7', 'place', 'Alchemist\'s lab (B11-C13)',
         'Ordinary alchemist\'s lab, "recently used". Search: a notebook ("subject 213: scars healing, unable to talk yet ... 214 died"). Secret doors A11|B11 and C12|D12.'),
        ('8', 'fight', 'Lizard men closet (D14)',
         '5 Lizardmen: "wary, not hostile". Parley: attitude (HAUGHTY/SLY 15, NICE 30, MEEK 50, ABUSIVE 0) + charisma bonus must reach 75 (MEEK from CHA 8, NICE from about CHA 16): '
         '"the enemy of my enemy..." and peace. Else a fight, no loot. Secret door D13|D14.'),
        ('9', 'place', 'Torture room (J14)', 'Instruments, a table with restraints, alchemical flasks. Text only. Secret door J13|J14.'),
        ('10', 'fight', 'Vat room (N10-P12)',
         'Secret door M12|N12. Search among the vats (S): a pain-crazed lizard man and two more attack (' + tag('fight', '3 Mutant Liz-men') + '), once.'),
        ('11', 'fight', 'Pumping room (F5)',
         'Three shackled lizard men "recoil in fear". Parley <b>NICE or MEEK</b>: they tell of Yarash and of help from their swamp tribe, <b>journal entry 35</b>. '
         'Otherwise they hurl contaminant (two random members take 201 unless they save) and fight (3 Lizardmen).'),
    ],
    table=dict(
        rows=[['Monster (MON7CHA)', 'Lvl', 'AC', 'HP'],
              ['Yarash', '9', '9', '27'], ['Mutant Liz-Man', '4', '3', '18'], ['Lizardman', '3', '4', '11']],
        widths=[100, 22, 22, 0],
        caption='Lvl, AC (descending), HP as stored in the game files.'),
    boxes=[
        '<b>SECRET DOORS</b> A11|B11, C12|D12, D13|D14, J13|J14, M12|N12: found by standing on either cell (about 1 chance in 6 per member per step, 2 in 6 with S, +1 in 6 for elves and half-elves); '
        'until found they block you. <b>PERSISTS</b> flags of this level are never reset by the script.',
        '<b>NOT TRACED</b> how the maze level\'s quest hooks start (the clerk\'s commission, see City Hall); the "alchemical lab" text appears once for B11 or C12; the grey regions are solid wall (no door, no teleport lands there).',
    ],
)
