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
| Ninenzaka | Nordstück ab Shijo (endet an einem Tempeltor) und Südstück bis Kiyomizu; die Mitte ist Tempelbezirk (geschlossen) | Kiyomizu-dera mit der Bühne auf dem Pfeilergerüst; hier ist der Ausgang |
| Torii-Gasse | Ost-West, Tunnel aus Torii (Vorbild Fushimi Inari) | kleiner Inari-Schrein |
| Seitengasse, Sannenzaka | Querverbindungen | – |

Außerhalb der Karte, nie gefaltet: die Higashiyama-Hügel im Osten, Hügel ringsum, Kyoto Tower im Südwesten, Kasumi-Nebelbänder.

Start: Westende der Shijo-dori, Blick nach Osten auf das Schreintor. Ausgang: vor der Kiyomizu-Bühne. Der kürzeste Weg (72 Zellen, ≈ 33 s) führt über die Hanamikoji und die Sannenzaka, vorbei an Pagode, Torii-Gasse und Maiko (Game-Design-Review K1). Die Kugeln folgen den Straßenmittellinien: der Weg vom Start, immer die Äste durch die Torii-Gasse und zur Pagode, plus zwei vom Level-Seed gewählte Äste (der Seed ist pro Stadt fest, wie in Tokyo). Jede Sackgasse endet auf einem Wahrzeichen (drei kleine Tempeltore ergänzt).

## Look (`kyoto_style.gd`, `kyoto_card.gdshader`)

- **Eine MultiMesh für die ganze Stadt:** jede Karte ein Quad; Art, Breite, Höhe und Variation in `INSTANCE_CUSTOM`. Der Shader druckt prozedural: Machiya (Koshi-Gitter, Noren, Inu-yarai, Papierlaterne), Läden, Tempelmauern mit den fünf Linien (Suji-bei), Kiefern, Dachkarten, die Wahrzeichen, Torii, Figuren, Hügel, Turm, Nebel. Keine Texturen, keine Fremdbilder.
- **Falten:** Scharnier an der Kartenunterkante; ab 24 m beginnt das Umklappen, ab 46 m liegt die Karte (86°). Die liegende Karte wird auf die Tiefe ihres Blocks gekürzt (Instanzfarbe), sie liegt nie über einer Straße. Wahrzeichen und Backdrop (+100) falten nie, jede Straße zeigt ihr Ziel. Die Pagode besteht aus zwei gekreuzten, beidseitig bedruckten Karten.
- **Aufklapp-Intro:** Beim Start liegt das Buch flach und stellt sich in 1,8 s von nah nach fern auf (Kamera unberührt; mit „Effekte reduzieren“ entfällt es). Einmaliger Hinweis: „Die Stadt klappt beim Laufen auf. Ruhiger: Esc → Effekte reduzieren“.
- **Blöcke:** Die Kollisionsboxen sind 3 m hoch (Physik), sichtbar nur als 6 cm dünner gedruckter Grundriss (`kyoto_slab.gdshader`).
- **Boden:** Washi; Straßen in blassem Blau mit Bokashi zum Rand und Steinpflaster; der Bordstein ist eine Tuschelinie genau an der Kollisionskante (`kyoto_floor.gdshader`).
- **Himmel:** Bokashi von Preußischblau oben zu Papier am Horizont; papierfarbener Nebel als Luftperspektive.
- **Farbregeln:** Gold nur für Kugeln (`#FFC714`), Grün nur für den Ausgang (`#22C460`); Zinnober nur als Akzent (Torii, Schreintor, Laternen, Maiko).
- **Kugeln:** Blattgold mit Tuscherand (`kyoto_orb.gdshader`), damit sie auch in Graustufen und bei Tritanopie vom hellen Papier abheben.
- **Torii-Gasse:** Pfosten bei ±2,3 m; ein Kollisionsgeländer füllt den Streifen vom Pfosten bis zur Mauer, der Boden druckt dort Kies und eine Tuschelinie (Regel „Tuschelinie = Kollisionskante“ bleibt gültig).
- **Minimap:** dunkle Straßen (AI1), helle Blöcke (AI3), Ausgang als grünes Quadrat (für alle Explorer-Städte).
- **Ton:** keine Geister-Sirene in Kyoto (`siren: false`); eigene Kyoto-Musik ist offen.
- **Schrift:** keine in der Stadt (kein Fake-Japanisch). Einzige Beschriftung: „出口 EXIT“ am Ausgang (Standardzeichen, auch in Tokyo verwendet).

