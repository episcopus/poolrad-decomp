"""The worker supervisor (tools/agent/worker.py): planning, frontier, salvage, sessions, owner release.

Everything runs on disposable registries and Git repositories; the live clone's locks, hand-offs and
frontier are never touched (common.ROOT and common.common_dir are redirected).
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/agent"))
import claim  # noqa: E402
import common  # noqa: E402
import control  # noqa: E402
import handoff  # noqa: E402
import heartbeat  # noqa: E402
import identity  # noqa: E402
import unlock  # noqa: E402
import worker  # noqa: E402


# ----------------------------------------------------------------------------- fixtures
def git_at(path, *args):
    return subprocess.check_output(["git", *args], cwd=path, text=True).strip()


def commit(path, message="fixture"):
    git_at(path, "add", "-A")
    git_at(path, "-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", message)
    return git_at(path, "rev-parse", "HEAD")


def registry(entries):
    """entries: (id, name, level, notes) rows of one unit."""
    out = []
    for rid, name, level, notes in entries:
        out.append('[[routine]]\nid = "%s"\nunit = "%s"\naddr = "%s"\nname = "%s"\nlevel = "%s"\nnotes = "%s"\n'
                   % (rid, rid.split(":")[0], rid, name, level, notes))
    return "\n".join(out)


SOURCE = ("unit OVL00;\ninterface\nprocedure Foo;\nprocedure Bar;\nimplementation\n"
          "{@stub} procedure Foo; begin end;\n{@stub} procedure Bar; begin end;\nend.\n")


@pytest.fixture(autouse=True)
def isolated_coordination(tmp_path, monkeypatch):
    directory = tmp_path / "git-common"
    directory.mkdir()
    monkeypatch.setattr(common, "common_dir", lambda: directory)
    return directory


@pytest.fixture
def repo(tmp_path, monkeypatch):
    """A clone with one queued unit (ovl00: Foo and Bar, both stubs), admitted and with dec-1 registered."""
    main = tmp_path / "clone"
    main.mkdir()
    git_at(main, "init", "-q", "-b", "main")
    (main / "re").mkdir()
    (main / "src").mkdir()
    (main / "work").mkdir()
    (main / "re/symbols.toml").write_text(registry([("ovl00:0000", "Foo", "none", ""), ("ovl00:0040", "Bar", "none", "")]))
    (main / "re/dseg.toml").write_text("")
    (main / "src/POOLVARS.PAS").write_text("unit POOLVARS;\ninterface\nimplementation\nend.\n")
    (main / "src/OVL00.PAS").write_text(SOURCE)
    (main / "work/queue.toml").write_text('[[unit]]\nid = "ovl00"\n')
    (main / "Makefile").write_text("match:\n\t@true\n")
    commit(main)
    monkeypatch.setattr(common, "ROOT", main)
    monkeypatch.setattr(common, "common_dir", lambda: main / ".git")
    monkeypatch.chdir(main)
    common.atomic_write(main / ".git/poolrad-control.json", '{"state":"running","reason":"test fixture"}\n')
    identity.register("dec-1", "decompiler", "test-harness", "test/model", "test-session")
    return main


# ----------------------------------------------------------------------------- planning
def test_plan_orders_by_address_and_skips_done_blocked_frontier_and_non_stubs(tmp_path):
    (tmp_path / "re").mkdir()
    (tmp_path / "src").mkdir()
    (tmp_path / "re/symbols.toml").write_text(registry([
        ("ovl05:0100", "Late", "none", ""),
        ("ovl05:0010", "Early", "none", "auto:entry"),
        ("ovl05:0200", "Done", "L2", ""),
        ("ovl05:0300", "Stuck", "none", "blocked (dec-1): tried X and Y"),
        ("ovl05:0400", "Exhausted", "none", ""),
        ("ovl05:0500", "Drafted", "none", ""),            # not a {@stub} any more: left to WRITE=1
        ("ovl05:0600", "Unblocked", "none", "the blocker is gone"),
        ("ovl05:0700", "ovl05_init", "none", ""),
    ]))
    (tmp_path / "src/OVL05.PAS").write_text(
        "unit OVL05;\ninterface\nimplementation\n"
        "{@stub} procedure Late; begin end;\n"
        "{@stub}procedure Early; begin end;\n"
        "procedure Done; begin end;\n"
        "{@stub} procedure Stuck; begin end;\n"
        "{@stub} function Exhausted: Byte; begin end;\n"
        "procedure Drafted; begin end;\n"
        "{@stub} procedure Unblocked; begin end;\n"
        "{@stub-init}\nbegin\nend.\n")
    frontier = {"ovl05:0400": {"attempts": 2}, "ovl05:0100": {"attempts": 1}}
    items = worker.plan(tmp_path, "ovl05", frontier, 2)
    assert [i.id for i in items] == ["ovl05:0010", "ovl05:0100", "ovl05:0600", "ovl05:0700"]
    assert items[-1].init and "initialisation" in items[-1].line()
    assert [i.id for i in worker.plan(tmp_path, "ovl05", frontier, 1)] == ["ovl05:0010", "ovl05:0600", "ovl05:0700"]
    assert [[i.id for i in b] for b in worker.batches(items, 3)] == [
        ["ovl05:0010", "ovl05:0100", "ovl05:0600"], ["ovl05:0700"]]
    # Without the marker the initialisation part is not an item; a decompiled init is not either.
    (tmp_path / "src/OVL05.PAS").write_text((tmp_path / "src/OVL05.PAS").read_text().replace("{@stub-init}\n", ""))
    assert [i.id for i in worker.plan(tmp_path, "ovl05", {}, 2)] == ["ovl05:0010", "ovl05:0100", "ovl05:0400", "ovl05:0600"]


# ----------------------------------------------------------------------------- frontier
def test_frontier_counts_attempts_and_releases_by_unit_or_routine(isolated_coordination):
    assert worker.load_frontier("ovl07") == {}
    assert worker.bump_frontier("ovl07", "ovl07:0010", "dec-1", "/log/a") == 1
    assert worker.bump_frontier("ovl07", "ovl07:0010", "dec-2", "/log/b") == 2
    assert worker.bump_frontier("ovl07", "ovl07:0020", "dec-1", "/log/a") == 1
    data = json.loads(worker.frontier_path("ovl07").read_text())
    assert data["ovl07:0010"]["attempts"] == 2 and data["ovl07:0010"]["agent"] == "dec-2"
    assert data["ovl07:0010"]["batch_log"] == "/log/b" and "last" in data["ovl07:0010"]
    assert worker.frontier_path("ovl07").parent == isolated_coordination / "poolrad-frontier"
    rows = worker.frontier_listing("ovl07")
    assert len(rows) == 2 and "attempts 2" in rows[0]
    assert worker.release_frontier("ovl07", "0010") == 1                      # by the offset part of the id
    assert set(worker.load_frontier("ovl07")) == {"ovl07:0020"}
    assert worker.release_frontier("ovl07") == 1
    assert not worker.frontier_path("ovl07").exists()
    assert worker.main(["--frontier"]) == 0 and worker.main(["--release", "ovl07"]) == 0


# ----------------------------------------------------------------------------- salvage and reset
def test_salvage_saves_every_uncommitted_change_then_leaves_the_tree_clean(tmp_path):
    wt = tmp_path / "wt"
    wt.mkdir()
    git_at(wt, "init", "-q", "-b", "main")
    (wt / "src").mkdir()
    (wt / "re").mkdir()
    (wt / "src/OVL00.PAS").write_text("unit OVL00;\n")
    (wt / "re/symbols.toml").write_text("")
    commit(wt)
    patch = tmp_path / "out/ovl00-batch1.patch"
    assert worker.salvage(wt, patch) is False and not patch.exists()
    (wt / "src/OVL00.PAS").write_text("unit OVL00;\n{ a draft that was never committed }\n")
    (wt / "src/NEW.PAS").write_text("unit NEW;\n")
    (wt / "re/learnings.toml").write_text("x = 1\n")
    assert worker.salvage(wt, patch) is True
    text = patch.read_text()
    assert "a draft that was never committed" in text and "untracked: src/NEW.PAS" in text and "unit NEW;" in text
    assert "re/learnings.toml" in text
    assert git_at(wt, "status", "--porcelain", "--untracked-files=all") == ""
    assert (wt / "src/OVL00.PAS").read_text() == "unit OVL00;\n"


def test_reset_batch_keeps_the_commits_as_patches(tmp_path):
    wt = tmp_path / "wt"
    wt.mkdir()
    git_at(wt, "init", "-q", "-b", "main")
    (wt / "a.txt").write_text("1\n")
    start = commit(wt)
    (wt / "a.txt").write_text("2\n")
    commit(wt, "ovl00: decompile Foo (ovl00:0000) [L2]")
    (wt / "a.txt").write_text("3\n")
    commit(wt, "ovl00: decompile Bar (ovl00:0040) [L2]")
    out = tmp_path / "commits"
    assert worker.reset_batch(wt, start, out) == 2
    assert git_at(wt, "rev-parse", "HEAD") == start and (wt / "a.txt").read_text() == "1\n"
    names = sorted(p.name for p in out.glob("*.patch"))
    assert len(names) == 2 and "decompile-Foo" in names[0] and "decompile-Bar" in names[1]


# ----------------------------------------------------------------------------- sessions
def test_run_session_runs_the_template_in_the_worktree_and_logs_it(tmp_path):
    wt = tmp_path / "wt"
    wt.mkdir()
    prompt = tmp_path / "p.md"
    prompt.write_text("hello batch")
    log = tmp_path / "logs/s.log"
    r = worker.run_session('cd {worktree} && echo "ok $(cat {prompt_file}) in $(pwd)"{model_flag}', prompt, wt, log,
                           timeout_s=20, model_flag="")
    assert r.returncode == 0 and not r.timed_out
    text = log.read_text()
    assert "ok hello batch in %s" % wt.resolve() in text and "$ exit 0" in text


def test_run_session_kills_the_whole_process_group_on_timeout(tmp_path):
    wt = tmp_path / "wt"
    wt.mkdir()
    prompt = tmp_path / "p.md"
    prompt.write_text("x")
    marker = tmp_path / "child.pid"
    log = tmp_path / "s.log"
    started = time.monotonic()
    r = worker.run_session("sh -c 'sleep 60 & echo $! > %s; wait'" % marker, prompt, wt, log, timeout_s=0.5)
    assert r.timed_out and time.monotonic() - started < worker.KILL_GRACE_SECONDS * 2 + 5
    assert "timed out, killed" in log.read_text()
    deadline = time.monotonic() + 5
    pid = int(marker.read_text().strip())
    while time.monotonic() < deadline:                 # the grandchild sleep died with its group
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            break
        time.sleep(0.1)
    else:
        os.kill(pid, 9)
        pytest.fail("the session's child process survived the kill")


def test_prompts_fill_the_templates_without_touching_pascal_braces(tmp_path):
    items = [worker.Item("ovl20:0000", "ovl20_fn_0000", 0), worker.Item("ovl20:0C9A", "ovl20_init", 0x10000, init=True)]
    text = worker.batch_prompt(tmp_path / "wt", "ovl20", "dec-7", items, 3)
    assert str(tmp_path / "wt") in text and "batch 3" in text and "unit/ovl20" in text
    assert "1. ovl20:0000 ovl20_fn_0000" in text and "2. ovl20:0C9A ovl20_init (initialisation part)" in text
    assert '--trailer "Agent: dec-7"' in text and "{@stub}" in text and "src/OVL20.PAS" in text
    review = worker.review_prompt(tmp_path / "wt", "ovl04", "rev-2")
    assert "work/reviews/ovl04.md" in review and "reviewer: rev-2" in review and "review/ovl04" in review


# ----------------------------------------------------------------------------- the owner release
def test_owner_release_removes_an_untouched_claim_and_refuses_everything_else(repo, monkeypatch):
    assert claim.main(["--agent", "dec-1", "--unit", "ovl00"]) == 0
    wt = repo.parent / "poolrad-worktrees/ovl00"
    assert wt.exists() and common.lock_path("ovl00").exists()
    assert unlock.main(["ovl00", "--agent", "dec-2", "--owner"]) == 2                    # not the holder
    assert unlock.main(["ovl00", "--agent", "dec-1", "--owner", "--force"]) == 2         # no flags mixed in
    (wt / "draft.txt").write_text("not committed")
    assert unlock.main(["ovl00", "--agent", "dec-1", "--owner"]) == 2                    # dirty worktree
    (wt / "draft.txt").unlink()
    pending = repo / ".git/poolrad-handoffs"
    pending.mkdir()
    (pending / "ovl00.md").write_text("unit = ovl00\nagent = dec-1\nbranch = unit/ovl00\n")
    assert unlock.main(["ovl00", "--agent", "dec-1", "--owner"]) == 2                    # hand-off pending
    (pending / "ovl00.md").unlink()
    assert common.lock_path("ovl00").exists()
    assert unlock.main(["ovl00", "--agent", "dec-1", "--owner"]) == 0
    assert not common.lock_path("ovl00").exists() and not wt.exists()
    assert not git_at(repo, "branch", "--list", "unit/ovl00")
    events = [json.loads(l) for l in (repo / ".git/poolrad-events.jsonl").read_text().splitlines()]
    last = [e for e in events if e["event"] == "unlock"][-1]
    assert last["owner_release"] is True and last["owner"] == "dec-1" and last["key"] == "ovl00"


def test_owner_release_refuses_a_branch_with_commits(repo):
    assert claim.main(["--agent", "dec-1", "--unit", "ovl00"]) == 0
    wt = repo.parent / "poolrad-worktrees/ovl00"
    (wt / "src/OVL00.PAS").write_text(SOURCE.replace("{@stub} procedure Foo", "procedure Foo"))
    commit(wt, "ovl00: decompile Foo")
    assert unlock.main(["ovl00", "--agent", "dec-1", "--owner"]) == 2
    assert common.lock_path("ovl00").exists() and wt.exists()
    assert unlock.main(["ovl00", "--agent", "orch"]) == 2                                  # unchanged rule: not merged


# ----------------------------------------------------------------------------- the supervisor loop
class FakeMake:
    """Stands in for `make` inside the worktree: `match` passes (or fails when told), `match WRITE=1`
    records L2 for every routine that is no longer a stub, `check` and `handoff` are recorded."""

    def __init__(self, match_rc=0):
        self.match_rc = match_rc
        self.calls = []

    def __call__(self, wt, args, log, env=None):
        self.calls.append(list(args))
        if args[0] == "match" and "WRITE=1" not in args:
            return self.match_rc
        if args[0] == "match":
            stubs = worker.stub_names((wt / "src/OVL00.PAS").read_text())
            text = (wt / "re/symbols.toml").read_text()
            blocks = text.split("[[routine]]")
            for k, b in enumerate(blocks[1:], 1):
                name = b.split('name = "')[1].split('"')[0]
                if name.lower() not in stubs:
                    blocks[k] = b.replace('level = "none"', 'level = "L2"')
            (wt / "re/symbols.toml").write_text("[[routine]]".join(blocks))
            return 0
        return 0


def session_script(tmp_path, body):
    script = tmp_path / "session.sh"
    script.write_text("#!/bin/sh\nset -e\ncd \"$1\"\n%s\n" % body)
    script.chmod(0o755)
    return "%s {worktree} {prompt_file}" % script


def test_worker_runs_batches_verifies_commits_and_hands_off(repo, monkeypatch, tmp_path):
    fake = FakeMake()
    monkeypatch.setattr(worker, "run_make", fake)
    # The session decompiles Foo and commits it; Bar is left untouched.
    cmd = session_script(tmp_path, "python3 -c \"import pathlib;p=pathlib.Path('src/OVL00.PAS');"
                                   "p.write_text(p.read_text().replace('{@stub} procedure Foo', 'procedure Foo'))\"\n"
                                   "git add -A && git -c user.name=s -c user.email=s@x commit -qm 'ovl00: decompile Foo (ovl00:0000) [L2]'\n"
                                   "echo 'ovl00:0000 Foo: matched' >> \"$2.out\"")
    cfg = worker.Config(agent="dec-1", role="decompiler", unit="ovl00", batch=6, session_cmd=cmd,
                        timeout_minutes=1, max_attempts=1, idle_seconds=0, sleep=lambda s: None)
    w = worker.Worker(cfg)
    assert w.run() == 0
    wt = repo.parent / "poolrad-worktrees/ovl00"
    log = git_at(wt, "log", "--format=%s", "main..unit/ovl00").splitlines()
    assert log == ["re: record L2 (worker)", "ovl00: decompile Foo (ovl00:0000) [L2]"]
    assert 'level = "L2"' in (wt / "re/symbols.toml").read_text().split("[[routine]]")[1]
    frontier = worker.load_frontier("ovl00")
    assert set(frontier) == {"ovl00:0040"} and frontier["ovl00:0040"]["attempts"] == 1
    assert frontier["ovl00:0040"]["batch_log"].endswith("ovl00-batch1.log")
    assert ["check"] in fake.calls
    hand = [c for c in fake.calls if c[0] == "handoff"][0]
    assert "STATE=partial" in hand and any(n.startswith("NOTE=worker: 1 matched this run, 0 blocked, 1 in frontier, check green") for n in hand)
    assert len([c for c in fake.calls if c == ["match", "UNIT=ovl00"]]) == 1          # one batch, one session
    beat = common.fields((repo / ".git/poolrad-heartbeats/dec-1.txt").read_text())
    assert beat["state"] == "stopped"
    logs = repo / "build/worker/dec-1"
    assert (logs / "ovl00-batch1.log").exists() and (logs / "ovl00-batch1.prompt.md").exists()
    assert "ovl00:0040 Bar" in (logs / "ovl00-batch1.prompt.md").read_text()
    assert common.lock_path("ovl00").exists()                                            # handed off, not released


def test_worker_resets_an_unmatched_batch_and_gives_back_an_untouched_claim(repo, monkeypatch, tmp_path):
    fake = FakeMake(match_rc=1)
    monkeypatch.setattr(worker, "run_make", fake)
    cmd = session_script(tmp_path, "echo '{ wrong }' >> src/OVL00.PAS\n"
                                   "git add -A && git -c user.name=s -c user.email=s@x commit -qm 'ovl00: decompile Foo (ovl00:0000) [L2]'\n"
                                   "echo scratch > src/SCRATCH.PAS")
    cfg = worker.Config(agent="dec-1", role="decompiler", unit="ovl00", batch=6, session_cmd=cmd,
                        timeout_minutes=1, max_attempts=1, idle_seconds=0, sleep=lambda s: None)
    assert worker.Worker(cfg).run() == 0
    wt = repo.parent / "poolrad-worktrees/ovl00"
    logs = repo / "build/worker/dec-1"
    assert "scratch" in (logs / "ovl00-batch1.patch").read_text()                         # the draft was saved
    assert list((logs / "ovl00-batch1-commits").glob("*.patch"))                          # the bad commit too
    assert not wt.exists() and not common.lock_path("ovl00").exists()                     # owner release
    assert not git_at(repo, "branch", "--list", "unit/ovl00")
    assert {k: v["attempts"] for k, v in worker.load_frontier("ovl00").items()} == {"ovl00:0000": 1, "ovl00:0040": 1}
    assert not [c for c in fake.calls if c[0] in ("check", "handoff")]


def test_worker_stops_when_control_is_not_running_and_hands_off_on_interrupt(repo, monkeypatch, tmp_path):
    common.atomic_write(repo / ".git/poolrad-control.json", '{"state":"paused","reason":"test"}\n')
    cfg = worker.Config(agent="dec-1", role="decompiler", unit="ovl00", session_cmd="true", idle_seconds=0,
                        sleep=lambda s: None)
    assert worker.Worker(cfg).run() == 0
    assert not common.lock_path("ovl00").exists()
    beat = common.fields((repo / ".git/poolrad-heartbeats/dec-1.txt").read_text())
    assert beat["state"] == "stopped" and "paused" in beat["note"]
    # A signal during a session: the session is killed, the claim ends in a release (nothing committed).
    common.atomic_write(repo / ".git/poolrad-control.json", '{"state":"running","reason":"test"}\n')
    fake = FakeMake()
    monkeypatch.setattr(worker, "run_make", fake)

    def interrupt(*args, **kwargs):
        raise worker.Interrupted("SIGTERM")
    monkeypatch.setattr(worker, "run_session", interrupt)
    cfg = worker.Config(agent="dec-1", role="decompiler", unit="ovl00", session_cmd="true", idle_seconds=0,
                        sleep=lambda s: None)
    assert worker.Worker(cfg).run() == 130
    assert not common.lock_path("ovl00").exists() and not (repo.parent / "poolrad-worktrees/ovl00").exists()
    beat = common.fields((repo / ".git/poolrad-heartbeats/dec-1.txt").read_text())
    assert beat["state"] == "stopped" and "SIGTERM" in beat["note"]


def test_reviewer_hands_off_passed_or_failed_from_the_committed_review(repo, monkeypatch, tmp_path):
    (repo / "re/symbols.toml").write_text(registry([("ovl00:0000", "Foo", "L2", ""), ("ovl00:0040", "Bar", "L2", "")]))
    (repo / "work/reviews").mkdir()
    (repo / "work/reviews/TEMPLATE.md").write_text("# Review\n")
    commit(repo, "ovl00 complete")
    identity.register("rev-1", "reviewer", "test-harness", "test/model", "test-session-2")
    fake = FakeMake()
    monkeypatch.setattr(worker, "run_make", fake)
    cmd = session_script(tmp_path, "mkdir -p work/reviews\n"
                                   "printf 'decompiler: dec-1\\nreviewer: rev-1\\n- [ ] must-fix Foo: wrong name at 0000\\n' > work/reviews/ovl00.md\n"
                                   "git add -A && git -c user.name=s -c user.email=s@x commit -qm 'review: ovl00'")
    cfg = worker.Config(agent="rev-1", role="reviewer", unit="ovl00", session_cmd=cmd, idle_seconds=0, sleep=lambda s: None)
    assert worker.Worker(cfg).run() == 0
    hand = [c for c in fake.calls if c[0] == "handoff"][0]
    assert "STATE=review-failed" in hand and any("must-fix Foo: wrong name" in n for n in hand)
    assert common.lock_path("review-ovl00").exists()
    # A passed review: no open must-fix, the stamp written by the (deterministic) review-pass step.
    common.lock_path("review-ovl00").unlink()
    git_at(repo, "worktree", "remove", "--force", str(repo.parent / "poolrad-worktrees/review-ovl00"))
    git_at(repo, "branch", "-D", "review/ovl00")
    fake.calls.clear()

    def stamp(wt, args, log, env=None):
        fake.calls.append(list(args))
        if args[0] == "review-pass" and "CHECK=1" not in args:
            p = wt / "re/symbols.toml"
            p.write_text(p.read_text().replace('level = "L2"', 'level = "L2"\nreview = "passed today by rev-1, abc"'))
        return 0
    monkeypatch.setattr(worker, "run_make", stamp)
    cmd = session_script(tmp_path, "mkdir -p work/reviews\n"
                                   "printf 'decompiler: dec-1\\nreviewer: rev-1\\n- [x] must-fix Foo: fixed\\n' > work/reviews/ovl00.md\n"
                                   "git add -A && git -c user.name=s -c user.email=s@x commit -qm 'review: ovl00'")
    cfg = worker.Config(agent="rev-1", role="reviewer", unit="ovl00", session_cmd=cmd, idle_seconds=0, sleep=lambda s: None)
    assert worker.Worker(cfg).run() == 0
    wt = repo.parent / "poolrad-worktrees/review-ovl00"
    assert "re: review ovl00 passed (worker)" in git_at(wt, "log", "--format=%s", "main..review/ovl00")
    hand = [c for c in fake.calls if c[0] == "handoff"][0]
    assert "STATE=review-passed" in hand
