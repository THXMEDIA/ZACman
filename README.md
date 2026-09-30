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
- **Gegner**: vier bis fünf blockige Pixel-Geister (`godot/scripts/ghost_mesh.gd`
  — ein MultiMesh aus kleinen Würfeln, das die klassische Pac-Man-Geist-Silhouette
  nachbildet, im selben chunky Retro-Look wie der ASCII-Shader und die
  Wort-Mesh-Objekte) mit BFS-Pfadsuche zum Spieler; im "Frightened"-Modus nach
  einer Power-Kugel fliehen sie und lassen sich fressen.
- **Minimap**: zeigt neben Wänden, Spieler und Gegnern jetzt auch die
  verbleibenden Pellets/Power-Pellets (`hud.gd::_draw_minimap`, liest direkt
  MazeView.pellet_alive/power_alive — ein eingesammeltes Pellet verschwindet
  dort also sofort mit). Pellets respawnen innerhalb eines Levels nie
  (`MazeView.consume_at` schaltet sie dauerhaft `alive=false`); ein Level ist
  beendet, sobald `remaining_pickups() <= 0` ist.
- **Sound**: komplett synthetisch (Godot: zur Ladezeit gerenderte PCM-Buffer
  aus Oszillator + Hüllkurve; Web: Web-Audio-Oszillatoren) — keine Samples.
- **Matrix-ASCII-Look**: die Wände der Matrix-Level sind direkt mit
  `godot/shaders/matrix_rain.gdshader` geshadet (`CityTheme.wall_matrix_rain`,
  angewendet in `MazeView._make_materials`) — durchlaufende, zufällige grüne
  Zeichen (8x8-Bitmuster, kein Font-Asset nötig), die von oben nach unten
  scrollen wie ein Terminal, mit eigenem Tempo/Phase je Spalte. Immer und in
  jeder Entfernung voll sichtbar, nicht nur ab einer gewissen Distanz — ein
  Materialeffekt, kein Screen-Space-Blend. Sehr feines Raster (48x90 Zeichen
  pro Wandfläche), damit es nicht blockig wirkt.
- **Boden/Himmel-Mashup** (bewusster Stilbruch zu den grünen Matrix-Wänden):
  brauner Erdboden, blauer "Himmel" als Deckenfarbe mit verstreuten weißen
  Voxel-Wolken im Super-Mario-/Minecraft-Pixel-Look (`godot/scripts/
  cloud_mesh.gd`, gesteuert über `CityTheme.ceil_sky_clouds`). An beiden
  Enden des seitlichen Wrap-Tunnels (`maze.tunnel_row`) steht statt des
  blauen Himmels eine gemalte Super-Mario-artige Kulisse
  (`godot/shaders/mario_vista.gdshader`: Hügel, Büsche, Sonne, bewusst in
  warmen statt blauen Tönen) — sonst würde der Tunnelausgang einfach ins
  flache Himmelblau auslaufen.
- **Startbildschirm-Auswahl**: zwei gleichberechtigte Modus-Buttons,
  "MATRIX-LEVEL" (die klassischen Speedrun-Level) und "EXPLORER-LEVEL"
  (Manhattan) — beide von Anfang an spielbar, nicht mehr hinter einem
  Speedrun-Unlock versteckt (`hud.gd::_build_start_panel`). Direkt unter dem
  Matrix-Level-Button sitzt zusätzlich ein "TESTBUILD"-Button: startet
  denselben normalen Matrix-Level, blendet in der HUD-Leiste aber zusätzlich
  einen "DEBUG"-Chip ein (FPS, Spielerposition, aktuelle Maze-Zelle, live
  aktualisiert in `main.gd::_process`) — gedacht zum schnellen Prüfen eines
  Builds, kein eigener Spielmodus. Der Startbildschirm ist inzwischen mit
  genug Buttons/Zeilen gewachsen, dass er in einem kleineren Fenster nicht
  mehr sicher komplett hineinpasste — der Panel-Inhalt sitzt deshalb in
  einem `ScrollContainer` innerhalb einer auf 5%-95% der Fensterhöhe
  verankerten Spalte (`hud.gd::_overlay_panel(scrollable=true)`), sodass
  z. B. der EXPLORER-LEVEL-Button garantiert erreichbar bleibt, notfalls
  per Scrollen.
