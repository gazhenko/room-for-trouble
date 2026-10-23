shader_type spatial;
// Full-screen post pass at the low internal resolution: 1-pixel ink outlines
// on depth discontinuities and soft highlight lines on convex normal creases.
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled, skip_vertex_transform, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D normal_tex : hint_normal_roughness_texture, filter_nearest;
uniform vec3 ink = vec3(0.16, 0.17, 0.24);
uniform float depth_threshold = 0.06;
uniform float normal_threshold = 0.55;
uniform float highlight = 0.18;
uniform float enabled = 1.0;

void vertex() {
	POSITION = vec4(VERTEX.xy * 2.0, 1.0, 1.0);
}

float lin_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 nrm(vec2 uv) {
	return texture(normal_tex, uv).xyz * 2.0 - 1.0;
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	vec3 col = texture(screen_tex, uv).rgb;
	if (enabled < 0.5) {
		ALBEDO = col;
	} else {
		float d0 = lin_depth(uv, INV_PROJECTION_MATRIX);
		float dl = lin_depth(uv + vec2(-px.x, 0.0), INV_PROJECTION_MATRIX);
		float dr = lin_depth(uv + vec2(px.x, 0.0), INV_PROJECTION_MATRIX);
		float du = lin_depth(uv + vec2(0.0, -px.y), INV_PROJECTION_MATRIX);
		float dd = lin_depth(uv + vec2(0.0, px.y), INV_PROJECTION_MATRIX);
		// Outline only on the nearer side so lines stay exactly one pixel wide.
		float thr = depth_threshold * d0;
		float edge = 0.0;
		edge = max(edge, step(thr, dl - d0));
		edge = max(edge, step(thr, dr - d0));
		edge = max(edge, step(thr, du - d0));
		edge = max(edge, step(thr, dd - d0));
		vec3 n0 = nrm(uv);
		float crease = 0.0;
		crease = max(crease, step(normal_threshold, 1.0 - dot(n0, nrm(uv + vec2(0.0, px.y)))));
		crease = max(crease, step(normal_threshold, 1.0 - dot(n0, nrm(uv + vec2(px.x, 0.0)))));
		vec3 outc = col;
		if (edge > 0.5 && d0 < 200.0) {
			outc = mix(col * 0.35, ink, 0.55);
		} else if (crease > 0.5 && d0 < 200.0) {
			outc = col + vec3(highlight) * (1.0 - col * 0.5);
		}
		ALBEDO = outc;
	}
}
