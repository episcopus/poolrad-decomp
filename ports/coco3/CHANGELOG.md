# Changelog: Pool of Radiance for the Tandy Color Computer 3

What changed in each version of the CoCo 3 port, newest first. The version is on the game's credits screen. The numbers follow semantic versioning: the
first goes up when an update makes you start over or change hardware, the second when something is added or changed, the third for fixes
(`docs/VERSIONING.md`).

## Unreleased

## 1.2.0 - 2026-11-16

### Added
- SuperIDE card: `ide_card.py pull` copies a saved game off the card into a PC game's `SAVE` folder, so you can carry on playing on a PC or a Tandy
  1000. The card is only read. A different saved game in the same slot of the folder is replaced only when you ask for it (`--replace-slot`), and its
  old files are kept in a backup folder.

## 1.1.0 - 2026-11-15

### Added
- SuperIDE card: `ide_card.py` can put saved games from a PC game's `SAVE` folder into a card that already holds the game (`--add-slot`), keeping the
  card's own saved games. A slot already in use is replaced only when you ask for it (`--replace-slot`), and a new listing shows what is in the card's
  save area.

### Changed
- Big battles are faster: the monsters choose their targets with much less work, so the machine spends about 30 % less time on a fight against a
  large crowd. The fights play out the same, roll for roll.
- The credits screen shows the full version number (`V1.1.0`).

### Fixed
- When the game moves the party to another map (the boat from New Phlan, the gate between the Slums and New Phlan), the location line under the party
  kept the old map's position, facing and time until the next step. It now shows the new map's at once. This is a bug of the original game.

## 1.0.1 - 2026-11-08

The builds of this version still show `V1.0` on the credits screen.

### Fixed
- Quick combat no longer hangs when a party member fights with darts. This is a bug of the original game.
- The credits screen names the port's author as Episcopus.

## 1.0.0 - 2026-10-25

The first release: the whole game on a CoCo 3 with 512 KB, played through 16 recorded test sessions (character creation, shopping, camping, combat and
saving) that match the PC original screen for screen.

### Added
- Six builds: twelve 35 track disks, five 80 track disks (XRoar with four drives, or real 80 track drives), one file for the CoCo SDC, a card image for
  a SuperIDE or Glenside IDE with the tool that writes it, and ready-made XRoar and MAME packs.
- The floppy sets are laid out so the game asks for as few disk swaps as possible.
- Sound: the PC speaker's effects on the CoCo's sound output.
- Encounters of any size, up to the original's 63 combatants.
- A loading screen that shows the CPU and the storage it found. On a 6309 the game runs in its native mode, which is faster. A CoCo 3 without 512 KB
  returns to BASIC with a message.
- No code wheel. The credits name the port and its version, and the game's prompts say BASIC where the PC said DOS.
- `ide_card.py` updates a card that holds an earlier build and keeps its saved games.
