#!/bin/bash
# render.sh <richtung> [ansichten]
B=/tmp/claude-0/-home-claude/1aaa4092-a4a3-5e5c-b391-8d187e585776/scratchpad
P=$B/tokyo_proto/$1
cp $B/tokyo_proto/common/city.gd $B/tokyo_proto/common/shot.gd $P/
cd $P
SHOT_DIR=$B/tokyo_shots SHOT_NAME=$1 SHOT_ONLY="$2" timeout 300 xvfb-run -a -s "-screen 0 1280x720x24" $B/bin/godot --rendering-driver opengl3 --path $P --resolution 1280x720 --script res://shot.gd 2>&1 | grep -vE "^\s*$|Godot Engine|OpenGL API" | head -40
