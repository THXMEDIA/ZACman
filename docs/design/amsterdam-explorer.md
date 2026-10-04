# Explorer-Stadt Amsterdam – Spezifikation v1

**Stand:** 04.10.2026 · **Freigabe:** Inhaber, E21 – Richtung J „Pappmodell Amsterdam 1:100“, **Abendlook** (goldene Stunde, Schreibtischlampe, lange Schatten), alles wie vom Art Director vorgeschlagen (Vorlage `studio/projekte/zapmaniac/art/explorer-stile-v1.md`, Abschnitte J und J v2) · **Branch:** `feature/explorer-amsterdam`

## Idee

Amsterdam ist ein Architekturmodell aus Wellpappe im Maßstab 1:100, erlebt auf Ameisenhöhe: Die Häuser haben echte Größe, das Material ist hundertfach vergrößert. Die Pappe ist 40 cm dick, jede Schnittkante zeigt die Welle als echten Querschnitt, die Grachten sind dunkel lackierter Karton, der Weg ist mit blauen Glaskopf-Stecknadeln abgesteckt. Jenseits der Modellkante liegen Schneidematte, Riesen-Bleistift, Stahllineal und Kaffeebecher auf dem Holztisch. Es ist Abend: eine tiefe, warme Sonne längs der Grachten, die Schreibtischlampe, lange Schatten, der unscharfe Raum dahinter. Die Kamera wird nie bewegt (E8e), es gibt keine Tiefenunschärfe und kein Korn im Spielblick.

## Karte (`godot/scripts/amsterdam_maze.gd`)

49 × 49 Zellen à 2 m. Grachtengürtel als Raster, echte Orte frei angeordnet, damit der Weg zum Ausgang an allen drei Wahrzeichen vorbeiführt (Lehre aus dem Kyoto-Review).

| Ort | Verlauf | Blickpunkt / Rolle |
|---|---|---|
| Damrak (Gracht, Reihen 7–10) | Ost-West, mündet in die Amstel | Nordufer: **Tanzende Häuser** – schiefe Giebelreihe direkt am Wasser |
| Damrak-Kai (Reihen 11–13) | Start, Blick nach Westen | gegenüber die Tanzenden Häuser, am Ende der **Westerkerk-Turm** (auf der Mittellinie) |
| Westermarkt (Spalten 7–9) | Nord-Süd vor der Kirche, quert Keizers- und Prinsengracht | Westerkerk-Front mit Turm, Querschiffgiebeln, Hochfenstern |
| Keizersgracht | Ost-West, zwei Kaistraßen, drei Brücken (Westermarkt, West, Ost) | Bäume an beiden Kais |
| Prinsengracht | Ost-West, zwei Kaistraßen; nur am Westermarkt überquerbar | Bäume; der Südkai läuft geradeaus auf die **Magere Brug** |
| Gassen (Spalten 14–15, 25–26) | Querverbindungen Keizers-/Prinsengracht, 4 m breit | – |
| Amstel (Spalten 36–41) | Nord-Süd über die ganze Karte | einzige Querung: **Magere Brug**; Blick nach Norden auf den Becher hinter der Modellkante |
| Amstel-Ostufer (Spalten 42–44) | Haltestelle | **Ausgang**: grüne Papp-Tram |

