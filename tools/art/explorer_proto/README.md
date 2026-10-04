# Explorer-Städte – Stil-Prototypen (Art Director, 04.10.2026)

Eigenständige Godot-4.3-Projekte, NICHT Teil des Spiels. Drei Richtungen für drei neue
Explorer-Städte:

| Ordner | Richtung | Stadt |
|---|---|---|
| `paris_aquarell/` | A Aquarell-Paris (Tusche + Lasur, Impressionismus) | Paris, Seine-Ufer |
| `arles_sternennacht/` | B Sternennacht über Arles (Van Gogh, gemeinfrei) | Arles, Platz mit Café, Nacht |
| `miami_popart/` | C Druckfarben-Miami (Pop Art, Ben-Day-Raster) | Miami, Ocean Drive |
| `himmelsbrunn_kulisse/` | D Kulissenstadt (symmetrische Achsen, Pastell, flaches Licht, Modellbau) | Himmelsbrunn, fiktiver Kurort |
| `kabuki_buehne/` | E Bühnenstadt (sehr Kabuki: Hinoki-Boden, Hanamichi, Schiebekulissen, Streifenvorhang, Kirschzweig-Borten, Kuromaku-Nacht, Drehbühne, grüne Versenkung) | Shibai-machi, fiktives Theaterviertel |
| `pappkarton/` | F Pappstadt (braune Wellpappe: Wellen-Schnittkanten per Shader, Klebeband, Druckreste, Marker-Masken, echte Sonne + Schatten) | Danboru-cho, fiktive Kartonstadt |
| `aizuri_popup/` | G Aizuri-Pop-up (Theater-Bilderbuch, Holzschnitt in Preußischblau, Teile klappen beim Näherkommen auf) | Bilderbuchstadt, fiktiv |
| `pappe_buehne/` | I Kartonbühne (fotorealistische Wellpappe: Kleinstadt-Gasse aus Umzugskartons auf schwarzer Bühne, Scheinwerfer, glühendes Packpapier) | fiktive Kleinstadt-Gasse mit Uhrturm |
| `pappe_miniatur/` | J Pappmodell Amsterdam 1:100 auf Ameisenhöhe (meterhohe Wellen in jeder Schnittkante, Tageslicht, Arbeitstisch) | Amsterdam, Grachtengürtel |
| `pappe_miniatur_v2/` | J v2: Realismus (CC0-Fotoscans, echte Wellen-Geometrie an der Kaimauer, Modellbau-Spuren) und vier Licht-Varianten `VARIANT=atelier\|abend\|studio\|nacht` | Amsterdam, Grachtengürtel |
| `pappe_wohnung/` | K Umzugswohnung (Kartonstapel als Gänge, Edding-Etiketten als Wegweiser, Pappmöbel, Abendsonne durch Packpapier) | Altbauwohnung, fiktiv |

Gemeinsame Helfer in `common/` (`geo.gd` Primitive, Figuren, Fahrzeuge, Kugel-MultiMesh,
Inverted-Hull-Konturen; `shot.gd` Kameras und Screenshots). Jede Richtung hat ihre Shader
und ihren Szenenaufbau in `city.gd`.

Rendern (unter xvfb, Compatibility-Renderer, 1280×720): `./render.sh <richtung> [ansichten]`
– schreibt nach `$OUT/<richtung>/*.png` (Standard: Scratchpad `explorer_shots/`).
Style-Tiles und Capsule-Mockups: `python3 tools/tiles.py` (Pillow, liest die Screenshots).

Ergebnisbilder: `docs/art/vorschlaege/explorer/<richtung>/`. Vorlage zur Freigabe:
Project-Dokument `studio/projekte/zapmaniac/art/explorer-stile-v1.md`.

Richtung D bringt den Font Jost (SIL OFL 1.1, `himmelsbrunn_kulisse/fonts/`, Lizenztext daneben) mit;
fürs Spiel als Subset bündeln und in `docs/art/lizenzen.md` eintragen. `tools/tiles.py` rendert
mit `ONLY=<richtung>` nur eine Richtung neu.

