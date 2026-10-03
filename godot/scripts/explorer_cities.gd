extends RefCounted
## ExplorerCities — what Main needs to run each Explorer city (the calm,
## untimed levels whose pellets lead to the subway, the exit into a
## speedrun). The look lives in the city's CityTheme (city_themes.gd), the
## street grid in its maze script; this registry ties them together for
## Main.begin_explorer_game(city_id):
##   theme         CityTheme id (city_themes.gd)
##   label         HUD level chip
##   maze_script   script with generate() -> MazeGen.Maze
##   seed          level seed of the city's scenery and pellet trails
##                 (0 = the city has no seeded scenery)
##   metro         "random": metro_count random open room cells (Manhattan)
##                 "maze": maze_script.metro_cells() (Tokyo: the station exit)
##   metro_script  the subway sign node (setup(pos) / update(delta, now))
##   traffic       "manhattan" = Manhattan's word traffic and pedestrians,
##                 "tokyo" = rain, wire cars, passers-by and the scramble
##                 crossing (tokyo_life.gd), "" = none
##   exit_text     level-clear banner when the player takes the subway

const EXPLORER_IDS := ["manhattan", "tokyo"]


static func get_city(id: String) -> Dictionary:
	match id:
		"manhattan":
			return {
				"id": "manhattan", "theme": "manhattan", "label": "MANHATTAN",
				"maze_script": "res://scripts/manhattan_maze.gd", "seed": 0,
				"metro": "random", "metro_count": 4, "metro_script": "res://scripts/metro_station.gd",
				"traffic": "manhattan", "exit_text": "SUBWAY — los zum Speedrun!",
			}
		"tokyo":
			return {
				"id": "tokyo", "theme": "tokyo", "label": "TOKYO",
				"maze_script": "res://scripts/tokyo_maze.gd", "seed": 7310,
				"metro": "maze", "metro_count": 1, "metro_script": "res://scripts/tokyo_metro_station.gd",
				"traffic": "tokyo", "exit_text": "U-BAHN — los zum Speedrun!",
			}
	return {}


static func has_city(id: String) -> bool:
	return not get_city(id).is_empty()
