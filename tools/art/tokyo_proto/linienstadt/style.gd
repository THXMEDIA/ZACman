# Richtung B "Linienstadt": schwarz + duenne kaltweisse Linien, Farbe NUR als Rolle,
# Boden als schwarze Glasflaeche (ueberall spiegelnd).
extends RefCounted
static func c(h: String) -> Color: return Color.html(h)
static func style() -> Dictionary:
	return {
		"bg": c("#000000"), "fog_col": c("#000000"), "fog_density": 0.018,
		"world_cols": [c("#dfe8f0"), c("#8d98a6"), c("#dfe8f0")],
		"mass_col": c("#000000"),
		"line_energy": 1.7, "line_thick": 0.06, "fade_h": 45.0, "top_mul": 0.15,
		"floor_step": 3.2, "floor_prob": 0.7, "floor_energy_mul": 0.35, "floor_thick_mul": 0.6, "mullion_prob": 0.5, "mullion_step": 2.0,
		"accent": c("#dfe8f0"), "accent_energy": 2.6,
		"sockel_col": c("#dfe8f0"), "sockel_energy": 2.4, "sockel_thick": 0.05, "shop_energy": 0.0,
		"curb_col": c("#dfe8f0"), "curb_energy": 1.0,
		"lamp_col": c("#dfe8f0"), "lamp_energy": 3.0, "lamp_halo": 0.15, "lamp_pool": 0.08, "lamp_rain": 0.6, "pole_energy": 0.15,
		"screen_a": c("#2a3038"), "screen_b": c("#dfe8f0"), "screen_mono": 1.0, "screen_light": c("#dfe8f0"), "screen_energy": 1.5, "screen_halo": 0.12,
		"sign_col": c("#8d98a6"), "sign_energy": 2.0, "cat_col": c("#dfe8f0"),
		"car_col": c("#5a6470"), "car_energy": 0.9, "head_col": c("#ffffff"), "tail_col": c("#ff1f3d"), "beam_energy": 0.07,
		"ped_col": c("#6d7884"), "ped_energy": 1.0, "ped_thick": 0.018, "umb_col": c("#6d7884"),
		"orb_col": c("#ffcf6e"), "orb_core": c("#fff6dc"), "orb_energy": 2.6, "orb_halo": 0.35,
		"metro_col": c("#00ff9c"), "metro_energy": 2.6,
		"asphalt_col": c("#020203"), "walk_col": c("#040405"), "paint_col": c("#2a2e34"),
		"spill_col": c("#dfe8f0"), "spill": 0.0, "puddle_amount": 0.5, "glass": 1.0, "refl_strength": 0.85, "streak": 0.015, "ripple": 0.0015, "asphalt_wet": 1.0,
		"rain_col": c("#dfe8f0"), "rain_base": 0.015, "rain_lit": 0.5, "rain_width": 0.006, "rain_count": 7000, "rain_slant": 0.06, "rain_len": 0.9,
		"glow_intensity": 0.6, "glow_threshold": 1.0, "glow_wide": 0.5, "exposure": 1.0,
		"halo_scale": 0.8, "halo_energy": 0.7, "cone_energy": 0.8,
		"bg_count": 80, "bg_energy_mul": 0.5, "beacon_col": c("#ff1f3d"),
	}