## Ausgang (`kyoto_exit.gd`)

Aufgeklappte Seitentür mit grünem Licht vor der Kiyomizu-Bühne, grüne Lichtfläche auf der Seite, und ein langes grünes Lesebändchen (zwei gekreuzte Streifen), das vom Himmel bis über die Tür hängt (15 m, ohne Nebel, von weit her über den Dächern sichtbar). Puls 0,5 Hz. Auslöseradius 1,2 m; ab 4,5 m einmal der Hinweis „Grüne Tür: umblättern in den Speedrun“. Banner: „NÄCHSTE SEITE: SPEEDRUN“ / „Umblättern – los zum Speedrun!“.

## Technik und Budget

- Statische Draw Calls: Wand-MultiMesh, Boden, Karten-MultiMesh, Himmel (≤ 6, Test). Keine Lichter, kein Glow, kein SSR.
- Der Falt-Abstand wird im Vertex-Shader pro Karte aus `MODEL_MATRIX` und Kameraposition berechnet; die MultiMesh hat eine feste große AABB.
- Kein Verkehr. Figuren stehen in Hauseingängen (keine Kollision nötig). Hinzu kommen seit der Hardware-Abnahme (06.10.2026) Kirschblütenbäume und langsame Passanten, siehe unten.

### Kirschblüte und Passanten (Hardware-Abnahme 06.10.2026)

- **Kirschblütenbäume** (`K_SAKURA`, `kyoto_scenery.gd`: `tree_cards`): Karten im selben Druck (Tuschestamm mit Gabel, Blütenwolken in einem blassen Zinnober-auf-Papier-Ton `KyotoStyle.BLOSSOM`, Schattenseite in Blau, einzelne Zinnoberblüten). Entlang der Fassaden vor den Häusern (Shijo, Hanamikoji, Seitengassen), hinter Tempelmauern (Torii-Gasse, Pagodenblock) höher, mit Krone über der Mauer. Größe, Spiegelung, Neigung (nur hinter Mauern) und Lage kommen aus dem Level-Seed (eigener Zufallsstrom `seed ^ TREE_SEED_XOR`, die Häuser bleiben wie sie waren). Sie falten wie die Häuser, haben keine Kollision, decken keine Hauseingangsfigur ab.
- **Blütenblätter** (`kyoto_petal.gdshader`): bis zu 240 Blätter in einem MultiMesh, Animation nur im Vertex-Shader (0,1 Zyklen/s, 0,2 Drehungen/s, kein Flackern), Ein- und Ausblenden über die Größe. „Effekte reduzieren“ blendet sie aus.
- **Passanten** (`kyoto_life.gd`, Traffic `"kyoto"`): 19 Papierfiguren (Yukata, Wagasa-Schirm, Tourist mit Rucksack, keine Maiko) gehen mit 0,7–1,1 m/s Gassen hin und her oder einen Rundweg (Shijo Ost, Ninenzaka Süd, Seitengasse, Hanamikoji). Ein MultiMesh, Karten drehen sich (nur Gierwinkel) zur Kamera und spiegeln sich in Gehrichtung, keine Allokation pro Frame. Harmlos wie in Tokyo: kein Leben-Verlust, nur der sanfte Schubs (Radius 0,4 m); die Wege halten 1,4–2,5 m Abstand zu den Fassaden der 6 m breiten Gassen (Test misst die freie Gasse). Die Kamera wird nie berührt. „Effekte reduzieren“: die Passanten stehen still.
- Draw Calls: Kyoto insgesamt 7 plus Ausgang (Wände, Boden, Karten, Himmel, Blütenblätter, Passanten, Kugeln).

