"""The Buccaneer base (slave compound): GEO6 block 1, ECL6 block 1 (tile set 6). Read from the area script
(see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='buccaneer-base',
    title='BUCCANEER BASE',
    subtitle=('Rescue the boy from the slave pen (ECL6/1)', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Game files: map GEO6 block 1, script ECL6 block 1, monsters MON6CHA,',
                 'loot ITEM6, reward ECL3 block 8. Grid A-P, 1-16, north up.'),
    geo=('GEO6', 1),
    start=(0, 8),
    exits=[(0, 7, 'N'), (0, 8, 'N')],
    hatch_events={8: ('#f3d9d3', '#d89b90'), 7: ('#f6e3c6', '#d9ae6b')},
    legend=['arrival', 'exit', 'door', 'lock2:locked door (Bash / Pick / Knock)', 'hatch:barracks (20)', 'hatch:guard tower (4)'],
    rooms=[
        ('MERCHANTS CAMP', 10.0, 7.5, 5.6, '#2f6d9a', True), ('SLAVE PEN', 7.0, 6.5, 4.6, '#7a5a9a', True),
        ('CAPTAIN', 12.35, 7.5, 4.8, '#9a3f2f', True), ('inner room', 14.0, 7.5, 4.0), ('BARRACKS', 4.0, 5.5, 4.6), ('BARRACKS', 4.0, 9.5, 4.6),
        ('BARRACKS', 8.0, 9.5, 4.6), ('BARRACKS', 11.0, 4.0, 4.6), ('BARRACKS', 11.0, 11.0, 4.6), ('ANIMAL PENS', 8.0, 13.0, 5.0, '#7a6d5c', True),
        ('(empty)', 8.0, 3.5, 4.4), ('(empty)', 8.0, 1.5, 4.4),
    ],
    markers=[
        ('1', 0, 7, 'hint', dict(dy=-1)), ('2', 11, 9, 'place'), ('3', 7, 5, 'hint', dict(dx=3)), ('4', 6, 7, 'secret'), ('5', 8, 7, 'loot', dict(dx=4, dy=2)),
        ('6', 11, 7, 'fight'), ('7', 12, 7, 'hint', dict(dy=3)), ('8', 11, 2, 'loot'), ('9', 6, 11, 'secret'), ('T', 3, 2, 'fight'), ('T', 3, 13, 'fight'),
        ('B', 2, 5.5, 'fight'),
    ],
    glance=('<b>QUEST</b> (City Hall council, ECL3/8): save the heir of House Bivant, a boy with a heart-shaped birthmark on his left shoulder, held in a slave pen here. '
            'The wilderness (ECL6/25) offers the base only while that quest is open and the boy is not yet saved. <b>ARRIVE</b> at the main gate (I1): you are escorted south '
            'to the merchants\' camp (I11) on every visit. <b>LEAVE</b> by walking off the north edge (H1, I1). <b>THREE WAYS</b>: buy the boy from the Captain (7: 75% of everyone\'s money, no fight); '
            'free him by force or stealth and run for the gate (waves of buccaneers); or wipe out the fort. <b>REWARD</b> (City Hall clerk, boy saved): <b>25 gems, 5 jewelry, 4 Clerical Scrolls '
            '(2 spells) and a Two-Handed Sword +1 (+3 vs undead)</b>. Locks are red-crossed; everything else is open.'),
    entries=[
        ('1', 'hint', 'Main gate (H1, I1)',
         'First step each visit: the escort south. Later: "some buccaneers stand guard" (text). Once you took the boy by force (not bought), 8 Buccaneers rush the gate, once per visit '
         '(flee: back to the camp). Walking off the edge ends the visit; a bought boy is then counted as saved.'),
        ('2', 'place', "Merchants' camp (G11-J12)", 'The place to rest: elsewhere the pre-camp script sets other camp-risk values (5/100 against 0/1: looks like risky) and a guard comes by: "go to the merchants area". With the boy taken by force, an interrupted camp is a raid.'),
        ('3', 'hint', 'Slave pen fence (face the pen wall from G7, F8, F9, I8, I9, G10 or H10), once per visit',
         'The boy; a fat merchant: "that boy will bring a good price at Zhentil Keep, I shall buy him". PUNCH MERCHANT (6 Buccaneers; flee: back to the camp), '
         'AGREE, SAY NOTHING (no effect), or <b>RESCUE BOY</b>: SNEAK INTO PEN puts you at the pen gate H7; ATTACK GUARDS fights its 4 guards now; or later.'),
        ('4', 'secret', 'Pen gate (H7), locked',
         'Two guards = <b>4 Buccaneers</b>: ATTACK, or "try to sneak by" (always fails), or leave. Beaten guards stay gone this visit. The gate itself is <b>locked</b> (door H7-H8: Bash, Pick or Knock). '
         'No guards at all while the animals run (9).'),
        ('5', 'loot', 'In the pen (G8-H9)', 'GET HIM takes the boy: the quest counts as saved and the slaves run out; you are put back at H7. <b>Raiders attack from now on (W).</b>'),
        ('6', 'fight', "Captain's door (H12)",
         'Two large guards: "do you have a pass?" SHOW PASS (an item of type Pass: buy one at 8), BRIBE (refused), ATTACK or LEAVE. ATTACK: <b>2 fighters (4th level)</b>, then the whole base comes (W). '
         'Once the boy is saved they sound the alarm at once.'),
        ('7', 'hint', "Captain's room (H13; the inner room H14-I15 has no script)",
         'Four chain-mail guards bring the <b>Captain</b>. <b>MENTION YOUNG BOY, then BUY THE BOY</b>: <b>75% of every member\'s money</b> (items may go too), then the boy is yours: '
         'no fight, no raids; walk out of the gate. ATTACK: Captain + 4 fighters (4th level); win: he stays dead this visit; flee: the waves start (W).'),
        ('8', 'loot', 'Pass seller (C12), until you buy',
         '"Want to buy a pass to see the captain?" One <b>Pass</b> (item) for <b>25% of the selected member\'s money</b> (items may go too: same command). Back every visit; gone once the boy is saved.'),
        ('9', 'secret', 'Animal pen gate (L7): the diversion',
         'RELEASE ANIMALS: for about 60 steps (a search step counts about 10) the main gate, the pen gate and the pass seller are unguarded and the barracks are empty; '
         'towers and the captain\'s door stay guarded. <b>Best stealth route</b>: release them, open the pen lock, take the boy, walk out.'),
        ('T', 'fight', 'Guard towers (C4, N4, G1, J1, A11, P11, E15, L15)',
         '"Four buccaneers: restricted area, leave now": ATTACK (<b>4 Buccaneers</b>, again every time you enter) or LEAVE. After the boy is taken they attack at once.'),
        ('B', 'fight', 'Barracks (the hatched rooms)',
         '"Twenty buccaneers: off limits": ATTACK (<b>20 Buccaneers</b>, every entry) or LEAVE. Their doors (south and middle) are locked; the north pair is open. Nothing to loot.'),
        ('W', 'fight', 'Raiders and waves (only after the boy is taken by force, or an alarm)',
         'Each step builds a chance of a raid: 20 Buccaneers; then 4 fighters (3rd level) + 30; then 4 + 40; then the Captain scene. Killing the door guards or fleeing the Captain starts 3 waves '
         'instead: 20 + a 3rd-level fighter; 50 + two fighters; 53 + three. <b>Captain</b> (if alive): SURRENDER (75% of money, escorted out, <b>quest failed for good</b>) or ATTACK: '
         '<b>Captain (L10, 110 hp) + 15 fighters (4th level) + 40 Buccaneers</b>; win: fort captured, boy saved, no more events. <b>Fleeing a wave fails the quest</b> (the first flee in other fights only warns).'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Buccaneer', '0', '10', '4', '4th Lvl Fighter', '4', '8', '30'], ['3rd Lvl Fighter', '3', '8', '18', 'Captain', '10', '10', '110'],
              ['5th Lvl Fighter', '5', '10', '39', '', '', '', '']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON6CHA); gear may change AC.'),
    boxes=[
        '<b>LOCKS</b> Bash, Pick (thief) or Knock (spell): pen gate H7, the south and middle barracks (E10, E12, L10, L12, I8, K8), the east door of the west building (E8) and the Captain\'s inner room (H13-H14). '
        '<b>PERSIST</b> (never reset): boy saved or failed, fort captured; <b>RESET</b> on every landing: the diversion, killed guards, bought pass, raids. '
        '<b>FAIL</b> by SURRENDER or two flees: the council says "your bungling the Bivant rescue has cost us" and the base cannot be entered again.',
        '<b>TEXT ONLY</b> the two empty west buildings B7-C9 (open door A8) and D7-E9 (locked door E8), the Captain\'s inner room, and the animal pens (their perimeter only reads "a densely packed animal pen").',
    ],
)
