# Explorer-Stadt Arles – Spezifikation v1

**Stand:** 05.10.2026, nach den Reviews (game-designer, ux-reviewer, code-reviewer, qa-playtester) · **Freigabe:** Inhaber, E19/E23 (04.10.2026) – Richtung B v2 „Sternennacht, echte Orte stilisiert“, Hauptlook **tiefe Nacht**, alle Empfehlungen des Art Directors angenommen (Vorlage `studio/projekte/zapmaniac/art/explorer-stile-v1.md`, Abschnitte B und B v2; Prototyp `tools/art/explorer_proto/arles_v2/` auf Branch `art/explorer-stile`) · **Branch:** `feature/explorer-arles`

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

- **Weg zum Ausgang an den Highlights vorbei:** Calade → République (Portal, Hôtel de Ville) → Rue de l'Hôtel de Ville frontal auf die Caféterrasse → **über die Nordseite der Place du Forum an der Terrasse entlang** (Reihe 17, die Tische stehen auf den Reihen 15–16; GD W3) → an den römischen Säulen in der Nordwest-Ecke vorbei (Spalte 8) → Rue du Forum zur Rhône → 34 m am Kai mit den Spiegelungen → Place Lamartine → grüne Tür. **73 Zellen = 146 m ≈ 33 s**; der kürzeste Weg überhaupt ist 65 Zellen – der Umweg am Café (8 Zellen) ist gewollt (Test: ≤ 10 Zellen länger). (Die Review nannte Reihe 16; dort stehen die Terrassentische, die Linie liegt deshalb eine Reihe südlich, 0,5 m frei von allen Kollisionsboxen; die nordwestliche Platane rückte dafür 2,6 m nach Süden.)
- **Kugelspur:** BFS vom Ausgang über die Straßen-Mittellinien, zurückgegangen vom Start, Pflicht-Äste **Thermen-Gasse** und **Arena-Ring (immer ganz, `MUST_LINES`)**, dazu zwei vom Level-Seed (1888) gewählte Äste. **Hauptweg dicht, Abstecher gepunktet (GD W4a):** der Weg vom Start zur Tür trägt auf jeder Zelle eine Kugel, Äste, die nicht darauf liegen, nur auf jeder zweiten (vom Ast-Ende gezählt, das Ende hat immer eine Kugel; `dotted_trails()`). Seed 1888: 130 Kugeln. Jede Straße endet auf einem Wahrzeichen oder der Rhône (Test).
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

