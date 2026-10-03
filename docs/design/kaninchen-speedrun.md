# Spezifikation: Speedrun-Look und Kaninchen-Mechanik

Freigegeben vom Inhaber am 03.10.2026 (Studio-Entscheidungen E8, E8a–g). Diese Datei ist die verbindliche Grundlage für die Umsetzung. Ersetzt die Entscheidungen zu Konditionen, Word Mode und Fear-Pickup vom 02.10.2026.

Herkunft: Art-Director-Prototypen (`tools/art/speedrun_proto/pacman_v2.patch`, `konditionen.patch`, Bilder im Branch `art/speedrun-vorschlaege` unter `docs/art/vorschlaege/speedrun/`), Game-Design-Spezifikation und technische Folgenabschätzung vom 03.10.2026.

## 1. Look

### 1.1 Speedrun-Basis: Pac-Man-Look „Lagune“ (immer)
- Alle Speedrun-Level nutzen den Basis-Look aus `pacman_v2.patch`: dunkle Kanäle, Leuchtkante `#1EF2C8` oben an jeder Wand, Farbverlauf zum Sockel je Level (Lagune `#0B7FA8` in Klassik I/III, Riff `#1FBF5A` in Klassik II/IV, übrige Level abwechselnd), Sockelstriche im 0,5-m-Takt, senkrechte Linien nur an freien Wandenden (Nachbar-Maske über MultiMesh-Custom-Data), Kreuzungsrahmen (gefastes Achteck) am Boden, Querraster alle 2 m.
- Raum/Nebel/Decke `#05070B`, Boden `#0D0F16` (beleuchtet, nicht unshaded – Geisterlicht als Vorwarnung), Wandmasse `#06141C`.
- Kugeln: Creme-Würfel `#FFF0C8`, Punktreihe auf ~0,4 m. Power-Kugel: Raute, blinkt 2 Hz (unter 3 Hz).
- Geister „Schild mit Visier“ (Hörner oben, Spitze unten, ein Sehschlitz; keine Kuppel, kein Zackensaum, keine Augen). Farben: Jäger `#FF3049`, Abfänger `#E2FF3A`, Streuner `#A65CFF` (nur in Lagune-Leveln), Lauerer `#FFA41F`, Nachzügler `#FF36C8`; verängstigt `#BDFCEF`. Kein Geist in der Verlaufsfarbe seines Levels, kein Cyan-Geist, kein Grün (kollidiert mit Matrix-Kondition).
- Minimap-Wände `#128F7C`; keine Wandlinie im Blaubereich 215–250° Farbton (Test vorhanden).
- CRT-Overlay: 270 Zeilen pro Bildhöhe (auflösungsunabhängig), Vignette, kein Flimmern.
- Keine Wolken, kein Himmel, kein Mario-Vista im Speedrun.
- Alle Linien/Raster über `fwidth()` geglättet und auf Distanz ausgeblendet.
- Explorer-Level (Manhattan, später Tokyo) behalten ihre eigenen Looks.
- Niedrige Wände: nicht umsetzen.

