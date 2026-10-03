# QA-Playtester: Zusätze für ZAPmaniac

- Godot 4.3 (siehe `godot/project.godot`). Binärdatei: `https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip`
- Vor den Tests einmal `godot --headless --path godot --import`.
- Tests: alle `godot/tests/test_*.gd` einzeln mit `--script`, dazu die Bot-Simulation `res://tests/BotTest.tscn` (Stand 02.10.2026: 13 Testskripte + 162 Simulations-Checks grün).
- Screenshots: `tools/qa/qa_screenshots.gd` (Startmenü, Matrix-Level, Pause, Manhattan); Aufruf im Dateikopf.
- Bekannte Headless-Artefakte, nicht als Bug melden: „All audio drivers failed“/ALSA-Fehler, RID-/ObjectDB-Leaks beim Beenden von Test-Skripten, `Parameter "m" is null` aus dem Dummy-Renderer.
- Erste Beobachtungen (02.10.2026, zu bestätigen): HUD-Chips (Punkte, Level, Zeit, Bestzeit, Leben) sind hinter dem Startmenü sichtbar; Texte nutzen teils „ue“ statt „ü“ („fuer“).
- Steam Deck und Controller sind kein Ziel (siehe Brief).
