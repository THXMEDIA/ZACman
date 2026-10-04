// Kyoto blocks: the collision boxes stay full height (physics), but they are
// drawn as a thin printed block plan on the page — the pop-up cards on their
// edges are the buildings (docs/design/kyoto-explorer.md).
shader_type spatial;
render_mode unshaded, world_vertex_coords;

uniform float plan_height = 0.06;
uniform vec3 plan_color : source_color = vec3(0.902, 0.878, 0.824);
uniform vec3 edge_color : source_color = vec3(0.553, 0.690, 0.839);
uniform float cell = 2.0;

varying vec3 wp;
varying float up;

void vertex() {
	VERTEX.y = min(VERTEX.y, plan_height);
	wp = VERTEX;
	up = NORMAL.y;
}

void fragment() {
	// top: block plan with a faint printed roof-tile hatch; sides: page edge
	float hatch = step(0.9, fract((wp.x + wp.z) * 1.6));
	vec3 top = mix(plan_color, edge_color, hatch * 0.25);
	ALBEDO = up > 0.5 ? top : edge_color;
}
