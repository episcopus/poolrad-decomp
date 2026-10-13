#!/bin/sh
# open_session.sh <name>: run one roster session in this terminal tab (tools/agent/run.py start).
# Reads the model from build/run/<name>.json and the prompt from build/run/<name>.prompt.md, names the
# tab, records this process's pid for `make stop-run`, and replaces itself with the interactive
# OpenCode UI in the main checkout, with that prompt as its first message.
# OpenCode v2's top-level command rejects --model (it exits at once, and iTerm then closes the tab).
# `opencode mini` is the interactive UI that accepts --model and --prompt, and it must stay in the
# foreground: a backgrounded TUI is not the terminal's foreground process and cannot read the keyboard.
name="$1"
[ -n "$name" ] || { echo "usage: open_session.sh <session name>"; exit 2; }
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 2
meta="build/run/$name.json"
prompt="build/run/$name.prompt.md"
[ -f "$meta" ] && [ -f "$prompt" ] || { echo "no run files for $name (make start-run writes them)"; exit 2; }
model=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["model"])' "$meta")
printf '\033]1;%s\007' "$name"          # the tab title
printf '\033]2;%s (%s)\007' "$name" "$model"
echo "session $name: opencode mini --model $model (prompt: $prompt)"
# exec keeps this pid, so the file written here is the OpenCode process stop-run signals.
echo $$ > "build/run/$name.pid"
exec opencode mini --model "$model" --prompt "$(cat "$prompt")"
echo "session $name: opencode failed to start" >&2
exit 1
