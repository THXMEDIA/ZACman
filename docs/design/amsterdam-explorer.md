# Explorer-Stadt Amsterdam – Spezifikation v1

**Stand:** 05.10.2026 (nach den Reviews: game-designer, ux-reviewer, code-reviewer, qa-playtester) · **Freigabe:** Inhaber, E21 – Richtung J „Pappmodell Amsterdam 1:100“, **Abendlook** (goldene Stunde, Schreibtischlampe, lange Schatten), alles wie vom Art Director vorgeschlagen (Vorlage `studio/projekte/zapmaniac/art/explorer-stile-v1.md`, Abschnitte J und J v2) · **Branch:** `feature/explorer-amsterdam`

## Idee

Amsterdam ist ein Architekturmodell aus Wellpappe im Maßstab 1:100, erlebt auf Ameisenhöhe: Die Häuser haben echte Größe, das Material ist hundertfach vergrößert. Die Pappe ist 40 cm dick, jede Schnittkante zeigt die Welle als echten Querschnitt, die Grachten sind dunkel lackierter Karton, der Weg ist mit blauen Glaskopf-Stecknadeln abgesteckt. Jenseits der Modellkante liegen Schneidematte, Riesen-Bleistift, Stahllineal und Kaffeebecher auf dem Holztisch. Es ist Abend: eine tiefe, warme Sonne längs der Grachten, die Schreibtischlampe, lange Schatten, der unscharfe Raum dahinter. Die Kamera wird nie bewegt (E8e), es gibt keine Tiefenunschärfe und kein Korn im Spielblick.

## Karte (`godot/scripts/amsterdam_maze.gd`)

49 × 49 Zellen à 2 m. Grachtengürtel als Raster, echte Orte frei angeordnet, damit der Weg zum Ausgang an allen drei Wahrzeichen vorbeiführt (Lehre aus dem Kyoto-Review).

| Ort | Verlauf | Blickpunkt / Rolle |
|---|---|---|
| Damrak (Gracht, Reihen 7–10) | Ost-West, mündet in die Amstel | Nordufer: **Tanzende Häuser** – schiefe Giebelreihe direkt am Wasser |
| Damrak-Kai (Reihen 11–13) | Start, Blick nach Westen | gegenüber die Tanzenden Häuser, am Ende der **Westerkerk-Turm** (auf der Mittellinie) |
| Westermarkt (Spalten 7–9) | Nord-Süd vor der Kirche, quert Keizers- und Prinsengracht und läuft bis an die **Modellkante** (Reihe 47) | Nord: Westerkerk-Front mit Turm, Querschiffgiebeln, Hochfenstern · Süd: die Platte ist ausgeschnitten (Kerbe, Reihe 48 = `cut`), dahinter der **Kaffeebecher mit Bleistift** (Maßstabs-Reveal) |
| Keizersgracht | Ost-West, zwei Kaistraßen, drei Brücken (Westermarkt, West, Ost) | Bäume an beiden Kais |
| Prinsengracht | Ost-West, zwei Kaistraßen; nur am Westermarkt überquerbar | Bäume; der Südkai läuft geradeaus auf die **Magere Brug** |
| Gassen (Spalten 14–15, 25–26) | Querverbindungen Keizers-/Prinsengracht, 4 m breit | – |
| Amstel (Spalten 36–41) | Nord-Süd über die ganze Karte | einzige Querung: **Magere Brug**; Blick nach Norden in den (gedämpften) Raum hinter dem Modell |
| Amstel-Ostufer (Spalten 42–44) | Haltestelle | **Ausgang**: grüne Papp-Tram |

