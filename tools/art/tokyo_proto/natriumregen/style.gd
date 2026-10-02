# Richtung A "Natriumregen": nasser Asphalt, Natrium-Amber + Weiss + Magenta-Akzent.
extends RefCounted
static func c(h: String) -> Color: return Color.html(h)
static func style() -> Dictionary:
	return {
		"bg": c("#060504"), "fog_col": c("#1c130c"), "fog_density": 0.012,
		"world_cols": [c("#ff9a2e"), c("#f2efe8"), c("#ff2e88")],
		"mass_col": c("#030304"),
		"line_energy": 2.2, "line_thick": 0.13, "fade_h": 55.0, "top_mul": 0.3,
		"floor_step": 3.6, "floor_prob": 0.45, "floor_energy_mul": 0.45, "mullion_prob": 0.15,
		"accent": c("#ff2e88"), "accent_energy": 3.2,
		"sockel_col": c("#ff9a2e"), "sockel_energy": 3.0, "shop_col": c("#ff8a20"), "shop_energy": 0.55,
		"curb_col": c("#f2efe8"), "curb_energy": 0.7,
		"lamp_col": c("#ffa040"), "lamp_energy": 5.0, "lamp_halo": 0.45, "lamp_pool": 0.35,
		"screen_a": c("#ff2e88"), "screen_b": c("#ff9a2e"), "screen_light": c("#ff4a90"), "screen_energy": 1.7, "screen_halo": 0.22,
		"sign_col": c("#f2efe8"),
		"car_col": c("#7c8088"), "car_energy": 0.9, "head_col": c("#ffffff"), "tail_col": c("#ff2a1a"),
		"ped_col": c("#a49a8c"), "ped_energy": 1.0, "ped_thick": 0.022, "umb_col": c("#a49a8c"),
		"orb_col": c("#ffd98a"), "orb_core": c("#fff8e6"), "orb_energy": 2.6, "orb_halo": 0.3,
		"metro_col": c("#39ff6a"), "metro_energy": 2.6,
		"asphalt_col": c("#0b0a0c"), "walk_col": c("#121012"), "paint_col": c("#6a6660"),
		"spill_col": c("#ff8a20"), "spill": 0.5, "puddle_amount": 0.55, "refl_strength": 1.1, "streak": 0.07, "ripple": 0.005, "asphalt_wet": 0.45,
		"rain_col": c("#c8c0b4"), "rain_base": 0.02, "rain_lit": 0.55, "rain_width": 0.008, "rain_count": 9000, "rain_slant": 0.22,
		"glow_intensity": 0.9, "glow_threshold": 0.85, "glow_wide": 0.8, "exposure": 1.0,
		"bg_count": 60, "bg_energy_mul": 0.55, "beacon_col": c("#ff2a1a"),
	}
