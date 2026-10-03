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
  shaders/          pacman_wall/pacman_floor/crt_overlay — Speedrun-Look „Lagune“; kond_wall/kond_floor — Konditions-Looks; mario_vista (nicht im Speedrun)
  scenes/           Main.tscn (Rest wird zur Laufzeit aus Code gebaut)
  tests/            Headless-Tests (Labyrinth, Speedrun, Bretter, Manhattan, Twitch, Chat-Abstimmung, Bot-Simulation)
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
  — ein MultiMesh aus kleinen Würfeln in der eigenen Silhouette „Schild mit
  Visier“: Hörner, ein Sehschlitz, Spitze unten; keine Kuppel, kein
  Zackensaum, keine Augen. Farben je Level-Look aus `city_themes.gd`: Jäger
  Rot, Abfänger Zitron, Streuner Violett (in allen Leveln, damit Klassik IV
  fünf unterscheidbare Farben hat), Lauerer Bernstein,
  Nachzügler Magenta; verängstigt Mint `#BDFCEF`) mit BFS-Pfadsuche zum Spieler; im "Frightened"-Modus nach
  einer Power-Kugel fliehen sie und lassen sich fressen.
- **Minimap**: zeigt neben Wänden, Spieler und Gegnern jetzt auch die
  verbleibenden Pellets/Power-Pellets (`hud.gd::_draw_minimap`, liest direkt
  MazeView.pellet_alive/power_alive — ein eingesammeltes Pellet verschwindet
  dort also sofort mit). Pellets respawnen innerhalb eines Levels nie
  (`MazeView.consume_at` schaltet sie dauerhaft `alive=false`); ein Level ist
  beendet, sobald `remaining_pickups() <= 0` ist.
- **Sound**: komplett synthetisch (Godot: zur Ladezeit gerenderte PCM-Buffer
  aus Oszillator + Hüllkurve; Web: Web-Audio-Oszillatoren) — keine Samples.
- **Speedrun-Look „Lagune“** (Spezifikation `docs/design/kaninchen-speedrun.md`
  1.1, umgesetzt aus dem Art-Prototyp `tools/art/speedrun_proto/pacman_v2.patch`):
  dunkle Kanäle, türkise Leuchtkante `#1EF2C8` oben an jeder Wand, Verlauf
  zum Sockel je Level (`Levels.POOL[].look`: „lagune“ `#0B7FA8` oder „riff“
  `#1FBF5A`), Sockelstriche im 0,5-m-Takt, senkrechte Linien nur an freien
  Wandenden (Nachbar-Maske als MultiMesh-Custom-Data), beleuchteter Boden
  mit 2-m-Raster und Kreuzungsrahmen, CRT-Overlay (270 Zeilen, Vignette).
  Shader: `godot/shaders/pacman_wall.gdshader`, `pacman_floor.gdshader`,
  `crt_overlay.gdshader`; Farben als Konstanten in `city_themes.gd`
  (`LOOK_*`, `GHOST_*`). Kugeln sind Creme-Würfel, die Power-Kugel eine mit
  2 Hz blinkende Raute. Keine Wolken, kein Himmel, kein Mario-Vista mehr im
  Speedrun (`ceil_sky_clouds = false`); Explorer-Level behalten ihren Look.
  Der Basis-Look steckt in `pacman_wall_base.gdshaderinc` /
  `pacman_floor_base.gdshaderinc`, damit die Konditions-Shader exakt von ihm
  aus überblenden. `MazeView.set_look()`/`register_look()` tauschen zur
  Laufzeit Material und Shader-Parameter derselben Wand- und Boden-Instanzen
  (nie ein zweiter Wandsatz). Der alte Matrix-Regen-Shader und der
  Psychedelik-Effekt sind entfernt.
