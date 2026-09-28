# ZACman (Kugelschlucker)

Ein First-Person-3D-Labyrinthspiel im Geiste von Pac-Man: durch ein
Labyrinth laufen, Kugeln schlucken, Power-Kugeln nutzen und leuchtenden
Wesen ausweichen — mit eigener, prozedural erzeugter Level-Geometrie,
eigener Optik und vollständig synthetisierten Sounds (keine Original-Assets).

**Spielbar im Browser:** öffne `web/index.html` direkt, oder starte den
Electron-Desktop-Wrapper (siehe unten). Steuerung: `WASD` laufen, Maus
umschauen, `Esc` Pause; auf Touch-Geräten Joystick + Wischsteuerung.

## Projektstruktur

```
web/               Browser-Version des Spiels (ein einziges HTML-File, Three.js via CDN)
core/maze-core.js  Getestete Labyrinth-Generierung + BFS-Pfadsuche (Node-Modul)
tests/             Automatisierte Tests: Labyrinth-Konnektivität + Bot-Simulation der Spiellogik
desktop/           Electron-Wrapper für einen nativen Desktop-Build (Grundlage für Steam)
docs/STEAM_ROADMAP.md  Weg von hier zu einer Steam-Veröffentlichung
```

## Spiel-Design

- **Labyrinthe**: pro Level neu generiert (randomisierter Tiefensuche-Spannbaum
  + zusätzliche Schleifen), links/rechts gespiegelt wie beim Original, mit
  zentralem "Gegner-Haus" und einem Seitentunnel zum Durchqueren.
- **Gegner**: vier bis fünf leuchtende Polyeder mit BFS-Pfadsuche zum Spieler;
  im "Frightened"-Modus nach einer Power-Kugel fliehen sie und lassen sich fressen.
  Palette an Rot/Magenta/Cyan/Bernstein/Violett angelehnt an die Farbsprache
  des Originals, aber mit eigener Form (Ikosaeder statt Geister-Sprite).
- **Sound**: komplett synthetisch per Web Audio (Oszillatoren + Hüllkurven) —
  keine Samples, kein Sample-Ripping.

## Entwicklung

```bash
npm test              # Labyrinth- und Spiellogik-Tests (node --test)
npm start              # web/index.html im Standard-Browser öffnen
npm run desktop        # Electron-Fenster starten (erst: npm --prefix desktop install)
npm run dist            # Desktop-Build für Win/Mac/Linux erzeugen
```

Die Tests in `tests/` extrahieren das Skript direkt aus `web/index.html` und
führen es in einer simulierten DOM-/Three.js-Umgebung mit einem Bot-Spieler
aus — es gibt keine separat gepflegte Kopie der Spiellogik, die aus dem
Takt geraten könnte.

## Steam-Veröffentlichung

Siehe [`docs/STEAM_ROADMAP.md`](docs/STEAM_ROADMAP.md) für den vollständigen
Plan: was hier im Repo schon vorbereitet ist (Electron-Wrapper, Build-Config)
und was als nächstes bei Valve selbst erledigt werden muss (Steamworks-Konto,
App-Gebühr, Store-Seite, Upload).
