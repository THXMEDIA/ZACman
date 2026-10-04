# Multiplayer – Spezifikation v1 (E17)

**Stand:** 04.10.2026 · **Freigabe:** Inhaber, E17 (Paket a–e wie empfohlen) · **Studio-Konzept:** `studio/projekte/zapmaniac/multiplayer-konzept-v1.md` (BeachVibeStudio-Project)

Vorgabe des Inhabers: Multiplayer zu zweit – Koop (gemeinsam ein Speed-Maze-Level clearen) und gegeneinander („Gegenwind“). Im Versus stimmen die Twitch-Chats beider Speedrunner jeweils für ihren Spieler ab und entscheiden, welcher Spieler als Nächstes ein gutes oder schlechtes weißes Kaninchen bekommt.

## 1. Entscheidungen (E17)

| | Entscheidung |
|---|---|
| a | Chat-Duell „Hilfe oder Sabotage“, gewertet nach Anteilen je Chat |
| b | Versus als Spiegelrennen: gleiche Level, gleicher Seed, jeder in seiner eigenen Labyrinth-Kopie, Best-of-3 |
| c | Nur online, kein lokaler Splitscreen (zwei Mäuse nicht unterscheidbar, Controller kein Ziel, ein Stream = ein Chat) |
| d | Koop: geteilte Kugeln, gemeinsamer Lebenspool 4, ein Kaninchen für den Aufheber |
| e | Reihenfolge: Versus → Steam-Lobby → Koop (Koop braucht den Umbau auf Spieler-Objekte) |

## 2. Versus „Gegenwind“ (umgesetzt, Branch `feature/multiplayer`)

**Ablauf**
1. Startscreen → **VERSUS** → Lobby: Name, **HOSTEN** (Port, Standard 47823/UDP) oder **BEITRETEN** (IP-Adresse des Hosts).
2. Verbindung → Abgleich per Commit-Reveal: Beide senden erst den Hash ihres geheimen Seeds, dann den Seed. Der Match-Seed folgt aus beiden (`ChatDuel.match_seed`), keiner kann ihn wählen. Aus ihm leiten beide dieselben **drei verschiedenen Level** ab (`VersusSession.levels_for`).
3. Der Host drückt **MATCH STARTEN**. Jede Runde beginnt für beide gleichzeitig mit **3-2-1-LOS!** (statt Intro und „Uhr startet mit dem ersten Schritt“); die Uhr läuft ab LOS.
4. Während der Runde: oben ein Rennbalken (beide Namen, Fortschritt in %, Runde, Stand), der Gegner als magentafarbener Punkt auf der eigenen Minimap (seine Position in seiner Kopie).
5. **Rundensieg:** die niedrigere Zielzeit. Wer im Ziel ist, wartet; sobald die eigene Uhr die Zeit des Gegners überschreitet, ist die Runde verloren und endet sofort. Wer das letzte Leben verliert, verliert die Runde. Verlieren beide alle Leben: kein Punkt. Gleichstand auf die Hundertstel: Runde an den Host.
6. **Match:** Best-of-3 (wer zuerst 2 Runden hat). Danach SIEG / NIEDERLAGE / UNENTSCHIEDEN mit HAUPTMENÜ. Verlässt der Gegner das Match, gewinnt der Verbliebene kampflos.
7. Pause ist möglich, die Rennzeit läuft weiter (wie im Solo). NEUSTART ist im Versus gesperrt.

**Kaninchen im Versus**
- Ein Kaninchen pro Level wie im Solo, freiwillig.
- Gezogen wird mit dem **Rundengenerator des Matches** (`ChatDuel.round_rng(match_seed, runde)`), für beide Spieler identisch. Ohne Chat-Einfluss (60 %) bekommen beide also dieselbe Kondition; mit unterschiedlichen Anteilen entscheidet dieselbe Zufallszahl u, wer gut und wer schlecht bekommt.
- Nicht das „Kaninchen der Woche“: dessen Ergebnis wäre vorher bekannt und machte das Duell berechenbar.

