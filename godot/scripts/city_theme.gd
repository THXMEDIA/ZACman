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
## A block's visible/collision footprint as a fraction of the full CELL x
## CELL grid square it occupies (1.0 = fills the cell edge-to-edge, the old
## behavior). A theme with real street-width proportions in mind (e.g.
## Manhattan) sets this below 1.0 so every building sits back from its
## cell's edges, leaving a real gap between building faces on top of the
## open street cell between them — same grid, same collision safety
## (still one solid block centered in its cell, so nothing can be cut
## through diagonally), just visibly and physically wider streets.
var wall_footprint_scale := 1.0
## When true (with wall_vertical_text), each block's hochkant lettering is
## squeezed to fit inside that block's footprint (CELL * wall_footprint_scale)
## in width and depth — so the letters never hang out over the street and the
## street looks as wide as it physically is. Off by default (other themes
## unchanged).
var wall_word_fit_footprint := false

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
## When false, MazeView doesn't build a physical ceiling plane at all — the
## env_bg_color/fog above simply reads as open sky. Needed by any theme
## whose buildings can be much taller than the old fixed MazeView.WALL_H
## (e.g. Manhattan's real-height skyscrapers): a low flat ceiling plane
## would otherwise slice straight through them, hiding everything above it
## behind an opaque "cave roof" — which is exactly the "only the bottom few
## letters of a tall building's name are visible" bug this fixes.
var ceil_enabled := true

## ---- Shader-based look (Speedrun "Lagune", spec 1.1) ----
## Optional .gdshader paths. Empty = the classic StandardMaterial3D
## behavior, so a theme that does not set them (Manhattan)
## looks exactly as before.
var wall_shader_path := "" # base-look wall shader; gets the neighbor mask (MultiMesh custom data)
var floor_shader_path := "" # gets the cell map (MazeView.maze_tex) and the level look's colors
## Rabbit-condition looks (spec 1.2): one shared wall/floor shader pair with
## the uniforms look/transition/flip/reduce_fx, swapped onto the same wall
## MultiMesh and floor by MazeView's Look API while a condition runs.
## "" = the theme has no condition looks (Manhattan).
var cond_wall_shader_path := ""
var cond_floor_shader_path := ""
var screen_overlay_shader_path := "" # full-screen canvas_item overlay (CRT lines), "" = none

## ---- Pickups ----
## Defaults are the original golden spheres / pink pulsing power pellet.
var pellet_color := Color(1.0, 0.82, 0.4)
var pellet_emission := Color(1.0, 0.69, 0.18)
var pellet_energy := 1.3
var pellet_shape := "sphere" # "sphere" | "cube" | "pin" (sphere head on a needle down to the floor)
## Optional spatial shader for the pellets (uniforms col, core, key); "" =
## the StandardMaterial from pellet_color/emission/energy.
var pellet_shader_path := ""
var pellet_size := 0.11 # sphere radius / half the cube edge (m)
var pellet_height := 0.32 # center above the floor (m)
var power_color := Color(1.0, 0.365, 0.635)
var power_emission := Color(1.0, 0.184, 0.525)
var power_energy := 1.6
var power_shape := "sphere"
var power_size := 0.26
var power_diamond := false # stand the cube on its tip (a diamond / "Raute")
var power_blink_hz := 0.0 # 0 = the old scale pulse; > 0 = on/off blinking (keep below 3 Hz)
var power_blink_on_fraction := 0.62 # share of each blink period the power pellet is visible

## ---- Level looks (per-level color variants of one theme) ----
## look id -> {"top": Color, "base": Color, "body": Color, "ghosts": Array}
## where "ghosts" is a ghost palette like ghost_palette below. MazeView picks
## the look named by the level data (Levels.POOL[].look), falling back to
## default_level_look. Empty = the theme has no per-level looks.
var level_looks: Dictionary = {}
var default_level_look := ""

## ---- Ghosts ----
## Colors handed out in order (ghost i gets entry i % size). A level look's
## own "ghosts" list wins over this one.
var ghost_palette: Array = [
	{"role": "jaeger", "color": Color(1.0, 0.231, 0.365), "glow": Color(1.0, 0.42, 0.514)},
	{"role": "abfaenger", "color": Color(1.0, 0.365, 0.635), "glow": Color(1.0, 0.62, 0.788)},
	{"role": "streuner", "color": Color(0.2, 0.878, 1.0), "glow": Color(0.616, 0.953, 1.0)},
	{"role": "lauerer", "color": Color(1.0, 0.655, 0.2), "glow": Color(1.0, 0.816, 0.541)},
	{"role": "nachzuegler", "color": Color(0.616, 0.361, 1.0), "glow": Color(0.788, 0.639, 1.0)},
]
var ghost_emission_energy := 0.7
var ghost_frightened_color := Color(0.13, 0.2, 0.93)
var ghost_frightened_emission := Color(0.33, 0.47, 1.0)

