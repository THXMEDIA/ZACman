# QA-Playtester: Zusätze für ZACman

- Godot 4.3 (siehe `godot/project.godot`). Binärdatei: `https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip`
- Vor den Tests einmal `godot --headless --path godot --import`.
- Tests: alle `godot/tests/test_*.gd` einzeln mit `--script`, dazu die Bot-Simulation `res://tests/BotTest.tscn` (Stand 03.10.2026, Etappe 3: 15 Testskripte + 303 Simulations-Checks grün; Reihenfolge wie `npm run test:godot`).
- Screenshots (Aufruf jeweils im Dateikopf; Skript nach `godot/` kopieren, unter `xvfb-run` mit `--rendering-driver opengl3` starten, `SHOT_DIR` setzen):
  - `tools/qa/qa_screenshots.gd`: Startmenü, Speedrun-Level, Pause, Manhattan.
  - `tools/qa/qa_kaninchen_shots.gd`: Start-Einblendung, Kaninchen, Titelkarte, alle Konditions-Looks (Etappe 2).
  - `tools/qa/qa_etappe3_shots.gd`: Startscreen mit Chaos-Schalter, HUD mit Chaos-Badge, Chat-Balken, Titelkarte mit Chat-Anteil, Bestenliste mit Wochenangabe (Etappe 3). Nutzt einen eigenen Speicherordner und füllt die Bretter mit Beispielzeiten.
- Bekannte Headless-Artefakte, nicht als Bug melden: „All audio drivers failed“/ALSA-Fehler, RID-/ObjectDB-Leaks beim Beenden von Test-Skripten, `Parameter "m" is null` aus dem Dummy-Renderer.
- Twitch ist im Test ohne Netz: Chat-Befehle über `Twitch.chat_command.emit(user, befehl, "")` einspeisen und `Twitch.enabled = true` setzen (siehe `_run_chat_vote_checks` in `bot_test.gd`).
- Erste Beobachtungen (02.10.2026, zu bestätigen): HUD-Chips (Punkte, Level, Zeit, Bestzeit, Leben) sind hinter dem Startmenü sichtbar.
- Steam Deck und Controller sind kein Ziel (siehe Brief).
