# ZACman (Kugelschlucker)

Ein First-Person-3D-Labyrinthspiel im Geiste von Pac-Man: durch ein
Labyrinth laufen, Kugeln schlucken, Power-Kugeln nutzen und leuchtenden
Wesen ausweichen — mit eigener, prozedural erzeugter Level-Geometrie,
eigener Optik und vollständig synthetisierten Sounds (keine Original-Assets).

**Godot-Version** (`godot/`) ist der aktive Entwicklungs- und Steam-Zielpfad.
**Web-Version** (`web/index.html`) ist der ursprüngliche Browser-Prototyp und
bleibt spielbar, wird aber nicht mehr parallel weiterentwickelt.

## Projektstruktur

```
godot/             Godot-4.3-Projekt — aktiver Entwicklungsstand, Steam-Ziel
  scripts/          Spiellogik (GDScript)
  shaders/          ascii_post.gdshader — Matrix-ASCII-Bildschirmeffekt
  scenes/           Main.tscn (Rest wird zur Laufzeit aus Code gebaut)
  tests/            Headless-Tests (Labyrinth, Speedrun, Manhattan, Twitch, Bot-Simulation)
web/               Browser-Prototyp (ein einziges HTML-File, Three.js via CDN)
core/              JS-Referenzimplementierung der Labyrinth-Generierung (für web/)
tests/             Node-Tests für die JS-Referenzimplementierung
docs/STEAM_ROADMAP.md  Weg von hier zu einer Steam-Veröffentlichung
```

## Godot-Version spielen / entwickeln

```bash
godot --path godot                                    # im Editor öffnen
godot --path godot godot/scenes/Main.tscn              # direkt starten (mit Editor installiert)
npm run test:godot                                     # alle Headless-Tests in Reihenfolge
```

Steuerung: `WASD` laufen, Maus umschauen, `Esc` Pause.

Die Bot-Simulation (`godot/tests/BotTest.tscn`) instanziiert die echte
`Main.tscn`-Szene headless, steuert den Spieler über den echten
`Input`-Singleton und prüft Kollisionen, Gegner-KI-Zustände, Pickup-Logik,
Level-Übergänge, den Speedrun-/Bonuslevel-Unlock und die Twitch-Chat-Befehle
im laufenden Godot-Physik-Loop — nicht in einer Attrappe.

## Spiel-Design

- **Labyrinthe**: pro Level neu generiert (randomisierter Tiefensuche-Spannbaum
  + zusätzliche Schleifen), links/rechts gespiegelt wie beim Original, mit
  zentralem "Gegner-Haus" und einem Seitentunnel zum Durchqueren. Der Godot-
  Generator (`godot/scripts/maze_gen.gd`) ist ein 1:1-Port der getesteten
  JS-Logik (`core/maze-core.js`) — beide sind unabhängig voneinander auf
  Konnektivität getestet.
- **Gegner**: vier bis fünf leuchtende Polyeder mit BFS-Pfadsuche zum Spieler;
  im "Frightened"-Modus nach einer Power-Kugel fliehen sie und lassen sich fressen.
- **Sound**: komplett synthetisch (Godot: zur Ladezeit gerenderte PCM-Buffer
  aus Oszillator + Hüllkurve; Web: Web-Audio-Oszillatoren) — keine Samples.
- **Matrix-ASCII-Look**: ein Screen-Space-Post-Effekt (`godot/shaders/ascii_post.gdshader`,
  angelehnt an das ReclaimTheStreets-Projekt) wandelt das Bild ab einer
  gewissen Entfernung in grüne ASCII-Zeichen um — Pellets/Gegner in
  Spielernähe bleiben scharf, die Labyrinthwände sind fast immer im
  ASCII-Bereich.
- **Speedrun-Unterstützung**: Live-Timer und persistierte Bestzeiten pro
  Level (`godot/scripts/speedrun.gd`). Wird eine Zielzeit unterboten,
  schaltet sich das **Manhattan-Bonuslevel** dauerhaft frei — ein von Hand
  nach dem echten Midtown-Straßenraster gebautes Level (`godot/scripts/
  manhattan_maze.gd`; echte Avenue-/Street-Namen, Startpunkt Penn Station,
  Geisterhaus bei Grand Central), spielbar über den Button auf dem
  Startbildschirm sobald freigeschaltet. Live-OSM/Overpass-Daten sind aus
  dieser Sandbox nicht erreichbar — für eine datengetriebene Variante siehe
  `tools/osm_to_chunks.py` im ReclaimTheStreets-Projekt, lokal ausführbar.
