"""Checks on the translated game (c/game) for defects the translator once had that no recorded session showed until a session
reached the code (tests/sessions/COVERAGE.md says which code that is). Each one is a class, not a line: the check looks at the
whole translation."""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "c/game"
sys.path.insert(0, str(ROOT / "tools/c"))

# `SpellHandlers[CastingSpell];` was written as a statement of its own: Turbo Pascal calls a procedure variable named as a
# statement, the translator evaluated it and called nothing, so no spell ever had an effect on the translation (found by the
# combat-spells session: Sleep and Bless never ran).
NO_OP_STATEMENT = re.compile(r"^\s*\(*\*?[A-Za-z_]\w*(\[[^\]]*\]|\.[A-Za-z_]\w*|->[A-Za-z_]\w*)*\)*;\s*$")


def test_no_statement_that_does_nothing():
    bad = []
    for f in sorted(GAME.glob("*.c")):
        for n, line in enumerate(f.read_text(errors="replace").split("\n"), 1):
            s = line.strip()
            if NO_OP_STATEMENT.match(line) and not re.match(r"(return|break|continue|goto)\b", s) and s != ";":
                bad.append("%s:%d  %s" % (f.name, n, s))
    assert not bad, "expression statements with no effect (a call the translator dropped?):\n" + "\n".join(bad[:20])


def test_spell_handler_is_called():
    src = (GAME / "ovl22.c").read_text()
    assert "rtl_proc(SpellHandlers[CastingSpell])" in src


# `Integer(WordVar) < 0` was written `WordVar < 0` (the cast of a same-size variable kept the C type of the variable): always
# false on an unsigned, so the Spells window of the character sheet never opened (found by the battle-aftermath session).
def test_integer_cast_of_a_word_reads_it_signed():
    src = (GAME / "ovl19.c").read_text()
    assert re.search(r"\(\*\(s16 \(\*\)\)&\(\*Choice\)\) < 0", src), "ChooseSpellFromList's Integer(Choice) < 0 lost its cast"

