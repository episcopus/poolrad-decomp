"""make start-run / stop-run: the roster and the prompt blocks of START-AGENT.md."""
import re
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/agent"))

import run  # noqa: E402

TEXT = """# Starting one agent

## The prompt for decompiler mimo

````markdown
You are a worker.
Assigned role: `decompiler`
```sh
echo hi
```
````

## The prompt for reviewer sonnet

````markdown
You are a reviewer.
````
"""


def test_prompt_blocks_are_cut_by_heading():
    assert run.prompt_block(TEXT, "decompiler mimo") == "You are a worker.\nAssigned role: `decompiler`\n```sh\necho hi\n```\n"
    assert run.prompt_block(TEXT, "reviewer sonnet") == "You are a reviewer.\n"
    with pytest.raises(ValueError):
        run.prompt_block(TEXT, "expert opus")


def test_open_session_keeps_the_v2_tui_in_the_foreground():
    """The top-level `opencode` command rejects --model and exits, which closes the iTerm tab."""
    text = (ROOT / "tools/agent/open_session.sh").read_text()
    assert 'exec opencode mini --model "$model" --prompt "$(cat "$prompt")"' in text
    assert re.search(r"^opencode\b.*&", text, re.M) is None


def test_a_variant_is_passed_as_a_model_suffix():
    assert run.model_spec({"model": "openrouter/anthropic/claude-haiku-5.5", "variant": "high"}) == \
        "openrouter/anthropic/claude-haiku-5.5#high"
    with pytest.raises(ValueError):
        run.check_session({"name": "dec-1", "role": "decompiler", "model": "a/b", "heading": "x"})
    with pytest.raises(ValueError):
        run.check_session({"name": "dec-1", "role": "decompiler", "model": "a/b#high",
                            "variant": "high", "heading": "x"})


def test_the_real_roster_resolves_every_prompt_block():
    """Interactive sessions need their START-AGENT block; worker and script sessions need none."""
    text = run.START_AGENT.read_text()
    rows = run.roster()
    names = [r["name"] for r in rows]
    assert len(names) == len(set(names))
    for r in rows:
        if run.mode_of(r) != "interactive":
            continue
        block = run.prompt_block(text, r["heading"])
        assert "Assigned role: `%s`" % r["role"] in block
        assert "Requested name: `%s`" % r["name"] in block
        assert run.model_spec(r) == "%s#%s" % (r["model"], r["variant"])


def test_decompilers_and_reviewers_run_as_workers_by_default():
    """2026-10-13: every interactive decompiler and reviewer stopped on its own while work remained."""
    assert run.mode_of({"role": "decompiler"}) == "worker"
    assert run.mode_of({"role": "reviewer"}) == "worker"
    assert run.mode_of({"role": "orchestrator"}) == "interactive"
    assert run.mode_of({"role": "expert"}) == "interactive"
    assert run.mode_of({"role": "decompiler", "mode": "interactive"}) == "interactive"


def write_roster(tmp_path, monkeypatch, body):
    path = tmp_path / "roster.toml"
    path.write_text(body)
    monkeypatch.setattr(run, "ROSTER", path)
    return run.roster()


def test_roster_validation(tmp_path, monkeypatch):
    rows = write_roster(tmp_path, monkeypatch, '[[session]]\nname = "dec-a"\nrole = "decompiler"\nmodel = "p/m"\nvariant = "high"\n')
    assert rows[0]["name"] == "dec-a"                  # a worker needs no heading
    with pytest.raises(ValueError, match="heading"):
        write_roster(tmp_path, monkeypatch, '[[session]]\nname = "orch"\nrole = "orchestrator"\nmodel = "p/m"\nvariant = "high"\n')
    with pytest.raises(ValueError, match="only decompilers and reviewers"):
        write_roster(tmp_path, monkeypatch,
                     '[[session]]\nname = "x"\nrole = "expert"\nmodel = "p/m"\nvariant = "high"\nmode = "worker"\nheading = "h"\n')
    with pytest.raises(ValueError, match="positive"):
        write_roster(tmp_path, monkeypatch, '[[session]]\nname = "d"\nrole = "decompiler"\nmodel = "p/m"\nvariant = "high"\nbatch = 0\n')


