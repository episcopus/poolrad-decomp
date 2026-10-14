"""make integrate: deterministic merging of hand-offs (SYSTEM-REVIEW 6.2).

A temporary clone stands in for the project: its Makefile has the targets the integrator runs, with a
`check` that fails on demand. The hand-off record, the receipt step and the lock release are faked at
the module boundary so the test covers the git mechanics: temporary worktree, merge, rejection with the
record marked and main untouched, one merge commit holding status and changelog, fast-forward of main.
"""
import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/agent"))

import common  # noqa: E402
import handoff  # noqa: E402
import integrate  # noqa: E402
import unlock  # noqa: E402

MAKEFILE = """rename: ; @true
merge-check: ; @true
status: ; @echo "generated $$(git rev-parse --short HEAD)" > work/status.md
check: ; @test -z "$$POOLRAD_TEST_CHECK_FAIL"
"""


def git(*args, cwd):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


@pytest.fixture
def clone(tmp_path, monkeypatch):
    repo = tmp_path / "repo"
    repo.mkdir()
    git("init", "-q", "-b", "main", cwd=repo)
    git("config", "user.email", "t@example.com", cwd=repo)
    git("config", "user.name", "t", cwd=repo)
    (repo / "work").mkdir()
    (repo / "docs/design").mkdir(parents=True)
    (repo / "src").mkdir()
    (repo / "Makefile").write_text(MAKEFILE)
    (repo / ".gitignore").write_text("build/\n")
    (repo / "work/status.md").write_text("old\n")
    (repo / "docs/design/CHANGELOG.md").write_text("# Changelog\n\n| Date | Section | Change | Evidence |\n|---|---|---|---|\n")
    (repo / "src/A.PAS").write_text("unit A;\n")
    git("add", "-A", cwd=repo)
    git("commit", "-qm", "base", cwd=repo)
    git("checkout", "-qb", "unit/a", cwd=repo)
    (repo / "src/A.PAS").write_text("unit A;\n{ decompiled }\n")
    git("commit", "-qam", "a: decompile X", cwd=repo)
    tip = git("rev-parse", "HEAD", cwd=repo)
    git("checkout", "-q", "main", cwd=repo)
    common_dir = repo / ".git"
    monkeypatch.setattr(common, "ROOT", repo)
    monkeypatch.setattr(common, "common_dir", lambda: common_dir)
    (common_dir / "poolrad-control.json").write_text(json.dumps({"state": "running", "reason": "test", "run_id": "t"}))
    handoffs = common_dir / "poolrad-handoffs"
    handoffs.mkdir()
    (handoffs / "a.md").write_text("unit = a\nagent = dec-t\nbranch = unit/a\ncommit = %s\nstate = complete\n"
                                   "time = 2026-10-12T00:00:00+00:00\nnote = X matched\n"
                                   "changelog = 5.1 | X decompiled | make match UNIT=a\n" % tip)
    cleared = []
    monkeypatch.setattr(handoff, "finish", lambda key, agent, decision, **kw: cleared.append(key) or (handoffs / (key + ".md")).unlink())
    monkeypatch.setattr(unlock, "main", lambda argv: 0)
    monkeypatch.setattr(handoff, "CHANGELOG", repo / "docs/design/CHANGELOG.md")
    monkeypatch.delenv("POOLRAD_TEST_CHECK_FAIL", raising=False)
    return repo, handoffs, cleared, tip


def test_a_green_hand_off_lands_on_main_as_one_commit(clone):
    repo, handoffs, cleared, tip = clone
    assert integrate.main([]) == 0
    assert cleared == ["a"]
    assert not (handoffs / "a.md").exists()
    head = git("log", "-1", "--format=%s%n%b", cwd=repo)
    assert head.startswith("Merge unit/a (complete): X matched")
    assert "Agent: integrator" in head and "Agent: dec-t" in head
    assert git("rev-list", "--count", "HEAD", cwd=repo) == "3"      # base, the unit commit, one merge commit
    assert "{ decompiled }" in (repo / "src/A.PAS").read_text()
    assert (repo / "work/status.md").read_text().startswith("generated")
    assert "| X decompiled | make match UNIT=a |" in (repo / "docs/design/CHANGELOG.md").read_text()
    assert not git("status", "--porcelain", cwd=repo)
    assert not (repo / "build/integrate/a").exists()                  # the temporary worktree is gone
    assert "integrate/a" not in git("branch", "--list", cwd=repo)


