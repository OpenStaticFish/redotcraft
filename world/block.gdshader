shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, alpha_to_coverage;

uniform sampler2DArray albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float block_emission : hint_range(0.0, 2.0) = 0.45;
uniform float min_light : hint_range(0.0, 1.0) = 0.05;
// Leaf shadow proxy. Leaves keep their cutout silhouette in the visible pass
// but write opaque coverage in the shadow pass, so the shadow map never samples
// mip-filtered leaf alpha and the canopy shadow silhouette stops crawling with
// view/sun angle. This trades the dappled leaf-shadow look for a solid canopy
// shadow. Non-leaf cutout blocks (glass, cross foliage) are unaffected. Set to
// 0 to restore the plain cutout (dappled) leaf shadows.
uniform float solid_leaf_shadows : hint_range(0.0, 1.0) = 1.0;
// Camera-submerged strength (0 above water), driven by DayNightCycle. Caustics
// are projected from the water surface onto sky-lit upward faces.
global uniform float underwater_caustics;
// Wind sway strength (0 disables), driven by DayNightCycle. Only vertices whose
// COLOR.a is set by the mesher (leaves and cross foliage) move.
global uniform float wind_strength;

varying vec4 light_data;
varying float texture_layer;
varying vec3 world_position;
varying float up_face;

void vertex() {
	light_data = CUSTOM0;
	texture_layer = CUSTOM1.x;
	vec3 base_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// COLOR.a carries the per-block wind weight (0 for solid blocks). VERTEX.y
	// is world height here, so the anchor ramps wind in over the first 8 blocks
	// and sways the canopy as a whole while ground clutter barely moves.
	float wind = COLOR.a;
	if (wind > 0.001 && wind_strength > 0.001) {
		float anchor = clamp(VERTEX.y, 0.0, 8.0) * 0.125;
		float phase = base_world.x * 0.35 + base_world.z * 0.3;
		float sway = sin(phase + TIME * 1.5) + 0.5 * sin(phase * 1.7 + TIME * 2.3);
		float cross = cos(phase * 0.9 + TIME * 1.2);
		VERTEX.x += wind * wind_strength * anchor * sway * 0.06;
		VERTEX.z += wind * wind_strength * anchor * cross * 0.05;
	}
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
	// Leaves are the only blocks with a full wind weight (see ChunkMesher
	// _build_light_tables), so COLOR.a doubles as the leaf marker here.
	float leaf = step(0.99, COLOR.a);
	float shadow_proxy = leaf * solid_leaf_shadows * (IN_SHADOW_PASS ? 1.0 : 0.0);
	ALPHA = max(tex.a, shadow_proxy);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.05;
	EMISSION = tex.rgb * COLOR.rgb * block * block_emission;
}
