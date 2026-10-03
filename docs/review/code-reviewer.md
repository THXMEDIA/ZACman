# Zusätzliche Anweisungen für `code-reviewer`

Gilt dauerhaft für dieses Projekt, zusätzlich zum Brief (`docs/review/brief.md`).
Anweisungen für ein einzelnes Review schreibst du direkt in den Auftrag.

- Steam Deck und Controller sind kein Ziel (siehe Brief). Die Entscheidungen im Brief gelten; prüfe ihre Umsetzung, besonders die Schlüssel von Bestzeiten/Boards (`levels.gd::board_key`, `level|brett|modus`), die Migration alter Spielstände auf Version 3 samt `archive`, die zwei Uhren `now`/`real_now` in `main.gd` (Chat-Stimmen laufen auf `real_now`, Cooldowns auf `now`) und dass jede Zufallsentscheidung des Kaninchens über `Conditions.pick_condition` mit eigenem Generator läuft.
