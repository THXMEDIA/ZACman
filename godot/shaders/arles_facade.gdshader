// Arles: all houses of the street grid (and the far city, the far bank) as ONE
// mesh. Vertex colour: r = palette / 8, g = lot seed, b = eave height / 20,
// a = share of lit windows (1 city, less in the distance). Windows, open and
// closed shutters, lit shops, doors, the dark plinth row (= collision edge),
// the cornice and the painted warm glow around lit windows come from the
// shader; strokes follow the wall, the roof strokes run down the slope.
shader_type spatial;

#include "res://shaders/arles_common.gdshaderinc"

uniform vec3 pal_a[6]; uniform vec3 pal_b[6]; uniform vec3 pal_c[6];
uniform vec3 roof_a[4]; uniform vec3 roof_b[4];
uniform vec3 roof_c = vec3(0.03, 0.03, 0.09);
uniform vec3 win_a = vec3(0.92, 0.58, 0.07);
uniform vec3 win_b = vec3(0.90, 0.45, 0.04);
uniform vec3 win_c = vec3(1.0, 0.88, 0.45);
uniform vec3 shut_a = vec3(0.10, 0.18, 0.42);
uniform vec3 shut_b = vec3(0.06, 0.11, 0.28);
uniform vec3 glass = vec3(0.01, 0.015, 0.05);
uniform vec3 door_col = vec3(0.07, 0.04, 0.03);
uniform float lit_ratio = 0.38;
uniform float win_emit = 1.5;

varying vec3 wpos; varying vec3 wn; varying vec4 vc;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + MAP_SHIFT;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vc = COLOR;
}

