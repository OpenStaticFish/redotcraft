shader_type spatial;

render_mode blend_mix, cull_disabled, depth_draw_opaque, diffuse_burley;

uniform sampler2D water_texture : filter_linear_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture;
// Refraction samples the current scene at native detail; mipped screen samples
// made even a very small UV offset look smeared at grazing angles.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform vec4 water_color : source_color = vec4(0.16, 0.42, 0.62, 1.0);
uniform vec3 foam_color : source_color = vec3(0.90, 0.94, 0.93);
uniform vec3 sky_reflection : source_color = vec3(0.58, 0.70, 0.80);
uniform float wave_amplitude = 0.025;
uniform float wave_speed = 0.05;
uniform float depth_fade = 2.4;
uniform float foam_amount = 0.025;
uniform float refraction_strength = 0.28;
uniform float refraction_mix = 0.48;
uniform float chromatic_strength = 0.0;
// Day/night sky strength (1 at noon, NIGHT_SKY_LIGHT at midnight) driven by
// DayNightCycle. The additive tint/sheen/foam terms are already emission, so
// without this they keep glowing after the terrain has gone dark.
global uniform float sky_light_strength;

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
		distortion = gradient * 0.004 * (1.0 - 0.6 * flow);
	} else {
		float side_noise = snoise(vec3(world_xz.x * 0.25, world_xz.y * 0.25, TIME * 0.15)) - 0.5;
		distortion = vec2(side_noise) * 0.003;
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
	// A narrow, faint band starts just inside shallow water. The previous
	// zero-depth ramp was solid white at every shore intersection.
	float foam = smoothstep(0.02, 0.12, thickness) * (1.0 - smoothstep(0.18, 0.45, thickness));
	foam *= face_up;

	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float fresnel = pow(1.0 - ndv, 5.0);
	vec3 block_light = light_data.rgb;
	vec3 tint = water_color.rgb * (0.98 + pattern * 0.035) * COLOR.rgb;
	// Keep the sandy shallows readable, but absorb the seabed progressively
	// with depth instead of showing distant gravel through glass-clear ocean.
	vec3 transmission = exp(-vec3(0.18, 0.09, 0.045) * thickness);
	// Sky exposure scaled by the time-of-day strength; the tint, sheen, and
	// foam terms follow the sun so nights stay dark while block light keeps
	// its warm glow (added below, unaffected).
	float sky = light_data.a * sky_light_strength;
	float sky_floor = max(light_data.a, 0.05) * sky_light_strength;
	vec3 surface = refracted * transmission;
	surface += tint * (vec3(1.0) - transmission) * sky_floor;
	surface += tint * (0.06 + fresnel * 0.10) * sky_light_strength;
	surface += sky_reflection * fresnel * 0.08 * sky;
	surface += foam_color * foam * foam_amount * sky_floor;
	surface += water_color.rgb * block_light * 0.35;
	float deep = 1.0 - exp(-thickness / max(depth_fade, 0.01) * 0.288);
	float alpha = clamp(mix(refraction_mix, 0.96, deep) + fresnel * 0.04, 0.0, 1.0);
	ALBEDO = vec3(0.0);
	// blend_mix applies ALPHA during compositing; multiplying here as well
	// would darken the refracted scene twice as transparency increases.
	EMISSION = surface;
	ALPHA = alpha;
	ROUGHNESS = 0.22;
	SPECULAR = 0.35;
	METALLIC = 0.0;
}