- **Speedrun-Unterstützung**: Live-Timer und persistierte Bestzeiten pro
  Level (`godot/scripts/speedrun.gd`). Wird eine Zielzeit unterboten, zeigt
  der Startbildschirm zusätzlich ein "★ Speedrun-Bestzeit-Bonus
  freigeschaltet"-Abzeichen neben dem Explorer-Button (rein kosmetisch,
  siehe `hud.gd::set_bonus_unlocked` — schaltet nichts mehr frei/zu).
  Manhattan ist ein von Hand nach dem echten Midtown-Straßenraster gebautes
  Level (`godot/scripts/manhattan_maze.gd`; echte Avenue-/Street-Namen,
  Startpunkt Penn Station, Geisterhaus bei Grand Central). Live-OSM/
  Overpass-Daten sind aus dieser Sandbox nicht erreichbar — für eine
  datengetriebene Variante siehe `tools/osm_to_chunks.py` im
  ReclaimTheStreets-Projekt, lokal ausführbar.
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
  Power-ups noch Geister (ein ruhiger Explorer), dafür fahren Fahrzeuge und
  laufen Fußgänger gleichermaßen auf festen Straßen/Avenues hin und her
  (siehe unten); beide sind reine Hindernisse (schieben den Spieler weg),
  verursachen aber nie Schaden.
