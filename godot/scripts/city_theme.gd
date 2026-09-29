extends Resource
## CityTheme — a data bundle describing one Explorer level's whole visual
## identity: wall word-skin + palette, optional per-cell landmark overrides,
## floor/ceiling materials, and the scene-wide environment (background/fog/
## ambient light). MazeView and Main read a CityTheme instead of branching
## on a raw "manhattan"/"normal" string, so a brand-new city (Tokyo neon
## rain, Parisian watercolor, Rio pop-art, ...) is just a new CityTheme
## instance registered in city_themes.gd — no changes to the builder code
## in maze_view.gd/main.gd themselves. See this project's "Explorer-Level-
## Erweiterung, Leaderboard & Konditionen" doc for the full plan this
## implements the first step of.

var id := ""
var display_name := ""

## ---- Walls / word-built-world skin ----
## The word an ordinary wall block is built from when no landmark applies
## (e.g. "WALL" for the Matrix levels, "BUILDING" for Manhattan).
var wall_word := "WALL"
var wall_font_size := 30
var wall_depth_scale := 0.6 # multiplier of MazeView.WALL_H
var wall_emission_energy := 1.1
## Cycled per-cell (see MazeView._wall_palette_color) so a skyline of
## identical words still reads as varied rather than one flat tint. A
## single-color array (the default) makes every block the same color.
var wall_palette: Array = [Color(0.25, 1.0, 0.35)]
## Corridors running either axis get a readable face at least some of the
## time, rather than perfectly UV-mapped signage — set false for a theme
## that wants every block facing the same way.
var wall_alternate_rotation := true

## ---- Optional per-cell landmark override ----
## A script exposing a static `landmark_at(row: int, col: int) -> String`
## (see manhattan_maze.gd) that names specific wall blocks (e.g. real
## Midtown buildings) in place of the generic wall_word. Null = no
## landmarks, every block uses wall_word.
var landmark_provider_script: Script = null
var landmark_accents: Array = [Color(1.0, 0.85, 0.25)]
var landmark_font_size := 15
var landmark_depth_scale := 0.55
var landmark_emission_energy := 2.4

## ---- Floor / ceiling ----
var floor_color := Color(0.024, 0.039, 0.094)
var floor_roughness := 0.9
var floor_metallic := 0.0
var floor_emission_enabled := false
var floor_emission_color := Color.BLACK
var floor_emission_energy := 0.0
var ceil_color := Color(0.016, 0.024, 0.067)
var ceil_emission_enabled := false
var ceil_emission_color := Color.BLACK
var ceil_emission_energy := 0.0

## ---- Scene-wide environment (background/fog/ambient) — read by Main ----
var env_bg_color := Color(0.0196, 0.0275, 0.0627)
var env_fog_color := Color(0.0196, 0.0275, 0.0627)
var env_fog_density := 0.03
var env_ambient_color := Color(0.165, 0.227, 0.4)
var env_ambient_energy := 0.9

## ---- Gameplay ----
## Manhattan-style "calm explorer" levels have no power pellets/Word Mode
## pickup and no ghosts (see manhattan_maze.gd's header); a future
## Matrix-style Explorer level would set this true.
var has_power_ups := true
## Whether MazeView starts in the word-built-world skin permanently (true
## for Manhattan) rather than only switching to it when the Word Mode
## pickup is eaten (the normal levels). Kept separate from has_power_ups so
## a future non-word-built theme (e.g. a shader-only NPR look) can be a
## permanent, power-up-free explorer without implying the letterform skin.
var permanently_word_built := false
