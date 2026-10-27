// Heat shimmer around the demon: a camera-facing quad that bends whatever is behind it.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.012;
uniform float speed = 5.0;

void vertex() {
	// billboard: keep position, face the camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float edge = smoothstep(0.0, 0.3, UV.x) * smoothstep(1.0, 0.7, UV.x)
		* smoothstep(0.0, 0.2, UV.y) * smoothstep(1.0, 0.75, UV.y);
	float wave = sin(UV.y * 38.0 - TIME * speed) * 0.6 + sin(UV.x * 21.0 + TIME * speed * 0.7) * 0.4;
	vec2 offs = vec2(wave, wave * 0.5) * strength * edge;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + offs, 0.0).rgb;
	ALPHA = edge;
}
