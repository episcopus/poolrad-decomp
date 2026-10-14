#!/bin/sh
# open_session.sh <name>: run one roster session in this terminal tab (tools/agent/run.py start).
# Reads the settings from build/run/<name>.json, names the tab and records this process's pid for
# `make stop-run`, then replaces itself with the session:
#  - a worker-mode session (decompilers and reviewers by default) becomes `run.py session <name>`, the
#    supervisor of docs/process/WORKER.md, which starts one fresh `opencode run` per batch;
#  - an interactive session becomes the OpenCode UI in the main checkout, with the prompt of
#    build/run/<name>.prompt.md as its first message.
# OpenCode v2's top-level command rejects --model (it exits at once, and iTerm then closes the tab).
# `opencode mini` is the interactive UI that accepts --model and --prompt, and it must stay in the
# foreground: a backgrounded TUI is not the terminal's foreground process and cannot read the keyboard.
name="$1"
[ -n "$name" ] || { echo "usage: open_session.sh <session name>"; exit 2; }
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 2
meta="build/run/$name.json"
prompt="build/run/$name.prompt.md"
[ -f "$meta" ] || { echo "no run files for $name (make start-run writes them)"; exit 2; }
model=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["model"])' "$meta")
mode=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("mode", "interactive"))' "$meta")
printf '\033]1;%s\007' "$name"          # the tab title
printf '\033]2;%s (%s, %s)\007' "$name" "$model" "$mode"
# exec keeps this pid, so the file written here is the process stop-run signals.
echo $$ > "build/run/$name.pid"
if [ "$mode" = worker ]; then
  echo "session $name: worker supervisor, sessions with $model (log: build/run/$name.log)"
  exec .venv/bin/python tools/agent/run.py session "$name"
fi
[ -f "$prompt" ] || { echo "no prompt file for $name (make start-run writes it)"; exit 2; }
echo "session $name: opencode mini --model $model (prompt: $prompt)"
exec opencode mini --model "$model" --prompt "$(cat "$prompt")"
echo "session $name: opencode failed to start" >&2
exit 1
