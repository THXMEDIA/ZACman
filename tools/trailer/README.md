# Trailer-Pitch (intern)

Werkzeuge für den internen Trailer-Pitch v2 von ZAPmaniac (nicht zur Veröffentlichung). Spielcode wird nicht verändert.

1. `trailer_capture.gd` – nimmt die Szenen als PNG-Folgen auf (Aufruf im Skriptkopf). Cloud: ca. 25 min für 1.815 Frames in 1080p (Software-Rendering). Auf dem eigenen PC mit Forward+ ohne `xvfb-run`/`--rendering-driver` für SSR und Glow.
2. `music.py` – prozedurale Temp-Musik (80 s, 120 BPM), keine fremden Samples.
3. `compose.py` – Schnitt, Texttafeln, Timer, Chat, Bestenliste, Glitches, Wasserzeichen → MP4.

Namen auf der Bestenliste über `TRAILER_NAMES` (6 Namen, Komma-getrennt); ohne Angabe neutrale Platzhalter. Echte Personen nur intern und nie ohne Zustimmung veröffentlichen. Beat-Sheet: `studio/projekte/zapmaniac/trailer-pitch-v1.md` (BeachVibeStudio-Project).