- **Himmel gebacken (Auflage):** `arles_root.gd` rendert `arles_sky_bake.gdshader` (Line Integral Convolution über ein Wirbelfeld mit acht Vortizes) einmal in eine 2048 × 1024-SubViewport (`UPDATE_ONCE`), liest sie mit Mipmaps zurück und gibt die Viewport frei. Die fertige Textur bleibt für die Sitzung im statischen Cache (`ArlesRoot.baked_sky`); jeder weitere Arles-Start liest sie, ohne neu zu backen (`sky_state` „cached“). Das Zurücklesen hängt als One-Shot-Verbindung an `RenderingServer.frame_post_draw` (kein `await`; prüft `is_inside_tree()`, damit eine sofort wieder freigegebene Stadt nichts zurücklässt; Code W3). **Ringsum nahtlos:** Feld und Rauschen sind in x periodisch. Laufzeit: Flowmap mit drei Textur-Abtastungen, kein Rauschen, keine Schleife; Drift 0,04 Phase/s. `ARLES_SKY_SAVE=<png>` speichert den Bake (QA).
- **Strich-LOD (Auflage):** zwischen 14 und 28 m und überall, wo ein Strich unter ≈ 3 Pixel fällt, wird Impasto zu großen, weichen Tupfern niedriger Frequenz (keine flache Mittelfarbe). Gilt für Fassaden, Objekte, Arkaden, Boden und Wasser.
- **Strich-Komfort nah an der Kamera (UX W-F):** unter 6 m wird die Helligkeitsamplitude der Striche um den lokalen Mittelwert leicht begrenzt (80 %), mit „Effekte reduzieren“ halbiert (50 %); das Relief folgt mit (`near_amp()` in `arles_common.gdshaderinc`, jeder Pinsel-Shader übergibt sie an `impasto()`).
- **Ableitungen in uniformem Kontrollfluss (Code W5):** `fwidth` für das Fensterraster der Fassade steht vor der Dach-/Wand-Verzweigung, in den Arkaden vor dem `discard`.
- **Rhône (Code H4):** die Spiegelsäulen-Schleife bricht je Laterne früh ab, wenn der Azimut weiter als 0,2 rad oder die Höhe außerhalb der Säule liegt – vor Rauschen und Exponentialfunktionen.
- **Licht (Auflage ≤ 7–8 Omni ohne Schatten):** Mond (Directional, ohne Schatten) + 6 Omni in der Stadt (Café, Statue, Portal, Arena, 2 × Kai) + 1 grünes am Ausgang = **7**. Alle übrigen Laternen und alle Fenster beleuchten Wände und Boden als **gemalte Lichtpfützen** im Shader. **Kachel-Liste:** pro 4-m-Kachel nur die nächsten 8 von 41 Laternen (`lamp_tex` = Positionen, `tile_tex` = Indizes; `arles_common.gdshaderinc`), statt 48 je Pixel im Prototyp.
- **Halo-MultiMesh (Auflage):** eine MultiMesh für alle Halos der Stadt; Halos blenden vor der Kamera aus (2,5–7 m, kein Vollbild-Blitz) und ignorieren den Nebel. Der grüne Stern gehört zum Ausgangsknoten (eigene Ein-Instanz-MultiMesh mit demselben Shader), damit sein Puls am Ausgang hängt.
- **Ruhiger Boden (Auflage):** Pflasterstrich längs der Straße, Kontrast etwa halbiert, Ocker-Akzent 7 %, dunkler Rinnstein exakt auf der Blockkante (= Kollision), heller Bordstreifen daneben; auf der Place du Forum kreisen die Striche um die Caféterrasse.
- **Wahrzeichen-Stein** mit leichtem Eigenleuchten (gemaltes Mondlicht): helle Massen vor dem dunklen Himmel. Bäume und Passanten ebenso leicht aufgehellt (Passanten heller als Pflaster und Fassaden, Auflage).
- **Farbregeln (Tests):** Zinnober `#FF4A1C` nur die Kugeln (`arles_orb.gdshader`: **Objekt statt Licht**, UX W-E – Kern höchstens `#FF7A50`, Glow-Anteil halbiert (`glow_share` 0,5), kräftige dunkle Kontur `#3A0E06`; CVD-Simulation der QA-Bilder siehe Abschnitt Tests); Minzgrün `#3AF5C8` nur der Ausgang (Tür, Läden, Stern, Licht); Halo-Ränder und Spiegelungen Gold `#D4A03A`, nicht Orange; Ocker-Fassaden selten (2 von 10 Grundstücken, Protanopie), Sockel immer abgedunkelt; Zypressen fast schwarz, Platanen blau. Keine Weltfarbe liegt näher als ΔOKLab 0,15 an Zinnober oder Minzgrün.
- **Kollision lesbar:** Die Wand-MultiMesh ist reine Physik (`walls_visible = false`, Boxen 3 m). Häuser stehen genau auf den Zellkanten; die Arena steht auf einem Sockel über dem ganzen Block; Thermen und Türme bleiben in ihren Blöcken. Was unter Augenhöhe in eine Straße ragt (Laternen, Bäume, Zypressen, Caféterrasse, Säulen, Statue, Obelisk, Portalstufen, Passanten, Karren), bekommt automatisch eine Kollisionsbox (`Obstacles`, 61 Boxen, Wandebene); Test: nichts davon liegt auf einer Kugel oder 0,5 m am Weg.
- **Minimap:** dunkle Straßen, Blöcke Lavendel auf 55 % Helligkeit (HSV-Wert; UX N-D, Kontrast weiter ≥ 3 : 1), die Kaibrüstung als Wasser, Kugeln Zinnober mit dunklem Ring (`CityTheme.minimap_pellet_outline`), Spielerpfeil weiß mit schwarzem Rand, Ausgang als Minzgrün-Ring mit dunklem Rand und 0,5-Hz-Puls (aus mit „Effekte reduzieren“; UX K-A, alle Explorer-Städte).
- **Schrift:** keine in der Stadt (kein Café-Name, kein Schild, keine Gedenktafel, kein Museumsname, keine Ziffern auf der Uhr). Keine Fonts, keine Texturen, kein Fremdmaterial – daher kein Eintrag in `docs/art/lizenzen.md`.
- **Ton:** keine Geister-Sirene (`siren: false`).

## Ausgang (`arles_exit.gd`)

Das **Gelbe Haus** (historisch rekonstruiert: zwei Geschosse, Ocker-Gelb, Walmdach) frontal vom Platz; **grüne Tür** und **grüne Fensterläden** in Minzgrün, darüber ein **grüner Stern** (Halo 7 m, 18 m hoch) – von überall über den Dächern sichtbar. Grünes Licht vor der Tür. Puls 0,5 Hz (Tür, Läden, Stern, Licht); „Effekte reduzieren“ hält ihn an und beruhigt auch den Pinsel des Hauses (Code H2). Auslöseradius 1,3 m; ab 12 m einmal „Grüne Tür: hinein in den Speedrun“ (GD W6; weg, sobald das Banner kommt). Banner **„HINTER DER TÜR: SPEEDRUN“ / „Hinein – los zum Speedrun!“** (UX N-C). Einmaliger Start-Hinweis **„Folge den Kugeln zur grünen Tür“**, auch mit „Effekte reduzieren“ (UX W-D, QA W1). Startscreen-Beschreibung: „Arles – gemalte Sternennacht, bewegter Himmel“.

