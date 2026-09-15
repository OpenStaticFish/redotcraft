shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// Flame billboards drawn over a burning block. The block mesh itself is
// untouched; these quads are positioned/oriented per instance by
// `world/fire_overlay.gd` and animated here so the CPU only rebuilds the
// instance list on the fire tick.
uniform sampler2D flame_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float emission_strength : hint_range(0.0, 4.0) = 2.0;

// INSTANCE_CUSTOM is a vertex-only built-in, so carry it to the fragment.
varying vec4 instance_data;

void vertex() {
	instance_data = INSTANCE_CUSTOM;
	float phase = instance_data.x;
	// The quad is vertical (local Y up); stretch and wobble the flame upward
	// from its base. No UV wrapping, so the sheet never jumps.
	float t = TIME * 3.2 + phase * 6.2831;
	VERTEX.y *= 1.0 + 0.14 * sin(t) + 0.06 * sin(t * 1.7 + 1.1);
	VERTEX.x += 0.06 * sin(t * 1.3 + VERTEX.y * 4.0) * clamp(VERTEX.y + 0.5, 0.0, 1.0);
}

void fragment() {
	float phase = instance_data.x;
	float progress = instance_data.y;
	vec4 tex = texture(flame_texture, UV);
	float flicker = 0.85 + 0.25 * sin(TIME * 9.0 + phase * 20.0);
	float fade = smoothstep(0.0, 0.12, progress) * (1.0 - smoothstep(0.72, 1.05, progress));
	ALBEDO = tex.rgb * emission_strength * flicker;
	ALPHA = tex.a * fade;
}
