// pacman_wall_base.gdshaderinc — Speedrun base look "Lagune" for walls (spec
// docs/design/kaninchen-speedrun.md 1.1, from the art-direction prototype
// tools/art/speedrun_proto/pacman_v2.patch). Shared by pacman_wall.gdshader
// (the base look) and kond_wall.gdshader (the rabbit-condition looks, which
// blend from exactly this base during the 0.8 s transition wave).
//
// Arcade-maze principle (described, not copied): walls are dark mass with a
// glowing outline, corridors are dark channels. Distinct from the original
// through ONE strong glowing top edge instead of a thin double line, a
// turquoise color with a per-level gradient (never blue), a dashed base
// (sense of speed) and vertical lines only at free wall ends.
// Which neighbors are walls comes from MazeView per instance (INSTANCE_CUSTOM).
// Every line is antialiased via fwidth() and fades to its mean on distance
// (no shimmer); the mass is lit, so ghost lights show round corners.

uniform vec3 line_top : source_color = vec3(0.118, 0.949, 0.784);  // #1EF2C8
uniform vec3 line_base : source_color = vec3(0.043, 0.498, 0.659); // #0B7FA8 Lagune; set per level look
uniform vec3 body_color : source_color = vec3(0.024, 0.078, 0.11); // #06141C
uniform float cell = 2.0;          // MazeView.CELL; the BoxMesh is cell x 1 x cell
uniform float edge_w = 0.11;       // glowing top edge (m)
uniform float base_w = 0.04;       // base line (m)
uniform float dash_len = 0.5;      // base dash period (m), spec: 0.5 m
uniform float dash_y = 0.24;       // height of the dashes above the floor (m)
uniform float dash_h = 0.09;
uniform float emission_gain = 2.4;

varying vec3 wpos;
varying vec3 wnorm;
varying vec4 nb;    // r: wall at row-1 (-Z), g: row+1 (+Z), b: col-1 (-X), a: col+1 (+X)
varying vec3 center;
varying float half_h;
varying float half_w;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	nb = INSTANCE_CUSTOM;
	center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	half_h = length(MODEL_MATRIX[1].xyz) * 0.5;
	half_w = length(MODEL_MATRIX[0].xyz) * cell * 0.5;
}

// Antialiased line: d = distance to the center line (m), w = width (m).
// Below one pixel the line is drawn 1 px wide and correspondingly darker
// instead of breaking up — no shimmer on distance.
float line_aa(float d, float w) {
	float fw = max(fwidth(d), 1e-5);
	float wc = max(w, fw);
	float a = clamp((wc * 0.5 - abs(d)) / fw + 0.5, 0.0, 1.0);
	return a * clamp(w / fw, 0.0, 1.0);
}

// The base look of one wall fragment. `cam` = camera position (world).
void pacman_wall(vec3 cam, out vec3 albedo, out vec3 emission) {
	float H = 2.0 * half_h;
	float y = wpos.y - (center.y - half_h);   // 0 = floor
	float top = H - y;                          // 0 = top edge
	vec3 grad = mix(line_base, line_top, smoothstep(0.0, H, y));
	albedo = body_color * mix(1.0, 0.45, clamp(y / max(H, 0.01), 0.0, 1.0));
	vec3 em = vec3(0.0);

	if (wnorm.y > 0.5) {
		// Top face: hidden behind the ceiling at full wall height; plain mass.
		albedo = body_color;
	} else if (abs(wnorm.y) < 0.5) {
		// Side faces
		float rim = line_aa(top - edge_w * 0.5, edge_w);
		float glow = exp(-max(top, 0.0) * 6.0) * 0.12;                 // halo under the top edge
		float base = line_aa(y - base_w * 0.5 - 0.01, base_w);
		bool face_x = abs(wnorm.x) > 0.5;
		float along = face_x ? wpos.z : wpos.x;
		float u = along / dash_len;
		float fu = fwidth(u);
		float dash = line_aa((fract(u) - 0.5) * dash_len, dash_len * 0.45);
		dash = mix(dash, 0.45, clamp(fu * 1.5 - 0.5, 0.0, 1.0));       // on distance: fade to the mean, never moiré
		float dash_band = line_aa(y - dash_y, dash_h) * dash;
		// vertical line only at free ends (corners/openings readable early)
		float h = face_x ? (wpos.z - center.z) : (wpos.x - center.x);
		bool open_neg = face_x ? (nb.r < 0.5) : (nb.b < 0.5);
		bool open_pos = face_x ? (nb.g < 0.5) : (nb.a < 0.5);
		float near_fade = smoothstep(1.3, 3.0, length(wpos - cam));
		float vert = 0.0;
		if (open_neg) { vert = max(vert, line_aa(h + half_w - base_w, base_w * 1.5) * near_fade); }
		if (open_pos) { vert = max(vert, line_aa(half_w - h - base_w, base_w * 1.5) * near_fade); }
		float wash = 0.07 * (1.0 - 0.75 * clamp(y / max(H, 0.01), 0.0, 1.0)); // dark turquoise mass instead of pure black
		em = line_top * max(rim, glow) + line_base * max(base, dash_band) + grad * (vert * 0.85 + wash);
	}
	emission = em * emission_gain;
}
