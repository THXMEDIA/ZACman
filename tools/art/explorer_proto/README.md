# Explorer-Städte – Stil-Prototypen (Art Director, 04.10.2026)

Eigenständige Godot-4.3-Projekte, NICHT Teil des Spiels. Drei Richtungen für drei neue
Explorer-Städte:

| Ordner | Richtung | Stadt |
|---|---|---|
| `paris_aquarell/` | A Aquarell-Paris (Tusche + Lasur, Impressionismus) | Paris, Seine-Ufer |
| `arles_sternennacht/` | B Sternennacht über Arles (Van Gogh, gemeinfrei) | Arles, Platz mit Café, Nacht |
| `miami_popart/` | C Druckfarben-Miami (Pop Art, Ben-Day-Raster) | Miami, Ocean Drive |
| `himmelsbrunn_kulisse/` | D Kulissenstadt (symmetrische Achsen, Pastell, flaches Licht, Modellbau) | Himmelsbrunn, fiktiver Kurort |

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

Prototyp-Abkürzungen, die so **nicht** ins Spiel dürfen (technische Prüfung): System-Fonts
über `Label3D`, fester Seed, Einzelknoten pro Figur/Fenster/Laterne (im Spiel MultiMesh),
viele Material-Duplikate (im Spiel ein Material je Rolle mit `INSTANCE_CUSTOM`),
Inverted-Hull als Kind-Mesh pro Objekt (im Spiel ein zweiter Pass auf der Wand-MultiMesh
oder Post-Edge), Sky-LIC mit 14 Noise-Abtastungen pro Pixel (im Spiel vorgebackene
Flow-Textur oder weniger Schritte). Alle Bilder sind im Software-Renderer entstanden; Glow,
Licht und Antialiasing sind im Spiel (Forward+) besser.