- **Grachten sind Wasser**, keine Wege: Wandzellen (volle 3 m Kollisionsbox), sichtbar als Lack 0,85 m unter der Straße. Die **Kaimauer** ist die Schnittkante der Grundplatte mit echter Wellen-Geometrie – genau dort ist die Kollisionskante.
- **Pflichtweg:** Der Damrak-Kai öffnet sich nur zum Westermarkt (Kirche passieren), die Prinsengracht ist nur dort überquerbar, die Amstel nur über die Magere Brug (Tests). Weg entlang der Nadeln 96 Zellen (192 m, ≈ 44 s bei 4,4 m/s); Seed 2121: 115 Nadeln.
- **Maßstabs-Reveal im Spielblick (GD K1):** Der Westermarkt läuft südlich der Prinsengracht weiter bis an die Modellkante. Dort ist die Grundplatte ausgeschnitten (Zellen (48, 7–9), Art `cut`: keine Platte, kein Haus, kein Wasser; die Wellen-Schnittkante ist die Kollisionskante, darunter die Schneidematte). Einige Meter dahinter steht in der Straßenachse der Kaffeebecher (12 m hoch, r 4,6 m) als Stifteköcher: ein schräg hineingesteckter Bleistift (Ende bei 17 m) und ein stehendes Stahllineal (30 cm = 30 m, Breitseite zur Straße, Oberkante ≈ 30 m) – die Silhouette, die weit über die Dächer ragt. Die Häuser an der Kante (Rechteck x 0–42, z 80–98) haben höchstens 2 Geschosse (Test: Lineal ≥ 10 m über den Dächern am Straßenende, Bleistift über dem Becherrand, Becher mindestens auf Dachhöhe).
- **Start:** Damrak-Kai (12, 28), Blick nach Westen (längster freier Gang; Main dreht dorthin). **Ausgang:** Bahnsteigzelle (32, 44), die Tram steht östlich hinter der Bordsteinkante.
- **Stecknadel-Spuren:** BFS vom Ausgang über die Straßen-Mittellinien, zurückgegangen vom Start, immer vom Kirchenvorplatz (Westermarkt-Nordende) und vom Straßenende an der Modellkante (Becher) als Pflicht-Ästen und zwei vom Level-Seed (2121) gewählten Ästen aus (12, 35), (20, 35), (27, 35), (27, 25). Jeder Seed führt über die Magere Brug (Test).
- **Hauptweg und Abstecher (GD W4a):** Der Weg vom Start zum Ausgang trägt auf jeder Zelle eine Nadel; Abstecher nur auf jeder zweiten Zelle, vom Ast-Ende aus gezählt (das Ende hat immer eine Nadel). Gemeinsame Logik `dotted_trails()` in `amsterdam_maze.gd` und `arles_maze.gd` (Kopie, siehe „Offen“).
- **Blickpunkte der Ast-Enden (GD W1, Test wie in Arles):** jedes Ende schaut auf etwas – Kirchenfront, Becher hinter der Kerbe, die offene Amstel (gegenüber nur Häuser), die Keizersgracht (`VIEW_POINTS`). Gestrichen: (35, 35) (sah über die Amstel die Tram, ohne hinzukommen) und (28, 43) (lief am Ausgang vorbei ins Leere); (31, 25) mitten in der Gasse wurde (27, 25) an der Gassenmündung.

## Look (`amsterdam_style.gd`, `amsterdam_scenery.gd`, Shader `amsterdam_*`)

