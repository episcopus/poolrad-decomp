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
    text = run.START_AGENT.read_text()
    rows = run.roster()
    names = [r["name"] for r in rows]
    assert len(names) == len(set(names)) and rows[0]["role"] == "orchestrator"
    for r in rows:
        block = run.prompt_block(text, r["heading"])
        assert "Assigned role: `%s`" % r["role"] in block
        assert "Requested name: `%s`" % r["name"] in block
