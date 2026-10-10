# Versus-Waffen (Blitzkanone, Kaugummi) – Prüfung v1

**Stand:** 10.10.2026 · **Art:** Machbarkeit und Designprüfung, noch nichts gebaut · **Anlass:** Wunsch des Inhabers.

## Wunsch
- **Blitzkanone:** ein Schuss, nur aus einem im Labyrinth findbaren Extra; lähmt den Gegner bei Treffer für einige Zeit.
- **Kaugummi:** Nahkampfwaffe; klebt den Gegner temporär fest und macht ihn danach für Zeit X langsamer. Kann gedroppt werden und ist dann eine Falle; danach Zeitsperre, bis er wieder verfügbar ist.

## Technischer Befund (aus dem Code)
- Versus „Gegenwind“ ist ein **Spiegelrennen**: jeder läuft in seiner eigenen Kopie desselben Labyrinths, der Gegner ist nur ein Punkt auf der Minimap (Position als Zelle, 5 Meldungen pro Sekunde, `prog`). Es gibt keinen gemeinsamen Raum. Ein „Treffer“ im Sinne von Zielen und Berühren existiert heute nicht.
- Das Netz ist vertrauensbasiert (Freundes-Matches): jeder Client simuliert nur sich, nur die Rundenentscheidung trifft der Host. Waffen passen dazu, wenn der **Getroffene den Effekt auf sich selbst anwendet** (er prüft Strahl oder Radius und darf ablehnen).
- Da beide Labyrinthe identisch sind, lassen sich **Zellen** zwischen den Kopien spiegeln: eine Falle in Zelle (r, c) kann beim Gegner dieselbe Zelle belegen. Das braucht keine Positionssynchronisation.
- Ein **Phantom** (der Gegner als durchscheinende Figur in der eigenen Kopie, Position und Blick ca. 15 Hz) ginge, ist aber neues Protokoll (Protokoll 3, ungesicherter Kanal), Interpolation, Darstellung und eine Verzögerung von rund 100 ms. Erst damit sind Zielen und Nahkampf sinnvoll.
- Die Regeln der Bewegung bleiben einhaltbar: Lähmung und Kleben sperren nur die Bewegung, die Kamera bleibt frei (E8e); Anzeige ohne Flackern über 3 Hz, mit „Effekte reduzieren“ ruhiger. Der Dash bietet Gegenspiel (Schutzphase), solange Treffer vorher telegraphiert werden.

## Befunde der Design-Prüfung (Game-Designer)
**Kritisch**
1. Ein unsichtbarer, sofortiger Blitz lässt sich nicht kontern; der Dash-Schutz wäre Zufall. → Aufladen 0,5 s sichtbar (Leuchtlinie) plus Warnton beim Opfer, Dash muss in diesem Fenster reagieren können.
2. Lähmung neben einem Geist kostet ein Leben (Todesspirale gegen den, der ohnehin zurückliegt). → Nach jedem Waffeneffekt 3 s Immunität gegen Waffen und 1,5 s gegen Geister.
3. Zeiten mit Treffer sind nicht vergleichbar. → Waffen-Matches nicht aufs Brett `woche`; Lobby-Schalter „Extras an/aus“, Zeiten nur ohne Extras aufs Brett.

**Wichtig**
- Schneeball: Die Falle ist der Schwachpunkt (der Führende legt sie hinter sich, der Verfolger läuft hinein). → Falle verfällt nach 15 s, bleibt für den Gegner sichtbar, Sperre beim Leger.
- Das Extra liegt auf der Route = Glück der Seed-Position. → Freiwillige Wette: weit abseits in einer Sackgasse mit messbarem Umweg.
- Chat-Duell und Kaninchen: Während einer schlechten Kondition keine Waffentreffer; der Chat beeinflusst die Waffen nicht.
- Treffer prüft der Getroffene gegen den gemeldeten Strahl (Toleranz ca. 0,5 m), nicht blind.

**Startwerte (Schätzung, nicht gemessen)**

| Wert | Start |
|---|---|
| Blitz-Aufladung | 0,5 s sichtbar |
| Blitz-Lähmung | 1,2 s |
| Kleben | 1,2 s, danach 2 s mit 60 % Tempo |
| Kaugummi-Sperre | 15 s (Treffer), 25 s (Falle) |
| Falle | verfällt nach 15 s |
| Extras | 1 pro Spieler und Runde, in einer Sackgasse |
| Immunität nach Effekt | 3 s gegen Waffen, 1,5 s gegen Geister |

Messung per Bot-Simulation (wie `qa_dash_gain.gd`): Zeitverlust pro Treffer, Begegnungsrate, Trefferquote mit und ohne Dash-Reaktion, Siegquote des Führenden (soll um höchstens 5 Prozentpunkte steigen).

