"""Podal Plaza: GEO1 block 18, ECL1 block 18 (tile set 1). Read from the area script
(see tools/maps/README.md for how each statement was checked). The name is the one the City Hall
clerk uses (ECL3 block 8: "Podal Plaza"); the script itself only says "the plaza"."""
from mapkit import tag

SPEC = dict(
    name='podal-plaza',
    title='PODAL PLAZA',
    subtitle=('Monster-crowded city square', 'Pool of Radiance (SSI, DOS)  |  annotated area map  |  SPOILERS'),
    source_note=('Game files: GEO1 block 18, script ECL1 block 18, MON1CHA, ITEM1;',
                 'City Hall text ECL3 block 8. Grid: (column,row) from 0, top left, north up.'),
    geo=('GEO1', 18),
    start=(4, 0),
    exits=[(0, 4, 'N'), (0, 11, 'N'), (4, 15, 'E'), (11, 15, 'E'), (15, 4, 'S'), (15, 11, 'S'), (4, 0, 'W'), (11, 0, 'W')],
    hatch_events={0: ('#f3d9d3', '#d89b90')},
    legend=['arrival', 'exit', 'door', 'lock2:locked door (Bash / Pick / Knock)', 'hatch:open plaza: random encounters'],
    rooms=[
        ('THE PLAZA', 7.0, 10.5, 8.0, '#9a4a3e', True),
    ],
    markers=[
        ('1', 7, 7, 'hint'), ('2', 8, 4, 'fight'), ('3', 8, 5, 'place'), ('4', 15, 1, 'hint'),
        ('5', 8, 13, 'place'), ('6', 8, 14, 'fight'), ('P', 10, 9, 'fight'),
    ],
    glance=('<b>ARRIVE</b> on the edge cell you walked in by (from the west gate, ECL7 block 26, you land on (0,4)). <b>EXITS</b> '
            '(eight street gaps): north (4,0) and (11,0) to ECL2 block 9; east (15,4) and (15,11) to ECL8 block 29; south (4,15) and (11,15) to ECL4 block 2; '
            'west (0,4) and (0,11) to ECL7 block 26. <b>CLEARING:</b> 9 fights in the open plaza (red hatch) set the cleared flag; the City Hall clerk then pays '
            '<b>250 gold + 200 platinum</b>. <b>AUCTION MODE:</b> if the clerk sent you to learn what is sold here, the plaza plays as an undercover '
            'mission instead (M). No passwords.'),
    entries=[
        ('M', 'hint', 'Two modes, fixed when you arrive',
         tag('hint', 'Plain mode') + ' (default): monsters roam the open plaza, fights count toward clearing (P). ' + tag('hint', 'Auction mode') +
         ': on arrival with the City Hall commission "a weapon of great power is to be auctioned to our enemies in Podal Plaza; find out what it is" '
         'active, the first step asks HOW WILL YOU PROCEED: <b>STRIDE BOLDLY</b> (every pack hostile and twice as big, no parley, no auction scene, '
         'fights do not count), <b>DISGUISE PARTY AS MONSTERS</b> or <b>SNEAK, REMAINING UNSEEN</b>. Only the last two reach the auction (1) and the '
         'recruiter (6) peacefully.'),
        ('P', 'fight', 'Open plaza encounters (red hatch, event 0)',
         '<b>Plain mode:</b> 1 step in 26 (about 1 in 3 when searching, S key) meets a pack: goblins 4 in 9, orcs 3 in 9, hobgoblins 1 in 9, ogres 1 in 9; '
         'big packs gain leaders; size scales with your party. PARLEY: attitude (ABUSIVE 30; SLY, NICE, MEEK 20; HAUGHTY 10) + d50 + twice your '
         'charisma bonus + pack bonus (goblins 20-30, orcs 10-20, others 0): 112+ they let you off, 90-111 they move off, less they attack. '
         'Fleeing lands you on a random cell of rows 0-7, columns 4-12. The 9th fight sets the cleared flag at your next step here: no more random packs, safe camping '
         '(before that a camp can be ambushed). <b>Auction mode:</b> 4 steps in 26 (9 searching) meet a pack; 3 in 26 an overheard remark (cycling): the boss is expected; '
         'more ogres since the giants took the castle; the Bane temple is recruiting for Mace again, "Grishnak won\'t be happy"; a man "melted into a puddle of lard '
         'when he touched the thing"; "the boss will be the guy bidding up the price". Disguised, a pack challenges you about 5% + 5% per non-human member (race field, inferred): '
         'answer SLY (passes on d30 against your charisma bonus), HAUGHTY or ABUSIVE (passes if party value beats d50); NICE or MEEK are attacked. Sneaking: 1 in 6 challenged, else they pass.'),
        ('1', 'hint', 'The auction (7,6)-(7,8)',
         'Auction mode with cover intact only. The auctioneer sells "an item both magical and powerful", a wand or staff. ' + tag('hint', 'STAND AND LISTEN:') +
         ' bidding reaches 5,000 gp, high bidder a man in plain clothes beside an ogre. MAKE A BID: he speaks a word, darkness, the ogre bolts; FOLLOW THE OGRE (searched, no item), '
         'MOVE AWAY or LOOK FOR THE MAN ("Garwin, I\'ll get you!", gone). WAIT FOR WINNER: man and ogre swap the wand for a large bag and vanish. '
         'MOVE IN CLOSER: "only a wand of fear". LISTEN TO COMMENTS: "a wand of illumination" or "a staff of command". '
         'Bidding, closing in and leaving test cover: sneaking always fails, disguise 1 in 6; found out = "Settlers! Kill them!" and a fight. '
         'Success only ends the scene: no loot, no XP.'),
        ('2', 'fight', 'Tavern (4,8)',
         '<b>First visit:</b> a drunk buccaneer (4th-level fighter) wants payment: CHALLENGE (one member duels him), ATTACK (patrons join: 4 Hobgoblins, 12 Goblin Guards, 8 Orcs), FLEE, '
         'BRIBE (a tenth of everyone\'s money, about a tenth of items). <b>Later:</b> ATTACK or LEAVE, or MIX WITH MONSTERS (disguised only; others are attacked): after insults, ATTACK or INSULT BACK '
         'start a free-for-all (25 Goblin Guards, 20 Hobgoblins, 5 Ogres), TRY TO LEAVE the patron fight, ' + tag('fight', 'JOIN IN HEAVY DRINKING') +
         ' (also DRINK HEAVILY): <b>the party passes out, every member loses all money and nearly every light item</b>, a disguise is blown. After a brawl the bar is wrecked and empty.'),
        ('3', 'place', 'The Pitt (5,8)', 'Door under a crude sign "THE PITT". Text only, nothing happens.'),
        ('4', 'hint', 'Hidden Ilmater temple (1,15)',
         'Walled compound (0,13)-(2,15), reached through <b>two locked doors</b>: west of (2,13), or west of (3,15). "A young woman comes forward: we provide help for those who can reach us. '
         'Are you in need of healing?" YES starts the healing routine (cost not in the script); "you can rest here as long as you wish". Camping on (1,15) or the compound is never interrupted.'),
        ('5', 'place', 'Small shrine (13,8)', '"Symbols of Bane have replaced those of Ilmater." Text only.'),
        ('6', 'fight', 'Robed orc, Bane\'s recruiter (14,8)',
         'Plain mode or a sneaking party: whatever you choose, he fights: 1 Orc Leader. Disguised: LEAVE, GREET or ATTACK. ' + tag('loot', 'Loot (both fights): 6 Leather Holy Symbols') +
         ' (item type 74), the pass the Temple of Bane guards ask for (ECL1 block 24). GREET: "we are recruiting creatures for our temple to the northeast" '
         '(after Mace is dead: "hiring creatures to recover our temple"); YES ("meet here in two hours, you may meet High Priest Mace") or NO ("return in two hours") both set the meeting. '
         'Step on (14,8) again after 2 game hours (re-entering the plaza also counts) and the crowd turns on you: "kill the unbelievers": 8 Orcs + 1 Orc Leader + 3 Ogres.'),
        ('7', 'place', 'Abandoned shops, decayed buildings',
         'Door cells show "An abandoned shop. Broken shelves are all that remain" ((9,0) (7,1) (12,1) (14,2) (1,3) (10,4) (13,5) (1,6) (13,6) (3,12) (7,12) (14,12) (8,13) (5,14) (13,14)) or '
         '"A decayed building left to the rats" ((10,1) (3,2) (5,2) (6,2) (8,6) (15,7) (2,8) (1,10) (1,12) (5,13) (14,13) (3,14) (10,14) (12,14)). Nothing else outside the red hatch has a script.'),
    ],
    table=dict(
        rows=[['Monster', 'Lvl', 'AC', 'HP', 'Monster', 'Lvl', 'AC', 'HP'],
              ['Goblin Guard', '0', '7', '4', 'Hobgoblin / Ldr', '2', '5', '6'], ['Goblin Leader', '0', '5', '7', 'Ogre', '5', '5', '21'],
              ['Orc', '1', '6', '5', 'Ogre Leader', '7', '3', '32'], ['Orc Leader', '1', '5', '8', '4th Lvl Fighter', '4', '8', '30']],
        widths=[62, 18, 18, 18, 66, 18, 18, 0],
        caption='Lvl, AC (descending), HP as stored in the game files (MON1CHA).'),
    boxes=[
        '<b>PASSWORDS</b> none. <b>LOCKS</b> the two orange doors (west of (2,13), west of (3,15)): Bash, Pick (thieves) or Knock. '
        '<b>HIDDEN</b> no search spots in this script. <b>PERSISTS</b> across visits: fights won and the cleared flag, tavern state, recruiter state; '
        'everything else (including a pending recruiter meeting) is reset when you re-land.',
        '<b>ORDER</b> Plain: clear the plaza (9 fights), kill the recruiter (6) for the Bane holy symbols, report to City Hall. '
        'Auction: take the clerk\'s commission, choose DISGUISE, watch the auction (1), greet the recruiter (6).',
        '<b>NOT TRACED</b> the temple healing cost; what the clerk wants when you report on the auction (no check found); what the tavern brawl script does to 21 random monsters.',
    ],
)
