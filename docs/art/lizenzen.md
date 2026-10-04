# Lizenzen von Fremdmaterial (Art)

Alles Sichtbare in ZAPmaniac entsteht per Code und Shader. Fremdmaterial ist nur,
was hier steht. Keine KI-generierten Inhalte (Steam-Offenlegung: nichts anzugeben).

| Datei | Herkunft | Lizenz | Nutzung |
|---|---|---|---|
| `tools/art/explorer_proto/pappe_miniatur_v2/scans/kraft_foto_*.jpg`, `tape_foto_*.jpg` (nur Prototyp J v2, nicht im Spiel) | Abgeleitet aus Poly Haven „Cardboard Box 01“ (Autor Rahul Chaudhary, https://polyhaven.com/a/cardboard_box_01), Dateien `cardboard_box_01_diff/nor_gl/arm_1k.jpg`, bezogen am 04.10.2026 über den Spiegel github.com/mdawg1001/painted-abyss (`playable/public/assets/cardboard_box_01/`, Commit 481b82c, README dort: „License: CC0 1.0“) | CC0 1.0 (Poly Haven: alle Assets CC0, https://polyhaven.com/license) – keine Namensnennung nötig, wir nennen sie trotzdem | Foto-Ebene der Pappe, Klebestreifen |
| `tools/art/explorer_proto/pappe_miniatur_v2/scans/holz_*.jpg` (nur Prototyp) | ambientCG „Wood095“ (Lennart Demes, https://ambientcg.com/view?id=Wood095), 1K, bezogen am 04.10.2026 über github.com/amazingsammed/mini_textures (`mini_texture/textures/Wood095_*.jpg`, Commit b080ca4; Manifest dort: „CC0 PBR materials from ambientCG (CC0)“) | CC0 1.0 (ambientCG) | Tischplatte |
| `tools/art/explorer_proto/pappe_miniatur_v2/scans/hdri_tag.hdr`, `hdri_warm.hdr`, `hdri_studio.hdr` (nur Prototyp) | Poly Haven HDRIs „Photo Studio Loft Hall“, „Comfy Cafe“ (2K, auf 1K halbiert), „Studio Small 05“ (1K), bezogen am 04.10.2026 über github.com/gkjohnson/3d-demo-data (`hdri/`, Commit 9149f69; README dort: „HDRIs from Polyhaven“) | CC0 1.0 (Poly Haven) | Umgebung/Hintergrund der Look-Varianten |
| `godot/fonts/NotoSansCJKjp-Bold-Subset.otf` | Noto Sans CJK JP Bold (Adobe/Google, Projekt noto-cjk, https://github.com/notofonts/noto-cjk), Version aus dem Ubuntu-Paket `fonts-noto-cjk` (TTC-Index 0) | SIL Open Font License 1.1 — Text liegt daneben: `godot/fonts/OFL-NotoSansCJK.txt` | Schilder der Explorer-Stadt Tokyo (Label3D) |

## Noto Sans CJK JP — Subset

- **Warum Subset:** Der volle Font hat rund 20 MB; gebraucht werden nur die
  Schilderzeichen. Das Subset ist 22 KB groß.
- **Enthaltene Zeichen:** `地下鉄↓↑←→カラオケラーメン居酒屋薬出口駅本屋喫茶寿司映画館営業中ー・0123456789`
- **Erzeugt mit** fontTools/pyftsubset:
  ```bash
  pyftsubset /usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc --font-number=0 \
    --text="地下鉄↓↑←→カラオケラーメン居酒屋薬出口駅本屋喫茶寿司映画館営業中ー・0123456789" \
    --output-file=godot/fonts/NotoSansCJKjp-Bold-Subset.otf \
    --layout-features='*' --name-IDs='*' --name-languages='*' --notdef-outline
  ```
  Neue Schilderzeichen: Zeichen in die Liste aufnehmen, Befehl erneut ausführen,
  Liste hier aktualisieren.
- **OFL-Bedingungen:** Ein Subset ist eine „Modified Version“. Die OFL erlaubt
  Veränderung, Bündelung und kommerzielle Nutzung, solange der Font nicht allein
  verkauft wird, die Lizenz beiliegt und kein *Reserved Font Name* verwendet wird.
  Reserviert ist nur der Name „Source“ (Adobe); das Subset trägt weiter den Namen
  „Noto Sans CJK JP“, der nicht reserviert ist. Copyright-Vermerk und Lizenztext
  liegen unverändert in `godot/fonts/OFL-NotoSansCJK.txt` und müssen in jedem
  Build-Paket mitgeliefert werden (Steam-Depot: Ordner `fonts/` samt Lizenzdatei).

## Fotoscans und HDRIs für Richtung J v2 (Prototyp, 04.10.2026)

- **Bezugsweg:** ambientCG, Poly Haven und andere Texturseiten sind aus der Studio-Sandbox
  gesperrt. Die Dateien stammen aus öffentlichen GitHub-Repositorys, die die **unveränderten
  Originaldateien** der Anbieter enthalten (Dateinamen und Auflösungen wie beim Anbieter). Die
  Lizenz folgt aus der Quelle (Poly Haven und ambientCG veröffentlichen ausschließlich unter CC0),
  nicht aus dem Spiegel. Vor einem Einsatz im Spiel: Originale direkt beim Anbieter laden und
  per Prüfsumme bzw. Sichtvergleich bestätigen (5 min, Inhaber oder Studio mit Netzzugang).
- **Ableitung:** `tools/art/explorer_proto/tools/pappe_scan.py <quellordner> <zielordner>` dreht
  den Karton-Atlas, rechnet die Beleuchtung heraus, setzt saubere Flächen (ohne Aufdrucke,
  Piktogramme, Schrift) zu einer kachelbaren 1K-Textur zusammen, schneidet den Klebeband-Streifen
  aus und halbiert die 2K-HDRIs. Die Originale liegen nicht im Repo.
- **Nicht übernommen:** Bereiche des Karton-Scans mit Aufdruck („Keep Out of Reach of Children“),
  Handhabungs-Piktogrammen und Rissen; das prozedurale „cardboard“-Material aus `mini_textures`
  (kein Foto, für uns ohne Mehrwert).
- **CC0** verlangt keine Namensnennung und erlaubt kommerzielle Nutzung und Veränderung. Wir
  nennen die Urheber in den Credits trotzdem (Rahul Chaudhary/Poly Haven, Lennart Demes/ambientCG,
  Poly-Haven-HDRI-Autoren).
