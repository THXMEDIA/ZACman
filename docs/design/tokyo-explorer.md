# Spezifikation: Explorer-Stadt Tokyo („Natriumregen“)

**Stand:** 03.10.2026 · v2 (M1 und M2 umgesetzt auf `feature/tokyo-explorer`)
**Grundlage:** Stil-Vorlage `studio/zapmaniac-tokyo-stil-v1.md`, Richtung A „Natriumregen“,
freigegeben vom Inhaber am 03.10.2026 (E6, keine Änderungswünsche). Prototypen und
Vorschlagsbilder: Branch `art/tokyo-vorschlaege`, `tools/art/tokyo_proto/` und
`docs/art/vorschlaege/tokyo/` (`natriumregen_*.png`).
**Verbindlich für:** Look, Lesbarkeit, Rechtsgrenzen, technische Auflagen und
Meilensteine der Explorer-Stadt Tokyo. Der Speedrun-Look bleibt unberührt
(`docs/design/kaninchen-speedrun.md`).

## 1. Ziel

Tokyo ist die zweite Explorer-Stadt neben Manhattan: ruhig, ohne Uhr, Punkte,
Geister und Kaninchen. Die Kugeln zeigen den Weg zur U-Bahn, die U-Bahn ist der
Ausgang in einen Speedrun. Stimmung: Fremder im Regen, einsam in der Menge,
staunend – der Gegenpol zum harten, grünen Speedrun.

Leitidee: **Die Stadt ist Natriumlicht, Kaltweiß und ein Magenta-Akzent auf
schwarzer Masse; einzige photoreale Fläche ist der nasse Asphalt, der alles
verdoppelt.** Gebäude, Menschen und Verkehr bestehen nur aus Neonröhren-Umrissen.

## 2. Look

### 2.1 Palette und Rollen (`godot/scripts/tokyo_style.gd`)

| Rolle | Farbe | Regel |
|---|---|---|
| Himmel | `#060504` | ruhiger Nachthimmel, Nebel färbt ihn nur zu 30 % |
| Gebäudemasse | `#030304` | unbeleuchtet, schwarz, verdeckt nur |
| Asphalt nass | `#0B0A0C` | einzige „photoreale“ Fläche, glänzend |
| Welt Amber (Natrium) | `#FF9A2E` | Gebäudelinien, Sockellinie, Laternen, Ladenfronten |
| Welt Kaltweiß | `#F2EFE8` | Gebäudelinien, Bordstein, Schilder |
| Akzent Magenta | `#FF2E88` | **nur** Screens und Akzentringe des Rundturms |
| Kugeln | `#FFD98A`, Kern `#FFF8E6` | **exklusiv** für Kugeln |
| U-Bahn | `#39FF6A` | **exklusiv**, einzige gefüllte Fläche, pulsiert 0,5 Hz |
| Scheinwerfer / Rücklicht | `#FFFFFF` / `#FF2A1A` | nur Verkehr; Karosserie in Kaltweiß, gedämpft |
| Passanten | `#A49A8C` | ~50 % der Gebäudelinien auf dem Bildschirm (nach Filmic-Tonemapping, Test) |
| Asphalt / Gehweg | `#0B0A0C` / `#100E0F` | nass; Gehweg minimal heller |
| Regen | `#C8C0B4` | Grundhelligkeit sehr gering, Farbe kommt aus dem Gegenlicht |

### 2.2 Typografie

- Schilder: **Noto Sans CJK JP Bold** (SIL OFL 1.1), als Subset gebündelt
  (`godot/fonts/NotoSansCJKjp-Bold-Subset.otf`, nur die Schilderzeichen;
  Lizenz in `docs/art/lizenzen.md`).
- UI bleibt die Godot-Standardschrift; Inter für Titel-Platzhalter und DejaVu Sans
  Mono für den ASCII-Übergang folgen mit M3.

### 2.3 Formsprache und Licht

