shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.05, 0.42, 0.75, 0.62);
uniform vec4 deep_color : source_color = vec4(0.01, 0.12, 0.22, 0.78);
uniform vec4 highlight_color : source_color = vec4(0.55, 0.95, 1.0, 0.35);
uniform sampler2D normal_a : hint_normal, repeat_enable;
uniform sampler2D normal_b : hint_normal, repeat_enable;
uniform sampler2D normal_c : hint_normal, repeat_enable;
uniform float normal_scale_a = 0.035;
uniform float normal_scale_b = 0.07;
uniform float normal_scale_c = 0.12;
uniform float wave_speed = 0.045;
uniform float wave_strength = 0.68;
uniform float roughness = 0.035;
uniform float metallic = 0.0;
uniform float fresnel_strength = 0.65;
uniform float fresnel_power = 3.0;


vec3 read_normal(sampler2D normal_texture, vec2 uv) {
	return texture(normal_texture, uv).rgb * 2.0 - 1.0;
}


void fragment() {
	vec2 uv_a = UV * normal_scale_a + vec2(TIME * wave_speed, TIME * wave_speed * 0.18);
	vec2 uv_b = UV * normal_scale_b + vec2(-TIME * wave_speed * 0.53, TIME * wave_speed * 0.31);
	vec2 uv_c = UV * normal_scale_c + vec2(TIME * wave_speed * 0.17, -TIME * wave_speed * 0.44);
	vec3 normal_sample = normalize(
		read_normal(normal_a, uv_a)
		+ read_normal(normal_b, uv_b)
		+ read_normal(normal_c, uv_c)
	);

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	float ripple = clamp(normal_sample.z * 0.5 + 0.5, 0.0, 1.0);
	vec4 base_color = mix(deep_color, shallow_color, ripple);
	vec4 color = mix(base_color, highlight_color, fresnel * fresnel_strength);

	ALBEDO = color.rgb;
	ALPHA = color.a;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	SPECULAR = 0.95;
	NORMAL_MAP = normalize(vec3(normal_sample.xy * wave_strength, normal_sample.z)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