- **Manhattan: echte Gebäudenamen, echte Höhen, echte Wolkenkratzer**
  (`godot/scripts/manhattan_maze.gd`, `maze_view.gd`, `word_mesh.gd`,
  `city_themes.gd`): 17 echte Midtown-Wahrzeichen (Empire State Building,
  Chrysler Building, Rockefeller Center, Times Square, Grand Central, ...)
  sind an ihrer realen Kreuzung im Straßenraster verankert, ersetzen dort das
  generische `BUILDING`-Wortmodell durch ihren echten Namen (Leerzeichen/
  Apostrophe entfernt, z. B. `EMPIRESTATEBUILDING`) und stehen jeweils in
  ihrer echten realen Höhe (Empire State Building 381 m Dachhöhe, Chrysler
  Building 319 m, 30 Rockefeller Plaza 259 m, Trump Tower 202 m, ... bis
  runter zu niedrigen Bauten wie der NY Public Library oder dem Bryant Park
  — Quelle: öffentliche Referenzwerte, keine Live-Vermessung, siehe
  `city_themes.gd::manhattan()`). Alle übrigen Gebäudeblöcke sind entweder
  ein gewöhnliches `BUILDING` (6–11 Einheiten hoch) oder — mit echten
  Wolkenkratzer-Odds — ein `SKYSCRAPER` (24–64 Einheiten, klar höher als
  seine Nachbarn), deterministisch pro Zelle gewählt. Jeder Name ist
  **hochkant** geschrieben: Buchstabe für Buchstabe von oben nach unten über
  die volle Gebäudehöhe gestapelt (`word_mesh.gd::build_vertical_stack`,
  dieselbe Technik wie schon bei der stehenden "MAN"-Figur in
  `man_walking_dog.gd`), statt eines einzelnen liegenden Wortes. Ein
  Wolkenkratzer sieht dadurch tatsächlich wie einer aus — deutlich höher,
  mit seinem Namen die ganze Fassade hoch. (Einschränkung: die reale
  *Grundfläche* der Gebäude ist nicht modelliert — jeder Block bleibt eine
  2×2-Meter-Zelle im Straßenraster, wie schon zuvor; echte 3D-Modelle
  einzelner Gebäude sind aus dieser Sandbox nicht ladbar, siehe unten.)
  Alle übrigen generischen Blöcke zyklen weiter durch eine warme,
  gedeckte Fünf-Farben-Palette (Ocker, Braun, Rostorange, Sandcreme,
  dunkles Oliv-Braun — kein Neon mehr; die ursprüngliche magenta-violette
  Neo-Noir-Cyberpunk-Fassung wich der wärmeren, gedeckten Bildsprache der
  Alex-Gopher-"The Child"-Referenzbilder, siehe `city_themes.gd::manhattan()`
  für die volle Palette samt Boden-/Himmel-/Ambient-Farben). Wahrzeichen
  heben sich weiterhin farblich ab, jetzt in Warmcreme-Gold, Rostorange-Rot
  und warmem Steingrau statt in Neonakzenten. Boden, Umgebungsfarbe/-Nebel
  und Ambient-Licht sind entsprechend umgestellt
  (`main.gd::_apply_theme_environment`) und kehren beim Verlassen zur
  normalen kühlen Blau-Palette der Matrix-Level zurück.
  **Keine physische Deckenebene mehr** (`CityTheme.ceil_enabled = false`
  für Manhattan): die alte, bei fester `MazeView.WALL_H`-Höhe liegende
  Deckenebene hat reale Wolkenkratzer (bis zu ~76 Einheiten hoch) von unten
  betrachtet verdeckt, sobald sie über diese Höhe hinausragten — sichtbar
  als Bug, bei dem von einem hohen `BUILDING`-Namen nur die untersten
  Buchstaben (z. B. nur "ING") zu lesen waren, der Rest aber wie
  abgeschnitten wirkte. Die Ursache war keine Text-, sondern eine
  Verdeckungs-Geometrie: eine deckende Ebene unterhalb der Turmspitze blockt
  jeden Blickstrahl von unten auf alles, was darüber liegt. Der neue
  `ceil_enabled`-Schalter lässt Manhattan ohne Deckenebene laufen (Himmel/
  Nebel/Hintergrundfarbe wirken direkt als offener Himmel), während die
  Matrix-Level ihre physische Wolken-Decke unverändert behalten.
  **Breitere Straßen** (`CityTheme.wall_footprint_scale = 0.55`): statt das
  Straßenraster selbst zu ändern (das hätte `MazeGen.cells_in_room()`s
  fest auf ein 2er-Perioden-Gitter angenommene Zellzählung projektweit
  gebrochen — Pellet-/Fußgänger-/Metro-Platzierung, Erreichbarkeits-Checks),
  sitzt jedes Gebäude jetzt sichtbar und kollisionsseitig von den Rändern
  seiner Rasterzelle zurückgesetzt (55 % der vollen Zellkante statt 100 %) —
  gleiche Topologie, gleiche Kollisionssicherheit (immer noch ein einzelner,
  mittig sitzender Block), aber spürbar mehr Luft zwischen zwei
  gegenüberliegenden Häuserfronten.
- **Punkte als Wegweiser zur Metro** (`maze_view.gd::_metro_trail_cells`):
  in Manhattan liegen die einsammelbaren Punkte nicht mehr auf jeder offenen
  Zelle, sondern nur noch entlang einer Handvoll kürzester Wege von
  verteilten Startpunkten zur jeweils nächsten U-Bahn-Station (Multi-Source-
  BFS von allen Metro-Zellen aus, zurückverfolgt von mehreren übers Level
  verteilten Punkten). Die Punkte bilden dadurch sichtbare Pfade, die zu
  einem Ausgang führen, statt das ganze Straßennetz gleichmäßig zu füllen —
  über eine Metro-Station verlässt man das Level wie zuvor.