### 1.2 Konditions-Looks
Ein gemeinsamer Wand-/Boden-Shader (aus `konditionen.patch`) mit Uniforms `look`, `transition`, `flip`, `reduce_fx`; Wechsel zur Laufzeit per Materialtausch bzw. Uniform, nie durch zweiten Wandsatz.
- **Übergang:** 0,8-s-Welle vom Spieler aus, Zelle für Zelle; in der Wellenfront zerfallen die Neonlinien zu Zeichen in Hasenweiß `#F2F2ED`. Rückweg identisch rückwärts.
- **Matrix „Durchlässiger Code“:** Wände nur noch Code-Raster (vor der Kamera fast offen, auf Gangbreite ~70 %, Ferne ~95 %), Oberkante als einzige durchgehende Linie, Rückseiten gedimmt, eigener Glyphensatz „ZAC-Code“ (keine Film-Glyphen). Grün `#00D94D`, Kopf `#CCFFDB`, Grund `#000301`.
- **Fear & Loathing „Kippbild“:** schmelzende Wüsten-Neon-Streifen (`#2B0A3D` → `#B3175C` → `#F26B33`), Casino-Teppich-Boden; wenn die Steuerungsmanipulation aktiv „gekippt“ ist, kippt die Welt in die Komplementärpalette (`#072E33` → `#0F8C85` → `#4DCCF2`) in 0,4 s bei gleicher Helligkeit; Streifen fließen dann nach oben.
- **Taschenuhr:** Basis-Look bleibt; leichter warmer Farbstich + langsames Uhren-Ticken; Geister sichtbar verlangsamt.
- **Stromausfall:** Basis-Look, dichter Nebel (Sicht ~2 Zellen), Minimap aus, Kugeln und Geister bleiben selbstleuchtend.
- **Für alle:** Kugeln, Power-Kugel und Geister ändern nie Farbe/Form (in Konditions-Looks schwarze Kontur zur Trennung); Minimap bleibt (außer Stromausfall). Bewegungen < 0,5 Hz, keine Vollbild-Blitze. Option „Effekte reduzieren“ (Einstellungen) wirkt auf alle Looks; die Spielwirkung der Kondition bleibt gleich.

## 2. Kaninchen-Mechanik

### 2.1 Start-Einblendung
- Bei jedem Speedrun-Start (`begin_game`, auch nach dem U-Bahn-Ausgang aus Manhattan; nicht bei `next_level`) erscheint 2,5 s „Follow the white rabbit. But beware“.
- Eigenes, zentriertes Panel mit Hintergrund (nicht das bestehende, dezentrierte Level-Banner, QA-W2).
- Die Uhr startet erst mit der ersten Bewegungseingabe nach der Einblendung; die Einblendung kostet keine Zeit. („Pause kostet Zeit“ bleibt gültig.)

### 2.2 Das Kaninchen
- Genau 1 White-Rabbit-Pickup pro Speedrun-Level, ab Level 1. Ersetzt Word-Mode-Pickup, Fear-&-Loathing-Pickup und die Konditionswahl am Startscreen (diese entfallen; Manhattan behält seine permanente Wort-Welt).
- Position: deterministisch je Level-Seed in einer Sackgasse, BFS-Distanz zum Start ≥ 40 % des Maximums; die Zelle bleibt frei von Pflicht-Kugeln (keine Kugel wird durch das Kaninchen ersetzt). Ab Levelstart auf der Minimap sichtbar.
- Freiwillig: Wer es liegen lässt, spielt einen voll deterministischen Lauf.
- Aufnahme: sofortige Titelkarte oben (Name, Symbol, Restzeit-Balken; Farbe gut = Grün, schlecht = Magenta), eigener Ton (gut aufsteigend, schlecht verstimmt fallend), Musikschicht für die Dauer.
- Dauer: gute Konditionen 10 s, schlechte 8 s; Tick-Töne in den letzten 3 s. Kein Stapeln: ein weiteres Kaninchen (falls es später mehrere gibt) ersetzt die laufende Kondition.

### 2.3 Konditions-Pool
Grundverhältnis gut:schlecht = 60:40, innerhalb gut bzw. schlecht gleich verteilt.

| Typ | Kondition | Wirkung |
|---|---|---|
| gut | Matrix | ASCII-Look, Wände ohne Kollision. In den letzten 3 s blenden die Wände ein/blinken; am Ende wird der Spieler sicher in die nächste offene Zelle gesetzt (Kapsel vollständig frei). |
| gut | Taschenuhr | Geister 50 % langsamer. |
| schlecht | Fear & Loathing | Steuerungsmanipulation + Kippbild-Look. |
| schlecht | Stromausfall | Sicht ~2 Zellen, Minimap aus. |