- Neonröhren an allen Gebäudekanten, dünnere Etagenbänder, wenige Pfosten;
  oben eine umlaufende Dachlinie. Helligkeit fällt nach oben auf ~30 %.
- **Sockellinie auf 2,3 m** an jeder Fassade zur Straße = Kollisionskante.
  Darunter warmes Ladenfenster-Leuchten (Amber, gedämpft, kein Flackern).
- Bordstein als niedrige kaltweiße Linie, an den Kreuzungsecken gerundet.
- Screens sind die einzigen flächigen Lichtquellen (Magenta→Amber, Drift < 0,1 Hz).
- Natriumlaternen an Fassadenauslegern (keine frei stehenden Masten: nichts im
  Weg, das nicht als Kollision sichtbar ist).
- Glow (Schwelle 0,85), Filmic-Tonemapping, Nebel `#1C130C`.

### 2.4 Lesbarkeitsregeln

1. Grün nur U-Bahn (gefüllt, Lichtkegel, Pulsieren); Gold nur Kugeln.
2. In der Welt höchstens Amber, Kaltweiß und Magenta; Magenta nur Screens/Rundturm,
   höchstens zwei Screens pro Blickachse.
3. Kein Violett, Cyan oder Blau in der Welt (Abgrenzung zum Genre-Standard und zu TRON).
4. Sockellinie (2,3 m) und Bordstein immer sichtbar; Sockellinie = Kollision.
5. Passanten ~50 % Helligkeit, Helligkeit nach oben auf ~30 %.
6. Kein Headbob, kein Flackern ≥ 3 Hz, keine Vollbild-Blitze (rote Linie E8e gilt auch hier).

## 3. Shibuya als Platzhalter (`godot/scripts/tokyo_maze.gd`)

Gröbere Gitter-Annäherung an die Umgebung einer großen Scramble-Kreuzung vor einem
Bahnhof. 1 Zelle = 2 m, 47 × 47 Zellen (94 m × 94 m), geschlossener Rand.

| Bereich | Zellen | Bemerkung |
|---|---|---|
| Bahnhof | Zeilen 0–2 | ganze Nordkante; U-Bahn-Ausgang **地下鉄** in der Fassade (Zelle 3/23) |
| Bahnhofsvorplatz | Zeilen 3–5 | Fußgängerfläche, kein Bordstein |
| Nord-Süd-Allee | Spalten 20–26 | je 1 Zelle Gehweg, 5 Zellen Fahrbahn |
| Ost-West-Allee | Zeilen 20–26 | dasselbe Profil |
| **Kreuzungsfeld** | 20–26 × 20–26 | ein offenes 7 × 7-Feld; Zebras an allen Armen, Diagonal-X |
| Gassen | 3 Zellen breit | NW, NO, SO (Nord-Süd), SW (Ost-West) |
| Start | Zelle 42/23 | südliche Allee, Blick nach Norden über die Kreuzung zum Bahnhof |

Platzhalter-Gebäude (alle ohne Namen, Logos oder echte Schriftzüge):

- **Nordturm mit Screen:** Rücksprung-Turm auf dem Nordostblock, großer
  senkrechter Screen diagonal über der Ecke zur Kreuzung (7 m über der Straße).
- **Rundturm, verfremdet:** **Achteck** statt Zylinder, schräg abgeschnittene
  Krone, zwei schräge Magenta-Ringe als Akzent, kein Schildpfeiler, keine Ziffern –
  bewusst nicht als Shibuya 109 lesbar; steht nordwestlich auf einem Sockelbau.
- **Skydeck-Turm:** hoher weißer Turm hinter dem Bahnhof (96 m) mit Deck-Ring.
- **Erhöhter Steg:** Fußgängerbrücke über die nördliche Allee (4,2 m, keine Kollision).
- Ladenschilder nur mit Allgemeinwörtern: 居酒屋, 本屋, ラーメン, 薬, 喫茶, カラオケ.
- Silhouetten-Ring außerhalb der Karte (Tiefe über Lichtdichte).

