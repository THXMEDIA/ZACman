extends RefCounted
## TokyoStyle — the approved look "Natriumregen" (direction A, studio
## template studio/zapmaniac-tokyo-stil-v1.md, owner decision 03.10.2026) as
## constants: palette with roles and the line dimensions of the Tokyo line
## city. The readability rules these encode (docs/design/tokyo-explorer.md):
##   - green only for the subway exit, warm white-gold only for the pellets
##   - the world uses at most amber, cold white and the magenta accent;
##     magenta only on screens and the tower accent
##   - the neon base line (2.3 m) and the curb always show the collision
##   - brightness falls to ~30 % towards the top, no flicker >= 3 Hz

const SKY := Color("060504")
const MASS := Color("030304")
const ASPHALT := Color("0b0a0c")
const FOG := Color("1c130c")
const AMBER := Color("ff9a2e") # world, sodium
const WHITE := Color("f2efe8") # world, cold white
const MAGENTA := Color("ff2e88") # accent: screens and tower only
const PELLET := Color("ffd98a") # exclusive: pellets
const PELLET_CORE := Color("fff8e6")
const METRO := Color("39ff6a") # exclusive: subway exit
const HEADLIGHT := Color("ffffff") # traffic front (M2)
const TAILLIGHT := Color("ff2a1a") # traffic back (M2)
const PASSERBY := Color("a49a8c") # pedestrians, ~50 % brightness (M2)
const LAMP := Color("ffa040") # sodium street lamps (amber family)
const POLE := Color("4d4a48") # lamp brackets, barely visible
const PAINT := Color("5a5652") # road paint, unlit, below the neon in value
const SHOP := Color("ff8a20") # shop fronts under the base line (amber family)

## Line energies (HDR multipliers of the unshaded neon material).
const AMBER_ENERGY := 2.2
const WHITE_ENERGY := 1.8
const MAGENTA_ENERGY := 3.0
const POLE_ENERGY := 0.35

## Brightness factors per line kind (UV.x of the line mesh).
const EDGE_MUL := 1.0
const BAND_MUL := 0.45
const MULLION_MUL := 0.4
const BASE_LINE_MUL := 0.95 # Sockellinie: the brightest line at eye level
const CURB_MUL := 0.38
const BACKGROUND_MUL := 0.5
const LAMP_MUL := 2.0

## Dimensions (m). The player's eye is at 0.95 m (player_controller.gd).
const BASE_LINE_Y := 2.3 # Sockellinie = collision edge of every building
const CURB_Y := 0.06
const EDGE_THICK := 0.075
const BAND_THICK := 0.035
const BASE_LINE_THICK := 0.05
const CURB_THICK := 0.05
const FLOOR_STEP := 2.6 # floor band spacing
const FIRST_BAND_Y := 4.4
const FADE_H := 42.0 # height over which line brightness falls to TOP_MUL
const TOP_MUL := 0.3
const SHOP_H := 2.15 # shop-front glow up to just under the base line

## World palette — the only colors a building line may have.
const WORLD_COLORS := {"amber": AMBER, "weiss": WHITE}
