// Shared parts of the Amsterdam cardboard shaders (docs/design/amsterdam-explorer.md).
// The kraft colour comes from a CC0 photo scan (Poly Haven "Cardboard Box 01",
// docs/art/lizenzen.md), sampled at two scales against tiling; the corrugation
// (flutes on cut edges, washboard ribs on faces) is procedural. Everything that
// repeats at the flute pitch fades to its mean colour with distance (moire).

uniform sampler2D foto_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foto_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foto_rgh : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float foto_m = 16.0;        // world size of one scan tile (m)
uniform float foto_detail_m = 3.1;  // second, smaller sampling for detail
uniform vec3 foto_mean : source_color = vec3(0.616, 0.510, 0.341);
uniform vec3 kraft : source_color = vec3(0.663, 0.506, 0.341);
uniform float pitch = 0.7;          // flute pitch (m)
uniform float far_flat = 45.0;      // beyond: no ribs, no normal detail (moire)

float h11(float p) { return fract(sin(p * 127.1) * 43758.5453); }
float h21(vec2 p) { p = fract(p * vec2(234.34, 435.345)); p += dot(p, p + 34.23); return fract(p.x * p.y); }
float vn(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1, 0)), f.x), mix(h21(i + vec2(0, 1)), h21(i + vec2(1, 1)), f.x), f.y);
}

// Kraft colour, roughness and a tangent-space normal offset at a point of a
// flat face (p in metres, any 2D parametrisation of the face), with explicit
// screen derivatives of p (dpx, dpy): safe after a discard or inside a
// branch that differs between neighbouring pixels (code W5).
void kraft_face_grad(vec2 p, vec2 dpx, vec2 dpy, float far, out vec3 c, out vec2 nxy, out float r) {
	vec2 pa = p / foto_m; vec2 ax = dpx / foto_m; vec2 ay = dpy / foto_m;
	vec2 pb = p / foto_detail_m + vec2(0.37, 0.11); vec2 bx = dpx / foto_detail_m; vec2 by = dpy / foto_detail_m;
	vec3 a = textureGrad(foto_alb, pa, ax, ay).rgb;
	vec3 b = textureGrad(foto_alb, pb, bx, by).rgb;
	vec3 det = (a / foto_mean) * mix(vec3(1.0), b / foto_mean, 0.35 * far);
	c = kraft * det;
	vec3 na = textureGrad(foto_nrm, pa, ax, ay).rgb * 2.0 - 1.0;
	vec3 nb = textureGrad(foto_nrm, pb, bx, by).rgb * 2.0 - 1.0;
	nxy = (na.xy * 0.6 + nb.xy * 0.5) * far;
	r = mix(0.86, textureGrad(foto_rgh, pa, ax, ay).r, 0.5);
}

// The same with implicit derivatives - only where the caller's branch is
// uniform per triangle (panel: per instance and face; cut-outs; flutes).
void kraft_face(vec2 p, float far, out vec3 c, out vec2 nxy, out float r) {
	vec3 a = texture(foto_alb, p / foto_m).rgb;
	vec3 b = texture(foto_alb, p / foto_detail_m + vec2(0.37, 0.11)).rgb;
	vec3 det = (a / foto_mean) * mix(vec3(1.0), b / foto_mean, 0.35 * far);
	c = kraft * det;
	vec3 na = texture(foto_nrm, p / foto_m).rgb * 2.0 - 1.0;
	vec3 nb = texture(foto_nrm, p / foto_detail_m + vec2(0.37, 0.11)).rgb * 2.0 - 1.0;
	nxy = (na.xy * 0.6 + nb.xy * 0.5) * far;
	r = mix(0.86, texture(foto_rgh, p / foto_m).r, 0.5);
}

// Liner-flute-liner pattern of a cut edge: v 0..1 across the board, u along
// the edge (m). Returns the paper mask (1 = paper, 0 = open cavity).
float flute_mask(float u, float v, float far) {
	float lin = 0.11;
	float w = 0.5 + (0.5 - lin - 0.07) * sin(u * 6.2831853 / pitch);
	float d = abs(v - w);
	float flute = 1.0 - smoothstep(0.035, 0.07, d);
	float inl = step(v, lin) + step(1.0 - lin, v);
	float paper = clamp(flute + inl, 0.0, 1.0);
	// far away: the mean of the pattern (no moire)
	return mix(0.62, paper, far);
}
