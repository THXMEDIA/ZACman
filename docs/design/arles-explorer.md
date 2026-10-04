# Explorer-Stadt Arles – Spezifikation v1

**Stand:** 05.10.2026 · **Freigabe:** Inhaber, E19/E23 (04.10.2026) – Richtung B v2 „Sternennacht, echte Orte stilisiert“, Hauptlook **tiefe Nacht**, alle Empfehlungen des Art Directors angenommen (Vorlage `studio/projekte/zapmaniac/art/explorer-stile-v1.md`, Abschnitte B und B v2; Prototyp `tools/art/explorer_proto/arles_v2/` auf Branch `art/explorer-stile`) · **Branch:** `feature/explorer-arles`

## Idee

Die ganze Stadt ist gemalt: ein Wirbelhimmel aus Strömungslinien in Ultramarin und Kobalt, kurze Impasto-Striche auf jeder Fläche, deren Richtung der Form folgt, Gaslaternen und Sterne als Halo-Scheiben, eine gelbe Caféterrasse als warmer Fixpunkt. Echte Orte von Arles, stilisiert und frei angeordnet, damit jede Straße auf ein Wahrzeichen zuläuft. „Van Gogh“ ist nur ein beschreibendes Stilwort, nie ein Titel; keine Gemälde-Komposition wird 1:1 nachgebaut (das Café wird frontal von Süden gesehen, nicht aus dem Blickwinkel des Gemäldes; kein Dorf mit Kirchturm unter dem Wirbel). Die Kamera wird nie bewegt (E8e), kein Headbob.

## Karte (`godot/scripts/arles_maze.gd`)

41 × 45 Zellen à 2 m (82 × 90 m), übernommen aus `karte.json` des Art Directors. 790 Straßenzellen, alle erreichbar. Kartenraum = Welt + (1, 0, 1) (Koordinaten des Prototyps; Zelle (r, c) liegt bei x 2c…2c+2, z 2r…2r+2).

| Straße | Verlauf | Blickpunkt am Ende |
|---|---|---|
| Rue de la Calade | Ost–West, **Start** am Ostende (35, 32), Blick nach Westen | Ost: Théâtre antique (im Rücken) · West: über den Platz auf das Hôtel de Ville mit Uhrturm |
| Place de la République | Platz | Süd: Portal von Saint-Trophime · Obelisk mit Brunnen · Pferdekarren |
| Rue de l'Hôtel de Ville | Nord–Süd | Nord: frontal auf die Caféterrasse · Süd: Portal |
| Place du Forum | Platz | Nord: Caféterrasse (gelbe Wand, Markise, große Laterne, Gäste) · NW-Ecke: zwei römische Säulen in der Hausecke · Mitte: Mistral-Denkmal · Platanen |
| Rue du Forum | Ost–West | Ost: Arena mit Westturm · West: die Rhône über die Brüstung |
| Quai (Rhône) | Nord–Süd an der Brüstung | Süd: Grand Prieuré · Nord: Place Lamartine mit grünem Stern |
| Seitengasse | Ost–West | Thermen-Apsis (Ziegel- und Steinbänder) |
| Place Lamartine | Platz | Nord: **Gelbes Haus = Ausgang** (Zelle (1, 7)) · Ost: Porte de la Cavalerie · Zypressen |
| Rue de la Cavalerie | Nord–Süd | Nord: Mauerturm |
| Rond-point des Arènes | Ring um die Arena | Arena immer zur Seite (Rundweg) |

- **Weg zum Ausgang an den Highlights vorbei:** Calade → République (Portal, Hôtel de Ville) → Rue de l'Hôtel de Ville frontal auf die Caféterrasse → Place du Forum (beim Queren der Rue du Forum steht die Arena im Osten) → Rue du Forum zur Rhône → 34 m am Kai mit den Spiegelungen → Place Lamartine → grüne Tür. **67 Zellen = 134 m ≈ 30 s**; der kürzeste Weg überhaupt ist 65 Zellen. (Der Prototyp nannte „50 m am Kai“; gemessen sind es 17 Zellen auf der Kaistraße.)
- **Kugelspur:** BFS vom Ausgang über die Straßen-Mittellinien, zurückgegangen vom Start, Pflicht-Äste **Thermen-Gasse** und **Arena-Ring (immer ganz, `MUST_LINES`)**, dazu zwei vom Level-Seed (1888) gewählte Äste. Seed 1888: 180 Kugeln. Jede Straße endet auf einem Wahrzeichen oder der Rhône (Test).
- **Nicht in der Stadt:** Pont de Langlois, Alyscamps (Inhaber).

