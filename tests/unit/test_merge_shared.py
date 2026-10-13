"""The record-level merge driver for the shared files: records merge, only same-record edits conflict."""
import re
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/agent"))
import merge_shared as ms
import safety

SYMBOLS = "re/symbols.toml"
POOLVARS = "src/POOLVARS.PAS"


def routine(uid, off, **fields):
    rec = {"id": "%s:%04X" % (uid, off), "unit": uid, "addr": "%s:%04X" % (uid, off), "size": 1,
           "name": "%s_fn_%04X" % (uid, off), "signature": "", "level": "none", "notes": "",
           "evidence": ["prologue"]}
    rec.update(fields)
    return "[[routine]]\n" + "".join("%s = %s\n" % (k, ms.toml_value(v)) for k, v in rec.items())


HEADER = "# Every routine the project knows.\n# Hand edits are preserved by id.\n\n"


def symbols(*records):
    return HEADER + "\n".join(records)


def set_field(text, key, name, value):
    """Change one field of the record `key` in a TOML registry text (value already TOML-formatted)."""
    out, n = re.subn(r'(id = "%s"\n(?:(?!\[\[).)*?^%s = )[^\n]*' % (re.escape(key), name),
                     lambda m: m.group(1) + value, text, flags=re.S | re.M)
    assert n == 1
    return out


def merged(base, ours, theirs, path=SYMBOLS):
    return ms.merge_texts(base, ours, theirs, path)


def test_identical_inputs_are_returned_byte_for_byte():
    for path in (SYMBOLS, "re/dseg.toml", "re/renames.toml", "re/learnings/shared.toml", POOLVARS):
        text = (ROOT / path).read_text()
        assert merged(text, text, text, path) == (text, 0)


def test_records_added_on_each_side_are_both_kept_in_order():
    a, b, c, d = routine("ovl01", 0), routine("ovl01", 0x100), routine("ovl01", 0x206), routine("ovl01", 0x300)
    base = symbols(a, c)
    ours = symbols(a, c, d)                      # sorted: appended at the end
    theirs = symbols(a, b, c)                    # sorted: inserted in the middle
    text, conflicts = merged(base, ours, theirs)
    assert conflicts == 0
    assert text == symbols(a, b, c, d)


def test_unsorted_theirs_addition_follows_its_predecessor():
    a, b, c, x = routine("ovl01", 0), routine("ovl01", 0x100), routine("ovl01", 0x206), routine("ovl02", 0)
    base = symbols(a, c)
    ours = symbols(a, c, x)
    theirs = symbols(c, a, b)                    # theirs reordered its file: no sorted insertion
    text, conflicts = merged(base, ours, theirs)
    assert conflicts == 0
    assert text == symbols(a, b, c, x)           # ours' order, b after a (its predecessor in theirs)


def test_record_deleted_on_one_side_and_untouched_on_the_other_is_deleted():
    a, b, c = routine("ovl01", 0), routine("ovl01", 0x100), routine("ovl01", 0x206)
    base = symbols(a, b, c)
    theirs = set_field(base, "ovl01:0206", "level", '"L2"')
    text, conflicts = merged(base, symbols(a, c), theirs)
    assert conflicts == 0
    assert text == symbols(a, set_field(c, "ovl01:0206", "level", '"L2"'))


def test_record_deleted_on_one_side_and_changed_on_the_other_conflicts():
    a, b = routine("ovl01", 0), routine("ovl01", 0x100)
    base = symbols(a, b)
    text, conflicts = merged(base, set_field(base, "ovl01:0100", "level", '"L2"'), symbols(a))
    assert conflicts == 1
    assert text.startswith(symbols(a) + ms.OURS + "\n") and text.rstrip().endswith(ms.THEIRS)


def test_same_field_changed_to_the_same_value_on_both_sides_is_clean():
    base = symbols(routine("ovl01", 0), routine("ovl01", 0x100))
    ours = set_field(base, "ovl01:0000", "level", '"L2"')
    theirs = set_field(base, "ovl01:0000", "level", '"L2"')
    theirs = set_field(theirs, "ovl01:0100", "notes", '"theirs"')
    text, conflicts = merged(base, ours, theirs)
    assert conflicts == 0
    assert text == set_field(ours, "ovl01:0100", "notes", '"theirs"')


def test_fields_changed_on_different_sides_of_one_record_merge_field_by_field():
    base = symbols(routine("ovl01", 0))
    ours = set_field(base, "ovl01:0000", "level", '"L2"')
    theirs = set_field(base, "ovl01:0000", "signature", '"procedure Foo(A: Byte)"')
    text, conflicts = merged(base, ours, theirs)
    assert conflicts == 0
    assert text == set_field(ours, "ovl01:0000", "signature", '"procedure Foo(A: Byte)"')


