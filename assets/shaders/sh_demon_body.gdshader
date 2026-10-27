// Esmiringhoy skin: charred plates, ember light pulsing in the cracks,
// darkened rim so the silhouette melts into the dark, and a dissolve for banishing.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

uniform sampler2D skin_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D crack_mask : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 ember_color : source_color = vec4(1.0, 0.353, 0.122, 1.0);
uniform float ember_energy = 2.5;
uniform float pulse_hz = 0.6;   // 0.6 lurking, 2.0 hunting
uniform float flare = 0.0;      // 1.0 while frozen in a flashlight beam
uniform float tri_scale = 1.6;
uniform float rim_dark = 0.75;
uniform float skin_dark = 0.45;  // keeps it a silhouette even in a direct beam
uniform float dissolve = 0.0;   // 0 = solid, 1 = gone

varying vec3 obj_pos;
varying vec3 obj_nrm;

vec4 triplanar(sampler2D tex, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z + 1e-5);
	return texture(tex, p.zy) * w.x + texture(tex, p.xz) * w.y + texture(tex, p.xy) * w.z;
}

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

void fragment() {
	vec3 p = obj_pos * tri_scale;
	vec3 n = normalize(obj_nrm);
	vec3 skin = triplanar(skin_tex, p, n).rgb;
	float mask = triplanar(crack_mask, p, n).r;

	// dissolve into smoke from the edges of each crack outward
	float d = mask * 0.6 + hash(floor(obj_pos * 40.0)) * 0.4;
	if (d < dissolve) {
		discard;
	}
	float burn_edge = smoothstep(dissolve, dissolve + 0.06, d);

	float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	ALBEDO = skin * skin_dark * mix(1.0, 1.0 - rim_dark, rim);
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;

	float pulse = 0.55 + 0.45 * sin(TIME * 6.2831 * pulse_hz);
	vec3 hot = mix(ember_color.rgb, vec3(1.0, 0.85, 0.6), flare * 0.6);
	EMISSION = hot * mask * ember_energy * (pulse + flare * 2.5);
	EMISSION += ember_color.rgb * (1.0 - burn_edge) * 4.0 * step(0.001, dissolve);
}