- **Pappe-PBR mit Fotoscans:** CC0-Kartonscan (Albedo, Normal, Rauheit) in zwei Maßstäben gegen Kachelmuster (`amsterdam_common.gdshaderinc`), darüber prozedural Waschbrett-Rippen der Welle und abgegriffene, hellere Schnittkanten. Flächenkoordinaten aus der Instanzskalierung (Box-UVs in Metern). Alles, was sich mit der Wellenteilung wiederholt, geht ab 22–45 m auf seinen Mittelwert (Moiré-Schutz).
- **Platten-MultiMesh** (eine für die ganze Stadt, ≈ 6 400 Instanzen, 85 Häuser): Fassaden aus Brüstungen, Pfeilern, Stürzen mit **echten Fensteröffnungen** (Laibungen zeigen Liner–Welle–Liner), Fensterkreuze aus Streifen, Türen zurückgesetzt, dunkle Räume dahinter, Brandmauern, Rückwände, Satteldächer, Lastbalken. Dünnste Achse = Pappstärke; Kantenflächen zeichnen die Welle.
- **Giebel** als extrudierte Ausschnitte: Treppen-, Glocken-, Hals- und Spitzgiebel, beim Aufbau zu **einem** Mesh zusammengeführt (mit Bäumen, Brückenwangen, Zifferblättern, Krone, Turmspitze).
- **Tanzende Häuser:** schmale, hohe Häuser am Damrak, Neigung bis ±3,7° (von Haus zu Haus wechselnd) und bis 2° nach vorn übers Wasser, keine Türen zum Wasser; alle anderen Häuser nur bis 0,23° schief.
- **Straßenecken:** Wo zwei Hausreihen an einer Blockecke zusammentreffen, behält die Ost-West-Reihe die Ecke; ihr Eckhaus bekommt zur Querstraße eine zweite Fassade mit Fenstern, die Nord-Süd-Reihe endet davor (24 Ecken). Sonst stünde die Brandmauer des einen Hauses in den Fenstern des anderen.
- **Modellbau-Spuren:** Klebestreifen aus dem Scan auf Platten und über dem Plattenstoß der Grundplatte (x 49, z 59), Bleistift-Bauflucht 0,6 m vor den Fassaden mit Teilstrichen und Radierlücken, Überschnitte des Cutters an Fensterecken, glänzende Weißleim-Wülste an Hausfüßen und Bäumen, einzelne Platten stehen bis 5 cm vor.
- **Bäume:** zwei gekreuzte Pappausschnitte, nur an Keizers- und Prinsengracht, 0,45 m vom Kai; ein Kollisionsblock am Stamm schließt die Lücke zur Kante (kein Durchquetschen).
- **Wasser:** dunkler Lack (`#1A120B`), Rauheit 0,07, Klarlack, leicht unebene Folie; keine Animation. Forward+: SSR spiegelt die Häuser.
- **Kaimauer:** doppelwellige Platte (B- und C-Welle) als echte Geometrie, Hohlräume 1,2 m tief, Licht fällt hinein und wirft Schatten (`amsterdam_flute.gdshader`), auch an der äußeren Modellkante.
- **Westerkerk:** Langhaus mit Hochfenstern (Rundbögen), zwei Querschiff-Treppengiebeln, Turm auf der Achse des Damrak-Kais: Sockel 7 m mit Portal, Uhrengeschoss mit weißen Zifferblättern, zwei Achteck-Geschosse (je zwei um 45° gedrehte Kästen), weiße **Kaiserkrone** (vier gekreuzte Ausschnitte), Spitze bis 62 m – das Höchste im Modell, von überall über den Dächern sichtbar.
- **Magere Brug:** weiß gestrichen, drei Bögen, zwei Portale („galgen“) mit Gitter-Waagebalken über der Fahrbahn, Zugstangen an den Rändern über dem Wasser. Alle Brücken: Geländer knapp außerhalb der begehbaren Breite (über dem Wasser) – das Geländer zeigt die Kollisionskante.
- **Abendlicht:** Sonne 2900 K, 15° hoch aus West-Südwest längs der Grachten, **einziger Schattenwerfer** (130 m, zwei Splits, Split 1 bei 22 %, Ausblenden ab 85 %; harte Lichtquelle `light_angular_distance` 0 – der weiche Rand kommt nur aus `shadow_blur` 1,6, kein PCSS-Suchschritt je Pixel; QA W3, Code W2); Schreibtischlampe 2700 K als Spot **ohne Schatten** hoch hinter der Westseite; warmes Rückstrahl-Licht von unten (Ersatz für indirektes Licht); HDRI „Comfy Cafe“ als Raum, Umgebungslicht und Spiegelung – wie im Prototyp weichgezeichnet und Glanzlichter gekappt, zusätzlich auf 35 % entsättigt und warm getönt (die Tageslichtfenster des Cafés wären sonst bläulich, Blau gehört den Nadeln); die hellste Stelle wird weich auf Leuchtdichte 0,7 begrenzt (Knie ab 0,45; Median des Raums ≈ 0,28), damit kein Blendfleck mit dem Ausgang konkurriert (QA K1, Test); Hintergrund-Energie 1,3, ACES, Belichtung 0,76, warmer Dunst.
- **Jenseits der Kante:** Grundplatte 98 × 98 m auf einer schiefergrauen Schneidematte (150 × 124 m, 1-cm-Raster, ohne Hersteller), Holztisch (CC0-Scan), ein Bleistift liegt westlich (am Ende von Keizers- und Prinsengracht zu sehen), der Becher mit dem zweiten Bleistift steht südlich am Ende des Westermarkts (x 16, z 104), Stahllineal östlich. Das Lackwasser spart die Kerbe aus (`cut_rect`).
- **Farbregeln:** Blau nur die Nadelköpfe (`#2E6BFF`), `#00B894` nur der Ausgang; Bleistiftgelb nur jenseits des Wegs; keine Weltfarbe im Blau-Bereich 190–260° (Test).
- **Kugeln:** Glaskopf-Stecknadeln: blauer Kopf (r 0,17 m auf 0,62 m) mit hellem Kern, Glanzpunkt und **dunkler Kontur**, schräge Stahlnadel bis in die Platte (`amsterdam_pin.gdshader`, Pellet-Form `pin` in MazeView, eine MultiMesh).
- **Minimap:** dunkle Straßen, Kraft-Blöcke, schiefergraue Grachten (`minimap_water_script`), Nadeln blau; Spielerpfeil weiß `#F4F1E8` mit 1,5 px schwarzem Rand, Ausgang als **Ring-Glyphe** in `#00B894` mit dunklem Rand (~13 px, größer als der Pfeil) und einem 0,5-Hz-Puls-Ring (aus mit „Effekte reduzieren“) – gilt für alle Explorer-Städte (UX K-A, QA K3). Die statische Schicht (Hintergrund, Wände, Wasser) wird einmal je Labyrinth in eine Textur gemalt (Code H3).
- **Schrift:** keine in der Stadt; die Tafeln an der Tram sind leer.
- **Ton:** keine Geister-Sirene (`siren: false`).