## Komfort

„Effekte reduzieren“ (Main → `ArlesRoot.set_reduce_fx`, `ArlesExit.set_reduce_fx`): Himmel steht, Rhône zittert nicht, Pinsel ruhiger (Relief halbiert, mehr Tupfer, Boden noch ruhiger, Striche nah an der Kamera mit halber Helligkeitsamplitude), auch am Gelben Haus; Ausgangspuls und Minimap-Puls aus. Kein Headbob, keine Kamera-Manipulation, kein Flackern über 0,5 Hz.

## Passanten und bewegte Pinselstriche (Abnahme 06.10.2026)

**Passanten** (`arles_life.gd`, Shader `arles_walker.gdshader`): 31 abendliche Gestalten in Mantel und Hut (auch Kappe oder bloßer Kopf), mit demselben Impasto-Pinsel gemalt wie die Stadt; die Striche haften am Körper (Figurenraum), laufen also mit. Sie schlendern langsam (0,5–0,9 m/s, Schritt ≤ 1 Hz) auf Gassen-Schleifen (hin und zurück, 0,9 m Gangbreite), Paare nebeneinander am Kai und am Kreis um das Mistral-Denkmal, einige um den Arena-Ring. Die statischen Figuren der Café-Szene (`FIGURES`) bleiben stehen. Harmlos: kein Leben-Verlust, nur der sanfte Schubs (Radius 0,35 m) wie in Tokyo über Main; Kamera und Maus bleiben unberührt. Eine MultiMesh (ein Draw Call), Gang im Shader (Füße, Mantelsaum, Arme), keine Allokation pro Frame, deterministisch je Seed. Alle Wege halten 0,85 m Abstand zu Wänden, 0,5 m zu jedem Hindernis, 3 m zu Start und Ausgangstür (Test). „Effekte reduzieren“ lässt sie stehen.

**Wabern der Pinselstriche** (`arles_common.gdshaderinc`, `impasto()`): jede Strichreihe gleitet langsam entlang ihrer Strichrichtung, höchstens 5 % der Strichlänge (Fassade ≈ 3,7 cm), als Welle über die Reihen (0,08 Hz). Eine Impasto-Auswertung (keine zweite Schicht, kein Geisterbild, kaum Mehrkosten: ein `sin`, ein Hash). Es blendet mit dem Strich-LOD aus (`1 - lod`): die weichen Fern-Tupfer bewegen sich nie, daher keine Kantenflimmer-Gefahr. Fassaden, Dächer, Objekte, Arkaden und Passanten voll, der Boden mit halber Stärke, die Rhône gar nicht (hat ihr eigenes Zittern), Fenster-Raster, Sockel und Gesims stehen fest. `moving = 0` (Effekte reduzieren) stoppt es überall.

## Technik und Budget

- **Draw Calls (statisch, Test ≤ 9):** Boden, Houses, Objects, Arcades, Tympanum, Rhône, Sky, Halos = 8, plus die Passanten (eine MultiMesh) = 9. Dazu Kugeln (eine MultiMesh) und der Ausgang (Haus, Tür, Läden, Stern).
- **Geometrie (Test):** Objects ≈ 36 000 Vertices (≤ 60 000), Houses ≈ 27 500 (≤ 40 000).
- **Gemeinsame Dateien:** `city_themes.gd` (`arles()`), `explorer_cities.gd` (Eintrag `arles`), `city_theme.gd` (Feld `minimap_pellet_outline`), `hud.gd` (Kugel-Ring auf der Minimap, 3 Zeilen). `main.gd` nur um den Passanten-Aufruf und den sanften Schubs erweitert (6 Zeilen, wie Tokyo), `maze_view.gd` unverändert. Startscreen: fünf Städte passen in eine Zeile (Screenshot `r1_start.png`).
- **Compatibility (alle QA-Bilder, Software-GL unter xvfb):** läuft fehlerfrei und sieht dem Prototyp sehr nahe (Glow an). **Forward+** war in der Sandbox nicht startbar: Glow und die 7 Omni-Lichter sind dort weicher; GI/SSAO braucht der gemalte Look nicht. **Abnahme auf echter Hardware steht aus** (60 fps bei 1080p, GTX-1660-Klasse): Flimmern der Striche in Bewegung, Übelkeits-Check des Himmels, Kosten der Lichtpfützen (jetzt 8 statt 48 Laternen je Pixel). Hebel: `lod_near/lod_far` kleiner, `TILE_LAMPS` 8 → 4, Glow aus, Halo-Zahl der Sterne.

