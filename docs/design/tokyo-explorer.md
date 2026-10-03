# Spezifikation: Explorer-Stadt Tokyo („Natriumregen“)

**Stand:** 03.10.2026 · v1 (M1 umgesetzt auf `feature/tokyo-explorer`)
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
| Scheinwerfer / Rücklicht | `#FFFFFF` / `#FF2A1A` | nur Verkehr (M2) |
| Passanten | `#A49A8C` | ~50 % Helligkeit (M2) |

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
5. Passanten ~50 % Helligkeit (M2), Helligkeit nach oben auf ~30 %.
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

- **Draw Calls der Statik ≤ 20** (M1: Wand-MultiMesh, Boden, 4 Linienfarben, Masse,
  Fahrbahnfarbe, Ladenfronten, 2 Screens, 6 Schriftzüge). Kugeln zählen nicht dazu
  (dynamisch; Umstellung auf MultiMesh ist M2).
- **Lichter ≤ 10** in der Szene (8 Laternen, 2 Screens) plus U-Bahn und Spielerlampe.
- Linien-Röhren: M1 ~1.900 Segmente (ca. 15.000 Vertices) in 4 Meshes.

### 4.4 Performance-Ziel

**Vorläufig 60 fps bei 1080p auf GTX-1660-Klasse** (vom Studio Head gesetzt,
Bestätigung durch den Inhaber offen). Erwartete Mehrlast ggü. Manhattan laut
code-reviewer 3–5 ms GPU mit Regen und SSR. Messung mit M2 (Regen, SSR,
Passanten) auf echter Hardware; die Sandbox rendert nur im Software-Renderer
(Compatibility, ohne SSR) und kann das Ziel nicht belegen.

## 5. Meilensteine

| | Inhalt | Status |
|---|---|---|
| **M1** (ca. 2 Wochen) | Explorer-Code allgemein; Shibuya-Gitter mit offenem Kreuzungsfeld, U-Bahn-Ausgang, Kugelspuren; Linien-Builder ins Spiel; Font gebündelt; Tokyo im einfachen Linien-Look spielbar (nasser Boden über Roughness, ruhiger Nachthimmel) | **umgesetzt** (03.10.2026) |
| **M2** (ca. 2–3 Wochen) | Boden von A mit SSR-Feinschliff und vorgebackener Pfützenmaske (≤ 8 Lichtpfützen); Regen im Shader (≤ 8.000, lichter über Kugeln, „Regen reduzieren“); Scramble mit Ampelphasen; Passanten und Autos als MultiMesh mit Shader-Animation (Schirme, Scheinwerfer weiß vorn/rot hinten); Halos und Lichtkegel als MultiMesh; Kugeln als MultiMesh; danach Performance-Messung und QA-Playtest | offen |
| **M3** (ca. 1–2 Wochen) | Feinschliff, Übergang Neon → Matrix-ASCII beim U-Bahn-Abstieg, Capsule mit Titelschrift (Kugelreihe groß im Vordergrund), Rechtsprüfung Gebäudeformen/Schilder, Reviews | offen |

## 6. Tests

- `godot/tests/test_tokyo.gd`: Gitter zusammenhängend, Rand geschlossen, Layout ohne
  Lücken; U-Bahn erreichbar und in der Bahnhofsfassade; Kreuzungsfeld offen (7 × 7);
  Kugelspuren als ununterbrochene Linien zur U-Bahn; Draw-Call- und Lichtbudget;
  Sockellinie = Kollisionsfläche (auf 1 mm) und deckt die ganze Straßenkante ab;
  Determinismus (gleicher Seed → gleiche Stadt, anderer Seed → andere Dekoration,
  gleiche Kollision); Palette und Lesbarkeitsregeln; keine Marken.
- `godot/tests/bot_test.gd`: Explorer-Auswahl am Startscreen, Tokyo-Lauf (HUD, keine
  Geister, Spieler stoppt physikalisch an der Fassade, Kugeln ohne Punkte, NEUSTART),
  U-Bahn → Speedrun mit **Theme-Reset** (Glow, SSR, Volumetrik, Tonemap, Lampe, Sichtweite).
- `godot/tests/test_city_themes.gd`: Speedrun und Manhattan behalten die Standardwerte.
- Manhattan unverändert: alle bisherigen Tests plus Pixelvergleich mit
  `tools/qa/qa_explorer_shots.gd` (`SHOT_SET=manhattan`, deterministisch).

## 7. Offene Punkte

- Performance-Ziel vom Inhaber bestätigen lassen; Messung auf GTX-1660-Klasse mit M2.
- SSR-Wirkung ist in der Sandbox nicht sichtbar (Compatibility-Renderer); erste
  Abnahme des nassen Bodens auf echter Hardware.
- Gebäudeformen und Schilder auf die Rechtsliste (M3).
- Tokyo hat noch keinen Verkehr und keine Passanten (M2); bis dahin ist die Stadt leer.
