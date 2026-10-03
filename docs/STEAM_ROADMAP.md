# Weg zu Steam

ZAPmaniac läuft jetzt als natives Godot-4-Projekt (`godot/`) — das ist der
Steam-Zielpfad, nicht mehr der Electron-Wrapper aus einer früheren Version
dieses Dokuments. `web/index.html` bleibt als browserspielbarer Prototyp
erhalten, ist aber nicht mehr der Ausgangspunkt für den Steam-Build.

## 1. Technischer Build (im Repo vorbereitet)

- `godot/` ist ein eigenständiges Godot-4.3-Projekt: `godot/project.godot`
  öffnen (oder `godot --path godot` von der Kommandozeile).
- Export-Ziele werden über die Godot-Editor-UI eingerichtet
  (Project → Export…), da `export_presets.cfg` maschinenspezifische
  Export-Templates referenziert und deshalb nicht mitversioniert ist
  (siehe `godot/.gitignore`). Für Windows/Linux/macOS je ein Preset mit
  den offiziellen Godot-Export-Templates (Editor → Manage Export Templates)
  anlegen.
- Headless-Tests laufen ohne Editor:
  ```
  godot --headless --path godot --script res://tests/test_maze.gd
  godot --headless --path godot res://tests/BotTest.tscn
  ```

## 2. Steamworks-Integration

Godot hat kein eingebautes Steamworks-SDK; die verbreitete Lösung ist das
Community-Plugin [**GodotSteam**](https://godotsteam.com/) (GDExtension,
deckt Achievements, Cloud-Saves, Lobbies/Matchmaking und Rich Presence ab).
Einbindung: GodotSteam-Release ins Projekt legen, `Steam.steamInit()` in
einem Autoload beim Start aufrufen. Mögliche erste Achievements, passend
zum bestehenden Code in `godot/scripts/main.gd`:

| Achievement | Auslöser im Code |
|---|---|
| Erste Kugel | `_check_pickups()` — erster `result.pellet == true` |
| Erste Power-Kugel | `result.power == true` |
| Erstes Wesen gefressen | `enemy.mode = "eaten"` in `_check_enemy_collision` |
| Level 3 erreicht | `level_index == 2` in `start_level` |
| Highscore geknackt | `score > high_score` in `end_game` |

## 3. Multiplayer (Koop + Kompetitiv) — nächster großer Schritt

Godot bringt eine High-Level-Multiplayer-API (ENet-basiert) mit, die zur
bestehenden Architektur passt:

- `godot/scripts/maze_gen.gd` ist bereits deterministisch (fester Seed →
  identisches Labyrinth) — der Server generiert einmal, alle Clients
  können denselben Seed erhalten und identisch rendern, oder der Server
  bleibt vollständig autoritativ und synchronisiert nur Spielerzustand.
- `MultiplayerSpawner` für Spieler- und Gegner-Instanzen, `MultiplayerSynchronizer`
  für Position/Score, RPCs (`@rpc("authority")`) für Pickup-Events (nur der
  Server entscheidet, ob eine Kugel gegessen wurde — verhindert Cheating
  und doppeltes Zählen bei zwei Spielern am selben Pellet).
- **Koop**: alle Spieler teilen sich `score`/`lives`, ein gemeinsames
  Zeitlimit oder gemeinsame Gegner-Wellen.
- **Kompetitiv**: pro Spieler eigener `score`, gleiches Labyrinth, wer beim
  Leeren des Labyrinths vorne liegt, gewinnt das Level — die Pickup-Logik
  in `_check_pickups()` müsste dafür pro Spieler statt global zählen.

## 4. Administrative Schritte bei Valve (nicht automatisierbar)

1. **Steamworks-Partnerkonto** unter partner.steamgames.com anlegen.
2. **App-ID kaufen** — 100 $ Steam-Direct-Gebühr (Rückerstattung nach
   ca. 1.000 $ Umsatz).
3. **Store-Seite**: Kapsel-Grafiken, Screenshots/Trailer, Beschreibung,
   Preis, IARC-Alterskennzeichnung.
4. **SteamPipe / Build-Upload**: `steamcmd` mit App-Build-Script (`.vdf`)
   auf den exportierten Godot-Build zeigen lassen.
5. Review durch Valve abwarten, Release-Datum setzen.

## 5. Rechtliches: Abstand zum Original

Eigener Name, eigene prozedural generierte Labyrinthe, eigene Gegner-Optik
(leuchtende Polyeder statt Geister-Sprites), vollständig synthetisierte
Sounds statt Sample-Kopien — sollte vor Veröffentlichung trotzdem von
jemandem mit Marken-/Urheberrechtskenntnis gegengeprüft werden.

## Nächster sinnvoller Schritt

Godot-Projekt im Editor öffnen und einmal durchspielen, dann entscheiden:
zuerst Multiplayer (Koop/Kompetitiv) oder zuerst Steamworks-Achievements —
beides baut auf der gleichen, jetzt getesteten Basis auf.
