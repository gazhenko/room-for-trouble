shader_type spatial;
// Shared toon material: vertex colour (or a nearest-filtered pixel texture
// projected in world XZ/XY) with three dithered light bands. Supports local
// dither fading near staff so low walls never hide a player (§12.6).
render_mode specular_disabled, ambient_light_disabled, cull_back;

uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform float use_tex = 0.0;          // 1 = floor (XZ), 2 = wall (XY), 3 = wall (ZY), 4 = UV
uniform float tex_scale = 1.0;
uniform vec4 emission : source_color = vec4(0.0);
uniform float fade_walls = 0.0;
uniform vec4 fade_points[4];          // xyz = staff world pos, w = active
uniform float dither_alpha = 1.0;      // < 1 → ordered-dither transparency
uniform vec3 ambient_color = vec3(0.56, 0.52, 0.62);
uniform vec3 shadow_tint = vec3(0.62, 0.55, 0.78);
uniform float bands = 3.0;

varying vec3 wpos;
varying vec3 wnorm;

float bayer4(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	int idx = q.x + q.y * 4;
	float m[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 to_linear(vec3 v) {
	return mix(v / 12.92, pow((v + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), v));
}

void fragment() {
	vec3 c = to_linear(COLOR.rgb) * tint.rgb;
	if (use_tex > 0.5) {
		vec2 uvp;
		if (use_tex > 4.5) {
			if (abs(wnorm.y) > 0.5) uvp = wpos.xz;
			else if (abs(wnorm.x) > abs(wnorm.z)) uvp = vec2(wpos.z, -wpos.y);
			else uvp = vec2(wpos.x, -wpos.y);
		}
		else if (use_tex < 1.5) uvp = wpos.xz;
		else if (use_tex < 2.5) uvp = vec2(wpos.x, -wpos.y);
		else if (use_tex < 3.5) uvp = vec2(wpos.z, -wpos.y);
		else uvp = UV;
		c *= texture(tex, uvp * tex_scale).rgb;
	}
	float a = dither_alpha * tint.a;
	if (fade_walls > 0.5) {
		for (int i = 0; i < 4; i++) {
			if (fade_points[i].w > 0.5) {
				vec3 fp = fade_points[i].xyz;
				vec2 d = wpos.xz - fp.xz;
				// Only fragments between the player and the camera (+z side) fade.
				if (d.y > -0.15 && d.y < 1.6 && abs(d.x) < 1.1 && wpos.y > 0.12) {
					float k = 1.0 - smoothstep(0.55, 1.1, length(vec2(d.x, d.y * 0.7)));
					a = min(a, 1.0 - 0.85 * k);
				}
			}
		}
	}
	if (a < 0.999 && a < bayer4(FRAGCOORD.xy)) {
		discard;
	}
	ALBEDO = c;
	EMISSION = emission.rgb * emission.a;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = clamp(ndl, 0.0, 1.0) * ATTENUATION;
	float th = bayer4(FRAGCOORD.xy) * 0.12 - 0.06;
	float level;
	if (lit > 0.55 + th) level = 1.0;
	else if (lit > 0.18 + th) level = 0.74;
	else level = 0.5;
	vec3 shade = mix(shadow_tint, vec3(1.0), (level - 0.5) / 0.5);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * level * shade;
}