Nachtrag E–G (04.10.2026): Gemalte/gedruckte Texturen (Kulissen, Laternen, Fahnen, Piktogramme,
Holzschnitt-Bögen) entstehen per `prints.py` im jeweiligen Ordner (Pillow, eigene Entwürfe) und
werden von `render.sh` vor dem Rendern erzeugt; `prints/` ist nicht eingecheckt. Fonts: Subsets von
Noto Serif/Sans CJK JP (SIL OFL 1.1) per `tools/cjk_subset.py`, Lizenztext in `<richtung>/fonts/`.
`common/geo.gd` hat dafür `extrude()` (ausgeschnittene Kulisse mit Schnittkanten-UV), `rect_poly()`,
`circle_poly()` und `tex()`. `REDUCE_FX=1 ./render.sh <richtung>` rendert mit „Effekte reduzieren“
(Papierschnee steht, Puls aus, Pop-up-Teile stehen).

Prototyp-Abkürzungen, die so **nicht** ins Spiel dürfen (technische Prüfung): System-Fonts
über `Label3D`, fester Seed, Einzelknoten pro Figur/Fenster/Laterne (im Spiel MultiMesh),
viele Material-Duplikate (im Spiel ein Material je Rolle mit `INSTANCE_CUSTOM`),
Inverted-Hull als Kind-Mesh pro Objekt (im Spiel ein zweiter Pass auf der Wand-MultiMesh
oder Post-Edge), Sky-LIC mit 14 Noise-Abtastungen pro Pixel (im Spiel vorgebackene
Flow-Textur oder weniger Schritte). Alle Bilder sind im Software-Renderer entstanden; Glow,
Licht und Antialiasing sind im Spiel (Forward+) besser.

Nachtrag I–K (04.10.2026, Papp-Fotorealismus): `tools/pappe_pbr.py` erzeugt prozedurale PBR-Texturen
(Kraftliner Albedo/Normal/Rauheit mit Fasern und Wellen-Abzeichnung, zerknittertes Packpapier als
periodisches Voronoi-Facettenfeld, Klebeband-Falten, Druck-/Edding-Atlas; keine Scans, ~25 s); jede
Richtung ruft es über ihr `prints.py` auf (`prints/` nicht eingecheckt, `FORCE=1` erzeugt neu).
`common/pappe.gd` enthält die gemeinsamen Shader und Bauhelfer: Karton-Shader für eine MultiMesh
(Instanzdaten Seed/Klebeband/Druck/Helligkeit; Ausbauchen, Kantenabrieb, Laschenfuge, Klebeband,
Herstellerlasche, Griffloch, Druck; Plattenmodus für Modellbau mit Wellen-Querschnitt an den Kanten),
Boden, Packpapier (Falten im Vertex-Shader, Transluzenz über BACKLIGHT), Papprolle, Schnittkante,
Glasmurmel, Lichtkegel, Vignette; `stack_wall()` stapelt Kartons mit Aussparungen. `SHOT_WAIT=4`
verkürzt die Frames je Ansicht (Software-Rendering ~10–20 s pro Frame).

Weitere Prototyp-Abkürzungen I–K (nicht ins Spiel): Packpapier-Bahnen und Lampenschirme als
Einzelknoten (im Spiel MultiMesh), Ausschnitte (Giebel, Bäume, Zifferblätter) als Einzel-Meshes (im
Spiel beim Levelaufbau zu einem Mesh zusammenführen), Fenster-Omnilichter zufällig verteilt.
Renderer: nur Compatibility (Software-GL) – Forward+ war in der Sandbox nicht startbar (kein
Vulkan-Treiber mit X11-Oberfläche). Es fehlen daher GI/Bounce-Licht, SSAO, Volumetrik, Tiefenunschärfe
und weiche Schatten; Omni-Schatten zeigen in Compatibility Dual-Paraboloid-Artefakte (deshalb Spots).

Nachtrag J v2 (04.10.2026): `pappe_miniatur_v2/` nutzt erstmals **Fremdmaterial** – CC0-Fotoscans und
CC0-HDRIs (Poly Haven, ambientCG), abgeleitet per `tools/pappe_scan.py` nach `pappe_miniatur_v2/scans/`
(eingecheckt, Lizenzen in `docs/art/lizenzen.md`). `common/pappe.gd` hat dafür eine optionale
Foto-Ebene (`foto` = 0 lässt I/K unverändert). Rendern: `VARIANT=abend ./render.sh pappe_miniatur_v2`
(Bilder nach `$OUT/pappe_miniatur_v2/<variante>/`), Capsules: `python3 pappe_miniatur_v2/capsule.py <ordner>`.
Die Optik (Tiefenunschärfe/Tilt-Shift, Vignette, Korn) ist ein Vollbild-Shader, der auch im
Compatibility-Renderer läuft; Glow ist dort aus (verfälscht sonst den Shader). `REDUCE_FX=1` schaltet
Unschärfe und Korn ab.