- **CityTheme-System für zukünftige Explorer-Level** (`godot/scripts/
  city_theme.gd`, `city_themes.gd`): Manhattan und die normalen Matrix-Level
  sind keine hartkodierten `if/else`-Zweige mehr in `maze_view.gd`, sondern
  zwei Instanzen einer `CityTheme`-Resource (Wand-Wort & -Palette, optionaler
  Wahrzeichen-Provider wie `manhattan_maze.gd`, Boden-/Decken-Material,
  Umgebungsfarben/-Fog, Power-up-An/Aus). Eine neue, stilistisch komplett
  andere Stadt (Paris im Aquarell-Look, Tokio/Shibuya als Neonröhren-
  Cyberpunk-Regenszene, Rio im Pop-Art-Stil, ...) wird dadurch reiner Content:
  eine neue `CityTheme` in `city_themes.gd` registrieren, `maze_view.gd`/
  `main.gd` müssen dafür nicht angefasst werden. Architektur-Hintergrund und
  Prioritäten dazu stehen im Claude-Projekt-Dokument "Explorer-Level-
  Erweiterung, Leaderboard & Konditionen".
- **Konditionen-System** (`godot/scripts/conditions.gd`,
  `scripts/conditions/`): auswählbare, laufweite Run-Modifikatoren im Sinne
  eines Balatro-artigen "jeder Run ist anders" — unabhängig vom
  levelinternen Word-Mode-Pickup. Aktuell registriert: **Matrix Ghost**
  (dauerhaft kollisionsfreie, wort-gebaute Welt für den ganzen Run) und
  **Fear & Loathing** (Steuerung wird laufend verrauscht und kippt in
  unregelmäßigen Abständen komplett in die Umkehrung, ähnlich einem
  Drogenrausch-Level). `Main.set_condition(id)` wählt/wechselt/entfernt eine
  Kondition (`""` = keine); jede neue Kondition ist ein neues Skript unter
  `scripts/conditions/` mit einem Registry-Eintrag — der Rest des Spiels
  muss dafür nicht geändert werden.
