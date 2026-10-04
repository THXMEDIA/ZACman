// Amsterdam: cut-out shapes of the model (gables, trees, bridge cheeks, the
// church's tower stages), extruded at level build and merged into ONE mesh.
// Faces: UV = polygon coordinates in metres. Cut edges: UV.x = distance along
// the outline (m), UV.y = 0..1 across the board — liner, flute, liner with
// dark open cavities. Per vertex: COLOR = (brightness, offset seed, paint
// 0 kraft / 0.5 white / 1 exit green, 1 = cut edge).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_back;

#include "res://shaders/amsterdam_common.gdshaderinc"

uniform vec3 white_paint : source_color = vec3(0.914, 0.894, 0.847);
uniform vec3 exit_paint : source_color = vec3(0.0, 0.722, 0.580);

varying float vdist;
varying vec4 vcol;

void vertex() {
	vdist = length((MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz - CAMERA_POSITION_WORLD);
	vcol = COLOR;
}

void fragment() {
	float far = 1.0 - smoothstep(far_flat * 0.5, far_flat, vdist);
	vec3 c; vec2 nxy; float r;
	float bri = mix(0.82, 1.08, vcol.r);
	vec2 off = vec2(vcol.g * 71.0, vcol.g * 37.0);
	float paint = vcol.b > 0.25 ? 1.0 : 0.0;
	vec3 paint_col = vcol.b > 0.75 ? exit_paint : white_paint;
	if (vcol.a > 0.5) {
		float u = UV.x;
		float v = UV.y;
		float paper = flute_mask(u, v, far);
		kraft_face(vec2(u, v * 0.4) + off, far, c, nxy, r);
		c *= bri;
		float w = 0.5 + 0.32 * sin(u * 6.2831853 / pitch);
		float occ = smoothstep(0.0, 0.32, abs(v - w));
		c = mix(c * 0.12 * (1.6 - occ), c * vec3(1.10, 1.07, 1.02), paper);
		c *= 0.92 + 0.12 * vn(vec2(u * 40.0, v * 4.0));
		NORMAL_MAP = vec3(0.5, 0.5 + 0.25 * (w - v) * (1.0 - paper) * far, 1.0);
		ROUGHNESS = 0.93;
		AO = mix(0.45, 1.0, paper);
		AO_LIGHT_AFFECT = 0.5;
		if (paint > 0.0) c = mix(c, paint_col * (0.9 + 0.1 * paper), 0.45 * paper);
		ALBEDO = c;
	} else {
		kraft_face(UV + off, far, c, nxy, r);
		c *= bri;
		float ribs = sin(UV.x * 6.2831853 / pitch);
		c *= 1.0 - 0.03 * ribs * far;
		nxy.x += cos(UV.x * 6.2831853 / pitch) * 0.22 * far;
		if (paint > 0.0) {
			float brush = vn(UV * vec2(0.4, 2.2)) * 0.6 + vn(UV * vec2(1.8, 7.0)) * 0.4;
			c = mix(c, paint_col * (0.92 + 0.1 * brush), paint);
			r = mix(r, 0.55, paint);
		}
		NORMAL_MAP = vec3(nxy * 0.5 + 0.5, 1.0);
		ROUGHNESS = r;
		ALBEDO = c;
	}
}