- **Grachten sind Wasser**, keine Wege: Wandzellen (volle 3 m Kollisionsbox), sichtbar als Lack 0,85 m unter der Straße. Die **Kaimauer** ist die Schnittkante der Grundplatte mit echter Wellen-Geometrie – genau dort ist die Kollisionskante.
- **Pflichtweg:** Der Damrak-Kai öffnet sich nur zum Westermarkt (Kirche passieren), die Prinsengracht ist nur dort überquerbar, die Amstel nur über die Magere Brug (Tests). Kürzester Weg 92 Zellen (184 m, ≈ 42 s bei 4,4 m/s); 131 Nadeln.
- **Start:** Damrak-Kai (12, 28), Blick nach Westen (längster freier Gang; Main dreht dorthin). **Ausgang:** Bahnsteigzelle (32, 44), die Tram steht östlich hinter der Bordsteinkante.
- **Stecknadel-Spuren:** BFS vom Ausgang über die Straßen-Mittellinien, zurückgegangen vom Start, immer vom Kirchenvorplatz (Westermarkt-Nordende, Pflicht-Ast) und zwei vom Level-Seed (2121) gewählten Ästen. Jeder Seed führt über die Magere Brug (Test).

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
- **Abendlicht:** Sonne 2900 K, 15° hoch aus West-Südwest längs der Grachten, mit Schatten (130 m); Schreibtischlampe 2700 K als Spot mit Schatten hoch hinter der Westseite; warmes Rückstrahl-Licht von unten (Ersatz für indirektes Licht); HDRI „Comfy Cafe“ als Raum, Umgebungslicht und Spiegelung – wie im Prototyp weichgezeichnet und Glanzlichter gekappt, zusätzlich auf 35 % entsättigt und warm getönt (die Tageslichtfenster des Cafés wären sonst bläulich, Blau gehört den Nadeln); Hintergrund-Energie 1,3, ACES, Belichtung 0,76, warmer Dunst.
- **Jenseits der Kante:** Grundplatte 98 × 98 m auf einer schiefergrauen Schneidematte (150 × 124 m, 1-cm-Raster, ohne Hersteller), Holztisch (CC0-Scan), Bleistift westlich (am Ende von Keizers- und Prinsengracht zu sehen), Becher nördlich (am Ende der Amstel), Stahllineal östlich.
- **Farbregeln:** Blau nur die Nadelköpfe (`#2E6BFF`), `#00B894` nur der Ausgang; Bleistiftgelb nur jenseits des Wegs; keine Weltfarbe im Blau-Bereich 190–260° (Test).
- **Kugeln:** Glaskopf-Stecknadeln: blauer Kopf (r 0,17 m auf 0,62 m) mit hellem Kern, Glanzpunkt und **dunkler Kontur**, schräge Stahlnadel bis in die Platte (`amsterdam_pin.gdshader`, Pellet-Form `pin` in MazeView, eine MultiMesh).
- **Minimap:** dunkle Straßen, Kraft-Blöcke, schiefergraue Grachten (`minimap_water_script`), Nadeln blau, Ausgang `#00B894`.
- **Schrift:** keine in der Stadt; die Tafeln an der Tram sind leer.
- **Ton:** keine Geister-Sirene (`siren: false`).

## Ausgang (`amsterdam_exit.gd`)

Grün gestrichene Papp-Tram (generisch, keine Betreiberfarben oder Logos) an einer Haltestelle am Amstel-Ostufer, mit Innenlicht (hellste Fläche am Wegende, grünes Licht auf dem Bahnsteig), dazu eine **Riesen-Stecknadel mit grüner Papierfahne** 24 m hoch über den Dächern (ungenebelt). Puls 0,5 Hz; „Effekte reduzieren“ hält ihn an. Auslöseradius 1,3 m; ab 4,5 m einmal „Grüne Tram: einsteigen in den Speedrun“. Banner „NÄCHSTE HALTESTELLE: SPEEDRUN“ / „Einsteigen – los zum Speedrun!“. Einmaliger Start-Hinweis: „Ein Pappmodell im Maßstab 1:100 – die blauen Stecknadeln zeigen den Weg zur grünen Tram“.

## Technik und Budget

- **Draw Calls (statisch, Test ≤ 9):** Boden (Grundplatte), Platten-MultiMesh, Ausschnitt-Mesh, Kaimauer-Wellen, Wasser, Schneidematte, Tisch, Tischdinge (ein Mesh mit Vertexfarben), Leim-MultiMesh. Die Wand-MultiMesh ist reine Physik (`CityTheme.walls_visible = false`). Dazu Kugeln (eine MultiMesh) und der Ausgang (Tram-MultiMesh, Innenlicht, Fahne, Nadelkopf).
- **Licht (Test):** 3 Lichter in der Stadt (Sonne, Lampe, Rückstrahlung), 2 davon mit Schatten; +1 Omni ohne Schatten in der Tram.
- **Geometrie (Test):** ≤ 9 000 Platten, Kaimauer ≤ 260 000 Vertices (aktuell ≈ 214 000, 864 m Schnittkante), Ausschnitte ≈ 34 000, Ausschnitte ≤ 80 000.
- **Environment:** neue CityTheme-Felder `env_sky_script` (HDRI als Hintergrund, Umgebungs- und Reflexionslicht), `env_bg_energy`, `env_sky_rotation_deg`, `env_adjustment_*`, `env_ssao_enabled` (nur Forward+); Main setzt sie bei **jedem** Theme-Wechsel zurück (Bot-Test: nach Amsterdam wieder Farb-Hintergrund, keine Lichter, kein SSAO).
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

