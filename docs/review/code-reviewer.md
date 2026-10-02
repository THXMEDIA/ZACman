# Zusätzliche Anweisungen für `code-reviewer`

Gilt dauerhaft für dieses Projekt, zusätzlich zum Brief (`docs/review/brief.md`).
Anweisungen für ein einzelnes Review schreibst du direkt in den Auftrag.

- Steam Deck und Controller sind kein Ziel (siehe Brief). Die Entscheidungen im Brief gelten; prüfe ihre Umsetzung, besonders die Schlüssel von Bestzeiten/Boards (`levels.gd::board_key`), die Migration alter Spielstände und die zwei Uhren `now`/`real_now` in `main.gd`.
