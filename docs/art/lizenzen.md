# Lizenzen von Fremdmaterial (Art)

Alles Sichtbare in ZAPmaniac entsteht per Code und Shader. Fremdmaterial ist nur,
was hier steht. Keine KI-generierten Inhalte (Steam-Offenlegung: nichts anzugeben).

| Datei | Herkunft | Lizenz | Nutzung |
|---|---|---|---|
| `godot/textures/amsterdam/kraft_foto_albedo.jpg`, `kraft_foto_normal.jpg`, `kraft_foto_rough.jpg` (1K) | Abgeleitet aus Poly Haven „Cardboard Box 01“ (Autor Rahul Chaudhary, https://polyhaven.com/a/cardboard_box_01), Dateien `cardboard_box_01_diff/nor_gl/arm_1k.jpg`, bezogen am 04.10.2026 über den Spiegel github.com/mdawg1001/painted-abyss (`playable/public/assets/cardboard_box_01/`, Commit 481b82c, README dort: „License: CC0 1.0“); Ableitung `tools/art/pappe_scan.py` | CC0 1.0 (Poly Haven: alle Assets CC0, https://polyhaven.com/license) – keine Namensnennung nötig, wir nennen sie trotzdem | **Explorer-Stadt Amsterdam:** Foto-Ebene jeder Pappfläche (Platten-MultiMesh, Ausschnitte, Grundplatte/Straßen, Kaimauer-Wellen) – `amsterdam_common.gdshaderinc` |
| `godot/textures/amsterdam/tape_foto_albedo.jpg`, `tape_foto_normal.jpg` (512 × 128) | wie oben, Klebeband-Streifen aus demselben Scan | CC0 1.0 | **Amsterdam:** Klebestreifen auf Platten und über dem Plattenstoß der Grundplatte; Normal als leichte Unebenheit des Lackwassers |
| `godot/textures/amsterdam/holz_albedo.jpg`, `holz_normal.jpg`, `holz_rough.jpg` (1K) | ambientCG „Wood095“ (Lennart Demes, https://ambientcg.com/view?id=Wood095), 1K, bezogen am 04.10.2026 über github.com/amazingsammed/mini_textures (`mini_texture/textures/Wood095_*.jpg`, Commit b080ca4; Manifest dort: „CC0 PBR materials from ambientCG (CC0)“), unverändert | CC0 1.0 (ambientCG) | **Amsterdam:** Arbeitstisch unter dem Modell |
| `godot/textures/amsterdam/hdri_warm.hdr` (1024 × 512) | Poly Haven HDRI „Comfy Cafe“ (https://polyhaven.com/a/comfy_cafe), 2K, auf 1K halbiert, bezogen am 04.10.2026 über github.com/gkjohnson/3d-demo-data (`hdri/`, Commit 9149f69; README dort: „HDRIs from Polyhaven“) | CC0 1.0 (Poly Haven) | **Amsterdam:** Raum hinter dem Modell (Himmel, weichgezeichnet), Umgebungslicht und Spiegelung (Abendlook) |
| `tools/art/explorer_proto/pappe_miniatur_v2/scans/*` (nur Prototyp J v2, Branch `art/explorer-stile`) | dieselben Quellen, dazu die HDRIs „Photo Studio Loft Hall“ und „Studio Small 05“ (Poly Haven) | CC0 1.0 | Look-Varianten des Prototyps, nicht im Spiel |
| `godot/fonts/NotoSansCJKjp-Bold-Subset.otf` | Noto Sans CJK JP Bold (Adobe/Google, Projekt noto-cjk, https://github.com/notofonts/noto-cjk), Version aus dem Ubuntu-Paket `fonts-noto-cjk` (TTC-Index 0) | SIL Open Font License 1.1 — Text liegt daneben: `godot/fonts/OFL-NotoSansCJK.txt` | Schilder der Explorer-Stadt Tokyo (Label3D) |

**Amsterdam (Explorer, „Pappmodell 1:100, Abend“):** Fremdmaterial sind nur die vier Zeilen
`godot/textures/amsterdam/…` oben (CC0). Alles andere – Häuser, Giebel, Westerkerk, Magere Brug,
Tram, Bleistift, Becher, Lineal, Schneidematte, Bleistiftlinien – entsteht per Code und Shader.
Keine Schrift in der Stadt, keine Logos oder Betreiberfarben an der Tram, Matte und Lineal ohne
Hersteller. Wahrzeichen sind gemeinfrei (Westerkerk 1638, Magere-Brug-Gestalt über 90 Jahre,
Damrak-Giebel 17. Jh.); Niederlande mit Panoramafreiheit (Art. 18 Auteurswet).

**Kyoto (Explorer, „Aizuri-Pop-up“):** alle Motive (Machiya, Pagode, Kiyomizu-Bühne, Torii, Tore, Theater, Kyoto Tower, Hügel, Figuren) entstehen prozedural in `godot/shaders/kyoto_card.gdshader`; keine Fotos, Scans oder Fremdbilder. Einzige Schrift: „出口 EXIT“ aus dem Noto-Subset unten.

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

## Fotoscans und HDRIs der Explorer-Stadt Amsterdam (04.10.2026)

- **Bezugsweg:** ambientCG, Poly Haven und andere Texturseiten sind aus der Studio-Sandbox
  gesperrt. Die Dateien stammen aus öffentlichen GitHub-Repositorys, die die **unveränderten
  Originaldateien** der Anbieter enthalten (Dateinamen und Auflösungen wie beim Anbieter). Die
  Lizenz folgt aus der Quelle (Poly Haven und ambientCG veröffentlichen ausschließlich unter CC0),
  nicht aus dem Spiegel. **Vor dem Release:** Originale direkt beim Anbieter laden und per
  Sichtvergleich bestätigen (5 min, Inhaber) – am besten gleich in 2–4K, siehe Austausch-Anleitung in
  `docs/design/amsterdam-explorer.md`.
- **Ableitung:** `tools/art/pappe_scan.py <quellordner> godot/textures/amsterdam [1k|2k|4k]` dreht
  den Karton-Atlas, rechnet die Beleuchtung heraus, setzt saubere Flächen (ohne Aufdrucke,
  Piktogramme, Schrift) zu einer kachelbaren Textur zusammen, schneidet den Klebeband-Streifen aus
  und halbiert 2K-HDRIs auf die Zielgröße. Die Originale liegen nicht im Repo.
- **Nicht übernommen:** Bereiche des Karton-Scans mit Aufdruck („Keep Out of Reach of Children“),
  Handhabungs-Piktogrammen und Rissen.
- **CC0** verlangt keine Namensnennung und erlaubt kommerzielle Nutzung und Veränderung. Credits
  trotzdem: Rahul Chaudhary/Poly Haven (Karton), Lennart Demes/ambientCG (Holz), Poly Haven
  („Comfy Cafe“).
- **Import:** die `.import`-Dateien liegen im Repo (VRAM-Kompression, Mipmaps, Normal-Maps als
  Normal-Map); `godot/.godot/` nicht. Ohne Import (frischer Checkout, Tests) lädt
  `AmsterdamStyle.tex()` die Rohdateien.
