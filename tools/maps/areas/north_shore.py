"""The north shore wilderness: ECL7 block 26 (the wilderness script) with the lizard men's grove, GEO7 block 26
(tile set 7). Read from the area script (see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='north-shore',
    title='NORTH SHORE',
    subtitle=("Wilderness north of Old Phlan, and the lizard men's grove", 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Read from the game files: wilderness script ECL7 block 26, grove plan GEO7 block 26,',
                 'monsters MON7CHA. Grid: columns A-P, rows 1-16 (grove plan only), north is up.'),
    geo=('GEO7', 26),
    start=(3, 2),
    extra_starts=[(13, 10), (6, 13)],
    exits=[(0, 7, 'N')],
    legend=['arrival', 'exit', 'door', 'grey:rim / not walkable'],
    rooms=[('POOL', 4, 4, 5.0), ('LIZARD HUTS', 13, 5.5, 5.4, '#9a6b2f', True)],
    markers=[
        ('1', 3, 4, 'fight', dict(dy=-1)), ('2', 6, 2, 'fight'), ('3', 14, 8, 'hint'), ('4', 11, 7, 'hint'), ('5', 11, 9, 'fight'),
        ('6', 11, 2, 'fight'), ('7', 15, 2, 'fight'), ('8', 3, 13, 'fight'), ('8', 5, 10, 'fight'), ('8', 5, 12, 'fight'),
        ('a', 13, 10, 'place'), ('a', 6, 13, 'place'),
    ],
    glance=('The script of this block runs the <b>world map</b> of the north shore (the shared wilderness map, squares (x,y); not a 16x16 plan). '
            'The plan on this page is only the <b>lizard men\'s grove</b>, a rare random discovery. Special squares: <b>nomad camp</b> (12,11); '
            '<b>Old Phlan</b> edges (12-13,26), (13,27), (11,28); <b>pyramid</b> (6,16) by rowboat from (6,14); <b>boat to New Phlan</b> (7,29). '
            'Arrivals: New Phlan\'s boats put you at (7,29) or (13,27); the old Podol Plaza exit at (11,28).'),
    entries=[
        ('R', 'fight', 'Random encounters (world map)',
         'About 1 step in 20, never on a special square. One in 21 of those is the grove instead (below). Groups, in 18 equal slots: Kobolds 4 (+Kobold Leaders), Displacer Beasts 2, '
         'Driders 1, Stirges 3, Lizard men 3, Bandits 1, Nomads 2, Merchants 2 (Bandits, Nomads, Merchants come with Aides); sizes scale with your party. '
         'Displacer Beasts and Stirges always attack; Nomads and Merchants greet you and leave; for the rest parley: attitude (HAUGHTY 30, SLY 30, NICE 30, MEEK 5, ABUSIVE 60) + d30 + '
         'charisma bonus (+ one value not traced): 140 or more they wander off, 100 or more you talk your way out, else they attack.'),
        ('W', 'place', 'Where the city choices lead',
         'North edge: CITY ECL3/14, GRAVEYARD ECL4/10 (Valhingen Graveyard). East edge: NORTH ECL3/14, SOUTH ECL1/24 (Temple of Bane), BOAT the New Phlan dock (ECL3/0). '
         'West edge: NORTH ECL1/18 (Podol Plaza), SOUTH ECL4/2 (Cadorna Textile House). ECL3/14 is a thieves\' mansion with traps and files '
         '(Kovel Mansion is an inference).'),
        ('Q', 'hint', 'The pyramid and the pollution',
         'Entering the pyramid: take the rowboat at (6,14) (YES), then at (6,16) ENTER (secret door; GO BACK returns you to the boat). Once the lab is dealt with '
         '(Yarash dead or his equipment wrecked) flag [4AB3] reaches 254: 12 of the 28 blocked terrain codes open up (inferred reading), and leaving the pyramid shows '
         '"the land is already beginning to recover" (once). City Hall pays <b>250 platinum + 15 jewelry</b>. The map edges: x=2 west leads to ECL6/25, x=15 east to ECL8/27, y 2 or less is closed.'),
        ('G', 'place', 'The grove (plan)',
         'Random find, "a small wooded grove" (start C4) or "some ruined huts" (start K14) or a grove start at N7 (the two a marks). Walking onto the rim cells asks "leave this area?". '
         'Fights are flagged per visit (leaving and returning resets them). No treasure anywhere: only fights.'),
        ('1', 'fight', 'Pool (E4, D5, F5, E6)', '"Someone or thing is splashing": approach, and 6 Lizardmen swimming attack.'),
        ('2', 'fight', 'Ambush (C7)', 'Two Displacer Beasts ambush you in the trees.'),
        ('3', 'hint', 'Chained kobolds (I15)',
         'Four Kobolds: RELEASE (they warn of the mutant lizard men), ATTACK (you kill them, no fight) or LEAVE.'),
        ('4', 'hint', 'Stench (H12)', '"An awful stench is coming from the west." Text only.'),
        ('5', 'fight', 'Hut of filth (J12)', 'Two horribly mutated lizard men (2 Mutant Liz-men).'),
        ('6', 'fight', 'Hut (C12)', 'Four Lizardmen attack at once.'),
        ('7', 'fight', 'Room of "large" lizard men (C16)', 'Four Lizardmen ("KILL"). Stepping here also wipes the other fight flags of the visit (the script ANDs them with 32), so the other fights can recur.'),
        ('8', 'fight', 'Stirge swarm (N4, K6, M6)',
         '6 Stirges swoop; then the next three steps onto those cells are quiet.'),
    ],
    table=dict(
        rows=[['World map (x,y)', 'Place', 'It asks'],
              ['(12,11)', 'Nomad camp', 'ENTER (ECL7/17) / LEAVE'],
              ['six squares round it', 'Abandoned camp', 'text only, once per visit'],
              ['(12,26) (13,26)', 'City, north edge', 'CITY / GRAVEYARD / LEAVE'],
              ['(13,27)', 'City, east edge', 'NORTH / SOUTH / BOAT / LEAVE'],
              ['(11,28)', 'City, west edge', 'NORTH / SOUTH / LEAVE'],
              ['(6,14)', 'Rowboat in the reeds', 'to the pyramid? YES: (6,16)'],
              ['(6,16)', 'Pyramid', 'ENTER (ECL7/22) / GO BACK'],
              ['(7,29)', 'Boat', 'TAKE BOAT (New Phlan dock) / STAY']],
        widths=[84, 82, 0],
        caption='Coordinates are the script\'s party variables [49C3], [49C4] (x, y); the exits are listed in W.'),
    boxes=[
        '<b>MONSTERS</b> (MON7CHA, level / AC / HP) Lizardman 3/4/11, Mutant Liz-Man 4/3/18, Displacer Beast 6/2/30, Stirge 2/8/5, Drider 7/3/36, Kobold 0/7/3, Bandit 0/6/6, '
        'Nomad 1/6/6, Merchant 0/6/6, Aides 3/8/18.  <b>NO PASSWORDS, no locked doors, no loot</b> in this block.',
        '<b>NOT TRACED</b> which terrain the blocked block codes are (and which 12 open); whether the city at (12-13,26-28) is Old Phlan (a name taken from the Valhingen map, inferred); the nomad-camp square on the world map changes after the camp is resolved.',
    ],
)