def test_worker_argv_carries_identity_model_and_options():
    argv = run.worker_argv({"name": "dec-a", "role": "decompiler", "model": "openrouter/x/y", "variant": "max",
                            "batch": 4, "timeout": 60}, "d8bd82ffe0844e16")
    assert argv[:8] == ["--agent", "dec-a", "--role", "decompiler", "--harness", "opencode", "--model", "openrouter/x/y"]
    assert argv[argv.index("--session") + 1] == "dec-a-run-d8bd82ff"
    assert argv[argv.index("--session-model") + 1] == "openrouter/x/y#max"
    assert argv[argv.index("--variant") + 1] == "max"
    assert argv[argv.index("--batch") + 1] == "4" and argv[argv.index("--timeout") + 1] == "60"


def test_open_session_hands_a_worker_to_the_supervisor():
    text = (ROOT / "tools/agent/open_session.sh").read_text()
    assert 'exec .venv/bin/python tools/agent/run.py session "$name"' in text
    assert text.index("run.py session") < text.index("exec opencode mini")


def test_stop_signals_workers_before_integrating():
    """A worker hands off on SIGTERM; its hand-off must land in stop-run's integration."""
    import inspect
    src = inspect.getsource(run.stop)
    assert src.index("signal_sessions(names, signal.SIGTERM)") < src.index('["make", "integrate"]')


def test_the_integrator_runs_as_a_script_with_its_resolver_model():
    """2026-10-14: the interactive orchestrator ended its turn and hand-offs waited an hour."""
    assert run.mode_of({"role": "integrator"}) == "script"
    row = {"name": "int-loop", "role": "integrator", "model": "p/m", "variant": "high", "interval": 60}
    run.check_session(row)                                   # no heading needed
    argv = run.argv_of(row, "5c2d26e1abcd")
    assert argv[:2] == ["--agent", "int-loop"] and argv[argv.index("--session-model") + 1] == "p/m#high"
    assert argv[argv.index("--interval") + 1] == "60" and "--role" not in argv
    with pytest.raises(ValueError, match="only it, runs as a script"):
        run.check_session({**row, "role": "orchestrator", "mode": "script"})
    text = (ROOT / "tools/agent/open_session.sh").read_text()
    assert '[ "$mode" = script ]' in text


def test_run_add_refuses_a_session_that_is_still_running(tmp_path, monkeypatch):
    monkeypatch.setattr(run.control, "state", lambda: {"state": "running", "run_id": "r1"})
    path = tmp_path / "roster.toml"
    path.write_text('[[session]]\nname = "int-loop"\nrole = "integrator"\nmodel = "p/m"\nvariant = "high"\n')
    monkeypatch.setattr(run, "ROSTER", path)
    monkeypatch.setattr(run, "pid_of", lambda name: 4242)
    monkeypatch.setattr(run, "alive", lambda pid: True)
    with pytest.raises(ValueError, match="already running"):
        run.add("int-loop")
    with pytest.raises(ValueError, match="not in work/roster.toml"):
        run.add("nobody")
    monkeypatch.setattr(run.control, "state", lambda: {"state": "stopped"})
    with pytest.raises(ValueError, match="running run"):
        run.add("int-loop")


def test_the_roster_has_an_integrator_and_an_escalation_tier():
    """The run needs its integration loop and someone for the routines tier 1 gives up on."""
    rows = run.roster()
    assert [r["name"] for r in rows if run.mode_of(r) == "script"] == ["int-loop"]
    tier2 = [r for r in rows if r.get("tier") == 2]
    assert tier2 and all(run.mode_of(r) == "worker" and r.get("cost_cap") for r in tier2)
    argv = run.argv_of(tier2[0], "abc12345")
    assert argv[argv.index("--tier") + 1] == "2" and argv[argv.index("--cost-cap") + 1] == str(tier2[0]["cost_cap"])


def test_a_worker_can_be_pinned_to_one_unit():
    row = {"name": "esc-ab", "role": "decompiler", "tier": 2, "model": "p/m", "variant": "xhigh", "unit": "ovl16"}
    run.check_session(row)
    argv = run.argv_of(row, "r1")
    assert argv[argv.index("--unit") + 1] == "ovl16" and argv[argv.index("--tier") + 1] == "2"
    with pytest.raises(ValueError, match="unit pins a worker"):
        run.check_session({"name": "int", "role": "integrator", "model": "p/m", "variant": "high", "unit": "ovl16"})
