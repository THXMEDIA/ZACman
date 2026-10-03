# Review-Brief: ZACman (Kugelschlucker)

Gilt für alle drei Reviewer (`game-designer`, `ux-reviewer`, `code-reviewer`).
Rollenspezifische Zusätze stehen in `docs/review/<rollenname>.md`.
Anweisungen für ein einzelnes Review kommen direkt in den Auftrag und haben Vorrang.

> Vorausgefüllt aus README und `docs/STEAM_ROADMAP.md`. Mit ❓ markierte Punkte bitte ergänzen.

## Das Spiel
- Pitch: First-Person-3D-Labyrinthspiel im Geiste von Pac-Man: durch prozedural erzeugte Labyrinthe laufen, Kugeln schlucken, Power-Kugeln nutzen, leuchtenden Wesen ausweichen. Eigene Optik (Speedrun-Look „Lagune“, Konditions-Looks, Wort-Welt in Manhattan), komplett synthetische Sounds.
- Genre und Referenzspiele: First-Person-Arcade/Maze, Speedrun-tauglich ❓ Referenzspiele ergänzen
- Zielgruppe: ❓ (Retro-Fans, Speedrunner, Streamer/Twitch-Zuschauer?)
- Plattformen: Steam (Windows, Linux, macOS). Steam Deck und Controller sind kein Ziel. `web/index.html` ist nur noch ein Browser-Prototyp und wird nicht weiterentwickelt.
- Engine: Godot 4.3 (GDScript), aktiver Stand in `godot/`
- Monetarisierung: ❓ (Kaufpreis? Achievements und Cloud-Saves über GodotSteam geplant)

## Designziele
- Gefühl: ❓
- Core Loop: Labyrinth erkunden → Kugeln sammeln → Power-Kugel nutzen, Geister fressen → Level leer → nächstes, neu generiertes Level. Dazu Speedrun-Timer mit Bestzeiten pro Level.
- Modi: Speedrun (Level-Pool, zufälliger Start, ein weißes Kaninchen pro Level), Explorer-Level Manhattan (ruhig, ohne Geister, ohne Uhr, Punkte und Bestenliste; echte Gebäudenamen und -höhen, Fahrzeuge und Fußgänger als Hindernisse; die Kugeln weisen nur den Weg zur U-Bahn, die U-Bahn ist der Ausgang in den Speedrun), Debug-Overlay per F3 (nur Debug-Builds).
- Besondere Systeme: weißes Kaninchen mit zeitlich begrenzten Konditionen (Matrix, Taschenuhr, Fear & Loathing, Stromausfall; „Kaninchen der Woche“), Twitch-Chat opt-in (`!power`, `!fruit`, nur unterstützend, nie störend; ab Etappe 3 darf der Chat über das Kaninchen-Verhältnis auch erschweren).
- Darf nicht passieren:
  - Twitch-Effekte dürfen ernsthafte Speedruns nicht verfälschen oder die Eingabe blockieren
  - Rechtlich zu nah am Original (eigener Name, eigene Labyrinthe, eigene Optik, keine Original-Assets)
  - Übelkeit/Orientierungsverlust in First-Person-Labyrinthen ohne Gegenmittel (FOV, Minimap, Bewegungsoptionen)

## Entscheidungen des Entwicklers (Stand 2026-10-03, nicht erneut melden, außer sie führen zu neuen Problemen)
- Verbindliche Spezifikation für Speedrun-Look und Kaninchen: `docs/design/kaninchen-speedrun.md` (E8, E8a–g). Umsetzung in drei Etappen; Etappe 1 (Look „Lagune“) und Etappe 2 (Kaninchen, Konditionen) sind umgesetzt, Etappe 3 (Chaos-Modus, Chat-Gewichtung, Brett-Migration) folgt.
- Manhattan ist ohne Zeit, ohne Highscore und ohne Abschluss. Pellets sind nur Hinweise auf die Metro; die Metro ist der Ausgang in einen Speedrun. Manhattan hat kein Kaninchen und behält seine permanente Wort-Welt.
- Speedrun-Level: Pool aus 6 Leveln mit festem Seed, zufälliger Start. „Offen“ (mehr Schleifen) und „Durchbruch“ (Türen in der Mittelspalte) sind die zwei Varianten des Labyrinth-Aufbaus und stehen als eigene Level zum Vergleich.
- **Konditionen nur per Kaninchen**: Genau ein weißes Kaninchen pro Speedrun-Level, in einer weit entfernten Sackgasse, freiwillig (seine Zelle trägt keine Pflicht-Kugel). Es löst eine zeitlich begrenzte Kondition aus (gut 10 s, schlecht 8 s, gut:schlecht 60:40). Keine Konditionswahl am Startscreen, kein Word-Mode-Pickup, kein separates Fear-Pickup mehr. Ein zweites Kaninchen würde ersetzen, nicht stapeln.
- **Kaninchen der Woche**: Das Ergebnis folgt aus Level-ID + ISO-Kalenderwoche (lokale Zeit des Spielers), eigener Zufallsgenerator, ein Neustart würfelt nicht neu.
- **Rote Linie Kamera (E8e)**: Keine Kondition manipuliert Maus, Blickrichtung oder Kamera. Keine Bewegung ohne Eingabe, kein Bildwackeln, kein FOV-Pulsieren, keine Zeitdilatation; Bewegungen der Looks < 0,5 Hz, Blinken < 3 Hz, keine Vollbild-Blitze. „Effekte reduzieren“ (Startscreen und Pause) beruhigt die Looks, die Spielwirkung bleibt gleich.
- **Fear & Loathing neu geregelt**: schlechte Kondition statt Risiko/Belohnungs-Item (keine doppelten Punkte mehr). Pro Aufnahme genau eine angekündigte Manipulation (A/D getauscht, Drift 25 % nur bei Eingabe, 150 ms Verzögerung), Look „Kippbild“ kippt, solange die Manipulation auf die Eingabe wirkt. Sinus-Rauschen und unangekündigte Umkehr sind entfallen.
- Bestzeiten und Bestenlisten pro Level, Brett und Modus. Die Kondition ist nicht mehr Teil des Schlüssels; bis Etappe 3 zählt jeder Speedrun-Lauf auf das Brett „woche“. Eigene Modi für Chat-Läufe sowie für Multiplayer PvP und Koop (Mehrspieler selbst noch nicht gebaut).
- Start-Einblendung „Follow the white rabbit. But beware“ (2,5 s) bei jedem Speedrun-Start; die Uhr startet erst mit der ersten Bewegungseingabe danach. Pause: Die Speedrun-Zeit läuft weiter, Effekt-Timer stehen.
- Geisterfarben: Der Streuner bleibt in allen Leveln Violett `#A65CFF` (Entscheidung Studio Head 03.10.2026), damit Klassik IV fünf unterscheidbare Geisterfarben hat.
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
