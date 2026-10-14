"""The scripted integration loop (tools/agent/integrator.py) over disposable Git repositories.

No model and no real `make integrate` runs: the tools the loop calls are recorded, `make` is faked, and
a resolver "session" is a shell script, as in the worker tests.
"""
import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/agent"))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402
import integrate  # noqa: E402
import integrator  # noqa: E402
from test_worker import commit, git_at, isolated_coordination, repo, session_script  # noqa: E402,F401


class Recorder:
    """Stands in for Loop.tool (integrate.py, expert.py) and Loop.make."""

    def __init__(self, integrate_rc=0):
        self.tools, self.makes, self.integrate_rc = [], [], integrate_rc

    def tool(self, args, log=None):
        self.tools.append([Path(args[0]).name, *args[1:]])
        return (self.integrate_rc, "integrate: main is now abc (Merge)\n") if args[0].endswith("integrate.py") else (0, "[]")

    def make(self, wt, args, log):
        self.makes.append(list(args))
        return 0


def loop(monkeypatch, recorder, session_cmd="", model=""):
    lp = integrator.Loop("int-loop", 1, session_cmd, model, 1, sleep=lambda s: None)
    monkeypatch.setattr(lp, "tool", recorder.tool)
    monkeypatch.setattr(lp, "make", recorder.make)
    return lp


def diverge(repo, conflict: bool):
    """unit/ovl00 in its own worktree with one commit, main with another; a rejected hand-off record."""
    git_at(repo, "branch", "unit/ovl00")
    wt = repo.parent / "poolrad-worktrees/ovl00"
    git_at(repo, "worktree", "add", "-q", str(wt), "unit/ovl00")
    (wt / "src/OVL00.PAS").write_text((wt / "src/OVL00.PAS").read_text().replace("procedure Foo;", "procedure Foo; { branch }", 1))
    sha = commit(wt, "ovl00: branch work")
    if conflict:                                     # the same line as the branch
        (repo / "src/OVL00.PAS").write_text((repo / "src/OVL00.PAS").read_text().replace("procedure Foo;", "procedure Foo; { main }", 1))
    else:                                            # another file: git merges it cleanly
        (repo / "re/dseg.toml").write_text('[[global]]\noffset = "0000"\nname = "MainOnly"\n')
    commit(repo, "main moves on")
    d = integrate.handoff_dir()
    d.mkdir(exist_ok=True)
    (d / "ovl00.md").write_text("agent = dec-1\nstate = complete\nbranch = unit/ovl00\ncommit = %s\nintegrate = rejected\n"
                                "integrate_reason = %s\nintegrate_log = /tmp/x.log\n" % (
                                    sha, "merge conflict in src/OVL00.PAS"))
    return wt, sha


def test_a_pass_integrates_waiting_handoffs_and_nothing_else(repo, monkeypatch):
    rec = Recorder()
    lp = loop(monkeypatch, rec)
    monkeypatch.setattr(integrate, "pending", lambda key=None: [])
    assert "waiting 0, rejected 0" in lp.step() and rec.tools == []
    monkeypatch.setattr(integrate, "pending", lambda key=None: [Path("ovl00.md")])
    note = lp.step()
    assert rec.tools == [["integrate.py"]] and "integrated 1 of 1" in note


def test_a_clean_merge_of_main_is_resolved_without_a_model(repo, monkeypatch):
    wt, _sha = diverge(repo, conflict=False)
    rec = Recorder()
    note = loop(monkeypatch, rec).step()
    assert "ovl00 resolved (mechanical merge of main) and integrated" in note
    assert ["integrate.py", "--key", "ovl00"] in rec.tools and ["check"] in rec.makes
    assert subprocess.run(["git", "merge-base", "--is-ancestor", "main", "HEAD"], cwd=wt).returncode == 0
    assert "ovl00" not in integrator.load_state()


def test_a_conflict_goes_to_one_model_session_which_must_leave_a_clean_merge(repo, monkeypatch, tmp_path):
    wt, _sha = diverge(repo, conflict=True)
    rec = Recorder()
    resolve = session_script(tmp_path, "git merge main >/dev/null 2>&1 || true\n"
                                       "python3 -c \"import pathlib,re;p=pathlib.Path('src/OVL00.PAS');"
                                       "p.write_text(re.sub(r'<<<<<<< HEAD\\n(.*?)=======\\n.*?>>>>>>> main\\n', r'\\1', p.read_text(), flags=re.S))\"\n"
                                       "git add -A && git -c user.name=s -c user.email=s@x commit -q --no-edit")
    note = loop(monkeypatch, rec, resolve, "p/m#high").step()
    assert "ovl00 resolved (model session" in note and ["integrate.py", "--key", "ovl00"] in rec.tools
    assert "{ branch }" in (wt / "src/OVL00.PAS").read_text() and "<<<<<<<" not in (wt / "src/OVL00.PAS").read_text()
    prompt = (repo / "build/integrator/ovl00-resolve.prompt.md").read_text()
    assert "merge conflict in src/OVL00.PAS" in prompt and "unit/ovl00" in prompt