- **WORD-Pickup als weißes Pixel-Kaninchen, neues Fear & Loathing-Pickup**
  (`godot/scripts/pixel_rabbit_mesh.gd`, `psychedelic_head_mesh.gd`,
  `maze_view.gd`, `main.gd`, `shaders/matrix_rain.gdshader`): das WORD-
  Pickup (normale Level; hebt Wandkollision auf und schaltet dauerhaft auf
  den wort-gebauten Look) zeigt sich jetzt nicht mehr als das Wort "WORD",
  sondern als kleines blockig-pixeliges weißes Kaninchen ("dem weißen
  Kaninchen folgen") — dieselbe Voxel-Technik wie schon bei den Wolken
  (`cloud_mesh.gd`). Neu dazugekommen ist ein zweites, selteneres Pickup:
  **Fear & Loathing**, sichtbar als abstrakter, kaleidoskopisch
  einfärbender Kopf (Totenkopf-Kugel, zwei überdimensionierte Augen, ein
  Ring rotierender Farbkugeln — eine eigene, nicht von einem realen
  Schauspieler oder einer bestimmten Filmfigur abgeleitete Gestalt) und für
  `FEAR_MODE_DURATION` (10 s) drei Dinge gleichzeitig: die Steuerung wird
  wie bei der gleichnamigen Kondition (`fear_and_loathing.gd`, direkt
  wiederverwendet statt dupliziert) laufend verrauscht/invertiert, der
  Matrix-Regen-Shader löst sich über einen neuen `psychedelic_amount`-
  Uniform in eine wabernde Regenbogen-Halluzination auf
  (`MazeView.set_psychedelic`), und die Wandkollision wird alle 0.4–1.1 s
  zufällig an/aus geschaltet (`Main._fear_next_noclip_toggle_at`). Ein
  vorher aktiv gewähltes Kondition (z. B. Matrix Ghost) wird beim Ende des
  Effekts unverändert wiederhergestellt.
- **Leaderboard** (`godot/scripts/leaderboard.gd`, Autoload `Leaderboard`):
  lokale Bestenlisten, ein Board pro Kombination aus (Stadt/Level) ×
  Kondition (`Leaderboard.board_key("manhattan", "matrix_ghost")` z. B.) —
  eine Matrix-Ghost-Zeit ohne Wandkollision ist nicht mit einer normalen
  Zeit vergleichbar, deshalb landen sie nie auf demselben Board. Persistiert
  lokal als JSON (`user://kugelschlucker_leaderboards.json`), hinter einer
  kleinen Schnittstelle (`submit_time`/`get_top`) gekapselt, damit ein
  späteres Steamworks-Backend (GodotSteam Leaderboards, sobald das Projekt
  eine Steamworks-App-ID hat — siehe `docs/STEAM_ROADMAP.md`) die
  Persistenz ersetzen kann, ohne Main/HUD anzufassen. Sowohl normale Level
  (`"normal-<level_index>"`) als auch das Manhattan-Bonuslevel tragen ihre
  Laufzeit ein.
- **Explorer-Abschluss-Auswahl**: Wird das Manhattan-Bonuslevel komplett
  durchgespielt, zeigt das HUD statt direkt zurück zum Hauptmenü ein Panel
  mit der Bestenliste des gerade gespielten Boards und vier Vorschlägen für
  den nächsten Lauf — gleiche Stadt/andere Kondition, andere Stadt/gleiche
  Kondition ("umgekehrt"), beides gleich (Wiederholung) und beides anders.
  "Andere Stadt" fällt aktuell auf dieselbe Stadt zurück, solange nur
  Manhattan als Explorer-Level existiert (siehe CityTheme-System oben) —
  sobald eine zweite Stadt registriert ist, werden alle vier Kombinationen
  automatisch unterschiedlich, ohne Code-Änderung an diesem Panel.
- **Verkehrs- und Fußgänger-Vielfalt in Manhattan** (`taxi.gd`,
  `pedestrian.gd`, `man_walking_dog.gd`, `kid_group.gd`, `dad_and_kid.gd`,
  `main.gd::_manhattan_vehicle_pool`): der Verkehr ist jetzt gewichtet
  gemischt statt fast nur `TAXI` — `TAXI` und ein neues, unauffälligeres
  `CAR` (stumpfes Stahlblau) sind am häufigsten, ein schnelleres, leichteres
  `BIKE` (Grün) seltener, und weiterhin gelegentlich eine `VERYLONGLIMOUSINE`
  in Chrom-Silber (das lange Wort steht selbst für die Fahrzeuglänge) als
  seltenster Typ. Mehr Fahrspuren (5 Zeilen-/4 Spalten-Straßen statt 3/2) und
  mehr Fahrzeuge insgesamt sorgen für dichteren Verkehr. Fußgänger **stehen
  nicht mehr still, sondern laufen** wie die Fahrzeuge eine feste Straße
  entlang und drehen an den Enden um (`pedestrian.gd`/`man_walking_dog.gd`/
  `kid_group.gd`/`dad_and_kid.gd` teilen sich dafür dieselbe optionale
  Lauf-Achsen-Logik wie `taxi.gd`, abwärtskompatibel zum alten
  Ein-Parameter-`setup()` für stehende Fußgänger). Ihre Zahl ist von 10 auf
  16 erhöht. Jeder Fußgänger ist zufällig entweder ein einzelner `MAN` oder
  `WOMAN`, ein `ManWalkingDog` (das Wort `MAN` als vertikal gestapelte
  Buchstaben, daneben tiefer das Wort `DOG`), eine `KidGroup` (drei versetzte
  `KID`-Wortmodelle) oder ein neues `DadAndKid` (das Wort `DAD` vertikal
  gestapelt, daneben ein kleineres `KID`) — für ein deutlich dichteres,
  belebteres und abwechslungsreicheres Straßenbild.
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