def test_different_values_conflict_on_that_record_only_and_exit_1(tmp_path):
    a, b = routine("ovl01", 0), routine("ovl01", 0x100)
    base = symbols(a, b)
    ours = set_field(set_field(base, "ovl01:0000", "level", '"L2"'), "ovl01:0100", "notes", '"ours"')
    theirs = set_field(set_field(base, "ovl01:0000", "level", '"L1"'), "ovl01:0100", "size", "7")
    paths = []
    for name, text in (("base", base), ("ours", ours), ("theirs", theirs)):
        (tmp_path / name).write_text(text)
        paths.append(str(tmp_path / name))
    assert ms.main([*paths, SYMBOLS]) == 1
    text = (tmp_path / "ours").read_text()
    block = text[text.index(ms.OURS):text.index(ms.THEIRS)]
    assert 'level = "L2"' in block and 'level = "L1"' in block
    # The other record is merged normally, outside the markers.
    rest = text.replace(block, "")
    assert 'notes = "ours"' in rest and "size = 7" in rest and ms.SEPARATOR not in rest


def test_lists_changed_on_both_sides_are_the_ordered_union_honouring_removals():
    base = symbols(routine("ovl01", 0, evidence=["prologue", "stale"]))
    ours = set_field(base, "ovl01:0000", "evidence", '["prologue", "ours-probe"]')
    theirs = set_field(base, "ovl01:0000", "evidence", '["prologue", "stale", "theirs-probe"]')
    text, conflicts = merged(base, ours, theirs)
    assert conflicts == 0
    assert safety.entries(text, "routine", "id")["ovl01:0000"]["evidence"] == ["prologue", "ours-probe", "theirs-probe"]


def test_notes_changed_on_both_sides_are_joined_unless_one_contains_the_other():
    base = symbols(routine("ovl01", 0, notes="auto:entry"))
    ours = set_field(base, "ovl01:0000", "notes", '"reads the key; auto:entry"')
    theirs = set_field(base, "ovl01:0000", "notes", '"called by ovl02; auto:entry"')
    text, conflicts = merged(base, ours, theirs)
    assert conflicts == 0
    assert safety.entries(text, "routine", "id")["ovl01:0000"]["notes"] == \
        "reads the key; auto:entry; called by ovl02; auto:entry"
    longer = set_field(base, "ovl01:0000", "notes", '"reads the key; auto:entry (ours)"')
    text, conflicts = merged(base, ours, longer)
    assert conflicts == 0 and 'notes = "reads the key; auto:entry (ours)"' in text


def test_comments_and_blank_lines_survive_a_merge():
    a = "# the first routine\n" + routine("ovl01", 0) + "\n\n"
    b = routine("ovl01", 0x100) + "# a trailing remark\n\n"
    c = routine("ovl01", 0x206)
    base = symbols(a, b, c)
    ours = set_field(base, "ovl01:0000", "level", '"L2"')
    theirs = set_field(base, "ovl01:0206", "level", '"L2"')
    text, conflicts = merged(base, ours, theirs)
    assert conflicts == 0
    assert text == set_field(ours, "ovl01:0206", "level", '"L2"')
    assert "# the first routine\n" in text and "# a trailing remark\n\n" in text and text.startswith(HEADER)


def test_header_comment_edits_merge_as_text():
    base = symbols(routine("ovl01", 0))
    ours = base.replace("# Hand edits", "# Hand edits (ours)")
    theirs = set_field(base, "ovl01:0000", "level", '"L2"')
    text, conflicts = merged(base, ours, theirs)
    assert conflicts == 0 and text == set_field(ours, "ovl01:0000", "level", '"L2"')


