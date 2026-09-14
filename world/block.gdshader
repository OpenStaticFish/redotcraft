shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, alpha_to_coverage;

uniform sampler2DArray albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float block_emission : hint_range(0.0, 2.0) = 0.45;
uniform float min_light : hint_range(0.0, 1.0) = 0.05;
// Camera-submerged strength (0 above water), driven by DayNightCycle. Caustics
// are projected from the water surface onto sky-lit upward faces.
global uniform float underwater_caustics;

varying vec4 light_data;
varying float texture_layer;
varying vec3 world_position;
varying float up_face;

void vertex() {
	light_data = CUSTOM0;
	texture_layer = CUSTOM1.x;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	up_face = step(0.5, NORMAL.y);
}

void fragment() {
	vec4 tex = texture(albedo_texture, vec3(UV, texture_layer));
	vec3 block = light_data.rgb;
	vec3 light = max(block + vec3(light_data.a), vec3(min_light));
	ALBEDO = tex.rgb * COLOR.rgb * light;
	if (underwater_caustics > 0.001) {
		vec2 p = world_position.xz * 0.55;
		float wave = sin(p.x + TIME * 0.8) + sin(p.y * 0.9 - TIME * 0.6)
			+ sin((p.x + p.y) * 0.55 + TIME * 1.1);
		float caustic = pow(clamp(wave * 0.333 + 0.5, 0.0, 1.0), 3.0);
		ALBEDO += tex.rgb * vec3(0.24, 0.34, 0.38) * caustic * underwater_caustics
			* light_data.a * up_face;
	}
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.05;
	EMISSION = tex.rgb * COLOR.rgb * block * block_emission;
}