def test_a_red_check_rejects_and_leaves_main_untouched(clone, monkeypatch):
    repo, handoffs, cleared, tip = clone
    before = git("rev-parse", "HEAD", cwd=repo)
    monkeypatch.setenv("POOLRAD_TEST_CHECK_FAIL", "1")
    assert integrate.main([]) == 1
    assert cleared == []
    assert git("rev-parse", "HEAD", cwd=repo) == before
    assert not git("status", "--porcelain", cwd=repo)
    f = common.fields((handoffs / "a.md").read_text())
    assert f["integrate"] == "rejected" and "make check failed" in f["integrate_reason"]
    assert Path(f["integrate_log"]).exists() and "$ make check" in Path(f["integrate_log"]).read_text()
    assert f["commit"] == tip and f["agent"] == "dec-t"              # the worker's fields survive
    # A rejected record waits for its worker: it is skipped until re-handed off, unless named.
    assert integrate.pending() == []
    assert [p.stem for p in integrate.pending("a")] == ["a"]
    monkeypatch.delenv("POOLRAD_TEST_CHECK_FAIL")
    assert integrate.main(["--key", "a"]) == 0
    assert cleared == ["a"]


def test_a_conflict_is_rejected_with_the_file_named(clone):
    repo, handoffs, cleared, tip = clone
    (repo / "src/A.PAS").write_text("unit A;\n{ conflicting }\n")
    git("commit", "-qam", "main moved", cwd=repo)
    before = git("rev-parse", "HEAD", cwd=repo)
    assert integrate.main([]) == 1
    f = common.fields((handoffs / "a.md").read_text())
    assert f["integrate"] == "rejected" and "merge conflict in src/A.PAS" in f["integrate_reason"]
    assert git("rev-parse", "HEAD", cwd=repo) == before
    assert not git("status", "--porcelain", cwd=repo)


def test_dry_run_merges_in_the_temporary_worktree_only(clone):
    repo, handoffs, cleared, tip = clone
    before = git("rev-parse", "HEAD", cwd=repo)
    assert integrate.main(["--dry"]) == 0
    assert git("rev-parse", "HEAD", cwd=repo) == before and cleared == []
    assert (handoffs / "a.md").exists()


def test_a_dirty_main_or_a_missing_branch_is_refused(clone, capsys):
    repo, handoffs, cleared, tip = clone
    (handoffs / "a.md").write_text((handoffs / "a.md").read_text().replace("branch = unit/a", "branch = unit/none"))
    assert integrate.main([]) == 1
    assert "does not exist" in common.fields((handoffs / "a.md").read_text())["integrate_reason"]
    (repo / "src/A.PAS").write_text("dirty\n")
    assert integrate.main([]) == 2
    assert "uncommitted" in capsys.readouterr().err


def test_a_branch_already_in_main_only_gets_its_bookkeeping(clone):
    repo, handoffs, cleared, tip = clone
    git("merge", "--no-ff", "-q", "-m", "merged by hand", "unit/a", cwd=repo)
    before = git("rev-parse", "HEAD", cwd=repo)
    assert integrate.main([]) == 0
    assert cleared == ["a"] and git("rev-parse", "HEAD", cwd=repo) == before


def test_main_moving_during_the_check_integrates_again_instead_of_rejecting(clone, monkeypatch):
    """2026-10-14: ovl22 was rejected because a tooling merge and a roster commit landed on main while its
    make check ran; the hand-off itself was fine."""
    repo, handoffs, cleared, tip = clone
    real_make = integrate.make
    checks = []

    def make(target, cwd, log, *extra):
        if target == "check":
            checks.append(cwd)
            if len(checks) == 1:                       # someone commits to main during the first check
                (repo / "work/roster.toml").write_text("# moved\n")
                git("add", "work/roster.toml", cwd=repo)
                git("commit", "-qm", "roster edit during the integration", cwd=repo)
        return real_make(target, cwd, log, *extra)
    monkeypatch.setattr(integrate, "make", make)
    assert integrate.main([]) == 0
    assert len([c for c in checks if Path(c) != repo]) == 2 and cleared == ["a"]   # two integrations, one per main
    log = git("log", "--format=%s", "-3", cwd=repo).splitlines()
    assert log[0].startswith("Merge unit/a (complete)") and log[1] == "roster edit during the integration"


def test_main_moving_again_on_the_retry_is_still_rejected(clone, monkeypatch):
    repo, handoffs, cleared, tip = clone
    real_make = integrate.make
    n = []

    def make(target, cwd, log, *extra):
        if target == "check":
            n.append(1)
            (repo / "work/roster.toml").write_text("# moved %d\n" % len(n))
            git("add", "work/roster.toml", cwd=repo)
            git("commit", "-qm", "moves again", cwd=repo)
        return real_make(target, cwd, log, *extra)
    monkeypatch.setattr(integrate, "make", make)
    assert integrate.main([]) == 1                      # one retry, then the usual rejection
    assert len(n) == 2 and "integrate = rejected" in (handoffs / "a.md").read_text()
