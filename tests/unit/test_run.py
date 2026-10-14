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


def test_the_real_roster_resolves_every_prompt_block():
    """Interactive sessions need their START-AGENT block; worker sessions need none."""
    text = run.START_AGENT.read_text()
    rows = run.roster()
    names = [r["name"] for r in rows]
    assert len(names) == len(set(names)) and rows[0]["role"] == "orchestrator"
    for r in rows:
        if run.mode_of(r) == "worker":
            continue
        block = run.prompt_block(text, r["heading"])
        assert "Assigned role: `%s`" % r["role"] in block
        assert "Requested name: `%s`" % r["name"] in block


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
    rows = write_roster(tmp_path, monkeypatch, '[[session]]\nname = "dec-a"\nrole = "decompiler"\nmodel = "p/m"\n')
    assert rows[0]["name"] == "dec-a"                  # a worker needs no heading
    with pytest.raises(ValueError, match="heading"):
        write_roster(tmp_path, monkeypatch, '[[session]]\nname = "orch"\nrole = "orchestrator"\nmodel = "p/m"\n')
    with pytest.raises(ValueError, match="only decompilers and reviewers"):
        write_roster(tmp_path, monkeypatch,
                     '[[session]]\nname = "x"\nrole = "expert"\nmodel = "p/m"\nmode = "worker"\nheading = "h"\n')
    with pytest.raises(ValueError, match="positive"):
        write_roster(tmp_path, monkeypatch, '[[session]]\nname = "d"\nrole = "decompiler"\nmodel = "p/m"\nbatch = 0\n')


def test_worker_argv_carries_identity_model_and_options():
    argv = run.worker_argv({"name": "dec-a", "role": "decompiler", "model": "openrouter/x/y", "variant": "max",
                            "batch": 4, "timeout": 60}, "d8bd82ffe0844e16")
    assert argv[:8] == ["--agent", "dec-a", "--role", "decompiler", "--harness", "opencode", "--model", "openrouter/x/y"]
    assert argv[argv.index("--session") + 1] == "dec-a-run-d8bd82ff"
    assert argv[argv.index("--session-model") + 1] == "openrouter/x/y#max"
    assert argv[argv.index("--variant") + 1] == "max"
    assert argv[argv.index("--batch") + 1] == "4" and argv[argv.index("--timeout") + 1] == "60"
    plain = run.worker_argv({"name": "rev-a", "role": "reviewer", "model": "p/m"}, "")
    assert "--variant" not in plain and plain[plain.index("--session-model") + 1] == "p/m"


def test_open_session_hands_a_worker_to_the_supervisor():
    text = (ROOT / "tools/agent/open_session.sh").read_text()
    assert 'exec .venv/bin/python tools/agent/run.py session "$name"' in text
    assert text.index("run.py session") < text.index("exec opencode mini")


def test_stop_signals_workers_before_integrating():
    """A worker hands off on SIGTERM; its hand-off must land in stop-run's integration."""
    import inspect
    src = inspect.getsource(run.stop)
    assert src.index("signal_sessions(names, signal.SIGTERM)") < src.index('["make", "integrate"]')