def test_realistic_symbols_slice_loses_nothing_the_safety_oracle_tracks():
    full = (ROOT / SYMBOLS).read_text()
    doc = ms.parse_toml(full, ms.classify(SYMBOLS))
    base = "\n".join(doc.head) + "\n" + "\n".join("\n".join(r.lines) for r in doc.records[:8]) + "\n"
    keys = [r.key for r in doc.records[:8]]
    ours = set_field(base, keys[0], "level", '"L3"')
    ours = set_field(ours, keys[1], "evidence", '["prologue", "ours-probe"]')
    ours = set_field(ours, keys[2], "notes", '"ours note"')
    ours = ours.replace("[[routine]]\nid = \"%s\"" % keys[3], routine("ovl00", 0x0040, name="OursAdded") + "\n[[routine]]\nid = \"%s\"" % keys[3])
    theirs = set_field(base, keys[1], "evidence", '["prologue", "theirs-probe"]')
    theirs = set_field(theirs, keys[2], "notes", '"theirs note"')
    theirs = set_field(theirs, keys[4], "signature", '"procedure TheirsSigned(X: Word)"')
    theirs = theirs.replace("\n" + "\n".join(doc.records[7].lines), "")        # theirs deleted the last record
    assert keys[7] not in theirs
    text, conflicts = merged(base, ours, theirs)
    assert conflicts == 0
    snapshots = [safety.entries(t, "routine", "id") for t in (base, ours, theirs, text)]
    assert safety.table_findings(SYMBOLS, *snapshots) == []
    result = snapshots[3]
    assert result[keys[1]]["evidence"] == ["prologue", "ours-probe", "theirs-probe"]
    assert result[keys[2]]["notes"] == "ours note; theirs note"
    assert result[keys[0]]["level"] == "L3" and result[keys[4]]["signature"] == "procedure TheirsSigned(X: Word)"
    assert "ovl00:0040" in result


def test_dseg_records_keyed_by_name_merge_with_offset_order():
    def g(off, name, **more):
        rec = {"offset": off, "name": name, "evidence": "probe"}
        rec.update(more)
        return "[[global]]\n" + "".join("%s = %s\n" % (k, ms.toml_value(v)) for k, v in rec.items())
    base = "# DGROUP\n\n" + "\n".join([g(0x100, "First"), g(0x300, "Third")])
    ours = "# DGROUP\n\n" + "\n".join([g(0x100, "First"), g(0x300, "Third"), g(0x400, "Fourth")])
    theirs = "# DGROUP\n\n" + "\n".join([g(0x100, "First"), g(0x200, "Second"), g(0x300, "Third", size=2)])
    text, conflicts = merged(base, ours, theirs, "re/dseg.toml")
    assert conflicts == 0
    assert list(safety.entries(text, "global", "name")) == ["First", "Second", "Third", "Fourth"]
    assert safety.entries(text, "global", "name")["Third"]["size"] == 2


def test_learning_files_match_the_glob():
    assert ms.classify("re/learnings/ovl12.toml").table == "lesson"
    assert ms.classify("re/renames.toml").key == "old"
    assert ms.classify(POOLVARS) == ms.POOLVARS
    assert ms.classify("src/OVL12.PAS") is None
    assert ms.sniff('[[lesson]]\nid = "x"\n').table == "lesson"


# ---------------------------------------------------------------- POOLVARS.PAS

PV_HEAD = ("unit POOLVARS;\n{ Game globals whose owning unit is not known yet. }\n{$A-,F+,S-,R-,G-,I-}\n"
           "interface\nuses Dos;\ntype\n  TPair = record\n    A, B: Byte;\n  end;\nconst\n  VarMapX = 195;\nvar\n")
PV_TAIL = "implementation\nend.\n"


def poolvars(*entries):
    return PV_HEAD + "".join(entries) + PV_TAIL


E0100 = "  ds0100: Word;                   { the first word }\n"
E0300 = ("  { A comment block above the declaration: two lines\n    explaining the table. }\n"
         "  ds0300: array[0..35, 0..43] of Byte;  { the area map: one code per block,\n"
         "                                          continued on a second line }\n")
E0500 = "  Regs: Registers;                { registers for Intr calls }\n"
E0700 = "  ds0700: ShortInt;               { the party's column }\n    { ShortInt, not Byte: widened with cbw. }\n"


def test_poolvars_entries_added_on_each_side_land_in_offset_order(monkeypatch):
    monkeypatch.setattr(ms, "_offsets", {"regs": 0x500, "newname": 0x600})
    base = poolvars(E0100, E0300, E0500, E0700)
    ours = poolvars(E0100, "  ds0200: Byte;                   { ours }\n", E0300, E0500, E0700)
    theirs = poolvars(E0100, "  ds0250: Byte;                   { theirs }\n", E0300, E0500,
                      "  NewName: Pointer;               { theirs, named in dseg }\n", E0700)
    text, conflicts = merged(base, ours, theirs, POOLVARS)
    assert conflicts == 0
    assert text == poolvars(E0100, "  ds0200: Byte;                   { ours }\n",
                            "  ds0250: Byte;                   { theirs }\n", E0300, E0500,
                            "  NewName: Pointer;               { theirs, named in dseg }\n", E0700)
    assert set(safety.declarations(ours)) | set(safety.declarations(theirs)) <= set(safety.declarations(text))


