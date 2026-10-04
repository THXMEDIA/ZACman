# Multiplayer – Spezifikation v1 (E17)

**Stand:** 04.10.2026 (nach QA und Reviews) · **Freigabe:** Inhaber, E17 (Paket a–e wie empfohlen) · **Studio-Konzept:** `studio/projekte/zapmaniac/multiplayer-konzept-v1.md` (BeachVibeStudio-Project)

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
1. Startscreen → **VERSUS** (neben SPEEDRUN) → Lobby: Name (vorbelegt mit dem Twitch-Kanal), Twitch-Schalter, Block **DU HOSTEST** (eigene LAN-IP verdeckt mit ZEIGEN/KOPIEREN, Port, Standard 47823/UDP) – „oder“ – Block **DU TRITTST BEI** (IP-Feld verdeckt, ZEIGEN, Enter tritt bei). Keine IP steht je im Klartext ohne Klick im Bild (Streamer-Schutz). „VERBINDUNG KLAPPT NICHT?“ erklärt Firewall, Portweiterleitung und Tailscale/ZeroTier. Beitreten gibt nach 10 s mit „Host nicht erreichbar“ auf. Verlässt ein Gegner die Lobby, wartet der Host auf den nächsten.
2. Verbindung → Abgleich per Commit-Reveal: Beide senden erst den Hash ihres geheimen Seeds, dann den Seed. Der Match-Seed folgt aus beiden (`ChatDuel.match_seed`), keiner kann ihn wählen. Aus ihm leiten beide dieselben **drei verschiedenen Level** ab (`VersusSession.levels_for`).
3. Der Host drückt **MATCH STARTEN**. Jede Runde beginnt für beide gleichzeitig mit **3-2-1-LOS!** (statt Intro und „Uhr startet mit dem ersten Schritt“); die Uhr läuft ab LOS.
4. Während der Runde: oben mittig der Rennbalken („BEST OF 3 · RUNDE 1 · 0:0 · MATCHBALL …“, je Spieler „DU“-Markierung, Name, Balken, Prozent, Leben), darunter das Chat-Duell (beide Anteile + „Chat: !gut = Hilfe für …“), Ereignisse („BOB IM ZIEL · 1:02.31“, „BOB: STROMAUSFALL · schlecht · Sabotage von #alice wirkt!“, „BOB −1 LEBEN“) und, sobald der Gegner im Ziel ist, „BOB IM ZIEL 1:02.31 · NOCH 0:07.4“ (unter 5 s rot). Der Gegner ist ein oranger Punkt auf der eigenen Minimap (seine Position in seiner Kopie). Die Kaninchen-Titelkarte sitzt unter dem Rennbalken.
5. **Rundenentscheidung – der Host entscheidet** (beide melden, der Host wendet die Regeln an und schickt `result`, beide zeigen dasselbe):
   - beide im Ziel → niedrigere Zeit auf die Hundertstel; gleich → Host
   - im Ziel gegen tot/aufgegeben → wer im Ziel ist; die eigene Uhr über der Gegnerzeit beendet die Runde sofort („ZU LANGSAM“)
   - tot gegen noch laufend → wer noch läuft (nach 0,6 s Karenz, damit zwei fast gleichzeitige Tode als „beide tot“ zählen)
   - beide tot → wer weiter kam (Anteil Kugeln), sonst wer später starb, sonst kein Punkt
6. **Zwischenpause 12 s** mit Ergebnis (beide Zeiten und Abstand), Vorschau „Runde 2: Klassik III in 12 s · Chats, stimmt jetzt ab!“.
7. **Match:** Best-of-3 (wer zuerst 2 Runden hat). Danach SIEG / NIEDERLAGE / UNENTSCHIEDEN (neutral gefärbt) mit Rundentabelle, **REVANCHE** (beide drücken → neues Commit-Reveal auf derselben Verbindung, neue Level, Start nach 5 s) und HAUPTMENÜ. Verlässt der Gegner ein laufendes Match, gewinnt der Verbliebene kampflos; nach Match-Ende bleibt das Ergebnis stehen.
8. Pause ist möglich, die Rennuhr läuft weiter. Im Versus heißt HAUPTMENÜ „MATCH AUFGEBEN“ (mit Rückfrage), NEUSTART fehlt, der Countdown verschwindet hinter dem Menü.
9. Geister-Zufall (verängstigte Geister) folgt im Versus dem Match-Seed, nicht dem Rechner.

**Kaninchen im Versus**
- Ein Kaninchen pro Level wie im Solo, freiwillig.
- Gezogen wird mit dem **Rundengenerator des Matches** (`ChatDuel.round_rng(match_seed, runde)`), für beide Spieler identisch. Ohne Chat-Einfluss (60 %) bekommen beide also dieselbe Kondition; mit unterschiedlichen Anteilen entscheidet dieselbe Zufallszahl u, wer gut und wer schlecht bekommt.
- Nicht das „Kaninchen der Woche“: dessen Ergebnis wäre vorher bekannt und machte das Duell berechenbar.

**Chat-Duell (E17a)**
- Beide Spieler schalten am Startscreen ihren Twitch-Chat ein. Jeder Client liest beide Kanäle (eine anonyme IRC-Verbindung, zweiter Kanal per JOIN).
- `!gut` in Chat X = Spieler X soll ein gutes Kaninchen bekommen. `!schlecht` in Chat X = der **Gegner** von X soll ein schlechtes bekommen.
- Pro Chat Anteile: h = gut/n, s = schlecht/n (unter 3 Stimmen 0). **d_A = 0,5·h_A − 1,0·s_B** (Hilfe zählt halb, Sabotage voll). Gut-Anteil p_A = 0,60 + 0,30·d − 0,10·d², begrenzt 20–80 % (dieselbe Kurve wie solo).
- Warum die Gewichte (Design-Review 04.10., K1): Mit gleichen Gewichten gilt bei abgestimmten Chats immer d_A = h_A + h_B − 1 = d_B – beide Spieler hätten stets denselben Anteil, die Chats entschieden nie, *wer* das gute Kaninchen bekommt. Mit 0,5/1,0 folgt p_A − p_B dem Unterschied der Chats: Sabotage bringt den eigenen Spieler relativ nach vorn, kostet ihn aber absolut (Gefangenendilemma – „Gegenwind“).

  | | B hilft | B sabotiert |
  |---|---|---|
  | **A hilft** | 72,5 / 72,5 | 42,5 / 60 |
  | **A sabotiert** | 60 / 42,5 | 20 / 20 |
- Normierung auf Anteile: 3 Stimmen in einem kleinen Chat wiegen so viel wie 3.000 in einem großen. Jedes `!schlecht` in Chat X trifft den Gegner von X; es senkt nebenbei den Hilfe-Anteil von X (der Preis der Sabotage).
- Das Duell läuft nur, wenn dieses Spiel beide Kanäle auf einer verbundenen Twitch-Verbindung liest und beide Kanalnamen gültig sind (nur a–z, 0–9, _); sonst ziehen beide mit 60 %. `!power`/`!fruit` wirken im Versus nicht.
- Anzeige im Rennbalken statt im Chip links; die Titelkarte nennt, wer gekippt hat („Duell 42 % → STROMAUSFALL · Sabotage von #bob“).

**Bretter**
- Rundenzeiten zählen im Modus `pvp` (`level|brett|pvp`) mit dem Spielernamen: Brett `woche` (auch bei eingeschaltetem Chaos-Modus), oder `chat`, sobald das Duell den eigenen Anteil verschoben hat. Kein Highscore im Versus. Eine sichtbare pvp-Bestenliste gibt es bewusst nicht (Design-Review N3); später eher eine Kopf-an-Kopf-Bilanz.

**Netz**
- Godots `ENetMultiplayerPeer` als reiner Paket-Peer (JSON, keine RPCs), Protokoll 2. Nachrichten: `hello`, `reveal`, `rematch`, `round`, `prog` (5/s, eigener Kanal, zuverlässig), `rabbit`, `finish`, `died`, `lost`, `result`, `bye` (Kopf von `versus_session.gd`). Zeiten als Hundertstel (ganze Zahlen).
- Jeder Client simuliert nur sein eigenes Rennen; keine Autorität über Kugeln oder Geister, daher kein Latenzvorteil. Nur die Rundenentscheidung trifft der Host.
- Alles aus dem Netz wird geprüft: Typen, Wertebereiche (NaN/∞, Zeiten, `go_in` 0,5–10 s, Woche), Zustand (kein zweites hello/reveal, kein Rundensprung), Kanalnamen (sonst IRC-Injection auf die eigene Twitch-Verbindung), Namen ohne Steuerzeichen; max. 1 KB je Paket, 64 Pakete je Frame, `prog` höchstens alle 50 ms. ENet erkennt einen stillen Abbruch nach 2–8 s.
- Vertrauensbasiert: Ein manipulierter Client könnte eine falsche Zeit melden. Für Freundes-Matches akzeptiert; vor öffentlichem Matchmaking oder Ranglisten-PvP nachzurüsten (z. B. Abgleich der Chat-Zählerstände, die `rabbit` schon mitsendet).
- Heute per IP und Port; NAT/Portfreigabe nötig. Steam-Lobby und Freundeseinladung folgen mit der Steam-App-ID (E16) und vermutlich einem Godot-Upgrade auf 4.4+ (GodotSteam-Multiplayer-Builds).

**Dateien**
- `scripts/chat_duel.gd` – Duell-Formel, Anteile, Rundengenerator, Commit-Reveal
- `scripts/versus_session.gd` – Protokoll, Handshake, Runden, Entscheidung
- `scripts/versus_controller.gd` – Lobby, Rundenablauf, Hooks in `main.gd`
- `scripts/versus_ui.gd` – Lobby, Rennbalken, Countdown, Ergebnis
- `scripts/twitch_chat.gd` – zusätzliche Kanäle (`join_extra`, Signal `channel_command`)
- Tests: `tests/test_chat_duel.gd` (50), `tests/test_versus_session.gd` (50: zwei Sitzungen in einem Prozess, feindliche Pakete, gleichzeitiger Tod, Revanche, zweiter Gegner, Join ohne Host), `tests/versus_e2e.gd` + `tools/qa/versus_e2e.sh` (zwei Spielinstanzen über localhost), Screenshots `tools/qa/qa_versus_shots.gd`

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
