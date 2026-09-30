// mario_vista.gdshader
//
// A flat pixelated backdrop panel capping each end of the maze's side
// tunnel (see MazeView._build_tunnel_vistas): a blocky sun, rolling green
// hills and a couple of bushes, deliberately in warm colors rather than
// the interior "sky" ceiling's blue — the tunnel mouths shouldn't just
// bleed into flat blue void, and this is styled like a classic Super
// Mario overworld backdrop instead.
//
// Technique: procedural, no texture asset — snap UV to a coarse grid
// (pixel_size) for the retro-blocky look, then layer a few cheap shapes
// (a circle for the sun/bushes, exp-falloff bumps for the hills) with
// step()/mix(). cull_disabled so the panel reads correctly regardless of
// which way its quad ends up facing.

shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float pixel_size = 0.045; // UV-space grid the shapes below snap to, for the blocky look

uniform vec3 sky_color = vec3(0.98, 0.82, 0.58);
uniform vec3 sun_color = vec3(1.0, 0.85, 0.2);
uniform vec3 hill_far_color = vec3(0.42, 0.78, 0.28);
uniform vec3 hill_near_color = vec3(0.22, 0.58, 0.17);
uniform vec3 bush_color = vec3(0.18, 0.5, 0.15);

float circle(vec2 uv, vec2 center, float r) {
	return step(length(uv - center), r);
}

void fragment() {
	vec2 puv = floor(UV / pixel_size) * pixel_size + pixel_size * 0.5;

	vec3 color = sky_color;

	float sun = circle(puv, vec2(0.78, 0.8), 0.1);
	color = mix(color, sun_color, sun);

	// Far hill: a broad, low bump.
	float far_hill_top = 0.34 + 0.09 * exp(-pow((puv.x - 0.32) * 2.6, 2.0));
	float far_hill = step(puv.y, far_hill_top) * step(0.16, puv.y);
	color = mix(color, hill_far_color, far_hill);

	// Near hill: a taller bump in front of the far one, reaching the ground.
	float near_hill_top = 0.24 + 0.15 * exp(-pow((puv.x - 0.6) * 2.2, 2.0));
	float near_hill = step(puv.y, near_hill_top);
	color = mix(color, hill_near_color, near_hill);

	// Ground strip along the bottom.
	float ground = step(puv.y, 0.1);
	color = mix(color, hill_near_color, ground);

	// A couple of bushes sitting on the ground.
	float bush = clamp(circle(puv, vec2(0.18, 0.11), 0.065) + circle(puv, vec2(0.46, 0.09), 0.05), 0.0, 1.0);
	color = mix(color, bush_color, bush);

	ALBEDO = color;
	EMISSION = color * 0.3;
}
