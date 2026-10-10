# Etagen-Spike (ZAP-7) – Ergebnis

**Stand:** 10.10.2026 · **Art:** Wegwerf-Prototyp, nur Debug-Builds (Taste **F4**), nicht Teil eines Levels, keines Brettes, keines Speicherstands.

## Was gebaut ist
- `scripts/etagen_spike.gd`: F4 im laufenden Speedrun- oder Training-Level baut über dem Level eine zweite, geisterfreie Etage (gleiche Größe, anderer Seed, Look „Riff“), 12 m höher, mit eigenen Kugeln.
- Drei **Aufzugszellen** (in beiden Etagen offen, in 30/60/90 % Entfernung vom Start sortiert), gelber Pad-Marker mit Lichtstrahl. Betreten = Schnitt auf die andere Etage (nur die Spielerhöhe springt, Yaw und Pitch bleiben unberührt, E8e). Der Aufzug ist danach 1 s tot und erst wieder scharf, wenn man von allen Aufzugszellen heruntergetreten ist.
- Nur die aktuelle Etage ist sichtbar; Minimap zeigt die aktuelle Etage, Chip „E1/E2“ unter der Karte. Geister bleiben in Etage 1 und können oben nicht treffen.
- F4 noch einmal oder jeder Levelwechsel entfernt die zweite Etage. Tests: 9 Checks im BotTest (Aufzug, Schutz gegen Zurückspringen, Yaw/Pitch, Aufräumen).

## Antworten auf die Spike-Fragen
| Frage | Befund |
|---|---|
| Trägt der Look über zwei Etagen? | Ja. Zweite Etage nutzt dasselbe Theme, Wände und Boden sehen gleich aus (Screenshot-Vergleich im Software-Renderer). |
| Nebel und Spielerlicht? | Ja. Nebel ist global, das Spielerlicht hängt am Spieler; 12 m Abstand plus Boden und Decke trennen die Etagen, nichts schimmert durch. |
| Kollision? | Funktioniert ohne Änderung: jede Etage hat ihren eigenen Wandkörper, 12 m versetzt. |
| Kosten? | Es ist immer nur eine Etage sichtbar; Messung der fps auf echter Hardware steht aus. |

## Was der Spike bewusst nicht löst (Integrationskosten für ein echtes Etagen-Level)
- Geister-KI, Kaninchen, Konditionen (Matrix-Noclip-Rettung, Stromausfall, Looks) und die Referenzroute kennen nur eine Etage. Bei einem echten Level müssten Konditionen pro Etage gelten.
- Geister „warten am Aufzug“ (Konzept) ist nicht gebaut.
- Bestenliste, Zielzeit und Zwischenzeiten kennen keine Etagen; ein Etagen-Level wäre ein neues Level im Pool, die sechs bestehenden bleiben unberührt (Regelversion!).
- Die Minimap zeigt eine Etage; Aufzugsmarker fehlen noch.

## Empfehlung
Der technische Kern trägt. Ob die Etagen *spielerisch* tragen (Umweg-Preis, geisterfreie Etage, Orientierung ohne Gesamtkarte), zeigt nur ein Spieltest: F4 drücken, Aufzug nehmen, oben Kugeln sammeln. Danach entscheiden, ob ein neues Etagen-Level in den Pool soll (geschätzt 12–18 h Studio-Zeit, nicht gemessen).
