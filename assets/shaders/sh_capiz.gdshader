// Capiz shell window panes, back-lit by cold moonlight.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, shadows_disabled;

uniform sampler2D capiz_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 tiling = vec2(1.0, 1.0);
uniform vec4 moon_color : source_color = vec4(0.486, 0.612, 0.788, 1.0);
uniform float glow = 0.4;

void fragment() {
	vec4 c = texture(capiz_tex, UV * tiling);
	float is_frame = step(0.95, c.a);
	ALBEDO = c.rgb * mix(0.2, 0.05, is_frame);
	// panes glow faintly where moonlight passes through the shell
	EMISSION = moon_color.rgb * c.rgb * glow * (1.0 - is_frame);
	ROUGHNESS = 0.6;
	ALPHA = mix(c.a, 1.0, is_frame);
}