- **Twitch-Chat (opt-in)**: anonymer, credential-freier IRC-Chat-Listener
  (`godot/scripts/twitch_chat.gd`) für einen frei wählbaren Kanal, per
  Checkbox auf dem Startbildschirm standardmäßig **aus** (damit ernsthafte
  Speedruns nicht beeinflusst werden). Zuschauer können mit `!power`
  (Frightened-Modus auslösen) und `!fruit` (Bonusfrucht spawnen) helfen —
  beide Effekte können den Spieler nur unterstützen, nie das Spiel beenden
  oder die Eingabe blockieren.
- **Word-Mode / das "Wort-Welt"-Aussehen** (`godot/scripts/word_mesh.gd`):
  jedes Objekt besteht aus seinem eigenen englischen Namen als echtes
  extrudiertes 3D-Buchstabenmodell (Godots `TextMesh`) — eine Wand ist das
  Wort `WALL`, ein Geist das Wort `GHOST`, ein Taxi das Wort `TAXI`, ein
  Fußgänger das Wort `PERSON`. In den normalen Matrix-Leveln ist das ein
  zeitlich begrenzter Power-up-Effekt: einmal pro Level liegt ein
  pulsierendes `WORD`-Icon versteckt; wer es einsammelt, bekommt für
  12 Sekunden den Wort-Welt-Look *und* geht kollisionsfrei durch Wände
  (`player_controller.gd::set_noclip`). Im **Manhattan-Bonuslevel** ist der
  Wort-Welt-Look dauerhaft aktiv statt eines Power-ups — dort gibt es weder
  Power-ups noch Geister (ein ruhiger Explorer), dafür fahren Fahrzeuge auf
  festen Straßen/Avenues hin und her und Fußgänger stehen an zufälligen
  Kreuzungen; beide sind reine Hindernisse (schieben den Spieler weg),
  verursachen aber nie Schaden.
- **Manhattan: echte Gebäudenamen & Neo-Noir-Cyberpunk-Look**
  (`godot/scripts/manhattan_maze.gd`, `maze_view.gd`): 17 echte Midtown-
  Wahrzeichen (Empire State Building, Times Square, Grand Central, Rockefeller
  Center, ...) sind an ihrer realen Kreuzung im Straßenraster verankert und
  ersetzen dort das generische `BUILDING`-Wortmodell durch ihren echten
  Namen, mit pulsierendem Akzent-Licht. Alle übrigen Gebäudeblöcke tragen das
  Wort `BUILDING` in einer von fünf zyklisch vergebenen Neonfarben. Boden,
  Decke und die Umgebungsbeleuchtung sind für Manhattan auf ein
  magenta-violettes Neo-Noir-Cyberpunk-Schema umgestellt
  (`main.gd::_apply_manhattan_environment`) und kehren beim Verlassen zur
  normalen kühlen Blau-Palette zurück.
- **Verkehrs- und Fußgänger-Vielfalt in Manhattan** (`taxi.gd`,
  `man_walking_dog.gd`, `kid_group.gd`): neben normalen `TAXI`-Fahrzeugen
  fährt gelegentlich eine `VERYLONGLIMOUSINE` in Chrom-Silber vorbei — das
  lange Wort selbst steht für die Fahrzeuglänge. Fußgänger sind zufällig
  entweder eine einzelne `PERSON`, ein `ManWalkingDog` (das Wort `MAN` als
  vertikal gestapelte Buchstaben, daneben tiefer das Wort `DOG`) oder eine
  `KidGroup` (drei versetzte `KID`-Wortmodelle) für ein abwechslungsreiches
  Straßenbild.
- **U-Bahn-Stationen** (`metro_station.gd`): leuchtend-pulsierende `SUBWAY`-
  Schilder markieren feste Punkte im Manhattan-Level, platziert wie Taxis/
  Fußgänger kollisionsfrei mit den Pellets. Betritt der Spieler eine Station,
  endet der Manhattan-Bonuslauf sofort und es geht zurück ins normale
  Speedrun-Level (frischer Lauf ab Level 1).

## Steam-Veröffentlichung

Siehe [`docs/STEAM_ROADMAP.md`](docs/STEAM_ROADMAP.md): Godot-Export-Setup,
Steamworks-Integration über GodotSteam, ein Konzept für Koop- und
kompetitiven Multiplayer auf Basis von Godots High-Level-Multiplayer-API,
und die administrativen Schritte bei Valve, die nur im eigenen
Steamworks-Konto erledigt werden können.

## Web-Prototyp (Referenz)

```bash
npm test              # Labyrinth- und Spiellogik-Tests für web/index.html
npm start              # web/index.html im Standard-Browser öffnen
```
