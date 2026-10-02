# Richtung C "Natriumdunst": dominanter Amber-Dunst, Linien tauchen aus dem Nebel,
# Screens faerben die Szene; Tuerkis exklusiv fuer Weg/Bahnhof.
extends RefCounted
static func c(h: String) -> Color: return Color.html(h)
static func style() -> Dictionary:
	return {
		"bg": c("#2a1305"), "fog_col": c("#3d1f08"), "fog_density": 0.017,
		"world_cols": [c("#ffb347"), c("#ff7a1a"), c("#ffd9a0")],
		"mass_col": c("#050201"),
		"line_energy": 2.4, "line_thick": 0.16, "fade_h": 50.0, "top_mul": 0.4,
		"floor_step": 4.0, "floor_prob": 0.35, "floor_energy_mul": 0.5, "mullion_prob": 0.0,
		"accent": c("#ff3b2f"), "accent_energy": 3.0,
		"sockel_col": c("#ffb347"), "sockel_energy": 2.6, "shop_col": c("#ff9a2e"), "shop_energy": 0.8,
		"curb_col": c("#ffd9a0"), "curb_energy": 0.6,
		"lamp_col": c("#ff9a2e"), "lamp_energy": 5.5, "lamp_halo": 1.0, "lamp_pool": 0.5, "lamp_rain": 2.5,
		"screen_a": c("#ff3b2f"), "screen_b": c("#ffd9a0"), "screen_light": c("#ff5a2a"), "screen_energy": 2.0, "screen_halo": 0.5,
		"sign_col": c("#ffd9a0"),
		"car_col": c("#9a6a40"), "car_energy": 0.8, "head_col": c("#fff4e0"), "tail_col": c("#ff1a0a"), "beam_energy": 0.25,
		"ped_col": c("#b07a48"), "ped_energy": 0.9, "ped_thick": 0.025, "umb_col": c("#b07a48"),
		"orb_col": c("#fff0c8"), "orb_core": c("#ffffff"), "orb_energy": 3.0, "orb_halo": 0.5,
		"metro_col": c("#00e5d4"), "metro_energy": 3.4, "metro_cone": 0.45, "metro_halo": 1.2,
		"asphalt_col": c("#100a06"), "walk_col": c("#171009"), "paint_col": c("#6a5040"),
		"spill_col": c("#ff8a20"), "spill": 0.7, "puddle_amount": 0.5, "refl_strength": 1.0, "streak": 0.11, "ripple": 0.007, "asphalt_wet": 0.5,
		"rain_col": c("#ffcf90"), "rain_base": 0.03, "rain_lit": 0.6, "rain_width": 0.008, "rain_count": 11000, "rain_slant": 0.35,
		"glow_intensity": 1.2, "glow_threshold": 0.7, "glow_wide": 1.2, "glow_bloom": 0.03, "exposure": 1.0,
		"halo_energy": 1.4, "cone_energy": 0.8,
		"bg_count": 60, "bg_energy_mul": 0.8, "beacon_col": c("#ff3b2f"),
	}
