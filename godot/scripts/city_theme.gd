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
## When true, the boxy (non-word-mode) walls are shaded with
## matrix_rain.gdshader instead of a plain StandardMaterial3D: scrolling
## random green glyphs baked directly into the wall surface, always fully
## visible regardless of camera distance (see MazeView._make_materials).
## Unlike the old screen-space post effect this doesn't fade to a flat
## color up close — it's the wall's actual material, not a distance blend.
var wall_matrix_rain := false

## ---- Per-building height / "real skyscraper" look ----
## A second word an ordinary block can be built from instead of wall_word,
## picked per-cell with skyscraper_chance_pct odds — e.g. Manhattan cycles
## most blocks as "BUILDING" but a minority as "SKYSCRAPER", each sized
## into the corresponding height range below, so skyscrapers actually read
## as taller than their neighbors rather than every block being a uniform
## MazeView.WALL_H box. "" (the default) disables the whole height-variation
## system: every block stays MazeView.WALL_H, exactly the old behavior.
var wall_word_tall := ""
var skyscraper_chance_pct := 0 # 0-100
var wall_height_min := 0.0 # 0.0 = disabled (falls back to MazeView.WALL_H)
var wall_height_max := 0.0
var wall_height_tall_min := 0.0
var wall_height_tall_max := 0.0
## Real-world building heights (converted to game units — see
## manhattan_maze.gd/city_themes.gd for the actual figures and their
## sources), keyed by the exact landmark name string as returned by
## landmark_provider_script.landmark_at(). A landmark with no entry here
## falls back to landmark_default_height.
var landmark_heights: Dictionary = {}
var landmark_default_height := 0.0 # 0.0 = disabled (falls back to MazeView.WALL_H)
## When true, a wall's word is built as a vertical letter-by-letter totem
## (see word_mesh.gd's build_vertical_stack) spanning the block's full
## height — "hochkant", like a skyscraper's name read up its own face —
## instead of one horizontal word centered on the block.
var wall_vertical_text := false

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
## When true, MazeView scatters blocky white pixel-cloud clusters (see
## cloud_mesh.gd) just below the ceiling — a Mario/Minecraft-style voxel
## sky, meant to go with a bright ceil_color rather than the original dark
## "underground" ceiling.
var ceil_sky_clouds := false

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
## When true (Manhattan), MazeView.build()'s pellets aren't a uniform floor
## fill of every open cell — they're only placed along a handful of walked-
## back shortest paths from spread-out points to their nearest metro-
## station cell, so they read as wayfinding signposts toward an exit rather
## than "collect everything". Needs metro_cells passed into build(); see
## MazeView._metro_trail_cells.
var pellets_follow_metro_trails := false
