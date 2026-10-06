// Arles sky, step 2 (run time): flow-map animation of the baked stroke
// texture (arles_sky_bake.gdshader) with two offset samples plus one for the
// direction and the yellow zones - three texture reads, no noise, no loop.
// Drift 0.04 phase per second (far below 0.5 Hz); "Effekte reduzieren"
// (moving = 0) stops it. The sphere is unshaded and ignores the fog.
shader_type spatial;
render_mode unshaded, cull_front, fog_disabled;

uniform sampler2D baked : filter_linear_mipmap, repeat_enable;
uniform vec3 base : source_color = vec3(0.08, 0.13, 0.40);
uniform vec3 mid : source_color = vec3(0.18, 0.33, 0.66);
uniform vec3 light : source_color = vec3(0.50, 0.70, 0.90);
uniform vec3 yellow : source_color = vec3(0.96, 0.79, 0.27);
uniform float speed = 0.04;
uniform float moving = 1.0;
uniform float horizon = 0.22;
uniform vec3 haze : source_color = vec3(0.08, 0.1, 0.25);

varying vec3 dir;

void vertex() {
	dir = normalize((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD);
}

void fragment() {
	float az = atan(dir.x, -dir.z);
	float elev = asin(clamp(dir.y, 0.0, 1.0));
	vec2 uv = vec2(az / 6.2831853 + 0.5, min(1.0 - elev / 1.5708, 0.985));
	vec4 b0 = texture(baked, uv);
	vec2 f = b0.ba * 2.0 - 1.0;
	float t = TIME * speed * moving;
	float ph1 = fract(t); float ph2 = fract(t + 0.5);
	vec2 off = vec2(f.x / 10.0, -f.y / (4.2 * 1.5708)) * 0.35;
	float a1 = texture(baked, uv - off * ph1).r;
	float a2 = texture(baked, uv - off * ph2).r;
	float w = abs(1.0 - 2.0 * ph1);
	float acc = mix(a1, a2, w);
	if (moving < 0.5) acc = b0.r;
	float strokes = smoothstep(0.46, 0.50, acc);
	float hi = smoothstep(0.545, 0.575, acc);
	vec3 c = mix(base, mid, strokes);
	c = mix(c, light, hi * 0.9);
	c = mix(c, yellow, hi * b0.g * 0.85);
	c *= 0.88 + 0.24 * step(0.5, fract(acc * 40.0));
	c *= mix(0.5, 1.0, smoothstep(-0.05, horizon, dir.y));
	c = mix(c, haze, smoothstep(0.10, -0.01, dir.y) * 0.9);
	ALBEDO = c;
}