Ohne Import (frischer Checkout, Tests) lädt `AmsterdamStyle.tex()` die Rohdateien (`imported()` prüft die Import-Ziele, keine Fehlermeldungen).

## Tests

- `godot/tests/test_amsterdam.gd` (78 Checks): Raster geschlossen, Erreichbarkeit, Grachten nicht begehbar, Brücken mit Wasser seitlich, Route an Damrak-Häusern, Westerkerk und über die Magere Brug (einzige Querung), Startachse auf den Turm, deterministische Spuren und Pflicht-Äste, nichts Sichtbares in der begehbaren Fläche unter Augenhöhe (lesbare Kollisionskante), Häuser füllen jede Fassadenlinie, Eckhäuser mit zweiter Fassade, vier Giebeltypen, tanzende Häuser, Fenster mit dunklem Raum, Modellbau-Spuren, Turm als höchster Punkt, weiße Krone, weiße Magere Brug, Wellenkante auf jeder Platte/Wasser-Grenze, Budget (Draw Calls, Platten, Vertices, Lichter, Schatten), Kollisionshöhe der gebauten Boxen, Baum-Blöcke, Komfort, Theme/Registry, Minimap-Kontrast, Exklusivfarben Blau/Grün, Ausgang (Tram hinter der Kante, Fahne, Puls, Effekte reduzieren), Textur- und Lizenzdateien.
- `godot/tests/bot_test.gd`: Start über den AMSTERDAM-Button, Ausgang auf der Minimap, Himmel und Lichter, „Effekte reduzieren“ stoppt den Puls, Tram → Speedrun, Theme-Reset (Farb-Hintergrund, keine Sonne/Lampe, kein SSAO/Adjustment).
- Screenshots: `tools/qa/qa_amsterdam_shots.gd` (a1–a13; die Totale a8 mit eigener QA-Kamera, die Spielkamera bleibt unberührt; `ONLY=a6,a8` rendert einzelne Bilder).

## Rechte (Kurzfassung, keine Rechtsberatung)

Westerkerk (1638), Magere-Brug-Gestalt (heutige Brücke 1934 in historischer Form, Typologie jahrhundertealt) und Damrak-Giebel (17. Jh.) sind gemeinfrei; die Niederlande haben Panoramafreiheit (Art. 18 Auteurswet). Keine Schriftzüge („I amsterdam“), kein Stadtwappen, keine GVB-Lackierung, keine jüngere Architektur. ⚖️ Kurzer Blick des Anwalts nur vor Marketing mit Bauwerksnamen im Store-Text. Scans: CC0 (`docs/art/lizenzen.md`).

## Offen

- Hardware-Abnahme Forward+ (fps, Schattenqualität über 130 m, Moiré der Kaimauer in Bewegung, SSR auf dem Lackwasser) – 30–60 min Inhaber.
- 2–4K-Originale bzw. eigene Fotos (Anleitung oben); bis dahin wiederholt sich die Foto-Ebene im Ego-Blick ab ~40 m sichtbar.
- Look „studio“ für Fotomodus/Trailer, Tiefenunschärfe dort (`CameraAttributesPractical`, nur Forward+), Intro-Schnitt auf die Totale (Inhaber-Frage 22).
- Indirektes Licht (SDFGI oder LightmapGI-Bake) – nur mit Vulkan, nicht in der Sandbox.
- Reviews (game-designer, ux-reviewer, code-reviewer) auf diesem Branch.
