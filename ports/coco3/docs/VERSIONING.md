# Versions and the changelog of the CoCo 3 port

Decided 2026-11-15 by the host: the CoCo 3 port is versioned with [semantic versioning](https://semver.org/) (MAJOR.MINOR.PATCH), its changes are kept in
`../CHANGELOG.md` for players, and every distribution (`make dist`) carries the version and the changelog. This file is the rule every agent follows.

## 1. Where the version lives

* `ports/coco3/VERSION` holds the number, three parts (`1.1.0`). It is written by `tools/changelog.py release`, never by hand.
* `tools/qol.py` puts it on the credits screen when the game is built (`EPISCOPUS - V1.1.0`), so a bug report can say which build it came from.
* `make dist` writes it into `build/dist/VERSION`, the top `README.md` and every folder's `README.txt`, and copies the changelog into every folder
  (`CHANGELOG.txt`), because the site and the testers get the folders one zip at a time.
* `build/dist/changelog.json` is the same changelog as data; the site's CoCo 3 page shows it (`npm run sync:coco3` in `~/dev/anonymousformula` copies it).

The port's version is not the PC game's (`1.3`, which the credits still show as `FROM PC V1.3`) and not the decompilation's.

## 2. What each part means

The question is always what a player of the previous version notices. The player's things that must survive an update are their saved games, their
hardware and their way of loading the game (the build they use).

| Part | Goes up when | Examples |
|---|---|---|
| MAJOR | an update makes a player start over, lose something or change hardware | saved games of the previous version no longer load or are not carried over by the update path (`ide_card.py write` on a card that holds an earlier build, the floppy set's save disk); more RAM, a 6309 or another ROM needed; a build kind dropped; a change of the game's rules that is neither a bug fix nor optional |
| MINOR | something is added or changed that a player can see or use, and their saved games, hardware and build still work | a new build or medium, a new option or quality of life change, a new tool in a build folder, a speed-up a player notices, a change of what a screen shows |
| PATCH | something is fixed, and nothing else changes | a bug of the port fixed, a bug of the original fixed (`fixes/` at the repository root), a wrong text corrected, a README of a build folder corrected, a rebuild whose bytes differ with no visible change |

The level of a release is the highest level of its entries; when MAJOR goes up, MINOR and PATCH go back to 0, when MINOR goes up PATCH goes back to 0.
A build whose bytes differ from the last release's always gets a new number: two builds that say the same version must be the same build.

## 3. The changelog

`../CHANGELOG.md` is for players, newest first, in the form of [Keep a Changelog](https://keepachangelog.com/). Every entry is one line a player
understands: what they will see, not which routine changed (commit messages and the `PHASE-*.md` reports keep that). Its sections:

| Section | Level | For |
|---|---|---|
| `### Breaking` | MAJOR | what makes a player start over, lose something or change hardware; say what they have to do |
| `### Added` | MINOR | new builds, options, tools, features |
| `### Changed` | MINOR | what works differently or faster |
| `### Fixed` | PATCH | bugs fixed, the port's and the original's (say which), texts corrected |
| `### Internal` | PATCH | a rebuild that changes the bytes and nothing a player sees |

Between releases the entries wait under `## Unreleased`. A release is a heading `## <version> - <date>` (ISO date) with the same sections, and an
optional line of text under the heading (for example the builds of 1.0.1, which still show `V1.0`).

## 4. The rule for agents

1. A change to the port that a player of a distribution would notice (anything that changes the bytes of `make dist`: the engine, the patches, the
   translator's output for the CoCo, `fixes/`, the data pipeline, the tools and texts that go into the build folders) adds its line under
   `## Unreleased` in the same commit, in the section of section 3. A change that only touches tests, the harness, the reports or tools that never reach
   a build folder adds none.
2. Nobody edits `VERSION` or turns Unreleased into a version by hand. `make dist` does it: it runs `tools/changelog.py release`, which picks the level from
   the sections under Unreleased (section 2), writes the new `VERSION`, dates the release and empties Unreleased, and then builds every distribution with
   that number. With nothing under Unreleased it builds the same version again, and says so when commits have touched the port since that version was
   made (they must then have been changes no player sees, or an entry is missing).
3. Commit the result of a release on its own: `coco3: release <version>` with `VERSION` and `CHANGELOG.md`.
4. `make changelog-check` (also run by `make dist` and by the repository's `make test`, `tests/unit/test_coco3_changelog.py`) refuses a changelog that
   does not follow section 3, a `VERSION` that is not its newest release, and dashes other than the hyphen of the release headings.
5. `make release-dry` prints the version the next `make dist` would make, and why.

## 5. Where it goes

* The public repository (`make publish-sync`, `publish/README.md` at the repository root): `ports/coco3/**` is published, so the changelog, this file and
  the tool go with every sync.
* The site (`~/dev/anonymousformula`, page `content/poolrad/coco3`): after `make dist`, `npm run sync:coco3` packs the folders and copies
  `changelog.json`; the page shows the version above the downloads and the whole changelog below them.

## 6. The bootstrap (2026-11-15)

Before this file the port had `VERSION` = `1.0`, shown as `V1.0`, set by step 8.13 (2026-10-25) and never changed. The history was read back from the
commits into three versions:

* 1.0.0, 2026-10-25: the first distribution (`make dist`, steps 8.10 to 8.13).
* 1.0.1, 2026-11-08: the builds the site's downloads were made from: the darts quick-combat fix of `fixes/` (2026-11-01) and the credits' new name.
  Only fixes, so a patch. Those builds still say `V1.0`.
* 1.1.0, 2026-11-15: the big battle's targeting (8.9k, a fight 31 % less busy), the saved-game slots of `ide_card.py` and the location line fix. New
  things and a speed-up a player notices, saved games kept: a minor release. It is the first build that shows three parts.
