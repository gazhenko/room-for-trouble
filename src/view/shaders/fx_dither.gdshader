shader_type spatial;
// Unshaded dithered effect material (steam puffs, sparkles, notes, rings).
render_mode unshaded, cull_disabled, specular_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform float alpha = 1.0;
uniform float soft_edge = 0.0;     // 1 = radial falloff on UV
uniform sampler2D tex : source_color, filter_nearest;
uniform float use_tex = 0.0;

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int idx = q.x + q.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}

vec3 to_linear(vec3 v) {
	return mix(v / 12.92, pow((v + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), v));
}

void fragment() {
	vec4 c = color * vec4(to_linear(COLOR.rgb), COLOR.a);
	if (use_tex > 0.5) {
		c *= texture(tex, UV);
	}
	float a = c.a * alpha;
	if (soft_edge > 0.5) {
		float r = length(UV - vec2(0.5)) * 2.0;
		a *= 1.0 - smoothstep(0.6, 1.0, r);
	}
	if (a < bayer4(FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = c.rgb;
}