## Tests

- `godot/tests/test_arles.gd` (123 Checks; neu in der Abnahme 06.10.: Passanten vorhanden und deterministisch, ein Draw Call, freie Wege (400 s gegen Wände, Hindernisse, Start, Ausgang, einander), langsam, harmlos, keine Allokation in 600 Frames, stehen mit „Effekte reduzieren“; Wabern: Uniform `moving`, LOD-Ausblendung, 5 % / 0,08 Hz, Boden halb, Rhône aus, an/aus; nach den Reviews: Weg an der Caféterrasse und den Säulen, Umweg ≤ 10 Zellen, Ring und Gasse gepunktet, Abstecher gepunktet/Hauptweg dicht, Strich-Amplitude nah, fwidth-Lage, Rhône-Abbruch, Kugel-Shader, Banner/Hinweis, Minimap-Blöcke 55 %, Haus-Pinsel ruhig, Himmel-Cache und sofortige Freigabe; bisher: Raster (41 × 45, geschlossen, 790 Zellen erreichbar, Kai, Tor), Blickpunkte an allen Straßenenden, Route (Reihenfolge der Straßen, Wahrzeichen am Weg, Kai-Strecke, Länge), Spuren (deterministisch, Mittellinien, Pflicht-Äste, Arena-Ring ganz), Budget (Draw Calls, Vertices, eine Halo-MultiMesh), Licht (6 + 1 Omni, Mond, keine Schatten), keine Schrift, Kollision (Wandboxen 3 m, Hindernisse für alles in der Straße, nichts auf Kugeln/Weg, jede Wahrzeichen-Zelle an der Straße bebaut), Himmel gebacken (2048 × 1024, einmal, nahtlos, Laufzeit ohne Rauschen/Schleife, Drift 0,04), Strich-LOD, Lichtpfützen-Kachelliste, ruhiger Boden, Halos ohne Blitz, Komfort, Theme/Registry („Van Gogh“ nie im Titel), Minimap-Kontraste, Exklusivfarben, Gold-Ränder, Ocker selten, Ausgang (Grün, Tür bündig, Stern hoch, Haus ragt nicht in den Platz, Puls, Effekte reduzieren)).
- `godot/tests/bot_test.gd`: Start über den ARLES-Button, Minimap-Ausgang, Glow und Himmel, „Effekte reduzieren“ stoppt Himmel und Puls, grüne Tür → Speedrun, Theme-Reset (kein Glow, kein Mond, keine Lampen).
- Screenshots: `tools/qa/qa_arles_shots.gd` (r1–r20; neu: r16–r18 Passanten, r19/r20 Wabern gegen „Effekte reduzieren“; vorher r13 Weg an der Caféterrasse, r14 Kugeln nah, r15 gepunkteter Abstecher am Arena-Ring; Ansichten wie im Prototyp; die Totale r10 mit eigener QA-Kamera, die Spielkamera bleibt unberührt; `ONLY=r3,r8` rendert einzelne Bilder).

## Rechte (Kurzfassung, keine Rechtsberatung)

Alle Bauwerke gemeinfrei (Urheber länger als 70 Jahre tot); Frankreichs Panoramafreiheit gilt für uns nicht, deshalb keine jüngeren Bauten. Café und Hotel nicht als heutiger Betrieb erkennbar (keine Namen, Schilder, Markisenaufdrucke, Logos). Kein Stierkampf-Bezug an der Arena. Sakralort Saint-Trophime: keine Gewalt, keine Zerstörung, kein Gag; Tympanon nur angedeutet. „Van Gogh“ bleibt EU-Marke → nur beschreibend. ⚖️ vor der Steam-Seite: INPI-Kurzcheck „Café Van Gogh“/„Café la Nuit“ (wir nennen sie nicht) und „Arles“ in einer Store-Überschrift.

## Offen

- Hardware-Abnahme Forward+ (siehe oben) – 30–60 min Inhaber.
- Leben in Bewegung (Passanten, Karren stehen still), Capsule-Bilder, Variante „blaue Stunde“ für Store-Bilder.
- Reviews umgesetzt (05.10.2026). Bewusst **nicht** umgesetzt (Inhaber-Entscheidungen bzw. später): Grüntöne der Ausgänge vereinheitlichen (UX W-A), Explorer-Tempo 3,1 m/s (GD W2), Ton je Stadt (GD W5), Rundgang der Woche bzw. Sammelziel (GD W7), Startscreen-Reihenfolge und Vorschaubilder (GD W9), Stretch-Aspect „expand“ (UX W-G), gemeinsame Helfer statt Kopien (Code W7, z. B. `dotted_trails()` in Amsterdam und Arles), Passanten in Hauseingängen (GD N3), Kollisionsbox-Volumen-Test (UX N-F).
