"""Tyranthraxus' tower, the top of Valjevo Castle: GEO5 block 7, ECL5 block 7 (tile set 5). Read from the area
script (see tools/maps/README.md for how each statement was checked)."""
from mapkit import tag

SPEC = dict(
    name='tyranthraxus-tower',
    title="TYRANTHRAXUS' TOWER",
    subtitle=('Top of Valjevo Castle: the last fight (ECL5/7)', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Game files: map GEO5 block 7, script ECL5 block 7, monsters MON5CHA, loot ITEM5.',
                 'Grid A-P, 1-16, north up. Castle name from City Hall text (ECL3/8).'),
    geo=('GEO5', 7),
    start=(7, 5),
    exits=[(7, 5, 'W')],
    grey_rects=[(0, 0, 3, 15), (12, 0, 15, 15), (4, 0, 11, 0), (4, 13, 7, 15), (8, 9, 11, 15)],
    illusion_edges=[(7, 5, 'N')],
    legend=['arrival', 'exit', 'door', 'illusion:secret door (search for it)', 'lock2:locked door (Bash / Pick / Knock)', 'grey:unused map space'],
    rooms=[
        ('AUDIENCE HALL', 11.2, 2.5, 5.4, '#9a3f2f', True), ('(open to the sky)', 11.7, 2.5, 4.2), ('TRAP-DOOR ROOM', 4.5, 7.5, 4.6),
        ('STATUE CELLAR', 4.2, 10.5, 5.6, '#7a5a9a', True), ('(empty rooms)', 10, 7, 4.6), ('stairs', 5, 5, 4.0),
        ('office', 5, 2, 4.0), ('waiting', 6, 1, 3.6),
    ],
    markers=[
        ('1', 7, 6, 'secret', dict(dx=-7)), ('2', 5, 5, 'place', dict(dy=-1)), ('3', 6, 2, 'fight', dict(dx=-3, dy=-3)), ('4', 5, 2, 'hint', dict(dy=3)),
        ('5', 6, 4, 'place'), ('6', 7, 3, 'place'), ('7', 8, 3, 'fight'), ('8', 5, 8, 'secret'), ('9', 7, 11, 'fight'),
    ],
    diamonds=[('L6', 5, 11, 'secret', dict(dy=0))],
    glance=('<b>ARRIVE</b> on F8 from the castle below (ECL5/5). <b>LEAVE</b> by the west stair of F8 (facing west, YES: back to ECL5/5) or by killing Tyranthraxus: the ending screen, then '
            'New Phlan (ECL3/0). The floors are stacked on one plan, so <b>stairs teleport</b> (wall id 2): F8 east to L8, L8 west to F8, F7 north to F5, F5 south to F7, '
            'D7 south to D9, D9 north to D7. The only way on from F8 is its <b>secret north door</b> (1), then up the stair F7 to F5 and along the row-5 hall. '
            'No random encounters; all fights are scripted. The shaded space outside the walls is unused.'),
    entries=[
        ('1', 'secret', 'Arrival closet and secret door (F8)',
         'Stairs on the west (down to the castle) and east (down to L8, the statue cellar, 9). The <b>north wall is a secret door</b> (dashed): until it is found the script stops you going through. '
         + tag('secret', 'Finding it') + ': stay on F8 and SEARCH (S key). Each time the script runs there every member rolls 0 to 5 and finds it on a roll at or below a number that is '
         '1 when searching and 0 when not, plus 1 for a race field reading 2 or 4 (looks like elf or half-elf; not proven): about 1 in 3 per member when searching. '
         '"A secret door is found" (north); the find is kept for good.'),
        ('2', 'place', 'Stair shaft (F7 to F5, F6 between)',
         'F7 facing north: "go UP these stairs?" puts you on F5; F5 facing south: "go DOWN" puts you on F7. F5 joins the row-5 hall (B5-M5), the way to the rest of the tower.'),
        ('3', 'fight', 'Waiting room (C7): the messenger',
         'A man playing with a dagger: a <b>1st-level thief (4 hp)</b>. If you robbed the Bane altar in the yard (ECL5/6) he cries "Blasphemers!" and attacks. Otherwise: COMBAT kills him (no loot); '
         'PARLAY: ABUSIVE and he fights, any other attitude he mutters about "just back from the north", goes into the office (C6) and out of the door for good. '
         'Once either has happened the room is empty.'),
        ('4', 'hint', 'Office (C6): the robed merchant, Genheeris',
         'Only until he is dealt with. If the messenger is alive or gone: he asks "what message from Tyranthraxus requires all of you?" (NICE or MEEK parley: you recite "Tell Al-Hyam Dhazid '
         'to execute phase 2 of plan A. Dismissed.", then LEAVE or STAY; any other attitude, or COMBAT, goes to the offer). If you killed the messenger he goes pale at once. The offer: '
         '"Kill Tyranthraxus instead of me and I will make you all generals." YES: <b>Genheeris (level 7, 22 hp) joins as an NPC</b> (with a full party of 8 he just leaves and "notifies others"). '
         'NO: you fight him alone. Fleeing puts you back in the corridor.'),
        ('5', 'place', 'E7', 'If Genheeris is in your party he walks out of it when you step here (the script removes him). Keep him by staying off E7.'),
        ('6', 'place', 'D7 / D8 / D9 stairs', 'D7 facing south: "go DOWN these stairs?" lands on D9, the audience hall; D9 facing north: "UP" lands on D7.'),
        ('7', 'fight', 'Audience hall (D9; room B9-E12, roofless): Tyranthraxus',
         'First step: "the ceiling torn away", a glowing pool (the walled cell C11: looks like) and an ancient bronze dragon rises. "Two guards" is the text but the script adds <b>12 8th-level fighters</b> '
         '(87 hp): COMBAT or flee (back to D7). When they are dead the dragon speaks and offers command of "the armies that will sweep the Moonsea". '
         + tag('fight', 'Every member then votes: ATTACK or JOIN TYRANTHRAXUS') + '. A member who joins changes sides for the fight; computer-run evil members (LE, NE, CE) join by themselves, except Genheeris. '
         'Fight: <b>Tyranthraxus (level 10, 80 hp, AC 0 as stored)</b>; flee puts you back on D7. Win: the ending screen, "you leave the castle" and New Phlan (ECL3/0). No loot.'),
        ('8', 'secret', 'Trap-door room (I6)',
         'Closed room H5-I6; the only door is the south one, <b>locked</b> (Bash, Pick or Knock, from I7). A trap door in the middle: open it (a member is picked); if Medusa is alive a d20 roll '
         'against that member\'s saving-throw number (script address 6B9B) turns him to stone when the roll is at or above it. Jump through: <b>3d6 damage to everyone</b>, no save, and you land on '
         + tag('secret', 'L6') + ', two steps north of Medusa (9). With Medusa dead the opener just reports "heads with faces full of terror".'),
        ('9', 'fight', 'Statue cellar (L8, room J5-M8): Medusa',
         '"A room filled with broken statues." It triggers when you stand on L8 (the F8 east stair puts you there; the trap door lands you on L6, two steps north); once she is dead it is empty. '
         '<b>Medusa (level 6, 30 hp)</b> runs at you: COMBAT, or flee (back to F8). Her gaze is the engine\'s, not scripted. No loot. Stairs L8 west lead up to F8.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Tyranthraxus', '10', '0', '80', 'Genheeris (NPC)', '7', '9', '22'], ['8th Lvl Fighter', '8', '6', '87', 'Medusa', '6', '5', '30'],
              ['1st Lvl Thief', '1', '10', '4', '', '', '', '']],
        widths=[62, 18, 18, 18, 62, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON5CHA); gear may change AC.'),
    boxes=[
        '<b>PERSIST</b> (kept in the save): secret door found; Medusa dead; messenger killed or gone; Genheeris joined or gone; guards dead; hall intro seen. Only the room-description texts '
        'repeat each visit. <b>LOCKS</b> Bash, Pick (thief) or Knock (spell) at the I6 door. <b>ORDER</b> Search F8 for the door; up to F5; the office (4) for Genheeris; keep him off E7; '
        'optional Medusa (no reward); then D7 to D9 for the guards and Tyranthraxus. Heal and save before the hall.',
        '<b>TEXT ONLY</b> the empty rooms F9-I12 and the row-5 hall have no scripts; their doors are plain. Resting uses the quiet camp values (no trouble set).',
    ],
)