def test_poolvars_unsorted_side_inserts_after_the_predecessor(monkeypatch):
    monkeypatch.setattr(ms, "_offsets", {})
    base = poolvars(E0300, E0100)                                    # not in offset order
    ours = poolvars(E0300, E0100, "  ds0050: Byte;\n")
    theirs = poolvars(E0300, "  ds0200: Byte;\n", E0100)
    text, conflicts = merged(base, ours, theirs, POOLVARS)
    assert conflicts == 0
    assert text == poolvars(E0300, "  ds0200: Byte;\n", E0100, "  ds0050: Byte;\n")


def test_poolvars_multi_line_declarations_and_comment_blocks_are_preserved(monkeypatch):
    monkeypatch.setattr(ms, "_offsets", {})
    base = poolvars(E0100, E0300, E0700)
    ours = poolvars(E0100.replace("Word", "Byte"), E0300, E0700)
    theirs = poolvars(E0100, E0300, E0700.replace("the party's column", "the party's row"))
    text, conflicts = merged(base, ours, theirs, POOLVARS)
    assert conflicts == 0
    assert text == poolvars(E0100.replace("Word", "Byte"), E0300, E0700.replace("the party's column", "the party's row"))
    doc = ms.split_poolvars(text)
    assert [r.key for r in doc.records] == ["ds0100", "ds0300", "ds0700"]
    assert "\n".join(doc.records[1].lines) + "\n" == E0300
    assert "\n".join(doc.records[2].lines) + "\n" == E0700.replace("the party's column", "the party's row")


def test_poolvars_same_entry_changed_differently_conflicts_with_markers_around_it(monkeypatch):
    monkeypatch.setattr(ms, "_offsets", {})
    base = poolvars(E0100, E0300)
    ours = poolvars(E0100.replace("Word", "Byte"), E0300)
    theirs = poolvars(E0100.replace("Word", "Integer"), E0300.replace("area map", "AREA MAP"))
    text, conflicts = merged(base, ours, theirs, POOLVARS)
    assert conflicts == 1
    expected = poolvars(ms.OURS + "\n" + E0100.replace("Word", "Byte") + ms.SEPARATOR + "\n" +
                        E0100.replace("Word", "Integer") + ms.THEIRS + "\n", E0300.replace("area map", "AREA MAP"))
    assert text == expected


def test_poolvars_head_and_tail_merge_as_text(monkeypatch):
    monkeypatch.setattr(ms, "_offsets", {})
    base = poolvars(E0100)
    ours = base.replace("  TPair = record", "  TTriple = record\n    C: Byte;\n  end;\n  TPair = record")
    theirs = base.replace("  VarMapX = 195;", "  VarMapX = 195;\n  VarMapY = 196;").replace("implementation\n", "implementation\n{ nothing }\n")
    text, conflicts = merged(base, ours, theirs, POOLVARS)
    assert conflicts == 0
    assert "  TTriple = record" in text and "  VarMapY = 196;" in text and "implementation\n{ nothing }\n" in text
    both = base.replace("  VarMapX = 195;", "  VarMapX = 194;")
    text, conflicts = merged(base, ours.replace("  VarMapX = 195;", "  VarMapX = 196;"), both, POOLVARS)
    assert conflicts == 1 and ms.OURS in text and "  TTriple = record" in text


def test_other_paths_fall_back_to_a_plain_text_merge(tmp_path):
    (tmp_path / "base").write_text("a\nb\nc\n")
    (tmp_path / "ours").write_text("a1\nb\nc\n")
    (tmp_path / "theirs").write_text("a\nb\nc2\n")
    args = [str(tmp_path / n) for n in ("base", "ours", "theirs")]
    assert ms.main([*args, "docs/notes.md"]) == 0
    assert (tmp_path / "ours").read_text() == "a1\nb\nc2\n"
    (tmp_path / "theirs").write_text("a2\nb\nc\n")
    assert ms.main([*args, "docs/notes.md"]) == 1
    assert "<<<<<<< ours" in (tmp_path / "ours").read_text()


def test_unparseable_registry_falls_back_to_a_text_merge_with_markers(capsys):
    base = symbols(routine("ovl01", 0))
    ours = set_field(base, "ovl01:0000", "level", '"L2"')
    theirs = base + "[[routine]]\nid = \"ovl01:0000\"\n"                       # duplicate id
    text, conflicts = merged(base, ours, theirs)
    assert conflicts >= 1
    assert "falling back" in capsys.readouterr().err


# ---------------------------------------------------------------- a real git merge