## ---- Minimap ----
var minimap_bg_color := Color(0.008, 0.012, 0.039, 0.4)
var minimap_wall_color := Color(0.118, 0.227, 0.478)
var minimap_frightened_color := Color(0.35, 0.82, 1.0)
## Explorer exits on the minimap (green square); alpha 0 = not drawn.
var minimap_exit_color := Color(0.22, 1.0, 0.42)

## ---- Scene-wide environment (background/fog/ambient) — read by Main ----
var env_bg_color := Color(0.0196, 0.0275, 0.0627)
var env_fog_color := Color(0.0196, 0.0275, 0.0627)
var env_fog_density := 0.03
var env_fog_sky_affect := 1.0 # Environment default
var env_ambient_color := Color(0.165, 0.227, 0.4)
var env_ambient_energy := 0.9
## Post-processing of the theme. Main applies ALL of these on every theme
## switch (_apply_theme_environment), so a theme that turns glow/SSR/
## volumetric fog on (Tokyo) never leaks them into the next one (the speedrun
## must not glow on). The defaults are a fresh Environment's values, i.e.
## exactly what the speedrun and Manhattan had before these fields existed.
var env_glow_enabled := false
var env_glow_intensity := 0.8
var env_glow_strength := 1.0
var env_glow_bloom := 0.0
var env_glow_hdr_threshold := 1.0
var env_glow_levels: Array = [0.0, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0] # Environment default (levels 3 and 5)
var env_ssr_enabled := false
var env_ssr_max_steps := 64
var env_ssr_fade_in := 0.15
var env_ssr_fade_out := 2.0
var env_ssr_depth_tolerance := 0.2
var env_volumetric_fog_enabled := false
var env_ssao_enabled := false # Forward+ only (Amsterdam: contact shadows in the joints)
var env_tonemap_mode := 0 # Environment.TONE_MAPPER_LINEAR
var env_tonemap_exposure := 1.0
var env_tonemap_white := 1.0
## The small light the player carries (player_controller.gd) and the camera's
## far plane: the defaults are the old fixed values (cyan-white lamp, 100 m).
var player_light_color := Color(0.56, 0.83, 1.0)
var player_light_energy := 1.1
var player_light_range := 7.0
var camera_far := 100.0

## ---- Neon-line city (Tokyo, docs/design/tokyo-explorer.md) ----
## A script with a static `build(maze, city_theme, seed: int) -> Node3D`
## that adds the theme's own static scenery (neon contours, signs, paint)
## on top of the wall MultiMesh; null = none (all other themes).
var scenery_builder_script: Script = null
## A script with a static `trail_cells(maze, metro_cells, start_cell, seed)
## -> Array` that decides where the wayfinding pellets lie (instead of
## MazeView's generic metro trails over the odd/odd room cells); null = the
## generic trails. Only used with pellets_follow_metro_trails.
var pellet_trail_provider_script: Script = null
## A script with a static `setup_floor(material: ShaderMaterial, maze, seed:
## int)` that MazeView calls once the floor_shader_path material exists
## (Tokyo: baked puddle mask, the lights the wet floor reflects); null = none.
var floor_setup_script: Script = null

## ---- Lit model city (Amsterdam, docs/design/amsterdam-explorer.md) ----
## false: the wall MultiMesh is not drawn (pure physics); the theme's
## scenery shows the buildings. Collision is unchanged.
var walls_visible := true
## A script with a static `sky() -> Sky`: Main then shows that sky as the
## background and takes ambient light and reflections from it (an HDRI room
## behind the model). null = the plain env_bg_color background (all others).
var env_sky_script: Script = null
var env_bg_energy := 1.0
var env_sky_rotation_deg := 0.0
var env_ambient_sky_contribution := 1.0
## Colour adjustment (Environment.adjustment_*), reset on every theme switch.
var env_adjustment_enabled := false
var env_adjustment_contrast := 1.0
var env_adjustment_saturation := 1.0
## Minimap: a script with a static `is_water(row, col) -> bool`; those wall
## cells are drawn in minimap_water_color instead of the wall colour.
var minimap_water_script: Script = null
var minimap_water_color := Color(0, 0, 0, 0)
## Minimap: a dark ring around every pellet (Arles); alpha 0 = none.
var minimap_pellet_outline := Color(0, 0, 0, 0)

## ---- Gameplay ----
## Manhattan-style "calm explorer" levels have no power pellets, no white
## rabbit and no ghosts (see manhattan_maze.gd's header); a future
## Matrix-style Explorer level would set this true.
var has_power_ups := true
## Whether MazeView starts in the word-built-world skin permanently (true
## for Manhattan); every other theme never shows it (the speedrun levels
## have no word skin). Kept separate from has_power_ups so
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
