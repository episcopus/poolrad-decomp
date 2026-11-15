"""The CoCo 3 port's version and changelog (ports/coco3/docs/VERSIONING.md, ports/coco3/tools/changelog.py): the real changelog follows the rules and
VERSION is its newest release; a release picks its level from the sections under Unreleased."""
import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("coco3_changelog", ROOT / "ports/coco3/tools/changelog.py")
cl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cl)

HEAD = "# Changelog\n\nIntro.\n\n"
BASE = """## 1.0.1 - 2026-11-08

A note.

### Fixed
- A fix
  over two lines.

## 1.0.0 - 2026-10-25

### Added
- Everything.
"""


def test_the_real_changelog_and_version_agree():
    log = cl.check()
    assert cl.vstr(log["releases"][0]["version"]) == (ROOT / "ports/coco3/VERSION").read_text().strip()


def test_parse_joins_continuation_lines_and_keeps_the_note():
    log = cl.parse(HEAD + "## Unreleased\n\n" + BASE)
    assert log["releases"][0]["sections"]["Fixed"] == ["A fix over two lines."]
    assert log["releases"][0]["note"] == "A note."
    assert [cl.vstr(r["version"]) for r in log["releases"]] == ["1.0.1", "1.0.0"]


@pytest.mark.parametrize("sections,want", [
    ("### Fixed\n- x\n", "1.0.2"),
    ("### Internal\n- x\n", "1.0.2"),
    ("### Added\n- x\n\n### Fixed\n- y\n", "1.1.0"),
    ("### Changed\n- x\n", "1.1.0"),
    ("### Breaking\n- x\n\n### Added\n- y\n", "2.0.0"),
])
def test_release_takes_the_highest_level(tmp_path, monkeypatch, sections, want):
    (tmp_path / "CHANGELOG.md").write_text(HEAD + "## Unreleased\n\n" + sections + "\n" + BASE)
    (tmp_path / "VERSION").write_text("1.0.1\n")
    monkeypatch.setattr(cl, "CHANGELOG", tmp_path / "CHANGELOG.md")
    monkeypatch.setattr(cl, "VERSION", tmp_path / "VERSION")
    assert cl.vstr(cl.release("2026-11-20")) == want
    assert (tmp_path / "VERSION").read_text() == want + "\n"
    log = cl.check()
    assert not log["unreleased"] and log["releases"][0]["date"] == "2026-11-20"
    assert cl.vstr(cl.release("2026-11-21")) == want          # nothing left: the same version again


@pytest.mark.parametrize("text,msg", [
    (HEAD + BASE, "Unreleased"),
    (HEAD + "## Unreleased\n\n### Fixes\n- x\n\n" + BASE, "unknown section"),
    (HEAD + "## Unreleased\n\n" + BASE.replace("1.0.1 - 2026-11-08", "1.1.0 - 2026-11-08"), "ask for patch"),
    (HEAD + "## Unreleased\n\n" + BASE.replace("1.0.1 - 2026-11-08", "1.0.3 - 2026-11-08"), "one step"),
    (HEAD + "## Unreleased\n\n" + BASE.replace("2026-11-08", "2026-10-01"), "dated before"),
    (HEAD + "## Unreleased\n\n" + BASE.replace("A fix", "A fix \u2014 here"), "dash"),
    (HEAD + "## Unreleased\n\n" + BASE.replace("## 1.0.1 - 2026-11-08", "## 1.0.1 (2026-11-08)"), "release heading"),
])
def test_parse_refuses(text, msg):
    with pytest.raises(cl.ChangelogError, match=msg):
        cl.parse(text)


def test_version_must_be_the_newest_release(tmp_path, monkeypatch):
    (tmp_path / "CHANGELOG.md").write_text(HEAD + "## Unreleased\n\n" + BASE)
    (tmp_path / "VERSION").write_text("1.0.0\n")
    monkeypatch.setattr(cl, "CHANGELOG", tmp_path / "CHANGELOG.md")
    monkeypatch.setattr(cl, "VERSION", tmp_path / "VERSION")
    with pytest.raises(cl.ChangelogError, match="VERSION says 1.0.0"):
        cl.check()
