"""The north shore wilderness: ECL7 block 26 (the wilderness script) with the lizard men's grove, GEO7 block 26
(tile set 7). Read from the area script (see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='north-shore',
    title='NORTH SHORE',
    subtitle=("World map; the plan is the lizard men's grove, a random find", 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
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
    glance=('The North Shore is an open <b>world map</b> of squares (x,y), not a 16x16 plan. The plan drawn on this page is only the <b>lizard men\'s grove</b>, '
            'a rare random find while walking. Special squares: <b>Nomad Camp</b> (25,11); <b>Old Phlan\'s gates</b> (25-26,26), (26,27), (24,28); '
            '<b>pyramid</b> (19,16) by rowboat from (19,14); <b>boat to New Phlan</b> (20,29). '
            'Arrivals: the New Phlan harbor master\'s WEST passage lands you at (20,29), BAY at (26,27); coming out of Podal Plaza puts you at (24,28). '
            '<b>The terrain, the walking route from the WEST landing to the west gate and every prompt are on the North Shore outdoor map page.</b>'),
    entries=[
        ('R', 'fight', 'Random encounters (world map)',
         'About 1 step in 20, never on a special square. One in 21 of those is the lizard men\'s grove instead (below). Groups, in 18 equal slots: Kobolds 4 (+Kobold Leaders), Displacer Beasts 2, '
         'Driders 1, Stirges 3, Lizard men 3, Bandits 1, Nomads 2, Merchants 2 (Bandits, Nomads, Merchants come with Aides); sizes scale with your party. '
         'Displacer Beasts and Stirges always attack; Nomads and Merchants greet you and leave; for the rest parley: attitude (HAUGHTY 30, SLY 30, NICE 30, MEEK 5, ABUSIVE 60) + d30 + '
         'charisma bonus (+ one further bonus not confirmed): 140 or more they wander off, 100 or more you talk your way out, else they attack.'),
        ('W', 'place', 'Where the city choices lead',
         'North gate (25,26), (26,26): CITY = Kovel Mansion, GRAVEYARD = Valhingen Graveyard. East gate (26,27): NORTH = Kovel Mansion, SOUTH = Temple of Bane, BOAT = New Phlan. '
         'West gate (24,28): NORTH = Podal Plaza, SOUTH = Cadorna Textile House. Kovel Mansion is a thieves\' mansion with traps and files.'),
        ('Q', 'hint', 'The pyramid and the pollution',
         'Entering the pyramid: take the rowboat at (19,14) (YES), then at (19,16) ENTER (secret door; GO BACK returns you to the boat). Once the lab is dealt with '
         '(Yarash dead or his equipment wrecked) part of the blocked terrain on this map opens up (not confirmed in play), and leaving the pyramid shows '
         '"the land is already beginning to recover" (once). City Hall pays <b>250 platinum + 15 jewelry</b>. Map edges: walking west past column 15 enters the West Wilderness, '
         'east past column 28 the East Wilderness; the north (row 2 or less) is closed.'),
        ('G', 'place', 'The lizard men\'s grove (the plan)',
         'Random find: "a small wooded grove" (arrive at (2,3)) or "some ruined huts" (arrive at (10,13)), or a third start at (13,6) (the two a marks). Walking onto the rim cells asks "leave this area?". '
         'Fights are flagged per visit (leaving and returning resets them). No treasure anywhere: only fights.'),
        ('1', 'fight', 'Pool (4,3), (3,4), (5,4), (4,5)', '"Someone or thing is splashing": approach, and 6 Lizardmen swimming attack.'),
        ('2', 'fight', 'Ambush (2,6)', 'Two Displacer Beasts ambush you in the trees.'),
        ('3', 'hint', 'Chained kobolds (8,14)',
         'Four Kobolds: RELEASE (they warn of the mutant lizard men), ATTACK (you kill them, no fight) or LEAVE.'),
        ('4', 'hint', 'Stench (7,11)', '"An awful stench is coming from the west." Text only.'),
        ('5', 'fight', 'Hut of filth (9,11)', 'Two horribly mutated lizard men (2 Mutant Liz-men).'),
        ('6', 'fight', 'Hut (2,11)', 'Four Lizardmen attack at once.'),
        ('7', 'fight', 'Room of "large" lizard men (2,15)', 'Four Lizardmen ("KILL"). Stepping here also resets the other fights of the visit, so they can recur.'),
        ('8', 'fight', 'Stirge swarm (13,3), (10,5), (12,5)',
         '6 Stirges swoop; then the next three steps onto those cells are quiet.'),
    ],
    table=dict(
        rows=[['World map (col,row)', 'Place', 'It asks'],
              ['(25,11)', 'Nomad Camp', 'ENTER / LEAVE'],
              ['six squares round it', 'Abandoned camp', 'text only, once per visit'],
              ['(25,26) (26,26)', 'Old Phlan, north gate', 'CITY / GRAVEYARD / LEAVE'],
              ['(26,27)', 'Old Phlan, east gate', 'NORTH / SOUTH / BOAT / LEAVE'],
              ['(24,28)', 'Old Phlan, west gate', 'NORTH / SOUTH / LEAVE'],
              ['(19,14)', 'Rowboat in the reeds', 'to the pyramid? YES / NO'],
              ['(19,16)', 'Pyramid', 'ENTER / GO BACK'],
              ['(20,29)', 'Boat', 'TAKE BOAT (to New Phlan) / STAY']],
        widths=[84, 82, 0],
        caption='World squares (column,row) as on the Overworld page; where each answer leads is listed in W.'),
    boxes=[
        '<b>MONSTERS</b> (level / AC / HP) Lizardman 3/4/11, Mutant Liz-Man 4/3/18, Displacer Beast 6/2/30, Stirge 2/8/5, Drider 7/3/36, Kobold 0/7/3, Bandit 0/6/6, '
        'Nomad 1/6/6, Merchant 0/6/6, Aides 3/8/18.  <b>NO PASSWORDS, no locked doors, no loot</b> on this map.',
        '<b>NOT CONFIRMED</b> which terrain squares open up once the pyramid lab is dealt with; the Nomad Camp square changes after the camp is resolved.',
    ],
)