- **Startbildschirm-Auswahl**: zwei gleichberechtigte Modus-Buttons,
  "SPEEDRUN" (die Speedrun-Level) und "EXPLORER-LEVEL"
  (Manhattan) — beide von Anfang an spielbar, nicht mehr hinter einem
  Speedrun-Unlock versteckt (`hud.gd::_build_start_panel`). Eine
  Konditionswahl gibt es nicht mehr (das weiße Kaninchen entscheidet, siehe
  unten); dazu der Schalter **„Effekte reduzieren“** (auch im Pausemenü,
  gespeichert in `kugelschlucker_settings.json`, `settings.gd`). Den
  Testbuild-Button gibt es nicht mehr; das
  Debug-Overlay (FPS, Position, Zelle) schaltet **F3** ein, nur in
  Debug-Builds (`main.gd::_unhandled_input`). Der Startbildschirm ist inzwischen mit
  genug Buttons/Zeilen gewachsen, dass er in einem kleineren Fenster nicht
  mehr sicher komplett hineinpasste — der Panel-Inhalt sitzt deshalb in
  einem `ScrollContainer` innerhalb einer auf 5%-95% der Fensterhöhe
  verankerten Spalte (`hud.gd::_overlay_panel(scrollable=true)`), sodass
  z. B. der EXPLORER-LEVEL-Button garantiert erreichbar bleibt, notfalls
  per Scrollen.
- **Speedrun-Unterstützung**: Live-Timer, Bestzeiten und Bestenlisten
  **pro Level, Brett und Modus** (`speedrun.gd`, `leaderboard.gd`;
  Schlüssel `level|brett|modus`, z. B. `klassik-2|woche|solo`, siehe
  `levels.gd::board_key`). Die Kondition ist nicht Teil des Schlüssels.
  Details unter **Bretter** weiter unten. Spielstände tragen ein
  Versionsfeld (`SAVE_VERSION`, derzeit 3), Werte werden beim Laden auf
  Typ geprüft, geschrieben wird atomar über eine `.tmp`-Datei. Tests nutzen
  einen eigenen Speicherordner (`save_paths.gd`, `tests/save_isolation.gd`)
  und fassen echte Spielstände nicht an. Die Uhr läuft
  auch in der Pause weiter; Effekt-Timer (Frightened, Konditionen) bleiben
  in der Pause stehen (`main.gd`: `now` vs. `real_now`).
  **Start-Einblendung**: Bei jedem Speedrun-Start (`begin_game`, auch nach
  dem U-Bahn-Ausgang aus Manhattan; nicht zwischen Leveln) erscheint 2,5 s
  lang „Follow the white rabbit. But beware“ in einem eigenen, zentrierten
  Panel. Währenddessen kann man sich umsehen, aber nicht laufen; danach
  wartet die Welt (Geister, Effekte, Uhr stehen), bis die erste
  Bewegungseingabe kommt — erst dann startet die Uhr. Die Einblendung
  kostet also keine Zeit.
- **Level-Pool** (`godot/scripts/levels.gd`): sechs Speedrun-Level mit festem
  Seed, vier klassische plus „Offen“ (mehr Schleifen, weniger Sackgassen)
  und „Durchbruch“ (drei Türen in der geschlossenen Mittelspalte, die
  Hälften hängen nicht mehr nur am Tunnel). Ein Lauf startet auf einem
  zufälligen Level und spielt danach jedes weitere einmal, bevor sich eines
  wiederholt. Die Zielzeit steht pro Level in `levels.gd` und wird von
  `tests/test_levels.gd` gegen eine „nächster Pellet“-Route und die
  physikalische Untergrenze geprüft. Wer sie unterbietet, bekommt ein
  „★ Zielzeit geschafft“-Abzeichen (rein kosmetisch, nur für Solo-Läufe
  auf dem Wochenbrett, `Levels.BADGE_BOARDS`).
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
  Speedruns nicht beeinflusst werden). Befehle:
  - `!power` (Frightened-Modus) und `!fruit` (Bonusfrucht) helfen nur, nie
    beenden oder blockieren sie etwas. Jeder hat einen globalen Cooldown
    von 20 s Spielzeit (`Main.CHAT_COMMAND_COOLDOWN_S`, Code-W8): etwa drei
    Frightened-Fenster (7 s), also kein Dauer-Frightened und kein
    Combo-Reset-Spam; in einem Level des Pools (Zielzeit 115–225 s) bleibt
    der Chat trotzdem 5- bis 11-mal sichtbar. Global statt pro Nutzer, weil
    ein Cooldown pro Nutzer mit vielen Zuschauern wirkungslos wäre.
  - `!gut` und `!schlecht` stimmen über das weiße Kaninchen ab
    (Spezifikation 2.6, `chat_vote.gd`): eine Stimme pro Nutzer im
    gleitenden 60-s-Fenster, die letzte zählt. Gut-Anteil = 60 % + 30
    Prozentpunkte × (gut − schlecht) / (gut + schlecht), begrenzt auf
    20–80 % (mit dieser Formel ist 30 % das Minimum); unter 3 verschiedenen
    Stimmen gilt 60 %. Gelesen wird bei der Kaninchen-Aufnahme. Hat der
    Chat den Anteil verschoben (≥ 3 Stimmen und ≠ 60 %), zieht ein
    Generator mit echtem Zufall mit dieser Gewichtung (weiter über
    `pick_condition`). Das ist der einzige Weg, auf dem der Chat ein Level
    auch erschweren kann. Anzeige im Chat-Modus: Chip „Kaninchen: 72 %
    gut“ mit grün/magenta Balken; die Titelkarte zeigt „Chat 72 % →
    MATRIX“.
  - Hatte der Chat in einem Level eine Hand im Spiel (wirksames
    `!power`/`!fruit` oder verschobenes Kaninchen), zählt das Level auf das
    Brett `chat`, nie auf `woche` oder `chaos` (`Main._mark_chat_assisted`).
