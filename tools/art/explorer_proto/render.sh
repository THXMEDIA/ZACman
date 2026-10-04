#!/bin/bash
# render.sh <richtung> [ansichten]
# Kopiert das Prototyp-Projekt der Richtung samt common/ in den Scratchpad und rendert die
# Ansichten unter xvfb mit dem Compatibility-Renderer (Software-GL). Ergebnis: $OUT/<richtung>/*.png
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
B=${SCRATCH:-/tmp/claude-0/-home-claude/1aaa4092-a4a3-5e5c-b391-8d187e585776/scratchpad}
GODOT=${GODOT:-$B/bin/godot}
OUT=${OUT:-$B/explorer_shots}
P=$B/explorer_proto/$1
D="$OUT/$1${VARIANT:+/$VARIANT}"   # J v2: VARIANT=atelier|abend|studio|nacht -> Unterordner
mkdir -p "$P" "$D"
# Richtungen E-G: gedruckte/gemalte Texturen werden per Pillow-Skript erzeugt (nicht im Repo)
[ -f "$HERE/$1/prints.py" ] && python3 "$HERE/$1/prints.py" >/dev/null
cp -r "$HERE/$1"/* "$P"/
cp "$HERE"/common/*.gd "$P"/
cd "$P"
SHOT_DIR="$D" SHOT_NAME="$1" SHOT_ONLY="$2" timeout 600 xvfb-run -a -s "-screen 0 1280x720x24" \
  "$GODOT" --rendering-driver opengl3 --path "$P" --resolution 1280x720 --script res://shot.gd 2>&1 \
  | grep -vE "^\s*$|Godot Engine|OpenGL API|^WARNING: (Blend|.*XDG)" | head -60
