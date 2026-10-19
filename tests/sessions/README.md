# Sessions: how a session is written, found and checked

A session is a key script (`*.keys`, commands in `tools/oracle/keys.py`) played on the original in the oracle (`make golden SESSION=<name>` records
it twice, the two runs must be identical) and its golden (`golden/<name>/`: digests of the screens and the state at every key read, our own screenshots,
the recording of everything the program read from the outside world). The C translation replays the recording (`make c-golden`): every screen and
every digest of the game's state must equal the original's. The CoCo port plays the same script in MAME and compares screens and state
(`ports/coco3`, `make game-run S=<name>`, `make game-state S=<name>`). `COVERAGE.md` says how much of the game the sessions run together.

## Which key command to use

* **`key X`** waits until the game is idle (it polled the keyboard four times without writing to the screen), delivers the key and releases it when
  the game takes it. A key reaches the game exactly once and at a moment it is ready for it: a replay on a slower or faster machine plays the same
  game. Use it wherever the screen is still while the game waits: the area view, menus, lists, prompts, combat.
* **`press X`** delivers the key at the next poll, idle or not, and releases it at the poll after. Use it only where the screen is never still
  (the camp screen, a prompt that animates a portrait) and give it a long `wait` (100 and more) before and after: a `press` that arrives while the game
  is busy is dropped by the keyboard flush the game does before most prompts, which keys are dropped depends on the speed of the machine
  (the first sessions of step 8.7b, written with `press` and `wait 2`, played differently on the CoCo and had to be written again with `key`).
* **`shot name`** right after a key labels the screen the game shows at its next poll. A `shot` after a `wait` fires between polls, in the middle
  of a redraw if the game is drawing: it can be recorded, but the screen cannot be reproduced on another machine.
* **`quit`** ends a session whose last screen is animated (the game never blocks in a read). `# max-insns: N` in a header comment raises the
  instruction limit of a long session; `# stop: exit` says the game itself ends the session (the party is beaten).

## How the sessions of 8.7b were found

Not by playing: a coverage-guided search on the C translation (`tools/c/`), a second per script instead of a minute. `explore_fuzz.py` walks at random and says where
a routine was first reached; `explore_climb.py` appends keys to a script and keeps the ones that reach lines no committed session reaches (it needs
`make coverage` first); `explore_prune.py` drops every key that is not needed for those lines; `explore_cov.py` says what a script adds. The explorer
(`c/platform/explore.c`) is not the oracle: dice and timing of a long script can differ, so a script found there is only a lead; it counts when it is
recorded on the original (and `make c-golden` then proves the translation against it). `make coverage WRITE=1` writes the new baseline.

## Sessions

| Session | What it plays | Areas it covers |
|---|---|---|
| `boot-title` | the title screens | startup, ovl00 to ovl02 |
| `create-character`, `create-elf-mage` | the character generator | ovl16 (create), ovl19 sheet |
| `walk-explore` | load game A, walk, area map, look, search | 3D view, ECL basics, ovl07, ovl10, ovl29 |
| `camp-save` | camp, save | ovl15, save files |
| `camp-rest-combat`, `parley-combat` | rest until a fight; parley; quick combat | combat (ovl08, ovl09, ovl13, ovl17, ovl24) |
| `battle-aftermath` | the fight to its end, treasure, the character sheet's menus | ovl05, ovl19, ovl21, ovl22 (spell list) |
| `combat-spells` | the same fight with the party casting (Bless, Sleep) | ovl22 casting, ovl12 affects, the aim prompt |
| `shop-buy` | the shop of the unsettled area | ovl06, ovl21, ovl19 |
| `temple-cast` | the temple's menu, then camp magic | ovl04, ovl15, ovl22 |
| `temple-heal` | the wounded party at the temple: heal, cure, raise dead, ... | ovl04, ovl21, ovl24 |
| `camp-magic` | camp menus: magic, memorise, party order | ovl15, ovl22 |
| `character-view` | camp, a character's sheet: items, money | ovl19, ovl21 |
| `character-menu` | the character menu: train, modify, drop | ovl16, ovl19 |
| `council-guards` | the City Hall's guards (a scripted fight the party loses) | ovl03, ovl07, ovl09, ovl13, ovl17, the end of the game |
