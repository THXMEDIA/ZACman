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
  scenes/           Main.tscn (Rest wird zur Laufzeit aus Code gebaut)
  tests/            Headless-Tests (Labyrinth-Konnektivität + Bot-Simulation)
web/               Browser-Prototyp (ein einziges HTML-File, Three.js via CDN)
core/              JS-Referenzimplementierung der Labyrinth-Generierung (für web/)
tests/             Node-Tests für die JS-Referenzimplementierung
docs/STEAM_ROADMAP.md  Weg von hier zu einer Steam-Veröffentlichung
```

## Godot-Version spielen / entwickeln

```bash
godot --path godot                                    # im Editor öffnen
godot --path godot godot/scenes/Main.tscn              # direkt starten (mit Editor installiert)
godot --headless --path godot --script res://tests/test_maze.gd   # Labyrinth-Tests
godot --headless --path godot res://tests/BotTest.tscn             # Bot-Simulation der gesamten Spiellogik
```

Steuerung: `WASD` laufen, Maus umschauen, `Esc` Pause.

Die Bot-Simulation instanziiert die echte `Main.tscn`-Szene headless, steuert
den Spieler über den echten `Input`-Singleton und prüft Kollisionen,
Gegner-KI-Zustände, Pickup-Logik und Level-Übergänge im laufenden Godot-
Physik-Loop — nicht in einer Attrappe.

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