## Ausgang (`amsterdam_exit.gd`)

Grün gestrichene Papp-Tram (generisch, keine Betreiberfarben oder Logos) an einer Haltestelle am Amstel-Ostufer, mit Innenlicht (hellste Fläche am Wegende, grünes Licht auf dem Bahnsteig), dazu eine **Riesen-Stecknadel mit grüner Papierfahne** 24 m hoch über den Dächern (ungenebelt). **Einstieg (UX W-B):** offene Doppeltür (1,2 m, Flügel nach innen geklappt, Trittstufe, Wagenboden) in der Bahnsteigseite genau in der Achse der letzten Nadel; dahinter eine helle Lichtfläche, davor ein weicher, heller Bodenfleck im Ausgangsgrün (`amsterdam_spot.gdshader`); die Auslösung liegt mittig vor der Tür. **Farbe in der Sonne (QA K2):** die grüne Farbe wird im Panel-Shader etwas dunkler aufgetragen und leuchtet mit 32 % `#00B894` (`EXIT_EMIT`), damit die tiefe Sonne sie nicht ausbleicht – der Farbwert `#00B894` selbst bleibt (Inhaber). Puls 0,5 Hz; „Effekte reduzieren“ hält ihn an. Auslöseradius 1,3 m; ab 12 m einmal „Grüne Tram: einsteigen in den Speedrun“ (GD W6, mehr als 2 s vor dem Ziel; verschwindet, wenn das Banner kommt). Banner „NÄCHSTE HALTESTELLE: SPEEDRUN“ / „Einsteigen – los zum Speedrun!“. Einmaliger Start-Hinweis **„Folge den blauen Nadeln zur grünen Tram“** – auch mit „Effekte reduzieren“ (`intro_hint_always`, QA W1); „Pappmodell 1:100“ steht jetzt in der Stadtbeschreibung auf dem Startscreen („Amsterdam – Pappmodell 1:100 im Abendlicht, ruhig“).

## Passanten und Fahrräder (`amsterdam_life.gd`, `amsterdam_figures.gd`, `amsterdam_folk.gdshader`)