## Look (`arles_style.gd`, `arles_scenery.gd`, Shader `arles_*`)

Portierung des Prototyps `arles_v2` (`city.gd`, `shaders.gd`) in Spielcode, zusammengefasst auf wenige Draw Calls:

| Teil | Inhalt | Shader |
|---|---|---|
| Houses (1 Mesh) | alle Häuser des Rasters (Satteldächer je 6 × 6-m-Grundstück, Traufe 7–11,5 m), Nachbarhäuser der Wahrzeichen, die Stadt ringsum, das andere Ufer | `arles_facade` – Fenster, offene/geschlossene Läden, erleuchtete Läden im EG, Türen, dunkler Sockel (= Kollisionskante), Gesims, gemalter Lichthof um erleuchtete Fenster; Fensterraster wird bei streifendem Blick gemittelt |
| Objects (1 Mesh) | Wahrzeichen, Laternen, Café, Tische, Figuren, Bäume, Zypressen, Kai, Brücke, Boote, Ferne (Viadukt, Montmajour, Alpilles) | `arles_obj` – Pinselmaterial je Teil über UV2.x (Tabelle `ArlesStyle.MATS`, 43 Materialien, Uniform-Arrays) |
| Arcades | Außenschale der Arena, 28 Bögen je Geschoss im Shader ausgeschnitten, dahinter das dunkle Gewölbe | `arles_arcade` |
| Tympanum | Saint-Trophime: Mandorla und vier Felder nur als Relief-Andeutung, keine Figuren | `arles_tympanon` |
| Rhône | dunkle Striche, 25 Laternen als in Striche gebrochene Säulen gespiegelt (Kern Gelb, Rand **Gold**) | `arles_water` |
| Sky | Wirbelhimmel, beim Levelaufbau gebacken | `arles_sky_bake` → `arles_sky` |
| Halos (1 MultiMesh) | 81 Halos: 41 Laternen + Café-Laterne, anderes Ufer, Brücke, 22 Sterne ringsum, Mond | `arles_halo` |