**Kugelspuren:** Mittellinien von Vorplatz, Alleen und Gassen bilden ein Netz.
Vom Start und von vier per Level-Seed gewählten Netz-Enden führt je eine
ununterbrochene Goldlinie (eine Kugel pro Zelle, 2 m Abstand) zur U-Bahn.

### Rechtsgrenzen (verbindlich)

- Keine echten Marken, Logos, Firmennamen, Werbung oder Markenfarben.
- Rundturm verfremdet (siehe oben), **nicht als Shibuya 109 lesbar**.
- **Keine Hachiko-Nachbildung** (kein Hundedenkmal, kein Ersatztier am Treffpunkt).
- **Keine TRON-Formen**: keine Lichtrenner, keine Hexagone, keine Scheiben, kein
  Cyan-gegen-Orange.
- Gebäudeformen und Schilder kommen in M3 auf die Rechtsliste (Prüfung vor Release).
- Keine KI-generierten Inhalte; alles per Code, Fremdmaterial nur der Font.

## 4. Technik

### 4.1 Architektur

- **Explorer-Städte allgemein** (`explorer_cities.gd`): Registry pro Stadt-ID mit
  Theme, Gitter-Skript, Level-Seed, Metro-Platzierung („random“ für Manhattan,
  „maze“ für den festen Bahnhofsausgang), Metro-Skript, Verkehr, Ausgangstext.
  `Main.begin_explorer_game(city_id)` / `start_explorer_level(city_id)` enthalten
  keine Stadtnamen mehr; `begin_manhattan_game()`, `start_manhattan_level()` und
  `playing_manhattan` bleiben als Namen für Tests und Werkzeuge.
- **Startscreen:** Zeile „EXPLORER | MANHATTAN | TOKYO“ statt des einzelnen
  Explorer-Buttons (gleiche Höhe, passt weiter bei 1152 × 720).
- **CityTheme `tokyo`** (`city_themes.gd`): schwarze Masse über die bestehende
  Wand-MultiMesh (`shaders/tokyo_mass.gdshader`, Höhen je Block über den
  Landmark-Provider), `scenery_builder_script` = `tokyo_scenery.gd`,
  `pellet_trail_provider_script` = `tokyo_maze.gd`. Der Look-Wechsel läuft über das
  bestehende Look-System (`MazeView.register_look(LOOK_BASE, …)`).
- **Linien-Builder** (`neon_lines.gd`): Röhren als dünne Boxen, gebündelt **eine
  Mesh-Instanz pro Farbe** (Amber, Weiß, Magenta, Ausleger), Helligkeitsfaktor je
  Linie in `UV.x`, Höhenabfall im Shader (`shaders/neon_line.gdshader`).
- **Kollision exakt an der Sockellinie:** Gebäude sind ganze Zellen
  (`wall_footprint_scale` 1,0); die Sockellinie wird aus der Grenze Wand/offen des
  Gitters erzeugt, ihre Innenseite liegt auf der Kollisionsfläche (Test).

- **M2:** `explorer_cities.gd` Verkehr `"tokyo"` → Main legt `tokyo_life.gd`
  unter `obstacle_root` an (Level-Seed der Stadt, Komfort-Werte) und ruft es
  jeden Frame auf; `_clear_explorer_obstacles` räumt es ab. Der Boden bekommt
  seine Parameter über `CityTheme.floor_setup_script` (`tokyo_wet.gd`).

### 4.2 Technische Auflagen (aus der technischen Prüfung, verbindlich)

1. **SSR statt Zweitrender-Spiegel** (kein SubViewport mit gespiegelter Kamera wie im Prototyp).
2. **Halos, Lichtkegel, Passanten, Autos als MultiMesh mit Shader-Animation**
   (keine Einzelknoten pro Figur, keine CPU-Animation pro Frame).
