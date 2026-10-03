# Speedrun-Look – Prototyp-Patches (Art Director, 03.10.2026)

Vorschläge zur Freigabe, NICHT im Spiel. Anwenden in einer Kopie von main (Stand 6e142d8):
`git apply tools/art/speedrun_proto/<name>.patch`

- `pacman_v2.patch` – Pac-Man-Basislook „Lagune“ (Wand-/Boden-Shader, CRT-Overlay, Geister „Schild mit Visier“).
  Umschalter im Prototyp: `ZAC_LOW_WALLS=1` (Variante Niedrig), `ZAC_PALETTE=riff`.
- `konditionen.patch` – Konditions-Looks Matrix „Durchlässiger Code“ und Fear & Loathing a/b/c
  (gemeinsamer Wand-/Boden-Shader, Umschaltung per Uniform `look`/`transition`/`flip`/`reduce_fx`).

Bilder: `docs/art/vorschlaege/speedrun/`. Vorlage: Project-Dokument `studio/art/zacman-speedrun-stil-v1.md`.
Beide Patches wurden unabhängig voneinander gebaut und müssen bei der Umsetzung zusammengeführt werden.