**Chat-Duell (E17a)**
- Beide Spieler schalten am Startscreen ihren Twitch-Chat ein. Jeder Client liest beide Kanäle (eine anonyme IRC-Verbindung, zweiter Kanal per JOIN).
- `!gut` in Chat X = Spieler X soll ein gutes Kaninchen bekommen. `!schlecht` in Chat X = der **Gegner** von X soll ein schlechtes bekommen.
- Pro Chat Anteile: h = gut/n, s = schlecht/n (unter 3 Stimmen 0). d_A = h_A − s_B. Gut-Anteil p_A = 0,60 + 0,30·d − 0,10·d², begrenzt 20–80 % (dieselbe Kurve wie solo).
- Beispiele: beide Chats helfen → 80/80; beide sabotieren → 20/20; A hilft, B sabotiert → 60/60; A halb/halb, B hilft voll → 72,5/72,5.
- Normierung auf Anteile: 3 Stimmen in einem kleinen Chat wiegen so viel wie 3.000 in einem großen. Kein Befehl in Chat X kann Spieler X schaden.
- Das Duell läuft nur, wenn beide Chats verbunden sind; sonst ziehen beide mit 60 %. `!power`/`!fruit` wirken im Versus nicht.
- HUD-Chip: „Kaninchen: Duell 60 %“ bzw. „Kaninchen: 35 % gut“, sobald die Chats den Anteil verschoben haben.

**Bretter**
- Rundenzeiten zählen im Modus `pvp` (`level|brett|pvp`): Brett `woche`, oder `chat`, sobald das Duell den eigenen Anteil verschoben hat (Hilfe oder Sabotage). Kein Highscore im Versus.

**Netz**
- Godots `ENetMultiplayerPeer` als reiner Paket-Peer (JSON, keine RPCs). Nachrichten: `hello`, `reveal`, `round`, `prog` (5/s, unzuverlässig), `rabbit`, `finish`, `died`, `lost`, `bye` (Kopf von `versus_session.gd`).
- Jeder Client simuliert nur sein eigenes Rennen; es gibt keine Host-Autorität über Kugeln oder Geister und daher keinen Latenzvorteil.
- Vertrauensbasiert: Ein manipulierter Client könnte eine falsche Zeit melden. Für Freundes-Matches akzeptiert; vor öffentlichem Matchmaking oder Ranglisten-PvP nachzurüsten (z. B. Abgleich der Chat-Zählerstände, die `rabbit` schon mitsendet).
- Heute per IP und Port; NAT/Portfreigabe nötig. Steam-Lobby und Freundeseinladung folgen mit der Steam-App-ID (E16) und vermutlich einem Godot-Upgrade auf 4.4+ (GodotSteam-Multiplayer-Builds).

**Dateien**
- `scripts/chat_duel.gd` – Duell-Formel, Anteile, Rundengenerator, Commit-Reveal
- `scripts/versus_session.gd` – Protokoll, Handshake, Runden, Entscheidung
- `scripts/versus_controller.gd` – Lobby, Rundenablauf, Hooks in `main.gd`
- `scripts/versus_ui.gd` – Lobby, Rennbalken, Countdown, Ergebnis
- `scripts/twitch_chat.gd` – zusätzliche Kanäle (`join_extra`, Signal `channel_command`)
- Tests: `tests/test_chat_duel.gd`, `tests/test_versus_session.gd` (zwei Sitzungen in einem Prozess), `tests/versus_e2e.gd` + `tools/qa/versus_e2e.sh` (zwei Spielinstanzen über localhost)

## 3. Koop (nächster Schritt, noch nicht gebaut)

- Ein gemeinsames Labyrinth, eine gemeinsame Uhr; jede Kugel einmal; gemeinsamer Lebenspool 4; wer stirbt, startet allein neu (1,6 s unverwundbar, seine Kondition endet).
- Ein Kaninchen, der Aufheber bekommt die Kondition. Wirkt die Kondition auf die Welt (Taschenuhr), gilt sie für beide; wirkt sie auf Körper/Sinne (Matrix, Fear & Loathing, Stromausfall), nur für den Aufheber.
- Bestenliste `level|woche|coop` mit beiden Namen. Chat im Koop: Mittelwert der Anteile beider Chats.
- Technik: Umbau von `main.gd` auf Spieler-Objekte (Leben, Kondition, Eingabe, HUD pro Spieler), Host-Autorität für Geister, Kugeln, Kaninchen; Konditions-Looks pro Spieler (heute global über Environment und Shader-Uniforms).

## 4. Offen / Risiken

- Balance: Matrix (durch Wände) könnte ein Rennen allein entscheiden → Messung (E10) vor dem Feintuning.
- Sabotage läuft ins Leere, wenn Spieler schlechte Kaninchen liegen lassen → Playtest.
- Lesbarkeit von Rennbalken und Chip im 1080p-Stream → UX-Review.
- NAT: Ohne Steam-Relay müssen Spieler Ports freigeben.