3. **Pfützenmaske vorgebacken**, höchstens **8 Lichtpfützen** im Bodenshader.
4. **Regen-Bewegung im Shader**, höchstens **8.000 Tropfen**; Regen lichter, wo
   Kugeln liegen, plus Option „Regen reduzieren“.
5. **Gebündelter OFL-CJK-Font als Subset** (kein System-Font).
6. **Level-Seed statt festem Seed:** alle variierende Dekoration (Etagenbänder,
   Pfosten, Silhouetten, Wahl der Kugelspuren) kommt aus dem Seed der Stadt
   (`explorer_cities.gd`, Tokyo 7310), nie aus `randf()` oder festen Zahlen im Builder.
7. **Theme-Wechsel setzt Glow, SSR, Volumetrik, Tonemapping, Nebel-Himmelsanteil,
   Spielerlampe und Sichtweite zurück** (`Main._apply_theme_environment` setzt bei
   jedem Wechsel alle Werte aus dem Theme; Speedrun und Manhattan tragen die Werte
   eines frischen `Environment`).

### 4.3 Budgets

- **Draw Calls der Statik ≤ 20** (Stand M2: 18 im Compatibility-Renderer —
  Wand-MultiMesh, Boden, 4 Linienfarben, Masse, Fahrbahnfarbe, Ladenfronten,
  2 Screens, 1 Screen-Schrift, 5 Schilder, Bodenspiegelung; in Forward+ 17,
  dort entfällt die Bodenspiegelung zugunsten von SSR).
- **Draw Calls Tokyo gesamt ≤ 32** (Test `test_tokyo_life.gd`), Stand M2 **28**:

  | Gruppe | Draw Calls | Inhalt |
  |---|---|---|
  | Statik | 18 | siehe oben |
  | Kugeln | 1 | alle Kugeln als **eine** MultiMesh (auch Manhattan und Speedrun) |
  | U-Bahn-Ausgang | 3 | Portal (gefüllte Fläche), Rahmen, Schild 地下鉄 |
  | Bewegte Stadt (`tokyo_life.gd`) | 6 | Regen, Autos, Passanten (inkl. Scramble-Welle), Halos, Lichtkegel, Lichtstreifen |

- **Additive Elemente ≤ 20 Draw Calls**, Stand M2 **6**: Ladenfronten,
  Bodenspiegelung, Regen, Halos, Lichtkegel, Lichtstreifen.
- Zusätzlich im Compatibility-Renderer eine Kopie des Bildes für die
  Bodenspiegelung (Bildschirmtextur), in Forward+ die SSR-Pässe.
- **Instanzen:** Regen 8.000 (sichtbar 5.600 mit „Effekte reduzieren“,
  2.800 mit „Regen reduzieren“), 16 Autos, 28 Passanten + 112 in der
  Scramble-Welle, 73 Halos (8 Laternen, U-Bahn, 4 je Auto), 41 Kegel
  (8 Laternen, U-Bahn, 2 je Auto), 80 Lichtstreifen (5 je Auto).
- **Lichter ≤ 10** in der Szene (8 Laternen, 2 Screens) plus U-Bahn und
  Spielerlampe; Boden und Regen werten je höchstens **8** Lichter aus (die
  nächsten zur Kamera; der Regen zählt die Scheinwerfer mit).
- **Pro Frame:** keine neuen Objekte, Ressourcen oder Knoten; die CPU setzt
  nur Instanz-Transforms (Autos, Personen, Autolichter) und zwei kurze
  Lichtlisten (Test über 600 Frames).
- Linien-Röhren: M1 ~1.900 Segmente (ca. 15.000 Vertices) in 4 Meshes.

### 4.4 Performance-Ziel

