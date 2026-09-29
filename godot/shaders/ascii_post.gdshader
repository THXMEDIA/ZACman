// ascii_post.gdshader
//
// Screen-space Post-Effekt fuer den Matrix-ASCII-Look: wandelt das gerenderte
// Bild in ein gruenes ASCII-Punktraster um. Nahe am Spieler (innerhalb
// radius_near) bleibt das Bild lesbar-scharf (Pellets/Gegner gut erkennbar);
// zwischen radius_near und radius_far wird linear zu ASCII geblendet;
// jenseits radius_far — inklusive der Labyrinthwaende, die im engen
// Korridor fast immer in diesem Bereich liegen — ist alles ASCII. Wird auf
// einem QuadMesh angewendet, das als Kind der Kamera direkt vor ihr haengt
// (siehe player_controller.gd / _setup_ascii_quad). Portiert aus dem
// ReclaimTheStreets-Projekt, hier auf reines Matrix-Gruen getrimmt.
//
// Technik: SCREEN_TEXTURE + DEPTH_TEXTURE sind in Godot-4-Spatial-Shadern
// eingebaute Sampler fuer genau diesen Zweck (kein zusaetzlicher Viewport
// noetig). Die "Zeichen" werden nicht aus einer Font-Textur gesampelt,
// sondern als 8x8-Bitmuster direkt im Shader kodiert (space/.:-=+*#@), damit
// keine externen Asset-Dateien gebraucht werden.

shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, blend_mix;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest;

uniform float cell_size_px = 8.0;
uniform float radius_near_m = 2.2;   // volle Realgrafik bis hierhin (Pellets/Gegner direkt vor dir)
uniform float radius_far_m = 6.0;    // ab hier volles ASCII (Waende im Korridor fast immer)
uniform vec3 ascii_tint = vec3(0.25, 1.0, 0.35);
uniform float ascii_darkness = 0.06; // Hintergrund-Helligkeit der Zellen (dunkler = mehr Matrix-Kontrast)

// 10 Helligkeitsstufen, jede als 8 Zeilen a 8 Bit (MSB = linkes Pixel).
// Grob von "leer" bis "voll" sortiert, angelehnt an klassische ASCII-Ramps.
const int GLYPH_ROWS[80] = int[80](
    // 0: ' '
    0,0,0,0,0,0,0,0,
    // 1: '.'
    0,0,0,0,0,24,24,0,
    // 2: ':'
    0,24,24,0,24,24,0,0,
    // 3: '-'
    0,0,0,126,0,0,0,0,
    // 4: '='
    0,0,126,0,126,0,0,0,
    // 5: '+'
    0,24,24,126,126,24,24,0,
    // 6: '*'
    36,24,126,24,36,0,0,0,
    // 7: '#'
    102,102,255,102,255,102,102,0,
    // 8: '%'
    99,102,60,24,60,102,198,0,
    // 9: '@'
    60,102,110,106,110,96,60,0
);

float luminance(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

int glyph_bit(int glyph_index, ivec2 local) {
    // local.x/local.y in [0,7]; Muster ist auf 8x8 ausgelegt.
    int row = GLYPH_ROWS[glyph_index * 8 + local.y];
    int bit = (row >> (7 - local.x)) & 1;
    return bit;
}

void fragment() {
    vec2 screen_uv = SCREEN_UV;
    vec3 real_color = textureLod(SCREEN_TEXTURE, screen_uv, 0.0).rgb;

    // Distanz zum Spieler aus der Tiefe rekonstruieren (View-Space).
    float depth = textureLod(DEPTH_TEXTURE, screen_uv, 0.0).r;
    vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
    vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view_pos.xyz /= view_pos.w;
    float dist_m = length(view_pos.xyz);

    // Zellkoordinaten in Pixeln.
    vec2 pixel = screen_uv * VIEWPORT_SIZE;
    vec2 cell_origin = floor(pixel / cell_size_px) * cell_size_px;
    vec2 cell_uv = (cell_origin + vec2(cell_size_px * 0.5)) / VIEWPORT_SIZE;
    vec3 cell_color = textureLod(SCREEN_TEXTURE, cell_uv, 0.0).rgb;

    float lum = clamp(luminance(cell_color), 0.0, 1.0);
    int glyph_index = clamp(int(lum * 9.0 + 0.5), 0, 9);

    ivec2 local = ivec2(mod(pixel - cell_origin, cell_size_px));
    // Bitmuster ist 8x8, Zelle kann groesser/kleiner sein -> auf 0..7 skalieren.
    ivec2 sample_local = clamp(ivec2(vec2(local) / cell_size_px * 8.0), ivec2(0), ivec2(7));
    int lit = glyph_bit(glyph_index, sample_local);

    vec3 ascii_color = mix(cell_color * ascii_darkness, cell_color * ascii_tint, float(lit));

    float blend = smoothstep(radius_near_m, radius_far_m, dist_m);
    vec3 final_color = mix(real_color, ascii_color, blend);

    ALBEDO = final_color;
    ALPHA = 1.0;
}