def test_a_session_that_fails_is_reset_and_attempts_are_bounded(repo, monkeypatch, tmp_path):
    wt, sha = diverge(repo, conflict=True)
    rec = Recorder()
    gives_up = session_script(tmp_path, "git merge main >/dev/null 2>&1 || true")     # leaves the conflict
    lp = loop(monkeypatch, rec, gives_up, "p/m#high")
    for attempt in (1, 2):
        note = lp.step()
        assert "could not be brought up to date with main (attempt %d" % attempt in note
        assert git_at(wt, "rev-parse", "HEAD") == sha and not git_at(wt, "status", "--porcelain")
    assert "left for the human (2 resolve attempts spent)" in lp.step()
    assert not any(t[:2] == ["integrate.py", "--key"] for t in rec.tools)


def test_lost_records_and_dirty_worktrees_are_never_touched(repo, monkeypatch):
    wt, sha = diverge(repo, conflict=False)
    rec = Recorder()
    lp = loop(monkeypatch, rec)
    (wt / "src/OVL00.PAS").write_text("{ a worker is still editing }\n")
    assert "uncommitted changes; not touched" in lp.step()
    assert (wt / "src/OVL00.PAS").read_text() == "{ a worker is still editing }\n"
    git_at(wt, "checkout", "--", ".")
    record = integrate.handoff_dir() / "ovl00.md"
    record.write_text(record.read_text().replace("merge conflict in src/OVL00.PAS", "make merge-check STAGED=1 found lost records"))
    assert "ovl00 left for the human (make merge-check" in lp.step()
    assert git_at(wt, "rev-parse", "HEAD") == sha


def test_the_loop_runs_until_control_is_stopped_and_heartbeats(repo, monkeypatch):
    rec = Recorder()
    lp = loop(monkeypatch, rec)
    monkeypatch.setattr(integrate, "pending", lambda key=None: [])

    def stop_after_one_wait(seconds):
        common.atomic_write(repo / ".git/poolrad-control.json", '{"state":"stopped","reason":"test"}\n')

    lp.sleep = stop_after_one_wait
    assert lp.run() == 0
    beat = common.fields((repo / ".git/poolrad-heartbeats/int-loop.txt").read_text())
    assert beat["state"] == "stopped"


def test_the_loop_never_takes_make_integrates_own_name():
    with pytest.raises(ValueError, match="its own name"):
        integrator.Loop("integrator", 1, "", "", 1)


def test_expert_scan_only_with_a_budget_for_this_run(repo, monkeypatch):
    rec = Recorder()
    lp = loop(monkeypatch, rec)
    assert lp.expert_scan() == "" and rec.tools == []
    policy = repo / ".git/poolrad-expert"
    policy.mkdir()
    (policy / "policy.json").write_text(json.dumps({"run_id": "another-run", "frozen": None}))
    assert lp.expert_scan() == "" and rec.tools == []


def test_only_one_make_integrate_runs_at_a_time(repo, capsys):
    held = integrate.exclusive()
    assert held is not None
    assert integrate.exclusive() is None                 # the loop, an orchestrator or the human: one at a time
    assert integrate.main([]) == 3 and "another make integrate is running" in capsys.readouterr().out
    held.close()
    again = integrate.exclusive()
    assert again is not None
    again.close()


def test_the_run_stops_itself_after_an_hour_without_planned_work(repo, monkeypatch):
    """2026-10-14: the workers ran out at 02:13 and the run idled until the human stopped it at 06:27."""
    import heartbeat
    rec = Recorder()
    now = [0.0]
    lp = integrator.Loop("int-loop", 1, "", "", 1, sleep=lambda s: None, idle_stop_minutes=60, clock=lambda: now[0])
    monkeypatch.setattr(lp, "tool", rec.tool)
    stops = []
    monkeypatch.setattr(lp, "auto_stop", lambda idle: stops.append(idle))
    monkeypatch.setattr(integrate, "pending", lambda key=None: [])
    heartbeat.beat("dec-9", "idle: nothing to claim, looking again in 300 s")
    heartbeat.beat("rev-9", "unit ovl00 batch 2: routines Foo")          # still working
    assert "no planned work" not in lp.step() and lp.idle_since is None
    heartbeat.beat("rev-9", "idle: nothing to claim, looking again in 300 s")
    assert "no planned work for 0 of 60 minutes" in lp.step()
    now[0] = 59 * 60
    lp.step()
    assert stops == []
    (common.lock_dir() / "ovl00.lock").write_text("agent = dec-9\n")      # work again: the clock restarts
    lp.step()
    assert lp.idle_since is None
    (common.lock_dir() / "ovl00.lock").unlink()
    lp.step()
    now[0] += 61 * 60
    assert "make stop-run started" in lp.step() and len(stops) == 1


def test_auto_stop_can_be_turned_off(repo, monkeypatch):
    lp = integrator.Loop("int-loop", 1, "", "", 1, sleep=lambda s: None, idle_stop_minutes=0)
    assert lp.watch_idle() == ""