**Vorläufig 60 fps bei 1080p auf GTX-1660-Klasse** (vom Studio Head gesetzt,
Bestätigung durch den Inhaber offen). Erwartete Mehrlast ggü. Manhattan laut
code-reviewer 3–5 ms GPU mit Regen und SSR. Messung auf echter Hardware steht
aus (M2 ist gebaut); die Sandbox rendert nur im Software-Renderer
(Compatibility, ohne SSR) und kann das Ziel nicht belegen.

### 4.5 Umsetzung M2 (bewegte Stadt)

- **Nasser Boden** (`shaders/tokyo_floor.gdshader`, `tokyo_wet.gd`): Pfützenmaske
  einmal pro Levelaufbau gebacken (FastNoiseLite, 512², Level-Seed), dazu
  Rinnsteine entlang der Bordsteine. Pfützen scharf und glänzend
  (Roughness 0,035), Asphalt halbnass (0,26–0,42) — das ist die
  Roughness-Maske für SSR. Bis zu 8 Lichtpfützen und gestreckte
  Reflexstreifen der 8 nächsten Lichter (Laternen, Screens, U-Bahn),
  Ladenfront-Glow aus der Zellkarte, Himmelsreflex und Grundhelligkeit
  (Boden nie schwarz). Fahrbahnfarbe in Pfützen dunkler.
- **Spiegelung ohne SSR** (`shaders/tokyo_floor_reflect.gdshader`, nur wenn
  kein RenderingDevice da ist, also im Compatibility-Renderer): eine dünne
  additive Schicht über Boden und Fahrbahnfarbe liest das fertige opake Bild
  an der am Horizont gespiegelten Blickrichtung (Bildschirmtextur), verwischt
  es senkrecht wie auf nassem Asphalt, scharf in Pfützen. Kein Zweitrender,
  keine SubViewport-Kamera (Auflage 1 bleibt erfüllt). Näherung: gespiegelt
  wird, was weit genug weg ist; nahe, niedrige Dinge spiegeln ungenau.
  In Forward+ entfällt die Schicht, SSR übernimmt, die Reflexstreifen
  laufen gedämpft weiter (`fake_refl` 0,45).
- **Regen** (`shaders/tokyo_rain.gdshader`): 8.000 Instanzen ohne
  Transforms; Ort aus `INSTANCE_ID`, Fallen, Wind und Umbrechen in einer Box
  (34 × 20 × 34 m) um die Kamera im Vertex-Shader; Aufhellung im Gegenlicht
  der 8 nächsten Lichter (inkl. Scheinwerfer), Ausblenden 0,7–2,6 m vor der
  Kamera und zum Rand der Box; über Kugelzellen 75 % weniger Tropfen.
- **Verkehr** (`tokyo_life.gd`, `tokyo_figures.gd`, `shaders/tokyo_car.gdshader`):
  Linksverkehr, je Achse zwei geschlossene Schleifen (Wenden hinter den
  Randgebäuden bzw. vor dem Bahnhofsvorplatz), 4 Autos je Schleife,
  Folgeabstand, Halt an den Haltelinien vor den Zebras und vor dem Spieler
  in der Spur. Die CPU rechnet nur die Position. Lichtstreifen der Autos
  (`shaders/tokyo_streak.gdshader`) am Spiegelpunkt des Lichts, zur Kamera
  gestreckt (von oben kürzer), über die Zellkarte verdeckt, wenn ein Gebäude
  dazwischen liegt. Hindernis wie Manhattan: Main schiebt den Spieler aus
  einer Kapsel entlang der Autoachse (Radius 1,05 m).
