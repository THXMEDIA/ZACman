#!/bin/bash
# Runs the Arena end-to-end test (godot/tests/arena_e2e.gd): a host and a
# client game instance race three rounds over ENet on localhost.
# Usage (repo root): tools/qa/arena_e2e.sh   (needs `godot` on PATH)
cd "$(dirname "$0")/../../godot" || exit 1
PORT=$((47950 + RANDOM % 40))
LOGDIR=$(mktemp -d)
VS_ROLE=host VS_PORT=$PORT timeout 600 godot --headless --path . --script res://tests/arena_e2e.gd > "$LOGDIR/host.log" 2>&1 &
HOST_PID=$!
VS_ROLE=client VS_PORT=$PORT timeout 600 godot --headless --path . --script res://tests/arena_e2e.gd > "$LOGDIR/client.log" 2>&1
CLIENT=$?
wait $HOST_PID
HOST=$?
grep -E "arena_e2e|FAIL|SCRIPT ERROR" "$LOGDIR/host.log" "$LOGDIR/client.log"
[ $HOST -eq 0 ] && [ $CLIENT -eq 0 ]