## Empfehlung: zwei Stufen
- **Stufe 1 (ohne Phantom, ca. 8–12 h Studio-Zeit, Schätzung):** Kaugummi **nur als Falle** (Zelle in die Kopie des Gegners gespiegelt, kleben plus verlangsamen) und Blitz als **Fernschuss mit Warnung** (kein Zielen: Auslösen schickt „Blitz“, der Gegner hat 0,5 s Warnung, in der er per Dash ausweichen kann, danach Lähmung). Findbares Extra, HUD-Chip, Netz-Nachrichten, Immunitätsfenster, Lobby-Schalter, Tests.
- **Stufe 2 (nur nach Playtest, ca. 10–15 h zusätzlich, Schätzung):** Phantom, gezielter Blitz, Nahkampf-Kaugummi.
- **Nicht tun:** Chat steuert Waffen; Waffen im Solo-Speedrun; Waffen auf dem Brett `woche`.

## Offene Entscheidungen (Inhaber)
1. Kaugummi zuerst nur als Falle (Empfehlung: ja)?
2. Blitz in Stufe 1 ohne Zielen, nur mit Warnung (Empfehlung: ja), oder gleich Phantom?
3. Extra-Ort: Sackgasse (Empfehlung) oder auf der Route?
4. Immunitätsfenster nach Treffern (Empfehlung: ja)?
5. Zeiten aus Waffen-Matches: eigenes Brett oder gar keins (Empfehlung: Lobby-Schalter, nur ohne Extras aufs Brett)?

---

## Update 10.10. (Entscheidungen und neuer Wunsch des Inhabers)

**Entschieden:** Kaugummi zuerst als **Falle**. Blitz **mit Ziel** (also kein Fernschuss). **Neuer Wunsch:** statt Spiegelrennen beide Spieler in **einem** Labyrinth; jeder hat **eigene Kugeln** zum Einsammeln; die Kugeln sind für den Gegner **sichtbar**.

### Prüfung: ein gemeinsames Labyrinth
**Machbar, und es ist die richtige Grundlage für „Blitz mit Ziel“.** Zielen, Treffen und Fallen brauchen einen gemeinsamen Raum; das Phantom aus Stufe 2 wäre dann kein Phantom mehr, sondern der echte zweite Spieler. Es ist aber ein Umbau des Versus, kein Zusatz.

**Was sich ändert**
- Beide Spieler laufen im selben Labyrinth (gleicher Seed wie heute), jeder auf eigener Startzelle (zwei gegenüberliegende offene Zellen statt einer).
- Der Gegner wird als Figur mit Position und Blickrichtung gezeigt (ca. 15–20 Hz, ungesicherter Kanal, interpoliert; Protokoll 3). Heute kennt das Netz nur Fortschritt und Zelle (5/s).
- **Kugeln je Spieler:** deterministisch aus dem Match-Seed in zwei Mengen geteilt (zwei Farben, zwei Multimeshes). Jeder frisst nur die eigene Menge; die Kugeln des Gegners bleiben sichtbar und verschwinden, wenn er sie frisst (Nachricht `eat`). Zeit und Sieg wie heute: wer zuerst alle eigenen Kugeln hat, gewinnt die Runde.
- **Verteilung:** abwechselnd über das ganze Labyrinth gestreut (nicht in Hälften), damit beide dieselben Wege laufen müssen, sich oft begegnen und die Mengen gleich schwer sind. Power-Kugeln ebenfalls je Spieler.
- **Geister:** Der günstige Weg sind **private Geister** (jeder Client simuliert seine eigenen, wie heute; sie jagen nur den eigenen Spieler und treffen nur ihn). Kein Netzverkehr für Geister, kein Host nötig. Preis: Man sieht die Geister des Gegners nicht. Der teure Weg wäre ein geteilter Geisterzustand mit Host-Autorität (zusätzlich ca. 10–15 h, Schätzung); er wird erst für Koop gebraucht.
- **Spieler gegeneinander:** keine Körperkollision (sonst Blockieren und Ärgern), die Interaktion läuft nur über Waffen.
- **Waffen:** Der Treffer wird beim Schützen gegen die interpolierte Figur geprüft, der Getroffene prüft gegen seine eigene Position (Toleranz ca. 0,5 m) und wendet den Effekt auf sich selbst an. Telegraph, Dash-Gegenspiel und Immunitätsfenster wie im Design-Review.

**Was gleich bleibt:** Commit-Reveal, Best-of-3, Host entscheidet die Runde, Chat-Duell, Kaninchen je Spieler (wirkt auf den Client des Aufhebers), Vertrauensmodell, Zeiten im Modus `pvp` (nicht mit den Solo-Brettern vergleichbar; weniger Kugeln je Spieler = kürzere Runden).

**Risiken**
- Der Netzcode-Umfang wächst (Positionen, Kugeln, Waffenereignisse) und muss wie bisher feindliche Pakete abfangen (Typen, Wertebereiche, Raten).
- Latenz: Treffer sind bei 100 ms Verzögerung tolerant zu prüfen; Zielen auf eine verzögerte Figur fühlt sich anders an als lokal.
- Es ist ein anderes Spiel als „Gegenwind“ als Spiegelrennen: Wegblockieren per Waffe, Kugeln des Gegners lesen. Das Spiegelrennen ohne Waffen könnte als Modus „Rennen“ bleiben (billig: es ist schon da).
- Die bestehenden Versus-Tests (53 + 50 + End-to-End) müssen für Protokoll 3 angepasst werden.

