# Review-Brief: ZACman (Kugelschlucker)

Gilt für alle drei Reviewer (`game-designer`, `ux-reviewer`, `code-reviewer`).
Rollenspezifische Zusätze stehen in `docs/review/<rollenname>.md`.
Anweisungen für ein einzelnes Review kommen direkt in den Auftrag und haben Vorrang.

> Vorausgefüllt aus README und `docs/STEAM_ROADMAP.md`. Mit ❓ markierte Punkte bitte ergänzen.

## Das Spiel
- Pitch: First-Person-3D-Labyrinthspiel im Geiste von Pac-Man: durch prozedural erzeugte Labyrinthe laufen, Kugeln schlucken, Power-Kugeln nutzen, leuchtenden Wesen ausweichen. Eigene Optik (Matrix-ASCII-Wände, Voxel-Wolken, Wort-Welt), komplett synthetische Sounds.
- Genre und Referenzspiele: First-Person-Arcade/Maze, Speedrun-tauglich ❓ Referenzspiele ergänzen
- Zielgruppe: ❓ (Retro-Fans, Speedrunner, Streamer/Twitch-Zuschauer?)
- Plattformen: Steam (Windows, Linux, macOS). Steam Deck und Controller sind kein Ziel. `web/index.html` ist nur noch ein Browser-Prototyp und wird nicht weiterentwickelt.
- Engine: Godot 4.3 (GDScript), aktiver Stand in `godot/`
- Monetarisierung: ❓ (Kaufpreis? Achievements und Cloud-Saves über GodotSteam geplant)

## Designziele
- Gefühl: ❓
- Core Loop: Labyrinth erkunden → Kugeln sammeln → Power-Kugel nutzen, Geister fressen → Level leer → nächstes, neu generiertes Level. Dazu Speedrun-Timer mit Bestzeiten pro Level.
- Modi: Matrix-Level (Speedrun mit Level-Pool, zufälliger Start), Explorer-Level Manhattan (ruhig, ohne Geister, ohne Uhr, Punkte und Bestenliste; echte Gebäudenamen und -höhen, Fahrzeuge und Fußgänger als Hindernisse; die Kugeln weisen nur den Weg zur U-Bahn, die U-Bahn ist der Ausgang in den Speedrun), Debug-Overlay per F3 (nur Debug-Builds).
- Besondere Systeme: Word-Mode-Power-up (12 s Wort-Welt-Look plus Noclip), Twitch-Chat opt-in (`!power`, `!fruit`, nur unterstützend, nie störend).
- Darf nicht passieren:
  - Twitch-Effekte dürfen ernsthafte Speedruns nicht verfälschen oder die Eingabe blockieren
  - Rechtlich zu nah am Original (eigener Name, eigene Labyrinthe, eigene Optik, keine Original-Assets)
  - Übelkeit/Orientierungsverlust in First-Person-Labyrinthen ohne Gegenmittel (FOV, Minimap, Bewegungsoptionen)

## Entscheidungen des Entwicklers (Stand 2026-10-02, nicht erneut melden, außer sie führen zu neuen Problemen)
- Manhattan ist ohne Zeit, ohne Highscore und ohne Abschluss. Pellets sind nur Hinweise auf die Metro; die Metro ist der Ausgang in einen Speedrun.
- Speedrun-Level: Pool aus 6 Leveln mit festem Seed, zufälliger Start. „Offen“ (mehr Schleifen) und „Durchbruch“ (Türen in der Mittelspalte) sind die zwei Varianten des Labyrinth-Aufbaus und stehen als eigene Level zum Vergleich.
- Bestzeiten und Bestenlisten gibt es einzeln pro Level und Kondition, dazu eigene Bretter für Läufe mit Chat-Interaktion sowie für Multiplayer PvP und Koop (Mehrspieler selbst noch nicht gebaut).
- Pause: Die Speedrun-Zeit läuft weiter, Effekt-Timer stehen.
- Fear-&-Loathing-Pickup ist ein Risiko/Belohnungs-Item (Game-Designer-Linie): doppelte Punkte, keine Zufallskollision, keine Eigenbewegung ohne Eingabe, eigener Ton, erst ab dem 2. Level eines Laufs, nur in Sackgassen, ein zweites Pickup verlängert nur.
- Zielzeiten sind neu berechnet (siehe `godot/scripts/levels.gd`).
- Kein Testbuild-Button mehr. Steam Deck ist kein Ziel: keine Findings zu Steam-Deck- oder Controller-Bedienung, Lesbarkeit auf kleinen Handheld-Displays und Handheld-Performance.

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