- **Himmel gebacken (Auflage):** `arles_root.gd` rendert `arles_sky_bake.gdshader` (Line Integral Convolution über ein Wirbelfeld mit acht Vortizes) einmal in eine 2048 × 1024-SubViewport (`UPDATE_ONCE`), liest sie mit Mipmaps zurück und gibt die Viewport frei. **Ringsum nahtlos:** Feld und Rauschen sind in x periodisch. Laufzeit: Flowmap mit drei Textur-Abtastungen, kein Rauschen, keine Schleife; Drift 0,04 Phase/s. `ARLES_SKY_SAVE=<png>` speichert den Bake (QA).
- **Strich-LOD (Auflage):** zwischen 14 und 28 m und überall, wo ein Strich unter ≈ 3 Pixel fällt, wird Impasto zu großen, weichen Tupfern niedriger Frequenz (keine flache Mittelfarbe). Gilt für Fassaden, Objekte, Arkaden, Boden und Wasser.
- **Licht (Auflage ≤ 7–8 Omni ohne Schatten):** Mond (Directional, ohne Schatten) + 6 Omni in der Stadt (Café, Statue, Portal, Arena, 2 × Kai) + 1 grünes am Ausgang = **7**. Alle übrigen Laternen und alle Fenster beleuchten Wände und Boden als **gemalte Lichtpfützen** im Shader. **Kachel-Liste:** pro 4-m-Kachel nur die nächsten 8 von 41 Laternen (`lamp_tex` = Positionen, `tile_tex` = Indizes; `arles_common.gdshaderinc`), statt 48 je Pixel im Prototyp.
- **Halo-MultiMesh (Auflage):** eine MultiMesh für alle Halos der Stadt; Halos blenden vor der Kamera aus (2,5–7 m, kein Vollbild-Blitz) und ignorieren den Nebel. Der grüne Stern gehört zum Ausgangsknoten (eigene Ein-Instanz-MultiMesh mit demselben Shader), damit sein Puls am Ausgang hängt.
- **Ruhiger Boden (Auflage):** Pflasterstrich längs der Straße, Kontrast etwa halbiert, Ocker-Akzent 7 %, dunkler Rinnstein exakt auf der Blockkante (= Kollision), heller Bordstreifen daneben; auf der Place du Forum kreisen die Striche um die Caféterrasse.
- **Wahrzeichen-Stein** mit leichtem Eigenleuchten (gemaltes Mondlicht): helle Massen vor dem dunklen Himmel. Bäume und Passanten ebenso leicht aufgehellt (Passanten heller als Pflaster und Fassaden, Auflage).
- **Farbregeln (Tests):** Zinnober `#FF4A1C` nur die Kugeln (heller Kern, dunkle Kontur `#3A0E06`, `arles_orb.gdshader`); Minzgrün `#3AF5C8` nur der Ausgang (Tür, Läden, Stern, Licht); Halo-Ränder und Spiegelungen Gold `#D4A03A`, nicht Orange; Ocker-Fassaden selten (2 von 10 Grundstücken, Protanopie), Sockel immer abgedunkelt; Zypressen fast schwarz, Platanen blau. Keine Weltfarbe liegt näher als ΔOKLab 0,15 an Zinnober oder Minzgrün.
- **Kollision lesbar:** Die Wand-MultiMesh ist reine Physik (`walls_visible = false`, Boxen 3 m). Häuser stehen genau auf den Zellkanten; die Arena steht auf einem Sockel über dem ganzen Block; Thermen und Türme bleiben in ihren Blöcken. Was unter Augenhöhe in eine Straße ragt (Laternen, Bäume, Zypressen, Caféterrasse, Säulen, Statue, Obelisk, Portalstufen, Passanten, Karren), bekommt automatisch eine Kollisionsbox (`Obstacles`, 61 Boxen, Wandebene); Test: nichts davon liegt auf einer Kugel oder 0,5 m am Weg.
- **Minimap:** dunkle Straßen, helle Blöcke (Lavendel), die Kaibrüstung als Wasser, Kugeln Zinnober mit dunklem Ring (`CityTheme.minimap_pellet_outline`, neu), Ausgang Minzgrün mit dunklem Rand.
- **Schrift:** keine in der Stadt (kein Café-Name, kein Schild, keine Gedenktafel, kein Museumsname, keine Ziffern auf der Uhr). Keine Fonts, keine Texturen, kein Fremdmaterial – daher kein Eintrag in `docs/art/lizenzen.md`.
- **Ton:** keine Geister-Sirene (`siren: false`).

## Ausgang (`arles_exit.gd`)

Das **Gelbe Haus** (historisch rekonstruiert: zwei Geschosse, Ocker-Gelb, Walmdach) frontal vom Platz; **grüne Tür** und **grüne Fensterläden** in Minzgrün, darüber ein **grüner Stern** (Halo 7 m, 18 m hoch) – von überall über den Dächern sichtbar. Grünes Licht vor der Tür. Puls 0,5 Hz (Tür, Läden, Stern, Licht); „Effekte reduzieren“ hält ihn an. Auslöseradius 1,3 m; ab 4,5 m einmal „Grüne Tür: hinein in den Speedrun“. Banner „DURCH DIE GRÜNE TÜR: SPEEDRUN“ / „Durch die grüne Tür – los zum Speedrun!“. Einmaliger Start-Hinweis: „Die roten Kugeln führen zur grünen Tür. Ruhiger: Esc → Effekte reduzieren“.

## Komfort

„Effekte reduzieren“ (Main → `ArlesRoot.set_reduce_fx`, `ArlesExit.set_reduce_fx`): Himmel steht, Rhône zittert nicht, Pinsel ruhiger (Relief halbiert, mehr Tupfer, Boden noch ruhiger), Ausgangspuls aus. Kein Headbob, keine Kamera-Manipulation, kein Flackern über 0,5 Hz.

## Technik und Budget