### Neue Empfehlung (Reihenfolge)
1. **Stufe A, Grundlage (ca. 12–18 h Studio-Zeit, Schätzung):** gemeinsames Labyrinth, zwei Startzellen, Gegner als Figur, Kugeln je Spieler sichtbar, private Geister, Protokoll 3, Tests. Ohne Waffen, als neuer Versus-Modus neben dem Spiegelrennen. Danach Handtest zu zweit.
2. **Stufe B, Waffen (ca. 8–12 h, Schätzung):** Kaugummi als Falle (sichtbar, nur für den Gegner, verfällt nach 15 s, Sperre 25 s), Blitzkanone mit Ziel (Aufladen 0,5 s sichtbar, Warnton, Dash weicht aus, Lähmung 1,2 s), findbares Extra in einer Sackgasse, Immunitätsfenster, Lobby-Schalter „Extras“.
3. **Stufe C, nur nach Playtest:** Nahkampf-Kaugummi (Kleben 1,2 s, danach 2 s mit 60 % Tempo).

### Fragen an den Inhaber (mit Empfehlung)
1. Geister im gemeinsamen Labyrinth **privat** (Empfehlung) oder geteilt (teurer, Koop-Grundlage)?
2. Kugeln **abwechselnd gestreut** (Empfehlung) oder in Zonen?
3. Darf man Kugeln des Gegners **fressen** (klauen)? Empfehlung: nein, nur sehen.
4. Spieler **ohne Körperkollision** (Empfehlung)?
5. Das Spiegelrennen als Modus **behalten** (Empfehlung) oder ersetzen?

---

## Update 10.10. (2): Entscheidungen des Inhabers und Stufe A gebaut

**Entschieden (Inhaber):** Geister **geteilt**; Kugeln **abwechselnd**; Kugeln des Gegners **nicht fressbar**, nur sichtbar; Spieler **kollidieren**; Spiegelrennen **bleibt** als Modus. Blitzkanone für Stufe B **kein Einzelschuss, sondern eine „Staffette“**: mehrere Blitze im Abstand von 5 Sekunden, jeder mit begrenzter Lähmung bzw. Verzögerung beim Gegner. (Lesart, vor Stufe B zu bestätigen: ein Extra lädt N Blitze, je Treffer z. B. 0,8 s Lähmung, danach 5 s bis zum nächsten.)

**Gebaut (Branch `feature/arena`), Stufe A ohne Waffen:**
- Lobby-Schalter MODUS (nur Host, Standard Arena); der Client sieht den Modus des Hosts.
- Startzellen gespiegelt (das Labyrinth ist spiegelsymmetrisch), Kugeln paarweise gespiegelt verteilt (links Schachbrett über 2×2-Blöcke, Spiegelkugel an den anderen), Power-Kugeln links Host, rechts Client. Beide Mengen sind Spiegelbilder.
- Eigene Kugeln in Themefarbe, gegnerische kleiner und matter in **Flieder `#dda6ff`** (das alte Orange war praktisch der Lauerer-Geist); Minimap: gegnerische als Ringe, Gegner als Pfeil.
- Gegner als Figur in Augenhöhe mit Namensschild, Kollisionskörper; der Dash geht durch; überlappend, während der Unverwundbarkeit nach einem Leben und nach 1,5 s Dauerkontakt ist er kurz durchlässig (gegen Einsperren).
- Geister: Host simuliert, je Geist ein Stammspieler (gerade: Host, ungerade: Client), Wechsel nur bei ≥ 4 Zellen Vorsprung, dann 2 s Halt. Client bewegt Puppen nach Snapshots (20/s). Jeder entscheidet über die eigenen Leben; der Geist, der jemanden erwischt, geht 3 s ins Haus. Power-Fenster gemeinsam (Host öffnet es beim gemeldeten Fressen einer Power-Kugel).
- Pause hält die geteilte Welt nicht an (wie die Uhr im Versus).
- Arena-Zeiten kommen auf **kein** Brett (halbe Kugelmenge, nicht vergleichbar).
- Protokoll 3 (pos, eat, gh, ghit, gate, power, mode), Plausibilitätsprüfungen, Tests: `test_arena.gd`, `arena_e2e.gd` (zwei echte Instanzen), Screenshots `tools/qa/qa_arena_shots.gd`.

**Offen nach dem Handtest:** Besitz des Power-Fensters (nur der Fresser darf Geister fressen?), Kaninchen-Ort fair zwischen beiden Starts, Rückmeldung beim Anstoßen, Legende beim Countdown, Gleichstand = kein Punkt statt Host.