def git_at(path, *args):
    return subprocess.check_output(["git", *args], cwd=path, text=True).strip()


def commit(path, message="fixture"):
    git_at(path, "add", "-A", ".")
    git_at(path, "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", message)
    return git_at(path, "rev-parse", "HEAD")


def test_git_merge_with_the_driver_merges_different_records_cleanly(tmp_path, monkeypatch):
    repo = tmp_path / "clone"
    (repo / "re").mkdir(parents=True)
    (repo / "src").mkdir()
    git_at(repo, "init", "-q", "-b", "main")
    (repo / ".gitattributes").write_text((ROOT / ".gitattributes").read_text())
    git_at(repo, "config", "merge.poolrad-shared.name", "test driver")
    git_at(repo, "config", "merge.poolrad-shared.driver",
           "%s %s %%O %%A %%B %%P" % (sys.executable, ROOT / "tools/agent/merge_shared.py"))
    a, b, c = routine("ovl01", 0), routine("ovl01", 0x100), routine("ovl01", 0x206)
    (repo / SYMBOLS).write_text(symbols(a, b, c))
    (repo / POOLVARS).write_text(poolvars(E0100, E0300, E0700))
    (repo / "re/dseg.toml").write_text("")
    commit(repo)
    git_at(repo, "switch", "-qc", "unit/left")
    (repo / SYMBOLS).write_text(set_field(symbols(a, b, c), "ovl01:0000", "level", '"L2"'))
    (repo / POOLVARS).write_text(poolvars(E0100, "  ds0200: Byte;                   { left }\n", E0300, E0700))
    commit(repo, "left")
    git_at(repo, "switch", "-qc", "unit/right", "main")
    (repo / SYMBOLS).write_text(set_field(symbols(a, b, c), "ovl01:0206", "signature", '"procedure Right"'))
    (repo / POOLVARS).write_text(poolvars(E0100, E0300, "  ds0500: Byte;                   { right }\n", E0700))
    commit(repo, "right")
    git_at(repo, "switch", "-q", "unit/left")
    monkeypatch.setattr(ms, "_offsets", {})
    result = subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                             "merge", "-q", "--no-edit", "unit/right"], cwd=repo, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert git_at(repo, "diff", "--name-only", "--diff-filter=U") == ""
    expected = set_field(set_field(symbols(a, b, c), "ovl01:0000", "level", '"L2"'), "ovl01:0206", "signature", '"procedure Right"')
    assert (repo / SYMBOLS).read_text() == expected
    assert (repo / POOLVARS).read_text() == poolvars(E0100, "  ds0200: Byte;                   { left }\n", E0300,
                                                     "  ds0500: Byte;                   { right }\n", E0700)
    # The merge-check oracle agrees that nothing was lost.
    monkeypatch.setattr(safety.common, "ROOT", repo)
    monkeypatch.chdir(repo)
    assert safety.merge_findings("HEAD") == []


def test_git_merge_with_the_driver_leaves_a_same_record_conflict_for_the_human(tmp_path):
    repo = tmp_path / "clone"
    (repo / "re").mkdir(parents=True)
    git_at(repo, "init", "-q", "-b", "main")
    (repo / ".gitattributes").write_text((ROOT / ".gitattributes").read_text())
    git_at(repo, "config", "merge.poolrad-shared.driver",
           "%s %s %%O %%A %%B %%P" % (sys.executable, ROOT / "tools/agent/merge_shared.py"))
    a, b = routine("ovl01", 0), routine("ovl01", 0x100)
    (repo / SYMBOLS).write_text(symbols(a, b))
    commit(repo)
    git_at(repo, "switch", "-qc", "unit/left")
    (repo / SYMBOLS).write_text(set_field(set_field(symbols(a, b), "ovl01:0000", "level", '"L2"'), "ovl01:0100", "notes", '"left"'))
    commit(repo, "left")
    git_at(repo, "switch", "-qc", "unit/right", "main")
    (repo / SYMBOLS).write_text(set_field(symbols(a, b), "ovl01:0000", "level", '"L1"'))
    commit(repo, "right")
    git_at(repo, "switch", "-q", "unit/left")
    result = subprocess.run(["git", "merge", "-q", "--no-edit", "unit/right"], cwd=repo, capture_output=True, text=True)
    assert result.returncode == 1
    assert git_at(repo, "diff", "--name-only", "--diff-filter=U") == SYMBOLS
    text = (repo / SYMBOLS).read_text()
    assert ms.OURS in text and 'notes = "left"' in text.split(ms.THEIRS)[1]
