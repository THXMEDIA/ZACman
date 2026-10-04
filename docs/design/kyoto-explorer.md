# Explorer-Stadt Kyoto – Spezifikation v1

**Stand:** 04.10.2026 · **Freigabe:** Inhaber, Richtung G „Aizuri-Pop-up“ (Vorlage `studio/projekte/zapmaniac/art/explorer-stile-v1.md`), Stadt Kyoto mit echten, stilisierten Bauwerken · **Branch:** `feature/explorer-kyoto`

## Idee

Kyoto ist ein aufgeschlagenes Bilderbuch. Jedes Haus, jeder Baum, jedes Tor ist eine Pop-up-Karte aus Papier, gedruckt im Holzschnitt-Blau (Aizuri-e: Preußischblau in Stufen, Papierweiß, Tusche, sparsam Zinnoberrot). Karten in der Nähe stehen, weiter weg liegen sie flach auf der Seite. Läuft man, klappt die Stadt um einen herum auf. Die Kamera wird dabei nie bewegt (E8e); „Effekte reduzieren“ stellt alle Karten auf.

## Karte (`godot/scripts/kyoto_maze.gd`)

45 × 49 Zellen à 2 m. Echte Orte aus Gion und Higashiyama, frei angeordnet, damit jede Straße auf ein Wahrzeichen zuläuft.

| Straße | Verlauf | Blickpunkt am Ende |
|---|---|---|
| Shijo-dori | breite Ost-West-Achse | West: Theater am Fluss (Vorbild Minami-za) · Ost: zinnoberrotes Westtor des Yasaka-Schreins (Nishi-rōmon) |
| Hanamikoji | Teehaus-Straße nach Süden | Tor des Kennin-ji |
| Yasaka-dori | schmale Gasse nach Osten | fünfstöckige Yasaka-Pagode (Hōkan-ji) über der Tempelmauer |
| Ninenzaka | Hangweg nach Süden | Kiyomizu-dera mit der Bühne auf dem Pfeilergerüst; hier ist der Ausgang |
| Torii-Gasse | Ost-West, Tunnel aus Torii (Vorbild Fushimi Inari) | kleiner Inari-Schrein |
| Seitengasse, Sannenzaka | Querverbindungen | – |

Außerhalb der Karte, nie gefaltet: die Higashiyama-Hügel im Osten, Hügel ringsum, Kyoto Tower im Südwesten, Kasumi-Nebelbänder.

Start: Westende der Shijo-dori, Blick nach Osten auf das Schreintor. Ausgang: vor der Kiyomizu-Bühne. Die Kugeln folgen den Straßenmittellinien (vier vom Level-Seed gewählte Äste plus der Weg vom Start), alle enden am Ausgang.

## Look (`kyoto_style.gd`, `kyoto_card.gdshader`)

- **Eine MultiMesh für die ganze Stadt:** jede Karte ein Quad; Art, Breite, Höhe und Variation in `INSTANCE_CUSTOM`. Der Shader druckt prozedural: Machiya (Koshi-Gitter, Noren, Inu-yarai, Papierlaterne), Läden, Tempelmauern mit den fünf Linien (Suji-bei), Kiefern, Dachkarten, die Wahrzeichen, Torii, Figuren, Hügel, Turm, Nebel. Keine Texturen, keine Fremdbilder.
- **Falten:** Scharnier an der Kartenunterkante; ab 24 m beginnt das Umklappen, ab 46 m liegt die Karte (86°). Backdrop-Karten (+100) falten nie.
- **Blöcke:** Die Kollisionsboxen sind 3 m hoch (Physik), sichtbar nur als 6 cm dünner gedruckter Grundriss (`kyoto_slab.gdshader`).
- **Boden:** Washi; Straßen in blassem Blau mit Bokashi zum Rand und Steinpflaster; der Bordstein ist eine Tuschelinie genau an der Kollisionskante (`kyoto_floor.gdshader`).
- **Himmel:** Bokashi von Preußischblau oben zu Papier am Horizont; papierfarbener Nebel als Luftperspektive.
- **Farbregeln:** Gold nur für Kugeln (`#FFC714`), Grün nur für den Ausgang (`#22C460`); Zinnober nur als Akzent (Torii, Schreintor, Laternen, Maiko).
- **Schrift:** keine in der Stadt (kein Fake-Japanisch). Einzige Beschriftung: „出口 EXIT“ am Ausgang (Standardzeichen, auch in Tokyo verwendet).

## Ausgang (`kyoto_exit.gd`)

Aufgeklappte Seitentür mit grünem Licht vor der Kiyomizu-Bühne, grüne Lichtfläche auf der Seite, und ein langes grünes Lesebändchen, das vom Himmel bis über die Tür hängt (15 m, ohne Nebel, von weit her über den Dächern sichtbar). Puls 0,5 Hz. Auslöseradius 1,2 m. Banner: „NÄCHSTER HALT: SPEEDRUN“ / „UMBLÄTTERN — los zum Speedrun!“.

## Technik und Budget

- Statische Draw Calls: Wand-MultiMesh, Boden, Karten-MultiMesh, Himmel (≤ 6, Test). Keine Lichter, kein Glow, kein SSR.
- Der Falt-Abstand wird im Vertex-Shader pro Karte aus `MODEL_MATRIX` und Kameraposition berechnet; die MultiMesh hat eine feste große AABB.
- Kein Verkehr, keine Passanten mit Bewegung; Figuren stehen in Hauseingängen (keine Kollision nötig).

## Tests

- `godot/tests/test_kyoto.gd` (44 Checks): Raster, Erreichbarkeit, Spuren, Karten auf der Kollisionskante, Wahrzeichen, Determinismus, Budget, Komfort, Palette, Ausgang.
- `godot/tests/bot_test.gd`: Start über den KYOTO-Button, Komfort-Schalter, Ausgang → Speedrun, Theme-Reset.
- Screenshots: `tools/qa/qa_kyoto_shots.gd` (k1–k10).

## Rechte (Einschätzung, Bestätigung publishing-manager offen)

Alle Bauwerke sind historisch (Kennin-ji, Yasaka-Pagode 1440, Kiyomizu-dera 1633, Nishi-rōmon 1497) oder werden nur stilisiert als Silhouette gezeigt (Kyoto Tower 1964, Theater nach Minami-za). Japan erlaubt die Abbildung von Bauwerken (§ 46 jap. UrhG); keine Namen, Logos, Wappen oder Schriftzüge im Spiel. Prüfpunkte vor der Steam-Seite: Kyoto-Tower-Silhouette (Marke des Betreibers?), Theater-Fassade (Betreiber Shochiku, keine Maneki-Namen, keine Wappen), Darstellung von Maiko (respektvoll, keine Karikatur).

## Offen

- Hardware-Abnahme durch den Inhaber: Falten im Laufen (Übelkeit?), Lesbarkeit der Kugeln auf hellem Papier, fps.
- Optional später: Seitenumblättern als Übergang in den Speedrun (heute: Banner wie Tokyo).
