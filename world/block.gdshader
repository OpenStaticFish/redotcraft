shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, alpha_to_coverage;

uniform sampler2DArray albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float block_emission : hint_range(0.0, 2.0) = 0.45;
uniform float min_light : hint_range(0.0, 1.0) = 0.05;

varying vec4 light_data;
varying float texture_layer;

void vertex() {
	light_data = CUSTOM0;
	texture_layer = CUSTOM1.x;
}

void fragment() {
	vec4 tex = texture(albedo_texture, vec3(UV, texture_layer));
	vec3 block = light_data.rgb;
	vec3 light = max(block + vec3(light_data.a), vec3(min_light));
	ALBEDO = tex.rgb * COLOR.rgb * light;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.05;
	EMISSION = tex.rgb * COLOR.rgb * block * block_emission;
}