- **Word-Mode / das "Wort-Welt"-Aussehen** (`godot/scripts/word_mesh.gd`):
  jedes Objekt besteht aus seinem eigenen englischen Namen als echtes
  extrudiertes 3D-Buchstabenmodell (Godots `TextMesh`) — eine Wand ist das
  Wort `WALL`, ein Geist das Wort `GHOST`, ein Taxi das Wort `TAXI`, ein
  Fußgänger das Wort `PERSON`. Den Wort-Welt-Look gibt es nur noch als
  dauerhafte Welt im **Manhattan-Bonuslevel** (der Word-Mode-Pickup der
  Speedrun-Level ist entfallen; `MazeView` baut die Wort-Wände nur für
  dauerhaft wortgebaute Themes) — dort gibt es weder
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
  Palette der Speedrun-Level zurück.
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
  Speedrun-Level ihre physische Decke unverändert behalten.
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
  city_theme.gd`, `city_themes.gd`): Manhattan und die Speedrun-Level
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
- **Weißes Kaninchen und Konditionen** (Spezifikation
  `docs/design/kaninchen-speedrun.md` 1.2 und 2.1–2.5; `white_rabbit.gd`,
  `conditions.gd`, `scripts/conditions/`, `condition_looks.gd`,
  `shaders/kond_*.gdshader*`):
  - **Kaninchen**: genau eines pro Speedrun-Level ab Level 1, als weißes
    Pixel-Kaninchen (`pixel_rabbit_mesh.gd`, Hasenweiß `#F2F2ED`). Es sitzt
    deterministisch je Level-Seed in einer Sackgasse, deren BFS-Distanz zum
    Start mindestens 40 % des Maximums beträgt (`WhiteRabbit.pick_cell`), ist
    ab Levelstart auf der Minimap zu sehen und freiwillig: seine Zelle trägt
    keine Kugel, es zählt nicht zum Levelabschluss. Wer es liegen lässt,
    spielt einen voll deterministischen Lauf.
  - **Konditionen** sind zeitlich begrenzte Effekte, die nur das Kaninchen
    auslöst. Registry in `conditions.gd` mit `is_good`, `duration_s` (gut
    10 s, schlecht 8 s) und `weight`; Grundverhältnis gut:schlecht 60:40,
    innerhalb gleich verteilt (`Conditions.pick_condition(rng, p_good)`).
    Pool: **Matrix** (gut; Wände ohne Kollision, Look „Durchlässiger Code“,
    in den letzten 3 s blenden die Wände blinkend ein, am Ende steht der
    Spieler sicher mit freier Kapsel in der nächsten offenen Zelle),
    **Taschenuhr** (gut; Geister 50 % langsamer, leicht warmer Farbstich,
    Uhren-Ticken), **Fear & Loathing** (schlecht; siehe unten, Look
    „Kippbild“), **Stromausfall** (schlecht; Nebel mit ~2 Zellen Sicht,
    Minimap aus, Kugeln und Geister leuchten weiter). Es gibt genau eine
    aktive Kondition (`Main.active_condition`); Noclip, Geistertempo,
    Minimap und Look werden daraus abgeleitet. Ein weiteres Kaninchen
    ersetzt die laufende Kondition, nichts stapelt sich.
  - **Fear & Loathing**: pro Aufnahme genau eine Manipulation, gezogen mit
    dem Kaninchen-Zufall und mit Symbol auf der Titelkarte: A/D getauscht,
    Drift (25 % Seitenzug, nur solange eine Bewegungseingabe anliegt) oder
    150 ms Verzögerung auf WASD (fester Ringpuffer; beim Loslassen steht man
    sofort). „Gekippt“ ist der Look, solange die Manipulation auf die
    aktuelle Eingabe wirkt. **Rote Linie**: Maus, Blickrichtung und Kamera
    werden nie manipuliert, keine Bewegung ohne Eingabe, kein Bildwackeln,
    kein FOV-Pulsieren, nie schneller als `PLAYER_SPEED`.
  - **Looks**: ein gemeinsamer Wand-/Boden-Shader (`kond_wall`/`kond_floor`
    mit `look`, `transition`, `flip`, `reduce_fx`), über die Look-API auf
    dieselben Instanzen gelegt. Übergang als 0,8-s-Welle vom Spieler aus, in
    der Wellenfront zerfallen die Linien zu Zeichen in Hasenweiß; Rückweg
    identisch. Kugeln, Power-Kugel und Geister behalten Farbe und Form
    (in Matrix und Kippbild mit schwarzer Kontur). Main setzt Looks immer
    erst nach dem Levelaufbau. „Effekte reduzieren“ beruhigt alle Looks
    (dichtere Matrix-Wände, kein Blinken, langsameres Fließen); die
    Spielwirkung bleibt gleich.
  - **HUD und Ton**: Titelkarte oben (Name, Symbol, Restzeit-Balken; gut
    grün, schlecht magenta), Aufnahme-Ton gut aufsteigend bzw. schlecht
    verstimmt fallend, Tick-Töne in den letzten 3 s (alles synthetisch,
    `audio_synth.gd`).
  - **Kaninchen der Woche**: Das Ergebnis jedes Kaninchens (Kondition und
    ggf. F&L-Manipulation) kommt aus einem eigenen `RandomNumberGenerator`
    mit dem Seed `hash("<level-id>|<JJJJ>-W<ww>")` — Level-ID plus
    ISO-Kalenderwoche nach der **lokalen Zeit des Spielers**
    (`Time.get_datetime_dict_from_system(false)`; das Spiel hat keinen
    Server und keine Zeitzonen-Datenbank, „diese Woche“ beginnt am Montag
    des Spielers). Ein Neustart würfelt nicht neu. Nie globales
    `randf()`/`randi()`. Im Chaos-Modus liefert `Main._make_rabbit_rng`
    stattdessen `WhiteRabbit.chaos_rng()` (zufälliger Seed); die
    Chat-Gewichtung kommt über `Main._rabbit_p_good`. Alles läuft über
    `Conditions.pick_condition(rng, p_good)`.
  - **Musikschicht**: Für die Dauer einer Kondition liegt eine zusätzliche
    synthetische Schicht über der Arcade-Musik (`audio_synth.gd`,
    `start_condition_layer`/`stop_condition_layer`): gut ein helles
    Arpeggio über den Arcade-Akkorden, schlecht ein tiefer, verstimmter
    Puls auf dem Tritonus. Gleiche Länge und gleiches Tempo wie der
    Arcade-Loop, synchron gestartet, 0,6 s Einblenden, 0,9 s Ausblenden.
  - Entfallen: Konditionswahl am Startscreen, Word-Mode-Pickup im Speedrun,
    separates Fear-Pickup (`psychedelic_head_mesh.gd`), doppelte Punkte,
    „erst ab Level 2“, Sinus-Rauschen und unangekündigte Steuerungsumkehr.