- **Passanten und Scramble** (`shaders/tokyo_walker.gdshader`): Gang im
  Vertex-Shader (Beine um die Hüfte, Arme um die Schulter, Schirm wippt;
  INSTANCE_CUSTOM Phase, Schrittfrequenz, Helligkeit, Schirm ja/nein,
  85 % mit Schirm). Ampelzyklus 80 s: 0–26 s Nord-Süd grün, 26–30 s alle rot,
  30–56 s Ost-West grün, 56–60 s alle rot, 60–80 s **All Walk**; Start im
  Zyklus bei 36 s (erster All Walk nach ~24 s). Die Welle (4 × 28) sammelt
  sich ab ~35 s an den Ecken (aus Ladentüren), quert gerade über die Zebras
  oder diagonal über das ganze Feld und ist nach spätestens 16,5 s drüben,
  danach verschwindet sie in Läden. Passanten sind harmlos (weicher Push wie
  Manhattan, 0,35 m). Fußgängerton: zwei kurze synthetische Sinus-Glissandi,
  dreimal (`Sfx.crossing_signal`). Es gibt bewusst keine sichtbaren
  Fußgängerampeln (Grün ist exklusiv für die U-Bahn).
- **Halos und Lichtkegel** (`shaders/tokyo_halo.gdshader`,
  `shaders/tokyo_cone.gdshader`): je eine MultiMesh, Farbe × Energie und
  Pulsfrequenz in INSTANCE_CUSTOM; U-Bahn mit grünem Halo und Kegel, 0,5 Hz.
  Halos und Kegel blenden direkt vor der Kamera aus (kein Vollbild-Blitz).
- **Kugeln als MultiMesh** (`maze_view.gd`): eine Instanz je Kugel, gegessen
  = Nullgröße. Manhattan bleibt pixelgleich (Vergleich mit
  `qa_explorer_shots.gd`: 0 abweichende Pixel).
- **Komfort:** „Regen reduzieren“ (Settings v4, neben „Effekte reduzieren“
  in derselben Zeile des Komfort-Blocks): 35 % der Tropfen, Helligkeit 0,6;
  „Effekte reduzieren“ allein: 70 %, 0,8; beide: 35 %, 0,5.

## 5. Meilensteine

| | Inhalt | Status |
|---|---|---|
| **M1** (ca. 2 Wochen) | Explorer-Code allgemein; Shibuya-Gitter mit offenem Kreuzungsfeld, U-Bahn-Ausgang, Kugelspuren; Linien-Builder ins Spiel; Font gebündelt; Tokyo im einfachen Linien-Look spielbar (nasser Boden über Roughness, ruhiger Nachthimmel) | **umgesetzt** (03.10.2026) |
| **M2** (ca. 2–3 Wochen) | Boden von A mit SSR-Feinschliff und vorgebackener Pfützenmaske (≤ 8 Lichtpfützen); Regen im Shader (≤ 8.000, lichter über Kugeln, „Regen reduzieren“); Scramble mit Ampelphasen; Passanten und Autos als MultiMesh mit Shader-Animation (Schirme, Scheinwerfer weiß vorn/rot hinten); Halos und Lichtkegel als MultiMesh; Kugeln als MultiMesh; danach Performance-Messung und QA-Playtest | **umgesetzt** (03.10.2026; Performance-Messung auf Hardware und QA-Playtest offen) |
| **M3** (1–2 h Studio-Zeit; Engpass Hardware-Abnahme – M1+M2 dauerten ≈ 2,5 h statt der geschätzten 4–5 Wochen) | Feinschliff, Übergang Neon → Matrix-ASCII beim U-Bahn-Abstieg, Capsule mit Titelschrift (Kugelreihe groß im Vordergrund), Rechtsprüfung Gebäudeformen/Schilder, Reviews | offen |

## 6. Tests

- `godot/tests/test_tokyo.gd`: Gitter zusammenhängend, Rand geschlossen, Layout ohne
  Lücken; U-Bahn erreichbar und in der Bahnhofsfassade; Kreuzungsfeld offen (7 × 7);
  Kugelspuren als ununterbrochene Linien zur U-Bahn; Draw-Call- und Lichtbudget
  der Statik; Sockellinie = Kollisionsfläche (auf 1 mm) und deckt die ganze
  Straßenkante ab; Determinismus (gleicher Seed → gleiche Stadt, anderer Seed →
  andere Dekoration, gleiche Kollision); Palette und Lesbarkeitsregeln; keine Marken.