Abnahme 06.10.2026: Die Stadt lebt ein wenig, im Stil des Modells. Kleine **Pappfiguren** (flache Ausschnitte aus Karton mit Kraft-Schnittkante, bedruckt in gedeckten, warmen Farben aus `AmsterdamStyle.FOLK_*`: kein Blau der Nadeln, kein Grün des Ausgangs, nichts heller als das Weiß der Brücke) und **Radfahrer** (Pappfigur auf Fahrrad mit Rädern, Rahmen, Sattel, Pedalen).

- **Zahlen:** 36 Passanten (14 % Kinder, kleiner), 16 Radfahrer auf 7 Fahrschleifen (Rechtecke über zwei Brücken, Haarnadeln entlang der langen Straßen), bis 14 abgestellte Räder an Brückengeländern und Baumstämmen am Kai.
- **Draw Calls:** zwei MultiMeshes (Passanten, Räder), der statische Aufbau bleibt ≤ 9. Gangart, Pedale und Felgenmarke laufen im Shader aus der Phase (zurückgelegte Strecke) – kein `TIME`, nichts wird pro Frame angelegt (Test zählt Objekte, Ressourcen, Knoten, Speicher).
- **Spuren:** Die Nadeln laufen in der Straßenmitte. Radfahrer fahren rechts 1,3 m daneben (Kurven gerundet, Haarnadel-Spitzen zwischen den Nadeln), Passanten gehen 0,8 m vor Bordstein oder Fassade in Stücken von 6–16 m (ein Mensch je Stück, Pause und Wende am Ende), 1,2 m Abstand zu Bäumen und Rädern, 5 m zum Start, 7 m zum Ausgang, nie auf der Mittellinie einer kreuzenden Straße. Einzelzellen-Durchgänge (2 m) bleiben leer.
- **Harmlos:** Kein Lebensverlust. Höchstens der weiche Schubs (`push_for()`, ≤ 0,5 m je Frame, Passanten r 0,35, Räder r 0,4, geparkte Räder als Kapsel r 0,3); Kamera und Maus bleiben unberührt. Passanten ≤ 1,3 m/s, Räder ≤ 4 m/s (Spieler 5,06 m/s), keine Bewegung ab 3 Hz (Test `max_motion_hz`).
- **„Effekte reduzieren“:** Alles steht still, aufrecht (`set_comfort(true)`), wie in den anderen Städten.
- **Deterministisch:** reine Funktion aus Level-Seed und Zeit.

## Kantenflimmern an Hausrändern (Abnahme 06.10.2026)

Ursachen (MSAA 4x und FXAA liefen bereits) und Abhilfen:

- **Z-Fighting:** deckungsgleiche Flächen an Brandmauern (Seitenbrett lief durch die Fassadenplatte), Kirchen-Stirnwänden und Eckhaus-Seitenfronten, Fensterkreuz auf Fensterlaibung, Brückengeländer an den Pfosten. Die Bretter sind jetzt um die Plattendicke zurückgesetzt bzw. verkürzt; gemessene Überlappungen gleichgerichteter, ebenengleicher Flächen 2008 → 275 (Rest verdeckt oder winzig).
- **Hochfrequente Muster, die mit der Entfernung nicht ausblenden:** Wellen-Rillen der Schnittkanten (`flute_mask`, jetzt per `fwidth` analytisch geglättet), Wellen-Raster in Panel-, Ausschnitt- und Kai-Shader (`pitch_fade`: blendet nach Pixelfußabdruck zur gemittelten Fläche aus), Verschleiß, Verschattung und Papier-Rauheit sowie die Rippen im Boden (nach Fußabdruck ausgeblendet).
- **Haarfeine Bretter:** im Vertex-Shader zwischen 6 und 10 m Abstand zusammengezogen.
- **Nicht angefasst:** Mipmaps der Fotoebene (sind an), Schatten-Bias (Sonne mit Winkelgröße 0 und Blur, kein Akne im Test sichtbar), Kameranahebene 0,05.
- **Offen für die Hardware-Abnahme:** SSR-Flackern auf dem Lackwasser und Schatten-Schimmer in den Wellenhöhlen bei Forward+ lassen sich in der Sandbox (nur Compatibility) nicht prüfen.

