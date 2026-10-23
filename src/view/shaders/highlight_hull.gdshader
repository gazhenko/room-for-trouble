shader_type spatial;
// Inverted-hull outline used as material_overlay for the selected interaction
// target and for item silhouettes. Pulses gently (reduced-motion: steady).
render_mode unshaded, cull_front, depth_draw_never, specular_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.86, 0.35, 1.0);
uniform float width = 0.045;
uniform float pulse = 1.0;

void vertex() {
	VERTEX += NORMAL * width * (1.0 + 0.25 * pulse * sin(TIME * 6.0));
}

void fragment() {
	ALBEDO = color.rgb;
}
