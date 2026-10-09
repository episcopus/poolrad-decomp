#!/usr/bin/env python3
"""name_units.py: set provisional/real unit names from strings in code (playbook 10).

Updates re/units.toml `name` and `evidence` for overlays (and notes prior-art leads).
Does not invent names without a string or documented lead.

Usage:
  python3 tools/re/name_units.py [--units re/units.toml]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# (substring to find in overlay code, unit name, evidence tag)
# Prior-art rows are [H] analogies to coab/OpenGoldBox only when our string also matches.
RULES = [
    (b"Unable to find item file", "Encounter", "[V] string in ovl; combat/parlay menus nearby"),
    (b"~COMBAT ~WAIT ~FLEE", "Encounter", "[V] encounter menu strings"),
    (b"Heal View Take Pool Share", "Temple", "[V] temple/heal menu"),
    (b"Buy View Take Pool Share", "Shop", "[V] shopkeeper dialogue/menu"),
    (b"as you Leave the Shopkeeper", "Shop", "[V] shopkeeper string"),
    (b"Move/Attack, Move Left", "CombatAI", "[V] combat move/attack string"),
    (b"Not with that weapon", "CombatAI", "[V] combat weapon check"),
    (b"Begins Casting", "CombatSpells", "[V] combat casting strings"),
    (b"Attack Ally:", "CombatSpells", "[V] combat spell UI"),
    (b"memorize spells", "SpellMemorize", "[V] camp spell memorize"),
    (b"Cleric Spells:", "SpellMemorize", "[V] spell list UI"),
    (b"Keep this character?", "CharCreate", "[V] character creation/training"),
    (b"Training costs 1000 gp", "CharCreate", "[V] training hall"),
    (b"Character name:", "CharCreate", "[V] name prompt"),
    (b"Put save disk in", "SaveLoad", "[V] save disk prompt"),
    (b"Load Which Game:", "SaveLoad", "[V] load menu"),
    (b"With the power of the pool of radiance", "PoolNarrative", "[V] pool of radiance text"),
    (b"Ready Item", "Inventory", "[V] item ready/trade UI"),
    (b"Trade with Whom?", "Inventory", "[V] trade UI"),
    (b"Choose Spell:", "CastSpell", "[V] spell chooser"),
    (b"Cast Spell on whom", "CastSpell", "[V] spell target"),
    (b"LoadWallSet", "GeoLoad", "[V] LoadWallSet error string"),
    (b"Load3DMap", "GeoLoad", "[V] Load3DMap error string"),
    (b"Load24x24Set", "PicLoad", "[V] Load24x24Set range error"),
    (b"Unable to load 8x8D", "TileLoad", "[V] 8x8D load error"),
    (b"The Whole Party Is Healed", "PartyHeal", "[V] heal-all string"),
    (b"Select type of coin", "Money", "[V] coin select"),
    (b"Loading...Please Wait", "Loader", "[V] loading banner"),
    (b"Gains an item", "TrainRewards", "[V] training reward"),
    (b"Each character receives", "TreasureShare", "[V] treasure share"),
    (b"Money Items Exit", "TreasureShare", "[V] treasure menu"),
]

# Unit-level prior-art leads (coab family) when our name already set from strings.
PRIOR_ART = {
    "Encounter": "[H] coab ovr* encounter/parlay family (addresses differ; role only)",
    "CombatAI": "[H] coab combat overlay family",
    "CombatSpells": "[H] coab combat spell overlays",
    "SpellMemorize": "[H] coab camp/spell memorize",
    "SaveLoad": "[H] coab save/load overlays",
    "GeoLoad": "[H] OpenGoldBox/coab geo+wall loaders",
    "CharCreate": "[H] coab character creation/training",
}


def find_strings(blob: bytes, minlen: int = 5) -> list[str]:
    out = []
    i = 0
    while i < len(blob):
        if i + 1 < len(blob) and 5 <= blob[i] <= 90:
            n = blob[i]
            s = blob[i + 1 : i + 1 + n]
            if len(s) == n and all(32 <= b < 127 for b in s):
                out.append(s.decode("ascii"))
                i += 1 + n
                continue
        j = i
        while j < len(blob) and 32 <= blob[j] < 127:
            j += 1
        if j - i >= minlen:
            out.append(blob[i:j].decode("ascii"))
            i = j
            continue
        i += 1
    return out


def set_fields(text: str, unit_id: str, name: str, evidence: str) -> str:
    parts = re.split(r"(?=\[\[resident\]\]|\[\[overlay\]\])", text)
    out = []
    for part in parts:
        if re.search(r'^id\s*=\s*"%s"' % re.escape(unit_id), part, re.M):
            part = re.sub(
                r'^name\s*=\s*".*"',
                'name = "%s"' % name,
                part,
                count=1,
                flags=re.M,
            )
            part = re.sub(
                r'^evidence\s*=\s*".*"',
                'evidence = "%s"' % evidence.replace('"', '\\"'),
                part,
                count=1,
                flags=re.M,
            )
        out.append(part)
    return "".join(out)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--units", default=str(ROOT / "re/units.toml"))
    ap.add_argument("--overlays-json", default=str(ROOT / "build/re/overlays.json"))
    ap.add_argument("--overlays-dir", default=str(ROOT / "build/re/overlays"))
    args = ap.parse_args(argv[1:])

    man = json.loads(Path(args.overlays_json).read_text())
    units_path = Path(args.units)
    text = units_path.read_text()
    named = 0
    for o in man["overlays"]:
        idx = o["overlay"]
        uid = "ovl%02d" % idx
        code = Path(args.overlays_dir, "ovl%02d.bin" % idx).read_bytes()
        blob_strs = "\n".join(find_strings(code))
        hit_name = None
        hit_ev = None
        for needle, name, ev in RULES:
            if needle.decode("ascii", "replace") in blob_strs or needle in code:
                hit_name, hit_ev = name, ev
                break
        if not hit_name:
            continue
        if hit_name in PRIOR_ART:
            hit_ev = hit_ev + "; " + PRIOR_ART[hit_name]
        text = set_fields(text, uid, hit_name, hit_ev)
        named += 1
        print("name_units: %s -> %s" % (uid, hit_name))

    units_path.write_text(text)
    print("name_units: named %d overlays -> %s" % (named, units_path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
