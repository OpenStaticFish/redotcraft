shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// Smoke puffs that rise off a burning block for the duration of its burn. Like
// the flame overlay, this is animated entirely in the shader and only needs an
// instance list refresh on the fire tick.
uniform sampler2D smoke_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 smoke_color : source_color = vec3(0.17, 0.17, 0.19);

// INSTANCE_CUSTOM is a vertex-only built-in, so carry it to the fragment.
varying vec4 instance_data;

void vertex() {
	instance_data = INSTANCE_CUSTOM;
	float phase = instance_data.x;
	float progress = instance_data.y;
	// The quad is vertical (local Y up); rise, drift and expand as it burns.
	float t = TIME * 0.9 + phase * 6.2831;
	VERTEX.y += progress * 1.3;
	VERTEX.x += 0.28 * sin(t) * progress;
	VERTEX.xy *= 0.65 + progress * 1.5;
}

void fragment() {
	float progress = instance_data.y;
	vec4 tex = texture(smoke_texture, UV);
	ALBEDO = smoke_color;
	ALPHA = tex.a * sin(clamp(progress, 0.0, 1.0) * PI) * 0.55;
}