## Technik und Budget

- **Draw Calls (statisch, Test ≤ 9):** Boden (Grundplatte), Platten-MultiMesh, Ausschnitt-Mesh, Kaimauer-Wellen, Wasser, Schneidematte, Tisch, Tischdinge (ein Mesh mit Vertexfarben), Leim-MultiMesh. Die Wand-MultiMesh ist reine Physik (`CityTheme.walls_visible = false`). Dazu Kugeln (eine MultiMesh) und der Ausgang (Tram-MultiMesh, Innenlicht, Fahne, Nadelkopf).
- **Licht (Test):** 3 Lichter in der Stadt (Sonne, Lampe, Rückstrahlung), **nur die Sonne mit Schatten** (Winkelgröße 0, zwei Splits); +1 Omni ohne Schatten in der Tram.
- **Aufbauzeit (QA W2, Code W1; Test ≤ 50 ms für den zweiten Aufbau headless):** Die Kaimauer hängt nur von der Karte ab und wird einmal je Sitzung gebaut (`flute_mesh_cached()`), mit Indexpuffer (geteilte Wellen-Stützpunkte) und vorab dimensionierten Arrays (Zählpass, kein `append`); Kit, Ausschnitt-Mesh, Platten- und Leim-MultiMesh werden je Level-Seed gecacht; die Platten-MultiMesh wird in einem Zug über `MultiMesh.buffer` gefüllt (H6). Gemessen headless (`begin_explorer_game("amsterdam")`): vorher 512 ms erster / 383 ms zweiter Aufbau, jetzt ≈ 290 ms / ≈ 41 ms; `flute_mesh` 243 → 72 ms.
- **Geometrie (Test):** ≤ 9 000 Platten, Kaimauer ≤ 260 000 Vertices (jetzt indiziert ≈ 73 000 Vertices (216 000 Indizes) statt ≈ 214 000), Ausschnitte ≈ 34 000, Ausschnitte ≤ 80 000.
- **Environment:** neue CityTheme-Felder `env_sky_script` (HDRI als Hintergrund, Umgebungs- und Reflexionslicht), `env_bg_energy`, `env_sky_rotation_deg`, `env_adjustment_*`, `env_ssao_enabled` (nur Forward+); Main setzt sie bei **jedem** Theme-Wechsel zurück, beim Rückweg auch `env.sky = null` (Code H1; Bot-Test: nach Amsterdam wieder Farb-Hintergrund, kein Himmel, keine Lichter, kein SSAO). SSR/SSAO nur, wenn `rendering_method` laut `ProjectSettings.get_setting_with_override` `forward_plus` ist (Code W6, Mobile hat auch ein RenderingDevice).
- **Forward+ (Ziel 60 fps bei 1080p, GTX-1660-Klasse):** Richtwerte aus dem Budget: ≈ 6 400 instanzierte Boxen (≈ 150 000 Vertices) + 214 000 Kaimauer-Vertices + Schattenpass der Sonne, SSR und SSAO wie Tokyo. **Abnahme auf echter Hardware steht aus.** Hebel, falls nötig: `directional_shadow_max_distance` 130 → 90, SSR aus, Kaimauer-Stützpunkte 6 → 4 pro Welle (`FLUTE_SAMPLES`), Lampe ohne Schatten.
- **Compatibility:** läuft fehlerfrei und lesbar (alle QA-Bilder sind Compatibility, Software-GL). Ohne SSR, SSAO und indirektes Licht; Sky-Reflexion nur grob.

## Texturen und Austausch gegen 2–4K

Die Scans liegen unter `godot/textures/amsterdam/` (1K) und werden nur über `AmsterdamStyle` geladen (`TEX_*`). Größen im Shader sind in Metern (`FOTO_M` 16 m, `FOTO_DETAIL_M` 3,1 m) – sie hängen **nicht** von der Auflösung ab. Austausch:

