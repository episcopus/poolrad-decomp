"""Sokal Keep (Thorn Island): GEO4 block 21, ECL4 block 21 (tile set 4). Read from the area script
(see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='sokal-keep',
    title='SOKAL KEEP',
    subtitle=('Thorn Island, by boat from Phlan harbor', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Read from the game files: area map GEO4 block 21, event script ECL4 block 21,',
                 'monsters MON4CHA, loot ITEM4. Grid: columns A-P, rows 1-16, north is up.'),
    geo=('GEO4', 21),
    start=(14, 8),
    exits=[(15, 7, 'S'), (15, 8, 'S')],
    hatch_events={3: ('#f3d9d3', '#d89b90')},
    illusion_ids={4},
    legend=['arrival', 'exit', 'search', 'door', 'illusion', 'hatch:patrol ground (P)', 'grey'],
    rooms=[
        ('BARRACKS', 2.1, 5), ('(empty room)', 2.5, 7.5, 4.6), ('GREAT HALL', 4.2, 7.5, 4.8),
        ('CHAPEL', 6.3, 7.5, 5.4), ('altar', 8.75, 7.5, 4.4), ("FERRAN'S CRYPT", 9.25, 7.5, 4.2),
        ('ARMORY', 4.35, 13.6, 6), ('HIDDEN', 0.18, 13.5, 5.2, '#6b3fa0', True), ('VAULT', 0.82, 13.5, 5.2, '#6b3fa0', True),
        ('SMITHY', 6.2, 14, 5.4), ('stable', 8.4, 12.5, 4.6), ('(sealed)', 9.1, 12.5, 4.2),
        ('FUNGUS', 8.35, 2.5, 5), ('ROOM', 9.1, 2.5, 5), ('GATE', 11.85, 7.5, 5.4, None, True),
        ('LANDING', 14.55, 7.5, 5.6), ('not reachable on foot', 0.75, 5, 5.2, '#948b7b'),
    ],
    markers=[
        ('1', 13, 6, 'hint'), ('2', 13, 7.5, 'hint'), ('3', 3, 13.0, 'secret', dict(dy=2)),
        ('4', 2, 15, 'secret', dict(dy=7.5, rad=6.2)), ('5', 0, 12, 'loot', dict(dx=-1, dy=-1)),
        ('6', 7, 14, 'fight', dict(dy=-8)), ('7', 11, 2, 'fight'), ('8', 3, 5, 'fight', dict(dy=-3)),
        ('9', 5, 7.5, 'fight', dict(dy=-1)), ('10', 7, 7.5, 'hint', dict(dy=-2, rad=7.4)),
        ('11', 10, 7.5, 'fight', dict(dy=-4, rad=7.4)), ('P', 11, 5, 'fight'),
    ],
    diamonds=[('a', 6, 15, 'loot'), ('b', 4, 4, 'loot')],
    glance=('<b>BOAT:</b> Phlan harbor master, end of the pier, 1 pp round trip. Until the keep is cleared it is the only boat out of Phlan. '
            '<b>LEAVE:</b> walk off the south edge at the dock (H16-I16). '
            '<b>REWARD:</b> once Ferran is dealt with, the City Hall clerk pays <b>250 platinum + 3 jewelry</b> and the other boat routes open. '
            '<b>NO</b> traps and no locked doors here; every fight is a scripted encounter.'),
    entries=[
        ('P', 'fight', 'Undead patrol (red hatch: all open ground)  ' + tag('fight', 'FIGHT') + '  ' + tag('hint', 'PASSWORD'),
         'Each step on hatched ground has a 1 in 6 chance of "a pack of undead": 6 Skeletons + 6 Zombies '
         '(up to 4 fought patrols per visit; a rest here can be interrupted by the same pack). '
         'ADVANCE (up to 2 steps) until PARLAY is offered, pick any attitude, type the word: <b>SHESTNI</b> before Ferran is freed, '
         '<b>SAMOSUD</b> after. Once said, later patrols just ask "give the password?".'),
        ('1', 'hint', 'Dead elf (G14)',
         'Hidden by reeds, west of the gate. ' + tag('secret', 'SEARCH') + ' (or S key) for a crumbling scroll of runes: the two '
         'passwords below (the rune pairs spell SAMOSUD and SHESTNI by letter pattern). '
         + tag('fight', 'Never pick ATTACK') + ': "you hack the body to bits" and the scroll is gone for this visit.'),
        ('2', 'hint', 'Gate (H14-I14)',
         'Rotting gates. You land just south at I15. Before Ferran is freed you hear "echoing footsteps within the keep".'),
        ('3', 'secret', 'Armory (M3-P6)', 'Everything has rotted; nothing to take. Its NE corner is the way to the vault.'),
        ('4', 'secret', 'Illusionary wall (P3, north side)',
         'Looks solid, walk north through it from P3 to P2: "a portion of the keep untouched by time".'),
        ('5', 'loot', 'Hidden vault (M1-P2)',
         '"A glow in the NW corner." The stands at M1 hold ' + tag('loot', 'Mace +2, Long Sword +1, Chain Mail +1, Shield +1')
         + ' (one yes/no prompt, taken once for good). Reachable without touching the hall fight: arm up first.'),
        ('6', 'fight', 'Smithy (N7-P9)',
         'Damp, wrecked. On your 3rd step inside, 4 Poisonous Frogs ambush (parley only gets you "CROAK!"). '
         + tag('loot', 'a: SEARCH at P7') + ' (S key): an old Hammer +1, once.'),
        ('7', 'fight', 'Insect house (C12)',
         'Walls and ceiling crawl with insects; 2 Huge Scorpions attack on your first step in (poison).'),
        ('8', 'fight', 'Barracks (E3-G5)',
         'A few steps in, ghostly shapes of the keep\'s old defenders howl. They cannot be fought (they only wail). '
         + tag('hint', 'ADVANCE, then PARLAY, type LUX') + ': they point to a floorboard: diary page (journal entry 3) + '
         + tag('loot', '5 gems') + '. ' + tag('loot', 'b: E5') + ' (S key) finds the same stash, about 1 search in 10, with or without meeting the ghosts.'),
        ('9', 'fight', 'Great hall (H5-I6)',
         tag('fight', 'The big fight: 15 Hobgoblins, 4 Orc Leaders, 31 Orcs (50 foes).') + ' Triggers on the first step in. '
         'Every route to the chapel and Ferran crosses it. You may flee; it returns until beaten. '
         'Won: a note on a hobgoblin body (journal entry 57). It stays empty afterwards.'),
        ('10', 'hint', 'Chapel (H7-I7)', 'Two dried orc husks, an altar on the south wall. Text only. The way on to Ferran.'),
        ('11', 'fight', 'Ferran Martinez (H11-I11)',
         'A pale undead guardian. ' + tag('hint', 'PARLAY at once, type LUX, then TELL THE TRUTH.') + ' He recounts the fall of Phlan '
         '(Tyranthraxus, Edranka, Torath; Mendor\'s library lost), points you to the illusionary wall if you have not taken the vault gear, and gives '
         'SAMOSUD. That frees the keep (Phlan counts it cleared). A wrong word: he fades until you re-land. LIE: fades for now, '
         'returns on your next step. Or fight him: same result, no story.'),
    ],
    table=dict(
        rows=[['Monster', 'No.', 'Lvl', 'AC', 'HP', 'Where'],
              ['Poisonous Frog', '4', '1', '8', '4', '6 smithy'], ['Huge Scorpion', '2', '5', '4', '20', '7 insects'],
              ['Skeleton', '6', '1', '7', '5', 'P patrol'], ['Zombie', '6', '2', '8', '10', 'P patrol'],
              ['Hobgoblin', '15', '2', '5', '6', '9 hall'], ['Orc Leader', '4', '1', '5', '8', '9 hall'],
              ['Orc', '31', '1', '6', '5', '9 hall'], ['Ferran Martinez', '1', '8', '2', '38', '11 crypt']],
        widths=[86, 22, 22, 22, 24, 0],
        caption='Lvl, AC (descending), HP as stored in the game files. Frogs and scorpions poison; skeletons, zombies and Ferran are undead.'),
    boxes=[
        '<b>PASSWORDS</b>  <b>LUX</b>: barracks ghosts (8) and Ferran (11), typed at the prompt.  '
        '<b>SHESTNI</b>: undead patrol before Ferran is freed.  <b>SAMOSUD</b>: patrol after.<br/>'
        '<b>RESETS</b> when you leave and re-land: frogs, scorpions, patrols, a faded Ferran. '
        '<b>STAYS</b> done: the hall fight, Ferran freed, vault gear, hammer, diary.',
        '<b>SUGGESTED ORDER</b>  1 Elf scroll (SEARCH).  2 East side: armory, illusionary wall, vault gear.  '
        '3 Smithy frogs and hammer.  4 West side: insects, barracks (LUX, gems).  '
        '5 Heal, then the great hall (50 foes).  6 Chapel, Ferran (LUX, truth).  '
        '7 Boat to Phlan, City Hall for the reward.',
        '<b>TEXT ONLY</b> (no fight, no loot): fungus room C9-D10, stable front N11 (its door is sealed), the empty room north of the hall, the chapel. '
        'Grey pockets on the map cannot be entered on foot.',
    ],
)