- **Draw Calls (statisch, Test ≤ 9):** Boden, Houses, Objects, Arcades, Tympanum, Rhône, Sky, Halos = 8. Dazu Kugeln (eine MultiMesh) und der Ausgang (Haus, Tür, Läden, Stern).
- **Geometrie (Test):** Objects ≈ 36 000 Vertices (≤ 60 000), Houses ≈ 27 500 (≤ 40 000).
- **Gemeinsame Dateien:** `city_themes.gd` (`arles()`), `explorer_cities.gd` (Eintrag `arles`), `city_theme.gd` (Feld `minimap_pellet_outline`), `hud.gd` (Kugel-Ring auf der Minimap, 3 Zeilen). `main.gd` und `maze_view.gd` unverändert. Startscreen: fünf Städte passen in eine Zeile (Screenshot `r1_start.png`).
- **Compatibility (alle QA-Bilder, Software-GL unter xvfb):** läuft fehlerfrei und sieht dem Prototyp sehr nahe (Glow an). **Forward+** war in der Sandbox nicht startbar: Glow und die 7 Omni-Lichter sind dort weicher; GI/SSAO braucht der gemalte Look nicht. **Abnahme auf echter Hardware steht aus** (60 fps bei 1080p, GTX-1660-Klasse): Flimmern der Striche in Bewegung, Übelkeits-Check des Himmels, Kosten der Lichtpfützen (jetzt 8 statt 48 Laternen je Pixel). Hebel: `lod_near/lod_far` kleiner, `TILE_LAMPS` 8 → 4, Glow aus, Halo-Zahl der Sterne.

## Tests

- `godot/tests/test_arles.gd` (83 Checks): Raster (41 × 45, geschlossen, 790 Zellen erreichbar, Kai, Tor), Blickpunkte an allen Straßenenden, Route (Reihenfolge der Straßen, Wahrzeichen am Weg, Kai-Strecke, Länge), Spuren (deterministisch, Mittellinien, Pflicht-Äste, Arena-Ring ganz), Budget (Draw Calls, Vertices, eine Halo-MultiMesh), Licht (6 + 1 Omni, Mond, keine Schatten), keine Schrift, Kollision (Wandboxen 3 m, Hindernisse für alles in der Straße, nichts auf Kugeln/Weg, jede Wahrzeichen-Zelle an der Straße bebaut), Himmel gebacken (2048 × 1024, einmal, nahtlos, Laufzeit ohne Rauschen/Schleife, Drift 0,04), Strich-LOD, Lichtpfützen-Kachelliste, ruhiger Boden, Halos ohne Blitz, Komfort, Theme/Registry („Van Gogh“ nie im Titel), Minimap-Kontraste, Exklusivfarben, Gold-Ränder, Ocker selten, Ausgang (Grün, Tür bündig, Stern hoch, Haus ragt nicht in den Platz, Puls, Effekte reduzieren).
- `godot/tests/bot_test.gd`: Start über den ARLES-Button, Minimap-Ausgang, Glow und Himmel, „Effekte reduzieren“ stoppt Himmel und Puls, grüne Tür → Speedrun, Theme-Reset (kein Glow, kein Mond, keine Lampen).
- Screenshots: `tools/qa/qa_arles_shots.gd` (r1–r12, Ansichten wie im Prototyp; die Totale r10 mit eigener QA-Kamera, die Spielkamera bleibt unberührt; `ONLY=r3,r8` rendert einzelne Bilder).

## Rechte (Kurzfassung, keine Rechtsberatung)

Alle Bauwerke gemeinfrei (Urheber länger als 70 Jahre tot); Frankreichs Panoramafreiheit gilt für uns nicht, deshalb keine jüngeren Bauten. Café und Hotel nicht als heutiger Betrieb erkennbar (keine Namen, Schilder, Markisenaufdrucke, Logos). Kein Stierkampf-Bezug an der Arena. Sakralort Saint-Trophime: keine Gewalt, keine Zerstörung, kein Gag; Tympanon nur angedeutet. „Van Gogh“ bleibt EU-Marke → nur beschreibend. ⚖️ vor der Steam-Seite: INPI-Kurzcheck „Café Van Gogh“/„Café la Nuit“ (wir nennen sie nicht) und „Arles“ in einer Store-Überschrift.

## Offen

- Hardware-Abnahme Forward+ (siehe oben) – 30–60 min Inhaber.
- Leben in Bewegung (Passanten, Karren stehen still), Capsule-Bilder, Variante „blaue Stunde“ für Store-Bilder.
- Reviews (game-designer, ux-reviewer, code-reviewer) auf diesem Branch.
