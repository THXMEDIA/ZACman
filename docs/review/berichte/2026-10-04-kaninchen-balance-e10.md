# Kaninchen-Balance nach E10 (04.10.2026)

Messung mit `tools/qa/qa_rabbit_balance.gd` nach E10 (b): Matrix 15 s, F&L-Drift 40 %, Spiegelung A/D + W/S. Strategie „zuerst“. Vorher (03.10.): Matrix −1,5 bis −2,4 s Wirkung. Jetzt im Mittel −2,9 s (bis −6,6 s in Klassik III), Gesamtbilanz der Wette −3,9 s. Grenzen: Der Bot gleicht Drift pro Frame aus (+0,3 s sagt daher wenig über Menschen), und die volle Spiegelung legt den Bot für die ganze Dauer lahm (+8,2 s = Dauer) – bei Menschen wird beides dazwischen liegen. Nächster Schritt: Playtest mit Menschen.

## Kaninchen-Wette: Messung per Bot (unverwundbar, feste Seeds)

Zeiten in Sekunden, in Klammern die Geisterkontakte (Gefahren-Näherung). Δt > 0 = langsamer.
Tabelle A: Δt gegenüber dem Lauf ohne Kaninchen (gierige Route) — das, was die Wette insgesamt kostet oder bringt.
Tabelle B: Δt gegenüber „Kaninchen ohne Wirkung“ mit derselben Strategie — die Wirkung der Kondition allein, ohne Umweg und ohne Routen-Effekt.

### Strategie „zuerst“, Tabelle A

| Kondition | Klassik I | Klassik II | Klassik III | Klassik IV | Offen | Durchbruch | Mittel |
|---|---:|---:|---:|---:|---:|---:|---:|
| ohne Kaninchen: t | 100.7 (2) | 162.1 (13) | 194.4 (15) | 212.8 (19) | 152.4 (11) | 183.5 (14) | 167.6 |
| Kaninchen ohne Wirkung (nur Umweg) | -4.8 (3) | -0.0 (10) | +5.5 (19) | +4.2 (11) | -5.4 (7) | -5.1 (13) | -1.0 |
| Matrix | -6.4 (1) | -0.0 (6) | -1.1 (22) | +1.3 (11) | -6.9 (6) | -10.1 (14) | -3.9 |
| Taschenuhr | -4.8 (0) | -0.0 (5) | +5.5 (15) | +4.2 (13) | -5.4 (6) | -5.1 (16) | -1.0 |
| Stromausfall | -4.8 (3) | -0.0 (10) | +5.5 (19) | +4.2 (14) | -5.4 (7) | -5.1 (13) | -1.0 |
| F&L A/D getauscht | +3.4 (4) | +8.2 (7) | +13.7 (22) | +12.4 (20) | +2.8 (7) | +3.0 (13) | +7.3 |
| F&L Drift | -4.6 (4) | +0.3 (9) | +5.8 (12) | +4.8 (5) | -5.1 (5) | -4.8 (15) | -0.6 |
| F&L Verzögerung | -4.1 (2) | +0.8 (12) | +6.4 (11) | +5.5 (8) | -4.5 (9) | -3.9 (14) | +0.0 |

### Strategie „zuerst“, Tabelle B

| Kondition | Klassik I | Klassik II | Klassik III | Klassik IV | Offen | Durchbruch | Mittel |
|---|---:|---:|---:|---:|---:|---:|---:|
| Matrix | -1.6 (1) | -0.0 (6) | -6.6 (22) | -2.9 (11) | -1.5 (6) | -5.0 (14) | -2.9 |
| Taschenuhr | -0.0 (0) | -0.0 (5) | +0.0 (15) | -0.0 (13) | +0.0 (6) | +0.0 (16) | -0.0 |
| Stromausfall | -0.0 (3) | -0.0 (10) | +0.0 (19) | -0.0 (14) | +0.0 (7) | +0.0 (13) | -0.0 |
| F&L A/D getauscht | +8.2 (4) | +8.2 (7) | +8.2 (22) | +8.2 (20) | +8.2 (7) | +8.2 (13) | +8.2 |
| F&L Drift | +0.2 (4) | +0.3 (9) | +0.3 (12) | +0.6 (5) | +0.2 (5) | +0.3 (15) | +0.3 |
| F&L Verzögerung | +0.7 (2) | +0.8 (12) | +0.9 (11) | +1.3 (8) | +0.8 (9) | +1.2 (14) | +1.0 |
