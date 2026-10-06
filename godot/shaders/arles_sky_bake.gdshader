// Arles sky, step 1 (once while the level is built, technical condition
// "Himmel backen"): line integral convolution over a swirl field, seamless all
// around (periodic in x: the player turns freely). Output: R = stroke value,
// G = chrome-yellow zone, BA = flow direction. 2048 x 1024, equirectangular
// (u = azimuth, v = elevation from the zenith down to the horizon).
shader_type canvas_item;

uniform float W = 10.0;

float hash21(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnp(vec2 p, float per) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float x0 = mod(i.x, per); float x1 = mod(i.x + 1.0, per);
	float a = hash21(vec2(x0, i.y)), b = hash21(vec2(x1, i.y)), c = hash21(vec2(x0, i.y + 1.0)), d = hash21(vec2(x1, i.y + 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
vec2 vortex(vec2 p, vec2 c, float s, float k) {
	vec2 r = p - c; r.x -= W * round(r.x / W);
	float d2 = dot(r, r);
	return vec2(-r.y, r.x) * s * exp(-d2 * k) / (sqrt(d2) + 0.15);
}
vec2 flow(vec2 p) {
	vec2 f = vec2(0.28, 0.06);
	f += vortex(p, vec2(0.7, 2.0), 2.6, 0.22);
	f += vortex(p, vec2(2.4, 1.4), -2.0, 0.3);
	f += vortex(p, vec2(3.9, 2.6), 1.8, 0.35);
	f += vortex(p, vec2(5.6, 1.6), -1.7, 0.3);
	f += vortex(p, vec2(7.1, 2.2), 2.2, 0.28);
	f += vortex(p, vec2(8.7, 1.3), -1.5, 0.4);
	f += vortex(p, vec2(4.6, 3.6), 1.4, 0.5);
	f += vortex(p, vec2(9.4, 3.4), -1.4, 0.45);
	return normalize(f);
}
void fragment() {
	float elev = (1.0 - UV.y) * 1.5708;
	vec2 p = vec2(UV.x * W, sin(elev) * 4.2 + 0.4);
	float acc = 0.0; vec2 q = p; vec2 q2 = p;
	for (int i = 0; i < 7; i++) {
		q += flow(q) * 0.03; q2 -= flow(q2) * 0.03;
		acc += vnp(q * vec2(14.0, 26.0), 14.0 * W) + vnp(q2 * vec2(14.0, 26.0), 14.0 * W);
	}
	acc /= 14.0;
	float zone = smoothstep(0.62, 0.78, vnp(p * 1.8 + vec2(7.0, 3.0), 18.0));
	vec2 f = flow(p);
	COLOR = vec4(acc, zone, f * 0.5 + 0.5);
}
