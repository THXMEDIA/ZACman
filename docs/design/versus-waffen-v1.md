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