void fragment() {
	// quantise the vertex colour: interpolation noise would flip the hash per pixel
	vec4 q = floor(vc * 255.0 + 0.5) / 255.0;
	int pi = clamp(int(q.r * 8.0 + 0.5), 0, 5); float seed = q.g; float eave = q.b * 20.0;
	float lit = lit_ratio * q.a;
	bool roof = wn.y > 0.3;
	vec2 uv; vec3 tu; vec3 tv; float a; float len; float wid;
	vec3 ca; vec3 cb; vec3 cc; float acc;
	if (roof) {
		uv = wpos.xz; tu = vec3(1, 0, 0); tv = vec3(0, 0, 1);
		a = atan(wn.z, wn.x) + (hash21(floor(wpos.xz * 0.7)) - 0.5) * 0.4; len = 0.55; wid = 0.13;
		int ri = int(mod(seed * 13.0, 4.0));
		ca = roof_a[ri]; cb = roof_b[ri]; cc = roof_c; acc = 0.14;
	} else {
		if (abs(wn.x) > 0.5) { uv = wpos.zy; tu = vec3(0, 0, 1); tv = vec3(0, 1, 0); }
		else { uv = wpos.xy; tu = vec3(1, 0, 0); tv = vec3(0, 1, 0); }
		len = 0.75; wid = 0.09;
		a = cell_angle(uv, len, (seed - 0.5) * 0.6, 0, vec2(0.0));
		ca = pal_a[pi]; cb = pal_b[pi]; cc = pal_c[pi]; acc = 0.12;
	}
	float dist = length(wpos - (CAMERA_POSITION_WORLD + MAP_SHIFT));
	float lod = stroke_lod(dist, length(fwidth(uv / wid)));
	float amp = near_amp(dist);
	// derivatives in uniform control flow (code W5): the window grid's
	// fwidth is taken here, before the roof / wall branch
	float s = abs(wn.x) > 0.5 ? wpos.z : wpos.x;
	float wl = smoothstep(0.10, 0.40, fwidth(s) * 0.5); // window grid too fine for the pixels: average
	vec2 dv; float ridge;
	vec3 c = impasto(uv, ca, cb, cc, acc, a, len, wid, lod, amp, dv, ridge);
	vec3 emitc = vec3(0.0);
	if (!roof) {
		float y = wpos.y;
		float colid = floor(s / 2.0); float fx = fract(s / 2.0) - 0.5;
		float flo = floor((y - 0.4) / 3.0); float fy = y - (flo * 3.0 + 0.4);
		float h1 = hash21(vec2(colid, flo) + seed * 31.7);
		float h2 = hash21(vec2(flo + 5.0, colid) + seed * 7.3);
		float h3 = hash21(vec2(colid * 1.7, flo + 3.0) + seed * 3.1);
		vec3 c_wall = c;
		if (y < 0.55) c *= 0.5;                                    // plinth = collision edge
		if (y > eave - 0.38 && y < eave) c = mix(c * 0.42, c * 1.2, step(eave - 0.09, y)); // cornice
		vec3 wc = c; float win = 0.0; float we = 0.0;
		float iny = step(0.9, fy) * step(fy, 2.45);
		if (flo >= 1.0 && y < eave - 0.55 && h1 < 0.85) {
			if (abs(fx) < 0.19 && iny > 0.5) {
				if (h2 < lit) {
					vec2 d2; float r2;
					wc = impasto(uv, win_a, win_b, win_c, 0.25, 1.5708 + (h3 - 0.5) * 0.5, 0.42, 0.13, max(lod, 0.25), amp, d2, r2);
					we = win_emit;
					if (abs(fx) < 0.016 || abs(fy - 1.95) < 0.028) { wc *= 0.3; we *= 0.25; }
				} else if (h3 < 0.62) {
					wc = mix(shut_a, shut_b, step(0.5, fract(fy * 9.0))) * mix(0.85, 1.15, h1);
				} else { wc = glass; }
				win = 1.0;
			} else if (h2 < lit && abs(fx) < 0.31 && iny > 0.5) {
				wc = mix(shut_a, shut_b, step(0.5, fract(fy * 9.0))) * 0.95; win = 1.0; // open shutters
			}
			if (abs(fx) < 0.25 && fy > 0.78 && fy < 0.9) { wc = c * 0.45; win = 1.0; } // sill
		}
		if (flo < 1.0 && y < eave - 0.55) {
			if (h1 < 0.20 && abs(fx) < 0.24 && fy < 2.35 && y > 0.55) {
				wc = door_col * (0.8 + 0.4 * step(0.5, fract(fx * 9.0))); win = 1.0;
			} else if (h1 < 0.34 && abs(fx) < 0.40 && fy > 0.55 && fy < 2.6) {
				vec2 d2; float r2;
				wc = impasto(uv, win_a, win_b, win_c, 0.25, 1.5708, 0.42, 0.13, max(lod, 0.25), amp, d2, r2);

				we = win_emit * 0.75; win = 1.0;
			}
		}
		c = mix(c, wc, win);
		emitc = wc * we * win;
		// warm glow around lit windows on the wall (painted, no light)
		if (flo >= 1.0 && y < eave - 0.55 && h1 < 0.85 && h2 < lit) {
			float ddx = max(abs(fx) * 2.0 - 0.38, 0.0); float ddy = max(abs(fy - 1.675) - 0.775, 0.0);
			emitc += win_a * exp(-length(vec2(ddx, ddy)) * 3.5) * 0.45 * (1.0 - win) * win_emit;
		}
		float upper_ = step(1.0, flo) * step(y, eave - 0.55);
		c = mix(c, c_wall * 0.8, wl);
		emitc = mix(emitc, win_a * win_emit * lit * 0.25 * upper_, wl);
		ridge *= (1.0 - win * 0.8);
	}
	vec3 wtan = normalize(tu * dv.x + tv * dv.y);
	vec3 n = normalize(wn + wtan * ridge * 0.7 * (1.0 - calm * 0.5));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = c; ROUGHNESS = 0.55; SPECULAR = 0.5;
	EMISSION = emitc + c * pools(wpos, wn);
}
