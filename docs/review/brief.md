# Review-Brief: ZAPmaniac

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
- Besondere Systeme: weißes Kaninchen mit zeitlich begrenzten Konditionen (Matrix, Taschenuhr, Fear & Loathing, Stromausfall; „Kaninchen der Woche“, Chaos-Modus), Musikschicht je Kondition, Twitch-Chat opt-in: `!power`, `!fruit` helfen (globaler Cooldown 20 s); `!gut`/`!schlecht` stimmen über das Gut/Schlecht-Verhältnis des Kaninchens ab — der einzige Weg, auf dem der Chat ein Level auch erschweren darf.
- Darf nicht passieren:
  - Twitch-Effekte dürfen ernsthafte Speedruns nicht verfälschen oder die Eingabe blockieren (jeder Einfluss des Chats verschiebt das Level aufs Brett `chat`)
  - Rechtlich zu nah am Original (eigener Name, eigene Labyrinthe, eigene Optik, keine Original-Assets)
  - Übelkeit/Orientierungsverlust in First-Person-Labyrinthen ohne Gegenmittel (FOV, Minimap, Bewegungsoptionen)

## Entscheidungen des Entwicklers (Stand 2026-10-03, nicht erneut melden, außer sie führen zu neuen Problemen)
- Verbindliche Spezifikation für Speedrun-Look und Kaninchen: `docs/design/kaninchen-speedrun.md` (E8, E8a–g). Alle drei Etappen sind umgesetzt: Look „Lagune“, Kaninchen und Konditionen, Bretter/Chaos-Modus/Chat-Gewichtung/Musikschicht/Migration.
- Manhattan ist ohne Zeit, ohne Highscore und ohne Abschluss. Pellets sind nur Hinweise auf die Metro; die Metro ist der Ausgang in einen Speedrun. Manhattan hat kein Kaninchen und behält seine permanente Wort-Welt.
- Speedrun-Level: Pool aus 6 Leveln mit festem Seed, zufälliger Start. „Offen“ (mehr Schleifen) und „Durchbruch“ (Türen in der Mittelspalte) sind die zwei Varianten des Labyrinth-Aufbaus und stehen als eigene Level zum Vergleich.
- **Konditionen nur per Kaninchen**: Genau ein weißes Kaninchen pro Speedrun-Level, in einer weit entfernten Sackgasse, freiwillig (seine Zelle trägt keine Pflicht-Kugel). Es löst eine zeitlich begrenzte Kondition aus (gut 10 s, schlecht 8 s, gut:schlecht 60:40). Keine Konditionswahl am Startscreen, kein Word-Mode-Pickup, kein separates Fear-Pickup mehr. Ein zweites Kaninchen würde ersetzen, nicht stapeln.
- **Kaninchen der Woche**: Das Ergebnis folgt aus Level-ID + ISO-Kalenderwoche (lokale Zeit des Spielers), eigener Zufallsgenerator, ein Neustart würfelt nicht neu.
- **Chaos-Modus** (Schalter am Startscreen, gespeichert): echter Zufall für jedes Kaninchen, eigenes Brett `chaos`, Badge CHAOS im HUD.
- **Chat und Kaninchen** (E8g, Formel nach Review 03.10.): `!gut`/`!schlecht`, eine Stimme pro Nutzer im gleitenden 60-s-Fenster, letzte zählt; Gut-Anteil p = 0,60 + 0,30·d − 0,10·d² mit d = (gut − schlecht)/(gut + schlecht), begrenzt 20–80 %, unter 3 Stimmen 60 %. Verschiebt der Chat den Anteil, wird mit echtem Zufall gezogen und das Level zählt aufs Brett `chat`. Der Chat darf also erschweren, aber nur über dieses Verhältnis. Chip nur bei verbundenem Chat; ohne Verschiebung zeigt er „Kaninchen: Woche“ bzw. „Chaos“.
- **Chat-Hilfe und Highscore** (Studio Head 03.10.): Hatte der Chat in einem Lauf eine Hand im Spiel, wird dessen Punktzahl nicht als Highscore gespeichert.
- **Tod beendet die Kondition** (Studio Head 03.10.): Bei Lebensverlust endet die laufende Kondition; danach Kollision an, Spieler auf der Startzelle mit Blick in den längsten Gang.
- **Verängstigte Geister** in Cerulean `#14A7CC` (nicht mehr fast-weiß; außerhalb 215–250°, Begründung in `city_themes.gd` und Spezifikation 1.1).
- **Komfort und Menüs** (Review 03.10.): Komfort-Block (Effekte reduzieren, Sichtfeld 60–100°, Mausempfindlichkeit) unter dem Titel und in der Pause; Pause WEITER/NEUSTART/HAUPTMENÜ, Game over NOCHMAL/HAUPTMENÜ/BESTENLISTE, Startscreen BEENDEN. Bestenliste mit Kondition und Datum je Eintrag, „Diese Woche/Allzeit“.
- **Wette messen statt schätzen**: `tools/qa/qa_rabbit_balance.gd` misst per Bot Δt jeder Kondition gegenüber einem Lauf ohne Kaninchen (Ergebnis im Bericht der Umsetzungsrunde). Werte wurden dabei nicht geändert.
- **Rote Linie Kamera (E8e)**: Keine Kondition manipuliert Maus, Blickrichtung oder Kamera. Keine Bewegung ohne Eingabe, kein Bildwackeln, kein FOV-Pulsieren, keine Zeitdilatation; Bewegungen der Looks < 0,5 Hz, Blinken < 3 Hz, keine Vollbild-Blitze. „Effekte reduzieren“ (Startscreen und Pause) beruhigt die Looks, die Spielwirkung bleibt gleich.
- **Fear & Loathing neu geregelt**: schlechte Kondition statt Risiko/Belohnungs-Item (keine doppelten Punkte mehr). Pro Aufnahme genau eine angekündigte Manipulation (A/D getauscht, Drift 25 % nur bei Eingabe, 150 ms Verzögerung), Look „Kippbild“ kippt, solange die Manipulation auf die Eingabe wirkt. Sinus-Rauschen und unangekündigte Umkehr sind entfallen.
- **Bretter**: Bestzeiten und Bestenlisten pro Level, Brett und Modus, Schlüssel `level|brett|modus`. Bretter `woche` (Standard), `chaos`, `chat` (Vorrang chat > chaos > woche); Modi `solo`, `pvp`, `coop` (Mehrspieler noch nicht gebaut). Die Kondition ist nicht Teil des Schlüssels. Wochen-Bestzeiten speichern ihre ISO-Woche, die Allzeit-Bestzeit nennt ihre Woche. Bestenliste am Startscreen. Alte Konditions-Bretter sind beim Laden archiviert (Datei-Version 3, Bereich `archive`, nie angezeigt); alte „none“-Zeiten wurden bewusst nicht aufs Wochenbrett übernommen (andere Pflichtstrecke).
- **Zielzeit-Abzeichen**: nur Solo auf dem Wochenbrett, auch mit Matrix (Studio Head: das Kaninchen ist eine freiwillige Wette mit Umweg).
- Start-Einblendung „Follow the white rabbit. But beware“ (2,5 s) bei jedem Speedrun-Start (ab dem zweiten Start der Sitzung per Taste überspringbar); die Uhr startet erst mit der ersten Bewegungseingabe danach, Laufen wird im selben Moment freigegeben. Pause: Die Speedrun-Zeit läuft weiter, Effekt-Timer stehen.
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
- Code-Konventionen: Szenen werden zur Laufzeit aus Code gebaut (`Main.tscn` ist die einzige Szene); Labyrinth-Generator deterministisch über Seed; jeder Zufall von `Main` läuft über eigene Generatoren (`Main.seed_randomness`), nie über globales `randf()`; Spielstände werden atomar geschrieben, kaputte Dateien vor dem Überschreiben gesichert; Headless-Tests in `godot/tests/` (`npm run test:godot`) müssen grün bleiben, inklusive Bot-Simulation `BotTest.tscn` ❓ weitere
