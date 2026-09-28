# Weg zu Steam

ZACman läuft heute als Browser-Spiel (`web/index.html`, Three.js). Für eine
Steam-Veröffentlichung braucht es einen nativen Desktop-Build plus die
Geschäfts-/Store-Seite bei Valve. Der technische Teil lässt sich hier im
Repo vorbereiten; der administrative Teil (Konto, Gebühr, Store-Seite)
erfordert Aktionen des Studios/der Person direkt bei Valve — das kann ich
nicht stellvertretend erledigen.

## 1. Technischer Build (im Repo vorbereitet)

- `desktop/` verpackt `web/index.html` unverändert als natives
  Electron-Fenster (`desktop/main.js`).
- Lokal bauen:
  ```
  cd desktop
  npm install
  npm start          # Fenster zum Testen
  npm run dist        # Zip/Installer für Win/Mac/Linux via electron-builder
  ```
- Der Output landet in `dist/` (siehe `desktop/package.json` → `build.directories.output`).
- **Noch offen:** Icons (`build/icon.ico`, `.icns`, `.png`) und Code-Signing
  für Windows/Mac ergänzen, sonst warnen Windows SmartScreen/Gatekeeper beim
  ersten Start.

## 2. Steamworks-Integration (Empfehlung)

Für ein "echtes" Steam-Gefühl (Achievements, Cloud-Saves, Overlay) bindet man
die Steamworks-API in den Electron-Prozess ein, z. B. über
[`steamworks.js`](https://github.com/ceifa/steamworks.js) im
`desktop/preload.js`. Mögliche erste Achievements, passend zum bestehenden
Scoring-Code in `web/index.html`:

| Achievement | Auslöser im Code |
|---|---|
| Erste Kugel | `state.score` wechselt von 0 auf 10 |
| Erste Power-Kugel | `Audio_.power()` wird aufgerufen |
| Erstes Wesen gefressen | `en.mode = 'eaten'` |
| Level 3 erreicht | `state.levelIndex === 2` in `startLevel` |
| Highscore geknackt | `state.score > state.highScore` in `endGame` |

Ohne Steamworks-SDK läuft das Spiel trotzdem in Steam (als reine
Electron-App mit Steam als Launcher) — die Integration ist ein Ausbau, kein
Blocker für die erste Veröffentlichung.

## 3. Administrative Schritte bei Valve (nicht automatisierbar)

Diese Schritte müssen im eigenen Steamworks-Konto gemacht werden:

1. **Steamworks-Partnerkonto** unter partner.steamgames.com anlegen
   (Firma oder Einzelperson, Steuerformular, Bankverbindung).
2. **App-ID kaufen** — 100 $ Steam-Direct-Gebühr pro Titel, wird nach
   ca. 1.000 $ Umsatz zurückerstattet.
3. **Store-Seite** anlegen: Kapsel-Grafiken, Screenshots/Trailer, Beschreibung,
   Preis, Alterskennzeichnung (IARC-Fragebogen).
4. **SteamPipe / Build-Upload**: `steamcmd` mit einem App-Build-Script
   (`.vdf`), das auf den Ordner aus `dist/` zeigt, hochladen.
5. **Review durch Valve** abwarten, Release-Datum setzen.

## 4. Rechtliches: Abstand zum Original

Das Spiel ist bewusst als eigenständiges Werk gehalten — eigener Name
("Kugelschlucker" / "ZACman"), eigene, prozedural generierte Labyrinthe,
eigene Gegner-Optik (leuchtende Polyeder statt Geister-Sprites) und
vollständig synthetisierte Sounds statt Sample-Kopien. Das sollte vor einer
Veröffentlichung von einer Person mit Marken-/Urheberrechtskenntnis
gegengeprüft werden, insbesondere Name und Store-Grafiken.

## Nächster sinnvoller Schritt

`desktop/npm install && npm start` lokal ausprobieren, dann Icons und ein
Store-Grafik-Set anfertigen, während parallel das Steamworks-Partnerkonto
beantragt wird (Bearbeitungszeit kann mehrere Tage betragen).