Neue Konditionen = ein Skript unter `scripts/conditions/` plus Registry-Eintrag mit `is_good`, `duration_s`, `weight`.

### 2.4 Fear & Loathing – Steuerung
- Pro Aufnahme genau eine Manipulation, zufällig (gleicher Zufallsgenerator wie das Kaninchen), angekündigt mit Symbol in der Titelkarte:
  - **A/D getauscht** (Seitwärts-Eingabe gespiegelt),
  - **Drift**: beim Laufen 25 % Seitenzug (nur solange Bewegungseingabe anliegt),
  - **Verzögerung**: 150 ms Verzögerung auf WASD (fester Ringpuffer).
- Das „Kippen“ des Looks entspricht dem aktiven Zustand der Manipulation.
- **Rote Linie (E8e):** Maus/Blickrichtung/Kamera werden nie manipuliert. Keine Bewegung ohne Eingabe, kein Bildwackeln, kein FOV-Pulsieren, keine Zeitdilatation.
- Das heutige Sinus-Rauschen und die unangekündigte Komplett-Umkehr entfallen.

### 2.5 Zufall und Bestzeiten („Kaninchen der Woche“, E8f)
- Standard: Das Ergebnis jedes Kaninchens (welche Kondition, welche F&L-Manipulation) folgt aus einem Seed aus Level-ID und ISO-Kalenderwoche (Europe/Berlin bzw. lokale Zeit des Spielers – dokumentieren, welche). Neustart würfelt nicht neu. Eigener `RandomNumberGenerator`, nie globales `randf()`.
- Chaos-Modus (am Startscreen einschaltbar): echter Zufall, eigenes Brett „chaos“.
- Chat: siehe 2.6, Brett „chat“.
- Brett-Schlüssel: `level|brett|modus` (Brett = `woche`/`chaos`/`chat`); die Kondition ist nicht mehr Teil des Schlüssels. Wochen-Bestzeiten zeigen die Kalenderwoche mit an; die Allzeit-Bestzeit pro Level auf dem Wochenbrett nennt ihre Woche.
- Alte Bretter mit Konditions-Schlüsseln (`matrix_ghost`, `fear_and_loathing`) werden beim Laden archiviert (nicht gelöscht) und nicht mehr angezeigt. Spielstände bekommen ein Versionsfeld und eine Typprüfung (Code-W3).

### 2.6 Twitch-Chat (E8g)
- Befehle `!gut` und `!schlecht`: eine Stimme pro Nutzer im gleitenden 60-s-Fenster, die letzte Stimme gilt.
- Gut-Anteil = 60 % + 30 Prozentpunkte × (gut − schlecht) / (gut + schlecht), begrenzt auf 20–80 %. Unter 3 verschiedenen Stimmen gilt die Basis 60 %.
- Gelesen im Moment der Kaninchen-Aufnahme. Hat der Chat den Anteil verschoben, wird echter Zufall mit dieser Gewichtung gezogen und das Level zählt auf das Brett „chat“ (`_mark_chat_assisted`).
- Anzeige im Chat-Modus: kleiner Balken „Kaninchen: 72 % gut“; bei Aufnahme „Chat 72 % → MATRIX“.
- Bestehende Chat-Befehle `!power`/`!fruit`: Cooldown ergänzen (Code-W8).
- Brief anpassen: Twitch darf jetzt auch erschweren (nur über das Kaninchen-Verhältnis).

## 3. Rechtsprüfung (offen, nicht Teil der Umsetzung)
Name „ZACman“ vs. „PAC-MAN“; Gesamteindruck 3D-Maze + Punktreihen + farbige Verfolger + blinkender Power-Punkt; Text „Follow the white rabbit“; Konditionsname „Fear & Loathing“; kein „Matrix“ im Store-Text. UI-Bezeichnungen „Matrix-Level“ und „Matrix Ghost“ entfallen ohnehin (Speedrun-Level heißen schlicht nach dem Level-Pool).
