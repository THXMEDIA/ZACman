// Wet floor of the Tokyo line city (docs/design/tokyo-explorer.md, M2):
// the only "photoreal" surface. Lit (OmniLights, SSR in Forward+), with
//  - a PRE-BAKED puddle mask (puddle_tex, scripts/tokyo_wet.gd; no fbm per
//    pixel): puddles sharp and glossy, asphalt half-wet; more water in the
//    gutters along the curbs; ROUGHNESS follows the mask (SSR roughness mask)
//  - at most 8 light pools + stretched reflection streaks of the 8 nearest
//    lights (lamps, screens, subway; light_pos/light_col, set by
//    tokyo_life.gd). The streaks are the fallback that makes the floor read
//    as wet without SSR (Compatibility renderer); with SSR they are toned
//    down (fake_refl)
//  - the shop-front glow spilling onto the sidewalk (from the cell map)
//  - a faint reflection of the fog-lit sky at grazing angles: the floor is
//    never pure black.
shader_type spatial;
render_mode cull_back, shadows_disabled;

uniform float cell = 2.0;
uniform sampler2D maze_tex : filter_nearest, repeat_disable;
uniform vec2 maze_size = vec2(47.0, 47.0);
uniform vec3 floor_albedo : source_color = vec3(0.043, 0.039, 0.047);
uniform vec3 walk_albedo : source_color = vec3(0.06, 0.055, 0.058);

uniform sampler2D puddle_tex : filter_linear, repeat_disable;
uniform float puddle_threshold = 0.6;
uniform float gutter_amount = 0.32;
// road bands (world meters): x range of the north-south road, z range of the
// east-west road (between the curbs)
uniform vec2 road_x = vec2(41.0, 51.0);
uniform vec2 road_z = vec2(41.0, 51.0);

uniform vec4 light_pos[8]; // xyz = light, w = source size (m)
uniform vec4 light_col[8]; // rgb = color * energy, w = pool radius (m)
uniform int light_n = 0;
uniform float pool_gain = 0.22;
uniform float streak_gain = 2.6;
uniform float fake_refl = 1.0; // 1 without SSR, lower with SSR (Forward+)

uniform vec3 shop_color : source_color = vec3(1.0, 0.54, 0.13);
uniform float shop_gain = 0.085;
uniform vec3 sky_color : source_color = vec3(0.11, 0.075, 0.047);
uniform float sky_gain = 0.8;
uniform float floor_lift = 0.009;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float wall_at(vec2 c) {
	if (c.x < 0.0 || c.y < 0.0 || c.x >= maze_size.x || c.y >= maze_size.y) {
		return 1.0;
	}
	return texture(maze_tex, (c + 0.5) / maze_size).r;
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 map_uv = (p + cell * 0.5) / (maze_size * cell);
	bool on_road = (p.x > road_x.x && p.x < road_x.y) || (p.y > road_z.x && p.y < road_z.y);

	// ---- puddle mask (baked) + gutters along the curbs ----
	float m = texture(puddle_tex, map_uv).r;
	float dx = min(abs(p.x - road_x.x), abs(p.x - road_x.y));
	float dz = min(abs(p.y - road_z.x), abs(p.y - road_z.y));
	float gutter = exp(-min(dx, dz) * 1.6) * (on_road ? 1.0 : 0.45);
	float puddle = smoothstep(puddle_threshold, puddle_threshold + 0.035, m + gutter * gutter_amount);
	float damp = smoothstep(0.25, 0.75, m); // half-wet asphalt varies a little

	// ---- shop-front glow on the sidewalk (cell map: neighbors that are walls) ----
	vec2 cf = (p + cell * 0.5) / cell;
	vec2 ci = floor(cf);
	vec2 f = cf - ci;
	float shop = 0.0;
	shop += wall_at(ci + vec2(-1.0, 0.0)) * exp(-f.x * cell * 1.3);
	shop += wall_at(ci + vec2(1.0, 0.0)) * exp(-(1.0 - f.x) * cell * 1.3);
	shop += wall_at(ci + vec2(0.0, -1.0)) * exp(-f.y * cell * 1.3);
	shop += wall_at(ci + vec2(0.0, 1.0)) * exp(-(1.0 - f.y) * cell * 1.3);
	shop *= 0.75 + 0.5 * m;

	// ---- view and fresnel (water: ~2 % straight down, strong at grazing) ----
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 I = normalize(wpos - cam);
	float cos_v = clamp(-I.y, 0.0, 1.0);
	// stylized: water is ~2 % straight down, but the wet look needs the
	// reflections a little stronger than physics where the eye looks down
	float fres = 0.08 + 0.92 * pow(1.0 - cos_v, 3.0);
	vec3 R = vec3(I.x, -I.y, I.z);
	vec3 side = normalize(vec3(-R.z, 0.0, R.x) + vec3(1e-5, 0.0, 0.0));

	// ---- light pools and stretched reflections of the nearest lights ----
	vec3 pools = vec3(0.0);
	vec3 refl = vec3(0.0);
	float wl0 = mix(0.045, 0.012, puddle);
	float wv0 = mix(0.20, 0.04, puddle);
	for (int i = 0; i < 8; i++) {
		if (i >= light_n) {
			break;
		}
		vec3 L = light_pos[i].xyz;
		vec3 col = light_col[i].rgb;
		float pr = light_col[i].w;
		vec2 dd = p - L.xz;
		pools += col * exp(-dot(dd, dd) / (pr * pr));
		vec3 D = L - wpos;
		float t = dot(D, R);
		if (t > 0.05) {
			vec3 off = D - R * t;
			float lat = dot(off, side);
			float vert = length(off - side * lat);
			float sz = light_pos[i].w / t;
			float wl = wl0 + sz;
			float wv = wv0 + sz;
			float al = lat / t;
			float av = vert / t;
			// long vertical tail (rough wet asphalt), narrow sideways
			refl += col * exp(-(al * al) / (wl * wl) - abs(av) / wv);
		}
	}

	vec3 base = on_road ? floor_albedo : walk_albedo;
	float wet = mix(0.55 + 0.25 * damp, 1.0, puddle);
	ALBEDO = base * mix(1.0, 0.45, wet);
	ROUGHNESS = mix(mix(0.42, 0.26, damp), 0.035, puddle);
	SPECULAR = 0.5;
	METALLIC = 0.0;

	float refl_amt = fres * mix(0.35, 1.0, puddle) * fake_refl;
	vec3 e = pools * pool_gain * mix(1.0, 0.6, puddle);
	e += refl * streak_gain * refl_amt;
	e += shop_color * shop * shop_gain * (on_road ? 0.25 : 1.0);
	e += sky_color * sky_gain * fres * mix(0.5, 1.0, puddle);
	e += vec3(floor_lift);
	EMISSION = e;
}