1. Originale beim Anbieter laden: Poly Haven `cardboard_box_01` in 2K oder 4K (JPG: `diff`, `nor_gl`, `arm`), ambientCG `Wood095` 2K-JPG, Poly Haven HDRI `comfy_cafe` 2K (.hdr). Alles in einen Ordner außerhalb des Repos.
2. `python3 tools/art/pappe_scan.py <ordner> godot/textures/amsterdam 4k` (oder `2k`). Erzeugt dieselben Dateinamen in 4096 px (Band 2048 × 512); Holz wird unverändert kopiert, das HDRI auf 2048 × 1024 begrenzt. Benötigt Python 3 mit numpy, Pillow, scipy.
3. Eigene Fotos statt Scans: unter denselben Namen ablegen (Albedo sRGB, Normal OpenGL Y+, Rauheit grau). Kachelbar machen, keine Aufdrucke.
4. `godot --headless --path godot --import` – die `.import`-Dateien behalten VRAM-Kompression, Mipmaps und Normal-Map-Modus. `.import`-Dateien committen, `.godot/` nicht.
5. `FOTO_MEAN` in `amsterdam_style.gd` auf den Mittelwert der neuen Albedo setzen (Farbzug bleibt neutral), Screenshots `tools/qa/qa_amsterdam_shots.gd` prüfen, `test_amsterdam.gd` laufen lassen.
6. `docs/art/lizenzen.md` um Datum, Auflösung und Bezugsweg (direkt beim Anbieter) ergänzen.

Ohne Import (frischer Checkout, Tests) lädt `AmsterdamStyle.tex()` die Rohdateien (`imported()` prüft die Import-Ziele, keine Fehlermeldungen) – **nur außerhalb exportierter Builds** (`OS.has_feature("template")` → kein Rohdatei-Fallback, Code W4). Fehlt eine Textur, warnt `push_warning` einmal (das Ergebnis `null` wird gecacht). Test: nach dem Import ist `imported()` für alle Pfade true.

## Tests

- `godot/tests/test_amsterdam.gd` (117 Checks; neu nach den Reviews: Hauptweg dicht/Abstecher gepunktet, Blickpunkt je Ast-Ende und kein Ende mit Tram-Blick über das Wasser, Westermarkt endet an der Schnittkante auf dem Becher, Becher/Bleistift über den Dächern, Schatten nur Sonne mit Winkelgröße 0 und zwei Splits, zweiter Aufbau mit denselben Mesh-Instanzen und < 50 ms, Kaimauer indiziert, Platten-Puffer, Tram-Tür/Lichtfläche/Bodenfleck/Emission, Textur-Import und Rohdatei-Regel, HDRI ohne Blendfleck; bisher: Raster geschlossen, Erreichbarkeit, Grachten nicht begehbar, Brücken mit Wasser seitlich, Route an Damrak-Häusern, Westerkerk und über die Magere Brug (einzige Querung), Startachse auf den Turm, deterministische Spuren und Pflicht-Äste, nichts Sichtbares in der begehbaren Fläche unter Augenhöhe (lesbare Kollisionskante), Häuser füllen jede Fassadenlinie, Eckhäuser mit zweiter Fassade, vier Giebeltypen, tanzende Häuser, Fenster mit dunklem Raum, Modellbau-Spuren, Turm als höchster Punkt, weiße Krone, weiße Magere Brug, Wellenkante auf jeder Platte/Wasser-Grenze, Budget (Draw Calls, Platten, Vertices, Lichter, Schatten), Kollisionshöhe der gebauten Boxen, Baum-Blöcke, Komfort, Theme/Registry, Minimap-Kontrast, Exklusivfarben Blau/Grün, Ausgang (Tram hinter der Kante, Fahne, Puls, Effekte reduzieren), Textur- und Lizenzdateien).
- `godot/tests/bot_test.gd`: Start über den AMSTERDAM-Button, Ziel-Hinweis auch mit „Effekte reduzieren“ (Kyoto ohne), Ausgang auf der Minimap, Himmel und Lichter, „Effekte reduzieren“ stoppt den Puls, Ausgangshinweis ab 12 m und weg mit dem Banner, Tram → Speedrun, Theme-Reset (Farb-Hintergrund, `env.sky == null`, keine Sonne/Lampe, kein SSAO/Adjustment), Minimap-Pfeil im Speedrun wieder cyan; dazu Hinweisbox (mittig, ≤ 560 px, oberes Drittel, wartet in der Pause), Startscreen-Beschreibungen, Regen-Schalter nur in Tokyo.
- `test_amsterdam.gd` prüft zusätzlich (`_check_life`): Figuren vorhanden, deterministisch, zwei MultiMeshes, Spuren frei über 4 Minuten (offener Boden, Abstand zu Nadeln, Start, Ausgang), keine Allokation in 600 Frames, langsam, weicher Schubs, „Effekte reduzieren“ friert ein, Palette.
- Screenshots: `tools/qa/qa_amsterdam_shots.gd` (a1–a18 und a1b; neu: a17 Passanten, a18 Radfahrer; neu: a1b Startscreen mit Fokus-Beschreibung, a11 Raum ohne Blendfleck, a14 Westermarkt mit Becher, a15 Tram-Tür, a16 Hinweis mit „Effekte reduzieren“; die Totale a8 mit eigener QA-Kamera, die Spielkamera bleibt unberührt; `ONLY=a6,a8` rendert einzelne Bilder).

