# Review-Brief: ZACman (Kugelschlucker)

Gilt für alle drei Reviewer (`game-designer`, `ux-reviewer`, `code-reviewer`).
Rollenspezifische Zusätze stehen in `docs/review/<rollenname>.md`.
Anweisungen für ein einzelnes Review kommen direkt in den Auftrag und haben Vorrang.

> Vorausgefüllt aus README und `docs/STEAM_ROADMAP.md`. Mit ❓ markierte Punkte bitte ergänzen.

## Das Spiel
- Pitch: First-Person-3D-Labyrinthspiel im Geiste von Pac-Man: durch prozedural erzeugte Labyrinthe laufen, Kugeln schlucken, Power-Kugeln nutzen, leuchtenden Wesen ausweichen. Eigene Optik (Matrix-ASCII-Wände, Voxel-Wolken, Wort-Welt), komplett synthetische Sounds.
- Genre und Referenzspiele: First-Person-Arcade/Maze, Speedrun-tauglich ❓ Referenzspiele ergänzen
- Zielgruppe: ❓ (Retro-Fans, Speedrunner, Streamer/Twitch-Zuschauer?)
- Plattformen: Steam (Windows, Linux, macOS). `web/index.html` ist nur noch ein Browser-Prototyp und wird nicht weiterentwickelt.
- Engine: Godot 4.3 (GDScript), aktiver Stand in `godot/`
- Monetarisierung: ❓ (Kaufpreis? Achievements und Cloud-Saves über GodotSteam geplant)

## Designziele
- Gefühl: ❓
- Core Loop: Labyrinth erkunden → Kugeln sammeln → Power-Kugel nutzen, Geister fressen → Level leer → nächstes, neu generiertes Level. Dazu Speedrun-Timer mit Bestzeiten pro Level.
- Modi: Matrix-Level (klassisch, Speedrun), Explorer-Level Manhattan (ruhig, ohne Geister, echte Gebäudenamen und -höhen, Fahrzeuge und Fußgänger als Hindernisse), Testbuild-Modus mit Debug-Chip.
- Besondere Systeme: Word-Mode-Power-up (12 s Wort-Welt-Look plus Noclip), Twitch-Chat opt-in (`!power`, `!fruit`, nur unterstützend, nie störend).
- Darf nicht passieren:
  - Twitch-Effekte dürfen ernsthafte Speedruns nicht verfälschen oder die Eingabe blockieren
  - Rechtlich zu nah am Original (eigener Name, eigene Labyrinthe, eigene Optik, keine Original-Assets)
  - Übelkeit/Orientierungsverlust in First-Person-Labyrinthen ohne Gegenmittel (FOV, Minimap, Bewegungsoptionen)

## Aktueller Stand
- Phase: spielbarer Prototyp in Godot, auf dem Weg zum Steam-Build
- Bekannte Baustellen, die Reviewer nicht erneut melden sollen (siehe `docs/STEAM_ROADMAP.md`):
  - Steamworks-Integration (GodotSteam) noch nicht eingebaut
  - Multiplayer (Koop/Kompetitiv) ist geplant, nicht begonnen
  - Export-Presets sind nicht versioniert (maschinenspezifisch)
  - Markenrechtliche Prüfung vor Veröffentlichung steht aus
  - ❓ weitere

## Schwerpunkte für Reviews
- Worauf besonders achten: Spielgefühl und Lesbarkeit in First-Person (Orientierung, Minimap, Geister erkennen), Schwierigkeitskurve der generierten Labyrinthe, Speedrun-Fairness (Determinismus, Timer), Performance der Shader und MultiMeshes, Testabdeckung der Headless-Tests ❓
- Was bewusst ignorieren: `web/` und `core/` (eingefrorener Prototyp), außer der Auftrag nennt sie ❓

## Technische Rahmen
- Mindestgeräte und Performance-Ziel: ❓
- Backend und Dienste: keine; Twitch über anonymen IRC-Listener ohne Credentials
- Code-Konventionen: Szenen werden zur Laufzeit aus Code gebaut (`Main.tscn` ist die einzige Szene); Labyrinth-Generator deterministisch über Seed; Headless-Tests in `godot/tests/` (`npm run test:godot`) müssen grün bleiben, inklusive Bot-Simulation `BotTest.tscn` ❓ weitere