## Tests

- `godot/tests/test_kyoto.gd` (94 Checks, u. a. Bäume und Passanten (Determinismus, Lage, freie Gasse, Budget, keine Allokation), liegende Karten bleiben auf ihrem Block, Route über Hanamikoji, Kollisionshöhe der gebauten Boxen, Geländer, Intro, Half-Float-Grenzen): Raster, Erreichbarkeit, Spuren, Karten auf der Kollisionskante, Wahrzeichen, Determinismus, Budget, Komfort, Palette, Ausgang.
- `godot/tests/bot_test.gd`: Start über den KYOTO-Button, Komfort-Schalter, Ausgang → Speedrun, Theme-Reset.
- Screenshots: `tools/qa/qa_kyoto_shots.gd` (k1–k18, k16–k18: Bäume, Passanten, reduziert).

## Rechte (publishing-manager, 04.10.2026 – keine Rechtsberatung)

Geringes Rechtsrisiko, mittleres Rufrisiko. § 46 jap. UrhG erlaubt die Verwertung von Bauwerken (außer Nachbau und Verkauf als Bild); Kyoto Tower ist in Japan gemeinfrei (Architekt † 1966), eine 3D-Marke ist nicht gefunden, aber nicht ausgeschlossen. Hausordnungen der Tempel betreffen Fotos vor Ort, keine Nachbildungen. Auflagen: keine Gewalt oder Zerstörung an Sakralorten (auch nicht in künftigen Modi), keine Schrift auf Torii/Laternen, Theater ohne Shochiku-/Maneki-Bezug, Kyoto Tower nur ferne Silhouette ohne Logo, Maiko respektvoll und ohne Interaktion, kein Sprung von der Kiyomizu-Bühne als Gag. Marketing: nur eigene Spielbilder, kein einzelnes Bauwerk als Key-Art, „Kyoto“ als Ort ja, Bauwerksnamen nicht als Titel, „Geisha“ meiden, kein „offiziell“. Vor der Steam-Seite ⚖️: Markenrecherche Kyoto Tower (J-PlatPat), ggf. Tempelnamen; Kultur-Check durch Muttersprachler.

### Frühere Einschätzung

Alle Bauwerke sind historisch (Kennin-ji, Yasaka-Pagode 1440, Kiyomizu-dera 1633, Nishi-rōmon 1497) oder werden nur stilisiert als Silhouette gezeigt (Kyoto Tower 1964, Theater nach Minami-za). Japan erlaubt die Abbildung von Bauwerken (§ 46 jap. UrhG); keine Namen, Logos, Wappen oder Schriftzüge im Spiel. Prüfpunkte vor der Steam-Seite: Kyoto-Tower-Silhouette (Marke des Betreibers?), Theater-Fassade (Betreiber Shochiku, keine Maneki-Namen, keine Wappen), Darstellung von Maiko (respektvoll, keine Karikatur).

## Offen

- Hardware-Abnahme durch den Inhaber: Falten im Laufen (Übelkeit?), fps, Shader-Kompilier-Hänger beim ersten Kyoto-Frame.
- Faltdistanz: Game Design will sie kürzer (sichtbarer), UX länger (langsamere Drehung, weniger Übelkeit) – Entscheidung nach Hardware-Test, heute 24/46 m.
- Goshuin-Stempel an den Wahrzeichen als Sammelziel (Game Design) – Inhaber-Entscheidung, weil Explorer bisher „ohne Abschluss“ ist.
- Eigene Kyoto-Musik (pentatonisch), Kugeln als Melodie.
- Optional später: Seitenumblättern als Übergang in den Speedrun (heute: Banner wie Tokyo).
