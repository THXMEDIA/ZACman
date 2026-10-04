# Lizenzen von Fremdmaterial (Art)

Alles Sichtbare in ZAPmaniac entsteht per Code und Shader. Fremdmaterial ist nur,
was hier steht. Keine KI-generierten Inhalte (Steam-Offenlegung: nichts anzugeben).

| Datei | Herkunft | Lizenz | Nutzung |
|---|---|---|---|
| `godot/fonts/NotoSansCJKjp-Bold-Subset.otf` | Noto Sans CJK JP Bold (Adobe/Google, Projekt noto-cjk, https://github.com/notofonts/noto-cjk), Version aus dem Ubuntu-Paket `fonts-noto-cjk` (TTC-Index 0) | SIL Open Font License 1.1 — Text liegt daneben: `godot/fonts/OFL-NotoSansCJK.txt` | Schilder der Explorer-Stadt Tokyo (Label3D) |

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
