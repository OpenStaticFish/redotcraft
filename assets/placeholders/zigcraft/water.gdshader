shader_type spatial;

render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley;

uniform sampler2D water_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform vec4 water_color : source_color = vec4(0.10, 0.50, 0.88, 1.0);
uniform vec3 foam_color : source_color = vec3(0.90, 0.96, 1.0);
uniform vec3 sky_reflection : source_color = vec3(0.62, 0.78, 0.98);
uniform float wave_amplitude = 0.12;
uniform float wave_speed = 0.12;
uniform float depth_fade = 1.5;
uniform float foam_amount = 0.4;
uniform float refraction_strength = 1.0;
uniform float refraction_mix = 0.85;
uniform float chromatic_strength = 0.0015;

varying vec2 world_xz;
varying float face_up;
varying vec4 light_data;

vec4 perm(vec4 x) {
	return mod(((x * 34.0) + 1.0) * x, 289.0);
}

float snoise(vec3 p) {
	vec3 a = floor(p);
	vec3 d = p - a;
	d = d * d * (3.0 - 2.0 * d);
	vec4 b = a.xxyy + vec4(0.0, 1.0, 0.0, 1.0);
	vec4 k1 = perm(b.xyxy);
	vec4 k2 = perm(k1.xyxy + b.zzww);
	vec4 c = k2 + a.zzzz;
	vec4 k3 = perm(c);
	vec4 k4 = perm(c + 1.0);
	vec4 o1 = fract(k3 * (1.0 / 41.0));
	vec4 o2 = fract(k4 * (1.0 / 41.0));
	vec4 o3 = o2 * d.z + o1 * (1.0 - d.z);
	vec2 o4 = o3.yw * d.x + o3.xz * (1.0 - d.x);
	return o4.y * d.y + o4.x * (1.0 - d.y);
}

vec3 gnoise(vec3 p) {
	vec3 a = floor(p);
	vec3 d = p - a;
	vec3 dd = 6.0 * d * (1.0 - d);
	d = d * d * (3.0 - 2.0 * d);
	vec4 b = a.xxyy + vec4(0.0, 1.0, 0.0, 1.0);
	vec4 k1 = perm(b.xyxy);
	vec4 k2 = perm(k1.xyxy + b.zzww);
	vec4 c = k2 + a.zzzz;
	vec4 k3 = perm(c);
	vec4 k4 = perm(c + 1.0);
	vec4 o1 = fract(k3 * (1.0 / 41.0));
	vec4 o2 = fract(k4 * (1.0 / 41.0));
	vec4 o3 = o2 * d.z + o1 * (1.0 - d.z);
	vec2 o4 = o3.yw * d.x + o3.xz * (1.0 - d.x);
	vec4 dz1 = (o2 - o1) * dd.z;
	vec2 dz2 = dz1.yw * d.x + dz1.xz * (1.0 - d.x);
	vec2 dx = (o3.yw - o3.xz) * dd.x;
	return vec3(
		dx.y * d.y + dx.x * (1.0 - d.y),
		(o4.y - o4.x) * dd.y,
		dz2.y * d.y + dz2.x * (1.0 - d.y)
	);
}

vec2 wave_noise(vec3 p, float off) {
	return (gnoise(p + vec3(0.0, 0.0, off)) * 0.4 +
		gnoise(2.0 * p + vec3(0.0, off, off)) * 0.2 +
		gnoise(3.0 * p + vec3(0.0, off, off)) * 0.225 +
		gnoise(4.0 * p + vec3(-off, off, 0.0)) * 0.2).xz;
}

void vertex() {
	light_data = CUSTOM0;
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	face_up = step(0.5, NORMAL.y);
	float flow = clamp((1.0 - COLOR.a) * 3.0, 0.0, 1.0);
	vec3 wave_pos = vec3(world_xz.x / 24.0, 0.0, world_xz.y / 16.0 + TIME * wave_speed);
	VERTEX.y += (snoise(wave_pos) - 1.0) * wave_amplitude * (1.0 - 0.65 * flow);
}

void fragment() {
	float flow = clamp((1.0 - COLOR.a) * 3.0, 0.0, 1.0);
	vec2 pattern_uv = world_xz * 0.22 + vec2(0.0, -TIME * (0.02 + 0.3 * flow));
	float pattern = texture(water_texture, pattern_uv).r;

	vec2 distortion = vec2(0.0);
	if (face_up > 0.5) {
		vec3 wave_pos = vec3(world_xz.x / 24.0, 0.0, world_xz.y / 16.0);
		vec2 gradient = wave_noise(wave_pos, TIME * wave_speed);
		vec3 world_normal = normalize(vec3(0.0, 1.0, 0.0) + vec3(gradient.x, 0.0, gradient.y) * 0.35);
		NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(world_normal, 0.0)).xyz);
		distortion = gradient * 0.022 * (1.0 - 0.6 * flow);
	} else {
		float side_noise = snoise(vec3(world_xz.x * 0.25, world_xz.y * 0.25, TIME * 0.15)) - 0.5;
		distortion = vec2(side_noise) * 0.012;
	}
	float proximity = clamp(24.0 / max(-VERTEX.z, 1.0), 0.0, 1.0);
	distortion *= refraction_strength * proximity;

	vec3 refracted;
	refracted.r = texture(screen_texture, SCREEN_UV + distortion - vec2(chromatic_strength, 0.0)).r;
	refracted.g = texture(screen_texture, SCREEN_UV + distortion).g;
	refracted.b = texture(screen_texture, SCREEN_UV + distortion + vec2(chromatic_strength, 0.0)).b;

	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	scene_view.xyz /= scene_view.w;
	float thickness = max(-scene_view.z - (-VERTEX.z), 0.0);
	float shallow = 1.0 - clamp(thickness / depth_fade, 0.0, 1.0);
	float foam = 1.0 - smoothstep(0.0, 0.45, thickness);

	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, 5.0);
	vec3 block_light = light_data.rgb;
	vec3 tint = water_color.rgb * (0.94 + pattern * 0.12) * COLOR.rgb;
	vec3 water_filter = tint * tint * 1.6;
	float tint_amount = mix(0.85, 0.4, shallow);
	vec3 surface = refracted * mix(vec3(1.0), water_filter, tint_amount);
	surface += tint * (0.12 + fresnel * 0.15);
	surface += sky_reflection * fresnel * 0.12 * light_data.a;
	surface += foam_color * foam * foam_amount * max(light_data.a, 0.05);
	surface += water_color.rgb * block_light * 0.35;
	float alpha = clamp(refraction_mix + fresnel * 0.12 + shallow * 0.08, 0.0, 1.0);
	ALBEDO = vec3(0.0);
	EMISSION = surface * alpha;
	ALPHA = alpha;
	ROUGHNESS = 0.22;
	SPECULAR = 0.35;
	METALLIC = 0.0;
}
