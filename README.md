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
  cloud_mesh.gd`, gesteuert über `CityTheme.ceil_sky_clouds`). Sowohl die
  Wolken als auch die Himmel-Deckenebene selbst schweben dafür bei
  `WALL_H * 1.5` statt direkt auf Höhe der Wandoberkanten (`MazeView.
  CLOUD_HEIGHT_MULT`) — vorher hingen die Wolken quasi auf den Mauern statt
  sichtbar darüber; ein zusätzlicher fester Mindestabstand
  (`CLOUD_MIN_WALL_CLEARANCE`, 0.6 Einheiten über den Wandoberkanten) sorgt
  dafür, dass auch eine ungewöhnlich große (zufällig skalierte) Wolke nie
  näher an die Mauern heranrutscht. An beiden
  Enden des seitlichen Wrap-Tunnels (`maze.tunnel_row`) steht statt des
  blauen Himmels eine gemalte Super-Mario-artige Kulisse
  (`godot/shaders/mario_vista.gdshader`: Hügel, Büsche, Sonne, bewusst in
  warmen statt blauen Tönen) — sonst würde der Tunnelausgang einfach ins
  flache Himmelblau auslaufen.
- **Startbildschirm-Auswahl**: zwei gleichberechtigte Modus-Buttons,
  "MATRIX-LEVEL" (die klassischen Speedrun-Level) und "EXPLORER-LEVEL"
  (Manhattan) — beide von Anfang an spielbar, nicht mehr hinter einem
  Speedrun-Unlock versteckt (`hud.gd::_build_start_panel`). Unter dem
  Matrix-Level-Button wählt man die **Kondition** (Normal, Matrix Ghost,
  Fear & Loathing). Den Testbuild-Button gibt es nicht mehr; das
  Debug-Overlay (FPS, Position, Zelle) schaltet **F3** ein, nur in
  Debug-Builds (`main.gd::_unhandled_input`). Der Startbildschirm ist inzwischen mit
  genug Buttons/Zeilen gewachsen, dass er in einem kleineren Fenster nicht
  mehr sicher komplett hineinpasste — der Panel-Inhalt sitzt deshalb in
  einem `ScrollContainer` innerhalb einer auf 5%-95% der Fensterhöhe
  verankerten Spalte (`hud.gd::_overlay_panel(scrollable=true)`), sodass
  z. B. der EXPLORER-LEVEL-Button garantiert erreichbar bleibt, notfalls
  per Scrollen.
- **Speedrun-Unterstützung**: Live-Timer, Bestzeiten und Bestenlisten
  **pro Level, Kondition und Modus** (`speedrun.gd`, `leaderboard.gd`;
  Schlüssel `level|kondition[|modus]`, siehe `levels.gd::board_key`).
  Modi: `solo`, `chat` (sobald ein Twitch-Befehl im Level gewirkt hat),
  `pvp` und `coop` (reserviert für den geplanten Mehrspieler, noch ohne
  Spielmodus). Alte Spielstände werden beim Laden migriert. Die Uhr läuft
  auch in der Pause weiter; Effekt-Timer (Frightened, Word, Fear) bleiben
  in der Pause stehen (`main.gd`: `now` vs. `real_now`).
- **Level-Pool** (`godot/scripts/levels.gd`): sechs Speedrun-Level mit festem
  Seed, vier klassische plus „Offen“ (mehr Schleifen, weniger Sackgassen)
  und „Durchbruch“ (drei Türen in der geschlossenen Mittelspalte, die
  Hälften hängen nicht mehr nur am Tunnel). Ein Lauf startet auf einem
  zufälligen Level und spielt danach jedes weitere einmal, bevor sich eines
  wiederholt. Die Zielzeit steht pro Level in `levels.gd` und wird von
  `tests/test_levels.gd` gegen eine „nächster Pellet“-Route und die
  physikalische Untergrenze geprüft. Wer sie unterbietet, bekommt ein
  „★ Zielzeit geschafft“-Abzeichen (rein kosmetisch, nur für saubere
  Solo-Läufe ohne Kondition).
  Manhattan ist ein ruhiges Level ohne Uhr, Punkte und Bestenliste; die
  Kugeln sind nur Wegweiser zu den U-Bahn-Schildern, und die U-Bahn ist der
  Ausgang in einen Speedrun. Es ist ein von Hand nach dem echten Midtown-Straßenraster gebautes
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
  oder die Eingabe blockieren. Wirkt ein Befehl, geht die Zeit dieses Levels
  auf die eigene Chat-Bestzeit und die Chat-Bestenliste, nie auf die
  Solo-Rekorde.
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
  endet der Explorer-Lauf und ein Speedrun auf einem zufälligen Level
  beginnt.

- **Mehr Zeichenvielfalt, dunklerer/leuchtenderer Matrix-Regen, mehr
  Kondition-Item-Spawns, synthetisierte Hintergrundmusik**
  (`shaders/matrix_rain.gdshader`, `scripts/maze_view.gd`,
  `scripts/audio_synth.gd`, `scripts/main.gd`, `tests/bot_test.gd`,
  `tests/test_audio_synth.gd`):
  - **Zeichenvielfalt**: Die Glyphen-Tabelle des Matrix-Regen-Shaders ist
    von 10 auf 31 8×8-Bitmap-Zeichen gewachsen (`GLYPH_ROWS`/`GLYPH_COUNT`)
    — die zusätzlichen 21 sind skriptgeneriert (ein paar zufällige
    "Striche" plus gelegentliche Querstriche, zu leere/zu volle Muster
    verworfen), ein Skript-Äquivalent zum Von-Hand-Zeichnen weiterer zwei
    Dutzend Pixel-Glyphen. `sample_layer()` wählt jetzt aus dem vollen
    `GLYPH_COUNT`-Bereich statt nur aus den ursprünglichen 9.
  - **Farbe**: `bg_color` ist deutlich näher an Schwarz gezogen und
    `glyph_color` ein tieferes, gesättigteres Grün als vorher (statt des
    eher blassen Mittelgrüns); `EMISSION` ist von `color * 1.5` auf
    `color * 2.2` angehoben. Zusammen ergibt das eine Wand, die insgesamt
    dunkler wirkt (mehr Kontrast, mehr Schwarzraum zwischen den Zeichen),
    während die aufleuchtenden Glyphen selbst stärker/neonhafter glühen —
    "dunkler UND leuchtender" statt nur insgesamt gedimmt.
  - **Mehr Kondition-Item-Spawns**: Sowohl das WORD-Pickup (weißes
    Kaninchen) als auch das Fear-&-Loathing-Pickup spawnen jetzt
    `WORD_POWERUP_COUNT`/`FEAR_POWERUP_COUNT` (je 2) statt nur je einmal
    pro Level. `MazeView` hält dafür jetzt Array-Felder
    (`word_powerup_cells`/`_nodes`/`_alive`, `fear_powerup_cells`/`_nodes`/
    `_alive`) statt einzelner Werte — dasselbe Parallel-Array-Muster wie
    bereits bei den Power-Pellets (`power_cells`/`power_nodes`/
    `power_alive`). Ein neues `_pick_multiple_farthest()` verteilt die
    mehreren Spawns eines Typs per Farthest-Point-Sampling über
    unterschiedliche Ecken des Labyrinths, statt sie zu häufen.
  - **Musik**: Für die "frei verfügbare" Arcade-Musik im Pac-Man-Stil (normale
    Speedrun-Level) und die Musik im Stil von Roudoudou/Air/The Herbaliser
    (Explorer-/Manhattan-Level) wurde **keine externe Audiodatei
    heruntergeladen** — zum einen verbietet die Sandbox, in der dieses
    Feature gebaut wurde, beliebige Downloads von Drittanbieter-Seiten
    (nur npm/PyPI/GitHub sind erreichbar), zum anderen widerspräche es dem
    bereits bestehenden Architekturprinzip von `audio_synth.gd`
    ("kein Sample-/Asset-File irgendwo — spiegelt den Web-Audio-
    Synthese-Ansatz des Browser-Prototyps"). Stattdessen komponieren zwei
    neue, original geschriebene Stücke direkt in GDScript, gerendert mit
    genau derselben Oszillator+Hüllkurven-Technik wie jeder andere
    Sound-Effekt in dieser Datei:
    - `play_arcade_music()`: knackige Square-Wave-Lead-Melodie über
      Triangle-Bass mit einem leisen Off-Beat-Klick, ein kurzer sich
      wiederholender ~4,8-s-Loop im I–vi–IV–V-Bounce-Gefühl klassischer
      Coin-op-Chiptunes. Startet in `Main.begin_game()`.
    - `play_explorer_music()`: warme gehaltene Dreiklang-Akkorde
      (Fmaj7–Dm9–Gm7–Cmaj7) auf Triangle, ein gemächlicher Sinus-Bass und
      ein leiser gebürsteter Noise-Shaker — ein ruhiger, jazziger
      Downtempo-/Lounge-Loop im Sinne von Roudoudou/Air/The Herbaliser, bei
      ca. 84 BPM. Startet in `Main._start_explorer_run()` (auch für
      Manhattan).
    - Beide Loops verwenden dieselbe `AudioStreamWAV`-Loop-Technik wie die
      bestehende Sirene (`_siren_loop`), verallgemeinert über einen neuen
      `_compose_loop()`-Helfer auf mehrstimmige Notenfolgen statt eines
      einzelnen Dauertons. `Sfx.stop_all()` stoppt jetzt auch die Musik
      (`stop_music()`), damit ein Game-Over sauber still wird.
  - Getestet: `tests/bot_test.gd` prüft die neue Glyphenzahl/Farb-/
    Emission-Defaults im Shader-Quelltext, dass beide Kondition-Item-Typen
    mit mehr als einem Exemplar spawnen, und dass `Sfx.music_state()` beim
    Start eines normalen bzw. Manhattan-Laufs auf `"arcade"`/`"explorer"`
    wechselt. Ein neuer eigener Test, `tests/test_audio_synth.gd`, baut
    `Sfx` isoliert auf und prüft, dass beide Musik-Loops als nicht-leere,
    nahtlos schleifende PCM-Buffer gerendert werden und dass
    `play_*_music()`/`stop_all()`/`music_state()` korrekt zusammenspielen.

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
