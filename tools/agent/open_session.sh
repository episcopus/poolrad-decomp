#!/bin/sh
# open_session.sh <name>: run one roster session in this terminal tab (tools/agent/run.py start).
# Reads the model from build/run/<name>.json and the prompt from build/run/<name>.prompt.md, names the
# tab, records the OpenCode pid for `make stop-run`, and starts the interactive OpenCode TUI in the
# main checkout with that prompt as its first message.
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
echo "session $name: opencode --model $model (prompt: $prompt)"
opencode --model "$model" --prompt "$(cat "$prompt")" "$root" &
echo $! > "build/run/$name.pid"
wait $!
echo "session $name ended; make stop-run or make run-status in the main checkout"
