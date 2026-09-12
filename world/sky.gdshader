shader_type sky;

uniform vec3 sky_top_color : source_color = vec3(0.29, 0.53, 1.0);
uniform vec3 sky_horizon_color : source_color = vec3(0.6, 0.78, 1.0);
uniform vec3 ground_horizon_color : source_color = vec3(0.55, 0.72, 0.95);
uniform vec3 ground_bottom_color : source_color = vec3(0.35, 0.52, 0.82);
uniform float sky_curve : hint_range(0.0, 1.0) = 0.1;
uniform float ground_curve : hint_range(0.0, 1.0) = 0.05;
uniform float sun_angle_max : hint_range(0.0, 30.0) = 2.5;
uniform float sun_curve : hint_range(0.0, 1.0) = 0.02;
uniform float sun_brightness : hint_range(0.0, 10.0) = 2.5;
uniform float star_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec3 star_color : source_color = vec3(0.85, 0.9, 1.0);
uniform float star_twinkle : hint_range(0.0, 1.0) = 0.35;
uniform vec3 milky_way_color : source_color = vec3(0.52, 0.57, 0.72);
uniform float milky_way_intensity : hint_range(0.0, 2.0) = 0.1;
uniform float moon_phase : hint_range(0.0, 1.0) = 0.5;
uniform float moon_radius : hint_range(0.005, 0.1) = 0.038;
uniform vec3 moon_color : source_color = vec3(0.85, 0.88, 1.0);
uniform float moon_brightness : hint_range(0.0, 3.0) = 1.4;
uniform float moon_halo : hint_range(0.0, 2.0) = 0.3;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float star_layer(vec3 dir, float scale, float threshold, float size_scale) {
	vec3 p = dir * scale;
	vec3 cell = floor(p);
	vec3 offset = fract(p);
	vec3 rnd = hash33(cell);
	float present = step(threshold, rnd.x);
	float d = length(offset - (0.2 + rnd * 0.6));
	float size = mix(0.05, 0.16, rnd.z) * size_scale;
	float star = present * (1.0 - smoothstep(0.0, size, d));
	float twinkle = 1.0 - star_twinkle * (0.5 + 0.5 * sin(TIME * (1.5 + rnd.x * 3.5) + rnd.z * 40.0));
	return star * mix(0.25, 1.0, rnd.y) * twinkle;
}

float value_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(cell);
	float n100 = hash13(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(cell + vec3(1.0, 1.0, 1.0));
	float nx00 = mix(n000, n100, f.x);
	float nx10 = mix(n010, n110, f.x);
	float nx01 = mix(n001, n101, f.x);
	float nx11 = mix(n011, n111, f.x);
	return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

float fbm(vec3 p) {
	float sum = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		sum += amplitude * value_noise(p);
		p *= 2.03;
		amplitude *= 0.5;
	}
	return sum;
}

float milky_way(vec3 dir) {
	vec3 plane_normal = normalize(vec3(0.35, 0.62, -0.7));
	float plane_distance = dot(dir, plane_normal);
	float band = exp(-abs(plane_distance) * 3.0);
	float clouds = fbm(dir * 3.2);
	float structure = mix(0.55, 1.0, clouds);
	float dust = exp(-abs(plane_distance) * 13.0) * clouds;
	band *= structure * (1.0 - 0.35 * dust);
	return band;
}

void sky() {
	float y = EYEDIR.y;
	vec3 upper = mix(sky_horizon_color, sky_top_color, pow(clamp(y, 0.0, 1.0), mix(1.0, 0.35, sky_curve)));
	vec3 lower = mix(ground_horizon_color, ground_bottom_color, pow(clamp(-y, 0.0, 1.0), mix(1.0, 0.35, ground_curve)));
	vec3 col = y >= 0.0 ? upper : lower;

	if (LIGHT0_ENABLED) {
		float sun_ang = acos(clamp(dot(EYEDIR, LIGHT0_DIRECTION), -1.0, 1.0));
		float sun_size = radians(sun_angle_max);
		float sun_disk = 1.0 - smoothstep(sun_size * (1.0 - sun_curve), sun_size, sun_ang);
		col += sun_disk * LIGHT0_COLOR * LIGHT0_ENERGY * sun_brightness;
	}

	if (star_intensity > 0.001) {
		float horizon_fade = smoothstep(-0.05, 0.35, y);
		float band = milky_way(EYEDIR);
		float stars = star_layer(EYEDIR, 55.0, 0.86, 1.0);
		stars += star_layer(EYEDIR, 110.0, 0.9, 0.7);
		stars += star_layer(EYEDIR, 220.0, 0.93, 0.5);
		stars += star_layer(EYEDIR, 90.0, 0.72, 0.8) * band * milky_way_intensity * 5.0;
		col += stars * star_color * star_intensity * horizon_fade * 1.6;
		col += band * milky_way_color * star_intensity * milky_way_intensity * horizon_fade;
	}

	if (LIGHT0_ENABLED) {
		vec3 moon_dir = -LIGHT0_DIRECTION;
		float moon_ang = acos(clamp(dot(EYEDIR, moon_dir), -1.0, 1.0));
		float disk = 1.0 - smoothstep(moon_radius * 0.9, moon_radius, moon_ang);
		float halo = (1.0 - smoothstep(moon_radius * 1.1, moon_radius * 5.0, moon_ang)) * moon_halo * (1.0 - disk) * star_intensity;
		if (disk > 0.0) {
			vec3 reference = abs(moon_dir.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
			vec3 right = normalize(cross(moon_dir, reference));
			vec3 up = normalize(cross(right, moon_dir));
			float x = dot(EYEDIR, right) / moon_radius;
			float local_y = dot(EYEDIR, up) / moon_radius;
			vec3 normal = normalize(-moon_dir + right * (x * moon_radius) + up * (local_y * moon_radius));
			float phase_angle = moon_phase * 6.2831853;
			vec3 virtual_sun = normalize(moon_dir * cos(phase_angle) + right * sin(phase_angle));
			float lit = clamp(dot(normal, virtual_sun), 0.0, 1.0);
			col += disk * lit * moon_color * moon_brightness * star_intensity;
		}
		col += halo * moon_color;
	}

	COLOR = col;
}
