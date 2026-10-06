# Bewegungs-Paket: Dash und Kehrtwende (Regelversion 2)

Stand 06.10.2026. Gilt in allen Speedrun-Leveln, für alle Spieler gleich, nicht abschaltbar.

## Tasten
- **Dash:** Shift. **Kehrtwende:** Q. Beide werden in `main.gd` (`_register_move_actions`) im Code registriert, `project.godot` bleibt unberührt. Anzeige der Tasten in EINSTELLUNGEN folgt der InputMap.

## Kehrtwende
- Schnitt (yaw + PI), keine Kamerafahrt. Neigung, Sichtfeld, Augenhöhe unberührt (E8e). Nur auf Tastendruck, nie über Konditionen, Kaninchen oder Chat. 0,4 s Pause (weit unter 3 Hz).
- Gilt auch in den Explorer-Städten.

## Dash
- 18 m/s für 0,2 s (ca. 3,6 m) in Richtung der Bewegungseingabe (nach einer Kondition wie Fear & Loathing, also kein Gratis-Gegenmittel), ohne Eingabe geradeaus.
- Normale Geister schaden nicht während des Dash und 0,15 s danach; verängstigte werden gefressen.
- Ladungen: 1 am Start, maximal 2. +1 pro gefressenem Geist oder Frucht, nie über die Zeit. Reset bei Levelstart und Lebensverlust. Kugeln kosten nichts.
- Startet nur bei mindestens 1 m freier Strecke (keine verschwendete Ladung vor Wänden). 0,5 s Pause.
- Zeitgewinn: ca. 0,48 s pro Dash (0,3–0,5 % einer Level-Zeit), gemessen mit `tools/qa/qa_dash_gain.gd`. Die Zielzeiten (`target_s`) bleiben Zeiten ohne Dash.

## Regelversion 2 und Bretter
- Zeiten ohne Dash/Kehrtwende sind mit Zeiten mit ihnen nicht vergleichbar. Speicherstand-Version 4 (`speedrun.gd`, `leaderboard.gd`): beim ersten Laden verschiebt sich jedes Brett einer älteren Datei ins Archiv unter `<Schlüssel>|regel1` (bleibt erhalten, wird nie angezeigt). Die Bretter beginnen neu.

## Weitere Schritte (Vorschläge, noch nicht gebaut)
Karten-Modi (Voll/Lokal/Aus) mit Kompass, Zwischenzeiten bei 25/50/75 %, Etagen-Spike.
