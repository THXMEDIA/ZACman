#!/bin/bash
# Arles v2: alle Bilder fuer docs/art/vorschlaege/explorer/arles_v2/ erzeugen (Software-Renderer, ~4 min).
# Aufruf: arles_v2/render_all.sh [zielordner]
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
B=${SCRATCH:-/tmp/claude-0/-home-claude/1aaa4092-a4a3-5e5c-b391-8d187e585776/scratchpad}
DST=${1:-$HERE/../../../docs/art/vorschlaege/explorer/arles_v2}
T=$B/arles_v2_render
rm -rf "$T"; mkdir -p "$T" "$DST"
python3 "$HERE/arles_v2/karte.py" "$T" > "$T/karte_pruefung.txt"
W=${SHOT_WAIT:-10}
# Hauptlook "tiefe Nacht" (+ gebackene Himmelstextur speichern)
SKY_SAVE="$T/himmel_bake.png" OUT=$T/nacht SHOT_WAIT=$W "$HERE/render.sh" arles_v2 | grep SHOT
# Effekte reduziert: Himmel steht, Puls aus, ruhigerer Pinsel, Wasser steht
REDUCE_FX=1 OUT=$T/reduziert SHOT_WAIT=$W "$HERE/render.sh" arles_v2 strasse | grep SHOT
# Variante "blaue Stunde"
VARIANT=blau OUT=$T/blau SHOT_WAIT=$W "$HERE/render.sh" arles_v2 strasse,totale,forum,arenes,kai,ausgang,capsule | grep SHOT
# Strich-LOD-Pruefung: zwei Frames im Abstand eines Lauf-Frames (4,4 m/s bei 60 fps = 7 cm), LOD an/aus
for L in 1 0; do
  for z in 63.00 62.93; do
    LOD=$L VIEW="lod${L}_z${z},27.0,1.7,${z},27.0,3.6,28.0,72" OUT=$T/lod SHOT_WAIT=$W "$HERE/render.sh" arles_v2 | grep SHOT
  done
done
python3 "$HERE/arles_v2/auswertung.py" "$T" "$DST"
