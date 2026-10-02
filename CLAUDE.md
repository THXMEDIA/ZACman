# Arbeitsweise

## Reviews
Das Projekt hat drei Review-Agenten in `.claude/agents/`: `game-designer`, `ux-reviewer` und `code-reviewer`. Sie lesen nur und liefern priorisierte Befunde; umgesetzt wird im Hauptkontext.

Dazu kommt der `qa-playtester`: Er startet das Spiel wirklich (Headless-Tests, Bot-Simulation, Screenshots über `tools/qa/qa_screenshots.gd`) und ändert keinen Spielcode. Er läuft vor den drei Reviewern, damit der `ux-reviewer` seine Screenshots bekommt. Zusätze: `docs/review/qa-playtester.md`.

- Nach einem größeren Feature, einer neuen Mechanik oder UI-Änderung und vor Merges die passenden Reviewer parallel starten.
- Im Auftrag an jeden Reviewer die geänderten Dateien und das Ziel der Änderung nennen, plus eventuelle Sonderanweisungen des Nutzers.
- Befunde zusammenfassen, Widersprüche zwischen den Rollen benennen und Kritisches zuerst umsetzen. Größere Designänderungen vorher mit dem Nutzer abstimmen.
- Projektkontext für die Reviewer steht in `docs/review/brief.md`, rollenspezifische Anweisungen in `docs/review/<rolle>.md`. Nächtliche Review-Berichte liegen in `docs/review/berichte/`.