## Rechte (Kurzfassung, keine Rechtsberatung)

Westerkerk (1638), Magere-Brug-Gestalt (heutige Brücke 1934 in historischer Form, Typologie jahrhundertealt) und Damrak-Giebel (17. Jh.) sind gemeinfrei; die Niederlande haben Panoramafreiheit (Art. 18 Auteurswet). Keine Schriftzüge („I amsterdam“), kein Stadtwappen, keine GVB-Lackierung, keine jüngere Architektur. ⚖️ Kurzer Blick des Anwalts nur vor Marketing mit Bauwerksnamen im Store-Text. Scans: CC0 (`docs/art/lizenzen.md`).

## Offen

- Hardware-Abnahme Forward+ (fps, Schattenqualität über 130 m, Moiré der Kaimauer in Bewegung, SSR auf dem Lackwasser) – 30–60 min Inhaber.
- 2–4K-Originale bzw. eigene Fotos (Anleitung oben); bis dahin wiederholt sich die Foto-Ebene im Ego-Blick ab ~40 m sichtbar.
- Look „studio“ für Fotomodus/Trailer, Tiefenunschärfe dort (`CameraAttributesPractical`, nur Forward+), Intro-Schnitt auf die Totale (Inhaber-Frage 22).
- Indirektes Licht (SDFGI oder LightmapGI-Bake) – nur mit Vulkan, nicht in der Sandbox.
- Reviews (game-designer, ux-reviewer, code-reviewer, qa-playtester) sind umgesetzt (05.10.2026). Bewusst **nicht** umgesetzt (Inhaber-Entscheidungen bzw. später):
  - Grüntöne der Ausgänge über die Städte vereinheitlichen (UX W-A)
  - Explorer-Tempo 3,1 m/s (GD W2)
  - Ton je Stadt (GD W5)
  - Rundgang der Woche bzw. Sammelziel (GD W7)
  - Wahrzeichen in weißer Pappe (GD W8)
  - Startscreen-Reihenfolge und Vorschaubilder (GD W9; Reihenfolge bleibt Manhattan, Tokyo, Kyoto, Amsterdam, Arles)
  - Stretch-Aspect „expand“ (UX W-G)
  - gemeinsame Helfer statt Kopien (Code W7; z. B. `dotted_trails()` steht in Amsterdam und Arles)
  - das unfertig wirkende Modell am Amstel-Ostufer
  - Tanzende Häuser schiefer, Steiger am Wasser (K5/N1)
  - Passanten in Hauseingängen (GD N3; Passanten gehen jetzt auf den Kaispuren)
  - Test auf das Volumen der Kollisionsboxen (UX N-F)
