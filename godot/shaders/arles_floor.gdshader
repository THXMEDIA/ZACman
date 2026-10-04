// Arles: calm paving (technical condition "ruhiger Boden"): strokes along the
// street, contrast about half of the walls', 7 % ochre accent; the dark gutter
// lies exactly on the block edge (= collision edge) with a lighter kerb strip
// beside it; on the Place du Forum the strokes circle the café terrace.
// maze_tex (MazeView): r = 1 wall cell.
shader_type spatial;

#include "res://shaders/arles_common.gdshaderinc"

uniform sampler2D maze_tex : filter_nearest;
uniform vec2 maze_size = vec2(45.0, 41.0);
uniform vec3 pave_a : source_color = vec3(0.2);
uniform vec3 pave_b : source_color = vec3(0.18);
uniform vec3 pave_c : source_color = vec3(0.6, 0.45, 0.2);
uniform vec3 gutter : source_color = vec3(0.05, 0.05, 0.1);
uniform vec3 kerb : source_color = vec3(0.4, 0.4, 0.5);
uniform vec3 outside : source_color = vec3(0.08, 0.08, 0.16);
uniform vec4 plaza = vec4(16.0, 30.0, 38.0, 52.0); // Place du Forum (map x0, z0, x1, z1)
uniform vec2 plaza_ctr = vec2(27.0, 30.0);
uniform float calm_floor = 0.45; // floor calmer than the walls (0.62 with reduced effects)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz + MAP_SHIFT;
}

float o(vec2 cell) {
	if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= maze_size.x || cell.y >= maze_size.y) return 0.0;
	return 1.0 - texture(maze_tex, (cell + 0.5) / maze_size).r;
}

void fragment() {
	vec2 cell = floor(wpos.xz / 2.0); vec2 f = fract(wpos.xz / 2.0);
	float here = o(cell);
	float ow = o(cell + vec2(-1, 0)); float oe = o(cell + vec2(1, 0));
	float on = o(cell + vec2(0, -1)); float os = o(cell + vec2(0, 1));
	float a = (on + os > ow + oe) ? 1.5708 : 0.0;
	int mode = 0;
	if (wpos.x > plaza.x && wpos.x < plaza.z && wpos.z > plaza.y && wpos.z < plaza.w) mode = 1;
	vec2 uv = wpos.xz;
	float ang = cell_angle(uv, 1.1, a, mode, plaza_ctr);
	float lod = stroke_lod(length(wpos - (CAMERA_POSITION_WORLD + MAP_SHIFT)), length(fwidth(uv / 0.2)));
	vec2 dv; float ridge;
	vec3 c = impasto(uv, pave_a, pave_b, pave_c, 0.07, ang, 1.1, 0.2, max(lod, max(calm_floor, calm * 0.62)), dv, ridge);
	float dmin = 9.0;
	if (ow < 0.5) dmin = min(dmin, f.x * 2.0);
	if (oe < 0.5) dmin = min(dmin, (1.0 - f.x) * 2.0);
	if (on < 0.5) dmin = min(dmin, f.y * 2.0);
	if (os < 0.5) dmin = min(dmin, (1.0 - f.y) * 2.0);
	if (dmin < 0.26) c = gutter;
	else if (dmin < 0.40) c = mix(kerb, c, 0.35);
	if (here < 0.5) c = outside;
	ALBEDO = c; ROUGHNESS = 0.7; SPECULAR = 0.35;
	vec3 wtan = vec3(dv.x, 0.0, dv.y);
	NORMAL = normalize((VIEW_MATRIX * vec4(normalize(vec3(0, 1, 0) + wtan * ridge * 0.35), 0.0)).xyz);
	EMISSION = c * pools(wpos, vec3(0, 1, 0)) * 1.15;
}
