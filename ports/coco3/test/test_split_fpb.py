"""split_fpb (tools/c/p2c_expr.py): the pointer of the outermost banked deref in a piece of generated C, for a `with` over a banked block
(the translator keeps the far pointer, not the window address) and for PEEKP (a pointer field read without taking a window)."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "tools", "c"))
from p2c_expr import ExprMixin  # noqa: E402

split = ExprMixin.split_fpb


def test_plain_deref():
    assert split("(*FPB(TCharacter *, Who))") == ("TCharacter *", "Who", "")


def test_field_path_is_kept():
    assert split("(*FPB(TCharacter *, NewCharacter)).Figure[I]") == ("TCharacter *", "NewCharacter", ".Figure[I]")


def test_nested_pointer_expression():
    code = "(*FPB(TCombatant *, PEEKP(TCharacter *, Who, .Combat))).Panic"
    assert split(code) == ("TCombatant *", "PEEKP(TCharacter *, Who, .Combat)", ".Panic")


def test_not_a_banked_deref():
    assert split("(*FPM(TCharacter *, Who))") is None
    assert split("w1->Name") is None
