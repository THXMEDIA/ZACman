extends RefCounted
## KyotoStyle — the approved look "Aizuri-Pop-up" (direction G, studio
## template studio/projekte/zapmaniac/art/explorer-stile-v1.md, owner
## decision 04.10.2026) as constants. The city is an opened picture book:
## every building is a paper pop-up card printed in woodblock blue (aizuri),
## standing up as the player comes near and lying flat on the page further
## away. Readability rules (docs/design/kyoto-explorer.md):
##   - gold only for the pellets, green only for the exit (bookmark + door)
##   - the world uses the blue steps, paper white, ink, and vermilion (beni)
##     as a small accent (torii, shrine gate, lanterns); never gold, never green
##   - the ink line on the page is the collision edge (facade line)
##   - the fold is the book's only motion, plus slow passers-by (kyoto_life.gd)
##     and a few falling blossom petals; "Effekte reduzieren" stands everything
##     up, stops the petals and lets the passers-by stand still

const AI1 := Color("1e3a6e") # deepest blue, key block
const AI2 := Color("3f6ca8")
const AI3 := Color("8db0d6")
const AI4 := Color("cfe0ee") # palest blue, printed streets
const PAPER := Color("f3eee2") # page, sky at the horizon
const SUMI := Color("1c1a1e") # ink outline
const BENI := Color("c8384b") # vermilion accent (torii, gate, lanterns)
const PELLET := Color("ffc714") # exclusive: pellets
const PELLET_CORE := Color("fff3b8")
const EXIT := Color("22c460") # exclusive: bookmark ribbon and exit door
const SLAB := Color("e6e0d2") # the block plan printed on the page
## Cherry blossom: a pale tint of the vermilion on paper (same ink, thinned
## out like a lighter printing pass), never a new pigment.
const BLOSSOM := Color("f2d6d2")

## Fold distances of the pop-up cards (m from the camera): closer than
## FOLD_NEAR stands, beyond FOLD_FAR lies flat on the page.
const FOLD_NEAR := 24.0
const FOLD_FAR := 46.0
const FOLD_MAX := 1.5 # rad, ~86 degrees

## Card kinds (INSTANCE_CUSTOM.r in kyoto_card.gdshader). +100 = backdrop
## that never folds.
const K_MACHIYA := 0
const K_SHOP := 1
const K_TEMPLE_WALL := 2
const K_PINE := 3
const K_ROOFS := 4
const K_THEATER := 10
const K_GATE := 11
const K_PAGODA := 12
const K_KIYOMIZU := 13
const K_TEMPLE_GATE := 14
const K_SHRINE := 15
const K_TORII := 16
const K_TOWER := 17
const K_MOUNTAINS := 18
const K_MIST := 19
const K_FIGURE := 20
const K_SAKURA := 21 # cherry tree
const K_WALKER := 22 # passer-by (kyoto_life.gd; always +NO_FOLD, moved on the CPU)
const NO_FOLD := 100