- **Bretter und Bestenliste** (`levels.gd`, `speedrun.gd`,
  `leaderboard.gd`, Spezifikation 2.5): Schlüssel `level|brett|modus`.
  - Bretter: `woche` (Kaninchen der Woche, Standard), `chaos`
    (Chaos-Modus) und `chat` (der Chat hatte eine Hand im Level, siehe
    Twitch). Vorrang: `chat` vor `chaos` vor `woche` (`Main.board_id`).
  - Modi: `solo`, `pvp` und `coop` (reserviert für den geplanten
    Mehrspieler). Chat ist seit Etappe 3 ein Brett, kein Modus mehr.
    Unbekannte Level, Bretter oder Modi werden nicht geschrieben
    (`Levels.is_valid_board_key`, Code-W8).
  - Bestzeiten auf dem Wochenbrett speichern die ISO-Kalenderwoche mit
    (`{"time", "week": "2026-W40"}`); die Allzeit-Bestzeit pro Level nennt
    ihre Woche. HUD: Chip BESTZEIT („1:23.45 · KW 39“) und Chip BRETT
    („WOCHE · KW 40“, „CHAOS“, „CHAT“).
  - Zielzeit-Abzeichen: nur Solo auf dem Wochenbrett, auch mit Matrix
    (Entscheidung Studio Head: das Kaninchen ist eine freiwillige Wette mit
    Umweg).
  - **Chaos-Modus**: Schalter am Startscreen (gespeichert in
    `kugelschlucker_settings.json`, Version 2), echter Zufall für jedes
    Kaninchen, eigenes Brett `chaos`, Badge CHAOS.
  - **Bestenliste**: Button BESTENLISTE am Startscreen; Tabs Woche, Chaos,
    Chat, Level-Umschalter, Top 10. Auf dem Wochenbrett steht bei jeder
    Zeit die Kalenderwoche, oben die Allzeit-Bestzeit mit Woche und die
    Bestzeit der laufenden Woche. Alle Einträge heißen noch „Player“.
  - **Migration auf Version 3** (beim Laden, idempotent): Bretter mit
    Konditions-Schlüsseln (`|none`, `|matrix_ghost`, `|fear_and_loathing`,
    mit oder ohne Modus) sowie die alten Manhattan- und
    `normal-N`-Bretter wandern unverändert in einen `archive`-Bereich der
    Datei: behalten, nie angezeigt. Bretter aus Etappe 2
    (`level|woche[|modus]`) werden übernommen (Woche unbekannt, Anzeige
    „KW ?“), `level|woche|chat` geht aufs Chat-Brett. Zeiten des alten
    Bretts „none“ werden **nicht** als Ausgangswert aufs Wochenbrett
    übernommen: Damals galt eine andere Pflichtstrecke (die heutige
    Kaninchen-Sackgasse trug eine Pflicht-Kugel; ab dem zweiten Level eines
    Laufs ersetzten Word-/Fear-Pickups Kugeln, GD-W1/Code-W2), und welche
    Variante eine Zeit war, steht nicht in der Datei.
  - Lokal als JSON (`user://kugelschlucker_speedrun.json`,
    `user://kugelschlucker_leaderboards.json`), hinter einer kleinen
    Schnittstelle (`submit_time`/`get_top`), damit ein späteres
    Steamworks-Backend (GodotSteam Leaderboards, siehe
    `docs/STEAM_ROADMAP.md`) die Persistenz ersetzen kann, ohne Main/HUD
    anzufassen. Manhattan hat kein Brett.
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

- **Speedrun-Level im Detail**: Gegner-Kollision ohne seitliches
  Vorbeischlüpfen (`Main.ENEMY_HIT_RADIUS` 0,85), Wände 4,4 m hoch mit
  `wall_footprint_scale` 1,12 (Korridore ~1,76 m), Geistertempo ab der
  zweiten Runde gedeckelt (`Main.GHOST_SPEED_CAP` 3,96 m/s, ≈ 90 % der
  Spielergeschwindigkeit). Musik: zwei original komponierte, zur Ladezeit
  synthetisierte Loops (`play_arcade_music` im Speedrun,
  `play_explorer_music` in Manhattan), keine Audiodateien.
- **Verlauf**: Ältere Umsetzungsrunden und Review-Runden stehen in der
  Git-Historie und unter `docs/review/berichte/`; dieser README beschreibt
  nur den Ist-Stand.

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
