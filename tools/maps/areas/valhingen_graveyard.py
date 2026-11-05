"""Valhingen Graveyard (Old Phlan, overrun by undead): GEO4 block 10, ECL4 block 10 (tile set 4). Read from the area
script (see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='valhingen-graveyard',
    title='VALHINGEN GRAVEYARD',
    subtitle=('Old Phlan, a graveyard turned upside down', 'Pool of Radiance (DOS)  |  area map  |  SPOILERS'),
    source_note=('GEO4 block 10, ECL4 block 10, MON4CHA, ITEM4.', 'Grid: columns A-P, rows 1-16, north is up.'),
    geo=('GEO4', 10),
    start=(4, 0),
    exits=[(4, 0, 'W')],
    hatch_events={2: ('#f3d9d3', '#d89b90'), 6: ('#f6e3c6', '#d9ae6b'), 9: ('#dde6f3', '#9db4d6')},
    legend=['arrival', 'exit', 'door', 'lock2:locked',
            'hatch:skeletons (SK)', 'hatch:zombies (ZO)', 'hatch:wights (WI)'],
    markers=[
        ('1', 4, 6, 'fight'), ('2', 6, 5, 'fight'), ('3', 7, 7, 'fight', dict(dx=-3)),
        ('4', 12, 1, 'fight'), ('4', 13, 1, 'fight'), ('5', 15, 0, 'fight'),
        ('6', 9, 5, 'fight', dict(dy=-3)), ('6', 10, 4, 'fight'),
        ('7', 15, 10, 'fight'), ('7', 15, 9, 'loot', dict(dx=-2, dy=-1)),
        ('8', 11, 9, 'fight'), ('9', 5, 9, 'fight'), ('9', 6, 9, 'fight'), ('9', 7, 9, 'fight'),
        ('10', 1, 9, 'fight'), ('11', 2, 8, 'loot'), ('12', 9, 8, 'hint'),
        ('13', 6, 15, 'fight'), ('13', 8, 15, 'loot'), ('14', 4, 12, 'secret'),
        ('15', 0, 15, 'fight'), ('15', 0, 14, 'fight', dict(dx=-3)),
    ],
    diamonds=[('a', 7, 7, 'loot', dict(dx=5, dy=5)), ('b', 0, 14, 'loot', dict(dx=6, dy=6))],
    glance=('<b>ARRIVE</b> at A5 facing east, from the overland map ("north edge of the city": CITY or GRAVEYARD). <b>LEAVE</b> by the west gate A5. '
            '<b>QUEST</b>: Diogenes the silver dragon sends you for a silver bottle (kobold caves); its efreeti is for the vampire (15). '
            '<b>REWARD</b>: City Hall pays for undead killed (per kill, see the box) and a special prize of <b>15 gems + 25 jewelry</b> once the vampire is destroyed. '
            '<b>WARNING</b>: once the vampire is dead (state 255) <b>every cell event here switches off</b>: take the chests and gifts first. No shops. Resting is interrupted by ghouls until then.'),
    entries=[
        ('SK', 'fight', 'Roaming packs (hatched)  ' + tag('fight', 'FIGHT'),
         'Per step: <b>SK</b> skeleton ground 1 in 5; <b>ZO</b> zombie ground 4 in 5 (3 in 5 when searching with S); <b>WI</b> wight ground 1 in 5 (2 in 5 searching). '
         'The pack is the whole remaining quota at once (see the box). Each wight brings 4 Zombies, and a pack also gets 2 Juju Zombies, 2 Ghouls or a Mummy. '
         'You may be ambushed or surprise them. Fleeing puts you back at B7, B10, H5, O7 or O10.'),
        ('1', 'fight', 'Claws in the soil (G5)', 'Once a visit while skeletons remain: a forced fight with a skeleton pack.'),
        ('2', 'fight', 'Enclave (F7)', '"Guarded by a skeleton army": <b>15 Skeletons</b>, once ever, on F7 (door on the east side of E7; not if the giant skeleton, 3, came first). The way on to the alcove is G7, then its east door.'),
        ('3', 'fight', 'Alcove (H7-H9)  ' + tag('fight', 'FIGHT') + '  ' + tag('loot', 'SEARCH'),
         '<b>Giant Skeleton</b> (+ skeleton retainers if 17 or more are left), once ever. ' + tag('loot', 'a: SEARCH') + ' for a marble chest: '
         + tag('loot', '28 sp, 69 gp, 10 gems, 12 jewelry, 4 clerical scrolls (2 spells each)') + '.'),
        ('4', 'fight', 'Bone tower (B13, B14)  ' + tag('fight', 'TRAP'),
         'B13: once ever, a "small army" of <b>30 Skeletons</b> (while skeletons remain). B14, the tower door: noxious fumes, <b>10 damage to everyone</b> (a saving throw applies), once a visit.'),
        ('5', 'fight', 'Skeleton maker (A16)  ' + tag('fight', 'SPECTRE') + '  ' + tag('loot', 'LOOT'),
         'A <b>Spectre</b> "creating new skeletons", only while the skeleton quota is unmet. ' + tag('loot', '2000 gp, 555 pp, 3 jewelry') + ', again next visit.'),
        ('6', 'fight', 'Zombie tower (F10, E11, F11)  ' + tag('fight', 'SPECTRE'),
         'F10 (door): once, <b>15 Zombies</b> pour out. F11: only rusting armor. E11: a <b>Spectre</b> making zombies (only while zombies remain): ' + tag('loot', '1111 gp, 542 pp, 13 gems') + '.'),
        ('7', 'fight', 'Stairs and crypt (K16, J16)',
         'K16: once ever, <b>25 Zombies</b> (not if J16 came first). J16: a <b>Juju Zombie</b> (+15 Zombies if 16 or more remain), once; then ' + tag('loot', 'scattered objects: 290 sp, 110 gp, 2 clerical scrolls, a Wand, a Potion') + '.'),
        ('8', 'fight', 'Mummy crypt (J12)', 'Once a visit: sarcophagi open on <b>Mummies</b>, party strength / 16 of them (at least 1).'),
        ('9', 'fight', 'Central tower (J6, J7, J8)',
         'J6: from the south, wights step out behind the tower (once, a wight pack); the door reads "DO NOT OPEN. A great evil has been laid to rest here" (SEARCH: silver holy symbols). '
         'J7: a static shock, <b>4 damage to everyone</b> (saving throw), once a visit. J8: a <b>Spectre</b> summoning a wight (while wights remain): ' + tag('loot', '2000 gp, 555 pp, 3 jewelry') + '.'),
        ('10', 'fight', 'Brass doors (J2)', 'Shadowy forms attack: <b>2 Spectres</b>, no loot, <b>every visit</b>. They count towards the mystic (12).'),
        ('11', 'loot', 'Knight\'s tomb (I3)  ' + tag('loot', 'ONCE'),
         '"Come, my brave adventurers, take my gifts": ' + tag('loot', 'Plate Mail +2, Long Sword +2, Shield +1, a Ring, 4 clerical scrolls') + '.'),
        ('12', 'hint', 'The mystic (I10)',
         'After 3 "credits" (a wight-maker Spectre is 1, the brass doors 2) a robed man (a level 6 magic-user) offers to join and says the vampire lives in the NE corner. '
         'Send him away and he attacks. In the party he says "the vampire is behind the northern wall" at P2.'),
        ('13', 'fight', 'Paladin\'s tower (P7, P8, P9)  ' + tag('loot', 'LOOT'),
         'P7: "spirits of those who fought the dragons: leave or die" (LEAVE puts you at O7). Staying, or stepping on P8: <b>4 Wights + 16 Zombies</b> (+ extras), once ever. '
         'Then O8, O9 and the east door to P9: strip the body ' + tag('loot', '(Sling +2, Hammer +3, a Potion, a Clerical Scroll, a 3-spell scroll)') + '. A <b>Wraith</b> guards it only if the wights were never fought.'),
        ('14', 'secret', 'Black marble crypt (M5)',
         'Enter from M3. A dust-filled coffin and a scroll (journal entry 43). EXAMINE and OVERTURN do nothing; <b>SANCTIFY</b> (the script checks no item) is the trick. '
         'Once the vampire has been driven off (15) he rises here: alone and weak (15 HP) if sanctified, else with 15 Wolves.'),
        ('15', 'fight', 'Vampire lair (P1, O1, P2)  ' + tag('fight', 'VAMPIRE') + '  ' + tag('loot', 'b: SEARCH'),
         'Reach P2 from O2; its north wall (same id as the walls beside it) hides a door to <b>P1</b>, "wooden stairs lead into a pit": go down to O1. <b>Vampire + 50 Wolves</b> (+ an Efreeti if you carry the silver bottle, looks like your ally); '
         'he turns to vapor and flees to the crypt (14). ' + tag('loot', 'b: SEARCH at O1 afterwards: 9000 gp, 12 gems, 4 clerical scrolls, Shield +1, Scroll of Restoring Levels, 3 Potions, a Wand') + '.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Skeleton', '1', '7', '5', 'Spectre', '8', '2', '38'], ['Zombie', '2', '8', '10', 'Wraith', '6', '4', '24'],
              ['Ghoul', '2', '6', '10', 'Mummy', '7', '3', '33'], ['Juju Zombie', '4', '6', '24', 'Vampire', '9', '1', '43 (15)'],
              ['Wight', '5', '5', '23', 'Wolf', '3', '7', '18'], ['Giant Skeleton', '5', '2', '28', 'Efreeti', '10', '2', '55']],
        widths=[62, 18, 18, 36, 50, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files. The mystic is a level 6 magic-user (AC 9, HP 23).'),
    boxes=[
        '<b>QUOTAS</b> (party strength P from hit points, armor, bonuses and levels): skeletons P/2, zombies P/4, wights P/8 (at most 4), each minus the ones you have already killed, recomputed on every landing; '
        'the roaming pack is exactly what is left. The three makers (5, 6, 9) appear only while their quota is open. '
        '<b>CITY HALL</b> pays new kills (per kill, by the script: 1 gp per skeleton, 1 pp per zombie, 1 gem per wight or giant skeleton, 1 jewelry per boss credit or wraith).',
        '<b>STAYS</b>: kill counts, once-ever fights (2, 3, 6, 7, 13), chests, gifts, mystic and vampire states. <b>RESETS</b> on re-landing: the visit flags (1, 4, 8, 9, 10 and the makers). '
        '<b>LOCKED</b>: only the door between P4 and P5 (an empty closet). The amber ticks between graves are doors you can walk through.',
    ],
)