- `godot/tests/test_tokyo_life.gd` (M2): sechs MultiMeshes, Regen ≤ 8.000 und
  Bewegung im Shader, 25–30 Passanten + Welle ≥ 100, Gang über INSTANCE_CUSTOM,
  Passanten ~50 % der Gebäudelinien auf dem Bildschirm, U-Bahn-Puls < 3 Hz;
  **Draw Calls gesamt ≤ 32 und additiv ≤ 20**; Kugel-MultiMesh; Pfützenmaske
  gebacken und seed-abhängig, Roughness-Maske, ≤ 8 Lichter; Spiegelung nur ohne
  SSR; Regen lichter über Kugeln; Komfort-Optionen; **keine neuen Objekte,
  Ressourcen, Knoten in 600 Frames**; Determinismus mit dem Seed;
  **Scramble-Phasen** (Verkehr fließt, All Walk nach ~24 s, Ton-Signal, beide
  Richtungen rot, Autos halten, Welle ≥ 100 quert gerade und diagonal, Feld beim
  Phasenende frei, danach wieder Verkehr); Autos halten vor dem Spieler.
- `godot/tests/bot_test.gd`: Explorer-Auswahl am Startscreen, Tokyo-Lauf (HUD, keine
  Geister, Spieler stoppt physikalisch an der Fassade, Kugeln ohne Punkte, NEUSTART),
  M2 in Main (bewegte Stadt mit Level-Seed, Auto als Hindernis, Passanten harmlos,
  „Regen reduzieren“ gespeichert und synchron, „Effekte reduzieren“ dämpft den
  Regen, Ton zum All Walk), U-Bahn → Speedrun mit **Theme-Reset** (Glow, SSR,
  Volumetrik, Tonemap, Lampe, Sichtweite; Regen und Verkehr abgeräumt).
- `godot/tests/test_city_themes.gd`: Speedrun und Manhattan behalten die Standardwerte.
- `godot/tests/test_audio_synth.gd`: Fußgängerton vorhanden und kurz.
- Manhattan unverändert: alle bisherigen Tests plus Pixelvergleich mit
  `tools/qa/qa_explorer_shots.gd` (`SHOT_SET=manhattan`, deterministisch).
- Art-Abnahme: `tools/qa/qa_explorer_shots.gd` (Totale im Verkehr und im Scramble,
  Straßenblick mit Regen, „Regen reduzieren“, U-Bahn, Gasse, Scramble in Augenhöhe).

## 7. Offene Punkte

- Performance-Ziel vom Inhaber bestätigen lassen; **Messung auf GTX-1660-Klasse
  mit M2** (Forward+, SSR, Regen, Verkehr) steht aus.
- SSR-Wirkung, echtes Glow und die Forward+-Kosten sind in der Sandbox nicht
  sichtbar (nur Compatibility-Renderer). Die Abnahme dort zeigt die Spiegelung
  ohne SSR; der nasse Boden in Forward+ (SSR + gedämpfte Streifen,
  `fake_refl` 0,45) muss auf echter Hardware abgenommen werden.
- Die Spiegelung ohne SSR ist eine Bildschirm-Näherung: nahe, niedrige Objekte
  (Kugeln, Autos direkt vor der Kamera) spiegeln nicht korrekt; von oben
  (Totale) gibt es kaum Spiegelung.
- Die Scramble-Welle läuft jeden Zyklus gleich (deterministisch, keine
  Variation pro Zyklus); in der Mitte der Diagonalen wird es dicht.
- Gebäudeformen und Schilder auf die Rechtsliste (M3).
- M3: Übergang Neon → ASCII beim U-Bahn-Abstieg, Capsule, Reviews.
