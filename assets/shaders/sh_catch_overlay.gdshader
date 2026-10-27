// Full-screen overlay for the catch sequence and for ghost vision afterwards.
// flood: red-black vignette that swallows the screen during the catch.
// vision: red demon vision once you have turned.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float flood : hint_range(0.0, 1.0) = 0.0;
uniform float vision : hint_range(0.0, 1.0) = 0.0;
uniform float shake : hint_range(0.0, 1.0) = 0.0;
uniform float grain_amount = 0.035;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 jitter = vec2(hash(vec2(TIME, 1.0)) - 0.5, hash(vec2(1.0, TIME)) - 0.5) * 0.02 * shake;
	vec3 scene = textureLod(screen_tex, uv + jitter, 0.0).rgb;

	// ghost vision: luminance pushed into blood red, bright things burn
	float lum = dot(scene, vec3(0.299, 0.587, 0.114));
	vec3 red_view = vec3(lum * 2.2, lum * 0.35, lum * 0.25) + vec3(0.06, 0.0, 0.0);
	vec3 col = mix(scene, red_view, vision);

	// vignette flood with ember noise
	float r = length((uv - 0.5) * vec2(1.6, 1.0));
	float dark = smoothstep(0.75 - flood * 0.95, 1.15 - flood * 0.95, r);
	float grain = hash(uv * 900.0 + TIME * 37.0);
	vec3 ember = mix(vec3(0.0), vec3(0.45, 0.04, 0.02), grain * flood);
	col = mix(col, ember, dark * step(0.001, flood));

	// constant light film grain
	col += (hash(uv * 731.0 + fract(TIME * 13.7)) - 0.5) * grain_amount;

	COLOR = vec4(col, 1.0);
}
