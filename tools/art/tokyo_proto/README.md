# Tokyo-Explorer – Stil-Prototypen (Art Director, 02.10.2026)

Eigenständige Godot-4.3-Projekte, NICHT Teil des Spiels. Drei Richtungen:
`natriumregen/` (empfohlen), `linienstadt/`, `natriumdunst/`. Gemeinsamer Szenenbau in
`common/city.gd`, Kameras/Screenshots in `common/shot.gd`, Palette/Parameter je Richtung in `style.gd`.

Rendern (unter xvfb, Compatibility-Renderer): `./render.sh <richtung> [ansichten]`.
Style-Tiles und Capsule: `tools/tiles.py` (Python/Pillow).

Ergebnisbilder: `docs/art/vorschlaege/tokyo/`. Vorlage zur Freigabe: Project-Dokument
`studio/art/zacman-tokyo-stil-v1.md`.

Achtung für die Übernahme ins Spiel (technische Prüfung): planarer SubViewport-Spiegel, einzelne
Halo-/Kegel-MeshInstances, Regen-Transforms per GDScript, Systemfont und fester Seed sind nur
Prototyp-Abkürzungen und dürfen so nicht ins Spiel.
